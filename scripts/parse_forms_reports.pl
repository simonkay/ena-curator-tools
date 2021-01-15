#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/parse_forms_reports.pl,v 1.2 2006/11/22 15:49:12 lin Exp $
#
#  (C) EBI 2001
#
#  DESCRIPTION:
#
#  Parses "object list reports" from Oracle*Forms to create a more user-friendly
#  output. See /ebi/services/tools/forms/doc/README.
#
#  MODIFICATION HISTORY:
#
#  19-MAR-2001 Nicole Redaschi     Created
#
#===============================================================================

use strict;
use SeqDBUtils;

my $file = $ARGV[0];

open ( FORM, "< $file" ) || die "cannot open file $file: $!";
while ( <FORM> )
{
   last if ( /^ [*-] Name/ );
}

my $line = $_;
( $line ) = ( $line =~ /^ [*-] Name *(.*)/ );
print "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\n";
print $line, "\n";
print "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\n";

while ( <FORM> )
{
   last if ( /^ [*-] Triggers/ );
}

# Form-level triggers
while ( <FORM> )
{
   last if ( /^ [*-] Alerts/ );
   last if ( /^ [*-] Blocks/ );

   if ( /^   [*-] Name/ )
   {
      my $line = $_;
      ( $line ) = ( $line =~ /^   [*-] Name *(.*)/ );
      print "\n================================================================================\n";
      print $line, "\n";
      print "================================================================================\n";
   }
   if ( /^   [*-] Trigger Text/ )
   {
      while ( <FORM> )
      {
	 last if ( /Fire in Enter-Query Mode/ );
	 print $_;
      }
   }
}

if ( /^ [*-] Alerts/ )
{
   while ( <FORM> )
   {
      last if ( /^ [*-] Blocks/ );
   }
}

# Blocks
while ( <FORM> )
{
   if ( /^   [*-] Name/ )
   {
      my $line = $_;
      ( $line ) = ( $line =~ /^   [*-] Name *(.*)/ );
      print "\n\n********************************************************************************\n";
      print "** $line";
      while ( <FORM> )
      {
	 if ( /^   [*-] Query Data Source Name/ )
	 {
	    my $line = $_;
	    ( $line ) = ( $line =~ /^   [*-] Query Data Source Name *(.*)/ );
	    if ( $line ne '' )
	    {
	       printf " based on %s", $line;
	    }
	 }
	 last if ( /^   [*-] Triggers/ );
      }
      
      print "\n********************************************************************************\n";

      # Block-level triggers
      while ( <FORM> )
      {      
	 last if ( /^   [*-] Items/ );

	 if ( /^     [*-] Name/ )
	 {
	    my $line = $_;
	    ( $line ) = ( $line =~ /^     [*-] Name *(.*)/ );
	    print "\n================================================================================\n";
	    print $line, "\n";
	    print "================================================================================\n";
	 }
	 if ( /^     [*-] Trigger Text/ )
	 {
	    while ( <FORM> )
	    {
	       last if ( /Fire in Enter-Query Mode/ );
	       print $_;
	    }
	 }
      }

      # Block items
      while ( <FORM> )
      {
	 last if ( /^   [*-] Relations/ );

	 # Item
	 if ( /^     [*-] Name/ )
	 {
	    my $line = $_;
	    ( $line ) = ( $line =~ /^     [*-] Name *(.*)/ );
	    print "\n--------------------------------------------------------------------------------\n";
	    printf "++ %-20s", $line;
	 }
	 elsif ( /^     [*-] Data Type/ )
	 {
	    my $line = $_;
	    ( $line ) = ( $line =~ /^     [*-] Data Type *(.*)/ );
	    printf "%s", $line;
	 }
	 elsif ( /^     [*-] Maximum Length/ )
	 {
	    my $line = $_;
	    ( $line ) = ( $line =~ /^     [*-] Maximum Length *(.*)/ );
	    printf "(%d)", $line;
	 }
	 elsif ( /^     [*-] Database Item/ )
	 {
	    my $line = $_;
	    ( $line ) = ( $line =~ /^     [*-] Database Item *(.*)/ );
	    if ( $line eq "Yes" )
	    {
	       printf "   [db]";
	    }
	 }

	 # Triggers
	 if ( /^       [*-] Name/ )
	 {
	    my $line = $_;
	    ( $line ) = ( $line =~ /^       [*-] Name *(.*)/ );
	    print "\n-- =============================================================================\n";
	    print "-- ", $line, "\n";
	    print "-- =============================================================================\n";
	 }
	 if ( /^       [*-] Trigger Text/ )
	 {
	    while ( <FORM> )
	    {
	       last if ( /Fire in Enter-Query Mode/ );
	       print "   ", $_;
	    }
	 }
      }
      last if ( /^ [*-] Canvases/ );
   }
   last if ( /^ [*-] Canvases/ );
}


close ( FORM ) || die "cannot close file $file: $!";
