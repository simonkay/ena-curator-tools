#!/ebi/production/seqdb/embl/tools/bin/perl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/search_ncbi_for_TIs.pl,v 1.3 2011/11/29 16:33:38 xin Exp $
#
#  (C) EBI 2006
#             
#
###############################################################################

#  Initialisation
use strict;
use DBI;
use dbi_utils;
#use Data::Dumper;
use LWP::UserAgent;


sub get_ti_list($) {

    my ( $sql, @ti_list, $db_instance, $dbh );

    my $db_instance = shift;

    if ( ($db_instance ne '/@ENADEV') && ($db_instance ne '/@ENAPRO') ) {
	dbi_logoff ( $dbh );
	die 'The first option needs to be /@ENADEV or /@ENAPRO'."\n";
    }

    $dbh = dbi_ora_connect ( $db_instance);
    $dbh->{AutoCommit}    = 0;
    $dbh->{RaiseError}    = 1;
    
    $sql = "select primaryacc#, acc_no from tpa_segment_data ts join dbentry d on ts.dbentryid = d.dbentryid where ts.acc_no like 'TI%' order by primaryacc#";

    @ti_list = dbi_gettable($dbh, $sql);

    # disconnect from Oracle
    dbi_logoff ( $dbh );

    return(\@ti_list);
}


sub search_ncbi_for_trace_identifiers(\@) {

    my ($ua, $req, $rescontent, $connection_error, @tiAbsentList);
    my ($request_URL_ncbi, $save_file, $i, @tiPresentList, $j);
    my ($res, $ti, $progressCounter);

    my $ti_list = shift;

    $ua = new LWP::UserAgent;
    $connection_error = 0;
    $ua->timeout(1000);

    print "There are ".scalar(@$ti_list)." trace identifiers stored in our database.\nPlease wait while the NCBI website is being searched...\n\n";

    for ($i=0; $i<@$ti_list; $i++) {

	$progressCounter = $i % 20;
	if ((!$progressCounter) && ($i)) {
	    print "Processed $i TI numbers...\n";
	}

	$ti = $$ti_list[$i][1];
	$ti =~ s/^TI//;

	$request_URL_ncbi="http://www.ncbi.nlm.nih.gov/Traces/trace.cgi?&cmd=retrieve&val=TI%3D".$ti."&retrieve=Submit";

	$req = new HTTP::Request GET => $request_URL_ncbi;
	$res = $ua->request($req);

	if ($res->is_success) {
	    $rescontent = $res->content;
		
	    if ($rescontent =~ /\s+Search result:\s+found /) {
		push(@tiPresentList, "$$ti_list[$i][1] (EMBL:$$ti_list[$i][0]) is present in the NCBI archive\n");
	    }
	    else {
		push(@tiAbsentList, "$$ti_list[$i][1] (EMBL:$$ti_list[$i][0]) is missing from NCBI archive\n");
	    }
	}
	else {
	    $connection_error = 1;
	    print STDERR "No reply to HTTP-request - bad luck this time\n";
	}	
    }

    return(\@tiAbsentList, \@tiPresentList);
}


sub save_data(\@\@) {

    my ($output_file, $numAbsent, $numPresent, $totalNumTIs, $msg);

    my $tiAbsentList = shift;
    my $tiPresentList = shift;

    $output_file = "ti.output";

    open(OUTFILE, ">$output_file") || die "Cannot open $output_file for writing\n";

    print "\nPlease look inside $output_file for the results.\n";

    $numAbsent = scalar(@$tiAbsentList);
    $numPresent = scalar(@$tiPresentList);
    $totalNumTIs = $numAbsent + $numPresent;

    if (@$tiPresentList) {
	$msg = "# There are ".scalar(@$tiPresentList)."/".$totalNumTIs." TIs from the internal database present in the NCBI trace archives\n"; 
	print "\n$msg";
	print OUTFILE "$msg\n";
	print OUTFILE  @$tiPresentList;
	print OUTFILE "\n\n";
    }
    if (@$tiAbsentList) {
	$msg = "# There are ".scalar(@$tiAbsentList)."/".$totalNumTIs." TIs from the internal database missing from the NCBI trace archives\n";
	print $msg;
	print OUTFILE "$msg\n";
	print OUTFILE  @$tiAbsentList;
    }

    close(OUTFILE);
}


sub main(\@) {

    my ($ti_list, $tiAbsentList, $tiPresentList);
    my $args = shift;

    print "This script looks to see if any of the trace identifiers stored in the database are present in the NCBIs trace archives.\n";

    $ti_list = get_ti_list($$args[0]);

    ($tiAbsentList, $tiPresentList) = search_ncbi_for_trace_identifiers(@$ti_list);

    save_data(@$tiAbsentList, @$tiPresentList);
}

main(@ARGV);
