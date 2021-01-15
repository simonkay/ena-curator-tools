#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/WebFeat2.pl,v 1.20 2011/11/29 16:33:37 xin Exp $
#
#  (C) EBI 2000
#
#  Written by Pascal Hingamp & Vincent Lombard
#
#  MODIFICATION HISTORY:
#  05-Mar-2003          - new design
#  12-Dec-2007            pass the directory on the command line
#
#
###############################################################################
#  PLEASE NOTE, the /align/ subdirectory probably should not be regenerated with this script, don't ignore the existing subdirectory
use strict;
use warnings;

my $debugging = 0;
if ($debugging) {
    select(STDOUT); $| = 1; # make unbuffered
    select(STDERR); $| = 1; # make unbuffered
}
umask 002; # ie rw-rw-r--

my %featHeaderRegex = ('key'                 => '^Feature\sKey\s+(\S+)$',  
		       'definition'          => '^Definition\s+(\S.+\S)',
		       'qualifiersMandatory' => '^Mandatory [Qq]ualifiers\s+(\S+.*)',
		       'qualifiersOptional'  => '^Optional [Qq]ualifiers\s+(\S+)',
		       'parent'              => '^Parent [Kk]ey\s+(\S.+\S)',
		       'scopeOrganism'       => '^Organism [Ss]cope\s+(\S.+\S)',
		       'scopeMolecule'       => '^Molecule [Ss]cope\s+(\S.+\S)',
		       'references'          => '^References?\s+(\S.+\S)',
		       'example'             => '^Examples?\s+(\S.+\S)',
		       'comment'             => '^Comments?\s+(\S.+\S)');
my $allFeatHeaderRegex = '(('.join(')|(', (values %featHeaderRegex)). '))';
my %qualHeaderRegex = ('qualifier'    => '^Qualifier\s+\/(\w+)',
		       'definition'   => '^Definition\s+(\S.+\S)',
		       'valueFormat'  => '^Value [Ff]ormat\s+(\S.+\n)',
		       'examples'     => '^Examples?\s+(\S.+\S)',
		       'comments'     => '^Comments?\s+(\S.+\S)'
		       );
my $allQualHeaderRegex = '(('.join(')|(', (values %qualHeaderRegex)). '))';
my %appendixRegex = ('endOfTOC'       => '^\s*\d+(\.?\d*)*\s+Country Names\s*$',
		     'featureStart'   => '^\s*\d+(\.?\d*)*\s+Appendix [A-Z]+:\s*Feature keys reference\s*$',
		     'qualifierStart' => '^\s*\d+(\.?\d*)*\s+Appendix [A-Z]+:\s*Summary of qualifiers for feature keys\s*$',
		     'qualifierEnd'   => '^\s*\d+(\.?\d*)*\s*Appendix [A-Z]+: Controlled vocabularies\s*$'
		     );

# handle the command line.
my $dir = "/ebi/production/seqdb/embl/data/WebFeat_web_pages"; ## old
my $sourceFile;
my $usage = "\n USAGE: WebFeat.pl <source_file> [<directory>]\n\n"
    . "where <source_file> is the location of a plaintext feature table document\n"
    . "If no directory is supplied it defaults to:\n"
    . "$dir (EMBL)\n\n"
    . "For the ALIGN database use:\n"
    . "WebFeat.pl /ebi/www/web/public/Services/WebFeat/align\n";

foreach my $arg (@ARGV) {
    if ($arg =~ /-h/){
	print "help?".$usage;
    } elsif ((-d $arg)
	     && (-w $arg)) {
	print "$arg is a real, directory that is writable\n";
	$dir = $arg;
    } elsif ((-r ($arg)
	      && (-f $arg))) {
	$sourceFile = $arg;
    } else {
	die $usage;
    }
}
if (!(defined($sourceFile))) {
    die $usage;
}

my $qualifiersDir = "$dir/qualifiers";
if (!(-e $qualifiersDir) | !(-d $qualifiersDir) || !(-w $qualifiersDir)) {
    (mkdir $qualifiersDir)
	|| die "Could not create $qualifiersDir\n" ;
}
print "Taking info from $sourceFile\n"
    . "and outputting to $dir"
    . " (and $qualifiersDir)\n";

my $header =
    "<html>\n<head>\n<title>EMBL Feature List</title>\n</head>\n<link rel=\"stylesheet\" "
    . "href=\"http://www.ebi.ac.uk/services/include/stylesheet.css\" type=\"text/css\">\n"
    . "<body bgcolor=\"#ffffff\" text=\"#000000\">\n";

my $footer = "</body>\n</html>\n";
my $keyFooter = "<tr>\n<td bgcolor=\"#669999\" align=\"right\" width=\"175\" valign=\"top\">"
    . "<font color=\"#ffffff\"><b>Last Updated</b></font></td>\n<td valign=\"top\">"
    . scalar localtime()
    . "</td>\n</tr>\n</table>\n</div>\n"
    . $footer;
my $qualifierFooter = "</td>\n</tr>\n</table>\n</div>\n" . $footer;
my $def    = "";


writeIndex($dir);
# start
print "\n=======================Starting FEATURE TO HTML v4======================\n";

#create the feature key frame
#(call the file alpha_key which contain all the feature key)
open(MENUBAR, "> $dir/alpha_key.html") or die "ERROR ! Can't create a new file, <$dir/alpha_key.html> : $!\n";
print MENUBAR $header
    . "<div align=\"center\">\n"
    . "<table border=\"0\" cellspacing=\"3\" cellpadding=\"3\" width=\"100%\" bgcolor=\"#eeeeee\">\n"
    . "<tr><td bgcolor=\"#669999\" valign=\"top\"><font color=\"#ffffff\"><b>F<br>E<br>A<br>T<br>U<br>R<br>E<br>S</b></font></td>\n"
    . "<td>";

###Feature Key

#read the feature key files
open(IN, "<$sourceFile") or die "ERROR ! Can't open feature table file <$sourceFile> : $!\n";

my ($key, $qual, $line);

# Get past the table of contents down to the real appendices
while ((defined($line = (<IN>)))
       && ($line !~ /$appendixRegex{'endOfTOC'}/)) {
    next;
}
#print "finished with line $.\n$line\n\n";
# Get to feature section
while ((defined($line = (<IN>)))
       && ($line !~ /$appendixRegex{'featureStart'}/)) {
    next;
}

my $keyFileHandle;
print "Expected order of Feature info\n"
    . " Feature Key\n"
    . " Definition\n"
    . " Mandatory qualifiers\n"
    . " Optional qualifiers\n"
    . " Parent Key\n"
    . " Organism scope\n"
    . " Molecule scope\n"
    . " References\n"
    . " Example\n"
    . " Comment\n";
# 
# NB 1 time Molecule scope before Parent key

#print "finished with line $.\n$line\n\n";
my $tryOnceMore = 0;
while (($tryOnceMore 
       || (defined($line = (<IN>))))
       && ($line !~ /$appendixRegex{'qualifierStart'}/)){
    $line =~ s/</&lt\;/g;
    $line =~ s/>/&gt\;/g;
    next if ($line =~ /^\s+$/);
    if ($line =~ /$featHeaderRegex{'key'}/) {
	$key = $1;
	$debugging && print $line; ##########
	
        if ($key eq 'source') {
            $qual = 'organism';
        } elsif ($key eq 'gene') {
            $qual = 'product';
        } else {
            $qual = 'gene';
        }
	
        # create a frame for each feature key
        open(OUT, "> $dir/$key.html") or die "ERROR ! Can't open file <$dir/$key.html> : $!\n";
	
        print OUT "<html><head><title>EMBL Database Features: $key</title></head>"
	    . "<frameset rows=\"70%,30%\" frameborder=\"yes\">\n"
	    . "<frame src=\"$key"
	    . "_s.html\" name=\"keys\">\n"
	    . "<frame src=\"qualifiers/$qual.html\" "
	    . "name=\"qualifiers\">\n</frameset>\n</html>";
        close(OUT);
	
        if ((defined($keyFileHandle))
	    && (fileno $keyFileHandle)) {
            print $keyFileHandle $keyFooter;
            close($keyFileHandle);
        }
        print "Feature: $key\n";
        #create the page use within the frame
        open($keyFileHandle, "> $dir/$key" . '_s.html') or die "ERROR ! Can't open file <$dir/$key" . "_s.html> : $!\n";
	
        print $keyFileHandle $header
	    . "<div align=\"center\">\n<table border=\"0\" cellspacing=\"3\" cellpadding=\"3\" height=\"100\%\" width=\"100\%\" bgcolor=\"#eeeeee\">\n"
	    . "<tr>\n<td bgcolor=\"#669999\" align=\"right\" width=\"175\">"
	    . "<font color=\"#ffffff\" size=\"+1\"><b>Feature</b></font></td>\n<td><b><font size=\"4\">$key</font></b></td></tr>\n";
        if ($key eq 'source' || $key eq 'gene') {
            print MENUBAR "<a href=\"$key.html\" target=\"display\" class=\"pbold_grey_small\">$key</a><br>\n";
        } else {
            print MENUBAR "<a href=\"$key" . "_s.html\" target=\"keys\" class=\"pbold_grey_small\">$key</a><br>\n";
        }
        next;
    }    #end of if (($key) = ($line =~ /^Feature\sKey\s+(\S+)/))
    if ((defined($keyFileHandle))
	&& (fileno $keyFileHandle)) {
	
	# parse the definition lines
	if (($def) = ($line =~ /$featHeaderRegex{'definition'}/)) {
	    $debugging && print "definition------- $line\n"; ##########
	  DEF: while (defined($line = <IN>)){
	      $debugging && print " more definition------- $line\n"; ##########
	      $line =~ s/</&lt\;/g;
	      $line =~ s/>/&gt\;/g;
	      last DEF if ($line =~ /^\s*$/);
		if ($line =~ /$allFeatHeaderRegex/) {
		    print "line $. in $key part of feature section should have a blank line before it\n";
		    last DEF;
		}
		if ($line =~ /^[^ ]/) {
		    print "line $. in $key part of feature section is either a bad header or is missing the leading spaces:\n the current section will absorb it:\n $line";
		}
		$def .= $line;
	    }
	    print $keyFileHandle "<tr>\n<td bgcolor=\"#669999\" valign=\"top\" align=\"right\" width=\"175\"><font color=\"#ffffff\">"
		. "<b>Definition</b></font><img src=\"http://www.ebi.ac.uk/services/images/trans.gif\" width=\"175\" height=\"1\"></td>\n<td valign=\"top\" width=\"100\%\">$def</td>\n</tr>\n";
	} ## end if (($def) = ($line =~...
	
	#parse the mandatory qualifier lines
	if (($def) = ($line =~ /$featHeaderRegex{'qualifiersMandatory'}/)) {
	    $debugging && print "qualifiersMandatory------- $line\n"; ##########
	    MAN: while (defined($line = <IN>)) {
		$debugging && print " more qualifiersMandatory------- $line\n"; ##########
		$line =~ s/</&lt\;/g;
		$line =~ s/>/&gt\;/g;
		last MAN if ($line =~ /^\s*$/);
		if ($line =~ /$allFeatHeaderRegex/) {
		    print "line $. in $key part of feature section should have a blank line before it\n";
		    last MAN;
		}
		if ($line =~ /^[^ ]/) {
		    print "line $. in $key part of feature section is either a bad header or is missing the leading spaces:\n the current section will absorb it:\n $line";
		}
		($line) = ($line =~ /^\s+(\S+.*)/);
		$def .= "<br>\n" . $line;
	    }
	    $def =~ s/\/(\w+)/\/<a href="qualifiers\/$1.html" target="qualifiers">$1<\/a>/g;
	    print $keyFileHandle "<tr>\n<td bgcolor=\"#669999\" valign=\"top\" align=\"right\" width=\"175\">"
		. "<font color=\"#ffffff\"><b>Mandatory Qualifiers</b></font></td>\n<td valign=\"top\">$def</td>\n</tr>\n";
	} ## end if (($def) = ($line =~...
	
#	print "looking for \'".$featHeaderRegex{'qualifiersOptional'}."\'\n in $.\n$line";
	#parse the optional qualifier lines
	if (($def) = ($line =~ /$featHeaderRegex{'qualifiersOptional'}/)) { # SHOULD be a lowercase q
	    $debugging && print "qualifiersOptional------- $line\n"; ##########
	    OPT: while (defined($line = <IN>)) {
		$debugging && print " more qualifiersOptional------- $line\n"; ##########
		$line =~ s/</&lt\;/g;
		$line =~ s/>/&gt\;/g;
		last OPT if ($line =~ /^\s*$/);
		if ($line =~ /$allFeatHeaderRegex/) {
		    print "line $. in $key part of feature section should have a blank line before it\n";
		    last OPT;
		}
		if ($line =~ /^[^ ]/) {
		    print "line $. in $key part of feature section is either a bad header or is missing the leading spaces:\n the current section will absorb it:\n $line";
		}
		($line) = ($line =~ /^\s+([\S ]+)$/);
		$def .= "<br>\n" . $line;
	    }
	    
	    $def =~ s/^\/(\w+)/\/<a href="qualifiers\/$1.html" target="qualifiers">$1<\/a>/gm;
	    
	    print $keyFileHandle "<tr>\n<td bgcolor=\"#669999\" valign=\"top\" align=\"right\" width=\"175\">"
		. "<font color=\"#ffffff\"><b>Optional Qualifiers</b></font></td>\n<td valign=\"top\"><multicol cols=2>$def</multicol></td>\n</tr>\n";
	} ## end if (($def) = ($line =~...

	#parse the parent key lines
	if (($def) = ($line =~ /$featHeaderRegex{'parent'}/)) {
	    $debugging && print "parent key------- $line\n"; ##########
	    print $keyFileHandle "<tr>\n<td bgcolor=\"#669999\" valign=\"top\" align=\"right\" width=\"175\"><font color=\"#ffffff\">"
		. "<b>Parent Key</b></font></td>\n<td valign=\"top\">$def</td>\n</tr>\n";
        next;
	}
	
	#parse the Organism scope lines
	if (($def) = ($line =~ /$featHeaderRegex{'scopeOrganism'}/)) {
	    $debugging && print "scopeOrganism------- $line\n"; ##########
	    print $keyFileHandle "<tr>\n<td bgcolor=\"#669999\" valign=\"top\" align=\"right\" width=\"175\"><font color=\"#ffffff\">"
		. "<b>Organism Scope</b></font></td>\n<td valign=\"top\">$def</td>\n</tr>\n";
        next;
	}

	#parse the molecule scope lines
	if (($def) = ($line =~ /$featHeaderRegex{'scopeMolecule'}/)) {
	    $debugging && print "scopeMolecule------- $line\n"; ##########
	    print $keyFileHandle "<tr>\n<td bgcolor=\"#669999\" valign=\"top\" align=\"right\" width=\"175\"><font color=\"#ffffff\">"
		. "<b>Molecule Scope</b></font></td>\n<td valign=\"top\">$def</td>\n</tr>\n";
        next;
	}
	#parse the Reference lines
	if (($def) = ($line =~ /$featHeaderRegex{'references'}/)) {
	    $debugging && print "references------- $line\n"; ##########
	    REF: while (defined($line = <IN>)) {
		$debugging && print " more references------- $line\n"; ##########
		$line =~ s/</&lt\;/g;
		$line =~ s/>/&gt\;/g;
		$line =~ s/(\[\d+\])/<br>$1/g;
		last REF if ($line =~ /^\s*$/);
		if ($line =~ /$allFeatHeaderRegex/) {
		    print "line $. in $key part of feature section should have a blank line before it\n";
		    last REF;
		}
		if ($line =~ /^[^ ]/) {
		    print "There seems to be a missing blank line on $.\n $line\n";
		}
		($line) = ($line =~ /^\s+(\S.+\S)/);
		$def .= "\n" . $line;
	    } ## end while (defined($line = <IN>...
	    print $keyFileHandle "<tr>\n<td bgcolor=\"#669999\" align=\"right\" width=\"175\" valign=\"top\">"
		. "<font color=\"#ffffff\"><b>References</b></font></td>\n<td valign=\"top\">$def</td>\n</tr>\n";
	} ## end if (($def) = ($line =~...

	$debugging && print "looking for \'".$featHeaderRegex{'example'}."\'\n in $.\n$line"; ######

	# parse the Example lines
	if (($def) = ($line =~ /$featHeaderRegex{'example'}/)) {
	    $def .= "<br>\n";
	    $debugging && print "example-------\n"; ##########
	    EGS: while (defined($line = <IN>)) {
		$debugging && print $line; ##########
		$debugging && print " more example-------\n"; ##########
		$line =~ s/</&lt\;/g;
		$line =~ s/>/&gt\;/g;
		last EGS if ($line =~ /^\s*$/);
		if ($line =~ /$allFeatHeaderRegex/) {
		    print "line $. in $key part of feature section should have a blank line before it\n";
		    last EGS;
		}
		if ($line =~ /^[^ ]/) {
		    print "There seems to be a missing blank line on $.\n $line\n";
		}
		($line) = ($line =~ /^\s+(\S.+\S)/);
		$def .= $line . "<br>\n";
	    } ## end while (defined($line = <IN>...
	    print $keyFileHandle "<tr>\n<td bgcolor=\"#669999\" align=\"right\" width=\"175\" valign=\"top\">"
		. "<font color=\"#ffffff\"><b>Examples</b></font></td>\n<td valign=\"top\">$def</td>\n</tr>\n";
	} ## end if (($def) = ($line =~...
	#parse the comment lines
	$debugging && print "looking for \'".$featHeaderRegex{'comment'}."\'\n in $.\n$line"; ######

	if (($def) = ($line =~ /$featHeaderRegex{'comment'}/)) {
	    $debugging && print "comment-------\n"; ##########
	    COM: while (defined($line = <IN>)) {
		$debugging && print $line; ##########
		$debugging && print " more comment-------\n"; ##########
		$line =~ s/</&lt\;/g;
		$line =~ s/>/&gt\;/g;
		last COM if ($line =~ /^\s*$/);
		if ($line =~ /$allFeatHeaderRegex/) {
		    print "line $. in $key part of feature section should have a blank line before it\n";
		    last COM;
		}
		if ($line =~ /^[^ ]/) {
		    print "There seems to be a missing blank line on $.\n $line\n";
		}
		$def .= "<br>" . $line;
	    }
	    print $keyFileHandle "<tr>\n<td bgcolor=\"#669999\" valign=\"top\" align=\"right\" width=\"175\">"
		. "<font color=\"#ffffff\"><b>Comments</b></font></td>\n<td valign=\"top\">$def</td>\n</tr>\n";
	    next;
	} ## end if (($def) = ($line =~...
	if ($line =~ /^\s*$/) {
	    next;
	}

	if($tryOnceMore == 0) {
	    print "line $. in $key part of feature section may be out of order:\n $line";
	    $tryOnceMore = 1;
	}
	else {
	    print "!!!!! eventually discarded line $.\n";
	    $tryOnceMore = 0;
	}
    } ## end while (defined(my $line =...
}
if ((defined($keyFileHandle))
    && (fileno $keyFileHandle)) {
    print $keyFileHandle $keyFooter;
    close($keyFileHandle);
}

$key = "";
$tryOnceMore = 0;

$debugging && print "Qualifier section\n"; #############
my $qualFileHandle;
###Qualifiers
print MENUBAR "</td></tr>"
    . "\n<tr>\n<td bgcolor=\"#336666\" valign=\"top\"><font color=\"#ffffff\">"
    . "<b>Q<br>U<br>A<br>L<br>I<br>F<br>I<br>E<br>R<br>S</b></font></td>\n<td>\n";
while (($tryOnceMore 
       || (defined($line = (<IN>))))
       && ($line !~ /$appendixRegex{'qualifierEnd'}/)){
    $line =~ s/</&lt\;/g;
    $line =~ s/>/&gt\;/g;
    
    # parse the qualifier lines
    if ($line =~ /$qualHeaderRegex{'qualifier'}/) {
	$key = $1;
	if ((defined($qualFileHandle))
	    && (fileno $qualFileHandle)) {
	    print $qualFileHandle $qualifierFooter;
	    close($qualFileHandle);
	}
	print "qual: $key\n";
	
	# create a new qualifier files
	open($qualFileHandle, "> $qualifiersDir/$key.html") or die "ERROR ! Can't open file <$qualifiersDir/$key.html> : $!\n";
	
	print $qualFileHandle $header
	    . "<div align=\"center\">\n<table border=\"0\" cellspacing=\"3\" cellpadding=\"3\" height=\"100\%\" width=\"100%\" bgcolor=\"#eeeeee\">"
	    . "\n<tr>\n<td bgcolor=\"#336666\"  valign=\"top\"  align=\"right\" width=\"175\"><font color=\"#ffffff\">"
	    . "<b>Qualifier</b></font><br><img src=\"http://www.ebi.ac.uk/services/images/trans.gif\" width=\"175\" height=\"1\"></td>\n<td  valign=\"top\" width=\"100\%\"><b>$key</b></td>\n</tr>\n";
	print MENUBAR "<a href=\"qualifiers/$key.html\" target=\"qualifiers\" class=\"pbold_grey_small\">$key</a><br>\n";
	$tryOnceMore = 0;
	next;
    } ## end if (($key) = ($line =~...
    if ((defined($qualFileHandle))
	&& (fileno $qualFileHandle)) {
	# parse the definition lines of the qualifier
	if (($def) = ($line =~ /$qualHeaderRegex{'definition'}/)) {
	    while (defined($line = <IN>)
		   && ($line !~ /$appendixRegex{'qualifierEnd'}/)) {
		$line =~ s/</&lt\;/g;
		$line =~ s/>/&gt\;/g;
		if ($line !~ /^\s{2,}/) {
		    if (($line =~ /\S/) && ($line !~ /$allQualHeaderRegex/)) {
			print "line $. in $key part of qualifier section is either a bad header or is missing the leading spaces:\n the current section will absorb it:\n $line";
		    }
		    else{
			last;
		    }
		}
		$def .= $line;
	    }
	    print $qualFileHandle "<tr>\n<td bgcolor=\"#336666\" valign=\"top\" align=\"right\" width=\"175\"><font color=\"#ffffff\">"
		. "<b>Definition</b></font></td>\n<td valign=\"top\"><font face=\"Arial,Helvetica\">$def</font></td></tr>\n";
	} ## end if (($def) = ($line =~...
	
	# parse the Value format lines of the qualifier
	if (($def) = ($line =~ /$qualHeaderRegex{'valueFormat'}/)) {
	    while ((defined($line = <IN>))
		   && ($line !~ /$appendixRegex{'qualifierEnd'}/)) {
		if ($line !~ /^\s{2,}/) {
		    if (($line =~ /\S/) && ($line !~ /$allQualHeaderRegex/)) {
			print "line $. in $key part of qualifier section is either a bad header or is missing the leading spaces:\n the current section will absorb it:\n $line";
		    }
		    else{
			last;
		    }
		}
		$line =~ s/^\s+//;      # Remove leading spaces
		$line =~ s/</&lt\;/g;
		$line =~ s/>/&gt\;/g;
		$def .= $line;
	    } ## end while (defined($line = <IN>...
	    print $qualFileHandle qq|<tr>\n<td bgcolor="#336666" align="right" valign="top"  width="175"><font color="#ffffff">|
		. qq|<b>Value Format</b></font></td>\n<td valign="top"><tt><pre>$def</pre></tt></td>\n</tr>\n|;
	} ## end if (($def) = ($line =~...
	
	# parse the Example lines
	if (($def) = ($line =~ /$qualHeaderRegex{'examples'}/)) {
	    $def .= "<br>\n";
	    while ((defined($line = <IN>))
		   && ($line !~ /$appendixRegex{'qualifierEnd'}/)) {
		$line =~ s/</&lt\;/g;
		$line =~ s/>/&gt\;/g;
		if ($line !~ /^\s{2,}/) {
		    if (($line =~ /\S/) && ($line !~ /$allQualHeaderRegex/)) {
			print "line $. in $key part of qualifier section is either a bad header or is missing the leading spaces:\n the current section will absorb it:\n $line";
		    }
		    else{
			last;
		    }
		}
		$def .= $line . "<br>\n";
	    }
	    print $qualFileHandle qq|<tr>\n<td bgcolor="#336666" align="right" width="175"  valign="top"><font color="#ffffff">|
		. qq|<b>Example</b></font></td>\n<td valign="top"><tt><font face="Arial,Helvetica">$def</font></tt>|;
	} ## end if (($def) = ($line =~...
	
	# parse the comment lines
	if (($def) = ($line =~ /$qualHeaderRegex{'comments'}/)) {
	    while ((defined($line = <IN>)
		   && ($line !~ /$appendixRegex{'qualifierEnd'}/))) {
		$line =~ s/</&lt\;/g;
		$line =~ s/>/&gt\;/g;
		if ($line !~ /\S/) {
		    next;
		}
		if ($line !~ /^\s{2,}/) {
		    if ($line !~ /$allQualHeaderRegex/) {
			print "line $. in $key part of qualifier section is either a bad header or is missing the leading spaces:\n the current section will absorb it:\n $line";
		    }
		    else{
			last;
		    }
		}
		if ($line) {
		    $def .= $line;
		}
	    }
	    print $qualFileHandle qq|<tr>\n<td bgcolor="#336666"  valign="top"  align="right" width="175"><font color=:"#ffffff">|
		. qq|<b>Comment</b></font></td>\n<td  valign="top" ><font face="Arial,Helvetica">$def</font>|;
	}
	if ($line !~/^\s*$/) {
	    if ($line =~ /$appendixRegex{'qualifierEnd'}/) {
		last;
	    }
	    if($tryOnceMore == 0) {
		unless ($line =~ /$qualHeaderRegex{'qualifier'}/) { 
		    print "line $. in $key part of qualifier section may be out of order or missing leading space:\n $line";
		}
		if ($line =~ /$allQualHeaderRegex/) {
		    $tryOnceMore = 1;
		}
		else {
		    print "!!!!! DISCARDING line:\n $line";
		}
	    }
	    else {
		print "!!!!! eventually discarded line $.\n";
		$tryOnceMore = 0;
	    }
	}
    } ## end if (($def) = ($line =~...
} ## end while (defined(my $line =...

#print "finished with line $.\n$line\n\n";
if ((defined($qualFileHandle))
    && (fileno $qualFileHandle)) {
    print $qualFileHandle $qualifierFooter;
    close($qualFileHandle);
}
close(IN);

print MENUBAR "</td>\n</tr>\n</table>\n</div>\n" . $footer;
close(MENUBAR);

print "\n=======================Finished FEATURE TO HTML v4======================\n";
print "Wrote to $dir\n"
    . "email es-request to ask them to update http://www.ebi.ac.uk/ena/WebFeat/ with this data\n";
    
    
sub writeIndex {
    my $directory = shift;
    open(INDEX, ">$directory/index.html") or die "ERROR ! Can't create a new file, <$directory/index.html> : $!\n";
    my $database;
    if ($dir =~ /\/align\//) {
	$database = "EMBL-ALIGN";
    } else {
	$database = "EMBL";
    }
    print INDEX <<EOF;
<html>
<head>
<title>EMBL Features & Qualifiers</title>
<meta content="text/html; charset=iso-8859-1" http-equiv="Content-Type">
<meta content="MSHTML 5.00.2920.0" name="GENERATOR">

</head>
<frameset   cols="200, *"   frameSpacing="0"  FRAMEBORDER="yes" scrolling="no" >
     <frame scrolling="yes" marginHeight="0" marginWidth="0" name="list"  src="alpha_key.html"  vscroll="yes" hscroll="auto">
     <frame scrolling="no" marginHeight="0" marginWidth="0" name = "display"  src="CDS.html"   vscroll="yes" hscroll="auto">
   </frameset>
</html>
EOF
;
    close(INDEX);
}

sub writeTop {
    my $directory = shift;
    open(TOP, ">$directory/top.html") or die "ERROR ! Can't create a new file, <$directory/top.html> : $!\n";
    if ($dir =~ /\/align\//) {
	print TOP <<EOF;
<html>
<head>
<title>EMBL-Align: Features & Qualifiers</title>
<META HTTP-EQUIV="Created" CONTENT="12/07/01">
<META HTTP-EQUIV="Owner" CONTENT= "EMBL Outstation - Hinxton, European Bioinformatics Institute">
<META NAME="Author" CONTENT="EBI External Servces">
<META NAME="Description" CONTENT="EMBL Features & Qualifiers">
<META NAME="Generator" CONTENT="Dreamweaver UltraDev 4">
<link rel="stylesheet" href="http://www.ebi.ac.uk/services/include/stylesheet.css" type="text/css">
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
<script language="javascript"  src="http://www.ebi.ac.uk/include/master.js"></script>
</head>

<body  marginwidth="0" marginheight="0" leftmargin="0" topmargin="0" rightmargin="0" bottommargin="0" onLoad="MM_preloadImages('http://www.ebi.ac.uk/services/images/home_o.gif','http://www.ebi.ac.uk/services/images/about_o.gif','http://www.ebi.ac.uk/services/images/databases_o.gif','http://www.ebi.ac.uk/services/images/utilities_o.gif','http://www.ebi.ac.uk/services/images/submissions_o.gif','http://www.ebi.ac.uk/services/images/research_o.gif','http://www.ebi.ac.uk/services/images/downloads_o.gif','http://www.ebi.ac.uk/services/images/services_o.gif')">
<table width="100%" border="0" cellspacing="0" cellpadding="0"  class="tabletop">

  <tr> 
    <td width="270" height="85" align="right"><img src="http://www.ebi.ac.uk/services/images/ebi_banner_1.jpg" width="270"  height="85"></td>
    <td valign="top" align="right" width="100%">
      <table border="0" cellspacing="0" cellpadding="0" class="tabletop" width="100%" height="85">
              <tr> 
                <td valign="top" align="right" colspan="2"> 
                  <table border="0" cellspacing="0" cellpadding="0" height="28" class="tablehead">
                    <tr> 
			
                      <td   class="tablehead"  align="left" valign="bottom"><img src="http://www.ebi.ac.uk/services/images/top_corner.gif" width="28"  height="28"></td>
                      <form name="Text1293FORM" action="javascript:querySRS(document.forms[0].db[document.forms[0].db.selectedIndex].value, document.forms[0].qstr.value)" method="post">
                        <td align="center" valign="middle"   class="small" nowrap><span class="smallwhite"><nobr>Get&nbsp;</nobr></span></td>

                        <td align="center" valign="middle"   class="small"><span class="small">
                          <select  id="FormsComboBox2" name="db" class="small">
                            <option value="EMBL" selected >Nucleotide sequences</option>
                            <option value="SWALL">Protein sequences</option>
                            <option value="PDB">Protein structures</option>
							<option value="INTERPRO">Protein signatures</option>
                            <option value="MEDLINE">Literature</option>

                          </select>
                  </span></td>
                        <td align="center" valign="middle"   class="small" nowrap><span class="smallwhite">&nbsp;for&nbsp;</span></td>
                        <td align="center" valign="middle"   class="small">
				  <span class="small">
                          <input id="FormsEditField3" maxlength="50" size="7" name="qstr"  class="small">
                          </span></td>
                        <td align="center" valign="middle"   class="small">&nbsp;</td>

                        <td align="center" valign="middle"   class="small">
				  <span class="small">
                          <input id="FormsButton3" type="submit" value="Go" name="FormsButton1" class="small">
                          </span></td>
                        <td align="center" valign="middle"   class="small" width="10" nowrap><a href="#" class="small" onClick="openWindow('http://www.ebi.ac.uk/help/DBhelp/dbhelp_frame.html')"> 
                          <nobr>&nbsp;?&nbsp</nobr></a></td>
                      </form>
                      <form name="Text1295FORM" action="http://search.ebi.ac.uk/compass" method="get" onSubmit ="if (document.Text1295FORM.scope.value=='') { alert('Please enter query.'); return false;}">
                        <input type="hidden" value="sr" name="ui">

                        <td align="center" valign="middle"   class="smallwhite" nowrap><span class="smallwhite"><nobr>&nbsp;Site search&nbsp;</nobr></span></td>
                        <td align="center" valign="middle"   class="small">
				  <span class="small">
                          <input id="FormsEditField4" maxlength="50" size="7" name="scope" class="small">
                          </span></td>
                        <td align="center" valign="middle"   class="small">&nbsp;</td>
                        <td align="center" valign="middle"   class="small">
				  <span class="small">

                          <input id="FormsButton2" type="submit" value="Go" name="FormsButton2" class="small">
                          </span></td>
                        <td align="center" valign="middle"   class="small" nowrap><nobr> 
                          <a href="#" class="small" onClick="openWindow('http://www.ebi.ac.uk/help/help/sitehelp_frame.html')"> 
                          &nbsp;?&nbsp;</a></nobr></td>
                      </form>
                    </tr>
                  </table>
                </td>

              </tr>
              <tr> 
                <td align="left" valign="bottom"><img src="http://www.ebi.ac.uk/services/images/ebi_banner_2.jpg" width="169" height="29"></td>
                
          <td align="right" valign="top"><img src="http://www.ebi.ac.uk/Groups/images/topbar3.gif" width="156"  height="25" usemap="#Map" border="0"></td>
              </tr>
            </table>
    </td>
  </tr>
  <tr>

    <td colspan="2"><img src="http://www.ebi.ac.uk/services/images/trans.gif" width="1"  height="5"></td>
  </tr>
</table>
<table width="100%" border="0" cellspacing="0" cellpadding="0"  class="tabletop" >
<tr>
    <td width="100%"> 
      <table width="679" border="0" cellspacing="0" cellpadding="0">
        <tr> 
          <td width="97" height="18"><a target="_top" href="http://www.ebi.ac.uk/index.html" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image8','','http://www.ebi.ac.uk/services/images/home_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/home.gif" width="97" name="Image8" border="0"  height="18"></a></td>
          <td width="97" height="18"><a  target="_top" href="http://www.ebi.ac.uk/Information" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image9','','http://www.ebi.ac.uk/services/images/about_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/about.gif" width="97" name="Image9" border="0"  height="18"></a></td>
          <td width="97" height="18"><a  target="_top" href="http://www.ebi.ac.uk/Groups" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image10','','http://www.ebi.ac.uk/services/images/research_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/research.gif" width="97" name="Image10" border="0"  height="18"></a></td>

          <td width="97" height="18"><a  target="_top" href="http://www.ebi.ac.uk/services" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image11','','http://www.ebi.ac.uk/services/images/services_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/services.gif" width="97" name="Image11" border="0"  height="18"></a></td>
          <td width="97" height="18"><a  target="_top" href="http://www.ebi.ac.uk/Tools" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image12','','http://www.ebi.ac.uk/services/images/utilities_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/utilities.gif" width="97" name="Image12" border="0"  height="18"></a></td>
          <td width="97" height="18"><a  target="_top" href="http://www.ebi.ac.uk/Databases" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image13','','http://www.ebi.ac.uk/services/images/databases_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/databases_o.gif" width="97" name="Image13" border="0"  height="18"></a></td>
          <td width="97" height="18"><a  target="_top" href="http://www.ebi.ac.uk/FTP" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image14','','http://www.ebi.ac.uk/services/images/downloads_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/downloads.gif" width="97" name="Image14" border="0"  height="18"></a></td>
          <td width="97" height="18"><a  target="_top" href="http://www.ebi.ac.uk/Submissions" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image15','','http://www.ebi.ac.uk/services/images/submissions_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/submissions.gif" width="97" name="Image15" border="0"  height="18"></a></td>
        </tr>
      </table>
      </td>
  </tr>

      <tr>
          <td width="100%" height="5"  class="tablehead" >
		    <table width="100%" height="5"  border="0" cellspacing="0" cellpadding="0">
              <tr> 
                
          <td width="100%" height="20" align="center"> 

            <nobr>
			<a target="_top" href="http://www.ebi.ac.uk/embl/" class="white">EMBL-NUCLEOTIDE SEQUENCE DATABASE:</a><span class="white"></span><span class="white"> | </span>
			<a target="_top" href="http://www.ebi.ac.uk/embl/WebFeat/align/" class="white">ALIGNMENT FEATURES AND QUALIFIERS</a><span class="white"> | </span>

			<a target="_top" href="http://www.ebi.ac.uk/webin-align/annotation/" class="white">ANNOTATION EXAMPLES</a><span class="white"> | </span>
            <a target="_top" href="http://www.ebi.ac.uk/embl/Documentation/FT_definitions/feature_table.html" class="white">FEATURE TABLE</a>
			</nobr></tr>
            </table>
		  </td>
     </tr>
	 <tr>

	   <td  class="tableborder"><img src="http://www.ebi.ac.uk/services/images/trans.gif" width="1" height= "3" ></td>
	 </tr>
	<tr>
    <td  class="tablebody"  height="6"><img src="http://www.ebi.ac.uk/services//images/trans.gif" width="1"  height="6"></td>
	</tr>
	 </table>
<map name="Map"> 
  <area shape="rect" coords="70,1,156,25" href="http://srs.ebi.ac.uk/" target="_top" alt="Start SRS Session" title="Start SRS Session"> 
  <area shape="rect" coords="1,1,69,25" href="http://www.ebi.ac.uk/Information/sitemap.html" target="_top" alt="EBI Site Map" title="EBI Site Map">
</map>
</body>

</html>
EOF


    } else {
	print TOP <<EOF;
<html lang="en"><!-- InstanceBegin template="/Templates/top_databases.dwt" codeOutsideHTMLIsLocked="false" -->
	<head> 
		<meta http-equiv="content-type" content="text/html; charset=iso-8859-1" />
		<!-- InstanceBeginEditable name="head" -->



<!-- InstanceEndEditable -->
		<!-- InstanceBeginEditable name="doctitle" --> 
<title>The EMBL Nucleotide Sequence Database</title>
<meta http-equiv="owner" content= "EMBL Outstation - Hinxton, European Bioinformatics Institute" />
<meta name="keywords" content="EBI, EMBL, bioinformatics, molecular, genetics, software, databases, genomics, sequencing, protein, computational biology, nucleotide, FASTA, BLAST, SRS,ClustalW, DNA, RNA, BioInformer, science, leading edge">
<meta name="author" content="EBI Web Team">

<!-- InstanceEndEditable -->
		<link rel="shortcut icon" href="/bookmark.ico" />
		<meta http-equiv="Owner" content="EMBL Outstation - Hinxton, European Bioinformatics Institute" />
		<meta name="author" content="EBI External Services" />
		<link rel="stylesheet" href="http://www.ebi.ac.uk/services/include/stylesheet.css" type="text/css" />
		<script language="javascript" src="http://www.ebi.ac.uk/include/master.js" type="text/javascript"></script>
		<script language="javascript" type="text/javascript">
			<!--
			var emailaddress="support";
			// -->
		</script>
	</head>

	<body  marginwidth="0" marginheight="0" leftmargin="0" topmargin="0" rightmargin="0" bottommargin="0" onload="EbiPreloadImages('services');">
		<table width="100%" border="0" cellspacing="0" cellpadding="0">	
			<tr>
				<td><table width="100%" border="0" cellspacing="0" cellpadding="0"  class="tabletop">
					<tr>
						<td width="270" height="65" align="right"><a target="_top" href="/"><img src="http://www.ebi.ac.uk/services/images/ebi_banner_1b.jpg" width="270"  alt="EBI Home Page"  height="65" border="0" /></a></td>
							<td valign="top" align="right" width="100%"><table border="0" cellspacing="0" cellpadding="0" class="tabletop" width="100%" height="65">
								  <tr> 
									<td valign="top" align="right" colspan="2"><table border="0" cellspacing="0" cellpadding="0" height="28" class="tablehead">
										<tr> 
										  <td class="tablehead"  align="left" valign="bottom"><img src="http://www.ebi.ac.uk/services/images/top_corner.gif" width="28" alt="Image"  height="28" /></td>

											<form name="Text1293FORM" action="javascript:querySRS(document.forms[0].db[document.forms[0].db.selectedIndex].value, document.forms[0].qstr.value)" method="post">
											<td align="center" valign="middle"   class="small"><span class="smallwhite"><nobr>Get&nbsp;</nobr></span></td>
											<td align="center" valign="middle"   class="small"><span class="small"><select  id="FormsComboBox2" name="db" class="small">                            
												<option value="EMBL" selected >Nucleotide sequences</option>
												<option value="SQUID">Protein sequences</option>
												<option value="PDB">Protein structures</option>
												<option value="INTERPRO">Protein signatures</option>

												<option value="MEDLINE">Literature</option>
												<option value="UNIPROT">Protein seq's [SRS]</option>
											</select></span></td>
											<td align="center" valign="middle" class="small"><span class="smallwhite">&nbsp;for&nbsp;</span></td>
											<td align="center" valign="middle" class="small"><span class="small"><input id="FormsEditField3" maxlength="50" size="7" name="qstr"  class="small" /></span></td>
											<td align="center" valign="middle" class="small">&nbsp;</td>
											<td align="center" valign="middle" class="small"><span class="small"><input id="FormsButton3" type="submit" value="Go" name="FormsButton1" class="small" /></span></td>

											<td align="center" valign="middle" class="small" width="10"><a target="_top" href="#" class="small2" onclick="openWindow('http://www.ebi.ac.uk/help/DBhelp/dbhelp_frame.html'); return false;"><nobr>&nbsp;?&nbsp;</nobr></a></td>
											</form>                      
											<form name="google" action="http://www.google.com/u/ebi" method="get" onsubmit ="if (document.google.q.value=='') { alert('Please enter query.'); return false;}">
											<input type="hidden" name="hq" value="inurl:www.ebi.ac.uk" />
											<td align="center" valign="middle"   class="smallwhite" nowrap><span class="smallwhite"><nobr>&nbsp;Site search&nbsp;</nobr></span></td>
											<td align="center" valign="middle"   class="small"><span class="small"><input id="FormsEditField4" type="text" maxlength="50" size="7" name="q" class="small" /></span></td>
											<td align="center" valign="middle"   class="small">&nbsp;</td>
											<td align="center" valign="middle"   class="small"><span class="small"><input id="FormsButton2" type="submit" value="Go" name="sa" class="small" /></span></td>

											<td align="center" valign="middle"   class="small" nowrap><nobr><a target="_top" href="#" class="small2" onclick="openWindow('http://www.ebi.ac.uk/help/help/sitehelp_frame.html'); return false;">&nbsp;?&nbsp;</a></nobr></td>
											</form>
										</tr>
									  </table></td>
								  </tr>
								  <tr> 
									<td align="left" valign="bottom"><a target="_top" href="/"><img src="http://www.ebi.ac.uk/services/images/ebi_banner_2b.jpg" border="0" alt="EBI Home Page" width="66" height="29" /></a></td>
									<td align="right" valign="middle"><img src="http://www.ebi.ac.uk/services/images/thetopbar_b.gif" width="156" alt="Image"  height="25" usemap="#Map" border="0" /></td>
								  </tr>

								</table></td>
					</tr>
					<tr>
						<td colspan="2"><img src="http://www.ebi.ac.uk/services/images/trans.gif" width="1" alt="Image"  height="5" /></td>
					</tr>
				</table><table width="100%" border="0" cellspacing="0" cellpadding="0"  class="tabletop">
					<tr>
						<td width="100%"><table width="679" border="0" cellspacing="0" cellpadding="0">
								   <tr>

										<td width="97" height="18"><a target="_top" href="http://www.ebi.ac.uk/" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image8','','http://www.ebi.ac.uk/services/images/home_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/home.gif" width="97" name="Image8" border="0"  height="18" /></a></td>
										<td width="97" height="18"><a target="_top" href="http://www.ebi.ac.uk/Information/" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image9','','http://www.ebi.ac.uk/services/images/about_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/about.gif" width="97" name="Image9" border="0"  height="18" /></a></td>
										<td width="97" height="18"><a target="_top" href="http://www.ebi.ac.uk/Groups/" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image10','','http://www.ebi.ac.uk/services/images/research_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/research.gif" width="97" name="Image10" border="0"  height="18" /></a></td>
										<td width="97" height="18"><a target="_top" href="http://www.ebi.ac.uk/services/" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image11','','http://www.ebi.ac.uk/services/images/services_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/services.gif" width="97" name="Image11" border="0"  height="18" /></a></td>
										<td width="97" height="18"><a target="_top" href="http://www.ebi.ac.uk/Tools/" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image12','','http://www.ebi.ac.uk/services/images/utilities_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/utilities.gif" width="97" name="Image12" border="0"  height="18" /></a></td>
										<td width="97" height="18"><a target="_top" href="http://www.ebi.ac.uk/Databases/" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image13','','http://www.ebi.ac.uk/services/images/databases_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/databases_o.gif" width="97" name="Image13" border="0"  height="18" /></a></td>
										<td width="97" height="18"><a target="_top" href="http://www.ebi.ac.uk/FTP/" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image14','','http://www.ebi.ac.uk/services/images/downloads_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/downloads.gif" width="97" name="Image14" border="0"  height="18" /></a></td>
										<td width="97" height="18"><a target="_top" href="http://www.ebi.ac.uk/Submissions/" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('Image15','','http://www.ebi.ac.uk/services/images/submissions_o.gif',1)"><img src="http://www.ebi.ac.uk/services/images/submissions.gif" width="97" name="Image15" border="0"  height="18" /></a></td>
								  </tr>

							</table></td>
			  	    </tr>
					  <tr>
						  <td width="100%" height="5"  class="tablehead" ><table width="100%" height="5"  border="0" cellspacing="0" cellpadding="0">
							  <tr> 
								<td width="100%" height="20" align="center"><!-- InstanceBeginEditable name="topnav" --> <nobr>
			<a target="_top" href="http://www.ebi.ac.uk/embl/" class="white">EMBL-NUCLEOTIDE SEQUENCE DATABASE: </a><span class="white"> | </span>

			<a target="_top" href="http://www.ebi.ac.uk/embl/WebFeat/" class="white">FEATURES AND QUALIFIERS</a><span class="white"> </span><span class="white"> | </span>
			<a target="_top" href="http://www.ebi.ac.uk/embl/Standards/web/index.html" class="white">ANNOTATION EXAMPLES</a><span class="white"> | </span>
            <a target="_top" href="http://www.ebi.ac.uk/embl/Documentation/FT_definitions/feature_table.html" class="white">FEATURE TABLE</a>
			</nobr><!-- InstanceEndEditable --></td>
							  </tr>

							</table></td>
					 </tr>
					 <tr>
					   <td class="tableborder"><img src="http://www.ebi.ac.uk/services/images/trans.gif" width="1" alt="Image" height="3"  /></td>
					 </tr><tr>
    <td  class="tablebody"  height="6"><img src="http://www.ebi.ac.uk/services/images/trans.gif" width="1"  height="6" /></td>
	</tr>
				</table>
				</td>

			</tr>
		</table>
		<script language="javascript" type="text/javascript">
			<!--
				loadSelects();
			// -->
		</script>
		<map name="Map"> 
			  <area shape="rect" coords="70,1,156,25" href="http://www.ebi.ac.uk/queries/" target="_top" alt="Which EBI biological databases are available and how do I access them?" title="Which EBI biological databases are available and how do I access them?" /> 
			  <area shape="rect" coords="1,1,69,25" href="http://www.ebi.ac.uk/Information/sitemap.html" target="_top" alt="EBI Site Map" title="EBI Site Map" />
		</map>		
	</body>
<!-- InstanceEnd --></html>
EOF

    }
    close(TOP);
}
