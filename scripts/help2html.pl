#!/ebi/production/seqdb/embl/tools/bin/perl -w
 
#help2html
#purpose: makes html version of align.help file

$HEADER = "";
$UNIX_DIR = "/ebi/www/web/public/Services/align";
open (IN,  "< $UNIX_DIR/alilist.header") or die "ERROR ! Can't open header file : $!\n";

while (<IN>) {
    $HEADER = $HEADER.$_; 
};
close (IN);
open (INDEX, "> $UNIX_DIR/listali.html") or die "ERROR ! Can't open file html file : $!\n";
print INDEX $HEADER;


$helpfile='/ebi/ftp/pub/help/align.help';
open(INFILE, $helpfile) || die "can't open help file\n";

$line_start="</td></font></tr><tr><td align=left><FONT FACE=\"Arial,Helvetica,Univers,Zurich BT\"><a href=\"ftp://ftp.ebi.ac.uk/pub/databases/embl/align/";
$line_br ="</a></font></td><td align=left><FONT FACE=\"Arial,Helvetica,Univers,Zurich BT\">";
$verytop=1;
$plusdat="\.dat\">";
while (<INFILE>) {
    if ( /.*(ds\d*).dat\s*-\s(.*)/ || /.*(ALIGN_\d*).dat\s*-\s(.*)/) {
        $html_line = $line_start.$1.$plusdat.$1.$line_br.$2;
        print INDEX $html_line;
	$verytop=0;
    } 
    else { 
	if (not($verytop)){
	    if (/Submitted/) {$html_line="<br>".$_} else {$html_line=$_}; 
	    print INDEX $html_line; 
	};
    }
};
close (INFILE);
open (IN,  "< $UNIX_DIR/alilist.footer") or die "ERROR ! Can't open footer file : $!\n";

$footer = "";
while (<IN>) {
    $footer = $footer.$_ 
};
close (IN);

print INDEX $footer;

$s_com = "date +\"%d-%m-%y\"";
chomp ($todays = `$s_com`);
print INDEX "<i>Last modified :$todays</i>\n";
print INDEX ("<\/body><\/html>");
close(INDEX);













