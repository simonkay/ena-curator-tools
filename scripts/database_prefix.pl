#!/ebi/production/seqdb/embl/tools/bin/perl -w
use strict;
use DBI;
use Getopt::Long;
use CGI;
use ENAdb;

my $embl    = 0;
my $ncbi    = 0;
my $ddbj    = 0;
my $patents = 0;
my $wgs     = 0;
my $prefix  = "";
my $filter  = "";
my $login;
my $html_out; # normally /ebi/extserv/seqdb/internal/seqdb/curators/guides/embl_prefix.html
my $wgs_url = "<a href=\"http://srs.ebi.ac.uk/srsbin/cgi-bin/wgetz?-newId+-e+[EMBLWGSMASTERS:%s00000000]\">%s</a>";

# timeDayDate # produces a nicely formatted time + date string
sub timeDayDate {
    my $thisTime;
    my $minutePadding = "";
    if ( (localtime)[1] < 10 ) {
        $minutePadding = "0";
    }
    if ( (localtime)[2] > 12 ) {
        $thisTime = ( (localtime)[2] - 12 ) . ":" . $minutePadding . (localtime)[1] . "pm";
    }
    else {
        $thisTime = (localtime)[2] . ":" . (localtime)[1] . "am";
    }
    my $thisDay = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" )[ (localtime)[6] ];
    my $thisDate =
        ( (localtime)[3] ) . "-"
      . ( "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" )[ (localtime)[4] ] . "-"
      . ( (localtime)[5] + 1900 );
    return "$thisTime $thisDay $thisDate";
}

my $usage = "\n PURPOSE: Query the database prefixes\n\n"
          . " USAGE:   $0\n"
          . "          </\@instance> [<prefix>] [-f(ilter)=<text>)[-n(cbi)] [-d(dbj)] [-e(mbl)] [-pat(ents)] [-w(gs)]\n\n"
          . "          </\@instance>    defaults to PRDB1 if not stated\n"
          . "          -f=<text>        Filters for text in the desciption\n"
          . "          <prefix>         uppercase prefix (or accession)\n"
          . "          -d(dbj)          show ddbj entries (default = all database)\n" 
          . "          -e(mbl)          show embl entries (default = all database)\n" 
          . "          -n(cbi)          show ncbi entries (default = all database)\n" 
          . "          -p(atents>       show just prefixes for patents\n"
          . "          -w<gs>           show just prefixes for WGS\n" 
          . "          -h(html)=<file>  saves prefixes table in html format\n\n";

GetOptions( "ncbi!"         => \$ncbi,
	    "genbank!"      => \$ncbi,
	    "ddbj!"         => \$ddbj,
	    "embl!"         => \$embl,
	    "patents!"      => \$patents,
	    "filter=s"      => \$filter,
	    "html=s"        => \$html_out,
	    "wgs!"          => \$wgs) || die($usage);

#$html_out && open(STDERR, "> /dev/null");

foreach my $arg (@ARGV) {
    if ($arg =~ /^(([A-Z]{1,2})|([A-Z]{3,5}))([0-9]{5,})?$/) {
	if ($prefix eq '') {
	    $prefix = $1;
	}  
    } elsif ( $arg =~ /\/\@\S+/ ) {
	if ((defined($login)) && ($login ne $arg)) {
	    die("You seem to be saying two databases, $login and $arg\n".$usage);
	}
	$login = $arg;
    } else {
	if ($filter eq '') {
	    $filter = $arg;
	} else {
	    $filter .= " $arg";
	} 
    }
}

if ($filter ne '') {
    $filter = "%" . $filter . "%";
}

if ($wgs == 1) {
    if ($filter ne '') {
	$filter = "WGS - ". $filter;
    } else {
	$filter = "WGS - %";
    }
}

if (!(defined($login))) {
    $login = "/\@enapro";
}

my $database = uc($login);

my %attr   = ( PrintError => 0,
	       RaiseError => 0,
               AutoCommit => 0 );

my $dbh = ENAdb::dbconnect($database,%attr)
    || die "Can't connect to database: $DBI::errstr";

my @wheres = ();
my @params = ();

my @databases = ();
$embl && push (@databases, "'E'");
$ncbi && push (@databases, "'G'");
$ddbj && push (@databases, "'D'");
if ((scalar(@databases) == 1) || (scalar(@databases) == 2))  {
    push (@wheres, "dbcode in (".join(',',@databases).")");
}
if ($filter ne "") {
    push (@wheres, "upper(entry_type) LIKE upper(?)");
    push (@params, $filter);
}
if ($patents) {
    push (@wheres, "dataclass = 'PAT'");
}
if ($prefix) {
    push (@wheres, "prefix = ?");
    push (@params, $prefix);
}


my $query = "SELECT prefix, dbcode, DECODE(dataclass,'PAT', 'P', '   '), nvl(entry_type,'no description')\n"
    . "  FROM cv_database_prefix \n";
if (scalar(@wheres) != 0) {
    $query .= " WHERE ". join("\n   AND ", @wheres) ."\n";
}
$query .= "ORDER BY length(prefix), prefix\n";

my $sth = $dbh->prepare($query) || die "database prepare error: $DBI::errstr\n ";

$sth->execute(@params) || die "database execute error: $DBI::errstr\n ";


my $html;
my $cgi;

if ($html_out) {
    open ($html, ">$html_out") || die "Could not open $html_out for writing: $!";
    $cgi = new CGI;
    print $html $cgi->start_html(-title=>'EMBL Accession Prefixes');
    print $html $cgi->start_table({-width=>'80%', -border=>'1'}), "\n\n";
    print $html "<tr><th align=\"right\">Prefix</th><th align=\"center\">DB</th><th>Patent?</th><th>Description</th></tr>\n";
} else {
    printf "%-6s %2s %3s %s\n", "PREFIX", "DB", "PAT", "Description";
    printf "%-6s %2s %3s %s\n", "======", "==", "===", "===========";
}
while ( my ( $result_prefix, $result_db, $result_pat, $result_desc) = $sth->fetchrow_array) {
    $result_desc =~ s/\s*$//s;
    if ($html_out) {
	my $bgcolor = "#F0FFF0";
	if ($result_db eq "G") {
	    $bgcolor = "#F0F0FF";
	    $result_db = "GenBank";
	} elsif ($result_db eq "D") {
	    $bgcolor = "#FFF0F0";
	    $result_db = "DDBJ";
	} else {
	    $result_db = "EMBL/ENA";
	}
	    
	if ($result_pat eq 'P') {
	    $result_pat = "patent";
	    $bgcolor =~ s/F0/E6/g;
	    $bgcolor =~ s/FF/EF/g;
	} else {
	    $result_pat = "&nbsp;";
	}
	$result_desc = CGI::escapeHTML($result_desc);
	if ($result_desc =~ /^WGS /) {
	    $result_prefix = sprintf $wgs_url, $result_prefix,$result_prefix;
	}
	if ($result_desc =~ /^\s*$/) {
	    $result_desc = "&nbsp;";
	}
	printf $html "<tr bgcolor=\"%s\"><td align=\"right\"><tt><b>%s</b></tt></td><td align=\"center\">%s</td><td>%s</td><td>%s</th></tr>\n"
	    , $bgcolor, $result_prefix, $result_db, $result_pat, $result_desc;
	
    } else {
	printf "%-6s %2s %3s %s\n", $result_prefix, $result_db, $result_pat, $result_desc;
    }
}
$sth->finish; 
$dbh->disconnect();


if ($html_out) {
    print $html $cgi->end_table 
	. "\n\n<p><font size =\"-2\">Page generated " . timeDayDate() . "</font></p>\n"
	. $cgi->end_html;
    close ($html);
    print STDERR "$html_out has been recreated\n";
}

 
