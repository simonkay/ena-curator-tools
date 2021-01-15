#!/ebi/services/tools/bin/perl
#
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/emblworld/emblworld_maker.pl,v 1.10 2011/06/20 09:39:35 xin Exp $
#
# This program produces a static web page that maps EMBL entries with lat-lon
# data onto a map of the world.
# Currently the map is at http://www3.ebi.ac.uk/Services/EMBLWorld/EMBLWorld.html
#
# 13-Mar-2006 F. Nardone  Created
# 15-Feb-2007   "   "     Use dentry.statusid
#
# ----------------------------------------------------------------------------
use strict;
use warnings;
use diagnostics;
use Data::Dumper;

use Utils qw(my_open my_close my_system);
use EBI::HtmlHelper;

use GD;
GD::Image->trueColor(1);

use DBI;
use Storable;

# The diameter of the dot representing a cluster of entries on the map
my $DOT_DIAMETER = 7;
# The name of the html page
my $PAGE_NAME = 'EMBLWorld.html';
# Colours of the dots
my %COLOURS = ( Archaea => [0,255,255],   # turquoise
                Bacteria => [255,255,0],  # yellow
                Eukaryota => [255,10,10], # red
                Viruses => [255,255, 255],# white
                Other => [180,180,180],   # grey
                Mixed => [255,0,255] );   # purple

my $SLICES_C = 8; # number of columns in the sliced image
my $SLICES_R = 4; # number of rows in the sliced image
my $IMAGE_W = 1024; # width of the shown image
my $IMAGE_H = 512;  # height of the shown image
my $SLICE_W = int( $IMAGE_W/$SLICES_C );
my $SLICE_H = int( $IMAGE_H/$SLICES_R );
my %DIRS = ( 1 => 'zoom_1',
             2 => 'zoom_2',
             3 => 'zoom_3' ); # directories for the different zoom levels (images and maps)

main();

sub main {

  my ( $dbconn, $bgimage, $output_dir ) = get_args();
  if ( !-e($output_dir) ) {

    mkdir( $output_dir );
  }

  foreach my $dir (values(%DIRS) ) {
    mkdir( "$output_dir/$dir" ) unless( -e("$output_dir/$dir") );
  }
    
  draw_sample_dots($output_dir);

  my $data = get_data( $dbconn );

  # Count entries and locations
  my $nof_locations = 0;
  my $nof_entries = 0;
  foreach ( values( %$data ) ) {
    $nof_locations += scalar( keys( %$_ ) );
    foreach ( values( %$_ ) ) {
      foreach ( values( %$_ ) ) {
        $nof_entries += $_;
      }
    }
  }

  my $main_map = GD::Image->newFromJpeg($bgimage);

  my $map_borders = { N => 90,
                      S => 90,
                      E => 180,
                      W => 180 };

  while ( my( $zoom_level, $directory ) = each(%DIRS) ) {

    my $map_w = (2 ** ($zoom_level-1)) * $IMAGE_W;
    my $map_h = (2 ** ($zoom_level-1)) * $IMAGE_H;
    my $map = GD::Image->new( $map_w, $map_h );

    $map->copyResampled( $main_map, 0,0, 0,0, $map_w, $map_h, $main_map->getBounds() );

    # Normalize data for size of image
    my $round = $zoom_level < 3;
    my $normal_data = normalize_data( $map_w, $map_h, $data, $map_borders, $round );

    # Paint the dots on the map
    paint_dots( $map, $normal_data );

    # Name of the image with the plotted entries
    my $image_name = 'world_with_dots';
    my $image_fh = my_open( ">$output_dir/$directory/$image_name.gd" );
    binmode( $image_fh );
    print( $image_fh $map->gd() );
    my_close( $image_fh );
    $image_fh = my_open( ">$output_dir/$directory/$image_name.jpg" );
    binmode( $image_fh );
    print( $image_fh $map->jpeg() );
    my_close( $image_fh );

    my $all_data = {nof_entries => $nof_entries,
                    nof_locations => $nof_locations,
                    data => $normal_data};
                  
    store( $all_data, "$output_dir/$directory/data.dat" );
  }

  # sample dots for the legend
  draw_sample_dots( $output_dir );
  # overlib JavaScript library, handles the mouseover
  my_system( "cp overlib.js $output_dir" );
  # emblworld JavaScript library, handles zooming
  my_system( "cp emblworld.js $output_dir" );
  # images for buttons etc.
  my_system( "cp -R imgs/ $output_dir" );
  # CGI scripts
  my_system( "cp EMBLWorld.pl $output_dir" );
  my_system( "cp image.pl $output_dir" );
  # EBI HTML libraries
  my_system( "cp -R EBI/ $output_dir" );
  
  my_system( "chmod -fR 0744 $output_dir/*" );
  my_system( "chmod 0755 $output_dir/*.pl" );
  my_system( "chmod 0755 $output_dir/zoom_*" );
  my_system( "chmod 0755 $output_dir/imgs" );
  my_system( "chmod 0755 $output_dir/EBI" );
}

sub paint_dots {
  # draw the dots on the map and returns an imagemap that specifies the mouseovers
  my ( $map, $normal_data ) = @_;

  # This will be the border of the dot
  my $border = $map->colorAllocate(0,0,0);

  # Allocate colours for the different kingdoms
  my %kingdom_colour;
  while ( my($kingdom, $colour) = each(%COLOURS) ) {
    $kingdom_colour{$kingdom} = $map->colorAllocate( @$colour );
  }

  my $html_map = "<map name='world_map'>\n";

  while ( my( $coord, $item_hr) = each %$normal_data ) {

    my ($x, $y) = $coord =~ m/(.+),(.+)/;
    my ($menu_text, $kingdom) = get_menu_text($item_hr);

    my $dot_colour = $kingdom_colour{$kingdom};
    unless ($dot_colour) {
      print STDERR "ERROR: no colour for '$kingdom'\n";
    }
    draw_dot( $map, $x, $y, $border, $dot_colour );
  }

  $html_map .= "</map>\n";
}

sub normalize_data {
  # return data normalised for picture coordinates and grouped by rounded real coordinates

  my ( $map_width, $map_height, $data, $map_borders, $round ) = @_;

  # Here we compute some factors that enable mapping of lat/lon coordinates onto
  #  the image.
  my $long_span = 360; # 360 degrees longitude span
  my $lat_span = 180;  # 180 degrees latitude span
  my $long_ratio = $map_width / $long_span;
  my $lat_ratio = $map_height / $lat_span;


  my $normal_data;
  while ( my( $coords, $item_hr) = each %$data ) {

    if ( $coords =~ m/(\d+)(\.?\d*)\s+([SN])\s+(\d+)(\.?\d*)\s+([EW])/ ) {

      my ($lat, $lat_side, $long, $long_side);
      if ( $round ) {
        ($lat, $lat_side, $long, $long_side) = ($1, $3, $4, $6);
      } else {
        ($lat, $lat_side, $long, $long_side) = ("$1$2", $3, "$4$5", $6);
      }

      if ( $lat == 0 ) {
        $lat_side = 'N';
      }
      if ( $long == 0 ) {
        $long_side = 'E';
      }
      my $rounded_coords = "$lat $lat_side $long $long_side";

      my ($x, $y) = get_x_y( $rounded_coords, $map_borders, $lat_ratio, $long_ratio, $map_height, $map_width );

      if ( exists($normal_data->{"$x,$y"}) ) {

        $normal_data->{"$x,$y"} = {%{$normal_data->{"$x,$y"}}, ($coords => $item_hr) };

      } else {

        $normal_data->{"$x,$y"} = {$coords => $item_hr};
      }
    } else {

      print( STDERR "WARNING: wrong coordinates '$coords'\n" );
    }
  }

  return $normal_data;
}

sub get_x_y {

  my( $coord, $map_borders, $lat_ratio, $long_ratio, $map_height, $map_width ) = @_;
  # Coordinates are in the format '23.4 N 45.6 W'
  if ( $coord =~ m/([\d\.]+)\s+([SN])\s+([\d\.]+)\s+([EW])/ ) {
    my ($lat, $lat_side, $long, $long_side) = ($1, $2, $3, $4);

    my ($x, $y);

    # Normalise the coordinates to map pixels
    if ( $lat_side eq 'N' ) {
      $y = int( ( $map_borders->{N} - $lat ) * $lat_ratio );
    } else {
      $y = int( $map_height - ( $map_borders->{S} - $lat ) * $lat_ratio );
    }
    if ( $long_side eq 'E' ) {
      $x = int( $map_width - ( $map_borders->{E} - $long ) * $long_ratio );
    } else {
      $x = int( ( $map_borders->{W} - $long ) * $long_ratio );
    }

    # Put on the border what falls out of the map
    # (should only happen if the image does not cover the whole world)
    $y = $y < 0 ? 0 : $y;
    $y = $y > $map_height ? $map_height : $y;
    $x = $x < 0 ? 0 : $x;
    $x = $x > $map_width ? $map_width : $x;

    return ($x, $y);

  } else {
    print STDERR "ERROR: bad coordinates '$coord'\n";
  }
}

sub draw_sample_dots {

  my ( $output_dir ) = @_;

  while ( my($kingdom, $colour) = each(%COLOURS) ) {

    my $img = GD::Image->newFromPng('white.png');
    my $border = $img->colorAllocate( 0,0,0 );
    my $colour = $img->colorAllocate( @$colour );
    draw_dot( $img, $DOT_DIAMETER/2, $DOT_DIAMETER/2, $border, $colour );

    my $fh = my_open( ">$output_dir/$kingdom.png" );
    binmode( $fh );
    print( $fh $img->png() );
    my_close( $fh );
  }
}

sub get_menu_text {
  # Returns an HTML text describing the cluster according to the data in %$item_hr
  # and a link to query SRS by the coordinates of the cluster
  my ($item_hr) = @_;

  my $kingdom_all;
  my $text = '';
  foreach my $coords ( keys(%$item_hr) ) {

    my ($lat,$lat_side, $lon,$lon_side) = $coords =~ m/(\S+) ([NS]) (\S+) ([EW])/;
    if ( !$lon_side ) {
      print STDERR "WARNING: bad coordinates '$coords'\n";
    }

    my $srs_query = "$lat&amp;$lat_side&amp;$lon&amp;$lon_side";
    $text .= "&lt;p&gt;$coords &lt;a href=http://srs.ebi.ac.uk/srsbin/cgi-bin/wgetz?".
    "-id+sessionid+[EMBL-FtDescription:$srs_query]+-e&gt;see entries&lt;/a&gt;&lt;br&gt;";

    my $titles_hr = $item_hr->{$coords};
    foreach my $title ( keys(%$titles_hr) ) {

      $text .= "'$title'&lt;br&gt;";

      my $kingdom_hr = $titles_hr->{$title};
      foreach my $kingdom ( keys(%$kingdom_hr) ) {

        $kingdom_all = $kingdom_all && ($kingdom_all ne $kingdom) ? 'Mixed' : $kingdom;
        my $number = $kingdom_hr->{$kingdom};
        $text .= "$kingdom: $number entries&lt;br&gt;";
      }
    }

    $text .= '&lt;/p&gt;';
  }

  $text =~ s/'/\\'/g;
  $text =~ s/"/\\"/g;
  return ($text, $kingdom_all);
}

sub get_data {
  # Returns a hashref like this:
  # { '23.4 N 45.6 W' => { '<title of publication>' => { '<superkingdom>' => <number of entries>,
  #                                                      '<superkingdom>' => <number of entries> },
  #                        '<title of publication>' => { '<superkingdom>' => <number of entries> }
  #                      },
  #   ...
  # }
  my ( $dbconn ) = @_;

  my $dbh = DBI->connect(
    'dbi:Oracle:',
    $dbconn, '',
    {PrintError => 0,
     RaiseError => 1 } );

  my $sth = $dbh->prepare( "SELECT --+ ORDERED
                                   fq.text, nvl(p.title, b.booktitle), decode( substr(lineage,0,3),
                                                                           'Arc', 'Archaea',
                                                                           'Euk', 'Eukaryota',
                                                                           'Bac', 'Bacteria',
                                                                           'Vir', 'Viruses',
                                                                                  'Other' )
                              FROM feature_qualifiers fq
                                   JOIN
                                   seqfeature sef ON fq.featid = sef.featid
                                   JOIN
                                   dbentry d ON sef.bioseqid = d.bioseqid
                                   JOIN
                                   citationbioseq cb ON d.bioseqid = cb.seqid
                                   JOIN
                                   publication p ON cb.pubid = p.pubid
                                   LEFT OUTER JOIN
                                   book b on p.pubid = b.pubid
                                   JOIN
                                   seqfeature sef_sof ON d.bioseqid = sef_sof.bioseqid
                                   JOIN
                                   sourcefeature sof ON sef_sof.featid = sof.featid
                                   JOIN
                                   ntx_lineage l ON sof.organism = l.tax_id
                             WHERE d.statusid = 4 -- public
                               AND fq.fqualid = 94 -- /lat_lon
                               AND p.pubtype <> 0 -- no submissions
                               AND sof.primary_source = 'Y'" );

  $sth->execute();
  my $data;

  while ( my ($coords, $text, $lineage) = $sth->fetchrow_array() ) {

    ++$data->{$coords}->{$text}->{$lineage};
  }

  $dbh->disconnect();
  return $data;
}

sub draw_dot {
  # Draw a circle on the map
  my ($img, $x, $y, $border_color, $inner_color) = @_;

  $img->filledEllipse($x,$y,$DOT_DIAMETER-1,$DOT_DIAMETER-1,$inner_color);
  $img->ellipse($x,$y,$DOT_DIAMETER,$DOT_DIAMETER,$border_color);
}

sub commify {

  $_[0] = reverse ($_[0]);
  $_[0] =~ s/(...)/$1,/g;
  $_[0] = reverse ($_[0]);
  $_[0] =~ s/^,//;
}

sub get_args {
  # returns the command line arguments
  if ( not defined $ARGV[2] ) {

    die( "USAGE:\n$0 <dbconnection> <background image (jpeg)> <output directory>\n\n" );
  }
  return @ARGV;
}

