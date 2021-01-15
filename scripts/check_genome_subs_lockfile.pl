#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# This script emails if a genome submissions account LOCK file is
# found which is more than a day old.
#
# Gemma Hoad  11-Dec-2009

use DBI;
use dbi_utils;

my $DATA_ROOT = "/ebi/production/seqdb/embl/data/gpscan";
#my $DATA_ROOT = "/ebi/production/seqdb/embl/data/ena_submission_accounts";



sub get_args(\@) {

    my $args = shift;

    my $db = "";
    my $test = 0;

    foreach my $arg (@$args) {

	if ($arg =~ /(devt|enapro)/) {
	    $db =  $arg;
	}
	elsif ($arg =~ /-t(est)?/) {
	    $test = 1;
	}
    }

    if ($db eq "") {
	$db = '/@enapro';
    }

    return($db, $test);
}

sub get_project_names($) {

    my $dbh = shift;

    my $sql = "select project_abbrev from cv_project_list where active='Y'";

    my $sth = $dbh->prepare($sql);
    $sth->execute();
    
    my @project_names;
    while (my $project_name = $sth->fetchrow_array()) {
	push(@project_names, $project_name);
    }

    return(\@project_names);
}

sub main() {

    my ($db, $test) = get_args(@ARGV);
    my $dbh = dbi_ora_connect($db);

    
    my $project_names = get_project_names($dbh);
    $dbh->disconnect();

    my @lockfiles;
    foreach my $project_name (@$project_names) {
	
	my $lockfile = "$DATA_ROOT/$project_name/LOCK";
	#print "$lockfile - does it exist?\n";
	if (-e "$lockfile") {
	    
	    #print "Checking $lockfile\n";
	    if (-M "$lockfile" >= 1.0) {
		
		#print "Lockfile is more than a day old\n\n";
		push(@lockfiles, $lockfile);
	    }
	}
    }
    
    if (@lockfiles) {
	my $email_subject = "Old genome submissions LOCK file found";
	my $email_addresses = "nimap\@ebi.ac.uk, xin\@ebi.ac.uk";

	if ($test) {
	    $email_addresses = "gemmah\@ebi.ac.uk";
	}
	my $email_text = "LOCK files older than one day has been found:\n\n"
	    .join("\n",@lockfiles)."\n\n";
    
	open(MAIL, "|/usr/sbin/sendmail -oi -t");
	
	print MAIL "To: $email_addresses\n"
	    . "From: datalib\@ebi.ac.uk\n"
	    . "Subject: $email_subject\n"
	    . $email_text;
	
	close(MAIL);
    }
}

main();
