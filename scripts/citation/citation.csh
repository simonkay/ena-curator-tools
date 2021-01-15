#!/bin/csh

/ebi/production/seqdb/embl/tools/curators/scripts/citation/citation.pl /@enapro >&! \
/ebi/production/seqdb/embl/tools/log/citation.log

tail -7 /ebi/production/seqdb/embl/tools/log/citation.log | \
Mail -s "citation update" mjang@ebi.ac.uk nimap@ebi.ac.uk xin@ebi.ac.uk

exit
