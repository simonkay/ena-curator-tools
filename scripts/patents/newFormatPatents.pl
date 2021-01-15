#!/ebi/production/seqdb/embl/tools/bin/perl -w


use strict;
use DBI;
use dbi_utils;
use Data::Dumper;
use SeqDBUtils2;

use Document;
use Sequence;

@ARGV == 3 || die "\n USAGE: $0 <user>/<passwd>@<db> <patentfilename> <outfile>\n\n";
my $login = $ARGV[0];
my $fname = $ARGV[1];
my $outfile = $ARGV[2];
my $logfile = "patents.log";
my @report;


### --- login to Oracle ---------------------------------------------------------
my $dbh = dbi_ora_connect ( $login );
dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );

my $flag = '';


open ( IN, $fname )    || die ( "can't open $fname: $!\n" );
open ( OUT, ">$outfile" ) || die ( "can't open $outfile: $!\n" );
open ( LOG, ">>$logfile" ) || die ( "can't open $logfile: $!\n" );

## get sysdate
my ( $today ) = dbi_getvalue ( $dbh, 
          "SELECT to_char (sysdate, 'DD-MON-YYYY HH24:MI:SS') FROM dual" ); 

print LOG "\n\n\n***** $today ********************\n";
$login =~ /\@(\w+)/;
my $db = uc($1) || $ENV { "ORACLE_SID" };
print LOG "***** file: $fname\n***** database: $db\n\n";


## select controlled vocabulary 
my ( @cv_patentoffice ) = dbi_getcolumn ( $dbh, "SELECT code FROM cv_patentoffice" );
my ( @featurekey ) = dbi_getcolumn ( $dbh, "select fkey from cv_fkey order by fkey desc" );

## populate hash for checking three-letter code
my %abbrev_letter;

my @table =  dbi_gettable ($dbh, "select upper (abbrev), letter
                                        from cv_aminoacid
                                       where letter is not null");
    
foreach my $row (@table){

    my ($abbrev, $letter) = @$row;
    $abbrev_letter{$abbrev} = $letter;
}
    
### name objects for document and sequence part of the flatfiles
my $doc;
my $seq;
my $nof_entries;

# accs updated by this method aren't automatically 
# distributed so must be done manually
open(ACCS_TO_DISTRIBUTE, ">accs_to_distribute_$fname");

while ( <IN> ) {
    chomp ( my $line = $_ );
    $line =~ s/\r//;

    # exchange national chars
    $line = translate ( $line );
    
    if ( $line =~ /\/End of file\// ) {
	$flag = '';
    }
    elsif ( $line =~ /^\-\-\-NEW ENTRY/ ) {
    ## new document

	if ( (defined($doc)) && ($doc)) {
	    test_entry ( $dbh, \*LOG, $doc, $seq, $nof_entries, \@cv_patentoffice, \@featurekey );
	    print_entry ( $dbh, \*OUT, $doc, $seq );
	}

	## create new document object
	$doc = Document->new();

	$nof_entries = 0;
	$flag = '';
    }
    elsif ( $line =~ /^ID\s+[^_]+_(\d+);[^;]+;[^;]+; ([^;]+);/ ) {

	my $seq_num = $1;
	my $mol = $2;

	## new sequence
	if ( defined $seq && $nof_entries != 0 ) {
	    test_entry ( $dbh, \*LOG, $doc, $seq, $nof_entries, \@cv_patentoffice, \@featurekey );
	    print_entry ( $dbh, \*OUT, $doc, $seq );
	}

	### create new sequence object
	$seq = Sequence->new();

	$seq->seqno( $seq_num );

	if ( $mol =~ /protein/i ) {
	    $seq->ftype ( 'PRT' );  #RNA, DNA, PRT or XXX
	}
	else {
	    $seq->ftype ( $mol ); 
	}

	$nof_entries++;

	$flag = '';
    }
    elsif ( $line =~ /^\((i|I)\)\s*DOCUMENT NUMBER\s*:\s*(.*)$/ ) {
	if ( !defined $doc ) {
	    bail ( "file format corrupt ( possibly missing \"---NEW ENTRY----------------------------\" line )\n", $dbh );
	}
	$doc->docnumber( $2 );
    }
    elsif ( $line =~ /^\((ii|II)\)\s*DOCUMENT OFFICE\s*:\s*(.*)$/ ) {
	$doc->docoffice( $2 );
    }
    elsif ( $line =~ /^\((iii|III)\)\s*DOCUMENT TYPE\s*:\s*(.*)$/ ) {
	$doc->doctype( $2 );
    }
    elsif ( $line =~ /^\((iv|IV)\)\s*DOCUMENT DATE\s*:\s*(.*)$/ ) {
	$doc->docdate( $2 );
    }
    elsif ( $line =~ /^\((v|V)\)\s*APPLICATION NUMBER\s*:\s*(.*)$/ ) {
	$doc->appnumber ( $2 );
    }
    elsif ( $line =~ /^\((vi|VI)\)\s*APPLICATION OFFICE\s*:\s*(.*)$/ ) {
	$doc->appoffice( $2 );
    }
    elsif ( $line =~ /^\((vii|VII)\)\s*APPLICATION DATE\s*:\s*(.*)$/ ) {
	$doc->appdate( $2 );
    }
    ### priority block: there can be more thane one
    elsif ( $line =~ /^\((viii|VIII)\)\s*PRIORITY APPLICATION NUMBER\s*:\s*(.*)$/ ) {
	$doc->push_prioappnumber ( $2 );
    }
    elsif ( $line =~ /^\((ix|IX)\)\s*PRIORITY APPLICATION OFFICE\s*:\s*(.*)$/ ) {
	$doc->push_prioappoffice( $2 );
    }
    elsif ( $line =~ /^\((x|X)\)\s*PRIORITY APPLICATION DATE\s*:\s*(.*)$/ ) {
	$doc->push_prioappdate( $2 );
    }
    
    elsif ( $line =~ /^\((xi|XI)\)\s*APPLICANT NAME\s*:\s*(.*)$/ ) {
	$doc->appname ( $2 );
	$flag = 'APPNAME';
    }
    elsif ( $line =~ /^\((xii|XII)\)\s*INVENTOR NAME\s*:\s*(.*)$/ ) {
	my $name = $2;
	if ($name !~ /;/){
	    $name = $name . ";";
	}
	$doc->invname ( $name );
	$flag = 'INVNAME';
    }
    elsif ( $line =~ /^\((xiii|XIII)\)\s*TITLE\s*:\s*(.*)$/ ) {

	$doc->title ( $2 );
	$flag = 'TITLE';
    }
    elsif ( $line =~ /COMMENT\s*:\s*(.*)$/ ) {
	$doc->comment( "Other publication ".$1 );
    }
    elsif ( $line =~ /^OS\s+(.+)$/ ) {

	my $org = $1;

	if ( $org =~ /Artifici/i ) {

	    $seq->qualifiers( $seq->get_cur_feat(), '/organism="synthetic construct"' );
	}
	else {
	    if ( $org =~ /^([a-z])/ ) {
		my $ucFirstLetter = uc($1);
		$org =~ s/^[a-z]/$ucFirstLetter/;
	    }

	    $seq->qualifiers( $seq->get_cur_feat(), "/organism=\"$org\"" );
	}

    }
    elsif ( $line =~ /^FT\s+[Ss]ource\s+([^\s]+).*$/ ) {

	$seq->locations( $seq->get_cur_feat(), $1 );  
     	$flag = 'FEATURE';

    }
    elsif ( $line =~ /FT\s+\/mol_type=\"([^"]+)\"/ ) {

	# add moltype to sourcefeature "
	if ( $1 eq 'Unassigned DNA' ) {
	    $seq->qualifiers( $seq->get_cur_feat(), '/mol_type="unassigned DNA"' );
	}
	elsif ( $1 eq 'Unassigned RNA' ) {
	    $seq->qualifiers( $seq->get_cur_feat(), '/mol_type="unassigned RNA"' );      
	}
	elsif ( $1 eq 'Unassigned Protein' ) {
	    $seq->qualifiers( $seq->get_cur_feat(), '/mol_type="protein"' );      
	}

    }
    # get qualifiers (organism is already provided)
    elsif ( $line =~ /^FT\s+(\/[^"]+"[^\n]+"?)/ ) {
        #"
	my $qual = $1;

	if (( $qual !~ /^\/organism=/ ) && ( $qual !~ /^\/note=\"peptide\"/i )) {
	    $seq->qualifiers( $seq->get_cur_feat(), $qual );
	}

	$_ = $qual;
	my $count_dbl_quotes = tr/\"//;

	if ($count_dbl_quotes == 1) {
	    $flag = 'QUALIFIER';
	}

    }
    # get additional lines of wrapped qualifiers
    elsif ( $flag eq 'QUALIFIER' ) {

	if ( $line =~ /^FT\s+([^\n]+)/ ) {
	    $seq->qualifiers( $seq->get_cur_feat(), $1, 1 );
	}

	$_ = $line;
	my $count_dbl_quotes = tr/\"//;

	if ($count_dbl_quotes == 1) {
	    $flag = '';
	}

    }
    # get features other than source
    elsif ( $line =~ /^FT\s+([^\s]+)\s+([^\s]+)/ ) {

	$seq->incr_cur_feat();

	$seq->features( $seq->get_cur_feat(), $1 );
	$seq->locations( $seq->get_cur_feat(), $2 );  
    }
    elsif ( $line =~ /^SQ\s+SEQUENCE\s+(\d+)/i ) {

	$flag = 'SEQ';

	if ( !defined $seq ) {
	    bail( "sequence start undefined, cannot procced processing", $dbh );
	}

    }
    else {
 
	if ( $line =~ /^\<\d+\>/ ) {
	    print_log ( \*LOG, "WARNING: unknown line type embedded in feature: $line", $doc );
	}

	if ( $flag eq 'INVNAME' ) {
	    $line =~ s/\s{2,}//g;	
	    if ($line !~ /\;/){
		$line .= $line .";";
	    }
	    $doc->invname( $doc->invname().$line );
	}
	elsif ( $flag eq 'APPNAME' ) {
	    $line =~ s/\s\s+/ /g;
	    $doc->appname( $doc->appname(). " ".$line );

	}
	elsif ( $flag eq 'TITLE' ) {
		$doc->title( $doc->title(). $line );

	}
	elsif ( $flag eq 'SEQ' ) {

	    if ( $line =~ m|//| ) {
		$flag = '';
	    }
	    else {
		$seq->seq( $seq->seq().$line );
	    }

	}
	else {
	    print_log ( \*LOG, "illegal line: $line", $doc );
	}
    }
}


# last entry

if ( defined $doc ) {
    test_entry ( $dbh, \*LOG, $doc, $seq, $nof_entries, \@cv_patentoffice, \@featurekey );
    print_entry ( $dbh, \*OUT, $doc, $seq );
}


# if there is any entry to delete, print out
my $file_name  = "patents_to_delete";

if (@report){

    open (REPORT, ">$file_name") or die "cannot open file $file_name:$!";
    print REPORT "accession numbers to delete before loading patent data\n";
    foreach my $acc(@report){

	print REPORT "$acc\n";
        print LOG "WARNING: delete $acc before loading due to bioseqtype change\n";
    }
    print "\nWARNING: before loading the data into the database, please delete entries in\n".
          "         file $file_name via delete_entry.pl and report accnos to ncbi.\n";
    close (REPORT);
}

close (IN)  || bail ( "can't close $fname: $!", $dbh );
close (OUT) || bail ( "can't close $outfile: $!", $dbh );
close (LOG) || bail ( "can't close $logfile: $!", $dbh );   #( bail ??????? )

close(ACCS_TO_DISTRIBUTE);

### --- disconnect from Oracle --------------------------------------------------
$dbh->commit;
$dbh->disconnect;



### --- list of subs -----------------------------------------------------------

sub delete_quotes {
    # deletes quotes and leading and trailing blanks

    my ( $text ) = @_;

    $text =~ s/^\s*\"\s*//;
    $text =~ s/\s*\"\s*$//;  #"
    
    # don't delete single quotes as there might be cases like
    # <223> Description of Artificial Sequence: 2'
    # methyl-modified oligonucleotide

    return $text;
}

sub member_of {

    my ( $elem, @array ) = @_;
    my ( $i );

    for ( $i = 0; $i < @array; $i++ ) {
	last if ( $array[$i] eq $elem );
    }
    return 1   if ( $i < @array );
    return 0;
}


sub member_of_nocase {

    # ignore case, returns 'correct' writing from list
    my ( $elem, @array ) = @_;
    my ( $i );

    for ( $i = 0; $i < @array; $i++ ) {
	last if ( uc( $array[$i] ) eq uc( $elem ) );
    }
    if ( $i < @array ) {
	return $array[$i];
    }
    return 0;
}

sub calc_seqlen {
    # returns length of given sequence ( ignoring blanks )
    my ( $seq ) = @_;
    return ( $seq =~ tr/a-zA-Z// );
}


sub print_log {
    # prints (error)message to file including header

    my ( $FH, $text, $doc, $seq ) = @_;

    if ( !defined $doc ) {
	# should not happen....
	print $FH "---- $text\n";
    }
    else {
	print  $FH $doc->docoffice().$doc->docnumber();
	defined $seq ? printf $FH " seq %-4s ", $seq->seqno() : print $FH ' ' x 10;
	print  $FH "$text\n";
    }
}


sub display_sequence {
    my ( $FH, $sq ) = @_;
    my ( @seq ) = split (//,$sq);
    
    my $j = 0;
    my $len = length ($sq);

    for ( my $i = 0; $i < $len; $i++ ) {

	if ( $j == 70 ) {
	    print $FH "\n";
	    $j = 0;
	}
	elsif ( !(($j-4) % 11) && $j > 4 ) {
	    print $FH ' ';
	    $j++;
	}
	if ( $j == 0 ) {
	    print $FH ' ' x 5;
	    $j = 5;
	}
	if ( $seq[$i] ne ' ' ) {
	    print $FH $seq[$i];
	    $j++;
	}
    }
    print $FH "\n";
}

sub format_invname {

    my ( $ls ) = @_;
  
    my @names = split ( /;\s*/, $ls );
    my $names_new = '';

    foreach ( @names ) {

	#delete starting and trailing blanks
	s/^\s*//;
	s/\s*$//;

	if ( $_ ne '' ) {
	    my $fname;
	    my $sname;
	    
	    if ( /\s*,\s*/ ) {
		$fname = $'; #'
		$sname = $`;
		$fname =~ s/\,//;   # there might be more commas we ignore
	    }
	    else {
		( /^([\w-]+)\s*(.*)$/ );
		$fname = $2;
		$sname = $1;
	    }

	    # surname
	    unless ( $sname =~ m/[a-z]/ ) {
		# change case only if all upper
		
		my @x = split ( / +/, $sname );
		for ( my $i = 0, $sname = ''; $i < @x-1; $i++ ) {    # von, van den ....
		    $sname .= lc($x[$i])." ";
		}
		if ( $x[@x-1] =~ /^(\w+)([\-\'])(\w+)/ ) {
		    $sname .= ucfirst(lc($1)).$2.ucfirst(lc($3));
		}
		else {
		    $sname .= ucfirst(lc($x[@x-1]));
		}
	    }

	    # firstname
	    $fname =~ s/ +/ /;
	    $fname =~ s/\(.*\)//;
	    my @x = split ( /[ \-]/, $fname );

	    $fname = '';
	    $fname = uc(substr($x[0], 0, 1))."."    if ( $x[0] );
	    $fname .= uc(substr($x[1], 0, 1))."."   if ( $x[1] );
	    #     $fname .= uc(substr($x[2], 0, 1))."."   if ($x[2]); not sure if we need this QL

	    $names_new .= ', '      if ( $names_new ne '' );
	    $names_new .= $sname." ".$fname;
	}
    }
    $names_new .= ';';
    return $names_new;
}


sub format_title {
    my ( $title ) = @_;

    $title =~ s/^\s*//;
    $title =~ s/\s*$//;

    unless ( $title =~/[a-z]/ ) { # downcase only if all uppercase
	$title = lc( $title );
    }

    my ( @tt ) = split (/\.\s/,$title);
    foreach ( @tt ) {
	$_ = ucfirst($_);
    }
    $title = join ( ". ", @tt );
    $title =~ s/\s+/ /g;   # delete redundant blanks

    if ($title eq ""){
	$title = "\"No title supplied\"";
    }
    else {
	$title = '"'.$title.'"';
    }  

    return $title;
}

sub format_appname {
    my ( $appname ) = @_;
    $appname =~ s/^\s*//;
    $appname =~ s/\s*$//;
    $appname =~ s/\s+/ /g;    # delete redundant blanks
    $appname =~ s/\s*;/;/g;   # delete blanks before semicolons
    $appname .= '.'   if ( $appname !~ /\.$/ );   # add final '.'
    return $appname;
}

sub display_long_line {

    # line max 80 chars

    my ( $FH, $header, $line ) = @_;
    my $len = 80 - length( $header );

    for (;;) {
	print $FH $header;

	if (length ($line) <= $len) {
	    printf $FH "%s\n", $line;
	    return;
	}
	else {
	    my @xline = split (//, $line);
	    my $i;
	    for ($i = $len; ($i > 0) && ($xline[$i] ne ' '); $i--) {;}
	    if ($i == 0) {
#       /* no blanks in line */
		printf $FH "%s\n", substr ($line, 0, $len);
		$line = substr ($line, $len);
	    }
	    else {
		printf $FH "%s\n", substr ($line, 0, $i);
		$line = substr ($line, $i+1)
	    }
	}
    }
}


sub format_date {

    my ( $db, $date, $FH, $doc ) = @_;

    # strip ';', if there is one
    $date =~ s/\;$//;

    my $sql = "select decode ( ?,
                               6, 
                               to_char(to_date ('$date', 'RRMMDD'), 'DD-MON-YYYY'),
                               to_char(to_date ('$date', 'YYYYMMDD'), 'DD-MON-YYYY'))
                      from dual";

    my $mb = $db->prepare($sql);
    $mb->bind_param(1, length($date));

    $mb->execute || dbi_error($DBI::errstr);

    my ( @res ) = $mb->fetchrow_array;
    $mb->finish;

    my $qwe = $res[0];

    if ( !defined ( $qwe ) || $qwe eq '' || $qwe eq '-1' ) {
	print_log ( \*$FH, "illegal date $date", $doc );
#    return '<' x 11;
	return $date;
    }
    return $qwe;
}


sub test_entry {

    my ( $db, $FH, $doc, $seq, $nof, $cv_office_ref, $cv_key_ref ) = @_;

    my ( @cv_office ) = @{$cv_office_ref};
    my ( @cv_key ) = @{$cv_key_ref};

    ### --- document part ( test only once ) --------------------------------------
    if ( ! $doc->is_tested() ) {
      
	if ( !member_of ( $doc->docoffice(), @cv_office )) {
	    print_log ( \*$FH, "illegal document office: ".$doc->docoffice(), $doc );
	}
	if ( $doc->appoffice() ne '' &&
	     !member_of ( $doc->appoffice(), @cv_office )) {
	    print_log ( \*$FH, "illegal application office: ".$doc->appoffice(), $doc );
	}

	# test if prioapp.. lines are in sync
	if ( $doc->nof ('prioappnumber') != $doc->nof ('prioappoffice') ||
	     $doc->nof ('prioappnumber') != $doc->nof ('prioappdate') ) {
	    print_log ( \*$FH, "priority application lines are out of sync", $doc );
	}

	# test and reformat dates
	$doc->docdate ( format_date ( $db, $doc->docdate(), \*$FH, $doc ));
	$doc->appdate ( format_date ( $db, $doc->appdate(), \*$FH, $doc ));
	for ( my $i = 0; $i < $doc->nof ('prioappdate'); $i++ ) {
	    $doc->set_prioappdate ( $i, format_date ( $db, $doc->get_prioappdate($i), \*$FH, $doc ));
	}

	$doc->set_tested();
    }

    ### --- sequence part ---------------------------------------------------------

    if ( $nof != $seq->seqno() ) {
	print_log ( \*$FH, "strange sequence order, should be $nof",
		    $doc, $seq );
    }

    if ( $seq->ftype() ne 'RNA' && $seq->ftype() ne 'DNA' && $seq->ftype() ne 'PRT' ) {
	print_log ( \*$FH, "illegal feature type ".$seq->ftype(), $doc, $seq );
    }

    # calculate seqlen
    if ( calc_seqlen($seq->seq()) != $seq->seqlen() ) {
	print_log ( \*$FH, "calculated seqlen ( ".calc_seqlen($seq->seq()).
		    " ) and given seqlen ( ".$seq->seqlen()." ) vary", $doc, $seq );
	$seq->seqlen( calc_seqlen($seq->seq()) );
    }

    # set sourcefeature location
    #$seq->locations ( 0, "1..".$seq->seqlen() );

    # check features
    for ( my $i = 0; $i < $seq->nof('features'); $i++ ) {
	if ( defined $seq->features ($i) ) {
	    my ( $xfeat ) = $seq->features ($i);
	    # change '-' to '_', except for the first char
	    substr( $xfeat, 1, length ($xfeat) - 1) =~ s/\-/\_/;
      
	    my ( $xkey ) = member_of_nocase ( $xfeat, @cv_key );
	    if ( $xkey eq '0' ) {
		print_log ( \*$FH, "ignored illegal feature: $xfeat", $doc, $seq );
		$seq->features ( $i, '*' );
	    }
	    elsif ( !defined $seq->locations ($i) ) {
		print_log ( \*$FH, "location missing for feature $xkey, feature not printed",
			    $doc, $seq );
		$seq->features ( $i, '*' );
	    }
	    else {
		# reformat and check location
		my ( $xloc ) = $seq->locations ( $i );
		$xloc =~ s/\_/\./g;
		$xloc =~ s/[\.\.]{3,}/\.\./;  # substitute three or more dots by two
		$xloc = lc($xloc);
		
		if ( $xloc =~ /\-\d+/ || $xloc =~ /,/ ) {
		    # delete features with negative and comma separated locations
		    # ( no warning on Tamaras request )
		    $seq->features ( $i, '*' )
		    }
		elsif ( ( $xloc =~ /\(\)\.\.\(\)/ && $xfeat eq 'misc_feature' ) ||
			$xloc =~ /^0\.\.0$/ )  {
		    # do not print misc_feature with location ()..() ( jul-2004 )
		    # do not print features with location (0)..(0)   ( aug-2004 )
		    $seq->features ( $i, '*' );
		    # add qualifiers to source
		    $seq->qualifiers ( 0, $seq->qualifiers($i) );
		}
		else {
		    # feature is ok
		    $seq->locations ( $i, $xloc );  
		    $seq->features ( $i, $xkey );
		}
	    }
	}
    }

    # check organism

    if ( $seq->qualifiers(0) =~ /organism=\"([^\%]*)\"/ ) { #"
	# lookup in taxonomy
	my $org = $1;
	my $org_name = uc($1);
	$org_name =~ s/'/''/g;  #'

        #my ( @orgs ) = dbi_getcolumn ( $db,
	#	"select tax_id from ntx_synonym where upper_name_txt = '$org_name'" );

	my $sql = "select tax_id from ntx_synonym where upper_name_txt = ?";

	my $mb = $db->prepare($sql);
	$mb->bind_param(1, $org_name );
	$mb->execute || dbi_error($DBI::errstr);

	my @orgs = ();
	while (my @row = $mb->fetchrow_array) {
	    push(@orgs, $row[0]);
	}
	$mb->finish;
	

	if ( !@orgs ) {   
	    print_log ( \*$FH, "organism unclassified: $org", $doc, $seq );
	}
	elsif ( @orgs > 1 ) {
	    print_log ( \*$FH, "organism not unique: $org", $doc, $seq )
	}
    }
    else {
	# no organism given
	$seq->qualifiers ( 0, '/organism="unknown"' );
    }
}


sub get_accession {

    my ( $db, $doc, $seq ) = @_;

    ### get accession, if entry in database; else get next AX accession

    ### this statement returns the first accno, if there is more than one....
    ### should not happen....
    my $sql = "select d.primaryacc#, p.doctype
                from dbentry d, patent p, patent_bioseq pb
               where p.docoffice = ?
                 and p.docnum = ?
                 and p.pubid = pb.pubid
                 and pb.orderin = ?
                 and pb.seqid = d.bioseqid "; # and rownum < 2

    #my ( $accno ) = dbi_getvalue_no_error ( $db, $call );
    my $mb = $db->prepare($sql);
    $mb->bind_param(1, $doc->docoffice() );
    $mb->bind_param(2, $doc->docnumber() );
    $mb->bind_param(3, $seq->seqno() );

    $mb->execute || dbi_error($DBI::errstr);

    my ($accno, $doctype) = $mb->fetchrow_array;
    $mb->finish;

  

    # check if the bioseq.bioseqtype has changed for updates
    my $new_acc_flag = "N";

    if ($accno) {
   
	my $sql = "select decode (b.bioseqtype, 1, 'PRT','nucleotide')  
                   from bioseq b, dbentry db
                  where b.seqid = db.bioseqid
                    and db.primaryacc# = ?";

	my $mb = $db->prepare($sql);
	$mb->bind_param(1, $accno);
	$mb->execute || dbi_error($DBI::errstr);

	my $bioseqtype = $mb->fetchrow_array();
	$mb->finish;

	#my ($bioseqtype) = dbi_getvalue ($db, $sql);
	my $new_bioseqtype = $seq->ftype();  

	if ($bioseqtype eq 'PRT' and $new_bioseqtype ne 'PRT'){
	    $new_acc_flag = "Y";
	}

	if ($bioseqtype eq 'nucleotide' and $new_bioseqtype eq 'PRT'){
	    $new_acc_flag = "Y";
	} 

	# if this is an update but with different doctype,  
	# update the doctype in the patent table (or the entry won't load)
	if ($new_acc_flag eq "N") {
	    if ($doctype ne $doc->doctype()) {
		my $sql = "UPDATE patent SET doctype = ? 
                            WHERE docoffice = ? 
                              AND docnum = ?"; 
		
		my $sth = $db->prepare($sql);
		$sth->execute($doc->doctype(), $doc->docoffice(), $doc->docnumber());
		dbi_commit($db);
		
		# accs updated by this method aren't automatically 
		# distributed so must be done manually
		print ACCS_TO_DISTRIBUTE "$accno\n";
	    }
	}
    }

    if ($new_acc_flag eq "Y"){
	push (@report, $accno);
    }

    if ( ! defined $accno || $new_acc_flag eq 'Y') {

	### get next epo accession number from stach
	$accno = SeqDBUtils2::assign_accno_single($db,'EPO'); # get an accession
	bail ( "cannot create accession number", $db )   if ( !defined $accno );   
    }
    return $accno;
}


sub print_entry {

    my ( $db, $FH, $doc, $seq ) = @_;

    my ( $acc ) = get_accession ( $db, $doc, $seq );

    my $seq_len = $seq->seqlen();

    # check if the protein is in 3-letter code and if it is change it to one-letter code
 
    my $result = $seq_len / 3;
    my $one_letter_seq = '';
    my $new_seq_length = 0;
  
    if ($seq->ftype() eq "PRT" and $result !~ /\d+\.\d+/){
      
	$one_letter_seq = change_to_one_letter($seq->seq(), $seq_len);
    
	if ($one_letter_seq ne ''){
	    $new_seq_length = length ($one_letter_seq);	  
	    print LOG $doc->docoffice().$doc->docnumber()." seq ".$seq->seqno().
                  "    sequence in three-letter code and has been converted to one-letter code\n",
        }
    }
    
    if ( $seq->ftype() eq "PRT" ) {
	if ( $one_letter_seq ne ''){ 
	    print $FH "ID   $acc; SV 1; linear; protein; PAT; UNC; $new_seq_length AA.\n";
	}
	else {
	    print $FH "ID   $acc; SV 1; linear; protein; PAT; UNC; $seq_len AA.\n";
	}			
    }
    else {
	my $topology = $seq->topology () eq 'C' ? 'circular ' : 'linear';
	my $seq_type = $seq->ftype ();
	print $FH "ID   $acc; SV 1; $topology; XXX; PAT; UNC; $seq_len BP.\n";
    }

    print $FH  "ST * public\n";
    print $FH  "XX\n";
    print $FH  "AC   $acc;\n";
    print $FH  "XX\n";
    print $FH  "DE   Sequence ".$seq->seqno()." from Patent ".$doc->docoffice().$doc->docnumber().".\n";
    print $FH  "XX\n";
    
    print $FH  "RN   [1]\n";
    display_long_line ( \*$FH, "RA   ", format_invname ( $doc->invname() ));
    display_long_line ( \*$FH, "RT   ", format_title ( $doc->title() ).";" );

    if (($doc->invname() eq "") && ($doc->appname() ne "")) {
	display_long_line ( \*$FH, "RG   ", format_appname ( $doc->appname() ));
	print $FH  "RL   Patent number ".$doc->docoffice().
	    $doc->docnumber()."-".$doc->doctype().
	    "/".$seq->seqno().", ".$doc->docdate().".\n";
    }
    else {
	print $FH  "RL   Patent number ".$doc->docoffice().
	    $doc->docnumber()."-".$doc->doctype().
	    "/".$seq->seqno().", ".$doc->docdate().".\n";
	display_long_line ( \*$FH, "RL   ", format_appname ( $doc->appname() ));
    }

    # RL   Patent number EP0242016-A/1, 21-OCT-1987.
    # RL   AGRICULTURAL GENETICS COMPANY LIMITED.
    

### applicationnumber/office not stored any more, ckanz 02-MAR-2004

#  print $FH  "PF   ".$doc->appdate()." ".$doc->appoffice().$doc->appnumber()."\n";

### patentpriority not stored any more, ckanz 02-MAR-2004

#  for ( my $i = 0; $i < $doc->nof ('prioappnumber'); $i++ ) {  ### added !!!
#
#    print $FH  "PR   ";
#
#    defined $doc->get_prioappdate($i) ?
#      print $FH $doc->get_prioappdate($i) : print $FH '<' x 11;
#    defined $doc->get_prioappoffice($i) ?
#      print $FH " ".$doc->get_prioappoffice($i) : print $FH " <<";
#
#    print $FH  $doc->get_prioappnumber($i)."\n";
#  }
    print $FH  "XX\n";


    if ( $doc->comment() ) {
	display_long_line ( \*$FH, "CC   ", $doc->comment() );
	print $FH "XX\n";
    }


    print $FH  "FH   Key             Location/Qualifiers\n";
    print $FH  "FH\n";


    for ( my $i = 0; $i < $seq->nof('features'); $i++ ) {
	
	my $feat_name = $seq->features($i);
    
	if ( defined $feat_name && $feat_name ne '*' && $feat_name ne '-' ) {
	    # '*': faulty feature; don't print '-' features

            # move to lowercase
	    if ($feat_name eq "Source") {
		$feat_name = "source";
	    }

	    my $qualifiers = $seq->qualifiers($i);
	    $qualifiers = defined( $qualifiers ) ? $qualifiers : '';

	    if ($feat_name eq "gene"){

		unless ($qualifiers =~ /\/gene|locus_tag|old_locus_tag/){
		    $feat_name = "misc_feature";
		}
	    }

	    if ($feat_name eq "misc_binding"){
    
		unless ($qualifiers =~ /\/bound_moiety/){ 
		    $feat_name = "misc_feature";
		}
	    }

	    if ($feat_name eq "modified_base"){
	 
		unless ($qualifiers =~ /\/mod_base/){ 
		    $feat_name = "misc_feature";
		}
	    }

	    unless ( $feat_name eq 'misc_feature' && $qualifiers eq '' ) {

		unless (($feat_name =~ /source/i) && ($i > 0)){

		    if ($one_letter_seq ne ''){
			printf $FH  "FT   %-15s %s\n", $feat_name, "1.." .$new_seq_length;
		    }
		    else {
			printf $FH  "FT   %-15s %s\n", $feat_name, $seq->locations($i);
		    } 
		}
		
		if ( $qualifiers ne '' ) {

		    my @qual = split ( /%%/, $qualifiers );
		    for ( my $j = 0; $j < @qual; $j++ ) {
			display_long_line ( \*$FH, "FT". ' ' x 19, $qual[$j] );
		    }
		}
	    }
	}
    }

    print $FH  "XX\n";
    if ($one_letter_seq ne ''){

	printf $FH "SQ   Sequence " . $new_seq_length ." %s;\n", ( $seq->ftype() eq "PRT"?"AA":"BP" );
	
	display_sequence ( \*$FH, $one_letter_seq );
    }
    else{

	printf $FH "SQ   Sequence ".$seq->seqlen()." %s;\n", ( $seq->ftype() eq "PRT"?"AA":"BP" );
 
	display_sequence ( \*$FH, $seq->seq() );
    }

    print $FH  "//\n";
}


sub translate {
   my($bim) = shift;
   return $bim unless defined $bim;
   $bim =~ tr/ÀÁÂÃÅ/A/;
   $bim =~ s/Ä|Æ/AE/g;
   $bim =~ tr/Ç/C/;
   $bim =~ tr/ÈÉÊË/E/;
   $bim =~ tr/ÌÍÎÏ/I/;
   $bim =~ tr/Ğ/D/;
   $bim =~ tr/Ñ/N/;
   $bim =~ tr/ÒÓÔÕ/O/;
   $bim =~ s/Ö/OE/g;
   $bim =~ tr/Ø/O/;
   $bim =~ tr/ÙÚÛ/U/;
   $bim =~ s/Ü/UE/g;
   $bim =~ tr/İ/Y/;
   $bim =~ s/ß/ss/g;
   $bim =~ tr/àáâãå/a/;
   $bim =~ s/ä|æ/ae/g;
   $bim =~ tr/ç/c/;
   $bim =~ tr/èéêë/e/;
   $bim =~ tr/ìíîï/i/;
   $bim =~ tr/ñ/n/;
   $bim =~ tr/òóôõø/o/;
   $bim =~ tr/ùúû/u/;
   $bim =~ s/ö/oe/g;
   $bim =~ s/ü/ue/g;
   $bim =~ tr/ıÿ/y/;
   $bim =~ tr/°/o/;

   return $bim;
}

sub change_to_one_letter {

    my ($seq, $seq_length) = @_;
   
    my $one_letter_seq = '';
    $seq =~ s/\s//g;
      
    for (my $i = 0; $i < $seq_length; $i += 3){

	my $amino_ac = substr ($seq, $i, 3);

	if (my $letter = $abbrev_letter{uc $amino_ac}){
	    $one_letter_seq .= $letter;
        }
	else {

	    return '';
	}
    }
    
    return ($one_letter_seq);
}

1;
