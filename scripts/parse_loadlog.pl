#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/parse_loadlog.pl,v 1.2 2008/02/18 15:37:47 szilva Exp $
#
#  (C) EBI 2008
#
###############################################################################

use strict;
use Data::Dumper;

my $submitter_mode = 0;
my $show_accessions = 1;

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

    my ($acc, $parsed_ctr, $failed_ctr, $acc_ctr, @failed_list);

    my $parsed_failed_list = shift;

    $parsed_ctr = 0;
    $failed_ctr = 0;
    $acc_ctr = 0;

    foreach $acc (keys(%$parsed_failed_list)) {

	if ($$parsed_failed_list{$acc} eq "parsed") {
	    $parsed_ctr++;
	}
	elsif ($$parsed_failed_list{$acc} eq "failed") {
	    $failed_ctr++;
	    push(@failed_list, "failed: $acc\n");
	}

	$acc_ctr++;
    }

    print "Total number of submitted entries: $acc_ctr\n"
	. "Number of successful entries:      $parsed_ctr\n" 
	. "Number of errors found:            $failed_ctr\n";

    return($failed_ctr, $acc_ctr, \@failed_list);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub display_parsed_failed_summary($$\@) {

    my $failed_ctr = shift;
    my $acc_ctr = shift;
    my $failed_list = shift;

    @$failed_list = sort(@$failed_list);

    print "\n" . $failed_ctr . "/" . $acc_ctr . " entries failed\n"
	. join("", @$failed_list) . "\n";
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub print_reports(\$\$\%) {

    my ($failed_ctr, $acc_ctr, $failed_list);

    my $summary_report = shift;
    my $full_details_report = shift;
    my $parsed_failed_list = shift;

    ($failed_ctr, $acc_ctr, $failed_list) = generate_numeric_summary(%$parsed_failed_list);

    if ($submitter_mode) {
	print "\n------------------------ Summary of Errors/Warnings -----------------------\n\n";
    }
    else {
	print "\n--------------------------------- Summary ---------------------------------\n\n";
    }

    print $$summary_report;
    print "\n--------------------- Full Details of Errors/Warnings ---------------------\n\n";
    print $$full_details_report;

    if (!$submitter_mode) {
	print "\n------------------------------ Parsed/Failed ------------------------------\n";
	display_parsed_failed_summary($failed_ctr, $acc_ctr, @$failed_list);
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

    my ($line, $DE_lines, %FT_lines, $get_rest_of_feature, $location);
    my $i;
    my $acc = shift;

    $DE_lines = "";
    $get_rest_of_feature = 0;

    if (open(READFFL, "<$acc.ffl")) {

	while ($line = <READFFL>) {

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

	close(READFFL);
    }
    else {
	print "Cannot open $acc.ffl\n";
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

    if ((!$show_accessions) && (!$acc_printed_full)) {
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
	    
	    $$full_details_report .= ":\n$transl\n" . "- Translation details:\n";
	    
	    foreach $transl_set (@{ $cds->{transl_set} }) {
		
		foreach $error (@{ $transl_set->{error} }) {
		    if ($error ne "") {
			if ($show_accessions || ((!$show_accessions) && ($error !~ /proteintranslation failed/))) {
			    $$full_details_report .= "$error\n";
		    }
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

sub build_line($$$$$$$;$) {

    my ($summary_line, $full_details_line, $tmp, $pad_length);

    my $acc = shift;
    my $DE_lines = shift;
    my $acc_ctr = shift;
    my $location = shift;
    my $acc_printed_summ = shift;
    my $acc_printed_full = shift;
    my $error_str = shift;
    my $not_entry_level = shift; # only defined if blank location is preferred

    $summary_line = "";
    $full_details_line = "";

    if ((!$acc_printed_summ) && ($acc_ctr > 1) && (!$show_accessions)) {
	$summary_line = "\n";
	$full_details_line = "\n";
    }

    $pad_length = 18;

    if ($location ne "") {
	$location =~ s/complement/c/gi;
	$location =~ s/join/j/gi;
	$location = substr($location, 0, $pad_length);

	if (!$show_accessions) {
	    $location = "Position ".$location;
	}
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
	if ($show_accessions) {
	    $tmp = $acc_ctr.".";
	    $summary_line .= sprintf("%-3s %-9s %-${pad_length}s  %s\n", $tmp, $acc, $location, $error_str);
	}
	else  {
	    $summary_line .= $acc_ctr.". Identifying DE line:\n$DE_lines\n".sprintf("%-${pad_length}s  %s\n", $location, $error_str);
	}
    }
    else {
	if ($show_accessions) {
	    $summary_line .= " " x 14;
	}

	$summary_line .= sprintf("%-${pad_length}s  %s\n",$location, $error_str);
    }

    if (!$acc_printed_full) {
	if ($show_accessions) {
	    $tmp = $acc_ctr.".";

	    if ($location !~ /entry-level/) {

		$full_details_line .= sprintf("%-3s %-9s\n", $tmp, $acc);
		$full_details_line .= "====== CDS ERROR START ====================================\n";

		if ($location !~ /^Position/) {
		    $full_details_line .= "Position ";
		}

		$full_details_line .= sprintf("%-${pad_length}s  %s\n", $location, $error_str);
	    }
	    else {
		$full_details_line .= sprintf("%-3s %-9s %-${pad_length}s  %s\n", $tmp, $acc, $location, $error_str);
	    }
	}
	else {
	    if ($location !~  /entry-level/) {
		$full_details_line .= $acc_ctr.". Identifying DE line:\n$DE_lines\n".
		    "====== CDS ERROR START ====================================\n";

		if ($location !~ /^Position/) {
		    $full_details_line .= "Position ";
		}

		$full_details_line .= sprintf("%-${pad_length}s  %s\n", $location, $error_str);
	    }
	    else {
		$full_details_line .= $acc_ctr.". Identifying DE line:\n$DE_lines\n".sprintf("%-${pad_length}s  %s\n", $location, $error_str);
	    }
	}
    }
    else {
#	if ($show_accessions) {
#	    $full_details_line .= " " x 14;
#	}

	if ($location !~ /entry-level/) {
	    $full_details_line .= "====== CDS ERROR START ====================================\n";
	}

	if ($location !~ /^Position/) {
	    $full_details_line .= "Position ";
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
    my $acc_ctr = shift;


    if ($submitter_mode && $$entry_info{error_count}) {
	remove_warnings_hidden_from_submitter(%$entry_info);
    }

    ($DE_lines, $FT_line_hash) = get_DE_and_FT_lines($$entry_info{acc});

    $acc_printed_summ = 0;
    $acc_printed_full = 0;
    $entry_level_errors_found = 0;

    ## add entry-level errors to reports
    if ($$entry_info{entry_errors}) {
	$error_str = get_entry_errors(@{ $$entry_info{entry_errors} });

	if ($submitter_mode) {
	    if (defined($error_str) && ($error_str ne "") && ($error_str !~ /ok/)) {
		($summ_line, $fd_line) = build_line($$entry_info{acc}, $DE_lines, $acc_ctr, "", $acc_printed_summ, $acc_printed_full, $error_str);

		$$summary_report .= $summ_line;
		$acc_printed_summ++;

		$$full_details_report .= $fd_line;
		$acc_printed_full++;
	    }
	}
	# curator mode
	else {
	    ($summ_line, $fd_line) = build_line($$entry_info{acc}, $DE_lines, $acc_ctr, "", $acc_printed_summ, $acc_printed_full, $error_str);

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
		($summ_line, $fd_line) = build_line($$entry_info{acc}, $DE_lines, $acc_ctr, $location, $acc_printed_summ, $acc_printed_full, $error_str);

		$$summary_report .= $summ_line;
		$acc_printed_summ++;

		if ($error_str !~ /coding pseudo/) {
		    $$full_details_report.= $fd_line;
		    $acc_printed_full++;
		}
	    }
	}
	# curator mode
	else {
	    ($summ_line, $fd_line) = build_line($$entry_info{acc}, $DE_lines, $acc_ctr, $location, $acc_printed_summ, $acc_printed_full, $error_str);

	    $$summary_report .= $summ_line;
	    $acc_printed_summ++;

	    if (($error_str !~ /ok/) && ($error_str !~ /coding pseudo/)) {
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
	    }
	    if ($error_str !~ /coding pseudo/) {
		$$full_details_report.= "====== CDS ERROR END ======================================\n";
	    }
	}

	$cds_level_errors_found++;
    }

    # catch accs with no warnings/errors/info for curator summary report
    if (!$submitter_mode) {
	if ((!$entry_level_errors_found) && (!$cds_level_errors_found)) {

	    ($summ_line, $fd_line) = build_line($$entry_info{acc}, $DE_lines, $acc_ctr, "", $acc_printed_summ, $acc_printed_full, "ok", 1);
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

sub parse_entry(\@\$\$\%$) {

    my ($line, %entry_info, $line_num, $collect_translation, $tmp);
    my ($transl_num, $cds_num, $get_cds, $pseudo, $acc_printed);

    my $acc_info = shift;
    my $summary_report = shift;
    my $full_details_report= shift;
    my $parsed_failed_list = shift;
    my $acc_ctr = shift;

    $collect_translation = "";
    $line_num = 1;
    $cds_num = -1;

    # check if there are any entry-level errors before CDS's start
    foreach $line (@$acc_info) {

	if ($line !~ /^INFO: \-{70}/) {
	    $tmp = $line;
	    $tmp =~ s/, (input|entry) line: \d+\n?//g;

	    if ($tmp =~ /(parsed|failed) entry: (\S+)/) {
		$entry_info{acc} = $2;
		$entry_info{status} = $1;
		$$parsed_failed_list{$2} = $1;
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

    for ($line_num=0; $line_num<@$acc_info; $line_num++) {

	# skip lines before cds starts
	if ($cds_num == -1) {
	    if ($$acc_info[$line_num] !~ /^INFO: \-{70}/) {
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
	    if (($collect_translation ne "") && ($$acc_info[$line_num] =~ /^(INFO|WARNING|ERROR): /)) {
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
	    if ($$acc_info[$line_num] =~ /^INFO: \-{70}/) {
		$transl_num = 0;
		$cds_num++;
		next;
	    }
	    # collect location of CDS (first instance)
	    elsif (($$acc_info[$line_num] =~ /(INFO|ERROR|WARNING): CDS (\S+)/) && (!defined($entry_info{cds}[$cds_num]{location}))) {
		$entry_info{cds}[$cds_num]{location} = $2;
		$entry_info{cds}[$cds_num]{location} =~ s/,$//;

		if ($$acc_info[$line_num] =~ /pseudo/) {
		    push(@{ $entry_info{cds}[$cds_num]{transl_set}[$transl_num]{error} }, "WARNING: coding pseudo");
		    $pseudo = 1;
		    $entry_info{error_count}++;
		}
	    }
	    # store accession and parsed/failed status
	    elsif ($$acc_info[$line_num] =~ /^INFO: \#{3} (parsed|failed) entry: ([^\n]+)/) {
		$entry_info{status} = $1;
		$entry_info{acc} = $2;
		$$parsed_failed_list{$2} = $1;
	    }
	    # collect protein translation
	    elsif (($$acc_info[$line_num] =~ /^(INFO: |      )([atgc]{3} )+/) || ($$acc_info[$line_num] =~ /^      ([A-Z\*]   ?)+/)) {
		$$acc_info[$line_num] =~ s/^\s+//;
		$collect_translation .= $$acc_info[$line_num];
	    }
	    # store INFO lines which aren't protein translations
	    elsif ($$acc_info[$line_num] =~ /^(INFO: .+)/) {
		$tmp = $1;
		$tmp =~ s/, input line: \d+//;

		push(@{ $entry_info{cds}[$cds_num]{transl_set}[$transl_num]{info} }, $tmp);
	    }
	    # store WARNINGs and  ERRORs
	    elsif ($$acc_info[$line_num] =~ /^((ERROR|WARNING): .+)/) {

		if ($$acc_info[$line_num] =~ /^(ERROR: DS number does not exist in the database)/) {
		    push(@{ $entry_info{entry_errors} }, $1);
		    $entry_info{error_count}++;
		}
		elsif ($$acc_info[$line_num] !~ /proteintranslation failed/) {
		    $tmp = $1;
		    $tmp =~ s/, input line: \d+//;
		    push(@{ $entry_info{cds}[$cds_num]{transl_set}[$transl_num]{error} }, $tmp);
		    $entry_info{error_count}++;
		}
	    }
	}
    }

    $acc_printed = build_reports(%entry_info, $$summary_report, $$full_details_report, $acc_ctr);

    return($acc_printed);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub parse_loadlog($) {

    my ($line, @acc_info, $summary_report, $full_details_report, %parsed_failed_list);
    my ($acc_printed, $acc_ctr);

    my $loadlog_file = shift;

    open(READ_LOADLOG, "<$loadlog_file") || die "Cannot open $loadlog_file: $!\n";

    $full_details_report = "";
    $acc_ctr = 1;

    while ($line = <READ_LOADLOG>) {

	if ($line =~ /^INFO: \#{3} (parsed|failed) entry: ([A-Z]+\d+)/) {
	    push(@acc_info, $line);

            # acc_printed flag is returned because in submitter mode, it doesn't follow
            # the number of the accession owing to not displaying ok entries 
	    $acc_printed = parse_entry(@acc_info, $summary_report, $full_details_report, %parsed_failed_list, $acc_ctr);
	    @acc_info = ();

	    if ($acc_printed) {
		$acc_ctr++;
	    }
	}
	elsif ($line =~ /^\#{3} (parsed|failed) entry: ([A-Z]{2}\d+)/) {
	    die "The input file $loadlog_file was not generated using the putff -new_log_format option. Please try again.\n";
	}
	elsif (($line =~ /INFO: =====+ CDS TRANSLATIONS ==+/) || ($line =~ /INFO: #######+ NEXT ENTRY ##+/)) {
	    next;
	}
	else {
	    push(@acc_info, $line);
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

    my $usage = "\n PURPOSE: Parses output from \"putff -parse_only\" to report if .ffl\n".
        "          files will load and if CDS features code correctly.\n".
	"          The old script 'ckprots' worked similarly to this script, reporting\n".
	"          on CDS feature errors.\n\n".
        " USAGE:   $0 <file to parse> [-s(ubmitter)] [-noacc]\n\n".
        " <file to parse>  This file is created by putffer (previously 'load.csh' or\n".
	"                  'loadcheck.csh') and is commonly called load.log\n".
	" -sub     submitter mode which only displays errors and certain warnings which the\n".
	"          curator cannot easily fix.  -sub can be used independently of the -noacc\n".
	"          option. (optional argument)\n".
	" -noacc   the output contains no accessions, using DE lines to identify a file\n".
        "          instead.  -noacc can be used independently of the -sub option.\n".
	"          (optional argument)\n";

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
