#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  SCRIPT DESCRIPTION:
#
#  A script to reverse complement a sequence.  The summary output from 
#  curator_blast is examined for complementary blast results.  Any complementary
#  sequences found have <orig_filename>.revcomp files made containing the 
#  complementary sequence to the original file.
#
#===============================================================================

use strict;

my $verbose;

my $usage =
    "\nPURPOSE: This script takes the output summary from blast16S, finds the complementary \n"
  . "(+/-) blast results and re-fills the embl files with the complementary sequence.\n\n"
  . " USAGE:   rev_comp_maker.pl [<sequence files>] [-v] [-h]\n\n"
  . "   <sequence files>      These are the files which need reverse complementing\n\n"
  . "   -v                  verbose mode\n\n"
  . "   -h                  shows this help text\n\n";

################################################################################
#

sub get_comp_seq($) {

    my ($line, $new_seq, $get_seq);

    my $compfile = shift;

    open(GETNEWSEQ, "<$compfile");

    $get_seq = 0;

    while ($line = <GETNEWSEQ>) {
	if ($line =~ /^SQ/) {
	    $get_seq = 1;
	}
	elsif ($line =~ /^\/\//) {
	    $new_seq .= $line;
	}
	elsif ($get_seq) {
	    $new_seq .= $line;
	}
    }

    return($new_seq);
}

################################################################################
#

sub get_seqret_rev_seq($) {

    my ($comp_file, $seqret_cmd, $comp_seq);

    my $embl_file = shift;

    $comp_file =  $embl_file.".rev";

    $seqret_cmd = "/ebi/extserv/bin/emboss/bin/seqret -srev -osformat2 embl -sequence $embl_file -outseq $comp_file -auto";
    system($seqret_cmd);

    $comp_seq = get_comp_seq($comp_file);

    unlink($comp_file);

    return ($comp_seq);
}

################################################################################
#

sub create_new_embl_file($$) {

    my ($line, @sequenceless_entry, $new_revcomp_file);

    my $filename = shift;
    my $new_seq = shift;

    open(GETEMBLDATA, "<$filename") || print "Cannot open $filename\n";
    
    while ($line = <GETEMBLDATA>) {
	if ($line =~ /^     [a-z]+ /) {
	    last;
	}
	else {
	    push(@sequenceless_entry, $line);
	}
    }

    close(GETEMBLDATA);


    $new_revcomp_file = $filename.".revcomp";
    open(CREATENEWSEQFILE, ">$new_revcomp_file") || print "Cannot open $new_revcomp_file\n";

    foreach $line (@sequenceless_entry) {
	print CREATENEWSEQFILE $line; 
    }

    print CREATENEWSEQFILE $new_seq;
    
    close(CREATENEWSEQFILE);

    print "$new_revcomp_file contains the reverse-complement sequence and entry.\n";
}

################################################################################
#

sub update_embl_files(\@) {

    my ($filename, $keep_backup_file, $comp_file, $comp_seq, $comp_acc);

    my $comp_accs = shift;

    foreach $comp_acc (@$comp_accs) {

	$filename = $comp_acc.".fflupd";

	if (! -e $filename) {
	    $filename = $comp_acc.".ffl";
	}
	if (! -e $filename) {
	    $filename = $comp_acc.".temp";
	    
	}
	if (! -e $filename) {
	    $filename = $comp_acc.".sub";
	    $keep_backup_file = 1;
	}
	if (! -e $filename) {
	    print "Cannot find file with the prefix $comp_acc (.fflupd, .ffl, .temp or .sub) in order to reverse complement the file\n";
	}
	
	$comp_seq = get_seqret_rev_seq($filename);
	
	create_new_embl_file($filename, $comp_seq);
    }
}

################################################################################
#

sub get_complement_accs(\@) {

    my ($line, $file, @comp_accs);

    my $summaryFiles = shift;

    foreach $file (@$summaryFiles) {
	open(READSUMM, "<$file") || die "Cannot read input file $file\n";

	while ($line = <READSUMM>) {
	    if ($line =~ /^(([A-Z]{1,2}\d+)|[a-z]+\d+): complement/) {
		push(@comp_accs, $1);
	    }
	}
	close(READSUMM);
    }

    return(\@comp_accs);
}

################################################################################
# Get the arguments

sub get_args($) {

    my (@summaryFiles, $arg);

    my $args = shift;

    # check the arguments for values
    foreach $arg (@$args) {

        if ($arg =~ /^\-v(erbose)?$/) { # verbose mode
            $verbose = 1;
        } elsif ($arg =~ /^\-h(elp)?/) {     # help mode
            die $usage;
        } elsif ($arg =~ /^([^-].+)/) {
            push(@summaryFiles, $1);
        } else {
            die "Unrecognised argument format. See below for usage.\n\n" . $usage;
        }
    }

    if (@summaryFiles > 1) {
        die "Cannot accept more than 1 summary file as input.  Please concatenate summary files.\n";
    }

    return (\@summaryFiles);
}

################################################################################
# main function

sub main(\@) {

    my ($summaryFiles, $comp_accs);

    my $args = shift;

    ($summaryFiles) = get_args($args);

    $comp_accs = get_complement_accs(@$summaryFiles);

    update_embl_files(@$comp_accs);
}

################################################################################
# run the script

main(@ARGV);
