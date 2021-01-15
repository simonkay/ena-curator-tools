#!/ebi/production/seqdb/embl/tools/bin/perl -w

#===============================================================================
# This script is intended to be a blackbox which runs enapro loading.  Initially 
# it will use both putff and the validator to show the load status of each entry
# but in time putff checks will be phased out and the validator messages will
# become dominant. The intention is that output will remain the same from the 
# script regardless of the processes running within it.
#
#
#===============================================================================

use strict;
use Getopt::Long;
use SeqDBUtils2 qw(get_input_files timeDayDate);
use DBI;
use Data::Dumper;


# settings from command line
#my $opt_noVal        = 0;
my $opt_ds            = 0;
my $opt_parseOnly     = 0;
my $opt_rollback      = 0;
my $opt_noErrorFile   = 0;
my $opt_newLogFormat  = 0;
my $opt_dataclass     = "";
my $opt_ncbi          = 0;
my $opt_genome_sub_id = 0;    # project id (datalib.project.projectid)
my $opt_audit         = 0;
my $opt_val_args      = "";   
my $opt_putff_args    = "";
my $opt_keep_reports  = 0;
my $verbose           = 0;
my $help              = 0;


my $val_error_email   = 'gemmah@ebi.ac.uk'; # test email address
my $putff_error_email = 'gemmah@ebi.ac.uk'; # test email address
#my $val_error_email   = 'lbower@ebi.ac.uk, nimap@ebi.ac.uk, xin@ebi.ac.uk';
#my $putff_error_email = 'reddyk@ebi.ac.uk, nimap@ebi.ac.uk, xin@ebi.ac.uk';
my $val_error_contact    = 'Lawrence';
my $putff_error_contact  = 'Kethi';

# name of final output file containing all results (timestamp in filename for uniqueness)
my $all_output_file = "load_info_".SeqDBUtils2::timeDayDate('yyyy-mm-dd-time').".val";

my @val_info_files = qw(VAL_ERROR.del VAL_INFO.del VAL_REPORTS.del FORMAT_ERRORS.del VAL_FIXES.del);

my $putff_output_suffix = "putff_out"; 
#--------------------------------------------------------------------------------------------------
#
sub get_all_validator_messages_for_this_entry($$$\@) {

    my $entry_start_linenum = shift;
    my $entry_end_linenum   = shift;
    my $infile              = shift;
    my $val_file_handles    = shift; # array of 5 file handles of validator output files.  If file is empty, filehandle is undefined

    my @entry_lines;

    foreach my $fh (@$val_file_handles) {

	if (defined $fh) {
	    seek $fh, 0, 0; # reset filehandle to top of file (required for each entry)

	    while (my $line = <$fh>) {

		if ($line =~ /line: (\d+) of $infile/) {

		    if (($1 >= $entry_start_linenum) && ($1 <= $entry_end_linenum)) {
			push(@entry_lines, $line);
		    }
		}
	    }
	}
    }

    return(\@entry_lines);
}
#--------------------------------------------------------------------------------------------------
#
sub open_5_val_info_files($) {
    
    my $infile = shift;
    my @VAL_FH;

    # if exists and is of non-zero size
    for (my $i=0; $i<5; $i++) {

	my $filename = $infile.".".$val_info_files[$i];

	if (-s $filename) { 
	    open($VAL_FH[$i], "<$filename"); 
	}
    }

    return(\@VAL_FH);
}
#--------------------------------------------------------------------------------------------------
#
sub close_5_val_info_files(\@) {

    my $VAL_FH = shift;

    foreach my $fh (@$VAL_FH) {
	if (defined $fh) {
	    close($fh);
	}
    }
}
#--------------------------------------------------------------------------------------------------
#
sub parse_files_into_single_output($$\%) {

    my $infile = shift;
    my $OUT_FH = shift;
    my $entry_start_linenums = shift;

    my ($putff_line, @putff_messages, $accession, $load_status, $entry_start_linenum, $entry_end_linenum, $val_messages, $putff_summary);
    my $entry_counter = 0;

    # putff results file
    open(PUTFF_RES, "<$infile.$putff_output_suffix");

    # array of 5 file handles.  If the file is empty, filehandle is undefined
    my $VAL_FH = open_5_val_info_files($infile);

    my $grab_putff_summary = 0;

    while ($putff_line = <PUTFF_RES>) {

	if (($grab_putff_summary) || ($putff_line =~ /^(INFO: )?total elapsed time:/)) {
	    $putff_summary .= $putff_line;
	    $grab_putff_summary = 1;
	}
	elsif ($putff_line !~ /^(INFO: )?\#\#\# /) {
	    push(@putff_messages, $putff_line);
	    
	}
	#when you hit the load-status line for the entry (e.g. ### failed entry: GG123456), 
	# find all the validator messages and print out before the load-status line is printed.
	elsif ($putff_line =~ /^(INFO: )?(\#\#\# \S+ entry: (\S*))/) {
	    $accession = $3;
	    $load_status = $2;

	    $entry_start_linenum = $$entry_start_linenums{$infile}[$entry_counter];

	    if (defined $$entry_start_linenums{$infile}[($entry_counter+1)]) {
		$entry_end_linenum = $$entry_start_linenums{$infile}[($entry_counter+1)] -1;
	    }
	    else {
		my $entry_end_linenum_string = `wc -l $infile`;
		$entry_end_linenum_string =~ /^(\d+)\s/;
		$entry_end_linenum = $1;
	    }

	    $val_messages = get_all_validator_messages_for_this_entry($entry_start_linenum, $entry_end_linenum, $infile, @$VAL_FH);

	    my $output = "$load_status\n".join("", @putff_messages).join("", @$val_messages)."-------------------\n";
	    print $output;
	    print $OUT_FH $output;

	    @putff_messages = ();
	    $entry_counter++;
	}
    }

    if ($grab_putff_summary) {
	$putff_summary = "Summary\n$putff_summary";
	print $putff_summary;
	print $OUT_FH $putff_summary;	
    }

    close(PUTFF_RES);
    close_5_val_info_files(@$VAL_FH);
}

#--------------------------------------------------------------------------------------------------
#
sub generate_combined_report(\@\%\%\%) {

    my $infiles = shift;
    my $val_failed = shift;
    my $putff_failed = shift;
    my $entry_start_linenums = shift;

    my $OUTFILE;
    open($OUTFILE, ">$all_output_file");

    foreach my $infile (@$infiles) {
	
	parse_files_into_single_output($infile, $OUTFILE, %$entry_start_linenums);
    }

    close($OUTFILE);
}
#--------------------------------------------------------------------------------------------------
#
sub get_entry_start_line_numbers(\@\%\%) {

    my $infiles = shift;
    my $val_failed_list = shift;
    my $entry_start_linenum = shift;

    my $linenum;

    foreach my $infile (@$infiles) {

	# if file hasn't failed in the validator
	if (! defined $$val_failed_list{$infile}) {

	    my @id_lines = `grep -n ^ID $infile`;

	    for (my $i=0; $i<@id_lines; $i++) {

		$linenum = 0;

		if ($id_lines[$i] =~ /(\d+)\:ID\s+[^;]*;/) {

		    $linenum = $1;

		    # e.g. 45:ID   AH123456; SV 1;... including if accession is XXX
		    $$entry_start_linenum{$infile}[$i] = $linenum;
		}
	    }
	}
    }
}
#--------------------------------------------------------------------------------------------------
# currently, validator fix mode is not enabled
sub run_validator($\%) {

    my $infile = shift;
    my $val_failed_list = shift;  # hash to populate

    my $cmd = "/ebi/production/seqdb/embl/tools/ena_validator-PROD.sh -l 2 ";

    if ($opt_val_args ne "") {
	$cmd .= $opt_val_args;
    }

    $cmd .= "$infile >& $infile.VAL_SUMMARY.del";
    $verbose && print "Running command: $cmd\n";
    my $exit_code = system($cmd);

    if ($exit_code) {
        # validator has failed
	$$val_failed_list{$infile} = 1;
    }
    else {
	foreach my $filename (@val_info_files) {
	    rename($filename, "$infile.$filename");
	}
    }
}
#--------------------------------------------------------------------------------------------------
#
sub run_putff($$\%) {

    my $infile = shift;
    my $db = shift;
    my $putff_failed = shift;  # hash to populate

    my $cmd = "/ebi/production/seqdb/embl/tools/bin/putff $db $infile";

    if ($opt_ds)               { $cmd .= " -ds $opt_ds"; }
    if ($opt_newLogFormat)     { $cmd .= " -new_log_format"; }
    if ($opt_ncbi)             { $cmd .= " -ncbi"; }
    if ($opt_noErrorFile)      { $cmd .= " -no_error_file"; }

    if ($opt_rollback)         { $cmd .= " -r"; }
    elsif ($opt_parseOnly)     { $cmd .= " -parse_only"; }

    if ($opt_dataclass ne "")  { $cmd .= " -dataclass $opt_dataclass"; }
    if ($opt_genome_sub_id)    { $cmd .= " -p $opt_genome_sub_id"; }

    if ($opt_putff_args ne "") { $cmd .= " $opt_putff_args"; }

    $cmd .= " >& $infile.putff_out";
    $verbose && print "Running command: $cmd\n\n";

    my $exit_code = system($cmd);


    if ($exit_code) {
        # validator has failed
	print "Putff has failed.  Perhaps the database is down?\n";
	$$putff_failed{$infile} = 1;
    }
}
#--------------------------------------------------------------------------------------------------
#
sub send_email($\%$$$) {

    my $program        = shift;
    my $failed_infiles = shift;
    my $email_list     = shift;
    my $addressee      = shift;
    my $cwd            = shift;

    if (keys %$failed_infiles) {
	open(MAIL, "|/usr/sbin/sendmail -oi -t");
	print MAIL "To: $email_list\n";
	print MAIL 'From: datalib@ebi.ac.uk'."\n"
	    . "Subject: $program failed in the entry loader\n"
	    . "Dear $addressee,\n\n$program failed in the entry loader "
	    . "on the following entries:\n$cwd/".join("\n$cwd/", keys(%$failed_infiles))."\n";
	close(MAIL);
    }
}
#--------------------------------------------------------------------------------------------------
#
sub email_developers_with_any_putff_and_val_failures(\%\%) {

    my ($val_failed, $putff_failed) = @_;

    my $cwd = `pwd`;
    chomp($cwd);

    if (keys %$val_failed) {
	send_email("Validator", %$val_failed, $val_error_email, $val_error_contact, $cwd);
    }

    if (keys %$putff_failed) {
	send_email("Putff", %$putff_failed, $putff_error_email, $putff_error_contact, $cwd);
    }
}
#--------------------------------------------------------------------------------------------------
#
sub notify_user_of_failures(\@\%\%) {

    my $infiles      = shift; 
    my $val_failed   = shift;
    my $putff_failed = shift;

    my $num_infiles      = scalar(@$infiles);
    my $num_val_failed   = scalar(keys %$val_failed);
    my $num_putff_failed = scalar(keys %$putff_failed);

    if (($num_val_failed == $num_infiles) && ($num_putff_failed == $num_infiles)) {
	# val failed on all entries
	die "ERROR: Both the validator and putff failed on all entries.  $putff_error_contact "
	    . "and my $val_error_contact have been notified.\n";
    }
    elsif ($num_val_failed == $num_infiles) {
        # validator failed on all entries
	print "WARNING: The validator has failed on all entries.  $val_error_contact has been notified.\n";
    }

}
#--------------------------------------------------------------------------------------------------
#
sub tidy_up_files(\@) {

    my $infiles = shift;

    # delete files containing putff and val stdout
    foreach my $infile (@$infiles) {
	unlink("$infile.$putff_output_suffix");
	unlink("$infile.VAL_SUMMARY.del");

	foreach my $val_output_file (@val_info_files) {
	    unlink("$infile.$val_output_file");
	}
    }
}
#--------------------------------------------------------------------------------------------------
#
sub getArgs(\@) {
    my (@infiles, $infile, @dbs, $db);

    my $args = shift;

    my $usage =
        "\n PURPOSE: To load entries into the specified database\n\n"
      . " USAGE:  $0 /(\@enapro|devt) <filename> [-ds <dsnum>] [-parse_only] [-r]\n"
      . " <filename>       a file containing 1+ EMBL entries\n"
      . " -ds <dsnum>                 The ds you are working in (required for tracking purposes)\n"
      . " -parse_only                 This will not load the entries but simply check them for errors\n"
      . " -r                          Rollback mode for checking if an entry will load without actually\n"
      . "                             loading it.  Does more checking than -parse_only\n"
      . " -no_error_file              Will not produce any error files for failed entries.\n"
      . " -new_log_format             Lists file and entry line numbers for each error.\n"
      . " -dataclass                  Should be used with the value or CON|TPA for different types of entry.\n"
      . " -ncbi                       Loads ncbi format files\n"
      . " -gen_sub <number>           Genome submission id (-p option in putff)\n"
      . " -audit \"<text>\"           Add an audit remark (50 characters max)\n"
      . " -vargs \"<args>\"           Extra validator arguments written as a string in between double quotes\n"
      . "                              if there are any spaces e.g. -vargs \"-r -filter\"\n"
      . " -pargs \"<args>\"           Extra putff arguments written as a string in between double quotes\n"
      . "                              if there are any spaces\n"
      . "                              e.g. -pargs \"-ignore_version_mismatch -tpa_max_gap_length=100\"\n"
      . " -keep_reports               Don't throw away putff and validator reports\n"
      . " -v(erbose)                  Extra information may be given\n"
      . " -help                       Displays this help message\n\n";

    GetOptions(
               "ds=i"           => \$opt_ds,
               "parse_only"     => \$opt_parseOnly,
               "r"              => \$opt_rollback,
               "no_error_file"  => \$opt_noErrorFile,
               "new_log_format" => \$opt_newLogFormat,
               "dataclass=s"    => \$opt_dataclass,
               "ncbi"           => \$opt_ncbi,
	       "gen_sub=i"      => \$opt_genome_sub_id,
               "audit"          => \$opt_audit,
	       "vargs=s"        => \$opt_val_args,
	       "pargs=s"        => \$opt_putff_args,
	       "keep_reports"   => \$opt_keep_reports,
               "verbose"        => \$verbose,
	       "help"           => \$help);

    if ($help) {
	die $usage;
    }

    foreach my $otherArg (@ARGV) {
        if (-e $otherArg) {
            push(@infiles, $otherArg);
        }
	elsif ($otherArg =~ /^\/\@(devt|enapro)/) {
            push(@dbs, $otherArg);
        }
	else {
	    die "Argument \"$otherArg\" not recognised.\n".$usage;
	}
    }

    if (@dbs > 1) {
	die "You can only input database for loading into.\n".$usage;
    }
    elsif (! @dbs) {
	die "No loading database was supplied.  Please enter /\@enapro or /\@devt in your arguments\n".$usage;
    }
    else {
	$db = $dbs[0];
    }

    if (! @infiles) {
	print "No input file was supplied. Finding files...\n";
	SeqDBUtils2::get_input_files(@infiles);

	if (! @infiles) {
	    die "ERROR: No files of fflupd, ffl, temp or sub filename suffix could be found.\n";
	}
    }

    return(\@infiles, $db);
}
#--------------------------------------------------------------------------------------------------
#
sub main(\@) {

    my $args = shift;

    my ($infiles, $db) = getArgs(@$args);

    my (%val_failed_list, %putff_failed_list);

    foreach my $infile (@$infiles) {

	run_validator($infile, %val_failed_list);

	run_putff($infile, $db, %putff_failed_list);
    }

    email_developers_with_any_putff_and_val_failures(%val_failed_list, %putff_failed_list);

    my (%entry_start_linenum);
    get_entry_start_line_numbers(@$infiles, %val_failed_list, %entry_start_linenum);

    notify_user_of_failures(@$infiles, %val_failed_list, %putff_failed_list);

    generate_combined_report( @$infiles, %val_failed_list, %putff_failed_list, %entry_start_linenum);

    if (! $opt_keep_reports) {
	tidy_up_files(@$infiles);
    }
}
#--------------------------------------------------------------------------------------------------
#
main(@ARGV);

