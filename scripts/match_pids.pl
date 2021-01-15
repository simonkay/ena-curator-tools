#!/ebi/production/seqdb/embl/tools/bin/perl
#
#

use strict;
use warnings;

use DBI;
use Utils qw(my_open my_close);

use EMBLentry::FeatureTable;
use EMBLentry::Feature;
use EMBLentry::Qualifier;
use EMBLentry::FeatureParser;
use EMBLentry::Writer;

main();

sub main {

  my( $dbconn, $flatfile, $accnosFile ) = getArgs();
  my $referenceQuals = getReferenceCDS( $dbconn, $accnosFile );
  my $outFh = my_open( ">$flatfile.out" );
  matchCDS( $outFh, $flatfile, $referenceQuals );
  my_close( $outFh );
}

sub matchCDS {
  my ( $outFh, $flatfile, $referenceCDS ) = @_;

  parse_entry(
    $flatfile,
    sub {
      compareCDS( @_, $referenceCDS, $outFh )
    },
    sub {
      print( $outFh $_[0] );
    }
  );

  sub compareCDS {

    my EMBLentry::FeatureTable $ft = shift( @_ );
    my ( $referenceCDS, $outFh ) = @_;

    my $allFeatures = $ft->{features};
    foreach my EMBLentry::Feature $thisFeature ( @$allFeatures ) {

      if ( $thisFeature->{key} eq 'CDS' ) {

        my $pid = getMatchingPID($referenceCDS, $thisFeature);
        if ( $pid ) {
          
          my EMBLentry::Qualifier $pidQual = EMBLentry::Qualifier->new();
          $pidQual->{name} = 'protein_id';
          $pidQual->{value} = "\"$pid\"";
          $thisFeature->addQualifier( $pidQual );
        }
      }
      dumpFeature( $outFh, $thisFeature );
    }
  }
}

sub getMatchingPID {
  # Compares (in order):
  #  1) /locus_tag, /old_locus_tag
  #  2) /gene
  #  3) /translation
  #  4) /product
  #

  my ( $referenceCDS, $cds ) = @_;

  my @quals = qw(locus_tag gene translation product);
  # qualifiers used for comparison (in order)

  my $thePid;
  foreach my $qual ( @quals ) {

    my $cdsQuals = $cds->{qualifiersByName}{$qual};
    my $found = 0;

    foreach my EMBLentry::Qualifier $thisCdsQual ( @$cdsQuals ) {

      my $value = $thisCdsQual->{value};
      if ( my $pid = $referenceCDS->{$qual}{$value} ) {

        ++$found;
        $thePid = $pid;
      }
    }
    if ( $found > 1 ) {

      print( STDERR "WARNING: while looking at /$qual I found more than one ($found)\n" );
      print( STDERR "WARNING:  protein_id matching:\n" );
      dumpFeature( \*STDERR, $cds );
      print( STDERR "================\n" );
      return undef;

    } elsif ( $found == 1 ) {

      print( STDERR "LOG: matched protein_id $thePid while looking at /$qual for:\n" );
      dumpFeature( \*STDERR, $cds );
      print( STDERR "================\n" );
      return $thePid;
    }
  }

  return undef;
}


sub getReferenceCDS {
  # Return an arrayref of all CDS for entries listed in
  #  the file <$accnoFile>
  #
  my ( $dbconn, $accnosFile ) = @_;
  $dbconn =~ s/^\/?\@?//;
  my $dbh = DBI->connect( "dbi:Oracle:$dbconn",'', '',
    { RaiseError => 1,
      PrintError => 0,
      AutoCommit => 0 } );
  $dbh->{LongReadLen} = 999999999999;
  my %allQuals;
  my $inFh = my_open( $accnosFile );
  while ( my $accno = readline($inFh) ) {
    chomp( $accno );
    addEntryCDS( $dbh, $accno, \%allQuals );
  }
  my_close( $inFh );
  $dbh->disconnect();

  return \%allQuals;
}

sub addEntryCDS {
  # (Only the '/locus_tag', '/old_locus_tag', '/gene',
  # '/translation', '/product' qualifiers are considered).
  #
  my ( $dbh, $accno, $allQuals ) = @_;


  my $translationSql = "SELECT c.PROTEIN_ACC, c.VERSION, c.SEQUENCE
                          FROM dbentry d
                          JOIN cdsfeature c ON d.bioseqid = c.bioseqid
                        WHERE d.primaryacc# = ?";


  my $translationSth = $dbh->prepare($translationSql);
  $translationSth->execute($accno);

  while ( my $row = $translationSth->fetchrow_arrayref() ) {

    my( $pid, $version, $sequence ) = @$row;

    if ( exists($allQuals->{translation}{"\"$sequence\""}) ) {
      # We do not consider repeated values
      $allQuals->{translation}{$sequence} = 0;
    } else {
      $allQuals->{translation}{$sequence} = "$pid.$version";
    }

    my $qualifiersSql = # We treat 'old_locus_tag' and 'locus_tag'
                        #  as being the same
    "SELECT decode(cv.fqual, 'old_locus_tag', 'locus_tag', cv.fqual), fq.text
       FROM cdsfeature c
            JOIN
            feature_qualifiers fq ON c.featid = fq.featid
            JOIN
            cv_fqual cv ON fq.fqualid = cv.fqualid
      WHERE fq.fqualid in (12,84,88,19)
        AND c.protein_acc = ?
     ORDER BY cv.fqual";


    my $qualifiersSth = $dbh->prepare( $qualifiersSql );
    $qualifiersSth->execute($pid);

    while ( my ($name, $value) = $qualifiersSth->fetchrow_array() ) {

      $value = "\"$value\"";
      if ( exists($allQuals->{$name}{$value}) ) {
        # We do not consider repeated values
        $allQuals->{$name}{$value} = 0;
      } else {

        $allQuals->{$name}{$value} = "$pid.$version";
      }
    }
  }
}


sub getArgs {

  my( $dbconn, $flatfile, $accnosFile ) = @ARGV;
  unless ( defined($accnosFile) ) {

    disable diagnostics;
    die( 
      "USAGE: $0 <db connection> <flatfile name> <accnos name>\n".
      "  Writes a file <flatfile name>.out containing pids for\n".
      "  CDS that matched those in the entries named in <accnos name>.\n".
      "\n" );
  }

  return ( $dbconn, $flatfile, $accnosFile );
}

