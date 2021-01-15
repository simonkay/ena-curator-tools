#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/create_tax_consult_letter.pl,v 1.21 2011/11/29 16:33:38 xin Exp $
#
#  (C) EBI 2000
#
#  MODULE DESCRIPTION:
#
#  Concatenates all *.tax files in the given directory ( while deleting DE and FT
#  headers outside the flatfile parts ) and gives a summary of all unclassified
#  organism names ( and accno's ) in a fragment letter to ncbi at top of the file.
#
#  MODIFICATION HISTORY:
#
#  22-MAR-2000  Carola Kanz        Created.
#===============================================================================

use strict;
use DirHandle;
use File::Basename;
use DBI;
use dbi_utils;
use SeqDBUtils;

#-------------------------------------------------------------------------------
# handle command line.
#-------------------------------------------------------------------------------

my $usage = "\n PURPOSE: Writes 'consult.tax' file for all *.tax files in the DS directory\n\n".
            " USAGE:   $0\n".
	    "          <user/password\@instance> [-ds<ds>] [-test] [-h]\n\n".
            "   <user/password\@instance>\n".
	    "                   where <user/password> is taken automatically from\n".
	    "                   current unix session\n".
	    "                   where <\@instance> is either \@enapro or \@devt\n".
	    "   -ds<ds>         runs in the current DS directory by default, or in\n".
	    "                   the DS directory given as the parameter <ds>\n".
	    "   -test           checks for test vs. production settings\n".
            "   -h              shows this help text\n\n";

( @ARGV >= 1 && @ARGV <= 3 ) || die $usage;
( $ARGV[0] !~ /^-h/i ) || die $usage;

hide ( 1 );

my $login = $ARGV[0];
my $ds    = 0;
my $test  = 0;

for ( my $i = 1; $i < @ARGV; ++$i )
{
   if ( $ARGV[$i] =~ /^\-ds(.+)$/ )
   {
      $ds = $1;
      ( $ds =~ /\D/ ) && die "ERROR: invalid DS number: $ds\n";
   }
   elsif ( $ARGV[$i] eq "-test" )
   {   
      $test = 1;
   }
   else
   {
      die ( $usage );
   }
}

die if ( check_environment ( $test, $login ) == 0 );

#-------------------------------------------------------------------------------
# get the DS number from the current working directory, if it was not specified
#-------------------------------------------------------------------------------

if ( $ds == 0 )
{
   $ds = get_ds ( $test ) || die;
}

#-------------------------------------------------------------------------------
# set the full DS path
#-------------------------------------------------------------------------------

my $dir = ( $test ) ? $ENV{"DS_TEST"} : $ENV{"DS"};
( defined $dir ) || die ( "ERROR: environment is not set\n" );

$dir = $dir."/".$ds;

#-------------------------------------------------------------------------------
# rename existing consult.tax file
#-------------------------------------------------------------------------------

my $consult = $dir."/consult.tax";
if ( -f $consult )
{
   my $timestamp = get_mtime ( $consult, "YYYY-MM-DD_HH24:MI:SS" );
   my $consult_renamed = $consult."_".$timestamp;
   rename ( $consult, $consult_renamed ) || die "ERROR: cannot rename file $consult to $consult_renamed: $!";
   chmod ( 0660, $consult_renamed );
}

#-------------------------------------------------------------------------------
# loop over all .tax files in the directory:create_tax_consult_letter_new.pl
# - "beautify"
# - extract organism information
# - append to tax.tmp file
#-------------------------------------------------------------------------------

my $dh = DirHandle->new ( $dir ) || die ( "ERROR: cannot open directory: $!\n" );
my @files = sort grep { -f } map { "$dir/$_" } grep { /\.tax$/ } $dh->read();
@files || die ( "ERROR: there are no files to be processed.\n" );

open ( OUT, ">$dir/tax.tmp" ) || die "ERROR: cannot open file $dir/tax.tmp: $!";
print OUT "\n\n";

my $count_entries = 0;
my %h_organisms = (); # we use the hash+array to get a unique list of
my @a_organisms = (); # organisms in the order they appear in the files
my $taxfile;
my $is_classified = 1;

foreach $taxfile ( @files ) 
{
  $count_entries++;

  print "*** $taxfile\n";
 
  open ( IN, $taxfile ) || die "ERROR: cannot open file $taxfile: $!";

  my $del_header = 0;
  while ( <IN> ) 
  {
     $del_header = 0 if ( $del_header == 1 && /^$/ );

     if ( $del_header == 0 ) 
     {
	print OUT $_;
     }
     else
     {
	# delete DE and FT header
	print OUT substr ( $_, 5, length($_)-5 );
     }

     if ( /^Source Feature Qualifiers/ || /^Description/ ) 
     {
	$del_header = 1;
     }

     # there may be more than one organism listed after this line!
     if ( /^Unclassified Organism\(s\) referenced in (.*):/  || /^Classified Organism[(]s[)] referenced in (.*):/  ) 
     {
        if ($_ =~ /^Unclassified/)
	{
	    $is_classified = 0;
	}
		    
	while ( <IN> )
	{
	   last if /^$/;
	   if ( ! defined $h_organisms { $_ } )
	   {
	      $h_organisms { $_ } = 1;
	      push ( @a_organisms, $_ );
	   }
	}
     }
  }
  print OUT "\n********************************************************************************\n\n";
  close ( IN )  || die "ERROR: cannot close file $taxfile: $!";
}

print "\nConsult created:\n";
print "*** $dir/consult.tax\n"; 
#-------------------------------------------------------------------------------
# print consult letter
#-------------------------------------------------------------------------------

open ( SUM, ">$dir/tax.sum" ) || die "ERROR: cannot open file $dir/tax.sum: $!";

my $count_organisms = @a_organisms;
printf SUM "Consult n = %d - DS %s\n", $count_organisms, $ds;
print SUM "taxonomy\@ncbi.nlm.nih.gov\n\n";

foreach my $organism ( @a_organisms ) 
{
   print SUM "$organism";
}

print  SUM "\n\nDear Taxonomy Colleagues,\n\n";

if ($is_classified == 0)
{
    printf SUM "Please enter the above %d organism%s from %d entr%s.\n\n",
       $count_organisms, ( $count_organisms == 1 ) ? "" : "s",
       $count_entries, ( $count_entries == 1 ) ? "y" : "ies"; 
}
else 
{
    printf SUM "Please examine the above %d organism%s from %d entr%s.\n\n",
       $count_organisms, ( $count_organisms == 1 ) ? "" : "s",
       $count_entries, ( $count_entries == 1 ) ? "y" : "ies"; 
}
   
# get submitter information

my $dbh = dbi_ora_connect ( $login );

my ( $surname, $firstname, $email, $tel ) = 
    dbi_getrow ( $dbh,
                "select nvl (surname, ' '),
                        nvl (first_name, ' '),
                        nvl (email_address, '-'),
                        nvl (tel_no, '-')
                   from v_submission_details
                  where idno = $ds" );

dbi_rollback ( $dbh );
dbi_logoff ( $dbh );

# check if submittor info found ( surname is mandatory )
die "ERROR: DS does not exist in database - no submittor information available!\n"
  if ( !defined $surname ); 

print SUM "In case you need to contact the submitter:\n\n"
    .     "Submitter: $surname"
    .     (( $firstname ne " ")?", $firstname":"") . "\n"
    .     "E-Mail: $email\n"
    .     "Phone: $tel\n"
    .     "Thanks and regards,\n\n"
    .     "EMBL-Bank, The European Nucleotide Archive\n\n";

# close files

close ( SUM ) || die "ERROR: cannot close file $dir/tax.sum: $!";
close ( OUT ) || die "ERROR: cannot close file $dir/tax.tmp: $!";

# concatenate summary and .tax files.

sys ( "cat $dir/tax.sum $dir/tax.tmp > $consult", __LINE__ );
chmod ( 0660, $consult );

# delete temporary and *.tax files

unlink ( $dir."/tax.tmp" ) || print "cannot delete $dir/tax.tmp: $!\n";
unlink ( $dir."/tax.sum" ) || print "cannot delete $dir/tax.sum: $!\n";
unlink ( @files ) == @files || print "could not unlink all of @files: $!\n";
