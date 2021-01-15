CREATE TABLE livelist_ddbj (
   primaryacc# VARCHAR2(15) NOT NULL,
   version NUMBER(5) NOT NULL
)
TABLESPACE enuca
/
GRANT select, insert, update, delete, alter on LIVELIST_DDBJ to EMBL_DEVELOPER;

CREATE TABLE livelist_ncbi (
   primaryacc# VARCHAR2(15) NOT NULL,
   version NUMBER(5) NOT NULL
)
TABLESPACE enuca
/
GRANT select, insert, update, delete, alter on LIVELIST_NCBI to EMBL_DEVELOPER;

CREATE TABLE livelist_missing (
   primaryacc# VARCHAR2(15) NOT NULL,
   dbcode VARCHAR2(5) NOT NULL,
   missing VARCHAR2(1) NOT NULL
)
TABLESPACE enuca
/
GRANT select, insert, update, delete, alter on LIVELIST_MISSING to EMBL_DEVELOPER;

ALTER TABLE livelist_missing
  ADD CONSTRAINT ck_livelist_missing$dbcode CHECK (dbcode IN ('D', 'G'));

CREATE TABLE livelist_zombie (
   primaryacc# VARCHAR2(15) NOT NULL,
   dbcode VARCHAR2(5) NOT NULL
)
TABLESPACE enuca
/
GRANT select, insert, update, delete, alter on LIVELIST_ZOMBIE to EMBL_DEVELOPER;

ALTER TABLE livelist_zombie
  ADD CONSTRAINT ck_livelist_zombie$dbcode CHECK (dbcode IN ('D', 'G'));

CREATE TABLE livelist_sequence_v (
   primaryacc# VARCHAR2(15) NOT NULL,
   dbcode VARCHAR2(5) NOT NULL,
   version_embl NUMBER(5) NOT NULL,
   version_collab NUMBER(5) NOT NULL
)
TABLESPACE enuca
/
GRANT select, insert, update, delete, alter on LIVELIST_SEQUENCE_V to EMBL_DEVELOPER;

ALTER TABLE livelist_sequence_v
  ADD CONSTRAINT ck_livelist_sequence_v$dbcode CHECK (dbcode IN ('D', 'G'));

