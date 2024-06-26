## train_svm -- trains an SVM to recognize a certain pattern of regulatory positions.
##

# setClass("regulatory_svm",#"restricted_boltzman_machine",
  # contains="genomic_data_model",
  # representation(
    # asvm= "list"
  # ),
# )


#' Returns a data.frame with center positions that pass a minimum depth filter ...
#'
#' @param gdm Genomic data model.
#' @param bw_plus Path to bigWig file representing the plus strand [char].
#' @param bw_minus Path to bigWig file representing the minus strand [char].
#' @param positions The universe of positions to test and evaluate [data.frame, (chrom,chromCenter)].  Hint: see get_informative_positions().
#' @param positive Bed file containing positive positions [data.frame, (chrom,chromStart,chromEnd)].
#' @param allow Bed file containing positions to avoid in the negative set [data.frame, (chrom,chromStart,chromEnd)].
#' @param n_train Number of training examples.
#' @param n_eval Number of examples on which to test performance.
#' @param pdf_path Specifies the path to a PDF file.  Set to NULL if no PDF should be printed.
#' @param plot_raw_data If TRUE (default), and if a PDF file is specified, plots the raw data used to train the model.
#' @param svm_type "SVR" for support vecctor regression (epsilon-regression).  "P_SVM" for probabilistic SVM (C-classification).
#' @return Returns a trained SVM.
regulatory_svm <- function(gdm, bw_plus_path, bw_minus_path, positions, positive, negative, n_train=25000, n_eval=1000, pos_frac=0.03, pdf_path= "roc_plot.pdf", plot_raw_data=TRUE, use_rgtsvm=FALSE, svm_type= "SVR", ncores=1, ..., debug= TRUE) {

  if(!file.exists(bw_plus_path))
    stop( paste("Can't find the bigwig of plus strand(", bw_plus_path, ")"));

  if(!file.exists(bw_minus_path))
    stop( paste("Can't find the bigwig of minus strand(", bw_minus_path, ")"));

  ########################################
  ## Divide into positives and negatives.

  batch_size = 10000;

  if (use_rgtsvm)
  {
    if(!requireNamespace("Rgtsvm"))
      stop("Rgtsvm has not been installed fotr GPU computing.");

    predict = Rgtsvm::predict.gtsvm;
    svm = Rgtsvm::svm;
  }

  #if( class(asvm)=="svm" && use_rgtsvm) class(asvm)<-"gtsvm";
  #if( class(asvm)=="gtsvm" && !use_rgtsvm) class(asvm)<-"svm";

  n_total <- n_train+n_eval
  indx_train_pos <- c(1:round(n_train*pos_frac)) 
  indx_eval_pos  <- c(round(n_train*pos_frac)+1):round(n_total*pos_frac) 
  indx_train_neg <- round(n_total*pos_frac)+c(1:round(n_train*(1-pos_frac)))
  indx_eval_neg  <- c((round(n_total*pos_frac)+round(n_train*(1-pos_frac))+1 ): n_total)

  indx_train <- c(indx_train_pos, indx_train_neg)
  indx_eval  <- c(indx_eval_pos, indx_eval_neg)

  ## Read genomic data.
  if(debug) 
     print("Collecting training data.")
  
  if(length(bw_plus_path) == 1) {
    tset <- get_test_set(positions= positions, positive= positive, negative= negative, n_samp= (n_train+n_eval), pos_frac = pos_frac)

    ## Get training indices.
    x_train_bed <- tset[indx_train,c(1:3)]
    y_train <- tset[indx_train,4]
    x_predict_bed <- tset[indx_eval,c(1:3)]
    y_predict <- tset[indx_eval,4]

    ## Write out a bed of training positions to avoid during test ...
    if(debug) {
      write.table(x_train_bed, "TrainingSet.bed", quote=FALSE, row.names=FALSE, col.names=FALSE, sep="\t")
    write.table(indx_train, "TrainIndx.Rflat")
    }

    # x_train <- parallel_read_genomic_data( x_train_bed, bw_plus_path, bw_minus_path)
    x_train <- read_genomic_data ( gdm, x_train_bed, bw_plus_path, bw_minus_path, ncores = ncores);

  } else {
    x_train <- NULL
    y_train <- NULL
    stopifnot(NROW(bw_plus_path) == NROW(bw_minus_path) & NROW(bw_plus_path) == NROW(positive))
    for(x in 1:length(bw_plus_path)){
      tset_x <- get_test_set(positions= positions[[x]], positive= positive[[x]], negative= negative[[x]], n_samp= (n_train+n_eval), pos_frac = pos_frac)
      x_train_bed <- tset_x[indx_train,c(1:3)]
      y_train <- c(y_train, tset_x[indx_train,4])

      # x_train <- rbind(x_train, parallel_read_genomic_data( x_train_bed, bw_plus_path[[x]], bw_minus_path[[x]]) );
      x_train <- rbind( x_train, read_genomic_data( gdm, x_train_bed, bw_plus_path[[x]], bw_minus_path[[x]], ncores = ncores) );

    }
  }

  gc();
  ########################################
  ## Train the model.
  if(debug) print("Fitting SVM.")
  if (svm_type == "SVR") {
    if(debug) print("Training a epsilon-regression SVR.");
    asvm <- svm( x_train, y_train, type="eps-regression" );
  }
  if (svm_type == "P_SVM") {
    if(debug) print("Training a probabilistic SVM.");
    asvm <- svm( x_train, as.factor(y_train), probability=TRUE);
  }

  gc();

  ########################################
  ## If a PDF file is specified, test performance, and write ROC plots to a PDF file.
  ## Currently *NOT* supported when training with >1 dataset.
 if(!is.null(pdf_path) && !is.na(pdf_path) && n_eval>0 && length(bw_plus_path) == 1) {

    pdf(pdf_path);

    # Plot raw data, if desired.
    if(plot_raw_data) {
      plot(colSums(x_train[y_train == 1,]), ylab="Training data", type="l", ...)
      points(colSums(x_train[y_train == 0,]), col="gray", type="l", ...)
    }

    remove(x_train);

    ## Predict on a randomly chosen set of sequences.
    if(debug) print("Collecting predicted data.")

    #x_predict <- parallel_read_genomic_data( x_predict_bed, bw_plus_path, bw_minus_path );
    x_predict <- read_genomic_data( gdm, x_predict_bed, bw_plus_path, bw_minus_path, ncores = ncores );

    pred <- predict( asvm, x_predict )

    ## Plot raw prediction data, if desired.
    if(plot_raw_data) {
      plot(colSums(x_predict[y_predict == 1,]), ylab="Prediction data", type="l", ...)
      points(colSums(x_predict[y_predict == 0,]), col="gray", type="l", ...)
    }
    remove(x_predict)

    ## Write ROC plots.
    roc_values <- logreg.roc.calc(y_predict, pred);
    AUC<- roc.auc(roc_values);
    roc.plot(roc_values, main=AUC, ...);
    print(paste("Model AUC: ",AUC));
    remove(roc_values);

    dev.off();
 }
 else {
   remove(x_train);
 }

  return(asvm);
}
