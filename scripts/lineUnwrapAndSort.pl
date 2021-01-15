#!/ebi/production/seqdb/embl/tools/bin/perl -w

#===============================================================================
# (C) EBI 2008 Nadeem Faruque
#
# script implement various EMBL-file reformattings and checks
# unwraps entries
# removes qualifiers with blank values
# strips leading/trailing whitespace from qualifier values
# removes replicate qualifier lines within a feature
# Optionally: removes db_xref, transl_table, translation, protein_id, codon_start=1
# Optionally: optionally sorts qualifier types alphabetically
# Optionally: sorts the feature table
#
# Details:-
#
#  HISTORY
#  =======
#  Nadeem Faruque   23-APR-2008 Created
#
#===============================================================================

use strict;
use Getopt::Long;
use SeqDBUtils2 qw(get_input_files get_locus_tag_from_project);
use DBI;

# debug lines
#use Data::Dumper;
#select(STDERR); $| = 1;
#select(STDOUT); $| = 1;

my $TEMPFILESUFFIX = ".ftfixtemp.del";
my $OLDFILESUFFIX  = ".pre-ftfix.del";
my $TAGCLOUDSUFFIX = ".notetagcloudwords.del";
my $fts_output_log = "./ftsort3.output";

# run settings
my $doStrip        = 0;
my $doSort         = 0;
my $doFts          = 0;
my $doPeptideFix   = 0;
my $doGeneLocusFix = 0;
my $doGeneStrip;
my $doSpanCheck            = 0;
my $doObsoleteFeatureFix   = 0;
my $doComplement_loc_fix   = 0;
my $quiet                  = 0;
my $verbose                = 0;
my $writeToFile            = 0;
my $doTagCloud             = 0;
my $doStats                = 0;
my $doGeneCdsLocusTagMerge = 1;    # default behaviour at the moment
my $runValidator           = 0;
my $doQualFix              = 0;
my $qual_report_min        = 3;    # only display incidence of /note qualifers if there are 3 or more of them
my $pdid                   = 0;    # project id (datalib.project.projectid
my $help                   = 0;
my $doTranslationStrip     = 0;

my $run_blast16S           = 0;
my $noteWordFile;
my $outHandle; # filehandle to STDOUT or if in write_file mode, to a file to be filled with the updated data
my $log_fh; # filehandle used in every subroutine - collects output from script 

sub log_message($) {
    my $message = shift;
    $quiet || print STDERR $message;
    if (defined($log_fh)) {
	print $log_fh $message;
    }
}

# pushNewFeatureQualifier adds a new qualifier to the list (unless it is a duplicate)
sub pushNewFeatureQualifier (\@%) {
    my $ra_qualifiers = shift;
    my $newQual       = shift;

    if (   (exists($newQual->{'VAL'}))
        && ($newQual->{'VAL'} =~ s/ {2,}/ /g)) {
        $verbose && log_message(sprintf "extra spaces removed from /%s=%s\n", $newQual->{'QUAL'}, $newQual->{'VAL'});
    }

    foreach my $qual (@{$ra_qualifiers}) {
        if (exists($newQual->{'VAL'})) {
            if (   ($qual->{'QUAL'} eq $newQual->{'QUAL'})
                && ($qual->{'VAL'} eq $newQual->{'VAL'})) {
                $verbose && log_message(sprintf "discarding duplicate qualifier /%s=%s\n", $newQual->{'QUAL'}, $newQual->{'VAL'});
                return;
            }
        } else {
            if ($qual->{'QUAL'} eq $newQual->{'QUAL'}) {
                $verbose && log_message(sprintf "discarding duplicate qualifier /%s\n", $newQual->{'QUAL'});
                return;
            }
        }
    } ## end foreach my $qual (@{$ra_qualifiers...
    if ($doSort) {
        @{$ra_qualifiers} = sort { return $a->{'QUAL'} cmp $b->{'QUAL'}; } (@{$ra_qualifiers}, $newQual);
    } else {
        push(@${ra_qualifiers}, $newQual);
    }
    return;
} ## end sub pushNewFeatureQualifier (\@%)

sub fix_complement_location($) {
    my $string = shift;

    my @locations = $string =~ /\b((\d+)(\.\.|\^)(\d+))\b/g;
    for (my $i = 0 ; $i < scalar(@locations) ; $i += 4) {
        my $replace =
            ($locations[ $i + 1 ] < $locations[ $i + 3 ] ? $locations[ $i + 1 ] : $locations[ $i + 3 ])
          . $locations[ $i + 2 ]
          . ($locations[ $i + 1 ] > $locations[ $i + 3 ] ? $locations[ $i + 1 ] : $locations[ $i + 3 ]);
        if ($locations[ $i + 0 ] ne $replace) {
            $verbose && log_message("location fix: $locations[$i+0] -> $replace\n");
            my $orig = quotemeta($locations[ $i + 0 ]);
            ${$string} =~ s/$orig/$replace/;
        }
    } ## end for (my $i = 0 ; $i < scalar...
    return $string;
} ## end sub fix_complement_location($)

sub list_gene_and_synonym_of_feature(\$) {
    my $r_feature = shift;
    my %symbolHash;
    foreach my $qual (@{ ${$r_feature}->{'QUALS'} }) {
        if (   ($qual->{'QUAL'} eq "gene")
            || ($qual->{'QUAL'} eq "gene_synonym")) {
            $symbolHash{ $qual->{'VAL'} } = 1;
        }
    }
    return sort (keys %symbolHash);
} ## end sub list_gene_and_synonym_of_feature(\$)

sub cleanGeneFromSymbolList ($@) {
    my $gene            = shift;
    my @geneAndSynonyms = @_;
    my @cleanList       = ();
    foreach my $symbol (@geneAndSynonyms) {
        if ($symbol ne $gene) {
            push(@cleanList, $symbol);
        }
    }
    return @cleanList;
} ## end sub cleanGeneFromSymbolList ($@)

sub repairGeneAndSynonymsInFeature (\$$@) {
    my $r_feature       = shift;
    my $geneSymbol      = shift;
    my @geneAndSynonyms = @_;

    #    $verbose && print $log_fh " repairGeneAndSynonymsInFeature for$$r_feature->{'LOCUS'} \n";

    # remove gene from list of all symbols
    @geneAndSynonyms = cleanGeneFromSymbolList($geneSymbol, @geneAndSynonyms);

    # update feature metainformation
    $$r_feature->{'GENE'} = $geneSymbol;

    # update lines
    my @cleanedQualifiers = ();
    foreach my $qualifier (@{ ${$r_feature}->{'QUALS'} }) {
        if ($qualifier->{'QUAL'} eq 'gene') {
            my $newGeneQual = { 'QUAL' => 'gene',
                                'VAL'  => $geneSymbol };
            push(@cleanedQualifiers, $newGeneQual);
            foreach my $synonym (@geneAndSynonyms) {
                my $newSynQual = { 'QUAL' => 'gene_synonym',
                                   'VAL'  => $synonym };
                push(@cleanedQualifiers, $newSynQual);
            }
        } elsif ($qualifier->{'QUAL'} ne 'gene_synonym') {
            push(@cleanedQualifiers, $qualifier);
        }
    } ## end foreach my $qualifier (@{ $...
    $$r_feature->{'QUALS'} = \@cleanedQualifiers;
    $$r_feature->{'GENE'}  = $geneSymbol;
} ## end sub repairGeneAndSynonymsInFeature (\$$@)

sub printFeatures(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub printFeatures\n");
    foreach my $feature (@{$ra_features}) {
        if (scalar(@{ $feature->{'QUALS'} }) == 0) {
	    if ($feature->{'KEY'} ne 'D-loop') {
		log_message(sprintf "!! No qualifiers for %s at \"%s\"\n", $feature->{'KEY'}, $feature->{'LOCN'});
	    }
	}
        printf $outHandle "FT   %-16s%s\n", $feature->{'KEY'}, $feature->{'LOCN'};
        foreach my $qual (@{ $feature->{'QUALS'} }) {
            printf $outHandle "FT                   /%s%s\n", $qual->{'QUAL'}, ((exists($qual->{'VAL'})) ? "=" . $qual->{'VAL'} : "");
        }
    } ## end foreach my $feature (@{$ra_features...
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub printFeatures(\@)

sub showDuplicateFeatures(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub showDuplicateFeatures\n");
    my %featuresSeen;
    foreach my $feature (@{$ra_features}) {
        my $feat = $feature->{'KEY'} . " at " . $feature->{'LOCN'};
        if (exists($featuresSeen{$feat})) {
            $featuresSeen{$feat}++;
        } else {
            $featuresSeen{$feat} = 1;
        }
    } ## end foreach my $feature (@{$ra_features...
    foreach my $feat (keys %featuresSeen) {
        if ($featuresSeen{$feat} > 1) {
            log_message(sprintf "!%d x feature!:%s\n", $featuresSeen{$feat}, $feat);
        }
    }
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub showDuplicateFeatures(\@)

sub showDuplicateLabels(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub showDuplicateLabels\n");
    my %labelsSeen;
    $quiet || log_message("\nChecking for repeated labels\n");
    foreach my $feature (@{$ra_features}) {
        foreach my $qual (@{ $feature->{'QUALS'} }) {
            if ($qual->{'QUAL'} eq "label") {
                if (exists($labelsSeen{ $qual->{'VAL'} })) {
                    $labelsSeen{ $qual->{'VAL'} }++;
                } else {
                    $labelsSeen{ $qual->{'VAL'} } = 1;
                }
            }
        } ## end foreach my $qual (@{ $feature...
    } ## end foreach my $feature (@{$ra_features...
    my %problems;

    # Label is unusual and probably reflects misplaced information, report in ascending order of frequency
    foreach my $label (sort { $labelsSeen{$a} <=> $labelsSeen{$b} } (keys %labelsSeen)) {
        if ($labelsSeen{$label} > 1) {
            log_message(sprintf "!!%d x %s/label=%s\n", $labelsSeen{$label}, (($label =~ /\s/) ? "ILLEGAL " : ""), $label);
        }
    }
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub showDuplicateLabels(\@)

sub showDuplicateNotes(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub showDuplicateNotes\n");
    my %notesSeen;
    $quiet || log_message("\nChecking for repeated notes\n");
    foreach my $feature (@{$ra_features}) {
        foreach my $qual (@{ $feature->{'QUALS'} }) {
            if ($qual->{'QUAL'} eq "note") {
                if (exists($notesSeen{ $qual->{'VAL'} })) {
                    $notesSeen{ $qual->{'VAL'} }++;
                } else {
                    $notesSeen{ $qual->{'VAL'} } = 1;
                }
            }
        } ## end foreach my $qual (@{ $feature...
    } ## end foreach my $feature (@{$ra_features...

    # Label is unusual and probably reflects misplaced information, report in ascending order of frequency
    foreach my $note (sort { $notesSeen{$a} <=> $notesSeen{$b} } (keys %notesSeen)) {
        if ($notesSeen{$note} > $qual_report_min) {
            log_message(sprintf "%d x /note=%s\n", $notesSeen{$note}, $note);
        }
    }
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub showDuplicateNotes(\@)

sub fkeyQualStats(\@) {
    my $ra_features = shift;


    my $time1 = (times)[0];
    $verbose && log_message("Doing sub fkeyQualStats\n");
    my %featuresSeen;
    my %qualifiersSeen;
    $quiet || log_message("\nFinding qualifier and feature usage\n");
    foreach my $feature (@{$ra_features}) {

        if (exists($featuresSeen{ $feature->{'KEY'} })) {
            $featuresSeen{ $feature->{'KEY'} }++;
        } else {
            $featuresSeen{ $feature->{'KEY'} } = 1;
        }

        foreach my $qual (@{ $feature->{'QUALS'} }) {
            if (exists($qualifiersSeen{ $qual->{'QUAL'} })) {
                $qualifiersSeen{ $qual->{'QUAL'} }++;
            } else {
                $qualifiersSeen{ $qual->{'QUAL'} } = 1;
            }
        }
    } ## end foreach my $feature (@{$ra_features...

    log_message("Feature Usage:\n");

    # Label is unusual and probably reflects misplaced information, report in ascending order of frequency
    foreach my $featureKey (sort { $featuresSeen{$a} <=> $featuresSeen{$b} } (keys %featuresSeen)) {
        log_message(sprintf "%d x FEATURE %s\n", $featuresSeen{$featureKey}, $featureKey);
    }

    log_message("\nQualifier Usage:\n");

    # Label is unusual and probably reflects misplaced information, report in ascending order of frequency
    foreach my $qualifierKey (sort { $qualifiersSeen{$a} <=> $qualifiersSeen{$b} } (keys %qualifiersSeen)) {
	log_message(sprintf "%d x  /%s\n", $qualifiersSeen{$qualifierKey}, $qualifierKey);
    }

    log_message("\n");
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub fkeyQualStats(\@)

sub minMaxFromLocation($) {
    my $locationString = shift;
    my ($min, $max);

    # destroy foreign locations - should really become 0 or SEQLEN + 1
    $locationString =~ s/[A-Z]{1,4}\d{5,9}\.\d+:[\d\.\^]+//g;
    $locationString =~ s/(^\D+)|(\D$)//g;
    my @baseLocations = split /\D+/, $locationString;
    foreach (@baseLocations) {
        $min = $_ if (!(defined($min)) || ($_ < $min));
        $max = $_ if (!(defined($max)) || ($_ > $max));
    }
    return ($min, $max);
} ## end sub minMaxFromLocation($)

sub lenFromLocation($) {
    my $locationString = shift;
    my $len            = 0;

    $locationString =~ s/[A-Z]{1,4}\d{5,9}\.\d+://g;    # foreign locations lose their foreign AC

    $locationString =~ s/(^\D+)|(\D$)//g;               # trim non-numbers from end
    $locationString =~ s/[<>]+//g;                      # remove partiality info
    $locationString =~ s/[^\d\^\.]+/,/g;                # remove all but , and .. and .
    my @segmentList = split /,/, $locationString;
    foreach my $span (@segmentList) {
        if ($span =~ /^(\d+)$/) {                       # eg 57
            $len += $1;
        } elsif ($span =~ /^(\d+)\^(\d+)$/) {           # eg 57^58
            $len += 0;
        } elsif ($span =~ /^(\d+)\.\.(\d+)$/) {         # eg 57..59
            $len += ($2 - ($1 - 1));
        } elsif ($span =~ /^(\d+)\.(\d+)\.\.(\d+)$/) {    # eg 56.57..59 then take max len
            $len += ($3 - ($1 - 1));
        } elsif ($span =~ /^(\d+)\.\.(\d+)\.(\d+)$/) {    # eg 56..59.60 then take max len
            $len += ($3 - ($1 - 1));
        } elsif ($span =~ /^(\d+)\.(\d+)\.\.(\d+)\.(\d+)$/) {    # eg 56.57..59.60 then take max len
            $len += ($4 - ($1 - 1));
        } else {
            log_message(sprintf "Don't understand location string element %s within \n  %s\n", $span, $locationString);
        }
    } ## end foreach my $span (@segmentList)
    return ($len);
} ## end sub lenFromLocation($)

sub hasGeneFeatures(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub hasGeneFeatures\n");
    foreach my $feature (@{$ra_features}) {
        if ($feature->{'KEY'} eq "gene") {
            $verbose
              and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
            return 1;
        }
    }
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return 0;
} ## end sub hasGeneFeatures(\@)

sub geneStrip(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub geneStrip\n");
    my %importandFeatureMinMax;
    my $geneStripCount = 0;
    my $geneStoreCount = 0;
    foreach my $feature (@{$ra_features}) {

        if (   ($feature->{'KEY'} eq "CDS")
            || ($feature->{'KEY'} eq "rRNA")
            || ($feature->{'KEY'} eq "tRNA")) {
            $importandFeatureMinMax{ $feature->{'MINB'} . ".." . $feature->{'MAXB'} } = 1;
        }
    } ## end foreach my $feature (@{$ra_features...
    my @cleanedList = ();
    foreach my $feature (@{$ra_features}) {
        if ($feature->{'KEY'} eq "gene") {
            if (defined($importandFeatureMinMax{ $feature->{'MINB'} . ".." . $feature->{'MAXB'} })) {
                $geneStripCount++;
                next;
            } else {
                $geneStoreCount++;
            }
        } ## end if ($feature->{'KEY'} ...
        push(@cleanedList, $feature);
    } ## end foreach my $feature (@{$ra_features...
    if ($geneStripCount > 0) {
        log_message(sprintf "%d gene features stripped\n", $geneStripCount);
    }
    if ($geneStoreCount > 0) {
        log_message(sprintf "%d gene features kept\n", $geneStoreCount);
    }
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return @cleanedList;
} ## end sub geneStrip(\@)

sub hasGeneSymbol(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub hasGeneSymbol\n");
    foreach my $feature (@{$ra_features}) {
        if (   ($feature->{'KEY'} eq 'CDS')
            && ($feature->{'GENE'} ne "")) {
            $verbose
              and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
            return 1;
        }
    } ## end foreach my $feature (@{$ra_features...
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return 0;
} ## end sub hasGeneSymbol(\@)

sub noteTagCloud(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub noteTagCloud\n");
    open(TAGS, ">>$noteWordFile") || (die "Couldn't open $noteWordFile\n");
    $quiet || log_message("Writing notewords to $noteWordFile for tagcloud\n");
    foreach my $feature (@{$ra_features}) {
        foreach my $qual (@{ $feature->{'QUALS'} }) {
            if ($qual->{'QUAL'} eq "note") {
                my $note = $qual->{'VAL'};
                $note =~ s/(^")|("$)//g;
                my @words = split(/[\s,]+/, $note);
                print TAGS join("\n", @words) . "\n";
            }
        } ## end foreach my $qual (@{ $feature...
    } ## end foreach my $feature (@{$ra_features...
    close(TAGS);
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return 0;
} ## end sub noteTagCloud(\@)

sub checkLocusTagPrefix(\%$$\@\@) {
    my $valid_locus_tag_prefixes = shift;
    my $entry_pdid = shift; # project id of the entry
    my $current_locus_tag = shift;
    my $lt_bad_prefix = shift;
    my $lt_no_underscore = shift;

    if ($current_locus_tag =~ /^\"?([^_]+)_/) {
	if ($1 ne $$valid_locus_tag_prefixes{$entry_pdid}) {
	    push(@$lt_bad_prefix, $current_locus_tag);
	}
    }

    if ($current_locus_tag !~ /_/) {
	push(@$lt_no_underscore, $current_locus_tag);
    }

    return 1;
}

sub hasLocusTag(\@\%$) {
    my $ra_features = shift;
    my $valid_locus_tag_prefixes = shift;
    my $entry_pdid = shift; # project id of the entry

    #print STDERR "In hasLocusTag\n";

    my (@lt_bad_prefix, @lt_no_underscore);
    my $found_locus_tag = 0;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub hasLocusTag\n");
    foreach my $feature (@{$ra_features}) {
        if (   ($feature->{'KEY'} eq 'CDS')
            && ($feature->{'LOCUS'} ne "")) {

	    if ($entry_pdid) {
		checkLocusTagPrefix(%$valid_locus_tag_prefixes, $entry_pdid, $feature->{'LOCUS'}, @lt_bad_prefix, @lt_no_underscore);
	    }

            $found_locus_tag = 1;
        }
    } ## end foreach my $feature (@{$ra_features...
    
    if ($entry_pdid) {
	# i.e. don't bother checking locus tags if current project id for the entry is not defined

	if (@lt_bad_prefix) {
	    $quiet || log_message("ERROR: locus_tag qualifiers found with an invalid prefix: \"$$valid_locus_tag_prefixes{$entry_pdid}\": ".join(", ", @lt_bad_prefix)."\n");
	}

	if (@lt_no_underscore) {
	    $quiet || log_message("WARNING: locus_tag qualifiers found without underscore after prefix: ".join(", ", @lt_no_underscore)."\n");
	}
    }
    
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);

    if ($found_locus_tag) {
	return 1;
    }

    return 0;
} ## end sub hasLocusTag(\@)

sub checkPeptideLengths(\@) {    # not full peptide check because of complex locations
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub checkPeptideLengths\n");
    foreach my $feature (@{$ra_features}) {
        if (($feature->{'KEY'} =~ /_peptide/) &&    # is it a peptide
            (($feature->{'LENGTH'} % 3) != 0) &&    # is it a multiple of 3
            ($feature->{'LOCN'} !~ /[<>]/) &&       # is it a multiple of 3
            ($feature->{'PSEUDO'} == 0)
          ) {                                       # is it non-pseudo
            log_message(sprintf "!! %s not a multiple of 3 at \"%s\"\n", $feature->{'KEY'}, $feature->{'LOCN'});
        }
    } ## end foreach my $feature (@{$ra_features...
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub checkPeptideLengths(\@)

sub hasNoGeneSymbolOnAllPeptides(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub hasNoGeneSymbolOnAllPeptides\n");
    foreach my $feature (@{$ra_features}) {
        if (   ($feature->{'KEY'} =~ /_peptide/)
            && ($feature->{'GENE'} eq "")) {
            $verbose
              and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
            return 1;
        }
    } ## end foreach my $feature (@{$ra_features...
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return 0;
} ## end sub hasNoGeneSymbolOnAllPeptides(\@)

sub hasNoLocusTagOnAllPeptides(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub hasNoLocusTagOnAllPeptides\n");
    foreach my $feature (@{$ra_features}) {
        if (   ($feature->{'KEY'} =~ /_peptide/)
            && ($feature->{'LOCUS'} eq "")) {
            $verbose
              and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
            return 1;
        }
    } ## end foreach my $feature (@{$ra_features...
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return 0;
} ## end sub hasNoLocusTagOnAllPeptides(\@)

sub geneCdsLocusTagMerge(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub geneCdsLocusTagMerge\n");

    my $locusTagAdditions = 0;

    foreach my $feature (@{$ra_features}) {
        if ($feature->{'KEY'} eq "CDS") {
            if ($feature->{'SPANS_O'}) {
                log_message("Feature $feature->{'KEY'} at $feature->{'LOCN'} spans origin - cds-gene skipping locus_tag merging\n");
                next;
            }
            foreach my $feature2 (@{$ra_features}) {
                if (   ($feature2->{'KEY'} eq 'gene')
                    && ($feature2->{'STRAND'} eq $feature->{'STRAND'})
                    && ($feature2->{'MINB'} <= $feature->{'MINB'})
                    && ($feature2->{'MAXB'} >= $feature->{'MAXB'})
                    && (!($feature2->{'SPANS_O'}))) {

                    # if CDS has no locus_tag try to get it from gene
                    if ($feature->{'LOCUS'} ne "") {
                        if ($feature2->{'LOCUS'} eq "") {

                            $feature2->{'LOCUS'} = $feature->{'LOCUS'};
                            pushNewFeatureQualifier(@{ $feature2->{'QUALS'} }, { 'QUAL' => "locus_tag", 'VAL' => $feature2->{'LOCUS'} });
                            $verbose
                              && log_message("$feature2->{'KEY'} at $feature2->{'LOCN'} gets $feature->{'LOCUS'} from $feature->{'KEY'} at $feature->{'LOCN'}\n");
                            $locusTagAdditions++;
                        }

                        # if gene has no locus_tag try to get it from CDS
                    } elsif ($feature2->{'LOCUS'} ne "") {
                        $feature->{'LOCUS'} = $feature2->{'LOCUS'};
                        pushNewFeatureQualifier(@{ $feature->{'QUALS'} }, { 'QUAL' => "locus_tag", 'VAL' => $feature->{'LOCUS'} });
                        $verbose && log_message("$feature->{'KEY'} at $feature->{'LOCN'} gets $feature2->{'LOCUS'} from $feature2->{'KEY'} at $feature2->{'LOCN'}\n");
                        $locusTagAdditions++;
                    }
                    last;
                } ## end if (($feature2->{'KEY'...
            } ## end foreach my $feature2 (@{$ra_features...
        } ## end if ($feature->{'KEY'} ...
    } ## end foreach my $feature (@{$ra_features...
    if ($locusTagAdditions > 0) {
        log_message(sprintf "%d successful added locus_tags after comparing gene and CDS features\n", $locusTagAdditions);
    }
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub geneCdsLocusTagMerge(\@)

sub addLocusTagToPeptides(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub addLocusTagToPeptides\n");

    my $locusTagAdditions = 0;
    my $locusTagOmissions = 0;

    foreach my $feature (@{$ra_features}) {
        if (   ($feature->{'KEY'} =~ /_peptide/)
            && ($feature->{'LOCUS'} eq "")) {
            $locusTagOmissions++;
            if ($feature->{'SPANS_O'}) {
                log_message("Feature $feature->{'KEY'} at $feature->{'LOCN'} spans origin - cds-gene skipping locus_tag adding\n");
                next;
            }
            foreach my $feature2 (@{$ra_features}) {
                if (   ($feature2->{'KEY'} eq 'CDS')
                    && ($feature2->{'LOCUS'} ne "")
                    && ($feature2->{'STRAND'} eq $feature->{'STRAND'})
                    && ($feature2->{'MINB'} <= $feature->{'MINB'})
                    && ($feature2->{'MAXB'} >= $feature->{'MAXB'})) {
                    $feature->{'LOCUS'} = $feature2->{'LOCUS'};

                    # this will get overridden by later CDS in order to avoid problems with a CDS that spans origin IF CDSs have a good set of locus_tags
                } ## end if (($feature2->{'KEY'...
            } ## end foreach my $feature2 (@{$ra_features...
            if ($feature->{'LOCUS'} ne "") {
                $locusTagAdditions++;
                pushNewFeatureQualifier(@{ $feature->{'QUALS'} }, { 'QUAL' => "locus_tag", 'VAL' => $feature->{'LOCUS'} });
            } elsif ($verbose) {

                #		log_message(sprintf " no /locus_tag for %s at %s\n", $feature->{'KEY'}, $feature->{'LOCN'});
            }
        } ## end if (($feature->{'KEY'}...
    } ## end foreach my $feature (@{$ra_features...
    if ($locusTagOmissions > 0) {
        log_message(sprintf "%d out of %d peptides had /locus_tags added\n", $locusTagAdditions, $locusTagOmissions);
    }
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub addLocusTagToPeptides(\@)

sub addGeneSymbolToPeptides(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub addGeneSymbolToPeptides\n");
    my $geneSymbolAdditions = 0;
    my $geneSymbolOmissions = 0;

    foreach my $feature (@{$ra_features}) {
        if (   ($feature->{'KEY'} =~ /_peptide/)
            && ($feature->{'GENE'} eq "")) {
            $geneSymbolOmissions++;
            if ($feature->{'SPANS_O'}) {
                log_message("Feature $feature->{'KEY'} at $feature->{'LOCN'} spans origin - cds-gene skipping locus_tag adding\n");
                next;
            }
            foreach my $feature2 (@{$ra_features}) {
                if (   ($feature2->{'KEY'} eq 'CDS')
                    && ($feature2->{'GENE'} ne "")
                    && ($feature2->{'STRAND'} eq $feature->{'STRAND'})
                    && ($feature2->{'MINB'} <= $feature->{'MINB'})
                    && ($feature2->{'MAXB'} >= $feature->{'MAXB'})) {

#		    log_message(sprintf "gene symbol:%s found in %s at %s\n%s", $feature2->{'GENE'}, $feature2->{'KEY'}, $feature2->{'LOCN'}, join(",",@{$feature2->{'QUALS'}}));
                    $feature->{'GENE'} = $feature2->{'GENE'};

                    # this will get overridden by later CDS in order to avoid problems with a CDS that spans origin
                } ## end if (($feature2->{'KEY'...
            } ## end foreach my $feature2 (@{$ra_features...
            if ($feature->{'GENE'} ne "") {
                $geneSymbolAdditions++;
                pushNewFeatureQualifier(@{ $feature->{'QUALS'} }, { 'QUAL' => "gene", 'VAL' => $feature->{'GENE'} });
            } elsif ($verbose) {

                #		log_message(sprintf " no /gene for %s at %s\n", $feature->{'KEY'}, $feature->{'LOCN'});
            }
        } ## end if (($feature->{'KEY'}...
    } ## end foreach my $feature (@{$ra_features...
    if ($geneSymbolOmissions > 0) {
        log_message(sprintf "%d out of %d peptides had /gene added\n", $geneSymbolAdditions, $geneSymbolOmissions);
    }
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub addGeneSymbolToPeptides(\@)

sub fixObsoleteFeatures(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub fixObsoleteFeatures\n");

    my @key2ncRNA_class = ("scRNA", "snRNA", "snoRNA");

    foreach my $feature (@{$ra_features}) {
        foreach my $deprecatedkey (@key2ncRNA_class) {
            if ($feature->{'KEY'} eq $deprecatedkey) {
                log_message("! $feature->{'KEY'} at $feature->{'LOCN'} converted to ncRNA feature\n");
                pushNewFeatureQualifier(@{ $feature->{'QUALS'} }, { 'QUAL' => "ncRNA_class", 'VAL' => '"' . $feature->{'KEY'} . '"' });
                $feature->{'KEY'} = "ncRNA";
                last;
            }
        } ## end foreach my $deprecatedkey (...
        if ($feature->{'KEY'} eq "repeat_unit") {
            log_message("! $feature->{'KEY'} at $feature->{'LOCN'} converted to repeat_region feature\n");
            $feature->{'KEY'} = "repeat_region";
        }
	foreach my $qual (@{ $feature->{'QUALS'} }) {
	    if ($qual->{'QUAL'} eq "specific_host") {
		$qual->{'QUAL'} = "host";
	    }
	}
    } ## end foreach my $feature (@{$ra_features...
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub fixObsoleteFeatures(\@)

sub sortFeatures(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub sortFeatures\n");

    @{$ra_features} =
      sort {

        # in general - first to appear is first on sequence
        if ($a->{'MINB'} != $b->{'MINB'}) {
            return $a->{'MINB'} <=> $b->{'MINB'};    # ie -1 if a < b
        }

        # for features starting at the same base
        # source starting at 1 takes priority
        if (($a->{'KEY'} eq "source") &&             # if a is a source starting at 1
            ($a->{'MINB'} == 1)
          ) {
            if (($b->{'KEY'} eq "source") &&         # if b is a source starting at 1
                ($b->{'MINB'} == 1)
              ) {
                return $b->{'MAXB'} <=> $a->{'MAXB'};    # then use the max location (reverse order when comparing max)
            } else {
                return -1;                               # source beginning at 1 goes first
            }
        } elsif (
            ($b->{'KEY'} eq "source") &&                 # if b is a source starting at 1 (but a wasn't)
            ($b->{'MINB'} == 1)
          ) {
            return 1;
        }

        # primer_bind starting at 1 comes next
        elsif (
            ($a->{'KEY'} eq "primer_bind") &&            # if a is a primer_bind starting at 1
            ($a->{'MINB'} == 1)
          ) {
            if (($b->{'KEY'} eq "primer_bind") &&        # if b is a primer_bind starting at 1
                ($b->{'MINB'} == 1)
              ) {
                return $b->{'MAXB'} <=> $a->{'MAXB'};    # then use the max location (reverse order when comparing max)
            } else {
                return -1;                               # primer_bind beginning at 1 goes first
            }
        } elsif (
            ($b->{'KEY'} eq "primer_bind") &&            # if b is a primer_bind starting at 1 (but a wasn't)
            ($b->{'MINB'} == 1)
          ) {
            return 1;
        }

        # exons with same start - shortest goes first
        elsif (   ($a->{'KEY'} eq "exon")
               && ($b->{'KEY'} eq "exon")) {
            return $a->{'MAXB'} <=> $b->{'MAXB'};        # shortest first
        }

        # introns with same start - shortest goes first
        elsif (   ($a->{'KEY'} eq "intron")
               && ($b->{'KEY'} eq "intron")) {
            return $a->{'MAXB'} <=> $b->{'MAXB'};        # shortest first
        }

        # longest goes first
        if ($b->{'MAXB'} != $a->{'MAXB'}) {
            return $b->{'MAXB'} <=> $a->{'MAXB'};        # then use the max location (reverse order when comparing max)
        }

        # a last-ditch attempt to choose between two locations (could use partial)
        elsif ($a->{'KEY'} eq "source") {
            return -1;                                   # all things being equal, source goes first
        } elsif ($b->{'KEY'} eq "source") {
            return 1;                                    # all things being equal, source goes first
        }

        # give up caring - eg a misc_feature and a repeat region at the same location
        return 0;
      } @{$ra_features};
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub sortFeatures(\@)

sub pushRawFeatureLine (\@$) {
    my $ra_featureLines = shift;
    my $lineRead        = shift;
    $lineRead =~ s/\s+^//;       # remove trailing spaces on line
    $lineRead =~ s/\s+"/"/;      # remove trailing spaces in qualifier value
    $lineRead =~ s/="\s+/="/;    # remove leading spaces in qualifier value
    if ($lineRead =~ /=""/) {    # empty qualifier
        return;
    }
    if (($doStrip == 0)
        || (   ($lineRead !~ m|^FT                   /protein_id=|)
            && ($lineRead !~ m|^FT                   /codon_start=1|)
            && ($lineRead !~ m|^FT                   /transl_table=|)
            && ($lineRead !~ m|^FT                   /db_xref=|))
      ) {
        $lineRead =~ s/ \{[^}]+\}"$/"/;    # remove _GR evidence
        push(@$ra_featureLines, $lineRead . "\n");
    } ## end if (($doStrip == 0) ||...
} ## end sub pushRawFeatureLine (\@$)

sub hasException(\@) {
    my $ra_featureLines = shift;
    foreach my $line (@{$ra_featureLines}) {
        if ($line =~ /^.. {19}\/exception=/) {
            return 1;
        }
    }
    return 0;
} ## end sub hasException(\@)


sub check_and_change_EC_numbers(\%\%$) {
    my $ra_qualifier_typos = shift;
    my $ra_valid_ec_nums   = shift;
    my $newQual           = shift;

    my $qualifier_value_match = 0;
    my $check_ec_num_is_valid = 0;

    $newQual->{'VAL'} =~ s/\"//g;

    # remove trailing dot from EC number, if it exists
    $newQual->{'VAL'} =~ s/\.$//;

    # 1.2.3.4
    $_ = $newQual->{'VAL'};
    my $num_dots = tr/\.//;

    while ($num_dots < 3) {
	$newQual->{'VAL'} .= '.-';

	$_ = $newQual->{'VAL'};
	$num_dots = tr/\.//;
    }
    
    foreach my $regex (keys %{ $$ra_qualifier_typos{'EC_number'} }) {
	
	if ($newQual->{'VAL'} =~ /^$regex$/i) {
	    
	    if ($$ra_qualifier_typos{'EC_number'}{$regex} =~ /DELETED/i) {
		log_message('WARNING: EC_number '.$newQual->{'VAL'}.' is labelled as DELETED so has been changed to /note="EC_number '.$newQual->{'VAL'}.", DELETED\"\n");
		$newQual->{'QUAL'} = "note";
		$newQual->{'VAL'}  = 'EC_number '.$newQual->{'VAL'}.', DELETED';
	    }
	    elsif ($$ra_qualifier_typos{'EC_number'}{$regex} =~ /\-\.\-\.\-\.\-/) {
		log_message('WARNING: EC_number '.$newQual->{'VAL'}.' is now -.-.-.-    EC_number has been changed to a /note: /note="EC_number '.$newQual->{'VAL'}.", REMAPPED ambiguously\"\n");
		$newQual->{'QUAL'} = "note";
		$newQual->{'VAL'}  = 'EC_number '.$newQual->{'VAL'}.', REMAPPED ambiguously';
	    }
	    else {
		# straight substitution
		log_message('WARNING: EC_number has been changed from '.$newQual->{'VAL'}.' to '.$$ra_qualifier_typos{ $newQual->{'QUAL'} }{$regex}."\n");
		$newQual->{'VAL'} = $$ra_qualifier_typos{ $newQual->{'QUAL'} }{$regex};
		$check_ec_num_is_valid = 1;
	    }
	    
	    $qualifier_value_match = 1;
	    last;  # match made so exit foreach of regexes
	}	
    }
    
    if ((!$qualifier_value_match) || $check_ec_num_is_valid) {
	# check ec num is valid against list of valid ec nums
	my $is_valid = 0;
	foreach my $valid_ec_num (keys %$ra_valid_ec_nums) {
	    if ($valid_ec_num eq $newQual->{'VAL'}) {
		$is_valid = 1;
		last;
				}
	}
	if (! $is_valid) {
	    log_message("WARNING: EC_number ".$newQual->{'VAL'}." invalid.  Changed to /note=\"EC_number ".$newQual->{'VAL'}.", UNKNOWN\"\n");
	    $newQual->{'QUAL'} = "note";
	    $newQual->{'VAL'} = 'EC_number '.$newQual->{'VAL'}.', UNKNOWN';
	}
    }
    # re-add double quotes to $newQual->{'VAL'} variable
    $newQual->{'VAL'} = '"'.$newQual->{'VAL'}.'"';

} # end of check_and_change_EC_numbers subroutine

# storeFeature cleans a list of feature lines and adds the feature object to a list
sub storeFeature(\@\@\%\%) {
    my $ra_features     = shift;
    my $ra_featureLines = shift;
    my $ra_qualifier_typos = shift;
    my $ra_valid_ec_nums = shift;

    # remove identical lines
    my @qualifiers = ();
    my $fMinBase;
    my $fMaxBase;
    my $fLength;
    my $locus_tag   = "";
    my $orientation = "+";    # NB this always flips if ANY part is complement
    my $firstGene   = "";
    my $fKey;
    my $locString    = "";
    my $pseudo       = 0;
    my $spansOrigin  = 0;
    my $hasException = hasException(@{$ra_featureLines});
    my $valid_ec_nums; # hash reference

    foreach my $line (@{$ra_featureLines}) {

        # Take feature key and location
        if ($line =~ /^FT   (\S+) +(.+)$/) {
            $fKey      = $1;
            $locString = $2;
            if ($doComplement_loc_fix) {
                $locString = fix_complement_location($locString);
            }

            ($fMinBase, $fMaxBase) = minMaxFromLocation($locString);
            $fLength = lenFromLocation($locString);
            if ($line =~ /complement/) {
                $orientation = '-';
            }
            if (   ($locString =~ /,1\.\./)
                || ($locString =~ /join\(complement\(1\.\./)) {
                $spansOrigin = 1;
                $verbose && log_message("Feature at $locString spans origin\n");
            }
        } ## end if ($line =~ /^FT   (\S+) +(.+)$/)

        # Take qualifier
        else {
            my $newQual;

            if ($line =~ /^.. {19}\/([^\s=]+)=(.+)$/) {
		my $qual = $1;
		my $val = $2;
		$newQual = { 'QUAL' => $qual, 'VAL' => $val };

#               There seems little point in storing 'QUOTED' Y or N because EC_number always uses quotes and 
#       	other qualifiers have substitutions done within the double-quotes (if any present).
#		if ($newQual->{'VAL'} =~ /^\"/) {
#		    $newQual = {'QUOTED' => 'Y'};
#		}
#		else {
#		    $newQual = {'QUOTED' => 'N'};
#		}

                if ($doComplement_loc_fix) {
                    if (   ($newQual->{'QUAL'} eq "anticodon")
                        || ($newQual->{'QUAL'} eq "codon")
                        || ($newQual->{'QUAL'} eq "rpt_unit")
                        || ($newQual->{'QUAL'} eq "rpt_unit_range")
                        || ($newQual->{'QUAL'} eq "transl_except")
                        || ($newQual->{'QUAL'} eq "tag_peptide")) {
                        $newQual->{'VAL'} = fix_complement_location($newQual->{'VAL'});
                    } ## end if (($newQual->{'QUAL'...
                } ## end if ($doComplement_loc_fix)

		# fix qualifier typos
		if ($doQualFix) {
		    
		    if ($newQual->{'QUAL'} eq "EC_number") {
			# NB EC_numbers are a special case - all transferred and deleted EC nums
			# exist in the cv_fqual_value_fix table (held in %$ra_qualifier_typos)
			# and all valid EC nums are held in %$ra_valid_ec_nums

			check_and_change_EC_numbers(%$ra_qualifier_typos, %$ra_valid_ec_nums, $newQual);
		    }
		    # for qualifier substitutions other than EC_number, so substitutes if regex is found.
		    else {
			foreach my $regex (keys %{ $$ra_qualifier_typos{ $newQual->{'QUAL'} } }) {
			    
			    if ($newQual->{'VAL'} =~ /\b$regex\b/i) {
				log_message('WARNING: '.$newQual->{'QUAL'}."=".$newQual->{'VAL'}." is being replaced by \"".$$ra_qualifier_typos{ $newQual->{'QUAL'} }{$regex}."\"\n");
				$newQual->{'VAL'} =~ s/\b$regex\b/$$ra_qualifier_typos{ $newQual->{'QUAL'} }{$regex}/i;
			    }
			}
		    }
		}
            } 
	    # value-free qualifier
	    elsif ($line =~ /^.. {19}\/([^\s=]+)$/) {
                $newQual = { 'QUAL' => $1 };
            } 

            # take important feature-attributes from qualifiers
            if (($newQual->{'QUAL'} eq "pseudo") || ($newQual->{'QUAL'} eq "non-functional")) {
                $pseudo = 1;
            }

            # need to harvest extra genes or synonyms
            if ($newQual->{'QUAL'} eq "gene") {
                if ($firstGene eq "") {
                    $firstGene = $newQual->{'VAL'};
                } 
		else {
                    $newQual->{'QUAL'} = "gene_synonym";
                }
            } 
	    elsif ($newQual->{'QUAL'} eq "locus_tag") {
                if ($locus_tag eq "") {    # not a second locus_tag
                    $locus_tag = $newQual->{'VAL'};
                } 
		elsif ($locus_tag ne $newQual->{'VAL'}) {    # ie second locus_tag is not a simple duplicate
                    log_message(sprintf "!! second locus_tag %s moved to a note in %s at \"%s\" (locus_tag %s)\n", $newQual->{'VAL'}, $fKey, $locString, $locus_tag);
                    $newQual->{'QUAL'} = "note";
                    $newQual->{'VAL'} =~ s/^\"/\"additional locus_tag=/;
                }
            } 
	    elsif (($newQual->{'QUAL'} eq "pseudo") || ($newQual->{'QUAL'} eq "non-functional")) {
                $pseudo = 1;
            }

            # store qual
	    if (($newQual->{'QUAL'} ne "translation") ||  !($doTranslationStrip) || ($hasException)) {
                pushNewFeatureQualifier(@qualifiers, $newQual);    # inefficient compared with adding it directly but may not be a significant cost
            }
        } ## end else [ if ($line =~ /^FT   (\S+) +(.+)$/)
    } ## end foreach my $line (@{$ra_featureLines...
    undef(@{$ra_featureLines});
    $locString =~ s/ //g;

    # qualifier sorting still desirable for diffing but curator alias 'ftfix' doesn't use the flag
    if ($doSort) {
        @qualifiers = sort { return $a->{'QUAL'} cmp $b->{'QUAL'}; } @qualifiers;
    }

    if ($hasException) {
        log_message(sprintf "!! exception found in %s at \"%s\"\n", $fKey, $locString);
    }

    push(@{$ra_features},
         {  'KEY'     => $fKey,
            'LOCN'    => $locString,
            'MINB'    => $fMinBase,
            'MAXB'    => $fMaxBase,
            'LENGTH'  => $fLength,
            'LOCUS'   => $locus_tag,
            'GENE'    => $firstGene,
            'PSEUDO'  => $pseudo,
            'STRAND'  => $orientation,
            'SPANS_O' => $spansOrigin,
            'QUALS'   => \@qualifiers
         });
} ## end sub storeFeature(\@\@)

sub locus_tag_fix(\@) {
    my $ra_features = shift;

    my $time1 = (times)[0];
    $verbose && log_message("Doing sub locus_tag_fix\n");
    my %lt_g_pairs;     # locus_tag key -> first gene name found of 1st CDS with that locus_tag
    my %lt_gs_pairs;    # locus_tag key -> string of gene and gene_synonym (for quick comparisons) from 1st CDS with that locus_tag
    my %g_lt_pairs;     # locus_tag key -> first locus_tag name found of 1st CDS with that locus_tag (value is wiped if ambiguous)
    my %unreliable_lt2g;
    my %unreliable_lt2gs;
    my %errors;         # store error in hash key for simple uniquification

    # 1st pass: harvest pairs from CDS, ignoring blanks
    $verbose && log_message(" locus_tag_fix First Pass - recruit info from CDS\n");
    foreach my $feature (@{$ra_features}) {

        # is there a pair? # NB LOCUS and GENE are blank if undefined
        if (   ($feature->{'KEY'} ne "CDS")
            || ($feature->{'LOCUS'} eq "")
            || ($feature->{'GENE'}  eq "")) {
            next;
        }
        my @gene_and_synonyms = list_gene_and_synonym_of_feature($feature);

        # LOCUS_TAG as a key - a gene of a locus_tag must be stable
        # store unless we already have seen this locus tag with a gene symbol
        if (!(exists($lt_g_pairs{ $feature->{'LOCUS'} }))) {
            $lt_g_pairs{ $feature->{'LOCUS'} } = $feature->{'GENE'};
        }

        # is there a disagreement? - NB we could look into multiple gene qualifiers for a fix
        elsif ($lt_g_pairs{ $feature->{'LOCUS'} } ne $feature->{'GENE'}) {
            my $error = sprintf "!! locus tag %s has changed from the first gene name = %s to %s", $feature->{'LOCUS'}, $lt_g_pairs{ $feature->{'LOCUS'} },
              $feature->{'GENE'};
            $errors{$error} = 1;             # number is meaningless, just need hash key initialised
            $unreliable_lt2g{'LOCUS'} = 1;
        }

        # LOCUS_TAG as a key - a gene and gene_symbol of a locus_tag must be stable
        # store unless we already have seen this locus tag with these symbols
        if (!(exists($lt_gs_pairs{ $feature->{'LOCUS'} }))) {
            $lt_gs_pairs{ $feature->{'LOCUS'} } = join(',', @gene_and_synonyms);
        }

        # is there a disagreement?
        elsif ($lt_gs_pairs{ $feature->{'LOCUS'} } ne join(',', @gene_and_synonyms)) {
            my $error = sprintf "!! locus tag %s has changed from the gene list name = %s to %s", $feature->{'LOCUS'}, $lt_gs_pairs{ $feature->{'LOCUS'} },
              @gene_and_synonyms;
            $errors{$error} = 1;              # number is meaningless, just need hash key initialised
            $unreliable_lt2gs{'LOCUS'} = 1;
        }

        # GENE as a key - a gene can have multiple /locus_tags (eg multiple gene copies) BUT it creates an ambiguity
        if (!(exists($g_lt_pairs{ $feature->{'GENE'} }))) {
            $g_lt_pairs{ $feature->{'GENE'} } = $feature->{'LOCUS'};
        }

        # is there ambiguity (eg 2 copies of a gene)
        elsif ($g_lt_pairs{ $feature->{'GENE'} } ne $feature->{'LOCUS'}) {
            $g_lt_pairs{ $feature->{'GENE'} } = "";
        }
    } ## end foreach my $feature (@{$ra_features...

    # 2nd pass: harvest pairs from non-CDS
    $verbose && log_message(" locus_tag_fix Second Pass - recruit info from non-CDS\n");
    foreach my $feature (@{$ra_features}) {
        if (   ($feature->{'KEY'} eq "CDS")
            || ($feature->{'LOCUS'} eq "")
            || ($feature->{'GENE'}  eq "")) {
            next;
        }
        my @gene_and_synonyms = list_gene_and_synonym_of_feature($feature);

        # LOCUS_TAG as a key - a gene of a locus_tag must be stable
        # store unless we already have seen this locus tag with a gene symbol
        if (!(exists($lt_g_pairs{ $feature->{'LOCUS'} }))) {
            $lt_g_pairs{ $feature->{'LOCUS'} } = $feature->{'GENE'};
        }

        # is there a disagreement in LT -> gene
        elsif ($lt_g_pairs{ $feature->{'LOCUS'} } ne $feature->{'GENE'}) {
            my $error = sprintf "!! locus tag %s has changed from the first gene name = %s to %s", $feature->{'LOCUS'}, $lt_g_pairs{ $feature->{'LOCUS'} },
              $feature->{'GENE'};

            # if Gene+Synonyms is reliable, fix feature based on CDS
            if (!(exists($unreliable_lt2gs{'LOCUS'})) && ($lt_gs_pairs{ $feature->{'LOCUS'} } eq join(',', @gene_and_synonyms))) {
                $error .= "\n! $feature->{'KEY'} at $feature->{'LOCN'} with locus_tag \"$feature->{'LOCUS'}\" had gene<_>synonym swap fixed";
                repairGeneAndSynonymsInFeature($feature, $lt_g_pairs{ $feature->{'LOCUS'} }, @gene_and_synonyms);
            } else {

                # couldn't reconcile gene name conflict
                $unreliable_lt2g{'LOCUS'} = 1;
            }
            $errors{$error} = 1;    # number is meaningless, just need hash key initialised
        } ## end elsif ($lt_g_pairs{ $feature...

        # LOCUS_TAG as a key - a gene and gene_symbol of a locus_tag must be stable
        # store unless we already have seen this locus tag with these symbols
        if (!(exists($lt_gs_pairs{ $feature->{'LOCUS'} }))) {
            $lt_gs_pairs{ $feature->{'LOCUS'} } = join(',', @gene_and_synonyms);
        }

        # is there a disagreement in LT -> gene + synonyms
        elsif ($lt_gs_pairs{ $feature->{'LOCUS'} } ne join(',', @gene_and_synonyms)) {
            my $error = sprintf "!! locus tag %s has changed from the gene and gene_synonym list name = %s to %s", $feature->{'LOCUS'}, $lt_gs_pairs{ $feature->{'LOCUS'} },
              @gene_and_synonyms;

            # if Gene+Synonyms is reliable, fix feature based on CDS
            if (!(exists($unreliable_lt2gs{'LOCUS'}))
                && (length(join(',', @gene_and_synonyms)) < length($lt_gs_pairs{ $feature->{'LOCUS'} }))) {
                $error .=
                    "\n! $feature->{'KEY'} at $feature->{'LOCN'} with locus_tag \"$feature->{'LOCUS'}\" had synonym fix\n" . "  "
                  . join(',', @gene_and_synonyms)
                  . " -> \n" . "  "
                  . $lt_gs_pairs{ $feature->{'LOCUS'} } . " \n";
                repairGeneAndSynonymsInFeature($feature, $lt_g_pairs{ $feature->{'LOCUS'} }, split /,/, $lt_gs_pairs{ $feature->{'LOCUS'} });
            } else {

                # couldn't reconcile gene name conflict
                $unreliable_lt2gs{'LOCUS'} = 1;
            }
            $errors{$error} = 1;    # number is meaningless, just need hash key initialised
        } ## end elsif ($lt_gs_pairs{ $feature...

        # GENE as a key - a gene can have multiple /locus_tags (eg multiple gene copies) BUT it creates an ambiguity
        if (!(exists($g_lt_pairs{ $feature->{'GENE'} }))) {
            $g_lt_pairs{ $feature->{'GENE'} } = $feature->{'LOCUS'};
        }

        # is there ambiguity (eg 2 copies of a gene)
        elsif ($g_lt_pairs{ $feature->{'GENE'} } ne $feature->{'LOCUS'}) {
            $g_lt_pairs{ $feature->{'GENE'} } = "";
        }
    } ## end foreach my $feature (@{$ra_features...

    if (scalar(keys %lt_g_pairs) == 0) {
        $verbose
          and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
        return;
    }

    # 3rd pass: check locus_tags for omissions of gene name
    $verbose && log_message(" locus_tag_fix Third Pass - using the information\n");
    foreach my $feature (@{$ra_features}) {

        # is there a locus_tag?
        if ($feature->{'LOCUS'} ne "") {

            # is there a pair for this locus_tag
            if (defined($lt_g_pairs{ $feature->{'LOCUS'} })) {

                # does this feature have a gene symbol
                if ($feature->{'GENE'} eq "") {
                    $feature->{'GENE'} = $lt_g_pairs{ $feature->{'LOCUS'} };
                    pushNewFeatureQualifier(@{ $feature->{'QUALS'} }, { 'QUAL' => "gene", 'VAL' => $feature->{'GENE'} });
                    my $error = sprintf "! locus_tag %s needed gene %s - fixed", $feature->{'LOCUS'}, $feature->{'GENE'};
                    $errors{$error} = 1;    # number is meaningless, just need hash key initialised
                    if (!(exists($unreliable_lt2gs{'LOCUS'}))) {
                        repairGeneAndSynonymsInFeature($feature, $feature->{'GENE'}, split /,/, $lt_gs_pairs{ $feature->{'LOCUS'} });
                    }
                } ## end if ($feature->{'GENE'}...
            } ## end if (defined($lt_g_pairs...
        } ## end if ($feature->{'LOCUS'...

        # is there a gene name without a locus_tag?
        elsif ($feature->{'GENE'} ne "") {
            if (exists($g_lt_pairs{ $feature->{'GENE'} })) {
                if ($g_lt_pairs{ $feature->{'GENE'} } ne "") {
                    $feature->{'LOCUS'} = $g_lt_pairs{ $feature->{'GENE'} };
                    pushNewFeatureQualifier(@{ $feature->{'QUALS'} }, { 'QUAL' => "locus_tag", 'VAL' => $feature->{'LOCUS'} });
                    my $error = sprintf "! gene %s needed locus_tag %s - fixed", $feature->{'GENE'}, $feature->{'LOCUS'};
                    $errors{$error} = 1;    # number is meaningless, just need hash key initialised
                } else {
                    my $error = sprintf "!! locus tag missing from gene %s, but this gene name has multiple locus_tags", $feature->{'GENE'};
                    $errors{$error} = 1;    # number is meaningless, just need hash key initialised
                }
            } ## end if (exists($g_lt_pairs...
        } ## end elsif ($feature->{'GENE'}...
    } ## end foreach my $feature (@{$ra_features...

    # 4th pass: if locus_tag matches old_locus_tag (case_insensitive match), 
    # change old_locus_tag(s) to a note
    foreach my $feature (@{$ra_features}) {

	my (@old_locus_tags);
	my $locus_tag = "";
        # is there a locus_tag?
        if ($feature->{'LOCUS'} ne "") {

	    # foreach qualifier...
	    foreach my $qual (@{ $feature->{'QUALS'} }) {
		if ($qual->{QUAL} eq 'locus_tag') {
		    $locus_tag = $qual->{VAL};
		}
		elsif ($qual->{QUAL} eq 'old_locus_tag') {
		    if ($locus_tag =~ /^$qual->{VAL}$/i ) {
			$qual->{QUAL} = 'note';
			log_message("WARNING: Converting /$qual->{QUAL}=\"$qual->{VAL}\" to a /note because it's the same as /locus_tag\n");
		    }
		}
	    } ## end my $qual (@{ $feature->{'QUALS'} }) {
        } ## end if ($feature->{'LOCUS'...
    } ## end foreach my $feature (@{$ra_features...

    $quiet || log_message(join("\n", (keys %errors)) . "\n");
    $verbose
      and log_message(sprintf " took %.2f CPU seconds\n\n", (times)[0] - $time1);
    return;
} ## end sub locus_tag_fix(\@)

sub process_FT(\@\%$) {
    my $ra_features = shift;
    my $valid_locus_tag_prefixes = shift;
    my $entry_pdid = shift;  # project id of the entry

    my $time1 = (times)[0];
    if (   ($doGeneCdsLocusTagMerge)
        && (hasGeneFeatures(@{$ra_features}))) {    # maybe saves time to check first
        geneCdsLocusTagMerge(@{$ra_features});
    }
    if (   ($doGeneStrip)
        && (hasGeneFeatures(@{$ra_features}))) {    # maybe saves time to check first
        @{$ra_features} = geneStrip(@{$ra_features});
    }
    if ($doFts) {
        sortFeatures(@{$ra_features});
    }
    if ($doObsoleteFeatureFix) {
        fixObsoleteFeatures(@{$ra_features});
    }
    if ($doPeptideFix) {                            # relies on features being sorted so that a CDS spanning origin comes first
        if (   (hasGeneSymbol(@{$ra_features}))
            && (hasNoGeneSymbolOnAllPeptides(@{$ra_features}))) {
            addGeneSymbolToPeptides(@{$ra_features});
        }
        if (   (hasLocusTag(@{$ra_features}, %$valid_locus_tag_prefixes, $entry_pdid))
            && (hasNoLocusTagOnAllPeptides(@{$ra_features}))) {
            addLocusTagToPeptides(@{$ra_features});
        }
        checkPeptideLengths(@{$ra_features});
    } ## end if ($doPeptideFix)
    if ($doGeneLocusFix) {
        locus_tag_fix(@{$ra_features});
    }
    if ($doSpanCheck) {

        #	locus_tag_span_check($ra_features);
        # not coded properly yet
    }

    #    log_message("FT NOW = :\n" . Dumper($ra_features));
    if ($doTagCloud) {
        noteTagCloud(@{$ra_features});
    }
    showDuplicateFeatures(@{$ra_features});
    showDuplicateLabels(@{$ra_features});
    if ($doStats) {
        showDuplicateNotes(@{$ra_features});
        fkeyQualStats(@{$ra_features});
    }
    printFeatures(@{$ra_features});
    undef(@{$ra_features});
    return;
} ## end sub process_FT(\@)

sub connect_to_enapro() {

    my $dbh;
    eval {
	$dbh = DBI->connect('dbi:Oracle:ENAPRO', '/', '',  {
	    RaiseError => 1, 
	    PrintError => 0,
	    AutoCommit => 0
	    });
    };

    if ($@) {	
	my $msg = "WARNING: ENAPRO cannot be connected to so no qualifier fixes can be done at this time\n";
	log_message($msg);
	$doQualFix = 0;
	return(0);
    }
    else {
	return($dbh);
    }
}

sub create_qual_fix_hash($) {
    my $dbh = shift;

    my $sth = $dbh->prepare("select qual.fqual, fix.regex, fix.value from cv_fqual_value_fix fix, cv_fqual qual where fix.fqualid = qual.fqualid order by fix.fqualid");

    $sth->execute();

    my %qualifier_typo_hash;
    while (my ($qualifier, $regex, $value) = $sth->fetchrow_array) {
	
	$qualifier_typo_hash{$qualifier}{$regex} = $value;
    }
    
    return(\%qualifier_typo_hash);
}

sub create_valid_ec_num_hash($) {
    my $dbh = shift;
    
    my $sth = $dbh->prepare("select ec_number from cv_ec_numbers where valid = 'Y'");

    $sth->execute();

    my %ec_num_hash;
    while (my $ec_num = $sth->fetchrow_array) {
	
	$ec_num_hash{$ec_num} = 1;
    }
    
    return(\%ec_num_hash);
}

sub get_qualifier_substitution_hashes($) {

    my $dbh = shift;

    my $qualifier_typo_hash = create_qual_fix_hash($dbh);
    my $valid_ec_num_hash = create_valid_ec_num_hash($dbh);

    return(\%$qualifier_typo_hash, \%$valid_ec_num_hash);
}

sub open_new_output_file() {
 
    # we'll allow overwriting in the small chance someone runs this
    # script twice within the same minute, rather than incrementing the timestamp
    my $filename = "ftfix.".SeqDBUtils2::timeDayDate("yyyy-mm-dd-time").".log.del";

    open($log_fh, ">$filename") || die "Cannot open $filename in write mode\n";
    return($filename);
}

sub run_validator($$) {
    my $infile = shift;
    my $val_broken_email_sent = shift;

    my $validator_output_file = $infile.".validator_out.del";

    my $cmd = "/ebi/production/seqdb/embl/tools/ena_validator-PROD.sh $infile >& $validator_output_file";
    #log_message("Running the validator on $infile\n");

    my $exit_code = system($cmd);

    if ($exit_code) {
	# validator has failed
	log_message("The Validator has failed.  Notifying Gemma...\n");

	my $cwd = `pwd`;

	if (!$val_broken_email_sent) {

	    open(MAIL, "|/usr/sbin/sendmail -oi -t");
	    print MAIL 'To: gemmah@ebi.ac.uk, lbower@ebi.ac.uk'."\n";
	    print MAIL 'From: datalib@ebi.ac.uk'."\n"
		. "Subject: Validator failed in ftfix\n"
		. "The validator has failed in ftfix from this directory:\n".$cwd."\n\nFirst entry to fail: $infile\n";
	    close(MAIL);

	    $val_broken_email_sent = 1;

	    if ($cwd =~ /\/(\d+)$/) {
		my $ds = $1;

		my $new_ds_path = "$ENV{VALFIX}/$ds/";
		my $counter = 1;
		while (1) {
		    if (! -e $new_ds_path) {
			system("mkdir $new_ds_path");
			last;
		    }
		    else {
			$new_ds_path = $new_ds_path."_$counter";
			$counter++;
		    }
		}
	    }
	}

	if ($cwd =~ /\/(\d+)$/) {
	    my $ds = $1;
	    system("cp $infile $ENV{VALFIX}/$ds/");
	}
    }
    else {
	if (open(VAL_OUTPUT, "<$validator_output_file")) {
	    log_message("------Validator output for $infile:\n");
	    while (my $line = <VAL_OUTPUT>) {
		log_message($line);
	    }
	    close(VAL_OUTPUT);
	    log_message("------End of validator output for $infile\n\n");
	    unlink($validator_output_file);
	}
    }
}

sub save_ftsort_output_to_log() {

    if (-e $fts_output_log) {

	open(OUTPUTLOG, "<$fts_output_log");
	while (my $line = <OUTPUTLOG>) {
	    log_message($line);
	}
	close(OUTPUTLOG);
	unlink($fts_output_log);
    }
}

sub check_PR_line_and_get_locus_tag_prefix($$\%) {
    my ($dbh, $PR_line, $valid_locus_tag_prefixes) = @_;

    #print STDERR "In check_PR_line_and_get_locus_tag_prefix\n";

    my $PRid = "";
    my $new_PR_line = "";
    my $entry_pdid = 0;  # project id of the entry

    #print STDERR "PR line = $PR_line\n";

    if ($PR_line =~ /^PR\s+Project:([^;]+)/) {
	$PRid = $1;
	$PRid =~ s/\://g;
	$PRid =~ s/\s+//g;
	
	# if there is a project id entered in the command line options...
	if ($pdid) {
	    if ($PRid ne $pdid) {
		log_message("WARNING: Project id in -pdid argument does not match that in the PR line - no changes made to PR line.\n         Now taking PR line project id to check locus tag prefixes.\n");
	    }
	}

	$entry_pdid = $PRid;
    }
    else {
	if ($PR_line !~ /^PR\s+;$/) {
	    log_message("WARNING: PR line not in the correct format: $PR_line\n");
	}
	
	# PR line without project id in it.
	if ($pdid) {
	    $new_PR_line = "PR   Project:$pdid;\n";
	    log_message("Adding new PR line: $new_PR_line");
	    $entry_pdid = $pdid;
	}
    }

    if (! defined($$valid_locus_tag_prefixes{$entry_pdid})) {
	$$valid_locus_tag_prefixes{$entry_pdid} = SeqDBUtils2::get_locus_tag_from_project($entry_pdid, $dbh);
    }

    return($new_PR_line, $entry_pdid);
} # end check_PR_line_and_get_locus_tag_prefix

sub fix_entry_and_validate($$\%\%$$) {

    my $infile = shift; # contains a single entry
    my $fixed_file = shift; # filename of $outHandle for feeding to the validator
    my $valid_ec_num_hash = shift;
    my $qualifier_typo_hash = shift;
    my $dbh = shift;
    my $val_broken_email_sent = shift;

    my $prevPrefix    = "--";
    my $lineRead      = "";
    my @featureLines  = ();
    my @features      = ();
    my $PR_line       = "";
    my $PR_check_done = 0;
    my $entry_pdid  = 0;
    my %valid_locus_tag_prefixes;

    open(my $current_entry_fh, "<$infile");
    while (my $latestLine = <$current_entry_fh>) {
	
	chomp($latestLine);
	
	if ($latestLine =~ /[^ -~\n\r]/) {
	    my $cleaned = $latestLine;
	    $cleaned =~ s/[^ -~\n\r]/\*/g;
	    log_message(sprintf "!! Illegal character found in line %d of $infile:%s\n", $., $cleaned);
	}
	
	if ($latestLine =~ /^\s*$/) {
	    next;
	}
	
	my $linePrefix = "";
	
	if (length($latestLine) < 2) {
	    $linePrefix = $latestLine;
	} 
	else {
	    $linePrefix = substr($latestLine, 0, 2);
	}
	
	if ($linePrefix eq 'ID') {
	    my $ac = $latestLine;
	    $ac =~ s/^ID   ([0-9A-Z]+).*/$1/;
	    $quiet || log_message("=========== ENTRY $ac FOUND ===========\n");
	    $PR_check_done = 0;
	}
	if ($linePrefix eq 'DE') {
	    $quiet || log_message("=========== $latestLine\n");

	    if ($latestLine =~ /[^A-Za-z0-9]16S[^A-Za-z0-9]/) {
		$run_blast16S = 1;
	    }
	}
	elsif ($linePrefix eq '//') {
	    $quiet || log_message("\n");
	    $PR_line = ""; # clear PR line (in case there is a different one for each entry
	}
	
	if ($linePrefix eq "FT") {
	    
	    if ($prevPrefix ne "FT") {
		if ($lineRead !~ /^\s*$/) {
		    print $outHandle $lineRead."\n";
		}
	    }
	    
	    # new qualifier - NB can't easily spot new qualifiers
	    if (($latestLine =~ m|^FT                   /[a-zA-Z0-9_]+=|) ||    # eg normal qual
		($latestLine =~ m|^FT                   /[a-zA-Z0-9_]+\s*$|)) {  # eg /pseudo
		
		pushRawFeatureLine(@featureLines, $lineRead);
		
		$lineRead = $latestLine;

		if (! $run_blast16S) {
		    if (($latestLine =~ /FT                   \/gene\=\"16S rRNA\"/) ||
			($latestLine =~ /FT                   \/product\=\"16S ribosomal RNA\"/)) {
			$run_blast16S = 1;
		    }
		}
	    }
	    
	    # new feature
	    elsif ($latestLine =~ /^FT   [^ ]/) {
		if ($prevPrefix eq "FT") {
		    pushRawFeatureLine(@featureLines, $lineRead);
		    storeFeature(@features, @featureLines, %$qualifier_typo_hash, %$valid_ec_num_hash);
		}
		$lineRead = $latestLine;
	    } 
	    else {
		if ($latestLine =~ /^FT                   (.*)/) {
		    my $newText = $1;
		    
		    # concatenate text with spaces unless it is a translation or has broken on a dash
		    if (   ($lineRead =~ /\/translation=/)
			   || (substr($lineRead, -1) eq "-")) {
			$lineRead .= $newText;
		    } 
		    else {
			$lineRead .= " " . $newText;
		    }
		} 
	    }
	} 
	else {
	    
	    # if there is a PR line found (or no PR line found but pdid argument was used)
	    if (($linePrefix eq 'PR') || 
		(($linePrefix eq 'DE') && (! $PR_check_done) && $pdid)) { 
		($PR_line, $entry_pdid) = check_PR_line_and_get_locus_tag_prefix($dbh, $latestLine, %valid_locus_tag_prefixes);
		
		if ($PR_line ne "") {
		    if ($linePrefix eq 'PR') {
			$latestLine = $PR_line; #replace
		    }
		    else {
			$latestLine = $PR_line.$latestLine; #prepend
		    }
		}
		$PR_check_done = 1;
	    }
	    
	    # just left the feature table THIS IS THE IMPORTANT PART
	    if ($prevPrefix eq "FT") {
		pushRawFeatureLine(@featureLines, $lineRead);
		storeFeature(@features, @featureLines, %$qualifier_typo_hash, %$valid_ec_num_hash);
		process_FT(@features, %valid_locus_tag_prefixes, $entry_pdid);
		$lineRead = $latestLine;
	    }
	    # new linetype
	    elsif ($prevPrefix ne $linePrefix) {
		if ($lineRead !~ /^\s*$/) {
		    print $outHandle $lineRead."\n";
		}
		$lineRead = $latestLine;
	    }
	    # more line data
	    else {
		if ($latestLine =~ /..   +(.*)/) {
		    $lineRead .= " " . $1;
		}
	    }
	} ## end else [ if ($linePrefix eq "FT")	    
	
	$lineRead =~ s/\s*$//;
		    
	if (   ($latestLine =~ /^RL   Submitted/)
	       || ($linePrefix eq "DT")
	       || ($linePrefix eq "RX")
	       || ($linePrefix eq "DR")
	       || ($linePrefix eq "SV")
	       || ($linePrefix eq "DT")
	       || ($linePrefix eq "AS")
	       || ($linePrefix eq "FH")
	       || ($linePrefix eq "CC")
	       || ($linePrefix eq "  ")) {
	    $prevPrefix = "--";    # prevent line unwrapping of these
	} 
	else {
	    $prevPrefix = $linePrefix;
	}
    } ##end while (<$current_entry_fh>) 

    close($current_entry_fh);
    
    print $outHandle $lineRead."\n";
    close $outHandle;
    
    if ($runValidator) {
	run_validator($fixed_file, $val_broken_email_sent);
    }
} # end fix_entry_and_validate()

sub split_file_into_entry_files($) {

    my $file_to_split = shift;

    my @entry_filenames;

    if (open(my $read_entry, "<$file_to_split")) {

	my $entry_id = "";
	my $entry;

	while (my $line = <$read_entry>) {

	    $entry .= $line;

	    if (($line =~ /^\/\//) || (eof($read_entry))) {
		    
		if ($entry_id eq "") {
		    $entry_id = "entry_1";
		    my $counter = 0;
		    while(-e $entry_id) {
			$counter++;
			$entry_id = "entry_$counter";
		    }
		}

		push(@entry_filenames, $entry_id);
		open(my $entry_in, ">$entry_id");
		print $entry_in $entry;
		close($entry_in);

		$entry_id = "";
		$entry = "";
	    }
	    # get a name for the entry, because the name appears in validator output
	    elsif ($line =~ /ID   ([^;]+);/) {
		if ($1 ne "XXX") {
		    $entry_id = $1;
		}
	    }
	    elsif (($entry_id eq "") && ($line =~ /AC   ([^;]+);?/)) {
		if ($1 ne "XXX") {
		    $entry_id = $1;
		}
	    }
	}
	close($read_entry);
    }
    else {
	die "Unable to read file to split: $file_to_split\n";
    }

    return(\@entry_filenames);
} # end split_file_into_entry_files()

sub exit_if_files_contain_fts_blocking_debris(\@) {

    my $infiles = shift;

    my $fts_blocker_line = '[FTS added following line]';
    my $grep_cmd =  "grep \"".quotemeta($fts_blocker_line )."\" "
	.join(" ", @$infiles)." | sort -u | sed ".'"s/\:[^:]*//g"';


    my @files_with_FTS_lines = `$grep_cmd`;

    if (@files_with_FTS_lines) {
	print STDERR "ERROR: ".scalar(@files_with_FTS_lines)." files found containing the line \"$fts_blocker_line\".  "
	    . "Please remove these lines and run ftfix again.\n";

	if (scalar(@files_with_FTS_lines) < 11) {
	    print STDERR @files_with_FTS_lines;
	}
	else {
	    for (my $i=0; $i<10; $i++) {
		print STDERR $files_with_FTS_lines[$i];
	    }
	    print STDERR "...  (too many files to list)\n";
	}


	open(FTS_OUT, "<$fts_output_log") || die "Error: Cannot print out fts output\n";
	while (my $line = <FTS_OUT>) {
	    print STDERR $line;
	}
	close(FTS_OUT);

	exit;
    }
} # end exit_if_files_contain_fts_blocking_debris(\@)

sub getArgs () {
    my @infiles;
    my $usage =
        "\n PURPOSE: Unwrap EMBL files and remove identical lines from each feature\n"
      . "          Also removes lines with empty qualifiers, and cleans whitespace inside.\n"
      . "          NB if there are no files specified in the command and only sub files exist in the\n"
      . "          directory (no temp, ffl or fflupd files) and you use the -write_file option, then\n"
      . "          fts (ftsort3.pl) will be run and .temp files will be updated instead.\n\n"
      . " USAGE:  $0 [space-separated file list] [-st(rip)?] [-so(rt)?] [-val] [-qualfix]\n\n"
      . " [space-separated ds list]   a list of (concatenated) EMBL files\n"
      . " -f(ts)                      sorts feature table\n"
      . " -so(rt)                     sorts qualifiers within a feature (not by qualifier value)\n"
      . " -g(ene_strip)               removes gene features with min-max locations identical to a major feature\n"
      . " -p(eptide_fix)              adds gene and locus_tag qualifiers to peptide features\n"
      . "                             and also check that non-partial peptide lengths are a multiple of 3\n"
      . " -l(ocus_tag_fix)            evaluates locus_tag-gene name pairings and tries to add lines\n"
      . " -sp(an_check)               TBA\n"
      . " -st(ats)                    gives statistics about feature/qualifier usage and repeated notes\n"
      . " -c(omplement_loc_fix)       fixes locations where people have done complement(30..1)\n"
      . " -w(rite_file)               replaces file with output (backs up original to .del file)\n"
      . " -q(uiet)                    gives no error messages about the data\n"
      . " -o(bsolete_feature_fix)     applies some feature table changes\n"
      . " -val                        the validator will not be run (runs by default)\n"
      . " -qualfix                    typos in the qualifiers will be corrected (including EC_number)\n"
      . " -pd(id) <PR>                add project id (from PR line) for checking locus_tag prefixes are valid\n"
      . " -translation_strip          strip out translation qualifiers\n"
      . " -v(erbose)                  extra information may be given\n"
      . " -st(rip)                    removes db_xref, protein_id, codon_start=1, transl_table for simple diff\n"
      . " -help                       displays this help message\n\n";

    GetOptions("sort!"                 => \$doSort,
               "fts!"                  => \$doFts,
               "gene_strip!"           => \$doGeneStrip,
               "peptide_fix!"          => \$doPeptideFix,
               "strip!"                => \$doStrip,
               "span_check!"           => \$doSpanCheck,
               "write_file!"           => \$writeToFile,
               "stats!"                => \$doStats,
               "complement_loc_fix!"   => \$doComplement_loc_fix,
               "tagcloud!"             => \$doTagCloud,             # not documented since it needs tag.pl to make a html file from the product
               "quiet!"                => \$quiet,
               "verbose!"              => \$verbose,
               "locus_tag_fix!"        => \$doGeneLocusFix,
               "obsolete_feature_fix!" => \$doObsoleteFeatureFix,
	       "val!"                  => \$runValidator,
	       "qualfix!"              => \$doQualFix,
	       "pdid=i"                => \$pdid,
	       "translation_strip!"    => \$doTranslationStrip,
	       "help!"                 => \$help);

    if ($help) {
	die $usage;
    }

    foreach my $otherArg (@ARGV) {
        if (-e $otherArg) {
            push(@infiles, $otherArg);
        }
	else {
            die "I was assuming that $otherArg was a filename but I cannot see it\n$usage";
        }
    }

    my $fts_has_run = 0;
    if (scalar(@infiles) == 0) {
        SeqDBUtils2::get_input_files(@infiles);

	if ($infiles[0] =~ /\.fflupd$/) {
	    die "Please specify which file to update\n";
	}
	elsif (($infiles[0] =~ /\.sub$/) && $writeToFile) {

	    log_message("running ftsort3.pl on *.sub\n");
	    # the following command uses *.sub since this clause contains filenames from automatic search
	    system("/ebi/production/seqdb/embl/tools/curators/scripts/ftsort3.pl *.sub > $fts_output_log");
	    print STDERR "Running fts\n";
	    $fts_has_run = 1;
	    # NB Globbing is used here because the SeqDBUtils2::get_input_files
	    #  won't refresh the directory to find the newly created temp files
	    @infiles = glob("*.temp");
	}

	# no input files have been supplied or found
	if (! defined($infiles[0])) {
	    die "No input file was supplied and no fflupd, ffl, temp or sub files can be found in this directory\n";
	}
    }
    else {
	foreach my $file (@infiles) {
	    if ($file eq "BULK.SUBS") {
		die "Please run assign on BULK.SUBS before running ftfix\n";
	    }
	}
    }

    # exit with warning if any input files contain "[FTS added following line]"
    exit_if_files_contain_fts_blocking_debris(@infiles);

    if ($doSpanCheck && !($doFts)) {
        die "Cannot do a check of locus_tag span conflicts unless you sort the feature table\n" . "let me know if that limitation is a problem for you\n";
    }

    return(\@infiles, $fts_has_run);
} ## end sub getArgs ()

sub main {

    my ($infiles, $fts_has_run) = getArgs();

   # NB ptem is run before the .sub files are formed 
   if ((! $fts_has_run) && (! defined $$infiles[0])) {
	$quiet || log_message("Running ptem\n");
	system("/ebi/production/seqdb/embl/tools/ena_templates.sh -m p -l 1");
   }

    my $ftfix_output_log;
    if ($writeToFile) {
	# sets global $log_fh to output file called $ftfix_output_log (ftfix*.del)
	#print "Changing log file to ftfix....\n";
	$ftfix_output_log = open_new_output_file();
    }

    my $dbh = connect_to_enapro();
    my ($qualifier_typo_hash, $valid_ec_num_hash);
    if ($doQualFix) {
	($qualifier_typo_hash, $valid_ec_num_hash) = get_qualifier_substitution_hashes($dbh);
    }

    my (%entry_infile_hash);
    my $current_entry_file = "singleentry.".SeqDBUtils2::timeDayDate("yyyy-mm-dd-time");

    foreach my $infile (@$infiles) {
	
        if (scalar(@$infiles > 1)) {
            $quiet || log_message("opening $infile\n");
        }
	
	open($outHandle, ">" . $infile . $TEMPFILESUFFIX) || die "cannot open tempfile " . $infile . $TEMPFILESUFFIX . ": $!";

        if ($doTagCloud) {
            $noteWordFile = $infile . $TAGCLOUDSUFFIX;
            (-e $infile . $TAGCLOUDSUFFIX) && unlink($infile . $TAGCLOUDSUFFIX);
        }
	
	my $entry_id = "";
	my $val_broken_email_sent = 0;
	#(-e $infile.$TEMPFILESUFFIX) && unlink($infile.$TEMPFILESUFFIX);

	# if file contains more than one entry, fix and validate one entry at a time
	my $num_entries_in_file = `grep -c ^ID $infile`;
	if ($num_entries_in_file > 1) {

	    my $entry_files = split_file_into_entry_files($infile);

	    my @temp_entry_files;
	    my $orig_outHandle = $outHandle;

	    foreach my $entry (@$entry_files) {

		#print STDERR "Opening $entry.tmp\n";
		close($outHandle);
		open($outHandle, ">".$entry.".tmp");

		fix_entry_and_validate($entry, $entry.".tmp", %$valid_ec_num_hash, %$qualifier_typo_hash, $dbh, $val_broken_email_sent);
		push(@temp_entry_files, $entry.".tmp");
		unlink($entry); # delete single entry file (unfixed)
	    }

	    # concatenate single entries back into whole file and clear up the debris
	    my $cmd = "cat ".join(" ", @temp_entry_files)." > ".$infile.$TEMPFILESUFFIX;
	    system($cmd);

	    foreach my $temp_entry_file (@temp_entry_files) {
		print STDERR "delete $temp_entry_file\n";
		unlink($temp_entry_file);  # delete single entry file (fixed)
	    }

	    close($outHandle);

	}
	# validate single entry file (so doesn't need splitting)
	else {
#	    if (-e $infile.$TEMPFILESUFFIX) {
#		print STDERR $infile.$TEMPFILESUFFIX." exists\n";
#	    }
#	    else {
#		print STDERR $infile.$TEMPFILESUFFIX." absent\n";
#	    }
	    fix_entry_and_validate($infile, $infile.$TEMPFILESUFFIX, %$valid_ec_num_hash, %$qualifier_typo_hash, $dbh, $val_broken_email_sent);
	}

	# send file contents to stdout
	if (!$writeToFile) {
	    open(my $writeToStdOut, ">-") || die "cannot open pipe to STDOUT". ": $!";
	    
	    if  (open (my $temp_entry_handle, "<".$infile.$TEMPFILESUFFIX)) {
		while (my $line = <$temp_entry_handle>) {
		    print $writeToStdOut $line;
		}
		close($temp_entry_handle);
	    }
	    close($writeToStdOut);
	}
	
	

	# by this stage, $infile.$TEMPFILESUFFIX contains all the fixed $infile
	# data for single and multi entry files

	if ($writeToFile) {
	    if (-e $infile . $TEMPFILESUFFIX) {
		if (rename($infile, $infile . $OLDFILESUFFIX)) {
		    log_message(sprintf "%s updated (old version now at %s)\n", $infile, $infile . $OLDFILESUFFIX);
		    
		    if (!(rename($infile . $TEMPFILESUFFIX, $infile))) {
                        log_message(sprintf "! could not replace %s with tempfile %s\n", $infile, $infile . $TEMPFILESUFFIX);
                    }
                } 
		else {
                    log_message(sprintf "! could not rename %s to %s, replacement skipped\n", $infile, $infile . $OLDFILESUFFIX);
                }
	    }
	}
	else {
	    unlink($infile.$TEMPFILESUFFIX);
	}

    } ## end foreach my $infile (@$infiles)

    if ($dbh) {
	$dbh->disconnect();
    }

    if ($fts_has_run) {
	save_ftsort_output_to_log();
    }

    if ($run_blast16S) {
	log_message("16S sequence(s) found.  Please find blast_16S results in blast16S_summary\n");
	system("/ebi/production/seqdb/embl/tools/curators/scripts/curator_blast.pl -t=16S -quick -auto");
    }

    if (defined($log_fh)) {
	close($log_fh);
	print STDERR "ftfix output can be found in $ftfix_output_log\n";
    }
} ## end sub main

main();

