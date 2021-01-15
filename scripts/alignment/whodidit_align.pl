#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/alignment/whodidit_align.pl,v 1.6 2006/12/07 14:57:24 gemmah Exp $
#
#  (C) EBI 2000
#
#  Written by Vincent Lombard
#
#  DESCRIPTION:
#
#  whoalign.pl
#  takes accession number input and gives userstamp, osuser,
#  remarks and timestamp of changes (updates/insertes/deletes) in the different
#  tables align and align_dbentry
#  database name from environment variables
#  changes in align_dbentry are only shown if there are no changes in other tables at
#  this time
#
#  MODIFICATION HISTORY:
#
# 15-DEC-2000 lombard      : add the curator name who load an alignment into
#                            the database
# 20-FEB-2001 lombard      : reduce the output line
# 27-APR-2001 lombard      : add the ds number in STDOUT
# 01-OCT-2001 lombard      : delete the redundancy so curators don't have the
#                            same message twice or more
# 
###############################################################################

use strict;
use DBI;
use dbi_utils;
use seqdb_utils;


#-------------------------------------------------------------------------------
# connect to database
#-------------------------------------------------------------------------------

my $Usage = "USAGE: $0 <username/password\@instance> <alignacc#>";
@ARGV == 2 || die "\n$Usage\n\n";

my $dbh = dbi_ora_connect ( $ARGV[0] );

#-------------------------------------------------------------------------------
# get accno
#-------------------------------------------------------------------------------

my $acc = $ARGV[1];
my $alignid;
# remove blanks and tabs and convert to upper case
$acc =~ s/[ \t]//g; $acc = "\U$acc";
$alignid = $acc;
$alignid =~ s/ALIGN_//;
$alignid =~ s/^0*//;

#-------------------------------------------------------------------------------
# test if entry exists in database
#-------------------------------------------------------------------------------

my $call = "SELECT count(*) FROM align WHERE alignacc = '$acc'";
if ( dbi_getvalue ( $dbh, $call ) == 0 ) {
  die "accession number/entry name $acc was not found in database\n\n";
}

#-------------------------------------------------------------------------------
# create tmp table
#-------------------------------------------------------------------------------

# drop first, if exists ( test first to avoid error message )
if ( exists_table ( $dbh, 'WHODIDITINALIGN_TMP' )) {
  dbi_do ( $dbh, "drop table whodiditinalign_tmp" );
}

dbi_do ( $dbh, "create table whodiditinalign_tmp (
                            userstamp  varchar2(30),
                            timestamp  date,
                            table_name varchar2(50),
                            remark     varchar2(100),
                            dbremark   varchar2(6))" ); 
 
#------------------------------------------------------------------------------
# select table 
#------------------------------------------------------------------------------

select_table('align_audit',$alignid);
select_table('align_dbentry_audit',$alignid);
 
#-- entry created date --------------------------------------------------------

$call =
"SELECT min (to_char (timestamp, 'YYYYMMDDHH24MISS'))
    FROM (
  SELECT timestamp
    FROM align
   WHERE alignid = $alignid
   UNION 
  SELECT timestamp
    FROM align_audit
   WHERE alignid = $alignid) ";

my ($created) = dbi_getvalue ( $dbh, $call );

$call =
"select userstamp
  from align 
  where to_char ( timestamp, 'YYYYMMDDHH24MISS') = '$created'
  union
  select userstamp from align_audit
  where to_char ( timestamp, 'YYYYMMDDHH24MISS') = '$created'";



my ($userstamp) = dbi_getvalue ( $dbh, $call );

insert_into_tmp ( $dbh,'-',$userstamp,$created, 'entry created', '-');

#------------------------------------------------------------------------------
# read tmp table 
#------------------------------------------------------------------------------

$call =
 "SELECT to_char (timestamp, 'YYYYMMDDHH24MISS'),
         to_char (timestamp, 'DD-MON-YYYY HH24:MI'),
         userstamp,
         table_name,
         nvl (remark, '-'),
         nvl (dbremark, '-')
    FROM whodiditinalign_tmp
   WHERE table_name != 'align_dbentry'
   UNION ALL
  SELECT to_char (timestamp, 'YYYYMMDDHH24MISS'),
         to_char (timestamp, 'DD-MON-YYYY HH24:MI'),
         userstamp,
         table_name,
         remark,
         dbremark
    FROM whodiditinalign_tmp
   WHERE table_name = 'align_dbentry'
     AND (to_char (timestamp, 'YYYYMMDDHH24MI') not in 
           (SELECT to_char (timestamp, 'YYYYMMDDHH24MISS') 
              FROM whodiditinalign_tmp 
             WHERE table_name != 'align_dbentry'))
   ORDER BY 1";

my ( @table ) = dbi_gettable ( $dbh, $call );

print STDERR "\n";

#------------------------------------------------------------------------------
# write protocoll
#------------------------------------------------------------------------------

my ($x0, $date, $ds, $user, $table, $remark,$dbremark);
my ($old_date) = "";
my ($old_user) = "";
my ($old_table) = "";
#-- take the ds ------------------------------------------------------------------
$call =
  " SELECT IDNO 
      FROM align
     WHERE alignid = $alignid";

  $ds = dbi_getvalue ( $dbh, $call );

  foreach my $row ( @table ) {
    ( $x0, $date, $user, $table, $remark, $dbremark) = @{$row};


my $date_notime=$date; # date variable without time
$date_notime =~ s/([\d]{2}-[A-Z]{3}-[\d]{4})\s.+/$1/;
    # try to avoid redundancy
    if ($old_date ne $date_notime or 
	$old_user ne $user or 
	$remark ne '-' or 
	$old_table ne $table) {
      # printout     
      write;

    }
    #initialise the old_variables with the new datas
    $old_date=$date_notime;
    $old_user=$user;
    $old_table = $table;
  }

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------

dbi_logoff ( $dbh );

#-------------------------------------------------------------------------------
# output formats
#-------------------------------------------------------------------------------
format STDOUT_TOP=
date        #ds        table               user         action  audit remark 
=========== ========== =================== ============ ======  =========================
.

format STDOUT=
@<<<<<<<<<< @<<<<<<<<< @<<<<<<<<<<<<<<<<<< @<<<<<<<<<<< @<<<<<  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$date, $ds, $table, $user, $dbremark, $remark
.

sub insert_into_tmp {

  confess ( "insert_into_tmp:@_:wrong number of arguments\n" )  if ( @_ != 6 );
  my ( $db, $tab, $userstamp, $timestamp, $remark, $dbremark) = @_;
    
  dbi_do ( $db, 
	      "insert into whodiditinalign_tmp
                ( userstamp, timestamp, table_name, remark, dbremark) 
               values
                ( '$userstamp', to_date ('$timestamp', 'YYYYMMDDHH24MISS'), 
                  '$tab', '$remark', '$dbremark')" ) ;
}

sub select_table {

my ($st_table, $alignid) = @_;
my (@values);
$call ="SELECT to_char (timestamp, 'YYYYMMDDHH24MI'),
               to_char (remarktime,  'YYYYMMDDHH24MISS'),
               nvl (userstamp, '-'),
               nvl (remark, '-'),
               nvl (dbremark, '-'),
               osuser
        FROM   $st_table
        WHERE  timestamp is not null
          AND  alignid = $alignid";

my ($cursor) = dbi_open $dbh, $call;
while ( (@values = dbi_fetch $cursor) ) {
  my ( $date, $xrdate, $user, $xremark, $xdbremark, $xosuser) = @values;
  insert_into_tmp ( $dbh, $st_table, $user,$date, $xremark, $xdbremark);
}
dbi_close $cursor;
}


