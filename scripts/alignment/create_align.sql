--------------------------------------------------------------------------------
--- Sequence for ID-generation
--------------------------------------------------------------------------------

create sequence ALIGNID increment by 1 maxvalue 999999 minvalue 1 nocache;
create public synonym ALIGNID for ALIGNID;

create public synonym load_clob for datalib.load_clob;
--------------------------------------------------------------------------------
--- CV_ALIGNSEQTYPE : small table to hold cv-values
--------------------------------------------------------------------------------
create table CV_ALIGNSEQTYPE
(  CODE                           VARCHAR2(1)         NOT NULL
,  DESCR                          VARCHAR2(11)        NOT NULL
) tablespace ENUCA storage ( initial 2048 next 2048 pctincrease 0 )
/

create public synonym CV_ALIGNSEQTYPE for CV_ALIGNSEQTYPE
/
alter table CV_ALIGNSEQTYPE add constraint PK_CV_ALIGNSEQTYPE primary key ( CODE )
using index tablespace ENUCA storage ( initial 2048 next 2048 pctincrease 0 )
/
alter table CV_ALIGNSEQTYPE add constraint UNQ_CV_ALIGNSEQTYPE unique ( DESCR )
using index tablespace ENUCA storage ( initial 2048 next 2048 pctincrease 0 )
/

insert into cv_alignseqtype ( code, descr ) values ( 'S', 'SIMPLE' );
insert into cv_alignseqtype ( code, descr ) values ( 'C', 'CONSTRUCTED' );
insert into cv_alignseqtype ( code, descr ) values ( 'Z', 'CONSENSUS' );
insert into cv_alignseqtype ( code, descr ) values ( 'P', 'PROTEIN' );
commit;


--------------------------------------------------------------------------------
--- ALIGN : main table to hold ID and status information
--------------------------------------------------------------------------------
create table ALIGN
(  ALIGNID                        NUMBER(15)          NOT NULL
,  ALIGNACC                       VARCHAR2(15)        NOT NULL
,  BIOSEQTYPE                     NUMBER(1)           NOT NULL
,  ENTRY_STATUS			  VARCHAR2(1)         NOT NULL
,  CONFIDENTIAL                   VARCHAR2(1)         NOT NULL
,  IDNO                           NUMBER(15)          NOT NULL
,  SYMBOLS                        NUMBER(15)          NOT NULL
,  NUMSEQ                         NUMBER(15)          NOT NULL
,  UNPUBLISHED                    VARCHAR2(1)         NOT NULL
,  FIRST_CREATED                  DATE
,  FIRST_PUBLIC                   DATE
,  DATE_REMINDER                  DATE
,  HOLD_DATE                      DATE
,  USERSTAMP                      VARCHAR2(30)
,  TIMESTAMP                      DATE
) tablespace ENUCA storage ( initial 1024000 next 204800 pctincrease 0 )
/

-- estimate app. 10000 initial rows for indexes

create public synonym ALIGN for ALIGN
/
alter table ALIGN add constraint PK_ALIGN primary key ( ALIGNID  )
using index tablespace ENUCA storage ( initial 266240 next 53248 pctincrease 0 )
/
alter table ALIGN add constraint UNQ_ALIGN unique ( ALIGNACC )
using index tablespace ENUCA storage ( initial 266240 next 53248 pctincrease 0 )
/
alter table ALIGN add constraint FK_ALIGN_1
foreign key ( BIOSEQTYPE ) references CV_MOLECULETYPE ( CODE )
/
alter table ALIGN add constraint FK_ALIGN_2
foreign key ( ENTRY_STATUS ) references CV_ENTRY_STATUS ( STATUS_CODE )
/
alter table ALIGN add constraint CK_ALIGN_PUBLIC
check ( CONFIDENTIAL in ('Y','N') )
/
alter table ALIGN add constraint CK_ALIGN_UNPUBLISHED
check ( UNPUBLISHED in ('Y','N','O') )
/
alter table ALIGN modify ( USERSTAMP default user )
/
alter table ALIGN modify ( TIMESTAMP default sysdate )
/

--------------------------------------------------------------------------------
--- ALIGN_AUDIT
--------------------------------------------------------------------------------
create table ALIGN_AUDIT
(  ALIGNID                        NUMBER(15)
,  ALIGNACC                       VARCHAR2(15)
,  BIOSEQTYPE                     NUMBER(1)
,  ENTRY_STATUS			  VARCHAR2(1)
,  CONFIDENTIAL                   VARCHAR2(1)
,  IDNO                           NUMBER(15)    
,  SYMBOLS                        NUMBER(15)  
,  NUMSEQ                         NUMBER(15)
,  UNPUBLISHED                    VARCHAR2(1) 
,  FIRST_CREATED                  DATE
,  FIRST_PUBLIC                   DATE
,  HOLD_DATE                      DATE
,  DATE_REMINDER                  DATE
,  USERSTAMP                      VARCHAR2(30)
,  TIMESTAMP                      DATE
,  REMARKTIME                     DATE
,  OSUSER                         VARCHAR2(50)
,  REMARK                         VARCHAR2(50)
,  DBUSER                         VARCHAR2(50)
,  DBREMARK                       VARCHAR2(6)
) tablespace INDXA storage ( initial 3414016 next 682803 pctincrease 0 )
/

create public synonym ALIGN_AUDIT for ALIGN_AUDIT
/
create index i_align_audit on align_audit(alignid)
/
--------------------------------------------------------------------------------
--- ALIGN_AUDIT trigger
--------------------------------------------------------------------------------

CREATE OR REPLACE TRIGGER ALIGN_AUDIT
BEFORE INSERT OR UPDATE OR DELETE ON ALIGN
FOR EACH ROW
BEGIN
IF inserting THEN
   :new.timestamp := sysdate;
   :new.userstamp := auditpackage.osuser;
ELSIF UPDATING THEN
   :new.timestamp := sysdate;
   :new.userstamp := auditpackage.osuser;
INSERT INTO ALIGN_AUDIT (
   alignid,
   alignacc,
   bioseqtype,
   entry_status,	
   confidential,
   idno,
   symbols,	
   numseq,
   unpublished,	
   first_created,
   first_public,
   hold_date,
   date_reminder,
   userstamp,
   timestamp,
   remarktime, osuser, remark, dbremark)
VALUES (
   :old.alignid,
   :old.alignacc,
   :old.bioseqtype,
   :old.entry_status,	
   :old.confidential,
   :old.idno,
   :old.symbols,	
   :old.numseq,
   :old.unpublished, 
   :old.first_created,
   :old.first_public,	
   :old.hold_date,
   :old.date_reminder,
   :old.userstamp,
   :old.timestamp,
   :new.timestamp, :new.userstamp, auditpackage.remark,'update');
ELSE
INSERT INTO ALIGN_AUDIT (
   alignid,
   alignacc,
   bioseqtype,
   entry_status,	
   confidential,
   idno,
   symbols,	
   numseq,
   unpublished,
   first_created,
   first_public,	
   hold_date,
   date_reminder,
   userstamp,
   timestamp,
   remarktime, osuser, remark, dbremark)
VALUES (
   :old.alignid,
   :old.alignacc,
   :old.bioseqtype,
   :old.entry_status,	
   :old.confidential,
   :old.idno,
   :old.symbols,	
   :old.numseq,
   :old.unpublished, 
   :old.first_created,
   :old.first_public,	
   :old.hold_date,
   :old.date_reminder,
   :old.userstamp,
   :old.timestamp,
   sysdate, auditpackage.osuser, auditpackage.remark,'delete');
END IF;
END;
/

--------------------------------------------------------------------------------
--- ALIGN_FILES : table to hold CLOBs separately (minimize updates!)
--------------------------------------------------------------------------------
---- this the storage for PRDB1
create table ALIGN_FILES
(  ALIGNID                        NUMBER(15)          NOT NULL
,  ANNOTATION                     CLOB                NOT NULL
,  FEATURES                       CLOB
,  SEQALIGN                       CLOB                NOT NULL
,  CLUSTAL                        CLOB                NOT NULL
,  USERSTAMP                      VARCHAR2(30)
,  TIMESTAMP                      DATE
) tablespace ENUCA storage ( initial 200M next 100M pctincrease 0 )
LOB (ANNOTATION) STORE AS af_annotation_clob (
        ENABLE STORAGE IN ROW
        STORAGE (INITIAL 500M NEXT 500M MAXEXTENTS 500 PCTINCREASE 0))
LOB (FEATURES) STORE AS af_features_clob (
        ENABLE STORAGE IN ROW
        STORAGE (INITIAL 500M NEXT 500M MAXEXTENTS 500 PCTINCREASE 0))
LOB (SEQALIGN) STORE AS af_seqalign_clob (
        ENABLE STORAGE IN ROW
        STORAGE (INITIAL 500M NEXT 500M MAXEXTENTS 500 PCTINCREASE 0))
LOB (CLUSTAL) STORE AS af_clustal_clob (
        ENABLE STORAGE IN ROW
        STORAGE (INITIAL 500M NEXT 500M MAXEXTENTS 500 PCTINCREASE 0))
/
-- estimate app. 10000 initial rows for indexes

create public synonym ALIGN_FILES for ALIGN_FILES
/
alter table ALIGN_FILES add constraint PK_ALIGN_FILES primary key ( ALIGNID  )
using index tablespace ENUCA storage ( initial 266240 next 53248 pctincrease 0 )
/
alter table ALIGN_FILES add constraint FK_ALIGN_FILES_1
foreign key ( ALIGNID ) references ALIGN ( ALIGNID )
/
alter table ALIGN_FILES modify ( USERSTAMP default user )
/
alter table ALIGN_FILES modify ( TIMESTAMP default sysdate )
/

 -------------------------------------------------------------------------------
 create table ALIGN_FILES_AUDIT
 (  ALIGNID                        NUMBER(15)          NOT NULL
 ,  ANNOTATION                     CLOB                NOT NULL
 ,  FEATURES                       CLOB
 ,  SEQALIGN                       CLOB                NOT NULL
 ,  CLUSTAL                        CLOB                NOT NULL
 ,  USERSTAMP                      VARCHAR2(30)
 ,  TIMESTAMP                      DATE
 ,  REMARKTIME                     DATE
 ,  OSUSER                         VARCHAR2(50)
 ,  REMARK                         VARCHAR2(50)
 ,  DBUSER                         VARCHAR2(50)
 ,  DBREMARK                       VARCHAR2(6)
 ) tablespace ENUCA storage ( initial 200M next 100M pctincrease 0 )
 LOB (ANNOTATION) STORE AS af_annotation_clob (
         ENABLE STORAGE IN ROW
         STORAGE (INITIAL 500M NEXT 500M MAXEXTENTS 500 PCTINCREASE 0))
 LOB (FEATURES) STORE AS af_features_clob (
         ENABLE STORAGE IN ROW
         STORAGE (INITIAL 500M NEXT 500M MAXEXTENTS 500 PCTINCREASE 0))
 LOB (SEQALIGN) STORE AS af_seqalign_clob (
         ENABLE STORAGE IN ROW
         STORAGE (INITIAL 500M NEXT 500M MAXEXTENTS 500 PCTINCREASE 0))
 LOB (CLUSTAL) STORE AS af_clustal_clob (
         ENABLE STORAGE IN ROW
         STORAGE (INITIAL 500M NEXT 500M MAXEXTENTS 500 PCTINCREASE 0))
 /
 
 create public synonym ALIGN_FILES_AUDIT for ALIGN_FILES_AUDIT
 /
 create index i_align_files_audit on align_files_audit(alignid)
 /
 -------------------------------------------------------------------------------
 --- ALIGN_FILES_AUDIT trigger
 -------------------------------------------------------------------------------
 
 CREATE OR REPLACE TRIGGER ALIGN_FILES_AUDIT
 BEFORE INSERT OR UPDATE OR DELETE ON ALIGN_FILES
 FOR EACH ROW
 BEGIN
 IF inserting THEN
    :new.timestamp := sysdate;
    :new.userstamp := auditpackage.osuser;
 ELSIF UPDATING THEN
    :new.timestamp := sysdate;
    :new.userstamp := auditpackage.osuser;
 INSERT INTO ALIGN_FILES_AUDIT (
    alignid,
    annotation,
    features,
    seqalign,
    clustal,
    userstamp,
    timestamp,
    remarktime, osuser, remark, dbremark)
 VALUES (
    :old.alignid,
    :old.annotation,
    :old.features,
    :old.seqalign,
    :old.clustal,
    :old.userstamp,
    :old.timestamp,
    :new.timestamp, :new.userstamp, auditpackage.remark,'update');
 ELSE
 INSERT INTO ALIGN_FILES_AUDIT (
    alignid,
    annotation,
    features,
    seqalign,
    clustal,
    userstamp,
    timestamp,
    remarktime, osuser, remark, dbremark)
 VALUES (
    :old.alignid,
    :old.annotation,
    :old.features,
    :old.seqalign,
    :old.clustal,
    :old.userstamp,
    :old.timestamp,
    sysdate, auditpackage.osuser, auditpackage.remark,'delete');
 END IF;
 END;
 /

--------------------------------------------------------------------------------
--- ALIGN_DBENTRY
--------------------------------------------------------------------------------
create table ALIGN_DBENTRY
(  ALIGNID                        NUMBER(15)          NOT NULL
,  ORDER_IN                       NUMBER(3)           NOT NULL
,  SEQNAME                        VARCHAR2(15)        NOT NULL
,  ALIGNSEQTYPE                   VARCHAR2(1)         NOT NULL
,  PRIMARYACC#                    VARCHAR2(15)
,  ENTRY_STATUS                   VARCHAR2(2)
,  CONFIDENTIAL                   VARCHAR2(1)
,  HOLD_DATE                      DATE
,  ORGANISM                       NUMBER(15)
,  DESCRIPTION                    VARCHAR2(40)
,  USERSTAMP                      VARCHAR2(30)
,  TIMESTAMP                      DATE
) tablespace ENUCA storage ( initial 18618368 next 3723673 pctincrease 0 )
/

-- estimate app. 100000 initial rows for indexes

create public synonym ALIGN_DBENTRY for ALIGN_DBENTRY
/
alter table ALIGN_DBENTRY add constraint PK_ALIGN_DBENTRY primary key ( ALIGNID, ORDER_IN )
using index tablespace ENUCA storage ( initial 5324800 next 1064960 pctincrease 0 )
/
alter table ALIGN_DBENTRY add constraint UNQ_ALIGN_DBENTRY_1 unique ( SEQNAME, ALIGNID )
initially deferred deferrable using index tablespace ENUCA storage ( initial 5324800 next 1064960 pctincrease 0 )
/
--alter table ALIGN_DBENTRY add constraint UNQ_ALIGN_DBENTRY_2 unique ( PRIMARYACC#, ALIGNID )
--using index tablespace ENUCA storage ( initial 5324800 next 1064960 pctincrease 0 )
--/
alter table ALIGN_DBENTRY add constraint FK_ALIGN_DBENTRY_1
foreign key ( ALIGNID ) references ALIGN ( ALIGNID )
/
alter table ALIGN_DBENTRY add constraint FK_ALIGN_DBENTRY_2
foreign key ( ALIGNSEQTYPE ) references CV_ALIGNSEQTYPE ( CODE )
/
alter table ALIGN_DBENTRY add constraint FK_ALIGN_DBENTRY_3
foreign key ( ENTRY_STATUS ) references CV_ENTRY_STATUS ( STATUS_CODE )
/
alter table ALIGN_DBENTRY add constraint FK_ALIGN_DBENTRY_4
foreign key ( ORGANISM ) references NTX_TAX_NODE ( TAX_ID )
/
alter table ALIGN_DBENTRY add constraint CK_ALIGN_DBENTRY_CONF
check ( CONFIDENTIAL in ('Y','N') )
/
alter table ALIGN_DBENTRY modify ( USERSTAMP default user )
/
alter table ALIGN_DBENTRY modify ( TIMESTAMP default sysdate )
/
create index I_ALIGN_DBENTRY_ORG on ALIGN_DBENTRY ( ORGANISM )
tablespace INDXA storage ( initial 2662400 next 532480 )
/

--------------------------------------------------------------------------------
--- ALIGN_DBENTRY_AUDIT
--------------------------------------------------------------------------------
create table ALIGN_DBENTRY_AUDIT
(  ALIGNID                        NUMBER(15)
,  ORDER_IN                       NUMBER(3)
,  SEQNAME                        VARCHAR2(15)
,  ALIGNSEQTYPE                   VARCHAR2(1)
,  PRIMARYACC#                    VARCHAR2(15)
,  ENTRY_STATUS                   VARCHAR2(2)
,  CONFIDENTIAL                   VARCHAR2(1)
,  HOLD_DATE                      DATE
,  ORGANISM                       NUMBER(15)
,  DESCRIPTION                    VARCHAR2(40)
,  USERSTAMP                      VARCHAR2(30)
,  TIMESTAMP                      DATE
,  REMARKTIME                     DATE
,  OSUSER                         VARCHAR2(50)
,  REMARK                         VARCHAR2(50)
,  DBUSER                         VARCHAR2(50)
,  DBREMARK                       VARCHAR2(6)
) tablespace INDXA storage ( initial 8192000 next 1638400 pctincrease 0 )
/

create public synonym ALIGN_DBENTRY_AUDIT for ALIGN_DBENTRY_AUDIT
/
create index i_align_dbentry_audit on align_dbentry_audit(alignid)
/
--------------------------------------------------------------------------------
--- ALIGN_DBENTRY_AUDIT trigger
--------------------------------------------------------------------------------

CREATE OR REPLACE TRIGGER ALIGN_DBENTRY_AUDIT
BEFORE INSERT OR UPDATE OR DELETE ON ALIGN_DBENTRY
FOR EACH ROW
BEGIN
IF inserting THEN
   :new.userstamp := auditpackage.osuser;
ELSIF UPDATING THEN
   :new.timestamp := sysdate;
   :new.userstamp := auditpackage.osuser;
INSERT INTO ALIGN_DBENTRY_AUDIT (
   alignid,
   order_in,
   seqname,
   alignseqtype,
   primaryacc#,
   entry_status,
   confidential,
   hold_date,
   organism,
   description,
   userstamp,
   timestamp,
   remarktime, osuser, remark, dbremark)
VALUES (
   :old.alignid,
   :old.order_in,
   :old.seqname,
   :old.alignseqtype,
   :old.primaryacc#,
   :old.entry_status,
   :old.confidential,
   :old.hold_date,
   :old.organism,
   :old.description,
   :old.userstamp,
   :old.timestamp,
   :new.timestamp, :new.userstamp, auditpackage.remark,'update');
ELSE
INSERT INTO ALIGN_DBENTRY_AUDIT (
   alignid,
   order_in,
   seqname,
   alignseqtype,
   primaryacc#,
   entry_status,
   confidential,
   hold_date,
   organism,
   description,
   userstamp,
   timestamp,
   remarktime, osuser, remark, dbremark)
VALUES (
   :old.alignid,
   :old.order_in,
   :old.seqname,
   :old.alignseqtype,
   :old.primaryacc#,
   :old.entry_status,
   :old.confidential,
   :old.hold_date,
   :old.organism,
   :old.description,
   :old.userstamp,
   :old.timestamp,
   sysdate, auditpackage.osuser, auditpackage.remark,'delete');
END IF;
END;
/

--------------------------------------------------------------------------------
--- Grants
--------------------------------------------------------------------------------

grant SELECT on ALIGNID to EMBL_DEVELOPER;
grant ALTER  on ALIGNID to EMBL_DEVELOPER;

grant SELECT on ALIGNID to EMBL_CURATOR;

grant SELECT on CV_ALIGNSEQTYPE to EMBL_DEVELOPER;
grant INSERT on CV_ALIGNSEQTYPE to EMBL_DEVELOPER;
grant UPDATE on CV_ALIGNSEQTYPE to EMBL_DEVELOPER;
grant DELETE on CV_ALIGNSEQTYPE to EMBL_DEVELOPER;
grant ALTER  on CV_ALIGNSEQTYPE to EMBL_DEVELOPER;

grant SELECT on CV_ALIGNSEQTYPE to EMBL_CURATOR;

grant SELECT on ALIGN to EMBL_DEVELOPER;
grant INSERT on ALIGN to EMBL_DEVELOPER;
grant UPDATE on ALIGN to EMBL_DEVELOPER;
grant DELETE on ALIGN to EMBL_DEVELOPER;
grant ALTER  on ALIGN to EMBL_DEVELOPER;

grant SELECT on ALIGN to EMBL_CURATOR;
grant INSERT on ALIGN to EMBL_CURATOR;
grant UPDATE on ALIGN to EMBL_CURATOR;

grant SELECT on ALIGN to EMBL_SELECT

grant SELECT on ALIGN_AUDIT to EMBL_DEVELOPER;
grant INSERT on ALIGN_AUDIT to EMBL_DEVELOPER;
grant UPDATE on ALIGN_AUDIT to EMBL_DEVELOPER;
grant DELETE on ALIGN_AUDIT to EMBL_DEVELOPER;
grant ALTER  on ALIGN_AUDIT to EMBL_DEVELOPER;

grant SELECT on ALIGN_AUDIT to EMBL_CURATOR;

grant SELECT on ALIGN_FILES to EMBL_DEVELOPER;
grant INSERT on ALIGN_FILES to EMBL_DEVELOPER;
grant UPDATE on ALIGN_FILES to EMBL_DEVELOPER;
grant DELETE on ALIGN_FILES to EMBL_DEVELOPER;
grant ALTER  on ALIGN_FILES to EMBL_DEVELOPER;

grant SELECT on ALIGN_FILES to EMBL_CURATOR;
grant INSERT on ALIGN_FILES to EMBL_CURATOR;
grant UPDATE on ALIGN_FILES to EMBL_CURATOR;

grant SELECT on ALIGN_FILES to EMBL_SELECT;

grant SELECT on ALIGN_DBENTRY to EMBL_DEVELOPER;
grant INSERT on ALIGN_DBENTRY to EMBL_DEVELOPER;
grant UPDATE on ALIGN_DBENTRY to EMBL_DEVELOPER;
grant DELETE on ALIGN_DBENTRY to EMBL_DEVELOPER;
grant ALTER  on ALIGN_DBENTRY to EMBL_DEVELOPER;

grant SELECT on ALIGN_DBENTRY to EMBL_CURATOR;
grant INSERT on ALIGN_DBENTRY to EMBL_CURATOR;
grant UPDATE on ALIGN_DBENTRY to EMBL_CURATOR;

grant SELECT on ALIGN_DBENTRY to EMBL_SELECT;

grant SELECT on ALIGN_DBENTRY_AUDIT to EMBL_DEVELOPER;
grant INSERT on ALIGN_DBENTRY_AUDIT to EMBL_DEVELOPER;
grant UPDATE on ALIGN_DBENTRY_AUDIT to EMBL_DEVELOPER;
grant DELETE on ALIGN_DBENTRY_AUDIT to EMBL_DEVELOPER;
grant ALTER  on ALIGN_DBENTRY_AUDIT to EMBL_DEVELOPER;

grant SELECT on ALIGN_DBENTRY_AUDIT to EMBL_CURATOR;

grant EXECUTE on LOAD_CLOB to EMBL_DEVELOPER;

grant EXECUTE on LOAD_CLOB to EMBL_CURATOR;

exit;
