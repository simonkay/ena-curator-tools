#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/get_biodiversity_stats.pl,v 1.3 2010/09/29 08:33:45 faruque Exp $
#
#  (C) EBI 2007
#
# This script checks if species from a text file are present in a web service
# of species (Catalogue of Life) 
#
###############################################################################

use strict;
use LWP::UserAgent;
use URI::Escape;

my $col_url = "http://www.catalogueoflife.org/annual-checklist/2010/webservice?name=";
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub get_web_page($) {
    my $species = shift;

    #escape odd characters but spaces need to change to +
    my $species_for_url = join('+', map{uri_escape($_)} split(' ',$species));

    my $request_URL = $col_url . $species_for_url;

    my $ua = new LWP::UserAgent;
    $ua->timeout(1000);

    my $req = new HTTP::Request GET => $request_URL;
    print "Retrieving info for $species\n";

    my $result = $ua->request($req);
    if (!( $result->is_success )) {
	print STDERR "No reply\n";
	return "";
    }
    
    my $rescontent = $result->content;	       

    if ( $rescontent =~ /<results id=.+?total_number_of_results="(\d+)"/ ) {

	if ($1 > 0) {
	    return $1;  # species found
	}
	else {
	    return 0;  # species not found
	}
    }
}
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub check_catalogue_with_species(\@) {

    my ($species, $species_status, $species_count);

    my $species_list = shift;

    open(SPECIESFOUND, ">species.found") || die "Cannot open species.found\n";
    open(SPECIESFOUND_MULTIPLE, ">species.found.multiple") || die "Cannot open species.found.multiple\n";
    open(SPECIESMISSING, ">species.missing") || die "Cannot open species.missing";

    foreach $species (@$species_list) {
	if ($species =~ /\w+/) {

	    $species =~ s/\n$//;
	    $species_status = get_web_page($species);

	    if ($species_status) {
		print SPECIESFOUND "$species\n";

		if ($species_status > 1) {
		    print SPECIESFOUND_MULTIPLE "$species\t\t$species_status results\n";
	        }
	    }
	    else {
		print SPECIESMISSING "$species\n";
	    }

	    $species_count++;
	}
    }
    close(SPECIESFOUND);
    close(SPECIESMISSING);
    close(SPECIESFOUND_MULTIPLE);

    return($species_count);
}
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub display_summary($) {

    my ($num_found, $num_found_multiple, $num_missing, $msg);

    my $species_count = shift;

    $num_found = `wc -l species.found`;
    $num_found_multiple =  `wc -l species.found.multiple`;
    $num_missing =  `wc -l species.missing`;

    $num_found   =~ s/(\d+)[^\d]+/$1/;
    $num_found_multiple   =~ s/(\d+)[^\d]+/$1/; # e.g. Drosophila melanogaster
    $num_missing =~ s/(\d+)[^\d]+/$1/;

    $msg = "\nSummary:\n"
	. "Number of species found in Catalogue of life:       $num_found"
	. "  ($num_found_multiple of these have multiple results)\n"
	. "Number of species *not found* in Catalogue of life: $num_missing\n"
	. "--------------------------------------\n"
	. "Total number of species checked: $species_count\n\n";


    open(SPECIES_SUMMARY, ">species.summary") || die "Cannot open species.summary\n";

    print SPECIES_SUMMARY $msg;
    print $msg;

    close(SPECIES_SUMMARY);
}
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub parse_list_of_species($) {

    my (@species);

    my $file = shift;

    open(SPECIESLIST, "<$file") || die "Can't open $file\n";
    @species = <SPECIESLIST>; 
    close(SPECIESLIST);

    return(\@species);
}
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub get_args(\@) {

    my $args = shift;

    if (scalar(@$args) != 1) {
	die "Bad usage.\nGood usage: get_biodiversity_stats.pl <filename containing list of species>\n";
    }
    else {
	if (! -e($$args[0])) {
	    die "$$args[0] can't be found.  It should be the name of a file containing a list of species to be checked against the Catalogue of Life.\n";
	}
    }

    return($$args[0]);
}
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub main(\@) {

    my ($file, $species_list, $species_count);

    my $args = shift;

    $file = get_args(@$args);

    $species_list = parse_list_of_species($file);

    $species_count = check_catalogue_with_species(@$species_list);

    display_summary($species_count);
}

main(@ARGV);
