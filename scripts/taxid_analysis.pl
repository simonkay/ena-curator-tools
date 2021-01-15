#!/ebi/production/seqdb/embl/tools/bin/perl -w

#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/taxid_analysis.pl,v 1.7 2011/11/29 16:33:38 xin Exp $
#
#  DESCRIPTION:
#

use strict;
use DBI;
use dbi_utils;
use Data::Dumper;
#------------------------------------------------
sub get_extended_hash_of_species(\@\%) {

    my ($data_row, @row);

    my $data_list = shift;
    my $species = shift;    # empty hash to populate

    foreach $data_row (@$data_list) {

	@row = split(/\t/, $data_row);
	chomp($row[4]);

	$$species{$row[4]} = $row[0]."\t".$row[1]."\t".$row[4]."\t".$row[3]."\t".$row[4]."\t";
    }

    sort { $a == $b } keys(%$species);
}
#------------------------------------------------
sub get_hash_of_organisms(\@\%) {

    my ($data_row, @row);

    my $data_list = shift;
    my $species = shift;    # empty hash to populate

    foreach $data_row (@$data_list) {

	@row = split(/\t/, $data_row);
	chomp($row[4]);

	#$$species{$row[4]} = $row[0]."\t".$row[1]."\t".$row[2]."\t".$row[3]."\t";
	$$species{$row[2]} = $row[0]."\t".$row[1]."\t".$row[2]."\t".$row[3]."\t".$row[4]."\t";
    }

    sort { $a == $b } keys(%$species);
}
#------------------------------------------------
sub the_species_match(\%$) {

    my ($match_found, $trace_or_genome_org, $current_org_species);

    my $trace_or_genome_species = shift;
    my $current_org = shift;

    $match_found = 0;

    # if the current organism is species+extrastuff, grab it's species.
    if ($current_org =~ /^(\w+\s\w+)\s\S+/) {
	$current_org_species = $1;

	foreach $trace_or_genome_org (keys(%$trace_or_genome_species)) {
	    if ($current_org_species eq $trace_or_genome_org) {
		$match_found = 1;
		last;
	    }
	}
    }
    # if the current organism is species only, search 
    # against the trace/genome species instead
    else {
	foreach $trace_or_genome_org (keys(%$trace_or_genome_species)) {

	    if ($trace_or_genome_org =~ /^(\w+\s\w+)\s\S+/) {
		$trace_or_genome_org = $1;
	    }

	    if ($current_org eq $trace_or_genome_org) {
		$match_found = 1;
		last;
	    }
	}
    }

    return($match_found);
}
#------------------------------------------------
sub the_orgs_match(\%$) {

    my ($trace_or_genome_org, $match_found);

    my $trace_or_genome_orgs = shift;
    my $current_org = shift;


    foreach $trace_or_genome_org (keys(%$trace_or_genome_orgs)) {
	if ($trace_or_genome_org eq $current_org) {
	    $match_found = 1;
	    last;
	
	}
    }

    return($match_found);
}
#------------------------------------------------
sub add_trace_genomes_comparison_data($$) {

    my ($all_results_file, $species, %genome_species, %trace_species);
    my (@genome_data, @trace_data, %all_species, $organism);
    my ($trace_genus_species, %genome_species_extended_list);
    my (%trace_species_extended_list);

    my $genomes_output_file = shift;
    my $traces_output_file = shift;

    open(READGENOMES, "<".$genomes_output_file) || die "Cannot open $genomes_output_file for reading\n";
    @genome_data = <READGENOMES>;
    close(READGENOMES);

    open(READTRACES, "<".$traces_output_file) || die "Cannot open $traces_output_file for reading\n";
    @trace_data = <READTRACES>;
    close(READTRACES);


    if ($genomes_output_file =~ /(.+?)\.RESULTS/) {
	$all_results_file = $1.".FULLRESULTS";
    }
    
    get_hash_of_organisms(@genome_data, %genome_species); # send empty hash to populate
    get_hash_of_organisms(@trace_data,  %trace_species);  # send empty hash to populate
    get_extended_hash_of_species(@genome_data, %genome_species_extended_list); # send empty hash to populate
    get_extended_hash_of_species(@trace_data,  %trace_species_extended_list);  # send empty hash to populate

    %all_species = (%genome_species,  %trace_species);


    foreach $organism (keys(%all_species)) {

        # exact match with trace organism?
	if (the_orgs_match(%trace_species, $organism)) {
	    $all_species{$organism} .= "\tT\t"; 
	}
        # species match with trace species?
	elsif (the_species_match(%trace_species_extended_list, $organism)) {
	    $all_species{$organism} .= "\tt\t";
	}
        # no trace match
	else {
	    $all_species{$organism} .= "\t-\t";
	}


        # exact match with genome organism?
	if (the_orgs_match(%genome_species, $organism)) {
	    $all_species{$organism} .= "E\n"; 
	}
        # species match with genome species?
	elsif (the_species_match(%genome_species_extended_list, $organism)) {
	    $all_species{$organism} .= "e\n";
	}
        # no genome match
	else {
	    $all_species{$organism} .= "-\n";
	}
    }


    open(WRITEALL, ">".$all_results_file) || die "Cannot open $all_results_file for writing\n";
    foreach $species (keys(%all_species)) {
	print WRITEALL $all_species{$species};
    }
    close(WRITEALL);


    return($all_results_file);
}
#------------------------------------------------
sub store_not_found_tax_ids(\@) {

    my ($new_filename, $tax_id_info);

    my $tax_ids_not_found = shift;

    $new_filename = "tax_ids_not_in_database.list";

    open(WRITETAXIDS, ">$new_filename")  || die "Cannot open $new_filename for writing\n";
    foreach $tax_id_info (@$tax_ids_not_found) {
	print WRITETAXIDS $tax_id_info;
    }

    close(WRITETAXIDS);
}
#------------------------------------------------
sub get_tax_data($$$$\@) {

    my ($species, $name, $division, $rank, $tax_id_match);
    my ($genome_taxid, $trace_taxid, $row_found);

    my $dbh = shift;
    my $FILEHANDLE = shift;
    my $sth = shift;
    my $tax_id = shift;
    my $compare_taxid_list = shift;

    $row_found = 0;

    $sth->execute($tax_id);

    while (($species, $name, $division, $rank) = $sth->fetchrow_array()) {

	$row_found = 1;

	if (!defined($rank) || ($rank eq "")) {

	    $rank = "";

	    if (! defined $species) {
		$rank = "strain";
	    }
	}

	if (!defined $species) {
	    print "species not defined\n";
	    print "tax_id = $tax_id\n";
	    $species = "NOT SPECIES $tax_id";
	}


	print $FILEHANDLE $division."\t".$tax_id."\t".$name."\t".$rank."\t".$species."\n";
    }

    return($row_found);
}
#------------------------------------------------
sub get_lineage_data($$) {

    my ($genomes_output_file, $traces_output_file, $sql, $dbh);
    my ($species, $name, $division, $rank, $tax_id, $row_found);
    my (@genome_taxids, @trace_taxids, $WRITEGENOMES, $WRITETRACES);
    my (@tax_ids_not_found, $sth);

    my $genomes_input_file = shift;
    my $traces_input_file = shift;

    $genomes_output_file = $genomes_input_file.".RESULTS";
    open($WRITEGENOMES, ">".$genomes_output_file) || die "Cannot open $genomes_output_file for writing\n";

    $traces_output_file = $traces_input_file.".RESULTS";
    open($WRITETRACES, ">".$traces_output_file) || die "Cannot open $traces_output_file for writing\n";

    # grab tax_ids
    open(READGENOMES, "<".$genomes_input_file) || die "Cannot open $genomes_input_file for reading\n";
    @genome_taxids = <READGENOMES>;
    close(READGENOMES);

    open(READTRACES, "<".$traces_input_file) || die "Cannot open $traces_input_file for reading\n";
    @trace_taxids = <READTRACES>;
    close(READTRACES);


    $dbh = dbi_ora_connect('/@enapro')  or die "Can't connect to database: $DBI::errstr";

    $sql = "select lin.species, 
                    lin.leaf, 
                    lin.division, 
                    tax.rank
             from  ntx_lineage lin, ntx_tax_node tax 
             where tax.tax_id = lin.tax_id and
                    lin.tax_id = ?";
    $sth = $dbh->prepare($sql);


    foreach $tax_id (@genome_taxids) {
	chomp($tax_id);
	$row_found = 0; 
	$row_found = get_tax_data($dbh, $WRITEGENOMES, $sth, $tax_id, @trace_taxids);
	if (!$row_found) {
	    push(@tax_ids_not_found, "$tax_id\t$genomes_input_file");
	}
    }

    foreach $tax_id (@trace_taxids) {
	chomp($tax_id);
	$row_found = 0;
	$row_found = get_tax_data($dbh, $WRITETRACES, $sth, $tax_id, @genome_taxids);

	if (!$row_found) {
	    push(@tax_ids_not_found, "$tax_id\t$traces_input_file");
	}
    }


    $dbh->disconnect;

    store_not_found_tax_ids(@tax_ids_not_found);

    return($genomes_output_file, $traces_output_file);
}
#------------------------------------------------
sub get_args(\@) {

    my ($arg, $genomes_input_file, $traces_input_file, $usage);
    my $args = shift;

    $usage = "$0 -g=<genomes_file> -t=<traces_file>\n\n"
	. "Please enter 2 arguments which are the filenames of 2 files containing newline-separated lists of tax ids. A results file will be produced which contains a variety of data associated with the tax id.  A comparison of the 2 files is also carried out.\n\n";


    $genomes_input_file = "";
    $traces_input_file = "";

    if (scalar(@$args) != 2) {
	die "Two arguments are required.  These are the filenames of files containing lists of tax ids\n\n$usage";
    }

    foreach $arg (@$args) {

	if ($arg =~ /^-g=(.+)/) {
	    $genomes_input_file = $1;

	    if (! -e $genomes_input_file) {
		die "The entered file $genomes_input_file does not exist.\n";
	    }
	}
	elsif ($arg =~ /^-t=(.+)/) {
	    $traces_input_file = $1;

	    if (! -e $traces_input_file) {
		die "The entered file $traces_input_file does not exist.\n";
	    }
	}
    }

    if (($genomes_input_file eq "") || ($traces_input_file eq "")) {
	die "Both a genomes filename and traces filename need to be entered.\n\n$usage\n";
    }

    return($genomes_input_file, $traces_input_file);
}
#------------------------------------------------
sub main(\@) {

    my ($genomes_input_file, $traces_input_file, $dbh);
    my ($genomes_output_file, $traces_output_file, $results_file);
    my $args = shift;

    ($genomes_input_file, $traces_input_file) = get_args(@$args);

    ($genomes_output_file, $traces_output_file) = get_lineage_data($genomes_input_file, $traces_input_file);

    $results_file = add_trace_genomes_comparison_data($genomes_output_file, $traces_output_file);

print "$genomes_output_file and $traces_output_file are output files containing species/leaf/division information.\n\n$results_file contains all the tax_id information including a note of which file the tax_id has come from.\n";
}



main(@ARGV);
