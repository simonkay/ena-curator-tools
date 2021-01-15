#!/ebi/production/seqdb/embl/tools/bin/perl -w

# chll - warns if line length exceeds 80 characters: 
# prints line number and length
# usage cll.pl <filename(s)> - wildcards allowed
# Version 1.0 - Peter Sterk

die "Usage: chll.pl <inputfile(s)>\n" unless @ARGV;
print "\nLines exceeding 80 characters (excluding newline):";

$header = " LINE#  LENGTH  FIRST 64 CHARACTERS\n------  ------  ----------------------------------------------------------------\n";

format =
@>>>>> @>>>>>>  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$., $line_length, $first_64_chars
.

while (<>) {
    chomp;
    if ($. == 1) {
	print "\n\n*** $ARGV ***\n";
	print $header;
    }
    if (($line_length = length) > 80) {
	$first_64_chars = substr ($_, 0, 64);
	write;
    }
    if (eof) {
        close ARGV;
    }
}
