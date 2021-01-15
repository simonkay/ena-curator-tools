#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/parse_loadlog_noaccinput.pl,v 1.1 2008/02/15 14:22:05 szilva Exp $
#
#  (C) EBI 2008
#
###############################################################################

use strict;
use Data::Dumper;

my $submitter_mode = 0;

#-------------------------------------------------------------------------------------
# structure of @entry_info:
# $entry_info[0]{acc}           = "AM12345";
# $entry_info[0]{status}        = "parsed"
# $entry_info[0]{error_count}   = 2
# $entry_info[0]{entry_error}[0] = "unclassified organism"
#                            [1] = "unclassified species"
# $entry_info[0]{cds}[0]{location}                  = "<1..>790"
#                       {transl_set}[0]{transl}     = "atc gaa ttt\n I   E   F"
#                                      {error}[0]   = "CDS <1..>591  /codon_start=3"
#                                             [1]   = "/codon_start=3 -> conceptual transl..."
#                                      {info}[0]    = "using /transl_table=5"
#                                            [1]    = "CDS <1..>737"
#
#
#               {cds}[1]{location}                  = "790..999"
#                       {transl_set}[0]{transl}     = "atc gaa ttt ggg\n I   E   F   P"
#                                      {error}[0]   = " CDS translation should not be pseudo"
#                                             [1]   = "/codon_start=3 -> conceptual transl..."
#                                      {info}[0]    = "using /transl_table=5"
#
# - Each item in the entry_info list describes the collection of info relating to a 
# single accession.
#
# - CDSs are CDS features which encapsulate a errors warnings relating to a particular
# location.  These are separated by lines like this: 'INFO: -------------------------'
#
# - The transl_sets are multiple translations on a particular CDS, created for example
#  while testing out different transl_tables. These are NOT separated by 
# 'INFO: ---------------' lines.
#  
# etc etc
#
#-------------------------------------------------------------------------------------

sub generate_numeric_summary(\%) {

    my ($entry_num, $parsed_ctr, $failed_ctr, $entry_ctr, @failed_list);

    my $parsed_failed_list = shift;

    $parsed_ctr = 0;
    $failed_ctr = 0;
    $entry_ctr = 0;

    foreach $entry_num (keys(%$parsed_failed_list)) {

	if ($$parsed_failed_list{$entry_num} eq "parsed") {
	    $parsed_ctr++;
	}
	elsif ($$parsed_failed_list{$entry_num} eq "failed") {
	    $failed_ctr++;
	    push(@failed_list, $entry_num);
	}

	$entry_ctr++;
    }

    print "Total number of submitted entries: $entry_ctr\n"
	. "Number of successful entries:      $parsed_ctr\n" 
	. "Number of errors found:            $failed_ctr\n";

    return($failed_ctr, $entry_ctr, \@failed_list);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub display_parsed_failed_summary($$\@) {

    my ($entry_num);

    my $failed_ctr = shift;
    my $entry_ctr = shift;
    my $failed_list = shift;

    @$failed_list = sort({$a <=> $b} @$failed_list);

    print "\n" . $failed_ctr . "/" . $entry_ctr . " entries failed\n";
    foreach $entry_num (@$failed_list) {
	print "failed entry num: $entry_num\n";
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub print_reports(\$\$\%) {

    my ($failed_ctr, $entry_ctr, $failed_list);

    my $summary_report = shift;
    my $full_details_report = shift;
    my $parsed_failed_list = shift;

    ($failed_ctr, $entry_ctr, $failed_list) = generate_numeric_summary(%$parsed_failed_list);

    if ($submitter_mode) {
	print "\n------------------------ Summary of Errors/Warnings-----------------------\n\n";
    }
    else {
	print "\n--------------------------------- Summary ---------------------------------\n\n";
    }

    print $$summary_report;
    print "\n--------------------- Full Details of Errors/Warnings ---------------------\n\n";

    if ($$full_details_report !~ /^\s*$/) {
	print $$full_details_report;
    }
    else {
	print "There are no errors to show in detail.\n";
    }

    if (!$submitter_mode) {
	print "\n------------------------------ Parsed/Failed ------------------------------\n";
	display_parsed_failed_summary($failed_ctr, $entry_ctr, @$failed_list);
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub check_and_reword_errors($\%) {

    my ($new_message);

    my $message = shift;
    my $new_message_list = shift;

    $message =~ s/^(WARNING|ERROR): //;
    $message =~ s/^\s+//;
    $message =~ s/\s+$//;

    $new_message = "";

    if (($message =~ /^CDS \S*\s+\/pseudo/) && ($message !~ /should not be pseudo/)) { 
	$new_message .= "coding pseudo";
    }
#    elsif ($message =~ /conceptual translation contains stop codon/){ 
#	$new_message = "";
#    }
    elsif ($message =~ /potential translation found/){ 
	$new_message = "";
    }
    elsif ($message =~ /((contains|missing) stop) codon/) {
	$new_message = $1.' (*)';
    }
    elsif ($message =~ /(invalid start) codon/) {
	$new_message = $1;
    }
    elsif ($message =~ /requires (\/codon_start)/) {
	$new_message = "add $1";
    }
    elsif ($message =~ /resubmit entry with(out)? qualifier (\/codon\_start\=\d)/) {
	$new_message = "try $2";
    }
    elsif ($message =~ /flat file and conceptual (translations differ( by X)?)/) {
	$new_message = $1;
    }
    elsif ($message =~ /translational exception not within frame/) {
	$new_message = "transl_except not in frame";
    }
    elsif ($message =~ /\/exception.*no flat file translation/) {
	$new_message = "/exception no translation";
    }
    elsif ($message =~ /stop-codon-only CDS must be at 3\' end and partial/) {
	$new_message = "must be 3' partial";
    }
    elsif ($message =~ /more than one stop codon at 3\' end/) {
	$new_message = "contains stop (*)";
    }
    elsif ($message =~ /incorrect or missing \/codon\_start qualifier/) {
	$new_message = "add or correct /codon_start";
    }
    elsif ($message =~ /stop codon at 3\' end - location must not be partial/) {
	$new_message = "remove 3' partial";
    }
    elsif ($message =~ /differs from standard table/) {
	$new_message = "/transl_table differs";
    }
    elsif ($message =~ /CDS .*\d+\.\.>?\d+/) {
	$new_message = "";
    }
    elsif ($message =~ /proteintranslation failed /) {
	$new_message = "";
    }
    else {
	$new_message = $message;
    }

    # add message to unique list of messages
    if ($new_message ne "") {
	$$new_message_list{$new_message} = 1;
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub remove_warnings_hidden_from_submitter(\%) {

    my ($transl_set, $warning, $cds);

    my $entry_info = shift;

    foreach $warning (@{ $$entry_info{entry_errors} }) {

	if ($warning =~ /^WARNING/) {

	    if (
		($warning =~ /organism unclassified/) ||
		($warning =~ /flat file and conceptual translations differ only in ambiguous codons/) ||
		($warning =~ /\S+\/number/i) ||
		($warning =~ /unclassified species name/)
		) {

		$warning = "";
		$$entry_info{error_count}--;
	    }
	}
    }

    foreach $cds (@{ $$entry_info{cds} }) {
	foreach $transl_set (@{ $cds->{transl_set} }) {
	    foreach $warning (@{ $transl_set->{error} }) {

		if ($warning =~ /^WARNING/) {

		    if (
			($warning =~ /CDS translation should not be pseudo/) ||
			($warning =~ /flat file and conceptual translations differ only in ambiguous codons/) ||
			($warning =~ /given \/transl_table/) ||
			($warning =~ /\S+\/number/i) ||
			($warning =~ /unclassified species name/) ||
			($warning =~ /flat file\s+translation: [A-Z]+/) ||
			($warning =~ /conceptual translation: [A-Z]+/)
			) {

			$warning = "";
			$$entry_info{error_count}--;
		    }
		}
	    }
	}
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_DE_and_FT_lines($) {

    my ($line, $DE_lines, %FT_lines, $get_rest_of_feature, $location, $i);
    my ($check_file_prefix, $check_file, $temp_file, $sub_file, @input_files);

    my $entry_num = shift;

    $DE_lines = "";
    $get_rest_of_feature = 0;

    if (! (-e "putffer.input_files")) {
	# look for .temp or .sub file like 1.temp or 01.temp or 001.temp etc
	for ($i=0; $i<6; $i++) {

	    $check_file_prefix = ("0" x $i).$entry_num;

	    $temp_file = $check_file_prefix.".temp";
	    $sub_file = $check_file_prefix.".sub";
	    
	    if (-e $temp_file) {
		$check_file = $temp_file;
		last;
	    }
	    elsif (-e $sub_file) {
		$check_file = $sub_file;
		last;
	    }
	}
    }
    else {
	open(INPUT_FILE_LIST, "<putffer.input_files");
	@input_files = <INPUT_FILE_LIST>;
	close(INPUT_FILE_LIST);

	$check_file = $input_files[($entry_num - 1)];
    }

    # if file containing DE lines is found, grab it's DE and FT lines
    # (for the location of the CDS)
    if (defined($check_file)) {

	open(READENTRY, "<$check_file") || die "Cannot open file $check_file to read it's DE lines.\n";

	while ($line = <READENTRY>) {

	    if ($line =~ /^(DE  .+)/) {
		$DE_lines .= $1."\n";
	    }

	    if ($get_rest_of_feature) {
		if (($line =~ /^FT   \S+/) || ($line !~ /^FT/)) {
		    $get_rest_of_feature = 0;
		    $location = "";
		}
		else {
		    $FT_lines{$location} .= $line;
		}
	    } 
	    elsif ($line =~ /^FT   CDS\s+([^\n]+)\n/) {
		$location = $1;
		$location =~ s/\s+//g;
		$FT_lines{$location} = $line;
		$get_rest_of_feature = 1;
	    }
	}

	close(READENTRY);
    }
    else {
	print "Cannot find file containing DE lines\n";
    }

    $DE_lines =~ s/\n$//;

    return($DE_lines, \%FT_lines);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub add_DE_and_FT_lines($\%$\$$) {

    my $DE_lines = shift;
    my $FT_line_hash = shift;
    my $location = shift;
    my $full_details_report = shift;
    my $acc_printed_full = shift;

    if (!$acc_printed_full) {
	$$full_details_report .= "$DE_lines\n";
    }

    if (defined($$FT_line_hash{$location})) {
	$$full_details_report .= $$FT_line_hash{$location};
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub add_protein_translation($\$\$;$) {

    my ($transl_set, $transl, $error, $info, $transl_set1, $error_in_cds);

    my $cds = shift;
    my $summary_report = shift;
    my $full_details_report = shift;
    my $pseudo = shift; # this signals for nothing to be written to full details report

    $error_in_cds = 0;

    # if this cds contains errors (not including pseudo seqs)...
    foreach $transl_set1 (@{ $cds->{transl_set} }) {
	foreach $error (@{ $transl_set1->{error} }) {
	    if ($error !~ /pseudo/) {
		$error_in_cds = 1;
		last;
	    }
	}
    }

    # only show translation if error is found in the cds (other than pseudo)
    if ($error_in_cds) {

	$transl = $cds->{transl_set}[0]{transl};
	$transl =~ s/[a-z \n]+//g;
	
	if (!$submitter_mode) {
	    $$summary_report .= "$transl\n";
	}
	
	if (! defined($pseudo)) {
	    $$full_details_report .= "- Protein translation";
	    
	    if ($transl =~ /\*/) {
		$$full_details_report .= " (* = stop codon)";
	    }
	
	    $$full_details_report .= ":\n$transl\n" . "- Codon details:\n";
      
	    foreach $transl_set (@{ $cds->{transl_set} }) {
		
		foreach $error (@{ $transl_set->{error} }) {
		    if ($error ne "") {
			$$full_details_report .= "$error\n";
		    }
		}
		
		foreach $info (@{ $transl_set->{info} }) {
		    if (($info !~ /total (elapsed|cpu)/) && ($info !~ /stored\s+entries/) && ($info ne "")) {
			$$full_details_report .= "$info\n";
		    }
		}
		
		if (defined($transl_set->{transl})) {
		    $$full_details_report .= $transl_set->{transl};    
		}
	    }
	    
	    $$full_details_report .= "\n\n";
	}
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_entry_errors(\@) {

    my (%errors, $error, $error_str);

    my $error_list = shift;

    foreach $error (@$error_list) {
	check_and_reword_errors($error, %errors);
    }

    if (keys(%errors)) {
	$error_str .= join("; ", sort(keys(%errors)) );

	$error_str =~ s/^; //;
	$error_str =~ s/; $//;
	$error_str =~ s/; (; )+/; /;
    }

    return($error_str);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_errors_and_locations($) {

    my ($error_str, $error, %transl_set_messages, $location, $transl_set);

    my $cds = shift;

    $error_str = "";

    foreach $transl_set (@{ $cds->{transl_set} }) {
	foreach $error (@{ $transl_set->{error} }) {
	    check_and_reword_errors($error, %transl_set_messages);
	}
    }

    if (keys(%transl_set_messages)) {
	$error_str .= join("; ", sort(keys(%transl_set_messages)) );

	$error_str =~ s/^; //;
	$error_str =~ s/; $//;
	$error_str =~ s/; (; )+/; /;
    }
    else {
	$error_str = "ok";
    }
    
    $location = "";
    if ($cds->{location}) {
	$location = $cds->{location};
    }

    return($error_str, $location);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub build_line($$$$$$;$) {

    my ($summary_line, $full_details_line, $tmp, $pad_length);

    my $DE_lines = shift;
    my $entry_ctr = shift;
    my $location = shift;
    my $acc_printed_summ = shift;
    my $acc_printed_full = shift;
    my $error_str = shift;
    my $not_entry_level = shift; # only defined if blank location is preferred

    $summary_line = "";
    $full_details_line = "";

    if ((!$acc_printed_summ) && ($entry_ctr > 1)) {
	$summary_line = "\n";
	$full_details_line = "\n";
    }

    $pad_length = 18;

    if ($location ne "") {
	$location =~ s/complement/c/gi;
	$location =~ s/join/j/gi;
	$location = "Position ". substr($location, 0, $pad_length);
    }
    else {
	if (!defined($not_entry_level)) {
	    $location = "Position entry-level";
	}
    }

    if ($location =~ /^Position/) {
	$pad_length = 27; 
    }

    if (!$acc_printed_summ) {
	$summary_line .= $entry_ctr.". Identifying DE line:\n$DE_lines\n".sprintf("%-${pad_length}s  %s\n", $location, $error_str);
    }
    else {
	$summary_line .= sprintf("%-${pad_length}s  %s\n",$location, $error_str);
    }

    if (!$acc_printed_full) {
	$full_details_line .= $entry_ctr.". Identifying DE line:\n$DE_lines\n";

	if ($location ne "entry-level") {
	    $full_details_line .= "====== CDS ERROR START ====================================\n";

	    if ($location !~ /^Position/) {
		$full_details_line .= "Position ";
	    }
	}

	$full_details_line .= sprintf("%-${pad_length}s  %s\n", $location, $error_str);
    }
    else {
	if ($location ne "entry-level") {
	    $full_details_line .= "====== CDS ERROR START ====================================\n";
	    
	    if ($location !~ /^Position/) {
		$full_details_line .= "Position ";
	    }
	}

	$full_details_line .= sprintf("%-${pad_length}s  %s\n", $location, $error_str);
    }


    return($summary_line, $full_details_line);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub build_reports(\%\$\$$) {

    my ($error_str, $location, $acc_printed_summ, $DE_lines, $FT_line_hash);
    my ($cds, $acc_printed_full, $summ_line, $fd_line, $entry_level_errors_found);
    my ($cds_level_errors_found);

    my $entry_info = shift;
    my $summary_report = shift;
    my $full_details_report= shift;
    my $entry_display_num = shift;


    if ($submitter_mode && $$entry_info{error_count}) {
	remove_warnings_hidden_from_submitter(%$entry_info);
    }


    #print Dumper(\%$entry_info);

    ($DE_lines, $FT_line_hash) = get_DE_and_FT_lines($$entry_info{entry_num});

    $acc_printed_summ = 0;
    $acc_printed_full = 0;
    $entry_level_errors_found = 0;

    ## add entry-level errors to reports
    if ($$entry_info{entry_errors}) {
	$error_str = get_entry_errors(@{ $$entry_info{entry_errors} });

	if ($submitter_mode) {
	    if (defined($error_str) && ($error_str ne "") && ($error_str !~ /ok/)) {
		($summ_line, $fd_line) = build_line($DE_lines, $entry_display_num, "", $acc_printed_summ, $acc_printed_full, $error_str);

		$$summary_report .= $summ_line;
		$acc_printed_summ++;

		$$full_details_report .= $fd_line;
		$acc_printed_full++;
	    }
	}
	# curator mode
	else {
	    ($summ_line, $fd_line) = build_line($DE_lines, $entry_display_num, "", $acc_printed_summ, $acc_printed_full, $error_str);
	    $$summary_report .= $summ_line;
	    $acc_printed_summ++;

	    if ($error_str !~ /ok/) {
		$$full_details_report .= $fd_line;
		$acc_printed_full++;
	    }
	}
	$entry_level_errors_found++;
    }

    $cds_level_errors_found = 0;

    ## add CDS level errors to reports
    foreach $cds (@{ $$entry_info{cds} }) {

	($error_str, $location) = get_errors_and_locations($cds);

	$summ_line = "";
	$fd_line = "";

	if ($submitter_mode) {
	    if ($error_str !~ /ok/) { 

		($summ_line, $fd_line) = build_line($DE_lines, $entry_display_num, $location, $acc_printed_summ, $acc_printed_full, $error_str);
		$$summary_report .= $summ_line;
		$acc_printed_summ++;

		$$full_details_report.= $fd_line;
		$acc_printed_full++;
	    }
	}
	# curator mode
	else {
	    ($summ_line, $fd_line) = build_line($DE_lines, $entry_display_num, $location, $acc_printed_summ, $acc_printed_full, $error_str);
	    $$summary_report .= $summ_line;
	    $acc_printed_summ++;

	    if ($error_str !~ /ok/) {
		$$full_details_report.= $fd_line;
		$acc_printed_full++;
	    }
	}

	if ($error_str !~ /ok/) {
	    if ($$entry_info{error_count}) {

		if ($error_str !~ /coding pseudo/) {
		    add_DE_and_FT_lines($DE_lines, %$FT_line_hash, $location, $$full_details_report, $acc_printed_full);
		}
	    
		if (defined($cds->{transl_set}[0]{transl})) {
		    if ($error_str !~ /coding pseudo/) {
			add_protein_translation($cds, $$summary_report, $$full_details_report);
		    }
		    else {
			add_protein_translation($cds, $$summary_report, $$full_details_report, 'pseudo');
		    }
		}

		$$full_details_report.= "====== CDS ERROR END ======================================\n";
	    }
	}

	$cds_level_errors_found++;
    }

    # catch accs with no warnings/errors/info for curator summary report
    if (!$submitter_mode) {
	if ((!$entry_level_errors_found) && (!$cds_level_errors_found)) {

	    ($summ_line, $fd_line) = build_line($DE_lines, $entry_display_num, "", $acc_printed_summ, $acc_printed_full, "ok", 1);
	    $$summary_report .= $summ_line;
	    $acc_printed_summ++;
	}
    }

    if ($$full_details_report !~ /\n\n$/) {
	$$full_details_report .= "\n";
    }

    return($acc_printed_summ);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub parse_entry(\@\$\$\%$$) {

    my ($line, %entry_info, $line_num, $collect_translation, $tmp);
    my ($transl_num, $cds_num, $get_cds, $pseudo, $entry_printed);

    my $subm_info = shift;
    my $summary_report = shift;
    my $full_details_report= shift;
    my $parsed_failed_list = shift;
    my $entry_display_num = shift;
    my $entry_num = shift;

    $collect_translation = "";
    $line_num = 1;
    $cds_num = -1;

    # check if there are any entry-level errors before CDS's start
    foreach $line (@$subm_info) {

	if ($line !~ /^INFO: \-{70}/) {
	    $tmp = $line;
	    $tmp =~ s/, (input|entry) line: \d+\n?//g;

	    if ($tmp =~ /(parsed|failed) entry: /) {
		$entry_info{entry_num} = $entry_num;
		$entry_info{status} = $1;

		$$parsed_failed_list{$entry_display_num} = $1;
	    }
	    else {
		push(@{ $entry_info{entry_errors} }, $tmp);
		$entry_info{error_count}++;
	    }

	}
	else {
	    last;
	}
    }

    $get_cds = 0;
    $pseudo = 0;
    $transl_num = 0;

    for ($line_num=0; $line_num<@$subm_info; $line_num++) {

	# skip lines before cds starts
	if ($cds_num == -1) {
	    if ($$subm_info[$line_num] !~ /^INFO: \-{70}/) {
		next;
	    }
	    else {
		$get_cds = 1;
		$cds_num++;
		next;
	    }
	}

        # break out of loop if acc already defined (appears at bottom of
        # entry so will be the last thing saved) - used for when no 
	# INFO/WARNING/ERROR lines are present
	if (defined($entry_info{acc})) {
	    last;
	}

	if ($get_cds) {
	    if (($collect_translation ne "") && ($$subm_info[$line_num] =~ /^(INFO|WARNING|ERROR): /)) {
		$collect_translation =~ s/^INFO: //;

		# 'if' added because pseudo CDSs have no translations
		if (!$pseudo) {
		    $entry_info{cds}[$cds_num]{transl_set}[$transl_num]{transl} = $collect_translation;
		}

		$pseudo = 0;
		$collect_translation = "";
		$transl_num++;
	    }
	    
	    # increment cds counter if new cds starts
	    if ($$subm_info[$line_num] =~ /^INFO: \-{70}/) {
		$transl_num = 0;
		$cds_num++;
		next;
	    }
	    # collect location of CDS (first instance)
	    elsif (($$subm_info[$line_num] =~ /(INFO|ERROR|WARNING): CDS (\S+)/) && (!defined($entry_info{cds}[$cds_num]{location}))) {
		$entry_info{cds}[$cds_num]{location} = $2;
		$entry_info{cds}[$cds_num]{location} =~ s/,$//;

		if ($$subm_info[$line_num] =~ /pseudo/) {
		    push(@{ $entry_info{cds}[$cds_num]{transl_set}[$transl_num]{error} }, "WARNING: coding pseudo");
		    $pseudo = 1;
		    $entry_info{error_count}++;
		}
	    }
	    # store accession and parsed/failed status
	    elsif ($$subm_info[$line_num] =~ /^INFO: \#{3} (parsed|failed) entry: /) {
		$entry_info{entry_num} = $entry_num;
		$entry_info{status} = $1;
		$$parsed_failed_list{$entry_num} = $1;
	    }
	    # collect protein translation
	    elsif (($$subm_info[$line_num] =~ /^(INFO: |      )([atgc]{3} )+/) || ($$subm_info[$line_num] =~ /^      ([A-Z\*]   ?)+/)) {
		$$subm_info[$line_num] =~ s/^\s+//;
		$collect_translation .= $$subm_info[$line_num];
	    }
	    # store INFO lines which aren't protein translations
	    elsif ($$subm_info[$line_num] =~ /^(INFO: .+)/) {
		$tmp = $1;
		$tmp =~ s/, input line: \d+//;

		push(@{ $entry_info{cds}[$cds_num]{transl_set}[$transl_num]{info} }, $tmp);
	    }
	    # store WARNINGs and  ERRORs
	    elsif ($$subm_info[$line_num] =~ /^((ERROR|WARNING): .+)/) {
		
		if ($$subm_info[$line_num] =~ /^(ERROR: DS number does not exist in the database)/) {
		    push(@{ $entry_info{entry_errors} }, $1);
		    $entry_info{error_count}++;
		}
		elsif ($$subm_info[$line_num] !~ /proteintranslation failed/) {
		    $tmp = $1;
		    $tmp =~ s/, input line: \d+//;
		    push(@{ $entry_info{cds}[$cds_num]{transl_set}[$transl_num]{error} }, $tmp);
		    $entry_info{error_count}++;
		}
	    }
	}
    }

    $entry_printed = build_reports(%entry_info, $$summary_report, $$full_details_report, $entry_display_num);

    return($entry_printed);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub parse_loadlog($) {

    my ($line, @subm_info, $summary_report, $full_details_report, %parsed_failed_list);
    my ($entry_printed, $entry_display_num, $entry_num);

    my $loadlog_file = shift;

    open(READ_LOADLOG, "<$loadlog_file") || die "Cannot open $loadlog_file: $!\n";

    $full_details_report = "";
    $entry_display_num = 1;
    $entry_num = 1;

    while ($line = <READ_LOADLOG>) {

	if ($line =~ /^INFO: \#{3} (parsed|failed) entry: ([A-Z]{2}\d+)/) {
	    die "Accession number $2 detected: Please use parse_loadlog.pl rather than this script.\n";
	}
	elsif ($line =~ /^\#{3} (parsed|failed) entry: ([A-Z]{2}\d+)/) {
	    die "The input file $loadlog_file was not generated using the putff -new_log_format option. Please try again.\n";
	}
	elsif ($line =~ /^INFO: \#{3} (parsed|failed) entry: /) {
	    push(@subm_info, $line);

            # entry_printed flag is returned because in submitter mode, it doesn't follow
            # the number of the accession owing to not displaying ok entries 
	    $entry_printed = parse_entry(@subm_info, $summary_report, $full_details_report, %parsed_failed_list, $entry_display_num, $entry_num);
	    @subm_info = ();

	    if ($entry_printed) {
		$entry_display_num++;
	    }
	    $entry_num++;
	}
	elsif (($line =~ /INFO: =====+ CDS TRANSLATIONS ==+/) || ($line =~ /INFO: #######+ NEXT ENTRY ##+/)) {
	    next;
	}
	else {
	    push(@subm_info, $line);
	}
    }

    close(READ_LOADLOG);

    return(\$summary_report, \$full_details_report, \%parsed_failed_list)
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

#-------------------------------------------------------------------------------------
# main flow of program
#-------------------------------------------------------------------------------------

sub main(\@) {

    my ($parse_file, $entry_info, $summary_report, $full_details_report, $parsed_failed_list);

    my $args = shift;

    $parse_file =  check_args(@$args);

    ($summary_report, $full_details_report, $parsed_failed_list) = parse_loadlog($parse_file);

    print_reports($$summary_report, $$full_details_report, %$parsed_failed_list);
}

#-------------------------------------------------------------------------------------
# run program
#-------------------------------------------------------------------------------------

main(@ARGV);
