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
use SeqDBUtils2;

# global variables
my $dbh;
my $test = 0;
my $DATADIR = "/ebi/production/seqdb/embl/data/gpscan";

################################################################################
sub remove_lock_file($) {

    my $prj_abbrev = shift;

    if (!$test) {
	unlink("$DATADIR/$prj_abbrev/LOCK");
    }
    else {
	print "\nDeleting $DATADIR/$prj_abbrev/LOCK\n";
    }
}

################################################################################

sub get_and_load_new_data($$) {

    my ($query, $run_sql, $bad_email, $input, @email_addresses, $email, $sql);

    my $prj_code = shift;
    my $column_name = shift;

    $input = <STDIN>;
    $input =~ s/^\s*//;
    $input =~ s/\s*$//;
    $input =~ s/\s\s+/ /g;

    $run_sql = 0;
    $bad_email = 0;

    if ($input =~ /^\s*$/) {
	print "No updates made.\n";
    }
    else {

	if ($column_name eq "project_desc") {

	    if (length($input) > 50) {
		print "The description entered contains too many characters.\n";
	    }
	    else {
		$run_sql = 1;
	    }
	}
	elsif ($column_name eq "project_organism_prefix") {

	    if (length($input) > 2) {
		print "The organism prefix entered contains too many characters.\n";
	    }
	    else {
		$run_sql = 1;
	    }
	}
	elsif ($column_name eq "project_email") {

	    @email_addresses = split(/, ?/, $input);

	    foreach $email (@email_addresses) {
		if ($input !~ /[^@]+@[^@]+/) {
		    print "The email address field is badly formatted (format: ben\@foo.com, bill\@foo.co.uk).\n";
		    $bad_email = 1;
		    last;
		}
	    }

	    if (!$bad_email) {
		$run_sql = 1;
	    }
	}

	if ($run_sql) {

	    $sql = "UPDATE cv_project_list  
                       SET $column_name = ?
                     WHERE project_code = ?";

	    $query = $dbh->prepare($sql);
	    $query->bind_param(1, $input);
	    $query->bind_param(2, $prj_code);
	    $query->execute();

	    # Commit (extracted from dbi_utils module)
	    if ( defined($DBI::errstr) && $DBI::errstr ne '' ) {
		print STDERR "Changes rolled back because \$DBI::errstr was not empty: $DBI::errstr\n";
		$dbh->rollback() || print STDERR ("Rollback failed\n");
		die();
	    }
	    $dbh->commit() || die("Could not commit changes\n");

	    print "\nUpdated and committed.\n";
	}
    }
}

################################################################################

sub request_and_amend_any_project_updates($$$$$$) {

    my ($item_number_to_update, $highest_item_num);

    my $prj_code = shift;
    my $prj_desc = shift; 
    my $prj_abbrev = shift; 
    my $prj_org_prefix = shift; 
    my $prj_email = shift;
    my $lock_file_present = shift;

    $highest_item_num = 4;

    if ($lock_file_present) {
	$highest_item_num = 5;
    }

    $item_number_to_update = "";

    while ($item_number_to_update !~ /^q/i) {

	print "\nAlter (1-5) (q to quit)? ";
	$item_number_to_update = <STDIN>;

	if ($item_number_to_update =~ /^q/i) {
	    exit;
	}

	$item_number_to_update =~ s/\s+$//;


	if (($item_number_to_update < 1) || ($item_number_to_update > $highest_item_num)) {

	    print "\nNumber out of range (expecting 1-$highest_item_num)\n";
	    next;
	}
	elsif ($item_number_to_update == 1) {
            # project_abbrev

	    print "\nAlter alteration of an abbreviation is currently not permitted since changes must be made in files, directories and the database!\n";
	}
	elsif ($item_number_to_update == 2) {
            # project_desc

	    print "\nPlease enter new description (max 50 chars):\n";
	    get_and_load_new_data($prj_code, "project_desc");
	}
	elsif ($item_number_to_update == 4) {
            # project_email

	    print "\nPlease enter new email address list (comma delimited):\n";
	    get_and_load_new_data($prj_code, "project_email");
	}
	elsif ($item_number_to_update == 5) {
            # project_lockfile
	    remove_lock_file($prj_abbrev);
	}
    }
}

################################################################################

sub get_last_loaded_date($) {

    my ($newest_file_date, $newest_file);

    my $prj_data_path = shift;

    $newest_file = `ls -ltr $prj_data_path | tail -1`;

    if ($newest_file =~ /[rwsx-].+\s+([JFMASOND][a-y]{2}.+(\d{2}:\d{2}|\d{4}))\s+\S+\n?/) {
	$newest_file_date = $1;
	$newest_file_date =~ s/\s\s+/ /g;
    }

    return($newest_file_date);
}

################################################################################

sub get_lock_warning($) {
    my $prj_abbrev = shift;
    my $lock_warning;
    my $lock_file = "/ebi/production/seqdb/embl/data/gpscan/" . $prj_abbrev . "/LOCK";
    
    if (-e $lock_file) {
	return "5) LOCKED (" 
	    . SeqDBUtils2::timeDayDate("timedaydate", localtime +( stat($lock_file))[9])
	    . ")\n";
    }
    return;
}

################################################################################

sub display_project_details($$$$$) {
    my $prj_code = shift;
    my $prj_desc = shift; 
    my $prj_abbrev = shift;
    my $prj_org_prefix = shift; 
    my $prj_email = shift;

    if (!defined($prj_email)) {
	$prj_email = "";
    }

    print "Project $prj_code\n"
	. "1) Abbrev: $prj_abbrev\n"
	. "2) Description: $prj_desc\n"
	. "3) Organism prefix: $prj_org_prefix\n"
	. "4) Email: $prj_email\n";

    my $lock_warning = get_lock_warning($prj_abbrev);
    if (defined($lock_warning)) {
	print $lock_warning;
    }

    my $prj_data_path = "$DATADIR/$prj_abbrev";
    if (-e $prj_data_path) {
	print "Datadir: $prj_data_path/\n"
	    . "Last loaded: "
	    . get_last_loaded_date($prj_data_path)
	    . "\n";
    }
    else {
	print "There is no associated project directory found at $prj_data_path\n";
    }
    
    return($lock_warning);
}

################################################################################

sub ask_which_project_to_view(\@\@\@) {

    my ($i, $project_index, $highest_index);

    my $prj_code = shift;
    my $prj_abbrev = shift;
    my $prj_desc = shift;

    print "More than one project has been found:\n";

    for ($i=0; $i<@$prj_code; $i++) {
	print $i+1 . ") Project: $$prj_code[$i]; $$prj_abbrev[$i]; $$prj_desc[$i]\n";
    }

    $highest_index = scalar(@$prj_code);
    $project_index = 0;

    # ask user which project to view (within specified range)
    while (($project_index < 1) || ($project_index > $highest_index)) {

	print "\nChoose project number from list: 1-$highest_index (q to quit): ";

	$project_index = <STDIN>;
	$project_index =~ s/\s*$//;
	if ($project_index =~ /^[qQ]?$/) {
	    exit;
	}
	if (($project_index < 1) || ($project_index > $highest_index)) {
	    print "Number is out of range.\n";
	}
    }

    $project_index = $project_index - 1;

    return($project_index);
}

################################################################################

sub build_sql_query($$$$$$$) {

    my ($sql, @bind_params, $uc_project_desc, $add_end_bracket);

    my $project_id = shift;
    my $project_desc = shift;
    my $project_abbrev = shift;
    my $project_org_prefix = shift;
    my $project_email = shift;
    my $embl_acc = shift;
    my $submitter_acc = shift;

    $add_end_bracket = 0;

    if ($submitter_acc ne "") {
	$sql = "select p.project_code,
                      p.project_desc, 
                      p.project_abbrev, 
	               p.project_organism_prefix, 
                      p.email_address
	          from cv_project_list p,
                      dbentry d,
                      gp_entry_info e
                where p.project_code = d.project#
                  and d.bioseqid = e.seqid 
                  and (gp_accid = ? 
                  or ";

	$add_end_bracket = 1;

	push(@bind_params, $submitter_acc);
    }
    elsif ($embl_acc ne "") {
	$sql = "select p.project_code,
                       p.project_desc, 
                       p.project_abbrev, 
	               p.project_organism_prefix, 
                       p.email_address
	          from cv_project_list p,
                       dbentry d
                 where p.project_code = d.project# 
                   and (d.primaryacc# = ? 
                   or ";
	$add_end_bracket = 1;

	push(@bind_params, $embl_acc);
    }
    else {
	$sql = "select p.project_code,
                       p.project_desc, 
                       p.project_abbrev, 
	               p.project_organism_prefix, 
                       p.email_address 
	          from cv_project_list p
                where ";
    }


    if ($project_id) {
	$sql .= "p.project_code = ? or ";
	push(@bind_params, $project_id);
    }

    if ($project_desc ne "") {
	$sql .= "upper(p.project_desc) like ? or ";
	$project_desc = uc($project_desc);
	push(@bind_params, '%'.$project_desc.'%');
    }

    if ($project_abbrev ne "") {
	$sql .= "p.project_abbrev = ? or ";
	push(@bind_params, $project_abbrev);
    }

    if ($project_org_prefix ne "") {
	$sql .= "p.project_organism_prefix = ? or ";
	push(@bind_params, $project_org_prefix);
    }

    if ($project_email ne "") {
	$sql .= "upper(p.email_address) like upper(?)";
	push(@bind_params, '%'.$project_email.'%');
    }


    if ($sql =~ /or $/) {
	$sql =~ s/or $//;
    }
    if ($add_end_bracket) {
	$sql .= ")";
    }

#    print "sql = $sql\n";
#    print "bind_parameters = ".join("\n", @bind_params)."\n\n";

    return($sql, \@bind_params);
}

################################################################################

sub find_projects_matching_args($$$$$$$) {

    my ($query, $sql, $bind_params, $i, @prj_code, @prj_desc, @prj_abbrev);
    my (@prj_org_prefix, @prj_email, $prj_index, @results);
    my ($bind_param_num);

    my $project_id = shift;
    my $project_desc = shift;
    my $project_abbrev = shift;
    my $project_org_prefix = shift;
    my $project_email = shift;
    my $embl_acc = shift;
    my $submitter_acc = shift;

    ($sql, $bind_params) = build_sql_query($project_id, $project_desc, $project_abbrev, $project_org_prefix, $project_email, $embl_acc, $submitter_acc);

    $query = $dbh->prepare($sql);

    for ($i=1; $i<(@$bind_params+1); $i++) {
	$query->bind_param($i, $$bind_params[($i-1)]);
    }

    $query->execute;

    while (@results = $query->fetchrow_array()) {

	push(@prj_code, $results[0]);
	push(@prj_desc, $results[1]);
	push(@prj_abbrev, $results[2]);
	push(@prj_org_prefix, $results[3]);
	push(@prj_email, $results[4]);
    }

    if (!@prj_code) {
	die "No projects could be found which matched your input parameters.\n";
    }

    # if > 1 project matches the supplied parameters
    if (@prj_code > 1) {
	$prj_index = ask_which_project_to_view(@prj_code, @prj_abbrev, @prj_desc);
    }
    else {
	$prj_index = 0;
    }

    return($prj_code[$prj_index], $prj_desc[$prj_index], $prj_abbrev[$prj_index], $prj_org_prefix[$prj_index], $prj_email[$prj_index]);

}

################################################################################

sub get_args(\@) {

    my ($arg, $usage, $project_id, $project_desc, $project_email, $embl_acc);
    my ($submitter_acc, $database, $prj_desc_or_num, $project_abbrev);
    my ($project_org_prefix, $add_project);

    my $args = shift;

    $usage =
	"\n USAGE: $0 [database] [-p=<projectnumber>] [-e=<email>] [-ab=<project_abbrev>] [-ac=<embl_accession>] [-sac=<submitter_accession>] [-h(elp)]\n\n"
	. " PURPOSE: From the commandline options, the program searches for the project.\n"
	. "         If a single project is found, it's details will be displayed.\n"
	. "         If multiple projects are found, you will have to choose from a list of projects.\n"
	. "         \n"
	. " database              /\@enapro or /\@enadev  "
	. " -p=<projectnumber>    Project number/id\n"
	. " -e=<email>            Email address of project submitter\n"
	. " -ab=<project_abbrev>  Project abbreviation e.g. sangermdcr\n"
	. " -ac=<embl_accession>  Embl accession number\n"
	. " -sac=<submitteracc>   Submitter's accession (remote accession)\n"
	. " -test                 test mode: no lock file deletion\n"
	. " -h(elp)               This help message\n"
	. " NB Please use genome_project_add.pl to add a project\n"
	. "\n";

    $add_project = 0;
    $project_id = 0;
    $project_desc = "";
    $project_abbrev = "";
    $project_org_prefix = "";
    $project_email = "";
    $embl_acc = "";
    $submitter_acc = "";
    $database = "";

    if ((defined($$args[0])) && (($$args[0]  =~ /^-h(elp)?/i ) || ( $$args[0] =~ /^-u(sage)/i ))) {
	die $usage;
    }
    elsif (@$args < 2) {

	foreach $arg (@$args) {
	    if ( $arg =~ /^(\/@)?(enapro|enadev)/i ) {

		if (defined($1)) {
		    $database = $1.$2;
		}
		else {
		    $database = '/@'.$2;
		}
	    }
	    elsif ( $arg =~ /^-add/i ) {
		$add_project = 1;
	    }
	}

	if ($database eq "") {
	    # in the absence of arguments request database...
	    print 'Please enter a database (/@enapro or /@enadev):'."\n";
	    $database = <STDIN>;
	    $database =~ s/\s*$//;

	    if ($database =~ /^(\/@)?(enapro|enadev)/i) {
		if (defined($1)) {
		    $database = $1.$2;
		}
		else {
		    $database = '/@'.$2;
		}
	    }
	    else {
		die "Unrecognised database.\n";
	    }
	}

	if (! $add_project) {
	    # ...and project name or id
	    print "Please enter a project description or number:\n";
	    $prj_desc_or_num = <STDIN>;
	    $prj_desc_or_num =~ s/\s*$//;
	    
	    if ($prj_desc_or_num =~ /^\d+$/) {
		$project_id = $prj_desc_or_num;
	    }
	    else {
		$project_desc = $prj_desc_or_num;
		$project_abbrev = $prj_desc_or_num;
	    }
	}
    }
    else {

	foreach $arg (@$args) {
	    if (( $arg =~ /^-h(elp)?/i ) || ( $arg =~ /^-u(sage)/i )) {
		die $usage;
	    }
	    elsif ( $arg =~ /^-add/i ) {
		$add_project =1;
	    }
	    elsif ( $arg =~ /^(\/@)?(enapro|enadev)/i ) {

		if (defined($1)) {
		    $database = $1.$2;
		}
		else {
		    $database = '/@'.$2;
		}
	    }
	    elsif ( $arg =~ /^-p=(.+)/i ) {
		$project_id = $1;
		
		if ($project_id !~ /^\d+$/) {
		    die "Project ID \"$project_id\" provided in unrecognised format. A number is expected.\n"
			. $usage;
		}
	    }
	    elsif ( $arg =~ /^-ab=(.+)/i ) {
		$project_abbrev = $1;
	    }
	    elsif ( $arg =~ /^-e=(.+)/i ) {
		$project_email = $1;
	    }
	    elsif ( $arg =~ /^-ac=(.+)/i ) {
		$embl_acc = $1;
		
		if ($embl_acc !~ /^[A-Z]{2}\d{6}$/) {
		    die "Embl accession \"$embl_acc\" provided in unrecognised format.\n"
		    . $usage;
		}
	    }
	    elsif ( $arg =~ /^-sac=(.+)/i ) {
		$submitter_acc = $1;
		
		if ($submitter_acc !~ /^_[A-Z0-9]{8}$/) {
		    die "Submitter accession \"$submitter_acc\" provided in unrecognised format.\n"
			. $usage;
		}
	    }
	    elsif ( $arg =~ /^-test/i ) {
                # test mode
		$test = 1;
	    }
	    else {
		die "I do not understand arg $arg\n" 
		    . $usage;
	    }
	}
    }

    if (! defined($database)) {
	die "You must enter a valid database: /\@enapro or /\@enadev\n";
    }

    return($database, $project_id, $project_desc, $project_abbrev, $project_org_prefix, $project_email, $embl_acc, $submitter_acc, $add_project);
}

################################################################################
sub main(\@) {

    my ($project_id, $project_desc, $project_email, $embl_acc, $submitter_acc);
    my ($prj_code, $prj_desc, $prj_abbrev, $prj_org_prefix, $prj_email);
    my ($database, $lock_file_present, $project_abbrev, $project_org_prefix);
    my ($add_project);

    my $args = shift;

    ($database, $project_id, $project_desc, $project_abbrev, $project_org_prefix, $project_email, $embl_acc, $submitter_acc, $add_project) = get_args(@$args);

    $database =~ s/^\/?\@?//;
    $dbh = DBI->connect( "dbi:Oracle:$database",'', '', {RaiseError => 1, PrintError => 0, AutoCommit => 0} );
    
    ($prj_code, $prj_desc, $prj_abbrev, $prj_org_prefix, $prj_email) = find_projects_matching_args($project_id, $project_desc, $project_abbrev, $project_org_prefix, $project_email, $embl_acc, $submitter_acc);
    
    $lock_file_present = display_project_details($prj_code, $prj_desc, $prj_abbrev, $prj_org_prefix, $prj_email);
    
    request_and_amend_any_project_updates($prj_code, $prj_desc, $prj_abbrev, $prj_org_prefix, $prj_email, $lock_file_present);
    $dbh->disconnect();
}

################################################################################
# Run the script

main(@ARGV);
