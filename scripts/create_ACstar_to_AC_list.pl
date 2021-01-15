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
use DBI;
use dbi_utils;



my ($query, $sql, @results, $file_ac_stars, $ac_star, $db_ac_star, $db_ac, $dbh);
my (@grep_res);

$dbh = dbi_ora_connect('/@enapro');

$sql = "select gp_accid, primaryacc# from dbentry, gp_entry_info where bioseqid = seqid and gp_accid like ?";
$query = $dbh->prepare($sql);


$file_ac_stars = "grep "."'^AC \*'".' *.embl';

@grep_res = `$file_ac_stars`;


open(SAVE, ">genoscope_acstar_ac_mapping.txt") || die "Cannot open genoscope_acstar_ac_mapping.txt:$!\n";

foreach $ac_star (@grep_res) {

    $ac_star =~ s/[^\.]+\.embl:AC \* (\S+)\s*/$1/;

    if ($ac_star =~ /^_/) {

	$query->bind_param(1, '%'.$ac_star.'%');
	$query->execute;

	while (($db_ac_star, $db_ac) = $query->fetchrow_array()) {
	    print SAVE "$db_ac_star\t$db_ac\n";
	}
    }
}
close(SAVE);

dbi_logoff($dbh);



