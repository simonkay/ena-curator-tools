#!/bin/csh

# schema_diff.csh compares the current database schema with copies of the
# tables user_objects, user_tab_columns and user_constraints, and creates
# new copy tables afterwards
# 15-DEC-1999   Carola Kanz
#  8-SEP-2003   Francesco Nardone:  uses shell variable for connection string

 
# logfile under RCS
co -l /ebi/production/seqdb/embl/tools/curators/scripts/log/schema_diff.log >&! \
  /ebi/production/seqdb/embl/tools/curators/scripts/log/schema_diff_create_tables.log

# compare
/ebi/production/seqdb/embl/tools/curators/scripts/schema_diff.pl $dblogin_embl_p >&! \
  /ebi/production/seqdb/embl/tools/curators/scripts/log/schema_diff.log

# sent email
cat /ebi/production/seqdb/embl/tools/curators/scripts/log/schema_diff.log | \
Mail -s "diff on schema" nimap@ebi.ac.uk, xin@ebi.ac.uk, mjang@ebi.ac.uk

ci -mschema_diff -t-schema_diff -f -u \
  /ebi/production/seqdb/embl/tools/curators/scripts/log/schema_diff.log >>& \
  /ebi/production/seqdb/embl/tools/curators/scripts/log/schema_diff_create_tables.log

# create new copy tables
/sw/arch/dbtools/oracle/product/9.2.0/bin/sqlplus \
  $dblogin_embl_p \
  @/ebi/production/seqdb/embl/tools/curators/scripts/schema_diff_create_tables_PRDB1.sql >>& \
  /ebi/production/seqdb/embl/tools/curators/scripts/log/schema_diff_create_tables.log

exit

