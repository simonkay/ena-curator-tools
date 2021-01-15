#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  (C) EBI 2005
#
#  Written by Philippe Aldebert
#
#  DESCRIPTION:
#
#  Script designed to deal with the automatic part of the annotation of EMBL
#  entries.
#  This new version has been entirely re-written, using the "strict;" module
#  Some bugs have been fixed, and some new functionalities added.
#  Two functionalities have been removed and passed on to EMBLmode:
#  - DE line builder
#  - Feature sorting
#
#  MODIFICATION HISTORY:
#
#  16-NOV-2005  Aldebert   : version 4 (fts4.pl)
#  12-DEC-2005  Aldebert   : some corrections made
#  06-FEB-2006  Aldebert   : some more corrections made
#
###############################################################################

use strict;
use DirHandle;

my @files = &get_file_list;

# declaring counters
my $i = 0; 
my $counter = 0;
my $orf_num = 1;
my $feature_counter = 0;
my $HD_counter = 0;
my $file_counter = 0;
my $KW_number = 0;

# declaring variables
my $EST = "";
my $GSS = "";
my $STS = "";
my $microDNA = "";
my $RN = "";
my $HLA_B = "";
my $FT_organelle = "";
my $Viridiplantae = "";
my $gene = "";
my $product = "";
my $file = "";
my $FT_organism = "";
my $warning = "";

# declaring arrays
my @lines = ();
my @FT_lines = ();
my @KW_lines = ();
my @warnings = ();
my @comments = ();

foreach $file (@comments) {
    @warnings = ();
    push (@warnings, $file);
    open ( IN, "< $file" ) or die ( "Couldn't open comment file $file!\n" );
    while (<IN>) {
	if (/\S/) {
	    print;
	}
    }
    close IN;
}

foreach $file (@files) {
    $counter = 0;
    $FT_organism = "";
    my $KW = "";
    $EST = "";
    $GSS = "";
    $STS = "";
    $microDNA = "";
    $HLA_B = "";
    @warnings = ();
    @KW_lines = ();

    $file_counter++;
    open ( IN, "< $file" ) or die ( "Couldn't open sub file $file!\n" );
    @lines = <IN>;
    close IN;

    $_ = $file;
    s/.sub/.temp/;
    my $curated_file = $_;

    $_ = $file;
    s/.sub/.fts/;
    my $warnings = $_;

    open ( OUT1, ">$curated_file" ) or die ( "Couldn't open file $curated_file: $!.\n" );
    open ( OUT2, ">$warnings" ) or die ( "Couldn't open file $warnings: $!.\n" );

# ID part of the entry/entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^ID/ ) {
	    if ( $lines[$i] =~ /^ID   (.+\s+)standard/ ) {
		&entryname;
	    }
	}
    }
    
# possible HD lines
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^HD\s\*\sconfidential\s(\d+-\w{3}-\d{4})/ ) {
	    &HD;
	}
    }

# AC lines
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^(AC\s{3}.+)$/ ) {
	    &AC_line;
	}
    }

# DT lines
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( ( $lines[$i] =~ /^DT\s{3}.+/ ) && ( $lines[$i+1] =~ /^DT\s{3}.+/ ) && ( $lines[$i+2] =~ /^XX/ ) ) {
	    &DT_lines;
	}
    }
    
# ** line to be included in entry/entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^FH   Key             Location\/Qualifiers/ ) {
	    $lines[$i] = "** FT table not sorted yet\nXX\n$lines[$i]";
	}
    }

# FT part of the entry/entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^FT\s{19}/ ) {
	    &FT_cleaner;
	    &FT_line_builder;
	}
    }

# R* lines read into individual ref blocks
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^RT\s{3}.+\w+(\.\";)$/ ) {
	    &extra_stop;
	}
	if ( $lines[$i] =~ /^R\w\s{3}/ ) {
	    if ( ( $lines[$i] =~ /^R\w\s{3}/ ) && ( $counter == 0 ) ) {
		$counter++;
		unless ($lines[$i-1] =~ /^XX/) {
		    $lines[$i-1] = "";
		}
	    }
	    elsif ( ( $lines[$i] =~ /^R\w\s{3}/ ) && ($counter == 1 ) ) {
		$lines[$i] = "$lines[$i-1]$lines[$i]";
		$lines[$i-1] = "";
	    }
	}
    }

# R* lines dealt with block by block
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( ( $lines[$i] =~ /^R\w\s{3}/ ) && ( $counter == 0 ) ) {
	    $counter++;
	    unless ($lines[$i-1] =~ /^XX/) {
		$lines[$i-1] = "";
	    }
	}
	elsif ( ( $lines[$i] =~ /^R\w\s{3}/ ) && ($counter == 1 ) ) {
	    $lines[$i] = "$lines[$i-1]$lines[$i]";
	    $lines[$i-1] = "";
	}
    }

# RL lines
    for ( $i = 0; $i <= $#lines; $i++) {
	&unpublished;
    }

# Swapping references in sequin entries (i.e.: swapping ref #1 with ref #2)
    my $ref1 = "";
    my $ref2 = "";
    for ( $i = 0; $i <= $#lines; $i++) {
	if ( ( $lines[$i] =~ /RN\s{3}\[2\]/ ) && ( $lines[$i] =~ /Submitted/ ) ) {
	    $ref1 = $lines[$i];
	}
	if ( ( $lines[$i] =~ /RN\s{3}\[1\]/ ) && ( $lines[$i] !~ /Submitted/ ) ) {
	    $ref2 = $lines[$i];
	}
	if ( ( $lines[$i] =~ /RN\s{3}\[(1|2)\]/ ) && ( $lines[$i] =~ /XX\n/ ) && ( $ref1 ne "" ) && ( $ref2 ne "" ) ){
	    $lines[$i] = "";
	}
    }

    $_ = $ref1;
    s/\[2\]/\[1\]/;
    s/XX\n//;
    $ref1 = $_;
    if ( $ref1 =~ /(RA\s{3}((\w+|\w+(\s\w+)+|\w+-\w+)(\s\w\.)+){1})(,.+);\n/ ) {
	$_ = $ref1;
	s/$6//;
	$ref1 = $_;
	$ref1 .= "XX\n";
    }
    $_ = $ref2;
    s/\[1\]/\[2\]/;
    $ref2 = $_;
    my $ref_block = "$ref1$ref2";

# sequence lines
    for ( $i = 0; $i <= $#lines; $i++) {
	if ( ( $lines[$i] =~ /^\s{5}/ ) && ( $counter == 0 ) ) {
	    $counter++;
	}
	elsif ( ( $lines[$i] =~ /^\s{5}/ ) && ($counter == 1 ) ) {
	    $lines[$i] = "$lines[$i-1]$lines[$i]";
	    $lines[$i-1] = "";
	}
	my $sequence = "";
	if ( $lines[$i] =~ /\s{5}/ ) {
	    if ( $lines[$i] =~ /(SQ\s{3}Sequence.+\n)/ ) {
		$_ = $lines[$i];
		s/$1//;
		s/\n//g;
		s/\d+//g;
		s/\s+//g;
		$sequence = $_;
	    }
	    if ( ( $lines[$i+1] !~ /\/\// ) && ( $sequence !~ /(a|c|g|t|r|y|m|k|s|w|h|b|v|d)/i ) && ( $sequence ne "" ) ) {
		$warning = "WARNING: Sequence in file $file only consists of n's\nPlease check this out.\n\n";
		push (@warnings, $warning);
		$warning = "";
	    }
	}
    }

# webin lines
    for ( $i = 0; $i <= $#lines; $i++) {
	if ( $lines[$i] =~ /(^No sequence|^no_seq)/ ) {
	    &webin_lines;
	}
    }

# counting features
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /FT\s{3}\w+/) {
	    $feature_counter++;
	}
    }
    &source_only;
    
# Identifying HLA-B entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^(DE|CC)\s{3}(.+|)(HLA-B|human leucocyte antigen B)(.+|)/i ) {
	    $HLA_B = "yes";
	}
    }
    
# Identifying EST entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^(DE|CC)\s{3}(.+|)(EST|expressed sequence tag)(.+|)/i ) {
	    &EST;
	}
    }

# Identifying STS entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^(DE|CC)\s{3}(.+|)(STS|sequence tagged site)(.+|)/i ) {
	    &STS;
	}
    }
    
# Identifying GSS entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^(DE|CC)\s{3}(.+|)(GSS|genome survey sequence)(.+|)/i ) {
	    &GSS;
	}
    }
    
# Identifying microsatellite DNA entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	my $microDNA = "";
	if ( $lines[$i] =~ /^(DE|CC)\s{3}(.+|)microsatellite DNA(.+|)/ ) {
	    &microDNA;
	}
    }

# Identifying alternative splicing entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^(DE|CC)\s{3}(.+|)(alternative splicing|splice variant)(.+|)/i ) {
	    &alternative_splicing;
	}
    }
    
# Identifying microRNA entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^(DE|CC)\s{3}(.+|)(microRNA|miRNA)(.+|)/ ) {
	    &miRNA;
	}
    }
    
# Identifying immunoglobulin heavy chain entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^(DE|CC)\s{3}(.+|)immunoglobulin heavy chain(.+|)/i ) {
	    &IGHV;
	}
    }

# Identifying TPA entries
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /^DE\s{3}TPA:\s/ ) {
	    &TPA;
	}
    }

# FT lines read into individual features
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( ( $lines[$i] =~ /^FT\s{3}\w+/ ) && ( $counter == 0 ) ) {
	    $counter++;
	    unless ($lines[$i-1] =~ /^FH/) {
		$lines[$i-1] = "";
	    }
	}
	elsif ( ( $lines[$i] =~ /^FT\s{19}/ ) && ($counter == 1 ) ) {
	    $lines[$i] = "$lines[$i-1]$lines[$i]";
	    $lines[$i-1] = "";
	}
    }

# FT table dealt with feature by feature
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( ( $lines[$i] =~ /FT   / ) && ( $HLA_B eq "yes" ) ) {
	    &HLA_B;
	}
	elsif ( ( $lines[$i] =~ /FT   / ) && ( $HLA_B ne "yes" ) ) {
	    # CDS features
	    if ( ( $lines[$i] =~ /^FT   CDS\s+(join\(|)(<|)\d+\.\.(>|)\d+/ ) && ( $lines[$i] !~ /\w+=\"(MHC class I antigen|HLA-B)\"/i ) && ( $lines[$i] !~ /ORF/i ) && ( $lines[$i] =~ /\/(gene=\".+)\"/ ) && ( $lines[$i] =~ /\/(product=\".+)\"/ ) && ( $lines[$i] !~ /(sno|small nucleolar |r|ribosomal |t|transfer )RNA/) ) {
		&CDS;
	    }
	    if ( ( $lines[$i] =~ /^FT   CDS\s+(join\(|)(<|)\d+\.\.(>|)\d+/ ) && ( $lines[$i] !~ /ORF/i ) && ( $lines[$i] =~ /\/gene=\"(.+)\"/ ) && ( $lines[$i] !~ /\/product=/ ) && ( $lines[$i] !~ /(sno|small nucleolar |r|ribosomal |t|transfer )RNA/) ) {
		&CDS_gene_no_product;
	    }
	    if ( ( $lines[$i] =~ /^FT   CDS\s+(join\(|)(<|)\d+\.\.(>|)\d+/ ) && ( $lines[$i] !~ /(sno|small nucleolar |r|ribosomal |t|transfer )RNA/) && ( $lines[$i] !~ /\/gene=/ ) && ( $lines[$i] !~ /\/product=\"MHC class I antigen\"/ ) && ( $lines[$i] =~ /\/product=\"(.+)\"/ ) ) {
		&CDS_product_no_gene;
	    }
	    if ( ( $lines[$i] =~ /^FT   CDS\s+(join\(|)(<|)\d+\.\.(>|)\d+/ ) && ( $lines[$i] !~ /\/product=\"(.+)\"/ ) && ( $lines[$i] !~ /\/gene=/ ) && ( $lines[$i] !~ /\/note=\"(.+|)orf(.+|)\"/i ) && ( $lines[$i] !~ /(sno|small nucleolar |r|ribosomal |t|transfer )RNA/) && ( $HLA_B ne "yes" ) ) {
		&CDS_no_product_no_gene;
	    }
	    if ( ( $lines[$i] =~ /^FT   CDS\s+(join\(|)(<|)\d+\.\.(>|)\d+/ ) && ( ( $lines[$i] =~ /\/gene=\"((.+|)orf(.+|))\"/i ) || ( $lines[$i] =~ /\/product=\"((.+|)orf(.+|))\"/i ) || ( $lines[$i] =~ /\/gene=\"(unknown|hypothetical( .+|))\"/i ) ) && ( $lines[$i] !~ /(sno|small nucleolar |r|ribosomal |t|transfer )RNA/) ) {
		&CDS_ORF;
	    }
	    if ( ( $lines[$i] =~ /\/gene=\".+\"/ ) && ( $lines[$i] =~ /\/note=\"((.+|)orf(.+|))\"/i ) && ( $lines[$i] =~ /^FT   CDS\s+((join\(|)(<|)\d+\.\.(>|)\d+)/ )  ) {
		&CDS_gene_ORF;
	    }
	    if ( ($lines[$i] =~ /^FT   CDS\s+(join\(|)(<|)\d+\.\.(>|)\d+/ ) && ( $lines[$i] =~ /\/product=\"(putative protein|unknown protein)\"/i) && ( $lines[$i] !~ /(sno|small nucleolar |r|ribosomal |t|transfer )RNA/) ) {
		&CDS_wrong_product;
	    }
	    # rRNA features 
	    if ( $lines[$i] =~ /^FT   (\w+)\s+(join\(|)(<|)\d+\.\.(>|)\d+\n(.+|)FT\s{19}\/(\w+)=\"(.+)S\s(r|ribosomal )RNA(.+|)\"\n/i ) {
		&rRNA;
	    }
	    # snoRNA features 
	    if ( $lines[$i] =~ /^FT   (\w+)\s+(join\(|)(<|)\d+\.\.(>|)\d+\n(.+|)FT\s{19}\/(\w+)=\"(.+)\s(sno|small nucleolar )RNA(.+|)\"\n/i ) {
		&snoRNA;
	    }
	    # tRNA features
	    if ( ( $lines[$i] =~ /(t|transfer )RNA/i ) && ( $lines[$i] =~ /^FT   (\w+\s+)(join\(|)(<|)\d+\.\.(>|)\d+/i ) ) {
		&tRNA;
	    }
	    # ITS features
	    if ( $lines[$i] =~ /^FT\s{3}(\w+\s+)(join\(|)(<|)\d+\.\.(>|)\d+\nFT\s{19}\/(\w+)=\"((ITS |ITS|internal transcribed spacer )(\d+))\"/ ) {
		&ITS;
	    }
	    # IGS features
	    if ( ( $lines[$i] =~ /(IGS|intergenic spacer)/i ) && ( $lines[$i] =~ /^FT   (\w+\s+)(join\(|)(<|)\d+\.\.(>|)\d+/i ) ) {
		&IGS;
	    }
	}
    }

# Making changes to FT table that are not related to type of feature
    my $source_5 = 0;
    my $source_3 = 0;
    my $CDS_5 = 0;
    my $CDS_3 = 0;
    my $first_loc = 0;
    my $second_loc = 0;
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( $lines[$i] =~ /FT   / ) {
	    # Influenza entries
	    if ( $lines[$i] =~ /organism=\"Influenza A virus \((.+)\((\w+)\)\)\"/i ) {
		&Influenza;
	    }
	    # variety
	    if ( ( $lines[$i] =~ /\/organism=/ ) && ( $lines[$i] =~ /\w+\svar\.\s(.+)\"/ ) ) {
		$lines[$i] .= "FT                   \/variety=\"$1\"\n";
	    }
	    # sub_species
	    if ( ( $lines[$i] =~ /\/organism=/ ) && ( $lines[$i] =~ /\w+\ssubsp\.\s(.+)\"/ ) ) {
		&subsp;
	    }
	    # Arabidopsis: switch from /variety to /ecotype
	    if ( ( $lines[$i] =~ /\/organism=\"Arabidopsis thaliana/ ) && ( $lines[$i] =~ /\/(variety)=\"(.+)\"/ ) ) {
		&var2eco;
	    }
	    # organelle
	    if ( $lines[$i] =~ /organelle=\"(\w+:|)(\w+)\"/i ) {
		&org;
	    }
	    # virus organisms
	    if ( ( $lines[$i] =~ /organism=\"(.+|.+\s|)virus(.+|\s.+|)\"/i ) && ( $lines[$i] !~ /\/virion/ ) && ( $lines[$i] !~ /\/proviral/ ) ) {
		&virus;
	    }
	    # uncultured organisms
	    if ( ( $lines[$i] =~ /organism=\"(.+|.+\s|)uncultured(.+|\s.+|)\"/i ) && ( $lines[$i] !~ /\/environmental_sample/ ) ) {
		&uncultured1;
	    }
	    if ( ( $lines[$i] =~ /organism=\"(.+|.+\s|)uncultured(.+|\s.+|)\"/i ) && ( $lines[$i] !~ /\/isolation_source/ ) ) {
		&uncultured2;
	    }
	    # wrong joined locations
	    if ( ( $lines[$i] =~ /^FT\s{3}CDS/ ) && ( $lines[$i] =~ /(\d+),(\d+)/ ) ) {
		$first_loc = $1;
		$second_loc = $2;
		$first_loc++;
		if ( $second_loc == $first_loc ) {
		    $_ = $lines[$i];
		    s/$1,$2\.\.//;
		    $lines[$i] = $_;
		    if ( $lines[$i] =~ /join\((<|)\d+\.\.(>|)\d+\)/ ) {
			$_ = $lines[$i];
			s/join\(//;
			s/\)//;
			$lines[$i] = $_;
		    }
		}
	    }
	    #dodgy partial locations
	    if ( $lines[$i] =~ /^FT\s{3}source\s{10}(\d+)\.\.(\d+)/ ) {
		$source_5 = $1;
		$source_3 = $2;
	    }
	    if ( $lines[$i] =~ /^FT\s{3}CDS\s{13}(join\(|complement\(|)<(\d+)\.(.+|)\.>(\d+)(\)|)/ ) {
		$CDS_5 = $2;
		$CDS_3 = $4;
		if ( ( $source_5 < $CDS_5 ) || ( $source_3 > $CDS_3 ) ) {
		    $warning = "WARNING: Dodgy partial locations in entry at <$CDS_5..>$CDS_3\nPlease check this out.\n\n";
		    push (@warnings, $warning);
		    $warning = "";
		}
	    }
	}
    }

# print warnings to .fts output file:
    for ( my $l = 0; $l <= $#warnings; $l++) {
	print OUT2 "$warnings[$l]";
    }

# KW lines created below:
    my $OK_KW = "";
    my @OK_KWs = (); 
    my %seen   = (); 
    my $keyword = "";

    for ( $i = 0; $i <= $#KW_lines; $i++ ) {
	my $genus = "";
	my $species = "";
	if ( $FT_organism =~ /(\w)\w+\s(\w)\w+/ ) {
	    $genus = $1;
	    $species = $2;
	}
	$_ = $KW_lines[$i];
	s/^$genus$species//gi;
	s/unknown //gi;
	s/hypothetical //gi;
	s/protein gene/protein/gi;
	s/putative //gi;
	s/ precursor//gi;
	s/ homologue/ protein/gi;
	s/ protein protein/ protein/gi;
	$KW_lines[$i] = $_;

	# making sure each KW in KW lines is unique:
	
	foreach $keyword ( @KW_lines ) { 
	    next if $seen { $keyword }++; 
	    if ( $keyword !~ /(unknown|hypothetical|putative|precursor)/ ) {
		push (@OK_KWs, $keyword); 
	    }
	}
    }

    for ( my $z = 0; $z <= $#OK_KWs; $z++ ) {
	if ( $OK_KWs[$z] ne "" ) {
	    if ( ( $FT_organism eq "Homo sapiens" ) || ( $FT_organism eq "Sus scrofa" ) || ( $FT_organism eq "Gallus gallus" ) || ( $FT_organism eq "Bos taurus" ) || ( $FT_organism eq "Saccharomyces cerevisiae" ) ) {
		if ( ( $OK_KWs[$z] =~ / gene/ ) && ( $OK_KWs[$z] !~ /((r|t|sno|micro|)RNA|HLA-B)/ ) ) {
		    $_ = $OK_KWs[$z];
		    s/\sgene//g;
		    $OK_KWs[$z] = $_;
		    $OK_KWs[$z] = "\U$OK_KWs[$z]";
		    $OK_KWs[$z] .= " gene";
		}
	    }
	    elsif ( ( $FT_organism eq "Danio rerio" ) || ( $FT_organism eq "Brachydanio rerio" ) ) {
		if ( ( $OK_KWs[$z] =~ / gene/ ) && ( $OK_KWs[$z] !~ /((r|t|sno|micro|)RNA|HLA-B)/ ) ) {
		    $_ = $OK_KWs[$z];
		    s/\sgene//g;
		    $OK_KWs[$z] = $_;
		    $OK_KWs[$z] = "\L$OK_KWs[$z]";
		    $OK_KWs[$z] .= " gene";
		}
	    }
	    elsif ( ( $FT_organism eq "Mus musculus" ) || ( $FT_organism eq "Rattus norvegicus" ) ) {
		if ( ( $OK_KWs[$z] =~ / gene/ ) && ( $OK_KWs[$z] !~ /((r|t|sno|micro|)RNA|HLA-B)/ ) ) {
		    $_ = $OK_KWs[$z];
		    s/\sgene//g;
		    $OK_KWs[$z] = $_;
		    $OK_KWs[$z] = "\u\L$OK_KWs[$z]";
		    $OK_KWs[$z] .= " gene";
		}
	    }
	}

	if ( $z == $#OK_KWs ) {
	    $OK_KWs[$z] = "$OK_KWs[$z].";
	}
	else {
	    $OK_KWs[$z] = "$OK_KWs[$z]; ";
	}
	$KW .= "$OK_KWs[$z]";
    }

# Printing stuff:

# print all lines to .temp output file:
    for ( my $k = 0; $k <= $#lines; $k++) {
        # FT lines, gene case
	if ( $lines[$k] =~ /FT\s{19}\/gene=\"(.+)\"/ ) {
	    my $gene_here = $1;
	    if ( ( $FT_organism eq "Homo sapiens" ) || ( $FT_organism eq "Sus scrofa" ) || ( $FT_organism eq "Gallus gallus" ) || ( $FT_organism eq "Bos taurus" ) || ( $FT_organism eq "Saccharomyces cerevisiae" ) ) {
		$_ = $lines[$k];
		s/gene=\"(.+)\"/gene=\"\U$gene_here\"/;
		$lines[$k] = $_;
	    }
	    elsif ( ( $FT_organism eq "Danio rerio" ) || ( $FT_organism eq "Brachydanio rerio" ) ) {
		$_ = $lines[$k];
		s/gene=\"(.+)\"/gene=\"\L$gene_here\"/;
		$lines[$k] = $_;
	    }
	    elsif ( ( $FT_organism eq "Mus musculus" ) || ( $FT_organism eq "Rattus norvegicus" ) ) {
		$_ = $lines[$k];
		s/gene=\"(.+)\"/gene=\"\u\L$gene_here\"/;
		$lines[$k] = $_;
	    }
	}
	# KW lines, general case
	if ( ( $lines[$k] =~ /^KW   / ) && ( $EST ne "yes" ) && ( $STS ne "yes" ) && ( $GSS ne "yes" ) && ( $microDNA ne "yes" ) ) {
	    my $out_str = "KW  ";
	    my $seq = $KW;
	    my $lines = 1;
	    my $word = "";
	    my $max_line_length = 75;
	    my @prim = split(/\s/,$seq);
	    foreach $word (@prim) {
		if( ( length "$out_str"." "."$word$word")/$lines <= $max_line_length ) {
		    $out_str = "$out_str"." "."$word";
		}
		else {
		    $lines++;
		    $out_str = "$out_str"."\n"."KW   $word";
		}
	    }
	    $out_str="$out_str"."\n";
	    print OUT1 "$out_str";
	}
	# KW lines, EST case
	elsif ( ( $lines[$k] =~ /^KW/ ) && ( $EST eq "yes" ) ) {
	    $KW = "KW   EST; expressed sequence tag.\n";
	    print OUT1 "$KW";
	}
	# KW lines, STS case
	elsif ( ( $lines[$k] =~ /^KW/ ) && ( $STS eq "yes" ) ) {
	    $KW = "KW   STS; sequence tagged site.\n";
	    print OUT1 "$KW";
	}
	# KW lines, GSS case
	elsif ( ( $lines[$k] =~ /^KW/ ) && ( $GSS eq "yes" ) ) {
	    $KW = "KW   GSS; genome survey sequence.\n";
	    print OUT1 "$KW";
	}
	# KW lines, microsatellite DNA case
	elsif ( ( $lines[$k] =~ /^KW/ ) && ( $microDNA eq "yes" ) ) {
	    $KW = "KW   microsatellite; repetitive DNA.\n";
	    print OUT1 "$KW";
	}
	# Reference block: replacing R* lines by $ref_block in sequin subs
	elsif ( ( $lines[$k] =~ /RN\s{3}\[(1|2)\]/ ) && ( $ref_block ne "" ) ) {
	    print OUT1 "$ref_block";
	}
	else {
	    print OUT1 "$lines[$k]";
	}
    }

} # end of foreach file loop

# print warnings to screen:
if ( ( $file_counter ne $HD_counter ) && ( $HD_counter != 0 ) ) {
    print "\n\nWARNING: some entries are confidential, some others are not\nPlease contact submitter to check this out.\n\n";
}

# List of sub-routines (alphabetically listed):

# sub routine that deals with AC lines in sequin subs
sub AC_line {
    my $ac = $1;
    $_ = $lines[$i];
    s/$ac/AC   \;/;
    $lines[$i] = $_;
}

# sub routine that deals with alternative splicing entries
sub alternative_splicing {
    push (@KW_lines, "alternative splicing");
}

# CDS
sub CDS {
    if ( $lines[$i] =~ /gene=\"(.+)\"/ ) {
	my $init_gene = $1;
	if ( ( $Viridiplantae eq "yes" ) && ( $FT_organelle ne "chloroplast" ) && ( $FT_organelle ne "mitochondrion" ) ) {
	    $gene = "\u\L$init_gene";
	    $_ = $lines[$i];
	    s/$init_gene/$gene/;
	    $lines[$i] = $_;
	}
	else {
	    $gene = $init_gene;
	}
    }
    if ( $lines[$i] =~ /product=\"(.+)\"/ ) {
	my $init_product = $1;
	$product = $init_product;
    }

    my $h_product = &human_entry;

    push (@KW_lines, "$gene gene");
    push (@KW_lines, $product);
}

# CDS gene no product
sub CDS_gene_no_product {
    my $init_gene = $1;
    if ( ( $Viridiplantae eq "yes" ) && ( $FT_organelle ne "chloroplast" ) && ( $FT_organelle ne "mitochondrion" ) ) {
	$gene = "\u\L$init_gene";
    }
    else {
	$gene = $init_gene;
    }
    push (@KW_lines, "$gene gene");
    $product = "\u\L$gene protein";
    push (@KW_lines, $product);
    $lines[$i]	.= "FT                   \/product=\"$product\"\n";
    $_ = $lines[$i];
    s/$init_gene/$gene/;
    $lines[$i] = $_;
    $warning = "WARNING: product name -$product- was made up from gene name\nPlease contact submitter for possible better product name.\n\n";
    push (@warnings, $warning);
    $warning = "";
}

# CDS gene and note=ORF
sub CDS_gene_ORF {
    $warning = "WARNING: CDS feature with locations $1 has both a /gene and a /note=\"ORF\"-like qualifier\nPlease check this out.\n\n";
    push (@warnings, $warning);
    $warning = "";
    if ( $lines[$i] !~ /\/product=\".+\"/ ) {
	$lines[$i] .= "FT                   \/product=\"hypothetical protein\"\n";
    }
}

# CDS no product no gene
sub CDS_no_product_no_gene {
    my $gene = "ORF$orf_num";
    push (@KW_lines, $gene);
    $orf_num++;
    $product = "hypothetical protein";
    $lines[$i]	.= "FT                   \/note=\"$gene\"\n"."FT                   \/product=\"$product\"\n";
}

# CDS ORF
sub CDS_ORF {
    my $gene_found = $1;
    $orf_num++;
    if ( $lines[$i] =~ /\/gene=\"(orf\d+|orf\w+)\"/i ) {
	$gene_found = $1;
	$gene = "\U$gene_found";
	$_ = $lines[$i];
	s/gene/note/;
	s/$gene_found/$gene/;
	$lines[$i] = $_;
	if ( $lines[$i] !~ /\/product=/ ) {
	    $lines[$i]	.= "FT                   \/product=\"hypothetical protein\"\n";
	}
	elsif ( ( $lines[$i] !~ /(hypothetical|putative) protein/ ) && ( $lines[$i] =~ /\/product=\"(.+)\"/ ) ) {
	    $product = $1;
	    print "product found here: $product\n";
	    push (@KW_lines, $product);
	}
	push (@KW_lines, $gene);
    }
    elsif ( $lines[$i] =~ /\/product=\"(orf\d+|orf\w+)\"/i ) {
	$gene_found = $1;
	$gene = "\U$gene_found";
	$_ = $lines[$i];
	s/$gene_found/hypothetical protein/;
	$lines[$i] = $_;
	$lines[$i]	.= "FT                   \/gene=\"$gene_found\"\n";
    }
}

# CDS product no gene
sub CDS_product_no_gene {
    my $init_product = $1;
    if ( ( $init_product ne "hypothetical protein" ) && ( $init_product ne "putative protein" ) && ( $init_product !~ /(orf\d+|orf\w+)/i ) ) {
	if (  $init_product =~ /protein$/ ) {
	    $product = "\u\L$init_product";
	}
	else {
	    $product = "\u\L$init_product protein";
	}
	push (@KW_lines, $product);
    }
    my $gene = "ORF$orf_num";
    push (@KW_lines, $gene);
    $orf_num++;
    $lines[$i]	.= "FT                   \/note=\"$gene\"\n";
}

# CDS wrong product
sub CDS_wrong_product {
    my $wrong_product = $1;
    $_ = $lines[$i];
    s/$wrong_product/hypothetical protein/;
    $lines[$i] = $_;
}

# sub routine that removes the DT lines found in sequin subs
sub DT_lines {
    $lines[$i] = "";
    $lines[$i+1] = "";
    $lines[$i+2] = "";
}

# sub routine that replaces "whatever" by "ENTRYNAME" in ID lines of sequin subs
sub entryname {
    my $entryname = $1;
    $_ = $lines[$i];
    s/$entryname/ENTRYNAME  /;
    $lines[$i] = $_;
}

# sub routine that turns division to ENV in ID line
sub env {
    if ( $FT_organism =~ /uncultured/i ) {
	for ( my $l = 0; $l <= $#lines; $l++) {
	    if ( $lines[$l] =~ /^ID\s{3}ENTRYNAME\s+\w+\;\s(\w+|\w+\s\w+)\;\s(\w+)\;\s\d+\sBP\.$/ ) {
		my $division = $2;
		$_ = $lines[$l];
		s/$division/ENV/;
		$lines[$l] = $_;
	    }
	}
    }
}

# sub routine that deals with EST entries
sub EST {
    $EST = "yes";
    for ( my $l = 0; $l <= $#lines; $l++) {
	if ( $lines[$l] =~ /^ID\s{3}ENTRYNAME\s+\w+\;\s(\w+|\w+\s\w+)\;\s(\w+)\;\s\d+\sBP\.$/ ) {
	    my $division = $2;
	    $_ = $lines[$l];
	    s/$division/EST/;
	    $lines[$l] = $_;
	}
    }
}

# sub routine that adds extra full stop at end of RT line
sub extra_stop {
    $_ = $lines[$i];
    s/$1/\";/;
    $lines[$i] = $_;
}

# sub routine that builds the FT lines
sub FT_cleaner {
    for ( $i = 0; $i <= $#lines; $i++ ) {
	# unknonw function
	if ( $lines[$i] =~ /FT\s{19}\/function=\"unknown\"\n/i ) {
	    $lines[$i] = "";
	}
	# empty spaces at beginning or end of qualifier contents
	if ( $lines[$i] =~ /FT\s{19}\/\w+=\"(\s+)/ ) {
	    $_ = $lines[$i];
	    s/\"(\s+)/\"/;
	    $lines[$i] = $_;
	}
	if ( ( $lines[$i] =~ /FT\s{19}\/\w+=\"/ ) && ( $lines[$i] =~ /(\s+)\"/ ) ) {
	    $_ = $lines[$i];
	    s/(\s+)\"/\"/;
	    $lines[$i] = $_;
	}
	# partial
	if ( $lines[$i] =~ /FT\s{19}\/\w+=\"partial(\s+)/ ) {
	    $_ = $lines[$i];
	    s/\"(\s+)/\"/;
	    $lines[$i] = $_;
	}
	if ( ( $lines[$i] =~ /FT\s{19}\/\w+=\"/ ) && ( $lines[$i] =~ /(\s+)partial\"/ ) ) {
	    $_ = $lines[$i];
	    s/(\s+)\"/\"/;
	    $lines[$i] = $_;
	}
	# truncated
	if ( $lines[$i] =~ /FT\s{19}\/\w+=\"truncated(\s+)/ ) {
	    $_ = $lines[$i];
	    s/\"(\s+)/\"/;
	    $lines[$i] = $_;
	}
	if ( ( $lines[$i] =~ /FT\s{19}\/\w+=\"/ ) && ( $lines[$i] =~ /(\s+)truncated\"/ ) ) {
	    $_ = $lines[$i];
	    s/(\s+)\"/\"/;
	    $lines[$i] = $_;
	}
	# proteine > protein
	if ( ( $lines[$i] =~ /FT\s{19}/ ) && ( $lines[$i] =~ /proteine/i ) ) {
	    $_ = $lines[$i];
	    s/proteine/protein/;
	    $lines[$i] = $_;
	}
	# tirosine > tyrosine
	if ( ( $lines[$i] =~ /FT\s{19}/ ) && ( $lines[$i] =~ /tirosine/i ) ) {
	    $_ = $lines[$i];
	    s/tirosine/tyrosine/;
	    $lines[$i] = $_;
	}
	# oxydase > oxidase
	if ( ( $lines[$i] =~ /FT\s{19}/ ) && ( $lines[$i] =~ /oxydase/i ) ) {
	    $_ = $lines[$i];
	    s/oxydase/oxidase/;
	    $lines[$i] = $_;
	}
	# oxydation > oxidation
	if ( ( $lines[$i] =~ /FT\s{19}/ ) && ( $lines[$i] =~ /oxydation/i ) ) {
	    $_ = $lines[$i];
	    s/oxydation/oxidation/;
	    $lines[$i] = $_;
	}
    }
}

# sub routine that builds the FT lines
sub FT_line_builder {
    my $qualifier = "";
    for ( $i = 0; $i <= $#lines; $i++ ) {
	# wrong EC number
	if ( ( $lines[$i] =~ /FT\s{19}\/EC_number=\"-\.\d+\.\d+\.\d+\"\n/ ) ||
             ( $lines[$i] =~ /FT\s{19}\/EC_number=\"\d+\.-\.\d+\.\d+\"\n/ ) || 
             ( $lines[$i] =~ /FT\s{19}\/EC_number=\"\d+\.\d+\.-\.\d+\"\n/ ) || 
             ( $lines[$i] =~ /FT\s{19}\/EC_number=\"-\.-\.\d+\.\d+\"\n/ ) || 
             ( $lines[$i] =~ /FT\s{19}\/EC_number=\"-\.\d+\.-\.\d+\"\n/ ) || 
             ( $lines[$i] =~ /FT\s{19}\/EC_number=\"\d+\.-\.-\.\d+\"\n/ ) || 
             ( $lines[$i] =~ /FT\s{19}\/EC_number=\"-\.-\.-\.\d+\"\n/ ) || 
             ( $lines[$i] =~ /FT\s{19}\/EC_number=\"-\.\d+\.-\.-\"\n/ ) || 
             ( $lines[$i] =~ /FT\s{19}\/EC_number=\"-\.-\.\d+\.-\"\n/ ) ) {
	    $warning = "WARNING: illegal EC_number found in entry\nPlease check this out.\n\n";
	    push (@warnings, $warning);
	    $warning = "";
	}
	# picking up organim name for later comparison
	if ( $lines[$i] =~ /FT\s{19}\/(\w+)=\"(.+)\"/ ) {
	    $qualifier = $1;
	    my $qual_contents = $2;
	    if ( $qualifier eq "organism" ) {
		$FT_organism = $qual_contents;
		&organism;
	    }
	}
	# uppercasing direction and rpt_type information
	if ( $lines[$i] =~ /FT\s{19}\/(\w+)=(.+)/ ) {
	    $qualifier = $1;
	    my $qual_contents = $2;
	    if ( ( $qualifier eq "direction" ) || ( $qualifier eq "rpt_type" ) ) {
		$_ = $lines[$i];
		s/$qual_contents/\U$qual_contents/;
		$lines[$i] = $_;
	    }
	}
    }
}

# sub routine that gets the input files
sub get_file_list {
    my $dh = DirHandle->new ( "." ) || die "cannot opendir: $!"; 
    my @list = $dh->read ();
    foreach $file ( @list ) {
	if ( $file =~ /^\w+\.(sub$)/i ) {
	    push (@files, $file);
	}
    }
    return @files;
}

# sub routine that deals with GSS entries
sub GSS {
    $GSS = "yes";
    for ( my $l = 0; $l <= $#lines; $l++) {
	if ( $lines[$l] =~ /^ID\s{3}ENTRYNAME\s+\w+\;\s(\w+|\w+\s\w+)\;\s(\w+)\;\s\d+\sBP\.$/ ) {
	    my $division = $2;
	    $_ = $lines[$l];
	    s/$division/GSS/;
	    $lines[$l] = $_;
	}
    }
}

# sub routine that deals with hold date
sub HD {
    my $HD = $1;
    my @HDs = ();
    $HD_counter++;
    push (@HDs, $HD);
    for ( my $n = 0; $n <= $#HDs; $n++ ) {
	if ( $HD ne $HDs[$n] ) {
	    $warning = "WARNING: Hold dates in entries differ\nPlease contact submitter to check this out.\n\n";
	    push (@warnings, $warning);
	    $warning = "";
	}
    }
}

# sub routine that deals with HLA_B entries
sub HLA_B {
    my $allele = "";
    for ( $i = 0; $i <= $#lines; $i++ ) {
	if ( ( $lines[$i] =~ /FT\s{3}CDS\s{13}/ ) && ( $lines[$i] !~ /FT\s{19}\/gene=\"HLA-B\"/ )  && ( $lines[$i] =~ /FT\s{19}\/gene=\"(.+)\"/ ) ) {
	    $_ = $lines[$i];
	    s/$1/HLA-B/;
	    $lines[$i] = $_;
	    $lines[$i] .= "FT                   \/product=\"MHC class I antigen\"\n";
	}
	elsif ( ( $lines[$i] =~ /FT\s{3}CDS\s{13}/ ) && ( $lines[$i] !~ /FT\s{19}\/product=\"MHC class I antigen\"/ ) && ( $lines[$i] =~ /FT\s{19}\/product=\"(.+)\"/ ) ) {
	    $_ = $lines[$i];
	    s/$1/MHC class I antigen/;
	    $lines[$i] = $_;
	    $lines[$i] .= "FT                   \/gene=\"HLA-B\"\n";
	}
	elsif ( ( $lines[$i] =~ /FT\s{3}CDS\s{13}/ ) && ( $lines[$i] =~ /FT\s{19}\/gene=\"HLA-B\"/ ) ) {
	    if ( $lines[$i] =~ /(FT\s{19}\/product=\".+\")/ ) {
		$_ = $lines[$i];
		s/$1/FT                   \/product=\"MHC class I antigen\"/;
		$lines[$i] = $_;
	    }
	    if ( $lines[$i] !~ /\/product=/ ) {
		$lines[$i] .= "FT                   \/product=\"MHC class I antigen\"\n";
	    }
	}
	elsif ( ( $lines[$i] =~ /FT\s{3}CDS\s{13}/ ) && ( $lines[$i] =~ /FT\s{19}\/product=\"MHC class I antigen\"/ ) ) {
	    if ( $lines[$i] =~ /(FT\s{19}\/gene=\".+\")/ ) {
		$_ = $lines[$i];
		s/$1/FT                   \/gene=\"HLA-B\"/;
		$lines[$i] = $_;
	    }
	    if ( $lines[$i] !~ /\/gene=/ ) {
		$lines[$i] .= "FT                   \/gene=\"HLA-B\"\n";
	    }
	}
	elsif ( ( $lines[$i] =~ /FT\s{3}CDS\s{13}/ ) && ( $lines[$i] !~ /FT\s{19}\/gene/ ) && ( $lines[$i] !~ /FT\s{19}\/product/ ) ) {
	    $lines[$i] .= "FT                   \/product=\"MHC class I antigen\"\n";
	    $lines[$i] .= "FT                   \/gene=\"HLA-B\"\n";
	}
	if ( $lines[$i] =~ /FT\s{3}CDS\s{13}/ ) {
	    if ( $lines[$i] =~ /(FT\s{19}\/function=\".+\")/ ) {
		$_ = $lines[$i];
		s/$1/FT                   \/function=\"antigen presenting molecule\"/;
		$lines[$i] = $_;
	    }
	    if ( $lines[$i] !~ /\/function=/ ) {
		$lines[$i] .= "FT                   \/function=\"antigen presenting molecule\"\n";
	    }
	    if ( $lines[$i] =~ /FT\s{19}\/allele=\"(.+\*|\*|)(\w+)\"/ ) {
		$allele = $2;
		$_ = $lines[$i];
		s/FT\s{19}\/allele=\"(.+\*|\*|)(\w+)\"/FT                   \/allele=\"HLA-B*$allele\"/;
		$lines[$i] = $_;
	    }
	    if ( $lines[$i] !~ /\/allele=/ ) {
		$lines[$i] .= "FT                   \/allele=\"HLA-B*\"\n";
		$warning = "WARNING: no allele name provided for HLA-B gene\nPlease contact submitter.\n\n";
		push (@warnings, $warning);
		$warning = "";
	    }
	}
    }
    push (@KW_lines, "$allele allele");
    push (@KW_lines, "HLA-B gene");
    push (@KW_lines, "MHC class I antigen");
    push (@KW_lines, "major histocompatibility complex");
    push (@KW_lines, "human leucocyte antigen B");
}

# sub routine that checks human gene and product names
sub human_entry {
    my @human_genes = ();
    my @human_products = ();
    my $h_gene = $gene;
    my $h_product = $product;
    my $human_nom = "../nomenclature.txt";
    if ( $FT_organism =~ /Homo sapiens/ ) {
	if ( $HLA_B ne "yes" ) {
	    open ( INHUMANNOM, "<$human_nom" ) or die ( "Couldn't open human nomenclature file!\n" );
	    my @human_nom_lines = <INHUMANNOM>;
	    my $human_gene = "";
	    my $human_product = "";
	    for ( my $a = 0; $a <= $#human_nom_lines; $a++ ) {
		if ( $human_nom_lines[$a] !~ /withdrawn/ ) {
		    my @fields = split /\t/, $human_nom_lines[$a];
		    $human_gene = $fields[0];
		    push (@human_genes, $human_gene);
		    $human_product = $fields[1];
		    push (@human_products, $human_product);
		}
	    }
	    close INHUMANNOM;
	    for ( my $b = 0; $b <= $#human_genes; $b++ ) {
		if ( $human_genes[$b] ne $gene ) {
		    $warning = "WARNING: human gene/product mismatch\nPlease contact submitter.\n\n";
		}
	    }
	    push (@warnings, $warning);
	    $warning = "";
	}
    }
}

# sub routine that deals with IGHV entries
sub IGHV {
    push (@KW_lines, "immunoglobulin heavy chain");
    push (@KW_lines, "variable region");
}

# sub routine that checks IGS features
sub IGS {
    if ( $lines[$i] =~ /^FT   (\w+\s+)(join\(|)(<|)\d+\.\.(>|)\d+/i ) {
	my $feature = $1;
	$_ = $lines[$i];
	s/$feature/misc_feature    /;
	s/\w+=\"IGS\"/note=\"intergenic spacer, IGS\"/;
	s/\w+=\"intergenic spacer\"/note=\"intergenic spacer, IGS\"/;
	$lines[$i] = $_;
	push (@KW_lines, "intergenic spacer");
	push (@KW_lines, "IGS");
    }
}

# sub routine that deals with Influenza names
sub Influenza {
    my $IAV_strain = $1;
    my $IAV_serotype = $2;
    if ( $lines[$i] =~ /(FT                   \/strain=\".+\"\n)/ ) {
	$_ = $lines[$i];
	s/FT                   \/strain=\"$1\"\n//;
	$lines[$i] = $_;
    }
    else {
	$lines[$i] .="FT                   \/strain=\"$IAV_strain\"\n";
    }
    if ( $lines[$i] =~ /(FT                   \/serotype=\".+\"\n)/ ) {
	$_ = $lines[$i];
	s/FT                   \/serotype=\"$1\"\n//;
	$lines[$i] = $_;
    }
    else {
	$lines[$i] .="FT                   \/serotype=\"$IAV_serotype\"\n";
    }
}

# sub routine that checks ITS features
sub ITS {
    my $feature = $1;
    my $qualifier = $5;
    my $ITS_number = $8;
    my $qual_contents = $6;
    $_ = $lines[$i];
    s/$feature/misc_feature    /;
    s/$qualifier/note/;
    s/$qual_contents/internal transcribed spacer $ITS_number, ITS$ITS_number/;
    $lines[$i] = $_;
    push (@KW_lines, "internal transcribed spacer $ITS_number");
    push (@KW_lines, "ITS$ITS_number");
}

# sub routine that deals with micro_DNA entries
sub microDNA {
    $microDNA = "yes";
}

# sub routine that deals with miRNA entries
sub miRNA {
    push (@KW_lines, "miRNA");
}

# sub routine that turns division to ORG in ID line
sub org {
    $FT_organelle = $2;
    if ( $FT_organelle ne "" ) {
	for ( my $l = 0; $l <= $#lines; $l++) {
	    if ( $lines[$l] =~ /^ID\s{3}ENTRYNAME\s+\w+\;\s(\w+|\w+\s\w+)\;\s(\w+)\;\s\d+\sBP\.$/ ) {
		my $division = $2;
		$_ = $lines[$l];
		s/$division/ORG/;
		$lines[$l] = $_;
	    }
	}
    }
}

# sub routine that checks organism names in entries where molecule type is "other DNA" or "other RNA"
sub organism {
    my $ID_mol_type = "";
    if ( ( $ID_mol_type =~ /other DNA/ ) && ( ( $FT_organism !~ /cloning vector/i ) || ( $FT_organism !~ /synthetic construct/i ) ) ) {
	$warning = "WARNING: possible improper use of the \"other DNA\" molecule type\nPlease check this out.\n\n";
	push (@warnings, $warning);
	$warning = "";
    }
    if ( ( $ID_mol_type =~ /other RNA/ ) && ( $FT_organism !~ /expression vector/i ) ) {
	$warning = "WARNING: possible improper use of the \"other RNA\" molecule type\nPlease check this out.\n\n";
	push (@warnings, $warning);
	$warning = "";
    }
}

# sub routine that checks rRNA features
sub rRNA {
    my $feature = $1;
    my $qualifier = $6;
    my $S_number = "$7S";
    if ( ( $lines[$i] =~ /gene=/ ) && ( $lines[$i] =~ /product=/ ) ) {
	$_ = $lines[$i];
	s/$feature\s+/rRNA            /;
	s/gene=\"(.+)S\s(r|ribosomal )RNA(.+|)\"\n/gene=\"$S_number rRNA\"\n/;
	s/product=\"(.+)S\s(r|ribosomal )RNA(.+|)\"\n/product=\"$S_number ribosomal RNA\"\n/;
	$lines[$i] = $_;
    }
    if ( ( ( $lines[$i] =~ /gene=/ ) && ( $lines[$i] !~ /product=/ ) ) || ( ( $lines[$i] !~ /gene=/ ) && ( $lines[$i] =~ /product=/ ) ) ) {
	$_ = $lines[$i];
	s/$feature\s+/rRNA            /;
	s/(\w+)=\"(.+)S\s(r|ribosomal )RNA(.+|)\"\n/gene=\"$S_number rRNA\"\nFT                   \/product=\"$S_number ribosomal RNA\"\n/;
	$lines[$i] = $_;
    }
    if ( ( $lines[$i] !~ /gene=/ ) && ( $lines[$i] !~ /product=/ ) ) {
	$_ = $lines[$i];
	s/$feature\s+/rRNA            /;
	s/(\w+)=\"(.+)S\s(r|ribosomal )RNA(.+|)\"\n/gene=\"$S_number rRNA\"\nFT                   \/product=\"$S_number ribosomal RNA\"\n/;
	$lines[$i] = $_;
    }
    push (@KW_lines, "$S_number rRNA gene");
    push (@KW_lines, "$S_number ribosomal RNA");
}

# sub routine that checks snoRNA features
sub snoRNA {
    my $feature = $1;
    my $qualifier = $6;
    my $sno_stuff = $7;
    if ( ( $lines[$i] =~ /gene=/ ) && ( $lines[$i] =~ /product=/ ) ) {
	$_ = $lines[$i];
	s/$feature\s+/snoRNA          /;
	s/gene=\"(.+)\s(sno|small nucleolar )RNA(.+|)\"\n/gene=\"$sno_stuff snoRNA\"\n/;
	s/product=\"(.+)\s(sno|small nucleolar )RNA(.+|)\"\n/product=\"$sno_stuff small nucleolar RNA\"\n/;
	$lines[$i] = $_;
    }
    if ( ( ( $lines[$i] =~ /gene=/ ) && ( $lines[$i] !~ /product=/ ) ) || ( ( $lines[$i] !~ /gene=/ ) && ( $lines[$i] =~ /product=/ ) ) ) {
	$_ = $lines[$i];
	s/$feature\s+/snoRNA          /;
	s/(\w+)=\"(.+)S\s(sno|small nucleolar )RNA(.+|)\"\n/gene=\"$sno_stuff snoRNA\"\nFT                   \/product=\"$sno_stuff small nucleolar RNA\"\n/;
	$lines[$i] = $_;
	if ( $lines[$i] !~ /product=/ ) {
	    $lines[$i] .= "FT                   \/product=\"$sno_stuff small nucleolar RNA\"\n";
	}
	elsif ( $lines[$i] !~ /gene=/ ) {
	    $lines[$i] .= "FT                   \/gene=\"$sno_stuff snoRNA\"\n";
	}
    }
    push (@KW_lines, "$sno_stuff snoRNA gene");
    push (@KW_lines, "$sno_stuff small nucleolar RNA");
}

# sub routine that deals with entries that have only a source feature
sub source_only {
    if ( $feature_counter == 1 ) {
	$warning = "WARNING: no feature provided by submitter besides of source feature\nPlease check this out.\n\n";
	push (@warnings, $warning);
	$warning = "";
    }
}

# sub routine that deals with STS entries
sub STS {
    $STS = "yes";
    for ( my $l = 0; $l <= $#lines; $l++) {
	if ( $lines[$l] =~ /^ID\s{3}ENTRYNAME\s+\w+\;\s(\w+|\w+\s\w+)\;\s(\w+)\;\s\d+\sBP\.$/ ) {
	    my $division = $2;
	    $_ = $lines[$l];
	    s/$division/STS/;
	    $lines[$l] = $_;
	}
    }
}

# sub routine that creates /sub_species
sub subsp {
    $lines[$i] .= "FT                   \/sub_species=\"$1\"\n";
}

# sub routine that deals with TPA entries
sub TPA {
    push (@KW_lines, "Third Party Annotation");
    push (@KW_lines, "TPA");
}

# sub routine that checks tRNA features
sub tRNA {
    if ( $lines[$i] =~ /^FT   (\w+\s+)(join\(|)(<|)\d+\.\.(>|)\d+/i ) {
	my $feature = $1;
	if ( $lines[$i] =~ /FT\s{19}\/(\w+)=\"(.+|)(t|transfer )RNA(-|)((\w{3})|)(.+|)\"\n/i ) {
	    my $qualifier = $1;
	    my $aa = $5;
	    my $tRNA_stuff = $7;
	    if ( $aa eq "" ) {
		$warning = "WARNING: incomplete tRNA gene name: no amino acid supplied!\nPlease check this out.\n\n";
		push(@warnings, $warning);
		$_ = $lines[$i];
		s/$feature/tRNA            /;
		s/(\w+)=\"(.+|)(t|transfer )RNA(.+|)\"\n/gene=\"tRNA-$aa$tRNA_stuff\"\nFT                   \/product=\"transfer RNA-$aa$tRNA_stuff\"\n/;
		$lines[$i] = $_;
	    }
	    else {
		$_ = $lines[$i];
		s/$feature/tRNA            /;
		s/(\w+)=\"(.+|)(t|transfer )RNA-((\w{3})|)(.+|)\"\n/gene=\"tRNA-$aa$tRNA_stuff\"\nFT                   \/product=\"transfer RNA-$aa$tRNA_stuff\"\n/;
		$lines[$i] = $_;
	    }
	    push (@KW_lines, "tRNA-$aa$tRNA_stuff gene");
	    push (@KW_lines, "transfer RNA-$aa$tRNA_stuff");
	}
    }
}

# sub routine that checks that there is a /environmental_sample in entries where the organism is uncultured
sub uncultured1 {
    $lines[$i] .= "FT                   \/environmental_sample\n";
    &env;
}

# sub routine that checks that there is an /isolation_source in entries where the organism is uncultured
sub uncultured2 {
    $lines[$i] .= "FT                   \/isolation_source=\"\"\n";
    $warning = "WARNING: uncultured organism name and no /isolation_source qualifier\nwas found in source feature!\nPlease check this out.\n\n";
    push (@warnings, $warning);
    $warning = "";
    &env;
}

# sub routine that deals with unpublished citations
sub unpublished {
    if ( $lines[$i] =~ /(RL.+(0:0-0|\[No Plans\]|in\s+preparation|Accepted|Thesis \(\?\)))/i ) {
	$_ = $lines[$i];
	s/RL.+(0:0-0|\[No Plans\]|in\s+preparation|Accepted|Thesis \(\?\))/RL   Unpublished/;
	$lines[$i] = $_;
    }
}

# sub routine that changes /variety to /ecotype for Arabidopsis thaliana entries
sub var2eco {
    $_ = $lines[$i];
    s/variety/ecotype/;
    $lines[$i] = $_;
}

# sub routine that checks that there is either /virion or /proviral in entries where the organism is a virus
sub virus {
    $warning = "WARNING: organism name is a virus and no /virion or /proviral qualifier were found in source feature!\nPlease check this out.\n\n";
    push (@warnings, $warning);
    $warning = "";
}

# sub routine that removes the webin lines
sub webin_lines {
    $lines[$i] = "";
}

close OUT1;
close OUT2;
