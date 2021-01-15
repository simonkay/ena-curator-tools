#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#std2htmlnew.pl - TK
#
#Purpose : make html files out of standards files, both public and internal at the same time
# only "gold star" standard are made into public html
# standard files are in /ebi/production/seqdb/embl/tools/curators/scripts/standards


use strict;
use vars qw($TMPFILE $VERSION $STD_FILES $UNIX_DIR $SCRIPT_DIR $HEADER $FOOTER);

#CONSTANTS
$UNIX_DIR = "/ebi/production/seqdb/embl/tools/curators/scripts/standards";
$SCRIPT_DIR = "/ebi/production/seqdb/embl/tools/curators/scripts";
$STD_FILES = 'std';
$VERSION = '3.0';
$TMPFILE = "$SCRIPT_DIR/std2html.temp";
$HEADER = "<HTML>\n<HEAD>\n<TITLE>EMBL Flat File Examples</TITLE>\n</HEAD>\n".
    "<BODY bgcolor=\"#FFFFFF\" text=\"#000000\" link=\"#0000DD\" vlink=\"#0000DD\" alink=\"#FF0000\">\n";
$FOOTER = "</BODY>\n</HTML>\n";

#VARIABLES
my ($mol, $status, $file, $root, $line, $html, $title, $author, $cl, $kw, $fh, %list_D, %list_R, 
%list_D_p, %list_R_p, %gold,$s_com,$fullinfo,$lasttouched,@fields,$todays, $Public_Web_Dir);

#=====================================================================================
#                     Main 
#=====================================================================================
print "\n=======================Starting STANDARD TO HTML v$VERSION======================\n";
print "\n internal standards first \n";

system('umask 002');

opendir DIR, $UNIX_DIR;

print "$UNIX_DIR/web/list.html\n";
open (INDEX, "> $UNIX_DIR/web/list.html") or die "ERROR ! Can't open file <web/list.html> : $!\n";
FILE: while (defined ($file = readdir DIR)) {
    unless (($root) = ($file =~ /^(\w+)\.$STD_FILES$/)) {next FILE};
    $s_com = "ls -l $UNIX_DIR$file";
    chomp ($_=`$s_com`);
    if (/(\s\w{3}\s+\d+\s\S+)/) {
	$lasttouched=$1;
    }
    open (IN,  "< $UNIX_DIR/$file") or die "ERROR ! Can't open file <$file> : $!\n";
    $line = <IN>;
    if (($title) = ($line =~ /^ID\s+(.+)\n$/)) {
            $title = ucfirst ($title);
	    print "".(sprintf "%-30.30s", $title);
#	    $list{$title} = "$root.html";
#	    print INDEX "<a href=\"$root.html\" target=\"examples\">$title</a></p><p>\n";
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
	"CELLPADDING=0 WIDTH=\"100%\" BGCOLOR=\"#3CB371\"><tr><td align=\"center\" width=\"100\">".
	"<a href=\"http://www3.ebi.ac.uk/internal/Services/curators/\" target=\"_top\"><img border=0 align=\"center\" ".
	"src=\"../../icons/button.gif\"></a></td>\n".
	"<td><h2 align=\"center\"><font color=\"#FFFFFF\">$title</font></h2></td>".
	"<td><ul compact><b>".
     "<li><a href=\"http://www3.ebi.ac.uk/internal/Services/curators/guides/guidelines.html\" target=\"_top\">Guidelines</a>".
     "<li><a href=\"http://www3.ebi.ac.uk/Services/WebFeat/\" target=\"_top\">Web Feat</a>".
     "<li><a href=\"http://www.ebi.ac.uk/embl/Documentation/FT_definitions/feature_table.html\" target=\"_top\">FT definition</a>".
	"</b></ul></td>".
	    "</tr></TABLE></TABLE>\n".
	"<p align=center>Molecule type: <b>$mol</b> - Status: ".($gold{$title}?'<img src="1star.gif" width=11 height=11 vspace=3>':'').
	"<b>$status</b>".
	"<CENTER><TABLE BORDER=0 CELLSPACING=0 CELLPADDING=3 WIDTH=\"100%\" BGCOLOR=\"#EEEEEE\"><tr><td>".
	"<pre>\n\n";
    ($cl, $kw, $fh) = ('#EEEEEE',0,0);
    LINE: while (defined ($line = <IN>)){
	if ($line =~ /^\s+$/ or $line =~ /^XX/) {next LINE};
	$line =~ s/__/../g;
	if ($line =~ /^KW/ && !$kw) {
	    $kw = 1; print OUT "\n</td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>"};
#	      if ($cl eq '#DDDDDD') {$cl='#EEEEEE'} else  {$cl='#DDDDDD'};};
	if ($line =~ /^FH/ && !$fh) {
	    $fh = 1; print OUT "</td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>\n\n";
	      if ($cl eq '#DDDDDD') {$cl='#EEEEEE'} else  {$cl='#DDDDDD'};};
#	if ($line =~ /^FH\s*$/ && $fh) {$line =~ s/FH/FH\n/};
	$line =~ s/="(.+)\n$/="<font color="#8B0000">$1<\/font>\n/;     # free text
	$line =~ s/^(FT         \s+)(\w.+)("?)\n$/$1<font color="#8B0000">$2<\/font>$3\n/;   # free text 2
	$line =~ s/"<\/font>/<\/font>"/;     # free text
	$line =~ s/^(FT\s+)\/(\w+)/$1\/<a href=\"http:\/\/www3.ebi.ac.uk\/Services\/WebFeat\/qualifiers\/$2.html" target=\"examples\">$2<\/a>/; # qualifier
	if ($line =~ s/^FT   ([A-Za-z_0-9\-']+)/FT   <a href=\"http:\/\/www3.ebi.ac.uk\/Services\/WebFeat\/$1.html" target=\"examples\">$1<\/a>/)    # key
	     {print OUT "</td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>";
	      if ($cl eq '#DDDDDD') {$cl='#EEEEEE'} else  {$cl='#DDDDDD'};}; # key
	$line =~ s/^DE   (.+)\n$/DE   <font color="#8B0000">$1<\/font>\n/;  # DE
	$line =~ s/^CE   (.+)\n$//;  # CE
	$line =~ s/^CC\s+(.+)\n$/     <font color="#F90000">$1<\/font>\n/;  # Comments
	$line =~ s/^RL   (\S+)\s+(.+)\n$/     <font color="#8B0000">Related site: <\/font><a href="$1" target=_blank>$2<\/a>\n/;  # Related links
	$line =~ s/^CC//;  # empty Comments
	print OUT $line;
    };

    print OUT "</pre></td></tr></table></CENTER>".
	"<hr>- EBI Internal Curator's Version -</CENTER><br><pre>".
	    "File:   $UNIX_DIR$file<br>".
	    "Script: $SCRIPT_DIR/std2htmlnew.pl</pre><hr>".
	    "<CENTER>Last updated by <b>$author</b> $lasttouched<br>"."</CENTER>".$FOOTER;
	#"<center><a href=\"../../curatorhp.html\"".
	#"target=\"_top\"><img align=\"MIDDLE\" src=\"../../icons/button.gif\"></a>".$FOOTER;
    close (OUT);
    close (IN);
}
closedir DIR;
print INDEX $HEADER."<center>\n".
	"<TABLE BORDER=0 CELLSPACING=3 CELLPADDING=3 WIDTH=\"100%\" BGCOLOR=\"#E9E9E9\">".
    "<tr><td BGCOLOR=\"#3CB371\" align=center valign=\"top\"><font color=\"#FFFFFF\"><b>D<br>N<br>A</b></font></td><td><font size=\"-1\">";
foreach $title (sort keys %list_D) {
  if ($gold{$title}) {
      print INDEX "<img src=\"1star.gif\" width=11 height=10 vspace=3>"}
  else {
      print INDEX "<img src=\"bstar.gif\" width=11 height=10 vspace=3>"};
#     print INDEX "<FONT COLOR=\"#b30000\" SIZE=+1>&#149;&nbsp;</FONT>".
      print INDEX "<a href=\"$list_D{$title}\" target=\"examples\">$title</a><br>\n";
};
print INDEX "</td></tr><tr><td BGCOLOR=\"#3CB371\" align=center valign=\"top\"><font color=\"#FFFFFF\"><b>R<br>N<br>A</b></font></td><td><font size=\"-1\">";
foreach $title (sort keys %list_R) {
  if ($gold{$title}) {
      print INDEX "<img src=\"1star.gif\" width=11 height=10 vspace=3>"}
  else {
      print INDEX "<img src=\"bstar.gif\" width=11 height=10 vspace=3>"};
    print INDEX "<a href=\"$list_R{$title}\" target=\"examples\">$title</a><br>\n";
};
print INDEX "</font></td></tr></table>".$FOOTER;
close (INDEX);
print "======================== Finished internal standards ================================\n\n";


$HEADER = "<HTML>\n<HEAD>\n<TITLE>EMBL Flat File Examples</TITLE>\n</HEAD>\n".
    "<BODY bgcolor=\"#FFFFFF\" text=\"#000000\" link=\"#0000DD\" vlink=\"#0000DD\" alink=\"#FF0000\">\n";

$s_com = "date +\"%d-%m-%y\"";
chomp ($todays = `$s_com`);
print $todays; 
print "\n=======================Starting PUBLIC STANDARD TO HTML v$VERSION======================\n";

$Public_Web_Dir = "/ebi/www/web/public/Services/Standards/web";

opendir DIR, $UNIX_DIR;

system('umask 002');

open (INDEX, "> $Public_Web_Dir/list.html") or die "ERROR ! Can't open public file <web/list.html> : $!\n";

FILE: while (defined ($file = readdir DIR)) {
    unless (($root) = ($file =~ /^(\w+)\.$STD_FILES$/)) {next FILE};
    open (IN,  "< $UNIX_DIR/$file") or die "ERROR ! Can't open file <$file> : $!\n";
    $line = <IN>;
    if (($title) = ($line =~ /^ID\s+(.+)\n$/)) {
            $title = ucfirst ($title);
	}
    else {
	print "ERROR: No ID line!\n"; 
	close (IN); 
	next FILE;
    };

    $line = <IN>;
    if ($line =~ /^ML\s+(RNA|DNA)/) {
	$mol = $1;
	}
    else {
	print "ERROR: No ML (molecule) line!\n"; 
	close (IN); 
	next FILE;
    };
    $line = <IN>;

    if ($line =~ /^AU\s+(.+)\n$/) {
	$author = $1;
	}
    else {
	$author = 'anonymous';
    };
    $line = <IN>;
    if ($line =~ /^ST\s+(\S.+)\n$/) {
	$status = $1;
    }
    else {
	$status = 'Preliminary';
	};
    if ($status =~ /gold standard/i) {
	$gold{$title} = 1;
	print "".(sprintf "%-30.30s", $title);
	print "\t$mol\t$author\t$status\n";
	if ($mol eq 'DNA') {$list_D_p{$title} = "$root.html"} else {$list_R_p{$title} = "$root.html"};
	
	
	open (OUT, "> $Public_Web_Dir/$root.html") or die "ERROR ! Can't open file <web/$root.html> : $!\n";
	$html = $HEADER; $html =~ s/Examples/Examples: $title/;
	print OUT $html;
	print OUT "<CENTER><TABLE BORDER=0 CELLSPACING=3 CELLPADDING=3 WIDTH=\"100%\" BGCOLOR=\"#E9E9E9\">";
	print OUT "<tr><td align=\"center\" BGCOLOR=\"#3CB371\"><TABLE BORDER=0 CELLSPACING=0 ";
	print OUT "CELLPADDING=0 WIDTH=\"100%\" BGCOLOR=\"#3CB371\"><tr>";
	print OUT "<td><h2 align=\"center\"><font color=\"#FFFFFF\">EMBL Annotation Examples</font></h2></td></tr>";
        print OUT "<tr><td align=center><font size=-1 color=\"#FFFFFF\">Last modified: $todays </font></td>";
	print OUT "</tr></TABLE></table>\n";
	print OUT "<h2 align=center>$title</h2>";
	print OUT "<CENTER><TABLE BORDER=0 CELLSPACING=0 CELLPADDING=3 WIDTH=\"100%\""; 
        print OUT "BGCOLOR=\"#EEEEEE\"><tr><td><pre>\n\n";
	print OUT "Molecule type: <b>$mol</b>\n\n";
	($cl, $kw, $fh) = ('#EEEEEE',0,0);
      LINE: while (defined ($line = <IN>)){
	  if ($line =~ /^\s+$/ or $line =~ /^XX/) {next LINE};
	  $line =~ s/__/../g;
	  if ($line =~ /^KW/ && !$kw) {next LINE};
	  if ($line =~ /^FH/ && !$fh) {
	      $fh = 1; print OUT "</td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>\n\n";
	      if ($cl eq '#DDDDDD') {$cl='#EEEEEE'} else  {$cl='#DDDDDD'};
	  };
	  $line =~ s/="(.+)\n$/="<font color="#8B0000">$1<\/font>\n/;
	  $line =~ s/^(FT         \s+)(\w.+)("?)\n$/$1<font color="#8B0000">$2<\/font>$3\n/;
	  $line =~ s/"<\/font>/<\/font>"/;
	  $line =~ s/^(FT\s+)\/(\w+)/$1\/<a href="..\/..\/WebFeat\/qualifiers\/$2.html" target="examples">$2<\/a>/;
	  if ($line =~ s/^FT   ([A-Za-z_0-9\-']+)/FT   <a href="..\/..\/WebFeat\/$1.html" target="examples">$1<\/a>/)
	     {print OUT "</td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>";
	      if ($cl eq '#DDDDDD') {$cl='#EEEEEE'} 
				 else  {$cl='#DDDDDD'};
			     };
	$line =~ s/^DE   (.+)\n$/DE   <font color="#8B0000">$1<\/font>\n/;
	$line =~ s/^CE\s+(.+)\n$/     <font color="#F90000">$1<\/font>\n/;  # Public Comments
	$line =~ s/^RL   (\S+)\s+(.+)\n$/<font color="#8B0000">Related site: <\/font><a href="$1" target=_blank>$2<\/a>\n/;  # Related links
				if ($line =~ /^CC/) {
				    next LINE};
				print OUT $line;
			    };

    print OUT "</pre></td></tr></table>".
	    "<font size=-1><i>- This view last updated May 2002 -</i></font></CENTER>".$FOOTER;
			      close (OUT);}
    close (IN);
}
closedir DIR;
print INDEX $HEADER."<center>\n".
	"<TABLE BORDER=0 CELLSPACING=3 CELLPADDING=3 WIDTH=\"100%\" BGCOLOR=\"#E9E9E9\">".
    "<tr><td BGCOLOR=\"#3CB371\" align=center valign=\"top\"><font color=\"#FFFFFF\"><b>D<br>N<br>A</b></font></td><td><font size=\"-1\">";
foreach $title (sort keys %list_D_p) {
      print INDEX "<a href=\"$list_D_p{$title}\" target=\"examples\">$title</a><br>\n";
};
print INDEX "</td></tr><tr><td BGCOLOR=\"#3CB371\" align=center valign=\"top\"><font color=\"#FFFFFF\"><b>R<br>N<br>A</b></font></td><td><font size=\"-1\">";
foreach $title (sort keys %list_R_p) {
    print INDEX "<a href=\"$list_R_p{$title}\" target=\"examples\">$title</a><br>\n";
};
print INDEX "</font></td></tr></table>".$FOOTER;
close (INDEX);

print "======================== Finished public standards ================================\n\n";







__END__



