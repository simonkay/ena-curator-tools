#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# journalCheck.pl
#
#  $Header: 
#
#  DESCRIPTION:
#
#  Takes an expression for a journal name on the cli and gives matches.
#
#  MODIFICATION HISTORY:
#
#  03-MAR-2004 Nadeem Faruque   Created
#
#===============================================================================

use strict;
use DBI;
use dbi_utils;
use SeqDBUtils;

#  VERSION:
my $VER = "0.1";

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage =
  "\n PURPOSE: Takes a journal name and tries to find matches\n\n"
  . " USAGE:   $0\n"
  . "          [user/password\@instance] [-h] 'journal title'\n\n"
  . "   <user/password\@instance>\n"
  . "                   where <user/password> is taken automatically from\n"
  . "                   current unix session\n"
  . "                   where <\@instance> is either \@enapro or \@devt\n"
  . "   -h              shows this help text\n\n"
  . "   'journal title' is case insensitive\n"
  . "                   and may include * or % to do wilcard searches\n"
    . "                   eg '%Small Ruminant%'\n\n";

my $login    = "";
my $journal  = "";

( $ARGV[0] =~ /^\/\@/ ) || die $usage;
( @ARGV > 1 ) or die ($usage);

$login = $ARGV[0];
for ( my $i = 1 ; $i < @ARGV ; ++$i ) {
    if ( $ARGV[$i] =~ /^-h?/ ) {
	die ( $usage );}
    else{
	$journal .= $ARGV[$i]." ";}
}
chop ($journal);
$journal =~ s/\*/%/g;
$journal =~ s/\'/\'\'/g;


open( STDERR, "> /dev/null" );
my $dbh = dbi_ora_connect( $login );


# exact query
my @results = dbi_gettable($dbh, "select cv.*, js.JOURNAL_SYN
                                    from CV_JOURNAL cv left outer join JOURNAL_SYNONYM js
                                      on cv.ISSN#=js.ISSN# 
                                   where 
                                         UPPER(cv.FULL_NAME)   like upper('$journal') or
                                         UPPER(cv.NLM_ABBREV)  like upper('$journal') or
                                         UPPER(cv.EMBL_ABBREV) like upper('$journal') or
                                         UPPER(js.JOURNAL_SYN) like upper('$journal') 
                                   order by cv.FULL_NAME");


# if exact query is unsuccessful, loosen journal name by adding wildcards
if (scalar (@results) == 0) {

    my $looseJournal = $journal;
    $looseJournal =~ s/^([^%])/%$1/;
    $looseJournal =~ s/([^%])$/$1%/;

    if ($journal ne $looseJournal) {

	print "No results with \"$journal\"\n"
	    . "Trying          \"$looseJournal\"\n";

	@results = dbi_gettable($dbh, "select cv.*, js.JOURNAL_SYN
                                    from CV_JOURNAL cv left outer join JOURNAL_SYNONYM js
                                      on cv.ISSN#=js.ISSN#
                                   where
                                         UPPER(cv.FULL_NAME)   like upper('$looseJournal') or
                                         UPPER(cv.NLM_ABBREV)  like upper('$looseJournal') or
                                         UPPER(cv.EMBL_ABBREV) like upper('$looseJournal') or
                                         UPPER(js.JOURNAL_SYN) like upper('$looseJournal')
                                   order by cv.FULL_NAME");
    }
} 

dbi_logoff( $dbh );
my $plural = "s";

if (scalar (@results) == 1){
    $plural = "";
}

print scalar (@results)." result$plural\n\n";

my $lastIssn = "";

foreach my $row (@results){

    if ($lastIssn ne $$row[0]) {
	($plural eq "s") and print "----------------------------------------------------------\n";
	printf "%-9s %s\n", $$row[0], $$row[1];
	defined ($$row[2])  and print "EMBL:     ".$$row[2]."\n";
	defined ($$row[3])  and print "NLM:      ".$$row[3]."\n";
	defined ($$row[4])  and print "Synonyms: ".$$row[4]."\n";
    }
    elsif ( defined($$row[4]) ) {
	    print "          $$row[4]\n";
    }

    $lastIssn = $$row[0];
}

if (@results > 1) {
    print "----------------------------------------------------------\n";
}

    
