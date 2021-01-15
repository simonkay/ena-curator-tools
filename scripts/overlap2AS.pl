#!/ebi/production/seqdb/embl/tools/bin/perl -w

# Converts TPA record with overlapping TPA spans into output file with new AS
# lines that represent the overlapping regions. OS line and sequence is also
# included in the output file. The output file is thus suitable for tpav.

# To be used during TPA entry
# curation.

# Guy Cochrane, EBI, 6.12.03. cochrane@ebi.ac.uk

# complementary span calculations corrected, 10.11.03, Guy Cochrane

use strict;

my ($BN_temp_file)=$ARGV[0];
my ($output_file);
my @lines;
my $result;
my ($calculation, $calculation2, $length, $TSstring, $PSstring);
$result="No match found\n";

# Test AS line variables
my ($line_calculator_beyond, $line_calculator_upto, $count, $PSstart, $PSend, $TPASstart, $TPASend, $complementary, $primaryAC_SV);

my ($inner_count, $qPSstart, $qPSend, $qTPASstart, $qTPASend, $qcomplementary, $qprimaryAC_SV);

# Check appropriate usage
unless ($BN_temp_file) {
    die("No input file name provided.\nUsage: overlap2AS.pl input_file.\n");
}
unless (-e $BN_temp_file) {
    die("Input file $BN_temp_file not found.\n");
}

#capture OS line for TPAV
#system ("grep '^OS' $BN_temp_file > $BN_temp_file.overlaps");
system ("grep '^AS' $BN_temp_file > $BN_temp_file.overlaps");

#open source file
open (SOURCE,"$BN_temp_file.overlaps") or die ("File access error, filename: $BN_temp_file.overlaps.\n");
@lines= <SOURCE>;
close SOURCE;

#open output file
open ( OUTFILE,">$BN_temp_file.overlaps.temp") or die ("File access error, filename: $BN_temp_file.overlaps.temp\n");

# Outer loop
for $count(0..$#lines) {
#    print("starting outer loop: $count\n");
    # Grab test AS line
    chomp($lines[$count]);
    if ($lines[$count] =~ m/^AS\s\s\s(\d+)-(\d+)\s+(\w+.\d+)\s+(\d+)-(\d+)\s+(c?)/) {
#	print ("$count: $lines[$count]\n");
	$TPASstart=$1;
	$TPASend=$2;
	$primaryAC_SV=$3;
	$PSstart=$4;
	$PSend=$5;
#	        print("\n");
#               print("TPAstart\tTPASend\tPSstart\tPSend\tprimaryAC_SV\n");
#		print("$TPASstart\t$TPASend\t$PSstart\t$PSend\t$primaryAC_SV\n");
	if ($6=~ m/c/) {
	    $complementary="c";
	}
	else {
	    $complementary="";
	}
#	print("Outer: $TPASstart\t$TPASend\t$primaryAC_SV\t$PSstart\t$PSend\t$complementary\n");
    }
	else { 
#	    print ("$count: $lines[$count]\n");
	    die ("Count: $count.\nInvalid AS line has been detected in $BN_temp_file.\n");
	}

# Inner loop
    $line_calculator_upto=$count-1;
    $line_calculator_beyond=$count+1;
    unless ($count==0) {
	for $inner_count(0..$line_calculator_upto) {
#	print("starting inner loop 1: $inner_count\n");

	    #load up query array
	    if ($lines[$inner_count] =~ m/^AS\s\s\s(\d+)-(\d+)\s+(\w+.\d+)\s+(\d+)-(\d+)\s+(c?)/) {
#	print ("$inner_count: $lines[$inner_count]\n");
		$qTPASstart=$1;
		$qTPASend=$2;
		$qprimaryAC_SV=$3;
		$qPSstart=$4;
		$qPSend=$5;
		if ($6=~ m/c/) {
		    $qcomplementary="c";
		}
		else {
		    $qcomplementary="";
		}
#	print("Q: $qTPASstart\t$qTPASend\t$qprimaryAC_SV\t$qPSstart\t$qPSend\t$qcomplementary\n");
	    }
	    else { 
#	    print ("$count: $lines[$count]\n");
	    die ("Count: $count.\nInvalid AS line has been detected in $BN_temp_file (inner loop).\n");
	}
#test 1 and prepare output

if ($TPASstart<$qTPASstart) {
    if ($TPASend>$qTPASend) {$result=2;}
    else {if ($qTPASstart<$TPASend) {$result=3;}
          else {$result=0;}
      }
}
else { if ($TPASend<=$qTPASend) {$result=4;}
       else { if ($TPASstart<$qTPASend) {$result=1;}
	    else {$result=0;}
		    }
	     }
#print ("$result\n");


# end test 1 and prepare output


if ($result==1) {
    $length=$qTPASend-$TPASstart;
    $TSstring="$TPASstart-$qTPASend";
    $calculation=$PSstart+$length;
    $PSstring="$PSstart-$calculation";
    if ($complementary eq "c" or $complementary eq "C") {
	$calculation=$PSend-$length;
	$PSstring="$calculation-$PSend";}
printf ( OUTFILE "AS   %-15s %-20s %-14s %-1s\n", $TSstring, $primaryAC_SV, $PSstring, $complementary);
}

if ($result==2) {
    $length=$qTPASend-$qTPASstart;
    $calculation=($qTPASstart-$TPASstart)+$PSstart;
    $calculation2=$calculation+$length;
    $TSstring="$qTPASstart-$qTPASend";
    $PSstring="$calculation-$calculation2";
    printf ( OUTFILE "AS   %-15s %-20s %-14s %-1s\n", $TSstring, $primaryAC_SV, $PSstring, $complementary);
}

if ($result==3) {
    $length=$TPASend-$qTPASstart;
    $calculation=$PSend-$length;
    die("Error: TPA span may differs too much from primary span in length:\nAS lines should follow TPA length rules");
    $TSstring="$qTPASstart-$TPASend";
    $PSstring="$calculation-$PSend";
    if ($complementary eq "c" or $complementary eq "C") {
	$calculation=$PSstart+$length;
	$PSstring="$PSstart-$calculation";}
    printf ( OUTFILE "AS   %-15s %-20s %-14s %-1s\n", $TSstring, $primaryAC_SV, $PSstring, $complementary);
}

#if ($result==4) {
#    $length=$TPASend-$qTPASstart;
#    $calculation=$PSend-$length;
	    
#    print ("AS   $qTPASstart-$TPASend        $primaryAC_SV     $calculation-$PSend  $complementary\n");
#}



	    


	}
    }
# Inner loop 2
    unless ($count==$#lines) {
	for $inner_count($line_calculator_beyond..$#lines) {
#	    print("starting inner loop 2: $inner_count\n");
	    #load up query array
	    if ($lines[$inner_count] =~ m/^AS\s\s\s(\d+)-(\d+)\s+(\w+.\d+)\s+(\d+)-(\d+)\s+(c?)/) {
#	print ("$inner_count: $lines[$inner_count]\n");
		$qTPASstart=$1;
		$qTPASend=$2;
		$qprimaryAC_SV=$3;
		$qPSstart=$4;
		$qPSend=$5;
#	        print("\n");
#               print("qTPAstart\tqTPASend\tqPSstart\tqPSend\tqprimaryAC_SV\n");
#		print("$qTPASstart\t$qTPASend\t$qPSstart\t$qPSend\t$qprimaryAC_SV\n");
		if ($6=~ m/c/) {
		    $qcomplementary="c";
		}
		else {
		    $qcomplementary="";
		}
#test 2 and prepare output

if ($TPASstart<$qTPASstart) {
    if ($TPASend>$qTPASend) {$result=2;}
    else {if ($qTPASstart<$TPASend) {$result=3;}
          else {$result=0;}
      }
}
else { if ($TPASend<=$qTPASend) {$result=4;}
       else { if ($TPASstart<$qTPASend) {$result=1;}
	    else {$result=0;}
		    }
	     }
#print ("$result\n");




# end test 2 and prepare output

if ($result==1) {
    $length=$qTPASend-$TPASstart;
    $TSstring="$TPASstart-$qTPASend";
    $calculation=$PSstart+$length;
    $PSstring="$PSstart-$calculation";
    if ($complementary eq "c" or $complementary eq "C") {
	$calculation=$PSend-$length;
	$PSstring="$calculation-$PSend";}
    printf ( OUTFILE "AS   %-15s %-20s %-14s %-1s\n", $TSstring, $primaryAC_SV, $PSstring, $complementary);
}

if ($result==2) {
    $length=$qTPASend-$qTPASstart;
    $calculation=($qTPASstart-$TPASstart)+$PSstart;
    $calculation2=$calculation+$length;
    $TSstring="$qTPASstart-$qTPASend";
    $PSstring="$calculation-$calculation2";
    printf ( OUTFILE "AS   %-15s %-20s %-14s %-1s\n", $TSstring, $primaryAC_SV, $PSstring, $complementary);
}

if ($result==3) {
    $length=$TPASend-$qTPASstart;
    $calculation=$PSend-$length;
    if ($calculation < 1) {die("Error: TPA span may differs too much from primary span in length:\nAS lines should follow TPA length rules");}
    $TSstring="$qTPASstart-$TPASend";
    $PSstring="$calculation-$PSend";
    if ($complementary eq "c" or $complementary eq "C") {
	$calculation=$PSstart+$length;
	$PSstring="$PSstart-$calculation";}
    printf ( OUTFILE "AS   %-15s %-20s %-14s %-1s\n", $TSstring, $primaryAC_SV, $PSstring, $complementary);
}

#if ($result==4) {
#    $length=$TPASend-$qTPASstart;
#    $calculation=$PSend-$length;
#    print ("AS   $qTPASstart-$TPASend        $primaryAC_SV     $calculation-$PSend  $complementary\n");
#}


#	    print("Starting inner loop 2: $inner_count\n");
	    }
	    else { 
#	    print ("$count: $lines[$count]\n");
	    die ("Count: $count.\nInvalid AS line has been detected in $BN_temp_file (inner loop).\n");
	}
	}
    }
}
close OUTFILE;

#output file processing
system ("mv $BN_temp_file.overlaps.temp $BN_temp_file.overlaps");
system ("grep '^OS' $BN_temp_file > $BN_temp_file.overlaps.temp");
system ("cat $BN_temp_file.overlaps >> $BN_temp_file.overlaps.temp");
system ("rm $BN_temp_file.overlaps");

#add sequence to output file
my @SQwhole_line;
my $SQline_number;
system ("grep -n '^SQ' $BN_temp_file > $BN_temp_file.SQ_line");
open (SQLINE,"<$BN_temp_file.SQ_line");
    @SQwhole_line = <SQLINE>;
close SQLINE;
#print("$SQwhole_line[0]\n");
unless ($SQwhole_line[0] =~ m/(\d+):/) {die ("No sequence found in $BN_temp_file\n");}
$SQline_number=$1;
#print ("Line number = $SQline_number\n");
#print ("BN_temp_file is $BN_temp_file\n");
system ("tail +$SQline_number $BN_temp_file >> $BN_temp_file.overlaps.temp");
system ("rm $BN_temp_file.SQ_line");
#unless ($BN_temp_file =~ m/(BN\d+).dat/) {die ("Input file does not have BN accession number\n");}
#system ("mv $BN_temp_file.overlaps.temp $1.temp");



sub test {

SWITCH: {
    if (($qTPASstart < $TPASstart)&&($TPASstart < $qTPASend)&&($qTPASend < $TPASend)) {
	$result="5' overlap: $count, $inner_count\n";
#	print("$result");
    }
    last SWITCH;
#default
	$result="No match found: $count, $inner_count\n";
	print("$result");
	}
}


















# Create output file
#print ("Overlap AS lines have been created in file $BN_temp_file.overlaps.\n\n");

print ("Output file: overlap0.temp\n");
print ("Now run tpav to check overlap alignments\n");

system ("mv $BN_temp_file.overlaps.temp overlap0.temp");
