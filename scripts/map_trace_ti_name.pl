#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2007
#
#===============================================================================

use strict;
use LWP::UserAgent;
use warnings;
use DirHandle;

my $verbose = 0;

#-------------------------------------------------------------------------------
# Usage   : usage(@ARGV)
# Description: populates global variables with commandline arguments (plus prints
# help text)
# Return_type : database and file to map
# Args    : @$args : list of arguments from the commandline.
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub get_args(\@) {

    my ( $arg, $usage, @inputFiles, $line );

    my $args = shift;

    $usage= "\nPURPOSE: To display the trace number of the trace name entered.\n\n"
        . "USAGE:\n"
        . "get_ti_num <trace name>  using one or more filenames\n"
        . "get_ti_num <file>+       using 1+ files containing lists of trace names\n"
        . "get_ti_num -h            this help message\n\n"
        . "where get_ti_num is an alias of:\n"
        . "/ebi/production/seqdb/embl/tools/curators/scripts/map_trace_ti_name.pl\n\n"
	. "Example trace names: 99747, AFHY657891.g1\n\n";
        
    
    # handle the command line.
    foreach $arg ( @$args ) {

        if ( $arg =~ /-h(elp)?/ ) {
            die $usage;
        }
	elsif ( $arg =~ /-v(erbose)?/ ) {
	    $verbose = 1;
	}
	elsif (! -e $arg) {
	    push(@inputFiles, $arg);
	}
	else {
	    open(INPUT, "<$arg") || die "Cannot open $arg: $!\n";
	    while ($line = <INPUT>) {
		if ($line =~ /^([^\s]+)/) {
		    push(@inputFiles, $1);
		}
	    }
	    close(INPUT);
	}
    }

    return(\@inputFiles);
}


#-------------------------------------------------------------------------------
# get_ti_from_ncbi
# params: 
# 1. accession number
# 2. verbose flag
#-------------------------------------------------------------------------------
sub get_ti_name_from_ncbi(\@) {

    my ($request_URL, $ua, $req, $result, $rescontent, $sequence, $species);
    my ($trace_name, @tracenameAndNum, $line, @rescontent, @sortedTraces);

    my $trace_names = shift;

    $request_URL = "http://www.ncbi.nlm.nih.gov/Traces/trace.cgi?cmd=retrieve&val=";

    foreach $trace_name (@$trace_names) {
	$request_URL .= 'TRACE_NAME%20%3D%20%22'.$trace_name.'%22%20or%20';
    }

    $request_URL =~ s/or\%20$//;
    $request_URL .= "&dopt=fasta&size=24&dispmax=500&seeas=Show";

    #print "request_URL = $request_URL\n";

    $ua = new LWP::UserAgent(parse_head => 0);
    $ua->timeout(1000);

    $req = new HTTP::Request GET => $request_URL;
    $verbose && print "Retrieving TI using $request_URL - ";

    $result = $ua->request($req);
    if (!( $result->is_success )) {
        print "No reply from NCBI\n";
        return "";
    }
    
    $rescontent = $result->content;

    # put string into array for easier searching
    @rescontent = split("\n", $rescontent);         

    foreach $line (@rescontent) {
	if ( $line =~ /\<pre\>\>gnl\|ti\|(\d+) name:([^\s]+)/g ) {
	    push(@tracenameAndNum, $2.",".$1);
	}
    }

    @sortedTraces = sort({$a cmp $b} @tracenameAndNum);

    return(\@sortedTraces);
}    


#-------------------------------------------------------------------------------
# Usage   : main(@ARGV)
# Description: contains the run order of the script
# Return_type : none
# Args    : @ARGV command line arguments
# Caller  : this script
#------------------------------------------------------------------------------
sub main(\@) {

    my ($inputFiles, $trace, $tiNumHash, $traces, $tracename, $tracenum);
    my ($prevTracename);

    my $args = shift;

    $inputFiles = get_args(@$args);
 
    $traces = get_ti_name_from_ncbi(@$inputFiles);

    print "\n";
    foreach $trace (@$traces) {
	($tracename, $tracenum) = split(/,/, $trace);
	print "$tracename maps to trace number $tracenum";

	if (defined($prevTracename) && ($prevTracename eq $tracename)) {
	    print " ** duplicate trace name";
	}

	print "\n";
	$prevTracename = $tracename;
    }
    print "\n";
}

main(@ARGV);
