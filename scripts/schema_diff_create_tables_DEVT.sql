/* 
   script creates a copy of the dd tables user_objects, user_tab_columns and 
   user_constraints ( to run the script schema_diff.pl )
   COPY is used as CREATE TABLE ... AS ... cannot handle longs...
   15-DEC-1999  Carola Kanz
*/

drop table old_user_objects;
create table old_user_objects as ( select * from user_objects );

COPY FROM datalib/brownsoup@devt -
REPLACE OLD_USER_TAB_COLUMNS (TABLE_NAME, COLUMN_NAME, DATA_TYPE, DATA_LENGTH, -
NULLABLE, DATA_DEFAULT) USING  -
(SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, DATA_LENGTH, NULLABLE,  -
DATA_DEFAULT FROM USER_TAB_COLUMNS);

COPY FROM datalib/brownsoup@devt -
REPLACE OLD_USER_CONSTRAINTS (OWNER, CONSTRAINT_NAME, CONSTRAINT_TYPE, TABLE_NAME, -
R_OWNER, R_CONSTRAINT_NAME, DELETE_RULE, STATUS, LAST_CHANGE, SEARCH_CONDITION) USING -
(SELECT OWNER, CONSTRAINT_NAME, CONSTRAINT_TYPE, TABLE_NAME, R_OWNER, R_CONSTRAINT_NAME, -
NVL (DELETE_RULE,'-'), STATUS, LAST_CHANGE, SEARCH_CONDITION FROM USER_CONSTRAINTS);

exit;



