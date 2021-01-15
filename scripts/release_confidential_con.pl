#!/ebi/production/seqdb/embl/tools/bin/perl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/release_confidential_con.pl,v 1.12 2012/07/09 13:30:59 mjang Exp $
#
#  release_confidential_con.pl
#  release confidential con entries:
#  check all confidential con entries with expired holddate or no holddate on
#  confidential segment entries
#    * no conf. segment entries: release con entry
#    * conf. segment entries and holddate expired: leave entry confidential and
#      report
#
#  NOTE: called after release of 'normal' confidential entries in 
#  check_hold_date.csh
#
#  10-APR-2003  Carola Kanz     created
#===============================================================================

use strict;
use warnings;
use DBI;
use dbi_utils;
use SeqDBUtils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n USAGE: $0 <user/password\@instance> [-test] [-h]\n\n";

@ARGV == 1 || @ARGV == 2 || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

hide(1);

my $login = $ARGV[0];
my $test  = 0;

for ( my $i = 1 ; $i < @ARGV ; ++$i ) {
    if ( $ARGV[$i] eq "-test" ) {
        $test = 1;
	print "Test MODE - transactions will rollback\n";
    }
    else {
        die ($usage);
    }
}

die if ( check_environment( $test, $login ) == 0 );

#-------------------------------------------------------------------------------
# connect to database and set auditremark
#-------------------------------------------------------------------------------

my $dbh = dbi_ora_connect($login);
dbi_do( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );
dbi_do( $dbh, "begin auditpackage.remark := 'entry automatically released'; end;" );


#-------------------------------------------------------------------------------
# get sysdate
#-------------------------------------------------------------------------------

my $today = dbi_getvalue($dbh,
    "SELECT to_char ( sysdate, 'DD-MON-YYYY' )
                                  FROM dual"
);
my $today_midnight = $today . " 23:59:59";

print "\n*************************\n"
    . "Releasing confidential entries with a hold date expiring\nat the end of "
    . "$today\n\n";

#-------------------------------------------------------------------------------
# release
# * expired con entries without any confidential segment entries
# * embl con entries without any confidential segment entries and without a
#   holddate
#-------------------------------------------------------------------------------

my $sql = "SELECT primaryacc#, nvl ( to_char ( hold_date, 'DD-MON-YYYY' ), '-' )
             FROM dbentry
            WHERE entry_type = 1
			  AND dbcode = 'E'
              AND (   ( statusid = 2 -- private
                         AND ( hold_date <= to_date ( '$today_midnight', 'DD-MON-YYYY HH24:MI:SS' ) 
                               OR hold_date is null ))
                   OR ( statusid in (5, 6)
                        AND  hold_date <= to_date ( '$today_midnight', 'DD-MON-YYYY HH24:MI:SS' ))) 
            ORDER BY primaryacc#";

my (@table) = dbi_gettable( $dbh, $sql );

my $i=0;
foreach my $row (@table) {
    my ( $accno, $holddate ) = @{$row};

    if (!$i) {
	print "\nReleased confidential con with expired holddate (or no holddate):\n\n"
	    . "AC        HOLD DATE\n"
	    . "-------------------------------------------------------------------\n";
    }

    # check segment entries for confidentiality
    my ($cnt) = dbi_getvalue($dbh,
	 "SELECT count ( d.primaryacc# ) 
          FROM dbentry d, con_segment_list csl
         WHERE csl.seg_seqid = d.bioseqid 
           AND d.statusid IN ( 1, 2, 3, 6 ) -- draft, private, cancelled, killed
           AND csl.con_seqid = ( 
                  SELECT bioseqid 
                    FROM dbentry 
                   WHERE primaryacc# = '$accno')"
    );

    if ( $cnt == 0 ) {
        dbi_do(
	       $dbh, "UPDATE dbentry
                       SET statusid = 4 -- public
                     WHERE primaryacc# = '$accno'"
        );
	if ($test) {
	    dbi_rollback($dbh);
	    print "*** Rolledback\n";	    
	}
	else {
	    dbi_commit($dbh);
	}

        printf "%-8s  %-11s\n", $accno, $holddate;
    }
    elsif ( $holddate ne '-' ) {
        printf "%-8s  %-11s  STILL CONF. SEGMENT ENTRIES, NOT RELEASED\n", $accno, $holddate;
    }

    $i++;
}

if ($i) {
    print "\n\ndata included\n";  # flag to send email
}

if ($test) {
    dbi_rollback($dbh);
    print "*** Rolledback\n";	    
}
else {
    dbi_commit($dbh);
}
dbi_logoff($dbh);

