#!/sw/arch/bin/perl -w

#
# std2htmlnew.pl
#
# Purpose : make html files out of standards files, both public and internal at the same time
# only "gold star" standard are made into public html
# standard files are in /ebi/www/web/internal/Services/curators/standards
#
#	Last Modification: 24/11/2003
#	Modified by: Adam Lowe (aplowe@ebi.ac.uk, adam@aplowe.com)
#	Purpose: General tidy-up.
#
#   NOTES: labels (FILE: and LINE:) only used for last/next operations on surrounding loop so I removed them.
#      	Coding style changed so C++/Java programmers have a chance of reading it.
#      	The (mostly duplicate) sections of code for individual internal/external page
#      	generation have been placed in two subroutines - from a maintenance viewpoint
#      	eliminating the obvious duplication of code is probably not worthwhile.
#      	Larger blocks of HTML have been merged into '<<' regions to allow easier maintenance.
#      	  The use of 'print "", << "TERMINATOR";' is important to ensure perl gets the idea 
#      	  (saves implying persistance by assigning a label to the string).
#
use strict;

#
# NOTE: If you want nice EBI paths (/ebi/xxx/yyy) reported on internal pages
# make sure you call with absolute path else the script may well prepend the
# physical path (/net/nfs/zzz/xxx/yyy).
#
my $SCRIPT_LOCATION = $0;
# if not rooted prepend working directory to path (assuming Unix or Unix-like OS)
if ($SCRIPT_LOCATION !~ m"^/") {
	$SCRIPT_LOCATION = `pwd`;
	chomp($SCRIPT_LOCATION);
	$SCRIPT_LOCATION .= "/$0";
	# may as well blow away any "/./"s in the path...
	$SCRIPT_LOCATION =~ s"/./"/"g;
}

########################################################################
# subroutine declarations...
########################################################################
sub main ();

# two functions for printing the main content html files...
#
#	Parameters:
#	0 input file name (including path)
#	1 output file name (including path)
#	2 last modified string
#	3 title (since we already processed it)
#	4 molecule type (since we already processed it)
#
# generates internal html document and returns 1 for 'gold standard', 0 otherwise
sub printInternalHTMLFile ($$$$$);
# generates external html document IFF status is 'gold standard', else it just returns 0
sub printExternalHTMLFile ($$$$$);


##############Main######################################################
# run main() then exit! 
main();
exit;


########################################################################
# subrouting definitions...
########################################################################

sub main () {
	# ADAM has localised these puppies as there is no gain in treating them as globals...
	my $UNIX_DIR = "/ebi/www/web/internal/Services/curators/standards";
	my $SCRIPT_DIR = "/ebi/services/tools/curators/scripts/perl";
	my $STD_FILES = 'std';
	my $VERSION = '4.0';
	my $TMPFILE = "$SCRIPT_DIR/std2html.temp";
	my $INTERNAL_WEB_DIR = "/ebi/www/web/internal/seqdb/curators/standards/web";
        my $PUBLIC_WEB_DIR = "/ebi/www/web/public/Services/Standards/web";
	#my $INTERNAL_WEB_DIR = "/homes/vaughan/public_html/test/int-web";
	#my $PUBLIC_WEB_DIR = "/homes/vaughan/public_html/test/pub-web";
	
	# variables...
	my ($dir, $intindex, $extindex, $filename, $fil, $line, $lasttouched, $title, $i, $err, $root, $mol);
	my %dnafiles = ();
	my %rnafiles = ();
	my @st = ();
	
	print "\n========================Starting STANDARD TO HTML v$VERSION========================\n";
	
	# make sure we don't lock anyone out with permissions problems...
	system('umask 002');
	
	# INTERNAL INDEX PAGE (MENU)....
	print "INTERNAL list file $INTERNAL_WEB_DIR/list.html\n";
	
	# EXTERNAL INDEX PAGE (MENU)....
	print "EXTERNAL list file $PUBLIC_WEB_DIR/list.html\n";
	
	open $intindex, "> $INTERNAL_WEB_DIR/list.html" or die "ERROR ! Can't open file <$INTERNAL_WEB_DIR/list.html> : $!\n";
	
	print $intindex "", << "EOINTINDEXHEADER";
<html>
<head>
<title>EMBL Flat File Examples</title>
<link href="http://www3.ebi.ac.uk/internal/seqdb/include/stylesheet.css" rel="stylesheet" type="text/css">
<style type="text/css">
A.standardslink:link { font-family: Arial, Helvetica, sans-serif; font-size: 11pt; font-weight: bold; color: #ffffff ; text-decoration: none}
A.standardslink:visited { font-family: Arial, Helvetica, sans-serif; font-size: 11pt; font-weight: bold; color: #ffffff ; text-decoration: none}
A.standardslink:active { font-family: Arial, Helvetica, sans-serif; font-size: 11pt; font-weight: bold; color: #ffffff ; text-decoration: none}
A.standardslink:hover { font-family: Arial, Helvetica, sans-serif; font-size: 11pt; font-weight: bold; color: #ffffff ; text-decoration: underline}
li.standardslist {color: #ffffff }
</style></head>
<body bgcolor="#FFFFFF" text="#000000" link="#0000DD" vlink="#0000DD" alink="#FF0000">
<center>
<table border="0" cellspacing="3" cellpadding="3" width="100%" bgcolor="#E9E9E9">
EOINTINDEXHEADER
	;
	
	open $extindex, ">$PUBLIC_WEB_DIR/list.html" or die  "ERROR ! Can't open file <$PUBLIC_WEB_DIR/list.html> : $!\n";
	
	print $extindex "", << "EOEXTINDEXHEADER";
<html>
<head>
<title>EMBL Flat File Examples</title>
<link rel="stylesheet" href="http://www.ebi.ac.uk/services/include/stylesheet.css" type="text/css">
</head>
<body bgcolor="#FFFFFF" text="#000000" link="#0000DD" vlink="#0000DD" alink="#FF0000">
<center>
<table border="0" cellspacing="3" cellpadding="3" width="100%" bgcolor="#E9E9E9">
EOEXTINDEXHEADER
	;
	
	
	print "Checking title and mol type of files...\n";
	$err = 0;
	# making sure we end up with the files in TITLE sorted order...
	opendir $dir, $UNIX_DIR or die "Failed to open source directory ($UNIX_DIR) for input\n";
	%dnafiles = ();
	%rnafiles = ();
	while (defined ($filename = readdir $dir)) {
		
		unless (($filename =~ /^(\w+)\.$STD_FILES$/)) {
			next;
		}
		
		# need to have a quick peek inside the file for title/mol type
		open $fil, "$UNIX_DIR/$filename" or die "ERROR ! Can't open file <$filename> : $!\n";		
		
		# title
		$line = <$fil>;
		if (($title) = ($line =~ /^ID\s+(.+)\n$/)) {
			$title = ucfirst ($title);
		} else {
			print "ERROR: No ID line in file $UNIX_DIR/$filename!\n";
			$err++;
			close $fil; 
			next;
		}
	
		# mol type...
		$line = <$fil>;		
		($mol) = ($line =~ /^ML\s+(RNA|DNA)\n$/);
		
		if ($mol eq "DNA") {
			$dnafiles{"$title"} = $filename;
		} elsif ($mol eq "RNA") {
			$rnafiles{"$title"} = $filename;
		} else {
			$err++;
		}
			
		close $fil;
	}
	closedir $dir;
	# finished hashing...
	
	if ($err) {
		print "ERROR: $err file(s) did not contain parsable ID or ML lines and will\nnot be processed - see error messages above\n";
	} else {
		print "All files appear to be okay, processing all of them\n";
	}
	
	# now DNA files in order of title...
	print "=======================Processing files for mol type DNA======================\n";
	print $intindex "<tr><td BGCOLOR=\"#7F9EDC\" align=\"center\" valign=\"top\"><font color=\"#FFFFFF\">",
				"<b>D<br>N<br>A</b></font></td><td>\n";
	print $extindex "<tr><td BGCOLOR=\"#999999\" align=\"center\" valign=\"top\"><font color=\"#FFFFFF\">",
				"<b>D<br>N<br>A</b></font></td><td>\n";
	
	$err = 0;					
	# foreach file we previously hashed, process in order of title (alphabetically)
	foreach $title (sort keys %dnafiles) {
	
		$filename = $dnafiles{"$title"};
		
		($root) = ($filename =~ /^(\w+)\.$STD_FILES$/);
		
		# may as well use built in stat...
		@st = stat ("$UNIX_DIR/$filename");
		$lasttouched = localtime $st[9];
	
		if (printInternalHTMLFile("$UNIX_DIR/$filename", "$INTERNAL_WEB_DIR/$root.html", $lasttouched, $title, "DNA")) {
			print $intindex "<img src=\"http://www3.ebi.ac.uk/internal/Services/curators/standards/web/1star.gif\" width=\"11\" height=\"10\" vspace=\"3\">",
				"<a href=\"$root.html\" class=\"small_list\" target=\"examples\">$title</a><br>\n" ;
		} else {
			print $intindex "<img src=\"http://www3.ebi.ac.uk/internal/Services/curators/standards/web/bstar.gif\" width=\"11\" height=\"10\" vspace=\"3\">\n",
				"<a href=\"$root.html\" class=\"small_list\" target=\"examples\">$title</a><br>\n" ;
		}
		
		if (printExternalHTMLFile("$UNIX_DIR/$filename", "$PUBLIC_WEB_DIR/$root.html", $lasttouched, $title, "DNA")) {
			print $extindex "<a href=\"$root.html\" class=\"pbold_grey_small\" target=\"examples\">$title</a><br>\n";
		} else {
			$err++;
		}
	}
	
	print $intindex "</td></tr>\n";
	print $extindex "</td></tr>\n";
	
		
	# now RNA files in order of title...
	print "=======================Processing files for mol type RNA======================\n";
	
	print $intindex "<tr><td BGCOLOR=\"#29498C\" align=\"center\" valign=\"top\"><font color=\"#FFFFFF\">",
		"<b>R<br>N<br>A</b></font></td><td>";
	
	print $extindex "<tr><td BGCOLOR=\"#666666\" align=\"center\" valign=\"top\"><font color=\"#FFFFFF\">",
		"<b>R<br>N<br>A</b></font></td><td>\n";
	
	# foreach file we previously hashed, process in order of title (alphabetically)
	foreach $title (sort keys %rnafiles) {
	
		$filename = $rnafiles{"$title"};
		
		($root) = ($filename =~ /^(\w+)\.$STD_FILES$/);
		
		# may as well use built in stat...
		@st = stat ("$UNIX_DIR/$filename");
		$lasttouched = localtime $st[9];
	
		if (printInternalHTMLFile("$UNIX_DIR/$filename", "$INTERNAL_WEB_DIR/$root.html", $lasttouched, $title, "RNA")) {
			print $intindex "<img src=\"http://www3.ebi.ac.uk/internal/Services/curators/standards/web/1star.gif\" width=\"11\" height=\"10\" vspace=\"3\">",
				"<a href=\"$root.html\" class=\"small_list\" target=\"examples\">$title</a><br>\n" ;
		} else {
			print $intindex "<img src=\"http://www3.ebi.ac.uk/internal/Services/curators/standards/web/bstar.gif\" width=\"11\" height=\"10\" vspace=\"3\">\n",
				"<a href=\"$root.html\" class=\"small_list\" target=\"examples\">$title</a><br>\n" ;
		}
		
		if (printExternalHTMLFile("$UNIX_DIR/$filename", "$PUBLIC_WEB_DIR/$root.html", $lasttouched, $title, "RNA")) {
			print $extindex "<a href=\"$root.html\" class=\"pbold_grey_small\" target=\"examples\">$title</a><br>\n";
		} else {
			$err++;
		}
	}
	
	print $intindex "</td></tr></table>\n</center>\n</body></html>\n";
	print $extindex "</td></tr></table>\n</center>\n</body></html>\n";
	
	# all done close and exit!
	close $intindex;
	close $extindex;
	
	print "========================Finished Processing files============================\n";
	print "$err files were not \'Gold Standard\' and so have not been made public\n";
	print "\n========================Finished STANDARD TO HTML v$VERSION=======================\n";
	
}
# end of main...

# generate an internal page
sub printInternalHTMLFile($$$$$) {
	my ($infilename, $outfilename, $lasttouched, $title, $mol_type) = @_;
	my ($in, $out, $author, $status, $gold);
	my ($cl, $kw, $fh, $line, $bgcolour);
	
	if ($mol_type eq "RNA") {
		$bgcolour = "29498C";
	} else {
		$bgcolour = "7F9EDC";
	}
	
	open $in, "$infilename";
		
	# skip title and mol type as we've already processed them...
	$line = <$in>;
	$line = <$in>;

	# author	
	$line = <$in>;
    ($author) = ($line =~ /^AU\s+(.+)\n$/);
   
   	# status
    $line = <$in>;
    ($status) = ($line =~ /^ST\s+(\S.+)\n$/);
  
  	$gold = 0;
  	if ($status) {
	    $gold = $status =~ /gold standard/i;
	}
	
	# logging...
	print "INTERNAL\t";
	print "".(sprintf "%-30.30s", $title);
	print "\t$mol_type\t";

	if ($author) {
		print "$author\t";
	} else {
    	print "ERROR: No AU (author) line!\t";
    	$author = 'anonymous';
    }
	
	if ($status) {
		print "$status\t";
	} else {
    	print "ERROR: No ST (status) line!\t";
    	$status = 'Preliminary';
    }
    print "\n";

  	open $out, ">$outfilename" or die "ERROR ! Can't open file <$outfilename> : $!\n";
   	print $out "", << "ENDOFINTERNALHTMLHEADER";
<html>
<head>
<title>EMBL Flat File Examples: EMBL Flat File Examples: $title</title>
<style type="text/css">
A.standardslink:link { font-family: Arial, Helvetica, sans-serif; font-size: 10pt; font-weight: bold; color: #ffffff ; text-decoration: none}
A.standardslink:visited { font-family: Arial, Helvetica, sans-serif; font-size: 10pt; font-weight: bold; color: #ffffff ; text-decoration: none}
A.standardslink:active { font-family: Arial, Helvetica, sans-serif; font-size: 10pt; font-weight: bold; color: #ffffff ; text-decoration: none}
A.standardslink:hover { font-family: Arial, Helvetica, sans-serif; font-size: 10pt; font-weight: bold; color: #ffffff ; text-decoration: underline}
li.standardslist {color: #ffffff }
</style></head>
<body bgcolor="#FFFFFF" text="#000000" link="#0000DD" vlink="#0000DD" alink="#FF0000">
<center>
<table border="0" cellspacing="3" cellpadding="3" width="100%" bgcolor="#E9E9E9"><tr><td align="center" bgcolor="#$bgcolour">
<table border="0" cellspacing="0" cellpadding="0" width="100%" bgcolor="#$bgcolour"><tr><td align="center" width="100">
<a href="http://www3.ebi.ac.uk/internal/Services/curators/" target="_top">
<img border="0" align="center" src="http://www3.ebi.ac.uk/internal/Services/curators/icons/button.gif"></a></td>
<td><h2 align="center"><font color="#FFFFFF">$title</font></h2></td><td width="150"><ul style="margin-bottom:0">
<li class="standardslist"><a class = "standardslink" href="http://www3.ebi.ac.uk/internal/seqdb/curators/guides/guidelines.html" target="_top">Guidelines</a></li>
<li class="standardslist"><a class="standardslink" href="http://www.ebi.ac.uk/embl/WebFeat/" target="_top">Web Feat</a></li>
<li class="standardslist"><a class="standardslink" href="http://www.ebi.ac.uk/embl/Documentation/FT_definitions/feature_table.html" target="_top">FT definition</a></li>
<li class="standardslist"><a class="standardslink" href="http://www.ebi.ac.uk/embl/Standards/web/index.html" target="_top">External Version</a></li>
</ul></td></tr>
</table>
</td></tr></table>
<p align="center">Molecule type: <b>$mol_type</b> - Status:
ENDOFINTERNALHTMLHEADER
;
	
	if ($gold) {
		print $out "<img src=\"http://www3.ebi.ac.uk/internal/Services/curators/standards/web/1star.gif\" width=\"11\" height=\"10\" vspace=\"3\">\n";
	}
	print $out "<b>$status</b>",
"<table border=\"0\" cellspacing=\"0\" cellpadding=\"3\" width=\"100%\" bgcolor=\"#EEEEEE\"><tr><td>",
"<pre>\n\n";

    ($cl, $kw, $fh) = ('#EEEEEE','#EEEEEE', 0,0);
    
    while (defined ($line = <$in>)){
    
		if ($line =~ /^\s+$/ or $line =~ /^XX/) {
			next;
		}
		
		# rest of this is more-or-less as-was 
		# (just changed the regular expressions to use | to save escaping '/')...
		$line =~ s/__/../g;
		
		if ($line =~ /^KW/ && !$kw) {
			$kw = 1; 
			print $out "\n</pre></td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>";
		}

		if ($line =~ /^FH/ && !$fh) {
			$fh = 1; 
			print $out "</pre></td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>\n\n";
			if ($cl eq '#DDDDDD') {
				$cl='#EEEEEE';
			} else  {
				$cl='#DDDDDD';
			}
		}
		$line =~ s|="(.+)\n$|="<font color="#8B0000">$1</font>\n|;     # free text
		$line =~ s|^(FT         \s+)(\w.+)("?)\n$|$1<font color="#8B0000">$2</font>$3\n|;   # free text 2
		$line =~ s|"</font>|</font>"|;     # free text
		$line =~ s|^(FT\s+)/(\w+)|$1/<a href="http://www.ebi.ac.uk/embl/WebFeat/qualifiers/$2.html" target="examples">$2</a>|; # qualifier
		if ($line =~ s|^FT   ([A-Za-z_0-9\-']+)|FT   <a href="http://www.ebi.ac.uk/embl/WebFeat/$1.html" target="examples">$1</a>|)    # key
		{
			 print $out "</pre></td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>";
			 if ($cl eq '#DDDDDD') {
			 	$cl='#EEEEEE';
			 } else {
			 	$cl='#DDDDDD';
			 }
		} # key
		$line =~ s|^DE   (.+)\n$|DE   <font color="#8B0000">$1</font>\n|;  # DE
		$line =~ s|^CE   (.+)\n$||;  # CE
		$line =~ s|^CC\s+(.+)\n$|     <font color="#F90000">$1</font>\n|;  # Comments
		$line =~ s|^RL   (\S+)\s+(.+)\n$|     <font color="#8B0000">Related site: </font><a href="$1" target="_blank">$2</a>\n|;  # Related links
		$line =~ s/^CC//;  # empty Comments
		print $out $line;
    }

    print $out "", << "EOFOOTER";
</pre></td></tr></table>
<hr>- EBI Internal Curator's Version -<br>
</center>
<pre>
File:   $infilename<br>
Script: $SCRIPT_LOCATION
</pre>
<hr>
<p align="center">Last updated by <b>$author</b> $lasttouched</p>
</body></html>
EOFOOTER
	;
	   

	close $in;
    close $out;
    
    return $gold;
}

# same again for external site...
sub printExternalHTMLFile ($$$$$) {
	my ($infilename, $outfilename, $lasttouched, $title, $mol_type) = @_;
	my ($in, $out, $author, $status, $bgcolour);
	my ($cl, $kw, $fh, $line);

	open $in, "$infilename";
	
	if ($mol_type eq "RNA") {
		$bgcolour = "666666";
	} else {
		$bgcolour = "999999";
	}
	
	# skip title and mol type as we've already processed them...
	$line = <$in>;
	$line = <$in>;

	# author
	$line = <$in>;
    ($author) = ($line =~ /^AU\s+(.+)\n$/);
    
    # status
    $line = <$in>;
    ($status) = ($line =~ /^ST\s+(\S.+)\n$/);
    	
	# logging...
	print "PUBLIC\t";
	print "".(sprintf "%-30.30s", $title);
	print "\t$mol_type\t";
     
	if ($author) {
		print "$author\t";
	} else {
    	print "ERROR: No AU (author) line\t";
    	$author = 'anonymous';
    }
    
    if (! $status || $status !~ /gold standard/i) {
    	print "skipping file\n";
		close $in;
		return 0;
	}
	
	print "$status\n";
	
	open $out, ">$outfilename" or die "ERROR ! Can't open file <$outfilename> : $!\n";
	print $out "", << "ENDOFEXTERNALHTMLHEADER";
<html>
<head>
<title>EMBL Flat File Examples: $title</title>
</head>
<body bgcolor="#FFFFFF" text="#000000" link="#0000DD" vlink="#0000DD" alink="#FF0000">
<center>
<table border="0" cellspacing="3" cellpadding="3" width="100%" bgcolor="#E9E9E9">
<tr><td align="center" BGCOLOR="#$bgcolour">
<table border="0" cellspacing="0" cellpadding="0" width="100%" bgcolor="#$bgcolour">
<tr><td><h2 align="center">
<font color="#FFFFFF">EMBL Annotation Examples</font></h2>
</td></tr>
<tr><td align="center">
<font size=-1 color="#FFFFFF">Last modified: $lasttouched </font>
</td></tr></table>
</td></tr></table>
<h2 align="center">$title</h2>
<table border="0" cellspacing="0" cellpadding="3" width="100%"bgcolor="#EEEEEE">
<tr><td><pre>
Molecule type: <b>$mol_type</b>		
ENDOFEXTERNALHTMLHEADER
	;

	($cl, $kw, $fh) = ('#EEEEEE',0,0);
	
	while (defined ($line = <$in>)) {
		# adam moved these conditions to top of loop
		if ($line =~ /^\s+$/ || $line =~ /^XX/ || $line =~ /^CC/ ||
			($line =~ /^KW/ && !$kw)) {
			next;
		}
		
		# rest of this is more-or-less as-was 
		# (just changed the regular expressions to use | to save escaping '/')...
		$line =~ s/__/../g;
		
		if ($line =~ /^FH/ && !$fh) {
			$fh = 1; print $out "</pre></td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>\n\n";
			if ($cl eq '#DDDDDD') {
				$cl='#EEEEEE';
			} else  {
				$cl='#DDDDDD';
			}
		}
		$line =~ s|="(.+)\n$|="<font color="#8B0000">$1</font>\n|;
		$line =~ s|^(FT         \s+)(\w.+)("?)\n$|$1<font color="#8B0000">$2</font>$3\n|;
		$line =~ s|"</font>|</font>"|;
		$line =~ s|^(FT\s+)/(\w+)|$1/<a href="http://www.ebi.ac.uk/embl/WebFeat/qualifiers/$2.html" target="examples">$2</a>|;
		if ($line =~ s|^FT   ([A-Za-z_0-9\-']+)|FT   <a href="http://www.ebi.ac.uk/embl/WebFeat/$1.html" target="examples">$1</a>|) {
			print $out "</pre></td></tr>\n<tr><td BGCOLOR=\"$cl\"><pre>";
		}
		if ($cl eq '#DDDDDD') {
			$cl='#EEEEEE';
		} else  {
			$cl='#DDDDDD';
		}
		$line =~ s|^DE   (.+)\n$|DE   <font color="#8B0000">$1</font>\n|;
		$line =~ s|^CE\s+(.+)\n$|     <font color="#F90000">$1</font>\n|; # Public Comments
		$line =~ s|^RL   (\S+)\s+(.+)\n$|<font color="#8B0000">Related site: </font><a href="$1" target="_blank">$2</a>\n|;  # Related links
		
		print $out $line;
	}

	print $out "", << "EOFOOTER";
</pre></td></tr></table>
<br>
<font size=-1><i>- This view last updated May 2002 -</i></font>
</center>
</body>
</html>
EOFOOTER
	;
	
	close $in;
	close $out;
	
	return 1;
}

__END__



