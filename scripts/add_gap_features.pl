#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2007
#
#===============================================================================

use strict;
use SeqDBUtils2;
use Data::Dumper;

my $verbose;
my $backupReq = 1;
my $stdOutReq = 1;
my $test_mode = 0;

################################################################################
# calculate gap locations/lengths from sequence

sub get_gap_features(\@) {

    my ($line, $getSeqFlag, $seq, $seqLen, $nCount, $nPos, $startnPos);
    my ($nCounter, @gaps, $currentNucleotide);

    my $sequenceData = shift;

    $getSeqFlag = 0;
    $nCounter = 0;

    foreach $line (@$sequenceData) {
	if ( $line =~ /^SQ / ) {
	    $getSeqFlag = 1;
	}
	elsif ($line =~ /\/\//) {
	    last;
	}
	elsif ( $getSeqFlag ) {
	    $seq .= $line;
	}
    }

    $seq =~ s/\/\///;
    $seq =~ s/[ \n\r\t]//g;
    $seq =~ s/\d+//g;
    $seq = lc($seq);

    $seqLen = length($seq);

    $_ = $seq;
    $nCount = tr/n//;

    if ($nCount) {
	for ($nPos=0; $nPos<$seqLen; $nPos++) {

	    $currentNucleotide = substr( $seq, $nPos, 1 );

	    if ( $currentNucleotide eq "n" ) {
		if (! $startnPos) {
		    $startnPos = $nPos+1;
		}

		$nCounter++;
	    }

	    if ( $nCounter && (($currentNucleotide ne "n") || ($startnPos + $nCounter - 1 == $seqLen))) {
		push(@gaps, {  
		    START  => $startnPos,
		    END    => $startnPos + $nCounter - 1,
		    LENGTH => $nCounter
		    });

		$startnPos = 0;
		$nCounter = 0;
	    }
	}
    }

    $verbose && print Dumper(\@gaps);

    return (\@gaps);
}

################################################################################
#

sub preformat_new_gap_features(\@) {

    my ($newGapFt, $gapFt, @newGaps);

    my $gapFeatures = shift;

    foreach $gapFt (@$gapFeatures) {
	$newGapFt = "FT   gap             ".$gapFt->{START}."..".$gapFt->{END}."\n"
	    .       "FT                   /estimated_length=".$gapFt->{LENGTH}."\n";
	
	push(@newGaps, $newGapFt);
    }

    return(\@newGaps);
}

################################################################################
# grab data, extract data and re-save data with new data included.

sub update_files_with_gap_features(\@) {

    my ( $inputFile, $line, @inputFileContents, $newGaps, $switch_array );
    my ( $changedFile, $backupFilename, $new_file, @changed_files, @first_part_of_entry );
    my ( @second_part_of_entry, $gapFeatures, $newGapFt, %changedFiles);

    my $inputFiles = shift;
    

    foreach $inputFile (@$inputFiles) {

	open( READINPUT, "<$inputFile" ) || die "Cannot open input file $inputFile for reading: $!\n";

	$new_file = $inputFile.".adding_gaps";
	open( WRITENEWDATA, ">$new_file");

	$switch_array = 0;
	$changedFile = 0;

        while ($line = <READINPUT>) {

	    if ($line =~ /^SQ/) {
		$switch_array = 1;
	    }

	    if (! $switch_array) {
		if (($line !~ /^FT\s+gap\s+/) && 
		    ($line !~ /^FT\s+\/estimated_length\=\d+/)) {
		    push(@first_part_of_entry, $line);
		}
	    }
	    else {
		push(@second_part_of_entry, $line);
	    }


	    if ($line eq "//\n") {

		$gapFeatures = get_gap_features(@second_part_of_entry);

		# Remove XX at the end of the FT table so we can tag on
		# new FT lines
		if ($first_part_of_entry[-1] =~ /^XX\s*$/) {
		    pop(@first_part_of_entry);
		}

		if (@$gapFeatures) {

		    $verbose && print "Gap(s) found in $inputFile\n";

		    ## pre-format new gap features
		    $newGaps = preformat_new_gap_features(@$gapFeatures);

		    if (@$newGaps) {
			$changedFile=1;
			foreach $newGapFt (@$newGaps) {
			    push(@first_part_of_entry, $newGapFt);
			}
		    }
		}

		# Add XX line in between FT and SQ lines
		@second_part_of_entry = ("XX\n", @second_part_of_entry);

		print WRITENEWDATA @first_part_of_entry;
		print WRITENEWDATA @second_part_of_entry;

		@first_part_of_entry  = ();
		@second_part_of_entry = ();
		$switch_array = 0;
	    }
	}
	
	if ($changedFile) {
	    $changedFiles{$inputFile} = 1;
	    if ((!$test_mode) || (!$backupReq)) {
		system("mv $inputFile $inputFile".".beforeGapUpdate.del");
	    }
	}
	
	if ((!$test_mode) || (!$backupReq)) {
	    system("mv $new_file $inputFile");
	}
	$changedFile = 0;
	
	close( READINPUT );
	close( WRITENEWDATA );
    }

    $verbose && print "Note: ".scalar(keys(%changedFiles))." file(s) have been updated with gap features.\nOriginal back ups for the updated files have been saved with the extension .beforeGapUpdate.del\n\n";
}

################################################################################
# make sure all the right arguments have been received

sub get_args(\@\@) {

    my ( $arg, $file, $errorFlag, $usage, @expanded_file_list );

    my $args = shift;
    my $inputFiles = shift;

    $usage = "USAGE: $0 [file]+\n\n"
	. "This script takes all the files in the current directory with the .fflupd/.ffl/.temp/.sub\n"
	. "suffix (whichever it can find, in that order of preference).\n"
        . "All input files containing sequences with gaps ('n's) in them will have gap features\n"
	. "inserted. Backups are made of the input files in case you want to revert back \n"
	. "(e.g. smith.temp.bak.del).\n\n"
	. "Running the script with the -v option will show you the files containing gaps.\n\n";

    # check the arguments for values
    foreach $arg ( @$args ) {

        if ( $arg =~ /^\-v(erbose)?/ ) {    # verbose mode
            $verbose = 1;
        }
        # no back up file made (for when script is called inside add_100n_gaps)
	elsif ( $arg =~ /\-nobackup/ ) {    
	    $backupReq = 0;
	}
	elsif ( $arg =~ /\-nostdoutput/ ) {    
	    $stdOutReq = 0;
	}
	elsif ( $arg =~ /(^[^-]+)/ ) {
	    push(@$inputFiles, $1);
	}
	elsif ( $arg =~ /\-t(est)?/ ) {
	    $test_mode = 1;
	}
	elsif ( $arg =~ /^\-h(elp)?/ ) {
	    die $usage;
	}
	else {
	    die "Unrecognised input: $arg\n\n".$usage;
	}
    }

    if (!$stdOutReq) {
	$verbose = 0;
    }

    if (@$inputFiles) {
	foreach $file (@$inputFiles) {

	    if ($file =~ /(\*|\?)/) {
		@expanded_file_list = glob($file);
		$file = "";
	    }
	    elsif (! -e $file) {
		$verbose && print "Error: $file does not exist\n";
		$errorFlag = 1;
	    }
	}

	if (@expanded_file_list) {
	    # scrunch up original file list

	    foreach $file (@$inputFiles) {
		if (($file ne "") && ($file =~ /(\*|\?)/)) {
		    push(@expanded_file_list, $file);
		}
	    }

	    @$inputFiles = ();
	    @$inputFiles = @expanded_file_list;
	}
    }

    if ($errorFlag) {
	exit;
    }

    if (!@$inputFiles) {
	get_input_files(@$inputFiles)
    }
}

################################################################################
# main function

sub main(\@) {

    my ( @inputFiles );

    my $args = shift;

    get_args(@$args, @inputFiles);

    update_files_with_gap_features( @inputFiles );
}

################################################################################
# Run the script

main(@ARGV);
 
