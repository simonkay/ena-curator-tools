#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/get_lineages.pl,v 1.4 2011/11/29 16:33:38 xin Exp $
#
#  (C) EBI 2007
#
# This script checks if species from a text file are present in a web service
# of species (Catalogue of Life) 
#
###############################################################################

use strict;
use DBI;
use dbi_utils;


#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub store_scientific_names(\@$) {

    my ($dbh, $lineage, $query, $sql, @results, $bind_param);
    my ($sci_name_count, $sci_name_total_count, $msg);

    my $lineage_list = shift;
    my $database = shift;

    open(STORE_RESULTS, ">scientific_names.list") || die "Cannot open scientific_names.list\n";    

    $dbh = dbi_ora_connect($database);

    $sql = "select leaf from ntx_lineage where lineage like ? and metagenome = 'N' and species is not null and species not like '% sp.%'";
#    $sql = "select leaf from ntx_lineage where lineage like ? and metagenome = 'N' and species is not null";
    print "sql = $sql\n";

    $query = $dbh->prepare($sql);
    $sci_name_total_count = 0;
    $msg = "Summary:\n";

    foreach $lineage (@$lineage_list) {

	$sci_name_count = 0;

	if ($lineage =~ /\w+/) {

	    $lineage =~ s/\n$//;
            $query = $dbh->prepare($sql);

	    $bind_param = '%'.$lineage.'%';
	    print "bind_param = $bind_param\n";
            $query->bind_param(1, $bind_param);

            $query->execute();

	    while (@results = $query->fetchrow_array()) {
		print STORE_RESULTS "$results[0]\n";
		$sci_name_count++;
	    }

	    $sci_name_total_count += $sci_name_count;

	    $msg .= "$lineage\t\t$sci_name_count entries found in $database\n";
	}
    }

    dbi_logoff($dbh);
    close(STORE_RESULTS);

    $msg .= "------------------\n"
	. "Total number of entries retrieved: $sci_name_total_count\n\n";


    print $msg;
    open(RESULTS_SUMMARY, ">scientific_names.list.summary") || die "Cannot open scientific_names.list.summary\n";
    print RESULTS_SUMMARY $msg;
    close(RESULTS_SUMMARY);
}
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub parse_list_of_lineages($) {

    my (@lineages);

    my $file = shift;

    open(LINEAGELIST, "<$file") || die "Can't open $file\n";
    @lineages = <LINEAGELIST>; 
    close(LINEAGELIST);

    return(\@lineages);
}
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub get_args(\@) {

    my ($arg, $database, $file);

    my $args = shift;

    $file = "";
    $database = "";

    foreach $arg (@$args) {

	if ($arg =~ /(\/\@(enapro|devt))/i) {
	    $database = $1
	}
	elsif ($arg =~ /([^-]+.*)/) {
	    $file = $1;

	    if (! -e($file)) {
		die "$1 can't be found.  It should be the name of a file containing a list of lineages or part-lineages.\n";
	    }
	}
    }

    if (($database eq "") || ($file eq "")) {
	die "Bad usage.\nGood usage: get_lineages.pl ".'</@enapro or /@devt>'." <filename containing list of lineages>\n";
    }

    return($file, $database);
}

#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
sub main(\@) {

    my ($file, $lineages, $lineage_count, $database);

    my $args = shift;

    ($file, $database) = get_args(@$args);

    $lineages = parse_list_of_lineages($file);

    $lineage_count = store_scientific_names(@$lineages, $database);

}

main(@ARGV);
