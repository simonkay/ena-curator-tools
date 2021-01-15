#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
use strict;
use DBI;
use DBD::Oracle;

use constant {EXT     => '.upd',
              DELETED => 'deleted',
              EC_LIST => '/ebi/production/seqdb/embl/tools/curators/scripts/collab/ec_lists/ec_list'};


main();

sub main {
  unless ( -f( EC_LIST ) ) {
    die "ERROR: missing list of ec numbers in ". EC_LIST ."\n\n";
  }

  my $fname = get_args();

  my $ec_numbers_hr = get_ec_numbers_hr();

  transform_file( $fname, $ec_numbers_hr );
}


sub get_ec_numbers_hr {
  my %ec_numbers;
  
  open( IN, "<", EC_LIST ) or
    die "ERROR: Can`t open '". EC_LIST ."for reading:\n$!\n";

  while ( <IN> ) {

    if ( m/^(\S+)\s+(\S+)$/ ) {

      $ec_numbers{$1} = $2;

    } else {

      die "ERROR: wrong line format in '" . EC_LIST . "':\n$_\n";
    }
  }

  # ENAPRO trumps the ec_list - should be handled in production of ec_list, or maybe a weekly comparison
  my $login = "ENAPRO";
  my %attr = (PrintError => 0,
	      RaiseError => 0,
	      AutoCommit => 0);
  my $dbh = DBI->connect('dbi:Oracle:' . $login, '/', '', \%attr)
      or die "Can't connect to database to retreive legal ECs: $DBI::errstr";
  my $sth = $dbh->prepare(
			  q{
			      SELECT ec_number
                                from cv_ec_numbers 
                               WHERE valid = 'Y'
			      });
  $sth->execute();
  while (my $ec_from_db = $sth->fetchrow_array) {
      if(defined($ec_numbers{$ec_from_db})) {
	  # consider comparing and reporting
	  if ($ec_numbers{$ec_from_db} ne $ec_from_db) {
	      printf STDERR "\"%s\" would be remapped to \"%s\" even though ENAPRO does not need us to\n", 
	      $ec_from_db, $ec_numbers{$ec_from_db};
	  }
      } else {
	   $ec_numbers{$ec_from_db} = $ec_from_db;
	   if ($ec_from_db !~ /\-$/) {
#	       print STDERR "added to list $ec_from_db\n"; # too many at this moment due to bad parsing of ec files
	   }
      }
  }
  $sth->finish();
  $dbh->rollback();
  $dbh->disconnect;
  return (\%ec_numbers);
}


sub transform_file {
    my ( $fname, $ec_numbers_hr ) = @_;

    my ( $ec_line_start, $note_start );
    my $ecQualCount          = 0;
    my $ecQualUnknownCount   = 0;
    my $ecQualRemappingCount = 0;
    my $ecQualDeletedCount   = 0;


    open( IN, "<", $fname ) or 
	die "ERROR: Can`t open '$fname' for reading:\n$!\n";

    open( OUT, ">", $fname.EXT ) or
	die "ERROR: Can`t open '$fname" . EXT . "' for writing:\n$!\n";

    $ec_line_start = "";

    while ( my $line = <IN> ) {
	
	# check if file is in embl or ncbi format
	if ($ec_line_start eq "") {
	    
	    print STDERR "ENTRY start line = $line\n";

	    if ( $line =~ /^ID/ ) {
		$ec_line_start = 'FT                   /EC_number=';
		$note_start    = 'FT                   /note=';
	    }
	    else {
		$ec_line_start = '                     /EC_number=';
		$note_start    = '                     /note=';
	    }
	}
	
        # if it is an EC line
	if ( $line =~ /^[F ][T ]                   \/EC_number=\"(.+)\"/ ) {
	    $ecQualCount++;
	    my $ec = $1;
	    $ec =~ s/^EC ?//;

	    if ( my $new_ec = $ec_numbers_hr->{$ec} ) {
		if ( $new_ec eq DELETED ) {
		    
		    $line = "$note_start\"deleted EC_number $ec\"\n";
		    printf STDERR "EC %s deleted\n", $ec;
		    $ecQualDeletedCount++;
		    
		} else {
		    
		    if ($line =~ s/^[^"]+\"(([0-9]+\.[0-9]+)\.1-\.-)\"/\"$2.-.-\"/) {
                        #"
			$line = $ec_line_start.$line;
			$ecQualRemappingCount++;
			print STDERR "Change Made to EC_number(1): $1  ->  $2.-.-\n"; 
		    }
		    else {
			if ($new_ec ne $ec) {
			    $ecQualRemappingCount++;
			    print STDERR "Change Made to EC_number: $ec  ->  $new_ec\n";
			}
			$line = "$ec_line_start\"$new_ec\"\n";
		    }
		}
	    }
	    else {
		$line = "$note_start\"unknown EC_number=$ec\"\n";
		printf STDERR "Unknown EC_number found: %s\n", $ec;
		$ecQualUnknownCount++;
	    }
	}
	print( OUT $line );
    }
    
    close( OUT );
    close( IN );
    printf STDERR "%d EC numbers found: %d remapped, %d marked deleted and %d unknown\n", 
			$ecQualCount,
			$ecQualRemappingCount,
			$ecQualDeletedCount,
			$ecQualUnknownCount;
}


sub get_args {
  my ( $fname ) = @ARGV;

  my $USAGE = "update_ec_numbers <file name>\n".
              "  the list of ec numbers is in ". EC_LIST ."\n\n";

  if ( ! -e $fname ) {
       die $USAGE;
  
  } else {
    return ($fname);
  }
}
     
