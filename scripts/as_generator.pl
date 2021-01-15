#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/as_generator.pl,v 1.33 2011/11/29 16:33:37 xin Exp $
#
#  (C) EBI 2007
#
# This script is an AS line generator for EMBL TPA submissions.  
#
###############################################################################

use strict;
use RevDB;
use DBI;
use SeqDBUtils2;
use Cwd;
use LWP::UserAgent;
use Data::Dumper;
use Bio::SearchIO;    # blast parsing module


# global variables
my ( $opt_connStr, %organism );

my $wuBlastDir = "/ebi/extserv/bin/wu-blast"; 
my $seqret     = "/ebi/extserv/bin/emboss/bin/seqret";

my $scoreLimit      = 100; # default cutoff score
my $minimumIdentity = 0.9; # default minimum percentage identity
my $minimumLength   = 0;   # default minimum length of hits allowed in results
my $gapPenalty      = -4;  # default gap penalty for nucleotides
my $gaps            = 0;   # if gaps=1 a gapped blast will be run
my $tsa             = 0;
my $verbose         = 0;
my $separator       = "\n#####################################################################\n";
my $pwd             = cwd; # current working directory
my $blastableDir    = $pwd . "/align_tpav.tpav_blastable_db.del";
my $logFile         = "asgen.log";


#-------------------------------------------------------------------------------
# Usage   : usage(@ARGV)
# Description: populates global variables with commandline arguments (plus prints
# help text
# Return_type :none.  Global variable values are set
# Args    : @$args : list of arguments from the commandline.
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub usage(\@\@) {

    my ( $usage, $arg, $file );

    my $args = shift;
    my $inputFiles = shift; # empty list

    $usage =
    "\n USAGE: $0 [-tsa] [-s={score}] [-l={length}] [-i={identity}] [-p(enalty)={gap penalty})] [-gaps] [-nogaps] [-v] [-h] [TPA filenames]\n\n"
  . " PURPOSE: Checks .temp files in current directory and find AS lines.\n"
  . "         All sequences mentioned on AS lines are formed into a blast\n"
  . "         database. The TPA/TSA sequence is blasted and all hits above the\n"
  . "         cutoff score are taken. For each hit that is not nested within\n"
  . "         a higher scoring hit, an AS line is made.\n"
  . "         The coverage of each section of the TPA/TSA sequence is reported.\n\n"
  . " -h(elp)             This help message\n"
  . " -v(erbose)          Verbose output\n"
  . " -tsa                TSA mode: 1) TSA's don't allow gaps (TPA gaps can be up to 50bp)\n"
  . "                     2) LOCAL_SPAN is used in the AH line rather than TPA_SPAN\n"
  . " -s(core)=<value>    Cutoff score (default = $scoreLimit)\n"
  . " -l(ength)=<value>     Minimum length of blast aligned sequence to be\n"
  . "                     allowed into the AS lines generated (default = $minimumLength)\n"
  . " -i(dentity)=<value>   Minimum sequence identity of a hit to be allowed\n"
  . "                     into the AS lines generated. Acceptable percentage\n"
  . "                     formats: 0.9, 90 or 90% (default = $minimumIdentity)\n"
  . " -p(enalty)=<value>  Gap penalty.  Default is -4.\n"
  . " -gaps               Allow a gapped blast to be run (by default an ungapped\n"
  . "                     blast is run).\n"
  . " -nogaps             Allow an ungapped blast to be run (this is default behaviour)\n"
  . " TPA Filenames       One or more filenames of TPA files to analyse.  Filenames should\n"
  . "                     be space-separated.\n\n";

    foreach $arg (@$args) {

	if ( $arg =~ /-v(erbose)?/i ) {
	    $verbose = 1;
	}
	elsif ( $arg =~ /\-s(core)?=(\d+)/i ) {
	    $scoreLimit = $2;
	}
	elsif ( $arg =~ /\-l(ength)?=(\d+)/i ) {
	    $minimumLength = $2;
	}
	elsif ( $arg =~ /\-tsa/i ) {
	    $tsa = 1;
	}
	elsif ( $arg =~ /\-h(elp)?/i ) {
	    die $usage;
	}
	elsif ( $arg =~ /\-i(dentity)?=([0-9\.]+%?)/i ) {
	    $minimumIdentity = $2;
	    $minimumIdentity =~ s/%$//;

	    if ($minimumIdentity > 1) {
		if ($minimumIdentity <=100){
		    $minimumIdentity = $minimumIdentity / 100;
		}
		else{
		    die "minimum identity of \"$minimumIdentity\" makes no sense, I prefer as a decimal fraction 0.90 or a percentage\n";
		}	
	    }
	}
	elsif ( $arg =~ /\-p(enalty)?=([0-9-]+)/i ) {
	    $gapPenalty = $2;
	    $gaps = 1;
	}
	elsif ( $arg =~ /\-g(aps?)?/i ) {
	    $gaps = 1;
	}
	elsif ( $arg =~ /\-nogaps?/i ) {
	    $gaps = 0;
	}
	elsif ($arg !~ /^\-/) {
	    push(@$inputFiles, $arg);  # take in data filename(s)
	}
	else {
	    die "\nI do not understand the argument \"$arg\"\n".$usage;
	}
    }

    foreach $file (@$inputFiles) {
        if (( ! (-f $file)) || (! (-r $file) )) {
            die "$file is not readable. Exiting script...\n";
        }
    }

    # gaps are not allowed in TSA entries
    if ($tsa) {
	$gaps = 0;
	$gapPenalty = -4;
    }
    
    if ($gapPenalty =~ /\./) {
	die "The gap penalty must be a whole negative number. -4 is the default.\n";
    }
    elsif ($gapPenalty > -1) {
	$gapPenalty = 1 * $gapPenalty;
    }

    if ( (!$gaps) && (!$tsa) && ($gapPenalty != -4) ) {
	print "\nWarning: Since the gap penalty option (-p) was entered but a gapped blastn\nwas not selected, a gapped blastn will be run.\n\n";
	$gaps = 1;
    }
}

#-------------------------------------------------------------------------------
# Usage   : get_filename_prefix($inputFilename, @$submission, $index)
# Description: parse the name and the number of input file name 
# Return_type : none.  Submission array is populated via a reference
# Args    : $inputFilename : filename string e.g. BN000178.ffl
#           @$submission : list of details about the submission
#           $index: element of @submission list to populate
# Caller  : called in parse_flatfiles
#-------------------------------------------------------------------------------
sub get_filename_prefix($\@$) {

    my $file = shift;
    my $submission = shift;
    my $index = shift;

    if ( $file =~ /([^.]+)\.[a-z]+$/ ) {
	$$submission[$index]{'fileprefix'} = $1;
	$$submission[$index]{'filename'} = $file;
    }
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
sub parse_flatfiles(\@\@\%) {

    my ( $file, $i, $line, @rangeList, $acc, $accStr, @splitAccs );

    my $inputFiles = shift;
    my $submission = shift;
    my $associateSeqFiles = shift;

    $i = 0;
    foreach $file (@$inputFiles) {

        my_open_FH( \*TPA_IN, "<$pwd/$file" );

	get_filename_prefix( $file, @$submission, $i );

        while ($line = <TPA_IN>) {
            # normal AS line e.g. AS   1-41           AC108564.5           2326-2366    c
	    if ( $line =~ /^AS\s+(\d+)-(\d+)\s+(\S+)\s+((\d+)-(\d+)|not_available)\s*([Cc]?)/ ) {
		$$associateSeqFiles{uc($3)} = "";
		push (@{$$submission[$i]{primaccs}}, $3);
            }
            # special AS line e.g. AS   BE213019.1-BE213024.1, BM028358.1, BE468907.1
	    elsif ( $line =~ /^AS\s+[A-Za-z]{1,4}\d+(\.\d+)?/ ) {

		$line =~ s/^AS\s+//;

		@splitAccs = split(/,?[ \t\n\r]+/, $line);

		foreach $accStr (@splitAccs) {

                    # accession ranges
		    if ( $accStr =~ /([A-Za-z]{1,2}\d+(\.\d+)?)\-([A-Za-z]{1,2}\d+(\.\d+)?)/ ) {

			$verbose && print "Expanding a range of accessions: $accStr\n";
			@rangeList = expand_acc_range($1, $3);
		
			foreach $acc (@rangeList) {
			    $$associateSeqFiles{uc($acc)} = "";
			    push (@{$$submission[$i]{primaccs}}, $acc);
			}
		    }
		    elsif ( $accStr =~ /([A-Za-z]{1,4}\d+(\.\d+)?)/ ) {

			$$associateSeqFiles{uc($1)} = "";
			push (@{$$submission[$i]{primaccs}}, $1);
		    }
		}
	    }
        }
        close(TPA_IN);

        $i++;
    }
}

#-------------------------------------------------------------------------------
# Usage   : save_seqs_to_file(\@submission, \%associatedSeqFiles, $tempDir)
# Description: For each temp file in the directory, this method saves the TPA 
# sequence to one file and all the full associated seqs (found in AS lines) to
# another file (all in fasta-format)
# Return_type : \@save_files: reference to a list of files to be run through 
#               formatdb (i.e. files to be turned into a blastable database)
# Args    : @$submission : array of details about the input files.  It supplies
# filename/filename prefix/associate accessions associated with each temp file.
#         : %$associateSeqFiles : hash of assoc. accessions (key) vs embl filename
# of EMBL file of that assoc. accession.
#         : $tempDir : directory in which to find the EMBL files containing seqs  
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub save_seqs_to_file(\@\%$) {

    my ( $saveFile, $conSaveFile, $i, @saveFiles, $saveText, $seqretCmd );
    my ( $primAcc, $tpaConstruct, $extraOptions, $emblFile, $line, $acc, $sv );

    my $submission = shift;
    my $associateSeqFiles = shift;
    my $tempDir = shift;

    if ( -e $blastableDir ) {
        system "rm -r $blastableDir";
    }
    mkdir $blastableDir;

    # foreach input file
    for ( $i=0; $i<@$submission; $i++ ) {

        $saveFile    = "$blastableDir/" . $$submission[$i]{fileprefix};
        $conSaveFile = $saveFile . ".fasta.con";

        push( @saveFiles, $saveFile );

	$seqretCmd = $seqret." -osformat2 fasta -auto";

        # create fasta-formatted TPA sequence file from EMBL file
	$extraOptions = " -sequence ".$$submission[$i]{filename}." -outseq $conSaveFile";

	$verbose && print "\nCreating fasta file for TPA sequence from ".$$submission[$i]{'filename'} ." using the following command:\n".$seqretCmd.$extraOptions."\n";

	$tpaConstruct = system $seqretCmd.$extraOptions;

	# create file of fasta-formatted full associate seqs
        open( SAVEFASTAFILE, ">$saveFile" ) || die "Cannot open $saveFile for writing [B]\n";

        foreach $primAcc ( @{ $$submission[$i]{'primaccs'} } ) {
	    $emblFile = $$associateSeqFiles{$primAcc};
	    
	    $verbose && print "Running $seqret -sequence $tempDir/$emblFile -stdout";
	    $saveText = `$seqretCmd -sequence $tempDir/$emblFile -stdout\n`;

	    if ($emblFile =~ /^[A-Za-z]{1,2}\d+\.\d+/) {
		$saveText =~ s/^>[^;]+;/>$emblFile;/;
	    }
	    elsif ($emblFile =~ /\.dat$/) {

		if (open(READ_ID, "<$tempDir/$emblFile")) {

		    while ($line = <READ_ID>) {
			if ($line =~ /ID\s+([A-Za-z]{1,2}\d+); SV (\d+)/) {
			    $acc = $1;
			    $sv  = $2;
			    $saveText =~ s/^>[^;]+;/>$acc.$sv;/;
			    last;
			}
		    }
		    close(READ_ID);
		}
		else {
		    print "\n\nCannot open $emblFile\n\n";
		}
	    }

            print SAVEFASTAFILE $saveText;
        }

        close(SAVEFASTAFILE);
    }

    return ( \@saveFiles );
}

#-------------------------------------------------------------------------------
# Usage   : compile_blastable_databases(@$fastaFileList);
# Description: compiles a file of fasta seqs into a blastable database
# Return_type : none. New files are created in the same directory as the fasta files
# Args    : @$fastaFileList : list of files that need compiling.   
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub compile_blastable_databases(\@) {

    my ( @path, $file );

    my $fastaFiles = shift;

    foreach $file (@$fastaFiles) {
        @path = ();
        @path = split( /\//, $file );
	if ( $verbose ) {
	    print "compiling $file: $wuBlastDir/wu-formatdb -t $path[-1] -p F -i $file\n";
	}
        system "cd $blastableDir; $wuBlastDir/wu-formatdb -t $path[-1] -p F -i $file > /dev/null; cd $pwd";
    }
}

#-------------------------------------------------------------------------------
# Usage   : blast_constructed_seq(@$fastaFileList, @$submission)
# Description: Blasts the TPA sequences against the blastable database
# Return_type : list of filenames containing blast results
# Args    : @$fastaFileList : list of blastable database files.
#           @$submission : list of input file details so filename for blast
# results can be constructed   
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub blast_constructed_seq(\@\@$) {

    my ( $blastn, $blastOutputFile, @outputFiles, $i, $blastCmdMsg );
    my ( $blastOptionsMsg, $gappedMsg, $scoreMsg, $printBlastOptionMsg );

    my $fastaFiles = shift;
    my $submission = shift;
    my $logFileFH = shift;

    $printBlastOptionMsg = 1;

    for ( $i = 0 ; $i < @$fastaFiles ; $i++ ) {

        $blastOutputFile = "$blastableDir/" . $$submission[$i]{fileprefix} . ".blast_output";

	# filter repeats in the tpa sequence with 'dust'

	# prevents alignments of single repeats.  see DS 68050
	#system "/ebi/extserv/bin/wu-blast/filter/dust ". $$fastaFiles[$i] . ".fasta.con 50 > ". $$fastaFiles[$i] . "fasta.temp";
	#rename $$fastaFiles[$i] . "fasta.temp", $$fastaFiles[$i] . ".fasta.con";

	if (! $gaps) {
	    $blastn = '/ebi/extserv/bin/wu-blast/blastn ' . $$fastaFiles[$i] . ' ' . $$fastaFiles[$i] . '.fasta.con -nogaps -S=' . $scoreLimit . ' -warnings -errors -notes > ' . $blastOutputFile;
	}
	else {
	    $blastn = '/ebi/extserv/bin/wu-blast/blastn ' . $$fastaFiles[$i] . ' ' . $$fastaFiles[$i] . '.fasta.con -gaps -n=' . $gapPenalty . ' -S=' . $scoreLimit . ' -warnings -errors -notes > ' . $blastOutputFile;
	}

	if ($verbose) {
	    $blastCmdMsg = "\nblastn command = $blastn\n";
	    print $logFileFH $blastCmdMsg;
	    print $blastCmdMsg;
	}

	if ($printBlastOptionMsg) {
	    $blastOptionsMsg = "\nChosen blastn options:\n"
	    . "  Type of blastn (-gaps/-nogaps):        ";

	    print $logFileFH $blastOptionsMsg;
	    print $blastOptionsMsg;
	

	    if (!$gaps) {
		print $logFileFH "ungapped\n";
		print "ungapped\n";
	    } else {
		$gappedMsg = "gapped\n"
		    . "  Gap penalty (-penalty):                $gapPenalty\n";
		print $logFileFH $gappedMsg;
		print $gappedMsg;
	    }

	    $scoreMsg = "  Minimum score of hit (-score):         $scoreLimit\n"
		. "  Minimum % identity of hit (-identity): ".($minimumIdentity*100)."%\n"
		. "  Minimum length of hit (-length):       $minimumLength\n";
	    print $logFileFH $scoreMsg;
	    print $scoreMsg;

	    $printBlastOptionMsg = 0;
	}

        push( @outputFiles, $blastOutputFile );

        system $blastn;
    }

    return ( \@outputFiles );
}

#-------------------------------------------------------------------------------
# Usage   : display_coverage(@$sortedHits, $originatingFile, $tpaLen)
# Description: displays the coverage of blast hits on each span of the TPA SEQ
# Return_type : none - just outputs to the command line
# Args    : @$sortedHits : list of blast hits - start and end positions are used
# to compare with each other. 
#           $originatingFile: input file (string)
#           $tpaLen : length (integer) of TPA sequence
# Caller  : called in "parse_blast_putput" method
#-------------------------------------------------------------------------------
sub display_coverage(\@$$$) {

    my ( %alignmentPoints, $hit, @alignmentPointList, @spansAndCoverage, $span );
    my ( $i, $paddedStr, $spanLen, $checkStartOfTPA, $spanEnd, @gapWarnings );
    my ( $warning, $header, $paddedMsg, $gapWarningsMsg, @gapsOfNoCoverage );

    my $sortedHits = shift;
    my $originatingFile = shift;
    my $tpaLen = shift;
    my $logFileFH = shift;

    $header = $separator."Primary ID Coverage: ($originatingFile)".$separator;
    print $logFileFH $header;
    print $header;

    foreach $hit (@$sortedHits) {

        $alignmentPoints{ $hit->{querystart} - 1 } = 1;
        $alignmentPoints{ $hit->{queryend} } = 1;
    }

    @alignmentPointList = sort { $a <=> $b } ( keys %alignmentPoints );

    for ( $i=1; $i<@alignmentPointList; $i++ ) {

        push( @spansAndCoverage,
              {  START    => $alignmentPointList[ $i - 1 ] + 1,
                 END      => $alignmentPointList[$i],
                 COVERAGE => 0
              }
        );
    }

    foreach $hit (@$sortedHits) {
        foreach $span (@spansAndCoverage) {
            if ( ( $span->{START} >= $hit->{querystart} ) && ( $span->{END} <= $hit->{queryend} ) ) {
                $span->{COVERAGE}++;
            }
        }
    }

    #print Dumper (\@spansAndCoverage);
    $checkStartOfTPA =1;
    foreach $span (@spansAndCoverage) {

	if (($checkStartOfTPA) && ($span->{START} > 1)) {
	    $spanLen = $span->{START} - 1;
	    $paddedStr = right_pad_or_chop( "1-" . $spanLen, 15, " " );
	    $paddedMsg = $paddedStr. "0x coverage (" . $spanLen . " nt span)\n";

	    print $logFileFH $paddedMsg;
	    print $paddedMsg;

	    push(@gapWarnings, "1-" . $spanLen . " (" . $spanLen . "bp)");
	}
	$checkStartOfTPA = 0;

	$spanEnd = $span->{END};
	$spanLen = ( $spanEnd - $span->{START} ) + 1;
	$paddedStr = right_pad_or_chop( $span->{START} . "-" . $spanEnd, 15, " " );
	$paddedMsg = $paddedStr. $span->{COVERAGE} . "x coverage (" . $spanLen . " nt span)\n";

	print $logFileFH $paddedMsg;
	print $paddedMsg;

	if (($span->{COVERAGE} == 0) && ($spanLen > 49)) {
	    push(@gapWarnings, $span->{START} . "-" . $spanEnd . " (" . $spanLen . "bp)");
	    push(@gapsOfNoCoverage, $span->{START}."|".$span->{END});
	}
    }

    # add 0x coverage for the end of the TPA, if necessary
    if ($spanEnd < $tpaLen) {
	$spanLen = $tpaLen - $spanEnd;
	$paddedStr = right_pad_or_chop( ($spanEnd+1) . "-" . $tpaLen, 15, " " );
	$paddedMsg = $paddedStr. "0x coverage (" . $spanLen . " nt span)\n";

	if ($spanLen > 49) {
	    print $logFileFH $paddedMsg;
	    print $paddedMsg;
	    push(@gapWarnings, ($spanEnd+1) . "-" . $spanEnd . " (" . $spanLen . "bp)");
	    push(@gapsOfNoCoverage, $span->{START}."|".$span->{END});
	}
    }

    if ( @gapWarnings ) {
	print $logFileFH "\nWarnings:\n";
	print "\nWarnings:\n";

	foreach $warning (@gapWarnings) {
	    $gapWarningsMsg = "TPA span $warning has no coverage by the primary sequences supplied.\n";
	    print $logFileFH $gapWarningsMsg;
	    print $gapWarningsMsg;
	}
    }

    return (\@gapsOfNoCoverage);
}

#-------------------------------------------------------------------------------
# Usage   : display_AS_lines(@$sortedHits)
# Description: displays new AS lines recalc'd from blast results.
# Return_type : none - just outputs to the command line
# Args    : @$sortedHits : array of blast hits - start and end positions are used
# to compare with each other. 
# Caller  : called in "parse_blast_putput" method
#-------------------------------------------------------------------------------
sub display_AS_lines(\@$$) {

    my ( $i, $ASline, $AHheader, @tpaFileContents, $substitutionDone );
    my ( $mockTpaFilename, $line );

    my $sortedHits = shift;
    my $originatingFile = shift;
    my $logFileFH = shift;

    my_open_FH( \*TPAFILE, "<$originatingFile" );
    @tpaFileContents = <TPAFILE>;

    $mockTpaFilename = $originatingFile.".asgen";
    my_open_FH( \*MOCKTPAFILE, ">".$mockTpaFilename );

    foreach $line (@tpaFileContents) {
	if (($line =~ /^AH/) || ($line =~ /^AS/)) {

	    if (! $substitutionDone) {
		$AHheader = "AH   LOCAL_SPAN      PRIMARY_IDENTIFIER   PRIMARY_SPAN   COMP\n";
		print MOCKTPAFILE $AHheader;

		$AHheader = $separator. "BLASTN-generated AS lines: ($originatingFile)" . $separator . $AHheader;
		print $AHheader;
		print $logFileFH $AHheader;

		for ( $i = 0 ; $i < @$sortedHits ; $i++ ) {
		    
		    $ASline = "AS   ";
		    
		    $ASline .= right_pad_or_chop( $$sortedHits[$i]{querystart} . "-" . $$sortedHits[$i]{queryend}, 16, " " );
		    $ASline .= right_pad_or_chop( $$sortedHits[$i]{accession},                                     21, " " );
		    $ASline .= right_pad_or_chop( $$sortedHits[$i]{hitstart} . "-" . $$sortedHits[$i]{hitend},     15, " " );
		    
		    if ( $$sortedHits[$i]{strand} == -1 ) {
			$ASline .= "C";
		    }
		    $ASline .= "\n";

		    print $ASline;
		    print $logFileFH $ASline;
		    print MOCKTPAFILE $ASline;
		    $substitutionDone = 1;
		}
	    }
	}
	else {
	    print MOCKTPAFILE $line;
	}
    }
    close(TPAFILE);
    close(MOCKTPAFILE);
    return($mockTpaFilename);
}

#-------------------------------------------------------------------------------
# Usage   : display_overlaps_within_primacc(@$sortedHits)
# Description: generates warnings about overlaps between the blast hits
# Return_type : none - just outputs to the command line
# Args    : @$sortedHits : array of blast hits - start and end positions are used
# to compare with each other. 
# Caller  : called in "parse_blast_putput" method
#------------------------------------------------------------------------------
sub display_overlaps_within_primacc(\@$) {

    my ($hit, $accno, %accnos, $i, $j, $start1, $end1, $start2, $end2, $warning);
    my (@sortedQueryStart);
    my $sortedHits = shift;
    my $logFileFH = shift;

    print "\n";

    foreach $hit (@$sortedHits) {
	push(@{$accnos{$hit->{accession}}}, {
	    querystart => $hit->{querystart},
	    queryend   => $hit->{queryend}
	});
    }

    foreach $accno (keys %accnos) {

	@sortedQueryStart = sort { $a->{querystart} <=> $b->{querystart} } @{$accnos{$accno}};

	if (@sortedQueryStart > 1) {
	    for ($i=0; $i<@sortedQueryStart; $i++) {

		$start1 = $sortedQueryStart[$i]{querystart};
		$end1   = $sortedQueryStart[$i]{queryend};

		for ($j=($i+1); $j<@sortedQueryStart; $j++) {

		    $start2 = $sortedQueryStart[$j]{querystart};
		    $end2   = $sortedQueryStart[$j]{queryend};

		    if ($end2 < $end1) {
			$warning = "Warning: In the generated AS lines, the accession $accno has a hit in position $start2"."-"."$end2 of the constructed sequence.  This span sits *inside the span* $start1"."-"."$end1.\n";
			print $logFileFH $warning;
			print $warning;
		    }
		    elsif (( $verbose ) && ( $end1 > $start2 )) {
			$warning = "Warning: There is a ".($end1 + 1 - $start2)."nt overlap in primary accession $accno from position $start2 to $end1 of the constructed sequence, in the generated AS lines.\n";
			print $logFileFH $warning;
			print $warning;
		    }
		}
	    }
	}
    }
}

#-------------------------------------------------------------------------------
# Usage   : blast_gaps_of_0x_coverage
# Description:
# Return_type : 
# Args    : 
# Caller  : called in parse_blast_output subroutine
#------------------------------------------------------------------------------
sub display_gaps_of_0x_coverage(\@$$$) {

    my ( $blastableDb, $noCovSpan, $startOfNoCovSpan, $endOfNoCovSpan );
    my ( $seqretCmd, $i, @newFilesToBlast, $file, @fileContents, $line );

    my $gaps_over_50bp = shift;
    my $lastBlastOutputFile = shift;
    my $inputFile = shift; # for displaying in messages
    my $logFileFH = shift;

    if ($lastBlastOutputFile =~ /^(.+\/[^.]+)\.blast_output$/) {
	$blastableDb = $1;
    }

    #create files containing 0x coverage span
    $i=0;
    foreach $noCovSpan (@$gaps_over_50bp){
	($startOfNoCovSpan, $endOfNoCovSpan) = split(/\|/, $noCovSpan);

	# invent a new filename to call blasted span with no coverage
	if ($i) {
	    $newFilesToBlast[$i] = $blastableDb."nocov".$i;
	}
	else {
	    $newFilesToBlast[$i] = $blastableDb."nocov";
	}

	$seqretCmd = $seqret.
	    " -sequence ". $blastableDb.".fasta.con".
	    " -sbegin1 " . $startOfNoCovSpan.
	    " -send1 "   . $endOfNoCovSpan.
	    " -osformat2 fasta".
	    " -auto".
	    " > ".$newFilesToBlast[$i]; 

	$verbose && print "Running seqret in blast_gaps_of_0x_coverage: $seqretCmd\n";

        system $seqretCmd;
	$i++;
    }

    print "TPA gap sequence(s):\n";

    foreach $file (@newFilesToBlast) {

	my_open_FH( \*GAPSEQ, "<$file" );
	@fileContents = <GAPSEQ>;
	close(GAPSEQ);

	foreach $line (@fileContents) {

	    if ($line =~ /^\>/) {
		$line =~ s/\n+//;
		$line .= " ($startOfNoCovSpan..$endOfNoCovSpan span from $inputFile)";
	    }
	    print $logFileFH $line."\n";
	    print $line."\n";
	}
    }
}

#-------------------------------------------------------------------------------
# Usage   : parse_blast_output(@blastOutputFiles, @$fastaFiles, @$submission, @$inputFiles)
# Description: extracts out info from the blast results and sends it off to be
# displayed.
# Return_type : none
# Args    : @$blastOutputFiles : list of files containing blast results.
#         : @$fastaFiles : list of blast database files in case a gapped blast
# needs to be run
#         : @$submission : list of details about the input files (required in 
# case a gapped blast needs to be run)
#         : @$inputFiles: list of input files from the commandline
# Caller  : called in the main
#------------------------------------------------------------------------------
sub parse_blast_output(\@\@\@\@$) {

    my ( @sortedHits, @hits, $hsp, $report, $searchio, $outputFile, $i, $hit );
    my ( $queryStart, $queryEnd, $redundant, $tmp, $existingHit, $queryLength );
    my ( $hitAccession, $blastOutputFileCounter, $subjectLen, $asgenOutputFile );
    my ( @asgenOutputFiles, $replacementMsg, $redundantMsg, $storingMsg );
    my ( $discardedMsg, $gaps_over_50bp );

    my $blastOutputFiles = shift;
    my $fastaFiles       = shift; # imported in case ungapped blast needs to be run
    my $submission       = shift; # ditto
    my $inputFiles       = shift; # displayed in parsed blast results
    my $logFileFH        = shift;

    $blastOutputFileCounter = 0;
    foreach $outputFile (@$blastOutputFiles) {
	while ( ! scalar(@hits) ) {

	    my_open_FH( \*BLASTRES, "<$outputFile" );

	    $searchio = new Bio::SearchIO( -format => 'blast', -file => $outputFile );

	    while ( $report = $searchio->next_result ) {

		$subjectLen = $report->query_length;

		$i = 0;
		while ( $hit = $report->next_hit ) {
		    
		    while ( $hsp = $hit->next_hsp ) {
			$queryStart = $hsp->query->start;
			$queryEnd   = $hsp->query->end;
			$queryLength = 1 + ($queryEnd - $queryStart);

			if ( $queryEnd < $queryStart ) {
			    $tmp        = $queryEnd;
			    $queryEnd   = $queryStart;
			    $queryStart = $tmp;
			}

                        # removing trailing semi-colon from accession number
			$hitAccession = $hit->accession;
			$hitAccession =~ s/;//;

			$redundant = 0;
			if (($hsp->hit->frac_identical() > $minimumIdentity) && ($minimumLength <= $queryLength)) {
			    # check all existing hits to see if this is redundant
			    foreach $existingHit (@hits) {

				if (( $$existingHit{accession} eq $hitAccession ) && ( $$existingHit{strand} == $hsp->strand )) {
				    if (( $queryStart >= $$existingHit{querystart} ) && ( $queryEnd <= $$existingHit{queryend} )) {
					
					if ( $verbose ) {
					    $redundantMsg = sprintf "Redundant hit to %s:%s%d..%d%s on tpa:%d..%d lies inside tpa:%s%d..%d%s\n", 
					    $hitAccession,
					    (($hsp->strand == -1) ? "complement(" : ""),
					    $hsp->hit->start,
					    $hsp->hit->end,
					    (($hsp->strand == -1) ? ")" : ""),
					    $queryStart,
					    $queryEnd,
					    (($$existingHit{strand} == -1) ? "complement(" : ""),
					    $$existingHit{querystart},
					    $$existingHit{queryend},
					    (($$existingHit{strand} == -1) ? ")" : "");

					    print $logFileFH $redundantMsg;
					    print STDERR $redundantMsg;
					}
					$redundant = 1; # do not save in next section
					last;
				    }
				    elsif (( $queryStart <= $$existingHit{querystart} ) && ( $queryEnd >= $$existingHit{queryend} )) {
					# replace existing hit with larger current span
					if ( $verbose ) {
					    $replacementMsg = sprintf " Hit %s:%s%d..%d%s on tpa:%d..%d has replaced the span which lies in the TPA span tpa:%d..%d\n", 
					    $hitAccession,
					    (($hsp->strand == -1) ? "complement(" : ""),
					    $hsp->hit->start,
					    $hsp->hit->end,
					    (($hsp->strand == -1) ? ")" : ""),
					    $queryStart,
					    $queryEnd,
					    $$existingHit{querystart},
					    $$existingHit{queryend};

					    print $logFileFH $replacementMsg;
					    print STDERR $replacementMsg;
					}

					$hits[$i] = { 
					    accession  => $hitAccession,
					    querystart => $queryStart,
					    queryend   => $queryEnd,
					    hitstart   => $hsp->hit->start,
					    hitend     => $hsp->hit->end,
					    score      => $hsp->hit->score,
					    strand     => $hsp->strand, 
					    identity   =>$hsp->hit->frac_identical() 
					};
					$i++;
					$redundant = 1; # do not save in next section
					last;
				    }
				}
			    }
			    if ( ! $redundant ) {

				if ( $verbose ) {
				    $storingMsg = sprintf "Storing hit to %s:%s%d..%d%s on tpa:%d..%d (len=%d, score=%d identity=%d%%)\n", 
				    $hitAccession,
				    (($hsp->strand == -1) ? "complement(" : ""),
				    $hsp->hit->start,
				    $hsp->hit->end,
				    (($hsp->strand == -1) ? ")" : ""),
				    $queryStart,
				    $queryEnd,
				    $queryLength,
				    $hsp->hit->score,
				    int (100 * $hsp->hit->frac_identical());

				    print $logFileFH $storingMsg;
				    print STDERR $storingMsg;
				}
				
				$hits[$i] = { 
				    accession  => $hitAccession,
				    querystart => $queryStart,
				    queryend   => $queryEnd,
				    hitstart   => $hsp->hit->start,
				    hitend     => $hsp->hit->end,
				    score      => $hsp->hit->score,
				    strand     => $hsp->strand, 
				    identity   =>$hsp->hit->frac_identical()
				    };
				$i++;
			    }
			}
			else {
			    if ( $verbose ) {
				$discardedMsg = sprintf "Hit of length %dbp, identity %d%% discarded\n", $queryLength, int (100 * $hsp->hit->frac_identical());

				print $logFileFH $discardedMsg;
				print STDERR $discardedMsg;
			    }
			}
		    }
		}
	    }

	    # if not hits were found and blast is ungapped, try a gapped blast or else quit.
	    if (! scalar(@hits) ) {

		if ( ! $gaps ) {
	            $gaps = 1;
		    $blastOutputFiles = blast_constructed_seq( @$fastaFiles, @$submission, $logFileFH);
		}
		else {
		    die "Warning:\nThere were no blast results returned that meet then criteria of score of at\n"
			. "least $scoreLimit and % identity of at least ".($minimumIdentity*100)."% , with or without using a gapped blastn.\n"
			. "Perhaps you could lower the % identity option (e.g. -i=".(($minimumIdentity - 0.05)*100)."%)?\n"
			. "Perhaps you could lower the score option (e.g. -s=".($scoreLimit - 20).")?\n"
			. "Perhaps the submitter's AS lines contain the wrong accession numbers?\n"
			. "Try adjusting your command-line options before running this program again.\n";
		}
	    }
	}
	close(BLASTRES);

        @sortedHits = sort { $a->{querystart} <=> $b->{querystart} } @hits;

        # display results (in different ways)
        $asgenOutputFile = display_AS_lines( @sortedHits, $$inputFiles[$blastOutputFileCounter], $logFileFH );

	# gather output filenames for printing later on
	push(@asgenOutputFiles, $asgenOutputFile);

        $gaps_over_50bp = display_coverage( @sortedHits, $$inputFiles[$blastOutputFileCounter], $subjectLen, $logFileFH );

	display_overlaps_within_primacc( @sortedHits, $logFileFH );

	if ( scalar(@$gaps_over_50bp) ) {
	    $verbose && print "Blasting ".scalar(@$gaps_over_50bp)."gap(s) in TPA\n";
	    display_gaps_of_0x_coverage( @$gaps_over_50bp, $outputFile, $$inputFiles[$blastOutputFileCounter], $logFileFH );
	}

	@hits = (); #clear array
	$blastOutputFileCounter++;
    }

    return(\@asgenOutputFiles);
}

#-------------------------------------------------------------------------------
# Usage   : main(@ARGV)
# Description: contains the run order of the script
# Return_type : none
# Args    : @ARGV command line arguments
# Caller  : this script
#------------------------------------------------------------------------------
sub main(\@) {

    my ( $rev_db, @submission, $acc, %associateSeqFiles, $temp_dir, $LOGFILE );
    my ( $blastOutputFiles, $fastaFiles, @inputFiles, $asgenOutputFiles );
    my ( $outputLoc );

    my $args = shift;

    usage(@$args, @inputFiles);

    if (! @inputFiles) {
	get_input_files(@inputFiles);
    }

    if ($verbose) {
	print "Generating AS lines for the following input file(s):\n";
	
	foreach (@inputFiles) {
	    print $_."\n";
	}
	print "\n";
    }
 
    # create directory to store sequence files
    $temp_dir = cwd.'/tpav_tmp.del';
    if (! (-e $temp_dir) ) {
	mkdir $temp_dir;
    }

    # %associateSeqFiles: hash of AC.version -> entry file location
    parse_flatfiles(@inputFiles, @submission, %associateSeqFiles);

    # connect to the revision database
    $rev_db = RevDB->new('rev_select/mountain@erdpro');

    # get a sequence file for eash associate sequence
    foreach $acc (keys %associateSeqFiles){
	$associateSeqFiles{$acc} = grab_entry($rev_db, $temp_dir, 0, $acc, 0, 1);
    }

    # disconnect from the revision database
    $rev_db->disconnect();

    # add all the seqs in an alignment plus the construct, into a fastafile.
    $fastaFiles = save_seqs_to_file( @submission, %associateSeqFiles, $temp_dir );

    compile_blastable_databases(@$fastaFiles);
    
    #log file will get std output saved to it
    print "Opening $pwd/$logFile\n";
    open( $LOGFILE, ">$pwd/$logFile" ) || print "Cannot open log file $logFile: $!\n";

    ($blastOutputFiles) = blast_constructed_seq( @$fastaFiles, @submission, $LOGFILE );

    $asgenOutputFiles = parse_blast_output( @$blastOutputFiles, @$fastaFiles, @submission, @inputFiles, $LOGFILE );

    $outputLoc =  "\nNB The new AS lines have been substituted into the following copies of TPA files:\n" . join("\n", @$asgenOutputFiles) . "\n\n";

    print $outputLoc;
    print $LOGFILE "\n$outputLoc";

    print "The summary of suggested changes listed above is also stored in $logFile\n\n";

    close($LOGFILE);
}

main(@ARGV);
