#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# (C) EBI 2000
#
# MERGE_DUPLICATE_FEATURES.PL
# Merges duplicate features of NCBI and EMBL entries.
#
# MODIFICATION HISTORY:
#
# 02-MAR-2000 Katerina Tzouvara     Created.
# 15-MAR-2000 Nicole Redaschi       Testing and bug fixes.
# 10-Mar-2003 Katerina Tzouvara     
# 06-May-2003 Katerina Tzouvara     variation feature removed from excluded list
# 24-Oct-2003 Nadeem Faruque        ncbi BASE COUNT lines no longer needed
# 04-Nov-2003 Nadeem Faruque        variation features excluded again
#===============================================================================

use strict;

my ($input_file)        = $ARGV[0];
my ($output_file)       = $input_file . "_out"; 
my ($qual_continuation) = 0;
my ($key_continuation)  = 0;
my ($keys, $data, $qualifiers);
my ($key, $qualifier, $number);
my ($index, $i, $j);
my (%excluded) = ( "source", 1, "conflict", 1, "misc_difference", 1, "old_sequence", 1, "unsure", 1, "variation", 1);

open ( IN, $input_file ) || die "cannot open $input_file for reading";
open ( OUT, "> $output_file" ) || die "cannot create $output_file for writing";

while ( <IN> ) {

   # entry starts here
   if ( /^ID   / || /^LOCUS       / ) {

      print OUT $_;

      # read and print header 
      while ( <IN> ) {

	 print OUT $_;
	 last if ( /^FH   Key             Location\/Qualifiers/ ||
		   /^FEATURES             Location\/Qualifiers/ );
      }
     
      # reference to anonymous array and hash where the keys and the qualifiers 
      # are respectively stored is needed, as there may be more than one set of
      # features during the iterations
      $keys = []; 
      $data = {};
      $number = 0;

      # read features 
      while ( <IN> ) {
	 
	 last if ( /^XX/ || /^SQ   Sequence/ || /^BASE COUNT/ || /^ORIGIN/ || /^CONTIG/ );

	 # if it is a key line then ...
	 if ( /^FT {3}(\S+)\s+/ || /^ {5}(\S+)\s+/ ) {
	    
	    # if the previous key didn't have any qualifiers, and it does not already
	    # exist in %data, we need to set $data->{$key} to some value here, so that
	    # the key exists when we check in %data for duplicated keys.
	    if ( $key_continuation && ! ( defined $data->{$key} ) ) {

	       $data->{$key}{"index"} = 0;
	    }

	    $key = $_;

	    # prepend "#$number#" to $key in case it is on the excluded list
	    # (to make it unique)
	    if (defined $excluded{$1}) {
	       $number++;
	       $key =~ s/^/#$number#/;
	    }

	    # if we do not have this key line already we add $key to the  
	    # array referenced by $keys and set the qualifier $index to 0...
	    if ( ! ( defined $data->{$key} ) ) { 

	       push(@$keys, $key);
	       $index = 0;

	       # ... otherwise we obtain the $index needed to merge the qualifiers
	    } else {

	       $index = $data->{$key}{"index"};
	    }

	    # set the flags for key and qualifier continuation to appropriate values
	    $key_continuation  = 1; 
	    $qual_continuation = 0;

	    # else if it is a qualifier line ...
	 } elsif ( /^FT {19}\// || /^ {21}\// ) { 

             #ignore dbxref qualifier for the variation feature
	     if((/\/db_xref/ && $key =~ /variation/)){
		 next;
	    }
	    # read line and set continuation flags...
	    $qualifier = $_;   
	    $key_continuation = 0;
	    $qual_continuation = 1;
	    
	    # ... and check if the qualifier needs to be merged.
	    if (!(defined $data->{$key}{$qualifier})) {
 
	      	     
		  $index++;
		  $data->{$key}{$qualifier} = $index;
		  # need to save the $index value for future merging of qualifiers
		  $data->{$key}{"index"} = $index;	
	             
	    } 

	    # else if it is a continuation line
	 } elsif ( /^FT {19}[\S]/ || /^ {21}[\S]/ || /^ {22}[\S]/ ) { 

	    # if it is a qualifier remove old value in the hash key...
	    if ($qual_continuation == 1) {

	       delete $data->{$key}{$qualifier};
	       $qualifier .= $_;

	       # ... and substitute with new value if it doesnt exist 
	       if (!(defined $data->{$key}{$qualifier})) { 

		  $data->{$key}{$qualifier} = $index;
	       }

	       # if it is key continuation remove previous value from array...   
	    } else {

	       pop @$keys;
	       $key .= $_;

	       # ... and push the new one to the arrray if it is unique...
	       if (!(defined $data->{$key})) { 

		  push(@$keys, $key);

		  # ... otherwise obtain the $index for the merging of the qualifiers
	       } else {
		  
		  $index = $data->{$key}{"index"};
	       }
	    }
	 }

	 # this line is at the beginning of the features so it should be 
	 # printed before the features
	 if (/^FH/) {

	    print OUT $_;
	 }
      }
    
      # print features into output file
      for ($i = 0; $i <= $#{$keys}; $i++) {
	
	 $keys->[$i] =~ /^(?:\#\d+\#)?(.*)/s; # emacs doesn't like # without escape
	 print OUT $1;
	 delete $data->{$keys->[$i]}{"index"};
	 %{$qualifiers} = reverse %{$data->{$keys->[$i]}};

	 for ($j = 1; $qualifiers->{$j}; $j++) {
	    
	    print OUT $qualifiers->{$j};
	 }
      }
	
      # read and print sequence 
      if ($_) { # CONs do not have sequence as such
         print OUT $_;
      }

      while ( <IN> ) {

	 print OUT $_;
	 last if (/^\/\//);
      }
   }
}

close (IN) || die "cannot close file $input_file";
close (OUT) || die "cannot close file $output_file";    
