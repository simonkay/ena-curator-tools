#!/ebi/production/seqdb/embl/tools/bin/perl 

print "usage: change_ftloc.pl <inputfile> <value>\n<inputfile> is EMBL flatfile or feature table\n<value> is the number of bases to be added (enter negative value to subtract)\n";

$inputfile = $inputfile_no_ext = $ARGV[0];
$inputfile_no_ext =~ s/\..*//;

$change_value = $ARGV[1];

$newline = "\n";

# Mark feature table lines containing locations (FT > @@)
    &mark_ft_locations;
    open(FT_LOC_FILE, ">${inputfile_no_ext}.ft_temp1");
    print FT_LOC_FILE $ftlines ;
    close(FT_LOC_FILE);
    $ftlines = "";

# Isolate all location values
    open(FT_LOC_FILE, "${inputfile_no_ext}.ft_temp1");
    open(FT_ISOL_FILE, ">${inputfile_no_ext}.ft_temp2");
    &isolate_loc_value;
    close(FT_LOC_FILE);
    close(FT_ISOL_FILE);

# Subtract $subt_value from locations
    open(FT_ISOL_FILE, "${inputfile_no_ext}.ft_temp2");
    open(FT_CH_LOC_FILE, ">${inputfile_no_ext}.ft_temp3");
    &change_locations;
    close(FT_ISOL_FILE);
    close(FT_CH_LOC_FILE);

# Restore feature table
    open(FT_CH_LOC_FILE, "${inputfile_no_ext}.ft_temp3");
    open(FT_DONE, ">${inputfile_no_ext}.ft");
    &restore_ft;
    close(FT_DONE);
    close(FT_CH_LOC_FILE);



# Delete temporary files
unlink <${inputfile_no_ext}.ft*_temp*>;
unlink <${inputfile_no_ext}.ID_FH*>;

# SUBROUTINES

sub mark_ft_locations {
    open(EMBLFLAT,"$inputfile");
    while (<EMBLFLAT>) {
        $ft_line = $_ ;

# Find locations in lines marked @@ and put those on separate lines.
# Add _XX_ to make it easier to remove newlines at later stage.
# Protect features with numbers (e.g. 5'UTR, -10_signal)

	if (/^FT   /) {
	    if (/^FT   [A-Za-z0-9-]/) {
		$ft_line =~ s/FT   5\'/@@   five/ ;
		$ft_line =~ s/FT   3\'/@@   three/ ;
		$ft_line =~ s/FT   -10_/@@   ten/ ;
		$ft_line =~ s/FT   -35_/@@   thirtyfive/ ;
		$ft_line =~ s/FT   /@@   / ;
                chop($ft_line);

	    }
            $ftlines .= $ft_line;
	}
    }
    $ftlines =~ s/(@@   [A-Za-z_-]+ .*)(FT                   \/)/\1${newline}\2/mg ;
    $ftlines =~ s/(@@   [A-Za-z_-]+ .*)FT(                   )/\1${newline}@@\2/mg ;
    $ftlines =~ s/(.)@@/\1${newline}@@/mg ;
}

sub isolate_loc_value {
    while (<FT_LOC_FILE>) {
	$loc_line = $_;
        if (/^@@   /) {
            $loc_line =~ s/([\d]+)([\D]*)/${newline}\1${newline}\2__XX__/g ;
        }
        print FT_ISOL_FILE $loc_line;
    }
}


sub change_locations {
    while (<FT_ISOL_FILE>) {
	$loc_line = $_;
        if (/^[0-9]+$/) {
            $loc_line += $change_value;
#            if ($loc_line < 1 || $loc_line > $fragmentlength) {
#                $loc_line = "_ALERT_" . $loc_line;
#            }
            $loc_line = $loc_line . "__XX__" . $newline;
        }
        print FT_CH_LOC_FILE $loc_line;
    }
}

sub restore_ft {
    while (<FT_CH_LOC_FILE>) {
	$loc_line = $_;
        if (/@@/) {
            $loc_line =~ s/@@   ten/@@   -10_/ ;
            $loc_line =~ s/@@   thirtyfive/@@   -35_/ ;
            $loc_line =~ s/@@   five/@@   5'/ ;
            $loc_line =~ s/@@   three/@@   3'/ ;
	}
        if (/^@@   /) {
	    chop($loc_line);
        }
        if (/__XX__$/) {
            $loc_line =~ s/__XX__// ;
	    chop($loc_line);
        }
        if (/^__XX__FT/) {
            $loc_line =~ s/__XX__// ;
	}
        if (/^__XX__@@/) {
            $loc_line =~ s/__XX__@@/FT/ ;
	    chop($loc_line);
        }
        if (/^@@/) {
            $loc_line =~ s/@@/FT/ ;
	}
        print FT_DONE $loc_line;
    }
}

sub number_ft {
    $featnum = 100001;
    while (<FT_DONE>) {
	$feat_line = $_;
        if (/^FT   [A-Za-z0-9_-]+/) {
	    $feat_line =~ s/^FT/${featnum}FT/;
            $featnum ++;
        } 
        print FT_FEATNUM $feat_line;
    }
}






