#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/check_locustag_and_gene_pairs.pl,v 1.5 2011/11/29 16:33:37 xin Exp $
#
#  (C) EBI 2008
#
###############################################################################

use strict;
use Data::Dumper;

my $verbose = 0;

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------


#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------


#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------


#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub print_report($\%\@) {

    my ($num_diff_genes, $num_empty_gene_quals, $gene, $blank_gene);

    my $distinct_locus = shift;
    my $genes_for_this_locus = shift;
    my $blank_genes_for_this_locus = shift;

    $num_diff_genes = scalar(keys(%$genes_for_this_locus));
    $num_empty_gene_quals = scalar(@$blank_genes_for_this_locus);
    
    # if there is more than one gene associated with this locus, complain!
    if ($num_diff_genes > 1) {
	print "  WARNING: $distinct_locus has $num_diff_genes gene qualifiers associated with it";
	
	if ($num_empty_gene_quals) {
	    print " plus $num_empty_gene_quals missing gene qualifier(s)";
	}

	print ":\n";
	
	foreach $gene (keys(%$genes_for_this_locus)) {
	    $$genes_for_this_locus{$gene} =~ s/, .$//;

      	    print "\t\t$gene\tfeature start line(s): $$genes_for_this_locus{$gene}\n";
	}
	
	foreach $blank_gene (@$blank_genes_for_this_locus) {
	    print "\t\tblank\tfeature start lines: $blank_gene\n";
	}
    }
    elsif (($num_diff_genes == 1) && $num_empty_gene_quals) {
	print "  WARNING: The locus $distinct_locus contains features that should have gene qualifier in them:\n";
    }
    elsif ($num_diff_genes == 1) {
	print "  ok\n";
    }
    elsif ($num_empty_gene_quals) {
	print "  WARNING: The locus $distinct_locus has no gene qualifiers associated with it's locus_tags\n";
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_distinct_list_of_loci_from_entry($) {

    my (%loci, @loci, $feature, $qual);

    my $entry = shift;

    foreach $feature (@{ $entry }) {

	foreach $qual (@{ $$feature{qualifiers} }) {

	    if ($qual =~ /^(locus_tag="[^"]+")/) { #"
		$loci{$1} = 1;
	    }
	}
    }

    @loci = keys(%loci);

    return(\@loci);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub check_for_conflicting_genes(\@) {

    my ($distinct_loci_list, $distinct_locus, $entry, $feature);
    my (@blank_genes_for_this_locus, %genes_for_this_locus, $qualifier_ctr);
    my ($qual, $get_gene_qual);

    my $entry_info = shift;

    foreach $entry (@$entry_info) {

	$distinct_loci_list = get_distinct_list_of_loci_from_entry($entry);

	foreach $distinct_locus (@$distinct_loci_list) {

	    %genes_for_this_locus = ();
	    $get_gene_qual = 0;

            # look thu all the features for this locus
	    foreach $feature (@$entry) {

		foreach $qual (@{ $$feature{qualifiers} }) {

		    # for this distinct locus what are the associated genes?
		    if ($qual eq $distinct_locus) {
			$get_gene_qual = 1;
		    }

		    if ($get_gene_qual && ($qual =~ /^gene/)) {
			$genes_for_this_locus{$qual} .= "$$feature{ft_start_line_num}, ";
		    }
		}

		if (!(keys(%genes_for_this_locus))) {

		    #print "feature{ft_start_line_num} = $$feature{ft_start_line_num}\n";
		    push(@blank_genes_for_this_locus, $$feature{ft_start_line_num});
		}
	    }

#	    print "genes_for_this_locus:".join(", ", @genes_for_this_locus);
#	    print "blank_genes_for_this_locus:".join(", ", @blank_genes_for_this_locus);
#	    exit;
	    print_report($distinct_locus, %genes_for_this_locus, @blank_genes_for_this_locus);
	}
    }
}

#-------------------------------------------------------------------------------
# data structure of @entry_info
#
# $entry_info[$entry_num][$feature_num]{ft_start_line_num} = 51
# $entry_info[$entry_num][$feature_num]{ft_start_line} = "FT   exon            complement(882..1113)"
# $entry_info[$entry_num][$feature_num]{qualifiers}[0] = 'gene="geneA"'
# $entry_info[$entry_num][$feature_num]{qualifiers}[1] = 'locus_tag="locus1"'
# $entry_info[$entry_num][$feature_num]{qualifiers}[2] = 'locus_tag="locus2"'
#
#
# NB $entry_number is used in case there is more than one entry in a file
# NB2 lists of locus_tags and genes are created for each feature, in case there
# are multiple values
#-------------------------------------------------------------------------------

sub parse_file_contents($) {

    my ($line, @entry_info, $entry_ctr, $FT_start_line_num, $file_line_ctr);
    my ($feature_ctr, $locustag_ctr, $gene_ctr, $FT_start_line, $feature_ctr_used);
    my (@locus_tags, @genes, $num_locus_tag_qual, $num_gene_qual, $current_qualifier);
    my ($qual);

    my $file = shift;

    open(READEMBL, "<$file") || die "Can't open $file: $!\n";

    $entry_ctr = -1;
    $file_line_ctr = 1;
    $feature_ctr = 0;
    $locustag_ctr = 0;
    $gene_ctr = 0;
    $feature_ctr_used = 0;
    $num_locus_tag_qual = 0;
    $num_gene_qual = 0;

    print "$file:\n";

    while ($line = <READEMBL>) {

	if ($line =~ /^ID   \S+/) { # new entry
	    $entry_ctr++;
	}
	elsif ($line =~ /^(FT   \S+\s+[^\n]+)/) { # new feature
	    if ($feature_ctr_used) {
		$feature_ctr++;
		$feature_ctr_used = 0;
	    }

	    if (($num_locus_tag_qual) || ($num_gene_qual)) {
		if (($num_gene_qual != $num_locus_tag_qual) || ($num_gene_qual > 1) || ($num_locus_tag_qual > 1)) {
		    print "  WARNING: There is/are $num_locus_tag_qual locus_tag qualifier(s) and $num_gene_qual gene qualifier(s) in the feature starting on line $FT_start_line_num\n";
		}
	    }
	    if ((defined(@{ $entry_info[$entry_ctr][$feature_ctr]{qualifiers} })) && (scalar(@{ $entry_info[$entry_ctr][$feature_ctr]{qualifiers} }) > 1)) {
		@{ $entry_info[$entry_ctr][$feature_ctr]{qualifiers} } = reverse sort { $a cmp $b } @{ $entry_info[$entry_ctr][$feature_ctr]{qualifiers} };
	    }

	    $num_locus_tag_qual = 0;
	    $num_gene_qual = 0;

	    $FT_start_line = $1;
	    $FT_start_line_num = $file_line_ctr;
	}
	elsif ($line =~ /^FT                   \/((locus_tag|gene)="[^"]+")/) { #"

	    $current_qualifier = $1;

	    foreach $qual (@{ $entry_info[$entry_ctr][$feature_ctr]{qualifiers} }) {
		if ($qual eq $current_qualifier) {
		    print "  WARNING: A duplicate qualifier has been detected: $current_qualifier in the feature starting on line $FT_start_line_num\n";
		}
	    }

	    if ($current_qualifier =~ /^gene/) {
	        $num_gene_qual++;
	    }
	    elsif ($current_qualifier =~ /^locus/) {
	        $num_locus_tag_qual++;
	    }

	    push(@{ $entry_info[$entry_ctr][$feature_ctr]{qualifiers} }, $current_qualifier);

	    $entry_info[$entry_ctr][$feature_ctr]{ft_start_line_num} = $FT_start_line_num;
	    $entry_info[$entry_ctr][$feature_ctr]{ft_start_line} = $FT_start_line;

	    $feature_ctr_used = 1;   # $feature_ctr is not used for features without locus_tag/gene quals

	}

	$file_line_ctr++;
    }

    close(READEMBL);



    return(\@entry_info);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub parse_files(\@) {

    my ($file, $entry_info);

    my $input_files = shift;

    foreach $file (@$input_files) {

	($entry_info) = parse_file_contents($file);

	check_for_conflicting_genes(@$entry_info);
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_input_files() {

    my (@input_files); 

#    @input_files = glob('*.EMBL');

    $input_files[0] = 'Pc00c32.EMBL';

    return(\@input_files);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub get_args(\@) {

    my ($arg, @ds_dirs, $database, $ds, @ds_not_valid, $ds_dir_root);

    my $args = shift;

    my $usage = "\n PURPOSE: The assigns accessions to *.temp or BULK.SUBS entries bulks in\n".
	"          different ds directories at the same time.\n\n".
        " USAGE:  $0 username/password\@db [space-separated ds list] [-v(erbose)?]\n\n".
        ' username/password@db        /@enapro or /@devt'."\n\n".
	" [space-separated ds list]   a list of 1+ different ds numbers you want to assigning\n".
	"                             together e.g. 70623 70654 71456\n\n".
	" -v(erbose)                  verbose mode\n\n";

    @ds_dirs =();

    foreach $arg (@$args) {
        
        if (($arg =~ /^-h(elp)?/i) || ($arg =~ /^-u(sage)?/i)) {
            die $usage;
        }
	elsif ($arg =~ /-v(erbose)?/i) {
	    $verbose = 1;
	}
	else {
	    die "Option $arg not recognised\n\n$usage";
	}
    }
}

#-------------------------------------------------------------------------------------
# main flow of program
#-------------------------------------------------------------------------------------

sub main(\@) {

    my ($input_files);

    my $args = shift;

    #get_args(@$args);
    $input_files = get_input_files();

    parse_files(@$input_files);

}

#-------------------------------------------------------------------------------------
# run program
#-------------------------------------------------------------------------------------

main(@ARGV);
