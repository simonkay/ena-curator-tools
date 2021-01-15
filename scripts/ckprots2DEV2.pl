#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/ckprots2DEV2.pl,v 1.1 2008/01/25 11:50:05 szilva Exp $
#
#  (C) EBI 2000
#
#  MODULE DESCRIPTION:
#
#  Parses the log file of the command 'putff -parse_only -new_log_format' (which makes a
#  syntax check on flat files) and reports:
#  1. messages about CDS translations
#  2. accession numbers of all entries that failed the parser
#
#  Output (to screen):
#  1. accession number or - if there is none - entry name
#  2. all cds locations with first and last aa and error or 'ok'.
#     NOTE: only the first try is shown for the cases where putff
#     tries to find a valid /codon_start because the information in the
#     file is incorrect.
#
#  MODIFICATION HISTORY:
#
#  30-JUN-2000  Carola Kanz        created.
#     APR-2001  Carola Kanz        added $test flag to avoid usage of this script
#                                  on logfiles not created with -parse_only option,
#                                  i.e. log files without the separator 
#                                  '### NEXT ENTRY ###' between entries which gives
#                                  an incomplete output otherwise
#  07-JUN-2001  Carola Kanz        fixed bug that ignored '*' as possible aa.
#                                  show first and last aa of *first* translation
#                                  if all /codon_start are tried for one location.
#  06-AUG-2001  F Nardone          Added '()' at the end of $pattern in add_message
#                                  so that $1 is always defined.
#  09-AUG-2001  Peter Stoehr       creates $USAGE to for usage notes
#  19-SEP-2001  Nicole Redaschi    rewrote much of main.
#  15-OCT-2001  Nicole Redaschi    fixed bug that last entry was not reported.
#                                  "fixed" compose_message to handle references properly.
#                                  added display of warnings.
#  02-NOV-2001  Nicole Redaschi    fixed parsing of status messages.
#  12-JAN-2004  Quan Lin           if cds is pseudo, print out in the report
#  18-JAN-2006  Nadeem Faruque     patched up to cope with changes in the putff output
#===============================================================================

use strict;

my $submitter_mode  = 0;
my $show_accessions = 1;

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

#sub write_problematic_feature($\%) {

#    my ($line, $DE_line, $location, $print_FT);

#    my $SAVEDATA = shift;
#    my $acc_info = shift;


#    foreach $acc (keys %$acc_info) {

#	open(READFFL, "<$acc.ffl") || die "Cannot open $acc.ffl\n";
#	$DE_line = "";

#	while ($line = <READFFL>) {
#	    if ($line =~ /^(DE  .+)/) {
#		$DE_line .= $1;
#	    }

#	    $print_FT = 0;

#	    foreach $location (@$acc) {

#		$location = quotemeta($location);

#		if ($line =~ /^FT   CDS\s+$location/) {
#		    print $SAVEDATA $line;
#		    $print_FT = 1;
#		}
#		elsif ($print_FT) {
#		    if ($line =~ /^FT   \S+/) {
#			$print_FT = 0;
#		    }
#		    else {
#			print $SAVEDATA $line;
#		    }
#		} 
#	    }
#	}
#	close(READFFL);
#    }
#}


#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

#sub write_protein_translation($\%) {

#    my $SAVEDATA = shift;
#    my $acc_info = shift;


#}

#-------------------------------------------------------------------------------
# Invoked in submitter_mode.  Output file is opened and appended with FT lines
# and protein translations for each problematic accession
#-------------------------------------------------------------------------------

#sub add_FT_lines_and_proteins($) {

#    my ($acc_info, $SAVEDATA);

#    my $submitter_file = shift;


#    open($SAVEDATA, ">$submitter_file") || die "Cannot write to $submitter_file: $!\n";

#    write_problematic_feature($SAVEDATA, %$acc_info);

#    write_protein_translation($SAVEDATA, %$acc_info);

#    close($SAVEDATA);
#}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub tidy_up_protein_seq(\$) {

    my $protein_seq = shift;

    $$protein_seq =~ s/ //g;
    $$protein_seq =~ s/(.{76})/   $1\n/g;
    $$protein_seq =~ s/(\S+)$/   $1/g;
    #$$protein_seq =~ s/\n\n+/\n/g;
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub make_summary_report(\%) {

    my ($summary_report_str, $summary_total_number_parsed, $summary_number_failed);
    my ($key);

    my $summary_report = shift;

    $summary_report_str = "\n\n------------------------------ summary report ------------------------------\n\n";
    
    $summary_total_number_parsed = 0;
    $summary_number_failed = 0;

    if ( %$summary_report ) {
	foreach $key ( keys(%$summary_report) ) {
	    $summary_total_number_parsed++;
	    
	    if ($key =~ /^failed/) {
		$summary_number_failed++;
	    }
	}

	$summary_report_str .= "$summary_number_failed/$summary_total_number_parsed failures\n";
	
	foreach $key ( sort keys(%$summary_report) ) {
	    if ($key =~ /^failed/) {
		$summary_report_str .= "$key\n";
	    }
	}
    }
    else {
	$summary_report_str .= "All entries are OK!\n\n";
    }

    return($summary_report_str);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub make_entry_count_summary($$$$) {

    my ($pad_length, $number_summary);

    my $total_number_of_entries = shift; 
    my $number_of_successful_entries = shift; 
    my $number_of_warnings = shift; 
    my $number_of_errors = shift;

    $pad_length = length($total_number_of_entries);

    $number_summary = "Total number of submitted entries: "
	            . sprintf("%".$pad_length."d", $total_number_of_entries)
 	            . "\nNumber of successful entries:      "
		    . sprintf("%".$pad_length."d", $number_of_successful_entries)
	            . "\nNumber of warnings:                "
		    . sprintf("%".$pad_length."d", $number_of_warnings)
	            . "\nNumber of errors found:            "
		    . sprintf("%".$pad_length."d", $number_of_errors)."\n";

    return($number_summary);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub add_message(\$$$;$) {
    # $1 used for /codon_start, has to be in last place

    my ( $message, $text, $pattern, $display ) = @_;

    if ( $text =~ /$pattern()/ ) {
	# the () at the end define $1 if there are no brackets in $pattern
	if ( $$message ) {
	    $$message .= "; ";
	}
	$$message .= ( defined $display ) ? $display.$1 : $pattern.$1;
    }
}

#-------------------------------------------------------------------------------
# checks concatenated warning and error lines for certain keywords:
# 3rd paramter to add_message is the regular expression to parse, 4th parameter
# the error message printed ( if not given, the third parameter is printed )
#-------------------------------------------------------------------------------

sub compose_message(\$$$) {

    my ( $message, $type, $text ) = @_;

    add_message ( $$message, $text, "contains stop codon", "contains stop" );
    add_message ( $$message, $text, "missing stop codon", "missing stop codon" );
    add_message ( $$message, $text, "invalid start codon", "invalid start codon" );
    add_message ( $$message, $text, "must be 5\' partial" );
    add_message ( $$message, $text, "must be 5\' or/and 3\' partial" );
    add_message ( $$message, $text, "requires \/codon\_start", "add /codon_start" );
    add_message ( $$message, $text, "resubmit entry with qualifier \/codon\_start\=(\\d)", 
		  "try /codon_start=" );
    add_message ( $$message, $text, "resubmit entry without qualifier \/codon\_start", 
		  "try without /codon_start" );

    if ( $text =~ /flat file and conceptual translations differ by X/ ) {
	add_message ( $$message, $text, "flat file and conceptual translations differ", 
		      "translations differ by X" );
    }
    else {
	add_message ( $$message, $text, "flat file and conceptual translations differ", 
		      "translations differ" );
    }

    add_message ( $$message, $text, "translational exception not within frame", 
		  "transl_except not in frame" );
    add_message ( $$message, $text, "\/exception.*no flat file translation", 
		  "/exception no translation" );
    add_message ( $$message, $text, "stop-codon-only CDS must be at 3\' end and partial", 
		  "must be 3' partial" );
    add_message ( $$message, $text, "more than one stop codon at 3\' end", 
		  "more than one stop codon at 3' end" );
    add_message ( $$message, $text, "incorrect or missing \/codon\_start qualifier", 
		  "add or correct /codon_start" );
    add_message ( $$message, $text, "stop codon at 3\' end - location must not be partial", 
		  "remove 3' end - location must not be partial" );
    add_message ( $$message, $text, "differs from standard table",
		  "/transl_table differs" );

    if ( ! $$message ) { 
	if ($type eq "W") {
	    $$message = "warning";
	}
	else {
	    $$message = "error"; 
	}
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub check_args(\@) {

    my ($arg, $input_file);

    my $args = shift;

    my $usage = "\n PURPOSE: Parses log file from \"putff -parse_only\" to report if .ffl\n".
	"          files will load and if CDS features code correctly\n\n".
	" USAGE:   $0\n".
	"          <putff_parse_only_log_file>\n\n".
	"          When executed in 'loadcheck.csh' or 'loadcheck1.csh'\n".
	"          <putff_parse_only_log_file> is called 'load.log'\n\n".
	"          Output:\n".
	"          Lists accession numbers\n".
	"          Lists entrynames if loadcheck fails on the ID line\n".
	"          Lists all CDS locations, first and last aa and error or 'ok'\n".
	"          NOTE: THE STOP CODON IS NOT REPORTED\n\n";

    foreach $arg (@$args) {
	
	if (($arg =~ /^-h(elp)?/) || ($arg =~ /^-u(sage)?/)) {
	    die $usage;
	}
	elsif ($arg =~ /^-s(ubmitter)?/) {
	    $submitter_mode = 1;
	}
	elsif ($arg =~ /^-noac(c)?/) {
	    $show_accessions = 0;
	}
	elsif ($arg =~ /^([^-]+.*)$/) {
	    $input_file =  $1;
	}
    }

    if (! defined($input_file)) {
	die "You must enter a log file to parse.\n$usage";
    }
    elsif (! -e $input_file) {
	die "The input file $input_file can't be found.\n$usage";
    }

    return($input_file);
}

#-------------------------------------------------------------------------------
# alter the log message (if it needs it)
#-------------------------------------------------------------------------------
		
sub update_log_message(\$) {

    my $log_msg = shift;

    if ($$log_msg =~ /^complement/) {
	$$log_msg =~ s/^complement/c/;
    }
    elsif ($$log_msg =~ /^join/) {
	$$log_msg =~ s/^join/j/;
    }

    $$log_msg = substr( $log_msg, 0, 18 );

    if ($$log_msg =~ /,$/) {
	$$log_msg =~ s/,$/ /;
    }

    if ($$log_msg =~ /^\s+/) {
	$$log_msg =~ s/^\s+//;
    }
}

#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------

sub look_for_warnings_in_entry($\$\$\%) {

    my ($line, $filePositionMarker);

    my $READ_LOAD_LOG = shift;
    my $error = shift;
    my $warning = shift;
    my $summary_report = shift;

    $filePositionMarker = tell($READ_LOAD_LOG);

    while ( <$READ_LOAD_LOG> ) {
	chomp ( $line = $_ );

	# CDS-location-line

	if ($line =~ /^(ERROR|INFO): CDS \S*/) {
	    last;
	}
	elsif ($line =~ /^ERROR: proteintranslation failed for entry/) {
	    # end of CDS TRANSLATIONS block:
	    # 1. failure: 'proteintranslation failed' message
	    last;
	}
	elsif ($line eq "") {
	    # 2. success: empty line or 'total elapsed time'
	    # pointless?
	    last;
	}
	elsif ($line =~ /^INFO: total elapsed time/) {
	    last;
	}
		
	# collect warnings and errors
	if ( $line =~ /^WARNING: (.*)/ ) {
	    $$warning .= " $1";
	}
	elsif ( $line =~ /^ERROR: (.*)/ ) {
	    $$error .= " $1";
	}
		# collect status messages
	if ( $line =~ /^INFO: \#\#\# (\S+) entry: *(\S+)/ ) {

	    $$summary_report{ $1.": ".$2 } = $2; # probably redundant

	    # we took a line that wasn't really ours so we should give it back
	    seek( $READ_LOAD_LOG, $filePositionMarker, 0);
	    last;
	}
	$filePositionMarker = tell($READ_LOAD_LOG);
    }
}

#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------

sub add_protein_seq(\$\$\$\$) {

    my $summ_cumulative_messages = shift;
    my $full_cumulative_messages = shift;
    my $protein_seq = shift;
    my $got_protein_seq = shift;
    
    if (($$full_cumulative_messages !~ /[A-Z\n\t ]+$/)) {

	tidy_up_protein_seq($$protein_seq);

	$$summ_cumulative_messages .= "\n".$$protein_seq;
	$$full_cumulative_messages .= "\n".$$protein_seq;
	
	$$protein_seq = ""; # reset variable
	$$got_protein_seq = 0;
    }
}

#-------------------------------------------------------------------------------
# read putff logfile
#-------------------------------------------------------------------------------

sub parse_load_log(\@$) {

    # if a translation contains internal stop codons, all /codon_start
    # are tried in putff to find a working one.
    # $first_aa_sv and $last_aa_sv are used to store the first and last
    # aa of the FIRST translation as this is the one in the flatfile.

    my (%summary_report, $submitter_file, $summ_cumulative_messages);
    my ($summary_report_str, $number_summary, %acc_info, $protein_seq);
    my ($first_cds, $CDSmessage, $parse_only, $pseudo, $got_protein_seq);
    my ($accno, $warning, $error, $acc_counter, $printed_acc_counter);
    my ($number_of_successful_entries, $number_of_warnings, $number_of_errors);
    my ($full_cumulative_messages, $READ_LOAD_LOG);

    $error      = '';
    $warning    = '';
    $accno      = '';
    $pseudo     = '';
    $parse_only = 0;
    $CDSmessage = "";
    $first_cds  = 1;
    $got_protein_seq = 0;

    $acc_counter = 0;
    $printed_acc_counter = 0;
    $number_of_successful_entries = 0;
    $number_of_warnings = 0;
    $number_of_errors = 0;

    my $args = shift;
    my $parse_file = shift;

    $submitter_file = "protein_check.log.submitter";

    if ($submitter_mode) {
	$summ_cumulative_messages = "\nErrors and warnings (those the submitter can't fix):";
    }


    # $submitter_file is written in submitter mode 
    open ($READ_LOAD_LOG, "<$parse_file" ) || die "Cannot read file $parse_file: $!\n";

    while ( <$READ_LOAD_LOG> ) {

	chomp ( my $line = $_ );
	if ( $line =~ /putff: Command not found\./ ) {
	    die "\nERROR: *** putff is not available\n\n";
	}
	elsif ( $line =~ /DS.* does not exist in the database/ ) {
	    die "\nERROR: $_\n";
	}

	# the "NEXT ENTRY" line signals that putff was used with the
	# -parse_only option and we should find CDS information
	if ( (! $parse_only) && ($line =~ /^INFO: \#+ NEXT ENTRY \#+/) ) {
	    $parse_only = 1;
	}

	# the "NEXT ENTRY" line or "total cpu" line signals that we are
	# at the beginning (or end) of an entry (don't use "total elapsed",
	# we may have already skipped it - see below!)
	if ( $parse_only &&
	     ( ($line =~ /^INFO: \#+ NEXT ENTRY \#+/) || ($line =~ /^INFO: total cpu/) ) 
	   ) {

	    if ($line =~ /^INFO: \#+ NEXT ENTRY \#+/) {
		$acc_counter++;
	    }


	    # check whether previous entry had no CDSs.
	    if (($CDSmessage eq "") && ($accno ne '')) {

		my $noCDSstr = sprintf "\n%-10s  no CDSs", $accno;
		$summ_cumulative_messages .= $noCDSstr;
		$full_cumulative_messages .= $noCDSstr;
	    }
	    else {
		$CDSmessage =~ s/ACCESSIO/$accno/gs;
		
		if ($CDSmessage !~ /$accno$/) {
		    $summ_cumulative_messages .= $CDSmessage;
		    $full_cumulative_messages .= $CDSmessage;
		}
	    }

	   
	    $first_cds = 1;
	    $accno = "ACCESSIO"; # placeholder value to be replaced once the entry is fully parsed
	    $CDSmessage = "";

	    if ($line =~ /^INFO: total cpu/) {
		# end of entries
		last;
	    }
	}
	# collect status messages
	elsif ( $line =~ /\#\#\# (\S+) entry: *(\S+)/ ) {

		$accno = sprintf "%-8s", $2; # for short accession numbers, pad with spaces
		$summary_report{ $1.": ".$2 } = $2;
	}
	
	# unless we have hit the "NEXT ENTRY" line, we do not
	# need to try to get information about CDSs
	if ( ! $parse_only ) {
	    next;
	}

	if (!defined $protein_seq) {
	    $protein_seq = "";
	}

	if (($protein_seq ne "") && (!$got_protein_seq) && ($line =~ /^(INFO|ERROR|WARNING):/)) {
	    # reached end of entry so stop collecting protein seq
	    $got_protein_seq = 1;
	}

	# start/end of a CDS
	if ( $line =~ /^INFO: \-{30}/ ) {

	    # if this isn't the first CDS, we need to print the information
	    # for the previous CDS.
	    if ( $first_cds != 1 ) {

		check_for_errors_or_warnings($error, $warning, );

		if ( $error ne '' || $warning ne '' ) {

		    my $message = '';

		    if ($error  ne '') {
			compose_message( $message, "E", $error );
			$number_of_errors++;
		    }
		    if ($warning ne '') {
			compose_message( $message, "W", $warning );
			$number_of_warnings++;
		    }
		    if ($pseudo eq '') {
			$CDSmessage .= $message;
		    }
		    else {
			$CDSmessage .= "$message coding pseudo";
		    }
		}
		else {
                    # in curator mode, show all the messages (good and bad)
		    if ($pseudo eq '') {
			$CDSmessage .= "ok";
			$number_of_successful_entries++;
		    }
		    else {
			$CDSmessage .= $pseudo;
			$number_of_warnings++;
		    }
		}
		
		# reset variables
		$error       = '';
		$warning     = '';
		$pseudo      = '';
	    }
	    
	    # try to find the CDS-location-line and concatenate warnings and errors 
	    # that appear before the CDS-location-line to grep for keywords later


	    look_for_warnings_in_entry($READ_LOAD_LOG, $error, $warning, %summary_report);


	    if ( ($line =~ /^INFO: CDS (\S*)/) || ($line =~ /^ERROR: CDS (\S*)/)) {

		my $log_msg = $1;
		update_log_message($log_msg);

                # create data structure of accessions with their problem locations
		push(@{ $acc_info{$accno} }, $log_msg);


		add_protein_seq($summ_cumulative_messages, $full_cumulative_messages, $protein_seq, $got_protein_seq);

                # format line such as "1.   <1..>790            ok" or
		$printed_acc_counter++;
		#my $acc_counter_str = $printed_acc_counter.".";

		my $print_this = "";
		if ($first_cds) {
		    $print_this = $accno;
		    $first_cds = 0;
		}

		if ($print_this eq "") {
		    $CDSmessage .= sprintf("\n%-18s  ", $log_msg);
		}
		else {
		    $CDSmessage .= sprintf("\n%8s %-18s  ", $print_this, $log_msg);
		}
	    }
	    
	    if ( $line =~ /^INFO: CDS \S*\s+\/(pseudo)/){
		$pseudo = $1;
	    }
	}
        # get warnings
	elsif ( $line =~ /^WARNING: (.*)/ ) {
	    $warning .= " $1";
	}
        # get errors
	elsif ( $line =~ /^ERROR: (.*)/ ) {
	    $error .= " $1";
	}
	# get protein sequence
        elsif ((!$got_protein_seq) && ($line =~ /^      ([\*A-Z]   )(([\*A-Z]   )*)/))  {
	    $protein_seq .= $1.$2;
	}
    }
    close($READ_LOAD_LOG)  || die "cannot close file $parse_file: $!\n";

    if (! $parse_only) {
	$summ_cumulative_messages .= "\nWARNING: ckprots probably run on a log file not created with -parse_only option";
    }
 
    $number_summary = make_entry_count_summary($acc_counter, $number_of_successful_entries, $number_of_warnings, $number_of_errors);


    $summary_report_str = "";
    if (!$submitter_mode) {
	$summary_report_str = make_summary_report(%summary_report);
    }

    return($number_summary, $summ_cumulative_messages, $full_cumulative_messages, $summary_report_str);
}

#-------------------------------------------------------------------------------------
# main flow of program
#-------------------------------------------------------------------------------------

sub main(\@) {

    my ($number_summary, $summ_cumulative_messages, $full_cumulative_messages);
    my ($summary_report_str, $parse_file);

    my $args = shift;

    $parse_file =  check_args(@$args);

    ($number_summary, $summ_cumulative_messages, $full_cumulative_messages, $summary_report_str) = parse_load_log(@$args, $parse_file);

    print $number_summary;
    print "$summ_cumulative_messages\n";
    print "\n\n-------------------------- full details -------------------------------";

    #print "$full_cumulative_messages\n";

    if (!$submitter_mode) {
	print "$summary_report_str\n";
    }

}

#-------------------------------------------------------------------------------------
# run program
#-------------------------------------------------------------------------------------

main(@ARGV);
