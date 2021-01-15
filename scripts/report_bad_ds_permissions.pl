#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/report_bad_ds_permissions.pl,v 1.6 2011/11/29 16:33:38 xin Exp $
#
#  (C) EBI 2000
#
#  MODULE DESCRIPTION:
#
#  Checks all DS directories and their contents are readable and 
#  writable by datalib.  If not, email the curator who owns them 
#  (or updates@ebi.ac.uk in the absence of an owner).
#
#  MODIFICATION HISTORY:
#
#===============================================================================

use strict;
#use Data::Dumper;
use DBI;
use dbi_utils;

#use Utils qw(my_system);


my $exit_status = 0;
my $verbose = 0;
my $test = 0;

#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------

sub get_args(\@) {

    my ($arg, $usage, $database);

    my $args = shift;

    $usage = "\nUSAGE: $0 [-test] [-h(elp)]\n\nThis script checks the permissions of all the ds directories and the files they contain.  If it finds any non-readwritable by datalib, it emails the owner (or updates".'@'."ebi.ac.uk if they don't work here anymore) and asks them to change the permissions.\n-test\tdoes the checks in \$DS_TEST and writes a report to $ENV{LOGDIR}/report_ds_permissions.log instead of emailing everyone.\n-help\twrites this message.\n";

    foreach $arg (@$args) {

	if ($arg =~ /^-test/) {
	    $test = 1;
	}
	elsif ($arg =~ /^-v(erbose)?/) {
	    $verbose = 1;
	}
	elsif ($arg =~ /^-h(elp)?/) {
	    die $usage;
	}
	else {
	    die "Unrecognised argument: $arg\n$usage";
	}
    }

    return($test);
}

#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------

sub format_email_messages(\%$) {

    my ($ds_or_file, %messages, $owner);

    my $bad_dirs_and_files = shift;
    my $ds_super_dir = shift;

    foreach $owner (keys %$bad_dirs_and_files) {

	foreach $ds_or_file (@{ $$bad_dirs_and_files{$owner} }) {

            # with directories...
	    if ($ds_or_file =~ /\/$/) {
		$messages{$owner} .= "chmod 770 $ds_super_dir/$ds_or_file\n";
	    }
	    else {
            # with files...
		$messages{$owner} .= "chmod -R ug+rw $ds_super_dir/$ds_or_file\n"
	    }

	    # with files AND directories
	    $messages{$owner} .= "chgrp services $ds_super_dir/$ds_or_file\n";
	}
    }

    return(\%messages);
}

#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------

sub check_owner_status($$) {

    my ($query, @results);

    my $owner = shift;
    my $dbh = shift;

    $query = $dbh->prepare(q{select curator_statusid from curator where user_name = ?});
    $query->bind_param(1, $owner);
    $query->execute;

    # only 1 row is returned
    @results = $query->fetchrow_array();

    # return curator_status
    return($results[0]);
}

#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------

sub get_owner_status(\%$) {

    my ($status, %owner_and_status, $owner);

    my $bad_dirs_and_files = shift;
    my $dbh = shift;

    foreach $owner (keys %$bad_dirs_and_files) {

	$status = check_owner_status($owner, $dbh);

	if (!defined($status)) {
	    $status = 2;
	}

	$owner_and_status{$owner} = $status;
    }

    return(\%owner_and_status);
}

#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------

sub get_bad_files_in_ds($$\%$) {

    my (@file_list, $file_listing, $file_name, $owner);

    my $ds_super_dir = shift;
    my $ds = shift;
    my $bad_dirs_and_files = shift;
    my $dbh = shift;

    @file_list = `ls -l $ds_super_dir/$ds/`;

    foreach $file_listing (@file_list) {

	if ($file_listing =~ /([-d])[rw-]{2}.([rw-]{2})\S+\s+\d+\s+(\S+).+(\d\d:\d\d|\d{4})\s+(\S+)\n/) {
#                           file/dir userperm groupperm            curator                    filename

	    $file_name = $5;
	    $owner = $3;

	    if ($2 ne "rw") {
		push(@{ $$bad_dirs_and_files{$owner} }, $ds.'/'.$file_name);
	    }
	}
    }
}

#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------

sub get_list_of_bad_ds_and_files($$) {
    
    my ($list_item, @dir_list, $ds, %bad_dirs_and_files, $owner);

    my $ds_super_dir = shift;
    my $dbh = shift;

    @dir_list = `ls -l $ds_super_dir`;

    foreach $list_item (@dir_list) {

	if ($list_item =~ /d[rwxs-]{9}\s+\d+\s+(\S+).+(\d\d:\d\d|\d{4})\s+(\d{4,5})\n/) {
#                                               owner                     filename
	    $ds = $3;
	    $owner = $1;

	    #$owner = get_valid_owner(%owner_and_status, $orig_owner, $dbh);

            # if ds dir has bad permissions, add it to the list 
	    # (making sure owner is an active curator)
	    if ((! -r "$ds_super_dir/$ds") || (! -w "$ds_super_dir/$ds") || (! -x "$ds_super_dir/$ds")) {

		push(@{ $bad_dirs_and_files{$owner} }, $ds.'/');
	    }

	    if ((-r "$ds_super_dir/$ds") && (-x "$ds_super_dir/$ds")) {
                # collate files with bad permissions from within ds 
                # if ds has group r-x permissions minimum (write-mode optional)

		get_bad_files_in_ds($ds_super_dir, $ds, %bad_dirs_and_files, $dbh);
	    }
	    elsif ((! -r "$ds_super_dir/$ds") || (! -x "$ds_super_dir/$ds")) {
		push(@{ $bad_dirs_and_files{$owner} }, $ds.'/*');
	    }
	}
    }

    return(\%bad_dirs_and_files);
}

#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------

sub check_user() {

    if ($ENV{USER} !~ /^datalib$/i) {
	die "This script must be run as the user datalib\n";
    }
}

#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------

sub generate_and_send_emails(\%\%$) {

    my ($email_subject, $capitalised_curator, $curator, $initial_text);
    my (@email_sent, $datasubs_msg, $email_on, $stdout_messages_on);
    my ($datasubs_bad_files);

    my $email_msgs = shift;
    my $owner_and_status = shift;
    my $ds_super_dir = shift;

    $email_subject = 'ds directories with bad permissions';

    if ($test) {
	$email_subject .= " (\$DS_TEST)";
    }

    $initial_text = "The following is a list of ds directories and/or files from $ds_super_dir which you need to change the permissions of so they can be archived.\n\nPlease change the permissions of these files/directories by running:\n\n";

    # flag that can be used while debugging to send emails or not
    $email_on = 1;

    # flag that can be used while debugging to display output messages or not
    $stdout_messages_on = 1;

    foreach $curator (keys %$email_msgs) {

	if ($email_on && ($$owner_and_status{$curator} == 1)) {

	    $capitalised_curator = ucfirst($curator);

	    open(MAIL, "|/usr/sbin/sendmail -oi -t");

	    print MAIL 'To: update@ebi.ac.uk'."\n";
	    #print MAIL 'To: test-upd@ebi.ac.uk'."\n";

	    print MAIL 'From: datalib@ebi.ac.uk'."\n"
		. "xForms: $capitalised_curator\n"
		. "Subject: $email_subject\n"
		. "Dear $curator,\n\n"
		. $initial_text
		. $$email_msgs{$curator};
	    
	    close(MAIL);

	    push(@email_sent, $curator);
	} 
	elsif ($$owner_and_status{$curator} != 1) {
            # make list of unknown curators, regardless of whether email mode is switched on

	    if ($curator ne "datalib") {
		$datasubs_bad_files .= "\necho $curator\n".$$email_msgs{$curator};
	    }
	}

	if ($stdout_messages_on && ($$owner_and_status{$curator} == 1)) {
	    # print email contents to STDOUT
	    print "\n\n#----------------------------------------------------------------\n"
		. "Dear $curator,\n\n";


	    print $initial_text
		. $$email_msgs{$curator};
	}
    }

    # print out messages for datasubs
    if ($datasubs_bad_files ne "") {

	$datasubs_msg = "The owner of these files/directories either no longer works here or they are not a \"curator\", hence this message is being sent to you.  You can ask various users listed below to change their file permissions (e.g. \"echo rasko\" lists rasko's files. NB appserv = lbower), or else will you may have to ask systems to make these changes for you.\n\n";

	$datasubs_bad_files =~ s/^\n//;

	if ($email_on) {

	    open(MAIL, "|/usr/sbin/sendmail -oi -t");

	    print MAIL 'To: update@ebi.ac.uk'."\n";
	    #print MAIL 'To: test-upd@ebi.ac.uk'."\n";

	    print MAIL 'From: datalib@ebi.ac.uk'."\n"
		. "Subject: $email_subject\n"
		. "Dear datasubs,\n\n"
		. $datasubs_msg	    
		. $initial_text
		. $datasubs_bad_files;
	    
	    close(MAIL);

	    push(@email_sent, "datasubs");
	}

	if ($stdout_messages_on) {

	    print "\n\n#----------------------------------------------------------------\n"
		."Dear datasubs,\n\n$datasubs_msg"
		. "$datasubs_bad_files\n";
	}
    }

    print "\n\nEmails have been sent to: ".join(", ", sort(@email_sent) )."\n";
}

#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------

sub main(\@) {

    my ($test, $ds_super_dir, $dbh, $bad_dirs_and_files, $owner_and_status);
    my ($email_msgs);

    my $args = shift;

    check_user();

    ($test) = get_args(@$args);

    if ($test) {
	$ds_super_dir = $ENV{"DS_TEST"};
	$dbh = dbi_ora_connect('/@devt');
    }
    else {
	$ds_super_dir = $ENV{"DS"};
	$dbh = dbi_ora_connect('/@enapro');
    }

    #$ds_super_dir = "/homes/gemmah/scripts/mockup/ds_small";


    $bad_dirs_and_files = get_list_of_bad_ds_and_files($ds_super_dir, $dbh);


    if (scalar(keys %$bad_dirs_and_files)) {

	$owner_and_status = get_owner_status(%$bad_dirs_and_files, $dbh);

	$email_msgs = format_email_messages(%$bad_dirs_and_files, $ds_super_dir);

	generate_and_send_emails(%$email_msgs, %$owner_and_status, $ds_super_dir);
    }
    else {
	print "No directories or files with bad permisssions were found inside $ds_super_dir\n\n";
    }

    dbi_logoff($dbh);
}

main(@ARGV);
