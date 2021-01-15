#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/assign_for_multiple_ds_directories.pl,v 1.4 2011/11/29 16:33:37 xin Exp $
#
#  (C) EBI 2008
#
###############################################################################

use strict;
use Cwd;

my $verbose = 0;


#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub run_assign_on_ds_dirs(\@$$) {

    my ($cmd, $exit_status, $current_working_dir, $ds);

    my $ds_dirs = shift;
    my $ds_dir_root = shift;
    my $database = shift;

    $exit_status = 0;

    # grab current directory
    $current_working_dir = cwd;

    # create assign command
    $cmd = "assign_accno.pl $database";

    if ($database !~ /enapro$/i) {
	$cmd .= " -test";
    }

    foreach $ds (@$ds_dirs) {
	chdir($ds_dir_root.$ds);
	$ENV{'PWD'} = $ds_dir_root.$ds;

	if ($verbose) {
	    print "Assigning in $ds using $cmd\n";
	}

	$exit_status = system($cmd);

	if ($exit_status == 0) {
	    print "Assigning in ds $ds was successful\n";
	}
	else {
	    chdir($current_working_dir);
	    die "ERROR: Assigning in ds $ds was NOT successful.  This ds and ds's of a higher number requested for assignment have not been assigned.\n";
	}
    }

    #chdir($current_working_dir);
    $ENV{'PWD'} = $current_working_dir;
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub check_valid_files_exist_in_ds_dirs(\@$) {

    my (@temp_files, $bulk_subs_file, @assignaccno_files, $ds, $temp_file_num);
    my ($bulk_subs_num);

    my $ds_dirs = shift;
    my $ds_dir_root = shift;

    if ($verbose) {
	print "\nChecking there are *.temp files or BULK.SUBS files present in all the ds directories and that there are no assign_accno.log files lying around (indicating assignment has already happened).\n\n";
    }

    foreach $ds (@$ds_dirs) {

	@temp_files = ();

	# check there are files to assign in ds
	@temp_files = glob($ds_dir_root.$ds.'/*.temp');
	$bulk_subs_file = $ds_dir_root.$ds.'/BULK.SUBS';

	if ((!@temp_files) && (! (-e $bulk_subs_file))) {
	    die "There are no *.temp files or BULK.SUBS found in ".$ds_dir_root.$ds."\nThese are required in all the inputted ds directories in order to assign accessions.\n";
	}

        # check files in ds have not already been assigned
	if (-e $ds_dir_root.$ds.'/assign_accno.log') {
	    die "An assign_accno.log file has been found in $ds_dir_root$ds indicating entries in this ds directory have already been assiged.\nThis script needs all input ds directories to contain unassigned entries in order to proceed.\n";
	}

	if (@temp_files) {
	    $temp_file_num += scalar(@temp_files);
	}
	    
	if (-e $bulk_subs_file) {
	    $bulk_subs_num++;
	}
    }

    if ($temp_file_num) {
	print "$temp_file_num temp files found\n";
    }

    if ($bulk_subs_num) {
	print "$bulk_subs_num BULK.SUBS file(s) found\n";
    }

    if ($verbose) {
	print "\nClear to go ahead and start assigning accessions.\n\n";
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_args(\@) {

    my ($arg, @ds_dirs, %ds_dirs, $database, $ds, @ds_not_valid, $ds_dir_root);

    my $args = shift;

    my $usage = "\n PURPOSE: The assigns accessions to *.temp or BULK.SUBS entries bulks in\n".
	"          different ds directories at the same time.\n\n".
        " USAGE:  $0 username/password\@db [space-separated ds list] [-v(erbose)?]\n\n".
        ' username/password@db        /@enapro or /@devt'."\n\n".
	" [space-separated ds list]   a list of 1+ different ds numbers you want to assigning\n".
	"                             together e.g. 70623 70654 71456\n\n".
	" -v(erbose)                  verbose mode\n\n";

    @ds_dirs =();

    foreach $arg (@$args) {
        
        if (($arg =~ /^-h(elp)?/i) || ($arg =~ /^-u(sage)?/i)) {
            die $usage;
        }
        elsif ($arg =~ /^(\/\@(enapro|devt))$/i) {
            $database = $1;
        }
	elsif ($arg =~ /-v(erbose)?/i) {
	    $verbose = 1;
	}
        elsif ($arg =~ /^(\d+)$/) {
            push (@ds_dirs, $1);
	    $ds_dirs{$1} = 1;  # created to inidcate presence of duplicates
        }
	else {
	    die "Option $arg not recognised\n\n$usage";
	}
    }

    # check for presence of ds dir input options and if these dirs exist.
    if (!@ds_dirs) {
	die "At least one ds directory is required as input.\n\n$usage";
    }
    else {

	if (scalar(@ds_dirs) > scalar(keys %ds_dirs)) {
	    die "The list of ds directories entered is contains duplicates.  Please try again.\n";
	}

	if ($database =~ /enapro$/i) {
	    $ds_dir_root = $ENV{DS}.'/';
	}
	else {
	    $ds_dir_root = $ENV{DS_TEST}.'/';
	}

	foreach $ds (@ds_dirs) {
	    if (! (-e $ds_dir_root.$ds)) {
		push(@ds_not_valid, $ds);
	    }
	}

	if (@ds_not_valid) {
	    die "These DS directories were not found in $ds_dir_root:\n".join("\n", @ds_not_valid)."\n\n".$usage;
	}
    }

    if ($verbose) {
	print "Chosen ds directories:\n".join("\n",@ds_dirs)."\n";
    }

    return(\@ds_dirs, $ds_dir_root, $database);
}

#-------------------------------------------------------------------------------------
# main flow of program
#-------------------------------------------------------------------------------------

sub main(\@) {

    my ($ds, $database, $ds_dirs, $ds_dir_root);

    my $args = shift;

    ($ds_dirs, $ds_dir_root, $database) = get_args(@$args);

    check_valid_files_exist_in_ds_dirs(@$ds_dirs, $ds_dir_root);

    run_assign_on_ds_dirs(@$ds_dirs, $ds_dir_root, $database);
}

#-------------------------------------------------------------------------------------
# run program
#-------------------------------------------------------------------------------------

main(@ARGV);
