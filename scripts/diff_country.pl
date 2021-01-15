#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/diff_country.pl,v 1.9 2010/10/05 11:05:14 faruque Exp $
#
# (C) EBI 1999
#
# diff_country
# compare ncbi country list and table cv_country; give accordant hits from un and
# cia lists for differences
#
# MODIFICATION HISTORY:
#
# 28-SEP-1999 Carola Kanz         Created.
#===============================================================================

use LWP::Simple;   
use LWP::UserAgent;
use DBI;
use strict;
use ENAdb;


# initialize urls.
my $url_ncbi = "http://www.ncbi.nlm.nih.gov/projects/collab/country.html";
 
sub get_embl_list($){
    my $database = shift;
    # connect to database.

    my %attr   = ( PrintError => 0,
		   RaiseError => 0,
		   AutoCommit => 0 );
    
    my $dbh = ENAdb::dbconnect($database,%attr)
	|| die "Can't connect to database: $DBI::errstr";
    
    my %list_from_embl;
    my $sth = $dbh->prepare("SELECT descr, new FROM cv_country order by descr");
    $sth->execute()
	|| die "database error: $DBI::errstr\n ";
    while (my ($country, $new) = $sth->fetchrow_array) {
	$list_from_embl{$country} = $new;
    }
    $sth->finish();
    $dbh->disconnect();
    print "EMBL has ".scalar(keys %list_from_embl)." countries\n";
    return %list_from_embl;
}
    

sub get_ncbi_list ($){
    my $url = shift;

    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new( GET => $url);
    my $response = $ua->request( $request );
    my $page = $response->as_string;

    my %list_from_ncbi;
    my ( @lines );
    @lines = split /\n/, $page;
    
    while ( @lines && $lines[0] !~ / Scope:          / ) {
	shift ( @lines );
    }
    while ( @lines && $lines[0] !~ /^<li>/ ) {
	shift ( @lines );
    }
    my $new = "Y";
    while ( @lines && $lines[0] !~ /<HR>/i ) { 
	$lines[0] =~ s/\s*<[^>]*>\s*//g;
	$lines[0] =~ s/(^\s*)|(\s*$)//g;
	if($lines[0] =~ s/Historical Country Names//g) {
	    $new = "N"; # NB Historic section is at the end
	}
	if ( $lines[0] =~ /\S/ ) {
	    $list_from_ncbi{$lines[0]} = $new;
	}
	shift ( @lines );
    }
    if (!(%list_from_ncbi)) {
	die ("Could not parse ncbi country page $url\n\n$page\n");
    }
    print "NCBI has ".scalar(keys %list_from_ncbi)." countries\n";
    return %list_from_ncbi;
}

sub compare_embl_and_ncbi (\%\%) {
  my $rh_list_from_embl = shift;
  my $rh_list_from_ncbi = shift;
  my %problems;

  print "\nChecking for differences between EMBL and NCBI country lists:\n";

  # loop over the ncbi countries
  foreach my $country ( sort keys %{$rh_list_from_ncbi} ) {
      # check on both lists
      if ( defined ( ${$rh_list_from_embl}{$country} ) ) {
          # check on both lists 
	  if ((${$rh_list_from_embl}{$country} eq 'N') &&
	      (${$rh_list_from_ncbi}{$country} eq 'Y')){
	      $problems{$country} = "Deprecated at EMBL but not at NCBI";
	  }
      }
      # if the country does not exist, print it on the report
      else {
	  $problems{$country} = "in NCBI but not EMBL";
      }
  }

  # loop over the embl countries
  foreach my $country ( sort keys %{$rh_list_from_embl} ) {
      # check on both lists
      if ( defined ( ${$rh_list_from_embl}{$country} ) ) {
          # check on both lists 
	  if ((${$rh_list_from_ncbi}{$country} eq 'N') &&
	      (${$rh_list_from_embl}{$country} eq 'Y')){
	      $problems{$country} = "Deprecated at NCBI but not at EMBL";
	  }
      }
      # if the country does not exist, print it on the report
      else {
	  $problems{$country} = "in EMBL but not NCBI";
      }
  }

  foreach my $country ( sort keys %problems ) {
      printf "\"%s\": %s\n", $country, $problems{$country};
  }
  print "\nComparison completed\n";
}

sub main($$) {
    my $database = shift;
    my $url_ncbi = shift;

    my %list_from_embl = get_embl_list($database);

    my %list_from_ncbi = get_ncbi_list($url_ncbi);

# compare embl and ncbi country lists

    compare_embl_and_ncbi ( %list_from_embl, %list_from_ncbi );
}

#----------------------------------------------------------------------------------

# handle command line.
my ( $database ) = $ARGV[0];
if (!(defined($database))) { 
    $database = "PRDB1";
}

main($database,$url_ncbi);



