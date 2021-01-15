#!/ebi/production/seqdb/embl/tools/bin/perl -w
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/check_new_genomes.pl,v 1.38 2011/11/29 16:33:38 xin Exp $

#================================================================================
# Module Description:
#
# The script checks for new submissions containing "complete genomes" on either
# DE or keyword line. It then checks if those ones are already in the genome_seq table
# and drops the ones that are already in.
#
# It's run by a crontab job once a week at midnight Saturday. It sends the results
# to the e-mail addresses stored in the genome_notification.lis in the same dirctory
# where the script is kept. Any one wishes to receive the notification needs to include
# their e-mail address in the genome_notification.lis.
#
# If two dates are provided on the command line, the script will find the new genomes
# added to enapro (or devt for testing) during the period specified and produce a report.
#
# Modification history:
#
# 20-MAY-2002    Quan Lin   Created.
#================================================================================

use strict;
use DBI;
use DBD::Oracle;
use sendEmails;
use ENAdb;

my $usage =
    "\nUSAGE 1:    $0 <database> <date1> <date2> \n"
  . "            finds the new genomes added to the chosen database between these two dates.\n"
  . "\nUSAGE 2:    $0 <database>\n"
  . "            finds the new genomes added to enapro for the last 7 days.  This option is only\n"
  . "            used by a crontab job and is run every Saturday at midnight.\n"
  . "\nPARAMETERS: <database> is either /\@devt or /\@enapro.\n"
  . "            Dates are entered like:01-jan-2001 01-mar-2001.\n"
  . "            The abbreviation for the months:JAN,FEB,MAR,APR,MAY,JUN,JUL,AUG,SEP,OCT,NOV,DEC.\n\n";

my ($date1, $date2, $last_run_date, $current_date, $dbh);

my @description_exclusion_regex = (" nearly complete","^Homo sapiens.*mitochon", "^Mus musculus.*mitochon", "^Ovis aries.*mitochon", "^Human immunodeficiency virus 1 ", "^Human immunodeficiency virus 2 ", "^HIV\-1 ", "^HIV\-2 ");
my $exclusion_by_de_count = 0;
main();

#-------------------------------------------------------------------------------------
# list of subs
#-------------------------------------------------------------------------------------

sub main {

    die $usage if (@ARGV == 0 || @ARGV == 2);
    my $database = $ARGV[0];
    defined($database) || die $usage;

    my %attr   = ( PrintError => 0,
		   RaiseError => 0,
		   AutoCommit => 0 );
    
    $dbh = ENAdb::dbconnect($database,%attr)
	|| die "Can't connect to database: $DBI::errstr";

    my $message1 = ">>>The format of one or both dates was wrong. Program terminated\n";
    my $message2 = ">>>Please provide two dates\n";

    if (@ARGV == 1) {
        my $current_time = get_time();
        my @hour = split(/\:/, $current_time);

        if ($hour[0] != 0) {    # make sure when no dates provided, the script is only run by the crontab
            die($message2);
        }

    } elsif (@ARGV == 3) {

        $date1 = uc $ARGV[1];
        $date2 = uc $ARGV[2];

        unless ($date1 =~ /\d+\-\w{3}\-\d{4}/ and $date2 =~ /\d+\-\w{3}\-\d{4}/) {
            die($message1);
        }
    } ## end elsif (@ARGV == 3)

    # get a list of AC's of candiate entries
    my %new_records = get_new_records();

    # get existing entries and also remove redundant ones from the list of candidates
    my ($unique_acc, $acc_exist) = drop_exist_records(\%new_records);

    # split into viral and non viral
    my ($virus, $non_viral_acc) = separate_viral_records_and_exclude_some_de($unique_acc);

    # remove those with identical DE's!?
    my @unique_nonviral_genome = compare_non_viral_descr($non_viral_acc, $acc_exist);

    my @complete_new_entries;

    # if there are some viruses, pass both lists, and only viruses where the current OS isn't on the new the same as an old one will be kept
    if (@$virus) {

        @complete_new_entries = compare_os_name($virus, \@unique_nonviral_genome);
    } else {

        @complete_new_entries = @unique_nonviral_genome;
    }

    my %complete_new_records = get_first_created_date(\@complete_new_entries);    # returns hash of AC->'\tDE\tdate'

    my @sorted_records = sort_by_description(\%complete_new_records);

    my @final_new_records;

    foreach my $val (@sorted_records) {
        push(@final_new_records, "$val$complete_new_records{$val}");
    }

    report_results(\@final_new_records);

    $dbh->rollback();
    $dbh->disconnect;
} ## end sub main

# get new entries containing complete genome
sub get_new_records {

    my %new_records;

    if (@ARGV == 1) {
        ($current_date, $last_run_date) = get_date();
        %new_records = get_new_entry($last_run_date, $current_date);
    } elsif (@ARGV == 3) {

        %new_records = get_new_entry($date1, $date2);
    }
    return %new_records;
} ## end sub get_new_records

#compare the new records with the ones already in the genome_seq table
# drop the ones already in from the new record list
sub drop_exist_records {

    my ($loc) = @_;
    my %new_records = %$loc;

    # get accession numbers exist already in the genome_seq table
    my %acc_exist = get_acc_exist();

    # compare the new acc# with the acc# in the genome_seq table, drop the ones
    # that already in the table

    my @new_acc;

    foreach my $key (keys(%new_records)) {
        if (!($acc_exist{$key})) {
            push(@new_acc, $key);
        }
    }

    return (\@new_acc, \%acc_exist);
} ## end sub drop_exist_records

# get descriptions for entries, separate viral and non-viral entries
sub separate_viral_records_and_exclude_some_de {

    my ($loc) = @_;
    my @unique_acc = @$loc;

    my @virus;
    my %non_viral_acc = ();

    foreach my $acc_num (@unique_acc) {
        my $description = get_desc($acc_num);

        if (excluded_by_description($description)) {
            $exclusion_by_de_count++;
        } elsif (   ($description =~ /virus\b/i)
                 || ($description =~ /\bviroid\b/i)) {
            push(@virus, "$acc_num");
        } else {
            $non_viral_acc{$description} = $acc_num;
        }
    } ## end foreach my $acc_num (@unique_acc)

    return \(@virus, %non_viral_acc);
} ## end sub separate_viral_records_and_exclude_some_de

sub excluded_by_description {
    my $description = shift;
    foreach my $excluded_regex (@description_exclusion_regex) {
        if ($description =~ /$excluded_regex/) {
            return 1;
        }
    }
    return 0;
} ## end sub excluded_by_description

sub compare_non_viral_descr {

    my ($loc_a, $loc_b) = @_;

    my %non_viral_acc = %$loc_a;
    my %acc_exist     = %$loc_b;

    my @new_nonviral_genome;

    # make description as hash key for comparison
    my @temp_acc      = keys(%acc_exist);
    my @temp_des      = values(%acc_exist);
    my %rev_acc_exist = ();

    for (my $i = 0 ; $i <= $#temp_acc ; $i++) {
        $rev_acc_exist{ $temp_des[$i] } = $temp_acc[$i];
    }

    # compare the description
    foreach my $key (keys(%non_viral_acc)) {
        if (!($rev_acc_exist{$key})) {
            push(@new_nonviral_genome, "$non_viral_acc{$key}\t$key\n");
        }
    }

    return @new_nonviral_genome;
} ## end sub compare_non_viral_descr

sub compare_os_name {

    my ($loc_a, $loc_b) = @_;
    my @virus               = @$loc_a;
    my @uni_nonviral_genome = @$loc_b;
    my %uni_os              = ();        # hash of all virus /organisms in new genome candidates

    foreach my $val (@virus) {
        my $organism = get_os($val);
        $uni_os{$organism} = $val;
    }

    # find out organisms that already exist in the genome_seq table and compare with the new one
    # and added the ones that are not in the genome_seq table to the non_viral list

    my %old_vir_os = get_old_vir();      # hash of all virus /organisms in existing virus genomes

    foreach my $key (keys(%uni_os)) {

        if (!($old_vir_os{$key})) {

            my $de_line = get_desc($uni_os{$key});
            push(@uni_nonviral_genome, "$uni_os{$key}\t$de_line\n");
        }
    } ## end foreach my $key (keys(%uni_os...

    return (@uni_nonviral_genome);
} ## end sub compare_os_name

# get first_created date for all new entries
sub get_first_created_date {

    my ($loc) = @_;
    my @complete_new_entries = @$loc;
    my %complete_new_records;

    foreach my $entry (@complete_new_entries) {
        chomp $entry;
        my ($acc_number, $desc) = split(/\t/, $entry);
        my $date = get_first_created($acc_number);
        $complete_new_records{$acc_number} = "\t$desc\t$date\n";
    }

    return %complete_new_records;
} ## end sub get_first_created_date

sub sort_by_description {

    my ($loc) = @_;
    my %complete_records = %$loc;

    my @sorted_genome = sort { $complete_records{$a} cmp $complete_records{$b} } keys %complete_records;
    return @sorted_genome;
} ## end sub sort_by_description

sub report_results {

    my ($loc) = @_;
    my @final_records = @$loc;

    if (@ARGV == 1) {

        # sending e-mails
        my $subject = "New genomes added to enapro between $last_run_date and $current_date (excluded by dDE=$exclusion_by_de_count)";

        send_email_with_array_msg("dbgroup2.email", "datalib\@ebi.ac.uk", $subject, @final_records);

    } elsif (@ARGV == 3) {
        open(REPORT, "> $date1*$date2.newgenome") || die "Can't open $date1*$date2.newgenome: $!";
        print "The new genomes added to enapro between $date1 and $date2\n"
          . "are listed in $date1*$date2.newgenome (excluded by dDE=$exclusion_by_de_count)\n\n";
        print REPORT "New genomes submitted to enapro between $date1 and $date2 are listed below.\n\n";
        print REPORT @final_records;
        close REPORT;
    } ## end elsif (@ARGV == 3)
} ## end sub report_results

# get current date and last run date
sub get_date {
    my $current_date;
    my $last_run_date;
    my $sth = $dbh->prepare(
        q{
                           SELECT to_char ((sysdate),'DD-MON-YYYY'), to_char ((sysdate-7),'DD-MON-YYYY')
			     FROM dual
                         })
	|| die "Can't prepare statement: $DBI::errstr";
    $sth->execute();
    ($current_date, $last_run_date) = $sth->fetchrow_array;
    return ($current_date, $last_run_date);
} ## end sub get_date

# get current time
sub get_time {
    my $current_time;
    my $sth = $dbh->prepare(
        q{
                           SELECT to_char ( sysdate,'HH24:MI:SS')
			     FROM dual
                         })
	|| die "Can't prepare statement: $DBI::errstr";
    $sth->execute();
    ($current_time) = $sth->fetchrow_array;
    return $current_time;
} ## end sub get_time

# Trace lineage of taxid to find if it is a cellular organism
sub isCellular($) {
    my $taxid = shift;
    my $getTaxParent = $dbh->prepare(
        q{
	    SELECT  parent_id
	    FROM    ntx_tax_node
	    WHERE   tax_id = ?
	}
	)
	|| die "Can't prepare statement: $DBI::errstr";
    while ($taxid != 1) {
        if ($taxid == 131567) {    # ie 'cellular organisms'
            $getTaxParent->finish;
            return 1;
        }
        $getTaxParent->execute($taxid) || die "Can't execute statement: $DBI::errstr";
        ($taxid) = $getTaxParent->fetchrow_array;
    } ## end while ($taxid != 1)
    return 0;
} ## end sub isCellular($)

# sql to get new entries having "complete genome" on either keyword or description
# line between two dates
sub get_new_entry {
    my ($first_date, $sec_date) = @_;
    my $sth = $dbh->prepare(
        q{
                            SELECT db.primaryacc#
                            FROM dbentry db, keywords k 
                            WHERE (db.first_created >= ? or db.first_public >= ?)
                            AND (db.first_created <= ? or db.first_public <= ?)
                            AND db.statusid = 4
                            AND db.first_public is not null
                            AND k.keyword like '%complete genome%'
			    AND k.dbentryid = db.dbentryid
                            UNION
                            SELECT db.primaryacc#
			    FROM description d, dbentry db 
			    WHERE (db.first_created >= ? or db.first_public >= ?)
                            AND (db.first_created <= ? or db.first_public <= ?)
                            AND db.statusid = 4
                            AND db.first_public is not null
			    AND d.text LIKE '%complete genome%'
			    AND (d.text NOT like '%section%' AND d.text NOT LIKE '%segment%')
			    AND d.dbentryid = db.dbentryid
                            AND db.dataclass not in ('EST', 'MAG', 'PAT')
			   })
	|| die "Can't prepare statement: $DBI::errstr";

    # excute sql
    $sth->bind_param(1, $first_date);
    $sth->bind_param(2, $first_date);
    $sth->bind_param(3, $sec_date);
    $sth->bind_param(4, $sec_date);
    $sth->bind_param(5, $first_date);
    $sth->bind_param(6, $first_date);
    $sth->bind_param(7, $sec_date);
    $sth->bind_param(8, $sec_date);

    $sth->execute || die "Can't execute statement: $DBI::errstr";
    die $sth->errstr if $sth->err;

    my %records;

    while (my $rows = $sth->fetchrow_array) {
        $records{$rows} = 1;
    }

    return %records;
} ## end sub get_new_entry

# sql to get all the acc numbers in genome_seq table aleady
sub get_acc_exist {
    my %results = ();

    my $sth = $dbh->prepare(
        q{
                              SELECT primaryacc#, descr
			      FROM genome_seq
                              })
	|| die "Can't prepare statement: $DBI::errstr";

    $sth->execute || die "Can't execute statement: $DBI::errstr";
    die $sth->errstr if $sth->err;

    while (my @rows = $sth->fetchrow_array) {
        $results{ $rows[0] } = $rows[1];
    }

    return %results;
} ## end sub get_acc_exist

# sql to get description for each new entry
sub get_desc {
    my ($acc) = @_;

    my $sth = $dbh->prepare(
        q{
                            SELECT d.text
	                    FROM dbentry db, description d
                            WHERE db.primaryacc# = ?
                            AND db.dbentryid = d.dbentryid
			  })
	|| die "Can't prepare statement: $DBI::errstr";

    $sth->execute($acc) || mail_error("Can't execute statement: $DBI::errstr");
    die $sth->errstr if $sth->err;
    my $des = $sth->fetchrow_array;
    return $des;
} ## end sub get_desc

# to get organism names for the new virus entries
sub get_os {
    my ($acc) = @_;

    my $sth = $dbh->prepare(
        q{
                            SELECT t.leaf
                            FROM ntx_lineage t, sourcefeature so, 
                                 dbentry db
                            WHERE t.tax_id = so.organism
 			      AND so.PRIMARY_SOURCE = 'Y'
                              AND so.bioseqid = db.bioseqid
                              AND db.primaryacc# = ?
                          })
	|| die "Can't prepare statement: $DBI::errstr";

    $sth->execute($acc) || mail_error("Can't execute statement: $DBI::errstr");
    die $sth->errstr if $sth->err;

    my $result = $sth->fetchrow_array;
    return $result;
} ## end sub get_os

# to get organism names for virues already in the genome_seq table
sub get_old_vir {
    my $sth = $dbh->prepare(
        q{
                           SELECT primaryacc#
                             FROM genome_seq
                            WHERE category = 2
                         })
	|| die "Can't prepare statement: $DBI::errstr";

    $sth->execute || mail_error("Can't execute statement: $DBI::errstr");
    die $sth->errstr if $sth->err;

    my %old_vir_os = ();

    while ((my $result) = $sth->fetchrow_array) {
        my $old_os = get_os($result);
        $old_vir_os{$old_os} = $result;
    }

    return %old_vir_os;
} ## end sub get_old_vir

sub get_first_created {
    my ($acc) = @_;
    my $sth = $dbh->prepare(
        q{
	SELECT first_created
	    FROM dbentry
	    WHERE primaryacc# = ?
	})
	|| die "Can't prepare statement: $DBI::errstr";

    $sth->execute($acc) || die "Can't execute statement: $DBI::errstr";
    die $sth->errstr if $sth->err;
    my $date = $sth->fetchrow_array;
    return $date;
} ## end sub get_first_created

# send error messages by e-mail. This sub was borrowed from Francesco.
sub mail_error {

    # send an e-mail to dbgroup and then dies
    # Should be more secure than making a direct system call to Mail

    my $messg = shift;

    #  send_email_with_string_msg("dbgroup3.email", "datalib\@ebi.ac.uk", "Subject: $0 @ARGV error!\n\n", $messg."\n\n$!\n"); # $0 is the program

    die($messg);
} ## end sub mail_error

