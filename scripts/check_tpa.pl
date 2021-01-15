#!/ebi/production/seqdb/embl/tools/bin/perl
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/check_tpa.pl,v 1.52 2013/10/08 14:52:37 blaise Exp $
#
#  (C) EBI 2002
#
#  Written by Vincent Lombard
#
#  DESCRIPTION:
#  Checks availability of entries (DDBJ/EMBL/GenBank and TI) used in a TPA 
#  submission.
#  Aligns submitted TPA span against submitted primary span.
#  Writes output to file valid.dat
# =================================
#  BUGS FIXES by  Blaise Sept 2013
# 1) protect single quote from organism names from breaking SQL constructs
# 2) Meaningful exit message when TAX id does not exist in DB
# 3) Change devt to enadev
# 4) Meaningfull exit message when flat file not retrieved
###############################################################################
#use lib '/nfs/gns/homes/blaise/dev/seqdb/tools/perllib/';
use strict;
use RevDB;
use DBI;
use dbi_utils;
use SeqDBUtils2;
use Data::Dumper;
use LWP::UserAgent;  # for advanced internet connections
use Cwd; # provided so module knows where to find the temp file

# global variables
my $quiet   = 0; # silent running
my $verbose = 0;
my $debug   = 0; # super verbose
my $alignwidth = 60;
my $showSummary = 0;
my $tsa         = 0;

select(STDOUT); $| = 1; # make unbuffered
select(STDERR); $| = 1; # make unbuffered

# paths
my $emboss_path = "/sw/arch/bin/EMBOSS";
my $pwd = "./";

#-------------------------------------------------------------------------------
# Usage   : usage(@ARGV)
# Description: populates global variables with commandline arguments (plus prints
# help text
# Return_type :none.  Global variable values are set
# Args    : @$args : list of arguments from the commandline.
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub usage(\@\@) {
    $debug && print " debug - running usage \n";

    my ( $arg, $usage, $opt_connStr, $file );

    my $args = shift;
    my $inputFiles = shift; # empty list

    $usage= "PURPOSE: Using the entries (DDBJ/EMBL/GenBank and TI) used in the\n"
        . "AS lines of a TPA/TSA to run stretcher (alignment program) to check if\n"
	. "these sequences line up with the TPA/TSA sequence as described.\n\n"
	."USAGE:   $0 <user/password\@instance> [-q(uiet)] [-v(erbose)] [-d(ebug)] [-w(idth)=<width>] [-s(ummary)] [-tsa] [TPA/TSA filename] [TPA filename]\n\n"
	."This script aligns submitted TPA/TSA span against submitted AS line\n"
        . "spans and writes output to <TPA/TSA filename>.val.\n"
	. "The script also compares /organism in TPA with /organism in all\n"
	. "contributing entries and writes output to taxonomy.log.\n\n"
	. "-w(idth)=<value> controls the width of the stretcher output (default width = 60).\n\n"
	. "-s(ummary) will display the summary found at the top of the .val file, on the command line.\n\n"
	. "-tsa denotes 1+ TSA sequences are being used as input. A TSA sequence is not allowed\n"
	. "     more than 5 consective n's and is not allowed more than 5% non-gcat letters.\n\n"
	. "<TPA/TSA filename> - if you want to use specific files to supply the primary accessions,\n"
	. "you can add them to the command-line, separated by spaces.\n\n";
    
    # handle the command line.
    foreach $arg ( @$args ) {
	if ( $arg =~ /^\/\@((enapro)|(enadev))/i ) {
	    $opt_connStr = $arg;
	} elsif ( $arg =~ /^\-v(erbose)?$/ ) {
	    $verbose = 1;
	} elsif ( $arg =~ /^\-d(ebug)?$/ ) {
	    $debug = 1;
	} elsif ( $arg =~ /^\-q(uiet)?$/ ) {
	    $quiet = 1;
	} elsif ( $arg =~ /^\-tsa$/ ) {
	    $tsa = 1;
	} elsif ( $arg =~ /^\-h(elp)?$/ ) {
	    die ( $usage );
	} elsif ( $arg =~ /^\-s(ummary)?$/ ) {
	    $showSummary = 1;
	} elsif ( $arg =~ /^\-w(idth)?=(\d+)$/ ) {
	    if ($2 > 10){
		$alignwidth = $2;
	    }
	} elsif ($arg !~ /^\-/) {
	    push(@$inputFiles, $arg);  # take in data filename(s)
	} else {
	    die ( "Do not understand the term $arg\n" . $usage );
	}
    }
    #quiet overrules other flags, but we can't mention anything because we are quiet
    if ($quiet){
	$verbose = 0;
	$debug   = 0;
    }
    $verbose && print "Verbose mode\n";
    $debug   && print " debug mode\n";

    foreach $file (@$inputFiles) {
        if (( ! (-f $file)) || (! (-r $file) )) {
            die "$file is not readable. Exiting script...\n";
        }
    }

    return($opt_connStr);
}

#-------------------------------------------------------------------------------
# Usage   : check_AS_line(@$inputFiles)
# Description: check the validity of the AS line
# Return_type : none
# Args    : $inputFiles : reference to an array of all input files
# Caller  : called in the main
#-------------------------------------------------------------------------------
 sub check_AS_line(\@) {
     $debug && print " debug - running check_AS_line\n";

     my ($ASlineFound, $totalASlineCounter, $file, $line, @file_with_AS_lines);

     my ($inputFiles) = @_;

     $totalASlineCounter = 0;     
     # parse all input files
     foreach $file (@$inputFiles) {

	 $verbose && print "checking AS lines in TPA file \"$pwd"."$file\"\n";
	 $ASlineFound = 0;
	 my_open_FH (\*TPA_IN, $pwd.$file);

	 while (<TPA_IN>) {
	     if (/^AS/) {
		 $line = $_;
		 if ($line !~ /^AS\s+\d+-\d+\s+\S+\s*(\d+-\d+|not_available)/) {
		     die ("$file AS invalid $line \ntpav aborted\n**************************************\n");
		 }
		 $ASlineFound = 1;
		 $totalASlineCounter++;
	     }
	     if (/^AS\s+(\d+)-(\d+)\s+(\S+)\s+((\d+)-(\d+)|not_available)/){ 
		 if ($1>$2){
		     die ("$file AS invalid $_ \ntpa span not valid\ntpav aborted\n**************************************\n");
		 }
		 elsif ($5 and $6) {
		     if ($5>$6) {
			 die ("$file AS invalid $_ \nprimary span not valid\ntpav aborted\n**************************************\n");
		     }
		 } 
		 else {
		     next;
		 }
	     }
	 }
	 close(TPA_IN);

	 if (!$ASlineFound) {
	     print "No AS lines were found in $file\n";
	 }
	 else {
	     push(@file_with_AS_lines, $file);
	 }
     }

     if (!$totalASlineCounter) {
	 die "\nNo AS lines were found in this ds directory.  Exiting script...\n\n";
     }
     else {
	 @$inputFiles = @file_with_AS_lines;
     }
 }


#-------------------------------------------------------------------------------
# Usage   : parse_flatfiles(@inputFiles, @submission, %associateSeqFiles, %organism)
# Description: extract details from input files in the ds directory
# Return_type : none.  @submission array is updated via a reference
# Args    :  @$inputfiles : reference to an array of all input files
#            @$submission: reference of an list containing input file details
#            %$associateSeqFiles: reference of a hash containing embl file names
# of primary sequence entries 
#            %$organism: reference to a hash of organisms
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub parse_flatfiles(\@\@\%\%) {
    $debug && print " debug - running parse_flatfiles\n";

    my ($ASnum, $file, $fileNum, $i, $wrappingDetected);

    my ($inputFiles, $submission, $associateSeqFiles, $organism) = @_;

    $fileNum=0;

    # parse all input file and create the submission array
    foreach $file (@$inputFiles) {

	my_open_FH (\*TPA_IN, $pwd.$file);
	$verbose && print "parsing TPA file \"$pwd"."$file\"\n";

	$i=0;
	$ASnum = 0;
	while (<TPA_IN>){
	    if ( /^AS\s+(\d+)-(\d+)\s+(\S+)\s+((\d+)-(\d+)|not_available)\s*([Cc]?)/ ) { 
		$$submission[$fileNum][$ASnum]{'tpa_span_from'}      = $1;
		$$submission[$fileNum][$ASnum]{'tpa_span_to'}        = $2; 
		$$submission[$fileNum][$ASnum]{'primary_identifier'} = uc($3);
		$$associateSeqFiles{uc($3)} = "";
		
		if ($4 ne "not_available"){
		    $$submission[$fileNum][$ASnum]{'primary_span_from'} = $5;
		    $$submission[$fileNum][$ASnum]{'primary_span_to'}   = $6;
		    
		    if ($7) {
			$$submission[$fileNum][$ASnum]{'tpa_comp'}      = 1;
		    }
		}
		$ASnum++;
	    } elsif ( /^FT\s+\/organism=\"([^\n]+)/ ) {

		$$organism{$fileNum}[$i] = $1;
		$$organism{$fileNum}[$i] =~ s/\s+$/ /;

		if ($1 !~ /\"/) {
		    $wrappingDetected = 1;
		} 
		else {
		    $$organism{$fileNum}[$i] =~ s/\"\s*//;
		    $i++;
		}
	    } 
	    elsif ($wrappingDetected && ( /^FT\s+([^\n]+)/ )) {

		$$organism{$fileNum}[$i] .= " " . $1;
		$$organism{$fileNum}[$i] =~ s/\s+$/ /;

		if ($1 =~ /\"/) {
		    $wrappingDetected = 0;
		    $$organism{$fileNum}[$i] =~ s/\"//;
		    $i++
		}
	    }
	}
	close (TPA_IN);

	$quiet || print "Number of AS lines found in $file: $ASnum\n\n";
	$fileNum++;
    }
  
}

#-------------------------------------------------------------------------------
# Usage   : get_tax_id_and _organism($dbh, $orgName)
# Description: returns the tax ID and organism from the database for a supplied
#              organism name
# Return_type : integer and string
# Args    : $dbh - database handle
#           $orgName - string of an organism name
# Caller  : called in check_taxonomy
#-------------------------------------------------------------------------------
sub get_tax_id_and_organism($$) {

    my ($sql, $tax_id, $db_org_name);

    my $dbh = shift;
    my $orgName = shift;
	$orgName =~s|'|''|g; #Protect sql command from breaking
    $tax_id = "";
    $db_org_name = "";
    
    $sql = "SELECT tax_id
	    FROM ntx_synonym
	    WHERE upper_name_txt = '" . uc($orgName) ."'";
    
    
    $tax_id = dbi_getvalue($dbh, $sql);
	
	$debug && print "$sql\n" ;
    
    if($tax_id){
    	$sql = "SELECT min (name_txt) 
            FROM ntx_synonym
            WHERE tax_id = $tax_id
              AND name_class = 'scientific name'";

        $db_org_name = dbi_getvalue($dbh, $sql);
		$db_org_name = dbi_getvalue($dbh, $sql) if ($tax_id);
	    return($tax_id, $db_org_name)	
	}
	else{
		return;		
		
	}
}

#-------------------------------------------------------------------------------
# Usage   : check_organism($dbh, $tpaOrganism, $tpaTaxId, $tpaSpecies, 
# $tpaSpeciesTaxId, $assocOrganism, $assocTaxId, $assocSpecies, $assocSpeciesTaxId)
# Description: creates a message dependent on values of the input organisms
# Return_type : $reply - a string revealing if the AS line accession species matches
#  the species in the parent TPA file, or not
# Args    : $tpaOrganism: the organism name to compare
#           $tpaTaxId: taxonomy id of organism
# Caller  : called from check_taxonomy
#-------------------------------------------------------------------------------
sub check_organism($$$$$$$$) {
    $debug && print " debug - running check_organism\n";

    my ($reply);

    my ($tpaOrganism, $tpaTaxId, $tpaSpeciesTaxId, $assocOrganism, $assocTaxId, $assocSpeciesTaxId, $primAccession, $tpaFilename) = @_;
 
    $reply = "$assocOrganism (tax:$assocTaxId)\n";

    if ($tpaSpeciesTaxId != $assocSpeciesTaxId) {
	$reply .= "\t** ALERT: $tpaFilename uses a segment from a completely different species.\n"
	       . "\t   $tpaFilename contains \"$tpaOrganism\" (taxid:$tpaTaxId).\n"
               . "\t   $primAccession contains \"$assocOrganism\" (taxid:$assocTaxId).\n";
    }
    elsif ($tpaTaxId != $assocTaxId) {
	$reply .= "\t** Warning: $tpaFilename uses a segment from a different organism (but same species).\n"
               . "\t   $tpaFilename contains \"$tpaOrganism\" (taxid:$tpaTaxId).\n"
               . "\t   $primAccession contains \"$assocOrganism\" (taxid:$assocTaxId).\n";
    }

    return $reply;
}

#-------------------------------------------------------------------------------
# Usage   : get_species_details($dbh, $tax_id)
# Description: grabs the species level scientific name and tax_id for the
#              entered organism
# Return_type : 1 string and 1 integer
# Args    : $dbh : database handle
#           $tax_id: taxonomy id of the organim you want to find the species of
# Caller  : called from check_taxonomy
#-------------------------------------------------------------------------------
sub get_species_details($$) {

    my ($sql, $parent_id, $rank, $tax_name, $sth);

    my $dbh = shift;
    my $tax_id = shift;

    $rank = "";
    $tax_name = "";
    $parent_id = 2; # initial setting (should not be 1)

    while (($rank ne "species") && ($parent_id != 1)) {
	$sql = "SELECT tax.parent_id, tax.tax_id, tax.rank, syn.name_txt 
                FROM ntx_tax_node tax, ntx_synonym syn 
                WHERE tax.tax_id = $tax_id AND syn.name_class = 'scientific name' 
                  AND syn.TAX_ID = tax.tax_id";

	$sth = $dbh->prepare( $sql );
	$sth->execute();

	while (($parent_id, $tax_id, $rank, $tax_name) = $sth->fetchrow_array() ) {

	    if ($rank ne "species") {
		$tax_id = $parent_id;
	    }
	    last;
	}
    }

    return($tax_name, $tax_id);
}

#-------------------------------------------------------------------------------
# Usage   : get_organism_and_tax_id_from_acc($dbh, $primary_acc)
# Description: gets the primary organism and tax_id from the accession supplied
# Return_type : 1 string and 1 integer
# Args    : $dbh : database handle
#           $primary_acc: accession number, with or without sequence version
# Caller  : called from check_taxonomy
#-------------------------------------------------------------------------------
sub get_organism_and_tax_id_from_acc($$) {

    my ($sql, $tax_name, $tax_id, $sth);

    my $dbh = shift;
    my $primary_acc = shift;

    $primary_acc =~ s/\.\d+$//;

    $sql = "SELECT ns.name_txt, ns.tax_id 
            FROM ntx_synonym ns, ntx_tax_node ntn, sourcefeature so, seqfeature seqf, dbentry db 
            WHERE ns.tax_id = ntn.tax_id 
              AND ntn.tax_id = so.organism 
              AND so.PRIMARY_SOURCE = 'Y' 
              AND so.featid= seqf.featid 
              AND seqf.bioseqid=db.bioseqid 
              AND ns.name_class='scientific name' 
              AND db.primaryacc#= '".$primary_acc."'";

	$debug && print "$sql\n";
    $sth = $dbh->prepare( $sql );
    $sth->execute();

    while (($tax_name, $tax_id) = $sth->fetchrow_array() ) {
    		return ($tax_name, $tax_id);		
    	
    }
}

#-------------------------------------------------------------------------------
# Usage   : check_taxonomy(@$submission, %$associateSeqFiles, %$organism, $tempDir, @$inputFiles, $opt_connStr)
# Description: checks to see if the organism in the AS line accessions are the 
# same as in the input file.
# Return_type : none - just writing to a file
# Args    : @$submission: provides the AS line accession to check
#           %$associateSeqFiles: provides filenames of the embl entry files
#           %$organism: holds a organisms extracted from the input files
#           $tempDir: subdirectory housing embl entry files
#           @$inputFiles: list of input file names
#           $opt_connStr: name of database to connect to e.g. @PRDB1
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub check_taxonomy(\@\%\%\@$$) {
    $debug && print " debug - running checkTaxonomy\n";

    my ($inputFileNum, $emblFile, $ASline, $numInputFiles, $tpaTaxId, $dbh);
    my ($scientificName, $tpaOrganism, $tpaSpecies, $tpaSpeciesTaxId, $line);
    my ($assocOrganism, $assocTaxId, $assocSpecies, $assocSpeciesTaxId);
    my ($tpaOrganismInFile, $assocOrganismInFile);

    my $submission = shift;
    my $associateSeqFiles = shift;
    my $organism = shift;
    my $inputFiles = shift;
    my $opt_connStr = shift;
    my $assocFileDir = shift;
    $numInputFiles = scalar(@$submission);
     
    
    my_open_FH(\*FILE,">taxonomy.log");

    $dbh = dbi_ora_connect ( $opt_connStr);
    $dbh->{AutoCommit}    = 0;
    $dbh->{RaiseError}    = 1;

    for ($inputFileNum=0; $inputFileNum<$numInputFiles; $inputFileNum++) {

	foreach $tpaOrganismInFile (@{ $$organism{$inputFileNum} }) {
		
		print "...\nProcessing $tpaOrganismInFile...\n";
	    ($tpaTaxId, $tpaOrganism) = get_tax_id_and_organism($dbh, $tpaOrganismInFile);
	   		
	    if ($tpaTaxId eq "") {
			print FILE "ERROR: Tax id not found from \"$tpaOrganismInFile\"";
			print "*" x 100 , "\n";
			print  "ERROR: Tax id not found from \"$tpaOrganismInFile\"\n";
			print "*" x 100 , "\n";
			next;
	    }

	    else {
			($tpaSpecies, $tpaSpeciesTaxId) = get_species_details($dbh, $tpaTaxId);
				    
			print FILE "Entry ".($inputFileNum+1)." ($$inputFiles[$inputFileNum]):\n"
			. "  TPA Organism:\n"
			. "    $tpaOrganismInFile (tax:$tpaTaxId)\n";

			if (uc($tpaOrganismInFile) ne uc($tpaOrganism)){
		    	print FILE "\t** Warning: \"$tpaOrganismInFile\""
				. " is a synonym; use \"$tpaOrganism\"\n";
			}
			elsif ($tpaOrganismInFile ne $tpaOrganism){
		    	print FILE "\t** Warning: \"$tpaOrganismInFile\""
				. " has problems with CaPITaL LEttERS; use \"$tpaOrganism\"\n";
			}

			print FILE "  Organisms from associate accs:\n";
			foreach $ASline (@{$$submission[$inputFileNum]}) {
		   	 if ( $$ASline{'primary_identifier'} !~ /^TI/ ) {
			
				($assocOrganism, $assocTaxId) = get_organism_and_tax_id_from_acc($dbh, $$ASline{'primary_identifier'});
				
				$debug && print "<>" x 100, "\n";
				$debug && print "assocOrganism=$assocOrganism \nassocTaxId=$assocTaxId\n";
				$debug && print "<>" x 100, "\n";
				if ($assocTaxId ne ''){
					($assocSpecies, $assocSpeciesTaxId) = get_species_details($dbh, $assocTaxId) ;	
				}
				else{
					print "*" x 100 ,"\n";
					print "No taxid found for $$ASline{'primary_identifier'}\n";
					print "*" x 100 ,"\n";
				}
				
			
			    }
		    else {

				open(READORG, "<$assocFileDir/".$$associateSeqFiles{ $$ASline{'primary_identifier'} }) || print "Cannot open $$associateSeqFiles{ $$ASline{'primary_identifier'} }: $!\n";
				while ($line = <READORG>) {
			    	if ($line =~ />\S+\s+([^\n]+)/) {
				
						$assocOrganismInFile = $1;
						$assocOrganismInFile =~ s/\s+$//;
						last;
			    		}
					}
					if ($assocOrganismInFile) {
			    		($assocTaxId, $assocOrganism) = get_tax_id_and_organism($dbh, $assocOrganismInFile);
			    		($assocSpecies, $assocSpeciesTaxId) = get_species_details($dbh, $assocTaxId);
					}
		    	}

		    	if ($assocTaxId) {
					print FILE "    " 
			    	. right_pad_or_chop($$ASline{'primary_identifier'}.":", 15, " ")
			    	. check_organism($tpaOrganism, $tpaTaxId, $tpaSpeciesTaxId, $assocOrganism, $assocTaxId, $assocSpeciesTaxId, $$associateSeqFiles{ $$ASline{'primary_identifier'} }, $$inputFiles[$inputFileNum]);
		    	}
		    	else {
					print FILE "    " 
			    	. right_pad_or_chop($$ASline{'primary_identifier'}.":", 15, " ")
			    	. " No organism available";
		    	}
			}
			print FILE "\n\n";
	    	}
		}
    }

    # disconnect from Oracle
    dbi_rollback ( $dbh );
    dbi_logoff ( $dbh );

    close(FILE);
}

#-------------------------------------------------------------------------------
# Usage   : run_emboss_stretcher(%$associateSeqFiles, @$submission, @$inputFiles, $temp_dir, @$valFiles)
# Description: Creates a .val file for each temp file, runs stretcher and writes
# the output to this file
# Return_type : none - a file is written to
# Args    : %$associateSeqFiles: provides filenames of the embl entry files to
# use in stretcher command
#           @$submission: provides the primary sequence fragment locations
#           @$inputFiles: provides a list of input file names
#           $temp_dir: filepath of where to find embl files
#           @$valFiles: list of .val files
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub run_emboss_stretcher(\%\@\@$) {
    $debug && print " debug - running run_emboss_stretcher\n";

    my ($outputFile, $entry, $ASline, $emblFile, $filenamePrefix);
    my ($fileContents, $stretcher_cmd, $valFile);

    my ($associateSeqFiles, $submission, $inputFiles, $temp_dir) = @_;

    $outputFile = "stretcher.out";
	
	
	
    for ($entry=0; $entry<@$submission; $entry++){

	$filenamePrefix = $$inputFiles[$entry];
	$filenamePrefix =~ s/\.[^.]+$//;
	
	$valFile = "$temp_dir/$filenamePrefix".".val";
	my_open_FH(\*FILE, ">>$valFile");
	
	foreach $ASline (@{$$submission[$entry]}){
	    $emblFile = "$temp_dir/".$$associateSeqFiles{$$ASline{'primary_identifier'}};
	    
	    if (!((-e $emblFile && -f $emblFile ) && (-e $$inputFiles[$entry] && -f $$inputFiles[$entry] ))){
	    #if (!(-e $$inputFiles[$entry] && -f $$inputFiles[$entry] )){	
	    	print "*" x 100, "\n";
	    	
			print "Cannot open align missing sequence \n$emblFile to  $$inputFiles[$entry]\n";
			print "*" x 100, "\n";
			next;
	    }
	    
	    #$stretcher_cmd = "$emboss_path/matcher $$inputFiles[$entry] $emblFile".
	    $stretcher_cmd = "$emboss_path/matcher $$inputFiles[$entry] $emblFile".
		" -sbegin1 ".$$ASline{tpa_span_from}.
		" -send1 "  .$$ASline{tpa_span_to}.
		" -sbegin2 ".$$ASline{primary_span_from}.
		" -send2 "  .$$ASline{primary_span_to}.
		" -outFile $outputFile ".
		" -auto  -awidth $alignwidth";
	
	    if ((defined($$ASline{tpa_comp})) && ($$ASline{tpa_comp} == 1)) {
		$stretcher_cmd .= " -sreverse2";
	    }
	    $verbose && print "running Stretcher: $stretcher_cmd\n";
	    
	    print `$stretcher_cmd`;
	    
	    open(STRETCHER_RES, "<$outputFile") || die "Cannot read $outputFile\n";
	    $fileContents = do{local $/; <STRETCHER_RES>};
	    close(STRETCHER_RES);

	    print FILE $fileContents; 
	}
	close (FILE);
    }
    unlink($outputFile);
}

#-------------------------------------------------------------------------------
# Usage   : format_and_print_stretcher_summary(@$s_tpaAcc, @$s_primAcc, @$s_ident, @$s_length, $fh) 
# Description: pads summary data and prints it to the.val file
# Return_type : none - a file is written to
# Args    : @$s_tpaAcc: from stretcher results, a list of tpa accessions
#         : @$s_primAcc: from stretcher results, a list of primary accessions 
#         : @$s_ident: from stretcher results, a list of % identity 
#         : @$s_length: from stretcher results, a list of fragment lengths
#         : $fh: filehandle of file to print to
#         : @$gapLocations: a list of warnings of gaps in TPA covera
# Caller  : called from print_stretcher_summary_to_file
#-------------------------------------------------------------------------------
sub format_and_print_stretcher_summary(\@\@\@\@$\%$) {

    my ($padChar, $i, $warningTitleFlag, $gap, $summaryHeader, $dataRow);
    my ( $warningTitle, $warning, $gapGroup );

    my ($s_tpaAcc, $s_primAcc, $s_ident, $s_length, $fh, $gapLocations, $inputFileName) = @_;

    $padChar = " ";

    $summaryHeader = "TPA Acc       Primary Acc   % Identity             Length\n"
            . "------------- ------------- ---------------------- ------- \n";

    print $fh $summaryHeader;
    $showSummary && print $summaryHeader;


    for ($i=0; $i<@$s_primAcc; $i++) {
	$dataRow = right_pad_or_chop($$s_tpaAcc[$i], 14, $padChar)
	    . right_pad_or_chop($$s_primAcc[$i], 14, $padChar) 
	    . right_pad_or_chop($$s_ident[$i], 23, $padChar)
	    . $$s_length[$i]. "\n";

	print $fh $dataRow;
	$showSummary && print $dataRow;	
    }

    $warningTitle = "\n# Warnings:\n";

    $warningTitleFlag = 1;
    for ($i=0; $i<@$s_primAcc; $i++) {

	if ($$s_ident[$i] =~ /\((\d+(\.\d+)?)%\)$/) {

	    if ($1 < 90) {
		if ($warningTitleFlag) {

		    print $fh $warningTitle;
		    $showSummary && print $warningTitle ;

		    $warningTitleFlag = 0;
		}
		$warning = "$$s_primAcc[$i] is less than 90% identical to the TPA sequence ($1%).\n";
		print $fh $warning;
		$showSummary && print $warning;

	    }
	}
    }
##############!!!!!!!!!!!!!!!

    if (defined($$gapLocations{$inputFileName})) {
# && (scalar(@{$$gapLocations{$inputFileName}})) {

	if ($warningTitleFlag) {
	    print $fh $warningTitle;
	    $showSummary && print $warningTitle;

	    $warningTitleFlag = 0;
	}

	foreach $gap (@{$$gapLocations{$inputFileName}}) {
	    $warning = "There is a gap of ".$gap." in the TPA sequence (no coverage by primary sequences).\n";
	    print $fh $warning;
	    $showSummary && print $warning;
	}
    }
}

#-------------------------------------------------------------------------------
# Usage   : write_stretcher_summary_to_file(\*FILE, $fileContents, $valFileName, @$inputFiles, @$gapLocations) 
# Description: sift through stretcher results and print summary to file
# Return_type : none - a file is written to
# Args    : $fh: filehandle of file to write to
#           @$valFileContents: array containing stretcher output
#           $valFileName: filename or path of the input file
#           @$inputFiles: a list of input files
#           @$gapLocations: a list of warnings of gaps in TPA coverage
# Caller  : called from add_stretcher_summary
#-------------------------------------------------------------------------------
sub write_stretcher_summary_to_file($\@$\@\%) {

    my ($line, @s_tpaAcc, @s_primAcc, @s_ident, @s_length, $file);
    my ($stretcherSetNum, $valFilenamePrefix, $inputFilename, $analysisHeader);

    my $fh = shift;
    my $valFileContents = shift;
    my $valFileName = shift;
    my $inputFiles = shift;
    my $gapLocations = shift;

    if ($valFileName =~ /([^\/.]+\.)[^.]+$/) {

	$valFilenamePrefix = $1; 
	$valFilenamePrefix = quotemeta($valFilenamePrefix);

	foreach $file (@$inputFiles) {
	    if ($file  =~ /^$valFilenamePrefix/) {
		$inputFilename = $file;
		last;
	    }
	}

	$analysisHeader = "# Analysis of alignment in $inputFilename\n\n";
	print $fh $analysisHeader;
	$showSummary && print "\n".$analysisHeader;
    }

    print $fh "# Stretcher Results Summary:\n\n";

    $stretcherSetNum = 0;
    foreach $line (@$valFileContents) {

	if ($line =~ /^\# 1:\s+([^\n;]+);?\n/) {
	    $s_tpaAcc[$stretcherSetNum] = $1;
	}
	elsif ($line =~ /^\# 2:\s+([^\n;]+);?\n/) {
	    $s_primAcc[$stretcherSetNum] = $1;
	}
	elsif ($line =~ /^\# Length:\s+(\d+)/) {
	    $s_length[$stretcherSetNum] = $1;
	} 
	elsif ($line =~ /^\# Identity:\s+([^)]+\))/) {
	    $s_ident[$stretcherSetNum] = $1;
	    $stretcherSetNum++;
	}
    }

    format_and_print_stretcher_summary(@s_tpaAcc, @s_primAcc, @s_ident, @s_length, $fh, %$gapLocations, $inputFilename);

    print $fh "\n\n";
}

#-------------------------------------------------------------------------------
# Usage   : add_stretcher_summary(@$valFiles, @$inputFiles, @$gapLocations)
# Description: parses the contents of the val file and rewrites the file with a 
# summary of results at the top
# Return_type : none - a file is written to
# Args    : @$valFiles: list of .val files to add summaries to
#           @$inputFiles: a list of input files
#           @$gapLocations: a list of warnings of gaps in TPA coverage
# Caller  : called in the main
#-------------------------------------------------------------------------------
sub add_stretcher_summary(\@$\%) {

    my (@fileContents, $file, $valFile);

    my $inputFiles = shift;
    my $tempDir = shift;
    my $gapLocations = shift;

    foreach $file (@$inputFiles) {

	if ($file =~ /(.+)\.[^.]+$/) {
	    $valFile = "$tempDir/$1".".val";
	}

	my_open_FH(\*READVAL, "<$valFile");
	@fileContents = <READVAL>;
	close(READVAL);

	my_open_FH(\*WRITEVAL, ">$valFile");
	write_stretcher_summary_to_file(\*WRITEVAL, @fileContents, $valFile, @$inputFiles, %$gapLocations);

	foreach ( @fileContents) {
	    print WRITEVAL$_;
	}

	close(WRITEVAL)
    }
}

#-------------------------------------------------------------------------------
# Usage   : look_for_big_gaps(@$submission, @$gapLocations)
# Description: if there are any gaps >50bp in TPA coverage, find gap locations
# Return_type : list of gap locations
# Args    : @$submission
# Caller  : this script
#------------------------------------------------------------------------------
sub look_for_big_gaps(\@\%\@) {

    my ($inputFileNum, $ASnum, $gapSize, $numASlines, $nextPosToCheck, $pos);
    my ($highestPos, $gapDetected, @sortedSpansByStart, $gapStart, $gapEnd);
    my ($startPos, %spans, $startPosCpy);

    my $submission = shift;
    my $gapLocations = shift;
    my $inputFiles = shift;

    $verbose && print "\nChecking for gaps in TPA sequence...\n";

    foreach ($inputFileNum=0; $inputFileNum<@$submission; $inputFileNum++) {

	$highestPos = 1;
	%spans = ();
	@sortedSpansByStart = ();

	$numASlines = scalar(@{ $$submission[$inputFileNum] });

	for ($ASnum=0; $ASnum<$numASlines; $ASnum++) {

	    if ($$submission[$inputFileNum][$ASnum]{'tpa_span_to'} > $highestPos) {
		$highestPos = $$submission[$inputFileNum][$ASnum]{'tpa_span_to'};
	    }

	    # eg spans{120-130} = 130 to avoid duplicate start positions
	    $spans{$$submission[$inputFileNum][$ASnum]{'tpa_span_from'}."-".$$submission[$inputFileNum][$ASnum]{'tpa_span_to'}} = $$submission[$inputFileNum][$ASnum]{'tpa_span_to'};

	}

	@sortedSpansByStart = sort {$a cmp $b} keys %spans;
	
	$highestPos++;
	foreach ($pos=1; $pos<$highestPos; $pos++) {

	    $gapDetected = 1;
	    foreach $startPos (keys %spans) {

		$startPosCpy = $startPos;
		$startPosCpy =~ s/\-\d+$//;

		# if pos falls inside a span, mark as 'not in a gap'
		if (($pos >= $startPosCpy) && ($pos <= $spans{$startPos})) {
		    $gapDetected = 0;
		    last;
		}
	    }

	    if ($gapDetected) {

		$gapStart = $pos;

		foreach $startPos (@sortedSpansByStart) {

		    $startPosCpy = $startPos;
		    $startPosCpy =~ s/\-\d+$//;

		    if ($startPosCpy > $gapStart) {
			$gapEnd = $startPosCpy - 1;
			$nextPosToCheck = $spans{$startPos};
			last;
		    }
		}

		$gapSize = ($gapEnd - $gapStart) + 1;
		push(@{ $$gapLocations{$$inputFiles[$inputFileNum]}}, $gapSize."bp at positions ".$gapStart."-".$gapEnd); 

#print $gapSize."bp at positions ".$gapStart."-".$gapEnd."\n";
		# move pos further along to save unnecessary looping
		$pos = $nextPosToCheck;
	    }
	}
    }
}
#-------------------------------------------------------------------------------
# Usage   : get_percentage_non_ngcat($num_n, $seqlen)
# Description: returns the percentage of non-ngcat letters in the sequence
# Return_type : number (2 decimal places)
# Args    : 1. number of letters in sequence that are not n, g, c, a or t
#           2. length of full sequence
# Caller  : inspect_tsa_sequence
#-------------------------------------------------------------------------------

sub get_percentage_non_ngcat($$) {

    my ($perc_non_ngcat);

    my $num_ngcat = shift;
    my $seqlen = shift;

    if ($num_ngcat) {
	$perc_non_ngcat = (($seqlen - $num_ngcat)/$seqlen) *100;
	
	if ($perc_non_ngcat =~ /(\d+\.\d\d)/) {
	    $perc_non_ngcat = $1;
	}
    }
    else {
	$perc_non_ngcat = 0;
    }

    return($perc_non_ngcat);
}

#-------------------------------------------------------------------------------
# Usage   : get_percentage_n($num_n, $seqlen)
# Description: returns the percentage of n's in the sequence
# Return_type : number (2 decimal places)
# Args    : 1. number of n's
#           2. length of full sequence
# Caller  : inspect_tsa_sequence
#-------------------------------------------------------------------------------

sub get_percentage_n($$) {

    my ($perc_n);

    my $num_n = shift;
    my $seqlen = shift;

    if ((defined $num_n) && ($num_n)) {
	$perc_n = ($num_n/$seqlen) *100;
	
	if ($perc_n =~ /(\d+\.\d\d)/) {
	    $perc_n = $1;
	}
    }
    else {
	$perc_n = 0;
    }

    return($perc_n);
}

#-------------------------------------------------------------------------------
# Usage   : inspect_tsa_sequence(@inputFiles, @valFiles)
# Description: for a tsa sequence
#                   - must be <5 consecutive n's
#                   - must have <5% n's in entire sequence
#                   - report on non-ngcat characters if >5% 
# Return_type : none
# Args    : a list of input files to read seq from and a list of val files to 
#           write output to
# Caller  : main()
#------------------------------------------------------------------------------

sub inspect_tsa_sequence(\@$) {

    my ($inputFile, $line, $get_sequence_line, %sequences, $acc, $line_num);
    my ($num_ngcat, %n_spans, $char, $n_count, $last_n_pos, $char_count, $msg);
    my ($tsa_summary, $seqlen, $perc_non_ngcat, %moreThan5ns, $first_n_pos, $span);
    my ($get_sequence, $fileCounter, $valFile, $warning_notice_printed, $num_n);
    my ($perc_n);

    my $inputFiles = shift;
    my $tempDir = shift;

    for ($fileCounter = 0; $fileCounter<@$inputFiles; $fileCounter++) {

	%sequences = {};
	%moreThan5ns = {};
	$num_ngcat = 0;
	$line_num = 1;
	$get_sequence_line = 0;
	%n_spans={};
	$tsa_summary = "";

	if (open(READSEQ, "<$$inputFiles[$fileCounter]")) {
	    while ($line = <READSEQ>) {

		if ($line =~ /^ID\s+([^;]+);/) {

		    $acc = $1;

		    if ($acc !~ /[A-Za-z]{1,2}\d+/) {
			$acc = $$inputFile[$fileCounter]."_".$line_num;
		    }
		}
		elsif ($line =~ /^SQ/) {
		    $get_sequence_line = 1;
		}
		elsif ($line =~ /^\/\//) {
		    $sequences{$acc} =~ s/[^a-zA-Z]//g;
		    $seqlen = length($sequences{$acc});
		    $get_sequence_line = 0;
		}
		elsif ($get_sequence_line) {
		    $sequences{$acc} .= $line;
		}

		$line_num++;
	    }

	    close(READSEQ);
	}
	else {
	    print "could not open $$inputFile[$fileCounter]\n";
	}

	$warning_notice_printed = 0;

	foreach $acc (sort keys %sequences) {
	    if ($acc =~ /\d+$/) {

		%n_spans = {};

		# if there are more than 5 n's
		if ($sequences{$acc} =~ /nnnnnn+/i) {

		    $moreThan5ns{$acc} = 1;
		    $n_count = 0;
		    $first_n_pos = 0;

		    for ($char_count=1; $char_count<length($sequences{$acc}); $char_count++) {

			$char = substr($sequences{$acc}, $char_count, 1);

			if ($char =~ /[Nn]/) {
			    $n_count++;

			    if (! $first_n_pos) {
				$first_n_pos = $char_count+1;
			    }
			}
			elsif ($n_count && ($char !~ /[Nn]/)) {
			    $last_n_pos = $char_count;

			    if ($n_count > 5) {
				$n_spans{$first_n_pos."-".$last_n_pos} = $n_count;
			    }

			    $n_count = 0;
			    $first_n_pos = 0;
			    $last_n_pos = 0;
			}
		    }
		}

		$num_ngcat = ($sequences{$acc} =~ tr/[ngcat]//);
		$num_n = ($sequences{$acc} =~ tr/[n]//);
		$msg = "";

		foreach $span (sort keys(%n_spans)) {
		    if ($span =~ /\d+-\d+/) {
			if (!$warning_notice_printed) {
			    $msg = "\nWarning: $acc\n";
			    $warning_notice_printed = 1;
			}

			$msg .= "  $n_spans{$span} consecutive n's at position $span\n";
		    }
		}

		if ($msg ne "") {
		    $tsa_summary .= $msg;
		}

		$perc_n = get_percentage_n($num_n, $seqlen);
		if ($perc_n > 5) {
		    $msg = "";
		    if (!$warning_notice_printed) {
			$msg = "\nWarning: $acc\n" ;
			$warning_notice_printed = 1;
		    }
		    $msg .= "  $perc_n% n's in sequence\n";
		    $tsa_summary .= $msg;
		} 


		$perc_non_ngcat =  get_percentage_non_ngcat($num_ngcat, $seqlen);
		if ($perc_non_ngcat > 5) {
		    $msg = "";
		    if (!$warning_notice_printed) {
			$msg = "\nWarning: $acc\n" ;
		    }
		    $msg .= "  $perc_non_ngcat% of sequence contains letters other than n, g, c, a and t\n";
		    $tsa_summary .= $msg;
		} 
	    }
	    $warning_notice_printed = 0;
	}

	if ($$inputFiles[$fileCounter] =~ /(.+)\.[^.]+$/) {
	    $valFile = $1.".val"; 
	}

	$tsa_summary =~ s/^\n//;
	print $tsa_summary;

	open(SAVEVAL, ">$tempDir/$valFile") || die "Cannot open $tempDir/$valFile for writing\n";
	print SAVEVAL $tsa_summary;
	print SAVEVAL "\nStretcher Results:\n\n";
	close(SAVEVAL);
    }
}

#-------------------------------------------------------------------------------
# Usage   : main(@ARGV)
# Description: contains the run order of the script
# Return_type : nonce
# Args    : @ARGV command line arguments
# Caller  : this script
#------------------------------------------------------------------------------
sub main(\@) {

    my (@inputFiles, $rev_db, $opt_connStr, %associateSeqFiles, $acc);
    my (%organism, $tempDir, @submission, @valFiles, %gapLocations);

    my $args = shift;

    $opt_connStr = usage(@$args, @inputFiles);

    if (! @inputFiles) {
	get_input_files(@inputFiles);
    }

    check_AS_line(@inputFiles);
   
    parse_flatfiles(@inputFiles, @submission, %associateSeqFiles, %organism);

    # create directory to store sequence files
    $tempDir = cwd.'/tpav_tmp.del';
    if (! (-e $tempDir) ) {
	mkdir $tempDir;
    }

    # connect to the revision database
    $rev_db = RevDB->new('rev_select/mountain@erdpro');
    # get a sequence file for eash associate sequence
    # %associateSeqFiles = hash of AC.version -> entry file location
    foreach $acc (keys %associateSeqFiles){
    	my $grabresult = grab_entry($rev_db, $tempDir, 0, $acc, $quiet, 1);
    	$associateSeqFiles{$acc} = $grabresult;	
    		
    }
    use YAML;
    print ":" x 200, "\n" if $verbose or $debug;
    print YAML::Dump \%associateSeqFiles,"\n" if $verbose or $debug;
    print ":" x 200, "\n" if $verbose or $debug;
    # disconnect to the revision database
    $rev_db->disconnect();
	
	
    check_taxonomy(@submission, %associateSeqFiles, %organism, @inputFiles, $opt_connStr, $tempDir);

	
    if ($tsa) {
	inspect_tsa_sequence(@inputFiles, $tempDir);
    }

    # do the global alignment of each fragment 
    run_emboss_stretcher(%associateSeqFiles, @submission, @inputFiles, $tempDir);

    look_for_big_gaps(@submission, %gapLocations, @inputFiles);

    add_stretcher_summary(@inputFiles, $tempDir, %gapLocations);

    # check .val files for results?
    print "\nPS I'm leaving $tempDir with the associate sequences for you to delete yourself\n";
}

main(@ARGV);
