#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
# Purpose: sort features by location, generate KW & DE lines, & many other flat file clean-ups!
# Author:  PH (with many a vital input from PS!)
# Date:    09-NOV-1998
# Version: see $VER below
#
# The main reason for not maintaining this script very much is that most, if
# not all, functionality in here should be transfered direclty to WEBIN and
# ultimately make this 'filter' script redundant (ie it wouldn't find anything
# more to do on WEBIN generated flat files).
#
# UNIX migration: should WEBIN have not yet absorbed all the FTSORT
# functionalities by UNIX migration time, then this script will have to be
# ported to UNIX too! It shouldn't be much work, since just the system calls
# need porting and also the file naming needs to be carefully checked (eg
# no ;## file ends etc.).
# PH - July 1999
#
# NR - Nov 2000
# - ported get_file_list and date function ($todayis) to unix
# - added missing () in mangle_qualifiers: if ($line =~ /^FT\s+\/(\w+)(\s|=)/)
# => this script needs to be rewritten: use strict!!! NO LABELS!
#
# PA - July 2005
# - modified l.115 to reflect recent change in format of sequin sub files
# - modified l.431 for same reason
#
# PA - 06-JUL-2005
# - recognises sequin files by the file name in the format SEQUINxx.sub
#
# NF - 14-JUL-2005
# - now does not think any organism with 'V' in the name is a virus when
#   applying the action $actions{RNA_gene}
#
# NF - 23-FEB-2006
# - updated ID line parser to cope with preliminary and pre-RNA
#
# NF - 06-JUL-2006
# - updated ID like parser to cope with new (and old) ID lines
#   moved sequin-specific features to sequin_finish.pl
#
#===============================================================================

use DirHandle;

#
#   CONSTANTS
#

# FTS VERSION:
$VER = "1.30";

# HASH LISTING OF FEATURES TO DISPLAY IN DELINE:
%DE_WORTHY = ( 'CDS', 'yes', 'rRNA', 'yes', 'tRNA', 'yes' );
%t_t = ( "A" => "Ala",
         "R" => "Arg",
         "N" => "Asn",
         "D" => "Asp",
         "C" => "Cys",
         "Q" => "Gln",
         "E" => "Glu",
         "G" => "Gly",
         "H" => "His",
         "I" => "Ile",
         "L" => "Leu",
         "K" => "Lys",
         "M" => "Met",
         "F" => "Phe",
         "P" => "Pro",
         "S" => "Ser",
         "T" => "Thr",
         "W" => "Trp",
         "Y" => "Tyr",
         "V" => "Val",
         "B" => "Asx",
         "Z" => "Glx"
);

#
#   GLOBAL VARIABLES
#
# NUMBER OF CONFIDENTIAL SUBS, HOLD DATE:
( $conf_nb, $hld ) = ( 0, '' );


# no keywords allowed except for the following when $no_keywords_flag = 1.  
# If $no_keywords_flag = , normal keywords e.g. genes and products will be added.
# Exceptions (when $no_keywords_flag = 1):
# 1. 'circular' in ID line =>                      KW   complete genome
# 2. 'complete genome' in DE line =>               KW   complete genome
# 3. 'complete mitochondrial genome' in DE line => KW   complete genome
# 4. 'complete plasmid' in DE line =>              KW   complete genome
# 5. 'complete chloroplast genome' in DE line =>   KW   complete genome
# 6. 'complete viral segment' in DE line =>        KW   complete viral genome
# 7. /\bEST\b/ in DE line =>                       KW   EST; expressed sequence tag
# 8. /\bGSS\b/ in DE line =>                       KW   GSS; genome survey sequence
# 9. /\bSTS\b/ in DE line =>                       KW   STS; sequence tagged site
$no_keywords_flag = 1;


#:::::::::::::::::::::::::GET LIST OF FLAT FILES IN DIR:::::::::::::::::::::::::::::::::::::::
#
print "FTSORT $VER looking through .SUB & .FFL files...\n";
@files = &get_file_list;
&human_nom_reading;

#
#::::::::::::::::::::::::FOR EACH FILE, READ LINES INTO ARRAY:::::::::::::::::::::::::::::::::
#
FILE: foreach $file (@files) {

    #:::::::::::::VARIABLE INITIALIZATIONS (SEE INIT_VAR FOR VARIABLE DESCRIPTIONS)::::::::
    #
    &init_vars;
    print "--------------------------------------------------------\n$file ";

    open( IN, "< $file" ) or die ("Can't open <$file>!\n");
    $file =~ s/\.\w+$/\.temp/;
    print "( saved as $file ) ";

    #
    #:::::::::::::::::::::READ IN TOP HALF OF FLAT FILE :::::::::::::::::::::::::::::::::::
    #
  LINE: while (<IN>) {
        $count++;
        if ( &mangle_top && $mol ) {
            push @newfile, $_;    #DISCARDS WEBIN HEADER LINES
        }
        if (/nnnnn/) {
            $actions{isNNN}++;
        }
        if (/^\/\//) {
            last LINE;
        }
        unless (/^FH\s+Key\s+Location\/Qualifiers/) {
            next LINE;
        }

        #
        #:::::::::::::READ FEATURE TABLE INTO ARRAY: ::::::::::::::::::::::::::::::::::
        #
        $line = <IN>;
        push @newfile, $line;
      FT: while ( defined( $line = <IN> ) ) {
            if ( $line =~ /^XX/ ) {
                last FT;
            }
            if ( ( $feat, $loc ) = ( $line =~ /^FT   (\S+)\s+(\S+)\s*$/ ) ) {

                #
                #::::::::::::::::::::::: NEW FEATURE:::::::::::::::::::::::::::
                #
                $key = $feat;
                push @fk, $key;
                if ( $DE_WORTHY{$key} ) { $DE_feat_nb++ }
                &get_loc;
            }
            else {

                #
                #::::::::::::::::::::::: QUALIFIERS:::::::::::::::::::::::::::
                #
                &mangle_qualifiers;
            }
        }

        #
        #:::::::::::::::LAST CHANCE FIXES TO FEATURES ::::::::::::::::::::::::::::::::
        #
        &check_features;

        #
        #:::::::::::::::SORT FEATURES IN ASCENDING LOCATION ORDER:::::::::::::::::::::
        #
        &sort_features;

        #
        #:::::::::::::::CREATE DE LINE::::::::::::::::::::::::::::::::::::::::::::::::
        #
        &make_de;

        #
        #:::::::::::::::GET KEYWORDS FROM DE LINE:::::::::::::::::::::::::::::::::::::
        #
	if ($no_keywords_flag) {
	    &get_de_keywords;
	}

        #
        #:::::::::::::::CREATE KW LINE::::::::::::::::::::::::::::::::::::::::::::::::
        #
        &make_kw;

        #
        #:::::::::::::::WRITE SORTED FT TO SCREEN AND TO ARRAY::::::::::::::::::::::::
        #
        if ( $actions{hold_date} ) {
            print " ** entry confidential until $actions{hold_date} **\n";
        }
        else {
            print "\n";
        }
        print "$de" . "FT   _";
        foreach $i ( 0 .. $#fk ) {
            print $fk[$i] . '_';

            #print "".(sprintf "%-17.17s", $fk[$i]).(sprintf "%6.6s",$min[$i])." - $max[$i]\n";
            if ( ( $i > 0 ) and ( $ft[$i] eq $ft[ $i - 1 ] ) ) {
                $actions{featureskip}++;
            }
            else {
                push @newfile, $ft[$i];
            }
        }
        print "\n";
        push @newfile, "XX   \n";
    }
    close(IN);

    #
    #:::::::::::::::WRITE WHOLE ARRAY TO OUTPUT FILE:::::::::::::::::::::::::::::::::::
    #
    open( OUT, "> $file" ) or die ("Can't open <$file>!\n");
    foreach $line (@newfile) {
        print OUT $line;
    }
    close(OUT);

    #
    #:::::::::::::::SUMMARIZE ACTIONS PERFORMED ON FILE:::::::::::::::::::::::::
    #
    &show_actions;
}

#
#::::::::::::::::::::::::CONCLUDE:::::::::::::::::::::::::::::::::::::::::::::::::
#
&show_comments;
if (@files) {
    print "" . ( $#files + 1 ) . " files processed" . ( $conf_nb ? " ( *** $conf_nb confidential: $hld !!! *** )" : '' ) . "\n";
}
else {
    print "\nNo .FFL or .SUB files to sort in this directory!\n\n";
}

#
#::::::::::::::::::::::::SCRIPT END:::::::::::::::::::::::::::::::::::::::::::::::::
#
#=============================================================================
#
#
#
#			FUNCTIONS
#
#=============================================================================
#		ADD WORDS TO FLAT FILE LINES WITH AUTO WRAP AROUND
#=============================================================================
sub add_to {
    my ( $typ, $ln, $add ) = @_;
    if ( $typ ne 'KW' ) {
        foreach $word ( split /\s+/, $add ) {
            $ln = &add_element( $typ, $ln, $word );
        }
    }
    else {
        $ln = &add_element( $typ, $ln, $add );
    }
    return ($ln);
}

sub add_element {
    my ( $typ, $ln, $add ) = @_;
    ($last) = ( reverse( split /\n/, $ln ) );
    if ( length($last) + length($add) > 78 ) {
        $ln .= "\n$typ  ";
    }
    $ln .= " $add";
    return ($ln);
}

#=============================================================================
#                           LOOK AT TOP LINES OF FF
#=============================================================================
sub mangle_top {

    if (/^DE   TPA:/)    # look for TPA on DE line
    {
        $istpa = 1;
        return 1;
    }

    if ( !$istpa )       # if TPA not on the DE line check KW line for TPA
    {
        if ( /^KW   / and /Third Party Annotation/ ) {
            $istpa = 1;
            return 1;
        }
    }

    if ( /^DE   / and /([0-9.]+) ?S (r|ribosomal )(R|D)NA/ ) {
        $sub_DE_info = $1;
        return 1;
    }

    if ( /^DE   / and /gene/ ) {
        $genefromDE = 1;
        return 1;
    }

    #             $1=ID   $2=~State                           $3=circ?          $4=mol
    if ((  /^ID   (.+) (standard|confidential|preliminary)\;( circular | )(other RNA|other DNA|unassigned DNA|unassigned RNA|genomic DNA|genomic RNA|mRNA|tRNA|rRNA|snoRNA|snRNA|scRNA|pre-RNA|DNA|RNA|viral cRNA)/
        )
        ||                                                                           # this format was replaced at the end of in May-2006
                                                                                     #           $1=AC   $2=SV    $3=topo  $4=mol  $5=class  $6=taxdiv $7=len)
        (/^ID   (.+) *; *(.+) *; *(.+) *; *(.+) *; *(.+) *; *(.+) *; *(\d+) BP\./)
      )
    {
        $tempmol         = $4;
        $mol_type_length = length($tempmol);
        $mol             = substr( $tempmol, $mol_type_length - 3, 10 );

	$topology = $3;
	if ( $topology =~ /circular/i ) {
	    $kw{'complete genome'} = 1;
	    $actions{circular}++;
	}

        if ( $count > 1 ) {
            $crude = 1;
            $webin = 1;
        }
        return 1;
    }

    if (    (/^ST \* .*(\d{1,2}-[A-Za-z]{3}-\d{4})/)
         || (/^HD \* confidential\s(\S+)\s*\n$/) )
    {    # this format was replaced at the end of in May-2006
        $actions{hold_date} = $1;
        $conf_nb++;
        if ( $hld !~ /$1/ ) {    # build up a string of hold dates
            $hld .= ' ' . $1;
        }
        return 1;
    }

    if (/^RT   \"?((unpublished)|(manuscript\sin\spreparation)|(no\stitle))\"?;?\s*$/i) {
        $_ = "RT   ;\n";
        $actions{bad_title}++;
        return 1;
    }
    return 1;
}

#=============================================================================
#                           GET LIST OF FLAT FILES IN DIR
#=============================================================================
sub get_file_list {
    my @files = ();
    @comments  = ();
    $info_file = '';

    my $dh   = DirHandle->new(".") || die "cannot opendir: $!";
    my @list = $dh->read();

    foreach $file (@list) {
        if ( $file =~ /^\w+\.(FFL$|SUB$|NEWSUB$)/i ) {
            push @files, $file;
        }
        elsif ( $file =~ /^\w+\.(TXT|COMMENT|COMM|COP|CMT|EXP|EXP[CS]\d+)/i ) {
            push @comments, $file;
        }
        elsif ( $file =~ /^\w+\.(INF|INFO)/i ) {
            $info_file = $file;
        }
    }
    return @files;
}

#=============================================================================
#                               VARIABLE INITIALIZATIONS
#=============================================================================
sub init_vars {
    @newfile         = ();                     # ARRAY WITH LINES ULTIMATELY REWRITTEN TO OUTPUT FILE
    $org             = "unknown";              # ORGANISM FOR CURRENT FILE
    $mol             = 0;                      # MOLECULE TYPE FOR CURRENT FILE
    $orf_num         = 1;                      # ORF NUMBER COUNTER
    $sub_DE_info     = '?';                    # EXTRA INFO FOUND IN SUBMITTER PROVIDED DE LINE
    $DE_feat_nb      = 0;                      # NB OF DE LINE WORTHY FEATURES COUNTER
    $exmin           = $exmax = 0;             # LIMITS OF EXON NUMBERS
    $count           = 0;                      # NUMBER OF LINES READ BEFORE 'ID' LINE FOUND (UNPROCESSED WEBIN IF >1)
    $crude           = 1;                      # UNPROCESSED WEBIN FLAG => modified to allow processing
                                               # of SEQUIN files - PH MAY 1999
    $webin           = 0;                      # WEBIN FILE FLAG
    $isrrna          = 0;                      # rRNA flag
    $isITS           = 0;                      # ITS flag
    $human_seq       = 0;                      # Human sequnce flag
    $genes_not_found = "";                     # list of genes not found;
    $genefromDE      = 0;                      # gene mentioned in DE
    $RNAgene         = 0;                      # RNA gene flag (for viruses)
    @max             = @min = ();              # ARRAYS OF FEATURE HIGHER & LOWER LIMITING LOCATIONS
    @comp            = ();                     # ARRAY OF FEATURE COMPLEMENTARY FLAGS
    @ft              = @fk = @DE_feat = ();    # ARRAYS OF FEATURES, FT KEYS & DE WORTHY FEATURES (DE_feat's)
    %kw              = %qlf = ();              # HASH TABLES OF KEYWORDS & QUALIFIERS
    %actions         = ();                     # HASH OF ACTIONS PERFORMED ON EACH FILE
    %DE_uniques      = ();                     # Hash of unique identifiers
    $DE_organelle    = 0;                      # Name of the organelle, nothing by default.
    $istpa           = 0;                      # tpa flag
}

#=============================================================================
#             Human Nomenclature file reading
#=============================================================================
sub human_nom_reading {

    $nomfile = "/ebi/production/seqdb/embl/tools/curators/data/nomenclature.txt";
    open( INNOMFILE, $nomfile ) || die "cannot open nomenclature file\n";
    while (<INNOMFILE>) {
        chomp;
        @fields = split ( /\t/, $_ );
        $human_genes{ $fields[0] } = $fields[1];
    }
    close(INNOMFILE);
}

#=============================================================================
#             GET FULL FEATURE LOCATIONS AND OUTER LOCATION LIMITS
#=============================================================================
sub get_loc {
    until ( $loc =~ /(\d|\))$/ ) {
        $more = <IN>;
        $line .= $more;
        ($more) = ( $more =~ /^FT\s+(\S+)\s$/ );
        $loc .= $more;
    }
    push @ft, $line;
    if ( $loc =~ /complement/ ) {
        push @comp, 1;
    }
    else {
        push @comp, 0;
    }
    $loc =~ s/(complement|join)//g;
    if ( $DE_WORTHY{$key} ) {
        $DE_feat[ $DE_feat_nb - 1 ]{partial} = 0;
        if ( $loc =~ /</ ) {
            $DE_feat[ $DE_feat_nb - 1 ]{partial} += 5;
        }
        if ( $loc =~ />/ ) {
            $DE_feat[ $DE_feat_nb - 1 ]{partial} += 3;
        }
    }
    $loc =~ s/\(|\)|<|>//g;
    if ( $loc =~ /^([0-9]+)$/ ) {
        push @max, $1;
        push @min, $1;
    }
    elsif ( $loc =~ /^(\d+)\D+(\d+)$/ ) {
        push @max, $2;
        push @min, $1;
    }
    else {
        $loc =~ /^(\d+)\D+\S*\D+(\d+)$/;
        push @max, $2;
        push @min, $1;
    }
}

#=============================================================================
#                           CHECK OUT QUALIFIERS
#=============================================================================
sub mangle_qualifiers {
    if ( $line =~ /^FT\s+\/(\w+)(\s|=)/ ) { $qlf{$1}++ }
# Webin is creating the old rpt_unit qualifier that now needs mapping to the two new ones
    if ( $line =~ /\/rpt_unit=/ ) {
	if ($line =~ /\/rpt_unit="((\d+\.\.\d+)|(\d+))"/){
	    $line =~ s/\/rpt_unit="((\d+\.\.\d+)|(\d+))"/\/rpt_unit_range=$1/;
	}
	else {
	    $line =~ s/\/rpt_unit=/\/rpt_unit_seq=/;
	}
    }
    if ( $line =~ /\/codon_start=\d\n$/ ) {
        if ( $line =~ /\/codon_start=1\n$/ ) {
            if ( $DE_feat[ $DE_feat_nb - 1 ]{partial} < 5 and !$comp[$#comp] ) {
                $line = '';
                $actions{codon_st}++;
            }
            if ( ( $DE_feat[ $DE_feat_nb - 1 ]{partial} == 5 or $DE_feat[ $DE_feat_nb - 1 ]{partial} == 0 )
                 and $comp[$#comp] )
            {
                $line = '';
                $actions{codon_st}++;
            }
        }
        else {
            if ( $DE_feat[ $DE_feat_nb - 1 ]{partial} < 5 and !$comp[$#comp] ) {
                $actions{codon_st_warn}++;
            }
            if ( ( $DE_feat[ $DE_feat_nb - 1 ]{partial} == 5 or $DE_feat[ $DE_feat_nb - 1 ]{partial} == 0 )
                 and $comp[$#comp] )
            {
                $actions{codon_st_warn}++;
            }
        }

    }
    if ( $line =~ /\/organism="(.+)"/ ) {
        $org = $1;
        if ( $org =~ /Homo sapiens/ ) {
            $human_seq = 1;
        }

        if ( ( $org =~ /virus/i ) and ( $mol eq RNA ) and ($genefromDE) ) {
            $RNAgene = 1;
            $actions{RNA_gene}++;
        }

        ( $g, $s ) = ( $org =~ /^(\w)\w*\W?\s+(\w)\w*/ );
        if ($g) {
            $g = lc $g;
        }
        if ($s) {
            $s = lc $s;
        }
    }

    if ( $line =~ /\/strain="(.+)"/ ) {
        $DE_uniques{strain} = $1;
    }
    if ( $line =~ /\/isolate="(.+)"/ ) {
        $DE_uniques{isolate} = $1;
    }
    if ( $line =~ /\/clone="(.+)"/ ) {
        $DE_uniques{clone} = $1;
    }

    if ( $line =~ /\/organelle="(.+)"/ ) {
        $DE_organelle = $1;
        if ( $DE_organelle =~ /.+:(.+)/ ) {
            $DE_organelle = $1;
        }
    }

    if ( ($gene) = ( $line =~ /\/gene="(.+)"/ ) ) {
        &do_gene_stuff;
    }
    if ( ($product) = ( $line =~ /\/product=\"([^"]+)"?\n$/ ) ) {
        &do_prod_stuff;
    }
    if ( ($exnb) = ( $line =~ /\/number=(\d+)\n$/ ) ) {
        if ( $key eq 'exon' ) {
            if ($exmin) {
                if ( $exnb > $exmax ) {
                    $exmax = $exnb;
                }
                elsif ( $exnb < $exmin ) {
                    $exmin = $exnb;
                }
            }
            else {
                $exmin = $exmax = $exnb;
            }
        }
    }
    if ( $line =~ /\/immunoglobulin$/ ) {
	$line = "";
    }

    if ($line =~ /\/virion$/ ) {
	$line = "";
    }

    $ft[$#fk] .= $line;
}

#=============================================================================
#                               DEAL WITH A GENE QUALIFIER
#=============================================================================
sub do_gene_stuff {
    if ( $gene =~ /ITS/ or $gene =~ /internal transcribed spacer/ ) {
        return;
    }

    #
    #::::::::::::::TAKE OUT EXTRA 'GENE' FROM /GENE:::::::::::::::::::::::::::::::::::
    #
    if ( $gene =~ /^(.+)\sgene$/ ) {
        $gene = $1;
        $line =~ s/\/gene=".+"/\/gene="$gene"/;
        $actions{extra_gene}++;
    }

    #::::::::::::::TAKE OUT PARTIAL FROM /GENE:::::::::::::::::::::::::::::::::::::::::
    #
    if ( $gene =~ s/(, |,|)partial( |)// ) {
        $line =~ s/(, |,|)partial( |)//;
        $actions{partial_gene}++;
    }

    #::::::::::::::TAKE OUT GENUS/SPECIES PREFIX:::::::::::::::::::::::::::::::::::::::::
    #
    if ( $g && $s ) {
        if ( $gene =~ /^$g$s/i ) {
            $gene =~ s/^$g$s//i;
            $line =~ s/"$g$s/"/i;
            $actions{gene_prefix}++;
        }
    }

    #::::::::::::::GIVE WARNING ABOUT XENOPUS :::::::::::::::::::::::::::::::::::::::::
    #
    if ( $org =~ /^Xenopus/ ) {
        if ( $gene =~ /^[xX]/i ) {
            $actions{xen_warning}++;
        }
    }

    #::::::::::::::MAKE UPPERCASE GENE LOWERCASE:::::::::::::::::::::::::::::::::::::::::
    #
    if ( ($ugene) = ( $gene =~ /^([A-Z]+)/ ) ) {
        unless (    $org =~ /^Trypanosoma/
                 or $org =~ /^Drosophila melanogaster/
                 or $org =~ /bacterium/
                 or $org =~ /virus/ )
        {
            $lgene = lc($ugene);
            $line =~ s/="$ugene/="$lgene/;
            $gene =~ s/$ugene/$lgene/;
            $actions{gene_case}++;
        }
    }

    #::::::::::::::MAKE LOWERCASE GENE UPPERCASE:::::::::::::::::::::::::::::::::::::::::
    #
    if ( ($ugene) = ( $gene =~ /^(\w+)/ ) ) {
        if (    $org =~ /^Homo sapiens/
             or $org =~ /^Sus scrofa/
             or $org =~ /^Bos taurus/
             or $org =~ /^Saccharomyces cerevisiae/
             or $org =~ /^Gallus gallus/ )
        {
            $lgene = uc($ugene);
            $line =~ s/="$ugene/="$lgene/;
            $gene =~ s/$ugene/$lgene/;
            $actions{gene_case_u}++;
        }
    }

    #::::::::::::::MAKE GENE MIXED CASE::::::::::::::::::::::::::::::::::::::::::::::::::
    #
    if ( ($ugene) = ( $gene =~ /^(\w+)/ ) ) {
        if (    $org =~ /^Mus musculus/
             or $org =~ /^Rattus norvegicus/ )
        {

            # $OG_organelle = "\u\L$qual_contents";
            $lgene = "\u\L$ugene";    ## done
            $line =~ s/="$ugene/="$lgene/;    # to do?
            $gene =~ s/$ugene/$lgene/;        # to do?
                                              #$actions{gene_case_u}++;
        }
    }

    #::::::::::::::TRANSFER ORF FROM /GENE TO /NOTE:::::::::::::::::::::::::::::::::::::::::
    #
    if (    $gene =~ /^orf(.*)$/i
         or $gene =~ /^putative orf(.*)$/i )
    {
        if ($1) {
            $i = $1;
        }
        else {
            $i = $orf_num;
            $orf_num++;
        }
        $gene = "ORF$i";
        $line =~ s/\/gene=".+"/\/note="$gene"/;

        if (! $no_keywords_flag) { $kw{$gene} = 1; }

        $actions{orf_note}++;

        if ( $key eq 'CDS' ) {
            $DE_feat[ $DE_feat_nb - 1 ]{orf} = $gene;

            #$line .= "[FTS added following line]\n".
            #"FT                   /product=\"!!hypothetical protein\"\n";
            #$actions{prod_orf}++;
        }
        return;
    }

    #::::::::::::::RIBOSOMAL RNA:::::::::::::::::::::::::::::::::::::::::
    #
    if ( $gene =~ /^([0-9\.]+) ?S( (r|ribosomal )(R|D)NA|$)/ ) {
        $isrrna = 1;
        if ( $gene ne "$1S rRNA" ) {
            $gene = $1 . 'S rRNA';
            $line = "FT                   /gene=\"$gene\"\n";
            $actions{rRNA_gene}++;
        }

        #$line .= "[FTS added following line]\n".
        #"FT                   /product=\"!!$1S ribosomal RNA\"\n";
        if ( $ft[$#fk] !~ /^FT   rRNA/ ) {    #::::::::KEY SWITCH!:::::::::::::::
            $key = 'rRNA';
            $DE_feat_nb++;
            if ( $ft[$#fk] =~ /^FT   \S+\s+\S*<\d+/ ) {
                $DE_feat[ $DE_feat_nb - 1 ]{partial} += 5;
            }
            if ( $ft[$#fk] =~ /^FT   \S+\s+\S*>\d+/ ) {
                $DE_feat[ $DE_feat_nb - 1 ]{partial} += 3;
            }
            $ft[$#fk] =~ s/^FT(   \S+\s+(\S+))/FT   rRNA            $2\n**$1/;
            $actions{rRNA_key}++;
        }
    }

    #::::::::::::::TRANSFER RNA:::::::::::::::::::::::::::::::::::::::::
    if ( $gene =~ /(^t|transfer |transport )(R|D|r)(NA|n|N|na)\-{0,1}\s{0,1}(\w+)\s{0,1}(\S{0,})/ ) {
        if ( $t_t{$4} ) {
            if ($5) { $gene = "tRNA-$t_t{$4} $5"; }
            else { $gene = "tRNA-$t_t{$4}"; }

        }
        else {
            if ($5) {
                $gene = "tRNA-$4 $5";
            }
            else {
                $gene = "tRNA-$4";
                if ( length($4) > 3 ) {
                    $actions{tRNA_nomenclature}++;
                }
            }
        }
        $line = "FT                   /gene=\"$gene\"\n";
        if ( $ft[$#fk] !~ /^FT   tRNA/ ) {    #::::::::KEY SWITCH!:::::::::::::::
            $key = 'tRNA';
            $DE_feat_nb++;
            if ( $ft[$#fk] =~ /^FT   \S+\s+\S*<\d+/ ) {
                $DE_feat[ $DE_feat_nb - 1 ]{partial} += 5;
            }
            if ( $ft[$#fk] =~ /^FT   \S+\s+\S*>\d+/ ) {
                $DE_feat[ $DE_feat_nb - 1 ]{partial} += 3;
            }
            $ft[$#fk] =~ s/^FT(   \S+\s+(\S+))/FT   tRNA            $2\n**$1/;
            $actions{tRNA_key}++;
        }
    }

    #:::::::::::::::IF HUMAN SEQ CHECK IN THE LIST OF GENES::::::::::::::::::::::::::
    if ($human_seq) {
        $gene_listed = $human_genes{ uc($gene) };
        if ($gene_listed) {
            $last_gene      = $gene;
            $product_listed = $human_genes{ uc($gene) };
        }
        if ( not $gene_listed ) {
            $actions{gene_not_listed}++;
            $genes_not_found = $genes_not_found . " " . uc($gene);
        }
    }

    #:::::::::::::::ADD TO LIST OF KW AND DE LINE BUILDING BLOCKS::::::::::::::::::::::::::
    #
    if ( $DE_WORTHY{$key} ) {    #add gene to KW list
        if (! $no_keywords_flag) { $kw{"$gene gene"} = 1; }

        $DE_feat[ $DE_feat_nb - 1 ]{gene} = $gene;
    }
}

#=============================================================================
#                               DEAL WITH A PRODUCT QUALIFIER
#=============================================================================
sub do_prod_stuff {
    if ( $product =~ /ITS/ or $product =~ /internal transcribed spacer/ ) {
        return;
    }

    #::::::::::::::::::::GET FULL PRODUCT TEXT::::::::::::::::::::::::::::::::
    #
    until ( $line =~ /\"\n$/ ) {
        $more = <IN>;
        $line .= $more;
        ($more) = ( $more =~ /^FT\s+(\S[^"]+)"?\n$/ );
        $product .= " ";
        $product .= $more;
    }

    #::::::::::::::::::::ORF PRODUCT:::::::::::::::::::::::::::::::::::::::::::::
    #
    if ( $key eq 'CDS' and $DE_feat[ $DE_feat_nb - 1 ]{orf} ) {
        unless ( $product eq 'hypothetical protein' ) {
            $line =~ s/FT   /**   /g;
            return;
        }

        #else {	$product = 'hypothetical protein';
        #	unless ($line =~ s/"!!/"/) {$line = ''}
        #};
    }

    #:::::::::::::::::::::rRNA PRODUCT::::::::::::::::::::::::::::::::::::::::::::
    #
    if ( $key eq 'rRNA' ) {
        $isrrna = 1;
        unless ( $product =~ /^[0-9.]+S ribosomal RNA$/ ) {
            $line =~ s/FT   /**   /g;
            return;
        }
    }

    #:::::::::::::::::::::tRNA PRODUCT::::::::::::::::::::::::::::::::::::::::::::
    #
    if ( $key eq 'tRNA' ) {
        $isrrna = 1;
        unless ( $product =~ /^transfer RNA/ ) {
            $line =~ s/FT   /**   /g;
            return;
        }
    }

    #::::::::::::::::::::TAKE OUT PARTIAL FROM /PRODUCT::::::::::::::::::::::::::::
    #
    if ( $product =~ s/(, |,|)partial( |)// ) {
        $line =~ s/(, |,|)partial( |)//;
        $actions{partial_prod}++;
    }

    #::::::::::::::::::::DOWN CASE PRODUCT NAME::::::::::::::::::::::::::::::::::::::
    #
    if (    $product =~ /^([A-Z])[a-z]+\s[a-z]+/
         && $product !~ /^([A-Z])[a-z]+\sprotein/ )
    {
        $init = lc($1);
        $line    =~ s/\/product="$1/\/product="$init/;
        $product =~ s/^[A-Z]/$init/;
        $actions{prod_case}++;
    }

    #:::::::::::::::::::::GENE NAME SAME AS PRODUCT NAME::::::::::::::::::::::::::::::
    #
    if ( $key eq 'CDS' and $DE_feat[ $DE_feat_nb - 1 ]{gene} ) {
        if ( $g && $s && $product =~ /^$g$s$DE_feat[$DE_feat_nb-1]{gene}/i ) {
            $product =~ s/^$g$s//i;
            $line    =~ s/"$g$s/"/i;
            $actions{prod_prefix}++;
        }
        if (     $product =~ /^$DE_feat[$DE_feat_nb-1]{gene}$/i
             and $product !~ /(in|ase|or)$/ )
        {
            $product .= ' protein';
            $line =~ s/"\n$/ protein"\n/i;
            $actions{prot_added}++;
        }
    }

    #:::::::::::::::IF HUMAN AND GENE NAME IN THE LIST CHECK THE PRODUCT::::::::::::::::::::::::::
    if ($human_seq) {
        if ($gene_listed) {
            if ( $product_listed =~ / \(/ ) {
                $actions{synonyms}++;
                $synonyms_used = "for $last_gene\n  listed - $product_listed\n  in flatfile - $product\n";
            }
            elsif ( not $product =~ $product_listed ) {
                $actions{prod_mismatch}++;
                $mismatched_products .= "for $last_gene\n  listed - $product_listed\n  in flatfile - $product\n";
            }
        }
    }

    #:::::::::::::::ADD TO LIST OF KW AND DE LINE BUILDING BLOCKS::::::::::::::::::::::::::
    #
    if ( $DE_WORTHY{$key} ) {
        if (! $no_keywords_flag) { $kw{$product} = 1; }

        $DE_feat[ $DE_feat_nb - 1 ]{product} = $product;
    }
}

#=============================================================================
#                           LAST CHANCE CHECK OF FEATURES
#=============================================================================
sub check_features {
    if ( $#fk > 0 ) {
        foreach $i ( 0 .. $#fk ) {

            #:::::::::::::::::::CHECK ITS IS CORRECT::::::::::::::::::::::::::::::::::::::
            #
            if (     $ft[$i] =~ /^FT   (\S+RNA|misc_feature)/
                 and $ft[$i] =~ /(internal transcribed spacer|ITS)/ )
            {
                if ( $ft[$i] =~ /\/\S+="[^"]+(1|2)/ ) {
                    $its_num = $1;
                }
                else {
                    $its_num = '';
                }
                $isITS   = 1;
                $gene    = "ITS$its_num";
                $product = "internal transcribed spacer" . ( $its_num ? " $its_num" : '' );    #ql
                ( $sub_feat, $loc, $rest ) = ( $ft[$i] =~ /^FT   (\S+)\s+(\S+)\n(.*)$/s );

                unless ( $sub_feat eq 'misc_feature' ) {
                    $insert = "[FTS added following line]\nFT   misc_feature    $loc\n";
                    $ft[$i] =~ s/^FT   (.+)\n/**   $1\n$insert/;
                }

                if ( $rest =~ /FT                   \/note="internal transcribed spacer $its_num"/ ) {
                    $insert = "[FTS added following line]\nFT                   /note=\"$product, $gene\"\n";
                    $ft[$i] =~ s/FT                   \/(\S+=".*(internal transcribed spacer|ITS).*")/$insert**                   \/$1/;
                }

                unless ( $rest =~ /FT                   \/note="internal transcribed spacer $its_num|ITS, $gene"/ ) {
                    $insert = "[FTS added following line]\nFT                   /note=\"$product, $gene\"\n";
                    $ft[$i] =~ s/FT                   \/(\S+=".*(internal transcribed spacer|ITS).*")/$insert**                   \/$1/;
                }

                #     $product="internal transcribed spacer $its_num"; #ql
                if (! $no_keywords_flag) { $kw{$product} = 1; }
                if (! $no_keywords_flag) { $kw{$gene}    = 1; }

                if ( $sub_feat eq 'rRNA' ) {
                  SLOT2: foreach $o ( 0 .. $DE_feat_nb - 1 ) {

                        #MIGHT NEED SOME TIDYING UP DOWN HERE!!!
                        #::::::look for empty slot
                        if (     !$DE_feat[$o]{gene}
                             and !$DE_feat[$o]{product}
                             and !$DE_feat[$o]{orf}
                             and !$DE_feat[$o]{its} )
                        {
                            $DE_feat[$o]{its} = "$product ($gene)";

                            #$DE_feat[$o]{product}=$product;
                            last SLOT2;
                        }
                    }
                }
                else {
                    $DE_feat_nb++;
                    $DE_feat[ $DE_feat_nb - 1 ]{its}     = "$gene";
                    $DE_feat[ $DE_feat_nb - 1 ]{product} = $product;
                }
                $actions{ITS_fixed}++;
                next;
            }

            #:::::::::::::::::::CHECK rRNA IS CORRECT::::::::::::::::::::::::::::::::::::::
            #
            if ( $ft[$i] =~ /^FT   rRNA/
                 and ( $ft[$i] !~ /\/gene=/ or $ft[$i] !~ /FT\s+\/product=/ ) )
            {
                if ( $ft[$i] =~ /([0-9.]+) ?S (r|ribosomal )(R|D)NA/ ) {
                    $guess_number = $1;
                }
                elsif ( $ft[$i] =~ /([0-9.]+) ?S/ ) {
                    $guess_number = $1;
                }
                else {
                    $guess_number = $sub_DE_info;
                    $actions{rRNA_guessed}++;
                }
                $gene    = $guess_number . "S rRNA";
                $product = $guess_number . "S ribosomal RNA";
                ( $no_s_gene, $no_s_prod ) = ( 0, 0 );
                $ft[$i] =~ s/\*\*\s+\/product="$product"/FT                   \/product="$product"/;
                unless ( $ft[$i] =~ /gene="$gene"/ ) {
                    $ft[$i] .= "[FTS added following line]\n" . "FT                   /gene=\"$gene\"\n";
                    $no_s_gene = 1;
                }
                unless ( $ft[$i] =~ /product="$product"/ ) {
                    $ft[$i] .= "[FTS added following line]\n" . "FT                   /product=\"$product\"\n";
                    $no_s_prod = 1;
                }

                if (! $no_keywords_flag) { $kw{$product}     = 1; }
                if (! $no_keywords_flag) { $kw{"$gene gene"} = 1; }

                if ( $no_s_gene and $no_s_prod ) {
                  SLOT: foreach $o ( 0 .. $DE_feat_nb - 1 ) {

                        #MIGHT NEED SOME TIDYING UP DOWN HERE!!!
                        #::::::look for empty slot
                        if (     !$DE_feat[$o]{gene}
                             and !$DE_feat[$o]{product}
                             and !$DE_feat[$o]{orf}
                             and !$DE_feat[$o]{its} )
                        {
                            $DE_feat[$o]{gene}    = $gene;
                            $DE_feat[$o]{product} = $product;
                            last SLOT;
                        }
                    }
                }
                else {
                  SLOT2: foreach $o ( 0 .. $DE_feat_nb - 1 ) {

                        #MIGHT NEED SOME TIDYING UP DOWN HERE!!!
                        #::::::look for empty slot
                        if ( ( $no_s_gene and !$DE_feat[$o]{gene} and $DE_feat[$o]{product} eq $product )
                             or (     $no_s_prod
                                  and !$DE_feat[$o]{product}
                                  and $DE_feat[$o]{gene} eq $gene )
                          )
                        {
                            $DE_feat[$o]{gene}    = $gene;
                            $DE_feat[$o]{product} = $product;
                            last SLOT2;
                        }
                    }
                }
                $actions{rRNA_gene}++;
                next;
            }

            #:::::::::::::::::::CHECK tRNA IS CORRECT::::::::::::::::::::::::::::::::::::::
            if ( $ft[$i] =~ /^FT   tRNA/
                 and ( $ft[$i] !~ /\/gene=/ or $ft[$i] !~ /FT\s+\/product=/ ) )
            {
                $guess_aa = 0;
                if ( $ft[$i] =~ /(t|transfer |transport )(R|D|r)(NA|n|na)\-{0,1}(\w+)\s{0,1}([a-zA-Z)(]{0,})/ ) {
                    $guess_aa = $4;
                    $actions{tRNA_guessed}++;
                }
                if ( not $guess_aa ) {
                    if ( $ft[$i] =~ /\,aa:(\w+)/ ) {
                        $guess_aa = $1;
                        $actions{tRNA_guessed}++;
                    }
                }

                if ($5) {
                    $add = " " . $5;
                }
                else {
                    $add = "";
                }
                $gene    = "tRNA-" . $guess_aa . $add;
                $product = "transfer RNA-" . $guess_aa . $add;
                my $escapedGene    = quotemeta($gene);
                my $escapedProduct = quotemeta($product);
                ( $no_s_gene, $no_s_prod ) = ( 0, 0 );
                $ft[$i] =~ s/\*\*\s+\/product="$escapedProduct"/FT                   \/product="$product"/;

                unless ( $ft[$i] =~ /gene="$escapedGene"/ ) {
                    $ft[$i] .= "[FTS added following line]\n" . "FT                   /gene=\"$gene\"\n";
                    $no_s_gene = 1;
                }
                unless ( $ft[$i] =~ /product="$escapedProduct"/ ) {
                    $ft[$i] .= "[FTS added following line]\n" . "FT                   /product=\"$product\"\n";
                    $no_s_prod = 1;
                }

                if ( ! $no_keywords_flag ) { $kw{$product}     = 1; }
                if ( ! $no_keywords_flag ) { $kw{"$gene gene"} = 1; }

                if ( $no_s_gene and $no_s_prod ) {
                  SLOT: foreach $o ( 0 .. $DE_feat_nb - 1 ) {

                        #MIGHT NEED SOME TIDYING UP DOWN HERE!!!
                        #::::::look for empty slot
                        if (     !$DE_feat[$o]{gene}
                             and !$DE_feat[$o]{product}
                             and !$DE_feat[$o]{orf}
                             and !$DE_feat[$o]{its} )
                        {
                            $DE_feat[$o]{gene}    = $gene;
                            $DE_feat[$o]{product} = $product;
                            last SLOT;
                        }
                    }
                }
                else {
                  SLOT2: foreach $o ( 0 .. $DE_feat_nb - 1 ) {

                        #MIGHT NEED SOME TIDYING UP DOWN HERE!!!
                        #::::::look for empty slot
                        if ( ( $no_s_gene and !$DE_feat[$o]{gene} and $DE_feat[$o]{product} eq $product )
                             or (     $no_s_prod
                                  and !$DE_feat[$o]{product}
                                  and $DE_feat[$o]{gene} eq $gene )
                          )
                        {
                            $DE_feat[$o]{gene}    = $gene;
                            $DE_feat[$o]{product} = $product;
                            last SLOT2;
                        }
                    }
                }
                $actions{rRNA_gene}++;
                next;
            }

            #:::::::::::::::::::CDS WITH NO GENE OR PRODUCT:::::::::::::::::::::::::::::::::
            #
            if (     $ft[$i] =~ /^FT   CDS/
                 and $ft[$i] !~ /\/(gene|product|EC_number)/ )
            {
                $gene = "ORF$orf_num";
                $orf_num++;
                $product = "hypothetical protein";
                $ft[$i] .= "[FTS added following 2 lines]\n" . "FT                   /note=\"$gene\"\n" . "FT                   /product=\"$product\"\n";

                if ( ! $no_keywords_flag ) { $kw{$product} = 1; }
                if ( ! $no_keywords_flag ) { $kw{$gene}    = 1; }

              SLOT: foreach $o ( 0 .. $DE_feat_nb - 1 ) {

                    #MIGHT NEED SOME TIDYING UP DOWN HERE!!!
                    #::::::look for empty slot
                    if (     !$DE_feat[$o]{gene}
                         and !$DE_feat[$o]{product}
                         and !$DE_feat[$o]{orf}
                         and !$DE_feat[$o]{its} )
                    {
                        $DE_feat[$o]{orf}     = $gene;
                        $DE_feat[$o]{product} = $product;
                        last SLOT;
                    }
                }
                $actions{orf_added}++;
                next;
            }

            #:::::::::::::::::::CDS WITH GENE BUT NO PRODUCT:::::::::::::::::::::::::::::
            #
            if (     $ft[$i] =~ /^FT   CDS/
                 and $ft[$i] !~ /\/product/
                 and $ft[$i] =~ /\/gene/ )
            {
                ($gene) = ( $ft[$i] =~ /\/gene="(.+)"/ );
                $product = ucfirst($gene) . ' protein';
                $ft[$i] .= "[FTS added following line]\n" . "FT                   /product=\"$product\"\n";
                $actions{genprod_added}++;
                next;
            }

            #:::::::::::::::::::CDS WITH /NOTE="ORF..." BUT NO PRODUCT::::::::::::::::::::
            #
            if (     $ft[$i] =~ /^FT   CDS/
                 and $ft[$i] =~ /\/note=\"ORF/
                 and $ft[$i] !~ /\/product="hypothetical protein"/ )
            {
                $ft[$i] .= "[FTS added following line]\n" . "FT                   /product=\"hypothetical protein\"\n";

                if ( ! $no_keywords_flag ) { $kw{'hypothetical protein'} = 1; }

              SLOT: foreach $o ( 0 .. $DE_feat_nb - 1 ) {

                    #MIGHT NEED SOME TIDYING UP DOWN HERE!!!
                    #::::::look for empty slot
                    if (     $DE_feat[$o]{orf}
                         and !$DE_feat[$o]{product}
                         and !$DE_feat[$o]{gene}
                         and !$DE_feat[$o]{its} )
                    {
                        $DE_feat[$o]{product} = 'hypothetical protein';
                        last SLOT;
                    }
                }
                $actions{prod_orf}++;
                next;
            }
        }
    }
}

#=============================================================================
#                           SORT FEATURES
#=============================================================================
sub sort_features {
    if ( $#fk > 0 ) {
        foreach $i ( 0 .. $#fk - 1 ) {
            foreach $o ( $i .. $#fk ) {
                if ( $min[$i] > $min[$o] ) {
                    $actions{ft_sorted}++;
                    ( $min[$i], $max[$i], $ft[$i], $fk[$i], $min[$o], $max[$o], $ft[$o], $fk[$o], $comp[$o] ) =
                      ( $min[$o], $max[$o], $ft[$o], $fk[$o], $min[$i], $max[$i], $ft[$i], $fk[$i], $comp[$i] );
                }
            }
        }
        foreach $i ( 0 .. $#fk - 1 ) {
            foreach $o ( $i .. $#fk ) {
                if ( $min[$i] == $min[$o] and $max[$i] < $max[$o] ) {
                    $actions{ft_sorted}++;
                    ( $min[$i], $max[$i], $ft[$i], $fk[$i], $min[$o], $max[$o], $ft[$o], $fk[$o], $comp[$o] ) =
                      ( $min[$o], $max[$o], $ft[$o], $fk[$o], $min[$i], $max[$i], $ft[$i], $fk[$i], $comp[$i] );
                }
            }
        }
    }

}

#=============================================================================
#                           WRITE DE LINE
#=============================================================================
sub make_de {
    $firstchar    = substr( $org, 0, 1 );
    $newfirstchar = uc($firstchar);
    $_            = $org;
    s/$firstchar/$newfirstchar/;
    $org = $_;

    if ($istpa) {
        $org = "TPA: $org";
    }

    # to print on DE line mitochondrial rather than mitochondrion ql
    if ( $DE_organelle =~ /mitochondrion/ ) {
        $DE_organelle = "mitochondrial";
    }

    $de = "DE   $org"
      . ( $qlf{'mitochondrion'} ? ' mitochondrial'    : '' )
      . ( $qlf{'chromoplast'}   ? ' chromoplast'      : '' )
      . ( $qlf{'chloroplast'}   ? ' chloroplast'      : '' )
      . ( $qlf{'cyanelle'}      ? ' cyanelle'         : '' )
      . ( $qlf{'kinetoplast'}   ? ' kinetoplast'      : '' )
      . ( $qlf{'macronuclear'}  ? ' macronuclear'     : '' )
      . ( $qlf{'proviral'}      ? ' proviral'         : '' )
      . ( $qlf{'transposon'}    ? ' transposon'       : '' )
      . ( $DE_organelle         ? ' ' . $DE_organelle : '' );

    if ( ( $mol eq 'RNA' ) && $isrrna ) {
        $actions{rRNA_RnaToDna}++;
    }
    if ( ( $mol eq 'RNA' ) && $isITS ) {
        $actions{ITS_RnaToDna}++;
    }
    if ( ( $mol eq 'RNA' ) && ( $DE_feat_nb > 1 ) ) {
        $actions{genomic_RNA_2_or_more_CDS}++;
    }
    if ($DE_feat_nb) {
        if (    ( $mol eq 'DNA' )
             or $isrrna
             or $RNAgene
             or $isITS
             or ( $DE_feat_nb > 1 ) )
        {

            #:::::::::::::::::: IF DE_feat FEATURES AND DNA or rRNA or genomic RNA
            &make_DNA_de;
        }
        else {

            #:::::::::::::::::: IF DE_feat FEATURES AND RNA :::::::::::::::::::
            &make_RNA_de;
        }
    }
    else {
        $de .= " ";
    }

    if ( $isrrna or $isITS ) {
        if (    ( $DE_uniques{strain} )
             or ( $DE_uniques{isolate} )
             or ( $DE_uniques{clone} ) )
        {
            $de .= ',';
        }
        if ( $DE_uniques{strain} ) {
            $de = &add_to( 'DE', $de, 'strain ' . $DE_uniques{strain} );
        }
        elsif ( $DE_uniques{isolate} ) {
            $de = &add_to( 'DE', $de, 'isolate ' . $DE_uniques{isolate} );
        }
        elsif ( $DE_uniques{clone} ) {
            $de = &add_to( 'DE', $de, 'clone ' . $DE_uniques{clone} );
        }
    }

    if ( not($isrrna) ) {
        if ( $RNAgene or ( ( $mol eq 'RNA' ) && ( $DE_feat_nb > 1 ) ) ) {
            $de .= ',';
            $de = &add_to( 'DE', $de, 'genomic RNA' );
        }
    }
    $de .= "\n";

  SEARCH: foreach $i ( 0 .. @newfile - 1 ) {
        if ( $newfile[$i] =~ /^DE   / and !$actions{de_added} ) {
            if ( $de eq $newfile[$i] ) {
                $actions{smart_sub} = 1;
            }
            elsif ($crude) {
                $newfile[$i] =~ s/^DE   /**   /;

                #$newfile[$i] = $de."--above: automatic DE--below: submitter DE--\n".
                $newfile[$i] = $de . $newfile[$i];
                $actions{de_added} = 1;
            }
        }
        else {
            $newfile[$i] =~ s/^DE   /**   /;
        }
        if ( $newfile[$i] =~ /^KW\s+/ ) { last SEARCH }
    }
}

#=============================================================================
#                           WRITE DNA DE LINE
#=============================================================================
sub make_DNA_de {
    if ( $DE_feat_nb - 1 > 1 ) {
        $mult = 1;
    }
    else {
        $mult = 0;
    }
    if ( $DE_feat_nb < 3 ) {
        $nottoomuch = 1;
    }
    else {
        $nottoomuch = 0;
    }

    foreach $i ( 0 .. $DE_feat_nb - 1 ) {
        if ( $i > 0 ) {
            if ( $nottoomuch && not($i) ) {
                $de = &add_to( 'DE', $de, 'and' );
            }
            else {
                if ( $i eq $DE_feat_nb - 1 ) {
                    $de = &add_to( 'DE', $de, 'and' );
                }
                else {
                    $de .= ',';
                }
            }
        }
        if ( $DE_feat[$i]{partial} && $nottoomuch ) {
            $de = &add_to( 'DE', $de, 'partial' );
        }
        if ( not( $DE_feat[$i]{its} ) ) {
            if ( not( $DE_feat[$i]{orf} ) ) {
                $de = &add_to( 'DE', $de, $DE_feat[$i]{gene} . ' gene' );
            }
            else {
                $de = &add_to( 'DE', $de, $DE_feat[$i]{orf} );
            }
        }

        if ( $DE_feat[$i]{partial} && not($nottoomuch) ) {
            if ( not( $DE_feat[$i]{its} ) ) {
                $de = &add_to( 'DE', $de, '(partial)' );
            }
        }

        if ( $DE_feat[$i]{product} ) {
            if ( not( $DE_feat[$i]{product} =~ /ribosomal RNA/ ) ) {
                if ( $DE_feat[$i]{its} ) {
                    $de = &add_to( 'DE', $de, $DE_feat[$i]{its} );
                }
                else {
                    if ( not( $DE_feat[$i]{gene} ) or $nottoomuch ) {
                        my $temp_prod = '';
                        if ( $DE_feat[$i]{gene} ) {
                            $temp_prod = $DE_feat[$i]{gene} . ' protein';
                        }
                        if (     not( $DE_feat[$i]{product} =~ /hypothetical protein/ )
                             and not( $DE_feat[$i]{product} =~ /$temp_prod/i ) )
                        {
                            $de = &add_to( 'DE', $de, 'for ' . $DE_feat[$i]{product} );
                        }
                    }
                }
            }
        }
        else {
            $actions{tRNA_nomenclature}++;
        }
    }

    #::::::::::::: exons :::::::::::: ::::::::::::::::::
    if ( $exmin && $DE_feat_nb == 1 ) {
        $de .= ',';
        if ( $exmin < $exmax ) {
            $de = &add_to( 'DE', $de, 'exons ' . $exmin . '-' . $exmax );
        }
        else {
            $de = &add_to( 'DE', $de, 'exon ' . $exmin );
        }
    }
}

#=============================================================================
#                           WRITE DE RNA LINE
#=============================================================================
sub make_RNA_de {
    if ( $DE_feat_nb - 1 > 1 ) {
        $mult = 1;
    }
    else {
        $mult = 0;
    }
    if ( $DE_feat_nb - 1 < 2 ) {
        $nottoomuch = 1;
    }
    else {
        $nottoomuch = 0;
    }

    foreach $i ( 0 .. $DE_feat_nb - 1 ) {
        if ( $i > 0 ) {
            if ($nottoomuch) {
                $de = &add_to( 'DE', $de, 'and' );
            }
            else {
                if ( $i eq $DE_feat_nb - 1 ) {
                    $de = &add_to( 'DE', $de, 'and' );
                }
                else {
                    $de .= ',';
                }
            }
        }
        if ( $DE_feat[$i]{partial} ) {
            $de = &add_to( 'DE', $de, 'partial' );
        }
        my $temp_prod = '';
        if ( $DE_feat[$i]{gene} ) {
            $temp_prod = $DE_feat[$i]{gene} . ' protein';
        }
        if ( $DE_feat[$i]{product} ) {
            $de = &add_to( 'DE', $de, 'mRNA for ' . $DE_feat[$i]{product} );
        }
	$temp_prod = quotemeta($temp_prod); 
        # to stop problem of 'product' => '?S ribosomal RNA',
        if ( not $DE_feat[$i]{orf} ) {
            if ( $DE_feat[$i]{gene}
                 and not( $DE_feat[$i]{product} =~ /$temp_prod/i ) )
            {
                $de = &add_to( 'DE', $de, '(' . $DE_feat[$i]{gene} . ' gene)' );
            }
        }
        else {
            $de = &add_to( 'DE', $de, '(' . $DE_feat[$i]{orf} . ')' );
        }
    }
}

#=============================================================================
#                           GET KEYWORDS FROM DE LINE
#=============================================================================

sub get_de_keywords {

    if ( $de =~ /complete (genome|plasmid)/i ) {
	$kw{'complete genome'} = 1;
	$actions{'complete genome'}++;
    }
    elsif ($de =~ /complete (mitochondrial|chloroplast) genome/i ) {
	$kw{'complete genome'} = 1;
	$actions{'complete genome'}++;
    }
    elsif ($de =~ /complete viral segment/i ) {
	$kw{'complete viral segment'} = 1;
	$actions{'complete viral segment'}++;
    }
    elsif ($de =~ /\bEST\b/ ) {
	$kw{'EST'} = 1;
	$kw{'expressed sequence tag'} = 1;
	$actions{EST}++;
    }
    elsif ($de =~ /\bSTS\b/ ) {
	$kw{'STS'} = 1;
	$kw{'sequence tagged site'} = 1;
	$actions{STS}++;
    }
    elsif ($de =~ /\bGSS\b/ ) {
	$kw{'GSS'} = 1;
	$kw{'genome survey sequence'} = 1;
	$actions{GSS}++;
    }
}

#=============================================================================
#                           WRITE KW LINE
#=============================================================================
sub make_kw {
    $kwl = 'KW  ';
    $i   = 0;

    foreach $entry ( sort keys %kw ) {
        unless ( $entry eq "hypothetical protein" ) {
            $i++;
            $entry =~ s/putative\s//i;
            if ( $i > 1 ) {
                $kwl .= ';';
            }
            $kwl = &add_to( "KW", $kwl, $entry );
        }
    }
    $kwl .= ".\n";
    if ( $crude and $i ) {
      SEARCH2: foreach $i ( 0 .. @newfile - 1 ) {
            if ( $newfile[$i] =~ /^KW\s+\.\s+$/ ) {
                $newfile[$i] = "$kwl";
                $actions{kw_added} = 1;
                last SEARCH2;
            }
            elsif ( $newfile[$i] =~ /^KW\s+(Third Party Annotation; TPA)(\.$)/ ) {
                my @kwl = split ( /KW  /, $kwl );
                $newfile[$i]       = "KW   $1;$kwl[1]";
                $newfile[$i]       = check_length( $newfile[$i] );
                $actions{kw_added} = 1;
                last SEARCH2;
            }
        }
    }
}

#============================================================================
# split KW if it's more than 80
#============================================================================
sub check_length {
    my $kw_line = shift;
    my ( @lines, $words );
    my $second_line    = "\nKW   ";
    my $first_line_end = 0;
    my $line_length    = 0;
    my $first_line     = "";

    if ( length($kw_line) > 80 ) {
        @lines = split ( /\s/, $kw_line );
        foreach $words (@lines) {
            $line_length = length($first_line) + length($words);
            if ( $line_length < 80 and $first_line_end == 0 ) {
                $first_line .= "$words ";
            }
            else {
                $second_line .= "$words ";
                $first_line_end = 1;
            }
        }
        my $new_kw = $first_line . $second_line;
        return "$new_kw\n";
    }
    else{
	return $kw_line;
    }
}

#=============================================================================
#                           SCAN DIR FOR COMMENT FILES & DISPLAY
#=============================================================================
sub show_comments {
    print "--------------------------------------------------------\n";
    unless (@comments) {
        return;
    }
    print "                    Submittor comments\n";
    print "--------------------------------------------------------\n";

    foreach $file (@comments) {
        print "$file\n";
        open( IN, "< $file" ) or die ("Can't open <$file>: $!\n");
        while (<IN>) {
            if (/\S/) {
                print;
            }
        }
        close(IN);
        print "\n--------------------------------------------------------\n";
    }
}

#=============================================================================
#                           DISPLAY ACTIONS TAKEN
#=============================================================================
sub show_actions {

    #	print "\nWARNING: Done :\t";
    #	print "".($actions{de_added}  ? 'DE ':'')
    #		.($actions{de_added}  && $actions{kw_added}?'and ':'')
    #		.($actions{kw_added}  ? 'KW ':'')
    #		.(!$actions{de_added}  && !$actions{kw_added}?'neither DE nor KW ':'');
    #	print "inserted in file\n";
    #	print "".($webin?               "WARNING: WebIn header/footer taken out\n":'');
    #	print "".($actions{hold_date} ? "WARNING: Hold_Date(**$actions{hold_date} **) left in!\n":'');
    #	print "".($actions{ft_sorted} ? "WARNING: FT sorted\n":'');
    print ""
      . ( $actions{gene_case}
          ? "NB: gene name downcased (" . $actions{gene_case} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{gene_case_u}
          ? "NB: gene name uppercased (" . $actions{gene_case_u} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{isNNN}
          ? "ALERT: suspicious NNN stretches ****** (" . $actions{isNNN} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{RNA_gene}
          ? "ALERT: Mol assumed genomic RNA as _gene_ in DE\n"
          : ''
      );
    print ""
      . ( $actions{genomic_RNA_2_or_more_CDS}
          ? "ALERT: Genomic RNA as more than 1 CDS\n"
          : ''
      );
    print ""
      . ( $actions{rRNA_RnaToDna}
          ? "ALERT: DE line constructed as for DNA (because rRNA)\n"
          : ''
      );
    print ""
      . ( $actions{ITS_RnaToDna}
          ? "ALERT: DE line constructed as for DNA (because ITS)\n"
          : ''
      );
    print ""
      . ( $actions{prod_case}
          ? "NB: product name downcased (" . $actions{prod_case} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{extra_gene}
          ? "NB: 'gene' removed from gene name (" . $actions{extra_gene} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{gene_prefix}
          ? "WARNING: Genus/species prefix taken out of gene name (" . $actions{gene_prefix} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{xen_warning}
          ? "ALERT: Suspicious gene name for Xenopus (" . $actions{xen_warning} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{prod_prefix}
          ? "WARNING: Genus/species prefix taken out of product name (" . $actions{prod_prefix} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{prot_added}
          ? "NB: 'protein' added to product name (" . $actions{prot_added} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{genprod_added}
          ? "NB: product name ('Gene protein') added to CDS (" . $actions{genprod_added} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{orf_note}
          ? "NB: ORF put in /note (" . $actions{orf_note} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{orf_added}
          ? "NB: ORF added to empty CDS (" . $actions{orf_added} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{prod_orf}
          ? "NB: ORF /product set to 'hypothetical protein' (" . $actions{prod_orf} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{partial_gene}
          ? "NB: 'partial' taken out of gene name (" . $actions{partial_gene} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{partial_prod}
          ? "NB: 'partial' taken out of product name (" . $actions{partial_prod} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{codon_st}
          ? "NB: useless /codon_start taken out (" . $actions{codon_st} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{codon_st_warn}
          ? "ALERT: codon_start>1 used with 5' complete CDS (" . $actions{codon_st_warn} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{unpub}
          ? "NB: journal citation changed to 'Unpublished' (" . $actions{unpub} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{rRNA_gene}
          ? "NB: rRNA gene/product corrected (" . $actions{rRNA_gene} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{rRNA_key}
          ? "NB: rRNA feature substitution (" . $actions{rRNA_key} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{tRNA_key}
          ? "NB: tRNA feature substitution (" . $actions{tRNA_key} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{rRNA_guessed}
          ? "NB: rRNA info guessed from DE line (" . $actions{rRNA_guessed} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{ITS_fixed}
          ? "NB: ITS feature fixed (" . $actions{ITS_fixed} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{bad_title}
          ? "NB: 'Unpublished' journal title deleted (" . $actions{bad_title} . "x)\n"
          : ''
      );
    print ""
      . ( $actions{featureskip}
          ? "NB: Feature(s) skipped because duplicate\n"
          : ''
      );
    print ""
      . ( $actions{'complete genome'}
          ? "NB: complete genome added to KW because of DE\n"
          : ''
      );
    print ""
      . ( $actions{'circular'}
          ? "NB: complete genome added to KW because of circular topology\n"
          : ''
      );
    print ""
      . ( $actions{'complete viral segment'}
          ? "NB: complete viral segment added to KW because of DE\n"
          : ''
      );
    print ""
      . ( $actions{EST}
          ? "NB: method division 'EST; expressed sequence tag' taken from DE\n"
          : ''
      );
    print ""
      . ( $actions{STS}
          ? "NB: method division 'STS; sequence tagged site' taken from DE\n"
          : ''
      );
    print ""
      . ( $actions{GSS}
          ? "NB: method division 'GSS; genome survey sequence' taken from DE\n"
          : ''
      );

    #	print "".($actions{smart_sub}? "WARNING: Automatic DE = smart submitter DE!\n":'');
    print ""
      . ( $actions{gene_not_listed}
          ? "ALERT: human genes not on the list - $genes_not_found\n"
          : ''
      );
    print ""
      . ( $actions{prod_mismatch}
          ? "ALERT: human gene/product mismatch \n$mismatched_products"
          : ''
      );
    print ""
      . ( $actions{synonyms}
          ? "ALERT: human gene/product includes synonyms \n$synonyms_used"
          : ''
      );
    print ""
      . ( $actions{tRNA_nomenclature}
          ? "ALERT: non-standard tRNA nomenclature has been used\n - please correct:$gene\n"
          : ''
      );

}
__END__
