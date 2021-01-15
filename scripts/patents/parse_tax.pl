#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2007
#
#
#===============================================================================

use strict;
use Data::Dumper;

sub get_list_of_org_substitutions($) {

    my ($line, %org_corrections, $get_next_line, $misspelt_org);
    my ($correctly_spelt_org);

    my $org_results_file = shift;

    $get_next_line = 0;

    open(ORGRES, "<$org_results_file") || die "Cannot open $org_results_file for reading: $!\n";

    while ($line = <ORGRES>) {

	if ($get_next_line) {
	    if ($line =~ /^  "([^"]+)"/) { #"
  	        $correctly_spelt_org = $1;
	        $org_corrections{$misspelt_org} = $correctly_spelt_org;
            }
            $get_next_line = 0;
        }
        elsif ($line =~ /^! \"([^"]+)\"(  UNKNOWN)?/) { #"
			
	    $misspelt_org = $1;

            if (! defined($2)) {
	        $get_next_line = 1;    
	    }
        }
    }

    close(ORGRES);

    print Dumper (\%org_corrections);

    return(\%org_corrections);
}
################
sub perform_osCheck($$$$$) {

    my ($osCheckScript, $cmd, $msg);

    my $org_list_file = shift;
    my $org_results_file = shift;
    my $database = shift;
    my $verbose = shift;
    my $LOGFILE = shift;

    $osCheckScript = "/ebi/production/seqdb/embl/tools/curators/scripts/osCheck.pl";

    $cmd = "$osCheckScript $database $org_list_file > $org_results_file";

    $msg = "\nChecking organism against $database by running command:\n".$cmd."\n";
    $verbose && print $msg;
    print $LOGFILE $msg;

    system($cmd);

}
#################

sub create_org_list($$) {

    my ($line, %orgs, $org);

    my $embl_file = shift;
    my $org_list_file = shift;

    open(READORGS, "<$embl_file") || die "Cannot read $embl_file: $!\n";

    foreach ($line = <READORGS>) {

	if ($line =~ /^FT\s+\\organism="([^"]+)"/) { #"
            $orgs{$1} = 1;
        }
    }

    close(READORGS);

    open(WRITEORGS, ">$org_list_file") || die "Cannot write to $org_list_file: $!\n";

    foreach $org (keys %orgs) {
        print WRITEORGS "$org\n";
    }

    close(WRITEORGS);
}
##################

sub perform_org_substitutions(\%$$$) {

    my ($line, $tmp_embl_file, $current_org, $bad_org, $cmd);

    my $org_substitutions = shift;
    my $embl_file = shift;
    my $verbose = shift;
    my $LOGFILE = shift;

    $tmp_embl_file = $embl_file.".subs_orgs";

    open(READORGS, "<$embl_file") || die "Cannot read $embl_file: $!\n";
    open(WRITEORGS, ">$tmp_embl_file") || die "Cannot write to $tmp_embl_file: $!\n";

    foreach ($line = <READORGS>) {


	if ($line =~ /^FT\s+\\organism="([^"]+)"/) { #"

            $current_org = $1;

	    foreach $bad_org (keys %$org_substitutions) {

		if ($current_org eq $bad_org) {
		    $line =~ s/"$bad_org"/"$$org_substitutions{$bad_org}"/;
		    last;
		}
	    }
        }

        print WRITEORGS $line;
    }

    close(READORGS);
    close(WRITEORGS);

    $cmd = "mv $tmp_embl_file $embl_file";
    system($cmd);
}


##################
sub check_orgs_are_ok(\@$$$$) {

    my ($patentFile, $org_list_file, $org_results_file, $org_substitutions);
    my ($file_suffix, $embl_file);

    my $patentFiles = shift;
    my $processOldFormat = shift;
    my $database = shift;
    my $verbose = shift;
    my $LOGFILE = shift;

    $org_results_file = "/homes/gemmah/scripts/orgs.res";


    if ($processOldFormat) {
	$file_suffix = ".substd.embl_out";
    }
    else {
	$file_suffix = ".newformat.substd.embl";
    }

    foreach $patentFile (@$patentFiles) {

	$org_list_file = $patentFile.".org_list";
	$org_results_file = $patentFile.".org_results";
	$embl_file = $patentFile.$file_suffix;

	create_org_list($embl_file, $org_list_file);

	perform_osCheck($org_list_file, $org_results_file, $database, $verbose, $LOGFILE);

	$org_substitutions = get_list_of_org_substitutions($org_results_file);

	perform_org_substitutions(%$org_substitutions, $embl_file, $verbose, $LOGFILE);
    }

}
################


check_orgs_are_ok(@patentFiles, $processOldFormat, $database, $verbose, $LOGFILE);

