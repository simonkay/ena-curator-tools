#!/ebi/production/seqdb/embl/tools/bin/perl

use strict;
use DBI;
use dbi_utils;
use SeqDBUtils2 qw(timeDayDate);

my ($collab, $db);
my $test = 0;


foreach my $arg (@ARGV) {

    if ($arg =~ /(ddbj|ncbi)/i) {
	$collab = uc($1);
    }
    elsif ($arg =~ /(enapro|devt)/i) {
	$db = $arg;
    }
    elsif ($arg =~ /^\-test$/) {
	$test = 1;
    }
    else {
	die "unrecognised argument: |$arg|\n";
    }
}

if ((!defined $collab) || (!defined $db)) {
    die "Please enter (ddbj|ncbi) and database as arguments\n";
}

my $livelist_dir = "/ebi/production/seqdb/embl/updates/livelist/".lc(${collab});

if ($test) {
    $livelist_dir = "/homes/gemmah/tmp/tmp4/".lc(${collab});
    print "working in test dir: $livelist_dir\n";
}

my $unregisted_projects = "livelist_${collab}_missing_project_ids_".SeqDBUtils2::timeDayDate('d-m-yyyy');

open(IN, "<$livelist_dir/current") || die "Cannot open $livelist_dir/current\n";

my %uniq_prj_ids;

while (my $line = <IN>) {
    
    if ($line =~ /([^\|]+\|){3}(.+)$/) {

	my @prj_ids = split(",", $2);

	foreach my $prj_id (@prj_ids) {
	    $uniq_prj_ids{$prj_id} = 1;
	}
    }
}

close(IN);
my $k = 0;
#foreach my $var (keys %uniq_prj_ids) {
#    $k++;
#    print "$k. $var\n";
#}

my $dbh;
eval {
    $dbh = DBI->connect('dbi:Oracle:', $db, '',  {
	RaiseError => 1, 
	PrintError => 0,
	AutoCommit => 0
	});
};

if ($@) {	
    die "ERROR: Cannot to connect to $db at this time.\n";
}

my $sql = "select count(projectid) from project where projectid=?";
my $sth = $dbh->prepare($sql);

open(OUT, ">$livelist_dir/$unregisted_projects");

my $i = 0;
my $j = 0;
my %unknown_project_ids;


foreach my $prj_id (keys %uniq_prj_ids) {

    $sth->execute($prj_id);

    my $prj_id_count = $sth->fetchrow_array();
    if ($prj_id_count == 0) {
	print OUT "$prj_id\n";
	$unknown_project_ids{$prj_id} = 1;
	$j++;
    }
    $i++
}
$sth->finish();

close(OUT);
system("chmod 644 $livelist_dir/$unregisted_projects");

print "Checked $i project ids ($j are unknown)\n";

$dbh->disconnect();

############ get missing project data and load into enapro

# sort unknown project ids into 

#my $latest_prj_data_file = `ls -lt /ebi/production/seqdb/embl/data/ncbi_projects/ftp-private.ncbi.nih.gov/GenProjDB/dumps/*.v4.dump.xml | head -1`;

#open(PRJ_INFO, "<$latest_prj_data_file");

#while (my $line = <PRJ_INFO>) {

#    if ($line =~ /<gp:ProjectID>(\d+)</) {
#	$file_project_id = $1;
#    }
#}

#close(PRJ_INFO);
