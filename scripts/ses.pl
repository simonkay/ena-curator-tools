#!/ebi/production/seqdb/embl/tools/bin/perl -w
use strict;
use DBI;
use DBD::Oracle;
use Getopt::Std;
use Carp;

main();
sub main {
    # connect to database.
    my ($login, $accno, $statusid, $remark) = parse_command_line();
    my $dbh = DBI->connect('DBI:Oracle:',$login,'',
            {
            RaiseError => 1, 
            PrintError => 0,
            AutoCommit => 0
            } )
    or die "Could not connect to log database: ".DBI->errstr;

    $dbh->do("alter session set nls_date_format='DD-MON-YYYY'" );

    # check whether entry exists.
    check_acc ($dbh, $accno);
    alter_status($dbh, $accno, $statusid, $remark);
    # logout from database
    $dbh->disconnect();
}

sub alter_status {
    my ($dbh, $accno, $statusid, $remark) = @_;
    eval {
        my $sth = $dbh->prepare(q{
            UPDATE dbentry
            SET 
            statusid = ?
            , change_date = sysdate
            WHERE primaryacc# = ?
        });
        $dbh->do("begin auditpackage.remark := '$remark'; end;");
        $sth->execute($statusid,$accno);
        $dbh->commit();
    };
    if($@) {
        confess "Error during altering status:\n $@";
    }
}

sub print_usage {
    print STDERR "Sets the status of an entry (dbentry.statusid), sets audit message (dbentry_audit.remark) and forces re-distribution by updating dbentry.change_date\n";
    print STDERR "Usage:\n";
    print STDERR "$0 <-l login\@database> <-a accno> <-s statusid> <-r audit_remark> [-h?]\n";
    print STDERR "-l            login: as scott/pass\@tiger\n";
    print STDERR "-a            accno: accession number\n";
    print STDERR "-s            statusid: (see cv_status: 4 - public, 5 - suppressed, 6 - killed, etc.)\n";
    print STDERR "-r            audit remark like \"killing obsolete entry\"\n";
    print STDERR "-h or -?      this help\n";
}

sub parse_command_line {
    my ($login, $accno, $statusid, $remark);
    my $ok = 1;
    my %opts = ();
    getopts('l:a:r:s:h?',\%opts);

    #
    # Checking for help and/or compulsory args
    #
    if( $opts{'?'} || $opts{h} || keys(%opts) < 1) {
        print_usage();
        exit 1;
    }
    if( !$opts{l}) {
        print STDERR "Missing login - use the -l switch.\n";
        $ok = 0;
    } else {
        $login = $opts{l};
    }
    if( !$opts{a} ) {
        print STDERR "Please provide accession number by using the -a switch.\n";
        $ok = 0;
    }
    if( !$opts{s}) {
        print STDERR "Please provide status ID by using the -s switch.\n";
        $ok = 0;
    }
    if( !$opts{r}) {
        print STDERR "Audit remark is missing - use the -r switch.\n";
        $ok = 0;
    }
    if(!$ok) {
        print_usage();
        exit 1;
    }
    #
    # Assigning values - we are assuming that values for compulsory args exists
    #
    $login = $opts{l};
    $accno = $opts{a};
    $statusid = $opts{s};
    $remark= $opts{r};

    return ($login, $accno, $statusid, $remark);
}

sub check_acc {
    my ($dbh,$accno) = @_;

    my $sth = $dbh->prepare("SELECT primaryacc# FROM dbentry WHERE primaryacc# = ?");
    $sth->execute($accno);
    my ($acc) = $sth->fetchrow_array();
    confess "entry $accno not found in database" unless defined $acc;
    $sth->finish();
}
