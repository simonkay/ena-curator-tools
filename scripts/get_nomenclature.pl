#!/ebi/production/seqdb/embl/tools/bin/perl -w
# $Header: /ebi/cvs/seqdb/seqdb/tools/curators/scripts/get_nomenclature.pl,v 1.11 2007/09/20 15:22:43 lin Exp $

#=============================================================================
# The script is used to get human gene nomenclature.txt file from HUGO's ftp 
# site. It's run as a crontab job every month.
#	
# MODIFICATION HISTORY:
#
# 18-NOV-2002   Quan Lin   created
# 17-AUG-2005   Quan Lin   ftp ceased to exist. changed to a new download page
# 23-NOV-2006   Quan Lin   changed output directory
#=============================================================================

use strict;
use LWP::Simple;

my $url = "http://tinyurl.com/2jv4sa";

# the above is the short form for this:http://www.genenames.org/cgi-bin/hgnc_downloads.cgi?title=Genew%20output%20data;hgnc_dbtag=on;col=gd_app_sym;col=gd_app_name;col=gd_pub_chrom_map;col=gd_pubmed_ids;status=Approved;status=Entry%20Withdrawn;status_opt=3;=on;where=;order_by=gd_app_sym_sort;limit=;format=text;submit=submit;.cgifields=;.cgifields=chr;.cgifields=status;.cgifields=hgnc_dbtag">here</a>

my $data_dir = "/ebi/production/seqdb/embl/tools/curators/data";
my $temp_file = "$data_dir/nomenclature.temp";
my $file = "$data_dir/nomenclature.txt";

getstore($url, $temp_file);

if (-s $temp_file){

    system ("mv $temp_file $file");
}
else {

    mail_error ("\nCouldn't mirror nomenclature.txt");
}  

#-------------------------------------------------------------------------
# list of subs
#-------------------------------------------------------------------------
    
sub mail_error{
# send an e-mail to dbgroup and then dies
# Should be more secure than making a direct system call to Mail

my $messg = shift;

my ($to);
  
$to = 'lin@ebi.ac.uk';

open(SENDMAIL, "|/usr/sbin/sendmail -oi -t") # -oi -> '.' is not end of
                                             # -t  -> use header for
or die "Can't fork for sendmail: $!\n";

print (SENDMAIL "To: $to\n");
print (SENDMAIL "Subject: $0 @ARGV error!\n\n"); # $0 is the program
print (SENDMAIL $messg);
print (SENDMAIL "\n\n$!\n");

close(SENDMAIL)
   or warn "sendmail didn't close nicely\n";
die ($messg);

}  
    



