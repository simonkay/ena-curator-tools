#!/ebi/production/seqdb/embl/tools/bin/perl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/map_ffl_to_sub.pl,v 1.5 2008/04/17 08:27:09 faruque Exp $
#
#  (C) EBI 2007
#
#  Written by Gemma Hoad
#  
###############################################################################

use strict;
use SeqDBUtils2;

#-------------------------------------------------------------------------------
# Usage   : usage(@ARGV)
# Description: populates global variables with commandline arguments (plus prints
# help text)
# Return_type : database and file to map
# Args    : @$args : list of arguments from the commandline.
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub usage(@) {

    my ( $arg, $usage, @inputFiles, $file );

    my $args = shift;

    $usage= "\nPURPOSE: To tell you which .sub file generates which .ffl file\n"
	. "(or vice-versa), depending on the input.\n\n"
	. "USAGE:\n"
        . "sub_ac_map <filename>+    # using one or more filenames\n"
        . "sub_ac_map <acc1>-<acc2>  # using an accession range\n"
        . "sub_ac_map                # using no filenames, so ALL .ffl and .sub files are mapped\n"
        . "sub_ac_map -h             # this help message\n\n"
        . "where sub_ac_map is an alias of:\n"
	. "/ebi/production/seqdb/embl/tools/curators/scripts/map_ffl_to_sub.pl\n\n"
	. "<filename>    must be a .sub or .ffl file.  A space-separated list of files can be used.\n"
	. "<acc1>-<acc2> is a range of accessions which exist within the directory e.g. AJ12340-AJ12349\n"
	. "              If no arguments are used, all .ffl and .sub files in the directory will be mapped.\n"
	. "-h            This help text.\n\n";
        
    
    # handle the command line.
    foreach $arg ( @$args ) {

	if ( ($arg =~ /^([^-]+\.ffl)$/i) ||
	     ($arg =~ /^([^-]+\.sub)$/i) ) {
	    print "1\n";
 	    push(@inputFiles, $1);
	}
	# range of accessions
	elsif ($arg =~ /.\-/) {

	    if (($arg =~ /^([A-Z]\d{5})(\.[A-Z]+)? ?- ?([A-Z]\d{5})(\.[A-Z]+)?$/i) ||
                ($arg =~ /^([A-Z]{2}\d{6})(\.[A-Z]+)? ?- ?([A-Z]{2}\d{6})(\.[A-Z]+)?$/i) ||
                ($arg =~ /^([A-Z]{4}\d{8,9})(\.[A-Z]+)? ?- ?([A-Z]{4}\d{8,9})(\.[A-Z]+)?$/i)) {

		@inputFiles = expand_acc_range($1, $3);

		foreach $file (@inputFiles) {
		    $file .= ".ffl";
		}
	    }
	}
	elsif ( $arg =~ /-h(elp)?/ ) {
	    die $usage;
	}
	else {
	    die ( "Do not understand the term $arg\n" . $usage );
	}
    }
    foreach $file (@inputFiles) {
	if (! -e $file) {
	    die "Input file $file cannot be located in this directory.\n\n";
	}
    }

    return(sort(@inputFiles));
}

#-------------------------------------------------------------------------------
sub make_fwd_and_rev_hashes(\@\@\%\%) {
    my $subFiles = shift;
    my $fflFiles = shift;
    my $subToFfl = shift;
    my $fflToSub = shift;

    for (my $c=0; $c<@$subFiles; $c++) {
	$$subToFfl{ $$subFiles[$c] } = $$fflFiles[$c];
	$$fflToSub{ $$fflFiles[$c] } = $$subFiles[$c];
    }
}

#-------------------------------------------------------------------------------
# Usage   : main(@ARGV)
# Description: contains the run order of the script
# Return_type : none
# Args    : @ARGV command line arguments
# Caller  : this script
#------------------------------------------------------------------------------
sub main(\@) {
    my $args = shift;

    my @inputFiles = usage(@$args); 
    
    my @sub_files =  find_files("","sub"); 
    if (scalar(@sub_files) == 0) {
	die "No .sub files found\n";
    }
    my @ffl_files =  find_files("","ffl");
    if (scalar(@ffl_files) == 0) {
	die "No .ffl files found\n";
    }
    my @sub_notused_files = find_files("","sub_notused"); 

    if (scalar(@sub_notused_files) != 0) {
	# check if we need to include .sub_notused in the sub list
	if (scalar(@sub_files) == scalar(@ffl_files)) {
	    printf STDERR "No need to consider the %s.sub_notused file%s (equal numbers of .ffl and .sub)\n", 
	                  (scalar(@sub_notused_files) > 1?scalar(@sub_notused_files)." ": ""),
	                  (scalar(@sub_notused_files) > 1?"s":"");
	} elsif ((scalar(@sub_files) != scalar(@ffl_files)) &&
		 (scalar(@sub_files) + scalar(@sub_notused_files) == scalar(@ffl_files))) {
	    printf STDERR "Warning: Assuming that the %s.sub_notused file%s were assigned but the .ffl files have NOT been deleted\n", 
	                  (scalar(@sub_notused_files) > 1?scalar(@sub_notused_files)." ": ""),
	                  (scalar(@sub_notused_files) > 1?"s":"");
	    @sub_files = sort(@sub_files, @sub_notused_files);
	} else {
	    printf STDERR "No mapping is currently possible due to there being %d .sub and %d .ffl files.\n\n"
		. "even if I try to also consider the %s.sub_notused file%s \n", 
		scalar(@sub_files), 
		scalar(@ffl_files), 
		(scalar(@sub_notused_files) > 1?scalar(@sub_notused_files)." ": ""),
		(scalar(@sub_notused_files) > 1?"s":"");
	}
	
    }
	    
	
    # die if BULK.FFL found
    foreach my $ffl_file (@ffl_files) {
	if ( $ffl_file =~ /BULK.FFL/i ) {
	    die "BULK.FFL has been found.  Unfortunately this can't be mapped to sub files at present.\n\n";
	}
    }

    # show mapping
    if (scalar(@sub_files) == scalar(@ffl_files)) {

	my (%subToFfl, %fflToSub);
	make_fwd_and_rev_hashes(@sub_files, @ffl_files, %subToFfl, %fflToSub);

	if (@inputFiles) {
	    foreach my $inputFile (@inputFiles) {
		if ($inputFile =~ /\.sub$/) {
		    print "$inputFile maps to ".$subToFfl{$inputFile}."\n";
		}
		elsif ($inputFile =~ /\.ffl$/) {
		    print "$inputFile maps to ".$fflToSub{$inputFile}."\n";
		}
	    }
	}
	else {
	    foreach my $ffl (sort(keys %fflToSub)) {
		print "$ffl maps to $fflToSub{$ffl}\n";
	    }
	}
    }
    # if a mix of sub->sub_notused before and after assignment we haven't a chance
    else {
	    printf STDERR "No mapping is possible due to there being %d .sub and %d .ffl files but no .sub_notused files.\n\n", 
		scalar(@sub_files), 
		scalar(@ffl_files);
	}
}

main(@ARGV);
