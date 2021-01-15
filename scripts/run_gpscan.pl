#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# This script sparks off parallel runs of genome projects if any
# unprocessed data is found.
#
# This script is intended to be called from csh script which is
# called from the datalib cron
#
#
# Gemma Hoad 19-Aug-09
#===============================================================================

use strict;
use DBI;
use GenomeProjectPipeline;
use DBLog;

# changes to gpscan_test if in test mode
#my $DATA_DIR = '/ebi/production/seqdb/embl/data/gpscan';
my $DATA_DIR = '/ebi/production/seqdb/embl/data/ena_submission_accounts';
my $DATA_DIR_TEST = '/ebi/production/seqdb/embl/data/gpscan_test';

#my $SCRIPTS_DIR = '/ebi/production/seqdb/embl/tools/curators/scripts';
my $SCRIPTS_DIR = '/ebi/production/seqdb/embl/developer/gemmah/seqdb/seqdb/tools/curators/scripts';

#############################################################
#
sub get_args(\@) {
    
    my ($arg, $test_mode, $db, $usage);

    my $args = shift;

    my $verbose = 0;

    $usage = "Usage: run_gpscan.pl <user/password\@instance> [-help] [-test]\n\n"
	."This script (which must be run as datalib) is used to\n"
	."spark of lots of parallel executions of the genome\n"
	."project pipeline script.  All the genome directories\n"
	."are searched through for new files.\n\n"
	."The genome project pipeline script triggered by this script is:\n"
	.$SCRIPTS_DIR."/genome_project_pipeline.pl\n";

    foreach $arg (@$args) {

	if (($arg =~ /^\-h(elp)?/) || ($arg =~ /^\-usage/)) {
	    die $usage;
	}
	elsif ($arg =~ /\/\@(enapro|devt)$/i) {
	    $db = $arg;
	}
	elsif ($arg =~ /^-t(est)?/i) {
	    $test_mode = 1;
	}
	elsif ($arg =~ /\-v(erbose)?/) {
	    $verbose = 1;
	}
    }

    if (! defined($db)) {
	die $usage;
    }

    if (($test_mode) || ($db =~ /devt/i)) {
	$db = '/@devt';
	$DATA_DIR = $DATA_DIR_TEST;
	$test_mode = 1;
	print STDERR "Using test mode so devt is chosen by default.\n";
    }

    # I've put this here so you can read the helo message if not datalib
    if (($ENV{'USER'} ne 'datalib') && (!$test_mode)) {
	die "Script must be run by datalib\n";
    }

    return($db, $test_mode, $verbose);
}
#############################################################
#
sub update_genome_submission_report($) {

    my $prj = shift;

    my $cmd = 'bsub -q production -o /ebi/production/seqdb/embl/tools/log/create_genome_submission_report.lsf /ebi/production/seqdb/embl/tools/operations/create_genome_submission_report.csh '.$prj;

    system($cmd);
}
#############################################################
#
sub get_active_projects($) {

    my $dbh = DBI->connect( 'dbi:Oracle:'.$db, '', '', {RaiseError => 1, PrintError => 1, AutoCommit => 0} ) || die "Can't connect to database: $DBI::errstr\n ";

    my $sql = "select project_abbrev, dir_name from cv_project_list where active='Y'";
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    
    my @projects;
    while (my $project_abbrev = $sth->fetchrow_array()) {
	push(@projects, $project_abbrev);
    }

    $dbh->disconnect;

    return(\@projects);
}
#############################################################
#
sub get_list_of_projects_needing_processing($$) {

    my ($project_dir, $files_found, @processing_dirs, @listing);
    my ($item, $all_project_dirs, $processing_dir, @dirs_to_process);

    my $dbh = shift;
    my $verbose = shift;

    @processing_dirs = qw{ftp uncompressed uncompressed_with_accs ready_for_processing split_seq split_bqv};

    #@all_project_dirs = glob("$DATA_DIR/*");
    $all_project_dirs = get_active_projects();

    foreach $project_dir (@$all_project_dirs) {

	# if a directory
	if (-d $project_dir) {

	    $files_found = 0;

	    foreach $processing_dir (@processing_dirs) {

		if (-e "$project_dir/$processing_dir") {
		    @listing = glob("$project_dir/$processing_dir/*");
		    
		    foreach $item (@listing) {

			# is a plain file
			if (-f $item) {
			    $files_found = 1;
			    last;
			}
		    }
		}
		
		if ($files_found) {
		    last;
		}
	    }
	    
	    if ($files_found) {
		
		$project_dir =~ /.+\/([^\/]+)$/;
		push(@dirs_to_process, $1); 
	    }
	}
    }
	
    $verbose && print STDERR "dirs in need of processing:\n".join("\n", @dirs_to_process)."\n\n";

    return(\@dirs_to_process);
}
#############################################################
#
sub main(\@) {

    my ($db, $test_mode, $cmd, $date, $prj, $logger);
    my ($projects_with_data, $log_id, $dbh, $verbose);

    my $args = shift;

    $test_mode = 0;

    ($db, $test_mode, $verbose) = get_args(@$args);

    $logger = DBLog->new(dsn => $db,
			 module => 'GPSCAN', 
			 proc   => 'CONTROLLER'
			 );
    $log_id = $logger->get_log_id();

    if( $log_id < 0 ) {
	die "Could not get log ID from database.\n";
    }


    $projects_with_data = get_list_of_projects_needing_processing($verbose);


    $date = `date`;
    print STDERR "###-------------------------###\n$date";

    if (@$projects_with_data) {

	foreach $prj (@$projects_with_data) {

	    print STDERR "Running $prj project\n";

	    $cmd = "$SCRIPTS_DIR/genome_project_pipeline.pl $db $prj -log_id=$log_id ";

	    if ($verbose) {
		$cmd .= "-verbose ";
	    }

	    if (!$test_mode) {
		$cmd .= ">> $ENV{LOGDIR}/gpscan_new.log";
	    }
	    else {
		$cmd .= "-test >> $ENV{LOGDIR}/gpscan_new.log.test_mode";
	    }
	    
	    #print "cmd = $cmd\n";
	    system($cmd);
	}
    }
    else {
	print STDERR "No files available for processing\n";
    }

    $logger->finish();
}
#############################################################
#

main(@ARGV);
