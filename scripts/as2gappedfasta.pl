#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/as2gappedfasta.pl,v 1.7 2011/11/29 16:33:37 xin Exp $
#
#  (C) EBI 2007
#
# This script generates a gapped fasta file from a file of AS lines.
#
###############################################################################

use strict;
use SeqDBUtils2;
use RevDB;
use Cwd;
use Data::Dumper;


my $verbose = 0;
my $sameAccsOnOneLine = 1;

#-------------------------------------------------------------------------------
# Usage   : usage(@ARGV)
# Description: populates global variables with commandline arguments (plus prints
# help text
# Return_type :none.  Global variable values are set
# Args    : @$args : list of arguments from the commandline.
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub usage(\@) {

    my ( $usage, $arg, $inputFile, $separateFlag, $togetherFlag );

    my $args = shift;
    my $inputFiles = shift; # empty list

    $usage =
    "\n USAGE: $0 [file] [-v(erbose)] [-h] \n\n"
  . " PURPOSE: Checks .temp files in current directory and find AS lines.\n"
  . "         All sequences mentioned on AS lines are formed into a blast\n"
  . "         database. The TPA sequence is blasted and all hits above the\n"
  . "         cutoff score are taken. For each hit that is not nested within\n"
  . "         a higher scoring hit, an AS line is made.\n"
  . "         The coverage of each section of the TPA sequence is reported.\n\n"
  . "         By default, AS lines containing the same accession in the same\n"
  . "         direction appear together in the same sequence in the jalview output.\n\\" 
  . " -h(elp)             This help message\n"
  . " -v(erbose)          Verbose output\n"
  . " file                File containing AS lines to put into gapped fasta\n"
  . "                     format\n"
  . " -s(eparate)         Display AS lines of the same accession and direction\n"
  . "                     as different sequences in the jalview output.\n"
  . " -t(ogether)         Display AS lines of the same accession and direction\n"
  . "                     in the same (gapped) sequence in the jalview output.\n"
  . "\n";

    foreach $arg (@$args) {

	if ( $arg =~ /-v(erbose)?/i ) {
	    $verbose = 1;
	}
	elsif ( $arg =~ /\-h(elp)?/i ) {
	    die $usage;
	}
	elsif ( $arg =~ /(^[^-]+)/ ) {
	    $inputFile = $1;
	}
	elsif ( $arg =~ /-s(eparate)?/i ) {
	    $sameAccsOnOneLine = 0;
	    $separateFlag = 1;
	}
	elsif ( $arg =~ /-t(ogether)?/i ) {
	    $sameAccsOnOneLine = 1;
	    $togetherFlag = 1;
	}
	else {
	    die "\nI do not understand the argument \"$arg\"\n".$usage;
	}
    }

    if ($separateFlag && $togetherFlag) {
	$sameAccsOnOneLine = 1;
	print "Warning: Both the -separate and -together options were both used.\n"
	    . "The AS lines of the same accession and direction will be displayed\n"
	    . "within the same (gapped) sequence in the jalview results (default\n"
	    . "behaviour).\n";
    }

    if ( !$inputFile ) {
	die $usage;
    }
    elsif (! -e $inputFile ) {
	die "'$inputFile' is not recognised as a file.\nExiting script...\n";
    }
    elsif ((! -T $inputFile) || (! -r $inputFile)) {
	die "'$inputFile' is not readable or is not a text file.\nExiting script...\n";
    }

    return($inputFile);
}

#-------------------------------------------------------------------------------
# Usage   : parse_flatfiles(@$inputFiles, @$submission, %$associateSeqFiles)
# Description: parse the input files in the ds directory and populate a list
# Return_type : none.  A list is populated via it's reference
# Args    : @$inputfiles : reference to a list of all input files 
#           @$submission : reference to a list of details of the submission
#           %$associateSeqFiles : hash of accession:filename
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub parse_flatfile($\@\%\%) {

    my ( $i, $line, @rangeList, $acc, $accStr, @splitAccs, $cwd, $saveSeq );
    my ( $distinctASacc, $primSpanLen, $tpaSpanLen, $dupPrimacc, $dupIndexNum );
    my ( $numSpans, $span, $j, $newComp );

    my $inputFile = shift;
    my $distinctASseqs = shift;
    my $associateSeqFiles = shift;
    my $tpaSequence = shift;

    $cwd = cwd;

    my_open_FH( \*ASFILE, "<$cwd/$inputFile" );
    
    $i=0;
    while ($line = <ASFILE>) {

	if ($line =~ /^\/\//) {
	    last;
	}
	elsif ($saveSeq) {
	    $$tpaSequence{seq} .= $line;
	}
	# normal AS line e.g. AS   1-41           AC108564.5           2326-2366    c
	elsif ( $line =~ /^AS\s+(\d+)-(\d+)\s+(\S+)\s+((\d+)-(\d+)|not_available)\s*([Cc]?)/ ) {

	    if ($sameAccsOnOneLine) {
		for ($j=0; $j<@$distinctASseqs; $j++) {

		    if ($$distinctASseqs[$j][0]{primacc} eq $3) {

			if (! defined($$distinctASseqs[$j][0]{comp})) {
			    $$distinctASseqs[$j][0]{comp} = "";
			}
			if (! defined($7)) {
			    $newComp = "";
			}
			else {
			    $newComp = $7;
			}

			if ($$distinctASseqs[$j][0]{comp} eq $newComp) {
			    $dupPrimacc = 1;
			    $dupIndexNum = $j;
			    $numSpans = $$distinctASseqs[$j][0]{num_spans};
			    last;
			}
		    }
		}
	    }

            # if accession and complementary flag are the same, add extra info 
	    if ($dupPrimacc) {
		$$distinctASseqs[$dupIndexNum][$numSpans]{as_start} = $1;
		$$distinctASseqs[$dupIndexNum][$numSpans]{as_end} = $2;
		$$distinctASseqs[$dupIndexNum][$numSpans]{prim_start} = $5;
		$$distinctASseqs[$dupIndexNum][$numSpans]{prim_end} = $6;

		$$distinctASseqs[$dupIndexNum][0]{num_spans}++;

		$i = $i - 1;
	    }
	    else {
		$$associateSeqFiles{uc($3)} = "";
		$$distinctASseqs[$i][0]{as_start} = $1;
		$$distinctASseqs[$i][0]{as_end} = $2;
		$$distinctASseqs[$i][0]{primacc} = $3;
		$$distinctASseqs[$i][0]{prim_start} = $5;
		$$distinctASseqs[$i][0]{prim_end} = $6;
		$$distinctASseqs[$i][0]{num_spans} = 1;
		
		if ($7) {
		    $$distinctASseqs[$i][0]{comp} = $7;
		} 
		else {
		    $$distinctASseqs[$i][0]{comp} = "";
		}
	    }

	    if ($dupPrimacc) {

		for ($j=0; $j<$$distinctASseqs[$i][0]{num_spans}; $j++) {

		    $primSpanLen = $$distinctASseqs[$dupIndexNum][$j]{prim_end} - $$distinctASseqs[$dupIndexNum][$j]{prim_start};
		    $tpaSpanLen  = $$distinctASseqs[$dupIndexNum][$j]{as_end} - $$distinctASseqs[$dupIndexNum][$j]{as_start};

		    if ($primSpanLen != $tpaSpanLen) {
			print "Warning: In AS line number ".($dupIndexNum+1)." the length of the primary span ($primSpanLen bp) does not match the length of the TPA span ($tpaSpanLen bp).  This means this span may be out of alignment in the generated fasta file.\n\n";
		    }
		}	 
	    }
	    else {
		$primSpanLen = $$distinctASseqs[$i][0]{prim_end} - $$distinctASseqs[$i][0]{prim_start};
		$tpaSpanLen  = $$distinctASseqs[$i][0]{as_end} - $$distinctASseqs[$i][0]{as_start};

		if ($primSpanLen != $tpaSpanLen) {
		    print "Warning: In AS line number ".($i+1)." the length of the primary span ($primSpanLen bp) does not match the length of the TPA span ($tpaSpanLen bp).  This means this span may be out of alignment in the generated fasta file.\n\n";
		}
	    }

	    $i++;
	}
	elsif ($line =~ /^SQ\s+Sequence (\d+) BP/) {
	    $$tpaSequence{seqlen} = $1;
	    $saveSeq=1;
	}

	$dupPrimacc = 0;
    }

    # $$tpaSequence{seq} will have no value if the input file 
    # contains no tpa sequence
    if ($$tpaSequence{seq}) {
	$$tpaSequence{seq} =~ s/\d+//g;
	$$tpaSequence{seq} =~ s/\s+//g;
	chomp($$tpaSequence{seq});
    }

    #get max AS line end number
    if (! $$tpaSequence{seqlen}) {

	$$tpaSequence{seqlen} = 0;

	foreach $distinctASacc (@$distinctASseqs) {

	    foreach $span (@$distinctASacc) {
		if ($span->{as_end} > $$tpaSequence{seqlen}) {
		    $$tpaSequence{seqlen} = $span->{as_end};
		}
	    }
	}
    }

    #print Dumper(\$distinctASseqs);
    #exit;

    close(ASFILE);
}

#-------------------------------------------------------------------------------
# Usage   :  make_fasta_file($newFilename, $temp_dir, %$associateSeqFile, $comp)
# Description: runs readseq on an embl file to return the sequence in a file in 
#              fasta format
# Return_type: none
# Args    : $newFilename: file into which fasta sequence is written
#         : $temp_dir: directory were embl/TI files are saved
#         : %$associateSeqFile: reference containing filename of embl/TI file
#         : $comp: either 'C' or empty string denoting if sequence is complementary
# Caller  : create_gapped_fasta_seq
#-------------------------------------------------------------------------------
sub make_fasta_file($$$$) {

    my ($readseq, $cmd);

    my $outputFile = shift;
    my $temp_dir = shift;
    my $associateSeqFile = shift;
    my $comp = shift;

    $readseq = "/ebi/production/extsrv/data/idata/appbin/READSEQ/readseq.jar";
    $cmd = "/sw/arch/bin/java -jar $readseq -f=Fasta -o=$outputFile $temp_dir/$associateSeqFile";

    if ($comp ne "") {
	$cmd .= " -reverse";
    }
    
    $verbose && print "running $cmd\n";
    
    system($cmd);
}
#-------------------------------------------------------------------------------
# Usage   : 
# Description: 
# Return_type: 
# Args    : 
#         : \$distinctSeq: reference to a reference of the details of a single AS line
# Caller  :
#-------------------------------------------------------------------------------
sub get_span_display_order(\%\$) {

    my ( $i, @sortOrder );

    my $orderingHash = shift;
    my $distinctSeq = shift;

    for ($i=0; $i<100; $i++) {
	if ( defined($$distinctSeq->[$i]->{as_start}) ) {
	    $$orderingHash{$i} = $$distinctSeq->[$i]->{as_start};
	}
	else {
	    last;
	}
    }

    @sortOrder = sort {$$orderingHash{$a} <=> $$orderingHash{$b}} keys %$orderingHash;

    return(\@sortOrder);
}

#-------------------------------------------------------------------------------
# Usage   : 
# Description: 
# Return_type: 
# Args    : 
#         : \$distinctSeq: reference to a reference of the details of a single AS line
# Caller  :
#-------------------------------------------------------------------------------
sub check_if_spans_overlap(\$\@) {

    my ( $i );

    my $distinctSeq = shift;
    my $indexOrder = shift;

    for ($i=0; $i<@$indexOrder; $i++) {

	if (($i+1) < @$indexOrder) {

	    if ($$distinctSeq->[ $$indexOrder[$i+1] ]->{as_start} < 
		$$distinctSeq->[ $$indexOrder[$i] ]->{as_end}) {
		print "Warning: span "
		    . $$distinctSeq->[ $$indexOrder[$i] ]->{as_start} . "-"
		    . $$distinctSeq->[ $$indexOrder[$i] ]->{as_end}
	            . " of accession $$distinctSeq->[0]->{primacc} overlaps with span "
		    . $$distinctSeq->[ $$indexOrder[$i+1] ]->{as_start} . "-"
		    . $$distinctSeq->[ $$indexOrder[$i+1] ]->{as_end}
		    . " on the TPA.\n";
	    }

#	    if ($$distinctSeq->[ $$indexOrder[$i+1] ]->{prim_start} < 
#		$$distinctSeq->[ $$indexOrder[$i] ]->{prim_end}) {
#		
#		print "Warning: span "
#		    . $$distinctSeq->[ $$indexOrder[$i] ]->{prim_start} . "-"
#		    . $$distinctSeq->[ $$indexOrder[$i] ]->{prim_end}
#                    ." of accession $$distinctSeq->[0]->{primacc} overlaps with span "
#		    . $$distinctSeq->[ $$indexOrder[$i+1] ]->{prim_start} . "-"
#		    . $$distinctSeq->[ $$indexOrder[$i+1] ]->{prim_end}
#                    . " within the primary accession.\n";
#	    }
	}
    }
}

#-------------------------------------------------------------------------------
# Usage   : add_gaps_to_sequence($readseqFile, $tpaSeqlLen, \$ASline)
# Description: pads the sequence with '-' characters
# Return_type: reference to a scalar containing a (padded) sequence
# Args    : $readseqFile: file containing fasta sequence
#         : $tpaSeqLen: length of TPA sequence
#         : \$distinctSeq: reference to a reference of the details of a single AS line
# Caller  : create_gapped_fasta_seq
#-------------------------------------------------------------------------------
sub add_gaps_to_sequence($$\$) {

    my ($fastaSeq, $snippedSeq, $primLen, $gappedSeq, %orderingHash);
    my ($spanIndexOrder, $i, $tmp);

    my $outputFile = shift;
    my $tpaSeqLen = shift;
    my $distinctSeq = shift;

    # get sequence
    my_open_FH( \*FASTAFILE, "<$outputFile" );
    $fastaSeq = do{local $/; <FASTAFILE>};
    $fastaSeq =~ s/^>[^\n]+\n//g; # remove fasta header
    $fastaSeq =~ s/\n+//g;
    close(FASTAFILE);

    if ($$distinctSeq->[0]->{num_spans} == 1) {

	$primLen = ($$distinctSeq->[0]->{prim_end} - $$distinctSeq->[0]->{prim_start}) + 1;


	# if sequence is complementary, recalc prim_start and prim_end
	if ($$distinctSeq->[0]->{comp} ne "") {
	    $$distinctSeq->[0]->{prim_end} = ($$distinctSeq->[0]->{seqlen} - $$distinctSeq->[0]->{prim_start}) +2;
	    $$distinctSeq->[0]->{prim_start} = ($$distinctSeq->[0]->{prim_end} - $primLen);
	}

	# carve out primary span
	$snippedSeq = substr($fastaSeq, ($$distinctSeq->[0]->{prim_start} - 1), $primLen);
	$gappedSeq = ("-" x ($$distinctSeq->[0]->{as_start} - 1)) . $snippedSeq . ("-" x ($tpaSeqLen - $$distinctSeq->[0]->{as_end}));
    }
    else {

	$spanIndexOrder = get_span_display_order(%orderingHash, $$distinctSeq);

	check_if_spans_overlap($$distinctSeq, @$spanIndexOrder);

        # left pad spans
	for ($i=0; $i<$$distinctSeq->[0]->{num_spans}; $i++) {

	    $primLen = ($$distinctSeq->[ $$spanIndexOrder[$i] ]->{prim_end} - $$distinctSeq->[ $$spanIndexOrder[$i] ]->{prim_start}) + 1;


	    # if sequence is complementary, recalc prim_start and prim_end
	    if ($$distinctSeq->[0]->{comp} ne "") {
		$$distinctSeq->[ $$spanIndexOrder[$i] ]->{prim_end} = ($$distinctSeq->[0]->{seqlen} - $$distinctSeq->[ $$spanIndexOrder[$i] ]->{prim_start}) +2;
		$$distinctSeq->[ $$spanIndexOrder[$i] ]->{prim_start} = ($$distinctSeq->[ $$spanIndexOrder[$i] ]->{prim_end} - $primLen);
	    }


            # carve out primary span
	    $snippedSeq = substr($fastaSeq, ($$distinctSeq->[ $$spanIndexOrder[$i] ]->{prim_start} - 1), $primLen);

	    if (!$i) {
		$gappedSeq .= ("-" x ($$distinctSeq->[ $$spanIndexOrder[$i] ]->{as_start}  - 1)) . $snippedSeq;
	    }
	    else {
		$gappedSeq .= ("-" x ($$distinctSeq->[ $$spanIndexOrder[$i] ]->{as_start} - $$distinctSeq->[ $$spanIndexOrder[$i-1] ]->{as_end} - 1)) . $snippedSeq;
	    }
	}

        #right pad last span
        $gappedSeq .= ("-" x ($tpaSeqLen - $$distinctSeq->[ $$spanIndexOrder[-1] ]->{as_end}));
    }

    return(\$gappedSeq);
}

#-------------------------------------------------------------------------------
# Usage   : get_associate_seq_length($temp_dir, $seqFileName, $distinctSeq)
# Description: gets length of associate sequence from assoc. sequence file
# Return_type: sequence length (integer)
# Args    : $temp_dir: directory containing sequence files
#         : $seqFileName: file name of sequence file
# Caller  : create_gapped_fasta_seq
#-------------------------------------------------------------------------------
sub get_associate_seq_length($$) {

    my ($line, $seqlen, $isTI);

    my $temp_dir = shift;
    my $associateSeqFile = shift;

    my_open_FH( \*ASSOCSEQFILE, "<$temp_dir/$associateSeqFile");

    while ($line = <ASSOCSEQFILE>) {

	if ($isTI) {
	    $line =~ s/\s+//g;
	    $seqlen += length($line);
	}
	elsif ($line =~ /^>TI\d+/i) {
	    $isTI = 1;
	}
	elsif ($line =~ /^ID([^;\n]+;)+ *(\d+) BP/) {
	    $seqlen = $2;
	    last;
	}
    }

    close (ASSOCSEQFILE);

    return($seqlen);
}

#-------------------------------------------------------------------------------
# Usage   : create_gapped_fasta_seq($temp_dir, %associateSeqFiles, @distinctSeqs, $tpaSeqLen, $gappedFastaFile)
# Description: creates and writes gapped fasta sequences to a file
# Return_type: none
# Args    : $temp_dir: directory containing sequence files
#           %associateSeqFile: file names of sequence files
#           @distinctSeqs: AS line details
#           $tpaSeqLen: length of TPA sequence
#           $gappedFastaFile: name of file to save gapped fasta seq into
# Caller  : main function
#------------------------------------------------------------------------------
sub create_gapped_fasta_seq($\%\@$$) {

    my ($distinctSeq, $readseqFile, $gappedSeq);

    my $temp_dir = shift;
    my $associateSeqFiles = shift;
    my $distinctSeqs = shift;
    my $tpaSeqLen = shift;
    my $gappedFastaFile = shift;

    my_open_FH( \*GAPPEDFASTAFILE, ">>$gappedFastaFile" );

    foreach $distinctSeq (@$distinctSeqs) {

	if ($distinctSeq->[0]->{comp}) {
	    $readseqFile = "$temp_dir/".$distinctSeq->[0]->{primacc}.".comp.temp.fasta";
	}
	else {
	    $readseqFile = "$temp_dir/".$distinctSeq->[0]->{primacc}.".temp.fasta";
	}

	# make fasta file
	if (! -e $readseqFile) {
	    make_fasta_file($readseqFile, $temp_dir, $$associateSeqFiles{ $distinctSeq->[0]->{primacc} }, $distinctSeq->[0]->{comp});
	}
	else {
	    $verbose && print "reusing $readseqFile\n";
	}

	# get seq length of comp associate seq for position recalc 
	if ($distinctSeq->[0]->{comp} ne "") {
	    $distinctSeq->[0]->{seqlen} = get_associate_seq_length($temp_dir, $$associateSeqFiles{ $distinctSeq->[0]->{primacc} });
	}

	# returns reference to a sequence (coz it might be big)
	$gappedSeq = add_gaps_to_sequence($readseqFile, $tpaSeqLen, $distinctSeq);

 
	print GAPPEDFASTAFILE ">$$associateSeqFiles{ $distinctSeq->[0]->{primacc} }";

	if ($distinctSeq->[0]->{comp} ne "") {
	    print GAPPEDFASTAFILE " C";
	}

	print GAPPEDFASTAFILE "\n$$gappedSeq\n\n";
    }

    close(GAPPEDFASTAFILE);
}

#-------------------------------------------------------------------------------
# Usage   : save_tpa_to_gapped_fasta_file(%tpaSequence, $gappedFastaFile)
# Description: saves TPA sequence in fasta format to another file
# Return_type: none
# Args    : %tpaSequence: hash containig details of tpa sequence
#         : $gappedFastaFile: filename to save TPA sequence to
# Caller  : main function
#-------------------------------------------------------------------------------
sub save_tpa_to_gapped_fasta_file(\%$$) {

    my $tpaSequence = shift;
    my $temp_dir = shift;
    my $gappedFastaFile = shift;

    open( GAPPEDFILE, ">$gappedFastaFile" );
    print GAPPEDFILE ">TPA sequence($$tpaSequence{seqlen} bp)\n$$tpaSequence{seq}\n";
    close(GAPPEDFILE);
}

#-------------------------------------------------------------------------------
# Usage   : startJalview($gappedFastaFileName);
# Description: asks if jalview should be opened.  If so, modify jalview properties
# Return_type: none
# Args    : $gappedFastaFile: file to display in jalview
# Caller  : main function
#-------------------------------------------------------------------------------
sub startJalview($) {

    my ($answer, @lines, $line);

    my $gappedFastaFilePath = shift;

    print "Do you want to open this file in Jalview? ";
    $answer = <STDIN>;

    if ($answer =~ /y(es)?/i) {
	my_open_FH( \*READJALVIEWFILE, "<".$ENV{HOME}."/.jalview_properties" );

	@lines = <READJALVIEWFILE>;

	foreach $line (@lines) {
	    if ($line =~ /^STARTUP_FILE=/) {
		$line = "STARTUP_FILE=$gappedFastaFilePath\n";
		last;
	    }
	}
	close(READJALVIEWFILE);

	my_open_FH( \*WRITEJALVIEWFILE, ">".$ENV{HOME}."/.jalview_properties" );
	print WRITEJALVIEWFILE @lines; 
	close(WRITEJALVIEWFILE);
	
	print "\nOpening Jalview...\n";

	system('/ebi/production/seqdb/embl/tools/curators/bin/jalview/Jalview &');
    }
    else {
	print "\nNB If you want to open this script in Jalview at any point, enter: "
	    . "'jalview &'\n"
	    . "...and then open $gappedFastaFilePath\n"
	    . "from within Jalview (File menu/Input Alignment/from File...)\n\n"
	    . "Exiting script...\n\n";
    }
}
#-------------------------------------------------------------------------------
# Usage   : main(@ARGV)
# Description: contains the run order of the script
# Return_type: none
# Args    : @ARGV command line arguments
# Caller  : this script
#------------------------------------------------------------------------------
sub main(\@) {

    my ( $inputFile, $temp_dir, $rev_db, %associateSeqFiles, $acc );
    my ( $distinctSeq, %tpaSequence, $gappedFastaFile, $cwd, @distinctASseqs );

    my $args = shift;

    $inputFile = usage(@$args);

    # create directory to store sequence files
    $cwd = cwd;
    $temp_dir = $cwd.'/tpav_tmp.del';
    if (! (-e $temp_dir) ) {
        mkdir $temp_dir;
    }

    # %associateSeqFiles: hash of AC.version -> entry file location
    parse_flatfile($inputFile, @distinctASseqs, %associateSeqFiles, %tpaSequence);

    # connect to the revision database
    $rev_db = RevDB->new('rev_select/mountain@erdpro');

    foreach $acc (keys %associateSeqFiles) {
        $associateSeqFiles{$acc} = grab_entry($rev_db, $temp_dir, 0, $acc, 0, 1);
    }

    # disconnect from the revision database
    $rev_db->disconnect();

    $gappedFastaFile =  $inputFile.".fasta";

    if (-e $gappedFastaFile) {
	system("rm $gappedFastaFile");
    }

    if ($tpaSequence{seq}) {
	save_tpa_to_gapped_fasta_file(%tpaSequence, $temp_dir, $gappedFastaFile);
    }

    create_gapped_fasta_seq($temp_dir, %associateSeqFiles, @distinctASseqs, $tpaSequence{seqlen}, $gappedFastaFile);

    print "\nThe associate sequences have been stored in this gapped fasta file: $gappedFastaFile\n\n";

    startJalview("$cwd/$gappedFastaFile");
}

main(@ARGV);
