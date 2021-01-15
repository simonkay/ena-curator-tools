#!/bin/csh

sqlplus /@enapro @/ebi/production/seqdb/embl/tools/curators/scripts/clean_up_table >&! \
/ebi/production/seqdb/embl/tools/curators/scripts/log/clean_up_table.log

cat /ebi/production/seqdb/embl/tools/curators/scripts/log/clean_up_table.log | \
Mail -s "clean_up_tables.... on enapro" nimap@ebi.ac.uk, mjang@ebi.ac.uk, xin@ebi.ac.uk

exit
