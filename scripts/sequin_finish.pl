#!/ebi/production/seqdb/embl/tools/bin/perl -w

#------------------------------------------------------------------------------#
# $Header:
#
# splitff_embl.pl
# USAGE: splitff_embl.pl <inputfile>
#
# simpler Version of Peter Sterks splitff.pl
# ( /ebi/services/tools/bulkload/scripts/splitff.pl )
# splits <inputfile> containing embl flatfiles into separate files for each
# entry; is used to split files created out of sequin submissions; deletes junk
# in front of first entry ( and junk between entries and after the last one,
# which does not appear in files created out of sequin submissions );
# files are named SEQUIN1.sub, SEQUIN2.sub etc, the <inputfile> is kept with the old
# filename
#
# 25-JUN-2001  Carola Kanz      created.
# 10-JUL-2001  Carola Kanz      * filenames 001.ffl, 002.ffl etc for 100 files
#                                 or more
#                               * parse sequin remains at the beginning of the
#                                 file for confidential/holddate and create
#                                 'HD *' line for confidential entries ( applies
#                                 to all entries in flatfile )
# 09-Aug-2001  Peter Stoehr      usage notes
# 08-JUL-2003  Quan Lin         * almost rewritten. The new version of the stoe
#                                 doesn't leave headers in the file any more.
#                               * works on multiple EMBL*.sqn files in the current
#                                 directory. Gets status and hold date from original
#                                 *.sqn files and splits multiple sequences in each
#                                 Sequin submissions into separate EMBL format flat files.
#                                 For confidential entries add hold date.Delete
#                                 gene feature if any. Print out a warning if status
#                                 and the hold date are diffrent in different submissions.
#                               * if a single file name is provided on the commond line
#                                 it just simply split it without adding any information.
# 06-OCT-2003  Quan Lin         * fixed a bug for splitting webin bulk submission files
# 15-OCT-2003  Quan Lin         * sequin_finish.pl has the functions specific for sequin files
#                                 taken out from splitff_embl.pl. The remaining splitff_embl.pl
#                                 will only be used to split the files without adding any info.
# 17-FEB-2005  Quan Lin         * for 1000 files or more, file format start from 0001.ffl
# 24-JUN-2005 Nadeem Faruque    * saves to SEQUINxxx.sub files not xxx.ffl
#                                 Suggests adding a ds history event
# 30-SEP-2005 Nadeem Faruque    * uses sprintf to do zero-padding of file names
#                                 sorts multiple sequin files into proper numeric order
#                                 Changed two misleading variable names
# 05-JUL-2006 Nadeem Faruque    * Multiple changes
#                                 Converts to new ID line
#                                 Absorbed sequin-specific ftsort3.pl activities
#                                 Makes log of processing
#                                 Deletes EMBL*.sqn files that it has used
#                                 Checks for concatenation in original sequin file
#                                 Only strips gene features if redundant
#                                 Moves the sequinID to the DE line
#                                 System calls replaced by lines of perl
#---------------------------------------------------------------------------------------#

use strict;
use DirHandle;

my $verbose = 0;
my $usage   =
  "\n PURPOSE: Converts Sequin submission flat files into EMBL format flat files.\n"
  . "          Does some reformatting, including creating correct HD line for\n"
  . "          confidential entries. Splits multiple entries from single or multiple\n"
  . "          Sequin submissions into separate flat files.\n"
  . "          Names the files SEQUIN1.sub, SEQUIN2.sub\n"
  . "          or SEQUIN01.sub, SEQUIN02.sub, etc.\n"
  . "          This script should be run for all\n"
  . "          Sequin submissions.\n\n"
  . "   USAGE: Do not supply a file name. The script will split all the EMBL*.sqn\n"
  . "          files in the directory.\n";

my $prefix = "EMBL";
my $SUFFIX = "sqn";

my %month2number = ( 'JAN' => '01',
                     'FEB' => '02',
                     'MAR' => '03',
                     'APR' => '04',
                     'MAY' => '05',
                     'JUN' => '06',
                     'JUL' => '07',
                     'AUG' => '08',
                     'SEP' => '09',
                     'OCT' => '10',
                     'NOV' => '11',
                     'DEC' => '12'
);

my $todaydig = ( ( (localtime)[5] + 1900 ) * 365 ) + ( ( (localtime)[4] + 1 ) * 30 ) + (localtime)[3];
open( LOG, ">sequin.report" ) || die "cannot create file sequin.report\n";
my %errors;

#=============================================================================
# Subroutines
#=============================================================================
#--------------------------------------------------------------------------------
# find_files get a sorted file list for a given extension
#----------------------------------------------------------------------------
sub find_files($$) {
    my $prefix    = shift;
    my $extension = shift;
    $extension =~ s/^\.//;    # remove any leading dot
    my $dh = DirHandle->new(".") || die "cannot opendir: $!";
    my @filesList = sort {
        my $aVal = $a;
        if ( $aVal =~ /(\D+)(\d+)\.$extension/ ) {
            $aVal = sprintf( "%s-%30d", $1, $2 );
        }
        my $bVal = $b;
        if ( $bVal =~ s/(\D+)(\d+)\.$extension// ) {
            $bVal = sprintf( "%s-%30d", $1, $2 );
        }
        $aVal cmp $bVal;
    } grep { -f } grep { /^$prefix.*\.$extension$/ } $dh->read();
    return @filesList;
}

#-------------------------------------------------------------------------
# sub get_status_info get status and hold date from original .sqn files
#------------------------------------------------------------------------
sub get_status_info(@) {
    my @files = @_;
    my %status_data;
    my (@number2month) = ( 'UNK', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC' );
    foreach my $file (@files) {
        $file =~ s/^$prefix//;    #get the original file name
        my $sequinPartsInFile = 0;
        open( SEQUINFILE, "< $file" ) || die "cannot open $file: $!\n";
        my $confi_status = 0;
        my $year         = "0000";
        my $month        = "UNK";
        my $day          = "0";
        print "Opening $file\n";

        while (<SEQUINFILE>) {
            if (/Seq-submit ::=/) {
                $sequinPartsInFile++;
            }
            elsif ( /^ +reldate/ ... /^ +tool +\"Sequin/ ) {
                $confi_status = 1;
                if (/^ +year (\d{4})/) {
                    $year = $1;
                }
                elsif (/^ +month (\d+)/) {
                    if ( ( $1 < 0 ) || ( $1 > 12 ) ) {
                        print "$file has a odd month in the line, \"$1\"\n";
                        $month = "UNK";
                    }
                    else {
                        $month = $number2month[$1];
                    }
                }
                elsif (/^ +day (\d{1,2})/) {
                    $day = $1;
                }
            }
        }
        if ( $sequinPartsInFile > 1 ) {
            die "The original Sequin file $file appears to be $sequinPartsInFile sequin files stuck together\n"
              . "You should split this (Sequin files begin with \"Seq-submit\")\n"
              . " delete your EMBL*.sqn files\n"
              . " and rerun the previous step (stoe)\n\n";
        }
        if ( $confi_status eq "0" ) {
            $status_data{$file} = "Standard\n";
        }
        else {
            $status_data{$file} = sprintf( "Confidential %02d-%s-%s", $day, $month, $year );
        }
        close(SEQUINFILE);
    }
    return %status_data;
}

#--------------------------------------------------------------------------------
# clean_and_stringify_references for a pointer to an array or references, add . to end of 'Submitted By', and trim author list
#----------------------------------------------------------------------------
sub clean_and_stringify_references(\@) {
    my $references    = shift;
    my $submissionRef = 0;
    my $submitterName;
    for ( my $i = 0 ; $i < scalar(@$references) ; $i++ ) {
        if ( @$references[$i] =~ /^RL   Submitted/m ) {
            $submissionRef = $i;
            @$references[$i] =~ s/\.*$/./s;
            if ( @$references[$i] =~ s/RA   ([^,]+),([^;]*);/RA   $1;/s ) {
                my $extraAuthors = $2;
                $extraAuthors =~ s/ *\nRA   / /s;
                $errors{"  * WARNING: additional submission names discarded $extraAuthors\n"} = 1;
            }
            if ( @$references[$i] =~ /RA   ([^,;]+)/ ) {
                $submitterName = $1;
                @$references[$i] =~ s/(EMBL\/GenBank\/DDBJ databases\. *\nRL   )/$1$submitterName, \nRL   /s;    # add author name to address!
            }
        }
        else {
            @$references[$i] =~ s/RP   ([^\n]+)\n//mg;
        }
    }
    my $refNumber       = 1;
    my $referencesBlock = "RN   [$refNumber]\n" . @$references[$submissionRef] . "XX\n";
    for ( my $i = 0 ; $i < scalar(@$references) ; $i++ ) {
        if ( $i != $submissionRef ) {
            $refNumber++;
            $referencesBlock .= "RN   [" . $refNumber . "]\n" . @$references[$i] . "XX\n";
        }
    }
    return $referencesBlock;
}

#--------------------------------------------------------------------------------
# clean_and_stringify_features for a pointer to an array or features, strip unwanted gene features
#----------------------------------------------------------------------------
sub clean_and_stringify_features(\@) {
    my $features = shift;
    my %geneFeatureUseful;
    my $geneFeaturesStripped = 0;

    # get location of gene features
    foreach my $feature (@$features) {
        if ( $feature =~ /^FT   gene +([^\/]+)/s ) {
            my $location = $1;
            $location =~ s/^FT +//mg;
            $geneFeatureUseful{$location} = 1;
        }
    }

    # find locations on non-gene and non-source features and see if they make the gene features redundant
    foreach my $feature (@$features) {
        if ( $feature =~ /^FT   (\S+) +([^\/]+)/s ) {
            if ( ( $1 ne "gene" ) && ( $1 ne "source" ) ) {
                my $location = $2;
                $location =~ s/^FT +//mg;

                # gene feature deemed redundant if another feature has same location
                if ( defined( $geneFeatureUseful{$location} ) ) {
                    $geneFeatureUseful{$location} = 0;
                }
            }
        }
        else {
            print "I've made a mess with the feature :\n$feature";    # should never happen.
        }
    }
    my $featureTable = "";
    foreach my $feature (@$features) {
        if ( $feature =~ /^FT   gene +([^\/]+)/s ) {
            my $location = $1;
            $location =~ s/^FT +//mg;
            if ( $geneFeatureUseful{$location} == 1 ) {
                $featureTable .= $feature;
            }
            else {
                $geneFeaturesStripped++;
            }
        }
        else {
            $featureTable .= $feature;
        }
    }
    if ( $geneFeaturesStripped > 0 ) {
        my $pluraity = "";
        if ( $geneFeaturesStripped > 1 ) {
            $pluraity = "s";
        }
        print LOG "  $geneFeaturesStripped gene feature$pluraity stripped when I made:\n";
    }
    return $featureTable;
}

#--------------------------------------------------------------------------------
# sequin_finish main
#----------------------------------------------------------------------------
sub sequin_finish() {
    my $time1;

    $time1 = (times)[0];
    $verbose
      && print "Finding suitable files";
    my @embl_files = find_files( $prefix, $SUFFIX );
    $verbose
      and printf " took %.2f CPU seconds\n\n", (times)[0] - $time1;

    if ( !@embl_files ) {
        die $usage;
    }

    #get status and hold date from original *.sqn files
    $time1 = (times)[0];
    $verbose
      && print "Finding equivalent original Sequin files";
    my %status_data = get_status_info(@embl_files);
    $verbose
      and printf " took %.2f CPU seconds\n\n", (times)[0] - $time1;

    $time1 = (times)[0];
    $verbose
      && print "Counting entries";
    my $total_entry_count = 0;    # total number of .sub files to produce
    foreach my $file (@embl_files) {
        my $entryCount = 0;
        open( READEMBL, "<$file" ) || die "cannot open $file: $!\n";
        while (<READEMBL>) {
            if (/^ID   /) {
                $entryCount++;
            }
        }
        close(READEMBL);
        print "$file has $entryCount entries\n";
        $total_entry_count += $entryCount;
    }
    $verbose
      and printf " took %.2f CPU seconds\n\n", (times)[0] - $time1;

    my $entry_number = 0;    # current entry number

    # if there are EMBL*.sqn files in the directory, we need to split, add hold date for
    # confidential entries and delete gene features if any
    my $conf = 0;
    my ( $status, $holddate, $original_name );

    foreach my $embl_file (@embl_files) {

        #find out if the entries in this file is confidential and get hold date
        $original_name = $embl_file;
        $original_name =~ s/^$prefix//;
        if ( !defined( $status_data{$original_name} ) ) {
            die "Original Sequin file, $original_name was not read\n";
        }
        ( $status, $holddate ) = split ( /\s/, $status_data{$original_name} );
        if ( $status eq "Confidential" ) {
            $conf = 1;
        }
        elsif ( $status eq "Standard" ) {
            $conf = 0;
        }
        open( IN, $embl_file ) || die "cannot open $embl_file\n";

        # entry-based variables for use when scanning reading the file
        # require blanking at the end of every entry.
        # in hindsight I should have peeked ahead in the file to get mol_type instead of storing everything in array entryInHand
        my $sequinID = "";    # Sequin UID placed where old ENTRYNAME is
        my @entryInHand;      # list of lines for new file
        my $mol_type = "unknown";    # mol_type from FT
        my @references;              # citations
        while (<IN>) {
            if (/^ID   /) {
                $entry_number++;
		my $topology = "linear";
		my $sequenceLength = 0;
##		           $1=ID   $2=state   $3     $4 = mol_type    $5         $6
                if (/^ID   ([^;]+) +([^;]+); *(circular *)?([^;]+) *; *([^;]+) *; *(\d+) *BP\. *$/) {
                    $sequinID = $1;
                    if ( defined($3) ) {
                        $topology = "circular";
                    }
		    $sequenceLength = $6;

# Need to cope with new bad ID line type
# ID   MU15ma-matK21aF standard; ; UNA;
                } elsif (/^ID   ([^; ]+)[ ;]+([^;]+); *(circular *)?([^;]+) *;.*$/) {
		    print "Coping with bad ID line, $_";
		    my $badIdLine = $_;
                    $sequinID = $1;
                    if ( defined($3) ) {
                        $topology = "circular";
                    }
		    my $filePosition = tell(IN); # Need to peek ahead in the file for sequence length
		    while (<IN>) {
			if (/^SQ   Sequence (\d+) BP/) {
			    $sequenceLength = $1;
			    last;
			}
		    }
		    if ($sequenceLength == 0) {
			die "Could not find the sequence length on an SQ line in that entry\n";
		    }
		    seek( IN, $filePosition, 0);
		    $_ = $badIdLine;
		} else {
                    die " Could not understand ID line in $embl_file, entry $entry_number:\n$_\n";
                }
		$_ = "ID   XXX; XXX; $topology; \tMOL_TYPE\t; XXX; XXX; $sequenceLength BP.\n";
		
		if ( $conf == 1 ) {
		    ## add 'HD *' line containing hold date
		    $_ .= "XX\nST * draft $holddate\n";
		}
		else {
		    $_ .= "XX\nST * draft\n";
		}
            }

            # add sequin ID to the end of the DE
            if (/^DE   /) {
                push ( @entryInHand, $_ );
                while (<IN>) {
                    if ( $_ !~ (/^DE   /) ) {
                        $sequinID =~ s/(^\s+)|(\s+$)//g;
                        push ( @entryInHand, "DE   (SequinID: $sequinID)\n" );
                        last;
                    }
                    push ( @entryInHand, $_ );
                }
            }
            if (/^DT   /) {
                next;    # discard
            }
            if (s/^AC   .*$/AC   ;/) {

                # clean AC line
            }
            if (/^RN   /) {    # reference block has started
                my @references;
                my $currentReference;
                while (<IN>) {    # all Ref block lines begin with an R and each reference is separated by XX
                    if ( (/^XX/) && ( $currentReference ne "" ) ) {

                        # end of reference
                        push ( @references, $currentReference );
                        $currentReference = "";
                        next;
                    }
                    if ( $_ !~ /^[RX]/ ) {

                        # end of reference block
                        last;
                    }
                    elsif (/^RN   /) {
                        next;    # strip the RN lines
                    }
                    else {
                        $currentReference .= $_;
                    }
                }
                my $referenceBlock = clean_and_stringify_references(@references);

                # Check date
                if ( $referenceBlock =~ /RL   Submitted \((\d{2})-(\w{3})-(\d{4})\)/ ) {
                    my $submdig = ( $3 * 365 ) + ( $month2number{$2} * 30 ) + $1;
                    if ( ( $todaydig - $submdig ) > 7 ) {
                        $errors{"\n*** Old Sequin file submission date - $1-$2-$3 ***** \n"} = 1;
                    }
                }
                push ( @entryInHand, $referenceBlock );
            }

            if (/^FT/) {    # feature table has started
                my @features;
                my $currentFeature .= $_;
                while (<IN>) {
                    if (/\/mol_type="([^\"]+)"/) {
                        $mol_type = $1;
                    }
                    if ( ( $_ !~ /^FT    / ) && ( $currentFeature ne "" ) ) {

                        # end of feature
                        push ( @features, $currentFeature );
                        $currentFeature = "";
                    }
                    if ( $_ !~ /^FT   / ) {

                        # end of FT
                        last;
                    }
                    else {
                        $currentFeature .= $_;
                    }
                }
                my $featureTable = clean_and_stringify_features(@features);

                # no current need to do this as two steps
                push ( @entryInHand, $featureTable );
            }

            push ( @entryInHand, $_ );
            if (/^\/\/$/) {
                $entryInHand[0] =~ s/\tMOL_TYPE\t/$mol_type/;
                my $file_name = "SEQUIN" . sprintf( "%0" . length($total_entry_count) . "s", $entry_number ) . ".sub";
                open( OUTFILE, ">$file_name" ) || die "cannot create file $file_name\n";
                print OUTFILE join ( "", @entryInHand );
                close(OUTFILE);
                print LOG " $original_name:$sequinID -> $file_name\n";

                # Blank-out entry-based variables, no need to undef since we'll probably reuse them
                $sequinID       = "";
                @entryInHand    = ();
                $mol_type       = "";
                @references     = ();
            }
        }
        close(IN);
    }

    # if status and hold date are different in the original *.sqn file print out
    # a warning. - PROBABLY NEEDS TO BE SAVED AS A FILE
    if (%status_data) {
        my %statuses;
        foreach $status ( values(%status_data) ) {
            $statuses{$status} = 1;
        }
        if ( scalar( keys %statuses ) > 1 ) {
            foreach my $state ( keys %statuses ) {
                $errors{ "*** WARNING: multiple sequin files contain different state and/or hold date: " . $state . "\n" } = 1;
            }
        }
    }
    print "$total_entry_count sub files created\n\n";

    print LOG "$total_entry_count sub files created\n\n#######################\n# Errors and Warnings #\n#######################\n";

    foreach my $error ( sort keys %errors ) {
        print LOG $error;
        print $error;
    }

    # Suggest adding the desired info to the ds history table
    if ( $total_entry_count > 25 ) {
        print "\nBulk submission of $total_entry_count so add the history event in forms or by executing:-\n";
        if ( $ENV{"PWD"} =~ /ds_test/ ) {
            print "dsHistoryDev -e=bulk \'$total_entry_count entries received - passed to \'\n";
        }
        else {
            print "dsHistory -e=bulk \'$total_entry_count entries received - passed to \'\n";
        }
    }
    foreach my $emblFileName (@embl_files) {
        unlink $emblFileName || print "Intermediate file $emblFileName could not be deleted:\n$!";
    }
}

#=================================================================================================================================

sequin_finish;
close(LOG);
