#!/ebi/production/seqdb/embl/tools/bin/perl -w

use strict;
use warnings;
use diagnostics;

use GD;
GD::Image->trueColor(1);
use CGI;
use Storable;

use EBI::EbiHtmlHelper;

# These should go in some sort of module
my $DATA_FILE = 'data.dat';
my $IMAGE_NAME = 'world_with_dots.jpg';
my $BASE_W = 1024;
my $BASE_H = 512;
my $WINDOW_W = 1024;
my $WINDOW_H = 512;
my $BASEDIR = '.';
my %ZOOM_DIRS = ( 1 => 'zoom_1',
                  2 => 'zoom_2',
                  3 => 'zoom_3' );
my $DOT_DIAMETER = 7;
my $PAN_STEP = 128; # movement of a pan action in pixels

my $CGI = CGI->new();

main_page();

sub main_page {

  print( "Content-type: text/html\n\n" );
  my $zoom_level = $CGI->param('z') || 1;# zoom level
  $zoom_level = $zoom_level > 3 ? 3 : $zoom_level;
  $PAN_STEP = $PAN_STEP * (2 ** ($zoom_level-1)); 
  my $x = $CGI->param('x') || 0; # left side of the image
  my $y = $CGI->param('y') || 0; # top side of the image
  my $full_img_w = (2 ** ($zoom_level-1)) * $BASE_W;
  my $full_img_h = (2 ** ($zoom_level-1)) * $BASE_H;

  my $data = retrieve( "$BASEDIR/$ZOOM_DIRS{$zoom_level}/$DATA_FILE" );
  my $html_map = get_map( $data->{data}, $zoom_level, $x, $y );

  print_page(\*STDOUT, $data->{nof_entries}, $data->{nof_locations}, $html_map, $zoom_level, $x, $y);
}

sub get_map {
  my( $data, $zoom_level, $map_x, $map_y ) = @_;

  my $map = '';

  while ( my( $coord, $item_hr) = each %$data ) {

    my ($x, $y) = $coord =~ m/(.+),(.+)/;
    $x -= $map_x;
    $y -= $map_y;

    if ( # coordinates within the displayed image
      $x >= 0 &&
      $x <= $WINDOW_W &&
      $y >= 0 &&
      $y <= $WINDOW_H    ) {

      my ($menu_text, $kingdom) = get_menu_text($item_hr);

      $map .= "  <area shape='circle' coords='$x,$y,". ($DOT_DIAMETER/2) ."' href='#' ".
      "onMouseOver=\"overlib('$menu_text', STICKY, MOUSEOFF, 2000, CAPTION, ' ', OFFSETX, -2, ".
      "OFFSETY, -57, WIDTH, 300, BGCOLOR, '#666666' )\" ".
      "onMouseOut='nd()' />\n";
    }
  }
  return \$map;
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

sub commify {

  $_[0] = reverse ($_[0]);
  $_[0] =~ s/(...)/$1,/g;
  $_[0] = reverse ($_[0]);
  $_[0] =~ s/^,//;
}

sub print_page {
  my ($fh, $nof_entries, $nof_locations, $html_map, $zoom_level, $x, $y) = @_;

  my $title = "EMBL World";

  commify( $nof_locations );
  commify( $nof_entries );
  my $html = '';
  # This is the content of the page
  my @crumbs = ( 
    {'http://www.ebi.ac.uk' => 'EBI'},
    {'http://www.ebi.ac.uk/embl' => 'EMBL Nucleotide Sequence Database'},
    {'' => $title }
  );

  $html = EBI::EbiHtmlHelper::drawBreadcrumbs( \@crumbs );
  $html .= "<br><br>";
  $html .= "<script type='text/javascript' src='emblworld.js'><!-- emblworld (c) EBI 2006 --></script>";
  $html .= "<script type='text/javascript' src='overlib.js'><!-- overLIB (c) Erik Bosrup --></script>";
  $html .= "<div id='overDiv' style='position:absolute; visibility:hidden; z-index:1000; font-size:80%'></div>";
  $html .= "<script type='text/javascript'>";
  $html .= "  var ZOOM_LEVEL = $zoom_level;\n";
  $html .= "  var ORIG_X = $x;\n";
  $html .= "  var ORIG_Y = $y;\n";
  $html .= "</script>";
  
  # Zoom level selector/indicator
  $html .= "<table border=0 cellspacing=2 cellpadding=0 width=100%>";
  $html .= "  <tr>";

  $html .= "<td valign='bottom'>Hover the mouse over a dot to see information about samples ";
  $html .= "available in that location, click anywhere to zoom in.</td>";

  $html .= "    <td valign='bottom' align='right'>Zoom level: ";

  foreach my $this_zoom_level ( sort keys(%ZOOM_DIRS) ) {

    if ( $this_zoom_level != $zoom_level ) {

      $html .= "<img onClick='zoom($this_zoom_level)' ";
      $html .= "id='zoom_$this_zoom_level'  onMouseOver='swap(this, \"over\")' ";
      $html .= "onMouseOut='swap(this, \"off\")' src='imgs/zoom_${this_zoom_level}_off.png'>";

    } else {

      $html .= "<img ";
      $html .= "id='zoom_$this_zoom_level' src='imgs/zoom_${zoom_level}_on.png'>";
    }
  }

  $html .= "    </td>";
  $html .= "  </tr>";
  $html .= "</table>";


  sub get_arrow {
    my( $img, $on, $pan_x, $pan_y ) = @_;

    my $arrow_html = '';
    if ( $on ) {

      $arrow_html .= "  <td><img src='imgs/${img}_on.png' id='$img' onMouseOver='swap(this, \"over\")'";
      $arrow_html .= "    onMouseOut='swap(this, \"on\")' onClick='pan($pan_x,$pan_y)'></td>";

    } else {

      $arrow_html .= "  <td><img src='imgs/${img}_off.png' id='$img'></td>";
    }

    return $arrow_html;
  }

  my $up_ok = $y > 0;
  my $down_ok = $y < ((2 ** ($zoom_level-1)) * $BASE_H) - $WINDOW_H;
  my $left_ok = $x > 0;
  my $right_ok = $x < ((2 ** ($zoom_level-1)) * $BASE_W) - $WINDOW_W;
  # map with arrows
  $html .= "<table border=0 cellspacing=0 cellpadding=0 width=0%>";
  $html .= "<tr>";
  
  $html .= get_arrow( 'up-left', $up_ok && $left_ok, -$PAN_STEP, -$PAN_STEP );
  $html .= get_arrow( 'up', $up_ok, 0, -$PAN_STEP );
  $html .= get_arrow( 'up-right', $up_ok && $right_ok, $PAN_STEP, -$PAN_STEP );
  
  $html .= "</tr>";
  $html .= "<tr>";

  $html .= get_arrow( 'left', $left_ok, -$PAN_STEP, 0 );
  $html .= "  <td>";

  # map image
  $html .= "<img id='EMBLWorld_img' border=0 src='image.pl?z=$zoom_level&x=$x&y=$y' ";
  $html .= "usemap='#EMBLWorld_map' onClick='zoom_and_center(this, event)' ";
  $html .= "style='position: relative'>";

  $html .= "</td>";

  $html .= get_arrow( 'right', $right_ok, $PAN_STEP, 0 );

  $html .= "</tr>";
  $html .= "<tr>";

  $html .= get_arrow( 'down-left', $down_ok && $left_ok, -$PAN_STEP, $PAN_STEP );
  $html .= get_arrow( 'down', $down_ok, 0, $PAN_STEP );
  $html .= get_arrow( 'down-right', $down_ok && $right_ok, $PAN_STEP, $PAN_STEP );

  $html .= "</tr>";
  $html .= "</table>";
  # end table with arrows

  $html .= "The map shows $nof_entries entries distributed over $nof_locations locations.<br>";

  # area map
  $html .= "<map id='EMBLWorld_map' name='EMBLWorld_map'>$$html_map</map>";

  $html .= "<div id='dia'></div>";

  $html .= "World image courtesy of <a href=http://www.nasa.gov/home/index.html?skipIntro=1>NASA</a>, ";
  $html .= "<a href=http://visibleearth.nasa.gov/>Visible Earth</a><br>\n";

  $html .= "<p>The dots on the map have different colours according to the taxonomy of the specimens:<br>";
  $html .= "<img src='Eukaryota.png'>Eukaryota&nbsp;&nbsp;&nbsp;<img src='Bacteria.png'>";
  $html .= "Bacteria&nbsp;&nbsp;&nbsp;<img src='Archaea.png'>Archaea&nbsp;&nbsp;&nbsp;";
  $html .= "<img src='Other.png'>Other&nbsp;&nbsp;&nbsp;<img src='Mixed.png'>Mixed</p>";

  $html .= "<p>In 2005 the International Nucleotide Sequence Database Collaboration ";
  $html .= "(<a href='http://www.insdc.org/'>INSDC</a>) introduced the ";
  $html .= "<tt><a href='http://www.ebi.ac.uk/embl/Documentation/FT_definitions/feature_table.html#7.4.1'>";
  $html .= "lat_lon</a></tt>";
  $html .= " qualifier that allows to describe precisely where the sequenced specimen was collected.";
  $html .= "The map above shows the geographical distribution of samples annotated so far.</p>";
  $html .= "<br><br>";

  my $template = 0; #100% width
  EBI::EbiHtmlHelper::drawPage(\*STDOUT, $template, $title, \$html, '', '' );
}

