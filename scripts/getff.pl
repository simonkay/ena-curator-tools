#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/getff.pl,v 1.35 2020/07/14 17:29:54 suranj Exp $
#
#  (C) EBI 2001
#
#  MODULE DESCRIPTION:
#
#  Unloads one entry or all entries linked to a DS.
#
#  Reports unclassified organisms when used with -tax flag and creates
#  <AC>.tax files for create_tax_consult_letter.pl.
#
#  MODIFICATION HISTORY:
#
#  03-SEP-2001 Nicole Redaschi     Created.
#  19-SEP-2001 Nicole Redaschi     Added -private_comments.
#  22-SEP-2001 Nicole Redaschi     Ported C++ code for creation of *.tax files
#                                  to this script.
#                                  added option -test.
#  10-OCT-2001 Nicole Redaschi     moved reinitialization of variables to fix bug.
#  29-NOV-2001 Carola Kanz         /organism can consist of more than one line
#  13-FEB-2003 Quan Lin            fixed a bug for checking unclassified organism.
#  21-OCT-2003 Quan Lin            added 2 flags. -every flag unloadentries into
#                                  individual <AC>.dat files. -taxall flag creates <AC>.tax
#                                  for all entries regardless whether they are classified or not.
#  03-MAY-2006 Carola Kanz         replaced unload/getff parameters -c/-d by -non_public
#  19-JUN-2006 Carola Kanz         unload/getff still use old ID line format
#  13-DEC-2006 Quan Lin            adapted to the new 6 entry status 
#  15-MAY-2007 Quan Lin            added two flags for getff and unload removed -private_comment 
#                                  option when working with devt, -test is no longer needed
#  07-SEP-2007 Quan Lin            use bind_param in sql
#
#  17-NOV-2010 Nima Pakseresht    add an option to unload a range of entries from first acc_num to second
#===============================================================================================


use strict;
use DBI;
use dbi_utils;
use SeqDBUtils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Unload one entry,all entries linked to a DS, or a range of entries.\n".
            "          Reports unclassified organisms when used with -tax flag and\n". 
            "          creates <AC>.tax files for create_tax_consult_letter.pl.\n".
            "          Creates <AC>.tax files for all entries when used with -taxall\n".
            "          regardless whether the organisms are classified or not.\n\n".
            " USAGE:   $0\n".
	    "          <user/password\@instance> [-ds<ds>|-a<ac|id>] [-every] [-tax] [-taxall]\n".
            "          [-nowrap] [-test] [-usage]\n\n".
            "   <user/password\@instance>\n".
	    "                         where <user/password> is taken automatically from\n".
	    "                         current unix session\n".
	    "                         where <\@instance> is either \@enapro or \@devt\n\n".
	    "   -ds<ds>               runs in the current DS directory by default, or in\n".
	    "                         the DS directory given as the parameter <ds>\n".
            "   -a<ac|id> or <ac-ac>  where <ac|id> is any accession number or entryname\n".
            "                         and <ac-ac> is a list of entries from first ac to second ac\n".
            "   -every                unloads entries into individual <AC>.dat files.\n".
            "   -tax                  reports unclassified organisms (files are removed!)\n".
            "   -taxall               creates <AC>.tax files for all entries.\n".
            "   -nowrap               does not wrap the long lines ((except that comments and sequences).\n".
	    "   -test                 checks for test vs. production settings\n".
            "   -usage                shows this help text\n\n";

( @ARGV >= 1 && @ARGV <= 7 ) || die $usage;
if ( $ARGV[0] =~ /^-((h(elp)?)|(usage))/i ){
    die $usage;
}

hide ( 1 );

my $login = $ARGV[0];
my $entry = "";
my $test  = 0;
my $ds    = 0;
my $tax   = 0;
my $star_line = "-ac_star_line";
my $nowrap = ""; 
my $taxall = 0; # flag to produce .tax for both classified and unclassfied
my $every = 0; # flag to unload entries into separet AC.dat files instead of DS.dat for all entries
my @file_names;

for ( my $i = 1; $i < @ARGV; ++$i )
{
   if ( $ARGV[$i] =~ /^\-a(.+)$/ )
   {
       $entry = uc ( $1 );
   }
   elsif ( $ARGV[$i] =~ /^\-ds(.+)$/ )
   {
      $ds = $1;
      ( $ds =~ /\D/ ) && die "ERROR: invalid DS number: $ds\n";
   }
   elsif ( $ARGV[$i] eq "-tax" )
   {
      $tax = 1;
   }
   elsif ( $ARGV[$i] eq "-taxall" )
   {
       $taxall = 1;
   }
   elsif ($ARGV[$i] eq "-every" )
   {
       $every = 1;
   }
   elsif ( $ARGV[$i] eq "-test" )
   {   
      $test = 1;
   }
   elsif ($ARGV[$i] eq "-nowrap"){
       $nowrap = $ARGV[$i];
   }
   else
   {
      die ( $usage );
   }
}

$login = uc ($login);
if ($login =~ /\/\@DEVT/){

      $test = 1;
}
die if ( check_environment ( $test, $login ) == 0 );

#-------------------------------------------------------------------------------
# get the DS number from the current working directory, if it was not specified
#-------------------------------------------------------------------------------

if ( $entry eq "" && $ds == 0)
{
   $ds = get_ds ( $test ) || die;
}


#-------------------------------------------------------------------------------
# connect to database
# we don't need a db connection for a single entry, but 
# 1. it makes the code easier
# 2. curators want to see "Connected..." message
#-------------------------------------------------------------------------------

my $dbh = dbi_ora_connect ( $login);

dbi_do ( $dbh, "alter session set nls_date_format='DD-MON-YYYY'" );

#-------------------------------------------------------------------------------
# filenames: 
# - getff produces <ac|id>.dat, which we need to rename to <AC|ID>.dat
# - unload produces .dat file
#-------------------------------------------------------------------------------

my $tmp = '';
my $dat = '';

#-------------------------------------------------------------------------------
# case 1: unload a single entry
#-------------------------------------------------------------------------------
if ( $entry ne "" )
{  
   
   if($entry =~ /(.+)\-(.+)/)
   {
     my $start=uc($1);
     my $end=uc($2);
    
     my $sth=$dbh->prepare("SELECT primaryacc# FROM dbentry where primaryacc# between ? and ?");
     $sth->execute($start,$end);
     my @accNumbers;
     while ( (my $acc) = $sth->fetchrow_array() )
      {
       push(@accNumbers,$acc);
      }

     my $file="acc.del";
     open(OUT,"> $file") || die "cannot open file:$file";
     foreach(@accNumbers)
      {
       print OUT $_."\n";
      }

     my $outFile=$start."\-".$end.".dat";
     sys("unload $login $file -non_public $star_line $nowrap -o $outFile",__LINE__) ;
     unlink ($file) || warn "cannot remove file:$file";

   }
   else
   {
     sys ( "javagetff $login $entry -non_public $star_line $nowrap", __LINE__ );
     $tmp = lc ( $entry ).".dat";
     $dat = uc ( $entry ).".dat";
     rename ( $tmp, $dat ) || die "cannot rename file $tmp to $dat: $!";
	   chmod ( 0660, $dat );
   } 
}
#-------------------------------------------------------------------------------
# case 2: unload all entries linked to DS either as AC.dat files or ds.dat
#-------------------------------------------------------------------------------
else
{
   # retrieve all accession numbers linked to DS from db.
   my $sth = $dbh->prepare ("SELECT acc_no FROM accession_details WHERE idno = ? ORDER BY acc_no");
   $sth->execute($ds);
   my @accnos;

   while( my $ac = $sth->fetchrow_array()){

       push (@accnos, $ac);   
   }
 
   if ( ! @accnos )
   {
      bail ( "No entries linked to DS $ds", $dbh );
   }

  #  write list file for unload.
   my $lis = $ds.".ac";
   open ( OUT, "> $lis" ) || die "cannot open file $lis: $!";
   foreach my $acc ( @accnos )
   {
      print OUT $acc, "\n";
   }
   close ( OUT ) || die "cannot close file $lis: $!"; 

   # unload entries.

   if ( $every == 1 ) # unload all entries to individual AC.dat files
   {
       foreach my $ac_no (@accnos)
       {
           sys ( "javagetff $login $ac_no -non_public $star_line $nowrap", __LINE__ );
	   $tmp = lc ( $ac_no ).".dat";
	   $dat = uc ( $ac_no ).".dat"; 
	   push (@file_names, $dat);
           rename ( $tmp, $dat ) || die "cannot rename file $tmp to $dat: $!";
	   chmod ( 0660, $dat );  
       }
       
   }
   else  # unload all entries to one ds.dat file
   {
         
     sys ( "unload $login $lis -non_public $star_line $nowrap", __LINE__ );       
     $dat = "$ds.dat";
     chmod ( 0660, $dat );
   }

   unlink ( $lis ) || warn "cannot remove file $lis: $!";
}

#-------------------------------------------------------------------------------
# case A: unloading entry/ies: exit here
#-------------------------------------------------------------------------------
if ( ! $tax and !$taxall )
{
    if ($every == 1) 
    {   
	print STDERR "Created the following files:\n";

	foreach my $file (@file_names)
	{
	    print STDERR "$file\n";
	}
    }
    else
    {
	print STDERR "\nCreated file $dat\n\n";
    }

   # logout from database
   dbi_rollback ( $dbh );
   dbi_logoff ( $dbh ); 
      
   exit;
}

#-------------------------------------------------------------------------------
# case B: taxonomy consult: check unloaded entry/ies for unclassified organisms
#-------------------------------------------------------------------------------

my $unclassified = 0;
my $doneline = 0;
my $ac  = "";
my $os  = "";
my $status = "";
my $tmp_file = "$dat.tmp";
my $tax_file = '';
my $taxid = 0;

open ( IN, "< $dat" ) || die "cannot open file $dat: $!"; 
while ( <IN> ) {    
    # start of entry: open tmp file
    if ( /^ID   / ) {
	open ( TMP, "> $tmp_file" ) || die "cannot open file $tmp_file: $!"; 
    }
    # get accession number
    # (beware, there can be multiple AC-lines, we only want the first one!)
    elsif ( /^AC   ([A-Z0-9]+)/ && $ac eq "" ) {
	$ac = $1;
    } elsif ( /^ST \* (.*)$/ ) {
	$status = $1;
    }
    # get organism
    elsif ( /^OS   (.*)$/ ) {
	$os = $1;
    }
    # check whether organism is unclassified
    elsif ( /^FT                   \/db_xref=\"taxon:(\-\d+)\"/ ) {
	$taxid = $1;
    }
    # end of entry: close tmp file and either remove it or create <AC>.tax file
    elsif ( /^\/\// ) {
	print TMP $_;
	close ( TMP ) || die "cannot close file $tmp_file: $!";
	if ( ($taxid < 0) || ($taxall == 1) ) {
	    if ( $doneline == 0 ) {
		print "\n--------------------------------------------------------------------------------\n";
		$doneline = 1;
	    }
	    if ($status eq "cancelled") {
		printf "NB unclassified in cancelled entry: %-12s \"%s\"\n", $ac, $os;
	    } else {
		$unclassified++;
		printf "unclassified in: %-12s \"%s\"\n", $ac, $os;
		create_tax_file ( $tmp_file, $ac.".tax", $dbh);
	    }
	}
	unlink ( $tmp_file ) || die "cannot remove file $tmp_file: $!";
	
	$status = $ac = $tax_file = $os = ""; # reinitialize variables!
	$taxid = 0;
	next; # because print at end of block would fail...
    }
    print TMP $_;
}
close ( IN ) || die "cannot close file $dat: $!"; 
unlink ( $dat ) || warn "cannot remove file $dat: $!";


if ( ! $unclassified and !$taxall )
{
   print "\nOK: All entries are classified!\n\n";
}
elsif ($taxall == 1)
{
    print "--------------------------------------------------------------------------------";
    printf "\n<AC>.tax files created for all entries.\n";
    print "--------------------------------------------------------------------------------\n";
}
else
{
   print "--------------------------------------------------------------------------------\n";
   printf "\nWARNING: found $unclassified unclassified entr%s - please check STATUS\n\n",
   ( $unclassified == 1 ) ? "y" : "ies";
}


# logout from database
dbi_rollback ( $dbh );
dbi_logoff ( $dbh ); 


#===============================================================================
# subroutines 
#===============================================================================

sub create_tax_file
{
   my ( $tmp, $tax, $dbh ) = @_;
   my $ac = uc ( $tax );
   $ac =~ s/.TAX//;

   open ( TAX, "> $tax" ) || die "cannot open file $tax: $!";
   print TAX "Entry information for $ac\n\n";

   my $sth = $dbh->prepare ("SELECT c.status, d.hold_date
                               FROM dbentry d, cv_status c
                              WHERE d.statusid = c.statusid
                                AND d.primaryacc# = ?");

   $sth->execute($ac);
   my ($status, $h_date)  = $sth->fetchrow_array();
   
   my $conf = 'N';
        
   if ( ($status eq 'draft' and $h_date) || $status eq 'private' || $status eq 'cancelled' 
               || $status eq 'killed'){

       $conf = 'Y';
   }
       
   if ($conf eq 'Y')
   {
      print TAX "--------------------------------------\n";
      print TAX "- C  O  N  F  I  D  E  N  T  I  A  L -\n";
      print TAX "--------------------------------------\n";
      print TAX "Full entry cannot be sent to NCBI for Acc#: $ac\n\n";
   }

   if (!$h_date){
       $h_date = '';
   }

   print TAX "Dataclass: $status \n\n";

   my @organisms   = ();
   my $source      = 0;
   my $sources     = '';
   my $citations   = '';
   my $description = '';
   my $in_org = 0;        # /organism might by more than one line
   my $xorganism = '';    # to concat organism if more than one line
   my $classifide = 1;

   open ( TMP, "< $tmp" ) || die "cannot open file $tmp: $!";
   while ( <TMP> )
   {
      
      if ( $in_org ) {
        # organism consists of more than one line
        /^FT\s+(.+)(.)/;
        $xorganism .= " $1";
        if ( $2 eq '"' ) {              # " this was the last organism line
	  push @organisms, $xorganism;
	  $in_org = 0;
	  $xorganism = '';
	}
	else {  
	  $xorganism .= $2; 
	}
      }
      elsif ( /^OC   unclassified\./)
      {
	 $classifide = 0;
      }
      elsif ( /^DE   / )
      {
	 $description .= $_;
      }
      elsif ( /^RN   / )
      {
	 my $keep = '';
	 my $submissionref = 0;
	 while ( <TMP> )
	 {
	    if ( /^XX/ )
	    {
	       if ( $submissionref == 0 )
	       {
		  $citations .= $keep."\n";
	       }
	       last;
	    }
	    elsif ( /^(R[AT]{1}   )/ )
	    {
	       $_ =~ s/$1//;
	       $keep .= $_;
	    }
	    elsif ( /^RL   Submitted .* to the EMBL\/GenBank\/DDBJ databases/ )
	    {
	       $submissionref = 1;
	    }	    
	 }
      }
      elsif ( /^(RT   )/ )
      {
      } 
      elsif ( /^FT   source/ )
      {
	 $source = 1;
      }
      elsif ( /^FT   \S+/ || /^XX$/ )
      {
	 $source = 0;
      }
      if ( $source )
      {
	 $sources .= $_;
	 if ( /^FT {19}\/organism="(.+)(.)/ )               # "
	 {
	   if ( $2 eq '"' ) {   # " organism consists only of one line
	     push @organisms, $1;
	   }
	   else {
	     $xorganism = "$1$2";
	     $in_org = 1;
	   }
	 }
      }	    
   }
   close ( TMP ) || die "cannot close file $tmp: $!";

   # print all /organism
      
   if ($classifide == 0)
   {
       print TAX "Unclassified Organism(s) referenced in $ac:\n";
   }
   elsif ($classifide == 1)
   {
       print TAX "Classified Organism(s) referenced in $ac:\n";
   }

   foreach my $organism ( @organisms )
   {
      print TAX $organism, "\n";
   }

   # print all source features
   print TAX "\nSource Feature Qualifiers:\n$sources";

   # print all citations without lineheader
   print TAX "\nCitations:\n$citations";

   # print description line
   print TAX "Description:\n$description\n\n";

   # print flatfile, if entry is not confidential
   if ( $conf eq 'N' )
   {
      open ( TMP, "< $tmp" ) || die "cannot open file $tmp: $!";
      while ( <TMP> )
      {
	 print TAX $_;
      }
      close ( TMP ) || die "cannot close file $tmp: $!";
   }

   close ( TAX ) || die "cannot close file $tax: $!";
   chmod ( 0660, $tax );
}
