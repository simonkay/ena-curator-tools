#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/putffer.pl,v 1.5 2011/11/29 16:33:38 xin Exp $
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

sub create_parsed_load_log_summary($$) {

    my ($response, $cmd1, $cmd2, $extra_opts, $full_cmd);

    my $lowest_form_file_ext = shift;
    my $parse_loadlog_options = shift;


    if ($lowest_form_file_ext =~ /ffl(upd)?/) {
	$cmd1 = '/ebi/production/seqdb/embl/tools/curators/scripts/parse_loadlog.pl load.log ';
    }
    else {
	$cmd1 = '/ebi/production/seqdb/embl/tools/curators/scripts/parse_loadlog_noaccinput.pl load.log ';
    }

    $cmd2 = '> ckprots.log';

    $full_cmd = $cmd1.$parse_loadlog_options.$cmd2 ;

#    $extra_opts = '';

#    print "Do you want to create a summary of the loading (y/n)?\n" ;
#    $response = <STDIN>;

#    if ($response !~ /^y(es)?\s*$/i) {
#	die "Note that a summary can be produced by running the following command at any time:\n$cmd1$cmd2\nNB The output will be added to ckprots.log\n-sub option will give a submitter report (without certain curator-only warnings)\n-noacc will remove the accessions and add DE lines as identifiers instead.\n\nExiting script.\n";
#    }

#    print "Is this report intended for submitter viewing (y/n)?\n";
#    $response = "";  # clear previous response
#    $response = <STDIN>;

#    if ($response =~ /^y(es)?\s*$/i) {
#	$extra_opts = '-sub ';
#    }

#    if ($lowest_form_file_ext =~ /ffl(upd)?/) {
#	print "Do you want to see the accession numbers in the report (y/n)?\n";
#	$response = "";  # clear previous response
#	$response = <STDIN>;
	
#	if ($response =~ /^n(o)?\s*$/i) {
#	    $extra_opts .= '-noacc ';
#	}
#    }

#    $full_cmd = $cmd1.$extra_opts.$cmd2;

#    if ($verbose) {
#	print "Creating summary of protein checks using:\n$full_cmd\n\n"; 
#    }

    system($full_cmd);

    print "ckprots.log has been created with the parsed loadcheck output.\n";
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub load_or_load_check_files($$$\@) {

    my ($cmd, $extra_opts, $pipe_cmd);

    my $ds = shift;
    my $database = shift;
    my $mode = shift;
    my $input_files = shift;

    if ($mode eq 'load') {
	$extra_opts = '';
	$pipe_cmd = '| tee';
    }
    else {
	$extra_opts = ' -parse_only';
	$pipe_cmd = '>&';
    }

    $cmd = "putff $database load.dat -ds $ds -no_error_file -new_log_format"
	 . $extra_opts.' '.$pipe_cmd.' load.log';

    if ($verbose) {
	print $mode."ing using:\n$cmd\n\n";
    }

    print $mode."ing may take a minute. Please wait...\n\n";

    system($cmd);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub concatenate_data_files(\@) {

    my ($cmd);

    my $input_files = shift;

    $cmd = "cat ".join(" ", @$input_files) . " > load.dat";

    if ($verbose) {
	print "Creating load.dat from all the data files:\n$cmd\n\n";
    }

    system($cmd);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub check_for_assign_accno_log(\@) {

    my ($file, @ffl_files, $num_ffls);

    my $input_files = shift;

    # .ffl files must have assign_accno.log present in order to load
    if (! -e 'assign_accno.log') {

	foreach $file (@$input_files) {
	    if ($file =~ /\.ffl$/) {
		push(@ffl_files, $file);
	    }
	}
    }

    $num_ffls = scalar(@ffl_files);

    if ($num_ffls) {
	die "The following $num_ffls .ffl files have been taken as input but there is no assign_accno.log file in this directory:\n".join("\n", @ffl_files)."\n...and so the .ffl files will not be loaded.\n";
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_lowest_form_of_file_ext(\@) {

    my ($lowest_form_file_ext, $file);

    my $input_files = shift;

    foreach $file (@$input_files) {
	if ($file =~ /\.(subs)?$/i) {
	    $lowest_form_file_ext = $1;
	}
	elsif ($file =~ /\.(temp)$/) {
	    $lowest_form_file_ext = $1;
	}
	elsif ($file =~ /\.(ffl(upd)?)$/) {
	    $lowest_form_file_ext = $1;
	}
    }

    return($lowest_form_file_ext);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_input_files($\@) {

    my ($suffix, @file_suffixes, @files, $response);

    my $mode = shift;
    my $input_files = shift;

    @file_suffixes = ('.fflupd', '.ffl', '.temp', 'BULK.SUBS', '.sub');


    foreach $suffix (@file_suffixes) {

	if ($suffix eq 'BULK.SUBS') {
	    @files = glob($suffix);
	}
	else {
	    @files = glob('*'.$suffix);
	}

	if (@files) {

	    if (($suffix eq '.fflupd') || ($verbose)) {
		print "The following files have been found:\n".join("\n", @files)."\n\n";
	    }

	    if (($suffix eq '.fflupd') && ($mode eq 'load')) {
		print "Go ahead and load these files (y/n)? ";
		$response = <STDIN>;

		if ($response !~ /^y(es)?\s*$/i) {
		    die "Exiting script.\n";
		}
	    }

	    last;
	}
    }

    if (@files) {
	@$input_files = @files;
    }
    else {
	die "No suitable input files can be found to load in this directory (.fflupd, .ffl, .temp, BULK.SUBS, .sub)\n";
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_ds_and_database($) {

    my ($current_working_dir, $ds);

    my $database = shift;
    
    $current_working_dir = cwd;

    if ($current_working_dir =~ /$ENV{DS}\/(\d+)$/) {
	$ds = $1;

	if ($database eq "") {
	    $database = '/@enapro';
	}
    }
    elsif ($current_working_dir =~ /$ENV{DS_TEST}\/(\d+)$/) {
	$ds = $1;

	if ($database eq "") {
	    $database = '/@devt';
	}
    }
    elsif ($current_working_dir =~ /\/ds\/(\d+)$/) {
	$ds = $1;

	if ($database eq "") {
	    $database = '/@devt';
	}
    }
    else {
	die "This script must be run from a ds or ds_test directory.\n";
    }

    return($ds, $database);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_args(\@) {

    my ($arg, @input_files, $mode, $file, $lowest_form_file_ext, $ds, $database);
    my ($parse_loadlog_options);

    my $args = shift;

    my $usage = "\n PURPOSE: The script loadchecks or loads embl entries, depending on\n".
	"          the input options used.  It must be run from a ds directory.\n\n".
	"          The script offers the option of running a ckprots-like script which\n".
	"          offers to parse the putff output.  The output of this is designed to\n".
	"          be read by the curator or submitter (submitters only see entries\n".
	"          with errors).\n\n".
	"          Previously load.csh and loadcheck.csh performed the same tasks as\n".
	"          this script\n\n".
        " USAGE:  $0 username/password\@db (-load | -loadcheck) [-v(erbose)?] [space-separated filename list] [-s(ubmitter)] [-noac(c)]\n\n".
	' username/password@db    /@enapro or /@devt'."\n\n".
        " [space-separated filename list]  optionally, you can specify particular files you\n".
	"              want to check for loading or to simply load. If no files are entered,\n".
	"              the script looks for *.fflupd files in the current ds directory to use\n".
	"              as input entries. If none are found, *.ffl files are looked for (then\n".
	"              BULK.SUBS, *.temp and then *.sub files in that order of priority).\n\n".
        " -loadcheck   check to see if there are any errors given if the input files were to\n".
	"              load. (default option if -load and -loadcheck options are omitted)\n\n".
	" -load        load the entries (it is suggested that loadcheck is tried beforehand).\n\n".
        "-s(ubmitter)   this is an indication of whether to run the parse_loadlog script in\n".
	"              submitter mode. (optional argument)\n\n".
	"-noac(c)     this indicates whether you would like to see accession numbers displayed\n".
	"              in the output from the parse_loadlog script (parsed putff results). (optional\n".
	"              argument)".
        "\n\n";


    $database = "";
    $parse_loadlog_options = "";

    foreach $arg (@$args) {
        
        if (($arg =~ /^-h(elp)?/i) || ($arg =~ /^-u(sage)?/i)) {
            die $usage;
        }
        elsif ($arg =~ /^(\/\@(enapro|devt))$/i) {
            $database = $1;
        }
        elsif ($arg =~ /^-load$/i) {
            $mode = 'load';
        }
        elsif ($arg =~ /^-loadcheck$/i) {
            $mode = 'loadcheck';
        }
	elsif ($arg =~ /-v(erbose)?/i) {
	    $verbose = 1;
	}
	elsif ($arg =~ /-s(ubmitter)?/i) {
	    $parse_loadlog_options .= " -sub";
	}
	elsif ($arg =~ /-noac(c)?/i) {
	    $parse_loadlog_options .= " -noacc";
	}
        elsif ($arg =~ /^([^-]+.*)$/) {
            push (@input_files, $1);
        }
    }

    ($ds, $database) = get_ds_and_database($database); # added here because it's a suitable place to have the 'you must run this script in a ds directory' message - after the help message can be retrieved 

    if (! defined($mode)) {
	$mode = 'loadcheck';
    }

    if (@input_files) {
	foreach $file (@input_files) {
	    if (! -e $file) {
		die "The input file $file can't be found.\n$usage";
	    }
	}
    }
    else { 
	get_input_files($mode, @input_files);
    }

    # add the input files to a file for reference by parse_loadlog_noacc.pl
    open (WRITE_INPUT_FILES, ">putffer.input_files");
    print WRITE_INPUT_FILES join("\n", @input_files)."\n";
    close(WRITE_INPUT_FILES);


    $lowest_form_file_ext = get_lowest_form_of_file_ext(@input_files);

    if ($mode eq 'load') {
	foreach $file (@input_files) {

	    if (($file eq 'BULK.SUBS') || ($file =~ /\.(sub|temp)$/)) {
		die "You cannot load BULK.SUBS, *.temp or *.sub filed, only loadcheck them.\nExiting script.\n"; 	
	    }
	}
    }
    
    check_for_assign_accno_log(@input_files);

    print "...".$mode."ing...\n\n";

    return($mode, \@input_files, $lowest_form_file_ext, $ds, $database, $parse_loadlog_options);
}

#-------------------------------------------------------------------------------------
# main flow of program
#-------------------------------------------------------------------------------------

sub main(\@) {

    my ($ds, $database, $mode, $input_files, $lowest_form_file_ext);
    my ($parse_loadlog_options);

    my $args = shift;

    ($mode, $input_files, $lowest_form_file_ext, $ds, $database, $parse_loadlog_options) = get_args(@$args);

    concatenate_data_files(@$input_files);

    load_or_load_check_files($ds, $database, $mode, @$input_files);

    if ($mode eq 'loadcheck') {
	create_parsed_load_log_summary($lowest_form_file_ext, $parse_loadlog_options); # a.k.a. ckprots
    }
}

#-------------------------------------------------------------------------------------
# run program
#-------------------------------------------------------------------------------------

main(@ARGV);
