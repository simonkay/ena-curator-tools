#!/ebi/services/tools/bin/perl -w
#std2html.pl 1.00 - Pascal Hingamp - 13 OCT 1998
#
#Purpose : make html files out of standards files
# standard files (on UNIX side) are found in /ebi/www/web/internal/Services/standards

use strict;
use vars qw($TMPFILE $VERSION $STD_FILES $UNIX_DIR $SCRIPT_DIR $HEADER $FOOTER);

#CONSTANTS
$UNIX_DIR = "/ebi/www/web/public/Services/Standards";
$SCRIPT_DIR = "~hingamp/perl";
$STD_FILES = 'std';
$VERSION = '2.0';
$TMPFILE = "$SCRIPT_DIR/std2html.temp";
$HEADER = "<HTML>\n<HEAD>\n<TITLE>EMBL Flat File Examples</TITLE>\n</HEAD>\n".
    "<BODY bgcolor=\"#FFFFFF\" text=\"#000000\" link=\"#0000DD\" vlink=\"#0000DD\" alink=\"#0000DD\">\n";
$FOOTER = "</BODY>\n</HTML>\n";

#VARIABLES
my ($mol, $status, $file, $root, $line, $html, $title, $author, $cl, $kw, $fh, %list_D, %list_R, %gold, $s_com, $todays);

#=====================================================================================
#                     Main 
#=====================================================================================
$s_com = "date +\"%d-%m-%y\"";
chomp ($todays = `$s_com`);
print $todays; 
print "\n=======================Starting PUBLIC STANDARD TO HTML v$VERSION======================\n";
opendir DIR, $UNIX_DIR;
open (INDEX, "> $UNIX_DIR/web/list.html") or die "ERROR ! Can't open file <web/list.html> : $!\n";
FILE: while (defined ($file = readdir DIR)) {
    unless (($root) = ($file =~ /^(\w+)\.$STD_FILES$/)) {next FILE};
    open (IN,  "< $UNIX_DIR/$file") or die "ERROR ! Can't open file <$file> : $!\n";
    $line = <IN>;
    if (($title) = ($line =~ /^ID\s+(.+)\n$/)) {
            $title = ucfirst ($title);
	    print "".(sprintf "%-30.30s", $title);
	}
    else {print "ERROR: No ID line!\n"; close (IN); next FILE;};
    $line = <IN>;
    if (($mol) = ($line =~ /^ML\s+(RNA|DNA)\n$/)) {
	print "\t$mol";
	if ($mol eq 'DNA') {$list_D{$title} = "$root.html"} else {$list_R{$title} = "$root.html"};
    }
    else {print "ERROR: No ML (molecule) line!\n"; close (IN); next FILE;};
    $line = <IN>;
    if (($author) = ($line =~ /^AU\s+(.+)\n$/)) {print "\t($author)";}
    else {print "\t- Warning: No AU (author) line!\n"; $author = 'anonymous'};
    $line = <IN>;
    if (($status) = ($line =~ /^ST\s+(\S.+)\n$/)) {print "\t$status\n"}
    else {print " - Warning: No ST (status) line!\n"; $status = 'Preliminary'};
    if ($status =~ /gold standard/i) {$gold{$title} = 1;};
    open (OUT, "> $UNIX_DIR/web/$root.html") or die "ERROR ! Can't open file <web/$root.html> : $!\n";
    $html = $HEADER; $html =~ s/Examples/Examples: $title/;
    print OUT $html .
	"<CENTER><TABLE BORDER=0 CELLSPACING=3 CELLPADDING=3 WIDTH=\"100%\" BGCOLOR=\"#E9E9E9\">".
	"<tr><td align=\"center\" BGCOLOR=\"#3CB371\"><TABLE BORDER=0 CELLSPACING=0 ".
	"CELLPADDING=0 WIDTH=\"100%\" BGCOLOR=\"#3CB371\"><tr>".
	"<td><h2 align=\"center\"><font color=\"#FFFFFF\">EMBL Annotation Examples</font></h2></td>".
	"</tr><tr>".
	"<td align=center><font size=-1 color=\"#FFFFFF\">Last modified: $todays </font></td>".
	"</tr></TABLE></table>\n".
	"<h2 align=center>$title</h2>".
	"<CENTER><TABLE BORDER=0 CELLSPACING=0 CELLPADDING=3 WIDTH=\"100%\" BGCOLOR=\"#EEEEEE\"><tr><td>".
	"<pre>\n\n".
	  "Molecule type: <b>$mol</b>\n\n";
    ($cl, $kw, $fh) = ('#EEEEEE',0,0);
    LINE: while (defined ($line = <IN>)){
	if ($line =~ /^\s+$/ or $line =~ /^XX/) {next LINE};
	$line =~ s/__/../g;
	if ($line =~ /^KW/ && !$kw) {next LINE};
	if ($line =~ /^FH/ && !$fh) {
	    $fh = 1; print OUT "</td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>\n\n";
	      if ($cl eq '#DDDDDD') {$cl='#EEEEEE'} else  {$cl='#DDDDDD'};};
	$line =~ s/="(.+)\n$/="<font color="#8B0000">$1<\/font>\n/;     # free text
	$line =~ s/^(FT         \s+)(\w.+)("?)\n$/$1<font color="#8B0000">$2<\/font>$3\n/;   # free text 2
	$line =~ s/"<\/font>/<\/font>"/;     # free text
	$line =~ s/^(FT\s+)\/(\w+)/$1\/<a href="..\/..\/WebFeat\/qualifiers\/$2.html" target="examples">$2<\/a>/; # qualifier
	if ($line =~ s/^FT   ([A-Za-z_0-9\-']+)/FT   <a href="..\/..\/WebFeat\/$1.html" target="examples">$1<\/a>/)    # key
	     {print OUT "</td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>";
	      if ($cl eq '#DDDDDD') {$cl='#EEEEEE'} else  {$cl='#DDDDDD'};}; # key
	$line =~ s/^DE   (.+)\n$/DE   <font color="#8B0000">$1<\/font>\n/;  # DE
	$line =~ s/^RL   (\S+)\s+(.+)\n$/<font color="#8B0000">Related site: <\/font><a href="$1" target=_blank>$2<\/a>\n/;  # Related links
			       if ($line =~ /^CC/) {
			       next LINE};
	print OUT $line;
    };

    print OUT "</pre></td></tr></table>".
	#"<hr>- EMBL flat file standards -</CENTER><br><pre>".
	    "<font size=-1><i>- This www view: Pascal Hingamp - Last updated January 1999 -</i></font></CENTER>".$FOOTER;
    close (OUT);
    close (IN);
}
closedir DIR;
print INDEX $HEADER."<center>\n".
	"<TABLE BORDER=0 CELLSPACING=3 CELLPADDING=3 WIDTH=\"100%\" BGCOLOR=\"#E9E9E9\">".
    "<tr><td BGCOLOR=\"#3CB371\" align=center valign=\"top\"><font color=\"#FFFFFF\"><b>D<br>N<br>A</b></font></td><td><font size=\"-1\">";
foreach $title (sort keys %list_D) {
      print INDEX "<a href=\"$list_D{$title}\" target=\"examples\">$title</a><br>\n";
};
print INDEX "</td></tr><tr><td BGCOLOR=\"#3CB371\" align=center valign=\"top\"><font color=\"#FFFFFF\"><b>R<br>N<br>A</b></font></td><td><font size=\"-1\">";
foreach $title (sort keys %list_R) {
    print INDEX "<a href=\"$list_R{$title}\" target=\"examples\">$title</a><br>\n";
};
print INDEX "</font></td></tr></table>".$FOOTER;
close (INDEX);
print "================================Finished !===================================\n\n";

__END__
