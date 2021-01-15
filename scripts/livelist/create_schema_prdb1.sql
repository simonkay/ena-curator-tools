CREATE TABLE livelist_ddbj (
   primaryacc# VARCHAR2(15) NOT NULL,
   version NUMBER(5) NOT NULL
)
TABLESPACE livelist_tab
   initrans 10
   pctfree 2
   storage(
     freelists 2)
/
comment on table datalib.livelist_ddbj
  is 'table where the data from the latest livelist are loaded';

comment on column datalib.livelist_ddbj.version
  is 'sequence version';

GRANT select on LIVELIST_DDBJ to EMBL_SELECT;

GRANT all on LIVELIST_DDBJ to ops$datalib;

CREATE TABLE livelist_ncbi (
   primaryacc# VARCHAR2(15) NOT NULL,
   version NUMBER(5) NOT NULL
)
TABLESPACE livelist_tab
   initrans 10
   pctfree 2
   storage(
     freelists 2)
/
comment on table datalib.livelist_ncbi
  is 'table where the data from the latest livelist are loaded';

comment on column datalib.livelist_ncbi.version
  is 'sequence version';

GRANT select on LIVELIST_NCBI to EMBL_SELECT;

GRANT all on LIVELIST_NCBI to ops$datalib;

CREATE TABLE livelist_missing (
   primaryacc# VARCHAR2(15) NOT NULL,
   dbcode VARCHAR2(5) NOT NULL
)
TABLESPACE livelist_tab
   initrans 10
   pctfree 2
   storage(
     freelists 2)
/
comment on table datalib.livelist_missing
  is 'table where the missing accession numbers from our database are stored';

GRANT select on LIVELIST_MISSING to EMBL_SELECT;

GRANT all on LIVELIST_MISSING to ops$datalib;

ALTER TABLE livelist_missing
  ADD CONSTRAINT ck_livelist_missing$dbcode CHECK (dbcode IN ('D', 'G'));

CREATE TABLE livelist_zombi (
   primaryacc# VARCHAR2(15) NOT NULL,
   dbcode VARCHAR2(5) NOT NULL
)
TABLESPACE livelist_tab
   initrans 10
   pctfree 2
   storage(
     freelists 2)
/
comment on table datalib.livelist_zombi
  is 'table where the accession numbers killed by collaborators but still existing in embl are stored';

GRANT select on LIVELIST_ZOMBI to EMBL_SELECT;

GRANT all on LIVELIST_ZOMBI to ops$datalib;

ALTER TABLE livelist_zombi
  ADD CONSTRAINT ck_livelist_zombi$dbcode CHECK (dbcode IN ('D', 'G'));


CREATE TABLE livelist_sequence_v (
   primaryacc# VARCHAR2(15) NOT NULL,
   dbcode VARCHAR2(5) NOT NULL,
   version_embl NUMBER(5) NOT NULL,
   version_collab NUMBER(5) NOT NULL
)
TABLESPACE livelist_tab
   initrans 10
   pctfree 2
   storage(
     freelists 2)
/
comment on table datalib.livelist_sequence_v
  is 'mismatching sequence versions.';

comment on column datalib.livelist_sequence_v.version_embl
  is 'sequence version in EMBL';

comment on column datalib.livelist_sequence_v.version_collab
  is 'sequence version in the collaborating BD (check dbcode)';

GRANT select on LIVELIST_SEQUENCE_V to EMBL_SELECT;

GRANT all on LIVELIST_SEQUENCE_V to ops$datalib;

ALTER TABLE livelist_sequence_v
  ADD CONSTRAINT ck_livelist_sequence_v$dbcode CHECK (dbcode IN ('D', 'G'));


