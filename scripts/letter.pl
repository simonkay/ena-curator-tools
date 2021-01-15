#!/ebi/production/seqdb/embl/tools/bin/perl -w
#
#  MODULE DESCRIPTION:
#
#  Sends a file to a list of email addresses. Note that the Mail command does
#  not seem to raise an error if an email address does not exist - you will
#  only receive a notification from the Mailer by email. 
#
#  MODIFICATION HISTORY:
#
#  29-SEP-1999 Nicole Redaschi
#
################################################################################

# handle command line.

@ARGV == 3 || die "\n USAGE: $0 <email_list> <letter> <subject>\n\n";
$email   = $ARGV[0];
$letter  = $ARGV[1];
$subject = $ARGV[2];

# loop over email list.

open ( IN, "< $email" ) || die "cannot open file $email: $!";
while ( <IN> ) {
  
  chomp;
  $mail = "Mail -s \"$subject\" $_ < $letter\n";
  $status = system ( $mail );
  $status && print "failed to send mail to $_";
}
close ( IN );
print "Data processed by $0 on ". ( scalar localtime ) . "\n";
