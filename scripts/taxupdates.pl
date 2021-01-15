#!/ebi/production/seqdb/embl/tools/bin/perl -w

# taxupdates.pl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/taxupdates.pl,v 1.8 2011/11/29 16:33:38 xin Exp $
#
#  DESCRIPTION:
#
#  Reads a file of accession numbers that have taxonomy updates
#  and adds a tax.upd file to each affected ds.
#  NB If tax.upd is already present it appends an appropriate number to the filename
#
#  MODIFICATION HISTORY:
#
#  05-07-2006 Nadeem Faruque   Created
#
#===============================================================================

use strict;
use DBI;
use dbi_utils;
use SeqDBUtils;

#select(STDERR); $| = 1; # make unbuffered
select(STDOUT);
$| = 1;    # make unbuffered

########### Globals - constants ###########

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage =
  "\n PURPOSE: Reads a file of accession numbers that have taxonomy updates\n"
  . "          and adds a tax.upd file to each affected ds.\n"
  . "          NB If tax.upd is already present it appends an appropriate number to the filename\n\n"
  . " USAGE:   $0\n"
  . "          [user/password\@instance] filename_of_accessions location_of_update_file\n\n"
  . "   <user/password\@instance>\n"
  . "                   where <user/password> is taken automatically from\n"
  . "                   current unix session\n"
  . "                   where <\@instance> is either \@enapro or \@devt\n\n";
my $time1;
my $login;
my $acFile;
my $textFile;
my $textFileName = "tax.upd";
my $logfile      = "taxupdate.log";
my @logdata;
my $quiet = 0;

#################################
# Subroutines
#################################

sub getAccessionNumberList($) {
    my $acFile = shift;
    my %acList;    # hash instead of list to uniquify
    open( ACLIST, "<$acFile" ) || die "cannot accession number list open $acFile: $!\n";
    while (<ACLIST>) {
        chomp;
        my $ac = uc($_);
        $ac =~ s/(^\s+)|(\s+$)//g;
        if ( $ac =~ /^[A-Z]{1,4}[0-9]{5,9}$/ ) {
            $acList{$ac} = 1;
        }
        else {
            my $error = "!! Invalid AC in $acFile \"$ac\"\n";
            print LOG $error;
            $quiet || print $error;
        }
    }
    close(ACLIST);
    return ( keys %acList );
}

sub acs2dss($@) {
    my ( $login, @acList ) = @_;
    my %dsList;    # hash instead of list to uniquify
    my $dbh = dbi_ora_connect($login);
    foreach my $ac (@acList) {
        my @result = dbi_getrow(
            $dbh, "select idno
                                  from  ACCESSION_DETAILS
                                  where ACC_NO = upper('$ac')"
        );
        if ( defined( $result[0] ) ) {
            $dsList{ $result[0] } = 1;
        }
        else {
            my $error = "!! No DS found for AC $ac\n";
            print LOG $error;
            $quiet || print $error;
        }
    }
    return ( keys %dsList );
}

sub slurpTextFile($) {
    my $textFile = shift;
    open( TXT, "< $textFile" ) || die "cannot open text file $textFile: $!\n";
    my $textFileContents = do { local $/; <TXT> };
    close(TXT);
    return $textFileContents;
}

sub reviveDS($$$) {
    my $ds         = shift;
    my $dsDir      = shift;
    my $login      = shift;
    my $testSuffix = " ";
    if ( $login !~ /PRDB1/i ) {
        $testSuffix = " test";
    }
    if ( !( -d "$dsDir/$ds" ) ) {
        if ( $ds != 0 ) {
	    print "/ebi/production/seqdb/embl/tools/curators/ds.csh $ds $testSuffix\n";
            my $dsCreationText = system("/ebi/production/seqdb/embl/tools/curators/ds.csh $ds $testSuffix");
        }
	if (!( -d "$dsDir/$ds" )){
	    my $message = "!Tried but seem to have failed to revive $dsDir/$ds\n";
	    $quiet || print $message;
	    print LOG $message;
	}
	else {
	    my $message = "Sucessfully dearchived $dsDir/$ds\n";
	    $quiet || print $message;
	    print LOG $message;
	}
    }
    return;
}

sub writeTextFileToDS($$\$) {
    my $ds    = shift;
    my $dsDir = shift;
    my $text  = shift;
    if ( -d "$dsDir/$ds" ) {
        my $file = "$dsDir/$ds/$textFileName";
        if ( -e $file ) {
            my $suffix = 2;
            while ( -e $file . $suffix ) {
                $suffix++;
            }
            $file = $file . $suffix;
        }
        open( TEXTFILE, "> $file" ) || die "Could not create the file $file";
        print TEXTFILE $$text;
        close(TEXTFILE);
        my $message = " $file made\n";
        print LOG $message;
        $quiet || print $message;
    }
    else {
        my $error = "!! DS $ds cannot be made\n";
        print LOG $error;
        $quiet || print $error;
    }
}

sub taxUpdates($$$) {
    my $acFile   = shift;
    my $login    = shift;
    my $textFile = shift;
    my $message;

    my $dsDir = $ENV{"DS_TEST"};
    if ( $login =~ /PRDB1/i ) {
        $dsDir = $ENV{"DS"};
    }

    my @acList = sort { $a cmp $b } getAccessionNumberList($acFile);
    $message = ( scalar @acList ) . " AC's found in $acFile\n";
    $quiet || print $message;
    print LOG $message;

    my $textfile = slurpTextFile($textFile);
    $message = "Read text file $textFile\n";
    $quiet || print $message;
    print LOG $message;

    my @dsList = sort { $a <=> $b } acs2dss( $login, @acList );
    $message = ( scalar @dsList ) . " DS's found in $acFile\n";
    $quiet || print $message;
    print LOG $message;

    foreach my $ds (@dsList) {
        reviveDS( $ds, $dsDir, $login );
        writeTextFileToDS( $ds, $dsDir, $textfile );
    }
}

################################################
# Main body, handle args and call &taxUpdates
################################################

if ( @ARGV == 3 ) {
    ( $ARGV[0] =~ /^-h/i )
      && die $usage;
    $login = $ARGV[0];
    my @unflaggedArguments;
    foreach my $arg (@ARGV) {
        if ( !( $arg =~ /^-/ ) ) {
            push ( @unflaggedArguments, $arg );
        }
        elsif ( $arg =~ /-q(uiet)?/i ) {
            $quiet = 1;
        }
    }
    if ( scalar(@unflaggedArguments) == 3 ) {
        ( $login, $acFile, $textFile ) = @unflaggedArguments;
    }
    else {
        die sprintf "%d arguments found, 3 arguments required\n%s", ( scalar @unflaggedArguments ), $usage;
        die "$usage";
    }
}
else {
    die sprintf "%d arguments found, 3 arguments required\n%s", @ARGV, $usage;
}
open( LOG, "> $logfile" ) || die "Could not create the file $logfile";

taxUpdates( $acFile, $login, $textFile );

close(LOG);

exit;

