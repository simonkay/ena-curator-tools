#!/ebi/production/seqdb/embl/tools/bin/perl -w

use strict;
use warnings;
use Getopt::Long;

# inefficient holding all sequence for each con at once - ask farm for 70GB memory!
# bsub -M 70000 -q production -o /ebi/production/seqdb/embl/data/dirsub/ds/79762/v4/out.txt "fasta2agp_wgs.pl -f cynoGenom_v4.6.fa -a out.agp -w out.fa -v"

select(STDOUT);
$| = 1;              # make unbuffered
select(STDERR);
$| = 1;              # make unbuffered
my $verbose = 1;
my %replaceTokens = (
                     'SeqLen' => { 'STRING' => '{SL}',
                                   'REGEXP' => quotemeta('{SL}')
                     },
                     'COlines' => { 'STRING' => '{CO_lines}',
                                    'REGEXP' => quotemeta('{CO_lines}')
                     },
                     'SuperConName' => { 'STRING' => '{supercontig}',
                                         'REGEXP' => quotemeta('{supercontig}')
                     });
my $suspiciouslyShortLength = 10; # not yet used
my $maxNstretch = 49;
my $fastaWidth  = 60;
my $contigNamePrefix = "contig_";
my %agpComponents = ('A' => 'entry',          # Active Finishing
                     'D' => 'entry',          # Draft HTG (often phase1 and phase2)
                     'F' => 'entry',          # Finished HTG (phase 3)
                     'G' => 'entry',          # Whole Genome Finishing
                     'N' => 'gap',            # gap with specified size
                     'O' => 'entry',          # Other sequence (typically means no HTG keyword)
                     'P' => 'entry',          # Pre draft
                     'U' => 'unknown gap',    # gap of unknown size, typically defaulting to predefined values.
                     'W' => 'entry',          # WGS contig
);

sub isGoodFile($$$) {
    my $filename        = shift;
    my $fileDescription = shift;
    my $fileType        = shift;
    if (!(defined $filename)) {
        print STDERR "No $fileDescription provided\n";
        return 0;
    }
    if ($fileType eq "new output") {
        if (-e $filename) {
            print STDERR "$fileDescription \"$filename\" already exists, I'll have to ask you delete it before we proceed\n";
            return 0;
        }
    } elsif ($fileType eq "input") {
        if (!(-e $filename)) {
            print STDERR "$fileDescription \"$filename\" does not exist\n";
            return 0;
        }
        if (!(-R $filename)) {
            print STDERR "$fileDescription \"$filename\" is not readable\n";
            return 0;
        }
        if (!(-f $filename)) {
            print STDERR "$fileDescription \"$filename\" is not a valid text file\n";
            return 0;
        }
        if (!(-s $filename)) {
            print STDERR "$fileDescription \"$filename\" is empty\n";
            return 0;
        }
    } else {

        # I guess we don't care that much about the file
    }
    $verbose && print STDERR "$fileDescription \"$filename\" seems fine\n";
    return 1;
} ## end sub isGoodFile($$$)



sub terminalNsTrimStart(\@) {
    my $ra_sequence = shift;
    my $numberNs = 0;
    for (my $i = 0; $i < scalar(@{$ra_sequence}); $i++) {
	if (${$ra_sequence}[$i] ne 'n') {
	    $numberNs = $i;
	    last;
	}
    }
    if ($numberNs > 0) {
	splice(@{$ra_sequence}, 0, $numberNs);
    }
    return $numberNs;
}

sub terminalNsTrimEnd(\@) {
    my $ra_sequence = shift;
    my $numberNs = 0;
    for (my $i = 0; $i < scalar(@{$ra_sequence}); $i++) {
	if (${$ra_sequence}[-1 * ( 1 + $i)] ne 'n') {
	    $numberNs = $i;
	    last;
	}
    }
    if ($numberNs > 0) {
	splice(@{$ra_sequence}, (-1 * $numberNs));
    }
    return $numberNs;
}

sub checkForTerminalNs($\@) {
    my $replicon = shift;
    my $ra_sequence = shift;

    my $startNs = terminalNsTrimStart(@{$ra_sequence});
    my $endNs   = terminalNsTrimEnd(@{$ra_sequence});

    if(($startNs != 0) || ($endNs != 0)) {
	printf STDERR "%s had terminal N's removed (%d from start. %d from end)\n", $replicon, $startNs, $endNs;
    }
    return;

}

sub findSegments($\@){
    my $replicon = shift;
    my $ra_sequence = shift;
    my $totalGapNs = 0;

    my @segments;
    my $currentGapStart;
    my $lastContigStart = 0;
    
    for (my $i = 0; $i < scalar(@{$ra_sequence}); $i++) {
	if ((${$ra_sequence}[$i] eq 'n') &&
	    (!(defined($currentGapStart)))) {

	    # something else to 
	    $currentGapStart = $i;
	} elsif ((${$ra_sequence}[$i] ne 'n') &&
		 (defined($currentGapStart))) {
	    my $gapLength = $i - $currentGapStart;
	    $totalGapNs += $gapLength;
	    if ( $gapLength > $maxNstretch) {
		my %contig = ('type'   => 'contig',
			      'start'  => $lastContigStart,
			      'end'    => $currentGapStart - 1
		    );
		$lastContigStart = $i;

		my %gap = ('type'   => 'gap',
			   'start'  => $currentGapStart,
			   'end'    => $i - 1
		    );


		push(@segments, \%contig, \%gap);
	    }
	    undef($currentGapStart); # if stored or if small, forget gap
	}
    }

    my %contig = ('type'   => 'contig',
		  'start'  => $lastContigStart,
		  'end'    => scalar(@{$ra_sequence}) - 1
	);
    push(@segments, \%contig);

    
    print STDERR "replicon $replicon has ".((1 + scalar(@segments))/2)." contigs and $totalGapNs Ns:\n";
    return(\@segments);
}



sub printSegments($$$\@\@){
    my $agp_fh = shift;
    my $wgs_fh = shift;
    my $replicon = shift;
    my $ra_sequence = shift;
    my $ra_segments = shift;

    my $contigs = (1 + scalar(@{$ra_segments}))/2;
    my $contigNumberWidth = length("$contigs");

    my $segmentNumber = 1;     
    foreach my $rh_segment (@{$ra_segments}) {
	my $seg_type  = ${$rh_segment}{'type'};
	my $seg_start = ${$rh_segment}{'start'};
	my $seg_end   = ${$rh_segment}{'end'};

	printf $agp_fh "%s\t%d\t%d\t%d\t", $replicon, ($seg_start + 1), ($seg_end + 1), $segmentNumber;

	if (${$rh_segment}{'type'} eq "contig") {
	    my $component_id = sprintf "%s_%0" . $contigNumberWidth . "d", $replicon, ((1 + $segmentNumber)/2);
	    printf $agp_fh "%s\t%s\t%d\t%d\t%s\n", 'W', $component_id, 1, (1 + ($seg_end - $seg_start)), '+';

	    print $wgs_fh ">" . $component_id;
	    for (my $i = $seg_start; $i <= $seg_end; $i++) {
		((($i - $seg_start) % $fastaWidth) == 0) && print $wgs_fh "\n";
		print $wgs_fh ${$ra_sequence}[$i];
	    }
	    print $wgs_fh "\n";
	} else {
	    printf $agp_fh "%s\t%d\t%s\t%s\n", 'N', (1 + ($seg_end - $seg_start)), 'fragment', 'yes';
	}

	$segmentNumber++;
    }
}

sub processSeq($$$\@){
    my $agp_fh = shift;
    my $wgs_fh = shift;
    my $replicon = shift;
    my $ra_sequence = shift;

    print STDERR "$replicon sequence was ".scalar( @{$ra_sequence})." long\n";
    $verbose && print STDERR "checking for terminal Ns\n";
    checkForTerminalNs($replicon,@{$ra_sequence});
    $verbose && print STDERR "checking for gaps\n";

    my $ra_segments = findSegments($replicon, @{$ra_sequence});

# should also have a step to disappear contigs < $minContigLength

    printSegments($agp_fh,$wgs_fh, $replicon, @{$ra_sequence},@{$ra_segments});
    return;
}

sub main {
    my $fastaInFileName;

    my $agpOutFileName = "out.agp";
    my $wgsOutFileName = "WGS.fasta";

    my $usage =
        "\n PURPOSE: Take scaffold sequences in fasta form and create a WGS contig fasta"
      . "            and AGP file\n\n"
      . " USAGE:   $0\n"
      . "          -f=<file> [-a=<file>] [-w=<file>] [-v]\n"
      . "                              --\n"
      . "          -f(astafile)=<file> Name of input fasta file\n"
      . "          -a(gpfile)=<file>   Name of output AGP file (default = $agpOutFileName)\n"
      . "          -w(gsfile)=<file>   Name of output WGS fasta file (default = $wgsOutFileName)\n"
      . "          -v(erbose)          Chatty output to let you know what is happening\n\n";

    GetOptions("fastafile=s"   => \$fastaInFileName,
               "agpfile=s"     => \$agpOutFileName,
               "wgsfile=s"     => \$wgsOutFileName,
               "verbose"       => \$verbose
    ) || die($usage);

    foreach my $arg (@ARGV) {
        if (!(defined($fastaInFileName))
            && ($arg =~ /\.fa(sta)?$/i)
	    && (-e $arg)
	    && (-t $arg)) {
            $agpOutFileName = $arg;
        } else {
            die "I don't know what you mean by \"$arg\"\n$usage\n";
        }
    } ## end foreach my $arg (@ARGV)

    isGoodFile($fastaInFileName, "fasta input file",          "input") || die $usage;
    isGoodFile($agpOutFileName,  "AGP out file",              "new output") || die $usage;
    isGoodFile($wgsOutFileName,  "WGS fasta contig out file", "new output") || die $usage;
#    system("/ebi/production/seqdb/embl/tools/curators/bin/agp_validate $agpfilename");

    open (my $in_fh, "<$fastaInFileName") || die "Could not open infile $fastaInFileName for reading: $!\n";
    open (my $agp_fh, ">$agpOutFileName") || die "Could not open outfile $agpOutFileName: $!\n";
    open (my $wgs_fh, ">$wgsOutFileName") || die "Could not open outfile $wgsOutFileName: $!\n";

    print STDERR "looking for gaps > $maxNstretch Ns\n";

    my $replicon = "";
    my $segmentNumber = 0;
    my $pendingSequence = "";
    while (my $line = <$in_fh>) {
	chomp($line);
	if ($line =~ />(.*)/) {
	    if ($replicon ne "") {
		my @sequence = split(//,$pendingSequence); # should store in an array at start
		$pendingSequence = "";
		processSeq($agp_fh,$wgs_fh,$replicon,@sequence);
	    }
	    $replicon = $1;
	    print STDOUT "found $replicon\n";
	    $segmentNumber = 1;
	} else {
	    $line =~ s/\s+//g;
	    $pendingSequence .= lc($line); # case insensitive - everything to lower
	}
    }
    if ($replicon ne "") {
		my @sequence = split(//,$pendingSequence); # should store in an array at start
		$pendingSequence = "";
		processSeq($agp_fh,$wgs_fh,$replicon,@sequence);
    }    
    close ($wgs_fh);
    close ($agp_fh);
    close ($in_fh);
} ## end sub main

main();
