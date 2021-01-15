#!/ebi/production/seqdb/embl/tools/bin/perl -w

##########################################################################
# copies all files in VMS DS dir into current UNIX dir
# and then applies a dose of parsem before sending back relevant files!
# Pascal Hingamp June 1999
##########################################################################

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#ftp gets a list of files and deposits them in the current directory
my ($ds) = $ARGV[0];
$ds =~ /^\d{5}$/ or die "please provide a DS number!\nusage: vmsparsem <DS#>\n";
print "Trying to ftp all files from DS $ds...\n";
system ('mkdir vmsparsem_temp');
#system ('cd vmsparsem_temp');
open (MYIN , '|ftp mars')  or die "Couldn't start ftp to mars: $!\n";
print MYIN "prompt\n";
print MYIN "cd DS:[$ds]\n";
print MYIN "lcd vmsparsem_temp\n";
print MYIN "mget *.form\n";
print MYIN "bye\n";
close MYIN;
system ('rm ./vmsparsem_temp/*.form.*');
opendir DIR, './vmsparsem_temp';
@files = readdir DIR;
closedir DIR;
@files = grep /\.form/i, @files;
print "\nFTPed @files\n\n";
system ('cd vmsparsem_temp; /ebi/production/seqdb/embl/tools/curators/scripts/parsem.pl');
open (MYIN , '|ftp mars')  or die "Couldn't start ftp to mars: $!\n";
print MYIN "prompt\n";
print MYIN "cd DS:[$ds]\n";
print MYIN "lcd vmsparsem_temp\n";
#print MYIN "put email_parser.cmt\n";## I should delete that after migration
print MYIN "mput *.parsercmt\n";
print MYIN "mput *.report\n";
print MYIN "mput *.sub\n";
print MYIN "mput *.info\n";
print MYIN "bye\n";
close MYIN;
system ('rm ./vmsparsem_temp/*.*');
#system ('cd ..');
rmdir './vmsparsem_temp';
print "\nEmail forms parsed to flat files and sent over to VMS. Finished!\n";
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
