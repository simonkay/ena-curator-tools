#!/ebi/production/seqdb/embl/tools/bin/perl
#
#

use strict;
#use warnings;
sub main();

main();

#The intention of this perl script is to reformat the incoming mga data
#into a more consistent format so that putff can process it.
#Main tasks it does:
# Outputs master file until \\
# inserts fake bp into Locus line to conform with NCBI format
# Add header MGA VAR to > line in variable file and output only these lines
# Output \\
#note that this is expecting the correct input formats if you give it a wierd
#format don't expect it to fail gracefully.
#this also assumes that there will be only one entry in the master file

sub main() {
    my $line;
    my $USAGE = "
USAGE: $0 <master mga file> <variable mga file>
PURPOSE: Creates an NCBI like version of these two files
";

    unless (defined $ARGV[1]) {
        die $USAGE;
    }
    my $master_file = $ARGV[0];
    my $variable_file = $ARGV[1];
    open INPUT_MASTER_FILE ,$master_file  or die "can't open file: ",$master_file,"$!\n";
    open INPUT_VARIABLE_FILE ,$variable_file  or die "can't open file: ",$variable_file,"$!\n";
    
    # Outputs master file until \\
    while($line = <INPUT_MASTER_FILE>) {
        if ($line =~ m/^LOCUS\s+(\S+)\s+(.+)/){
            print "LOCUS       " ,$1, " 9999 bp ", $2,"\n";
        }
        elsif ($line =~ m/^\s\s\s\s\ssource/){
                print "     source          1..1\n";
        }
        elsif ($line !~ m/^\/\//){
            print $line;
        }
    }
    
    # Add header MGA VAR to > line in variable file and output only these lines
    # >AAAAA0000001|BC1004AA60F1902|1||||
    # gcggaagtcggaccggtcgc
    # //
    while($line = <INPUT_VARIABLE_FILE>) {
      if ($line =~ m/^>/){
        print "MGA VAR     ",$line;
      } elsif ($line !~ m/^\/\//){
        print "            ",$line;
      }
    }
    print "//";
}
