#!/usr/bin/python
# Given an input BED file, will subsample the lines down.
# arguments are infile N1 N2 N3...
# where each Ni is a number (in millions) of lines that we want in a subsampled file.

import random
import gzip
import sys
import re

infile_path = sys.argv[1]
if not '.bed' in infile_path:
    print 'ERROR: expecting a bed file.'
    sys.exit()

num_lines = sum(1 for line in open(infile_path))
num_list = sys.argv[2:]
subsamps = []
for num in num_list:
    prob = float(num)*(1000000.0)/num_lines
    print num
    print prob
    path = re.sub('.bed', str(num)+'m.bed', infile_path)
    outfile = gzip.open(path,'w')
    subsamps.append((prob,outfile))

i=0
print 'Opening file', infile_path
for line in gzip.open(infile_path):
    if i%5000000==0:
        print str(100*float(i)/num_lines)+'%'
    i+=1
    if 'rRNA' in line:
        # in theory we can exclude anything else here, too
        continue
    for option in subsamps:
        r = random.random()
        prob = option[0]
        outfile = option[1]
        if r <= prob:
            outfile.write(swapped_line)
