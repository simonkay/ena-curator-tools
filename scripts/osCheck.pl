#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# osCheck.pl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/osCheck.pl,v 1.11 2011/11/29 16:33:38 xin Exp $
#
#  DESCRIPTION:
#
#  reads a file that contains organism names (1 per line) and
#  checks that they are known proper scientific names.
#
#  MODIFICATION HISTORY:
#
#  03-OCT-2003 Nadeem Faruque   Created
#  06-OCT-2003 Nadeem Faruque   Now checks classification is to species level
#                               and looks for cyanobacteria
#  01-NOV-2007 Nadeem Faruque   Wildcards non-word OS names
#
#===============================================================================

use strict;
use DBI;
use dbi_utils;
use SeqDBUtils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage =
  "\n PURPOSE: Checks a list of organism names in a text file\n"
  . "          to ensure that they are known scientific names.\n\n"
  . " USAGE:   $0\n"
  . "          [user/password\@instance] [-h] filename\n\n"
  . "   <user/password\@instance>\n"
  . "                   where <user/password> is taken automatically from\n"
  . "                   current unix session\n"
  . "                   where <\@instance> is either \@enapro or \@devt\n"
  . "                   (\@enapro by default)\n\n"
  . "   -q(uiet)        quiet output\n\n"
  . "   -v(erbose)      verbose\n\n"
  . "   -h              shows this help text\n\n";

my $login    = "";
my $quiet    = 0;
my $test     = 0;
my $verbose  = 0;
my $fileName = "";

if (@ARGV > 0) {
    ($ARGV[0] !~ /^-h/i) || die $usage;
    $login = $ARGV[0];

    for (my $i = 0 ; $i < @ARGV ; ++$i) {
        if ($ARGV[$i] =~ /^-q(uiet)?/) {
            $quiet = 1;
        } elsif ($ARGV[$i] =~ /^-v(erbose)?/) {
            $verbose = 1;
        } elsif (!($ARGV[$i] =~ /^-/)) {
            $fileName = $ARGV[$i];
        } else {
            die ($usage);
        }
    } ## end for (my $i = 0 ; $i < @ARGV...
} ## end if (@ARGV > 0)

((-r $fileName) and (-f $fileName))
  or die "File \"$fileName\" not found\n";

my %badOrganismHash;    # Key - organism name=>
my %badNameHash;        # Key - organism name=>
my %osListHash;         # Key - organism name=>taxid

if ($login eq "/\@devt") {
    $test = 1;
}
$quiet and open(STDERR, "> /dev/null");

open(FILE, $fileName)
  || die ("Cannot open cannot $fileName\n");
$quiet or print "Reading from file $fileName\n";

while (defined(my $organism = <FILE>)) {
    $organism =~ s/(^\s+)|(\s+$)//sg;
    next if ($organism eq "");
    $osListHash{$organism} = 0;
    $quiet or print "$organism\n";
}
close(FILE);

#  Taxonomy queries accessing oracle
die if (check_environment($test, $login) == 0);
my $dbh = dbi_ora_connect($login)
  or die "Can't connect to database: $DBI::errstr";

my $sql       = $dbh->prepare("SELECT tax_id FROM ntx_synonym WHERE upper_name_txt = upper(?) group by tax_id");
my $sql_loose =
  $dbh->prepare(
    "SELECT l.tax_id, l.leaf FROM ntx_synonym s, ntx_lineage l WHERE s.upper_name_txt LIKE upper(?) and l.tax_id = s.tax_id and rownum < 200 group by l.tax_id, l.leaf"
  );

# Match /organism names with Tax_ID's
foreach my $organismFromList (keys %osListHash) {
    my $osForSearching = $organismFromList;
    $osForSearching =~ s/ {2,}/ /g;
    $sql->execute(uc($osForSearching)) || die ("query failed with message " . $DBI::errstr . "\n");
    my ($result) = $sql->fetchrow_array();
    if (defined($result)) {
        $osListHash{$organismFromList} = $result;
    } else {
	if ($verbose) {
	    print "Search failed with query:\n"
		. $sql->{Statement}."\n";
	    print "params:\n"
		. join("\n",(values %{$sql->{ParamValues}}))."\n";
	}
        $osForSearching =~ s/\W+/%/g;
        $verbose and print "now trying $osForSearching\n";
        my @candidateList;
        $sql_loose->execute(uc($osForSearching)) || die ("query failed with message " . $DBI::errstr . "\n");
        my $osForFilteringResults = quotemeta($osForSearching);
        $osForFilteringResults =~ s/\W+/\\W*/g;
        $verbose && print " filtering for matches to \"$osForFilteringResults\"\n";

        while (my (@resultRow) = $sql_loose->fetchrow_array()) {
            if ($resultRow[1] =~ /^$osForFilteringResults$/i) {
                push (@candidateList, \@resultRow);
            }
        }
        $verbose
          && print "! Degenerate search $osForSearching returned " . scalar(@candidateList) . " entr" . (scalar(@candidateList) == 1 ? "y" : "ies") . "\n";
        if (scalar(@candidateList) > 1) {
            if (scalar(@candidateList) < 50) {
                print "  \"" . join ("\"\n  \"" . @candidateList) . "\"\n";
            } else {
                print " too many to list\n";
            }
        } elsif (scalar(@candidateList) == 1) {
            $sql_loose->execute(uc($osForSearching)) || die ("query failed with message " . $DBI::errstr . "\n");
            $osListHash{$organismFromList} = $candidateList[0][0];
        } else {
	    if ($verbose) {
            # could make a looser search such as wildcarding ends and then vowels
		print "Search failed with second query:\n\n"
		    . $sql_loose->{Statement}."\n";
		print "params:\n"
		    . join("\n",(values %{$sql_loose->{ParamValues}}))."\n";
	    }
        }
    } ## end else [ if (defined($result))

    if ($osListHash{$organismFromList} == 0) {
        $verbose
          and print $osListHash{$organismFromList} . " UNKNOWN\n";
        $badOrganismHash{$organismFromList} = " UNKNOWN";
    } elsif ($osListHash{$organismFromList} < 0) {
        $verbose
          and print $osListHash{$organismFromList} . " in database but unclassified\n";
        $badOrganismHash{$organismFromList} = " in database but unclassified";
    }
} ## end foreach my $organismFromList...

# Check /organism names are the scientific names and check
foreach my $organismFromList (keys %osListHash) {
    if ($osListHash{$organismFromList} > 0) {
        my @taxInfo = ascendTaxTree($osListHash{$organismFromList});

        $verbose
          and print $osListHash{$organismFromList} . "\n"
          . "species level or below $taxInfo[0]\n"
          . "cyanobacterium $taxInfo[1]\n"
          . "Scientific Name $taxInfo[2]\n"
          . "Taxonomy $taxInfo[3]\n\n";
        if ($organismFromList ne $taxInfo[2]) {
            $badNameHash{$organismFromList} .= "! \"$organismFromList\" should be \n\"$taxInfo[2]\"\n\n";
        }
        if ($taxInfo[0] != 1) {
            $badNameHash{$organismFromList} .= "! \"$organismFromList\" is not classified to the species level\n"
              . "  http://www.ncbi.nlm.nih.gov/Taxonomy/protected/wwwtax.cgi?mode=Undef&id="
              . $osListHash{$organismFromList} . "\n\n";
        }
        if ($taxInfo[1] == 1) {
            $badNameHash{$organismFromList} .= "! \"$organismFromList\" is a cyanobacterium, currently we need to check these\n\n";
        } elsif ($taxInfo[2] eq 'Drosophila pseudoobscura') {
	    $badNameHash{$organismFromList} .= "! \"$taxInfo[2]\" should be taken to the sub-species level\n\n";
	} elsif ($taxInfo[2] eq 'Oryza sativa') {
	    $badNameHash{$organismFromList} .= "! \"$organismFromList\" should be taken to a more specific tax node, eg \"Oryza sativa Indica Group\"\n\n";
	}
	    

    } ## end if ($osListHash{$organismFromList...
} ## end foreach my $organismFromList...

dbi_logoff($dbh);

foreach my $organismFromList (sort keys %badOrganismHash) {
    print "? \"$organismFromList\" " . $badOrganismHash{$organismFromList} . "\n\n";
}
foreach my $organismFromList (sort keys %badNameHash) {
    print $badNameHash{$organismFromList};
}
if ((scalar(keys %badNameHash) + (scalar(keys %badOrganismHash))) == 0) {
    my $plural = "s";
    if (scalar(keys %osListHash) == 1) {
        $plural = "";
    }
    print "Taxonomy OK found for the " . scalar(keys %osListHash) . " organism$plural\n";
}
exit;

# ascendTaxTree used to have to ascend parent nodes to gain info, now it just reads ntx_lineage
sub ascendTaxTree {
    my $tax_id         = shift;
    my $cyano          = 0;
    my $scientificName = "";
    my $lineage        = "";
    my $species        = "";
    my $isSpecies      = 0;
    my $sth = $dbh->prepare(
        q{SELECT lineage, nvl(species, '-'), leaf
				  FROM  ntx_lineage
				  WHERE tax_id = ?
			      });
    $sth->execute($tax_id) || die ("query failed with message " . $DBI::errstr . "\n");
    ($lineage, $species, $scientificName) = $sth->fetchrow_array;
    if ($lineage =~ /^Bacteria; Cyanobacteria/) {
        $cyano = 1;
    }
    if ($species ne "-") {
        $isSpecies = 1;
    }
    return ($isSpecies, $cyano, $scientificName, $lineage);
} ## end sub ascendTaxTree
