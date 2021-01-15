#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/ges.pl,v 1.7 2011/11/29 16:33:38 xin Exp $
#
use strict;
use DBI;
use DBD::Oracle;
use Getopt::Std;
use Carp;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

sub print_usage {
    print STDERR "Displays current status and history of entry status changes of an entry.\n";
    print STDERR "Usage:\n";
    print STDERR "$0 <-l login\@database> <-a accno> [-h?]\n";
    print STDERR "-l           login: as scott/pass\@tiger\n";
    print STDERR "-a           accno: accession number\n";
    print STDERR "-h or -?     this help\n";
}
         
sub parse_command_line {
    my ($login, $accno);

    my %opts = ();
    getopts('l:a:h?',\%opts);

    #
    # Checking for help and/or compulsory args
    #
    if( $opts{'?'} || $opts{h} || keys(%opts) < 1) {
        print_usage();
        exit 1;
    }
    if( !$opts{l}) {
        print STDERR "Missing login - use the -l switch.\n";
        print_usage();
        exit 1;
    } else {
        $login = $opts{l};
    }
    if( !$opts{a} ) {
        print STDERR "Please provide accession number using the -a switch.\n";
        print_usage();
        exit 1;
    }
    #
    # Assigning values - we are assuming that values for compulsory args exists
    #
    $login = $opts{l};
    $accno = $opts{a};

    return ($login, $accno);
}

main();


sub main {
    # connect to database.
    my ($login,$accno) = parse_command_line();
    $login =~ s/^\/?\@?//;
    my $dbh = DBI->connect("DBI:Oracle:$login",'','',
            {
            RaiseError => 1, 
            PrintError => 0,
            AutoCommit => 0
            } )
    or die "Could not connect to log database: ".DBI->errstr;

    $dbh->do("alter session set nls_date_format='DD-MON-YYYY'" );

    # check whether entry exists.
    check_acc ($dbh,$accno);
    # print out stuff we want to see
    display_all ($dbh, $accno);
    # logout from database
    $dbh->disconnect();
}

sub check_acc {
    my ($dbh,$accno) = @_;

    my $sth = $dbh->prepare("SELECT primaryacc# FROM dbentry WHERE primaryacc# = ?");
    $sth->execute($accno);
    my ($acc) = $sth->fetchrow_array();
    confess "entry $accno not found in database" unless defined $acc;
    $sth->finish();
}

sub display_all {
    my ($dbh, $acc) = @_;
    my (@date, @status, @remark, @h_date, @ext_ver, @user);

    print "\n\n"; 
    printf "%-12s%-13s%-50s%-11s%-11s\n", "Date", "User", "Remark", "Status","Hold_date"; 
    printf "%-12s%-13s%-50s%-11s%-11s\n", "=========== ", "============ ", 
           "================================================= ", "========== ","===========";

    my $sth = $dbh->prepare("SELECT db.timestamp,
            db.userstamp,
            cv.status,         
            '-',
            NVL ((to_char (hold_date, 'DD-MON-YYYY')), '-'),
            NVL (ext_ver, '0')
            FROM dbentry db, cv_status cv
            WHERE db.primaryacc# = ?
            and db.statusid = cv.statusid");
    $sth->execute($acc);
    while ( my ( $date, $user, $status, $remark, $h_date, $ext_ver ) = $sth->fetchrow_array() ) {
        push (@date, $date);
        push (@status, $status);
        push (@remark, $remark);
        push (@h_date, $h_date);
        push (@ext_ver, $ext_ver);
        push (@user, $user);
    }
    $sth->finish();

    my $sql_dbentry_audit = $dbh->prepare("SELECT da.timestamp,
            da.userstamp,
            NVL (cv.status, '-'),
            NVL(remark, '-'),
            NVL ((to_char (hold_date, 'DD-MON-YYYY')), '-'),
            NVL (ext_ver, '0')
            FROM dbentry_audit da 
                left join cv_status cv
                on da.statusid = cv.statusid
            WHERE da.primaryacc# = ?
            ORDER BY da.timestamp desc");
    $sql_dbentry_audit->execute($acc);
    while ( my ( $date, $user, $status, $remark, $h_date, $ext_ver ) = $sql_dbentry_audit->fetchrow_array() ) {
        push (@date, $date);
        push (@status, $status);
        push (@remark, $remark);
        push (@h_date, $h_date);
        push (@ext_ver, $ext_ver);
        push (@user, $user);
    }
    $sql_dbentry_audit->finish();

    my $i = 0;
    for ($i = 0; $i<= $#date; $i++){
        if ($status[$i] eq 'public') {
            $h_date[$i] = '-';
            if ($ext_ver[$i] eq '0' ){
                $status[$i] = 'pre-public';
            }
        }
        if ($i == $#date){
            printf "%-12s%-13s%-50s%-11s%-11s\n",$date[$i], $user[$i], "Created", $status[$i],$h_date[$i];    
        } else {
            printf "%-12s%-13s%-50s%-11s%-11s\n",$date[$i], $user[$i], $remark[$i+1], $status[$i],$h_date[$i];    
        }
    }		
    print "\n";
}
