#!/ebi/production/seqdb/embl/tools/bin/perl -w
###########################################################################
# 	$Id: popgen.pl,v 1.50 2012/05/01 13:12:21 rasko Exp $
#
# popgen.pl     : script with graphical user interface to add new completed
#                 genomes to the table genome_seq in ENAPRO and update
#                 existing ones.
#
# AUTHOR        : Peter Sterk
# FIRST VERSION : October 2000
#
# Intranet page:
# http://www3.ebi.ac.uk/internal/seqdb/curators/genome_projects/genomewebserver.html
# 
# $Source: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/genomes/popgen.pl,v $
# $Date: 2012/05/01 13:12:21 $
# $Author: rasko $
#
# $Log: popgen.pl,v $
# Revision 1.50  2012/05/01 13:12:21  rasko
# supports wgs entries
#
# Revision 1.47  2010/05/04 16:01:19  faruque
# Now copes properly with multiple projectIDs associated with a genome entry.
#
# Revision 1.46  2010/03/16 11:49:56  faruque
# Automatically checks for other project replicons.
# Ctrl f (and Ctrl d) now scans forward (or backward) up to 1000 accessions until it hits the next database_ena entry.
#
# Revision 1.45  2010/03/04 15:50:57  faruque
# Queries yingdexer's project data if requested
#
# Revision 1.44  2010/01/12 16:50:54  faruque
# Can retrieve replicon ACs from project tables in ENAPRO
# Extra lines of creating description.
#
# Revision 1.43  2009/10/05 10:42:34  faruque
# Takes segement/chromosome number from DE for segments
#
# Revision 1.42  2009/09/04 15:50:01  faruque
# Copes with new category 'archaeal virus'
# Guesses phage and archael virus category based on taxonomy info
#
# Revision 1.41  2008/10/20 09:49:39  faruque
# Fixed but with transposition of plasmid word in DE giving a misplaced space.
#
# Revision 1.40  2008/10/16 16:00:14  faruque
# typo in last checkin - fixed
#
# Revision 1.39  2008/10/16 15:50:33  faruque
# Uses ac2magpi to get project IDs but doesn't do much with them (just shows in a window)
# NB Still does not properly use cached data (would need a refresh button  and would need to insert/delete from the cache to do so properly).
#
# Revision 1.38  2008/09/16 14:09:21  faruque
# Checks descr is not too long
#
# Revision 1.37  2008/02/22 15:20:12  faruque
# Removed use of dbi_utils
#
# Revision 1.36  2008/02/18 15:37:47  szilva
# Merging changes from RCS
#
# Revision 1.35  2008/02/04 16:25:26  faruque
# check teh cvs log
#
# Revision 1.35  2008/02/04 16:24:59  faruque
# Restructured cached genome info data
# Now includes feature counts (to help decisons about choosing from several candidate entries
#
# Revision 1.34  2008/01/14 13:53:18  faruque
# Fixed bug in next/prev shortcut keys
#
# Revision 1.33  2008/01/08 15:40:35  faruque
# Next-prev AC query from shortcut or menu
# updates cached genome data
#
# Revision 1.32  2007/12/06 16:02:58  faruque
# Faster response in showing potential duplicates
#
# Revision 1.31  2007/12/03 14:02:26  faruque
# Finally works on ant
#
# Revision 1.29  2007/02/08  16:01:52  faruque
# *** empty log message ***
#
# Revision 1.28  2006/10/02  11:35:41  faruque
# Reveals other entries from the same organism when querying the genome table
#
# Revision 1.27  2006/08/09  11:33:49  faruque
# *** empty log message ***
#
# Revision 1.26  2006/08/09  10:26:29  faruque
# changed for move to evo-1
#
# Revision 1.25  2006/02/02  16:22:57  faruque
# Now copes with multi-source organisms
#
# Revision 1.24  2006/01/30  10:12:44  faruque
# *** empty log message ***
#
# Revision 1.23  2006/01/23  14:31:41  faruque
# *** empty log message ***
#
# Revision 1.22  2005/11/14  10:04:55  faruque
# Fixed detection of mitochondrial category entries.
#
# Revision 1.21  2005/11/07  10:44:10  faruque
# Now guesses more categories (including ones based on OC -sf'
#
# Revision 1.20  2005/10/31  09:44:00  faruque
# *** empty log message ***
#
# Revision 1.19  2005/09/30  15:14:31  faruque
# *** empty log message ***
#
# Revision 1.18  2005/09/29  15:06:54  faruque
# Now prefills form for genomes not in table
#
# Revision 1.17  2004/06/28  13:39:14  faruque
# *** empty log message ***
#
# Revision 1.16  2004/06/25  10:19:51  faruque
# *** empty log message ***
#
# Revision 1.15  2004/06/25  10:04:14  faruque
# Now gets entry info (OS and DE lines) when queried
# Also has a slot for chromosome
#
###########################################################################
# To do:
# Update cached data of the existing DE + OS when inserting (and deleting when deleting
###########################################################################
use DBI;
use Tk;
use Tk::DialogBox;
use Tk::LabEntry;
use strict;
use SeqDBUtils2;

#my $database_ena = "DEVT";
my $database_ena = "ENAPRO";
umask( 003 );

my $currentState  = "started";
my $homeDir = "/ebi/production/seqdb/embl/tools/curators/scripts/genomes";

open USERS, "$homeDir/.users"
    || die "Can't find list of authorized users\n";
my $users = do{local $/; 
	       <USERS>};
close USERS;
unless ($users =~ /\b$ENV{'USER'}\b/) {
    die "User $ENV{'USER'} not authorized. Please speak to Nima or Xin.\n";
}

my $news = "12-JAN-2009   Nadeem Faruque  Ctrl-d and Ctrl-f now scan forward up to 1000 accessions until they hit an entry\n"
    . "Also entries are queried for associated magpi entries automatically (though those entries aren't checked against genomes";
my $text_message;
my $accno  = "";
my $desc   = "";
my $deLine = "";
my $osLine = "";
my $chromo = "";
my $status = "";
my $feature_count = "";
my $magpiGroup = "";

my $cat    = 1; ## should be 0 to start?
my %attr   = ( PrintError => 0,
	       RaiseError => 0,
               AutoCommit => 0 );
my $dbh_ena = DBI->connect( 'dbi:Oracle:'.$database_ena, '/', '', \%attr )
    || die "Can't connect to database_ena: $DBI::errstr";

my $dsn = "dbi:Oracle:etapro";
my $user = "gc_reader";
my $pw = "reader";

my $dbh_eta = DBI->connect( $dsn, $user, $pw )
    || die "Can't connect to database_eta: $DBI::errstr";


my $report_dir = "$homeDir/reports";
#my $publishMenuItem;
my %reverse_categoryHash;

my %entryInfo;
# Global cache of existing info (should use a proper data structure)
my %de2ac;
my %taxid2ac;
# This part is unavoidably slow and is worth commenting out if possible while testing changes
getExistingInfoHashes($dbh_ena, "", \%de2ac,\%taxid2ac);


# Made some more globals

my (@menus,@message_vars, $category, %categoryHash, $acno);
my %frameSet;
my ($button_query,$button_delete,$button_update,$button_insert,$button_clear,$button_project_info);
my $top = MainWindow->new();

my $blindAdd = 0; # 1 = exclude searching for other entries from the OS.


sub testProjectID {
    my $magpiGroup = shift;
    my $exists;
    my $sth_eta = $dbh_eta->prepare ("SELECT 1 from gc_project where project_id = ?") 
	|| die "database_eta error: $DBI::errstr\n ";
    # could look for bad projectids (eg non-int, but better to just ignore the error since it means the same
    $sth_eta->execute($magpiGroup);
#	|| die "Can't execute statement: $DBI::errstr";
    ($exists) = $sth_eta->fetchrow_array ;
    return $exists;
}

sub projectid2repliconsFromWeb {
    my $magpiGroup = shift;
    my @repliconAcsFromWeb;

    my  $out = `curl -s 'http://www.ebi.ac.uk/ena/data/view/display=xml&Project:$magpiGroup' | grep gbAcc`;
    # dirty way to quickly explore the usefulness of the curated project dataset
    foreach my $ac (split(/[\n\r]+/,$out)) {
	$ac =~ s/\s*\<gbAcc\>([0-9A-Z]+)\<\/gbAcc\>.*/$1/;
	push(@repliconAcsFromWeb,$ac);
    }
    return @repliconAcsFromWeb;
}

sub projectid2replicons {
    my $magpiGroup = shift;
    my @repliconAcs;

    my $sth_eta = $dbh_eta->prepare ("SELECT substr(replicon_acc, 1, instr(replicon_acc,  '.')-1) from
gc_replicon
join gc_assembly_set_project using (set_acc)
join gc_project using (project_acc)
where project_id = ?") 
	|| die "database_eta error: $DBI::errstr\n ";

    $sth_eta->execute($magpiGroup);
#	|| die "Can't execute statement: $DBI::errstr";
    while (my ($ac) = $sth_eta->fetchrow_array) {
	push (@repliconAcs, $ac);
    }
    return @repliconAcs;
}

# this takes too long
sub getExistingInfoHashes{
    my $dbh_ena    = shift;
    my $singleAC = shift;
    my $de2ac = shift;
    my $taxid2ac = shift;
    my %organisms;
    my $organismQuery;
    
    if ($singleAC eq "") {
	print STDERR "Caching info about existing genome_seq entries please be patient\n";
	
# cannot cope with plasmids yet
	$organismQuery = $dbh_ena->prepare(q{
	    SELECT gs.primaryacc#, gs.descr, 'OS=' || so.organism || ':chromosome=' || nvl(gs.chromosome, '-'), so.organism, nvl(gs.chromosome, '-')
		FROM genome_seq gs
		JOIN sourcefeature so ON gs.seqid = so.bioseqid
		WHERE so.primary_source = 'Y'
		GROUP BY gs.primaryacc#, gs.descr, 'OS=' || so.organism || ':chromosome=' || nvl(gs.chromosome, '-'), so.organism, nvl(gs.chromosome, '-')
	    }); 
	
	$organismQuery->execute()
	    || die "Can't execute statement: $DBI::errstr";
    } else {
	$organismQuery = $dbh_ena->prepare(q{
	    SELECT gs.primaryacc#, gs.descr, 'OS=' || so.organism || ':chromosome=' || nvl(gs.chromosome, '-'), so.organism, nvl(gs.chromosome, '-')
		FROM genome_seq gs
		JOIN sourcefeature so ON gs.seqid = so.bioseqid
		WHERE so.primary_source = 'Y'
		AND gs.primaryacc# = ?
		GROUP BY gs.primaryacc#, gs.descr, 'OS=' || so.organism || ':chromosome=' || nvl(gs.chromosome, '-'), so.organism, nvl(gs.chromosome, '-')
	    }); 
	$organismQuery->execute($singleAC)
	     || show_error("Can't execute statement: $DBI::errstr");
    }
    
    while ( my @results = $organismQuery->fetchrow_array ) {
	$entryInfo{$results[0]} = { 'DESCRIPTION'  => $results[1],
				    'SUMMARY'      => $results[2],
				    'TAX'          => $results[3],
				    'CHROMOSOME'   => $results[4]};
	my $magpiIDs = join(',',SeqDBUtils2::ac_2_magpiIDs($dbh_ena,$results[0]));
	if ($magpiIDs) {
	    $entryInfo{$results[0]}->{'MAGPIS'} = $magpiIDs;
	}
	push(@{$de2ac{$results[1]}},$results[0]);
	push(@{$taxid2ac{$results[3]}},$results[0]);
    }	
    
    print STDERR "Checking cached data for duplicate descriptions\n";
    # check for replicate descriptions
    if ($singleAC eq "") {
	print "\n";
	foreach my $de (sort keys %$de2ac) {
	    if (scalar @{$de2ac{$de}} > 1) {
		print STDERR "!\"$de\" in use in ";
		foreach my $acFromHash( @{$de2ac{$de}} ) {
		    printf STDERR "  %s (%d feat)", $acFromHash, count_features($acFromHash);
		}
		print STDERR "\n";
	    }
	}
	print "\n\n";
    }
    return 1;
}

sub overrideCat {
    my $dbh_ena  = shift;
    my $ac   = shift;
    my $cat  = shift;
    my $os2code_div = $dbh_ena->prepare(q{
	SELECT l.gc_id, l.division
	  FROM ntx_lineage l, dbentry d, sourcefeature so
         WHERE d.bioseqid = so.bioseqid
           AND so.primary_source = 'Y'
           AND so.organism = l.tax_id
	   AND d.primaryacc# = ?
	}); 
    $os2code_div->execute($ac)
	|| die "Can't execute statement: $DBI::errstr";

    if ( my ($gc, $div) = $os2code_div->fetchrow_array ) {
	if ($div eq "PHG") {
	    $cat = "phage";
	} elsif (($gc == 11) && 
		 ($div eq "VRL")) {
	    $cat = "archaeal virus";
	}
    }
    $os2code_div->finish();
    return $cat;
}


sub updateInfoHashes {
    my $ac = shift;
    removeFromExistingInfoHashes($ac);
    getExistingInfoHashes($dbh_ena, $ac, \%de2ac,\%taxid2ac);
    return 1;
}

sub removeFromExistingInfoHashes {
    my $acToBeRemoved = shift;
    if (defined($entryInfo{$acToBeRemoved})) {
	my $oldDE    = $entryInfo{$acToBeRemoved}->{'DESCRIPTION'};
	my $oldTaxid = $entryInfo{$acToBeRemoved}->{'TAX'};
	undef($entryInfo{$acToBeRemoved});
	if (defined($oldDE)) {
	    my $arrayLength = scalar(@{$de2ac{$oldDE}}); # NB changed to 0 when array element is found
	    for (my $i = 0; $i < $arrayLength; $i++){
		if (${$de2ac{$oldDE}}[$i] eq $acToBeRemoved) {
		    splice (@{$de2ac{$oldDE}}, $i, 1);
		    # remove hash member if there was only one element in its list
		    if($arrayLength == 1) {
			undef($de2ac{$oldDE});
		    }
		    $arrayLength = 0;
		}
	    }
	}
	if (defined($oldTaxid)) {
	    my $arrayLength = scalar(@{$taxid2ac{$oldTaxid}}); # NB changed to 0 when array element is found
	    for (my $i = 0; $i< $arrayLength; $i++){
		if (${$taxid2ac{$oldTaxid}}[$i] eq $acToBeRemoved) {
		    splice (@{$taxid2ac{$oldTaxid}}, $i, 1);
		    # remove hash member if there was only one element in its list
		    if($arrayLength == 1) {
			undef($taxid2ac{$oldTaxid});
		    }
		    $arrayLength = 0;
		}
	    }
	}
    }
    return 1;
}

sub queryForAdjacentAc {
    my $direction = shift; # +1 or -1
    $accno =~ s/(^\s+)|(\s+$)//g;
    $accno = uc($accno);
    my $startingAc = $accno;
    my $scanDistance = 1000;
#    print STDERR "Scanning $scanDistance from $accno using $direction\n";

    for (my $i = 1; $i <= $scanDistance; $i++) {
	my $previousAc = $accno;
	$accno = adjacentAc(uc( $accno ), $direction);
	if ($previousAc eq $accno) { # if adjacentAc can't be done, accno is unchanged
	    return 0;
	}
	if (query_acc()) {
	    return 1;
	}
    }
    $text_message->insert('end', 
			  sprintf("Scanned %s from %s and gave up after %d accessions\n", 
				  ($direction == +1?"forwards":"backwards"),
				  $startingAc, 
				  $scanDistance), 
			  'red' );
    return 0;
}
    
sub queryNextAc {
#    print STDERR "queryNextAc\n";
    queryForAdjacentAc(+1);
}

sub queryPreviousAc {
#    print STDERR "queryPreviousAc\n";
    queryForAdjacentAc(-1);
}
   
sub adjacentAc {
    my $ac = shift;
    my $change = shift;
    my $prefix;
    my $numberComponentIn;
    if ($ac =~ /\b([A-Za-z]+)(\d+)\b/) {
	$prefix = $1;
	$numberComponentIn = $2;
    }
    else {
	$text_message->insert('end', sprintf("Cannot seem to resolve %s %d\n", $ac, $change), 'red' );
	return $ac;
    }
    my $numberComponentOut = $numberComponentIn + $change;
    if ($numberComponentOut < 0) {
	$text_message->insert('end', sprintf("Cannot go smaller than %s\n", $ac), 'red' );
	return $ac;
    }
    my $numberComponentOutString = sprintf "%0".length($numberComponentIn)."d", $numberComponentOut;
    if (length($numberComponentOutString) > length($numberComponentIn)) {
	$text_message->insert('end', sprintf("Cannot go larger than %s\n", $ac), 'red' );
	return $ac;
    }
    return $prefix.$numberComponentOutString;
}

# Report other entries for any organism
sub taxid2genomeEntries($$$){
    my $dbh_ena    = shift;
    my $ac     = shift;
    my $taxid  = shift;
    my %resultsHash;
    my $organismQuery = $dbh_ena->prepare(q{
	SELECT gs.primaryacc#, gs.DESCR
	    FROM genome_seq gs
	    JOIN dbentry d        ON gs.seqid =  d.bioseqid
	    JOIN sourcefeature so ON gs.seqid = so.bioseqid
	    WHERE gs.primaryacc#   != ?
	    AND so.PRIMARY_SOURCE = 'Y'
	    AND so.ORGANISM       = ?
	});
#	    AND d.statusid        = 4 /* public */
    
    $organismQuery->bind_param( 1, $ac);
    $organismQuery->bind_param( 2, $taxid);
    $organismQuery->execute
	|| show_error("Can't execute statement: $DBI::errstr");
    while ( my @results = $organismQuery->fetchrow_array) {
	$resultsHash{$results[0]} = $results[1]; 
    }
    $organismQuery->finish;
    return %resultsHash;
}


$top->title( 'POPGEN Genomes Web Server Entry Form' );

menu_bar();

lab_entries();

category_listbox();

#category_radio_buttons();

action_buttons();

text_message();

MainLoop();


sub count_features{
    my $ac  = shift;
    if (!(defined($entryInfo{$ac}->{'FEATURES'}))) {
	my $featureCounter = $dbh_ena->prepare(
					   q{ SELECT count(*)
					        FROM seqfeature f, dbentry d
					       WHERE d.primaryacc# = ?
						 AND d.bioseqid = f.bioseqid 
						 AND f.fkeyid != 69 -- no gene features
					      } );
	$featureCounter->execute($ac)
	     || show_error("Can't execute statement: $DBI::errstr");

        # Ensure result is cached in the entryInfo hash
	$entryInfo{$ac}->{'FEATURES'} = $featureCounter->fetchrow_array;
	(defined($entryInfo{$ac}->{'FEATURES'})) || ($entryInfo{$ac}->{'FEATURES'} = 0);

	$featureCounter->finish();
    }
    return $entryInfo{$ac}->{'FEATURES'};
}

sub clean_description($){
    my $description = shift;
    $description =~ s/ *\.?$//i; # remove trailing spaces and .'s
    $description =~ s/ sequence$//i;
    $description =~ s/\bmitochondrial DNA, complete genome\.?/mitochondrion/;
    $description =~ s/ (complete)? mitochondrial ((genome)|(DNA)|($))/ mitochondrion/i;
    $description =~ s/ genome$//i;
    $description =~ s/ cds$//i;
    $description =~ s/,? complete$//i;
    $description =~ s/,? complete plasmid$//i;
    $description =~ s/,? genomic RNA$//i;
    $description =~ s/(\bp[^ ]+) plasmid$/plasmid $1/;
    $description =~ s/ DNA$//i;
    $description =~ s/,* whole genome shotgun( sequence)?\.*//i;
    $description =~ s/\bmitochondrial$/mitochondrion/; 
    $description =~ s/(\bspecimen )?voucher \S+ mitochondrion*$/mitochondrion/; # specimen vouchers common in mitochondion descriptions
    $description =~ s/\bisolate \S+ mitochondrion*$/mitochondrion/; # isolate names common in mitochondion descriptions
    $description =~ s/\bcultivar \S+ chloroplast/chloroplast/; # cultivars popular in plant plastids
    return $description;
}

sub menu_bar {
    my $f = $top->Frame( -relief => 'ridge', -borderwidth => 2 );
    $f->pack( -side => 'top', 
	      -anchor => 'n', 
	      -expand => '1', 
	      -fill => 'x' );
    
    foreach ( qw/File Help/ ) {
        push ( @menus, $f->Menubutton( -text => $_, -tearoff => 0 ) );
    }
    $menus[$#menus]->pack( -side => 'right' );
    $menus[0]->pack( -side       => 'left' );
    $menus[0]->cascade( -label => 'Export report' );
    my $cm = $menus[0]->cget( -menu );
    my $er = $cm->Menu( -tearoff => 0 );
    $menus[0]->entryconfigure( 'Export report', -menu => $er );
    $er->command( -label   => 'Selected category',
                  -command => [ \&export_report, 'selected' ] );
    $er->command( -label   => 'All categories',
                  -command => [ \&export_report, 'all' ] );
    
    $menus[0]->command( -label => 'Make Web Pages', 
			-state => 'normal', 
			-command => \&call_getGenomes );
    
#    $publishMenuItem = $menus[0]->command( -label => 'Publish Web Pages', 
#			 -state => 'disabled', 
#			-command => \&publishPages );
    $menus[0]->command( -label => 'Prev AC',   
			-accelerator => 'Ctrl+d',
			-command => \&queryPreviousAc );
    $menus[0]->command( -label => 'Next AC',   
			-accelerator => 'Ctrl+f',
			-command => \&queryNextAc );
    $menus[0]->separator;
    $menus[0]->command( -label => 'Quit',   
			-accelerator => 'Ctrl+q',
			-command => \&terminate );
    
    
    @message_vars = ( "OK",
                      "About popgen - populate genomes table - for Integr8 and genomes pages",
                      "popgen.pl\nPeter Sterk\nEBI 2000"
		      ."getGenomes.pl\nNadeem Faruque 2003"
		      );
    $menus[$#menus]->command( -label   => 'About Entry Form',
                              -command => [ \&show_messageBox, @message_vars ]
			      );
    $top->bind('<Control-Key-d>' => \&queryPreviousAc); 
    $top->bind('<Control-Key-f>' => \&queryNextAc);  
    $top->bind('<Control-Key-q>' => \&terminate); 
    
}

sub terminate {
    $dbh_ena->disconnect;
    exit;
}
sub debug {
    print STDERR "accno = ".$accno."\n";
}

sub show_messageBox {
    my ( $type, $title, $message ) = @_;
    my $button = $top->messageBox( -type    => $type,
                                   -title   => $title,
                                   -message => $message
				   );
}

sub clear_fields {
    $deLine = "";
    $osLine = "";
    $accno  = "";
    $desc   = "";
    $chromo = "";
    $status = "";
    $magpiGroup = "";
    $feature_count = "";
    $category->selectionClear( 0, 'end' );
    $text_message->delete( '1.0', 'end' );
    $text_message->insert( 'end', "READY\n", 'darkgreen' );
}

sub delete_row {
    query_acc();
    my $query_text = $text_message->get( '1.0', 'end' );
    return if $query_text =~ /Accession number .* invalid or not found/;
    $text_message->delete( '1.0', 'end' );
    $accno =~ s/(^\s+)|(\s+$)//g;
			
    my $button = $top->messageBox(
				  -type    => "OKCancel",
				  -title   => "Confirm deletion",
				  -message => "Do you really want to delete $accno?",
				  -default => "Cancel",
    );
    if ( $button eq "Cancel" ) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end', "Deletion cancelled.\n", 'red' );
        return;
    }
			
    my $sth_ena = $dbh_ena->prepare(
			    q{
				DELETE from genome_seq
				    WHERE primaryacc# = upper ( ? ) }
				);
    $sth_ena->execute($accno) || show_error("Can't execute statement: $DBI::errstr");
    $sth_ena->finish;
    $dbh_ena->commit();
    print "Deleted \"$accno\"\n";
    $text_message->delete( '1.0', 'end' );
    $text_message->insert( 'end', "$accno deleted.\n", 'darkgreen' );
    removeFromExistingInfoHashes($accno);
}

sub show_project_entries {
    if ($magpiGroup eq '') {
	$text_message->insert('end', "No Project ID\n", 'red' );
	return;
    }	
    foreach my $magpiGroup_split (split(/,/, $magpiGroup)) {
	if (!(testProjectID($magpiGroup_split))) {
	    $text_message->insert('end', sprintf("Project ID %s not found in ENAPRO\n", $magpiGroup_split), 'red' );
	    next;
	}	
	my @repliconAcs = projectid2replicons($magpiGroup_split);
	
	$text_message->insert('end', 
			      sprintf("Project %s contains ...\nReplicons: %s\n", 
				      $magpiGroup_split, 
				      join (', ',@repliconAcs)), 
			      'black' );
	
# temporary effort to investigate how much extra info is in xml v1 (not in enapro)
# should use map not foreach
# also, projectid2repliconsFromWeb is a very dirty way of doing it - should use proper http call (and xml parsing!)
	my @repliconAcsFromWeb = projectid2repliconsFromWeb($magpiGroup_split);
	my @repliconAcsFromWebOnly = ();
	foreach my $replicon (@repliconAcsFromWeb) {
	    if (!(grep(/$replicon/,@repliconAcs))) {
		push (@repliconAcsFromWebOnly, $replicon);
	    }
	}
	$text_message->insert('end', 
			      sprintf("Replicons only from v1 project XML: %s\n", 
				      join (', ',@repliconAcsFromWebOnly)), 
			      'black' );
    }
#    $text_message->update;
}
sub update_row {
    my ($cat)        = $category->curselection();;
    my $selected_cat = $reverse_categoryHash{$cat};
    $accno =~ s/(^\s+)|(\s+$)//g;
    $chromo =~ s/(^\s+)|(\s+$)//g;
    if ($chromo eq ""){
	$chromo = "-";
    }
    if ( length($chromo) > 10) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
			       "\"$chromo\" too long for the chromosome field - row not updated.\n",
			       'red' );
        return;
    }			    
    if ( length($desc) > 180) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
			       "\"$desc\" too long for the desc field - row not updated.\n",
			       'red' );
        return;
    }			    

    if (( $accno eq "") || 
	( ( $accno !~ /^\w\d{5}$/) && 
	  ($accno !~ /^\w\w\d{6}$/ &&
       $accno !~ /^\w\w\w\w\d{8}$/ &&
       $accno !~ /^\w\w\w\w\d{9}$/) )) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
			       "No or invalid accession number $accno - row not updated.\n",
			       'red' );
        return;
    }
    if ( $desc eq "" ) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
                               "No description given - row not updated.\n",
                               'red' );
        return;
    }
    unless ( defined $cat ) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
                               "No category selected - row not updated.\n",
                               'red' );
        return;
    }
    $text_message->delete( '1.0', 'end' );

    my $sth_ena = $dbh_ena->prepare(
			    q{
				UPDATE genome_seq
				    SET descr = ?,
				    category = (SELECT code from cv_genome_category
						WHERE descr = ? ),
				    chromosome = ?
				    WHERE primaryacc# = upper ( ? )
				}
			    );


    $sth_ena->bind_param( 1, $desc );
    $sth_ena->bind_param( 2, $selected_cat );
    $sth_ena->bind_param( 3, $chromo );
    $sth_ena->bind_param( 4, $accno );

    $sth_ena->execute() || show_error("Can't execute statement: $DBI::errstr");
    $sth_ena->finish;
    $dbh_ena->commit();
    query_acc();
    updateInfoHashes($accno);
    $text_message->delete( '1.0', 'end' );
    $text_message->insert( 'end', "$accno updated.\n", 'darkgreen' );
}

sub insert_row {
    my ($cat) = $category->curselection();
    unless ( defined $cat ) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
                               "No category selected - row not inserted.\n",
                               'red' );
        return;
    }
    my $selected_cat = $reverse_categoryHash{$cat};
    
    if (!(defined($accno))){
	$accno = "";
    }
    $desc  =~ s/(^\s+)|(\s+$)//g;
    $accno =~ s/(^\s+)|(\s+$)//g;
    if ( !defined $chromo ) {
	$chromo = "-";} # stop it being null
    $chromo =~ s/(^\s+)|(\s+$)//g;
    if ($chromo eq ""){
        $chromo = "-";
    }
    if ($desc =~ /\t/){
	if ($accno eq ""){
	    # parse ACCESSION\tDESCRIPTION[\tDATE] ie output from new genomes cron
	    $desc =~ s/(\w+)\s*\t\s*([^\t]+)(\t.*)?/$2/;
	    $accno = $1;
	    print "  (extracted accession and description as \"$accno\" \"$desc\")\n";
	}
	else{
	    $desc =~ s/\t/*/g;
	    $text_message->insert( 'end',
				   "Description contains a tab (see asterix in text)\n"
				   ." and accession number was provided.\n",
				   'red' );
	    return;
	}
	
    }
    if ( length($chromo) > 10) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
			       "\"$chromo\" too long for the chromosome field - row not inserted.\n",
			       'red' );
        return;
    }			    
    if ( length($desc) > 180) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
			       "\"$desc\" too long for the desc field - row not updated.\n",
			       'red' );
        return;
    }			    
    if ( ($accno eq "") || 
	 ( ( $accno !~ /^\w\d{5}$/) && 
	   ($accno !~ /^\w\w\d{6}$/ &&
        $accno !~ /^\w\w\w\w\d{8}$/ &&
        $accno !~ /^\w\w\w\w\d{9}$/) ) ) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
			       "No or invalid accession number $accno - row not inserted.\n",
			       'red' );
        return;
    }
    if ( $desc eq "" ) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
                               "No description given - row not inserted.\n",
                               'red' );
        return;
    }
    $text_message->delete( '1.0', 'end' );

    my $sth_ena0 = $dbh_ena->prepare(
			     q{
				 SELECT d.primaryacc#, cvs.status
				     FROM dbentry d, cv_status cvs
				     WHERE d.primaryacc# = upper ( ? )
				     AND d.statusid      = cvs.statusid
				 }
			     );

    my ( $entry_name, $entry_status );

    $sth_ena0->bind_param( 1, $accno );
    $sth_ena0->execute($accno) || show_error("Can't execute statement: $DBI::errstr");

    while ( ( $entry_name, $entry_status ) = $sth_ena0->fetchrow_array ) {
#	print "\$entry_name, \$entry_status = $entry_name, $entry_status\n";
        last;
    }
    if ( !defined $entry_name){
        $text_message->delete( '1.0', 'end' );
        $text_message->insert(
			      'end',
			      "No entry $accno found in EMBL database_ena.\n" .
			      "Nothing inserted.\n",
			      'red'
			      );
	return;
    }
    elsif($entry_status ne 'public' ) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert(
			      'end',
			      "$accno is $entry_status.\nNothing inserted.\n",
			      'red'
			      );
        return;
    }
    $sth_ena0->finish;
    my $sth_ena = $dbh_ena->prepare(
			    q{
				INSERT into genome_seq ( seqid, primaryacc#, category, status, descr, chromosome )
							 SELECT d.bioseqid, d.primaryacc#, gc.code, 'C', ltrim ( rtrim ( ? ) ), ?
						       FROM dbentry d, cv_genome_category gc
							 WHERE d.primaryacc# = upper ( ? )
							 AND upper ( gc.descr ) = upper ( ? ) }
				);
			    
			    
    $sth_ena->bind_param( 1, $desc );
    $sth_ena->bind_param( 2, $chromo );
    $sth_ena->bind_param( 3, $accno );
    $sth_ena->bind_param( 4, $selected_cat );

    $sth_ena->execute() || show_error("Can't execute statement: $DBI::errstr");
    $sth_ena->finish;
    $dbh_ena->commit();

    query_acc();
    $text_message->insert( 'end', "Row inserted for $accno.\n", 'darkgreen' );
    updateInfoHashes($accno);
    print "Added \"$accno\"\t\"$desc\" to $selected_cat (cat $cat)\n";

}

sub show_error {
    my $dbi_error = $_[0];
    $text_message->delete( '1.0', 'end' );
    $text_message->insert( 'end', "$dbi_error\n", 'red' );
}


sub regen_description{
    query_acc_full(1);
}
    

sub query_acc {
    return query_acc_full(0);
}

sub query_acc_full {
    my $regenerate_desc = shift;
    my ( $chromoIn, $workingDescription, $cat, $acIn, $deLineIn, $organism, $lineage, $taxid);
    $accno =~ s/(^\s+)|(\s+$)//g;
    $accno = uc( $accno );
    if($accno eq ""){
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
                               "No accession number given.\n",
                               'red' );
	if($desc ne "") {
	    my $searchText = quotemeta($desc );
	    foreach my $deFromHash (keys %de2ac) {
		if ($deFromHash =~ /$searchText/i) {
		    $text_message->insert('end', sprintf("%s found in %s\n", $deFromHash, @{$de2ac{$deFromHash}}), 'darkgreen' );
		}
	    }
	}
        return 2;
    } 

    my $sth_ena = $dbh_ena->prepare(
			    q{
				SELECT db.PRIMARYACC#, d.TEXT, syn.name_txt, lin.lineage, so.organism, s.status
				    FROM description d, dbentry db, ntx_synonym syn, sourcefeature so, ntx_lineage lin, cv_status s
				    WHERE db.PRIMARYACC# = ?
				    AND db.statusid    = s.statusid
				    AND db.dbentryid   = d.DBENTRYID
				    AND db.BIOSEQID    = so.BIOSEQID
				    AND so.PRIMARY_SOURCE = 'Y'
				    AND so.organism    = syn.tax_id 
				    AND syn.name_class = 'scientific name'
				    AND syn.tax_id     = lin.tax_id
				}
			    );
			
    $sth_ena->bind_param( 1, $accno );
    $sth_ena->execute($accno) || show_error("Can't execute statement: $DBI::errstr");
			
    while ( ( $acIn, $deLineIn, $organism, $lineage, $taxid, $status) = $sth_ena->fetchrow_array ) {
        last;
    }
    $sth_ena->finish();
    if ( !defined $acIn ) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
                               "Accession number \"$accno\" not in database_ena.\n",
                               'red' );
	$osLine = "";
	$deLine = "";
	$chromo = "-";
	$status = "N/A";
	$feature_count = "";
	$desc   = "";
	$magpiGroup = "";
        return 0;
    } 
    $magpiGroup = join(',',SeqDBUtils2::ac_2_magpiIDs($dbh_ena,$acIn));
    if ( !defined $deLineIn ) {
	$deLineIn = "";
	print "$accno has no description!\n";
    }
    $deLine = "";
    $deLineIn =~ s/(^\s+)|(\s+$)//g;
    $deLine = $deLineIn;

    if ( !defined $organism ) {
	$organism = "";
	print "$accno has no organism!\n";
    }
    $osLine = "";
    $organism =~ s/(^\s+)|(\s+$)//g;
    $osLine = $organism;

# the following should be updated to use the cached data
    $sth_ena = $dbh_ena->prepare(
			 q{
			     SELECT gs.descr, cv.descr, nvl(gs.chromosome,'-')
				 FROM genome_seq gs, cv_genome_category cv, dbentry db
				 WHERE gs.primaryacc# = ?
				 AND gs.primaryacc# = db.PRIMARYACC#
				 AND gs.category = cv.code}
			 );

    $sth_ena->execute($accno) || show_error("Can't execute statement: $DBI::errstr");

    while ( ( $workingDescription, $cat, $chromoIn) = $sth_ena->fetchrow_array ) {
        last;
    }
    (defined($chromoIn)) or $chromoIn = "-";
    $sth_ena->finish();
    $feature_count = count_features($accno); # place the value in the Tk field
    $chromo = "";
    $chromoIn =~ s/(^\s+)|(\s+$)//g; 
    $chromo = $chromoIn;

    if ( !defined $workingDescription ) {
        $text_message->delete( '1.0', 'end' );
        $text_message->insert( 'end',
                               sprintf ("Accession number %s (%d features) not in genomes table.\n", $accno, count_features($accno)),
                               'red' );
	$chromo = "-";
    }
    if (defined($status) && ($status ne 'public')) {
	$status = uc($status);
        $text_message->insert( 'end',
                               "status $status\n",
                               'red' );	
	$workingDescription   = "status $status";
    } elsif ( (!defined $workingDescription ) || ($regenerate_desc == 1)) {
# needs to be smart enough to cope with changes in the OS!
	$workingDescription   = clean_description($deLineIn);
	if ($workingDescription =~ /\bchromosome ([0-9A-Z]+)/){
	    $chromo = $1;} 
	elsif ($workingDescription =~ /\bsegment (\S+)/){
	    $chromo = $1;} 
	if ($workingDescription =~ /\bmitochondrial .*plasmid/){
	    $cat = "mitochondrial plasmid"
	    }
	elsif ($workingDescription =~ /\bplasmid\b/){
	    $cat = "plasmid";
	}
	elsif ($workingDescription =~ /\bchloroplast\b/){
	    $cat = "chloroplast";
	}
	elsif ($workingDescription =~ /\bplastid\b/){
	    $cat = "chloroplast";
	}
	elsif ($workingDescription =~ /\bmitochondr(ial)|(ion)/){
	    $cat = "mitochondrion"
	    }
	elsif ($workingDescription =~ /\b([bB]acterio)?phage\b/){
	    $cat = "phage"
	    }
	elsif ($workingDescription =~ /\bviroid\b/){
	    $cat = "viroid"
	    }
	elsif ($workingDescription =~ /\bvirus\b/){
	    $cat = "virus"
	    }
	elsif ($workingDescription =~ /virus\b/){ # maybe this rule will be low specificity
	    $cat = "virus"
	    }
	elsif ($lineage =~ /^Eukaryota; /){
	    $cat = "eukaryota";
	}
	elsif ($lineage =~ /^Bacteria; /){
	    $cat = "bacteria";
	}
	elsif ($lineage =~ /^Archaea; /){
	    $cat = "archaea";
	}
# since none others picked, take rougher guesses
	elsif ($workingDescription =~ /phage\b/){ 
	    $cat = "phage"
	    }
	$cat = overrideCat($dbh_ena,$accno,$cat); # checking tax tables may help for some
    } else {
        $text_message->delete( '1.0', 'end' );
	$text_message->insert( 'end', "READY\n", 'darkgreen' );
    }
    $desc = "";
    $desc = $workingDescription;
    if(defined($cat)){
	$category->selectionClear( 0, 'end' );
	$category->selectionSet( $categoryHash{$cat} );
    }
    $sth_ena->finish;
    if ((defined($magpiGroup)) && ($magpiGroup !~ /^\s*$/)) {
	show_project_entries();
    } else {
	print STDERR "magpiGroup no good for $acIn\n";
    }

    if ($blindAdd != 1) {
	if (defined($de2ac{$desc})) {
	    foreach my $acFromHash (@{$de2ac{$desc}}) {
		if ($acFromHash ne $accno) {
		    $text_message->insert('end', 
					  sprintf("Same DE:%s (%s)\n", 
						  $acFromHash, $entryInfo{$acFromHash}->{'SUMMARY'}), 
					  'red' );
		}
	    }
	}
	if (defined($taxid2ac{$taxid})) {
	    foreach my $acFromHash (@{$taxid2ac{$taxid}}) {
		if ($acFromHash ne $accno) {
		    $text_message->insert('end', 
					  sprintf("Same OS%s:%s \"%s\" (%d features)\n", 
						  $taxid, $acFromHash, $entryInfo{$acFromHash}->{'DESCRIPTION'}, count_features($acFromHash)), 
					  'darkgreen' );
		}
	    }
	}
    }	
    return 1;
}

sub category_listbox {
    # Section for category lists and buttons
    $frameSet{'MAIN'} = $top->Frame(
#			   -borderwidth => 5, 
#			   -relief => 'groove'
				    )->pack( -expand => '1', 
					     -fill   => 'x',
					     -side   => 'top', 
					     -anchor => 'n');
    # Section for category list box
    $frameSet{'TOP_PLUS'} = $frameSet{'MAIN'}->Frame()->pack( -side   => 'left', 
							      -anchor => 'nw');
    $frameSet{'TOP_PLUS'}->Label( -text => "Category:" )->pack( -side   => 'left', 
								-anchor => 'nw' ); 
    
    
    $category = $frameSet{'TOP_PLUS'}->Listbox( -width      => '30',
						-height     => '12',
						-background => 'white',
						-exportselection => '0',
						-selectmode => 'single',
						)->pack( -anchor => 'w', 
							 -padx => '15' , 
							 -pady => '5' );
    
    my $sth_ena = $dbh_ena->prepare(
			    q{
				SELECT descr
				    FROM cv_genome_category}
			    );
    
    $sth_ena->execute() || die "Can't execute statement: $DBI::errstr";
    
    my $cat_no = 0;
    while ( ( $cat ) = $sth_ena->fetchrow_array ) {
        unless ( $cat eq "complete" ) {
            $categoryHash{$cat} = $cat_no;
            $cat_no++;
            $category->insert( 'end', $cat );
        }
    }
    %reverse_categoryHash = reverse %categoryHash;
    
    $sth_ena->finish;
    $category->selectionClear( 0, 'end' );
}


sub action_buttons {
    # Section for main buttons
    $frameSet{'BUTTONS'} = $frameSet{'MAIN'}->Frame()->pack(  -expand => '1', 
							      -fill => 'both',
							      -side => 'top', 
							      -anchor => 'ne');
    
    $button_query = $frameSet{'BUTTONS'}->Button( -text             => 'Query AC/DE',
						  -activeforeground => 'blue',
						  -command          => \&query_acc
						  );
    $button_query->pack( -side   => 'top',
			 -anchor => 'ne',
			 -padx   => '12',
			 -pady   => '1',
			 -expand => '1', 
			 -fill   => 'both'
			 );
    
    $button_delete = $frameSet{'BUTTONS'}->Button( -text             => 'Delete',
						   -activeforeground => 'blue',
						   -command          => \&delete_row
						   );
    $button_delete->pack( -side   => 'top',
                          -anchor => 'ne',
			  -padx   => '12',
			  -pady   => '1',
			  -expand => '1', 
                          -fill   => 'both'
			  );
    
    $button_update = $frameSet{'BUTTONS'}->Button( -text             => 'Regenerate description',
						   -activeforeground => 'blue',
						   -command          => \&regen_description
						   );
    $button_update->pack( -side   => 'top',
                          -anchor => 'ne',
			  -padx   => '12',
			  -pady   => '1',
			  -expand => '1', 
                          -fill   => 'both'
			  );
    
    $button_update = $frameSet{'BUTTONS'}->Button( -text             => 'Update',
						   -activeforeground => 'blue',
						   -command          => \&update_row
						   );
    $button_update->pack( -side   => 'top',
                          -anchor => 'ne',
			  -padx   => '12',
			  -pady   => '1',
			  -expand => '1', 
                          -fill   => 'both'
			  );
    
    $button_insert = $frameSet{'BUTTONS'}->Button( -text             => 'Insert',
						   -activeforeground => 'blue',
						   -command          => \&insert_row
						   );
    $button_insert->pack( -side   => 'top',
                          -anchor => 'ne',
			  -padx   => '12',
			  -pady   => '1',
			  -expand => '1', 
                          -fill   => 'both'
			  );
    
    $button_clear = $frameSet{'BUTTONS'}->Button( -text             => 'Clear',
						  -activeforeground => 'blue',
						  -command          => \&clear_fields
						  );
    $button_clear->pack( -side   => 'top',
                         -anchor => 'ne',
                         -padx   => '12',
                         -pady   => '1',
                         -expand => '1', 
			 -fill   => 'both'
			 );
    
}

sub lab_entries {
    $frameSet{'TOP_PLUS'} = $top->Frame()->pack( -anchor => 'n',
						 -side   => "top",
						 -fill   => 'x',
						 -expand => '1');
    
    $frameSet{'TOP_PLUS'}->Label(-anchor => 'n',
				 -text   => "Query and alter $database_ena genome_seq table and update WWW Server" 
				 )->pack( -anchor => 'n',
					  -side   => "top",
					  -fill   => 'x',
					  -expand => '1');
    
    
    $frameSet{'ACCESSION_PLUS'} = $frameSet{'TOP_PLUS'}->Frame()->pack( -side => 'top',
									-anchor => 'nw',
									); 
    $frameSet{'CHROMOSOME_PLUS'} = $frameSet{'ACCESSION_PLUS'}->Frame()->pack( -side => 'right',
									       -anchor => 'ne',
									       -padx   => '0',
									       -pady   => '0'
									       ); 
    $frameSet{'STATUS_ONLY'} = $frameSet{'CHROMOSOME_PLUS'}->Frame()->pack( -side => 'right',
									    -anchor => 'ne',
									    -padx   => '0',
									    -pady   => '0'
									    ); 
    
    $frameSet{'FEATURE_COUNT'} = $frameSet{'CHROMOSOME_PLUS'}->Frame()->pack( -side => 'right',
									    -anchor => 'ne',
									    -padx   => '0',
									    -pady   => '0'
									    ); 
    
    
    $frameSet{'ACCESSION_PLUS'}->LabEntry(-label     => 'Accession#:',
					  -labelPack => [ -side   => "left", 
							  -anchor => "w" ],
					  -background => 'white',
					  -width      => 10,
					  -textvariable => \$accno
					  )->pack( -side   => "top", 
						   -anchor => "nw", 
						   -pady   => 2 );
    
    $frameSet{'CHROMOSOME_PLUS'}->LabEntry(-label     => 'Chromosome#:',
					   -labelPack => [ -side   => "left", 
							   -anchor => "w" ],
					   -background => 'white',
					   -width     => 10,
					   -textvariable => \$chromo
					   )->pack( -side   => "top", 
						    -anchor => "ne", 
						    -pady   => 2);
    $frameSet{'STATUS_ONLY'}->LabEntry(-width     => 12,
				       -textvariable => \$status
				       )->pack( -side   => "top", 
						-anchor => "ne", 
						-padx   => 0, 
						-pady   => 2);
    
    $frameSet{'FEATURE_COUNT'}->LabEntry(-label     => 'Features:',
					 -labelPack => [ -side   => "left", 
							   -anchor => "w" ],
					 -width     => 4,
					 -textvariable => \$feature_count
					 )->pack( -side   => "top", 
						  -anchor => "ne", 
						  -padx   => 10, 
						  -pady   => 2);
    
    $frameSet{'TOP_PLUS'}->LabEntry(-label     => 'Description:',
				    -labelPack => [ -side   => "left", 
						    -anchor => "w" ],
				    -width  => 70,
				    -textvariable => \$desc,
				    -background => 'white'
				    )->pack( -side => "top", 
					     -anchor => "nw",
					     -fill   => 'x',
					     -expand => '1' , 
					     -pady   => 2 );
    
    
    $frameSet{'TOP_PLUS'}->LabEntry(-label     => '     DE line: ',
				    -labelPack => [ -side   => "left", 
						    -anchor => "w" ],
				    -width  => 65,
				    -textvariable => \$deLine,
				    -font   => 'fixed'
				    )->pack( -side => "top", 
					     -anchor => "nw",
					     -fill   => 'x',
					     -expand => '1'  , 
					     -pady   => 2);
    $frameSet{'TOP_PLUS'}->LabEntry(-label     => '    OS line: ',
				    -labelPack => [ -side   => "left", 
						    -anchor => "w" ],
				    -width  => 65,
				    -textvariable => \$osLine,
				    -font   => 'fixed'
				    )->pack( -side => "top", 
					     -anchor => "nw",
					     -fill   => 'x',
					     -expand => '1' , 
					     -pady   => 2 );
    
    $frameSet{'PROJECTS'} = $frameSet{'TOP_PLUS'}->Frame()->pack( -side => 'top',
								  -anchor => 'w',
								  -padx   => '0',
								  -pady   => '0'
								  ); 
    $frameSet{'MAGPI INFO'} = $frameSet{'PROJECTS'}->Frame()->pack( -side => 'right',
								    -anchor => 'e',
								    -padx   => '0',
								    -pady   => '0'
	); 
    $frameSet{'PROJECTS'}->LabEntry(-label     => ' MAGPI project: ',
				    -labelPack => [ -side   => "left", 
						    -anchor => "w" ],
				    -width  => 20,
				    -textvariable => \$magpiGroup,
				    -font   => 'fixed'
				    )->pack( -side => "top", 
					     -anchor => "nw",
					     -fill   => 'x',
					     -expand => '1' , 
					     -pady   => 2 );

    $button_project_info = $frameSet{'MAGPI INFO'}->Button( -text             => 'Show Project ACs',
							    -activeforeground => 'blue',
							    -command          => \&show_project_entries
	);
    # NB should use validateCommand on the LabEntry for MAGPI project to grey out this button 
    $button_project_info->pack( -side   => 'top',
				-anchor => 'ne',
				-padx   => '12',
				-pady   => '1',
				-expand => '1', 
				-fill   => 'x'
	);

}

sub text_message {
    $frameSet{'OUTPUT'} = $top->Frame()->pack( -pady => 5,
					       -expand => '1',
					       -padx   => '0',
					       -pady   => '0' );
    
    $text_message = $frameSet{'OUTPUT'}->Text( -height => 15, 
					       -width => 100, 
					       -background => 'white'
					       )->pack(-fill   => 'x',
						       -expand => '1');
    $text_message->tagConfigure( 'red',       -foreground => 'red' );
    $text_message->tagConfigure( 'darkgreen', -foreground => 'darkgreen' );
    $text_message->insert( 'end', "$news\n", 'darkgreen' );
}

sub export_report {
    my $option = $_[0];
    my ( $accession, $description );
    my @categoryList = ();
    
    my $sth_ena = $dbh_ena->prepare(
			    q{
				SELECT gs.primaryacc#, gs.descr
				    FROM cv_genome_category gc, genome_seq gs
				    WHERE upper ( decode ( gc.descr, 'mitochondrion', 'organelle',
							   'chloroplast', 'organelle',
							   'mitochondrial plasmid', 'organelle',
							   gc.descr ) ) = upper ( ? )
							   AND gs.category = gc.code
							   ORDER BY gs.descr }
			    );
    
    $text_message->delete( '1.0', 'end' );
    
    if ( $option eq 'selected' ) {
        my ($cat) = $category->curselection();
        unless ( defined $cat ) {
            $text_message->insert( 'end',
                                   "No category selected. Export cancelled.",
                                   'red' );
            return 0;
        }
        $categoryList[0] = $reverse_categoryHash{$cat};
    } elsif ( $option eq 'all' ) {
        @categoryList = keys %categoryHash;
    }
    foreach my $c ( @categoryList ) {
        my $file = $c;
        $file = "mito_plasmid" if $file eq "mitochondrial plasmid";
        open OUT, ">$report_dir/$file.rep"
	    || die "Can't write to $file.rep: $!";
	$sth_ena->execute($c) || show_error("Can't execute statement: $DBI::errstr");
	
        while ( ( $accession, $description ) = $sth_ena->fetchrow_array ) {
            print OUT $accession, '|', $description, "\n";
        }
	
        $sth_ena->finish;
        close OUT;
    }
    $text_message->delete( '1.0', 'end' );
    $text_message->insert( 'end', "Export finished.\n", 
			   'darkgreen' );
    return 1;
}

#sub publishPages {
#    $text_message->delete( '1.0', 'end' );
#    $text_message->insert( 'insert',
#			   "See your terminal window to publish\nNB Cannot run in background",
#			   "darkgreen" );
#    $text_message->update;
#    system ("/usr/bin/rsh web10-node1.ebi.ac.uk 'cd /ebi/web10/main/html/seqdb-dev/genomes;/ebi/www/main/bin/publish'");
#    $text_message->delete( '1.0', 'end' );
#    $text_message->insert( 'insert',
#			   "Genomes pages published" );
#    $text_message->update;
#    $publishMenuItem->configure(-state => 'disabled');
#}

sub call_getGenomes {
    $text_message->delete( '1.0', 'end');
    $text_message->insert( 'insert',
			   "Running getGenomes.pl for all categories. Please be patient.\n",
			   "darkgreen" );
    $text_message->update;
    system ("bsub -I /ebi/production/seqdb/embl/tools/curators/scripts/getGenomes.pl");
    $text_message->delete( '1.0', 'end');
    $text_message->insert( 'insert',
			   "getGenomes.pl is being run and should mail you the log once it publishes tha pages at\nhttp://evo-1.ebi.ac.uk/genomes\n"
			   ."Mail es-group\@ebi.ac.uk to ask for it to be copied to evo-1",
			   "darkgreen" );
    $text_message->update;
#    $publishMenuItem->configure(-state => 'normal');
    return 1;
}

