SELECT to_char (sysdate, 'DD-MON-YYYY HH24:MI:SS') from dual;

exec clean_up_table.clean_up_journalarticle;
exec clean_up_table.clean_up_accepted;
exec clean_up_table.clean_up_cv_journal;
exec clean_up_table.clean_up_book;
exec clean_up_table.clean_up_thesis;
exec clean_up_table.clean_up_unpublished;
exec clean_up_table.clean_up_patent;
exec clean_up_table.clean_up_pubauthor;
exec clean_up_table.clean_up_person;

SELECT to_char (sysdate, 'DD-MON-YYYY HH24:MI:SS') from dual;

EXIT;
