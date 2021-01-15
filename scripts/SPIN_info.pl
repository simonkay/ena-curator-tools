#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/SPIN_info.pl,v 1.2 2006/10/31 11:25:29 gemmah Exp $
#
#  (C) EBI 2004
#
#  Written by Guy Cochrane/Philippe Aldebert
#
#  DESCRIPTION:
#  
# Converts submitter contact information from downloaded SPIN file into 
# Webin-type info file
#
#  MODIFICATION HISTORY:
#
# 27-FEB-2004  Guy          : version 1
#
# 29-SEP-2004  Philippe     : Telephone number used to appear in AD4 line 
#                             of output file - bug fixed
#
###############################################################################


use strict;
use DirHandle;

my ($i);

my $AD1 = "";
my $AD2 = "";
my $AD3 = "AD3:";
my $AD4 = "AD4:";
my $AD5 = "AD5:";
my $AD6 = "AD6:";
my $EML = "";
my $file = "";
my $FNM = "";
my $name = "";
my $SUR = "";
my $TEL = "";

my @files = &get_file_list;
my @lines = ();

foreach $file (@files) {
open ( IN, "< $file" ) or die ( "Couldn't open sub file $file!\n" );
@lines = <IN>;
close IN;

open ( OUT, ">$name.info" ) or die ( "Couldn't open file $name.info: $!.\n" );


for ($i = 0; $i <= $#lines; $i++) {
    if ( $lines[$i] =~ /^First name : (.+)/ ) {
        $FNM = "FNM: $1";
    }
    if ( $lines[$i] =~ /^Last name : (.+)/ ) {
        $SUR = "SUR: $1";
    }
    if ( $lines[$i] =~ /^Department : (.+)/ ) {
        $AD1 = "AD1: $1";
    }
    if ( $lines[$i] =~ m/^Address : (.+)/ ) {
        $AD2 = "AD2: $1";
        if ( ( $lines[$i+1] !~ /^Country :/ ) && ( $lines[$i] !~ /^Telephone :/ ) && ( $lines[$i] =~ /^E-mail :/ ) ) {
            $AD3 = "AD3: $lines[$i+1]";
            chomp $AD3;
        }
        if ( ( $lines[$i+2] !~ /^Country :/ ) && ( $lines[$i] !~ /^Telephone :/ ) && ( $lines[$i] =~ /^E-mail :/ ) ) {
            $AD4 = "AD4: $lines[$i+2]";
            chomp $AD4;
        }
        if ( ( $lines[$i+3] !~ /^Country :/ ) && ( $lines[$i] !~ /^Telephone :/ ) && ( $lines[$i] =~ /^E-mail :/ ) ) {
            $AD5 = "AD5: $lines[$i+3]";
            chomp $AD5;
        }
    }
    if ( $lines[$i] =~ /^Country : (.+)/ ) {
        $AD6 = "AD6: $1";
        chomp $AD6;
    }
    if ( $lines[$i] =~ /^Telephone : (.+)/ ) {
        $TEL = "TEL: $1";
    }
    if ( $lines[$i] =~ /^E-mail : (.+)/ ) {
        $EML = "EML: $1";
    }
}


sub get_file_list {
    my $dh = DirHandle->new ( "." ) || die "cannot opendir: $!"; 
    my @list = $dh->read ();
    foreach $file ( @list ) {
        if ( $file =~ /^(\w+)\.pep$/i ) {
            $name = $1;
            push (@files, $file);
        }
    }
    return @files;
}

print OUT "WID: na\nWIP: na\nSBT: F\n$FNM\nINI:\n$SUR\n$AD1\n$AD2\n$AD3\n$AD4\n$AD5\n$AD6\n$EML\n$TEL";

close OUT;
}
