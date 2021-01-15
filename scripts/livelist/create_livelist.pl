#!/ebi/production/seqdb/embl/tools/bin/perl 
# filename	: create_livelist.pl
# usage		: $0 -u <username/password\@database>
#                    -m <l|s|k> live|suppressed|killed list mode
#                    -o <output filename> (default: mode.date)
#                    -d <data path> (default: embl production path)
#                    -f <ftp path> (default: private ftp path)
# function      : create live/suppressed/killed entries list.
#                    1) check options
#                    2) db query and write list file in data path
#                    3) move to ftp path
#
# Example output: Same for live, killed and suppressed lists
#FN123457.1|20-APR-2009|943474329|13456,98765
#FN123458.1|20-APR-2009|943474320|
#FN123459.1|20-APR-2009|943474321|88656
#
# changes
# 20081027 mjang    created from livelist.pl, supplist.pl and killlist.pl
#---------------------------------------------------------------------------
use strict;
use warnings;
use Getopt::Std;
use DBI;
use Utils qw(my_open my_close my_system);
use ENAdb;

main();

sub main {
    
    # 1. check option -----------------------------------------------
    my %opt = ();
    getopts('m:d:f:o:u:',\%opt);
    
    my $usage = qq{
      USAGE: $0 -u <username/password\@database> 
                -m <l|s|k> live|suppressed|killed list mode
                -o <output filename> (default: mode.date)
                -d <data path> (default: embl production path)
                -f <ftp path> (default: private ftp path)
      
      PURPOSE: Prints the live|suppressed|killed list to <file>.
      FORMAT: (<primaryacc.seq_ver>|<last public date>|<seq_chksum>|<project id>(,<project id>)*)
      Give valid options.
    };
    
    my ($dblogin, $outfile, $datapath, $ftppath, $condition, $statusid);
    
    my %prefix = ( 'l' => 'embl_livelist.',
                   'k' => 'embl_killlist.',
                   's' => 'embl_supplist.' );

    unless (defined $opt{u} && defined $prefix{$opt{m}}) {
        die $usage;
    }
    $dblogin = $opt{u};
    $outfile  = $opt{o} ? $opt{o} : $prefix{$opt{m}}.`date +"%Y%m%d"`;
    chomp $outfile;    # cut the trailing "\n"
    $datapath = $opt{d} ? $opt{d} : '/ebi/production/seqdb/embl/updates/livelist';
    $ftppath  = $opt{f} ? $opt{f} : '/ebi/ftp/private/embldata/livelist';

    if($opt{m} eq 'l') { # mode live
        $condition = 'd.ext_ver IS NOT NULL AND d.ext_ver != 0 ';
        $statusid = 4;
    }
    else {  # supp and kill
        $condition = 'd.first_public IS NOT NULL ';

        if($opt{m} eq 's') {
            $statusid = 5;    # suppressed
        }
        else {
            $statusid = 6;    # killed
        }
    }
    # 2. write list -----------------------------------------------
    print "$0 -u $dblogin -m $opt{m} -o $outfile -d $datapath -f $ftppath"
           ."\nstarting dbquery at ".`date`;

    $dblogin =~ s/^\/?\@?//;
    my %attr = ( PrintError => 0,
	         RaiseError => 0,
                 AutoCommit => 0 );
    my $dbh = ENAdb::dbconnect($dblogin,%attr);

    my $sth2 = $dbh->prepare("SELECT XREF_ACC FROM ena_xref WHERE ena_xrefid = 'BioProject' AND acc = ?")
	or die("can't prepare projectid subquery \n$DBI::errstr\n\n"); 

    eval{ # if the list writing fails, the program dies -------------
        my ($primaryacc, $date, $seqacc, $seqver, $chksum);
        my $sth = $dbh->prepare (
          qq{ SELECT d.primaryacc#,
               b.seq_accid,
               b.version,
               DECODE ( d.ext_date,
                    NULL, TO_CHAR ( d.first_public, 'DD-MON-YYYY' ),
                          TO_CHAR ( d.ext_date,     'DD-MON-YYYY' ) ),
               b.chksum
              FROM dbentry d, bioseq b
              WHERE b.seqid = d.bioseqid
              AND d.dbcode = 'E'
              AND d.statusid = ?
              AND $condition
              AND b.bioseqtype = 0
              ORDER BY d.primaryacc# } )
	or die("can't prepare main query \n$DBI::errstr\n\n");

        $sth->execute($statusid)
 	or die("can't execute main query \n$DBI::errstr\n\n");

        $sth->bind_columns(\$primaryacc, \$seqacc, \$seqver, \$date, \$chksum);

        my $fh = my_open(">$datapath/$outfile");

        while ($sth->fetch) {

            if (!defined $date) {
                $date = "";
            }

            # NB There may be more than one projectid per entry
            $sth2->execute($primaryacc);

            my $projectid_string = "";
            while(my $projectid = $sth2->fetchrow_array()) {
                $projectid_string .= "$projectid,";
            }
            if ($projectid_string =~ /,$/) {
                chop($projectid_string);
            }

            print $fh "$primaryacc.$seqver|$date|$chksum|$projectid_string\n";
        }
        $sth->finish;
        my_close($fh);
    };

    if ($@) {
        die "ERROR: $@";
    }

    $dbh->disconnect  or die("can't disconnect to Oracle \n$DBI::errstr\n\n");

    # 3. move to ftp path -------------------------------------------
    chmod(0644, "$datapath/$outfile");
    my_system("mv $datapath/$outfile $ftppath/$outfile");

    print "$0 -u $dblogin -m $opt{m} finished at ".`date`;
}
