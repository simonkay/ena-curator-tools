#!/ebi/production/seqdb/embl/tools/bin/perl

#--------------------------------------------------------------------------------
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/sqninfo.pl,v 1.16 2011/11/29 16:33:38 xin Exp $
#
# sqninfo.pl: creates .info file from sequin input; loadable via loadsubinfo.pl
# into the database
#
# created by Peter Sterk
# 19-JUN-2001 Carola Kanz      * added SBT line ( submission_tool=sequin )
#                              * small changes to allow .info file being loaded
#                                by loadsubinfo.pl
# 20-JUN-2001 Carola Kanz      give error message if field exceeds max length in
#                              submission_details table
# 09-Aug-2001 Peter Stoehr     usage notes
# 19-MAR-2003 Carola Kanz      * changed order to match order in webin .info files
#                              * deleted fax
# 04-JUL-2003  Quan Lin        * removes Microsoft carriage return characters
#                              * combine city with postcode to one line
#                              * convert country name that's not written with correct
#                                letter cases
#                              * fixed a bug with the initial
#                              * now can cope with ad1 written in two lines
#                              * if ad2 is longer that 40, move down to ad3 and
#                                if ad3 is longer than 40, move down to ad4
#
# 05-JUL-2006 Nadeem Faruque   * No longer makes CNF: and HLD lines for use by ftsort3.pl
#
#--------------------------------------------------------------------------------

my $usage =
  "\n PURPOSE: Creates and writes a *.info file from a *.sqn file\n\n"
  . " USAGE:   $0 <inputfile>\n\n"
  . "          <inputfile>  where inputfile is the name of the sequin file\n\n";

@ARGV == 1 || die $usage;

$inputfile = $inputfile_no_ext = $ARGV[0];
$inputfile_no_ext =~ s/\..*//;
$outputfile = "${inputfile_no_ext}.info";
open( SQNFILE, "$inputfile" ) || die ("Can't open file \n");
open( SQNINFO, ">$outputfile" ) || ("Can't write file \n");
$br        = "\n";
$fnm       = "FNM:$br";
$sur       = "SUR:$br";
$ini       = "INI:$br";
$ad1       = "AD1:$br";
$ad2       = "AD2:$br";
$ad3       = "AD3:$br";
$ad4       = "AD4:$br";
$ad5       = "AD5:$br";
$ad6       = "AD6:$br";
$eml       = "EML:$br";
$tel       = "TEL:$br";
$sbt       = "SBT:S$br";    # constant: submission_tool=sequin
$is_street = 0;

while (<SQNFILE>) {
    chomp;
    s/\r//g;

    if (/phy-set/) {
        print STDOUT "ATTENTION - possible alignment!\n\n";
    }

    if ( /^Seq-submit/ ... /^\s+cit \{/ ) {
        if (/^ +last \"/) {
            $sur = $_;
            $sur =~ s/^ +last \"(.+)\" ,/SUR:\1${suf}$br/;
        }
        if (/^ +first \"/) {
            $fnm = $_;
            $fnm =~ s/^ +first \"(.+)\" ,/FNM:\1$br/;

        }
        if (/^ +initials \"/) {
            $ini = $_;
            $ini =~ s/^ +initials \"(.*)\.*(.*)\.*\"[ \}]* ,/INI:\1$br/;
        }
        if (/^ +suffix \"/) {
            $suf = $_;
            $suf =~ s/^ +suffix \"(.*)\"[ \}]* ,/ \1/;
            $sur =~ s/\n//m;
            $sur = $sur . $suf . "\n";
        }
        if (/^ +affil \"/) {
            $ad1 = $_;

            # if there are two lines
            while (<SQNFILE>) {

                last if (/^ +div \"/);
                last if (/^ +city \"/);    # if div is missing from the file
                chomp;
                s/\r//g;
                $ad1 = $ad1 . $_;

            }
            $ad1 =~ s/^ +affil \"(.+)\"[ \}]* ,/AD1:\1$br/;
        }
        if (/^ +div \"/) {
            chomp;
            s/\r//g;
            $ad2 = $_;

            # if there are two lines
            while (<SQNFILE>) {
                last if (/^ +city \"/);
                chomp;
                s/\r//g;
                $ad2 = $ad2 . $_;
            }

            $ad2 =~ s/^ +div \"(.+)\"[ \}]* ,/AD2:\1$br/;

            $len = length($ad2);
            ( $ad2, $ad2_extra ) = check_length($ad2);

            #   $ad2_extra =~ s/\s/\,/;
            chomp $ad2_extra;
            if ( $len > 44 ) {
                $ad2_extra = "$ad2_extra ";    # if length is more than 44, add a space
            }

        }

        # ad3 when street info is missing
        if ($ad2_extra) {
            $ad3_nostreet = "AD3:$ad2_extra\n";
        }
        elsif ( !$ad2_extra ) {
            $ad3_nostreet = "AD3:\n";
        }

        # ad3 when street info is present
        if (/^ +street \"/) {
            $ad3 = $_;
            $ad3 =~ s/^ +street \"(.+)\"[ \}]* ,/AD3:$ad2_extra\1$br/;

            ( $ad3, $ad3_extra ) = check_length($ad3);
            $is_street = 1;
        }

        chomp $ad3_extra;
        $ad4 = "AD4:$ad3_extra\n";

        if (/^ +city \"/) {
            $ad5 = $_;
            $ad5 =~ s/^ +city \"(.+)\"[ \}]* ,/AD5:\1$br/;

        }
        if (/^ +sub \"/) {
            $sub = $_;
            $sub =~ s/^ +sub \"(.+)\"[ \}]* ,/, \1$br/;
            $ad5 =~ s/\n//m;
            $ad5 = $ad5 . $sub;
        }
        if (/^ +postal-code \"/) {
            $postcode = $_;
            $postcode =~ s/^ +postal-code \"(.+)\"[ \}]* ,/ \1$br/;
            $ad5      =~ s/\r//g;
            $ad5      =~ s/\n//g;
            $ad5 = $ad5 . $postcode;
        }
        if (/^ +country \"/) {
            $ad6 = $_;
            $ad6 =~ s/^ +country \"(.+)\"[ \}]* ,/\1$br/;
            $ad6 =~ s/U\.K\./United Kingdom/i;
            $ad6 =~ s/UK/United Kingdom/i;
            $ad6 =~ s/Scotland/United Kingdom/i;

            # make sure that each word in the country name starts with a upper case and
            # the rest are lower case
            @words = split ( /\s/, $ad6 );
            if ( $#words > 0 ) {
                foreach $word (@words) {
                    $word = lc $word;
                    $word = ucfirst $word;
                    $all .= "$word ";
                }
                $ad6 = "AD6:$all\n";
            }
            elsif ( $#words == 0 ) {
                $ad6 = lc $ad6;
                $ad6 = ucfirst $ad6;
                $ad6 = "AD6:$ad6";
            }
        }
        if (/^ +email \"/) {
            $eml = $_;
            $eml =~ s/^ +email \"(.+)\"[ \}]* ,/EML:\1$br/;
        }
        if (/^ +phone \"/) {
            $tel = $_;
            $tel =~ s/^ +phone \"(.+)\"[ \}]* ,/TEL:\1$br/;
        }
    }
}

# print SQNINFO "SUBMITTER DETAILS\n\n";
print SQNINFO $sbt, $fnm, $ini, $sur, $ad1, $ad2;
if ( $is_street == 1 ) {
    print SQNINFO $ad3;
}
else {
    print SQNINFO $ad3_nostreet;
}
print SQNINFO $ad4, $ad5, $ad6, $eml, $tel;

close(SQNFILE);
close(SQNINFO);

print "SUBMITTER DETAILS\n\n";
print $sbt, $fnm, $ini, $sur, $ad1, $ad2;

if ( $is_street == 1 ) {
    print $ad3;
}
else {
    print $ad3_nostreet;
}
print $ad4, $ad5, $ad6, $eml, $tel, "//\n\n";

## check if max. length allowed in Oracle is not exceeded
my %len = ( $fnm, 20, $ini, 10, $sur, 40, $ad1, 40, $ad2, 40, $ad3, 40, $ad4, 40, $ad5, 40, $ad6, 40, $eml, 80, $tlf, 30 );

foreach my $k ( keys %len ) {
    if ( length($k) > $len{$k} + 4 ) {    # max length in Oracle + header length
        print "ERROR field exceeds max. length of " . $len{$k} . " chars: $k";
    }
}

print "\nOutput written to ${inputfile_no_ext}.info\n\n";

#==========================================================
# list of subs
#==========================================================
sub check_length {

    ($line) = @_[0];
    $line1 = "";
    $line2 = "";

    if ( length($line) > 44 ) {
        @contents = split ( /\s/, $line );
        $cnt      = 0;

        foreach $val (@contents) {

            $line_length = length($line1) + length($val);

            if ( $line_length <= 42 ) {    # because a space and a ,is added after
                $line1 .= "$val ";
                $cnt++;
            }
            elsif ( $line_length > 43 ) {
                last;
            }
        }

        for ( $i = $cnt ; $i <= $#contents ; $i++ ) {
            $line2 .= "$contents[$i] ";
        }

        return ( "$line1\n", "$line2\n" );
    }
    else {
        return ( $line, "" );
    }
}
