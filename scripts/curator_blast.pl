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
#  $RCSfile: curator_blast.pl,v $
#  $Revision: 1.30 $
#  $Date: 2011/12/21 13:47:16 $
#  $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/curator_blast.pl,v $
#  $Author: rasko $
#
#===============================================================================

use strict;
use Bio::Tools::BPlite;
use Bio::SearchIO; 
use File::Find;
use Data::Dumper;
use SeqDBUtils2;
use Cwd;

my $verbose;
my $pwd             = cwd;
my $wuBlastDir      = "/ebi/extserv/bin/wu-blast";
my $blastableDir    = "/ebi/production/seqdb/embl/tools/curators/scripts/curator_blast_databases";
my $dsBlastableDir  = cwd . "/blastables.del";
my $quick_blast     = 0;
my $interactive = 1;

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# This script is used for 16S RNA matching. Confirmed from Richard 21 Dec 2011.
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

my $usage =
    "\nPURPOSE: This script uses the sequences found in one of the accepted file\n"
  . "types within the current directory [.fflupd, .ffl, .temp, .sub]. With these input\n"
  . "files it runs a blastn on either the 16S RNA database or the gene and genus extracted\n"
  . "extracted from the input files.  The script then parses the results to give a summary \n"
  . "of the top x number of blast hits.\n\n"
  . " USAGE:   curator_blast.pl [<sequence files>] [-t=<blast type>] [-n=<number of hits>] [-f=<sequence file list>] [-v] [-h]\n\n"
  . "   <sequence files>    where <sequence files> are of type .fflupd, .ffl, .temp or .sub\n"
  . "                       These input files must contain at least one embl entry.\n"
  . "                       NB If you want to add a selection of files using a\n"
  . "                       wildcard (*), you must escape the * with a backslash\n"
  . "                       If no filename is entered, a sequence file will be\n"
  . "                       sought automatically (.fflupd if present, .ffl if not...).\n"
  . "                       e.g. curator_blast.pl \*.ffl\n"
  . "                       You may also add a list of space-separated filenames.\n\n"
  . "   -t=<blast type>     where <blast type> is 16S (the only available value at present).\n"
  . "                       If -t is not used, the gene and genus from the input files will be\n"
  . "                       used to generate a blastable database instead.\n\n"
  . "   -n=<number of hits> where <number of hits> will alter is the top x number of\n"
  . "                       hit sequences displayed per blast result in the results\n"
  . "                       summary, ordered by E number (default = 3).\n\n"
  . "   -f=<sequence file list>  where <sequence file list> is the name of a file containing a\n"
  . "                            list of embl files which you want to blast\n\n"
  . "   -log                Create a file called blast.log containing all the blast results.\n\n"
  . "   -auto               Runs non-interactively and overwrites blast16S_summary if it already\n"
  . "                       exists, without asking\n"
  . "   -v                  verbose mode\n\n"
  . "   -h                  shows this help text\n\n";

################################################################################
# get SRS data

sub get_srs_data($$$) {

    my ($srsQuery, @orgNameParts, $srsQueryCount, $numEntries);

    my $gene       = shift;
    my $org        = shift;
    my $saveToFile = shift;

    if ($org =~ /\s/) {

        $srsQuery = "getz '(((";

        @orgNameParts = split(/ /, $org);

        foreach (@orgNameParts) {
            $srsQuery .= "[emblcds-org:$_*] & ";
        }
        $srsQuery =~ s/ & $//;
        $srsQuery .= ") | [emblcds-org:$org*]) & ";
    } else {
        $srsQuery = "getz '([emblcds-org:$org*] & ";
    }

    $srsQuery .= "([emblcds-gene:$gene*] > parent))'";

    if ($verbose && $interactive) {
        print "Gathering data to create a blastable database using the following " . "SRS query:\n$srsQuery\n\n";
    }

    $srsQueryCount = $srsQuery . " -c";
    $numEntries    = `$srsQueryCount`;

    if (!$numEntries) {
        die "Sorry, there are no entries containing the organism \"$org\" and gene \"$gene\" in\nthe EMBL-CDS database in SRS.\n";
    } else {
        if ($verbose) {
            $numEntries =~ s/\s+//g;
	    $interactive && print "$numEntries hits found.\n";
        }
    }

    $srsQuery .= "  -f seq -sf fasta";

    $interactive && print "\nCreating blastable database...\n\n";

    system `$srsQuery > $saveToFile`;
}

################################################################################
# compile the blastable database

sub format_blastable_DB($) {

    my (@path);

    my $file = shift;
    @path = split(/\//, $file);

    if ($verbose && $interactive) {
        print "compiling $file: $wuBlastDir/wu-formatdb -t $path[-1] -p F -i $file\n";
    }

    system "cd $dsBlastableDir; $wuBlastDir/wu-formatdb -t $path[-1] -p F -i $file > /dev/null; cd $pwd";
}

################################################################################
# create a blastable database if gene and org are specified

sub create_blastable_db($$) {

    my ($blastDataFile);

    my $gene = shift;
    my $org  = shift;

    if (!(-e $dsBlastableDir)) {
        system "mkdir $dsBlastableDir";
    }

    $blastDataFile = "$dsBlastableDir/$org" . "_" . "$gene.dat";

    if (!(-e $blastDataFile)) {
        get_srs_data($gene, $org, $blastDataFile);
        format_blastable_DB($blastDataFile);
    } else {
        if ($verbose && $interactive) {
            print "Using existing blastable database.\n";
        }
    }

    return ($blastDataFile);
}

################################################################################
# Make a fasta-formatted files

sub make_fasta_sequence_files($) {

    my ($entryCounter, $sequence, $len, $identifier);
    my ($tmpFastaFile, $line);

    my $queryFile = shift;

    $tmpFastaFile = $queryFile . '.fasta';

    open(SAVESEQ, ">$tmpFastaFile") || die "cannot open $tmpFastaFile";

    open(QUERYFILE, "<$queryFile") || die "cannot open $queryFile";
    {
	#local $/ = "\/\/\n"; # for this anonymous code block we are  defining the stream-in separator (every time we read from the file we  get a chunk ending in '//\n')
	$entryCounter = 0;
	while ($line = <QUERYFILE>) {
	    
	    if ($line =~ /^\/\//) {
		$entryCounter++;
		$identifier .= $queryFile . "_Entry_" . $entryCounter;
		$sequence =~ s/[^a-zA-Z]//g;
		$len = length($sequence);

		print SAVESEQ ">$identifier = $len bp\n";
		print SAVESEQ $sequence . "//\n";

		$identifier = "";
		$len = 0;
		$sequence = "";
	    }
	    elsif ($line =~ /AC   ([A-Z0-9]+)/) {
		$identifier = $1;
	    }
	    elsif ($line =~ /^   +[a-zA-Z]+/) {
		$sequence .= $line;
	    }
	}
    }
    close(QUERYFILE);
    close(SAVESEQ);
    
    return ($tmpFastaFile);
}

################################################################################
# run a blast and save the output to a file

sub generate_blast_output($$$) {

    my ($blastScript, $cmdlnOptions, $writeFile, @blastOutput, $delFile);
    my ($makeFastaSeqScript, $tmpFastaFile);

    my $queryFile       = shift;
    my $blastOutputFile = shift;
    my $blastDBlocn     = shift;

    # make fasta sequence file
    $tmpFastaFile = make_fasta_sequence_files($queryFile);

    # make blast output file

    # -W=40 -gapW=1 options speed up blast too
    $blastScript = "$wuBlastDir/blastn $blastDBlocn $tmpFastaFile -E=5.1e-50 -warnings -errors -notes > $blastOutputFile";


    if ($verbose && $interactive) {
        print "Running blast with the following command:\n$blastScript\n\n";
    }

    system $blastScript;

    # delete temp file
    unlink($tmpFastaFile);
}

################################################################################
# parse the output of the blast

sub parse_blast_output($$$$) {

    my $blastOutputFile  = shift;
    my $fileNameAcc      = shift;
    my $displayHitNumber = shift;
    my $BLASTSUMM        = shift;

    my $in = new Bio::SearchIO(-format => 'blast', 
                               -file   => $blastOutputFile);
    my $counter = 0;
    my $no_blast_match = 1;

    while( my $result = $in->next_result ) {
	$counter++;

        my $acc;
        # .sub and .temp files don't contain acc numbers so filename is used instead.
        if ($fileNameAcc ne "") {
            $acc = $fileNameAcc." seq $counter";
        } elsif ($result->query_name =~ /^(\w+\s)?([A-Za-z]{2}\d+)/) {
            $acc = $2;
        } else {
            $acc = $result->query_name;
            $acc = substr($acc, 0, 10);
        }

        print $BLASTSUMM "$acc: \n";

        my $hitCounter = 0;
        while( my $hit = $result->next_hit) {
            $hitCounter++;
            last if ($hitCounter > 3);

            $no_blast_match = 0;

            if ( my $hsp = $hit->next_hsp) {
                    my $strand = $hsp->strand('query') . '/' . $hsp->strand('hit');
                    $strand =~ s/\-1/\-/g;
                    $strand =~ s/1/\+/g;
                    print $BLASTSUMM "   " . $strand . "; ";

                    my ($queryStart, $queryEnd) = $hit->range('query');
                    if ($queryStart > $queryEnd) {
                       ($queryEnd, $queryStart) = $hit->range('query');
                    }
                    my ($hitStart, $hitEnd) = $hit->range('hit');
                    if ($hitStart > $hitEnd) {
                       ($hitEnd, $hitStart) = $hit->range('hit');
                    }

                    my $hitLength = $hit->length;
                    my $queryLength = $result->query_length;

                    #print $BLASTSUMM $hit->start('query') . '..' . $hit->end('query') . '/' .
                    #                 $hit->start('hit') . '..' . $hit->end('hit') . '; ';

                    # get 5' missing 
                    my $diff;
                    if ($hitStart > 1) {
                        print $BLASTSUMM "5' " . ($hitStart-1) . "bp missing; ";
                    }
                    elsif ($queryStart > 1) {
                        print $BLASTSUMM "5' " . ($queryStart-1) . "bp extra; ";
                    }
                    else {
                        print $BLASTSUMM "5' same; ";
                    }

                    # get 3' missing
                    if ($hitEnd < $hitLength) {
                        print $BLASTSUMM "3' " . ($hitLength-$hitEnd) . "bp missing; ";
                    }
                    elsif ($queryEnd < $queryLength) {
                        print $BLASTSUMM "3' " . ($queryLength-$queryEnd) . "bp missing; ";
                    } 
                    else {
                        print $BLASTSUMM "3' same; ";
                    }

                    print $BLASTSUMM "E= " . $hsp->evalue . "; ";

                    my $name = $hit->accession . ' ' . $hit->description;
                    # $name =~ s/^[^ ]+ //;
		    # if ($name =~ /^([A-Za-z]+\d+\.\d+)\.(\d+) \d+ bp(.+)/) {
		    #	$name = "$1_$2$3\n";
		    #} 

                    printf $BLASTSUMM ("I= %.1f", ($hsp->length('query') / $result->query_length * 100));
                    print $BLASTSUMM "%; ";

                    print $BLASTSUMM substr($name, 0, 15) . "...";

            } # end while( my $hsp = $hit->next_hsp )

            if ($hit->num_hsps > 1) {
                print $BLASTSUMM "* 1st of " . ($hit->num_hsps - 1) . " HSPs *";
            }

            print $BLASTSUMM "\n";

        } ## end while( my $hit = $result->next_hit )
        print $BLASTSUMM "#########################################\n";
    }

    return($no_blast_match);
} ## end sub parse_blast_output($$$)

################################################################################
#

sub find_classification_in_common(\%) {

    my ($classSet, @classes, $org, $wholeSetMatchingOrg, $matchClash, $i);
    my ($maxClassLen, @classesToCheckAgainst);

    my $classifications = shift;

    foreach $classSet (keys %$classifications) {

        if ((!@classesToCheckAgainst) && ($classSet ne "Unclassified")) {
            @classesToCheckAgainst = split(/;\s*/, $classSet);
        }

        if ((!$maxClassLen) || (@classesToCheckAgainst > $maxClassLen)) {
            $maxClassLen = scalar(@classesToCheckAgainst);
        }
    } ## end foreach $classSet (keys %$classifications)

    for ($i = 0 ; $i < $maxClassLen ; $i++) {

        foreach $classSet (keys %$classifications) {
            @classes = split(/;\s*/, $classSet);

            if ($classes[$i] eq $classesToCheckAgainst[$i]) {
                $org = $classes[$i];
            } else {
                $matchClash = 1;
                last;
            }
        } ## end foreach $classSet (keys %$classifications)
        if ($matchClash) {
            $wholeSetMatchingOrg = $classes[ ($i - 1) ];
            last;
        } else {
            $wholeSetMatchingOrg = $org;
        }
    } ## end for ($i = 0 ; $i < $maxClassLen...

    if ($verbose && $interactive) {
        print "Highest common phylum found: $wholeSetMatchingOrg\n";
    }

    return ($wholeSetMatchingOrg);
}

################################################################################
#

sub get_gene_and_org(\@) {

    my ($file, @emblFileContents, $line, $i, %genus, %genes, $classn, $tmp);
    my ($prevLine, %classification, $gene, $org, %genesDiffCase);

    my $seqFiles = shift;

    foreach $file (@$seqFiles) {
        open(READINFILE, "<$file") || die "Cannot open $file: $!\n";
        @emblFileContents = <READINFILE>;
        close(READINFILE);

        $i        = 0;
        $prevLine = "";

        # gather genes, genus and organism classification from embl file
        foreach $line (@emblFileContents) {

            if ($line =~ /^FT +\/gene="([^"]+)/) {
                $tmp               = uc($1);
                $genes{$tmp}       = 1;
                $genesDiffCase{$1} = 1;
            } elsif ($line =~ /^OS   (\S+)/) {
                $genus{ uc($1) } = 1;
            } elsif (($prevLine =~ /^OC/) && ($line =~ /^OC   ([^\n]+)/)) {
                $tmp = $1;
                $tmp =~ s/^OC  //;
                $classn .= $tmp;
            } elsif ($line =~ /^OC   ([^\n]+)/) {
                if ($1 =~ /Unclassified/) {
                    $interactive && print "Warning: An unclassifed organism has been found in $file.\n";
                } else {
                    $classn = $1;
                }
            }

            $prevLine = $line;
        } ## end foreach $line (@emblFileContents)
        $classn =~ s/\.$//;
        $classification{$classn} = 1;
    } ## end foreach $file (@$seqFiles)

    if ((scalar(keys %genesDiffCase) > 1) && (scalar(keys %genes) == 1)) {
        $interactive && print "Warning: Genes in different cases have been found:\n" . join("\n", (keys %genesDiffCase)) . "\n\n";
    }

    # check organims are the same and genes are the same
    if (scalar(keys %genes) > 1) {
        die "Error: More than one gene has been found:\n" . join("\n", (keys %genes)) . "\n\nPlease use files containing the same gene as input.\n";
    } else {
        foreach (keys %genes) {
            $gene = $_;
        }
    }

    if (scalar(keys %genus) > 1) {
        if ($verbose && $interactive) {
            print "Warning: More than one genus has been collected:\n" . join("\n", (keys %genus)) . "\n\n";
        }

        $org = find_classification_in_common(%classification);
    } else {
        foreach (keys %genus) {
            $org = $_;
        }
    }

    return ($gene, $org);
} ## end sub get_gene_and_org(\@)

################################################################################
# see if file contains a reference to the blast type and warn user if not.

sub check_file_for_blast_type($$) {

    my ($fileContents, $lc_blastType);

    my $file         = shift;
    my $uc_blastType = shift;

    open(SEQFILE, "<$file") || die "Cannot open $file for checking.  Exiting script...\n";
    $fileContents = do { local $/; <SEQFILE> };    # read file into string
    close(SEQFILE);

    $lc_blastType = $uc_blastType;
    $lc_blastType =~ tr/A-Z/a-z/;

    if (($fileContents !~ /$uc_blastType/) && ($fileContents !~ /$lc_blastType/)) {
        $interactive && print "Warning:\nThe sequence file $file does not contain any references to \"$uc_blastType\" as expected in this blast run.\n\n";
    }
}

################################################################################
# Add all the blast results into one blast.log file

sub concatentate_blast_results_into_log(\@) {

    my ($blastFile, $logFile, $fileContents);

    my $blastFiles = shift;

    $logFile = "blast.log";

    open(LOGFILE, ">$logFile") || die "Cannot open $logFile for saving the blast output files to.\n";

    foreach $blastFile (@$blastFiles) {

        if (open(BLASTFILE, "<$blastFile")) {

            $fileContents = do { local $/; <BLASTFILE> };    # read file into string

            print LOGFILE $fileContents;

            close(BLASTFILE);
            unlink($blastFile);
        } else {
            $interactive && print "Warning:\nCannot open file $blastFile in order to save its contents to blast.log\n";
        }
    } ## end foreach $blastFile (@$blastFiles)

    if ($verbose && $interactive) {
        print "All the original unparsed blast results can be found listed inside blast.log\n";
    }

    close(LOGFILE);
}

################################################################################
# Delete all the blast results files

sub delete_blast_results(\@) {

    my ($blastFile);

    my $blastFiles = shift;

    foreach $blastFile (@$blastFiles) {
	if (-e $blastFile) {
            unlink($blastFile);
	}
    }

    if ($verbose && $interactive) {
        print "All the original unparsed blast results have been deleted\n";
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

	$file =~ s/\s+$//;

        if ((!(-f $file)) || (!(-r $file))) {
            die "$file is not readable. Exiting script...\n";
        }
    }
}

################################################################################
# check if the blast type entered is allowable

sub get_blast_type($) {

    my $blastType = shift;

    if ($blastType ne "") {

        # change to uppercase
        $blastType =~ tr/a-z/A-Z/;

        # accept default blast if blast type is not recognised
        if ($blastType !~ /16S/) {
            $blastType = "16S";
        }
    } else {
        $blastType = "16S";
    }

    return ($blastType);
}

################################################################################
#

sub make_file_of_no_hit_entries(\@$) {

    my $no_blast_match_files = shift;
    my $no_hits_file = shift;

    if (open(WRITEFLELIST, ">".$no_hits_file)) {
	print WRITEFLELIST join("\n", @$no_blast_match_files)."\n";
    }
    else {
	$interactive && print "Cannot write list of files to $no_hits_file:\n".join(" ", @$no_blast_match_files)."\n";
    }

    close(WRITEFLELIST);
}

################################################################################
#

sub get_list_of_seq_files($\@) {

    my ($seq_file_list, $file);

    my $seq_list_file = shift;
    my $seqFiles = shift;

    open(READFILELIST, "<".$seq_list_file) || die "Cannot read $seq_list_file\n";;

    while ($file = <READFILELIST>) {
	push(@$seqFiles, $file);
    }

    close(READFILELIST);
}

################################################################################
# 

sub show_overwrite_warning($) {

    my ($input);

    my $summary_file = shift;

    if (-e $summary_file) {

	$input = "";

	while ($input !~ /^[YyNn]/) { 
	    print "$summary_file already exists.  Do you want to overwrite it (y/n)?  ";
	    $input = <STDIN>;

	    if ($input =~ /^[Nn]/) {
		die "Existing script...\n";
	    }
	}
    }
}

################################################################################
# Get the arguments

sub get_args($) {

    my (@seqFiles, $blastType, $arg, $displayHitNumber, $make_blast_log);
    my ($seq_list_file, $seq_file_list);

    my $args = shift;

    $blastType = "";

    # check the arguments for values
    foreach $arg (@$args) {

        if ($arg =~ /^\-t=(.+)$/) {    # blast type
            $blastType = $1;
        } elsif ($arg =~ /^\-n=(.+)$/) {     # number of hits to display
            $displayHitNumber = check_hit_display_number($1);
        } elsif ($arg =~ /^\-log$/) {        # provide log file of blast results
	    $make_blast_log = 1;
        } elsif ($arg =~ /^\-q(uick)?$/) {   # run quick, insensitive blast
	    $quick_blast = 1;
        } elsif ($arg =~ /^\-f=(.+)/) {      # provided file containing list of seq files
	    $seq_list_file = $1;
	} elsif ($arg eq "-auto") {
	    $interactive = 0;
	} elsif ($arg =~ /^\-v(erbose)?$/) { # verbose mode
            $verbose = 1;
        } elsif ($arg =~ /^\-h(elp)?/) {     # help mode
            die $usage;
        } elsif ($arg =~ /^([^-].+)/) {
            push(@seqFiles, $1);
        } else {
            die "Unrecognised argument format. See below for usage.\n\n" . $usage;
        }
    } ## end foreach $arg (@$args)

    if ($seq_list_file) {
	get_list_of_seq_files($seq_list_file, @seqFiles);
    }

    organise_inputted_seq_files(@seqFiles);

    if (!$displayHitNumber) {
        $displayHitNumber = 3;
    }

    return ($blastType, $displayHitNumber, \@seqFiles, $make_blast_log);
}

################################################################################
# main function

sub main(\@) {

    my ($blastOutputFile, $blastType, $acc, $file, $make_blast_log, $gene);
    my ($seqFiles, $counter, $fileNamePrefix, $fileNameSuffix, $blastDBlocn);
    my (@blastOutputFiles, $displayHitNumber, $summary_file, $BLASTSUMM);
    my ($no_blast_match, $org, @no_blast_match_files, $no_hits_file);

    my $args = shift;

    ($blastType, $displayHitNumber, $seqFiles, $make_blast_log) = get_args($args);

    if ($blastType eq "") {

	# check env is prepped for running SRS
	if (!defined($ENV{SRSROOT})) {
	    die "Please run:\n"
		. "source /ebi/production/extsrv/srs/srs7/srs7pub/etc/prep_srs\n"
		. "before running this script.\nIf that doesn't work, SRS is down...\n";
	}
        ($gene, $org) = get_gene_and_org(@$seqFiles);
    } else {
        $blastType = get_blast_type($blastType);
    }

    if ($verbose && $interactive) {
        print "\nUsing seq files :  " . join(", ", @$seqFiles) . "\n";

        if (!$blastType) {
            print "Using gene \"$gene\" and genus \"$org\" from input files\n\n";
        } else {
            print "Using blast type:  $blastType\n\n";
        }
    } ## end if ($verbose)

    if ($gene && $org) {
        $blastDBlocn = create_blastable_db($gene, $org);
    } elsif ($blastType eq "16S") {
	if ($quick_blast) {
	    $blastDBlocn = "$blastableDir/16Score";
	}
	else {
	    $blastDBlocn = "$blastableDir/silva_rRNA/EBI_refs.fasta";
	}
    }

    if ($quick_blast) {
	$summary_file = "blast16S_summary";
    } 
    else {
	$summary_file = "blast16S_sens_summary";
    }

    $interactive && show_overwrite_warning($summary_file);

    open($BLASTSUMM, ">".$summary_file) || die "Cannot write to $summary_file\n";

    $counter = 1;

    foreach $file (@$seqFiles) {

        if ($verbose && $interactive) {
            print "Processing $file...\n\n";
        }

        $blastOutputFile = "blast" . $blastType . "_$counter.output";
        push(@blastOutputFiles, $blastOutputFile);

        generate_blast_output($file, $blastOutputFile, $blastDBlocn);

        # .sub and .temp sequence files contain no accession, so use the
        # filename as an accession (printed in the output)
        ($fileNamePrefix, $fileNameSuffix) = split(/\./, $file);
        if (($fileNameSuffix ne 'fflupd') && ($fileNameSuffix ne 'ffl')) {
            $acc = $fileNamePrefix;
        } else {
            $acc = "";
        }

        $no_blast_match = parse_blast_output($blastOutputFile, $acc, $displayHitNumber, $BLASTSUMM);

	if ($no_blast_match) {
	    push(@no_blast_match_files, $file);
	}

        $counter++;
    } ## end foreach $file (@$seqFiles)

    close($BLASTSUMM);


    if (@no_blast_match_files) {
	$no_hits_file = "blast16S_nomatches";
	make_file_of_no_hit_entries(@no_blast_match_files, $no_hits_file);

	if ($interactive) {
	    if ($quick_blast) {
		print scalar(@no_blast_match_files)." file(s) have been found containing entries which didn't look like rRNAs.  These are listed in '$no_hits_file'.  Please run:\nblast16S_sens -f=blast16S_nomatches\n...to check them against a larger set of rRNA sequences.\n\n";
	    }
	    else {
		print "No hits were found for the files found in '$no_hits_file' in the larger Silva rRNA database i.e. this sequence may not have a rRNA-like structure.\n\n";
	    }
	}
    }

    $interactive && print "A summary of the output can be found in $summary_file\n";

    if ($make_blast_log) {
	concatentate_blast_results_into_log(@blastOutputFiles);
    }
    else {
	delete_blast_results(@blastOutputFiles);
    }

} ## end sub main(\@)

################################################################################
# run the script

main(@ARGV);
