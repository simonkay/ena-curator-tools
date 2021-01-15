#!/ebi/production/seqdb/embl/tools/bin/perl -w

# sqninfo.pl extracts submitter details and hold date
# information from sequin asn.1 file


use strict;

my $inputfile = my $inputfile_no_ext = $ARGV[0];
$inputfile_no_ext =~ s/\..*//;
my $outputfile = "${inputfile_no_ext}.info";       

open(SQNFILE,"$inputfile") || die ("Can't open file \n");
open(SQNINFO,">$outputfile") || ("Can't write file \n");

my $br = "\n";
my $fnm="FNM:$br";
my $sur="SUR:$br";
my $ini="INI:$br";
my $ad1="AD1:$br";
my $ad2="AD2:$br";
my $ad3="AD3:$br";
my $ad4="AD4:$br";
my $ad5="AD5:$br";
my $ad6="AD6:$br";
my $eml="EML:$br";
my $tel="TEL:$br";
my $fax="FAX:$br";
my $cnf="CNF:N$br";
my $hld="HLD:$br";
my ($suf,$sub,$year,$month,$day);

my %months = (
           '1' => 'JAN',
           '2' => 'FEB',
           '3' => 'MAR',
           '4' => 'APR',
           '5' => 'MAY',
           '6' => 'JUN',
           '7' => 'JUL',
           '8' => 'AUG',
           '9' => 'SEP',
          '10' => 'OCT',
          '11' => 'NOV',
          '12' => 'DEC');



while (<SQNFILE>) {
    chomp;
    if (/phy-set/) {
        print STDOUT "ATTENTION - possible alignment!\n\n";
    }

 if (/^Seq-submit/.../^    cit \{/) {  
    if (/^ +last \"/) {
        $sur = $_;
        $sur =~ s/^ +last \"(.+)\" ,/SUR:$1${suf}$br/; 
    }
    if (/^ +first \"/) {
        $fnm = $_;
        $fnm =~ s/^ +first \"(.+)\" ,/FNM:$1$br/;
    }
    if (/^ +initials \"/) {
        $ini = $_;
        $ini =~ s/^ +initials \"\w\.(.*)\"[ \}]* ,/INI:$1$br/;
    }
    if (/^ +suffix \"/) {
        $suf = $_;
        $suf =~ s/^ +suffix \"(.*)\"[ \}]* ,/ $1/;
        $sur =~ s/\n//m;
        $sur = $sur . $suf . "\n";
    }
    if (/^ +affil \"/) {
        $ad1 = $_;
        $ad1 =~ s/^ +affil \"(.+)\"[ \}]* ,/AD1:$1$br/;
    }
    if (/^ +div \"/) {
        $ad2 = $_;
        $ad2 =~ s/^ +div \"(.+)\"[ \}]* ,/AD2:$1$br/;
    }
    if (/^ +street \"/) {
        $ad3 = $_;
        $ad3 =~ s/^ +street \"(.+)\"[ \}]* ,/AD3:$1$br/;
    }
    if (/^ +city \"/) {
        $ad4 = $_;
        $ad4 =~ s/^ +city \"(.+)\"[ \}]* ,/AD4:$1$br/;
    }
    if (/^ +sub \"/) {
        $sub = $_;
        $sub =~ s/^ +sub \"(.+)\"[ \}]* ,/, $1$br/;
        $ad4 =~ s/\n//m;
        $ad4 = $ad4 . $sub;
    }
    if (/^ +postal-code \"/) {
        $ad5 = $_;
        $ad5 =~ s/^ +postal-code \"(.+)\"[ \}]* ,/AD5:$1$br/;
    }
    if (/^ +country \"/) {
        $ad6 = $_;
        $ad6 =~ s/^ +country \"(.+)\"[ \}]* ,/AD6:$1$br/;
        $ad6 =~ s/United Kingdom/UK/i;
        $ad6 =~ s/U\.K\./UK/i;
        $ad6 =~ s/Scotland/UK/i;
        $ad6 =~ s/Germany/FRG/i;
    }
    if (/^ +email \"/) {
        $eml = $_;
        $eml =~ s/^ +email \"(.+)\"[ \}]* ,/EML:$1$br/;
    }
    if (/^ +phone \"/) {
        $tel = $_;
        $tel =~ s/^ +phone \"(.+)\"[ \}]* ,/TEL:$1$br/;
    }
    if (/^ +fax \"/) {
        $fax = $_;
        $fax =~ s/^ +fax \"(.+)\"[ \}]* ,/FAX:$1$br/;
    }
}
    if (/^ +reldate/.../^ +tool \"Sequin/) {
        $cnf = "CNF:Y\n";
        if (/^ +year /) {
            $year = $_;
            $year =~ s/^ +year (\d{4}) ,/-$1/;
	}	
        if (/^ +month /) {
            $month = $_;
            $month =~ s/^ +month (\d\d?) ,/$months{$1}/;
	}
        if (/^ +day/) {
            $day = $_;
            $day =~ s/^ +day (\d{1,2}) \} ,/$1/;
            if ($day < 10) {
                $day = "0" . $day;
	    }
	}
    
    $hld = "HLD:" . $day . "-" . $month . $year . "\n";
}
}
print SQNINFO "SUBMITTER DETAILS\n\n";
print SQNINFO $fnm,$sur,$ini,$ad1,$ad2,$ad3,$ad4,$ad5,$ad6,$eml,$tel,$fax,$cnf,$hld,"//\n";

close(SQNFILE);
close(SQNINFO);

print "SUBMITTER DETAILS\n\n";
print $fnm,$sur,$ini,$ad1,$ad2,$ad3,$ad4,$ad5,$ad6,$eml,$tel,$fax,$cnf,$hld,"//\n\n";

print "Output written to ${inputfile_no_ext}.info\n\n";





