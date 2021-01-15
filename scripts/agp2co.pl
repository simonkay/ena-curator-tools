#!/ebi/production/seqdb/embl/tools/bin/perl -w

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;    ########

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
my $suspiciouslyShortLength = 10;
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

sub readSkelFile($) {
    my $skelfileName = shift;
    $verbose && print STDERR "Reading skeleton file \"$skelfileName\"\n";
    open(SKEL, "< $skelfileName") || die "cannot open skeleton file $skelfileName: $!\n";
    my $skelfileContents = do { local $/; <SKEL> };
    close(SKEL);
    $verbose && print STDERR "SKEL=\n$skelfileContents\n";
    return $skelfileContents;
} ## end sub readSkelFile($)

sub isSkelGood($) {
    my $skelfileContents = shift;
    my $ok               = 1;
    foreach my $token (keys %replaceTokens) {
        my $tokenCount = $skelfileContents =~ s/($replaceTokens{$token}{'REGEXP'})/$1/gs;
        $verbose and print STDERR "Skeleton file contains $tokenCount x $replaceTokens{$token}{'STRING'}\n";
        if ($tokenCount == 0) {
            print STDERR "ERROR: " . $replaceTokens{$token}{'STRING'} . " not found in skel file\n";
            $ok = 0;
        } elsif (   ($tokenCount < 3)
                 && ($token eq "SeqLen")) {
            print STDERR "ERROR: " . $replaceTokens{$token}{'STRING'} . " should be in the skeleton at least 3 times, not just $tokenCount\n\n";
            $ok = 0;
        }
    } ## end foreach my $token (keys %replaceTokens)
    return $ok;
} ## end sub isSkelGood($)

sub fillSegmentName2AcLenHash($\%) {
    my $bulkFileName         = shift;
    my $rh_segmentName2AcLen = shift;
    open(IN, "< $bulkFileName") || return;
    my $contigname   = "";
    my $contigac     = "";
    my $seqLen       = 0;
    my $segmentCount = 0;
    my $sequenceVersionWarning;
    my $sequenceLengthWarning;

    while (my $line = <IN>) {
        chomp($line);
        if ($line =~ /^ID   (.*)$/) {
            my @id = split(/; */, $1);
            if (scalar(@id) != 7) {
                die("$_ seems to have " . scalar(@id) . " pieces and not 7\n");
            }

            if ($id[1] =~ /SV (\d+)/) {
                $contigac = "$id[0].$1";
            } else {
                $contigac               = "$id[0].1";
                $sequenceVersionWarning = 1;
            }
            if ((defined($id[6])) && ($id[6] =~ /(\d+) BP/)) {
                $seqLen = $1;
            } else {
                $sequenceLengthWarning = 1;
            }
        } elsif ($line =~ /^DE   .*\s(\S+)\s*$/) {
            $contigname = $1;
        } elsif ($line =~ /^\/\//) {
            $segmentCount++;
            if ($verbose
                && (($segmentCount % 100) == 0)) {
                print STDERR "$segmentCount segments read\n";
            }
            if (   ($contigac eq '')
                || ($contigname eq '')) {
                print STDERR "Segment $segmentCount (ending on line $.) has AC=$contigac, name=$contigname\n";
            } else {
                if (defined($$rh_segmentName2AcLen{$contigname})) {
                    print STDERR "Segment $contigname appears more than once\n";
                } else {
                    ${$rh_segmentName2AcLen}{$contigname}->{'AC'}     = $contigac;
                    ${$rh_segmentName2AcLen}{$contigname}->{'length'} = $seqLen;
                }
            } ## end else [ if (($contigac eq '') ...
            $contigac   = "";
            $contigname = "";
            $seqLen     = 0;
        } ## end elsif ($line =~ /^\/\//)
    } ## end while (my $line = <IN>)
    close(IN);
    $sequenceVersionWarning
      && print STDERR "WARNING: $bulkFileName lacked sequence version numbers, I assume it is 1\n";
    $sequenceLengthWarning
      && print STDERR "WARNING: $bulkFileName lacked sequence lengths on ID lines\n";
    my $badCount = $segmentCount - scalar(keys %{$rh_segmentName2AcLen});
    $verbose && print STDERR "$segmentCount segments read, $badCount were bad\n";
    return ($badCount == 0);    # ie any bad returns 1, else 0
} ## end sub fillSegmentName2AcLenHash($\%)

sub mapSegmentName2Ac($\%) {
    my $name                 = shift;
    my $rh_segmentName2AcLen = shift;
    if (!(exists(${$rh_segmentName2AcLen}{$name}->{'AC'}))) {
        print STDERR "!! ERROR: Could not resolve contig name $name\n";
        $$rh_segmentName2AcLen{$name}->{'AC'}     = $name;
        $$rh_segmentName2AcLen{$name}->{'length'} = 0;
    }
    return (${$rh_segmentName2AcLen}{$name}->{'AC'});
} ## end sub mapSegmentName2Ac($\%)

sub mapSegmentName2Len($\%) {
    my $name              = shift;
    my $rh_segmentName2Ac = shift;
    if (!(exists(${$rh_segmentName2Ac}{$name}->{'length'}))) {
        die("Cannot find any sequence length for $name\n");
    }
    return ${$rh_segmentName2Ac}{$name}->{'length'};
} ## end sub mapSegmentName2Len($\%)

sub initialize_object($) {
    my $name = shift;

    my @components = ();
    my %object = ('name'       => $name,
                  'length'     => 0,
                  'unoriented' => 0,
                  'components' => \@components);
    return %object;
} ## end sub initialize_object($)

sub read_agp($\@) {
    my $in     = shift;
    my $ra_agp = shift;    # list of all objecte (ie CONs)

    my %current_object;    # object - has $name, $length, $unoriented and array of components

    while (my $line = <$in>) {
        chomp($line);
        if ($line =~ /^\s*$/) {
            next;
        }

        # parses agp lines - see http://www.ncbi.nlm.nih.gov/projects/genome/assembly/agp/AGP_Specification.shtml
        my @columns = split(/\s+/, $line);

        if ((scalar(@columns) < 8) ||    # agp files can currently have 8 columns if line is a gap
            (scalar(@columns) > 9)
          ) {
            die scalar(@columns) . " columns (not 8 or 9) in line $line\n";
        }

        my ($object, $object_beg, $object_end, $part_number, $component_type) = @columns[ 0, 1, 2, 3, 4 ];

        # create new object if we've just started, else store old object if moved onto a new one
        if (!(%current_object)) {
            %current_object = initialize_object("$object");
        } elsif ($current_object{name} ne $object) {
            my %object = %current_object;    # need to make copy else it reuses the same variable address
            push(@{$ra_agp}, \%object);

            # oddly, despite the next two steps, \%current_object is reused
            undef(%current_object);
            %current_object = initialize_object("$object");
        } ## end elsif ($current_object{name...

        if ($part_number != scalar(@{ $current_object{'components'} } + 1)) {
            printf STDERR "! %s has %d parts but new part is numbered %d\n", $current_object{'name'}, scalar(@{ $current_object{components} }), $part_number;
        }

        # test there is no overlap in current object locations
        if ($object_beg != $current_object{length} + 1) {
            die(sprintf "ERROR %s, new part trying to use %d-%d but we have already reached base %d\nline: %s",
                $current_object{'name'}, $object_beg, $object_end, $current_object{'length'}, $line);
        }

        # now deal with the specifics of the component
        if (   (!(exists($agpComponents{$component_type})))
            || (!(defined($agpComponents{$component_type})))) {
            die "Illegal component type $component_type in line $line\n";
        }

        my $object_span_length = ($object_end - $object_beg) + 1;

        if ($agpComponents{$component_type} eq 'entry') {

            # normal segment
            my ($component_id, $component_beg, $component_end, $orientation) = @columns[ 5, 6, 7, 8 ];

            my $component_length = ($component_end - $component_beg) + 1;
            if ($component_length != $object_span_length) {
                printf STDERR "! %s has span of %d (%d-%d) covered by %s span of %d (%d-%d)\n", $current_object{name}, $object_span_length, $object_beg,
                  $object_end, $component_id, $component_length, $component_beg, $component_end;
            }
            $current_object{'length'} += $component_length;

            my %component = ('name'          => $component_id,
                             'type'          => 'contig',
                             'orientation'   => $orientation,
                             'component_beg' => $component_beg,
                             'component_end' => $component_end,
                             'length'        => $component_length);
            if (($orientation ne "+") && ($orientation ne "-")) {
                $current_object{'unoriented'} = 1;
            }

            push(@{ $current_object{components} }, \%component);
        } elsif ($agpComponents{$component_type} eq 'gap') {
            my ($component_length, $gap_type, $linkage) = @columns[ 5, 6, 7 ];    # column 9 is not currently used on gaps
                                                                                  # should use linkage to verify gap type
            if (($component_length * 1) ne $component_length) {
                die "this line says it is a gap, but there is no gap length\n$line\n";
            }

            if ($component_length != $object_span_length) {
                printf STDERR "! %s has span of %d (%d-%d) covered by gap of %d\n", $current_object{name}, $object_span_length, $object_beg, $object_end,
                  $component_length;
            }
            $current_object{'length'} += $component_length;

            my %component = ('type'   => 'gap',
                             'length' => $component_length);
            push(@{ $current_object{components} }, \%component);
        } elsif ($agpComponents{$component_type} eq 'unknown gap') {
            my ($component_length, $gap_type, $linkage) = @columns[ 5, 6, 7 ];    # column 9 is not currently used on gaps
                                                                                  # should use linkage to verify gap type
            if (($component_length * 1) ne $component_length) {
                die "this line says it is a gap, but there is no gap length\n$line\n";
            }

            if ($component_length != 100) {
                printf STDERR "! %s has span of %d (%d-%d) covered by unknown gap of illegal length %d\n", $current_object{name}, $object_span_length,
                  $object_beg, $object_end, $component_length;
                $component_length = 100;
            }

            if ($component_length != $object_span_length) {
                printf STDERR "! %s has span of %d (%d-%d) covered by unknown gap of %d\n", $current_object{name}, $object_span_length, $object_beg,
                  $object_end, $component_length;
            }
            $current_object{'length'} += $component_length;

            my %component = ('type'   => 'gap',
                             'length' => "unk100");
            push(@{ $current_object{components} }, \%component);
        } ## end elsif ($agpComponents{$component_type...
    } ## end while (my $line = <$in>)
    if (%current_object) {
        my %object = %current_object;    # need to make copy else it reuses the same variable address
        push(@{$ra_agp}, \%object);
    }
} ## end sub read_agp($\@)

sub putAcInAgp(\@\%) {
    my $ra_agp               = shift;
    my $rh_segmentName2AcLen = shift;
    foreach my $rh_object (@{$ra_agp}) {
        foreach my $rh_component (@{ ${$rh_object}{'components'} }) {
            if (${$rh_component}{'type'} eq "contig") {
                ${$rh_component}{'AC'} = mapSegmentName2Ac(${$rh_component}{'name'}, %{$rh_segmentName2AcLen});
            }
        }
    }
} ## end sub putAcInAgp(\@\%)

sub checkForTinySegments(\@) {
    my $ra_agp = shift;    # list of all objecte (ie CONs)
    foreach my $rh_object (@{$ra_agp}) {
        foreach my $rh_component (@{ ${$rh_object}{'components'} }) {
            if (   (${$rh_component}{'type'} eq "contig")
                && (${$rh_component}{'length'} < $suspiciouslyShortLength)) {
                printf STDERR ("! %s object contains component %s (%s) which is only %bp long\n",
                               ${$rh_object}{'name'},
                               ${$rh_component}{'AC'},
                               ${$rh_component}{'name'},
                               ${$rh_component}{'length'});
            } elsif (   (${$rh_component}{'type'} eq "gap")
                     && (${$rh_component}{'length'} < $suspiciouslyShortLength)) {
                printf STDERR ("! %s object contains gap which is only %bp long\n", ${$rh_object}{'name'}, ${$rh_component}{'length'});
            }
        } ## end foreach my $rh_component (@...
    } ## end foreach my $rh_object (@{$ra_agp...
} ## end sub checkForTinySegments(\@)

sub checkForOvershotComponents(\@\%) {
    my $ra_agp               = shift;
    my $rh_segmentName2AcLen = shift;
    foreach my $rh_object (@{$ra_agp}) {
        foreach my $rh_component (@{ ${$rh_object}{'components'} }) {
            if (${$rh_component}{'type'} eq "contig") {
                my $componentTotalLength = mapSegmentName2Len(${$rh_component}{'name'}, %{$rh_segmentName2AcLen});
                if ($componentTotalLength < ${$rh_component}{'component_end'}) {
                    die(sprintf "! Object %s contains %s:%d..%d but true length of %s is only %d",
                        ${$rh_object}{'name'},
                        ${$rh_component}{'AC'},
                        ${$rh_component}{'component_beg'},
                        ${$rh_component}{'component_end'},
                        ${$rh_component}{'name'},
                        $componentTotalLength);
                } ## end if ($componentTotalLength...
            } ## end if (${$rh_component}{'type'...
        } ## end foreach my $rh_component (@...
    } ## end foreach my $rh_object (@{$ra_agp...
} ## end sub checkForOvershotComponents(\@\%)

sub checkForTerminalGaps(\@) {
    my $ra_agp = shift;
    foreach my $rh_object (@{$ra_agp}) {
        my %firstComponent = %{ ${ ${$rh_object}{'components'} }[0] };
        if ($firstComponent{'type'} ne 'contig') {
            printf STDERR "! Object %s begins with a component of type %s\n", ${$rh_object}{'name'}, $firstComponent{'type'};
        }
        my %lastComponent = %{ ${ ${$rh_object}{'components'} }[-1] };
        if ($lastComponent{'type'} ne 'contig') {
            printf STDERR "! Object %s ends with a component of type %s\n", ${$rh_object}{'name'}, $firstComponent{'type'};
        }
    } ## end foreach my $rh_object (@{$ra_agp...
} ## end sub checkForTerminalGaps(\@)

sub checkForRepeatedObjects(\@) {
    my $ra_agp = shift;
    my %objectNames;
    foreach my $rh_object (@{$ra_agp}) {
        if (!(defined($objectNames{ ${$rh_object}{'name'} }))) {
            $objectNames{ ${$rh_object}{'name'} } = 1;
        } else {
            $objectNames{ ${$rh_object}{'name'} }++;
        }
    }

    foreach my $name (sort keys %objectNames) {
        if ($objectNames{$name} > 1) {
            printf STDERR "! The object %s has been mentioned separately %d times\n", $name, $objectNames{$name};
        }
    }
} ## end sub checkForRepeatedObjects(\@)

sub writeComponent(\%) {
    my $rh_component = shift;
    if (${$rh_component}{'type'} eq "contig") {
        my $text = sprintf("%s:%d..%d", ${$rh_component}{'AC'}, ${$rh_component}{'component_beg'}, ${$rh_component}{'component_end'});
        if (${$rh_component}{'orientation'} eq '-') {
            $text = "complement(" . $text . ")";
        }
        return ($text);
    } else {
        return ("gap(" . ${$rh_component}{'length'} . ")");
    }
} ## end sub writeComponent(\%)

sub writeAgpToCon($\@$) {
    my $skelfileContents = shift;
    my $ra_agp           = shift;
    my $out              = shift;

    foreach my $rh_object (@{$ra_agp}) {
        my $conEntry   = $skelfileContents;
        my $contigName = ${$rh_object}{'name'};
        if (${$rh_object}{'unoriented'}) {
            $contigName = "unoriented $contigName";
        }
        $conEntry =~ s/$replaceTokens{'SuperConName'}{'REGEXP'}/$contigName/gs;
        $conEntry =~ s/$replaceTokens{'SeqLen'}{'REGEXP'}/${$rh_object}{'length'}/gs;

        my $coBlock;
        my @coElements = map { writeComponent(%{$_}) } @{ ${$rh_object}{'components'} };
	$coBlock = "join(" . join(",\nCO   ", @coElements) . ")";
        $conEntry =~ s/$replaceTokens{'COlines'}{'REGEXP'}/CO   $coBlock/s;
        print $out $conEntry;
    } ## end foreach my $rh_object (@{$ra_agp...
} ## end sub writeAgpToCon($\@$)

sub main {
    my $agpfilename;
    my $skelfileName;
    my $confilename  = "CONS.ffl";
    my $bulkfilename = "BULK.ffl";

    my $usage =
        "\n PURPOSE: Create CON files from an AGP file\n\n"
      . " USAGE:   $0\n"
      . "          -s=<file> -a=<file> [-b=<file> [-c=<file>] [-v]\n"
      . "                              --\n"
      . "          -s(kelfile)=<file>  Name of input skeleton file\n"
      . "          -a(gpfile)=<file>   Name of input AGP file\n"
      . "          -b(ulkfile)=<file>  Name of bulk file containing segments (default = $bulkfilename)\n"
      . "          -c(onfile)=<file>   Name of output CON file (default is $confilename)\n"
      . "          -v(erbose)          Chatty output to let you know what is happening\n"
      . "                              --\n"
      . "                              Skeleton should contain:\n"
      . "                              $replaceTokens{'SeqLen'}{'STRING'} for seq length of CON\n"
      . "                              $replaceTokens{'COlines'}{'STRING'} where the CO lines will be placed\n"
      . "                              $replaceTokens{'SuperConName'}{'STRING'} for name of the CON\n"
      . "                              --\n"
      . "                              Bulkfile should contain:\n"
      . "                              Accessions\n"
      . "                              The segment name as the last token on the DE line\n"
      . "                              --\n";

    GetOptions("skelfile=s"    => \$skelfileName,
               "agpfile=s"     => \$agpfilename,
               "bulkfile=s"    => \$bulkfilename,
               "confilename=s" => \$confilename,
               "verbose"       => \$verbose
    ) || die($usage);

    foreach my $arg (@ARGV) {
        if (!(defined($agpfilename))
            && ($arg =~ /\.agp$/i)) {
            $agpfilename = $arg;
        } elsif (!(defined($skelfileName))
                 && ($arg =~ /\.skel$/i)) {
            $skelfileName = $arg;
        }
        elsif (!(defined($confilename))
               && (   ($arg =~ /\.con$/i)
                   || (($arg =~ /\.sub$/i)))
          ) {
            $confilename = $arg;
        }
        elsif (!(defined($bulkfilename))
               && (   ($arg =~ /\.ffl$/i)
                   || (($arg =~ /\.sub$/i)))
          ) {
            $bulkfilename = $arg;
        } else {
            die "I don't know what you mean by \"$arg\"\n$usage\n";
        }
    } ## end foreach my $arg (@ARGV)

    my $skel;
    isGoodFile($skelfileName, "skeleton input file", "input") || die $usage;
    isGoodFile($agpfilename,  "AGP input file",      "input") || die $usage;
    system("/ebi/production/seqdb/embl/tools/curators/bin/agp_validate $agpfilename");
    isGoodFile($bulkfilename, "Bulk input file", "input")
      || print STDERR "\nWARNING No usable $bulkfilename to get contig name to accession mappings for segments\n"
      . " I'll proceed in the hope that the AGP already contains accessions\n\n";
    isGoodFile($confilename, "CON output file", "new output") || die $usage;

    my $skelfileContents = readSkelFile($skelfileName);
    isSkelGood($skelfileContents) || die $usage;

    my %segmentName2AcLen;
    fillSegmentName2AcLenHash($bulkfilename, %segmentName2AcLen);
    my $agp_fh;
    my $con_fh;
    open($agp_fh, "<$agpfilename") || die "Could not open agp file $agpfilename for reading: $!\n";
    my @agp;
    read_agp($agp_fh, @agp);
    close($agp_fh);
    putAcInAgp(@agp, %segmentName2AcLen);
    checkForOvershotComponents(@agp, %segmentName2AcLen);
    checkForTinySegments(@agp);
    checkForTerminalGaps(@agp);
    checkForRepeatedObjects(@agp);
    open($con_fh, ">$confilename") || die "Could not open con file $confilename for writing: $!\n";
    writeAgpToCon($skelfileContents, @agp, $con_fh);
    close($con_fh);
} ## end sub main

main();
