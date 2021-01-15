#! /ebi/production/seqdb/embl/tools/bin/perl -w
use strict;
use RevDB;
use SeqDBUtils2;

my $rev_db = RevDB->new('rev_select/mountain@erdpro');
my $dir = $ENV{'PWD'}."/temporary";
mkdir $dir;
foreach my $identifier (@ARGV) {
    my $ac      = $identifier;
    my $version = 0;
    if ($ac =~ s/\.(\d*)$//){
	$version = $1;
    }
    print "Retrieved "
	. SeqDBUtils2::grabEntry($rev_db,$dir,0,$ac,$version)
	. "\n";
}
$rev_db->disconnect();
exit;
