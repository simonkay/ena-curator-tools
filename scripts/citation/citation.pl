#!/ebi/production/seqdb/embl/tools/bin/perl -w

#--------------------------------------------------------------------------------
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/citation/citation.pl,v 1.11 2007/08/20 08:58:31 gemmah Exp $
#
# citation.pl
# update EMBL citations by matching the Medline database
#
# first production version:
# * match on 
#     - ISSN
#     - volume
#     - firstpage
#     - first author surname
# * if a match is found, update/add:
#     - pubmedid
#     - medlineid
#     - issue
#     - pubyear
#     - lastpage ( if medlinepgn in format <number>-<number> )
#     - title ( only if compressed forms are equal )
#
# * no 'fuzzy matches' so far
# * no update of authors so far
# * all authors are selected at the moment even if only the first one is 
#   needed ( for comparison, no update yet ) - could be changed to increase
#   performance
# * only table journalarticle is regarded but not table accepted
# * matching could be improved using tables citation_ascii and authors_ascii
#   instead of citation resp. authors ( tables not in production yet )
#
# * no reports are send with this version of the script
#
# * ( performance: run on 28-JUL-2003 ( 154363 citations processed ) ~= 12 hours )
#
# 28-JUL-2003  Carola Kanz      first production version
# 29-JAN-2004  Carola Kanz      multiple hits: compare author as well
# 29-JAN-2004  Carola Kanz      option to read pubids from file
# 14-AUG-2004  Carola Kanz      use table medline.author_ascii 
# 16-AUG-2004  Carola Kanz      * updated log output ( less lines, easier to grep )
#                               * update match criteria: citations need to match
#                                 on issn, volume, firstpage and on either of
#                                 first author, last author, compressed title
# 21-APR-2005  Carola Kanz      use of medlineids discontinued from release 83
#                               ( june 2005 )
# 10-OCT-2005  Quan Lin         changed medline schema to the new cdb schema
#--------------------------------------------------------------------------------

# to deal with national characters
BEGIN {
  $ENV{'NLS_LANG'} = 'American_america.we8iso8859p1';
}


use strict;
use DBI;
use dbi_utils;
use SeqDBUtils;
use Class::Struct;

my $exit_status = 0;


#--- structs --------------------------------------------------------------------
# struct 'Citation' : EMBL citation ( tables journalarticle ( later to be used
# for accepted as well ), publication, pub_xref )
struct Citation => {
                    pubid     => '$',
                    issn      => '$',
                    volume    => '$',
                    issue     => '$',
                    firstpage => '$',
                    lastpage  => '$',
                    title     => '$',
                    pubyear   => '$',
                    pubmedid  => '$',
                    xtitle    => '$'
};

# struct 'Medline': Medline citation ( table medline.citation )
struct Medline => {
                   issn               => '$',
                   volume             => '$',
                   issue              => '$',
                   pages              => '$',
                   title              => '$',
                   pubyear            => '$',
                   pmid               => '$',
                   authorlistcomplete => '$',
                   lastpage           => '$',
                   xtitle             => '$'
};                   

# struct 'Author': used as array for both databases
struct Author => {
                  firstname  => '$',
                  surname    => '$'
};


# counter
my %cnt = ( all => 0,
            hit => 0,
            no_hit => 0,
            multi => 0,
            match => 0,
            multi_incl_author => 0 );



#--- command line ---------------------------------------------------------------
my $usage =  "\n  USAGE: $0 <user/password\@instance> [filename]\n\n";


@ARGV == 1 || @ARGV == 2 || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;


my $login = $ARGV[0];
if ( $ARGV[1] ) {
  open ( IN, $ARGV[1] ) || die "\nERROR: cannot open file $ARGV[1]\n\n"; 
}

# --- login to Oracle ---
my $dbh = dbi_ora_connect ( $login );
my $dbh_med = dbi_ora_connect ( "cdb_reader/reader\@medline",
                  {LongReadLen => 4194303, AutoCommit => 0, PrintError => 1} );

# --- set audit remark ---
dbi_do ( $dbh, "begin auditpackage.remark := 'no distribution - EMBL citation update'; end;" );





if ( $ARGV[1] ) {

  #--- select all journalarticles with pubid in infile ----------------------------

  while ( <IN> ) {
    chomp ( my $xpubid = $_ );

    my ( @y ) = dbi_getrow ( $dbh,
      "select j.pubid,
              j.issn,
              j.volume,
              nvl ( j.issue, ' ' ),
              j.firstpage,
              j.lastpage,
              nvl ( p.title, '-' ),
              nvl ( to_char ( p.pubdate, 'YYYY' ), 0 )
         from journalarticle j, publication p
        where j.pubid = p.pubid
          and j.pubid = $xpubid" );

    if ( defined $y[0] ) {
      compare_pubid ( $dbh, $dbh_med, \@y );
    }
    else {
      print "+++ pubid: $xpubid does not exist in db\n";
      print "-" x 80 ."\n";
    }

  }
  close ( IN );
  
}

else {

  #--- select all journalarticles -------------------------------------------------
  my $x = dbi_open ( $dbh,
      "select j.pubid,
              j.issn,
              j.volume,
              nvl ( j.issue, ' ' ),
              j.firstpage,
              j.lastpage,
              nvl ( p.title, '-' ),
              nvl ( to_char ( p.pubdate, 'YYYY' ), 0 )
         from journalarticle j, publication p
        where j.pubid = p.pubid
        order by j.pubid" );

  while ( my ( @y ) = dbi_fetch ( $x ) ) {
    compare_pubid ( $dbh, $dbh_med, \@y );
    dbi_commit ( $dbh )   if ( ! ( $cnt{all} % 100 ) );
  }
}


# print counts
print "\ncitations processed:     ".$cnt{all}.
      "\n          hits:          ".$cnt{hit}.
      "\n          no hits:       ".$cnt{no_hit}.
      "\n          multiple hits: ".$cnt{multi}.
      "\n          multiple hits ( incl. author ): ".$cnt{multi_incl_author}.
      "\n          match:         ".$cnt{match}."\n\n";

dbi_commit ( $dbh ); 
dbi_logoff ( $dbh );
dbi_rollback ( $dbh_med );   # just in case
dbi_logoff ( $dbh_med );




#===============================================================================
# subroutines
#================================================================================

sub compare_pubid {

  my ( $dbh, $dbh_med, $ref_cit ) = @_;

  my $citation = fill_citation ( @{$ref_cit} );

  $cnt{all}++;

  print "=== pubid: ".$citation->pubid."  issn: ".$citation->issn."  vol: ".
    $citation->volume."  pages: ".$citation->firstpage."-".$citation->lastpage."  ";

  my ( $nof, $medline ) = select_medline ( $dbh_med, $citation->issn, $citation->volume, 
                                           $citation->firstpage );

  print "pmid: ".$medline->pmid."  "  if ( $medline->pmid );
  
  if ( $nof == 0 ) {
    $cnt{no_hit}++;
    print "*** NO HIT ***\n";
  }
  else {

    # --- citations match on issn, volume, firstpage ---

    # --- select journalarticle authors ---
    my ( @authors ) = select_authors ( "C", $dbh, $citation->pubid );


    # --- for multiple hits: select medline again ---
    if ( $nof > 1 ) {
      $cnt{multi}++;
      print "*** multi hit ***\n";

      ( $nof, $medline ) = select_medline ( $dbh_med, $citation->issn, $citation->volume, 
                                            $citation->firstpage, $authors[0]->surname );

      if ( $nof > 1 ) {
        # still multiple hit
        $cnt{multi_incl_author}++;
        print "*** MULTI HIT ***\n";
        print "-" x 80 ."\n";
        return;
      }
      elsif ( $nof == 0 ) {
        # no author match ( should be rare... )
        print "*** multi hit - no hit ***\n";
        print "-" x 80 ."\n";
        return;
      }
    }

    # --- select medline authors ---
    my ( @med_authors ) = select_authors ( "M", $dbh_med, $medline->pmid );

    # *** final match: check also if either first author, last author or title match
    if (( @med_authors && @authors && ( $authors[0]->surname eq $med_authors[0]->surname ||
                                        $authors[-1]->surname eq $med_authors[-1]->surname ))
        || same_titles ( $citation->title, $medline->title )) {

      if ( @med_authors && @authors ) {
        print $authors[0]->surname."/".$med_authors[0]->surname."  ";
      }
           
      # *** match ****
      # fill/update some data before updating ( or reporting, not implemented yet )

      $cnt{hit}++;
      print "*** HIT ***\n";
      
      # --- select pub_xref data for journalarticle ( pubmedid ) ---
      $citation->pubmedid  ( select_pub_xref ( $dbh, $citation->pubid, "U" ) );

      # --- calculate lastpage for medline
      $medline->lastpage ( calc_lastpage ( $medline->pages ) );

      # --- update in database ( or report ) citation according to medline ------
      my ( $upd ) = update_citation ( $dbh, $citation, $medline, \@authors, \@med_authors );
      $cnt{match}++     if ( $upd == 0 );
    }
    else {
      print "*** no hit ***\n";
    }
  }
  print "-" x 80 ."\n";
}




#===============================================================================

sub fill_citation {
  my ( @data ) = @_;

  my $cit = Citation->new();
  $cit->pubid ( $data[0] );
  $cit->issn ( $data[1] );
  $cit->volume ( $data[2] );
  $cit->issue ( $data[3] );
  $cit->firstpage ( $data[4] );
  $cit->lastpage ( $data[5] );
  $cit->title ( $data[6] );
  $cit->pubyear ( $data[7] );

  return $cit;
}


#-------------------------------------------------------------------------------

sub select_pub_xref {
  my ( $db, $pubid, $type ) = @_;

  my $id = dbi_getvalue ( $db,
      "SELECT primaryid
         FROM pub_xref
        WHERE pubid = $pubid
          AND dbcode = '$type'" );

  $id = 0    if ( !defined $id );
  return $id;
}


#-------------------------------------------------------------------------------

sub select_medline {
  my ( $db, $issn, $volume, $firstpage, $surname ) = @_;

  $surname =~ s/'/''/  if ( defined $surname );

  my $sql = "SELECT cv.issn,
                    j.volume,
                    nvl (j.issue, ' '),
                    c.page_info,
                    c.title,
                    j.pubyear,
                    c.external_id,
                    c.authorlistcomplete_yn
               FROM cdb.citations c, 
                    cdb.cv_journals cv, 
                    cdb.journal_issues j
              WHERE cv.id = j.journal_id
                AND c.journal_issue_id = j.id
                AND c.source = 'MED'
                AND cv.issn = '$issn'
                AND j.volume = '$volume'
                AND (c.page_info like '${firstpage}-%' or c.page_info = '$firstpage')"; #one-page articles
  
  my ( @tab ) = dbi_gettable ( $db,$sql);

  my $med = Medline->new();
  my $cnt = 0;

  foreach my $row ( @tab ) {
    my ( @x ) = @{$row};

    if ( defined $surname ) {

      my $sql1 = "SELECT min(i.order_in) 
                   FROM cdb.individual_authors i,
                        cdb.citations c
                  WHERE c.external_id = '$x[6]'
                    AND i.lastname = '$surname'
                    AND i.citation_id = c.id
                    AND c.source = 'MED'";

      my $order = dbi_getvalue($db, $sql1);

      if (!$order or ($order != 1)){next;};

    }

    $med->issn ( $x[0] );
    $med->volume ( $x[1] );
    $med->issue ( $x[2] );
    $med->pages ( $x[3] );
    $med->title ( $x[4] );
    $med->pubyear ( $x[5] );
    $med->pmid ( $x[6] );
    $med->authorlistcomplete ( $x[7] );
    
    $cnt++;
  }

  return ( $cnt, $med );
}


#-------------------------------------------------------------------------------

sub select_authors {
  my ( $type, $db, $id ) = @_;

  my ( $sql );

  if ( $type eq "M" ) {
    # medline authors

    $sql = "SELECT nvl (i.lastname, i.collectivename),
                   nvl (i.initials, ' ')
              FROM cdb.individual_authors i,
                   cdb.citations c
             WHERE i.citation_id = c.id
               AND c.external_id = '$id'
               AND c.source = 'MED'
          ORDER BY i.order_in";
  }
  else {
    # datalib authors

    $sql = "SELECT p.surname,
            nvl ((translate (p.firstname, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ.- ','ABCDEFGHIJKLMNOPQRSTUVWXYZ')), ' ' )
              FROM person p, pubauthor pa
             WHERE pa.pubid = $id
               AND pa.person = p.personid
             ORDER BY pa.orderin";
  }

  my ( @tab ) = dbi_gettable ( $db, $sql );

  my @authors = ();

  foreach my $row ( @tab ) {
    my ( $x, $y ) = @{$row};
    my $a = Author->new();
    $a->surname ( $x );
    $a->firstname ( $y );

    push ( @authors, $a );
  }

  return ( @authors );
}


#-------------------------------------------------------------------------------

sub calc_lastpage {
  my ( $pages ) = @_;

  # calculate lastpage from 'pages'
  # e.g. 127-8 -> 128; 130-42 -> 142; 999-1003 -> 1003
  # if 'pages' does not match format <number>-<number>, lastpage is set to zero
  # ( i.e. update cannot be done automatically )
  # exception: if 'pages' only consist of an integer, it is assumed that first-
  # and lastpage are the same ( e.g. 123 -> 123 )
  
  # check for single number first
  if ( $pages =~ /^[0-9]+$/ ) {
    return $pages;
  }

  if ( $pages =~ /^([0-9]+)\-([0-9]+)$/ ) {
    if ( length ( $2 ) >= length ( $1 ) ) {
      return $2;
    }
    return ( substr ( $1, 0, length ( $1 ) - length ( $2 ) ).$2 );
  }

  # could not split 'pages'
  print "cannot split MEDLINPGN: $pages\n";
  return 0;
}

#-------------------------------------------------------------------------------

sub update_citation {
  my ( $db, $cit, $med, $authors_ref, $med_authors_ref ) = @_;
  my $upd = 0;

#  my ( $cit_ref, $med_ref ) = @_;
#  my ( $cit ) = \$cit_ref;
#  my ( $med ) = \$med_ref;

  my ( @authors ) = @{$authors_ref};
  my ( @med_authors ) = @{$med_authors_ref};

  
  # --- compare and update 
      
  # --- 1) table journalarticle ( lastpage, issue ) ---
  # ( $med->lastpage can be zero as some medlinepgn are not splitable, don't update lastpage ) 
  if ( $cit->issue ne $med->issue ||
       ( $cit->lastpage ne $med->lastpage && $med->lastpage != 0 ) ) {
    
    update_journalarticle ( $db, $cit->pubid, $med->issue, $med->lastpage );
    print "UPDATE journalarticle: ";
    print "issue: ".$cit->issue." -- ".$med->issue    if ( $cit->issue ne $med->issue );
    print "  lastpage: ".$cit->lastpage." -- ".$med->lastpage  
      if ( $cit->lastpage ne $med->lastpage && $med->lastpage != 0 );
    print "\n";
    $upd = 1;
  }
      
  # --- 2) table publication ( title, year ) ---
  # check if title needs update ( or if differences are only being reported )
  my $diff_title = diff_titles ( $cit->title, $med->title );
  if ( $diff_title || $cit->pubyear ne $med->pubyear ) {
    # delete [] around the medline title, if there are any
    if ( $med->title =~ /^\[(.*)\]$/ )   { $med->title ( $1 ); }
    update_publication ( $dbh, $cit->pubid, $med->title, $diff_title, $med->pubyear );
    print "UPDATE publication: title:\n   ".$cit->title."\n   ".$med->title."\n" if ( $diff_title );
    print "UPDATE publication: year: ".$cit->pubyear."  ".$med->pubyear."\n"  
      if ( $cit->pubyear ne $med->pubyear );
    $upd = 1;
  }
        
  # --- 3) table pub_xref ( pubmedid ) [ might be insert or update ] ---
  # ( pmid does always exist in medline )
  if ( $cit->pubmedid == 0 ) {
    add_pub_xref ( $dbh, $cit->pubid, $med->pmid, "U" );
    print "add PUBMEDID ".$cit->pubid."  --- ".$cit->pubmedid." :: ".$med->pmid.":\n";
    $upd = 1;
  }
  elsif ( $cit->pubmedid != $med->pmid ) {
    update_pub_xref ( $db, $cit->pubid, $med->pmid, "U" );
    print "update PUBMEDID ".$cit->pubid." --- ".$cit->pubmedid." :: ".$med->pmid.":\n";
    $upd = 1;
  }

  # --- 4) authors [ only compare, don't update automatically yet; also check 'authorlistcomplete' ] ---
  # ( if automatic update at some point be aware of different format ( W.E. -> WE ) !!! )
  if ( $med->authorlistcomplete eq 'N' ) {
    print "*** medline authorlist not complete!\n";
    $upd = 1;
  }

  if ( $#authors != $#med_authors ) {
    print "*** UPDATE diff number of authors ( ".($#authors + 1)." -- ".($#med_authors + 1)." )\n";
    $upd = 1;
  }
  else {
    for ( my $i = 0; $i < $#med_authors; $i++ ) {
      if ( ( $med_authors[$i]->surname   ne $authors[$i]->surname ) ||
           ( $med_authors[$i]->firstname ne $authors[$i]->firstname ) ) {
        print "UPDATE author ".$authors[$i]->firstname." ".$authors[$i]->surname." -- ".
          $med_authors[$i]->firstname." ".$med_authors[$i]->surname."\n";
        $upd = 1;

#         # check if medline author only contains printable ascii chars
#         if ( contains_invalid_chars ( $med_authors[$i]->surname ) ||
#              contains_invalid_chars ( $med_authors[$i]->firstname ) ) {
#           print "INVALID CHARS in author: ".$med_authors[$i]->firstname." ".
#             $med_authors[$i]->surname."\n";
#         }
      }
    }
  }
  return $upd;
}

#-------------------------------------------------------------------------------

# diff_titles: used for title update
sub diff_titles {
  my ( $cit_title, $med_title ) = @_;
  my ( $cp_cit_title, $cp_med_title ) = ( $cit_title, $med_title );

  if ( $med_title =~ /^\[In Process Citation\]$/ ) {
    return 0;
  }
  # check for non printable/non ascii chars
  if ( contains_invalid_chars ( $med_title ) ) {
    print "INVALID CHARS in title: $med_title\n";
    return 0;
  }

  if ( $med_title =~ /^\[(.*)\]$/ ) {
    $med_title = $1;
  }
  if ( $med_title =~ /\.$/ && $cit_title !~ /\.$/ ) {
    $cit_title .= '.';
  }
  if ( $med_title eq $cit_title ) {
    return 0;
  }

  # don't update if medline title contains double quotes
  if ( $med_title =~ /\"/ ) {
    print "TITLE: medline title contains double quotes, not updated.\n".
      "our title    : $cp_cit_title\nmedline title: $cp_med_title\n";
    return 0;
  }

  # titles differ; check if compressed titles are the same
  $cit_title =~ s/\s//g;    $cit_title = uc ( $cit_title );
  $med_title =~ s/\s//g;    $med_title = uc ( $med_title );

  if ( $cit_title eq $med_title ) {
    # update
    return 1;
  }
  
  # compressed titles differ: report
  print "TITLE: titles differ, no automatic update.\n".
    "our title    : $cp_cit_title\nmedline title: $cp_med_title\n";
  return 0;    
}

#--------------------------------------------------------------------------------

# same_titles: used for title matching
sub same_titles {
  my ( $cit_title, $med_title ) = @_;

  if ( $med_title =~ /^\[(.*)\]$/ ) {
    $med_title = $1;
  }
  if ( $med_title =~ /\.$/ && $cit_title !~ /\.$/ ) {
    $cit_title .= '.';
  }
  if ( $med_title eq $cit_title ) {
    return 1;
  }

  # titles differ; check if compressed titles are the same
  $cit_title =~ s/\s//g;    $cit_title = uc ( $cit_title );
  $med_title =~ s/\s//g;    $med_title = uc ( $med_title );

  if ( $cit_title eq $med_title ) {
    return 1;
  }
  
  return 0;    
}


#-------------------------------------------------------------------------------

sub contains_invalid_chars {
  my ( $txt ) = @_;

  if ( $txt !~ /^((\s*)|([!-~]*))*$/ ) {
    return 1;
  }
  return 0;
}


#--------------------------------------------------------------------------------

sub update_journalarticle {
  my ( $db, $pubid, $issue, $lastpage ) = @_;

  my $sql = "UPDATE journalarticle ";
  if ( $issue eq ' ' ) {
     $sql .= "  SET issue = NULL ";
  }
  else {
     $sql .= "  SET issue = '$issue' ";
  }
     $sql .=      ",lastpage = '$lastpage' "   if ( $lastpage != 0 );
     $sql .= "WHERE pubid = $pubid";

  dbi_do ( $db, $sql );
}

#--------------------------------------------------------------------------------

sub update_publication {
  my ( $db, $pubid, $title, $diff_title, $year ) = @_;

  # escape single quotes in title
  $title =~ s/'/''/g; #'

  my $sql = "UPDATE publication
                SET pubdate = to_date ( '$year', 'YYYY' ) ";
     $sql .= "       ,title = '$title' "    if ( $diff_title );
     $sql .= "WHERE pubid = $pubid";

  dbi_do ( $db, $sql );
}

#--------------------------------------------------------------------------------

sub add_pub_xref {
  my ( $db, $pubid, $id, $type ) = @_;

  # print "INSERT INTO pub_xref ( pubid, dbcode, primaryid ) VALUES ( $pubid, '$type', '$id' )\n";

  dbi_do ( $db,
           "INSERT INTO pub_xref ( pubid, dbcode, primaryid )
               VALUES ( $pubid, '$type', '$id' )" );
}


sub update_pub_xref {
  my ( $db, $pubid, $id, $type ) = @_;

  # print "UPDATE pub_xref SET primaryid = '$id' WHERE pubid = $pubid AND dbcode = '$type'\n";

  dbi_do ( $db,
           "UPDATE pub_xref
               SET primaryid = '$id'
             WHERE pubid = $pubid
               AND dbcode = '$type'" );
}


exit $exit_status;
