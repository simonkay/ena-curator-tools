#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# This script allow the user to view and edit a genome project, which is
# defined by the input parameters.  This script connects to 
# genome_project_add.pl which allows the user to add a new project when using
# the option -add.
#
#  (C) EBI 2007
#
#===============================================================================

use strict;
use Data::Dumper;


################################################################################

sub display_project_details(\@) {

    my ($i);

    my $results = shift;

    for ($i=0; $i<@$results; $i++) {
	print "Project ID:       ";
	if (defined $$results[$i]{project_id}) {
	    print $$results[$i]{project_id};
	}

	print "\nOrganism:         ";
	if (defined $$results[$i]{org_name}) {
	    print $$results[$i]{org_name};
	}

	print "\nStrain:           ";
	if (defined $$results[$i]{strain_name}) {
	    print $$results[$i]{strain_name};
	}

	print "\nLocus_tag prefix: ";
	if (defined $$results[$i]{locus_tag_prefix}) {
	    print $$results[$i]{locus_tag_prefix};
	}

	print "\nCreate Date:      ";
	if (defined $$results[$i]{create_date}) {
	    print $$results[$i]{create_date};
	}

	print "\nAccession:        ";
	if (defined $$results[$i]{acc_insdc}) {
	    print $$results[$i]{acc_insdc};
	}

	print "\nCentre Name:      ";
	if (defined $$results[$i]{centre_name}) {
	    print join(", ", @{$$results[$i]{centre_name}});
	}

	print "\nContact Name:     ";
	if (defined(@{$$results[$i]{name}})) {
	    print join(", ", @{$$results[$i]{name}});
	}

	if (defined(@{$$results[$i]{email}})) {
	    print " (".join(", ", @{$$results[$i]{email}}).")\n\n";
	}
	else {
	    print "\n\n";
	}
    }
}

################################################################################

sub store_if_a_search_match(\@\%\%) {

    my ($search_field, $match_found, $number_to_match, $match_num, %my_entry);
    my (@name_parts, $email_address, $name);

    my ($results, $entry, $search_terms) = @_;

    $match_num = 0;
    $match_found = 0; # for use in the subentry fields
    $number_to_match = scalar(keys(%$search_terms));

    foreach $search_field (keys %$search_terms) {

	if ($search_field eq "project_id") {

	    if ($$entry{$search_field} eq $$search_terms{$search_field}) {
		$match_num++;
	    }
	}
	elsif ($search_field eq "email") {

	    foreach $email_address (@{$$entry{email}}) {
		if ($email_address =~ /$$search_terms{email}/i) {
		    $match_found++;
		}
	    }
	    if ($match_found) {
		$match_num++;
	    }
	    $match_found = 0;
	}
	elsif ($search_field eq "name") {
	    
	    foreach $name (@{$$entry{name}}) {
		if ($name =~ /$$search_terms{name}/i) {
		    $match_found++;
		}
	    }

	    if ($match_found) {
		$match_num++;
	    }
	    $match_found = 0;
	}
	elsif ((defined($$entry{$search_field})) && 
	       ($$entry{$search_field} =~ /$$search_terms{$search_field}/i)) {
	    $match_num++;
	}

    }

    if ($match_num == $number_to_match) {
	%my_entry = %$entry;
	push(@$results, \%my_entry);
    }
}

################################################################################

sub open_data_file() {

    my (@data_files, $fh);

    @data_files = `ls -lt /ebi/production/seqdb/embl/data/ncbi_projects/ftp-private.ncbi.nih.gov/GenProjDB/dumps/*.v4.dump.xml`;

    # extract filename from first (newest) file in list
    #-rw-r--r-- 1 datalib services 12013019 Aug 20 12:03 /ebi/production/seqdb/embl/data/ncbi_projects/ftp-private.ncbi.nih.gov/GenProjDB/dumps/20090820.v4.dump.xml

    if ($data_files[0] =~ /[^\/]+(.+)/) {
	open($fh, "<$1") || die "Cannot read $1\n";
#	open($fh, "</net/isilon3/production/seqdb/embl/data/ncbi_projects/ftp-private.ncbi.nih.gov/GenProjDB/dumps/gem.test") || die "Cannot read /net/isilon3/production/seqdb/embl/data/ncbi_projects/ftp-private.ncbi.nih.gov/GenProjDB/dumps/gem.test\n";
    }
    else {
	die "$data_files[0] doesn't match the regex\n";
    }

    return($fh);
}

################################################################################

sub find_projects_matching_args(\%) {

    my ($fh, $line, %entry, @results, $results_counter, %name_list, %email);
    my (%centrename, $first_name);

    my $search_terms = shift;

    $results_counter = 0;
    $first_name = "";

    $fh = open_data_file();
    
    while ($line = <$fh>) {

	if ($line =~ /<gp:ProjectID>([^<]+)/) {
	    $entry{project_id} = $1;
	}
	elsif ($line =~ /<gp:OrganismName>([^<]+)/) {
	    $entry{org_name} = $1;
	}
	elsif ($line =~ /<gp:StrainName>([^<]+)/) {
	    $entry{strain_name} = $1;
	}
	elsif ($line =~ /<gp:LocusTagPrefix>([^<]+)/) {
	    $entry{locus_tag_prefix} = $1;
	}
	elsif ($line =~ /<gp:CreateDate>([^<]+)/) {
	    $entry{create_date} = $1;
	}
	elsif ($line =~ /<gp:CenterName>([^<]+)/) {
	    $centrename{$1} = 1;
	}
	elsif ($line =~ /<gp:accINSDC>([^<]+)/) {
	    $entry{acc_insdc} = $1;
	}
	elsif ($line =~ /<gp:FirstName>([^<]+)/) {
	    $first_name = $1;
	}
	elsif ($line =~ /<gp:LastName>([^<]+)/) {

            # I make that assumption all first_name fields with data have 
	    # an accompanying last_name field
	    if ($first_name ne "") {
		$name_list{"$first_name $1"} = 1; # uniquify
		$first_name = "";
	    }
	    else {
		$name_list{$1} = 1;
	    }
	}
	elsif ($line =~ /<gp:Email>([^<]+)/) {
	    $email{$1} = 1;
	}
	elsif (($line =~ /<\/gp:Document>/) || (eof($fh))) {

	    # enter unique list of names/emails/centrenames into entry hash
	    if (keys(%name_list)) {
		push(@{$entry{name}}, keys(%name_list));
	    }
	    if (keys(%email)) {
		push(@{$entry{email}}, keys(%email));
	    }
	    if (keys(%centrename)) {
		push(@{$entry{centre_name}}, keys(%centrename));
	    }

	    # process previous entry
	    if (scalar(keys(%entry))) {
		store_if_a_search_match(@results, %entry, %$search_terms);
	    }

	    # new entry
	    %entry = ();
	    %name_list = ();
	    %email = ();
	    %centrename = ();
	    $first_name = "";
	}
    }
	   
    close($fh);
	   
    return(\@results);
}

################################################################################

sub get_args(\@) {

    my ($usage, $arg, %search_terms, $input);

    my $args = shift;

    $usage =
    "\n USAGE: $0 [-h(elp)]\n\n"
  . " PURPOSE: Perform a search on the latest ncbi projects."
  . "  You will be prompted for search terms.\n\n"
  . " ALIASES: gps and gpsearch\n";

    foreach $arg (@$args) {

	if ($arg  =~ /^-h(elp)?/i) {
	    die $usage;
	}
    }

    print "Search for NCBI genome projects\nSkip any search fields by leaving blank and pressing 'return'\n\n";
    print "Enter project id: ";
    $input = <STDIN>;
    chomp($input);
    if ($input ne "") {
	$search_terms{project_id} = $input;
    }

    print "Enter (part of) organism name: ";
    $input = <STDIN>;
    chomp($input);
    if ($input ne "") {
	$search_terms{org_name} = $input;
    }

    print "Enter (part of) strain name: ";
    $input = <STDIN>;
    chomp($input);
    if ($input ne "") {
	$search_terms{strain_name} = $input;
    }

    print "Enter (part of) locus_tag prefix: ";
    $input = <STDIN>;
    chomp($input);
    if ($input ne "") {
	$search_terms{locus_tag_prefix} = $input;
    }

    print "Enter (part of) name: ";
    $input = <STDIN>;
    chomp($input);
    if ($input ne "") {
	$search_terms{name} = $input;
    }
    
    print "Enter (part of) email:  ";
    $input = <STDIN>;
    chomp($input);
    if ($input ne "") {
	$search_terms{email} = $input;
    }

    print "\n";

    if (! scalar(keys(%search_terms))) {
	die "In order to run the search you must have at least one search term\n";
    }
    else {
	print "Searching...\n\n";
    }

    return(\%search_terms);
}

################################################################################
sub main(\@) {

    my ($search_terms, $results);

    my $args = shift;

    $search_terms = get_args(@$args);

    $results = find_projects_matching_args(%$search_terms);
 
    if (@$results) {
	display_project_details(@$results);
    }
    else {
	print "No records match search criteria\n";
    }
}

################################################################################
# Run the script

main(@ARGV);
