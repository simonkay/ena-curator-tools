#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/distribute_entry.pl,v 1.14 2011/11/29 16:33:38 xin Exp $
# Replacement of distribute_entry.pl based on 
# badly name duplicate-function script de.pl
#
# Non-interactive script to re-distribute entries
#
use strict;
use Getopt::Long;
use DBI;

my $verbose = 0;
my $COMMITSIZE  = 5000;
my $REMARKLIMIT = 50;
main();

sub main {
    my ($login, $ra_accessions, $remark) = parse_command_line();
    if ($verbose) {
        print "Login:\n \"$login\"\n";
        print "Entries:\n " . join("\n",@{$ra_accessions})."\n";
        print "Audit:\n \"$remark\"\n";
        print "Committing in chunks of $COMMITSIZE\n\n";
    }
    if (scalar(@$ra_accessions) == 0) {
        print STDERR "No accessions listed\n";
	exit(2);
    }
   $login =~ s/^\/?\@?//;
    my $dbh = DBI->connect("DBI:Oracle:$login",'', '',
                           {  RaiseError => 1,
                              PrintError => 0,
                              AutoCommit => 0
                           }
    ) or die "Could not connect to $login database: " . DBI->errstr;

    simplify_accession_list($dbh, $ra_accessions);
    $verbose && print STDERR scalar(@$ra_accessions) . " accessions found\n";

    $dbh->do("alter session set nls_date_format='DD-MON-YYYY'");

    $dbh->do("begin auditpackage.remark := '$remark'; end;");

    #
    # process entries
    #
    my $select_h = $dbh->prepare("
            SELECT primaryacc#, statusid 
              FROM dbentry
             WHERE primaryacc# = ? 
            "
    );
    my $update_timestamp_h = $dbh->prepare("
            UPDATE dbentry 
               SET timestamp   = sysdate, 
                   change_date = sysdate
            WHERE primaryacc#  = ?
            "
    );

    my $count = 0;
    foreach (@$ra_accessions) {
        my $acc = $_;
        $acc =~ s/\s//g;    # clear whitespace
        $acc = uc($acc);    # make uppercase
        $select_h->execute($acc);
        my ($primary, $statusid) = $select_h->fetchrow_array();
        if (!defined $primary) {
            print STDERR "WARNING: entry $acc does not exist in the database.\n";
        } elsif ($statusid ne "4") {
            print STDERR "WARNING: entry $acc is not public.\n";
        } else {
            $update_timestamp_h->execute($primary) || die "database prepare error: $DBI::errstr\n ";
            print STDERR "$acc flagged for distribution.\n";
	    if (++$count % $COMMITSIZE == 0) {
		$dbh->commit();
	    }
        }
        $dbh->commit();
    } ## end foreach (@$ra_accessions)
    $dbh->commit();
    $select_h->finish();
    $dbh->disconnect();
    printf STDERR "%d entries flagged for distribution\n", $count;
} ## end sub main

sub parse_command_line {
    my ($login, @accnos, $remark);
    my @files = ();
    my $helpme;
    my %opts = ();
    GetOptions("remark=s"    => \$remark,
               "accession=s" => \@accnos,
               "login=s"     => \$login,
               "verbose"     => \$verbose,
               "usage|help"  => \$helpme);
    if ($helpme) {
        print_usage();
        exit;
    }

    foreach my $arg (@ARGV) {
        if ($arg =~ /^([A-Z]{1,4}\d{5,})$/) {
            push(@accnos, $1);
        } elsif ($arg =~ /^([A-Z]{1,4}\d{5,})-([A-Z]{1,4}\d{5,})$/) {
            push(@accnos, $arg);    # can't resolve ranges until we have a database connection
        } elsif ($arg =~ /\/\@\S+/) {
            if ((defined($login)) && ($login ne $arg)) {
                print STDERR "You seem to be saying two databases, $login and $arg\n";
                $helpme = 1;
            }
            $login = $arg;
        } elsif (-e $arg) {
	    if (-s $arg) {
		push(@files, $arg);
	    } else {
		$verbose && print STDERR "File $arg is empty\n";
	    }
        } else {
            print STDERR "I don't understand arg $arg\n";
            $helpme = 1;
        }
    } ## end foreach my $arg (@ARGV)
    if (!(defined($login))) {
        print STDERR "You must provide a login like /\@enapro\n";
        $helpme = 1;
    }
    if (!(defined($remark))) {
        print STDERR "You must provide an audit remark using the -r flag\n";
        $helpme = 1;
    }
    if ( length($remark) > $REMARKLIMIT ) {
	print STDERR "Remark should be $REMARKLIMIT characters or less\n"
	    . "$remark is ".length($remark)." long\n"
	    . ' ' x  $REMARKLIMIT . "|-> excess\n";
        $helpme = 1;
    }
    if ($helpme) {
        print_usage();
        exit 1;
    }

    foreach my $fname (@files) {
        open INFILE, $fname or die "Could not read file $fname $!";
        while (<INFILE>) {
            chomp();
            $_ =~ s/\s//g;
	    if ($_ !~ /^#/) {
		push(@accnos, $_);
	    } else {
		$verbose && print STDERR "ignoring line $_\n";
	    }
        }
        close INFILE;
    } ## end foreach my $fname (@files)

    return ($login, \@accnos, $remark);
} ## end sub parse_command_line

sub print_usage {
    print "Script to re-distribute entries (for whatever reason) if they were missed by the daily distribution.\n"
      . "Usage:\n"
      . "$0 <login> <-a accno | accno_file> <-r \"Audit remark\"> [-vh?]\n"
      . "-a           accno: accession number\n"
      . "accno_file   file with a list of acc numbers ( - for STDIN)\n"
      . "-r           audit remark like -r \"Entry CDS was missing\n"
      . "-v           verbose output\n"
      . "-h or -?     this help\n";
} ## end sub print_usage

# script should be able to accept ranges within the list of entries
sub accno_range_to_list {
    my ($dbh, $ra_accnos, $ac_from, $ac_to) = @_;
    if (!(defined($ac_to))) {
        if ($ac_from =~ s/\-([A-Z0-9]+)//) {    #range not yet split
            $ac_to = $1;
        } else {
            $ac_to = $ac_from;                  # ie accidental use of derange!
        }
    }
    my $sth = $dbh->prepare("SELECT primaryacc# from dbentry where primaryacc# between ? and ?") || die "database prepare error: $DBI::errstr\n ";
    $sth->execute($ac_from, $ac_to) || die "database execute error: $DBI::errstr\n ";
    while (my ($acc) = $sth->fetchrow_array) {
        push(@$ra_accnos, $acc);
    }
    $sth->finish;
} ## end sub accno_range_to_list

sub simplify_accession_list {
    my ($dbh, $ra_accessions) = @_;
    my @fullList = ();
    foreach my $item (@$ra_accessions) {
        if ($item =~ /^([A-Z]{1,4}\d{5,})-([A-Z]{1,4}\d{5,})$/) {
            accno_range_to_list($dbh, \@fullList, $1, $2);
        } else {
            push(@fullList, $item);
        }
    }
    @$ra_accessions = grep { $_ if !$_{$_}++ } @fullList;    # remove duplicates (if any)
} ## end sub simplify_accession_list
