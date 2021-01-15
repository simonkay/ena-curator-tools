#!/ebi/production/seqdb/embl/tools/bin/perl -w

# -------------------------------------------------------
#         pars_email_sub.pl         
#  Author : Sukhaswami Malladi  ; 
#  calls Pascal's Flat file generator in function : webin_ffile
#  Today : 6th May 1999
#  PERL script to parse email submissions to Nucleotide
#  Database flat file. Generates flat file : flat_file.out
#  in addition to empars.out, the intermediate file for
#  WEBIN to generate its own flat file.
#  running command : ./pars_email_sub.pl 'email submission file'
# -------------------------------------------------------
#  Diary:
#   14-05-1999 : All feature keys in 
#     http://mercury.ebi.ac.uk/ebi_docs/embl_db/ft/keys_alphabetical.html 
#     are now present in this list
#   14-05-1999 : RL lines modified as per Nicole's suggestions, HD added
#----------------------------------------
@emlines = ( "I.  CONFIDENTIAL STATUS",
 "Enter an X if you want these data to be confidential    [",
 "If confidential write the release date here :",
 "(Date format DD-MMM-YYYY e.g. 30-JUN-1998)",
 "II.  CONTACT INFORMATION",
 "Last name            :",
 "First name           :",
 "Middle initials      :",
 "Department           :",
 "Institution          :",
 "Address              :",
 "                     :",
 "Country              :",
 "Telephone            :",
 "Fax                  :",
 "Email                :",
 "III. CITATION INFORMATION",
 "Author 1             :",
 "Author 2             :",
 "Author 3             :",
 "(e.g. Smith A.B.)",
 "(Copy line for extra authors)",
 "Title                :",
 "Journal              :",
 "Volume               :",
 "First page           :",
 "Last page            :",
 "Year                 :",
 "Institute (if thesis):",
 "Publication status",
 "Mark one of the following",
 "In preparation       [",
 "Accepted             [",
 "Published            [",
 "Thesis/Book          [",
 "No plans to publish  [",
 "IV. SEQUENCE INFORMATION",
 "Sequence length (bp) :",
 "Molecule type",
 "Mark one of the following",
 "Genomic DNA          [",
 "cDNA to mRNA         [",
 "rRNA                 [",
 "tRNA                 [",
 "Genomic RNA          [",
 "cDNA to genomic RNA  [",
 "Mark if either of these apply",
 "Circular             [",
 "Checked for vector",
 "contamination        [",
 "V. SOURCE INFORMATION",
 "Organism             :",
 "Sub species          :",
 "Strain               :",
 "Cultivar             :",
 "Variety              :",
 "Isolate/individual   :",
 "Developmental stage  :",
 "Tissue type          :",
 "Cell type            :",
 "Cell line            :",
 "Clone                :",
 "Clone (if >1)        :",
 "Clone library        :",
 "Chromosome           :",
 "Map position         :",
 "Haplotype            :",
 "Natural host         :",
 "Laboratory host      :",
 "Macronuclear         [",
 "Mark one if immunoglobulin",
 "or T cell receptor ",
 "Germline             [",
 "Rearranged           [",
 "Mark one if viral",
 "Proviral             [",
 "Virion               [",
 "Mark one if from an organelle",
 "Chloroplast          [",
 "Mitochondrion        [",
 "Chromoplast          [",
 "Kinetoplast          [",
 "Cyanelle             [",
 "Plasmid (not clone)  [",
 "Further source information",
 "(e.g. taxonomy, specimen voucher etc)",
 "Note                 :",
 "VI. FEATURES OF THE SEQUENCE",
 "YOU MUST DESCRIBE AT LEAST ONE FEATURE OF THE SEQUENCE OR THERE WILL BE A",
 "DELAY IN THE PROCESSING OF YOUR SUBMISSION",
 "Complete the block below for every feature you need to describe. If you",
 "have more than one feature copy the block as many times as you require. For",
 "help see 8) ENTERING FEATURES AND LOCATIONS above. ",
 "FEATURE NO.",
 "Feature key           :",
 "From                  :",
 "To                    :",
 "Gene name             :",
 "Product name          :",
 "Codon start 1,2 or 3  :",
 "EC number             :",
 "Complementary strand  [",
 "Experimental evidence [",
 "VII. SEQUENCE INFORMATION ",
 "Enter the sequence data below",
 "(IUPAC nucleotide base codes, Nucl. Acids Res. 13: 3021-3030, 1985)",
 "BEGINNING OF SEQUENCE:",
 "END OF SEQUENCE",
 "Include the translation for each CDS feature below.",
 "BEGINNING OF TRANSLATION:",
 "END OF TRANSLATION" );

@valid_ft_keys = (
"allele",
"attenuator",
"C_region",
"CAAT_signal",
"CDS",
"conflict",
"D-loop",
"D_segment",
"enhancer",
"exon",
"GC_signal",
"gene",
"iDNA",
"intron",
"J_segment",
"LTR",
"mat_peptide",
"misc_binding",
"misc_difference",
"misc_feature",
"misc_recomb",
"misc_RNA",
"misc_signal",
"misc_structure",
"modified_base",
"mRNA",
"mutation",
"N_region",
"old_sequence",
"polyA_signal",
"polyA_site",
"precursor_RNA",
"prim_transcript",
"primer_bind",
"promoter",
"protein_bind",
"RBS",
"repeat_region",
"repeat_unit",
"rep_origin",
"rRNA",
"S_region",
"satellite",
"scRNA",
"sig_peptide",
"snRNA",
"source",
"stem_loop",
"STS",
"TATA_signal",
"terminator",
"transit_peptide",
"tRNA",
"unsure",
"V_region",
"V_segment",
"variation",
"3'clip",
"3'UTR",
"5'clip",
"5'UTR",
"-10_signal",
"-35_signal"  );

# ------------ MAIN ------------

#$infile   = '/homes/sukhaswa/Embl/Email_sub/'.+$ARGV[0];
$infile   = $ARGV[0];

if ( $infile == '' ) { print "Command: pars_email_subs.pl email-sub-file\n"; }

open INFIL,$infile  or die "$infile : could not open file. !!";
open IIFIL, ">temp.txt";
while ( $ili = <INFIL> ) {
    if ( $ili =~ /^>+/ ) {
	$ili =~ s/^> //;
	$ili =~ s/^>+//;
    }
    print IIFIL "$ili";
#    print "$ili";    
}
close(INFIL);
close(IIFIL);
$infile = 'temp.txt';

# ------- VMS operation ------
#$grep = 'search ';
#$fulsub   = `$grep $infile ""`;

$grep     = '/usr/bin/grep ';
$fulsub   = `$grep ^ $infile`;
$fulsub =~ s/[\t\r\f]/ /g;  # change these characters in submission
($junk,$fulsub) = split(/I. +CONFIDENTIAL STATUS/,$fulsub);
$fulsub = 'I.  CONFIDENTIAL STATUS'.+$fulsub;
#print "\n---\n$fulsub\n-------\n";

$flat_file = '>flat_file.out';

$outfile = '>empars.out';
open POFIL, $outfile  or die "Could not open file $infile!!";
print POFIL "no_seq=1";
print POFIL "\nid=\nCAPITAL_MENDED=";

# ----------------- preliminary check ----------
&check_lines;
&check_line_width;
# ------------------- Annotations --------------
&contact_info;
&confidential_status;
# ----------------------------------------------
&citation_info;
&seq_info_annotation;
&source_info;
&get_tax_id($organism);
&features_info;
&seq_info_sequence;
close(POFIL);
&generate_flatfile;
print "\nWEBIN Flat File follows: ('flat_file.out' is alternative ";
print "flat-file for this submission)-\n";
&webin_ffile;
#print "\n--End of report.\n";
#print "\n------Parser Flat File -----\n";
#system("rm temp.txt");
# VMS system("type flat_file.out");
# VMS system("dele temp.txt");
exit();
# ----------- END OF MAIN ------------

# ------- Annotator/Curator can modify the input submission
# based on this routine's report and rerun script on modified 
# input to get better results
sub check_lines
{
    print "\n----------------------------------------------------------";
    print "\nEmail submissions parsing";
    print " 1. Lines absent or modified in submission";
    print "\n----------------------------------------------------------";
    $i=0;$nf=0;$emtxt=1;
    foreach $emtxt (@emlines) {
	$foun = 0; $lno=0;
	open INFIL,$infile  or die "Could not open $infile!!";
	while ( $lin = <INFIL> ) {
	    ++$lno;
	    $f_in = index($lin,$emtxt);
	    if ( $f_in >= 0 ) {
		$foun = 1;
		last;
	    }
#	print "\ncomparing ($f_in): [$lin] <=> [$emtxt]";	    
	}
	if ( $foun == 0 ) {
	    print "\n$emtxt";
	    ++$nf;
	} 
	else { 
#	print "\nfound {$emtxt} at line $lno\n"; 
	}
	close(INFIL);
    }
    print "\n---------------------------------------------------------";   
    if ( $nf == 0 ) {
	print "\nAll lines present";
    } else { print "\n$nf found.\nPlease correct the lines mentioned above ";
	     print "in the submitted file and rerun \n this script for ";
	     print "possible improved flat file output.\n"; }
    print "Output flat file is 'flat_file.out'\n";
    print "----------------------------------------\n2. Other errors\n";
    print "----------------------------------------";
}

sub check_line_width
{
    $lno = 0;
    open INCFIL,$infile  or die "Could not open $infile!!";
    while ( $lin = <INCFIL> ) {
	$lin =~ s/ +$//;
	++$lno; $llw = length($lin);
	if ( $llw > 80 ) {
	    print "\nError at line - $lno : line width ($llw) greater than 80:\n$lin\n";
	}
    }
    close(INCFIL);
    return;
}

#
# ------ now parse the submission to extract requried information
# ===============================================================
# ------ Purposes : $conf_status = 1 (CONFIDNENTIAL SEQUENCE) or 0 (NOT)
#                $rel_date = date of release (e.g. 01-APR-1999)    
sub confidential_status
{
    $conf_status = 0;
    $rel_date = '';
    ($conf_txt,$temptxt) = split(/\nII\. +CONTACT/,$fulsub);
#    print "\n--conf.status--\n($conf_txt)\n---";
    $conf_status = '';
    if ( $conf_txt =~ /\[[X|x]\]/ ) {
	$conf_status = 'confidential';
    } 
    ($temptxt,$rel_date) = split(/date +here +\:/,$conf_txt);
#    print "\n--rel-date-txt--\n($rel_date)\n---";
    if ( $rel_date =~ /^\d+-\w+-\d+/ ) {
	$rel_date = $&;
	if ( $rel_date =~ /\d+-/ ) { 
	    $conf_day = $&; $conf_day =~ s/-//;
	}
	if ( $rel_date =~ /-\S+-/ ) { 
	    $conf_mon = $&; $conf_mon =~ s/-//g;
	}
	if ( $rel_date =~ /-\d+/ ) { 
	    $conf_year = $&; $conf_year =~ s/-//;
	}
	print POFIL "\nconfidential_day=$conf_day";
	print POFIL "\nconfidential_month=$conf_mon";
	print POFIL "\nconfidential_year=$conf_year";
    }
    return;
}

# ==================================================
# A ':' is not expected in any of the contact fields
sub contact_info
{
    $last_name       = '';    $first_name      = ''; $middle_initials = '';    
    $department      = '';    $institution     = ''; $address1        = '';
    $address2        = '';    $address3        = ''; 
    $address4        = '';    $address5        = ''; 
    $email           = '';    
    $country         = '';    $telephone       = ''; $fax             = '';    
    ($coninf_txt,$temptxt) = split(/\nIII\. +CITATION/,$fulsub);
    ($temptxt,$coninf_txt) = split(/\nII\. +/,$coninf_txt);
#    print "\n--contact info.--\n($coninf_txt)\n---";
    $adno = 1;
    while ( $coninf_txt =~ /\n(.*):(.*)/g ) {
	$nvp = $&;
	($name,$valu) = split(/:/,$nvp);
        $name =~ s/\n//g; $name =~ s/ +/ /g;
	$valu =~ s/ +/ /g;  $valu =~ s/^ +//;
	if ( $name =~ /Last name +/ )            { $last_name       = $valu; }
	if ( $name =~ /First name +/ )           { $first_name      = $valu; }
	if ( $name =~ /Middle initials +/ )      { $middle_initials = $valu; }
	if ( $name =~ /Department +/ )           { $department      = $valu; }
	if ( $name =~ /Institution +/ )          { $institution     = $valu; }
	if ( $name =~ /Address +/ )              { $address1        = $valu; }
	if ( $name =~ /Country +/ )              { $country         = $valu; }
	if ( $name =~ /Telephone +/ )            { $telephone       = $valu; }
	if ( $name =~ /Fax +/ )                  { $fax             = $valu; }
	if ( $name =~ /Email +/ )                { $email           = $valu; }
#	if ( $name =~ /^ +/ and length($name) >= 3  ) { 
	if ( $name =~ /^ +/ and length($valu) >= 1  ) { 
	    ++$adno; $addr = 'address'.+$adno ;
	    $$addr = $valu;
	    $nal = length($name);
#	    print "\n(****$addr=) $$addr, len=$nal\n";
	}
#	print "\ntxt = $name AND valu = $valu";
    }
    print POFIL "\nfirstname=$first_name";
#    print  "firstname=$first_name";
    print POFIL "\nmiddlename=$middle_initials";  
    print POFIL "\nlastname=$last_name";      
    print POFIL "\ninstitution=$institution";  
    print POFIL "\ndepartment=$department";
    print POFIL "\naddress=$address1, $address2, $address3";
#    print POFIL "\naddress=$address2";         
#    print POFIL "\naddress=$address3";
    print POFIL "\ncountry1=$country"; 
    print POFIL "\ntelefon=$telephone";
    print POFIL "\nFAX=$fax";              
    print POFIL "\ne-mail=$email";
    return;
}

# ==========================
sub citation_info
{
    ($citeinf_txt,$temptxt) = split(/\nIV\. +SEQUENCE/,$fulsub);
    ($temptxt,$citeinf_txt) = split(/\nIII\. +/,$citeinf_txt);
    ($authrs,$temptxt) = split(/\(e\.g\./,$citeinf_txt);
    ($temptxt,$authrs) = split(/INFORMATION/,$authrs);
    $authrs =~ s/^\s+//g;
# -------------- REFERENCE -----------
    ($ref_txt,$temptxt) = split(/\nPublication status/,$citeinf_txt);
    ($temptxt,$ref_txt) = split(/extra authors\)\n/,$ref_txt);
#    print "\n--REFTEXT --\n($ref_txt)\n--";
    ($tit_txt,$temptxt) = split(/\nJournal +:/,$ref_txt);
    $tit_txt =~ s/\n/ /g; $tit_txt =~ s/ +/ /g; 
    $tpos = index($tit_txt,':');
    $title = substr($tit_txt,$tpos+1);
    $title =~ s/^ +//;    $title =~ s/\s+/ /g;
    print POFIL "\n1title=$title";
#    print "\n--Citation info.--\n($citeinf_txt)\n---";
# -------- AUTHOR NAMES --------------- 
# Do not expect a ':' in Author names!
#    print "\n--AUTHORS --\n($authrs)\n--";
    $auno = 0;
    while ( $authrs =~ /(.*):(.*)\n/g ) {
	$nvp = $&;
	++$auno; $auth = 'author'.+$auno;
	($temptxt,$auname) = split(/:/,$nvp);
	$auname =~ s/\n//g;	
	$auname =~ s/^ +//;
	$$auth = $auname;
	($lname,$ffname) = split(/ /,$auname);
#	print POFIL "\nAU-test=Lname($lname)Fname($ffname)";
	$fname = ''; $mname = '';
	if ( $ffname =~ /\A\w+\.{0,1}/ )    { $fname = $& };
	if ( $ffname =~ /\w+\.{0,1} *\Z/ )  { $mname = $& };
	if ( $ffname =~ /\A\w+\.{0,1} *\Z/) { $mname = '' };
	$fir = 'fnam'.+$auno;   $$fir = $fname;
	$mid = 'mnam'.+$auno;   $$mid = $mname;
	$las = 'lnam'.+$auno;	$$las = $lname;
	print POFIL "\n1$auth\_firstname=$fname";
	print POFIL "\n1$auth\_middlename=$mname";
	print POFIL "\n1$auth\_lastname=$lname";
    }
    $journal = '';
    ($jrl_txt,$temptxt) = split(/\nVolume +:/,$ref_txt);
    ($temptxt,$journal) = split(/\nJournal +:/,$jrl_txt);
    $journal =~ s/\n/ /g; $journal =~ s/ +/ /g; $journal =~ s/^ +//;
    print POFIL "\n1possessions=$journal";
# ---	
    ($vol_txt,$temptxt) = split(/\nFirst page +:/,$ref_txt);
    ($temptxt,$volume) = split(/\nVolume +:/,$vol_txt);
    $volume =~ s/\n/ /g; $volume =~ s/ +/ /g; $volume =~ s/^ +//;
    if ( length($volume) < 1 ) { $volume = 0; } 
    print POFIL "\n1volume=$volume";
# ---
    ($fp_txt,$temptxt) = split(/\nLast page +:/,$ref_txt);
    ($temptxt,$fpage) = split(/\nFirst page +:/,$fp_txt);
    $fpage =~ s/\n/ /g; $fpage =~ s/ +/ /g; $fpage =~ s/^ +//;
    if ( length($fpage) < 1 ) { $fpage = 0; } 
    print POFIL "\n1first page=$fpage";
    
    ($lp_txt,$temptxt) = split(/\nYear +:/,$ref_txt);
    ($temptxt,$lpage) = split(/\nLast page +:/,$lp_txt);
    $lpage =~ s/\n/ /g; $lpage =~ s/ +/ /g; $lpage =~ s/^ +//;
    if ( length($lpage) < 1 ) { $lpage = 0; } 
    print POFIL "\n1last page=$lpage";
    
    ($yr_txt,$temptxt) = split(/\nInstitute \(if thesis\):/,$ref_txt);
    ($temptxt,$year) = split(/\nYear +:/,$yr_txt);
    $year =~ s/\n/ /g; $year =~ s/ +/ /g; $year =~ s/^ +//;
    if ( length($year) < 1 ) { $year = 1999; } 
    print POFIL "\n1year=$year";

    ($temptxt,$institute) = split(/\nInstitute \(if thesis\):/,$ref_txt);
    $institute =~ s/\n/ /g; $institute =~ s/ +/ /g; $institute =~ s/^ +//;
    print POFIL "\n1university=$institute";
# --------- PUBLICATION STATUS ----------
    $pubty = '';
    ($temptxt,$pubstat_txt) = split(/\nMark one of the following *\n/,$citeinf_txt);
#    print "\nPublication-status=($pubstat_txt)";
    
    if ( $pubstat_txt =~ /In preparation +\[[X|x]\]/ ) {
	print POFIL "\n1data_type=In preparation";
	$pubty = 'InPreparation';
    }    
    if ( $pubstat_txt =~ /Accepted +\[[X|x]\]/ ) {
	print POFIL "\n1data_type=Accepted";
    }
    if ( $pubstat_txt =~ /Published +\[[X|x]\]/ ) {
	print POFIL "\n1data_type=Published";
    }
    $is_thesis = 0;
    if ( $pubstat_txt =~ /Thesis\/Book +\[[X|x]\]/ ) {
	print POFIL "\n1data_type=Thesis or book";
	$is_thesis = 1;
    }    
    if ( $pubstat_txt =~ /No plans to publish +\[[X|x]\]/ ) {
	print POFIL "\n1data_type=No plans to publish";
	$pubty = 'NoPlanToPublish';
    }
    print POFIL "\nnumber_of_citations=1";
    return;
}

sub seq_info_annotation
{
    ($seqinf_txt,$temptxt) = split(/\nV\. +SOURCE INFO/,$fulsub);
    ($temptxt,$seqinf_txt) = split(/\nIV\. +/,$seqinf_txt);
#    print "\n--Seq-4-info.--\n($seqinf_txt)\n---";	
    $sequence_len = 0;
    if ( $seqinf_txt =~ /Sequence length \(bp\) +: *\d+/ ) {
	$seqlen = $&;
	$seqlen =~ s/Sequence length \(bp\) +://; 
	$sequence_len = int($seqlen);
    }
    print POFIL "\nseq_length=$sequence_len";
# ----- Assuming atleast one item is marked 'X' else it is DNA (%^&#!*@$!!)
    ($moltype_txt,$temptxt) = split(/\nMark if either/,$seqinf_txt);
    $molecule_type = 'DNA';
    if ( $moltype_txt =~ /\n(.*)\[[X|x]\]/ ) {
	$molecule_type = $&;	     $molecule_type =~ s/\[[X|x]\]//; 
	$molecule_type =~ s/ +$//;   $molecule_type =~ s/\n//g;
	if ( $molecule_type =~ / RNA/ || $molecule_type =~ / mRNA/ ) {
	    $molecule_type = 'RNA';
	}
    }
    print POFIL "\nsequenced_mol=$molecule_type";
    ($temptxt,$cirvec_txt) = split(/\nMark if either/,$seqinf_txt);
    if ( $cirvec_txt =~ /Circular +\[[X|x]\]/ ) {
	print POFIL "\ncircular=on";
    }
    $chek_vec = 'OFF';
    if ( $cirvec_txt =~ /ontamination +\[[X|x]\]/ ) {
	$chek_vec = 'ON';   
    }
    print POFIL "\nchek_vector_contamination=$chek_vec";
    return;    
}

sub source_info
{
    ($source_txt,$temptxt) = split(/\nVI\. +FEATURES OF/,$fulsub);
    ($temptxt,$source_txt) = split(/\nV\. +/,$source_txt);
#    print "\n--Source-info.--\n($source_txt)\n---";
    $organism = '';
    if ( $source_txt =~ /Organism +:(.*)\n/ ) {
	$organism = $&;	    $organism =~ s/Organism +://;	
	$organism =~ s/\nSub species +://;  $organism =~ s/\n/ /g; 
	$organism =~ s/ +/ /g;  $organism =~ s/ +$//; $organism =~ s/^ +//;
    }
    print POFIL "\norganism=$organism";

    $sub_species = '';
    if ( $source_txt =~ /Sub species +:(.*)\n/ ) {
	$sub_species = $&;	$sub_species =~ s/Sub species +://;	
	$sub_species =~ s/\n/ /g; 	$sub_species =~ s/ +/ /g;  
	$sub_species =~ s/ +$//;        $sub_species =~ s/^ +//;
    }
    print POFIL "\nsub_species=$sub_species";

    $strain = '';
    if ( $source_txt =~ /Strain +:(.*)\n/ ) {
	$strain = $&;	$strain =~ s/Strain +://;	
	$strain =~ s/\n/ /g; 	$strain =~ s/ +/ /g;  
	$strain =~ s/ +$//;     $strain =~ s/^ +//;
    }
    print POFIL "\nstrain=$strain";

    $cultivar = '';
    if ( $source_txt =~ /Cultivar +:(.*)\n/ ) {
	$cultivar = $&;	$cultivar =~ s/Cultivar +://;	
	$cultivar =~ s/\n/ /g; 	$cultivar =~ s/ +/ /g;  
	$cultivar =~ s/ +$//;   $cultivar  =~ s/^ +//;
    }
    print POFIL "\ncultivar=$cultivar";

    $variety = '';
    if ( $source_txt =~ /Variety +:(.*)\n/ ) {
	$variety = $&;	        $variety =~ s/Variety +://;	
	$variety =~ s/\n/ /g; 	$variety =~ s/ +/ /g;  
	$variety =~ s/ +$//;    $variety =~ s/^ +//;
    }
    print POFIL "\nvariety=$variety";

    $iso_ind = '';
    if ( $source_txt =~ /Isolate\/individual +:(.*)\n/ ) {
	$iso_ind = $&;	$iso_ind =~ s/Isolate\/individual +://;	
	$iso_ind =~ s/\n/ /g; 	$iso_ind =~ s/ +/ /g;  
	$iso_ind =~ s/ +$//;    $iso_ind =~ s/^ +//;
    }
    print POFIL "\nisolate=$iso_ind";

    $dev_stage = '';
    if ( $source_txt =~ /Developmental stage +:(.*)\n/ ) {
	$dev_stage = $&;     $dev_stage =~ s/Developmental stage +://;	
	$dev_stage =~ s/\n/ /g;    $dev_stage =~ s/ +/ /g;  
	$dev_stage =~ s/ +$//;     $dev_stage =~ s/^ +//;
    }
    print POFIL "\ndev_stage=$dev_stage";

    $tiss_type = '';
    if ( $source_txt =~ /Tissue type +:(.*)\n/ ) {
	$tiss_type = $&;	   $tiss_type =~ s/Tissue type +://;	
	$tiss_type =~ s/\n/ /g;    $tiss_type =~ s/ +/ /g;  
	$tiss_type =~ s/ +$//;     $tiss_type =~ s/^ +//;
    }
    print POFIL "\ntissue_type=$tiss_type";

    $cell_type = '';
    if ( $source_txt =~ /Cell type +:(.*)\n/ ) {
	$cell_type = $&;	   $cell_type =~ s/Cell type +://;	
	$cell_type =~ s/\n/ /g;    $cell_type =~ s/ +/ /g;  
	$cell_type =~ s/ +$//;     $cell_type =~ s/^ +//;
    }
    print POFIL "\ncell_type=$cell_type";

    $cell_line = '';
    if ( $source_txt =~ /Cell line +:(.*)\n/ ) {
	$cell_line = $&;	   $cell_line =~ s/Cell line +://;	
	$cell_line =~ s/\n/ /g;    $cell_line =~ s/ +/ /g;  
	$cell_line =~ s/ +$//;     $cell_line =~ s/^ +//;
    }
    print POFIL "\ncell_line=$cell_line";

    $clone1 = '';
    if ( $source_txt =~ /Clone +:(.*)\n/ ) {
	$clone1 = $&;	        $clone1 =~ s/Clone +://;	
	$clone1 =~ s/\n/ /g;    $clone1 =~ s/ +/ /g;  
	$clone1 =~ s/ +$//;     $clone1 =~ s/^ +//;
    }
    print POFIL "\nclone=$clone1";

    $clone2 = '';
    if ( $source_txt =~ /Clone \((.*)\) +:(.*)\n/ ) {
	$clone2 = $&;	        $clone2 =~ s/Clone \((.*)\) +://;	
	$clone2 =~ s/\n/ /g;    $clone2 =~ s/ +/ /g;  
	$clone2 =~ s/ +$//;     $clone2 =~ s/^ +//;
    }
    print POFIL "\nclone=$clone2";

    $clone_lib = '';
    if ( $source_txt =~ /Clone library +:(.*)\n/ ) {
	$clone_lib = $&;	   $clone_lib =~ s/Clone library +://;	
	$clone_lib =~ s/\n/ /g;    $clone_lib =~ s/ +/ /g;  
	$clone_lib =~ s/ +$//;     $clone_lib =~ s/^ +//;
    }
    print POFIL "\nclone_lib.=$clone_lib";

    $chromosome = '';
    if ( $source_txt =~ /Chromosome +:(.*)\n/ ) {
	$chromosome = $&;	    $chromosome =~ s/Chromosome +://;	
	$chromosome =~ s/\n/ /g;    $chromosome =~ s/ +/ /g;  
	$chromosome =~ s/ +$//;     $chromosome =~ s/^ +//;
    }
    print POFIL "\nchromosome=$chromosome";

    $map_position = '';
    if ( $source_txt =~ /Map position +:(.*)\n/ ) {
	$map_position = $&;	    $map_position =~ s/Map position +://;	
	$map_position =~ s/\n/ /g;    $map_position =~ s/ +/ /g;  
	$map_position =~ s/ +$//;     $map_position =~ s/^ +//;
    }
    print POFIL "\nmap=$map_position";

    $haplotype = '';
    if ( $source_txt =~ /Haplotype +:(.*)\n/ ) {
	$haplotype = $&;	   $haplotype =~ s/Haplotype +://;	
	$haplotype =~ s/\n/ /g;    $haplotype =~ s/ +/ /g;  
	$haplotype =~ s/ +$//;     $haplotype =~ s/^ +//;
    }
    print POFIL "\nhaplotype=$haplotype";

    $natural_host = '';
    if ( $source_txt =~ /Natural host +:(.*)\n/ ) {
	$natural_host = $&;	    $natural_host =~ s/Natural host +://;	
	$natural_host =~ s/\n/ /g;    $natural_host =~ s/ +/ /g;  
	$natural_host =~ s/ +$//;     $natural_host =~ s/^ +//;
    }
    print POFIL "\nspecific_host=$natural_host";

    $lab_host = '';
    if ( $source_txt =~ /Laboratory host +:(.*)\n/ ) {
	$lab_host = $&;	    $lab_host =~ s/Laboratory host +://;	
	$lab_host =~ s/\n/ /g;    $lab_host =~ s/ +/ /g;  
	$lab_host =~ s/ +$//;     $lab_host =~ s/^ +//;
    }
    print POFIL "\nlab_host=$lab_host";

    $is_macronuc = '';    $is_mnuc = '';
    if ( $source_txt =~ /Macronuclear +\[[X|x]\]\n/ ) {
	$is_macronuc = 'ON';     $is_mnuc = 'Macronuclear';
    }
    print POFIL "\nMacronuclear ?=$is_macronuc";

    $imm_tcell_rec = '';
    if ( $source_txt =~ /Germline +\[[X|x]\]\n/ ) {
	print POFIL "\ngermline=on";
	print POFIL "\nimmunoglobulin=on";
    }
    if ( $source_txt =~ /Rearranged +\[[X|x]\]\n/ ) {
	print POFIL "\nrearranged=on";
	print POFIL "\nimmunoglobulin=on";
    }
    $vir_type = '';
    if ( $source_txt =~ /Proviral +\[[X|x]\]\n/ ) {
	$vir_type = 'proviral'; 
    }
    if ( $source_txt =~ /Virion +\[[X|x]\]\n/ ) {
	$vir_type = 'virion'; 
    }
    print POFIL "\nviral_kind=$vir_type";

    $organelle = '';
    if ( $source_txt =~ /Chloroplast +\[[X|x]\]\n/ ) {
	$organelle = 'chloroplast'; 
    }
    if ( $source_txt =~ /Mitochondrion +\[[X|x]\]\n/ ) {
	$organelle = 'mitochondrion'; 
    }
    if ( $source_txt =~ /Chromoplast +\[[X|x]\]\n/ ) {
	$organelle = 'chromoplast'; 
    }
    if ( $source_txt =~ /Kinetoplast +\[[X|x]\]\n/ ) {
	$organelle = 'kinetoplast'; 
    }
    if ( $source_txt =~ /Cyanelle +\[[X|x]\]\n/ ) {
	$organelle = 'cyanelle'; 
    }
    if ( $source_txt =~ /Plasmid \(not clone\) +\[[X|x]\]\n/ ) {
	$organelle = 'plasmid';
    }
    print POFIL "\norganelle_type=$organelle";

    ($temptxt,$note_txt) = split(/\nNote +:/,$source_txt);
    $note_txt =~ s/\n/ /g;   $note_txt =~ s/ +/ /g; 
    $note_txt =~ s/^ +//;    $note_txt =~ s/ +$//;
    print POFIL "\nclassification=$note_txt";
    return;
}

sub features_info
{
    ($features_txt,$temptxt) = split(/\nVII\. +SEQUENCE INFO/,$fulsub);
    ($temptxt,$features_txt) = split(/\nVI\. +/,$features_txt);
    $features_txt =~ s/(.*)FEATURE NO\.1/FEATURE NO\.1/s;
#    print "\n--Features-info.--($features_txt)\n---";
    @all_features = split(/\][\n]{2}/,$features_txt);
    $ftnum =0;
    foreach $featxt( @all_features ) {
	++$ftnum; 
#	print "\n===[$ftnum]=$featxt\n===\n";
#	print POFIL "\n--------------------------------";
	if ( $featxt =~ /Feature key +:(.*)\n/ ) {
	    $txt = 'key'.+$ftnum;
	    $$txt = $&;	  $$txt =~ s/Feature key +://;  $$txt =~ s/\n//; 
	    $$txt =~ s/ +/ /g;     $$txt =~ s/ $//; $$txt =~ s/^ +//;	    
	    $feat_name[$featnum] = $$txt; ++$featnum; 
	    $ftkey = uc($$txt); $is_valid_ftkey = 0;
	    foreach $ftkchk ( @valid_ft_keys ) {
		$uft = uc($ftkchk); $le1 = length($uft); 
		$le2 = length($ftkey);
#		print "\ncomparing ($uft)($ftkey)";
		if ( $uft =~ /$ftkey/ && $le1 == $le2) 
		{ $is_valid_ftkey = 1; }
	    }
	    if ( $is_valid_ftkey == 0 ) 
	    { print "\n$ftkey - is invalid feature key"; }
#	    print POFIL "\nprefix=$$txt$ftnum";
	    if ( $ftkey =~ /CDS/ ) {
		++$ftcds;
		$ftr = 'CDS_simple'.+$ftcds;
#		print POFIL "\nprefix=$$txt$ftnum";
		print POFIL "\nfeature=$ftcds";
		print POFIL "\nprefix=$ftr";
	    } else {
#		$ftr = $$txt.+'__'.+$ftnum;
		$ftr = $$txt;
		print POFIL "\nfeature=$ftr";
		($fenam,@temp) = split(/ /,$ftr);
		print POFIL "\nfeatureName=$fenam";
		print POFIL "\nfeatureNo=1";
#		print POFIL "\nfeature=$$txt$ftnum";
	    }
	}
	$fromnum=0; $parti = '';
	while ( $featxt =~ /From +:(.*)\n/g ) {
	    ++$fromnum; 
	    $txt = 'from'.+$ftnum.+$fromnum;
#	    $txt = 'from'.+$fromnum;
	    if ( $$txt =~ /\d+/ ) { $$txt = $& };
	    $$txt = $&;	     $$txt =~ s/From +://;
	    $$txt =~ s/\n//; $$txt =~ s/ +/ /g;
	    $$txt =~ s/ $//; $$txt =~ s/^ +//;
	    $$txt =~ tr/0-9<>//cd;
	    if ( $$txt =~ /[<|>]/ ) { 
		$parti = 'partial'; 
#		print POFIL "\n$txt=$$txt";
	    }
	    print POFIL "\n$txt=$$txt";
	    $ltf1 = length($$txt);
	    if ( $ltf1 < 1  ) 
	    { print "\nFeature Location - is invalid."; }
	}
	$tonum=0;
	while ( $featxt =~ /To +:(.*)\n/g ) {
	    ++$tonum; 
	    $txt = 'to'.+$ftnum.+$tonum;
#	    $txt = 'to'.+$tonum;
	    if ( $$txt =~ /\d+/ ) { $$txt = $& };
	    $$txt = $&;	     $$txt =~ s/To +://;
	    $$txt =~ s/\n//; $$txt =~ s/ +/ /g;
	    $$txt =~ s/ $//; $$txt =~ s/^ +//;
	    $$txt =~ tr/0-9<>//cd;
	    if ( $$txt =~ /[<|>]/ ) { $parti = 'partial'; }
	    print POFIL "\n$txt=$$txt";
	    $ltf2 = length($$txt);
	    if ( $ltf2 < 1  ) 
	    { print "\nFeature Location - is invalid."; }
	}
	$opstr = 'jstr'.+$ftnum; $$opstr = '';
	if ( $fromnum > 1 && $tonum > 1 ) {
	    $$opstr = 'join(';
	    for( $i=1;$i<=$fromnum;++$i ) {
		$txt1 = 'from'.+$ftnum.+$i;
		$$txt1 =~ tr/0-9<>//cd;
		$txt2 = 'to'.+$ftnum.+$i;
		$$txt2 =~ tr/0-9<>//cd;
		$$opstr = $$opstr.+$$txt1.+'..'.+$$txt2.+',';
	    }
	    chop($$opstr); $$opstr=$$opstr.+')';
	    print POFIL "\n$$opstr";
	}
	if ( $featxt =~ /Gene name +:(.*)\n/ ) {
	    $txt = 'gene'.+$ftnum;
	    $$txt = $&;	     $$txt =~ s/Gene name +://;
	    $$txt =~ s/\n//; $$txt =~ s/ +/ /g;
	    $$txt =~ s/ $//; $$txt =~ s/^ +//;
	    print POFIL "\n$txt=$$txt";
	}
	if ( $featxt =~ /Product name +:(.*)\n/ ) {
	    $txt = 'product'.+$ftnum;
	    $$txt = $&;	     $$txt =~ s/Product name +://;
	    $$txt =~ s/\n//; $$txt =~ s/ +/ /g;
	    $$txt =~ s/ $//; $$txt =~ s/^ +//;
	    print POFIL "\n$txt=$$txt";
	}
	if ( $featxt =~ /Codon start 1,2 or 3 +:(.*)\n/ ) {
	    $txt = 'codstart'.+$ftnum;
	    $$txt = $&;	     $$txt =~ s/Codon start 1,2 or 3 +://;
	    $$txt =~ s/\n//; $$txt =~ s/ +/ /g;
	    $$txt =~ s/ $//; $$txt =~ s/^ +//;
	    print POFIL "\n$txt=$$txt";
	}
	if ( $featxt =~ /EC number +:(.*)\n/ ) {
	    $txt = 'ecnum'.+$ftnum;
	    $$txt = $&;	     $$txt =~ s/EC number +://;
	    $$txt =~ s/\n//; $$txt =~ s/ +/ /g;
	    $$txt =~ s/ $//; $$txt =~ s/^ +//;
	    print POFIL "\n$txt=$$txt";
	}
	$txt = 'complem_strand'.+$ftnum;
	$$txt = 'NO';
	if ( $featxt =~ /Complementary strand +\[[X|x]/ ) {
	    $$txt = 'YES';
	} 
	print POFIL "\n$txt=$$txt";
	$txt = 'experim_evid'.+$ftnum;
	$$txt = '';
	if ( $featxt =~ /Experimental evidence +\[[X|x]/ ) {
	    $$txt = 'EXPERIMENTAL';
	}
	print POFIL "\n$txt=$$txt";
    }
#    print POFIL "\n--------------------------------------";
#
# -------- write the hash file for webin....
#
    open FHFIL, '>featu.hash' or die "Could not open featu.hash!!";
    print FHFIL "Citation=2\n";
    for ($klo=0;$klo<$featnum;++$klo) {
	$qfeat = $feat_name[$featnum];
	$totkli[$klo] = 0;
	for( $kli=0;$kli<$featnum;++$kli ) {
	  if ( $qfeat == $feat_name[$kli] ) {
	  	++$totkli[$kli];
	  }
	}
    }
    for ($klo=0;$klo<$featnum;++$klo) {
	if ( $feat_name[$klo] =~ /CDS/ ) {
	   $feat_name[$klo] = 'CDS_simple';
	}		
	$feat_name[$klo] =~ s/ /_/g;
	print FHFIL "$feat_name[$klo]=$totkli[$klo]\n";
    }
    return;
}

sub seq_info_sequence
{
    ($temptxt,$seqdat_inf) = split(/\nVII\. +SEQUENCE INFORMATION/,$fulsub);
#    print "\nSequence-data-info\n$seqdat_inf";
    if ( $seqdat_inf =~ /BEGINNING OF SEQUENCE:(.*)END OF SEQUENCE/s ) {
	$seqtxt = $&;
	$seqtxt =~ s/BEGINNING OF SEQUENCE//;
	$seqtxt =~ s/END OF SEQUENCE//;
	$seqtxt =~ s/\n//g;$seqtxt =~ s/\d+//g;$seqtxt =~ s/://g;
	$seqtxt = lc($seqtxt);
	print POFIL "\nsequence=$seqtxt";
    }
    $transnum=0;
    while ( $seqdat_inf =~ /BEGINNING OF TRANSLATION:(.*)END OF TRANSLATION/sg ) {
	++$transnum;
	print POFIL "\nprefix=CDS_simple$transnum";
	$transeq = $&;
	$transeq =~ s/BEGINNING OF TRANSLATION//;
	$transeq =~ s/END OF TRANSLATION//;
	$transeq =~ s/\n//g;$transeq =~ s/\d+//g;$transeq =~ s/://g;
	$txtt = 'CDS_simple'.+$transnum.+'translation';
	print POFIL "\n$txtt=$transeq";
    }
    return;
}

sub generate_flatfile
{
    open FLFIL, $flat_file  or die "Could not open-write $flat_file!!";
    $sub_cat = ''; $glist = ''; $gkwlis='';
    if ( $vir_type =~ /VIR/ ) { $sub_cat = 'VRL' } 
    print FLFIL "ID   ENTRYNAME  $conf_status; $molecule_type; $sub_cat; $sequence_len BP.\n";
    if ( $conf_status =~ /confidential/ ) {
	print FLFIL "XX\n";
	print FLFIL "HD  * confidential $conf_day-$conf_mon-$conf_year\n";
    }
    print FLFIL "XX\n";
#    print FLFIL "AC   emsubac\n";
#    print FLFIL "XX\n";
    for ( $ii=1;$ii<=$ftnum;++$ii) {
	$gene = 'gene'.+$ii;
	$gg = &protect($$gene);
#	$gg = $$gene;
	$resul = $klist =~ /$gg/;
	if ( $resul == 0  ) {
	    $klist = $klist.+$gg.+', ';
	}
#	print "\n2-ggene = ($gg) klist = ($klist)";
    }
    $klist=~ s/, $//; 
    $solist = $sub_species.+', '.+$strain.+', ';
    $solist = $solist.+$cultivar.+', '.+$variety.+', ';
    $solist = $solist.+$iso_ind.+', '.+$dev_stage.+', ';
    $solist = $solist.+$tiss_type.+', '.+$cell_type.+', ';
    $solist = $solist.+$cell_line.+', '.+$clone1.+', ';
    $solist = $solist.+$clone2.+', '.+$clone_lib.+', ';
    $solist = $solist.+$chromosome.+', '.+$map_position.+', ';
    $solist = $solist.+$haplotype.+', '.+$natural_host.+', ';
    $solist = $solist.+$lab_host.+', '.+$is_mnuc.+', ';
    $solist = $solist.+$imm_tcell_rec.+', '.+$vir_type.+', ';
    $solist = $solist.+$organelle.+';';
    $solist =~ s/ +,//g;    $solist =~ s/ +, +//g;
    $delin = $organism.+', '.+$klist.+', '.+$parti.+', '.+$solist; 
#    print FLFIL "---$delin--\n";
    $delin =~ s/ +, +//g;
    $delin =~ s/,,/,/g;
    $delin =~ s/, ;$/;/;
    &wrap_put_strin($delin,'DE');
    print FLFIL "XX\n";
    &wrap_put_strin($klist.+';','KW');
    print FLFIL "XX\n";
    print FLFIL "OS   $organism;\n";
    print FLFIL "XX\n";
#    &wrap_put_strin($note_txt.+';','OC');
#    print FLFIL "XX\n";
# -------------------- REFERENCES -----------------
    for ( $ii=1;$ii<=$auno;++$ii) {
	$n1 = 'fnam'.+$ii;  $n2 = 'mnam'.+$ii;  $n3 = 'lnam'.+$ii;
	$ralist = $ralist.+$$n3.+' '.+$$n1.+' '.+$$n2.+', ';
    }
    $ralist =~ s/ +$//;    $ralist =~ s/ ,//g;    $ralist =~ s/,$//;
    print FLFIL "RN   [1]\n";
    &wrap_put_strin($ralist.+';','RA');
    &wrap_put_strin($title.+';','RT');
#    $reflist = $journal.+', '.+$volume.+' '.+$fpage.+'-'.+$lpage.+' '.+$institute;
    $reflist = $journal.+', '.+$volume.+':'.+$fpage.+'-'.+$lpage.+'('.+$year.+');';
    if ( $is_thesis == 1 ) {
	$reflist = 'Thesis ('.+$year.+') '.+$institute;
    }
    if ( $pubty =~ /InPreparation/ ) {
	$reflist = 'Unpublished [InPreparation]';
    }
    if ( $pubty =~ /NoPlanToPublish/ ) {
	$reflist = 'Unpublished [NoPlanToPublish]';
    }
    &wrap_put_strin($reflist.+';','RL');
    print FLFIL "XX\n";
    $ii=1; $ralist = '';
    $n1 = 'fnam'.+$ii;  $n2 = 'mnam'.+$ii;  $n3 = 'lnam'.+$ii;
    $ralist = $ralist.+$$n3.+' '.+$$n1.+' '.+$$n2.+', ';
    $ralist =~ s/ +$//;    $ralist =~ s/ ,//g;    $ralist =~ s/,$//;
    print FLFIL "RN   [2]\n";
    print FLFIL "RP   1-$sequence_len\n";
    &wrap_put_strin($ralist.+';','RA');
    $nday  = (localtime)[3];  
    $nmonth=(JAN,FEB,MAR,APR,MAY,JUN,JUL,AUG,SEP,OCT,NOV,DEC)[(localtime)[4]]; 
    $nyear = (localtime)[5]; if ( $nyear < 50 ) { $nyear+=2000;} 
    else { $nyear+=1900; };
    print FLFIL "RT   ;\n";
    print FLFIL "RL   Submitted ($nday-$nmonth-$nyear) to the EMBL/GenBank/DDBJ databases.\n";
#.+to$journal.+', '.+$volume.+' '.+$fpage.+'-'.+$lpage.+' '.+$institute;
    $reflist = $last_name.+' '.+$first_name.+' '.+$middle_initials.+', ';  
    $reflist = $reflist.+$department.+', '.+$institution.+' ';
    $kj =1;
    while ( $kj <= $adno ) {
	$adrs = 'address'.+$kj;
	$reflist = $reflist.+$$adrs.+', ';
	++$kj;
    }
    $reflist = $reflist.+$country;
    &wrap_put_strin($reflist.+';','RL');
    print FLFIL "XX\n";
# ----------------------------- FEATURES ---------------
    print FLFIL "FH   Key             Location/Qualifiers\n";
    print FLFIL "FH\n";
    print FLFIL "FT   source          1..$sequence_len\n";          
    print FLFIL "FT                   /organism=\"$organism\"\n";          
    if ( length($sub_species) > 0 ) { 
	print FLFIL "FT                   /sub_species=\"$sub_species\"\n";
    }
    if ( length($strain) > 0 ) { 
	print FLFIL "FT                   /strain=\"$strain\"\n";
    }
    if ( length($cultivar) > 0 ) { 
	print FLFIL "FT                   /cultivar=\"$cultivar\"\n";
    }
    if ( length($iso_ind) > 0 ) { 
	print FLFIL "FT                   /isolate=\"$iso_ind\"\n";
    }
    if ( length($dev_stage) > 0 ) { 
	print FLFIL "FT                   /dev_stage=\"$dev_stage\"\n";
    }
    if ( length($tiss_type) > 0 ) { 
	print FLFIL "FT                   /tissue_type=\"$tiss_type\"\n";
    }
    if ( length($cell_line) > 0 ) { 
	print FLFIL "FT                   /cell_line=\"$cell_line\"\n";
    }
    if ( length($clone1) > 0 ) { 
	print FLFIL "FT                   /clone=\"$clone1\"\n";
    }
    if ( length($clone2) > 0 ) { 
	print FLFIL "FT                   /alt_clone=\"$clone2\"\n";
    }
    if ( length($clone_lib) > 0 ) { 
	print FLFIL "FT                   /clone_lib=\"$clone_lib\"\n";
    }
    if ( length($chromosome) > 0 ) { 
	print FLFIL "FT                   /chromosome=\"$chromosome\"\n";
    }
    if ( length($map_position) > 0 ) { 
	print FLFIL "FT                   /map_position=\"$map_position\"\n";
    }
    if ( length($haplotype) > 0 ) { 
	print FLFIL "FT                   /haplotype=\"$haplotype\"\n";
    }
    if ( length($natural_host) > 0 ) { 
	print FLFIL "FT                   /natural_host=\"$natural_host\"\n";
    }
    if ( length($lab_host) > 0 ) { 
	print FLFIL "FT                   /lab_host=\"$lab_host\"\n";
    }
    if ( length($is_mnuc) > 0 ) { 
	print FLFIL "FT                   /is_macronuclear=\"$is_mnuc\"\n";
    }
    if ( length($imm_tcell_rec) > 0 ) { 
	print FLFIL "FT                   /tcell_receptor=\"$imm_tcell_rec\"\n";
    }
    if ( length($organelle) > 0 ) { 
	print FLFIL "FT                   /organelle=\"$organelle\"\n";
    }
    for ($jj=1; $jj<=$ftnum; ++$jj) {
	$ftk = 'key'.+$jj; $fro = 'from'.+$jj.+'1'; $tro = 'to'.+$jj.+'1';
	$opstr = 'jstr'.+$jj; $nsp1 = ' '; $nsp2 = length($$ftk);
	for ( $mm=1;$mm<=(15-$nsp2); ++$mm) { $nsp1=$nsp1.+' ';}
	if ( length($$opstr) > 0 ) {	    
	    print FLFIL "FT   $$ftk$nsp1$$opstr\n";
	} else {
	    print FLFIL "FT   $$ftk$nsp1$$fro..$$tro\n";
	} 
	$te = 'gene'.+$jj;
	if ( length($$te) > 0 ) { 
	    print FLFIL "FT                   /gene=\"$$te\"\n";
	}
	$te = 'product'.+$jj;
	if ( length($$te) > 0 ) { 
	    print FLFIL "FT                   /product=\"$$te\"\n";
	}
	$te = 'codstart'.+$jj;
	if ( length($$te) > 0 ) { 
	    print FLFIL "FT                   /codon_start=\"$$te\"\n";
	}
	$te = 'ecnum'.+$jj;
	if ( length($$te) > 0 ) { 
	    print FLFIL "FT                   /ec_number=\"$$te\"\n";
	}
	$te = 'experim_evid'.+$jj;
	if ( length($$te) > 0 ) { 
	    print FLFIL "FT                   /evidence=\"$$te\"\n";
	}
    }
# ---------------- SEQUENCE --------------
    print FLFIL "XX\n";
    &output_sequence($seqtxt);
    print FLFIL "//\n";
    close(FLFIL);
    return;       
}

sub output_sequence{
    local($sequen) = @_;
    $sequen =~ s/ +//g;
#    print "\n$sequen\n";
    &base_composition($sequen);
#    print FLFIL "SQ    Sequence $sequence_len BP;\n";
    $l1 = length($sequen);
    if ( $l1 != $sequence_len ) { print "\nSequence (length) error!";}
    $j=0; $j2 = 50;
    while ( $j < $l1 ) {
	$frag1 = substr($sequen,$j,50);
	$l2  = length($frag1);
	$j2  = $j+1;
#	$spc = tochar($j2);
	$spc = $j2;
	$spc=~ s/ +//g;
	if ( $j2 <= 9 )        { 
	    $spc = '       '.+$spc.+'  '; }
	if ( $j2 > 9 && $j2 <= 99 )    { 
	    $spc = '      '.+$spc.+'  ';}
	if ( $j2 > 99 && $j2 <= 999 )  { 
	    $spc = '     '.+$spc.+'  '; }
	if ( $j2 > 999 && $j2 <= 9999 ){ 
	    $spc = '    '.+$spc.+'  ';  }
	if ( $j2 > 9999 && $j2 <= 99999 ){ 
	    $spc = '   '.+$spc.+'  '; }	      
	if ( $j2 > 99999 && $j2 <= 999999 ){ 
	    $spc = '  '.+$spc.+'  '; }	
	$sqlin=$spc;
	$j3 = 0;
	while ( $j3 < 50 ) {
	    $sub_frag = substr($frag1,$j3,10);
	    $sqlin=$sqlin.+$sub_frag.+' ';
	    $j3=$j3+10;
	}
	print FLFIL "$sqlin \n";
	$j= $j + 50;
    }
    return;
}

sub wrap_put_strin{
    local ($str_text, $ident) = @_;
    
    $l1 = length($str_text) + 1;
    $j2=0; $pos2=1;
    while ($pos2 != -1 ) {
	$pos2  = index($str_text,' ',49+$pos1);
	$frag  = substr($str_text,$pos1,($pos2+1)-$pos1);
	if ( $pos2 != -1 ) {
	    print FLFIL "$ident   $frag \n";
	} else {
	    $frag = substr($str_text,$pos1,$l1);
	    print FLFIL "$ident   $frag\n";
	}
#	print "   Pos1 ='||$pos1||' Pos2='||$pos2";
	$pos1=$pos2+1;
    }
    return $l1;
}

sub wrap_put_feat_string{
    local($str_text,$ident,$feat) = @_;
    $l1 = length($str_text);
    if ( $str_text !~ / / && $l1 > 30 ) {
	while ( $iu < $l1 ) {
	    $frag=substr($str_text,$iu,15);
	    $newstr=$newstr.+$frag.+' ';
	    $iu=$iu+15;
	}
	if ( $newstr =~ / +$/ ) {
	    $newstr =~ s/ +$//;
	}
    }
    else {
	$newstr=$str_text;
    }
    $newstr='/'.+$feat.+'="'.+$newstr.+'"';
    $l1 = length($newstr) + 1;
    $j2=0;
    while ( $pos2 != 0 ) {
	$pos2=instrb($newstr,' ',49+$pos1,1);
	$frag = substr($newstr,$pos1,($pos2+1)-$pos1);
	if ( $pos2 != 0 ) {
	    print FLFIL "$ident                  $frag ";
	} else {
	    $frag = substr($newstr,$pos1,$l1);
	    print FLFIL "$ident                  $frag ";
	}
#	 print '   $pos1='||$pos1||' $pos2='||$pos2);
	$pos1=$pos2+1;
    }	
    return $l1;
}

sub get_tax_id{
    use Oraperl;
    local($spec_name) = @_;    
    &login_to_oracle;
    $cursor_c2 = 'select  tax_id
                  from  DATALIB.ntx_synonym
                  where upper_name_txt = UPPER(\''.+$spec_name.+'\')';
    $cursor_c3 = 'select  parent_id
                from    DATALIB.ntx_tax_node
                where   tax_id in
                ( select tax_id
                  from  DATALIB.ntx_synonym
                  where upper_name_txt = UPPER(\''.+$spec_name.+'\'))';
#    print "\n$cursor_c2\n";
    $csr = &ora_open($lda, $cursor_c2) || 
	die "\nCursor not opened ($ora_errstr)\n";
    while( @fdata = &ora_fetch($csr) ) {
	warn "\nTruncated!!!" if $ora_errno == 1406;
#	print "\nOracle data got : ";
	foreach $fdat ( @fdata ) {
#	    print "$fdat ";
	    print POFIL "\ntax_id=$fdat ";
	}
    }
    warn $ora_errstr if $ora_errno;    
    do ora_close($csr) || die "\ncan't close cursor";
    do ora_logoff($lda) || die "\ncan't log off from Oracle(:<->:)";    
    return;
}    

sub login_to_oracle
{
    $session = '@PRDB1'; 
    $usr     = 'MITBASE';
    $pswd    = 'MITBASE';
#
    $lda = &ora_login($session,$usr,$pswd)  || 
        die print "\nLogin error *** $ora_errstr";
#    &ora_do( $lda,'alter session set nls_date_format = \'DD\/MM\/YYYY\'');
    print "\nLog into ORACLE for TAXID OK.";
}

sub base_composition{
    local($seqdat) = @_;
    local($sln)=length($seqdat);
    $no_u = $no_c = $no_a = $no_g = $no_t = $othbas = 0;
    while ( $seqdat =~ /u/g ) { ++$no_u; }
    while ( $seqdat =~ /c/g ) { ++$no_c; }
    while ( $seqdat =~ /a/g ) { ++$no_a; }
    while ( $seqdat =~ /g/g ) { ++$no_g; }
    while ( $seqdat =~ /t/g ) { ++$no_t; }
    $othbas = $sln - ( $no_a + $no_c + $no_g + $no_t );
    print FLFIL "SQ   $sln BP; $no_a A; $no_c C; $no_g G; $no_t T; $othbas other;\n";
}

sub webin_ffile
{
    use lib '/ebi/www/web/public/Services/webin';
    use FlatFile;    
#    open KFIL, 'feat.hash' || die "\nUnable to open feat.hash!!\n";
    open KFIL, 'featu.hash' || die "\nUnable to open featu.hash!!\n";
    while ( $lin = <KFIL> ) {  # Make the associated array $features
	$lin =~ s/\n$//;
	($a,$b) = split(/=/,$lin);
	$features{$a} = $b;
    }
    close(KFIL);
    my($file_ref) = \*STDOUT;
    $flat_file = new FlatFile($file_ref, 
			      '/net/nfs0/vol0/home/sukhaswa/Embl/Email_sub',
			      "/empars.out",0,0,
#			      "/wb.fil",0,0,
			      0,
			      0,
			      \%features);
    $flat_file->print();
}

sub protect
{
    local ($_)=@_;
#   s![;:$\\\$'`|<>()]!\\$&!g; #use backslash to escape special characters
#    s![;:$\\\$'`|<>()]!_!g; #use _ to escape special characters
    s![\[()\]|]!_!g; #use _ to escape special characters
   $_;
}
