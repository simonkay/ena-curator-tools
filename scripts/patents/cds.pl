#!/ebi/production/seqdb/embl/tools/bin/perl -w

use strict;
use Utils;

main();

sub main {
  #
  #
  #

  my ($dat_file, $putff_file) = @ARGV;

  unless ( $putff_file ) {
    print STDERR "USAGE: $0 <data file> <putff file>\n".
                 "  recompose CDS location from <data file> according\n".
                 "  to the errors contained in <putff file>.\n".
                 "  <data file>.2 will contain the corrected entries\n".
                 "  <data file>.1 will contain all other entries\n";
    exit;
  }

  my ($id_to_change_h, $to_change_h) = analyse_putff_output( $putff_file );

  use Data::Dumper;
  #print Dumper($to_change_h);


  if ( scalar keys(%$id_to_change_h) > 0 ) {
    print_out_file( $id_to_change_h, $to_change_h, $dat_file );

  } else {
    print STDERR "nothing changed.\n";
  }

  #print Dumper($to_change_h);
}




sub analyse_putff_output {
  #
  #
  #
  my ( $putff_file ) = @_;

  Utils::my_open( \*IN_PUTFF, "<$putff_file" );

  my ($id, $wrong_loc, $right_loc, $action) = ('', '', '', 0);
  my (%id_to_change_h, %to_change_h);
  my $loc_to_change = 0;

  while ( <IN_PUTFF> ) {

    if ( m/^[^A-Z]/ ) {
      if ( $action ) {

        $id_to_change_h{$id} = 1;

        $wrong_loc = quotemeta( $wrong_loc );

        push( @{$to_change_h{$id}}, {WRONG_LOC => $wrong_loc,
            RIGHT_LOC => $right_loc,
            ACTION => $action} );

        ++$loc_to_change;
      }
      ($wrong_loc, $right_loc, $action) = ('', '', 0);
    }

    if ( m/^\*{3} accno: (\w+)/ ) {

      $id = $1;
      if ( exists($id_to_change_h{$id}) ) {
        print( STDERR "WARNING: entry '$id' seems to appear twice in the putff  file.\n".
                      "--------\n" );
      }

    } elsif ( m/^ERROR \/codon_start=/ ) {

      ($wrong_loc, $right_loc, $action) = ('', '', 0);

    } elsif ( m/^ERROR CDS length must be a multiple of 3/ ) {

      # Remove the whole CDS feature
      $action = 'remove_cds';

    } elsif ( m/ERROR CDS (.+)/ ) {
      unless ( $wrong_loc ) {# The same error block can have more than one 'ERROR CDS ...'
        $wrong_loc = $1;
        $action = 'change_cds';
      }

    } elsif ( $action && m/^CDS (.+)/ ) {
      $right_loc = $1;

    } elsif ( m/^ERROR segment end \d+ > sequence length \(\d+\)/ ) {

      # Remove the whole CDS feature
      $action = 'remove_cds';

    }
      
  }

  close( IN_PUTFF );

  my $entries_to_change = scalar( keys( %id_to_change_h ) );

  print STDERR "$loc_to_change locations in $entries_to_change entries to be changed.\n";
  return ( \%id_to_change_h, \%to_change_h );

}



sub print_out_file {
  #
  #
  #
  my ($id_to_change_h, $to_change_h, $dat_file) = @_;


  Utils::my_open( \*IN_DAT, "<$dat_file" );
  Utils::my_open( \*OUT_ERR, ">$dat_file.2" );
  Utils::my_open( \*OUT_OTHER, ">$dat_file.1" );

  my ($entry_index, $location_index) = (0, 0);
  my ($loc_changed, $entries_changed) = (0, 0);
  my $locations_a;
  my $wrong_loc;
  my $right_loc;
  my $action;
  my $head = '';
  my $state = '';

  while ( <IN_DAT> ) {

    if ( m/^ID/ ) {

      $state = 'ID met';

    } elsif ( m/^AC   (\w+)/ ) {

      my $ac = $1;
      if ( $id_to_change_h->{$ac} ) {

        ++$entries_changed;
        $location_index = 0;
        $locations_a = $to_change_h->{$ac};
        $wrong_loc = $locations_a->[$location_index]->{WRONG_LOC};
        $right_loc = $locations_a->[$location_index]->{RIGHT_LOC};
        $action = $locations_a->[$location_index]->{ACTION};

        if ( $action eq 'remove_cds' ) {

          $state = 'remove_next_cds';

        } elsif ( $action eq 'change_cds' ) {

          $state = 'change_next_cds';
        }

        print( OUT_ERR $head );
        $head = '';

      } else {

        $state = 'dont_change_this';
        print( OUT_OTHER $head );
        $head = '';
      }
    }


    if ( $state eq 'change_next_cds'
      && s/^FT   CDS {13}$wrong_loc/FT   CDS             $right_loc/ ) {

      # changed location
      ++$loc_changed;
      ++$location_index;

      $wrong_loc = $locations_a->[$location_index]->{WRONG_LOC};
      $right_loc = $locations_a->[$location_index]->{RIGHT_LOC};
      $action = $locations_a->[$location_index]->{ACTION};
      $action = $action ? $action : '';

      if ( $wrong_loc ) {

        if ( $action eq 'remove_cds' ) {

          $state = 'remove_next_cds';

        } elsif ( $action eq 'change_cds' ) {

          $state = 'change_next_cds';
        }

      } else {

        $wrong_loc = 'xXx';
        $right_loc = 'xXx';
      }

    } elsif ( $state eq 'remove_next_cds'
      && m/^FT   CDS {13}$wrong_loc/ ) {

      $state = 'remove_this_cds';

    } elsif ( $state eq 'remove_this_cds'
      && (m/^FT   \S/ or m/^XX/) ) {

      # changed location
      ++$loc_changed;
      ++$location_index;

      $wrong_loc = $locations_a->[$location_index]->{WRONG_LOC};
      $right_loc = $locations_a->[$location_index]->{RIGHT_LOC};
      $action = $locations_a->[$location_index]->{ACTION};
      $action = $action ? $action : '';

      if ( $wrong_loc ) {

        if ( $action eq 'remove_cds' ) {

          $state = 'remove_next_cds';

        } elsif ( $action eq 'change_cds' ) {

          $state = 'change_next_cds';

        } else {

          $state = 'keep_going';
        }

      } else {

        $wrong_loc = 'xXx';
        $right_loc = 'xXx';
        $state = 'keep_going';
      }
    }

    if ( $state eq 'dont_change_this' ) {

      print OUT_OTHER;

    } elsif ( $state eq 'remove_next_cds' or  $state eq 'change_next_cds' ) {

      print OUT_ERR;

    } elsif ( $state ne 'remove_this_cds' ) {

      $head .= $_;
    }
  }

  close( OUT_OTHER );
  close( OUT_ERR );
  close( IN_DAT );

  print STDERR "$loc_changed locations in $entries_changed entries changed.\n";
}
