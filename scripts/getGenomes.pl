#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2003
#
#  SCRIPT DESCRIPTION:
#
#  Genome sequence entry info retriever and webpage maker
#
#  MODIFICATION HISTORY:
#
# $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/getGenomes.pl,v $
# $Date: 2015/08/12 14:27:06 $
# $Author: rasko $
#
#===============================================================================

use DBI;
use strict;
use LWP::Simple;
use LWP::UserAgent;
use File::Find;
use Net::FTP;
use File::Listing qw(parse_dir);
use Storable;
use Storable qw(nstore store_fd nstore_fd freeze thaw dclone);
use SeqDBUtils2;
use LWP::Simple;   # uniprot scraping
use LWP::UserAgent; # uniprot scraping
$| = 1;    # unbuffered output

umask(003);

my $testing = 0;    ###### global to save to different directory and to stop it synching with evo-1
my $distrust_cached_protein_count_below_cds_ratio = 0.01; # by default, we are happy 1% of CDSs are in cached UniProt data, esle we ask UniProt again
my $distrust_cached_protein_count_above_cds_ratio = 0.000001; # permits us to refresh a selected range
my $distrust_cached_protein_count_of_zero = 0;
my $distrustCount = 0;
my $distrustFraction = 0;
my $distrustUsefulCount = 0;
my $distrustUsefulRatio = 0;
my $distrustUnusefulCount = 0;
my $distrustUnusefulRatio = 0;
my $distrustZeroCountUsefulCount = 0;
my $distrustZeroCountUnusefulCount = 0;
my $webDir = "/ebi/production/seqdb/embl/data/genomes_web_page_files";    # for output directory
if ($testing) {
    $webDir = "/ebi/production/seqdb/embl/data/genomes_web_page_files_test";    # for output directory
}
my $homeDir           = "/ebi/production/seqdb/embl/tools/curators/data/getGenomesData/";
my $dataInDir         = $homeDir;
my $dataOutDir        = $homeDir;
my $getGenomesLogTEMP = $webDir . "/getGenomesTEMP.html";
my $getGenomesLog     = $webDir . "/getGenomes.html";
my $notQuiet           = 1;
my $fullRun           = 1;
my $fullRunNewFastas  = 0;

my $karynsGenomesUrl = "http://www.ebi.ac.uk/2can/genomes/";

my $enaBrowserUrl      = "http://www.ebi.ac.uk/ena/data/view/";

my $enaBrowserArgConff = "&expanded=true";
my $enaBrowserArgNonConff = "&expanded=false";
my $enaBrowserArgHtml  = "";    # currently the default, else we must use "&display=html";
my $enaBrowserArgText  = "&display=txt";

my $uniprotBrowserHtml1  = "http://www.uniprot.org/uniprot/?query=database%3A%28type%3Aembl+";
my $uniprotBrowserHtml2  = "%29";
my $uniprotBrowserFasta1 = "http://www.uniprot.org/uniprot/?query=database%3A%28type%3Aembl+";
my $uniprotBrowserFasta2 = "%29&format=fasta";

########################################################
# Subroutines (prototyped)
########################################################


sub makeLink($$;$) {
    my $url   = shift;
    my $text  = shift;
    my $target= shift;
    if (defined($target)) {
	$target = "target=\"$target\"";
    } else {
	$target = "";
    }
    return("<a $target href=\"$url\">$text</a>");
}

sub makeEntryLinkWGSmaster($$) {
    my $entryAc  = shift;
    my $linkText = shift;
    my $url = $enaBrowserUrl . $entryAc . $enaBrowserArgHtml;
    return(makeLink($url,$linkText));
}

sub makeEntryLinkProject($$) {
    my $entryAc  = shift;
    my $linkText = shift;
    my $url = $enaBrowserUrl . "Project:" . $entryAc;
    return(makeLink($url,$linkText,"magpiWindow"));
}

sub makeEntryLinkTaxonomy($$) {
    my $entryAc  = shift;
    my $linkText = shift;
    my $url = $enaBrowserUrl . "Taxon:" . $entryAc;
    return(makeLink($url,$linkText,"taxWindow"));
}

sub makeEntryLinkStandard($$) {
    my $entryAc  = shift;
    my $linkText = shift;
    my $url = $enaBrowserUrl . $entryAc . $enaBrowserArgHtml;
    return(makeLink($url,$linkText));
}

sub makeEntryLinkNonExpanded($$) {
    my $entryAc  = shift;
    my $linkText = shift;
    my $url = $enaBrowserUrl . $entryAc . $enaBrowserArgText . $enaBrowserArgNonConff;
    return(makeLink($url,$linkText));
}

sub makeEntryLinkCOLines($$) {
    my $entryAc  = shift;
    my $linkText = shift;
    my $url = $enaBrowserUrl . $entryAc . "#Contig_" . $entryAc;
    return(makeLink($url,$linkText));
}

sub makeEntryLinkText($$) {
    my $entryAc  = shift;
    my $linkText = shift;
    my $url = $enaBrowserUrl . $entryAc . $enaBrowserArgText;
    return(makeLink($url,$linkText));
}

sub makeEntryLinkTextExpanded($$) {
    my $entryAc  = shift;
    my $linkText = shift;
    my $url = $enaBrowserUrl . $entryAc . $enaBrowserArgText . $enaBrowserArgConff;
    return(makeLink($url,$linkText));
}

sub makeEntryLink($$;$) {
    my $entryAc  = shift;
    my $linkType = shift;
    my $linkText = shift;
    if (!(defined($linkText))) {
	$linkText = $entryAc;
    }
    if ((!(defined($linkType))) || ($linkType eq '')) {
	$linkType = 'default';
    }

    if ($linkType eq 'WGSmaster') {
	return( makeEntryLinkWGSmaster($entryAc,$linkText));
    } elsif ($linkType eq 'Project') {
	return( makeEntryLinkProject($entryAc,$linkText));
    } elsif ($linkType eq 'Taxonomy') {
	return( makeEntryLinkTaxonomy($entryAc,$linkText));
    } elsif ($linkType eq 'text') {
	return (makeEntryLinkText($entryAc,$linkText));
    } elsif ($linkType eq 'text-expanded') {
	return (makeEntryLinkTextExpanded($entryAc,$linkText));
    } elsif ($linkType eq 'non-expanded') {
	return (makeEntryLinkNonExpanded($entryAc,$linkText));
    } elsif ($linkType eq 'co-block') {
	return (makeEntryLinkCOLines($entryAc,$linkText));
    } elsif ($linkType eq 'default') {
	return (makeEntryLinkStandard($entryAc,$linkText));
    } else {
	die "cannot make link for $entryAc for unknown linktype of $linkText\n";
    }
}


sub makeMagpiLinkString($) {
    my $mapiIDs = shift;
    my $magpiString = "";
    my $joinString = ""; # we need to use a comma before the url except for the first
    if (defined($mapiIDs) &&
	defined(@{$mapiIDs}) &&
	(scalar(@{$mapiIDs}) > 0)) {
	foreach my $magpiid (@{$mapiIDs}) {
	    $magpiString .= $joinString . makeEntryLink($magpiid,'Project');
	    $joinString = ", ";
	}
    }
    return ($magpiString);
}




my $totalEntryCount = 0;
my $segmentCount    = 0;
my $verbose         = 0;

# default - call SRS for protein counts when the sequence version is new
#  1 = also call for entries in the cache with 0 protein counts
#  2 = call for all - ignore cached info

# Sequence types
#  0 = regular entries
#  1 = database CONs
#  2 = TPA
#  3 = WGS
#  4 = ANN (annotated CONs
# 97 = default for unknown manual entries - should be unused
# 98 = ENSEMBL
# 99 = manual CONs

my %genomeCategories;
my $usage =
    " PURPOSE: Generate genomes web pages\n"
  . " USAGE:  $0 [-division] [-cds=[n-]n] [-zerocds] [-h]\n"
  . "   -division  The division to be analysed (default = all)\n"
  . "              Where the division is one of archaea, bacteria, eukaryota,\n"
  . "              organelle, phage, archaealvirus, plasmid, viroid or virus.  \n"
  . "              Multiple divisions may be given, eg\n"
  . "               $0 -virus -bacteria \n"
  . "   -cds       The minimum proportion of CDS found in cached UniProt protein counts\n"
  . "              default is $distrust_cached_protein_count_below_cds_ratio\n"
  . "              If range is given, it wil be used\n"
  . "   -zerocds   Check UniProt if cached count is zero (default is no)\n"
  . "   -h         shows this help text\n";

for ( my $i = 0 ; $i < @ARGV ; ++$i ) {
    $ARGV[$i] = lc( $ARGV[$i] );
    $ARGV[$i] =~ s/^\-//;
    if ( $ARGV[$i] eq "archaea" ) {
        $genomeCategories{4} = "archaea";
    }
    elsif ( $ARGV[$i] eq "bacteria" ) {
        $genomeCategories{5} = "bacteria";
    }
    elsif ( $ARGV[$i] eq "eukaryota" ) {
        $genomeCategories{6} = "eukaryota";
    }
    elsif ( $ARGV[$i] eq "organelle" ) {
        $genomeCategories{3} = "organelle";
    }
    elsif ( $ARGV[$i] eq "phage" ) {
        $genomeCategories{12} = "phage";
    }
    elsif ( $ARGV[$i] eq "archaealvirus" ) {
        $genomeCategories{13} = "archaealvirus";
    }
    elsif ( $ARGV[$i] eq "plasmid" ) {
        $genomeCategories{7} = "plasmid";
    }
    elsif ( $ARGV[$i] eq "viroid" ) {
        $genomeCategories{8} = "viroid";
    }
    elsif ( $ARGV[$i] eq "virus" ) {
        $genomeCategories{2} = "virus";
    }
    elsif ( $ARGV[$i] =~ /^v(erbose)?$/ ) {
        $verbose = 1;
    }
    elsif ( $ARGV[$i] =~ /^cds=([0-9\.]+)-([0-9\.]+)$/ ) {
	$distrust_cached_protein_count_above_cds_ratio = $1;
        $distrust_cached_protein_count_below_cds_ratio = $2;
    }
    elsif ( $ARGV[$i] =~ /^cds=([0-9\.]+)$/ ) {
        $distrust_cached_protein_count_below_cds_ratio = $1;
    }
    elsif ( $ARGV[$i] =~ /^z(erocds)?$/ ) {
        $distrust_cached_protein_count_of_zero = 1;
    }
    else { die( "I don't understand $ARGV[$i]\n".$usage); }
}


lockFile("make");

$notQuiet && print STDERR  "\nRunning getGenomes.pl for " . $ENV{'USER'} . "\n";
$notQuiet && print STDERR "\nConnecting to database ENAPRO...\n";

my $dbh = DBI->connect( 'dbi:Oracle:ENAPRO', '/', '' ) or 
    do {
        print "Can't execute statement: $DBI::errstr";
        return;
    };

open LOG, ">$getGenomesLogTEMP"
  || die "Can't create file: $getGenomesLogTEMP";
print LOG "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\">\n"
  . "<html><head><title>getGenomes problems</title></head>\n"
  . "<body><h2>getGenomes problems "
  . timeDayDate("timedaydate")
  . "</h2>\n";

my %karynsGenomesLocations;
findKarynsGenomes( \%karynsGenomesLocations );
$notQuiet
  and print STDERR commify( scalar( keys %karynsGenomesLocations ) ) . " Karyn's Genomes links found\n\n";
if ( scalar( keys %karynsGenomesLocations ) == 0 ) {
    print "Cannot query for Karyn's Genomes links links, using cached data $homeDir/karynsGenomesLocations.stored\n";
    if ( -e "$homeDir/karynsGenomesLocations.stored" ) {
        %karynsGenomesLocations = %{ retrieve("$homeDir/karynsGenomesLocations.stored") };
        $notQuiet
          and print STDERR commify( scalar( keys %karynsGenomesLocations ) ) . " cached karynsGenomesLocations read\n";
    }
    else {
        print "$homeDir/karynsGenomesLocations.stored not found, quitting\n";
        lockFile("remove");
        exit 0;
    }
}
store( \%karynsGenomesLocations, "$homeDir/karynsGenomesLocations.stored" );

# Write the 'static' pages from the bodies of ones in the datadirectory
$notQuiet
  and print "Using the html files in $homeDir to make the full equivalent pages for the divisions\n\n";
writeOutput( "index", "at the EBI",                   "", 0, 0, 0, 0, 0, 0, 0 );
writeOutput( "wgs",   "Whole Genome Shotgun entries", "", 0, 0, 0, 0, 0, 0, 0 );
writeOutput( "help",  "help",                         "", 0, 0, 0, 0, 0, 0, 0 );
my %cachedInfo;

#####################
# get proteinCountCache
if ( -e "$dataOutDir/proteinCounts.stored" ) {
    $notQuiet
      and print "Reading $dataOutDir/proteinCounts.stored\n";
    %cachedInfo = %{ retrieve("$dataOutDir/proteinCounts.stored") };
    $notQuiet
      and print commify( scalar( keys %cachedInfo ) ) . " cached proteinCounts read\n";
}
else {
    print "Cannot find protein count info file $dataOutDir/proteinCounts.stored\n";
}

do_getGenomes();

#####################
# store proteinCountCache
$notQuiet
  and print commify( scalar( keys %cachedInfo ) ) . " proteinCounts stored\n";
nstore( \%cachedInfo, "$dataOutDir/proteinCounts.stored" );

#my $mailHeader = "content-type: text/html; charset=\"iso-8859-1\"\n".
#    "Reply-To: nimap@ebi.ac.uk, xin@ebi.ac.uk\n".
#    "nimap@ebi.ac.uk, xin@ebi.ac.uk\n".
#    "Subject: getGenomes error log\n";

lockFile("remove");

# ungainly use of mailheaders for 3 different users, should probably write this on-the-fly
# note the mail is not a multi-part message in MIME format, just a html stuck in the mail - works in AppleMail and Thunderbird, not Sqirrelmail
my $mailheader = "$homeDir/mailheader.txt";
if ( -e "$homeDir/mailheader_" . $ENV{'USER'} . ".txt" ) {
    $mailheader = "$homeDir/mailheader_" . $ENV{'USER'} . ".txt";
    print "mailing log to " . $ENV{'USER'} . "\n";
}
system("cat $mailheader $getGenomesLog |  /usr/sbin/sendmail -t");
print "I mailed $getGenomesLog\n$totalEntryCount total entries\n$segmentCount segments\n";
$dbh->disconnect;
exit();

########################################################
# Subroutines (non-prototyped)
########################################################

# Lockfile #
# mediates the creation/destruction of the lock file
sub lockFile {
    my $action   = shift;
    my $lockFile = "$homeDir/lockFile";
    if ($testing) {
        $lockFile .= "_testing";
    }
    if ( $action eq "make" ) {
        if ( -e "$lockFile" ) {
            open LOCK, "<$lockFile"
              or die "$lockFile exists already but cannot read!\n";
            my $existingLock = do { local $/; <LOCK> };
            chomp($existingLock);
            die "$lockFile exists:-\n \"$existingLock\"\n" . "is someone else updating?\n";
        }
        else {
            open LOCK, ">$lockFile"
              or die "Can't create $lockFile file: $!";
            print LOCK "Update started " . timeDayDate("timedaydate"). " by user $ENV{'USER'}\n";
            close LOCK;
        }
    }
    else {
        unlink("$lockFile");
    }
    return 1;
}

# getCachedInfo # gets cached data for each AC.entryversion (if present)
sub getCachedInfo {
    if ( -e $dataOutDir . "/cachedInfo" ) {
        $notQuiet and print "Reading cached data file of protein counts $dataOutDir/cachedInfo\n";
        open CACHEFILE, "$dataOutDir/cachedInfo"
          or die $dataOutDir . "/cachedInfo exists but is unreadable\n";
        while (<CACHEFILE>) {
            chomp( my $lineIn = $_ );
            if ( !( $lineIn =~ /^\s+$/ ) && !( $lineIn =~ /^\#/ ) ) {
                $lineIn =~ s/ *\t */\t/g;
                my @lineInArray = split /\t/, $lineIn;
                if ( defined( $lineInArray[0] ) ) {
                    if ( defined( $lineInArray[1] ) ) {
                        $cachedInfo{ $lineInArray[0] }{PROTEINCOUNT} = $lineInArray[1];
                    }
                }
            }
        }
        close CACHEFILE;
    }
    else {
        print "No cache file $dataOutDir/cachedInfo creating protein count afresh\n";
    }
}

# writeCachedInfo # gets cached data for each AC.entryversion (if present)
sub writeCachedInfo {
    open CACHEFILE, ">$dataOutDir/cachedInfo";
    $notQuiet and print "Writing cached data file $dataOutDir/cachedInfo\n";
    foreach my $acNumber ( sort keys %cachedInfo ) {
        if ( defined( $cachedInfo{$acNumber}{PROTEINCOUNT} ) ) {
            print CACHEFILE $acNumber . "\t" . $cachedInfo{$acNumber}{PROTEINCOUNT} . "\n";
        }
    }
    close CACHEFILE;
}

# commify # adds commas to delimit thousands in numbers
sub commify {
    local $_ = shift;
    1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
    return $_;
}

# deTrim # Removes some redundant text from the end of sequence descriptions
sub deTrim {
    my $string = shift;
    $string =~ s/, complete genome//i;
    $string =~ s/ of the Complete Nucleotide Sequence\.?//i;
    $string =~ s/ from chromosome 14 of Homo sapiens \(Human\)//i;
    $string =~ s/( genomic sequence)?,?( of the)?\s*(complete( plasmid)? \w+)?\.?$//i;
    $string =~ s/,? (whole)|(complete) (genome)|(sequence)( shotgun)?.?//i;
    return $string;
}

sub scrapeProteinCountFromUniProt {
    my $acNumber = shift;
    $acNumber =~ s/\.[0-9]*//; # strip dot version
    my $url = "http://www.uniprot.org/uniprot/?query=database%3A%28type%3Aembl+".$acNumber."%29&format=list";
    #print " asking for protein count from $url\n";
    return `/usr/bin/curl -s  \'$url\'|wc -l`; 
}

sub getCDScount {
    my $acNumber = shift;
    $acNumber =~ s/\.[0-9]*//; # strip dot version
    my $sth = $dbh->prepare(
	q{ SELECT count(*) 
             FROM cdsfeature 
            WHERE acc = ?
              AND seqlen > 1 -- may help to ignore some pseudo
         }
        ); 
# would need to do this to ignore pseudo CDSs
#   and not exists (select 1
#                     from feature_qualifiers q
#                    where q.featid = c.featid
#                      and q.fqualid = 28 -- pseudo
#                  )
    $sth->execute($acNumber);
    if (my ($cdsCount) = $sth->fetchrow_array()) {
	return $cdsCount;
    }
    print " No CDS count value returned for $acNumber\n";
    return 0;
}
    
sub newProteinCount {
    my $acNumberAndVersion = shift;
    $cachedInfo{$acNumberAndVersion}{PROTEINCOUNT} = scrapeProteinCountFromUniProt($acNumberAndVersion);
    return $cachedInfo{$acNumberAndVersion}{PROTEINCOUNT};
}

sub distrustCachedProteinCount($$) {
    my $cdsCount = shift;
    my $cachedCount = shift;

    if($cdsCount == 0) {
	return 0;
    } 
    my $fractionInUniProt = $cachedCount / $cdsCount;
    if (($cachedCount == 0) && ($distrust_cached_protein_count_of_zero)) {
	return 1;
    } elsif (($fractionInUniProt < $distrust_cached_protein_count_above_cds_ratio ) &&
	     ($fractionInUniProt > $distrust_cached_protein_count_below_cds_ratio )) {
	# suspiciously small number in UniProt compared to a simple CDS count
	$distrustCount++;
	$distrustFraction += $fractionInUniProt;
	return 1;
    }
    return 0;
}

sub distrustCacheTally($$$) {
    my $cdsCount = shift;
    my $cachedCountOld = shift;
    my $cachedCountNew = shift;

    my $fractionInUniProt = $cachedCountOld / $cdsCount;
    if ($cachedCountNew > $cachedCountOld) {
	if ($cachedCountOld == 0) {
	    $distrustZeroCountUsefulCount++;
	} else {
	    $distrustUsefulCount++;
	    $distrustUsefulRatio += $fractionInUniProt;
	}
    } else {
	if ($cachedCountOld == 0) {
	    $distrustZeroCountUnusefulCount++;
	} else {
	    $distrustUnusefulCount++;
	    $distrustUnusefulRatio += $fractionInUniProt;
	}
    }
    return;
}
    

sub getProteinCount {
    my $acNumberAndVersion = shift;

    if ( !(exists( $cachedInfo{$acNumberAndVersion}{PROTEINCOUNT} ) ) ) {
	return newProteinCount($acNumberAndVersion);
    } else {
	my $cdsCount = getCDScount($acNumberAndVersion);
	if (distrustCachedProteinCount($cdsCount,$cachedInfo{$acNumberAndVersion}{PROTEINCOUNT})) {
	    my $cachedCountOld = $cachedInfo{$acNumberAndVersion}{PROTEINCOUNT};
	    my $cachedCountNew = newProteinCount($acNumberAndVersion);
	    distrustCacheTally($cdsCount, $cachedCountOld, $cachedCountNew);
	}
	return $cachedInfo{$acNumberAndVersion}{PROTEINCOUNT};
    }
}
    

# findGenRevFiles #
sub findGenRevFiles {
    my %genRevsFound;
    my $ftpServer  = "ftp.ebi.ac.uk";
    my $ftpBaseUrl = "/pub/databases/genome_reviews/last_release/dat/";

    #    my $ftpServerLocation = "/ebi/ftp/pub/databases/genome_reviews/dat/";
    # NB Find files with ftp because the ftp file system mounting was erratic

    my $ftp = Net::FTP->new( $ftpServer, Timeout => 30 )
      or die "Can't connect to $ftpServer: $!";
    $ftp->login( "anonymous", "faruque\@ebi.ac.uk" )
      or die "Can't login to ftp server: $!";
    $ftp->cwd($ftpBaseUrl)
      or die "Can't CWD to $ftpBaseUrl: $!";    #
    my @ls = $ftp->ls('-lR');
    $ftp->binary();

    foreach my $file ( parse_dir( \@ls ) ) {
        my ( $name, $type, $size, $mtime, $mode ) = @$file;

        # We only want to process plain files ending in '_GR.dat.*'
        next unless ( $type eq 'f' and ( $name =~ /_GR\.dat.*/ ) );
        $name =~ s|^\./||;
        $name =~ s|\.gz$||;
        my $ac = $name;
        $ac =~ s|(\w+)_GR\.dat(\.gz)?|$1|;
        if ( exists( $genRevsFound{$ac} ) ) {
            print LOG "<p><font color=\"red\">Duplicate $ac Genome Review files found, " . "ftp://"
              . $ftpServer
              . $ftpBaseUrl
              . $name . " and "
              . $genRevsFound{$ac}
              . "</font></p>\n";
        }
        $genRevsFound{$ac} =
          "ftp://" . $ftpServer . $ftpBaseUrl . $name . ".gz";    # I add it back here because the ftp sever now doesn't unzip the files automatically
    }
    $ftp->quit;
    return %genRevsFound;
}

# writeOutput # produces the main web pages
sub writeOutput {
    my $file                  = shift;
    my $lastwords             = ucfirst(shift);                   # NB Description
    my $intro                 = shift;                            # Text to put over the table page
    my $items                 = shift;                            # Array of the sequences to list
    my $multiOrganism         = shift;                            # Denotes if taxonomy info should be analysed
    my $logErrors             = shift;
    my $taxInfo               = shift;                            #
    my $oddEntryUrls          = shift;
    my $proteomeLinks         = shift;
    my $genomeReviewLocations = shift;

    #    if ($lastwords eq "Plasmid"){
    #	$multiOrganism = 0;}
    my $logTable = "";
    my %organismTaxLinkMade;

    # Prepare stuff for html output
    my $baseUrl = "http://www.ebi.ac.uk/genomes/";

    #$title will be constructed from firstword+lastword
    my $menuitem      = "databases";
    my $pagetitle     = "Genomes Pages";
    my $pageurl       = $baseUrl . "index.html";
    my $firstword     = "Genomes"; 
    my $title         = $pagetitle . " - " . $lastwords;
    my $loadmethods   = "\/\/checkBrowser(); genjob(); setem()";
    my $unloadmethods = "\/\/closeNotify()";
    my $menu = [ ($file eq "index" ? "Complete genomes" : "<a href=\"index.html\">Complete genomes</a>"),
                  ($file eq "archaea" ? "Archaea" : "<a href=\"archaea.html\">Archaea</a>"),
                  ($file eq "archaealvirus" ? "Archaeal virus" : "<a href=\"archaealvirus.html\">Archaeal virus</a>"),
                  ($file eq "bacteria" ? "Bacteria" : "<a href=\"bacteria.html\">Bacteria</a>"),
                  ($file eq "eukaryota" ? "Eukaryota" : "<a href=\"eukaryota.html\">Eukaryota</a>"),
                  ($file eq "organelle" ? "Organelle" : "<a href=\"organelle.html\">Organelle</a>"),
                  ($file eq "phage" ? "Phage" : "<a href=\"phage.html\">Phage</a>"),
                  ($file eq "plasmid" ? "Plasmid" : "<a href=\"plasmid.html\">Plasmid</a>"),
                  ($file eq "viroid" ? "Viroid" : "<a href=\"viroid.html\">Viroid</a>"),
                  ($file eq "virus" ? "Virus" : "<a href=\"virus.html\">Virus</a>"),
                 [  1,
                    "<a href=\"\">Links</a>",
                     ($file eq "wgs" ? "WGS info" : "<a href=\"wgs.html\">WGS info</a>"),
                    "<a href=\"http://www.ensemblgenomes.org/\">EnsemblGenomes</a>",
                    "<a href=\"http://www.ebi.ac.uk/fasta33/genomes.html\">Fasta33 Server</a>",
                    "<a href=\"http://www.ensembl.org/index.html\">Ensembl</a>"
                 ]
    ];
    my $out_html = "";

    if ( $file eq "index" ) {
        open( IN, "<$dataInDir/index.html" )
          or die "$dataInDir/index.html cannot be read - I need it to make the real index.html\n";
        my $infileText = do { local $/; <IN> };
        close IN;
        $infileText =~ s/.*<body[^>]*>(.*)<\/body[^>]*>.*/$1/si; # trim body
        my $top40 = getLastFortyGenomes();
        $infileText =~ s/{top40}/$top40/si;
        my $thisDate =
            ( (localtime)[3] ) . "-"
          . ( "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" )[ (localtime)[4] ] . "-"
          . ( (localtime)[5] + 1900 );
        $infileText =~ s/{date}/$thisDate/si;

        $out_html .= $infileText;
    }
    elsif ( $file eq "wgs" ) {
        open( IN, "<$dataInDir/wgs.html" )
          or die "$dataInDir/wgs.html cannot be read - I need it to make the real wgs.html\n";
        my $infileText = do { local $/; <IN> };
        close IN;

        #	local $/ = undef;
        #	my $infileText = <IN>;
        #	close IN;
        $infileText =~ s/.*<body[^>]*>(.*)<\/body[^>]*>.*/$1/si;
        my $wgs = getWGSTable();
        $infileText =~ s/{wgs}/$wgs/si;
        my $thisDate =
            ( (localtime)[3] ) . "-"
          . ( "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" )[ (localtime)[4] ] . "-"
          . ( (localtime)[5] + 1900 );
        $infileText =~ s/{date}/$thisDate/si;
        $out_html .= $infileText;
    }
    elsif ( $file eq "help" ) {
        open( IN, "<$dataInDir/help.html" )
          or die "$dataInDir/help.html cannot be read - I need it to make the real help.html\n";
        my $infileText = do { local $/; <IN> };
        close IN;

        $infileText =~ s/.*<body[^>]*>(.*)<\/body[^>]*>.*/$1/si;
        $infileText =~ s/.*(<h3>About The Pages<\/h3>)/$1/si; # trim more header
        my $thisDate =
            ( (localtime)[3] ) . "-"
          . ( "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" )[ (localtime)[4] ] . "-"
          . ( (localtime)[5] + 1900 );
        $infileText =~ s/{date}/$thisDate/si;
        $out_html .= $infileText;
    }
    else {

        # Only normal entry list pages and con-segment pages remain at this point
        open OUT_LIST1, ">$webDir/$file.txt"
	    or die "Can't create file: $webDir/$file.txt $!";

        # the genome category pages (are multi-source) and have an extra textfile
	my $list2filename = "/dev/null";
	if ($multiOrganism) {
	    $list2filename = "$webDir/$file.details.txt";
	}
        open OUT_LIST2, ">$list2filename"
	    or die "Can't open a new file: $list2filename $!" ;
        print OUT_LIST2 "#AC.SeqVer.\tEntryVer.\tVer.Date\tTaxid\tDescription\n";
        
        my $thisDate =
            ( (localtime)[3] ) . "-"
          . ( "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" )[ (localtime)[4] ] . "-"
          . ( (localtime)[5] + 1900 );

        my $outputTableTop =
            "<h3>List of available genomes (on "
          . $thisDate
          . ")</h3>"
          . "<table style=\"font-size: 93%\">\n"
          . "<tr>\n\t"
          . "<th rowspan=\"2\">&nbsp;</th>\n\t"
          . "<th rowspan=\"2\" style=\"vertical-align:middle;text-align:center;\" width=\"45%\">Description</th>\n\t"
          . "<th rowspan=\"2\" style=\"vertical-align:middle;text-align:center;\">Length (bp)</th>\n\t"
          . "<th colspan=\"2\" style=\"text-align:center;\">Sequence</th>\n\t"
          . ($multiOrganism?"<th rowspan=\"2\" style=\"vertical-align:middle;text-align:center;\">Project</th>\n\t":"") # don't show project/MAGPI column for CON pages
          . "<th rowspan=\"2\" style=\"vertical-align:middle;text-align:center;\">Proteins</th>\n"
          . "</tr>\n"
          . "<tr>\n\t"
          . "<th style=\"text-align:center;\">Plain</th>\n\t"
          . "<th style=\"text-align:center;\">HTML</th>\n"
          . "</tr>\n";

        $out_html .=
            $intro . "\n"
          . "<!-- Intro -->\n"
          . "<p>Accession numbers of all the entries listed below may be downloaded as a "
          . "<a href=\"$file.txt\">text file</a> "
          . "for use in downloading using the <a href=\"http://www.ebi.ac.uk/cgi-bin/sva/sva.pl?&do_batch=1\">Sequence Version Archive</a>.</p>\n";
        if ( $lastwords eq "Eukaryota" ) {
            $out_html .=
              "Due to the increased numbers of completed genome sequences, this page no longer includes direct links to <a href=\"http://www.ensembl.org/index.html\">Ensembl genomes</a>.  Please use the link to browse them directly.</p>\n";
        }
        $multiOrganism
          && ( $out_html .= "<p>A more-detailed, <a href=\"$file.details.txt\">tab-delimited list</a> is also available.</p>\n" );
        $out_html .= $outputTableTop;
        my $lastDE                    = "Will be the previous DE line";
        my $lastProteome              = " ";
        my $lastProteomeErr           = " ";
        my $lastAC                    = "";
        my $lastTaxNode               = 0;
        my $lastTaxBinomial           = 0;
        my $bgColor                   = 1;
        my $pending_html              = "\n"; # holds a current batch of lines for colspan changes, or filtering out of organelle-only entries in Eukaryota page
        my $pending_list1             = ""; # holds a current batch of lines for filtering out of organelle-only entries in Eukaryota page
        my $pending_list2             = ""; # holds a current batch of lines for filtering out of organelle-only entries in Eukaryota page
        my $proteomeRowSpan           = 0;
        my $magpiRowSpan              = 0;
        my $magpiStringLastUsed       = "";
        my $proteomeAvailable         = "";
        my $genomeEntryNumber         = 0;
        my $genomeEntryNumberLastUsed = 1;                                # a fix to avoid skipping numbers with unused
                                                                          # mitochondrial genome entries in eukaryotes
        my $genomeEntrySuffix         = 97;

        # ie chr($genomeEntrySuffix) gives "a" -> z and then A-Z

        foreach my $item (@$items) {
            $totalEntryCount++;
	    my $magpiStringCurrent = makeMagpiLinkString($item->{'MAGPIS'}); 

            if ( $intro =~ /segments/ ) {
                $segmentCount++;
            }

            my $escapedOS = quotemeta( $$taxInfo{ $item->{TAX_ID} }->{ORGANISM} );
            if ( $item->{DESCRIPTION} eq $lastDE ) {
                if ( $item->{AC_NUMBER} !~ /ensembl.org/ ) {    # eliminate duplicate message for ENSEMBL cases
                    $logTable .=
                        "<tr bgcolor=\"#FFDDDD\">\n"
                      . "\t\t<td>"
                      . $item->{DESCRIPTION}
                      . "</td>\n"
                      . "\t\t<td>Identical description for both "
		      . makeEntryLink($lastAC,'default')
		      . "(" . $magpiStringLastUsed . ")" # should cater for joined multiple 
		      . " and "
		      . makeEntryLink($item->{AC_NUMBER},'default')
		      . "(" . $magpiStringCurrent . "), consider checking the description\n" # should cater for joined multiple 
                      . "</td></tr>";
                }
            }

            my $seqFilePlainUrl;
            my $seqFilePlainAnchor = "";
            my $seqFileHtmlUrl;
            my $seqFileHtmlAnchor = "";
            my $seqTd             = "<td>";    # actually 2 table cells

            # Is it an ENSEMBL reference?
            if ( $item->{ENTRY_TYPE} == 98 ) {
                $seqFileHtmlUrl    = $item->{AC_NUMBER};
                $seqFileHtmlAnchor = "ENSEMBL";
            }

            # is it an odd entry from the .manual file with its own URL?
            elsif ( exists( $$oddEntryUrls{ $item->{AC_NUMBER} } ) ) {
                $seqFilePlainUrl    = $$oddEntryUrls{ $item->{AC_NUMBER} };
                $seqFilePlainAnchor = "<tt>$item->{AC_NUMBER}</tt>";
            }

            # Then we can use the ENAbrowser
            else {
                $seqFilePlainUrl    = $enaBrowserUrl . $item->{AC_NUMBER} . $enaBrowserArgText . $enaBrowserArgConff;
                $seqFilePlainAnchor = "<tt>$item->{AC_NUMBER}</tt>";
                $seqFileHtmlUrl     = $enaBrowserUrl . $item->{AC_NUMBER} . $enaBrowserArgHtml;
                $seqFileHtmlAnchor  = $item->{AC_NUMBER};
            }

            if ( $seqFilePlainAnchor eq "" ) {
                $seqTd .= "&nbsp;</td>\n\t<td>";
            }
            else {

                $seqTd .= "<a href=\"$seqFilePlainUrl\">$seqFilePlainAnchor</a></td>\n\t<td>";
            }
            if ( $seqFileHtmlAnchor eq "" ) {
                $seqTd .= "&nbsp;</td>\n";
            }
            else {
                $seqTd .= "<a href=\"$seqFileHtmlUrl\">$seqFileHtmlAnchor</a></td>\n";
            }

            my $deEnding      = "";
            my $seqFileAnchor = $item->{AC_NUMBER};

            #For multipart sequences (ie CONs
            if (($item->{PARTS} > 1 )      || # still want these links if con of a single entry so I've added 2 more possibilities:- 
		($item->{ENTRY_TYPE} == 1 ) || 
		($item->{ENTRY_TYPE} == 4 )){
                $deEnding = " (<a href=\"$item->{AC_NUMBER}.html\">" . commify( $item->{PARTS} ) . "&nbsp;part".(($item->{PARTS} >  1)? "s":"")."</a>";
		$deEnding .= " in a  <a href =\"$enaBrowserUrl$item->{AC_NUMBER}\">CON entry</a>";
                $deEnding .= ")\n";
            }
	    
            my $genomeEntrySuffixLetter = "";
            my $proteinTd               = "<td>&nbsp;";
            my $magpiTd                 ;
            my $descriptionTd           = "<td>";
            my $taxBinomial             = $$taxInfo{ $item->{TAX_ID} }->{BINOMIAL};
            my $proteinCount            = "0";

	    if (defined($magpiStringCurrent) &&
		($magpiStringCurrent eq $magpiStringLastUsed) &&
		($magpiStringCurrent ne "") &&
		($lastTaxBinomial == $taxBinomial)) {
		$magpiRowSpan++;
		$magpiTd = "";
		$verbose && print STDERR "MAGPI:".$item->{AC_NUMBER}.":same $magpiStringCurrent == $magpiStringLastUsed\n";##############
	    } else {
		$verbose && print STDERR "MAGPI:".$item->{AC_NUMBER}.":diff $magpiStringLastUsed -> $magpiStringCurrent\n";#############
		$pending_html =~ s/_MAGPIROWSPAN_/$magpiRowSpan/;
		$magpiRowSpan = 1;
		$magpiStringLastUsed = $magpiStringCurrent;
		if ( (defined($magpiStringCurrent)) && ($magpiStringCurrent ne "" )) {
		    $magpiTd =
			"\t<td rowspan=\"_MAGPIROWSPAN_\" style=\"vertical-align:middle;text-align:center;\">$magpiStringCurrent</td>\n";
		} else {
		    $magpiTd = "\t<td>&nbsp;</td>\n";
		}
	    }
		$verbose && print STDERR "MAGPI:".$item->{AC_NUMBER}.":NB $magpiStringLastUsed -> $magpiStringCurrent\n";#############


            if ( $item->{ENTRY_TYPE} <= 4 ) {
                if ( defined( $item->{VERSION} ) ) {
                    $proteinCount = getProteinCount( $item->{AC_NUMBER} . "." . $item->{VERSION} );
                }
                else {
                    print LOG "No dbentry.ext_ver obtained for $item->{AC_NUMBER}<br/>"
			. " $item->{DESCRIPTION}<br/>\n"
			. "I use the version number to know when to used cached info or ask SRS<br/>\n\n";
                    $proteinCount = getProteinCount( $item->{AC_NUMBER} . ".0");
                }
            }
            elsif ( $item->{PARTS} > 1 ) {
		
                # Protein counts already prepared for non-CON multipart entries
                $proteinCount = getProteinCount( $item->{AC_NUMBER} );
            }
	    
            if ($multiOrganism) {

                $genomeEntrySuffix++;
                if ( $lastwords ne "Plasmid" ) {
		    
                    #if ( exists( $$proteomeLinks{ $item->{AC_NUMBER} } ) ) {
                    #    $proteomeAvailable = $$proteomeLinks{ $item->{AC_NUMBER} };
                    #}
                    #elsif ( exists( $$proteomeLinks{ $item->{TAX_ID} } ) ) {
                    #    $proteomeAvailable = $$proteomeLinks{ $item->{TAX_ID} };
                    #}
                    #else {
                    #    $proteomeAvailable = "";
                    #}
                }
                
                $proteomeAvailable = "";
		
                if (( $proteomeAvailable eq $lastProteome ) and
		    ( $proteomeAvailable ne "" )) {
                    $proteomeRowSpan++;
                    $proteinTd = "";
                } else {	    
                    $pending_html =~ s/_PROTEOMEROWSPAN_/$proteomeRowSpan/;
                    $proteomeRowSpan = 1;
                    $lastProteome     = $proteomeAvailable;
		    if ( $proteomeAvailable ne "" ) {
                        $proteinTd =
                            "<td rowspan=\"_PROTEOMEROWSPAN_\" style=\"vertical-align:middle;text-align:center;\"><a target=\"proteomeWindow\" "
			    . "href=\"$proteomeAvailable\">Proteome</a> ";
                    }
		    elsif ( $item->{ENTRY_TYPE} <= 4 ) {
			if ( $proteinCount > 0 ) {
			    $proteinTd =
				"<td ><b>"
				. commify($proteinCount)
				. "</b> <a href=\"$uniprotBrowserFasta1$item->{AC_NUMBER}$uniprotBrowserFasta2\">fasta</a>\n"
				. "\t\t<a href=\"$uniprotBrowserHtml1$item->{AC_NUMBER}$uniprotBrowserHtml2\">UniProt</a>";
			}
			elsif ( $proteinCount == -1 ) {    # ie new entry version and SRS's getz is unavailable
			    $proteinTd =
				"<td ><b>"
				. "</b> <a href=\"$uniprotBrowserFasta1$item->{AC_NUMBER}$uniprotBrowserFasta2\">FASTA</a>\n"
				. "\t\t<a href=\"$uniprotBrowserHtml1$item->{AC_NUMBER}$uniprotBrowserHtml2\">SRS</a>";
			}
			else {
			    $proteinTd = "<td class=\"tdcenter\">n/a";
			}
		    }
		    else{   
			$proteinTd = "<td class=\"tdcenter\">n/a"; # catch all blank NEW
		    }

		    if ( $proteinTd eq "<td>&nbsp;" ) {
			if ( -e $webDir . "/" . $item->{AC_NUMBER} . ".fasta" ) {
			    $proteinCount = getProteinCount( $item->{AC_NUMBER});
			    
			    $proteinTd = "<td ><b>" . commify($proteinCount) . "</b> <a href=\"" . $item->{AC_NUMBER} . ".fasta\">FASTA</a>";
			}
			else {
			    my $proteomeError = "No proteome for non-standard entry $item->{TAX_ID} (" . $$taxInfo{ $item->{TAX_ID} }->{ORGANISM} . ")\n";
			    if ( $lastProteomeErr ne $proteomeError ) {
				print STDERR $proteomeError;
				$lastProteomeErr = $proteomeError;
			    }
			}
		    }
		}
		
                if ( $lastTaxNode != $item->{TAX_ID} ) {
                    if ( $genomeEntrySuffix > 98 ) {
                        $pending_html =~ s/_SUFFIX_/a/s;
                    }
                    else {
                        $pending_html =~ s/_SUFFIX_//s;
                    }
                    $bgColor *= -1;
                    $genomeEntryNumber++;
                    $genomeEntrySuffix       = 97;
                    $genomeEntrySuffixLetter = "_SUFFIX_";
                }
                else {
                    if ( $genomeEntrySuffix > 122 ) {
                        $genomeEntrySuffixLetter = chr( $genomeEntrySuffix - 58 );
                    }
                    else {
                        $genomeEntrySuffixLetter = chr($genomeEntrySuffix);
                    }
                }
                if ( $lastTaxBinomial != $taxBinomial ) {
                    if ( $lastwords eq "Eukaryota" ) {
                        if ( ($pending_html =~ /chromosome/s ) || ($pending_html =~ /supercontig/s )) {
			    print OUT_LIST1 $pending_list1;
			    print OUT_LIST2 $pending_list2; 
                            $out_html .= $pending_html;
                            $genomeEntryNumberLastUsed = $genomeEntryNumber;
                        }
                        else {	    
                            # Omit organisms with no chromosome entries and reuse numbers
                            $genomeEntryNumber = $genomeEntryNumberLastUsed; # put genomeEntryNumber back to the last one used
                        }
                    }
                    else {
			print OUT_LIST1 $pending_list1;
			print OUT_LIST2 $pending_list2; 
                        $out_html .= $pending_html;
                    }
		    $pending_list1 = "";
		    $pending_list2 = "";
                    $pending_html =
                        "<tr><td colspan=\"7\" style=\"text-align:center; background:#E6E6E6;\">"
			. makeEntryLink($taxBinomial,'Taxonomy',$$taxInfo{$taxBinomial}->{ORGANISM});
                    if ( defined( $karynsGenomesLocations{$taxBinomial} ) ) {
                        $pending_html .= " <a href=\"" . $karynsGenomesUrl . $karynsGenomesLocations{$taxBinomial} . "\">(Description)</a>";
                    }
                    $pending_html .= "</td></tr>\n";
                    $organismTaxLinkMade{$taxBinomial} = 1;
                    $bgColor = -1;
		}
	    }
	    
            # single organism
            else {
                my $proteinCount;
                if ( defined( $item->{VERSION} ) ) {
                    $proteinCount = getProteinCount( $item->{AC_NUMBER} . "." . $item->{VERSION} );
                }
                else {
                    $notQuiet
			and print "No entry version held for $item->{AC_NUMBER}\n" . " $item->{DESCRIPTION}\n";
                    $proteinCount = getProteinCount( $item->{AC_NUMBER} . ".0" );
                }
		
                if ( $item->{ENTRY_TYPE} eq "0" ) {
                    if ( $proteinCount > 0 ) {
                        $proteinTd =
                            "<td ><b>"
			    . commify($proteinCount)
			    . "</b> <a href=\"$uniprotBrowserFasta1$item->{AC_NUMBER}$uniprotBrowserFasta2\">FASTA</a>\n"
			    . "\t\t<a href=\"$uniprotBrowserHtml1$item->{AC_NUMBER}$uniprotBrowserHtml2\">UniProt</a>";
                    }
                    else {
                        $proteinTd = "<td style=\"text-align:center\">n/a";
                    }
                }
                $bgColor = -1;
                $genomeEntryNumber++;
		print OUT_LIST1 $pending_list1;
		print OUT_LIST2 $pending_list2; 
                $out_html .= $pending_html;
		$pending_list1 = "";
		$pending_list2 = "";
                $pending_html = "\n";
            }
	    
            $descriptionTd .= $item->{DESCRIPTION};
            $descriptionTd =~ s/(chromosome|segment|plasmid) (\S+)/$1 <b>$2<\/b>/;
	    $descriptionTd =~ s/<b>VIIII</<b>IX</; # A fudge to turn VIIII to IX (VIIII is used because it sorts correctly)    
            if ( !( defined( $organismTaxLinkMade{"$item->{TAX_ID}"} ) ) ) {
                $organismTaxLinkMade{"$item->{TAX_ID}"} = 1;
                my $organismNameAndLink = makeEntryLink($item->{TAX_ID},'Taxonomy',$$taxInfo{ $item->{TAX_ID} }->{ORGANISM});
                $descriptionTd =~ s/$escapedOS/$organismNameAndLink/i;
            }
	    
            if ( defined( $$genomeReviewLocations{ $item->{AC_NUMBER} } ) ) {
                $descriptionTd .= " (<a href =\"$$genomeReviewLocations{$item->{AC_NUMBER}}\">Genome Review</a>)";
            }
	    
            $descriptionTd .= $deEnding;
            if ( $bgColor == -1 ) {
                $pending_html .= "<tr>\n";
            }
            else {
                $pending_html .= "<tr >\n";
            }
            $pending_html .= "\t<td>"
              . $genomeEntryNumber
              . $genomeEntrySuffixLetter
              . "</td>\n"
              . "\t$descriptionTd</td>\n"
              . "\t<td >"
              . commify( $item->{SEQ_LEN} )
              . "</td>\n" 
              . "\t" . $seqTd 
	      . ($multiOrganism?$magpiTd:"") # don't show project/MAGPI column for CON pages
              . (($proteinTd ne "")?"\t" . $proteinTd . "</td>\n":"")
              . "</tr>\n";

            $lastDE = $item->{DESCRIPTION};
            $lastAC = $item->{AC_NUMBER};

            $lastTaxNode     = $item->{TAX_ID};
            $lastTaxBinomial = $$taxInfo{ $item->{TAX_ID} }->{BINOMIAL};

            if ($multiOrganism) {
		if ((($file eq "virus") || 
		     ($file eq "eukaryota")) &&
		    ($$taxInfo{ $item->{TAX_ID}}->{CODE} == 11)){
                    $logTable .= 
                        "<tr bgcolor=\"#E0E0E0\">\t\t"
                      . "<td><a href=\"http://www.ncbi.nlm.nih.gov/Taxonomy/protected/wwwtax.cgi?"
                      . "mode=Info&lvl=1&id="
                      . $item->{TAX_ID} . "\""
                      . ">$$taxInfo{$item->{TAX_ID}}->{ORGANISM}</a></td>\t\t"
                      . "<td>Genetic code 11 but category $file in genome table entry for "
 		      . makeEntryLink($item->{AC_NUMBER},'default')
                      . "</td>\n"
                      . "</tr>\n";
                }
		    
                if ( !( $item->{DESCRIPTION} =~ /^(TPA: )?$escapedOS/i ) ) {
                    my $badDescription = $item->{DESCRIPTION};
                    $badDescription =~ s/($escapedOS)/<b>$1<\/b>/i;
                    $logTable .=
                        "<tr bgcolor=\"#DDFFDD\">\t\t"
                      . "<td>OS is <a href=\"http://www.ncbi.nlm.nih.gov/Taxonomy/protected/wwwtax.cgi?"
                      . "mode=Info&lvl=1&id="
                      . $item->{TAX_ID} . "\""
                      . ">$$taxInfo{$item->{TAX_ID}}->{ORGANISM}</a></td>\t\t"
                      . "<td>genomes table description is \"$badDescription\" in genome table entry for "
		      . makeEntryLink($item->{AC_NUMBER},'default')
		      . "</td>\n"
                      . "</tr>\n";
                }
            }

            # Database refs get their accession number into the list file
            if ( $item->{ENTRY_TYPE} <= 4 ) {
                $pending_list1 .= "$item->{'AC_NUMBER'}\n";
                ($multiOrganism)
                  && ( $pending_list2 .= 
                       "$item->{'AC_NUMBER'}.$item->{'SVERSION'}\t$item->{'VERSION'}\t$item->{'VDATE'}\t$item->{'TAX_ID'}\t$item->{'DESCRIPTION'}\n" );
            } 

        }

	# we have now finished the entries on the page, 
        # complete list table
        if ( $genomeEntrySuffix > 98 ) {
            $pending_html =~ s/_SUFFIX_/a/s;
        }
        else {
            $pending_html =~ s/_SUFFIX_//s;
        }

	$pending_html =~ s/_MAGPIROWSPAN_/$magpiRowSpan/;

        # Exclude species with just organelles from the Eukaryotic table
        if ( $lastwords eq "Eukaryota" ) {
            if ( $pending_html =~ /chromosome/s ) {
		print OUT_LIST1 $pending_list1;
		print OUT_LIST2 $pending_list2;
                $out_html .= $pending_html;
            }
        }
        else {
	    print OUT_LIST1 $pending_list1;
	    print OUT_LIST2 $pending_list2;
            $out_html .= $pending_html;
        }
        close OUT_LIST1;
        close OUT_LIST2;

        # If there are 'errors' and they are to be reported, write them to LOG
        if ( ( $logErrors == 1 ) and ( $logTable ne "" ) ) {
            print LOG "\n<table border=\"1\" style=\"font-size: 100%\">\n"
              . "\t<tr bgcolor=\"222222\">\n"
              . "\t\t<td><b><font color=\"#FFFFFF\">Organism/Duplicate DE</font></b></td>\n"
              . "\t\t<td><b><font color=\"#FFDDDD\">Duplicate</font><font color=\"#FFFFFF\"> or </font>"
              . "<font color=\"#DDFFDD\">Organism</font><font color=\"#FFFFFF\"> problem</font></b></td>\n"
              . "\t</tr>\n";
            print LOG $logTable;
            print LOG "\n</table>";
        }
        $out_html .= "</table style=\"font-size: 100%\">\n";
        if ( $genomeEntryNumber > 1 ) {    # should always be true
            if ($multiOrganism) {
                $out_html =~ s/(<!-- Intro -->)/$1<p>$genomeEntryNumber organisms.<\/p>\n/s;
            }
            else {
                $out_html =~ s/(<!-- Intro -->)/$1<p>$genomeEntryNumber entries.<\/p>\n/s;
            }
        }
    }
    $out_html .= "<p><font size =\"-2\">Page generated " . timeDayDate("timedaydate") . "</font></p>\n";
    # actually write HTML
    open OUT, ">$webDir/$file.html"
      or die "Can't create file: $webDir/$file.html $!";
    my $pageTitle = $title;
    $pageTitle =~ s/ - at the / | /i;
        
    my $EBIheader    = <<EBIHEADER;
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="eng"><!-- InstanceBegin template="/Templates/new_template_no_menus.dwt" codeOutsideHTMLIsLocked="false" --> 
<head> 
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />  
<meta name="author" content="Rasko" /> 
<meta http-equiv="Content-Language" content="en-GB" /> 
<meta http-equiv="Window-target" content="_top" /> 
<meta name="no-email-collection" content="http://www.unspam.com/noemailcollection/" /> 
<!-- InstanceBeginEditable name="doctitle" --> 
<title>$pageTitle</title> 
<!-- InstanceEndEditable --> 
<script  src="https://www.ebi.ac.uk/inc/js/contents.js" type="text/javascript"></script> 
<link rel="stylesheet" href="//www.ebi.ac.uk/web_guidelines/css/compliance/mini/ebi-fluid-embl.css">
<link type="text/css" rel="stylesheet" href="//www.ebi.ac.uk/web_guidelines/css/compliance/develop/embl-petrol-colours.css"/>
<script defer="defer" src="//www.ebi.ac.uk/web_guidelines/js/cookiebanner.js" type="text/javascript"></script>
<script defer="defer" src="//www.ebi.ac.uk/web_guidelines/js/foot.js" type="text/javascript"></script>


<link rel="SHORTCUT ICON" href="http://www.ebi.ac.uk/bookmark.ico" /> 

</head>
<body> 

<div id="wrapper" class="container_24 page">
     <header>
      <div id="global-masthead" class="masthead grid_24">
        <!--This has to be one line and no newline characters-->
        <a href="//www.ebi.ac.uk/" title="Go to the EMBL-EBI homepage">
        <img src="//www.ebi.ac.uk/web_guidelines/images/logos/EMBL-EBI/EMBL_EBI_Logo_white.png" alt="EMBL European Bioinformatics Institute" /></a>

        <nav>
         <ul id="global-nav">
          <!-- set active class as appropriate -->
          <li class="first active" id="services"><a href="//www.ebi.ac.uk/services">Services</a></li>
          <li id="research"><a href="//www.ebi.ac.uk/research">Research</a></li>
          <li id="training"><a href="//www.ebi.ac.uk/training">Training</a></li>
          <li id="industry"><a href="//www.ebi.ac.uk/industry">Industry</a></li>
          <li id="about" class="last"><a href="//www.ebi.ac.uk/about">About us</a></li>
         </ul>
      </nav>
     </div>

     <div id="local-masthead" class="masthead grid_24">
       <!-- local-title -->
       <!-- NB: for additional title style patterns, see http://frontier.ebi.ac.uk/web/style/patterns -->
        <div class="grid_12 alpha" id="local-title"  align="center">
          <a ref="http://www.ebi.ac.uk/ena/" title="Back to European Nucleotide Archive homepage">
           <img src="http://www.ebi.ac.uk/web_guidelines/images/logos/ena/ENA-logo.png" alt="European Nucleotide Archive" > 
         </a> 
        </div>
        
        <div class="grid_12 omega">
			<form id="local-search" action="/ena/data/search" method="get" name="local-search">
			    <fieldset>
			        <div class="left">
			            <label> 
			                <input id="local-searchbox" type="text" name="query" />
			            </label> 
			            <!-- Include some example searchterms - keep them short and few! --> 
			            <span class="examples">Examples: <a title="ENA accession (e.g. BN000065)" href="/ena/data/search?query=BN000065">BN000065</a>, <a title="Free text search (e.g. histone)" href="/ena/data/search?query=histone">histone</a></span>
			        </div>
                    <div class="right">
                        <input class="submit" type="submit" value="Search" />
                        <!-- If your search is more complex than just a keyword search, you can link to an Advanced Search, with whatever features you want available -->
                        <span class="adv"><a id="adv-search" title="Advanced search" href="/ena/data/warehouse/search">Advanced</a></span> 
                        <span class="adv"><a id="seq-search" title="Sequence search" href="/ena/search">Sequence</a></span>
                    </div>
                </fieldset>
            </form>
		</div>
        
        <!-- local nav -->
        <nav>
            <ul class="grid_24" id="local-nav">
              <li class="first"><a href="http://www.ebi.ac.uk/ena">Home</a></li>
	      <li class="active"><a href="http://www.ebi.ac.uk/ena/browse">Search &amp; Browse</a></li>
	      <li><a href="http://www.ebi.ac.uk/ena/submit">Submit &amp; Update</a></li>
	      <li><a href="http://www.ebi.ac.uk/ena/about">About ENA</a></li>
	      <li class="last"><a href="http://www.ebi.ac.uk/ena/support">Support</a></li>
           </ul>
        </nav>	
      </div>
     </header>

<div id="content" role="main" class="grid_24 clearfix">     

EBIHEADER

	print OUT $EBIheader;
	
    my $GENMenu = <<HTML;
    <!-- start left menu here -->
    <div class="grid_4 alpha">
    <!--<div class="int-nav">-->
    <div class="shortcuts submenu">
        <h3>Genomes at EBI</h3>
        <ul>
            <li><a href=\"index.html\">Complete genomes</a></li>
            <li><a href=\"archaea.html\">Archaea</a></li>
            <li><a href=\"archaealvirus.html\">Archaeal virus</a></li>
            <li><a href=\"bacteria.html\">Bacteria</a></li>
            <li><a href=\"eukaryota.html\">Eukaryota</a></li>
            <li><a href=\"organelle.html\">Organelle</a></li>
            <li><a href=\"phage.html\">Phage</a></li>
            <li><a href=\"plasmid.html\">Plasmid</a></li>
            <li><a href=\"viroid.html\">Viroid</a></li>
            <li><a href=\"virus.html\">Virus</a></li>
            <li>Links
                <ul>
                    <li><a href=\"wgs.html\">WGS info</a></li>
                    <li><a href=\"http://www.ensemblgenomes.org/\">EnsemblGenomes</a></li>
                    <li><a href=\"http://www.ensembl.org/index.html\">Ensembl</a></li>
                    <li><a href=\"http://www.ebi.ac.uk/fasta33/genomes.html\">Fasta33 Server</a></li>
                    
                </ul>
            </li>
        </ul>
    </div>
    </div>
HTML


    print OUT $GENMenu;
    
    print OUT "<div class=\"grid_20 omega\">";
    
    print OUT "<h2>$title</h2> ";
    print OUT $out_html;
    
    my $EBIfooter    = <<EBIFOOTER;
         </div>
                                


<footer>
		<div id="global-footer" class="grid_24">

			<nav id="global-nav-expanded">

				<div class="grid_4 alpha">
					<h3 class="embl-ebi"><a href="//www.ebi.ac.uk/" title="EMBL-EBI">EMBL-EBI</a></h3>
				</div>

				<div class="grid_4">
					<h3 class="services"><a href="//www.ebi.ac.uk/services">Services</a></h3>
				</div>

				<div class="grid_4">
					<h3 class="research"><a href="//www.ebi.ac.uk/research">Research</a></h3>
				</div>

				<div class="grid_4">
					<h3 class="training"><a href="//www.ebi.ac.uk/training">Training</a></h3>
				</div>

				<div class="grid_4">
					<h3 class="industry"><a href="//www.ebi.ac.uk/industry">Industry</a></h3>
				</div>

				<div class="grid_4 omega">
					<h3 class="about"><a href="//www.ebi.ac.uk/about">About us</a></h3>
				</div>

			</nav>

			<section id="ebi-footer-meta">
				<p class="address">EMBL-EBI, Wellcome Trust Genome Campus, Hinxton, Cambridgeshire, CB10 1SD, UK &nbsp; &nbsp; +44 (0)1223 49 44 44</p>
				<p class="legal">Copyright &copy; EMBL-EBI 2014 | EBI is an Outstation of the <a href="http://www.embl.org">European Molecular Biology Laboratory</a> | <a href="/about/privacy">Privacy</a> | <a href="/about/cookies">Cookies</a> | <a href="/about/terms-of-use">Terms of use</a></p>	
			</section>

		</div>

    </footer>
		</div><!--! end of #wrapper -->

EBIFOOTER

    print OUT $EBIfooter;
    
    close OUT;
    $notQuiet and print STDERR "written $webDir/$file.html\n";
}

sub getWGSTable {
    my @wgsEntries;
    my $wgsEntriesQuery = $dbh->prepare(
        q{ SELECT prefix, entry_type
				       FROM cv_database_prefix
				       WHERE entry_type like 'WGS - %'
				       ORDER by prefix
				   }
    );
    $wgsEntriesQuery->execute()
      || die "Can't execute statement: $DBI::errstr";

    while ( my @results = $wgsEntriesQuery->fetchrow_array ) {
        $results[1] =~ s/^WGS - //;
        push( @wgsEntries,
              {  'PREFIX'      => "$results[0]",
                 'DESCRIPTION' => "$results[1]"
              }
        );
    }
    $wgsEntriesQuery->finish;
    my $outputTable =
        "<table style=\"font-size: 100%\">\n"
      . "\t<tr class=\"tablebody\">\n"
      . "\t\t<th></th>\n"
      . "\t\t<th>Prefix</th>\n"
      . "\t\t<th>Organism</th>\n"
      . "\t\t<th>Entries</th>\n"
      . "\t</tr>\n";
    my $rowCounter = 0;
    print "\nFound " . scalar(@wgsEntries) . " WGS projects\n";
    foreach my $entry (@wgsEntries) {

        my $wgsEntryQuery = $dbh->prepare(
            q{ SELECT sum(sequences)
                 FROM wh_wgs_entry 
                WHERE dataclass = 'WGS'
                  AND wgsid = ?
		  HAVING sum(sequences) > 0
	       }
        ); 
        $wgsEntryQuery->execute($entry->{PREFIX})
	    || die "Can't execute statement: $DBI::errstr";;
#         Slower but more up-to-date
#         my $wgsEntryQuery = $dbh->prepare(
#             q{ select count(*) 
# 		   FROM dbentry d
# 		   WHERE d.primaryacc# like ?
# 		   AND d.statusid = 4 -- ie 'public'
# 		   AND d.dataclass = 'WGS' -- exclude MGA 5 letter prefix entries
# 	       }
#         ); # could use select sequences from wh_wgs_entry where dataclass = 'WGS' and wgsid = ? (no wildcard)
#         $wgsEntryQuery->execute( 1, $entry->{PREFIX} . "%" );

        my $wgsEntryCount = 0;
        while ( my @results = $wgsEntryQuery->fetchrow_array ) {
            $wgsEntryCount = $results[0];
            $testing && print "wgs ".$entry->{PREFIX}." = $wgsEntryCount public entries\n";
        }
        $wgsEntryQuery->finish;
	    if ($entry->{DESCRIPTION} =~ /desc to add/) {
		print "!!  wgs " . $entry->{PREFIX} . " (" . $entry->{DESCRIPTION} . ") has $wgsEntryCount entries and needs a description\n";
		print LOG "<li><font color=\"red\">wgs " . $entry->{PREFIX} . " (" . $entry->{DESCRIPTION} . ") has $wgsEntryCount entries and needs a description</font></li>\n";
	    }
        if ( $wgsEntryCount > 0 ) {
	    my $wgsMasterAc = $entry->{PREFIX} . '00' . '000000';

            $outputTable .= "<tr>\n"
              . "\t\t<td >"
              . ++$rowCounter
              . "</td>\n"
              . "\t\t<td class=\"tdcenter\">". makeEntryLink($wgsMasterAc,'default',$entry->{PREFIX}) . "</td>\n"
              . "\t\t<td>&nbsp;$entry->{DESCRIPTION}</td>\n" . "\t\t<td >" . commify($wgsEntryCount) . "</td>\n" . "\t</tr>\n";
        }
        else {
#            print "  wgs " . $entry->{PREFIX} . " (" . $entry->{DESCRIPTION} . ") has no public entries\n";
#            print LOG "wgs <tt>" . $entry->{PREFIX} . "</tt> &quot;<b>" . $entry->{DESCRIPTION} . "</b>&quot; has no public entries<br/>\n";
        }
    }
    print "\n";
    $outputTable .= "</table>\n";
    return $outputTable;
}

sub getLastFortyGenomes {
    my @lastEntries;
    my $lastGenomeEntries = $dbh->prepare(
        q{
         SELECT gs.descr, gs.primaryacc#, b.version, b.seqlen, to_char(d.FIRST_PUBLIC, 'DD-MON-YYYY'), to_char(d.FIRST_PUBLIC, 'YYYYMMDD')
		FROM genome_seq gs, bioseq b, dbentry d, cv_status cvs
		WHERE gs.primaryacc# = d.primaryacc#
		AND gs.primaryacc# = b.seq_accid
		AND d.statusid = cvs.statusid
		AND cvs.status = 'public'
                AND d.FIRST_PUBLIC is not NULL
		GROUP BY gs.descr, gs.primaryacc#, b.version, b.seqlen, to_char(d.FIRST_PUBLIC, 'DD-MON-YYYY'), to_char(d.FIRST_PUBLIC, 'YYYYMMDD')
		ORDER BY to_char(d.FIRST_PUBLIC, 'YYYYMMDD')
		DESC
	    }
    );
    my $i = 1;
    $lastGenomeEntries->execute
	|| die "Can't execute statement: $DBI::errstr";
    
    while ( ( my @results = $lastGenomeEntries->fetchrow_array ) and ( $i++ <= 40 ) ) {
	push( @lastEntries,
	      {  'DESCRIPTION' => "$results[0]",
		 'AC_NUMBER'   => "$results[1]",
		 'VERSION'     => $results[2],
		 'DATETEXT'    => $results[4]
		 }
	      );
    }
    $lastGenomeEntries->finish;
    my $outputTable =
        "<table style=\"font-size: 100%\">\n"
      . "\t<tr>\n"
      . "\t\t<th>Date</th>\n"
      . "\t\t<th>Accession</th>\n"
      . "\t\t<th>Description</th>\n"
      . "\t</tr>\n";
    foreach my $entry (@lastEntries) {
        $outputTable .=
            "\t<tr>\n\t\t<td class=\"tdcenter\">$entry->{DATETEXT}</td>\n"
          . "\t\t<td class=\"tdcenter\">" 
	  . makeEntryLink($entry->{AC_NUMBER},'default',"$entry->{AC_NUMBER}.$entry->{VERSION}")
	  . "</td>\n"
          . "\t\t<td>&nbsp;$entry->{DESCRIPTION}\n"
	  . "\t</tr>\n";
    }
    $outputTable .= "</table>\n";
    return $outputTable;
}

# getGenomeEntriesOfCat # gets all the entries from the genomes table in the database
sub getGenomeEntriesOfCat {
    my $genomeCat = shift;
    my @resultsArray;
    my $genomeEntriesOfCat;
    if ( $genomeCat == 3 ) {
        $genomeEntriesOfCat = $dbh->prepare(
            q{
	    SELECT so.organism, gs.descr, gs.primaryacc#, b.seqlen, b.seqid, d.entry_type, d.ext_ver, to_char(gs.TIMESTAMP, 'YYYYMMDD'), to_char(gs.TIMESTAMP, 'DD-MON-YYYY'), to_char(nvl(d.EXT_DATE, d.TIMESTAMP), 'YYYYMMDD'), b.version
		FROM genome_seq gs, bioseq b, sourcefeature so, seqfeature f, dbentry d, cv_status cvs
		WHERE gs.category  IN (3,9,10,11)
		AND gs.primaryacc# = d.primaryacc#
		AND gs.primaryacc# = b.seq_accid
		AND b.seqid        = f.bioseqid
		AND f.featid       = so.featid
		AND d.statusid = cvs.statusid
		AND cvs.status = 'public'
		AND so.primary_source = 'Y'
		GROUP BY so.organism, gs.descr, gs.primaryacc#, b.seqlen, b.seqid, d.entry_type, d.ext_ver, to_char(gs.TIMESTAMP, 'YYYYMMDD'), to_char(gs.TIMESTAMP, 'DD-MON-YYYY'), to_char(nvl(d.EXT_DATE, d.TIMESTAMP), 'YYYYMMDD'), b.version
		ORDER BY gs.primaryacc#
	    }
        );
    }
    elsif ( $genomeCat == 6 ) {
        $genomeEntriesOfCat = $dbh->prepare(
            q{
	    SELECT so.organism, gs.descr, gs.primaryacc#, b.seqlen, b.seqid, d.entry_type, d.ext_ver, to_char(gs.TIMESTAMP, 'YYYYMMDD'), to_char(gs.TIMESTAMP, 'DD-MON-YYYY'), to_char(nvl(d.EXT_DATE, d.TIMESTAMP), 'YYYYMMDD'), b.version
		FROM genome_seq gs, bioseq b, sourcefeature so, seqfeature f, dbentry d, cv_status cvs
		WHERE gs.category  IN (3,9,10,11,6)
		AND gs.primaryacc# = d.primaryacc#
		AND gs.primaryacc# = b.seq_accid
		AND b.seqid        = f.bioseqid
		AND f.featid       = so.featid
		AND d.statusid = cvs.statusid
		AND cvs.status = 'public'
		AND so.primary_source = 'Y'
		GROUP BY so.organism, gs.descr, gs.primaryacc#, b.seqlen, b.seqid, d.entry_type, d.ext_ver, to_char(gs.TIMESTAMP, 'YYYYMMDD'), to_char(gs.TIMESTAMP, 'DD-MON-YYYY'), to_char(nvl(d.EXT_DATE, d.TIMESTAMP), 'YYYYMMDD'), b.version
		ORDER BY gs.primaryacc#
	    }
        );
    }
    else {
        $genomeEntriesOfCat = $dbh->prepare(
            q{
	    SELECT so.organism, gs.descr, gs.primaryacc#, b.seqlen, b.seqid, d.entry_type, d.ext_ver, to_char(gs.TIMESTAMP, 'YYYYMMDD'), to_char(gs.TIMESTAMP, 'DD-MON-YYYY'), to_char(nvl(d.EXT_DATE, d.TIMESTAMP), 'YYYYMMDD'), b.version
		FROM genome_seq gs, bioseq b, sourcefeature so, seqfeature f, dbentry d, cv_status cvs
		WHERE gs.category  = ?
		AND gs.primaryacc# = d.primaryacc#
		AND gs.primaryacc# = b.seq_accid
		AND b.seqid        = f.bioseqid
		AND f.featid       = so.featid
		AND d.statusid = cvs.statusid
		AND cvs.status = 'public'
		AND so.primary_source = 'Y'
		GROUP BY so.organism, gs.descr, gs.primaryacc#, b.seqlen, b.seqid, d.entry_type, d.ext_ver, to_char(gs.TIMESTAMP, 'YYYYMMDD'), to_char(gs.TIMESTAMP, 'DD-MON-YYYY'), to_char(nvl(d.EXT_DATE, d.TIMESTAMP), 'YYYYMMDD'), b.version
		ORDER BY gs.primaryacc#
	    }
        );
        $genomeEntriesOfCat->bind_param( 1, $genomeCat );
    }
    $genomeEntriesOfCat->execute()
	|| die "Can't execute statement: $DBI::errstr";
    my $multiSource = "";    # holds the AC when within a multisource entry
    while ( my @results = $genomeEntriesOfCat->fetchrow_array ) {
	my @magpiIDs = SeqDBUtils2::ac_2_magpiIDs($dbh,$results[2]);
        push( @resultsArray,
              {  'TAX_ID'      => $results[0],
                 'DESCRIPTION' => "$results[1]",
                 'AC_NUMBER'   => "$results[2]",
                 'SEQ_LEN'     => $results[3],
                 'SEQ_ID'      => $results[4],
                 'ENTRY_TYPE'  => $results[5],
                 'PARTS'       => 1,
                 'VERSION'     => $results[6],
                 'DATENUMBERS' => $results[7],
                 'DATETEXT'    => $results[8],
                 'VDATE'       => $results[9],
                 'SVERSION'    => $results[10],
		 'MAGPIS'      => \@magpiIDs
              }
        );
    }
    $genomeEntriesOfCat->finish;
    return @resultsArray;
}

# getGenomeEntriesFromFile # gets any additional entries from any manual input file
sub getGenomeEntriesFromFile {
    my $inputFile     = shift;
    my $resultsArray  = shift;
    my $oddEntryUrls  = shift;
    my $manualEntries = 0;
    open IN, "$inputFile"
      or die "$inputFile exists but I cannot read it\n";
    $notQuiet and print "Reading $inputFile\n";
    while (<IN>) {
        my $manualLine = $_;
        my $tax_id     = 0;
        my $de         = "";
        my $ac         = "";
        my $len        = 0;
        my $id         = 0;
        my $type       = 97;              # 97 is my default for unknown entries
        my $parts      = 0;
        my $version    = 0;
        my $dateNumber = 20030513;
        my $dateText   = "13-MAY-2003";

        if ( !( $manualLine =~ /^\s+$/ ) && !( $manualLine =~ /^\#/ ) ) {
            $manualLine =~ s/ *\t */\t/g;
            my @resultsLineArray = split /\t/, $manualLine;
            if ( $resultsLineArray[0] ne "" ) {
                $tax_id = $resultsLineArray[0];
            }
            if ( $resultsLineArray[1] ne "" ) {
                $de = $resultsLineArray[1];
            }
            if ( $resultsLineArray[2] ne "" ) {
                $ac = $resultsLineArray[2];
            }
            if ( $resultsLineArray[3] ne "" ) {
                $len = $resultsLineArray[3];
            }
            if ( $resultsLineArray[4] ne "" ) {
                $dateNumber = $resultsLineArray[4];
            }
            if ( $resultsLineArray[5] ne "" ) {
                $dateText = $resultsLineArray[5];
            }
            if ( $resultsLineArray[6] ne "" ) {
                $type = $resultsLineArray[6];
            }

            if ( $ac =~ /^[a-zA-Z]{1,2}[0-9]{4,8}$/ ) {
                print "manual entry for dbentry $resultsLineArray[2]\n";
                my @idLenDe = ac2IDLenDe( $resultsLineArray[2] );
                $id      = $idLenDe[0];
                $len     = $idLenDe[1];
                $version = $idLenDe[4];
                if ( $de eq "" ) {
                    $de = $idLenDe[2];
                }
                $type = $idLenDe[3];
            }
            elsif ( $ac =~ /((www)|(pre))\.ensembl\./i ) {
                $type = 98;
            }
            else {
                my $location = $ac;
                $ac =~ s/.*\/(.+)\..*/$1/;
                $$oddEntryUrls{$ac} = $location;
                ( $notQuiet and print "$ac is at $location\n" );

                #                $type = 99;
                # Should aleady be specified in .manual file manual fake expanded yeast entries are type 97
            }

            # Get lengths where AC field is actually a URL
            if ( $fullRun && $ac =~ /^http:/ ) {
                my $attempts        = 1;
                my $evaluatedLength = lengthFromWeb($ac);
                while ( ( $evaluatedLength < 0 ) && ( $attempts++ < 10 ) ) {
                    $evaluatedLength = lengthFromWeb($ac);
                    $attempts++;
                }
                if ( $attempts > 1 ) {    # Unfortnately ENSEMBL can take several tries
                    if ( $evaluatedLength < 0 ) {
                        print LOG "<p><a href=\"$ac\"" . ">$ac</a>\n" . "<font color=\"red\">failed</font> after $attempts attempts</p>\n";
                    }
                    else {
                        print LOG "<p><a href=\"$ac\"" . ">$ac</a>\n" . "took $attempts attempts</p>\n";
                    }
                }
                $notQuiet
                  && print $ac. " = " . commify($evaluatedLength) . "bp\n";
                if ( $evaluatedLength > 0 || $len eq "" ) {
                    $len = $evaluatedLength;
                }
            }

            push( @$resultsArray,
                  {  'TAX_ID'      => $tax_id,
                     'DESCRIPTION' => "$de",
                     'AC_NUMBER'   => "$ac",
                     'SEQ_LEN'     => $len,
                     'SEQ_ID'      => $id,
                     'ENTRY_TYPE'  => $type,
                     'PARTS'       => 1,
                     'VERSION'     => $version,
                     'DATENUMBERS' => $dateNumber,
                     'DATETEXT'    => $dateText,
                     'VDATE'       => $dateNumber,
                     'SVERSION'    => 1
                  }
            );
            $manualEntries++;
        }
    }
    close IN;
    return $manualEntries;
}

# getTaxInfo # gets tax details 
# takes taxid and returns hash {containing that organism's name, species-level taxid, GC}, and species taxid and species name
sub getTaxInfo {
    my $organism      = shift;
    my $speciesNode   = $organism; # keep fist organism as binomial unless we find a higher node is species
    my $speciesName   = "";
    my $code          ;
    my $organismName  = "";

    my $getTaxInfo = $dbh->prepare(
        q{
	SELECT    s.tax_id, l.species, l.leaf, l.gc_id
	  FROM  ntx_lineage l, ntx_synonym s
	    WHERE l.tax_id     = ?
	    AND   l.species    = s.name_txt
	}
    );#	    AND   s.name_class = 'scientific name' would probably do more harm than good


    $getTaxInfo->execute($organism )|| die "Can't execute statement: $DBI::errstr";
    ($speciesNode, $speciesName, $organismName, $code) = $getTaxInfo->fetchrow_array;
    $getTaxInfo->finish;
    if (!(defined($code))){
	print "TAX ALERT: no genetic code for organism $organismName (taxid:$organism)\n";
    }

    # Plasmids are classified as a species, but we wish to group them as simply 'plasmid'
    if (    ( $organismName =~ /[Pp]lasmid\s/ )
         or ( $organismName eq "eukaryotic plasmids" ) )
    {
	$speciesNode = 2435;
	$speciesName = "broad-host-range plasmids";
    }

    my $taxInfoItem = { 'ORGANISM' => "$organismName",
			'BINOMIAL' => $speciesNode,
			'CODE'     => $code
			};
    return ( $taxInfoItem, $speciesNode, $speciesName);  ###### to finish
}

# ac2IDLenDe # Provides additional entry info for any extra entries that only have the AC
sub ac2IDLenDe {
    my $ac = shift;
    my $ac2IDLenDe = $dbh->prepare(
        q{
	SELECT b.seqid, b.seqlen, de.text, d.entry_type, d.ext_ver
	    FROM bioseq b, dbentry d, description de
	    WHERE d.primaryacc# = ?
	      AND d.primaryacc# = b.seq_accid
	      AND b.seqid = d.bioseqid
	      AND d.dbentryid = de.dbentryid
	    GROUP BY b.seqid, b.seqlen, de.text, d.entry_type, d.ext_ver
	}
    );

    $ac2IDLenDe->execute($ac)
      || die "Can't execute statement: $DBI::errstr";

    while ( my @result = $ac2IDLenDe->fetchrow_array ) {
        if ( $result[1] eq "" ) {
            next;
        }
        else {
            $ac2IDLenDe->finish;
            return @result;
        }
    }
    print LOG "AC $ac NOT FOUND by sub ac2IDLenDe";
    $notQuiet and print "AC $ac NOT FOUND by sub ac2IDLenDe";
    return ( 0, "AC $ac NOT FOUND" );
}

# seqid2AcLenDe # provides additional entry info for any extra entries that only have the ID
sub seqid2AcLenDe {
    my $seqid = shift;
    my @acLenDe;
    my $seqid2AcLenDe = $dbh->prepare(
        q{
    SELECT b.seq_accid, b.seqlen, de.text, d.ext_ver, d.entry_type
	FROM bioseq b, description de, dbentry d
	WHERE b.seqid  = ?
	   AND b.seqid = d.bioseqid
	   AND d.dbentryid = de.dbentryid
	GROUP BY b.seq_accid, b.seqlen, de.text, d.ext_ver, d.entry_type
    }
    );

    $seqid2AcLenDe->execute($seqid )
      || die "Can't execute statement: $DBI::errstr";

    while ( my @result = $seqid2AcLenDe->fetchrow_array ) {
        if ( $result[0] eq "" ) {
            next;
        }
        else {
            $seqid2AcLenDe->finish;
            return @result;
        }
    }
    return ("NOT_FOUND', 0, 'SeqID $seqid NOT FOUND");
}

# lengthFromWeb # gets and parses ENSEMBL and manual con web pages to retreive the length
sub lengthFromWeb {
    my $URL        = shift;
    my $userAgent  = LWP::UserAgent->new;
    my $request    = HTTP::Request->new( GET => $URL );
    my $urlDataRaw = $userAgent->request($request);
    my $urlData    = $urlDataRaw->as_string;

    if ( $urlData =~ /Server Error/ ) {
        return -1;
    }
    if ( $URL =~ /ensembl/i ) {
        if ( $urlData =~ s/.*name=\"seq_region_right\"[^>]+value=\"(\d+)\".*/$1/is ) {
            return $urlData;
        }
        elsif ( $urlData =~ s/.*name=\"chr_len\" value=\"(\d+)\".*/$1/is ) {
            return $urlData;
        }
        else {
            return -1;
        }
    }
    if ( $URL =~ /genomes\/data\//i ) {
        $urlData =~ s/^.*DNA; CON; (\d+) BP.*$/$1/s;
        return $urlData;
    }
    return 0;
}

# getProteomeLinks # gets the available proteome page links
sub getProteomeLinks {
    my $proteomeLinks = shift;
    $notQuiet && print "Connecting to prot database\n";
    my $dbh = DBI->connect( 'dbi:Oracle:PROT', '/', '' ) or
      do {
        print "Can't execute statement: $DBI::errstr";
        return;
      };

    my $query = $dbh->prepare(
        q{
	    SELECT c.genome_ac, d.uri
		FROM proteomes.db_xref d, proteomes.xref2proteome x,
		proteomes.component c, proteomes.proteome p
		WHERE x.proteome_id = c.proteome_id
		AND c.proteome_id = p.proteome_id
		AND NOT p.scope = 2
		AND d.uri = x.uri
		AND d.dbname = 'EBI'
		GROUP BY d.uri, c.genome_ac
	}
    );
#	SELECT c.genome_ac, d.uri
#	    FROM proteomes.db_xref d, proteomes.xref2proteome x, proteomes.component c
#	    WHERE x.proteome_id = c.proteome_id
#	    AND d.uri = x.uri
#	    AND d.dbname = 'EBI' 
#	    GROUP BY d.uri, c.genome_ac

    $query->execute
      or do {
        print "Can't execute statement: $DBI::errstr";
        return;
      };

    while ( my @resultLine = $query->fetchrow_array ) {
        if (     ( defined( $resultLine[0] ) )
             and ( defined( $resultLine[1] ) ) )
        {
            $$proteomeLinks{ $resultLine[0] } = $resultLine[1];
        }
        else {
            print "Bad PROT result " . join( ",", @resultLine ) . "\n";
        }
    }
    $query->finish;
    $dbh->disconnect;
    print "  Disconnected from prot database with " . scalar( keys %$proteomeLinks ) . " results\n\n";
    return;
}

# conSegmentsFromWeb # gets the con segment AC numbers from manual cons on the web
sub conSegmentsFromWeb {
    my $URL = shift;
    print "$URL searched for segments\n";
    my $urlData = get $URL;
    $urlData =~ s/\n//g;
    $urlData =~ s/^.*join\(//;    # Trim front of segment listing

    #    $urlData =~ s/<\/a>(\.\d+)[^>]*$/$1/;      # Trim end of segment listing
    #    $urlData =~ s/<\/a>(\.\d+)[^<]*/$1\t/g;    # Replace anchor ends with tabs
    $urlData =~ s/<\/a>[^>]*$//;      # Trim end of segment listing
    $urlData =~ s/<\/a>[^<]*/\t/g;    # Replace anchor ends with tabs
    $urlData =~ s/<[^>]*>//g;         # Remove hrefs
    $urlData =~ s/\s$//g;             # Remove any residual end tabs!
    my @conSegments = split /\t/, $urlData;
    return @conSegments;
}

# Sort entries by 'Genus species, organism name, description' according to natural language
sub sortLines {
    my $resultsArray = shift;
    my $taxInfo      = shift;

    @$resultsArray = map { $_->[0] }
      sort {
        my @a_list = split /(\D+)/, $a->[1];
        my @b_list = split /(\D+)/, $b->[1];
        for ( my $i = 1 ; $i < @a_list ; $i++ ) {
            last if $i >= @b_list;
            my $result;
            if ( $i % 2 ) {
                $result = $a_list[$i] cmp $b_list[$i];
            }
            else {
                $result = ( $a_list[$i] || 0 ) <=> ( $b_list[$i] || 0 );
            }
            return $result if $result;
        }
        return 0;
      }
      map {
        [  $_,
           uc(     $$taxInfo{ $$taxInfo{ $_->{TAX_ID} }->{BINOMIAL} }->{ORGANISM} . "\t"
                 . $$taxInfo{ $_->{TAX_ID} }->{ORGANISM} . "\t"
                 . ( ( $_->{ENTRY_TYPE} == 98 ) ? "ENSEMBL" : " " )
		   . ($_->{'MAGPIS'}?join(",",@{$_->{'MAGPIS'}}):" ")
                 . $_->{DESCRIPTION}
           )
        ]
      } @$resultsArray;
}

# getGenomes # The main part
sub do_getGenomes {

    # should get any category parameters
    my %taxInfo;
    my %oddEntryUrls;    # actually just hold manual urls now
# For testing uncomment one or more of these lines
#   $genomeCategories{12} = "phage";
#   $genomeCategories{2} = "virus";
#   $genomeCategories{6} = "eukaryota";
#   $genomeCategories{7} = "plasmid";
#   $genomeCategories{8} = "viroid";
#   $genomeCategories{5} = "bacteria";
#   $genomeCategories{4} = "archaea";

    # Populate %proteomeLinks with AC->Proteome links
    $notQuiet
      and print "Not getting proteome links\n";
    my %proteomeLinks;
#    getProteomeLinks( \%proteomeLinks );    # Hash of $proteomeLinks{"AC"} = url
    $notQuiet
      and print "Finished not getting proteome links\n";
    $notQuiet
      and print commify( scalar( keys %proteomeLinks ) ) . " proteome links found\n\n";
    if ( scalar( keys %proteomeLinks ) == 0 ) {
        print "Cannot query for proteome links, using cached data $homeDir/proteomeLinks.stored\n";
        if ( -e "$homeDir/proteomeLinks.stored" ) {
            %proteomeLinks = %{ retrieve("$homeDir/proteomeLinks.stored") };
            $notQuiet
              and print commify( scalar( keys %proteomeLinks ) ) . " cached proteomeLinks read\n";
        }
        else {
            print "$homeDir/proteomeLinks.stored not found, quitting\n";
            lockFile("remove");
            exit 0;
        }
    }

    $notQuiet && print "Opening log file $getGenomesLogTEMP\n";

    my %genomeReviewLocations = findGenRevFiles();
    print LOG "<p>Genome Review files found on ftp server = " . commify( scalar keys %genomeReviewLocations ) . "</p>\n";

    print "\n";

    # If no genome category/ies specified use all
    if ( scalar( keys %genomeCategories ) == 0 ) {
        $notQuiet && print "Running getGenomes for all genome categories\n";
        %genomeCategories = ( 4  => 'archaea',
                              5  => 'bacteria',
                              6  => 'eukaryota',
                              3  => 'organelle',
                              12 => 'phage',
                              13 => 'archaealvirus',
                              7  => 'plasmid',
                              8  => 'viroid',
                              2  => 'virus'
        );
    }

    # 4 categories are all presented as part of category 3 !
    if (    exists( $genomeCategories{9} )
         || exists( $genomeCategories{10} )
         || exists( $genomeCategories{11} ) )
    {
        $genomeCategories{3} = "organelle";
    }

    # For each category get genome table entries
    foreach my $genomeCat ( keys %genomeCategories ) {

        # All organelle entries are done in genomeCat 3
        if ( $genomeCat == 9 || $genomeCat == 10 || $genomeCat == 11 ) {
            next;
        }

        $notQuiet && print "Processing $genomeCategories{$genomeCat}\n";
        my $eukaryota = 0;
        if ( lc( $genomeCategories{$genomeCat} ) eq "eukaryota" ) {
            $eukaryota = 1;
        }

        ( $notQuiet && print "  Getting $genomeCategories{$genomeCat} db entries\n" );
        my @resultsArray = getGenomeEntriesOfCat($genomeCat);

        print LOG "<h2>$genomeCategories{$genomeCat}</h2>";
        print LOG "<p>" . scalar(@resultsArray) . " database entries found</p>\n";

        # All manual entries are stored in genomeCategory.manual files, as tab delimited text
        # NB Note all Organelle entries should go in 'organelle.manual'
        if ( $fullRun && -e "$dataInDir/$genomeCategories{$genomeCat}.manual" ) {
            $notQuiet
              && print "Reading in the manual file " . "$dataInDir/$genomeCategories{$genomeCat}.manual\n";
            print LOG "<p>Read manual file $dataInDir/" . "$genomeCategories{$genomeCat}.manual finding \n";
            my $manualEntryCount = getGenomeEntriesFromFile( "$dataInDir/$genomeCategories{$genomeCat}.manual", \@resultsArray, \%oddEntryUrls );
            $notQuiet && print $manualEntryCount. " manual entries found\n";
            print LOG $manualEntryCount . " manual entries</p>\n";
        }

        # go through array and do stuff
        my $conEntries = 0;
        $notQuiet
          && print "  scanning results to do tax binomials and [fake] cons\n";

        # Add to %proteomeLinks with Tax_ID->Proteome links
        $notQuiet
          and print "Linking-in proteome URLs\n";
        foreach my $resultLine (@resultsArray) {
            if ( exists( $proteomeLinks{ $resultLine->{'AC_NUMBER'} } ) ) {
                $proteomeLinks{ $resultLine->{'TAX_ID'} } = $proteomeLinks{ $resultLine->{'AC_NUMBER'} };
            }
        }
        store( \%proteomeLinks, "$homeDir/proteomeLinks.stored" );

        #if ($genomeCat == 7){
        #    $taxInfo{2435} = {
        #	'ORGANISM' => 'plasmid',
        #	'BINOMIAL' => 2435
        #	};
        #}

        foreach my $resultLine (@resultsArray) {
            #	    if ($genomeCat == 7){
            #		$resultLine->{TAX_ID} = '2435';}
            #	    Originally used to make all plasmids to be OS plasmid

            # if tax node new, make node and find out parent (if not already species level)
            if ( !( exists( $taxInfo{ $resultLine->{TAX_ID} } ) ) ) {
                my @taxInfoResult = getTaxInfo( $resultLine->{TAX_ID} );

                # returns desired tax node, species-level taxid, species-level name

                $taxInfo{ $resultLine->{TAX_ID} } = $taxInfoResult[0];

                # make parent node if parent previously unseen
                if ( !( exists( $taxInfo{ $taxInfoResult[1] } ) ) ) {
                    $taxInfo{ $taxInfoResult[1] } = { 'ORGANISM' => "$taxInfoResult[2]",
                                                      'BINOMIAL' => $taxInfoResult[1],
						      'CODE'     => $taxInfo{ $resultLine->{'TAX_ID'}}->{'CODE'}
                    };
		    
                }
            }

            #	    print "$resultLine->{AC_NUMBER} is type $resultLine->{ENTRY_TYPE}\n"; ######
            # Handle manual CON files
            if ( $resultLine->{ENTRY_TYPE} == 99 ) {
                my @conSegmentEntries;
                my $conName = $resultLine->{AC_NUMBER};
                $conName =~ s/.*\/([^\.]+)\.html?/$1/;
                my @conSegments       = conSegmentsFromWeb( $oddEntryUrls{ $resultLine->{AC_NUMBER} } );
                my $segmentCount      = scalar(@conSegments);
                my $totalProteinCount = 0;

                foreach my $conSegment (@conSegments) {
                    my @acDe = ac2IDLenDe($conSegment);
                    my $proteinCount = getProteinCount( $conSegment . "." . $acDe[4] );
                    $totalProteinCount += $proteinCount;
                    push( @conSegmentEntries,
                          {  'TAX_ID'      => $resultLine->{TAX_ID},
                             'DESCRIPTION' => deTrim( $acDe[2] ),
                             'AC_NUMBER'   => $conSegment,
                             'SEQ_LEN'     => $acDe[1],
                             'SEQ_ID'      => $acDe[0],
                             'ENTRY_TYPE'  => $acDe[3],
                             'PARTS'       => 1,
                             'VERSION'     => $acDe[4]
                          }
                    );
                }
                $notQuiet
                  and print STDERR " Segments for $resultLine->{AC_NUMBER}: = $segmentCount\n";
                $resultLine->{PARTS} = $segmentCount;
                $cachedInfo{$conName}{PROTEINCOUNT} = $totalProteinCount;
                my $intro = " ";
                if ( exists $proteomeLinks{ $resultLine->{AC_NUMBER} } ) {
                    $intro .=
                        "<a href=\""
                      . $proteomeLinks{ $resultLine->{AC_NUMBER} } . "\" "
                      . "target=\"proteomeWindow\"><img alt=\"Integr8\" width=\"75\" "
                      . "height=\"50\" border =\"0\" "
                      . "src=\"http://www.ebi.ac.uk/services/images/integr8_small.gif\" /></a>\n";
                }
                $intro .= "<p>Ordered segments from the manually created " . "<a href=\"$resultLine->{AC_NUMBER}\">CON file</a></p>";
                writeOutput( "$conName", ucfirst("$resultLine->{DESCRIPTION}"),
                             "$intro", \@conSegmentEntries, 0, 0, \%taxInfo, \%oddEntryUrls, \%proteomeLinks, \%genomeReviewLocations );
            }

            # Handle proper CON/ANN files
            # Possibly should generate the con and expanded con (and gz versions)
            if (( $resultLine->{ENTRY_TYPE} eq "1" ) ||
		( $resultLine->{ENTRY_TYPE} eq "4" )){
                $conEntries++;
                my @conSegmentEntries;
                my $con2Segments = $dbh->prepare(
                    q{
                    SELECT b.seq_accid, con.component_order, b.seqlen, b.seqid, de.text, d.ext_ver, d.entry_type
                        FROM  bioseq b, scaffold con, description de, dbentry d
                        WHERE con.scaffold_acc = (select sequence_acc from bioseq where seqid = ? )
                        AND   con.contig_acc = b.sequence_acc
                        AND   b.seqid = d.bioseqid
                        AND   d.dbentryid = de.dbentryid
                        ORDER BY con.component_order
		    }
                );
                $con2Segments->execute($resultLine->{SEQ_ID})
                  || die "Can't execute statement: $DBI::errstr";

                my $segmentCount = 0;

                while ( my @con2SegmentsResults = $con2Segments->fetchrow_array ) {
                    $segmentCount++;
                    my $proteinCount = getProteinCount( $con2SegmentsResults[0] . "." . $con2SegmentsResults[5] );
                    push( @conSegmentEntries,
                          {  'TAX_ID'      => $resultLine->{TAX_ID},
                             'DESCRIPTION' => deTrim( $con2SegmentsResults[4] ),
                             'AC_NUMBER'   => $con2SegmentsResults[0],
                             'SEQ_LEN'     => $con2SegmentsResults[2],
                             'SEQ_ID'      => $con2SegmentsResults[2],
                             'ENTRY_TYPE'  => $con2SegmentsResults[6],
                             'PARTS'       => 1,
                             'VERSION'     => $con2SegmentsResults[5]
                          }
                    );
                }
                #$notQuiet
                #  and print " Segments for $resultLine->{AC_NUMBER}: = $segmentCount\n";
                $resultLine->{PARTS} = $segmentCount;
                my $intro = " ";
                if ( exists $proteomeLinks{ $resultLine->{AC_NUMBER} } ) {
                    $intro .=
                        "<a href=\""
                      . $proteomeLinks{ $resultLine->{AC_NUMBER} } . "\" "
                      . "target=\"proteomeWindow\"><img alt=\"Integr8\" width=\"75\" "
                      . "height=\"50\" border =\"0\" "
                      . "src=\"http://www.ebi.ac.uk/services/images/integr8_small.gif\" /></a>\n";
                }

                $intro .= "&nbsp;\n"
                  . "<p>Ordered segments from the "
                  . makeEntryLink($resultLine->{AC_NUMBER},'co-block',"CON entry")
                  . " $resultLine->{AC_NUMBER}\n";
                if ( defined( $oddEntryUrls{ $resultLine->{AC_NUMBER} } ) ) {
                    $intro .= " (<a href =\"$oddEntryUrls{$resultLine->{AC_NUMBER}}\">expanded version</a>)";
                }
                else {
                    $intro .= " (" . makeEntryLink($resultLine->{AC_NUMBER},'text-expanded', "expanded version") . ")";
                }

                if ( defined( $genomeReviewLocations{ $resultLine->{AC_NUMBER} } ) ) {
                    $intro .= " (<a href =\"$genomeReviewLocations{$resultLine->{AC_NUMBER}}\">Genome Review file</a>)";
                }
                $intro .= ".</p>\n";
		my $magpiString  = makeMagpiLinkString($resultLine->{'MAGPIS'});
		if ($magpiString ne '') {
		    $intro .= "<p>Genome Project: " . $magpiString . ".</p>\n";
		}
                writeOutput( "$resultLine->{AC_NUMBER}", ucfirst("$resultLine->{DESCRIPTION}"),
                             "$intro", \@conSegmentEntries, 0, 0, \%taxInfo, \%oddEntryUrls, \%proteomeLinks, \%genomeReviewLocations );
            }
        }
        print LOG "<p>$conEntries CON entries</p>\n";

        $notQuiet && print "  sorting results\n";
        sortLines( \@resultsArray, \%taxInfo );
        writeOutput( $genomeCategories{$genomeCat},
                     ucfirst( $genomeCategories{$genomeCat} ),
                     "", \@resultsArray, 1, 1, \%taxInfo, \%oddEntryUrls, \%proteomeLinks, \%genomeReviewLocations );

    }

    if ($distrust_cached_protein_count_of_zero) {
	print LOG "<hr>Distrusted any cached proteinCount of 0\n";
	print "Distrusted any cached proteinCount of 0\n";
    }
    printf LOG "<hr><p>Distrusted any proteinCount where < %.2f-%.2f of the CDS were in cached UniProt data<br>\n", $distrust_cached_protein_count_above_cds_ratio, $distrust_cached_protein_count_below_cds_ratio;
    printf "\nDistrusted any proteinCount where < %.2f of the CDS were in cached UniProt data<br>\n", $distrust_cached_protein_count_below_cds_ratio;

    if ($distrustCount > 0) {
	$distrustFraction = $distrustFraction / $distrustCount;
	printf LOG "Total of %d distrusted averaging %.2f\n<br>", $distrustCount, $distrustFraction;
	printf "Total of %d averaging %.2f\n", $distrustCount, $distrustFraction;
    }
    if ($distrustUsefulCount > 0) {
	$distrustUsefulRatio = $distrustUsefulRatio / $distrustUsefulCount;
	printf LOG "%d useful averaging %.2f\n<br>", $distrustUsefulCount, $distrustUsefulRatio;
	printf "%d useful averaging %.2f\n", $distrustUsefulCount, $distrustUsefulRatio;
    }
    if ($distrustUnusefulCount > 0) {
	$distrustUnusefulRatio = $distrustUnusefulRatio / $distrustUnusefulCount;
	printf LOG "%d useless averaging %.2f\n<br>", $distrustUnusefulCount, $distrustUnusefulRatio;
	printf "%d useless averaging %.2f\n", $distrustUnusefulCount, $distrustUnusefulRatio;
    }
    printf LOG "%d zero-cached count were improved; %d were not</p>\n<hr>\n", $distrustZeroCountUsefulCount, $distrustZeroCountUnusefulCount;
    printf "%d zero-cached count were improved; %d were not\n\n", $distrustZeroCountUsefulCount, $distrustZeroCountUnusefulCount;

    if ($testing) {
        print LOG "New files should be on the dev server\n" . "http://evo-test.ebi.ac.uk/seqdb-srv/genomes/\n";
    }
    else {
        print LOG "New files should be on the <a href=\"http://evo-test.ebi.ac.uk/genomes/\">test web server</a>\n"
          . "Please mail <a href=\"mailto:es-group\@ebi.ac.uk\">es-group\@ebi.ac.uk</a> to request it be copied over from\n"
          . "evo-test:/ebi/www/main/html/seqdb-srv/genomes/ to evo-1";
    }

    print LOG "\n</body></html>\n";
    close LOG;

    rename $getGenomesLog, $getGenomesLog . "OLD"
      || print "Cannot rename old log\n";
    rename $getGenomesLogTEMP, $getGenomesLog
      || print "Cannot rename log\n";

    #    Didn't really want to stop writing to the log but no choice if it is going to get ftp'ed successfully too
    if ($testing) {
        my $rsyncCommand = "/usr/bin/rsync -e ssh -aWruvz $webDir/ evo-test:/ebi/www/main/html/seqdb-srv/genomes/";
        print "attempting sync (I hope you have set up your ssh keys correctly).\n"
          . "log onto each machine, do \'ssh-keygen -t rsa\' to create \'~/.ssh/id_rsa\'\n"
          . "and \'cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys\'\n"
          . "$rsyncCommand\n";
        system($rsyncCommand);
        print "New files should be on the dev server\n" . "http://evo-test.ebi.ac.uk/seqdb-srv/genomes/\n";
    }
    else {
        my $rsyncCommand = "/usr/bin/rsync -e ssh -aWruvz $webDir/ evo-test:/ebi/www/main/html/seqdb-srv/genomes/";
        print "attempting sync (I hope you have set up your ssh keys correctly)\n"
          . "log onto each machine, do \'ssh-keygen -t rsa\' to create \'~/.ssh/id_rsa\'\n"
          . "and \'cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys\'\n"
          . "$rsyncCommand\n";
        system($rsyncCommand);
        print "New files should be on the dev server\n"
          . "http://evo-test.ebi.ac.uk/seqdb-srv/genomes/\n"
          . "Please mail <a href=\"mailto:es-group\@ebi.ac.uk\">es-group\@ebi.ac.uk</a> to request it be copied over from\n"
          . "evo-test:/ebi/www/main/html/seqdb-srv/genomes/ to evo-1";
    }

    #      ."and publish with\n"
    #      . "rsh web10-node1.ebi.ac.uk \\\n"
    #      . "'cd /ebi/web10/main/html/seqdb-dev/genomes;/ebi/www/main/bin/publish'\n";
    return ();
}

sub findKarynsGenomes {
    my $karynsGenomesLocations = shift;
    my @pages;

    # Read list of pages
    my $url        = "http://www.ebi.ac.uk/2can/genomes/all.html";
    my $userAgent  = LWP::UserAgent->new;
    my $request    = HTTP::Request->new( GET => $url );
    my $urlDataRaw = $userAgent->request($request);
    my @urlData    = split /\n/, $urlDataRaw->as_string;
    foreach my $dataLine (@urlData) {
        if ( $dataLine =~ /<td class="leftsubheading"><a *href=\"([^\"]+)\"/ ) {
            push( @pages, $1 );
        }
    }
    $notQuiet
      and print commify( scalar(@pages) ) . " Karyn's Genomes pages found\n\n";

    # Read each page from list and look for taxids in it
    foreach my $page (@pages) {
        my $url = "http://www.ebi.ac.uk/2can/genomes/" . $page;
        $request    = HTTP::Request->new( GET => $url );
        $urlDataRaw = $userAgent->request($request);
        @urlData    = split /\n/, $urlDataRaw->as_string;
        foreach my $dataLine (@urlData) {
            if ( $dataLine =~ /newt\/display\?search=(\d+)\"/ ) {
                $$karynsGenomesLocations{"$1"} = $page;
            }
        }
    }
    return;
}




