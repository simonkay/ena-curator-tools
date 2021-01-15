#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2006
#
#  SCRIPT DESCRIPTION:
#
#  A script to run a 16S blast and output a summary of results.
#
#  MODIFICATION HISTORY:
#  CVS version control block - do not edit manually
#  $RCSfile: vector_contamination_check.pl,v $
#  $Revision: 1.8 $
#  $Date: 2009/03/18 13:27:08 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/vector_contamination_check.pl,v $
#  $Author: gemmah $
#
#===============================================================================

use strict;
use Bio::Tools::BPlite;
use File::Find;
use Data::Dumper;
use SeqDBUtils2;
use Cwd;

my $verbose;
my $pwd             = cwd;
my $wuBlastDir      = "/ebi/extserv/bin/wu-blast";
my $blastDBlocation = "/ebi/production/seqdb/embl/tools/curators/scripts/curator_blast_databases/silva_vector/vectordb-200803.fasta";
my $dsBlastableDir  = cwd . "/blastables.del";
my $seqret          = "/ebi/extserv/bin/emboss/bin/seqret";
my $split_script    = "/ebi/production/seqdb/embl/tools/curators/scripts/splitffl.pl";

my $usage =
    "\nPURPOSE: Use this script to identify any vector contamination in the sequence.\n"
  . " By default the script will look for vector contamination throughout the whole\n"
  . " sequence, but there is an option (-e) to only look for vector sequences at either\n"
  . " end of the provided sequence.\n\n"
  . " USAGE: vector_contamination_check.pl [<sequence files>] [-e(nds)] [-l(ength)=<number of bases to check>] [-v(erbose)] [-h(elp)]\n\n"
  . "   <sequence files>   where <sequence files> are of type .fflupd, .ffl, .temp or .sub\n"
  . "                      These input file must contain at least one embl entry.\n"
  . "                      NB If you want to add a selection of files using a\n"
  . "                      wildcard (*), you must escape the * with a backslash\n"
  . "                      You may also add a list of space-separated filenames.\n\n"
  . "   -e            Check the ends of the sequence for vector contamination.\n\n"
  . "   -l=<number>   The length of the ends of the sequence you want to check for vector\n"
  . "                 contamination, where x is a number.  Default = 90, so 90 nt at each\n"
  . "                 end of the sequence will be blasted against the vector database. A\n"
  . "                 value below 10 may produce less reliable results.\n\n"
  . "   -v            Verbose mode\n\n"
  . "   -h            Shows this help text\n\n";


################################################################################
# get accession and sequence length from an embl file

sub get_acc_and_seqlen($$) {

    my ($acc, $len, $line, $line_num, $locate_entry_number, $file_entry_number);
    my ($sequence, $get_sequence_line, $grab_sequence);

    my $queryFile  = shift;
    my $masterFile = shift;

    $acc = "";
    $len = 0;
    $line_num = 1;

    # if the file containing a single entry is of the format 01.findvec.tmp
    # then take the filename number in order to find the line number of this
    # entry in the bulk file (for the substitute accession).
    if ($queryFile =~ /^(\d+)\.findvec\.tmp$/) {

	$locate_entry_number = $1;
	$locate_entry_number =~ s/^0*//g; # remove leading zeros

	$file_entry_number = 0;
	$grab_sequence = 0;
	$get_sequence_line = 0;

	if (open(READBULK, "<$masterFile")) {
	    
	    while ($line = <READBULK>) {
		
		if ($line =~ /^ID/) {

		    $file_entry_number++;

		    if ($file_entry_number == $locate_entry_number) {
			$acc = $masterFile."_ln".$line_num;
			$grab_sequence = 1;
		    }
		}
		
		elsif ($grab_sequence) {

		    if ($line =~ /^SQ/) {
			$get_sequence_line = 1;
		    }
		    elsif ($line =~ /^\/\//) {
			$grab_sequence = 0;
			$sequence =~ s/[^a-zA-Z]//g;
			$len = length($sequence);
		    }
		    elsif ($get_sequence_line) {
			$sequence .= $line;
		    }
		}

		$line_num++;
	    }
	}
	close(READBULK);
	return($acc, $len);
    }
    # if entry file contains an accession...
    else {

	if (open(READEMBL, "<$queryFile")) {

	    while ($line = <READEMBL>) {
		if ($line =~ /^ID\s+([^;]+);/) {
		    if ($1 eq "XXX") {
			$acc = $queryFile."_ln".$line_num;
		    }
		    else {
			$acc = $1;
		    }
		}
		elsif ($line =~ /^SQ/) {
		    $grab_sequence = 1;
		}
		elsif ($line =~ /^\/\//) {
		    $grab_sequence = 0;
		    $sequence =~ s/[^a-zA-Z]//g;
		    $len = length($sequence);
		}
		elsif ($grab_sequence) {
		    $sequence .= $line;
		}

		$line_num++;
	    }
	} 
	else {
	    die "Could not read $queryFile\n";
	}

	close(READEMBL);
	return($acc, $len);
    }
}

################################################################################
#

sub display_summary($$$\%) {

    my ($item);

    my $results_counter = shift;
    my $num_entries = shift;
    my $dir_name = shift;
    my $summary_list = shift;

    print "\n########################################################\nSummary:\n";
    if ($results_counter) {

	if ($num_entries == $results_counter) {
	    print "All";
	}
	else {
	    print "$results_counter out of ".$num_entries;
	}
	print " sequences appear to contain vector.\n\n";
    }
    else {
	print "None of your sequences appear to contain vector.\n";
    }


    foreach $item (sort keys(%$summary_list)) {
	printf("%-10s %-7s uncontaminated span\n", $item, $$summary_list{$item});
    }


    print "--------------------------------------------------------\n- All the original unparsed blast results (if any) can be\nfound listed inside $dir_name/findvec_<accession>.log files.\n- This summary can be found in $dir_name/findvec.log\n--------------------------------------------------------\n";
}


################################################################################
# display the likes of "the uncontaminated sequence lies in span 31-601"

sub display_uncontaminated_span_positions(\%$) {

    my ($i, $j, $pos, $low_pos, $high_pos, $first_true_nucleotide_pos);
    my ($last_true_nucleotide_pos, @positions, $next_low_pos, $next_high_pos);
    my ($block_entered);

    my $vector_hsps = shift;
    my $querylen = shift;

#####
# I really don't know how to do this - it's obvious if there is a large gap between vector spans at the beginning and end of the sequence.  What happens if there is no gap?  Perhaps I shouldn't worry because the situaton would be unlikely...
#
# look to see if there is coverage at position 1, then 2, then 3 and find the lowest position without coverage.
#
# look to see if there is any coverage at position $seqlen, then $seqlen - 1, then $seqlen - 2 and note the point that coverage fails.
#
#####

    $first_true_nucleotide_pos = 0;
    @positions = sort keys(%$vector_hsps);

    if (($positions[0] =~ /(\d+)\-\d+/) && ($1 > 11)) {
	$first_true_nucleotide_pos = 1;
    }
    else {
        # look for coverage at start of sequence
	for ($i=0; $i<@positions; $i++) {
	    $block_entered = 0;
	    
	    ($low_pos, $high_pos) = split("-", $positions[$i]); # 1, 30 #  31, 60
	    
	    # check to see if there are any other spans within 10nt of the
	    # end of the first span.
	    for ($j=($high_pos+1); $j<($high_pos+11); $j++) { #31; <41  # 61, 71
	    
		if (defined $positions[($i+1)]) {
		    ($next_low_pos, $next_high_pos) = split("-", $positions[($i+1)]); # 31, 60 # 361, 391
		    
		    if ($j >= $next_low_pos) {
			$first_true_nucleotide_pos = $next_high_pos + 1;
			$block_entered = 1;
		    last;
		    }
		}
	    }
	    
	    if (!$block_entered) {
		$first_true_nucleotide_pos = $high_pos+1;
		last;
	    }
	}
    }

    # look for coverage at end of sequence
    $last_true_nucleotide_pos = 0;
    @positions = reverse sort keys(%$vector_hsps);

   if (($positions[0] =~ /\d+\-(\d+)/) && ($1 < ($querylen - 11))) {
	$last_true_nucleotide_pos = $querylen;
    }
    else {
	for ($i=0; $i<@positions; $i++) {
	    $block_entered = 0;

	    ($low_pos, $high_pos) = split("-", $positions[$i]); # 662, 691 #  632, 663

	    # check to see if there are any other spans within 10nt of the
	    # end of the first span.
	    for ($j=($low_pos-1); $j>($low_pos-11); $j--) { #31; <41  # 61, 71
	    
		if (defined $positions[($i+1)]) {
		    ($next_low_pos, $next_high_pos) = split("-", $positions[($i+1)]); # 632, 663 # 361, 391
		    
		    if ($j <= $next_high_pos) {
			$last_true_nucleotide_pos = $next_low_pos - 1;
			$block_entered = 1;
			last;
		    }
		}
	    }
	    
	    if (!$block_entered) {
		$last_true_nucleotide_pos = $low_pos-1;
		last;
	    }
	}
    }

    if ($verbose) {
	print "\nAllowing gaps of up to 10 bases between vector spans at\nthe ends of the sequence, the uncontaminated sequence\nbetween these positions: $first_true_nucleotide_pos"."-"."$last_true_nucleotide_pos\n";
    }
    else {
	print "\nSuggested uncontaminated span: $first_true_nucleotide_pos"."-"."$last_true_nucleotide_pos\n";
    }

    return($first_true_nucleotide_pos."-".$last_true_nucleotide_pos);
}

################################################################################
# Make a fasta-formatted file from an embl-format file

sub make_snippet_fasta_file($$$) {

    my ($tmpFastaFile, $seqretCmd);

    my $firstPosition = shift;
    my $lastPosition = shift;
    my $queryFile = shift;

    $tmpFastaFile = $queryFile . '.fasta';

    $seqretCmd = $seqret." -sbegin $firstPosition -send $lastPosition -osformat2 fasta -sequence $queryFile -outseq $tmpFastaFile -auto";

    $verbose && print "\nCreating fasta file for TPA sequence from ".$queryFile." using the following command:\n".$seqretCmd."\n\n";

    system($seqretCmd);

    return ($tmpFastaFile);
}

################################################################################
# pull out any vector hits found

sub check_endsonly_results_for_vectors($\%$$$) {

    my ($keep_checking_spans, $report, $pos, $hsp, $hit, $hit_name, $acc);
    my ($querylen, $adjustment);

    my $blastOutputFile = shift;
    my $vector_hsps = shift;
    my $firstPosition = shift;
    my $lastPosition = shift;
    my $end_being_checked = shift;  # 5 or 3

    $keep_checking_spans = 0;

    open(BLASTRES, $blastOutputFile) || die "Cannot open $blastOutputFile in order to read and parse the blast output. Exiting script...\n";

    $report = new Bio::Tools::BPlite(-fh => \*BLASTRES);
    {
        while ($hit = $report->nextSbjct) {

	    while ($hsp = $hit->nextHSP) {

		if ($hsp->percent == 100) {
		    $keep_checking_spans = 1;

		    $pos = $hsp->query->start."-".$hsp->query->end;

		    if ($end_being_checked == 3) {  # 3 prime end so adjust positions
			$adjustment = $firstPosition - 1;
			$pos = ($hsp->query->start + $adjustment)."-".($hsp->query->end + $adjustment);
		    }

		    if ($hit->name =~ /([A-Z]{1,2}\d{5,6}(\.\d+)?)/) {
			$hit_name = $1;
		    }

		    if ((defined $$vector_hsps{$pos}) && ($$vector_hsps{$pos} !~ /$hit_name/)) {
			$$vector_hsps{$pos} .= ", $hit_name";
		    }
		    else {
		        $$vector_hsps{$pos} = $hit_name;
		    }
		}
            }
        }

        # the following line takes you to the next report in the stream/file
        # it will return 0 if that report is empty,
        # but that is valid for an empty blast report.
        # Returns -1 for EOF.

        last if ($report->_parseHeader == -1);
        redo;
    }

    close(BLASTRES);

    return($keep_checking_spans);
}

################################################################################
#

sub print_endsonly_results(\%$$) {

    my ($checked5Prime, $checked3Prime, $msg, $msg2, $pos, %vectorAt5End);
    my (%vectorAt3End, $results_found);

    my $vector_hsps = shift;
    my $endLengthCheck = shift; 
    my $querylen = shift;

    $checked5Prime = 0;
    $checked3Prime = 0;

    foreach $pos (sort keys %$vector_hsps) {

	if ($pos =~ /(\d+)\-\d+/) {
	    if ($1 < $endLengthCheck) {

		$vectorAt5End{$pos} = $$vector_hsps{$pos};

		if (! $checked5Prime) {
		    $checked5Prime = 1;
		}
	    }
	    else {
		$vectorAt3End{$pos} = $$vector_hsps{$pos};

		if (! $checked3Prime) {
		    $checked3Prime = 1;
		}
	    }
	}
    }

    $results_found = 1;
    $msg  = "Vector found at ";
    $msg2 = "\n\n";

    if ($checked5Prime && !$checked3Prime) {
	print $msg."5'".$msg2;
    }
    elsif (!$checked5Prime && $checked3Prime) {
	print $msg."3'".$msg2;
    }
    elsif ($checked5Prime && $checked3Prime) {
	print $msg."5' and 3'".$msg2;
    }
    elsif (!$checked5Prime && !$checked3Prime) {
	print "No vector found\n"; 
	$results_found = 0;
    }


    foreach $pos (sort keys %vectorAt5End) {
	printf("  %-11s %s\n", $pos,  $vectorAt5End{$pos});
    }
    if (scalar(keys(%vectorAt5End)) && scalar(keys(%vectorAt3End))) {
	print "\n";
    }

    foreach $pos (sort keys %vectorAt3End) {
	printf("  %-11s %s\n", $pos,  $vectorAt3End{$pos});
    }

    return($results_found);
}

################################################################################
# run a blast on the first 30 bp of the sequence, then first 60bp and so on
# until no more vector is found.  Then repeat with last 30bp, last60bp etc until
# no more vector is found at the 3' end.

sub generate_and_parse_endsonly_blast_output($$$$$\%) {

    my ($tmpFastaFile, $keep_checking_spans, $lastPosition, $blastScript);
    my ($loopCounter, %vector_hsps, $firstPosition, $blastChunkSize);
    my ($endAfterNextLoop, $results_found, $span);

    my $queryFile       = shift;
    my $blastOutputFile = shift;
    my $endLengthCheck  = shift;
    my $acc             = shift;
    my $querylen        = shift;
    my $summary_list    = shift; # empty hash to be filled with true span list

    $keep_checking_spans = 1;
    $firstPosition = 1;
    $lastPosition = 30;
    $loopCounter = 1;

    if ($acc eq "") {
	$acc = $queryFile;
    }

    if ($endLengthCheck >= 30) {
	$blastChunkSize = 30;
    }
    elsif ($endLengthCheck >= 20) {
	$blastChunkSize = 20;
    }
    elsif ($endLengthCheck >= 15) {
	$blastChunkSize = 15;
    }
    elsif ($endLengthCheck >= 10) {
	$blastChunkSize = 10;
    }

    $endAfterNextLoop = 0;

    # check spans from 5' end
    while ($keep_checking_spans && ($lastPosition <= $endLengthCheck)) {
	#print "firstpos = $firstPosition\n";
	#print "lastpos = $lastPosition\n";

        # make fasta sequence file
	($tmpFastaFile) = make_snippet_fasta_file($firstPosition, $lastPosition, $queryFile);

        # make blast output file
	$blastScript = "$wuBlastDir/blastn $blastDBlocation $tmpFastaFile" . " -warnings -errors -notes > $blastOutputFile".".".$loopCounter;

	$verbose && print "Running blast with the following command:\n$blastScript\n\n";

	system($blastScript);

	$keep_checking_spans = check_endsonly_results_for_vectors($blastOutputFile.".".$loopCounter, %vector_hsps, $firstPosition, $lastPosition, 5);

	$loopCounter++;

	if ($endAfterNextLoop) {
	    last;
	}

	$lastPosition += $blastChunkSize;

	if (($lastPosition > $endLengthCheck) && ($lastPosition != ($endLengthCheck + $blastChunkSize))) {
	    $lastPosition = $endLengthCheck;
	    $endAfterNextLoop = 1;
	}
    }

    # reset variables for 3' checks
    $firstPosition = $querylen - 29;
    $lastPosition  = $querylen;
    $keep_checking_spans = 1;

    $endAfterNextLoop = 0;
    #%vector_hsps = ();

    # check spans from 3' end
    while ($keep_checking_spans && ($firstPosition >= $querylen - $endLengthCheck + 1)) {

        # make fasta sequence file
	($tmpFastaFile) = make_snippet_fasta_file($firstPosition, $lastPosition, $queryFile);

        # make blast output file
	$blastScript = "$wuBlastDir/blastn $blastDBlocation $tmpFastaFile" . " -warnings -errors -notes > $blastOutputFile".".".$loopCounter;

	if ($verbose) {
	    print "Running blast with the following command:\n$blastScript\n\n";
	}

	system($blastScript);

	# delete fasta file now it is no longer needed
	unlink($tmpFastaFile);

	$keep_checking_spans = check_endsonly_results_for_vectors($blastOutputFile.".".$loopCounter, %vector_hsps, $firstPosition, $lastPosition, 3);

	$loopCounter++;

	$firstPosition -= $blastChunkSize;
    }
    print "\n########################################################\n$acc ($querylen bp): ";
    $results_found = print_endsonly_results(%vector_hsps, $endLengthCheck, $querylen);

    if ($results_found) {
	$span = display_uncontaminated_span_positions(%vector_hsps, $querylen);
	$$summary_list{$acc} = $span;
    }

    return($results_found);
}

################################################################################
# Make a fasta-formatted file from an embl-format file

sub make_fasta_sequence_file($) {

    my ($entryCounter, $latestSequence, $len, $identifier, $tmpFastaFile);
    my $queryFile = shift;

    $tmpFastaFile = $queryFile . '.fasta';

    open(SAVESEQ, ">$tmpFastaFile") || die "cannot open $tmpFastaFile";

    open(QUERYFILE, "<$queryFile") || die "cannot open $queryFile";
    {
        local $/ = "\/\/\n"; # for this anonymous code block we are  defining the stream-in separator (every time we read from the file we  get a chunk ending in '//\n')

        $entryCounter = 0;
        while (<QUERYFILE>) {

            if ($_ =~ /^ID/) {
                $latestSequence = $_;
                $entryCounter++;
                $identifier = $queryFile . "_Entry_" . $entryCounter;
                if ($latestSequence =~ /\nAC   ([A-Z0-9]+)/s) {
                    $identifier = $1;
                }
                $latestSequence =~ s/^.*\nSQ   [^\n]+\n//s;
                $latestSequence =~ s/[^a-zA-Z]//gs;
                $len = length($latestSequence);

                print SAVESEQ ">$identifier = $len bp\n";
                print SAVESEQ $latestSequence . "\n";
            }
        }
    }
    close(QUERYFILE);
    close(SAVESEQ);

    return ($tmpFastaFile);
}

################################################################################
# run a blast on the whole sequence and save the output to a file

sub generate_full_blast_output($$) {

    my ($blastScript, $tmpFastaFile, $acc, $querylen);

    my $queryFile       = shift;
    my $blastOutputFile = shift;

    # make fasta sequence file
    ($tmpFastaFile) = make_fasta_sequence_file($queryFile);

    # make blast output file
    $blastScript = "$wuBlastDir/blastn $blastDBlocation $tmpFastaFile" . " -warnings -errors -notes > $blastOutputFile";

    if ($verbose) {
        print "Running blast with the following command:\n$blastScript\n\n";
    }

    system($blastScript);

    # delete temp file
    unlink($tmpFastaFile);
}

################################################################################
# parse the full sequence output of the blast

sub parse_full_blast_output($$$\%) {

    my ($report, $hsp, $pos, $hit, $hit_name, $results_retrieved, %vector_hsps);
    my ($span);
 
    my $blastOutputFile = shift;
    my $acc             = shift;
    my $querylen        = shift;
    my $summary_list    = shift;

    open(BLASTRES, $blastOutputFile) || die "Cannot open $blastOutputFile in order to read and parse the blast output. Exiting script...\n";

    $report = new Bio::Tools::BPlite(-fh => \*BLASTRES);
    {
        while ($hit = $report->nextSbjct) {

	    while ($hsp = $hit->nextHSP) {

		if ($hsp->percent == 100) {

		    $pos = $hsp->query->start."-".$hsp->query->end;

		    if ($hit->name =~ /([A-Z]{1,2}\d{5,6}(\.\d+)?)/) {
			$hit_name = $1;
		    }

		    if (defined $vector_hsps{$pos}) {
			$vector_hsps{$pos} .= ", ";
		    }

		    $vector_hsps{$pos} .= $hit_name;
		}
            }
        }

        # the following line takes you to the next report in the stream/file
        # it will return 0 if that report is empty,
        # but that is valid for an empty blast report.
        # Returns -1 for EOF.

        last if ($report->_parseHeader == -1);
        redo;
    }

    print "\n########################################################\n$acc ($querylen bp): ";
    if (scalar(keys(%vector_hsps))) {

	print "Vector found\n\n";
	foreach $pos (sort keys(%vector_hsps)) {
	    printf("  %-11s %s\n", $pos,  $vector_hsps{$pos});
	}

	$results_retrieved = 1;

	$span = display_uncontaminated_span_positions(%vector_hsps, $querylen);
	$$summary_list{$acc} = $span;
    }
    else {
	print "No vector found\n\n";
	$results_retrieved = 0;
    }

    close(BLASTRES);

    return($results_retrieved);
} 

################################################################################
# Add all the blast results into one findvec.log file

sub concatentate_blast_results_into_log($$$$) {

    my ($logFile, $catCmd, $mvCmd, @files);
    
    my $blastFile = shift;
    my $dir_name = shift;
    my $acc = shift;
    my $full_blast = shift;
    
    $logFile = "$dir_name/findvec_$acc.log";

    if (!$full_blast) {  # if the ends-only blast is run, there are many more blast output files
	$blastFile =~ s/\..*$//g;

	@files = <$blastFile.*>;

	print Dumper(\@files);

	if (scalar(@files)) {
	    $catCmd = "cat $blastFile.* > $logFile";
	    $verbose && print "Putting all the blast files together in a single file: ".$catCmd."\n";
	    system($catCmd);
	    unlink<$blastFile.*>;
	}
    }
    else {
	$mvCmd = "mv $blastFile $logFile";
	system($mvCmd);
    }
} 

################################################################################
# check if the hit number is in the right format

sub check_hit_display_number ($) {

    my ($hitNumber);
    my $input = shift;

    if ($input =~ /\d+/) {
        $hitNumber = $input;
    } else {
        $hitNumber = "3";
    }

    return ($hitNumber);
} 

################################################################################
# check input sequence file is readable

sub organise_inputted_seq_files(\@) {

    my ($file, @moreFiles, @newListofFiles);

    my $seqFiles = shift;

    if (@$seqFiles) {

        foreach $file (@$seqFiles) {
            if ($file =~ /^(\*\..+)/) {
                @moreFiles = glob($1);
                push(@newListofFiles, @moreFiles);
            } else {
                push(@newListofFiles, $file);
            }
        } ## end foreach $file (@$seqFiles)
    } else {
        get_input_files(@newListofFiles);
    }

    @$seqFiles = @newListofFiles;

    foreach $file (@$seqFiles) {
        if ((!(-f $file)) || (!(-r $file))) {
            die "$file is not readable. Exiting script...\n";
        }
    }
}


################################################################################
# Get the arguments

sub get_args($) {

    my (@seqFiles, $arg, $checkEndsOnly, $endLengthCheck, $checkChunkSize);

    my $args = shift;

    $checkEndsOnly = 0;
    $endLengthCheck = 90;
    $checkChunkSize = 30;

    # check the arguments for values
    foreach $arg (@$args) {

        if ($arg =~ /^\-e(nds)?$/) {         # only check ends of the sequence for vec contam
            $checkEndsOnly = 1;
	}
        elsif ($arg =~ /^\-l(ength)?=(\d+)$/) {      # check this length of sequence at each end
            $endLengthCheck = $2;
            $checkEndsOnly = 1;

	    if ($endLengthCheck < 10) {
		print "Warning: Checking a the first and last $endLengthCheck bases of a sequence won't give a particularly meaningful set of blast results.  You will get more reliabel results if you check longer stretches of sequence at the ends.  Default = 90 nt.\n";
	    }
	}
	elsif ($arg =~ /^\-v$/) {         # verbose mode
            $verbose = 1;
        } 
	elsif ($arg =~ /^\-h/) {          # help mode
            die $usage;
        } 
	elsif ($arg =~ /^([^-].+)/) {
            push(@seqFiles, $1);
        } 
	else {
            die "Unrecognised argument format. See below for usage.\n\n" . $usage;
        }
    }

    organise_inputted_seq_files(@seqFiles);

    return ($checkEndsOnly, $endLengthCheck, \@seqFiles);
}

################################################################################
# main function

sub main(\@) {

    my ($blastOutputFile, $acc, $file, $endLengthCheck, $seqFiles, $input_entry);
    my ($entry_counter, $checkEndsOnly, $querylen, $results_counter, $dir_name);
    my ($results_retrieved, @input_entries, $num_entries_in_file, $split_script_output);
    my (%summary_list);

    my $args = shift;

    ($checkEndsOnly, $endLengthCheck, $seqFiles) = get_args($args);

    # create dir to put output files
    $dir_name = "findvec";
    if (! -d $dir_name) {
	system("mkdir $dir_name");
    }

    if ($verbose) {
        print "\nUsing seq files :  " . join(", ", @$seqFiles) . "\n";

        if ($checkEndsOnly) {
            print "Checking only the ends of the sequence for vector contamination.\n\n";
        } 
	else {
            print "Checking the whole sequence for vector contamination.\n\n";
        }
    }

    $entry_counter = 1;
    $results_counter = 0;

    foreach $file (@$seqFiles) {

	$num_entries_in_file = `grep -c ^ID $file`;
	if ($num_entries_in_file > 1) {
	    $verbose && print "Clearing out old *.findvec.tmp entries...\n";
	    unlink <*.findvec.tmp>;
	    
	    $split_script .= " -s=findvec.tmp ".$file;
	    $verbose && print "Splitting $file into individual entries...\n$split_script\n";
	    $split_script_output = `$split_script`;
	    
	    @input_entries = <*.findvec.tmp>;  #get list of files in current directory
	}
	else {
	    $input_entries[0] = $file;
	}
	
	foreach $input_entry (@input_entries) {
	    ($acc, $querylen) = get_acc_and_seqlen($input_entry, $file);

	    $blastOutputFile = "$dir_name/findvec_blastoutput_$acc.log";

	    if ($checkEndsOnly) {
		$blastOutputFile .= ".".$entry_counter;
		$results_retrieved = generate_and_parse_endsonly_blast_output($input_entry, $blastOutputFile, $endLengthCheck, $acc, $querylen, %summary_list);
		concatentate_blast_results_into_log($blastOutputFile, $dir_name, $acc, 0);
	    } 
	    else {
		generate_full_blast_output($input_entry, $blastOutputFile);
		$results_retrieved = parse_full_blast_output($blastOutputFile, $acc, $querylen, %summary_list);
		concatentate_blast_results_into_log($blastOutputFile, $dir_name, $acc, 1);
	    }

            # delete temporary entry file
	    if ($input_entry =~ /(.+\.findvec\.tmp)$/) {
		unlink($1);
	    }

	    $entry_counter++;
	    $results_counter += $results_retrieved;
        }

	@input_entries = ();
    }


    display_summary($results_counter, $entry_counter - 1, $dir_name, %summary_list);
}

################################################################################
# run the script

main(@ARGV);
