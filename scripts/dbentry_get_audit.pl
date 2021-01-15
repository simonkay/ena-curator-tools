#!/ebi/production/seqdb/embl/tools/bin/perl -w

#===============================================================================
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/deprecated/dbentry_get_audit.pl,v 1.7 2011/06/22 09:36:25 nimap Exp $
#
# (C) EBI 1998
#
# DBENTRY_GET_AUDIT:
# get audit history for table dbentry.
#
# MODIFICATION HISTORY:
#
# 20-AUG-1998 Nicole Redaschi     Created.
# 17-FEB-2004 Carola Kanz         used DBI and strict
#===============================================================================


use strict;
use DBI;
use dbi_utils;


#-------------------------------------------------------------------------------
# query for input
#-------------------------------------------------------------------------------

my $acc = '';
if ( @ARGV ) {
  $acc = $ARGV[0]; 
}
else {
  print "\nenter accession number: "; chomp ( $acc = <STDIN> );
}

# remove blanks and tabs and convert to upper case
$acc =~ s/[ \t]//g; $acc = "\U$acc";

#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------

my $system_id = "ENAPRO";
print "\nconnecting to database $system_id...\n\n";

my $dbh = dbi_ora_connect ( "/\@$system_id" );


#-------------------------------------------------------------------------------
# check whether accession number exists
#-------------------------------------------------------------------------------

if ( dbi_getvalue ( $dbh, "SELECT count(*) FROM dbentry WHERE primaryacc# = '$acc'" ) != 1 ) {
  bail ( "accession number $acc was not found in database $system_id\n\n", $dbh );
}

#-------------------------------------------------------------------------------
# set the date format
#-------------------------------------------------------------------------------

dbi_do ( $dbh, "ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY'" );

#-------------------------------------------------------------------------------
# execute the queries
#-------------------------------------------------------------------------------

my ( $date, $user, $status, $conf, $remark );

my $sql_dbentry =
 "SELECT timestamp,
         userstamp,
         entry_status,
         nvl(confidential, 'N'),
         '-'
    FROM dbentry
   WHERE primaryacc# = '$acc'";

my ( @tab ) = dbi_gettable ( $dbh, $sql_dbentry );
foreach my $row ( @tab ) {
  ( $date, $user, $status, $conf, $remark ) = @{$row};
  write;
}

print "-------------- ----------- -------------------------------------------------- ------ ----\n";
my $sql_dbentry_audit =
 "SELECT remarktime,
         userstamp,
         entry_status,
         nvl(confidential, 'N'),
         nvl(remark, '-')
    FROM dbentry_audit
   WHERE primaryacc# = '$acc'
ORDER BY timestamp desc";

( @tab ) = dbi_gettable ( $dbh, $sql_dbentry_audit );
foreach my $row ( @tab ) {
  ( $date, $user, $status, $conf, $remark ) = @{$row};
  write;
}

print "\n";

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------

dbi_logoff ( $dbh );

#-------------------------------------------------------------------------------
# output format
#-------------------------------------------------------------------------------

format STDOUT_TOP =
user           date        audit remark                                       status conf
============== =========== ================================================== ====== ====
.

format STDOUT =
@<<<<<<<<<<<<< @<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<< @<<<
$user, $date, $remark, $status, $conf
.
