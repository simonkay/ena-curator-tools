#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/ckprots2.pl,v 1.1 2007/12/10 14:06:15 gemmah Exp $
#
#  (C) EBI 2000
#
#  MODULE DESCRIPTION:
#
#  Parses the log file of the command 'putff -parse_only -new_log_format' (which makes a
#  syntax check on flat files) and reports:
#  1. messages about CDS translations
#  2. accession numbers of all entries that failed the parser
#
#  Output (to screen):
#  1. accession number or - if there is none - entry name
#  2. all cds locations with first and last aa and error or 'ok'.
#     NOTE: only the first try is shown for the cases where putff
#     tries to find a valid /codon_start because the information in the
#     file is incorrect.
#
#  MODIFICATION HISTORY:
#
#  30-JUN-2000  Carola Kanz        created.
#     APR-2001  Carola Kanz        added $test flag to avoid usage of this script
#                                  on logfiles not created with -parse_only option,
#                                  i.e. log files without the separator 
#                                  '### NEXT ENTRY ###' between entries which gives
#                                  an incomplete output otherwise
#  07-JUN-2001  Carola Kanz        fixed bug that ignored '*' as possible aa.
#                                  show first and last aa of *first* translation
#                                  if all /codon_start are tried for one location.
#  06-AUG-2001  F Nardone          Added '()' at the end of $pattern in add_message
#                                  so that $1 is always defined.
#  09-AUG-2001  Peter Stoehr       creates $USAGE to for usage notes
#  19-SEP-2001  Nicole Redaschi    rewrote much of main.
#  15-OCT-2001  Nicole Redaschi    fixed bug that last entry was not reported.
#                                  "fixed" compose_message to handle references properly.
#                                  added display of warnings.
#  02-NOV-2001  Nicole Redaschi    fixed parsing of status messages.
#  12-JAN-2004  Quan Lin           if cds is pseudo, print out in the report
#  18-JAN-2006  Nadeem Faruque     patched up to cope with changes in the putff output
#===============================================================================

use strict;

my $submitter_mode = 0;


#===============================================================================
#  subroutines
#===============================================================================

sub add_message(\$$$;$) {
    # $1 used for /codon_start, has to be in last place

    my ( $message, $text, $pattern, $display ) = @_;

    if ( $text =~ /$pattern()/ ) {
	# the () at the end define $1 if there are no brackets in $pattern
	if ( $$message ) {
	    $$message .= "; ";
	}
	$$message .= ( defined $display ) ? $display.$1 : $pattern.$1;
    }
}

#-------------------------------------------------------------------------------
# checks concatenated warning and error lines for certain keywords:
# 3rd paramter to add_message is the regular expression to parse, 4th parameter
# the error message printed ( if not given, the third parameter is printed )
#-------------------------------------------------------------------------------

sub compose_message(\$$$) {

    my ( $message, $type, $text ) = @_;

    add_message ( $$message, $text, "contains stop codon", "contains stop" );
    add_message ( $$message, $text, "missing stop codon", "missing stop codon" );
    add_message ( $$message, $text, "invalid start codon", "invalid start codon" );
    add_message ( $$message, $text, "must be 5\' partial" );
    add_message ( $$message, $text, "must be 5\' or/and 3\' partial" );
    add_message ( $$message, $text, "requires \/codon\_start", "add /codon_start" );
    add_message ( $$message, $text, "resubmit entry with qualifier \/codon\_start\=(\\d)", 
		  "try /codon_start=" );
    add_message ( $$message, $text, "resubmit entry without qualifier \/codon\_start", 
		  "try without /codon_start" );

    if ( $text =~ /flat file and conceptual translations differ by X/ ) {
	add_message ( $$message, $text, "flat file and conceptual translations differ", 
		      "translations differ by X" );
    }
    else {
	add_message ( $$message, $text, "flat file and conceptual translations differ", 
		      "translations differ" );
    }

    add_message ( $$message, $text, "translational exception not within frame", 
		  "transl_except not in frame" );
    add_message ( $$message, $text, "\/exception.*no flat file translation", 
		  "/exception no translation" );
    add_message ( $$message, $text, "stop-codon-only CDS must be at 3\' end and partial", 
		  "must be 3' partial" );
    add_message ( $$message, $text, "more than one stop codon at 3\' end", 
		  "more than one stop codon at 3' end" );
    add_message ( $$message, $text, "incorrect or missing \/codon\_start qualifier", 
		  "add or correct /codon_start" );
    add_message ( $$message, $text, "stop codon at 3\' end - location must not be partial", 
		  "remove 3' end - location must not be partial" );
    add_message ( $$message, $text, "differs from standard table",
		  "/transl_table differs" );

    if ( ! $$message ) { 
	if ($type eq "W") {
	    $$message = "warning";
	}
	else {
	    $$message = "error"; 
	}
    }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------

sub check_args(\@) {

    my ($arg, $input_file);

    my $args = shift;

    my $usage = "\n PURPOSE: Parses log file from \"putff -parse_only\" to report if .ffl\n".
	"          files will load and if CDS features code correctly\n\n".
	" USAGE:   $0\n".
	"          <putff_parse_only_log_file>\n\n".
	"          When executed in 'loadcheck.csh' or 'loadcheck1.csh'\n".
	"          <putff_parse_only_log_file> is called 'load.log'\n\n".
	"          Output:\n".
	"          Lists accession numbers\n".
	"          Lists entrynames if loadcheck fails on the ID line\n".
	"          Lists all CDS locations, first and last aa and error or 'ok'\n".
	"          NOTE: THE STOP CODON IS NOT REPORTED\n\n";

    foreach $arg (@$args) {
	
	if (($arg =~ /^-h(elp)?/) || ($arg =~ /^-u(sage)?/)) {
	    die $usage;
	}
	elsif ($arg =~ /^-s(ubmitter)?/) {
	    $submitter_mode = 1;
	}
	elsif ($arg =~ /^([^-]+.*)$/) {
	    $input_file =  $1;
	}
    }

    if (! defined($input_file)) {
	die "You must enter a log file to parse.\n$usage";
    }
    elsif (! -e $input_file) {
	die "The input file $input_file can't be found.\n$usage";
    }

    return($input_file);
}

#-------------------------------------------------------------------------------
# alter the log message (if it needs it)
#-------------------------------------------------------------------------------
		
sub update_log_message(\$) {

    my $log_msg = shift;

    if ($$log_msg =~ /^complement/) {
	$$log_msg =~ s/^complement/c/;
    }
    elsif ($$log_msg =~ /^join/) {
	$$log_msg =~ s/^join/j/;
    }
}

#-------------------------------------------------------------------------------
# read putff logfile
#-------------------------------------------------------------------------------

sub main(\@) {

    # if a translation contains internal stop codons, all /codon_start
    # are tried in putff to find a working one.
    # $first_aa_sv and $last_aa_sv are used to store the first and last
    # aa of the FIRST translation as this is the one in the flatfile.

    my (%summary_report, $file);

    my $first_aa    = ' ';
    my $last_aa     = ' ';
    my $first_aa_sv = ' ';
    my $last_aa_sv  = ' ';

    my $error      = '';
    my $warning    = '';
    my $accno      = '';
    my $pseudo     = '';
    my $parse_only = 0;
    my $CDSmessage = "";
    my $first_cds  = 1;

    my $args = shift;

    $file =  check_args(@$args);

    open ( IN, "< $file" ) || die "cannot open file $file: $!\n";

    while ( <IN> ) {

	chomp ( my $line = $_ );

	if ( $line =~ /putff: Command not found\./ ) {
	    die "\nERROR: *** putff is not available\n\n";
	}
	elsif ( $line =~ /DS.* does not exist in the database/ ) {
	    die "\nERROR: $_\n";
	}

	# the "NEXT ENTRY" line signals that putff was used with the
	# -parse_only option and we should find CDS information
	if ( (! $parse_only) && ($line =~ /^INFO: \#+ NEXT ENTRY \#+/) ) {
	    $parse_only = 1;
	}

	# the "NEXT ENTRY" line or "total cpu" line signals that we are
	# at the beginning (or end) of an entry (don't use "total elapsed",
	# we may have already skipped it - see below!)
	if ( $parse_only &&
	     ( ($line =~ /^INFO: \#+ NEXT ENTRY \#+/) || ($line =~ /^INFO: total cpu/) ) 
	   ) {

	    # check whether previous entry had no CDSs.
	    if (($CDSmessage eq "") && ($accno ne '')) {
		printf "\n%-10s                        no CDSs", $accno;
	    }
	    else {
		$CDSmessage =~ s/ACCESSIO/$accno/gs;
		if ($CDSmessage !~ /$accno$/) {
		    print $CDSmessage;
		}
	    }
	   
	    $first_cds = 1;
	    $accno = "ACCESSIO"; # placeholder value to be replaced once the entry is fully parsed
	    $CDSmessage = "";

	    if ($line =~ /^INFO: total cpu/) {
		# end of entries
		last;
	    }
	}
	# collect status messages
	elsif ( $line =~ /\#\#\# (\S+) entry: *(\S+)/ ) {
	    $accno = sprintf "%-8s", $2; # for short accession numbers, pad with spaces

	    if (!$submitter_mode) {
		$summary_report{ $1.": ".$2 } = $2;
	    }
	}
	
	# unless we have hit the "NEXT ENTRY" line, we do not
	# need to try to get information about CDSs
	if ( ! $parse_only ) {
	    next;
	}

	# start/end of a CDS
	if ( $line =~ /^INFO: \-{30}/ ) {

	    # if this isn't the first CDS, we need to print the information
	    # for the previous CDS.
	    if ( $first_cds != 1 ) {
		if ( $first_aa_sv ne ' ' ) {
		    $CDSmessage .= "$first_aa_sv  $last_aa_sv  ";
		}
		else {
		    $CDSmessage .= "$first_aa  $last_aa  ";
		}
		
		if ( $error ne '' || $warning ne '' ) {

		    my $message = '';

		    if ($error  ne '') {
			compose_message( $message, "E", $error );
		    }
		    if ($warning ne '') {
			compose_message( $message, "W", $warning );
		    }
		    if ($pseudo eq '') {
			$CDSmessage .= $message;
		    }
		    else {
			$CDSmessage .= "$message coding pseudo";
		    }
		}
		else {
                    # in curator mode, show all the messages (good and bad)
		    if ($pseudo eq '') {
			$CDSmessage .= "ok";
		    }
		    else {
			$CDSmessage .= $pseudo;
		    }

		    # if in submitter_mode, dispose of this non-error line
                    # (submitters only want to see what corrections are required)
		    if ($submitter_mode) {

			if (($CDSmessage =~ /ACCESSIO\s+[^\n]+$/) && 
			            (($CDSmessage =~ /\s+ok$/) || ($CDSmessage =~ /$pseudo/))) {
			    $CDSmessage =~ s/(ACCESSIO)\s+[^\n]+$/$1/;
			}
			else {
			    $CDSmessage =~ s/\n[^\n]+$//;
			}
		    }
		}
		
		# reset variables
		$error       = '';
		$warning     = '';
		$pseudo      = '';
		$first_aa    = ' ';
		$last_aa     = ' ';
		$first_aa_sv = ' ';
		$last_aa_sv  = ' ';
	    }
	    
	    # try to find the CDS-location-line and concatenate warnings and errors 
	    # that appear before the CDS-location-line to grep for keywords later
	    my $filePositionMarker = tell(IN);

	    while ( <IN> ) {
		chomp ( $line = $_ );

		# CDS-location-line

		if ($line =~ /^(ERROR|INFO): CDS \S*/) {
		    last;
		}
		elsif ($line =~ /^ERROR: proteintranslation failed for entry/) {
		    # end of CDS TRANSLATIONS block:
		    # 1. failure: 'proteintranslation failed' message
		    last;
		}
		elsif ($line eq "") {
		    # 2. success: empty line or 'total elapsed time'
                    # pointless?
		    last;
		}
		elsif ($line =~ /^INFO: total elapsed time/) {
		    last;
		}
		
		# collect warnings and errors
		if ( $line =~ /^WARNING: (.*)/ ) {
		    $warning .= " $1";
		}
		elsif ( $line =~ /^ERROR: (.*)/ ) {
		    $error .= " $1";
		}
		# collect status messages
		if ( $line =~ /^INFO: \#\#\# (\S+) entry: *(\S+)/ ) {

		    if (!$submitter_mode) {
			$summary_report{ $1.": ".$2 } = $2; # probably redundant
		    }

		    seek( IN, $filePositionMarker, 0);  # we took a line that wasn't really ours so we should give it back
		    last;
		}
		$filePositionMarker = tell(IN);
	    }


	    if ( ($line =~ /^INFO: CDS (\S*)/) || ($line =~ /^ERROR: CDS (\S*)/)) {

		my $log_msg = $1;
		update_log_message($log_msg);
		$log_msg = substr( $log_msg, 0, 15 );

		if ($log_msg =~ /,$/) {
		    $log_msg =~ s/,$/ /;
		}

		my $print_this = "";
		if ($first_cds) {
		    $print_this = $accno;
		    $first_cds = 0;
		}

                # if accession exists but has been stripped of it's information tail 
                # (in submitter mode), format add the new bit of info to the accession line
		if (($submitter_mode) && ($CDSmessage =~ /ACCESSIO$/)) {
		    $CDSmessage .= sprintf("%-2s %-15s  ", "", $log_msg);
		}
		else {
		    $CDSmessage .= sprintf("\n%-10s %-15s  ", $print_this, $log_msg);
		}
	    }
	    
	    if ( $line =~ /^INFO: CDS \S*\s+\/(pseudo)/){
		$pseudo = $1;
	    }
	}
        # get warnings
	elsif ( $line =~ /^WARNING: (.*)/ ) {
	    $warning .= " $1";
	}
        # get errors
	elsif ( $line =~ /^ERROR: (.*)/ ) {
	    $error .= " $1";
	}
	# get first and last aa
	elsif ( ($line =~ /^      ([\*A-Z]   )([\*A-Z]   )*/) || ($line =~ /^      ([\*A-Z]\s*)([\*A-Z]\s*)*$/) )  {
	    if ( $first_aa eq ' ' ) {
		$first_aa = substr ( $1, 0, 1 );
	    }
	    $line =~ /([\*\w])\s*$/;
	    $last_aa = $1; 
	}
	# special case /codon_start (see above)
	elsif ( ($line =~ /\/codon_start/) && ($first_aa_sv eq ' ') ) {
	    $first_aa_sv = $first_aa;
	    $last_aa_sv  = $last_aa;
	    $first_aa    = ' ';
	    $last_aa     = ' ';
	}
    }
    close(IN) || die "cannot close file $file: $!\n";


    if (! $parse_only) {
	print "\nWARNING: ckprots probably run on a log file not created with -parse_only option";
    }
    
    if (!$submitter_mode) {
	print "\n\n------------------------------ summary report ------------------------------\n\n";
    
	if ( %summary_report ) {
	    foreach my $key ( sort keys(%summary_report) ) {
		print "$key\n";
	    }
	}
	else {
	    print "All entries are OK!\n\n";
	}
    }
}

#-------------------------------------------------------------------------------------
# run program
#-------------------------------------------------------------------------------------

main(@ARGV);
