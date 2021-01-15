#!/ebi/production/seqdb/embl/tools/bin/perl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/check_expired_hold_date.pl,v 1.7 2008/02/18 15:37:47 szilva Exp $
#
#  (C) EBI 2000
#
#  MODULE DESCRIPTION:
#
#  Accession numbers of *non-standard* confidential entries with expired
#  hold dates are sent by $email to the appropriate curator e.g. draft 
# with expired hold date.
#  
#===============================================================================

use strict;
use warnings;
use DBI;
use DBD::Oracle;
use dbi_utils;
use SeqDBUtils;
use SeqDBUtils2;


#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n USAGE: $0 <user/password\@instance> [-test] [-h]\n\n";

( @ARGV >= 1 && @ARGV <= 2 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

hide ( 1 );

my $login = $ARGV[0];
my $test  = 0;

for ( my $i = 1; $i < @ARGV; ++$i ){
    if ( $ARGV[$i] eq "-test" ){   
	$test = 1;
    }
    else{
	die ( $usage );
    }
}

die if ( check_environment ( $test, $login ) == 0 );

#-------------------------------------------------------------------------------
# connect to database and set auditremark
#-------------------------------------------------------------------------------

my $dbh = dbi_ora_connect ( $login );
dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );
dbi_do ( $dbh, "begin auditpackage.remark := 'hold date expired - entry automatically released'; end;" );

#-------------------------------------------------------------------------------
# get sysdate
#-------------------------------------------------------------------------------

my ( $today ) = dbi_getvalue ( $dbh, 
			       "SELECT to_char ( sysdate, 'DD-MON-YYYY' )
                                  FROM dual" ); 
my $today_midnight = $today." 23:59:59"; 

print "*************************\n";
print "Releasing confidential entries with a holddate expiring at the end of\n"
    . "$today\n\n";

#-------------------------------------------------------------------------------
# expired non-standard entries: send a mail to updates
#-------------------------------------------------------------------------------

my $table_hdr = "Curator  DS      P  AC        HOLD DATE    STATUS\n"
              . "-------------------------------------------------\n";

#print "\n-----------------------------------------\n"
#    . "non-standard (excluding deleted) entries:\n\n"
#    . $table_hdr;

#$mb = $dbh->prepare(
#		    q{ select d.project#, nvl(a.idno,0), nvl(cu.user_name, 'n/a'), d.primaryacc#, to_char ( d.hold_date, 'DD-MON-YYYY' ), cv.status
#			   FROM dbentry d, cv_status cv, accession_details a, submission_details ds, curator cu
#			   WHERE d.hold_date <= to_date ( ?, 'DD-MON-YYYY HH24:MI:SS' )
#			   AND d.statusid NOT IN (3,4,5)
#			   AND d.dbcode = 'E'
#			   and d.statusid = cv.statusid
#			   and d.primaryacc# = a.acc_no (+)
#			   and a.idno = ds.idno (+)
#			   and ds.curatorid = cu.curatorid(+)
#			   group by d.project#, nvl(a.idno,0), nvl(cu.user_name, 'n/a'), d.primaryacc#, to_char ( d.hold_date, 'DD-MON-YYYY' ), cv.status
#			   ORDER BY cv.status, d.project#, nvl(cu.user_name, 'n/a'), nvl(a.idno,0), d.primaryacc#
#		       });

my $mb = $dbh->prepare(
		    q{ select d.project#, d.primaryacc#, to_char ( d.hold_date, 'DD-MON-YYYY' ), cv.status
			   FROM dbentry d, cv_status cv
			   WHERE d.hold_date <= to_date ( ?, 'DD-MON-YYYY HH24:MI:SS' )
			   AND d.statusid NOT IN (3,4,5)
			   AND d.dbcode = 'E'
			   and d.statusid = cv.statusid
			   group by d.project#, d.primaryacc#, to_char ( d.hold_date, 'DD-MON-YYYY' ), cv.status
			   ORDER BY cv.status, d.project#, d.primaryacc#
		       });

$mb->bind_param( 1, $today_midnight);
$mb->execute || bail ( "select from database failed", $dbh );

my (@ac_and_msg, $line);
my $i = 0;

while ( my ( $project, $acc, $hdate, $status ) = $mb->fetchrow ) {

    #$line = sprintf "%2s  %-8s  %11s  %s\n", (( $project ) ? $project : ""), $acc, $hdate, $status;

    $line = sprintf "%2s  %-8s  %11s  %s\n", $project, $acc, $hdate, $status;

    $ac_and_msg[$i]{ac}  = $acc;
    $ac_and_msg[$i]{msg} = $line;
    $i++;
}

my $email_subject = "Entries containing expired hold date";
my $initial_text = "This check for expired hold dates was run on $today\n\n"
    . "Please edit the following entries:\n\n"
    . $table_hdr;

if (@ac_and_msg) {
    SeqDBUtils2::send_errors('ac', @ac_and_msg, $dbh, $email_subject, $initial_text);
}

$mb->finish;  

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------

dbi_rollback ( $dbh );
dbi_logoff ( $dbh );
