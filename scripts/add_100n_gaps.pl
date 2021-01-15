#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2007
#
#===============================================================================

use strict;
use SeqDBUtils2;
use File::Copy;

my $verbose;

################################################################################
# if a gaps of < or > 100 bp are found, shift the positions of the other features

sub modify_ft_positions(\@$$) {

    my ($ft, $wrappedLine, @joinPos, $newPos, $i, @tmp, $tmp);
    my ($rippleChanges);

    my $features = shift;
    my $startPos = shift;
    my $changeInFtPositons = shift;

    $startPos += 1;

    foreach $ft (@$features) {

	if ($ft =~ /^([^j]+join\(<?)((\d+\.\.>?\d+(,|\)))+)/) {

	    if ($4 !~ /\)/) {
		$wrappedLine = 1;
	    }

	    @tmp = split(/[,\)]/, $2);

	    foreach $tmp (@tmp) {
		push( @joinPos,  split(/\.\.>?/, $tmp));
	    }

	    for ($i=0; $i<@joinPos; $i++) {

		if (($rippleChanges) || ($joinPos[$i] > $startPos)) {
		    $newPos = $joinPos[$i] + $changeInFtPositons;

		    $ft =~ s/([^0-9])$joinPos[$i]([^0-9])/$1$newPos$2/;
		    $rippleChanges = 1;
		}
	    }
	    @joinPos = ();
	}
	elsif ($wrappedLine) {

	    if ($ft  =~ /((\d+\.\.>?\d+)(,|\)))+/) {
		push( @joinPos,  split(/\.\.>?/, $2) );
	    }

	    for ($i=0; $i<@joinPos; $i++) {

		if ( ($rippleChanges) || ($joinPos[$i] > $startPos) ) {

		    $newPos = $joinPos[$i] + $changeInFtPositons;

		    $ft =~ s/([^0-9])$joinPos[$i]([^0-9])/$1$newPos$2/;
		    $rippleChanges = 1;
		}
	    }

	    if ($ft =~ /\)/) {
		$wrappedLine = 0;
	    }
	    else {
		@joinPos = ();
	    }
	}
	elsif ($ft =~ /^(FT\s+\w+[^0-9]*)(\d+)(\.\.[^0-9]*)(\d+)(.*?)/) {

	    if ($2 > $startPos) {
		$ft = $1.($2+$changeInFtPositons).$3.($4+$changeInFtPositons).$5."\n";
	    }
	    elsif ($4 > $startPos) {
		$ft = $1.$2.$3.($4+$changeInFtPositons).$5."\n";
	    }
	}
    }
}

################################################################################
# calculate gap locations/lengths from sequence

sub resize_gaps_and_features(\@) {

    my ($line, $getSeqFlag, $seq, $seqLen, $nCount, $nPos, @startnPos);
    my ($currentNucleotide, $modified, $origSeqLen, $nSpanCounter);
    my (@features, @endnPos, $calcNSpan, $spanLen, $seqBeforeNs, $seqAfterNs);

    my $inputFileContents = shift;

    $getSeqFlag = 0;
    $modified = 0;

    foreach $line (@$inputFileContents) {

	if ( $line =~ /^FT/ ) {
	    push(@features, $line);
	}
	elsif ( $line =~ /^SQ / ) {
	    $getSeqFlag = 1;
	}
	elsif ( $getSeqFlag ) {
	    $seq .= $line;
	}
    }

    $seq =~ s/\/\///;
    $seq =~ s/[ \n\r\t]//g;
    $seq =~ s/\d+//g;
    $seq = lc($seq);

    $_ = $seq;
    $nCount = tr/n//;

    if ($nCount) {
	$seqLen = length($seq);
	$origSeqLen = $seqLen;

	$nSpanCounter = 0;
	for ($nPos=0; $nPos<$seqLen; $nPos++) {

	    $currentNucleotide = substr($seq, $nPos, 1);

	    if ($currentNucleotide eq "n") {

		if (! $startnPos[$nSpanCounter]) {
		    $startnPos[$nSpanCounter] = $nPos;
		}
		else {
		    $endnPos[$nSpanCounter] = $nPos;
		}

		# flag to say calc span when n's are no longer found
		$calcNSpan = 1;
	    }
	    elsif ($calcNSpan) {

		$spanLen = ($endnPos[$nSpanCounter] - $startnPos[$nSpanCounter]) + 1;

		$seqBeforeNs = substr($seq, 0, $startnPos[$nSpanCounter]);
		$seqAfterNs  = substr($seq, $endnPos[$nSpanCounter] + 1);

		if (($spanLen > 100) || (($spanLen > 20) && ($spanLen < 100))) {

		    $seq = $seqBeforeNs . ('n' x 100) . $seqAfterNs;
		    $seqLen = length($seq);
		    $nPos = $endnPos[$nSpanCounter] + (100 - $spanLen);

		    $nSpanCounter++;
		    $modified = 1;
		}

		$calcNSpan = 0;
		$startnPos[$nSpanCounter] = 0;
	    }
	}

	if ($modified) {
	    modify_ft_positions(@features, $startnPos[0], $seqLen - $origSeqLen);
	}
    }

    return (\$seq, \@features, $nCount);
}

################################################################################
# wipe pre-existing gaps from the input file data

sub delete_existing_gaps(\@) {

    my ( $line, $removeNextLine );

    my $inputFileContents = shift;


    # find pre-existing gap features and delete them
    foreach $line (@$inputFileContents) {
	if ( $line =~ /FT   gap.*/) {
	    $line = "";
	    $removeNextLine = 1;
	}
	elsif (($removeNextLine) && ($line =~ /estimated_length=/)) {
	    $line = "";
	    $removeNextLine = 0;
	}
	else {
	    $removeNextLine = 0;
	}
    }
}
################################################################################
# grab data, extract data and re-save data with new data included.

sub update_files_with_gap_features(\@) {

    my ( $inputFile, $line, @inputFileContents, $ft, $prevLine, @filesWithGaps );
    my ( $changedFileCounter, $backupFilename, $features, $gapsPresent );
    my ( $sequenceFlag, $seq, $newSeqLen, @updatedFiles );

    my $inputFiles = shift;
    
    $prevLine = "";
    $changedFileCounter = 0;

    foreach $inputFile (@$inputFiles) {

	open( READINPUT, "<$inputFile" ) || die "Cannot open the file $inputFile for reading: $!\n";
	@inputFileContents = <READINPUT>;
	close( READINPUT );

	delete_existing_gaps(@inputFileContents);

	($seq, $features, $gapsPresent) = resize_gaps_and_features(@inputFileContents);

	if ($gapsPresent) {
	    push(@filesWithGaps, $inputFile);
	    $gapsPresent = 0;

	    ## make back ups
	    $backupFilename = $inputFile.".bak.del";
	    if (! (-e  $backupFilename)) {
		copy( $inputFile, $backupFilename );
	    }

	    if ($verbose) {
		print "Gap(s) found in $inputFile\n";
	    }
	    
	    ## save new data
	    open( WRITEINPUT, ">$inputFile" ) || die "Cannot open the file $inputFile for writing: $!\n";

	    foreach $line (@inputFileContents) {

		if ($line =~ /^FT/) {
		    # don't write to file
		}
		elsif ($line =~ /^SQ/) {
		    print WRITEINPUT "SQ   Sequence $newSeqLen BP;\n";
		    $sequenceFlag = 1;
		}
		elsif ($line =~ /^(ID   \S+;.+?)\d+( BP\.)/) {
		    $newSeqLen = length($$seq);
		    print WRITEINPUT $1.$newSeqLen.$2;
		}
		elsif (($prevLine  =~ /^FT/) && ($line  !~ /^FT/)) {

		    # print new features to the file
		    foreach $ft (@$features) {
			print WRITEINPUT $ft;
		    }

		    print WRITEINPUT $line;
		}
		elsif ((!$sequenceFlag) && ($line ne "")) {
		    print WRITEINPUT $line;
		}
 
		$prevLine = $line;
	    }

	    print WRITEINPUT "$$seq\n//\n";
	    $sequenceFlag = 0;
	    
	    close( WRITEINPUT );
	    $changedFileCounter++;
	}
    }

    return(\@filesWithGaps);
}

################################################################################
# make sure all the right arguments have been received

sub get_args(\@\@) {

    my ( $arg, $file, $errorFlag, $usage );

    my $args = shift;
    my $inputFiles = shift;

$usage = "USAGE: $0 [file]+\n\n"
        . "This script will take embl-formatted input files listed on the command line\n"
	. "and if any n's are found in the sequence, these gaps are adjusted to gaps of\n"
	. "length 100 nt.  The original input file is saved to <inputfilename>.bak.del\n"
	. "and the recalculated features and sequence are saved to the input file name.\n"
	. "Features are sorted into the right order.\n"
	. "If not files are entered on the command line, the script will look for .fflupd\n"
	. "files in preference to .ffl files, in preference to .temp files, in preference\n"
	. "to .sub files and use those files found as input.\n\n";

    # check the arguments for values
    foreach $arg ( @$args ) {

        if ( $arg =~ /^\-v(erbose)?/ ) {    # verbose mode
            $verbose = 1;
        }
	elsif ( $arg =~ /(^[^-]+)/ ) {
	    push(@$inputFiles, $1);
	}
	elsif ( $arg =~ /^\-h(elp)?/ ) {
	    die $usage;
	}
	else {
	    die "Unrecognised input: $arg\n\n".$usage;
	}
    }

    if (@$inputFiles) {
	foreach $file (@$inputFiles) {
	    if (! -e $file) {
		print "Error: $file does not exist\n";
		$errorFlag = 1;
	    }
	}
    }

    if ($errorFlag) {
	exit;
    }

    if (!@$inputFiles) {
	get_input_files(@$inputFiles);
    }
}

################################################################################
# script creates gap features and puts them below the rest of the fts

sub add_gap_features(\@) {

    my ( $file );

    my $gappyFiles = shift;

    foreach $file (@$gappyFiles) {

	if (-e $file.".bak.del") {
	    system ("/ebi/production/seqdb/embl/tools/curators/scripts/add_gap_features.pl -nobackup -nostdoutput $file");
	}
	else {
	    system ("/ebi/production/seqdb/embl/tools/curators/scripts/add_gap_features.pl -nostdoutput $file");
	}
    }
}

################################################################################
# print the filecontents with new features to the output file

sub write_features_to_file($\@\@) {
	
    my ($line, $ft, $ftPrinted);

    my $updateFile = shift;
    my $ftInfo = shift;
    my $fileContents = shift;


    open(WRITERECALCFTS, ">$updateFile") || die "Cannot open file: $!\n";

    foreach $line (@$fileContents) {

	if ($line !~ /^FT/) {
	    if ($line ne "") {
		print WRITERECALCFTS $line;
	    }
	}
	else {
	    if (!$ftPrinted) {
		foreach $ft (@$ftInfo) {
		    print WRITERECALCFTS $ft;
		}

		$ftPrinted = 1;
	    }
	}
    }

    close(WRITERECALCFTS);
}

################################################################################
# make arrays of details from the feature list, for cleaner processing

sub put_fts_and_gaps_in_arrays(\@\@\@\@\@\@) {

    my ($i, $getQualifiers, $getGapQualifiers, $ftNum, $gapNum);

    my $fileContents = shift;
    my $ftInfo = shift;
    my $gapInfo = shift;
    my $gapType = shift;
    my $gapStart = shift;
    my $gapEnd = shift;

    $ftNum = 0;
    $gapNum = 0;
    @$ftInfo = ();
    @$gapInfo = ();

    # put features into array and gaps into another array
    for ($i=0; $i<@$fileContents; $i++) {
	
	if ($getQualifiers) {
		
	    if (($$fileContents[$i] =~ /^FT/) &&
		($$fileContents[$i] !~ /^FT   (\w+) +.+/)) {
		
		$$ftInfo[$ftNum] .= $$fileContents[$i];
	    }
	    else {
		$getQualifiers = 0;
		$ftNum++;
	    }
	}
	elsif ($getGapQualifiers) {

	    if (($$fileContents[$i] =~ /^FT/) &&
		($$fileContents[$i] !~ /^FT   (\w+) +.+/)) {
		
		$$gapInfo[$gapNum] .= $$fileContents[$i];
	    }
	    else {
		$getGapQualifiers = 0;
		$gapNum++;
	    }
	}

	if ((!$getQualifiers) && ($$fileContents[$i] =~ /^FT   (\w+) +<?(\d+)\.\.(\d+)/)) {

	    if ($1 ne "gap") {
		$getQualifiers = 1;

		$$ftInfo[$ftNum] = $$fileContents[$i];
	    }
	    else {
		$getGapQualifiers = 1;

		$$gapInfo[$gapNum] = $$fileContents[$i];
		    
		$$gapType[$gapNum]  = $1;
		$$gapStart[$gapNum] = $2;
		$$gapEnd[$gapNum]   = $3;

		$$fileContents[$i] = "";
	    }
	}
	# get fts such as 'CDS  join'
	elsif ((!$getQualifiers) && ($$fileContents[$i] =~ /^FT   (\w+) +.+/)) {
	    $getQualifiers = 1;
	    
	    $$ftInfo[$ftNum] = $$fileContents[$i];
	}
    }
}

################################################################################
# insert new feature or gap into middle of feature array

sub insert_ft_into_ft_list($\@$) {

    my ($i, @newFtList);

    my $insertAtPosn = shift;
    my $readArray = shift;
    my $ftText = shift;

    for ($i=0; $i<$insertAtPosn; $i++) {
	push(@newFtList, $$readArray[$i]);
    }

    push(@newFtList, $ftText);


    for ($i=$insertAtPosn; $i<@$readArray; $i++) {
	push(@newFtList, $$readArray[$i]);
    }

    return(@newFtList);
}

################################################################################
# reorder new gap features and modify nt positions in existing fts

sub integrate_gap_features(\@) {

    my ($file, $i,  @fileContents, $getQualifiers, $newFt, $moveToNextGap);
    my (@ftInfo, @ftType, @ftStart, @ftEnd, $ftNum, $tmp, $getGapQualifiers);
    my (@gapInfo, @gapType, @gapStart, @gapEnd, $gapNum, $currentFtEnd);
    my ($newFtStart, $newFtEnd);

    my $gappedFiles = shift;

    $moveToNextGap = 0;

    foreach $file (@$gappedFiles) {

	open(READUPDFILE, "<$file") || die "Cannot open $file:$!\n";
	@fileContents = <READUPDFILE>;
	close(READUPDFILE);

	put_fts_and_gaps_in_arrays(@fileContents, @ftInfo, @gapInfo, @gapType, @gapStart, @gapEnd);

        # slot in gap fts and recalc feature positions
	for ($gapNum=0; $gapNum<@gapInfo; $gapNum++) {

	    for ($ftNum=0; $ftNum<@ftInfo; $ftNum++) {

		if ($ftInfo[$ftNum] =~ /^FT   (\w+) +<?(\d+)\.\.(\d+)/) {
		    $ftType[$ftNum]  = $1;
		    $ftStart[$ftNum] = $2;
		    $ftEnd[$ftNum]   = $3;
		} 
		elsif ($ftInfo[$ftNum] =~ /^FT   (\w+) +.+/) {
		    $ftType[$ftNum] = $1;
		}

		if (($ftType[$ftNum] ne "source") && ($ftType[$ftNum] ne "CDS") &&
		    ($ftInfo[$ftNum] !~ /^FT   gap +/)) {

		    # if gap start lies inside current feature
		    if (($gapStart[$gapNum] > $ftStart[$ftNum]) &&
			($gapStart[$gapNum] < $ftEnd[$ftNum])) {

			$currentFtEnd = $gapStart[$gapNum] - 1;
			$ftInfo[$ftNum] =~ s/(\.\.>?)(\d+)/$1$currentFtEnd/;

			@ftInfo = insert_ft_into_ft_list(($ftNum+1), @ftInfo, $gapInfo[$gapNum]);


			if ($ftInfo[($ftNum+2)] =~  /^FT   (\w+) +<?(\d+)\.\.(\d+)/) {
			    $ftStart[($ftNum+2)] = $2;
			}

			# insert extra feature after gap, if required
			if ($currentFtEnd < $ftStart[($ftNum+2)]) {

			    $newFt = $ftInfo[$ftNum];

			    $newFtStart = $gapEnd[$gapNum] + 1;
			    $newFt =~ s/(\d+)(\.\.>?)/$newFtStart$2/;

			    $newFtEnd = $ftStart[($ftNum+2)] - 1;
			    $newFt =~ s/(\.\.>?)(\d+)/$1$newFtEnd/;

			    if ($newFtStart >= $newFtEnd) {
				# do nothing
			    }
			    else {
				@ftInfo = insert_ft_into_ft_list(($ftNum+2), @ftInfo, $newFt);
			    }
			
			    $moveToNextGap = 1;
			}

		    }
		    # if gap span is exactly the same as feature span
		    elsif ((($gapStart[$gapNum] == $ftStart[$ftNum]) && 
			    ($gapEnd[$gapNum] == $ftEnd[$ftNum])) || 
			   (($gapStart[$gapNum] < $ftStart[$ftNum]) && 
			    ($gapStart[$gapNum] > $ftEnd[$ftNum]))) {

			$ftInfo[$ftNum] = $gapInfo[$gapNum];

			$moveToNextGap = 1;
		    }
		    # if gap starts before feature
		    elsif (($gapStart[$gapNum] < $ftStart[$ftNum]) &&
			   ($gapEnd[$gapNum] < $ftEnd[$ftNum])) {

			$tmp = $gapEnd[$gapNum] + 1;
			$ftInfo[$ftNum] =~ s/(\d+)(\.\.>?)/$tmp$2/;
			$moveToNextGap = 1;
		    }


		    if ($moveToNextGap) {
			$ftNum = @ftInfo;
			$moveToNextGap = 0;
		    }
		}
	    }
	}

	write_features_to_file($file, @ftInfo, @fileContents);
    }
}

################################################################################
# main function

sub main(\@) {

    my ( @inputFiles, $filesWithGaps);

    my $args = shift;

    get_args(@$args, @inputFiles);

    print "\nUpdating input files with gap features:\n" . scalar(@inputFiles) . " file(s) found\n";

    ($filesWithGaps) = update_files_with_gap_features( @inputFiles );

    if (@$filesWithGaps) {
	add_gap_features(@$filesWithGaps);
    }

    print "Note: Unchanged copies of the input files have been saved with the extension .bak.del\n"
    . "  ".scalar(@$filesWithGaps)." file(s) have had their gaps and features updated.\n\n";

    if (@$filesWithGaps) {
	integrate_gap_features(@$filesWithGaps);
    }
}

################################################################################
# Run the script

main(@ARGV);
