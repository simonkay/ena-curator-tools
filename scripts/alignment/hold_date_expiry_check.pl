#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  hold_date_expiry_check.pl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/alignment/hold_date_expiry_check.pl,v 1.3 2011/06/20 09:39:35 xin Exp $
#
#  DESCRIPTION:
#
#  checks the alignment hold date to see if it's ready for release.  Accessions in the SO lines are
#  checked too to see if they are public since the file can't be released if not.
#
#  MODIFICATION HISTORY:
#
#  01-12-2008 Gemma Hoad   Created
# 
#===============================================================================



use strict;
use Time::Local;
use DBI;
use DBD::Oracle;

my $ALIGN_DATA = '/ebi/production/seqdb/embl/data/alignment/';

#----------------------------------------------------

sub get_todays_date() {

    my ($today, $today_numeric, $dd, $mm, $yy);

    $today = `date '+%d-%m-%Y'`;
    ($dd, $mm, $yy) = split('-', $today);
    $mm = $mm - 1;  # months are 0-11 in timelocal function
    $today_numeric = timelocal(0,0,0,$dd,$mm,$yy);

    return($today_numeric);
}

#----------------------------------------------------

sub get_entry_status_of_sec_acc($$) {

    my ($sql, $sth, $status);

    my $acc = shift;
    my $dbh = shift;

    if ($acc ne "CONSTRUCTED") {
	$sql = "select s.status from dbentry d, cv_status s where d.statusid = s.statusid and d.primaryacc# = ?";
	$sth = $dbh->prepare($sql);
	$sth->execute($acc);
	$status = $sth->fetchrow_array();
	$sth->finish();

	if ((!defined($status)) || ($status eq "")) {
	    $status = "unavailable";
	}
    }

    if ((!defined($status)) || ($status eq "")) {
	$status = "unavailable";
    }

    return($status);
}

#----------------------------------------------------

sub move_entry_to_public_dir($) {

    my ($cmd);

    my $aln_acc = shift;

    $cmd = "mv $ALIGN_DATA/private/$aln_acc.* $ALIGN_DATA/public/";
    #$cmd = "mv ~/tmp/enapro/private/$aln_acc.* ~/tmp/enapro/public/";
    system($cmd);
    #print "\nRunning $cmd\n\n";
}

#----------------------------------------------------

sub get_numeric_date($) {

    my ($dd, $mm, $yy, $aln_hold_date_numeric);

    my $aln_hold_date = shift;

    ($dd, $mm, $yy) = split('-', $aln_hold_date);

    if ($mm eq "JAN") { $mm = 0; }
    elsif ($mm eq "FEB") { $mm = 1; }
    elsif ($mm eq "MAR") { $mm = 2; }
    elsif ($mm eq "APR") { $mm = 3; }
    elsif ($mm eq "MAY") { $mm = 4; }
    elsif ($mm eq "JUN") { $mm = 5; }
    elsif ($mm eq "JUL") { $mm = 6; }
    elsif ($mm eq "AUG") { $mm = 7; }
    elsif ($mm eq "SEP") { $mm = 8; }
    elsif ($mm eq "OCT") { $mm = 9; }
    elsif ($mm eq "NOV") { $mm = 10; }
    elsif ($mm eq "DEC") { $mm = 11; }

    $aln_hold_date_numeric = timelocal(0,0,0,$dd,$mm,$yy);
    
    return($aln_hold_date_numeric);
}

#----------------------------------------------------

sub main() {

    my (@dat_files, $dat_file, $line, $aln_hold_date, $today_numeric, $SO_line_acc);
    my ($alignment_acc, $aln_hold_date_numeric, $sec_acc_entry_status, $dbh, %attr);
    my ($msg, $aln_ready_for_release, $sec_acc_not_public);


    %attr   = ( PrintError => 0,
		RaiseError => 0,
		AutoCommit => 0 );
    $dbh = DBI->connect( 'dbi:Oracle:'.'enapro', '/', '', \%attr ) || die "Can't connect to database: $DBI::errstr\n ";   


    $today_numeric = get_todays_date();

    open(WRITEREPORT, ">".$ENV{LOGDIR}."/hold_date_expiry.report");

    @dat_files = `ls -1 $ALIGN_DATA/private/ALIGN_*.dat`;


    foreach $dat_file (@dat_files) {

	chomp($dat_file);

	if ($dat_file =~ /(ALIGN_\d+)\.dat$/) {
	    $alignment_acc = $1;
	    $dat_file = $alignment_acc.".dat";
	}
	
	if (open(READDATES, "<$ALIGN_DATA/private/$dat_file")) {

	    $msg = "\n---------------------------\nFILE: $dat_file (hold date: ";
	    $aln_ready_for_release = 0;
	    $sec_acc_not_public = 0;
	    $aln_hold_date_numeric = 0;

	    while ($line = <READDATES>) {

		if ($line =~ /^FH   Key/) {
		    last;
		}
		elsif ($line =~ /^DT   (\d{2}\-[A-Z]{3}\-\d{4})/) {
		    $aln_hold_date = $1;
		    $aln_hold_date_numeric = get_numeric_date($aln_hold_date);
		    $msg .= "$aln_hold_date) \n";
		}
		elsif ($aln_hold_date_numeric != 0) {

		    # if alignment is due for release, check it's secondary accessions
		    if ($aln_hold_date_numeric <= $today_numeric) {

			# print message once
			if ($aln_ready_for_release < 1) {
			    $msg .= " --- due for release\n\n";
			    $aln_ready_for_release = 1;
			}

			if ($line =~ /^SO   \d+\s+\S+\s+(\S+)\s+/) {
			    $SO_line_acc = $1;
			    ($sec_acc_entry_status) = get_entry_status_of_sec_acc($SO_line_acc, $dbh);
			
			    $msg .= "$SO_line_acc: $sec_acc_entry_status\n";

			    if ($sec_acc_entry_status ne "public") {
				$sec_acc_not_public++;
			    }

			}
			elsif ($line =~ /^SO/) {
			    $msg .= "SO line format not recognised in $dat_file: $line\n";
			}
		    }
		    # print out accession and status (if private, for the log file
		    elsif ($aln_hold_date_numeric > $today_numeric) {

			if ($line =~ /^SO   \d+\s+\S+\s+(\S+)\s+/) {
			    $SO_line_acc = $1;
			    ($sec_acc_entry_status) = get_entry_status_of_sec_acc($SO_line_acc, $dbh);
			
			    $msg .= "$SO_line_acc: $sec_acc_entry_status\n";

			    if ($sec_acc_entry_status ne "public") {
				$sec_acc_not_public++;
			    }
			}
			elsif ($line =~ /^SO/) {
			    $msg .= "SO line format not recognised in $dat_file: $line\n";
			}
		    }
		}

	    }
	    
	    close(READDATES);

	    print WRITEREPORT $msg;
	    print $msg;
	    
	    if ($aln_ready_for_release && (!$sec_acc_not_public)) {
		$msg = "\nMoving $dat_file to the public folder\n";
		move_entry_to_public_dir($alignment_acc);
	    }
	    #i.e. alignment is not yet ready for release
	    elsif (!$aln_ready_for_release) { 
		$msg = " --- not ready for release\n\n";
	    }
	    #i.e. alignment is due for release but secondary accessions are not yet public
	    elsif ($aln_ready_for_release && $sec_acc_not_public) {
		$msg = "\nSecondary accessions in $dat_file have not yet reached public status\n\n";
	    }

	    print WRITEREPORT $msg;
	    print $msg;
	}
	else {
	    print "Cannot open $dat_file for reading\n";
	}
    }

    $dbh->disconnect();

    close(WRITEREPORT);
}


main();

