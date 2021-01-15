#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# creating an enaftp report on ac-ac* status
#
# Gemma Hoad  16-APR-10

use DBI;
use strict;
use ENAdb;

my $FTP_ROOT = '/ebi/ftp/private/enaftp';

sub get_args(\@) {

    my $args = shift;

    my $login;
    my $project_abbrev = "all";

    foreach my $arg (@$args) {
	if ($arg =~ /\/\@[a-zA-Z0-9]+/) {
	    $login = $arg;
	} else {
	    $project_abbrev = $arg;
	}
    }
    
    return($login, $project_abbrev);
}

sub get_project_names_and_dirs($$) {

    my $dbh = shift;
    my $project_abbrev = shift;
    my $sql;

    if ($project_abbrev eq "all") {
	# i.e. no project_abbrev has been entered
	$sql = "select project_abbrev, dir_name from cv_project_list where active='Y'";
    }
    else {
	$sql = "select project_abbrev, dir_name from cv_project_list where project_abbrev='$project_abbrev'";
    }

    my $sth = $dbh->prepare($sql);
    $sth->execute();
    
    my %project_pathwords;
    while (my ($project_name, $dir_name) = $sth->fetchrow_array()) {
	$project_pathwords{$project_name} = $dir_name;
    }

    if (! keys(%project_pathwords)) {
	# this may happen if project_name entered is dud
	die "ERROR: Project name $project_abbrev is not recognised\n";
    }

    return(\%project_pathwords);
}

sub main() {

    my ($database, $project_abbrev) = get_args(@ARGV);

    if (!(defined($database))) {
	$database = '/@enapro';
    }
    my %attr   = ( PrintError => 0,
		   RaiseError => 0,
		   AutoCommit => 0 );
    
    my $dbh = ENAdb::dbconnect($database,%attr)
	|| die "Can't connect to database: $DBI::errstr";
    
    my $project_pathword_hash = get_project_names_and_dirs($dbh, $project_abbrev);

    my $sql = "select d.primaryacc# || '.' || b.version Accession, 
		 substr(g.gp_accid,length(p.project_code) + 1 ) Internal_ID, 
		 decode( d.dataclass, 'HTG', 'Unfinished', 'Finished') Completeness, 
		 to_char(nvl(d.ffdate,d.ext_date), 'DD-MON-YYYY') FFdate, 
		 s.status EMBL_Status
		     from dbentry d, bioseq b, gp_entry_info g, cv_status s, cv_project_list p
		     where p.project_abbrev = ?
		     and d.project# = p.project_code
		     and g.seqid = d.bioseqid
		     and d.bioseqid = b.seqid
		     and d.statusid = s.statusid
		     order by s.status, d.primaryacc#";

    my $sth = $dbh->prepare($sql);

    foreach my $project_name (keys %$project_pathword_hash) {

	my $report_root     = "$FTP_ROOT/$$project_pathword_hash{$project_name}/ena_reports";
	# should protect against concurrent runs, but use of a unique tempfile name will help
	my $new_report      = sprintf "%s/.entries.txt.tmp_%s.", $report_root , time();
	my $existing_report = "$report_root/entries.txt";

	open(my $REPORT, ">$new_report");
	
	print $REPORT "#                          Automated Sequence Loading Archive\n".
                  "#AC            AC *                                           State          First Public  Entry Status\n".
                  "#------------  ---------------------------------------------  -------------  ------------  ------------\n";

	$sth->execute($project_name);

	while (my @row = $sth->fetchrow_array()) {

	    foreach my $value (@row) {
		if (!defined $value) {
		    $value = "";
		}
	    }

	    printf($REPORT  "%-14s %-46s %-14s %-13s %s\n", $row[0],
                                                    $row[1],
                                                    $row[2],
                                                    $row[3],
                                                    $row[4]);
	}

	close($REPORT);
	rename($new_report, $existing_report); # overwrite old report now the new one has completed
    }

    $dbh->disconnect();
}

main();
