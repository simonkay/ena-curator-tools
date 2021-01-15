#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  asgen_multi.pl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/asgen_multi.pl,v 1.1 2008/12/22 17:17:24 gemmah Exp $
#
#  DESCRIPTION:
#
#  Takes in a single filename or filename wildcard and runs asgen on it 
#  with the given parameters (asgen itslf can only process a single temp file)
#
#
#===============================================================================

use strict;
#use Data::Dumper;

my $scoreLimit      = 100; # default cutoff score
my $minimumIdentity = 0.9; # default minimum percentage identity
my $minimumLength   = 0;   # default minimum length of hits allowed in results
my $gapPenalty      = -4;  # default gap penalty for nucleotides
my $gaps            = 0;   # if gaps=1 a gapped blast will be run
my $verbose         = 0;
my $asgen           = '/ebi/production/seqdb/embl/tools/curators/scripts/as_generator.pl';

#-----------------------------------------------------------------------------------------------------

sub run_asgen(\%) {

    my (@fileList, $file, $cmd, $num_files);

    my $inputFiles = shift;


    $num_files = scalar(keys(%$inputFiles));

    print "There are $num_files files to run asgen on.\n";

    if ($num_files > 10) {
	print "Therefore this script may take a while to complete\n";
    }

    print "\n";

    foreach $file (keys(%$inputFiles)) {

	$cmd = "$asgen -score=$scoreLimit -length=$minimumLength -identity=$minimumIdentity -penalty=$gapPenalty $file";

	if ($gaps) {
	    $cmd .= " -gaps"; 
	}
	else {
	    $cmd .= " -nogaps"; 
	}

	$cmd .= " >& ".$file.".asgen.log";

	print "Running command:\n$cmd\n";
	system($cmd);
    }
}

#-----------------------------------------------------------------------------------------------------

sub get_args(\@) {

    my ($usage, $arg, %inputFiles);

    my $args = shift;

    $usage =
    "\n USAGE: $0 [-s={score}] [-l={length}] [-i={identity}] [-p(enalty)={gap penalty}] [-nogaps] [-gaps] [-v] [-h] [TPA filename]\n\n"
  . " PURPOSE: Checks .temp files in current directory and find AS lines.\n"
  . "         All sequences mentioned on AS lines are formed into a blast\n"
  . "         database. The TPA sequence is blasted and all hits above the\n"
  . "         cutoff score are taken. For each hit that is not nested within\n"
  . "         a higher scoring hit, an AS line is made.\n"
  . "         The coverage of each section of the TPA sequence is reported.\n\n"
  . " -h(elp)             This help message\n"
  . " -v(erbose)          Verbose output\n"
  . " -s(core)=<value>    Cutoff score (default = $scoreLimit)\n"
  . " -l(ength)=<value>     Minimum length of blast aligned sequence to be\n"
  . "                     allowed into the AS lines generated (default = $minimumLength)\n"
  . " -i(dentity)=<value>   Minimum sequence identity of a hit to be allowed\n"
  . "                     into the AS lines generated. Acceptable percentage\n"
  . "                     formats: 0.9, 90 or 90% (default = $minimumIdentity)\n"
  . " -p(enalty)          Gap penalty.  Default = -4"
  . " -gaps               Allow a gapped blast to be run (by default an ungapped\n"
  . "                     blast is run).\n"
  . "                     Optionally specify a value for the gap penalty (default = -4)\n"
  . " -nogaps             Allow an ungapped blast to be run (this is default behaviour)\n"
  . " TPA Filename        Either (a) a single filename or (b) a wildcard filename should\n"
  . "                     be used where multiple files need to be run through asgen (e.g.\n"
  . "                     *.temp or hoad_*.temp).\n\n";


    foreach $arg (@$args) {

	if ($arg =~ /^\-h(elp)?/i) {
	    die $usage;
	}
        elsif ( $arg =~ /-v(erbose)?/i ) {
            $verbose = 1;
        }
        elsif ( $arg =~ /\-s(core)?=(\d+)/i ) {
            $scoreLimit = $2;
        }
        elsif ( $arg =~ /\-l(ength)?=(\d+)/i ) {
            $minimumLength = $2;
        }
        elsif ( $arg =~ /\-i(dentity)?=([0-9\.]+%?)/i ) {
            $minimumIdentity = $2;
            $minimumIdentity =~ s/%$//;

            if ($minimumIdentity > 1) {
                if ($minimumIdentity <=100){
                    $minimumIdentity = $minimumIdentity / 100;
                }
                else{
                    die "minimum identity of \"$minimumIdentity\" makes no sense, I prefer as a deci
mal fraction 0.90 or a percentage\n";
                }       
            }
        }
        elsif ( $arg =~ /\-p(enalty)?=([0-9-]+)/i ) {
            $gapPenalty = $2;
        }
        elsif ( $arg =~ /\-g(aps?)?/i ) {
            $gaps = 1;
        }
        elsif ($arg !~ /^\-/) {
	    $inputFiles{$arg} = 1;
        }
        else {
            die "\nThe argument \"$arg\" has not been recognised\n\n".$usage;
        }
    }

#    print Dumper(\%inputFiles);

    if (scalar(keys(%inputFiles)) < 1) {
	die "Only one input file should be entered e.g. myfile.temp or akhtar*.temp\n\n";
    }

    return(\%inputFiles);
}

#-----------------------------------------------------------------------------------------------------

sub main(\@) {

    my ($inputFiles);

    my $args = shift;

    $inputFiles = get_args(@$args);

    run_asgen(%$inputFiles);
}

#-----------------------------------------------------------------------------------------------------

main(@ARGV);
