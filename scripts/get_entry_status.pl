#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/get_entry_status.pl,v 1.20 2011/11/29 16:33:38 xin Exp $
#
#  (C) EBI 1998
#
#  MODULE DESCRIPTION:
#
#  Displays audit history for table dbentry.
#
#  MODIFICATION HISTORY:
#
#  20-AUG-1998 Nicole Redaschi     Created.
#  05-MAY-2000 Carola Kanz         login given as first parameter, added strict
#  31-AUG-2000 Carola Kanz         oraperl -> dbi
#  26-SEP-2000 Nicole Redaschi     use dbi_utils. changed output format.
#  09-AUG-2001 Peter Stoehr        usage notes
#  13-APR-2007 Quan Lin            rewrote most of it, using new statusid
#  31-OCT-2007 Nadeem Faruque      changed sql to uses (implicit) bind_param
#===============================================================================

use strict;
use DBI;
use DBD::Oracle;
use SeqDBUtils2;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Displays current status and history of entry status changes of an entry.\n".
            " USAGE:   $0\n".
	    "          <user/password\@instance> <ac> \n\n".
	    "          <user/password\@instance>\n".
	    "                      where <user/password> is taken automatically from\n".
	    "                      current UNIX session\n".
	    "                      where <\@instance> is either \@enapro or \@devt\n".
	    "                      (production or development databases respectively)\n\n".
    "          <ac>        where ac is one or more accession numbers\n".
    "                      and/or filename(s) of accession numbers\n\n";
         

my @accnos = ();
my @pids   = ();
my $login   ;
my $filename;
for ( my $i = 0; $i < @ARGV; ++$i ) {
    if ( $ARGV[$i] =~ /\/\@\S+/ ) {
	if ((defined($login)) && ($login ne $ARGV[$i])) {
	    die("You seem to be saying two databases, $login and $ARGV[$i]\n".$usage);
	}
	$login = $ARGV[$i];
    } elsif ( $ARGV[$i] =~ /^\b(([A-Z]{1}\d{5})|([A-Z]{2}\d{6})|([A-Z]{4}\d{8,9})|([A-Z]{5}\d{7}))\b(\.\d+)?$/i) {
	push(@accnos, uc($1));
    } elsif ( $ARGV[$i] =~ /^\b(([A-Z]{3}\d{5})|(TPXA_\d{5}))\b(\.\d+)?$/i) {
	push(@pids, uc($1));
    } elsif ( -e($ARGV[$i])) {
	$filename = $ARGV[$i];
    } else {
	print STDERR "$ARGV[$i] is not usable\n";
    } 
}

if (!(defined($login))) { 
    die($usage);
}

if (defined($filename)) {
    if (open(IN,"<$filename")) {
        while ( <IN> ) {
            chomp;
            s/\r//g;
	    my $acc = $_;
	    if ($acc ne '') {
		$acc =~ s/^ACCESSION   ([A-Z]+[0-9]+).*/$1/; # (inadvertantly) ready a Genbank file - take the first token
		$acc =~ s/^AC   ([A-Z]+[0-9]+).*/$1/; # (inadvertantly) ready an EMBL file - take the first token.  NB secondaries taken if line is wrapped
		if ( $acc =~ /^[A-Z]+[0-9]+$/ ) {
		    push ( @accnos, uc($acc) );
		}
	    }
        }
        close ( IN );
    } else {
	print STDERR "Tried and failed to read accessions from $filename\n";
    }
}

main();


sub main {
    # connect to database.
    my %attr   = ( PrintError => 0,
		   RaiseError => 0,
		   AutoCommit => 0 );
    my $database = uc($login);
    $database =~ s/^\/\@//;
    my $dbh = DBI->connect( 'dbi:Oracle:'.$database, '/', '', \%attr )
	|| die "Can't connect to database: $DBI::errstr\n "; 
    $dbh->do(q{ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY'}); 

    if (scalar(@pids) != 0) {
	my %accHash;
	foreach my $pid (@pids) {
	    my $acc = SeqDBUtils2::pid_2_ac($dbh,$pid);
	    if ((defined($acc)) && ($acc ne '')) {
		print "protein_id $pid found in $acc\n";
		$accHash{$acc} = 1;
	    } else {
		print "protein_id $pid NOT FOUND\n";
	    }
	}
	if (scalar (keys %accHash) != 0) {
	    push (@accnos,(keys %accHash));
	}
    }

    if (scalar(@accnos) == 0) {
	print "\naccession number: ";
	chomp ( my $id = <STDIN> );
	push (@accnos, uc($id));
    }
    
    print "\n";
    foreach my $id (@accnos) {
	if ($id =~ /\b(([A-Z]{1}\d{5})|([A-Z]{2}\d{6})|([A-Z]{4}\d{8,9})|([A-Z]{5}\d{7}))\b/) {
# check whether entry exists.
	    my $acc = check_acc ($dbh, $id);
	    
	    if ( !defined $acc ) {
		print STDERR ( "entry $id not found in database\n" );
	    } else {
		display_all ($dbh, $acc);
	    }
	}
    }
    # logout from database
    $dbh->disconnect;
}

sub check_acc {
    my ($dbh, $id) = @_;

    my $sth = $dbh->prepare("SELECT primaryacc# FROM dbentry WHERE primaryacc# = ?");
    $sth->execute($id)
	|| die "database error: $DBI::errstr\n ";

    my ($acc) = $sth->fetchrow_array;
    
    $sth->finish;
    return $acc;
}

sub display_all {
    my ($dbh, $acc) = @_;
    my (@date, @status, @remark, @h_date, @ext_ver, @user);
    
    my $acHeader = "= $acc =";
    printf "%s\n%s\n%s\n", "=" x length($acHeader) , $acHeader, "=" x length($acHeader);

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
    $sth->execute($acc)
	|| die "database error: $DBI::errstr\n ";
    while ( my ( $date, $user, $status, $remark, $h_date, $ext_ver ) = $sth->fetchrow_array) {
	push (@date, $date);
        push (@status, $status);
        push (@remark, $remark);
        push (@h_date, $h_date);
        push (@ext_ver, $ext_ver);
        push (@user, $user);
    }
    $sth->finish;

    my $sql_dbentry_audit = $dbh->prepare("SELECT da.timestamp,
                da.userstamp,
                NVL (cv.status, '-'),
                NVL(remark, '-'),
                NVL ((to_char (hold_date, 'DD-MON-YYYY')), '-'),
                NVL (ext_ver, '0')
           FROM dbentry_audit da left join cv_status cv
             on da.statusid = cv.statusid
          WHERE da.primaryacc# = ?
       ORDER BY da.timestamp desc");
    $sql_dbentry_audit->execute($acc)
	|| die "database error: $DBI::errstr\n ";
    while ( my ( $date, $user, $status, $remark, $h_date, $ext_ver ) = $sql_dbentry_audit->fetchrow_array) {
	push (@date, $date);
        push (@status, $status);
        push (@remark, $remark);
        push (@h_date, $h_date);
        push (@ext_ver, $ext_ver);
        push (@user, $user);
    }
    $sql_dbentry_audit->finish;

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

