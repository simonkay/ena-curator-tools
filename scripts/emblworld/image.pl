#!/ebi/production/seqdb/embl/tools/bin/perl -w

use strict;
use warnings;
use diagnostics;

use GD;
GD::Image->trueColor(1);
use CGI;

# These should go in some sort of module
my $IMAGE_NAME = 'world_with_dots.jpg';
my $BASEDIR = './';
my %ZOOM_DIRS = ( 1 => 'zoom_1',
                  2 => 'zoom_2',
                  3 => 'zoom_3' );

my $CGI = CGI->new();

main();

sub main {

  my $zoom_level = $CGI->param('z');# zoom level
  my $x = $CGI->param('x'); # left side of the image
  my $y = $CGI->param('y'); # top side of the image
  my $w = 1024;#$CGI->param('w'); # width of the image
  my $h = 512;#$CGI->param('h'); # height of the image

  my $fh;
  my $img = GD::Image->newFromJpeg( "$BASEDIR/$ZOOM_DIRS{$zoom_level}/$IMAGE_NAME", 1 );
  if ( !$img ) {
    die;
  }

  print "Content-type: image/jpeg\n\n";
  if ( $zoom_level > 1 ) {

    # Create a new image of the desired size
    my $scaled = GD::Image->new($w, $h, 1);

    # Copy the relevant part of the original image
    $scaled->copy($img, 0,0, $x,$y, $w,$h);

    # Print out the data
    print $scaled->jpeg();

  } else {

    print $img->jpeg();
  }
}
