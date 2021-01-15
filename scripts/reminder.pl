#!/ebi/production/seqdb/embl/tools/perl-5.8.8/bin/perl
#
# Sends a message to update@ebi.ac.uk when a deadline is reached
# Deadlines and messages are stored in /ebi/production/seqdb/embl/data/reminder/reminder.lst
# as <date> <message>
#
# Runs weekly from datalib's crontab
#

use strict;
use warnings;
use Date::Manip;
use sendEmails;

use Mailer;
use Utils qw(my_open my_close readfile printfile);

my $exit_status = 0;
my $REMINDER_FILE = '/ebi/production/seqdb/embl/data/reminder/reminder.lst';
my $LAST_ACTION_FILE = '/ebi/production/seqdb/embl/data/reminder/last_action.date';
my $LOG_FILE = '/ebi/production/seqdb/embl/data/reminder/reminder_sent.log';

main();

sub main {

  my $last_action = readfile( $LAST_ACTION_FILE );
  my $last_action_date = ParseDateString( $last_action );
  my $in_fh = my_open( $REMINDER_FILE );
  my $log_fh = my_open( ">>$LOG_FILE" );
  print( $log_fh "---\n". scalar(localtime()) ."\n" );

  my $now = ParseDateString( "today" );

  while ( my $line = <$in_fh> ) {
      if ($line =~ /^\s*$/){
	  next;
      }
    my ($date) = $line =~ m/^(\S+)\s/;
    unless ( defined($date) ) {
      chomp( $line );
      print( "ERROR: cannot find date in '$line'\n" );
      exit($exit_status);
    }

    my $reminder_date = ParseDateString( $date );

    # my $ignore = Date_Cmp( $last_action, $reminder_date );
    # uncomment this to make it send messages only once
    my $ignore = 0;
    if ( $ignore > 0 ) {# We already dealt with this

      next;

    } else {

      my $due = Date_Cmp( $now, $reminder_date );
      if ( $due > 0 ) {
        # date is earlier
	send_email_with_string_msg('update.email', 'datalib_do_not_reply@ebi.ac.uk', 'Action reminder', $line);

        print( $log_fh "    $line" );
      }
    }
  }

  printfile( $LAST_ACTION_FILE, $now );
  my_close( $in_fh );
  my_close( $log_fh );
}

exit($exit_status);
