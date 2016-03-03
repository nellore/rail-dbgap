#!/usr/bin/env bash
set -ex;
cut -f2 | { IFS= read -r SRR;
KMERSIZE=21;
cd /mnt/space/sra_workspace/secure;
fastq-dump ${SRR} --stdout -X 10000 \
  | bioawk -v kmersize=${KMERSIZE} -v srr=${SRR} -c fastx \
    '{
	    for (i=1; i<=length($seq)-kmersize; i++) {
            revcompsubseq = substr($seq, i, kmersize);
            subseq = revcompsubseq;
            revcomp(revcompsubseq);
            if (revcompsubseq < subseq) {
                print "UniqValueCount:" revcompsubseq "\t" srr;
            } else {
                print "UniqValueCount:" subseq "\t" srr;
            }
	    }
    }'
}
