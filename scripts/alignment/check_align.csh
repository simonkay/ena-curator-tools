#!/bin/csh

# run the program and pipe errors into logfile
# check for the alignment
/ebi/production/seqdb/embl/tools/curators/scripts/alignment/check_align.pl /@ENAPRO >&! \
/ebi/production/seqdb/embl/tools/curators/scripts/alignment/log/alignment.log
# check for the journal
/ebi/production/seqdb/embl/tools/curators/scripts/alignment/journal_check_align.pl /@ENAPRO >&! \
/ebi/production/seqdb/embl/tools/curators/scripts/alignment/log/align_citation_upd.log

# mail logfile 
cat /ebi/production/seqdb/embl/tools/curators/scripts/alignment/log/alignment.log \
/ebi/production/seqdb/embl/tools/curators/scripts/alignment/log/align_citation_upd.log | \
Mail -s "alignment check" nimap@ebi.ac.uk, xin@ebi.ac.uk

exit


