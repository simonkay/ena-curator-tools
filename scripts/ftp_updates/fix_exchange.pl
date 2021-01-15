#!/ebi/production/seqdb/embl/tools/bin/perl

#===============================================================================
# (C) EBI 1998 Nicole Redaschi
#
# Fixes known errors in NCBI daily update files.
#
#  HISTORY
#  =======
#  Nicole Redaschi  00-000-1998 Created
#  Nadeem Faruque   01-JUL-2003 Added lines to count usage of correction
#                               Added new 'In press' correction
#  Nadeem Faruque   12-OCT-2005 Added temporary fixes for collab 2005 changes
#  Nadeem Faruque   12-DEC-2005 New quualifiers need better formatted data (eg lat_lon)
#  Blaise Alako     05-Feb-2015 Added list of journal title correction
#  Blaise Alako     05-Feb-2015 /Collection_date qualifier line formatting.
#===============================================================================

use strict;
use warnings;

#---------------------------------------------------
# query for input
#-------------------------------------------------------------------------------

my ( $infile, $outfile ) = @ARGV;

unless ( defined($outfile) ) {
    die( "USAGE:\n  $0 <infile> <outfile>\n" . "Fixes common error in <infile> and writes the corrected file to <outfile>\n\n" );
}

my %errorCounts;
my %badLatLon;

my $FIX_LOG = '/ebi/production/seqdb/embl/data/collab_exchange/logs/fixlog';
my $EC_LIST = '/ebi/production/seqdb/embl/tools/curators/scripts/collab/ec_lists/ec_list';

open( IN,  $infile )     || die "cannot open file $infile: $!";
open( OUT, ">$outfile" ) || die "cannot open file $outfile: $!";
open( LOG, ">$FIX_LOG" ) || die "cannot open file $FIX_LOG: $!";
print LOG "$infile.tmp\n";
my $correctionsTally = "/ebi/production/seqdb/embl/data/collab_exchange/logs/corrections.count";

if ( -e $correctionsTally ) {
    open( CORRECTIONS, "$correctionsTally" )
      || die "cannot open file $correctionsTally: $!";
    while (<CORRECTIONS>) {
        chomp;
        if (/ = /) {
            my @tally = split / = /;
            $errorCounts{"$tally[0]"} = scalar( $tally[1] );
        }
    }
    close(CORRECTIONS);
}

my %oldErrorCounts = %errorCounts;


sub update_out_of_date_ec_numbers($) {

    my (%ec_data, $ec_num, $ec_update, $line);

    my $check_ec_num = shift;

    open(EC_DATA, "<$EC_LIST");
    while ($line = <EC_DATA>) {
	($ec_num, $ec_update) = split(" ", $line);
	$ec_data{$ec_num} = $ec_update;
    }
    close(EC_DATA);

         
    foreach $ec_num (keys %ec_data) {
 
	if ($ec_num eq $check_ec_num) {
	    # return replacement ec number
	    return $ec_data{$ec_num}
	}
    }

    # no replacement ec number found
    return(0);
}


sub addToTally($) {
    my $correction = shift;
    if ( exists( $errorCounts{"$correction"} ) ) {
        $errorCounts{"$correction"}++;
    }
    else {
        $errorCounts{"$correction"} = 1;
    }
}

my $line;
while ($line = <IN>) {

    # get rid of the headers in error files
    next if ($line =~ m|^ERROR|);

    # in case of unexpected ordering - any routine that discards lines (and hence $line ends up being replaced by a latter one) should go at top
#    if (/^DBLINK/) { 
#        addToTally("DBLINK:stripped");
#	while (<IN>) { # strip any other lines in this block
#	    (/^            /) || last;
#	}	
#    }
    if ($line =~ s/^DEFINITION  TPA_((inf)|(exp)|(reasm)):/DEFINITION  TPA:/) {
        addToTally("GKEYWORDS:tpa_definitionLine");
    }

    if ($line =~ s|^KEYWORDS    GSS \(genome survey sequence\)([.;])|KEYWORDS    GSS; genome survey sequence$1|) {
        addToTally("GKEYWORDS:gss");
    }
    if ($line =~ s/^KEYWORDS    Third Party Annotation((; TPA:experimental\.)|(; TPA:inferential\.)|(\.))/KEYWORDS    Third Party Annotation; TPA$1/) {
        addToTally("GKEYWORDS:tpa");
    }

    if ($line =~ m|^  AUTHORS   |) {

        # AUTHORS: move URL to title
        if ($line =~ s|^(  AUTHORS   )\.$|$1|) {
            addToTally("AUTHORS:JustADot");
        }

        # AUTHORS: move URL to title
        elsif ($line =~ s|^  AUTHORS   NCI-CGAP http://www\.ncbi\.nlm\.nih\.gov/ncicgap\.|  AUTHORS   NCI-CGAP\.|) {
            addToTally("AUTHORS:NCI-CGAP");
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            $line = <IN>;
            $line =~ s|^            Tumor Gene Index|            Tumor Gene Index http://www\.ncbi\.nlm\.nih\.gov/ncicgap|;
        }

        # AUTHORS: move GRASP to consortium
        elsif ($line =~ s|^  AUTHORS   GRASP Consortium, Davidson,W.S., Koop,B.F. and|  AUTHORS   Davidson,W.S. and  Koop,B.F.\.|) {
            addToTally("AUTHORS:GRASP");
            print OUT $line;
            print OUT "  CONSRTM   GRASP Consortium\n";
            $line = <IN>;
            $line =~ s|            http://web.uvic.ca/cbr/grasp\.|  REMARK    http://web.uvic.ca/cbr/grasp|;
        }

        # AUTHORS: move The Petunia Platform to Consortium
        elsif ($line =~ s|^  AUTHORS   The Petunia Platform|  CONSRTM   The Petunia Platform|) {
            addToTally("AUTHORS:PetuniaPlatform");

            # leave url in the consortium name
        }

        # AUTHORS: move URL to title
        elsif ($line =~ s|^  AUTHORS   NCI/NINDS-CGAP http://www\.ncbi\.nlm\.nih\.gov/ncicgap\.|  AUTHORS   NCI/NINDS-CGAP\.|) {
            addToTally("AUTHORS:NCI/NINDS-CGAP");
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            $line = <IN>;
            $line =~ s|            \(CGAP/BTGAP\), Tumor Gene Index|            \(CGAP/BTGAP\), Tumor Gene Index http://www\.ncbi\.nlm\.nih\.gov/ncicgap|;
        }

        # AUTHORS: move URL to title
        elsif ($line =~ s|^  AUTHORS   NCI/NIDR-CGAP http://www\.ncbi\.nlm\.nih\.gov/ncicgap\.|  AUTHORS   NCI/NIDR-CGAP\.|) {
            addToTally("AUTHORS:NCI/NIDR-CGAP");
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            $line = <IN>;
            print OUT "            http://www\.ncbi\.nlm\.nih\.gov/ncicgap\n";
        }

        # AUTHORS: move URL to title
        elsif ($line =~ s|^  AUTHORS   NIH-MGC http://mgc\.nci\.nih\.gov/\.|  AUTHORS   NCI-MGC\.|) {
            addToTally("AUTHOR:NIH-MGC.1");
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            $line = <IN>;
            print OUT "            http://mgc\.nci\.nih\.gov/\n";
        }

        # AUTHORS: move URL to title
        elsif ($line =~ s|^  AUTHORS   NIH-MGC http://www\.ncbi\.nlm\.nih\.gov/MGC/\.|  AUTHORS   NIH-MGC\.|) {
            addToTally("AUTHORS:NIH-MGC.2");
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            $line = <IN>;
            print OUT "            http://www\.ncbi\.nlm\.nih\.gov/MGC/\n";
        }

        # AUTHORS: move URL to title
        elsif ($line =~ s|^  AUTHORS   NIH-XCG http://image\.llnl\.gov/image/html/xenopuslib_info\.shtml\.|  AUTHORS   NIH-XCG\.|) {
            addToTally("AUTHORS:NIH-XCG");
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            print OUT "            http://image\.llnl\.gov/image/html/xenopuslib_info\.shtml\n";
            $line = <IN>;
        }

        # AUTHORS: move URL to title
        elsif ($line =~ s|^  AUTHORS   HCGP http://www\.ludwig\.org\.br/ORESTES\.|  AUTHORS   HCGP\.|) {
            addToTally("AUTHORS:ludwig");
            print OUT $line;
            $line = <IN>;
            print OUT $line;
            $line = <IN>;
            print OUT "            http://www\.ludwig\.org\.br/ORESTES\n";
        }

        # AUTHORS: shorten 'surname'
        elsif ($line =~ s|^  AUTHORS   The Anopheles Genome Sequencing Consortium\.|  AUTHORS   Anopheles Genome Sequencing Consortium\.|) {
            addToTally("AUTHORS:Anopheles");
        }
        elsif ($line =~ s|^(  AUTHORS   )(DOE Joint Genome Institute, Stanford Human Genome Center and Los)$|$1DOE Joint Genome Institute.\n  REMARK    $2|) {
            addToTally("AUTHORS:DOE Joint Genome Institute");
        }
        elsif ($line =~ s|^(  AUTHORS   )(Stanford Human Genome Center and Los Alamos National Laboratory\.)$|$1DOE Joint Genome Institute.\n  REMARK    $2|) {
            addToTally("AUTHORS:DOE Joint Genome Institute2");
        }

        # Try small non-exclusive authorname fixes
        else {

            # AUTHORS: Bovee Sr., -> Bovee Sr.,
            if ($line =~ s/(\sSr)\.,/$1,/g) {
                addToTally("AUTHORS:Sr.1");
            }

            # AUTHORS: Bovee Jr., -> Bovee Jr.,
            if ($line =~ s/(\sJr)\.,/$1,/g) {
                addToTally("AUTHORS:Jr.1");
            }

            # AUTHORS: St.Clair, / St. Clair, -> StClair,
            if ($line =~ s/ (St\. *)([^,]*,)/ St$2/g) {
                addToTally("AUTHORS:St.1");
            }
            print OUT $line;
            while ($line = <IN>) {    #should do...while to be neater
                last
                  if ($line =~ /^  TITLE     /);    # this line is printed at the very end of the script!
                                         # AUTHORS: Bovee Sr., -> Bovee Sr.,
                if ($line =~ s/(\sSr)\.,/$1,/g) {
                    addToTally("AUTHORS:Sr.1");
                }

                # AUTHORS: Bovee Jr., -> Bovee Jr.,
                if ($line =~ s/(\sJr)\.,/$1,/g) {
                    addToTally("AUTHORS:Jr.1");
                }

                # AUTHORS: St.Clair, / St. Clair, -> StClair,
                if ($line =~ s/ (St\. *)([^,]*,)/ St$2/g) {
                    addToTally("AUTHORS:St.1");
                }

                print OUT $line;
            }
        }
    }

    # JOURNAL:
    elsif ($line =~ /^  JOURNAL   /) {

        if ($line =~ s/^  JOURNAL   PLoS Biol\. 5 \(3\), e77/  JOURNAL   (er) PLoS Biol. 5 (3), e77/){
            addToTally("JOURNAL:VenterSorcererII");
	}

        if ($line =~ s/^  JOURNAL   J\. Struct\. Func\. Genomics 2 pre, L72-L86 \(2001\)/  JOURNAL   J\. Struct\. Funct\. Genomics 2 (1), 23-28 \(2002\)/) {
            addToTally("JOURNAL:RIKEN2002");
        }

        # fix Patent office errors - unsure where/why this 'fix' arose
        #        if ( s/^(  JOURNAL   )(Patent: )/$1Unpublished.\n            $2/ ) {
        #            addToTally( "JOURNAL:Patent" );}

        # we cannot handle supplements, so we pretend it's the issue by
        # surrounding it with ()
        if ($line =~ s/^(  JOURNAL   .* )(Suppl [^,]*), /$1($2), /) {
            addToTally("JOURNAL:Supplement");
        }

        # eg Cold Spring Harb. Symp. Quant. Biol. 45 Pt 1
        # -> Cold Spring Harb. Symp. Quant. Biol. 45 (Pt 1)
        if ($line =~ s/  JOURNAL   Cold Spring Harb. Symp. Quant. Biol. 45 Pt 1,/  JOURNAL   Cold Spring Harb. Symp. Quant. Biol. 45 (Pt 1),/) {
            addToTally("JOURNAL:ColdSprintHarbour45Pt1");
        }

        # confusing array of these - should be rationalised
        # JOURNAL: "Published Only in DataBase(YYYY)" -> "Unpublished (YYYY)"
        if ($line =~ /^  JOURNAL   Published Only in Database(\(\d{4}\))/) {
            $line = "  JOURNAL   Unpublished $1\n";
            print LOG "NEW In press line used in line-$line";
            addToTally("PublishedOnlyinDatabase1");
        }    #  New line for In press entries

        #START Adding new journal formating coorection ...
	if ($line =~ s/(Genome Announc \d \(\d\)) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:GenomeAnnounc");
	}
	if ($line =~ s/(AUSTRALASIAN PLANT PATHOLOGY CONFERENCE\, AUCKLAND\, NEW ZEALAND\; New Zealand) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:AustralasianPlantPathology");
	}
	if ($line =~ s/(4TH INTERNATIONAL CONFERENCE OF BOTANY AND MICROBIOLOGICAL SCIENCES\;) (\(\d+\))( In press)/$1 0-0 $2$3/){
		addToTally("JOURNAL:4THINTERNATIONALECONFERENCEOFBOTANY");
	}
	if ($line =~ s/(APS-CPS JOINT MEETING\;) (\(\d+\))/$1 0-0 $2/){
		addToTally("JOURNAL:APS-CPS-JOINT-MEETING");
	}
	if ($line =~ s/(Appl Plant Sci \d \(\d\)) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:Appl-Plant-Science");
	}
	if ($line =~ s/(Emerging Infect\. Dis\. \d+ \(\d\)) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:Emerging-Infectious-Disease");
	}
	if ($line =~ s/(Euro Surveill\. \d+ \(\d+\)) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:Euro-Surveillance");
	}
	if ($line =~ s/(Genome Biol\.) (\(\d+\))/$1\, 0-0 $2/) {
		addToTally("JOURNAL:Genome-Biology");
	}
	if ($line =~ s/(MBio \d \(\d\)) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:Molecular-Biology");
	}
	if ($line =~ s/(Proc\. Biol\. Sci\. \d+ \(\d+\)) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:Proceding-Biology");
	}
	if ($line =~ s/(Published Only in Database) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:Published-Only-In-Database");
	}
	if ($line =~ s/(Rokni\,M\.B\. \(Ed\.\)\; SCHISTOSOMIASIS\; InTech\, Rijeka\, Croatia) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:Rokni-Schistosomiasis");
	}
	if ($line =~ s/(Sci\. Rep\. \d+) (\(\d+\))/$1\, 0-0 $2/) {
		addToTally("JOURNAL:Science-Rep");
	}
	if ($line =~ s/(G3 \(Bethesda\)) (\(\d+\)) (In press)/$1\, 0-0 $2 $3/){
		addToTally("JOURNAL:G3-Bethesda");
	}
	if ($line =~ s/(PLoS Biol\. \d \(\d\)) (\(\d+\))/$1\, 0-0 $2/){
		addToTally("JOURNAL:Ploas-Biology");
	}
	#---END added JOURNAL CORRECTIONS 
        # remove "In press"
        elsif ($line =~ s/^(  JOURNAL   [\w\. ]+),? +(\d+)[, ]+(\(\d{4}\)) +[Ii][Nn] [Pp][Rr][Ee][Ss]{2}/$1 $2, 0-0 $3/) {
            addToTally("JOURNAL:Inpress.3");
        }
        elsif ($line =~ s/^(  JOURNAL   [\w\. ]+),? +(\(\d{4}\)) +[Ii][Nn] [Pp][Rr][Ee][Ss]{2}/$1 0, 0-0 $2/) {
            addToTally("PublishedOnlyinDatabase2");
        }
        elsif ($line =~ s/^  JOURNAL   Published Only in DataBase/  JOURNAL   Unpublished./) {
            addToTally("PublishedOnlyinDatabase3");
        }

        # if no volume number given
        elsif ($line =~ s/^(  JOURNAL   [\w\. ]+),? +(\(\d{4}\)) +[Ii][Nn] [Pp][Rr][Ee][Ss]{2}/$1 0, 0-0 $2/) {
            addToTally("JOURNAL:Inpress.1");
        }
        elsif ($line =~ /^  JOURNAL   [\w\. ]+ \(\d+\) \(\d{4}\) [Ii][Nn] [Pp][Rr][Ee][Ss]{2}/) {
            $line =~ s/\) (\(\d+\)) [Ii][Nn] [Pp][Rr][Ee][Ss]{2}/\), 0-0 $1/;
            addToTally("JOURNAL:Inpress.2");
        }
        elsif ($line =~ /^(  JOURNAL   .+)([Ii][Nn] [Pp][Rr][Ee][Ss]{2})\s*$/) {
	    my $journal_txt = $1;
	    my $in_press = $2;

            $line =~ s/$journal_txt$in_press/$journal_txt/;
            addToTally("JOURNAL:Inpress.4");
        }

        # fix doi lines with 'electronic resource' tag
	#if (s/^  JOURNAL   ([^,]+), (doi:\d+[^(]+)(\(\d\d\d\d\))/  JOURNAL   (er) $1 0 (0), 0-0 $3/) {
	if ($line =~ /^  JOURNAL   ([^,]+), (doi:\d+[^(]+)(\(\d{4}\))/) {
	    my $journal_title = $1;
	    my $published_year = $3;

	    if ($journal_title =~ /(\d{4})\s*$/) {
		my $journal_year = "(".$1.")";

		if ($journal_year eq $published_year) {
		    $journal_title =~ s/\d{4}\s*$//;
		}
	    }

	    $line =~ s/^  JOURNAL   ([^,]+), doi:\d+[^(]+\(\d{4}\)/  JOURNAL  $journal_title (0), 0-0 $published_year/;

            addToTally("JOURNAL:doi.1");
       }
    }

    # temporary: replace mutation & allele by variation
    elsif ($line =~ s/^     (mutation)|(allele  )        /     variation       /) {
        addToTally("FT:mutantAllele2Variation");
    }

    #QUALIFIER fixes trying to rearrange them to be more ordered
    elsif ($line =~ /^ {21}/) {

        # QUALIFIER:/replace
        if ($line =~ s/^( {21}\/replace=)"-"/$1""/) {
            addToTally("Q.replace.ValueIsDash");
        }

        # QUALIFIER:/collection_date
        elsif ($line =~ /^ {21}\/collection_date=\"([^\"]+)\"/) {
            my $collectionDate = $1;
            if ( $collectionDate =~ /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/ ) {
                $collectionDate ="$1-$2-$3";                ; #sprintf( "%02s-%s-%s", $2, ( "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" )[ scalar($1) ], $3 );
                addToTally("Q.collection_date.Formatting.US");
            }

            # fix Collection dates without hyphens
            elsif ( $collectionDate =~ s/ /-/g ) {
                addToTally("Q.collection_date.Formatting.spaces");
            }
            $line = "                     /collection_date=\"$collectionDate\"\n";
        }
        elsif ($line =~ s/^( {21}\/collection_date=\d-)/$1/) {
            addToTally("Q.collection_date.Formatting.padding");
        }

        # QUALIFIER:/country
        elsif ($line =~ /^ {21}\/country=/) {
            if ($line =~ /^ {21}\/country=\"US:\'Memphis, TN\'\"/) {
                $line =~ s/US:\'Memphis, TN\'/USA:Memphis, TN/;
                addToTally("Q.country.MemphisProblems");
            }
            elsif ($line =~ s/^( {21}\/country=\"US):/$1A:/) {
                addToTally("Q.country.US->USA");
            }
        }

        # QUALIFIER:/lat_lon
        elsif ($line =~ /^ {21}\/lat_lon=\"(.*)\"/) {    # NB won't cope with wrapped lat_lon values
            my $lat_lon = $1;
            if ( $lat_lon =~ s/O\./0./g ) {
                addToTally("Q.lat_lon:O.instead.of.0");
            }

            # Fix comma seperator
            if ( $lat_lon =~ s/ *[;,] */ /g ) {
                addToTally("Q.lat_lon:comma.in.seperator");
            }

            # Fix lat and long in value
            if ( $lat_lon =~ s/( *lat(: )?)|( *latitude(: )?)|( *long(: )?)|( *longitude(: )?)//g ) {
                addToTally("Q.lat_lon:lat.long.in.valuecomma.in.seperator");
            }

	    # Fix format "S 18.94 E 48.41"
            if ( $lat_lon =~ /^([NSEW]) ?([0-9\.]+) ([NSEW]) ?([0-9\.]+)$/ ) {
                $lat_lon = "$2 $1 $4 $3";
                addToTally("Q.NESW.before.numbers");
            }

            #       Fix first, people doing Long-lat
            #                    $1        $2          $3       $4
            if ( $lat_lon =~ /^([0-9\.]+) ?([EW]) ([0-9\.]+) ?([NS])$/ ) {
                $lat_lon = "$3 $4 $1 $2";
                addToTally("Q.lat_lon:lon_lat");
            }

            #       Fix people using -'ve instead of W or S
            #                    $1     $2          $3     $4
            if ( $lat_lon =~ /^([-+]?)([0-9\.]+) ([-+]?)([0-9\.]+)$/ ) {
                my $lat = "N";
                if ( $1 eq "-" ) {
                    $lat = "S";
                }
                my $lon = "E";
                if ( $3 eq "-" ) {
                    $lon = "W";
                }
                $lat_lon = sprintf "%.2f %s %.2f %s", scalar($2), $lat, scalar($4), $lon;
                addToTally("Q.lat_lon:-or+");
            }

            #       Fix people using too many decimal places and/or illegal lat_lon separator
            #                       $1               $2     $3                $4      
            elsif ( $lat_lon =~ /^([0-9]+\.[0-9]+) *([NS]) ([0-9]+\.[0-9]+) *([EW])$/ ) {
                $lat_lon = sprintf "%.2f %s %.2f %s", scalar($1), $2, scalar($3), $4;
                addToTally("Q.lat_lon:precision");
            }

            #       Fix people using minutes (inc minutes in decimal fractions)
            #                       $1        $2       $3            $4          $5        $6       $7            $8
            elsif ( $lat_lon =~ /^(\d+) *deg(rees)? *([0-9\.]+)\' *([NS])[; ,]+(\d+) *deg(rees)? *([0-9\.]+)\' *([EW])$/ ) {
                $lat_lon = sprintf "%.2f %s %.2f %s", scalar($1) + ( scalar($3) / 60 ), $4, scalar($5) + ( scalar($7) / 60 ), $8;
                addToTally("Q.lat_lon:minutes_1");
            }

            #       Fix people using minutes and seconds
            #                      $1        $2       $3        $4             $5         $6        $7       $8      $9              $10
            elsif ( $lat_lon =~ /^(\d+) *deg(rees)? *(\d+)\' *([0-9\.]+)\'\'? *([NS])[; ,]+(\d+) *deg(rees)? *(\d+)\' *([0-9\.]+)\'\'? *([EW])$/ ) {
                $lat_lon = sprintf "%.2f %s %.2f %s", scalar($1) + ( scalar($3) / 60 ) + ( scalar($4) / 3600 ), $5,
                  scalar($6) + ( scalar($8) / 60 ) + ( scalar($9) / 3600 ), $10;
                addToTally("Q.lat_lon:minutes_seconds");
            }

            #       Fix people using minutes and seconds separated by : or -
            #                      $1        $2        $3      $4          $5   $6    $7       $8
            elsif ( $lat_lon =~ /^(\d+)[:\-](\d+)[:\-](\d+) *([NS])[; ,]+(\d+)[:\-](\d+)[:\-](\d+) *([EW])$/ ) {
                $lat_lon = sprintf "%.2f %s %.2f %s", scalar($1) + ( scalar($2) / 60 ) + ( scalar($3) / 3600 ), $4,
                  scalar($5) + ( scalar($6) / 60 ) + ( scalar($7) / 3600 ), $8;
                addToTally("Q.lat_lon:minutes_seconds");
            }

            #       Fix people using minutes (inc minutes in decimal fractions) but marking degrees with '.'
            #                      $1     $2     $3     $4          $5     $6     $7     $8
            elsif ( $lat_lon =~ /^(\d+)\.(\d+)\.(\d+) *([NS])[; ,]+(\d+)\.(\d+)\.(\d+) *([EW])$/ ) {
                $lat_lon = sprintf "%.2f %s %.2f %s", scalar($1) + ( scalar("$2.$3") / 60 ), $4, scalar($5) + ( scalar("$6.$7") / 60 ), $8;
                addToTally("Q.lat_lon:minutes_2");
            }

            #       Fix people using decimal minutes with stupid formatting 1 (eg "N 37 45.403', 119 1.456' W")
            #                      $1     $2    $3                $4     $5          $6
            elsif ( $lat_lon =~ /^([NS]) (\d+) (\d+\.\d+)\'[; ,]+(\d+) (\d+\.\d+)\' ([EW])$/ ) {
                $lat_lon = sprintf "%.2f %s %.2f %s", scalar($2) + ( scalar($3) / 60 ), $1, scalar($4) + ( scalar($5) / 60 ), $6;
                addToTally("Q.lat_lon:minutes_3");
            }

            #       Fix people using minutes (inc minutes in decimal fractions)
            #                      $1        $2       $3            $4          $5        $6       $7            $8
            elsif ( $lat_lon =~ /^(\d+) *deg(rees)? *([0-9\.]+)min *([NS])[; ,]+(\d+) *deg(rees)? *([0-9\.]+)min *([EW])$/ ) {
                $lat_lon = sprintf "%.2f %s %.2f %s", scalar($1) + ( scalar($3) / 60 ), $4, scalar($5) + ( scalar($7) / 60 ), $8;
                addToTally("Q.lat_lon:minutes_4");
            }

            #       Fix people using minutes (and a final quote mark(!)
            #                      $1        $2       $3        $4         $5        $6       $7       $8
            elsif ( $lat_lon =~ /^(\d+) *deg(rees)? *(\d+)\' *([NS])[; ,]+(\d+) *deg(rees)? *(\d+)\' *([EW])\'?$/ ) {
                $lat_lon = sprintf "%.2f %s %.2f %s", scalar($1) + ( scalar($3) / 60 ), $4, scalar($5) + ( scalar($7) / 60 ), $8;
                addToTally("Q.lat_lon:minutes");
            }
            $line = "                     /lat_lon=\"" . $lat_lon . "\"\n";

            # remember any lat_lon values that are still badly formed
            if ( $lat_lon =~ /^(\d)+\.(\d+) [NS] (\d)+\.(\d+) [EW]$/ ) {
                if ( ( $1 >= 90 ) || ( $3 >= 180 ) ) {
                    $badLatLon{$lat_lon} = 1;
                }
            }
            else {
                $badLatLon{$lat_lon} = 1;
            }
        }
        elsif ($line =~ /^ {21}\/lat_lon=\"(.*)/) {    # NB grab any lat_lon that are wrapped and will escape the previous section
            $badLatLon{ $1 . "..." } = 1;
        }

        # QUALIFIER:/mol_type
        elsif ($line =~ s/^( {21}\/mol_type=\"pre\-)RNA\"/$1mRNA\"/) {
            addToTally("Q.mol_type.pre-RNA->pre-mRNA");
        }

        # QUALIFIER:/organelle - probably vestigial
        elsif ($line =~ /^ {21}\/organelle=/) {
            if ($line =~ s/^( {21}\/organelle=\".+:) /$1/) {
                addToTally("Organelle:blank");
            }
            elsif ($line =~ s/^( {21}\/)mitochondrion/$1organelle="mitochondrion"/) {
                addToTally("Organelle:mitochondrion");
            }
            elsif ($line =~ s/^( {21}\/)kinetoplast/$1organelle="mitochondrion:kinetoplast"/) {
                addToTally("Organelle:kinetoplast");
            }
            elsif ($line =~ s/^( {21}\/)chloroplast/$1organelle="plastid:chloroplast"/) {
                addToTally("Organelle:chloroplast");
            }
            elsif ($line =~ s/^( {21}\/)chromoplast/$1organelle="plastid:chromoplast"/) {
                addToTally("Organelle:chromoplast");
            }
            elsif ($line =~ s/^( {21}\/)cyanelle/$1organelle="plastid:cyanelle"/) {
                addToTally("Organelle:cyanelle");
            }
        }

        # QUALIFIER:/cons_splice: upcase values
        elsif ($line =~ /^ {21}\/cons_splice=/) {
            if ($line =~ s/no/NO/g) {
                addToTally("cons_splice:toupper");
            }
            if ($line =~ s/yes/YES/g) {
                addToTally("cons_splice:toupper");
            }
            if ($line =~ s/absent/ABSENT/g) {
                addToTally("cons_splice:toupper");
            }
        }

        # QUALIFIER: /plasmid, /transposon, /insertion_seq: blank
        elsif ($line =~ /^ {21}\/(plasmid|transposon|insertion_seq)=\"\"$/) {
            $line =~ s/\"\"/\"Unknown\"/;
            addToTally("emptyPlasmidTransposonOrInsertion_seq");
        }

        # QUALIFIER: /compare: quoted
        elsif ($line =~ /^ {21}\/compare=\"/) {
            $line =~ s/compare=\"([\w.]+)\"/compare=$1/;
            addToTally("QuotedCompareQualifier");
        }

        # QUALIFIER: /sex: "Both for embryonic"
        elsif ($line =~ /^ {21}\/sex=\"Both for embryonic/) {
            $line =~ s/sex=\"Both for embryonic/note=\"sex:Both for\n                     embryonic/;
            addToTally("BothForEmbryonic");
        }

        if ($line =~ /^ {21}\/EC_number=\"([^"]+)\"/) { #"

	    my $ec_number = $1;

            if ($line =~ s/^( {21}\/EC_number=\"[0-9]+\.[0-9]+)\.1-\.-\"/$1.-.-\"/) {
                addToTally("Q.EC_number.1-.- -> -.- ");
            }
            elsif ($line =~ s/^( {21}\/EC_number=\"[0-9]+\.[0-9]+\.[0-9]+\.)0+\"/$1-\"/) {
                addToTally("Q.EC_number.0 -> .- ");
            }
            elsif ($line =~ s/^( {21}\/EC_number=\"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\."/$1"/) {
                addToTally("Q.EC_number.EndsInanExtraDot");
            }
            elsif ($line =~ s/^( {21}\/EC_number=\"[0-9\-]+\.[0-9\-]+\.[0-9\-]+)\.?"/$1.-"/) {
                addToTally("Q.EC_number.WithOnly3Parts");
            }
            elsif ($line =~ s/^( {21}\/EC_number=\"[0-9\-]+\.[0-9\-]+)\.?"/$1.-.-"/) {
                addToTally("Q.EC_number.WithOnly2Parts");
            }

	    my $new_ec_number = 0;
	    $new_ec_number = update_out_of_date_ec_numbers($ec_number);
	    if ($new_ec_number) {
		$line =~ s/$ec_number/$new_ec_number/;
		addToTally("Q.EC_number.transferred");
	    }

        }

        # fix organism.
        elsif ($line =~ s/^( {21}\/organism=\")artificial sequence\"/$1synthetic construct\"/) {
            addToTally("artificial2synthetic");
        }
        elsif ($line =~ s/^( {21}\/organism=\")unclassified\"/$1unidentified\"/) {
            addToTally("unclassified2unidentified");
        }

        # /estimated_length="unknown":
        elsif ($line =~ s/\/estimated_length="unknown"/\/estimated_length=unknown/) {
            addToTally("estimatedLength:quoted");
        }

        # fix pos:complement -> pos:
        elsif ($line =~ s/pos:complement\(([^)]+)\)/pos:$1/) {
            addToTally("posComplement->pos");
        }

        # fix most 'nested qualifiers' ie normal lines in feature table with a / in column 22:
        elsif ($line =~ /^ {21}\/\w*[^=]"]/) {    # " needed for emacs colouring
            if ( $line =~ s/^( {21})(\/.{0,57})$/$1 $2/ ) {
                addToTally("pseudoNestedQualifier");
            }
        }

    }
    print OUT $line;
}

open( CORRECTIONS, ">$correctionsTally" )
  || die "cannot open file $correctionsTally for writing: $!";

foreach my $correctionType ( keys %errorCounts ) {
    if ( exists( $oldErrorCounts{"$correctionType"} ) ) {
        print LOG ":$correctionType = " . ( $errorCounts{"$correctionType"} - $oldErrorCounts{"$correctionType"} ) . "\n";
    }
    else {
        print print LOG ":$correctionType = " . $errorCounts{"$correctionType"} . "\n";
    }
    print CORRECTIONS "$correctionType = " . $errorCounts{"$correctionType"} . "\n";
}
print CORRECTIONS "  $infile.tmp was the last processed\n";
close(CORRECTIONS) || die "cannot close file $infile: $!";
system("sort -o $correctionsTally $correctionsTally");
close(IN)  || die "cannot close file $infile: $!";
close(OUT) || die "cannot close file $outfile: $!";
close(LOG) || die "cannot close file $FIX_LOG: $!";

my $BAD_LATLON = '/ebi/production/seqdb/embl/data/collab_exchange/logs/badLatLon.txt';
if ( scalar( keys %badLatLon ) > 0 ) {
    open( LATLON, ">>$BAD_LATLON" )
      || die "cannot open file $BAD_LATLON: $!";
    foreach my $lat_lon ( keys %badLatLon ) {
        print LATLON $lat_lon . "\n";
    }
    close(LATLON) || die "cannot close file $BAD_LATLON: $!";
}

#rename( "$infile",     "$infile.RAW" );
#rename( "$infile.tmp", $infile );

exit();
