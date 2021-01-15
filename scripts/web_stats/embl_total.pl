#!/ebi/production/seqdb/embl/tools/bin/perl

use strict;
use DBD::Oracle;
use DBI;
use GD;
use GD::Graph::bars;
use GD::Graph::hbars;
use GD::Graph::pie;
use GD::Graph::Data;
use GD::Graph::lines;

use Data::Dumper;
use Carp;

use lib '/ebi/production/seqdb/embl/tools/perllib/';
use EBI::EbiHtmlHelper;

use Utils qw(my_open my_close my_open_gz);

#my $WEBDIR = '/ebi/www/web/public/Services/DBStats';

my $WEBDIR =  '/ebi/extserv/seqdb/Services/DBStats';
my $DATADIR = '/ebi/production/seqdb/embl/tools/web_stats/';

# File Names
my $ENTRIES_DAT_FILE = 'entries.dat';
my $NUCL_DAT_FILE = 'nucl.dat';
my $DIVISIONS_FILE = '/ebi/ftp/pub/databases/embl/release/division.ndx.gz';
my $HTML_PAGE = 'index.html';
my $HTML_ORG_STATS_PAGE = 'org_stats.html';

# image names
my $TOP_ORG_NUCL_PICT = 'top_org_nucl';
my $TOP_ORG_ENTRIES_PICT = 'top_org_entries';
my $GROWTH_NUCL_PICT = 'growth_nucl';
my $GROWTH_ENTRIES_PICT = 'growth_entries';
my $DIV_PICT = 'divisions';
my $CLASS_PICT = 'classes';
my $WORLD_ORIG_PICT = '/ebi/extserv/seqdb/Services/EMBLWorld/zoom_1/world_with_dots.jpg';
my $WORLD_REDUX_PICT = 'world_with_dots.jpg';


my $ORG_STAT_NAMES = [ 'Homo sapiens', 'Mus musculus', 'Rattus norvegicus', 'Caenorabditis elegans' ];

main();

sub main {

  my ( $dbconn ) = @ARGV;
  unless( $dbconn ) {
    die( "USAGE: $0 <db connection>" );
  }
  # Uncomment the following lines for testing
#   $WEBDIR = '/homes/lin/public_html/embl_total';
#   $DATADIR = '/net/bluearc3/vol004/embl/developer/lin/scripts/embl_total';

  my @colors = ( '#00CC66',
                 '#993366',
                 '#FFaa66',
                 '#FFFF33',
                 '#FF9900',
                 '#3399FF',
                 '#00CCFF',
                 '#FF3333',
                 '#000000',
                 '#aaaaaa',
                 '#999900',
                 '#9999FF',
                 '#00FF00',
                 '#66CCFF',
                 '#FFCCCC',
                 '#8871A5',
                 '#55FF88',
                 '#92C6FF',
                 '#FFDF96',
                 '#CCFF66' );

  foreach my $color ( @colors ) {

    GD::Graph::colour::add_colour( $color );
  }

  my ($day, $mon, $year) = (localtime( time ))[3,4,5];
  $year += 1900;
  my $month_name = qw(January February March April May June July August September October November December)[$mon];
  my $date = "$day $month_name $year";

  my $stats = get_embl_stats();

  my $org_stats = get_org_stats( $dbconn );

  my $nucl_dat = read_and_update( $NUCL_DAT_FILE, $year, $stats->{total}->{nucl} );
  my $entries_dat = read_and_update( $ENTRIES_DAT_FILE, $year, $stats->{total}->{entries} );
  
  draw_growth_charts( $entries_dat, $nucl_dat );

  my $org_colors = draw_top_org_charts( $stats, \@colors );

  draw_org_stats( $org_stats, $org_colors, \@colors );

  draw_release_charts( $stats );

  draw_world_pict();

  print_pages( $date, $stats, $org_colors );
}

sub draw_world_pict {

  my $pic = GD::Image->newFromJpeg( $WORLD_ORIG_PICT, 1 );
  my $pic_small = GD::Image->new( 400, 200, 1 );
  my ($w,$h) = $pic->getBounds();

  $pic_small->copyResized( $pic, 0,0, 0,0, 400,200, $w,$h );

  my $image_fh = my_open( ">$WEBDIR/$WORLD_REDUX_PICT" );
  binmode( $image_fh );
  print( $image_fh $pic_small->jpeg() );
  my_close( $image_fh );
}

sub print_pages {

  my ( $date, $stats, $org_colors ) = @_;
  my ( $top_org_table_en, $top_org_table_bp ) = print_main_page( $date, $stats, $org_colors );
  print_org_stats_page( $org_colors, $top_org_table_en, $top_org_table_bp );
}

sub get_left_menu {

  my $menuitems = [
                    "<a href='http://www.ebi.ac.uk/embl/index.html'>Index</a>",
                    "<a href='http://www.ebi.ac.uk/embl/Access/index.html'>Access</a>",
                    "<a href='http://www.ebi.ac.uk/embl/Documentation/index.html'>Documentation</a>",
                    "<a href='http://www.ebi.ac.uk/embl/News/news.html'>News</a>",
                    "<a href='http://www.ebi.ac.uk/embl/Submission/index.html'>Submission</a>",
                    "<a href='http://www.ebi.ac.uk/embl/Group_info/index.html'>Group Info</a>",
                    "<a href='http://www.ebi.ac.uk/embl/Contact/index.html'>Contact</a>"
                  ];
  return EBI::EbiHtmlHelper::drawLeftMenu( $menuitems );
}

sub print_main_page {

  my ( $date, $stats, $top_org_colors ) = @_;

  my $curr_entries = format_number( $stats->{total}->{entries} );
  my $curr_nucl = format_number( $stats->{total}->{nucl} );

  my $normal_entries = format_number( $stats->{0}->{entries} );
  my $con_entries = format_number( $stats->{1}->{entries} );
  my $tpa_entries = format_number( $stats->{2}->{entries} );
  my $wgs_entries = format_number( $stats->{3}->{entries} );

  my $normal_nucl = format_number( $stats->{0}->{nucl} );
  my $con_nucl = format_number( $stats->{1}->{nucl} );
  my $tpa_nucl = format_number( $stats->{2}->{nucl} );
  my $wgs_nucl = format_number( $stats->{3}->{nucl} );

  my @top_org_nucl = map( {$_->{organism}} @{$stats->{org_nucl}} );
  push ( @top_org_nucl, 'Other' );
  my $top_nucl_table = get_top_orgs_table( \@top_org_nucl, $top_org_colors );

  my @top_org_entries = map( {$_->{organism}} @{$stats->{org_entries}} );
  push ( @top_org_entries, 'Other' );

  my $top_entries_table = get_top_orgs_table( \@top_org_entries, $top_org_colors );

  my $content = <<HTML;

    <center>
      <p>
      This morning the EMBL Database contained <b>$curr_nucl</b> nucleotides in <b>$curr_entries</b> entries.
      </p>
      <p>
      <span class="pbold">Breakdown by entry type:</span><br>
      <table border=0 cellspacing=1 cellpadding=2 align=center style='text-align: left'>
        <tr>
          <td class="pbold" align='middle'>Entry Type</td>
          <td class="pbold" align='middle'>Entries</td>
          <td class="pbold" align='middle'>Nucleotides</td>
        </tr>
        <tr>
          <td class='psmall'>Standard</td>
          <td class='psmall' align=right>$normal_entries</td>
          <td class='psmall' align=right>$normal_nucl</td>
        </tr>
        <tr>
          <td class='psmall'>Constructed (CON)</td>
          <td class='psmall' align=right>$con_entries</td>
          <td class='psmall' align=right>n/a</td>
        </tr>
        <tr>
          <td class='psmall'>Third Party Annotation (TPA)</td>
          <td class='psmall' align=right>$tpa_entries</td>
          <td class='psmall' align=right>$tpa_nucl</td>
        </tr>
        <tr>
          <td class='psmall'>Whole Genome Shotgun (WGS)</td>
          <td class='psmall' align=right>$wgs_entries</td>
          <td class='psmall' align=right>$wgs_nucl</td>
        </tr>
      </table>
      </p>

      <h2>Top Organisms</h2>

      <p>
      <span class="pbold">By nucleotide count</span>
      </p>

      <p>
      <img SRC="$TOP_ORG_NUCL_PICT.png" >
      <br>
      <br>
      $top_nucl_table
      </p>

      <p>
      <span class="pbold">By entry count</span>
      </p>

      <p>
      <img SRC="$TOP_ORG_ENTRIES_PICT.png" >
      <br>
      <br>
      $top_entries_table
      </p>
      <p>
        <a href="$HTML_ORG_STATS_PAGE">More organism-related statistics</a>.
      </p>

      <h2>Geographical distribution</h2>

      <p>
        <a href='http://www.ebi.ac.uk/embl/Services/EMBLWorld/EMBLWorld.pl'
        ><img SRC="$WORLD_REDUX_PICT" style='border: 1 solid black'></a>
      </p>

      <h2>EMBL Database Growth</h2>

      <p>
      <span class="pbold">Total nucleotides</span><br>
      <font size="-1">(current $curr_nucl)</font><br>
      <img SRC="$GROWTH_NUCL_PICT.png" ><br>
      </p>
      <p>
      <span class="pbold">Number of entries</span><br>
      <font size="-1">(current $curr_entries)</font><br>
      <img SRC="$GROWTH_ENTRIES_PICT.png" ><br>
      </p>
      <p>
      <i><font size="-1">Graphs created on $date </font></i><br>
      </p>

      <h2>Release $stats->{rel_number}</h2>

      <p>
      <span class="pbold">Database Taxonomic Divisions (Release $stats->{rel_number}, <i>$stats->{rel_date}</i>)</span>
      </p>
      <img SRC="$DIV_PICT.png" ><br>
      </p>
      <p>
      </p>

      <p>
      <span class="pbold">Database Data Classes (Release $stats->{rel_number}, <i>$stats->{rel_date}</i>)</span>
      </p>
      <img SRC="$CLASS_PICT.png" ><br>
      </p>
      <p>
      </p>
    </center>
HTML

  my $template = 1; # fixed width page
  my $title = 'The EMBL Nucleotide Sequence Database, statistics';
  my $header_code = '';
  my $left_column = get_left_menu();

  my $out_fh = my_open( ">$WEBDIR/$HTML_PAGE" );

  EBI::EbiHtmlHelper::drawPage( $out_fh, $template, $title, \$content, $header_code, $left_column );

  close( $out_fh );

  system( "perl -i -pe 's|iframe src=\"/|iframe src=\"http://www.ebi.ac.uk/|' $WEBDIR/$HTML_PAGE" );

  return ( $top_entries_table, $top_nucl_table )
}

sub print_org_stats_page {

  my ( $org_colors, $top_entries_table, $top_nucl_table ) = @_;

  my $org_stats_table = get_org_stats_table( $org_colors );

  my $content = <<HTML;
    <center>
      <!-- =========================================================================== -->
      <p>
      <h2>Percentage of data by organism.</h2>
      <table border=0 cellpadding=3>
        <tr>
          <td class="pbold" align="center">
            By number of entries.
          </td>
          <td class="pbold" align="center">
            By nucleotide count.
          </td>
        </tr>
        <tr>
          <td>
            <img SRC="org_growth_en.png" >
          </td>
          <td>
            <img SRC="org_growth_bp.png" >
          </td>
        </tr>
        <tr>
          <td class="pbold" colspan=2 align=center>
            Average entry length in base pairs.
          </td>
        </tr>
        <tr>
          <td colspan=2 align=center>
            <img src="org_avg_len.png">
          </td>
        </tr>
        <tr>
          <td colspan=2>
            $org_stats_table
          </td>
        </tr>
      </table>
      <span>
        Note: these statistics are computed using the date of when an entry first appeared
        in the database and its current size.
        We estimate that, on average, entries do not change significantly in size and
        therefore these graph are of interest even if not 100% accurate.
      </span>
      </p>
      <!-- =========================================================================== -->

      <h2>Top Organisms</h2>

      <p>
      <span class="pbold">By nucleotide count</span>
      </p>
      <p>
      <img SRC="$TOP_ORG_NUCL_PICT.png" >
      <br>
      <br>
      $top_nucl_table
      </p>
      <p>
      <span class="pbold">By entry count</span><br>
      </p>
      <img SRC="$TOP_ORG_ENTRIES_PICT.png" >
      <br>
      <br>
      $top_entries_table
      </p>
    </center>
HTML

  my $out_fh = my_open( ">$WEBDIR/$HTML_ORG_STATS_PAGE" );

  my $template = 0; # 100% width page
  my $title = 'The EMBL Nucleotide Sequence Database, statistics';
  my $header_code = '';
  my $left_column = get_left_menu();

  EBI::EbiHtmlHelper::drawPage( $out_fh, $template, $title, \$content, $header_code, $left_column );

  close( $out_fh );

    system( "perl -i -pe 's|iframe src=\"/|iframe src=\"http://www.ebi.ac.uk/|' $WEBDIR/$HTML_ORG_STATS_PAGE" );
}

sub get_top_orgs_table {

  my ( $top_org_names, $top_org_colors ) = @_;

  my $table = '<table border=0 cellpadding=0 cellspacing=5 align=center style=\'text-align:left\'>';
  my $cols = 4;
  for( my $i = 0; $i < $#$top_org_names; $i += $cols ) {

    $table .= "<tr>\n";

    for ( my $ii = $i; $ii < $i + $cols; ++$ii ) {

      my $orgname = $top_org_names->[$ii];
      my $style;
      if ( defined( $orgname ) ) {
        my $color = $top_org_colors->{$orgname};
        if ( $color ) {

          $style = "background-color: $color; border: 1px black solid;";

        } else {
          $style='';
          $orgname='';
        }
      } else {
        $style='';
        $orgname='';
      }
      $table .= "<td style='$style'>&nbsp;&nbsp;</td>";
      $table .= "<td style='FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-SIZE: 7pt;";
      $table .= " FONT-WEIGHT: normal;'>&nbsp;$orgname&nbsp;</td>\n";
    }

    $table .= "</tr>\n";
  }

  $table .= '</table>';

  return $table;
}

sub get_org_stats_table {

  my ( $top_org_colors ) = @_;

  my $table = '<table border=0 cellspacing=2 cellpadding=0><tr>';

  foreach my $org_name ( @$ORG_STAT_NAMES ) {

    my $color = $top_org_colors->{$org_name};
    $table .= "<td style='background-color:$color; border: 1px black solid'>&nbsp;&nbsp;</td><td>&nbsp;$org_name&nbsp;</td>\n";
  }

  $table .= '</table>';

  return $table;
}

sub format_number {

  my ( $number ) = @_;

  $number = reverse $number;
  $number =~ s/(\d{3})/$1,/g;
  $number =~ s/,$//; # remove extra comma if present

  return reverse $number;
}


sub read_and_update {

  my ( $fname, $year_now, $curr_value ) = @_;
  my %stats;

  my_open( \*IN_OUT, "<$DATADIR/$fname" );

  while( <IN_OUT> ){

    chomp;
    my ( $year, $data ) = split( /\s+/ );
    if ( $data ) {

      $stats{$year} = 1 * $data;
    }
  }

  $stats{$year_now} = $curr_value;

  close( IN_OUT );
  my_open( \*IN_OUT, ">$DATADIR/$fname" );

  foreach my $year ( sort( keys( %stats ) ) ) {

    print( IN_OUT "$year\t$stats{$year}\n" );
  }

  close( IN_OUT );

  return \%stats;
}

sub get_org_stats {

  my ( $dbconn ) = @_;

  my $dbh = DBI->connect('dbi:Oracle:', $dbconn, '',
    { PrintError => 1,
      AutoCommit => 0,
      RaiseError => 0});


  my $hum_sql = 'select substr(s.month, 5, 4) Year, sum(s.entries), sum(s.bases)
               from db_statistics_human_growth s
             group by substr(s.month, 5, 4)
             order by substr(s.month, 5, 4)';
  my $hum_stats = get_running_totals( $dbh, $hum_sql );

  my $mus_sql = 'select substr(s.month, 5, 4) Year, sum(s.entries), sum(s.bases)
               from db_statistics_mmusculus_growth s
             group by substr(s.month, 5, 4)
             order by substr(s.month, 5, 4)';
  my $mus_stats = get_running_totals( $dbh, $mus_sql );

  my $cel_sql = 'select substr(s.month, 5, 4) Year, sum(s.entries), sum(s.bases)
               from db_statistics_celegans_growth s
             group by substr(s.month, 5, 4)
             order by substr(s.month, 5, 4)';
  my $cel_stats = get_running_totals( $dbh, $cel_sql );

  my $all_sql = q{select to_char( dbe.first_public, 'YYYY' ) Year, count( dbe.primaryacc# ), sum( bs.seqlen )
                    from dbentry dbe,
                         bioseq bs
                   where dbe.first_public is not null
                     and dbe.bioseqid = bs.seqid
                     and dbe.statusid = 4 -- public
                  group by to_char( dbe.first_public, 'YYYY' )
                  order by to_char( dbe.first_public, 'YYYY' ) };
  my $all_stats = get_running_totals( $dbh, $all_sql );


  my $rat_sql = 'select substr(s.month, 5, 4) Year, sum(s.entries), sum(s.bases)
               from ops$datalib.db_statistics_rat_growth s
             group by substr(s.month, 5, 4)
             order by substr(s.month, 5, 4)';
  my $rat_stats = get_running_totals( $dbh, $rat_sql );

  $dbh->disconnect();


  my (%hum_percentages, %mus_percentages, %cel_percentages, %rat_percentages);

  sub averager {
    my ( $data ) = @_;

    if ( defined( $data->[0] ) && defined( $data->[1] ) ) {
      return $data->[1] / $data->[0];
    } else {
      return undef;
    }
  }

  my (%hum_averages, %mus_averages, %cel_averages, %rat_averages);
  foreach my $year ( keys(%$all_stats) ) {

    $hum_averages{$year} = averager( $hum_stats->{$year} );
    $mus_averages{$year} = averager( $mus_stats->{$year} );
    $cel_averages{$year} = averager( $cel_stats->{$year} );
    $rat_averages{$year} = averager( $rat_stats->{$year} );
  }

  sub percenter {
    my ( $total, $data ) = @_;

    my $perc_bp;
    my $perc_en;

    if ( defined( $data->[0] ) ) {
      $perc_bp = int( (100*$data->[0]/$total->[0]) + 0.5 );
    } else {
      $perc_bp = 0;
    }
    if ( defined( $data->[1] ) ) {
      $perc_en = int( (100*$data->[1]/$total->[1]) + 0.5 );
    } else {
      $perc_en = 0;
    }

    return [$perc_bp, $perc_en];
  }
  while ( my( $year, $total ) = each( %$all_stats ) ) {

    $hum_percentages{$year} = percenter( $total, $hum_stats->{$year} );
    $mus_percentages{$year} = percenter( $total, $mus_stats->{$year} );
    $cel_percentages{$year} = percenter( $total, $cel_stats->{$year} );
    $rat_percentages{$year} = percenter( $total, $rat_stats->{$year} );
  }

  return { hum => \%hum_percentages,
           mus => \%mus_percentages,
           cel => \%cel_percentages,
           rat => \%rat_percentages,
           hum_avg => \%hum_averages,
           mus_avg => \%mus_averages,
           cel_avg => \%cel_averages,
           rat_avg => \%rat_averages  };
}


sub get_running_totals {

  my ( $dbh, $sql ) = @_;

  my $res = $dbh->selectall_arrayref( $sql );

  my %stats;

  my ($running_total_en, $running_total_bp) = (0, 0);
  foreach my $row ( @$res ) {
    $running_total_en += $row->[1];
    $running_total_bp += $row->[2];
    $stats{$row->[0]} = [$running_total_en, $running_total_bp];
  }

  return \%stats;
}

sub get_embl_stats {

  my $dbh = DBI->connect('dbi:Oracle:', '/@PRDB1', '',
    { PrintError => 1,
      AutoCommit => 0,
      RaiseError => 1});

  my %stats;

  my $sql_total = q{
    SELECT dbe.entry_type, count(dbe.primaryacc#), sum(bs.seqlen)
      FROM bioseq bs,
           dbentry dbe
     WHERE dbe.bioseqid = bs.seqid
       AND dbe.first_public is not null
       AND bs.bioseqtype = 0
       AND dbe.statusid = 4 -- public
       AND dbe.entry_type IN (0, 1, 2, 3) 
    GROUP BY dbe.entry_type
       };

 my $sth_total = $dbh->prepare( $sql_total );
 $sth_total->execute();

 while (my ($type, $entries, $nucl) = $sth_total->fetchrow_array() ) {

   $stats{$type} = {entries => $entries, nucl => $nucl};
   $stats{total}{entries} += $entries;

   unless( $type == 1 ) {# do not count CON's nucleotides
     $stats{total}{nucl} += $nucl;
   }
 }

 $sth_total->finish;

#  %stats = (
#   0 => {entries =>	38839794, nucl =>	43069290603},
#   1 => {entries =>	237117, nucl => 1111},
#   2 => {entries =>	4415, nucl => 331215110},
#   3 => {entries =>	4420507, nucl => 28148816807},
#   total => {entries => 43501833, nucl => 71549322520}
#  );

  my $sql_top_org_nucl = q{
  SELECT * FROM (SELECT bases, organism
                   FROM db_statistics_top_organisms
                 ORDER BY bases DESC)
  WHERE rownum < 11 };

  my $sth_top_org_nucl = $dbh->prepare( $sql_top_org_nucl );
  $sth_top_org_nucl->execute();

  my @top_org_nucl;
  while ( my($nucl, $org) = $sth_top_org_nucl->fetchrow_array() ) {

    push( @top_org_nucl, { organism => $org, data => $nucl} );
  }
  $sth_top_org_nucl->finish();


  my $sql_top_org_entries = q{
  SELECT * FROM (SELECT entries, organism
                   FROM db_statistics_top_organisms
                 ORDER BY entries DESC)
   WHERE rownum < 11 };

  my $sth_top_org_entries = $dbh->prepare( $sql_top_org_entries );
  $sth_top_org_entries->execute();

  my @top_org_entries;
  while ( my($entries, $org) = $sth_top_org_entries->fetchrow_array() ) {

    push( @top_org_entries, { organism => $org, data => $entries} );
  }
  $sth_top_org_entries->finish();

  $stats{org_nucl} = \@top_org_nucl;
  $stats{org_entries} = \@top_org_entries;

  read_release_stats( $dbh, \%stats );

  $dbh->disconnect;

  return (\%stats);
}


sub read_release_stats {

  my ( $dbh, $stats ) = @_;

  my $sql = q{SELECT rel#, to_char(reldate, 'DD MON YYYY')
                FROM dbrelease_statistic
               WHERE rel# = (SELECT max(rel#)
                             FROM dbrelease_statistic)};

  ($stats->{rel_number}, $stats->{rel_date}) = $dbh->selectrow_array( $sql );

  my_open_gz( \*IN, "<$DIVISIONS_FILE" );

  my $item;
  while ( <IN> ) {

    if ( m/([^:]+):\D+([\d,]+)\s+([\d,]+)/ ) {

      my ( $division, $entries, $nucl ) = ($1, $2, $3);
      $entries =~ s/,//g;# get rid of commas in numbers
      $nucl    =~ s/,//g;# get rid of commas in numbers

      $stats->{$item}->{$division} = {entries => $entries, nucl => $nucl};

    } elsif ( m/^(\w+)  +entries +nucleotides/ ) {

      $item = $1;
    }
  }

  close( IN );
}

sub draw_org_stats {

  my ($stats, $org_colors, $all_colors) = @_;

  my @colors;

  foreach my $org_name ( @$ORG_STAT_NAMES ) {

    if ( exists( $org_colors->{$org_name} ) ) {

      push( @colors, $org_colors->{$org_name} );

    } else {

      $org_colors->{$org_name} = shift( @$all_colors );
      push( @colors, $org_colors->{$org_name} );
    }
  }

  draw_org_growth( \@colors, $stats );
  draw_org_avg_len( \@colors, $stats );
}

sub draw_org_avg_len {

  my ( $colors, $stats ) = @_;
  my @years = sort( keys( %{$stats->{hum_avg}} ) );

  my @colvalues;

  foreach my $year ( @years ) {

    push( @{$colvalues[0]}, $stats->{hum_avg}{$year} );
    push( @{$colvalues[1]}, $stats->{mus_avg}{$year} );
    push( @{$colvalues[2]}, $stats->{rat_avg}{$year} );
    push( @{$colvalues[3]}, $stats->{cel_avg}{$year} );
  }

  my $colnames = [map( substr($_, 2, 2), @years)];
  my @data_arr = ( $colnames, @colvalues );

  my $data = GD::Graph::Data->new( \@data_arr )
    or croak( GD::Graph::Data->error );

  my $graph = GD::Graph::lines->new(300, 300);

  my $opt = get_org_stats_opt( $colors, 10000 );

  $graph->set( %$opt ) or croak( $graph->error );
  $graph->plot( $data ) or croak( $graph->error );

  save_chart( $graph, 'org_avg_len' );
}

sub draw_org_growth {

  my ( $colors, $stats ) = @_;
  my @img_names = qw(org_growth_en org_growth_bp);
  my @years = sort( keys( %{$stats->{hum}} ) );

  for my $index (0,1) {

    my @colvalues;

    foreach my $year ( @years ) {

      push( @{$colvalues[0]}, $stats->{hum}{$year}[$index] );
      push( @{$colvalues[1]}, $stats->{mus}{$year}[$index] );
      push( @{$colvalues[2]}, $stats->{rat}{$year}[$index] );
      push( @{$colvalues[3]}, $stats->{cel}{$year}[$index] );
    }
    foreach my $colvalue ( @colvalues ) {
      if ( !$colvalue->[-1] ) {# 0 or undef
        delete( $colvalue->[-1] );
      }
    }

    my $colnames = [map( substr($_, 2, 2), @years)];
    my @data_arr = ( $colnames, @colvalues );

    my $data = GD::Graph::Data->new( \@data_arr )
      or croak( GD::Graph::Data->error );

    my $graph = GD::Graph::lines->new(300, 300);

    my $opt = get_org_stats_opt( $colors, 100 );

    $graph->set( %$opt ) or croak( $graph->error );
    $graph->plot( $data ) or croak( $graph->error );

    save_chart( $graph, $img_names[$index] );
  }
}

sub get_org_stats_opt {

  my ($colors, $ymax) = @_;

  return {
    dclrs             => $colors,

    x_label           => 'Year',
    x_label_position  => 1/2,
    x_labels_vertical => 0,
    x_long_ticks      => 1,

    y_label         => ' ',
    y_max_value     => $ymax,
    y_tick_number   => 25,
    y_label_skip    => 1,
    y_long_ticks    => 0,

    bar_spacing     => 2,

    transparent     => 1,
    fgclr           => 'lgray',
    boxclr          => 'white',
    borderclrs      => 'black',
    labelclr        => 'black',
    axislabelclr    => 'black',
    valuesclr       => 'black',
    textclr         => 'black',
  }
}

sub draw_growth_charts {

  my ( $entries_dat, $nucl_dat ) = @_;

  my $nucl_set = {
    pict => $GROWTH_NUCL_PICT,
    divider  => 2 * (10**9),
    label_formatter => sub {return int( shift() / 10**9 ) },
    y_label  => 'Gbases',
    barcolor => 'blue',
    data => $nucl_dat
  };

  my $entry_set = {
    pict => $GROWTH_ENTRIES_PICT,
    divider  => 10**6,
    label_formatter => sub {return int( shift() / 10**6 ) },
    y_label  => 'Millions of Entries',
    barcolor => 'red',
    data => $entries_dat
  };

  draw_bars( $entry_set );
  draw_bars( $nucl_set );
}


sub draw_bars {

  my ($set) = @_;

  my ($colnames, $colvalues, $max_value) = get_data( $set->{data} );
  my $data = GD::Graph::Data->new( [$colnames, $colvalues] )
    or die GD::Graph::Data->error;

  my $graph = GD::Graph::bars->new(380, 300);
  my $options = get_options( $max_value, $set );
  $graph->set( %$options ) or warn $graph->error;


  $graph->plot( $data )
    or die $graph->error;

  save_chart( $graph, $set->{pict} );
}


sub draw_top_org_charts {
  # Draw a pie chart of the top 10 organisms by nucleotides and one by entries

  my ($stats, $colors) = @_;


  my %org_colors;
  foreach my $org_stat ( @{$stats->{org_nucl}}, @{$stats->{org_entries}} ) {

    $org_colors{ $org_stat->{organism} } = 0;
  }

  foreach my $org ( keys( %org_colors ) ) {
    $org_colors{$org} = shift( @$colors );
  }

  my @nucl_colors;
  foreach my $org_stat ( @{$stats->{org_nucl}} ) {

    push( @nucl_colors, $org_colors{$org_stat->{organism}} );
  }
  push( @nucl_colors, '#dddddd' );# 'Other' color
  $org_colors{Other} = '#dddddd';

  my @entries_colors;
  foreach my $org_stat ( @{$stats->{org_entries}} ) {

    push( @entries_colors, $org_colors{$org_stat->{organism}} );
  }
  push( @entries_colors, '#dddddd' );# 'Other' color

  draw_pie( $stats->{org_nucl}, $stats->{total}->{nucl}, \@nucl_colors, $TOP_ORG_NUCL_PICT );
  draw_pie( $stats->{org_entries}, $stats->{total}{entries}, \@entries_colors , $TOP_ORG_ENTRIES_PICT );

  return( \%org_colors );
}


sub draw_pie {

  my ($all_arr, $total_all, $colors, $fname) = @_;

  my ( $label_arr, $data_arr, $total );

  foreach ( @$all_arr ) {

    push( @$label_arr, $_->{organism} );
    push( @$data_arr, $_->{data} );
    $total += $_->{data};
  }

  push( @$label_arr, 'Other' );
  push( @$data_arr, $total_all - $total );
  my $data = [ $label_arr, $data_arr ];

  my $graph = new GD::Graph::pie( 250, 210 );

  $graph->set(
    '3d' => 0,

    axislabelclr => 'black',
    pie_height => 10,

    l_margin => 15,
    r_margin => 15,

    dclrs => $colors,

    start_angle => 180,

    suppress_angle => 360,

    transparent => 0,
  );

  $graph->plot( $data );
  save_chart( $graph, $fname );
}


sub draw_release_charts {

  my ( $stats ) = @_;

  draw_hbars( $stats->{Class}, $CLASS_PICT );
  draw_hbars( $stats->{Division}, $DIV_PICT );
}

sub draw_hbars {

  my ( $stats, $pic_name ) = @_;

  my ( @labels, @entries, @nucl );
  my ( $max_entries, $max_nucl ) = (0, 0);

  foreach my $div ( sort keys(%$stats) ) {

    my $data = $stats->{$div};

    unless( $div eq 'Total' ) {
      push( @labels, $div );
      push( @entries, $data->{entries} );
      push( @nucl, int( $data->{nucl}/1000 ) );

      $max_entries = $data->{entries} > $max_entries ? $data->{entries} : $max_entries;
      $max_nucl = $data->{nucl} > $max_nucl ? $data->{nucl} : $max_nucl;
    }
  }

  $max_nucl = int( $max_nucl/1000);
  my @data = (\@labels, \@entries, \@nucl);

  my $graph = GD::Graph::hbars->new( 520, 520 );
  my $number_formatter = sub {return int( shift() / (10**6) ) };

  $graph->set(
              two_axes        => 1,
              y1_label        => 'Millions of Entries',
              y2_label        => 'Gbases',
              y_long_ticks    => 1,
              y1_max_value    => $max_entries + 10**6,
              y2_max_value    => $max_nucl + 10**6,
              bar_spacing     => 2,

              y_tick_number   => 12,

              show_values     => 0,

              y_number_format => $number_formatter,

              transparent     => 1,

              fgclr           => 'black',
              boxclr          => 'background',
              dclrs           => ['red', 'green'],
              borderclrs      => 'black',
              labelclr        => 'black',
              axislabelclr    => 'black',
              valuesclr       => 'black',
              textclr         => 'black',
              legendclr       => 'black',
              );

  $graph->set_legend( 'Entries', 'Nucleotides' );
  $graph->set_text_clr( 'black' );
  $graph->set_legend_font( ['verdana', 'arial', gdMediumBoldFont], 12 );

  $graph->plot(\@data);
  save_chart( $graph, $pic_name );
}


sub get_options {

  my ($max_value, $set) = @_;
  my $number_formatter = $set->{label_formatter};

  GD::Graph::colour::add_colour( 'background' => [230,230,230] );

  my $tick_number = int(($max_value/$set->{divider}) + 1);
  my $opt = {
    x_label           => 'Year',
    x_label_position  => 1/2,
    x_labels_vertical => 0,

    y_label         => $set->{y_label},
    y_max_value     => $tick_number * $set->{divider},
    y_tick_number   => int($tick_number/4),
    y_label_skip    => 1,
    y_number_format => $number_formatter,
    y_long_ticks    => 1,

    bar_spacing     => 2,

    transparent     => 1,
    fgclr           => 'black',
    boxclr          => 'background',
    dclrs           => [ $set->{barcolor} ],
    borderclrs      => [ $set->{barcolor} ],
    labelclr        => 'black',
    axislabelclr    => 'black',
    valuesclr       => 'black',
    textclr         => 'black',
  };

  return $opt;
}


sub get_data {

  my ($data_h) = @_;

  my (@colnames, @colvalues);
  my $max_value = 0;

  foreach my $name ( sort keys( %$data_h ) ) {

    push( @colnames, substr( $name, 2, 2 ) );
    push( @colvalues, $data_h->{$name} );

    $max_value = $data_h->{$name} > $max_value ? $data_h->{$name} : $max_value;
  }

  return (\@colnames, \@colvalues, $max_value);
}


sub save_chart {

  my ($chart, $name) = @_;

  my $ext = $chart->export_format;

  my $out_fh = my_open( ">$WEBDIR/$name.png");
  binmode $out_fh;
  print $out_fh $chart->gd->png();
  close $out_fh;
}

