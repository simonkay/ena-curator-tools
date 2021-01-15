#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# 
#
#  (C) EBI 2007
#
#===============================================================================

use strict;
use DBI;

# global variables
my $dbh;
my $DIRS_LOADING = "/ebi/production/seqdb/embl/data/gpscan";
my $DIRS_ENAFTP  = "/ebi/ftp/private/enaftp";
my $DIRS_DIS  = "/ebi/production/seqdb/embl/data/gpscan/maillist";

my $testing = 0; # non testing only vailable for datalib
################################################################################

sub my_die($) {
    my $explanation = shift;
    $dbh->rollback();
    die($explanation .
	"undoing database changes\n\n");
}

################################################################################
sub display_confirmation($\%) {
    my $database = shift;
    my $rh_newProject = shift;

    print "Summary: Your project has been successfully loaded into $database "
	. "with the following details:\n\n";

    foreach my $key (sort keys %{$rh_newProject}) {
	printf "%-20s : %-60s\n", $key, ${$rh_newProject}{$key};
    }
    print "\n\nDear Colleague\n\n"
	. "For the account (".${$rh_newProject}{'project_abbrev'}.")\n"
        . "   Please login into your Webin space at ftp webin.ebi.ac.uk with your Webin-xxx account id\n"
        . "\n"
        . "Simply leave uncompressed embl-formatted files in the 'clone' subdirectory (either singles or concatenated)\n"
        . "and they will be picked up and processed normally within 1 hour.\n"
	. "\n"
	. "Loading reports will be sent to:\n"
	. join("\n",${$rh_newProject}{'email_address'})."\n"
        . "\n"
        . "We will be introducing an improved reporting system that should leave copies of\n"
        . "the latest project information in a directory 'reports' in the 'clone' directory, we will notify you when this is added.\n"
        . " \n"
        . "IMPORTANT: When replying to this message please DO NOT alter the subject\n"
        . "line in any way. If you change the subject line processing of your\n"
        . "request/data will be delayed.\n"
        . "\n"

        . "Yours sincerely,\n\n";
}

################################################################################

sub randomPathword() {
 my $pathword ="";
 my $_rand;
 my $pathword_length = 20;

 my @chars = split(" ",
 "a b c d e f g h i j k m n o
  p q r s t u v w x y z A B C D
  E F G H I J K L M N P Q R S
  T U V W X Y Z 2 3 4 5 6 7
  8 9 ");

 srand;

 while (length($pathword) < $pathword_length) {
     $_rand = int(rand scalar( @chars ));
     $pathword .= $chars[$_rand];
 }
 return $pathword;
}

################################################################################

sub getUniquePathword() {
    my $pathword = "";
    my $sth_pathwordCheck = $dbh->prepare("SELECT 1 from cv_project_list where DIR_NAME = ?");
    while ($pathword eq "") {
	$pathword = randomPathword();
	$sth_pathwordCheck->execute($pathword);
	my ($exists) = $sth_pathwordCheck->fetchrow_array;
	if ($exists) {
	    $pathword = "";
	}
    }    
    $sth_pathwordCheck->finish();
    return $pathword;
}
    
################################################################################

sub make_loading_dirs(\%) {
    my $rh_newProject = shift;
    my $loadingDirPath = "$DIRS_LOADING/".${$rh_newProject}{'project_abbrev'};
    (-e $loadingDirPath) && my_die("$loadingDirPath already exists\n");
    if ($testing) {
	print STDERR "test mode: not creating directories at $loadingDirPath\n";
    } else {
	mkdir($loadingDirPath, 0775) || my_die("Cannot create $loadingDirPath: $!\n");
	mkdir($loadingDirPath."/old", 0775) || my_die("Cannot create $loadingDirPath/old: $!\n");
	mkdir($loadingDirPath."/err", 0775) || my_die("Cannot create $loadingDirPath/err: $!\n");
	print STDERR "Created directories in $loadingDirPath\n";
    }

    ${$rh_newProject}{'loading dir'} = $loadingDirPath;
    return;
}

################################################################################

sub make_ftp_dirs(\%) {
    my $rh_newProject = shift;
    my $ftpDirPath = "$DIRS_ENAFTP/".${$rh_newProject}{'dir_name'};
    my $ftpDirDropPath = $ftpDirPath . "/to_ena";
    my $ftpDirDropPathSym = ${$rh_newProject}{'loading dir'} . "/ftp";

    if ($testing) {
	print STDERR "test mode: not creating directories at $ftpDirPath\n" .
	    " nor symlink at $ftpDirDropPathSym\n";
    } else {
	(-e $ftpDirPath) && my_die("$ftpDirPath already exists\n");
	mkdir($ftpDirPath, 0755) || my_die("Cannot create $ftpDirPath: $!\n");
	mkdir($ftpDirDropPath, 0774) || my_die("Cannot create $ftpDirDropPath: $!\n");
	chmod 0744, $ftpDirDropPath; # oddly, the above mkdir doesn't seem to work - maybe a sticky bit complication
	print STDERR "Created directories in $ftpDirPath\n";
	symlink($ftpDirDropPath, $ftpDirDropPathSym) ||  my_die("Cannot symlink $ftpDirDropPath as $ftpDirDropPathSym: $!\n");
    }

    ${$rh_newProject}{'ftp dir'} = $ftpDirPath;
    return;
}

################################################################################

sub make_dis_file(\%) {
    my $rh_newProject = shift;
    my $disFileName = "$DIRS_DIS/".${$rh_newProject}{'project_abbrev'}.".dis";
    (-e $disFileName) && my_die("$disFileName already exists\n");

    open (my $fh_dis, ">$disFileName")  
	|| my_die("Cannot create $disFileName: $!\n");
    print STDERR "$disFileName: created\n";
    foreach my $email (split(/,\s*/,${$rh_newProject}{'email_address'})) {
	print $fh_dis "$email\n";
    }
    close($fh_dis)  
	|| my_die("Cannot close $disFileName: $!\n");
    chmod(0660,$disFileName)  
	|| my_die("Cannot chmod 0660 $disFileName: $!\n");

     ${$rh_newProject}{'dis file'} = $disFileName;

    if ($testing) {
	print STDERR "test mode: removing dis file after creation\n";
	unlink($disFileName) ||  my_die("Cannot delete $disFileName: $!\n");
    }
    # skip step: Make a lastUpdate file - this one is just '0000000000' and is a used at the start (NB this doesn't actually appear to do anything)
    return;
}
   
################################################################################

sub load_new_project(\%) {
    my $rh_newProject = shift;

    ${$rh_newProject}{'dir_name'} = getUniquePathword();

    my $sth_nextCode = $dbh->prepare("select max(project_code) + 1 from cv_project_list");

    $sth_nextCode->execute;
    (${$rh_newProject}{'project_code'}) = $sth_nextCode->fetchrow_array();
    $sth_nextCode->finish();

    my $sql = "insert into cv_project_list  
                  (project_code, 
                   project_abbrev, 
                   project_desc,
                   project_organism_prefix,
                   email_address,
                   dir_name)
           values (?, ?, ?, ?, ?,?)";

    my $query = $dbh->prepare($sql);
    $query->bind_param(1, ${$rh_newProject}{'project_code'});
    $query->bind_param(2, ${$rh_newProject}{'project_abbrev'});
    $query->bind_param(3, ${$rh_newProject}{'project_desc'});
    $query->bind_param(4, ${$rh_newProject}{'project_org_prefix'});
    $query->bind_param(5, ${$rh_newProject}{'email_address'});
    $query->bind_param(6, ${$rh_newProject}{'dir_name'});
    $query->execute();
    $query->finish();
    print "\n...saving new project\n\n";
}

################################################################################

sub ask_for_and_check_email() {

    my ($email, @email_addresses, $em1, $em2, @email_addresses2, @new_email_list);

    $email = "";

    print "\nEmail contacts?\n"
	. "(includes notifable EBI staff; e.g. ben\@sanger.ac.uk, "
	. "faruque\@ebi.ac.uk); comma-delimited; type q to quit)\n";

    while ($email eq "") {
	$email = <STDIN>;
	$email =~ s/,?\s*$//;

	if ($email =~ /^q(uit)?$/) {
	    exit;
	}
	elsif ($email eq "") {
	    print "\nPlease enter at least one email address. Try again:\n";
	    $email = "";
	}
	elsif ($email !~ /[^@]+\@[^@]+/) {
	    print "\nEmail format unrecognised. Try again:\n";
	    $email = "";
	}
	else {
            # check email addresses added are all complete
	    @email_addresses = split(/,\s*/, $email);

	    @new_email_list = ();

	    foreach $em1 (@email_addresses) {

		if ($em1 =~ /\s+/) {
                    # in case commas are missing inbetween email addresses...
		    @email_addresses2 = split(/\s+/, $em1);

		    foreach $em2 (@email_addresses2) {

			push(@new_email_list, $em2);

			if ($em2 !~ /[^@]+\@[^@]+/) {
			    print "\n$em2 is not a valid email address format. Try again.\n";
			    $email = "";
			    last;
			}
		    }
		}
		else {

		    push(@new_email_list, $em1);

		    if ($em1 !~ /[^@]+\@[^@]+/) {
			print "\n$em1 is not a valid email address format. Try again.\n";
			$email = "";
			last;
		    }
		}
	    }
	}
    }

    if (@new_email_list) {
        # create better-formatted email string
	$email = join(", ", @new_email_list);
    }

    return($email);
}

################################################################################

sub check_if_field_is_unique($$) {

    my ($sql, $query, @results, @code, @abbrev, @desc);

    my $field = shift;
    my $input = shift;

    if ($field eq 'project_abbrev') {

	$sql = "select project_code, 
                       project_desc 
                  from cv_project_list 
                 where project_abbrev = ?";

        $query = $dbh->prepare($sql);
        $query->bind_param(1, $input);
        $query->execute;

        @results = $query->fetchrow_array();

	if (@results) {
	    print "This project already exists (Project $results[0]; $results[1]). Please choose another abbreviation (type q to quit):\n";

	    $input = ""; #signal to re-request input
	}
    }
    elsif ($field eq 'project_desc') {

	$sql = "select project_code, 
                       project_abbrev, 
                       project_desc 
                  from cv_project_list 
                 where project_desc like ?";

	$query = $dbh->prepare($sql);
	$query->bind_param(1, '%'.$input.'%');
	$query->execute;

	while (@results = $query->fetchrow_array()) {
	    push(@code,   $results[0]);
	    push(@abbrev, $results[1]);
	    push(@desc,   $results[2]);
	}

	if (@code) {

	    print "The description entered is very similar to the following existing projects:\n";

	    for (my $i=0; $i<@code; $i++) {
		print "Project $code[$i]; $abbrev[$i]; $desc[$i]\n";
	    }

	    my $change_desc = "";
	    while ($change_desc !~ /^[YNyn]/) {
		print "Change description (y/n)?\n";
		$change_desc = <STDIN>;

		if ($change_desc =~ /^y/i) {
		    $input = ""; #signal to re-request input
		}
	    }
	}
    }
    return($input);
}

################################################################################

sub ask_for_and_check_param($) {

    my ($input, $field_max_length, $field_name);

    my $field = shift;

    $input = "";

    if ($field eq 'project_abbrev') {
	print "Project abbreviation?\n"
	    . "(25 characters max; e.g. sangerhs; no spaces recommended; "
	    . "type q to quit)\n";

	$field_name = "abbreviation";
	$field_max_length = 25;
    }
    elsif ($field eq 'project_desc') {
	print "\nDescription?\n"
	    . "(50 characters max; e.g. C. elegans nematode project; "
	    . "type q to quit)\n";

	$field_name = "description";
	$field_max_length = 50;
    }
    elsif ($field eq 'project_org_prefix') {
	print "\nOrganism prefix?\n"
	    . "(2 characters max; e.g. CE; "
	    . "type q to quit)\n";

	$field_name = "organism prefix";
	$field_max_length = 2;
    }
    elsif ($field eq 'email_address') {
	$input = ask_for_and_check_email();
    }

    while ($input eq "") {

	$input = <STDIN>;
	$input =~ s/\s*$//;

	if ($input =~ /^q(uit)?$/i) {
	    exit;
	}
	elsif ($input eq "") {
	    $input = "";
	}
	elsif (length($input) > $field_max_length) {
	    print "The $field_name entered exceeds the maximum length. Please try again (type q to quit):\n";
	    $input = "";
	}
	elsif (($field eq 'project_abbrev') || ($field eq 'project_desc')) {
	    $input = check_if_field_is_unique($field, $input);
	}
    }

    return($input);
}

################################################################################

sub ask_for_project_details(\%) {
    my $rh_newProject = shift;

    my ($prj_abbrev, $prj_desc, $prj_org_prefix, $prj_email);

    print "Add New Project\n"
	. "---------------\n\n"
	. "Please enter all of the following:\n\n";

    my @fields = ('project_abbrev','project_desc','project_org_prefix','email_address');
    foreach my $field (@fields) {
	${$rh_newProject}{$field} = ask_for_and_check_param($field);
    }
}

################################################################################

sub get_args(\@) {

    my ($arg, $usage, $database); 

    my $args = shift;

    $usage =
    "\n USAGE: $0 [database] [-h(elp)]\n\n"
  . " PURPOSE: This program allows the user to add a genome project.  This script is called via the genome_project_admin.pl\n"
  . " database              /\@enapro or /\@enadev  "
  . " -h(elp)               This help message\n"
  . "\n";

    foreach $arg (@$args) {
	if ( $arg =~ /^(\/@)?(enapro|enadev)/i ) {
	    
	    if (defined($1)) {
		$database = $1.$2;
	    }
	    else {
		$database = '/@'.$2;
	    }
	}  
    }

    if (! defined($database)) {
	die "You must enter a valid database: /\@enapro or /\@enadev\n";
    }

    return($database);
}

################################################################################
sub main(\@) {

    my ($prj_desc, $prj_abbrev, $prj_org_prefix, $prj_email, $database);

    my $args = shift;

    $database = get_args(@$args);
    if ($ENV{'USER'} ne "datalib") {
	print "You are not datalib and so can't create the required directories\n";
	$testing = 1;
    } elsif (uc($database) ne "/\@ENAPRO") {
	print "Non ENAPRO transactions done in test mode\n";
	$testing = 1;
    }
	
    $testing && print "- running in test mode - no directories created, and no database commits\n";
    $database =~ s/^\/?\@?//;
    $dbh = DBI->connect("DBI:Oracle:$database",'', '',
			{  RaiseError => 1,
			   PrintError => 0,
			   AutoCommit => 0
                           }
			) or die "Could not connect to log database: " . DBI->errstr;
    my %newProject;
    
    ask_for_project_details(%newProject);

    my $pathword; # must move
    load_new_project(%newProject);

    make_loading_dirs(%newProject);
    make_dis_file(%newProject);
    make_ftp_dirs(%newProject);
    display_confirmation($database, %newProject);

    if ($testing) {
	$dbh->rollback();
    } else {
	$dbh->commit();
    }

    $dbh->disconnect();
}

################################################################################
# Run the script

main(@ARGV);
