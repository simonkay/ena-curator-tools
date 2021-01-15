#!/ebi/production/seqdb/embl/tools/bin/perl -w

#$Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/patents/find_three_letter.pl,v 1.2 2007/07/06 15:51:11 gemmah Exp $

use strict;
use DBI;
use dbi_utils;
use Utils qw(my_open_gz my_open);

# find three-letter code sequences in patent entries. input file should be in EMBL format.
# reports any sequence that have more than 75% valid three-letter code

@ARGV == 2 || die "\n USAGE: $0 <user>/<passwd>@<db> <patentfilename> \n\n";
my $login = $ARGV[0];
my $fname = $ARGV[1];
my $outfile = $fname."_report";
my $fh;
my $three_letter = 'N';


if ($fname =~ /\.gz/){	
    $fh = my_open_gz ("<$fname");
}
else {
    $fh = my_open ("<$fname");
}

open ( OUT, ">$outfile" ) || die ( "can't open $outfile: $!\n" );

printf OUT "%-15s%-20s%-15s\n", "acc number", "patent number", "three-letter-code(%)";
print OUT "-------------------------------------------------------\n";

my %abbrev_letter = get_code ();

my $mol_type = '';
my $ac = '';

my %records;

while (<$fh>) {
  
    if (/^ID   (\S+)\; \SV \d+\; \w+\; (\w+)\;/){
       $ac = $1;
       $mol_type = $2;
    }
    
    if ($mol_type eq "protein") {
       
	if (/^RL   Patent number/){
	   
	    $records{$ac}{rl} = $_;
	}

	if (/^SQ   Sequence/){
            my $seq = '';

	    while (<$fh>){
		
		last if (/^\/\//);
		$seq .= $_;
	    }

	    $seq =~ s/\d+//g;
	    $seq =~ s/\s//g;
	    $records{$ac}{sequence} = $seq;
	}
    }	        
}    
    
foreach my $ac (keys (%records)){

    my $seq_len = length ($records{$ac}{sequence});
    my $result = $seq_len / 3;
    my $percent;

    if ($result !~ /\d+\.d+/){

	$percent = check_three_letter ($records{$ac}{sequence}, $seq_len);
    }

    if ($percent > 75){	
	$three_letter = 'Y';
	my $patent_num;
	if ($records{$ac}{rl} =~ /RL   Patent number (.+)\,/){

	    $patent_num = $1;
	}
	printf OUT "%-15s%-20s%-15s\n", $ac, $patent_num, $percent;
    }   
}

if ($three_letter eq 'Y') {

    print "INFO: some entries may have three-letter code, please check $outfile\n\n";
}
else {

    print "INFO: no three-letter code found in the file $fname\n\n";
}

close ($fh);
close (OUT);


sub get_code {

    my $dbh = dbi_ora_connect ($login);
    my %abbrev_letter;
    my @table =  dbi_gettable ($dbh, "select upper (abbrev), letter
                                        from cv_aminoacid
                                       where letter is not null");
    
    foreach my $row (@table){

	my ($abbrev, $letter) = @$row;
	$abbrev_letter{$abbrev} = $letter;
    }
    dbi_logoff ($dbh);
    return %abbrev_letter;
}

 
sub check_three_letter {

    my ($seq, $seq_length) = @_;
    
    my $valid_count = 0; 
    my $invalid_count = 0;
    my $percent;

    for (my $i = 0; $i < $seq_length; $i += 3){

	my $amino_ac = substr ($seq, $i, 3);

	if (my $letter = $abbrev_letter{uc $amino_ac}){
	  
	    $valid_count++;
        }
	else {

	    $invalid_count++;
	}
    }
    
    if ($invalid_count == 0){
	$percent = 100;
    }
    else {

	$percent =  int (($valid_count / ($valid_count + $invalid_count)) * 100);
    }
   
    return ($percent);
}





