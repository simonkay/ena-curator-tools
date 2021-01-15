#!/ebi/production/seqdb/embl/tools/bin/perl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/release_confidential.pl,v 1.6 2012/07/05 13:16:54 mjang Exp $
#
#  (C) EBI 2007
#
#  MODULE DESCRIPTION:
#
#  Releases private or temporarily-killed EMBL entries with expired hold dates.
#  
#===============================================================================

use strict;
use warnings;
use DBI;
use DBD::Oracle;
use dbi_utils;
use SeqDBUtils;


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
	print "Test MODE - transactions will rollback\n";
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

my $today = dbi_getvalue($dbh, 
			       "SELECT to_char ( sysdate, 'DD-MON-YYYY' )
                                  FROM dual" ); 
my $today_midnight = $today." 23:59:59"; 

print "*************************\n"
    . "Releasing confidential entries with a hold date expiring\nat the end of "
    . "$today\n\n";

#-------------------------------------------------------------------------------
# expired standard entries: release them
#-------------------------------------------------------------------------------
            
my $mb = $dbh->prepare(
		       q{ SELECT project#, primaryacc#, to_char ( hold_date, 'DD-MON-YYYY' )
			    FROM dbentry
			   WHERE statusid in (2,5,6) -- private or temp sup/killed
			     AND hold_date <= to_date ( ?, 'DD-MON-YYYY HH24:MI:SS' ) 
			     AND dbcode = 'E'
			     AND entry_type != 1
		        ORDER BY project#, primaryacc#
		    });

$mb->bind_param( 1, $today_midnight);
$mb->execute || bail ( "select from database failed", $dbh );

my @toRelease;
my $i=0;
while ( my ( $project, $acc, $hdate ) = $mb->fetchrow ) {
    push (@toRelease, $acc);

    if (!$i) {
	print "-------------------------\n"
	    . "standard entries:\n\n"
	    . "P   AC        HOLD DATE\n"
	    . "-------------------------\n";
    }

    printf "%2s  %-8s  %11s\n", ( $project != 0 ) ? $project : '', $acc, $hdate;
    $i++;
}
$mb->finish;  

my $releaseSql = $dbh->prepare(
		       q{ UPDATE dbentry
                             SET statusid = 4
			   WHERE primaryacc# = ?
			  });

my $releaseAc = "";

foreach $releaseAc (@toRelease) {
    ($test == 1) && (print " releasing $releaseAc");
    $releaseSql->bind_param( 1, $releaseAc);
    $releaseSql->execute || bail ( "release of $releaseAc failed", $dbh );

    if ($test) {
	dbi_rollback($dbh);
	print " *** Rolledback\n";
    }
    else {
	dbi_commit($dbh);
    }
}

if ($releaseAc ne "") {
    print "\n\ndata included";  # flag to send email
}

$releaseSql->finish;

#-------------------------------------------------------------------------------
# logout from database
#-------------------------------------------------------------------------------

#dbi_rollback ( $dbh );
dbi_logoff ( $dbh );



