{==============================================================================
  Program:     TestDdlStatements
  Purpose:     Checks the generated DDL, clause by clause.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21

  Why this exists: a DDL statement that is subtly wrong does not fail politely.
  Firebird's parser cares about clause ORDER - DEFAULT before NOT NULL, DESC
  before INDEX - and gets a syntax error rather than a warning when it is
  wrong. None of that is visible by reading the builder; all of it is visible
  by reading its output.

  The second thing tested here is what ALTER DOMAIN does NOT emit. Sending
  ALTER DOMAIN ... TYPE when the type has not changed makes Firebird re-check
  every existing value, which on a large table is a long outage caused by a
  statement that was never needed.
==============================================================================}
program TestDdlStatements;
{$mode objfpc}{$H+}
uses SysUtils, Classes, Identifier, MetaTypes, DdlStatements;

var
  Failures: Integer;

{ Reports a failed expectation, showing both strings. }
procedure Fail(const AWhat, AGot, AWanted: string);
begin
  WriteLn('  FAIL  ', AWhat);
  WriteLn('        got:    ', AGot);
  WriteLn('        wanted: ', AWanted);
  Inc(Failures);
end;

{ Checks that AGot is exactly AWanted. }
procedure CheckEqual(const AWhat, AGot, AWanted: string);
begin
  if AGot = AWanted then
    WriteLn('  ok    ', AWhat)
  else
    Fail(AWhat, AGot, AWanted);
end;

{ Checks a plain condition. }
procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    WriteLn('  ok    ', AWhat)
  else
  begin
    WriteLn('  FAIL  ', AWhat);
    Inc(Failures);
  end;
end;

{ Returns an identifier from a plain upper-case name. }
function Id(const AName: string): TIdentifier;
begin
  Result := TIdentifier.FromDatabase(AName);
end;

{ Returns a column description. }
function Col(const AName, AType: string; ANotNull: Boolean = False;
  const ADefault: string = ''; const AComputed: string = ''): TDdlColumn;
begin
  Result.Name := AName;
  Result.DataType := AType;
  Result.NotNull := ANotNull;
  Result.DefaultValue := ADefault;
  Result.ComputedBy := AComputed;
  Result.Collation := '';
end;

{ Runs every check on DROP. }
procedure TestDrops;
begin
  WriteLn('DROP');
  CheckEqual('table', DropStatement(mntTable, Id('CUSTOMER')),
    'DROP TABLE CUSTOMER');
  CheckEqual('global temporary table drops as a table',
    DropStatement(mntGTT, Id('TMP')), 'DROP TABLE TMP');
  CheckEqual('view', DropStatement(mntView, Id('V_SALES')),
    'DROP VIEW V_SALES');
  CheckEqual('procedure', DropStatement(mntProcedure, Id('P_POST')),
    'DROP PROCEDURE P_POST');
  CheckEqual('psql function', DropStatement(mntFunctionSQL, Id('F_NET')),
    'DROP FUNCTION F_NET');
  CheckEqual('legacy udf', DropStatement(mntUDF, Id('F_OLD')),
    'DROP EXTERNAL FUNCTION F_OLD');
  CheckEqual('dml trigger', DropStatement(mntTriggerDML, Id('T_BI')),
    'DROP TRIGGER T_BI');
  CheckEqual('database trigger', DropStatement(mntTriggerDB, Id('T_CONN')),
    'DROP TRIGGER T_CONN');
  CheckEqual('domain', DropStatement(mntDomain, Id('D_MONEY')),
    'DROP DOMAIN D_MONEY');
  CheckEqual('generator drops as a sequence',
    DropStatement(mntGenerator, Id('G_ID')), 'DROP SEQUENCE G_ID');
  CheckEqual('exception', DropStatement(mntException, Id('E_BAD')),
    'DROP EXCEPTION E_BAD');
  CheckEqual('index', DropStatement(mntIndex, Id('IX_NAME')),
    'DROP INDEX IX_NAME');
  CheckEqual('role', DropStatement(mntRole, Id('MANAGER')),
    'DROP ROLE MANAGER');

  { A name needing quotes keeps them. }
  CheckEqual('lower-case name is quoted',
    DropStatement(mntTable, TIdentifier.FromDatabase('my table')),
    'DROP TABLE "my table"');

  { Things that must not offer a DROP. }
  Check(not CanDrop(mntSysTable), 'a system table cannot be dropped');
  Check(not CanDrop(mntSysIndex), 'a system index cannot be dropped');
  Check(not CanDrop(mntTables), 'a folder cannot be dropped');
  Check(not CanDrop(mntColumn), 'a column has no DROP of its own');
  Check(not CanDrop(mntDatabase), 'a database is not dropped from here');
  CheckEqual('an undroppable kind yields nothing',
    DropStatement(mntSysTable, Id('RDB$RELATIONS')), '');
  CheckEqual('an empty name yields nothing',
    DropStatement(mntTable, TIdentifier.Empty), '');
  WriteLn;
end;

{ Runs every check on the simple object builders. }
procedure TestSimpleObjects;
begin
  WriteLn('Sequences, exceptions, roles');
  CheckEqual('sequence with no start value is one statement',
    CreateSequenceStatement(Id('G_ID'), 0), 'CREATE SEQUENCE G_ID');
  CheckEqual('sequence with a start value is two statements',
    CreateSequenceStatement(Id('G_ID'), 100),
    'CREATE SEQUENCE G_ID;' + LineEnding + 'ALTER SEQUENCE G_ID RESTART WITH 100');
  CheckEqual('restart', AlterSequenceStatement(Id('G_ID'), 42),
    'ALTER SEQUENCE G_ID RESTART WITH 42');
  CheckEqual('negative restart is allowed',
    AlterSequenceStatement(Id('G_ID'), -5),
    'ALTER SEQUENCE G_ID RESTART WITH -5');

  CheckEqual('exception', CreateExceptionStatement(Id('E_BAD'), 'Bad input'),
    'CREATE EXCEPTION E_BAD ''Bad input''');
  CheckEqual('exception message with an apostrophe is escaped',
    CreateExceptionStatement(Id('E_BAD'), 'Customer''s balance is wrong'),
    'CREATE EXCEPTION E_BAD ''Customer''''s balance is wrong''');
  CheckEqual('alter exception',
    AlterExceptionStatement(Id('E_BAD'), 'Still bad'),
    'ALTER EXCEPTION E_BAD ''Still bad''');
  CheckEqual('empty message is still a valid literal',
    CreateExceptionStatement(Id('E_BAD'), ''), 'CREATE EXCEPTION E_BAD ''''');

  CheckEqual('role', CreateRoleStatement(Id('MANAGER')),
    'CREATE ROLE MANAGER');
  CheckEqual('literal quoting', SqlStringLiteral('it''s'), '''it''''s''');
  WriteLn;
end;

{ Runs every check on domains. }
procedure TestDomains;
var
  D: TDdlDomain;
  Old: TDdlDomain;
begin
  WriteLn('Domains');
  D.Name := Id('D_MONEY');
  D.DataType := 'NUMERIC(15,2)';
  D.NotNull := False;
  D.DefaultValue := '';
  D.CheckCondition := '';
  D.Collation := '';
  CheckEqual('plain domain', CreateDomainStatement(D),
    'CREATE DOMAIN D_MONEY AS NUMERIC(15,2)');

  D.DefaultValue := '0';
  D.NotNull := True;
  D.CheckCondition := 'VALUE >= 0';
  CheckEqual('clause order is type, default, not null, check',
    CreateDomainStatement(D),
    'CREATE DOMAIN D_MONEY AS NUMERIC(15,2) DEFAULT 0 NOT NULL ' +
    'CHECK (VALUE >= 0)');

  D.Collation := 'UNICODE';
  Check(Pos('COLLATE UNICODE', CreateDomainStatement(D)) > 0,
    'collation comes last');

  CheckEqual('a domain with no type yields nothing',
    CreateDomainStatement(Default(TDdlDomain)), '');

  { ALTER emits only what changed. }
  Old := D;
  CheckEqual('no change yields no statements', AlterDomainStatements(Old, D),
    '');

  D.DefaultValue := '1';
  CheckEqual('only the default changed',
    AlterDomainStatements(Old, D), 'ALTER DOMAIN D_MONEY SET DEFAULT 1');

  D := Old;
  D.DefaultValue := '';
  CheckEqual('clearing the default drops it',
    AlterDomainStatements(Old, D), 'ALTER DOMAIN D_MONEY DROP DEFAULT');

  D := Old;
  D.NotNull := False;
  CheckEqual('dropping not null',
    AlterDomainStatements(Old, D), 'ALTER DOMAIN D_MONEY DROP NOT NULL');

  D := Old;
  D.DataType := 'NUMERIC(18,4)';
  CheckEqual('only the type changed',
    AlterDomainStatements(Old, D), 'ALTER DOMAIN D_MONEY TYPE NUMERIC(18,4)');

  D := Old;
  D.CheckCondition := 'VALUE > 0';
  CheckEqual('replacing a check drops then adds',
    AlterDomainStatements(Old, D),
    'ALTER DOMAIN D_MONEY DROP CONSTRAINT;' + LineEnding +
    'ALTER DOMAIN D_MONEY ADD CONSTRAINT CHECK (VALUE > 0)');

  D := Old;
  D.CheckCondition := '';
  CheckEqual('removing a check only drops',
    AlterDomainStatements(Old, D), 'ALTER DOMAIN D_MONEY DROP CONSTRAINT');
  WriteLn;
end;

{ Runs every check on the clause strippers. }
procedure TestStrippers;
begin
  WriteLn('Stored clause strippers');
  CheckEqual('default keyword removed',
    StripDefaultKeyword('DEFAULT 0'), '0');
  CheckEqual('lower case keyword removed',
    StripDefaultKeyword('default CURRENT_DATE'), 'CURRENT_DATE');
  CheckEqual('keyword straight onto a bracket',
    StripDefaultKeyword('DEFAULT(0)'), '(0)');
  CheckEqual('a value that merely starts with the letters is left alone',
    StripDefaultKeyword('DEFAULTS'), 'DEFAULTS');
  CheckEqual('a bare expression is left alone',
    StripDefaultKeyword('0'), '0');
  CheckEqual('empty stays empty', StripDefaultKeyword(''), '');

  CheckEqual('check keyword and brackets removed',
    StripCheckKeyword('CHECK (VALUE > 0)'), 'VALUE > 0');
  CheckEqual('nested brackets keep their own',
    StripCheckKeyword('CHECK ((A > 0) AND (B > 0))'), '(A > 0) AND (B > 0)');
  CheckEqual('a first bracket that closes early is not unwrapped',
    StripCheckKeyword('CHECK (A > 0) AND (B > 0)'), '(A > 0) AND (B > 0)');
  CheckEqual('lower case check', StripCheckKeyword('check (VALUE IS NOT NULL)'),
    'VALUE IS NOT NULL');
  CheckEqual('no keyword, just brackets',
    StripCheckKeyword('(VALUE > 0)'), 'VALUE > 0');
  CheckEqual('empty stays empty', StripCheckKeyword(''), '');

  { The bug these exist to stop: read a domain, write it back, read again. }
  CheckEqual('a default survives a round trip unchanged',
    StripDefaultKeyword('DEFAULT ' + StripDefaultKeyword('DEFAULT 0')), '0');
  CheckEqual('a check survives a round trip unchanged',
    StripCheckKeyword('CHECK (' + StripCheckKeyword('CHECK (VALUE > 0)')
      + ')'), 'VALUE > 0');
  WriteLn;
end;

{ Runs every check on indexes. }
procedure TestIndexes;
var
  X: TDdlIndex;
begin
  WriteLn('Indexes');
  X.Name := Id('IX_CUST_NAME');
  X.TableName := Id('CUSTOMER');
  X.Columns := TStringArray.Create('LAST_NAME', 'FIRST_NAME');
  X.Unique := False;
  X.Descending := False;
  X.ComputedBy := '';
  CheckEqual('two-column index', CreateIndexStatement(X),
    'CREATE INDEX IX_CUST_NAME ON CUSTOMER (LAST_NAME, FIRST_NAME)');

  X.Unique := True;
  CheckEqual('unique comes before INDEX', CreateIndexStatement(X),
    'CREATE UNIQUE INDEX IX_CUST_NAME ON CUSTOMER ' +
    '(LAST_NAME, FIRST_NAME)');

  X.Descending := True;
  CheckEqual('unique then descending then INDEX', CreateIndexStatement(X),
    'CREATE UNIQUE DESCENDING INDEX IX_CUST_NAME ON CUSTOMER ' +
    '(LAST_NAME, FIRST_NAME)');

  X.Unique := False;
  X.Descending := False;
  X.ComputedBy := 'UPPER(LAST_NAME)';
  CheckEqual('a computed index names no columns', CreateIndexStatement(X),
    'CREATE INDEX IX_CUST_NAME ON CUSTOMER COMPUTED BY (UPPER(LAST_NAME))');

  X.ComputedBy := '';
  X.Columns := nil;
  CheckEqual('an index over nothing yields nothing',
    CreateIndexStatement(X), '');

  CheckEqual('activate', AlterIndexActiveStatement(Id('IX_A'), True),
    'ALTER INDEX IX_A ACTIVE');
  CheckEqual('deactivate', AlterIndexActiveStatement(Id('IX_A'), False),
    'ALTER INDEX IX_A INACTIVE');
  WriteLn;
end;

{ Runs every check on tables. }
procedure TestTables;
var
  T: TDdlTable;
begin
  WriteLn('Tables');
  T.Name := Id('CUSTOMER');
  T.Columns := nil;
  T.PrimaryKey := nil;

  SetLength(T.Columns, 3);
  T.Columns[0] := Col('ID', 'INTEGER', True);
  T.Columns[1] := Col('NAME', 'VARCHAR(60)', True, '''unknown''');
  T.Columns[2] := Col('CREATED', 'TIMESTAMP', False, 'CURRENT_TIMESTAMP');

  CheckEqual('columns, one per line', CreateTableStatement(T),
    'CREATE TABLE CUSTOMER (' + LineEnding +
    '  ID INTEGER NOT NULL,' + LineEnding +
    '  NAME VARCHAR(60) DEFAULT ''unknown'' NOT NULL,' + LineEnding +
    '  CREATED TIMESTAMP DEFAULT CURRENT_TIMESTAMP' + LineEnding +
    ')');

  T.PrimaryKey := TStringArray.Create('ID');
  Check(Pos('  PRIMARY KEY (ID)' + LineEnding + ')',
    CreateTableStatement(T)) > 0, 'primary key is a table-level constraint');

  T.PrimaryKey := TStringArray.Create('ID', 'NAME');
  Check(Pos('PRIMARY KEY (ID, NAME)', CreateTableStatement(T)) > 0,
    'compound primary key');

  T.PrimaryKey := nil;
  SetLength(T.Columns, 4);
  T.Columns[3] := Col('UPPER_NAME', '', False, '', 'UPPER(NAME)');
  Check(Pos('UPPER_NAME COMPUTED BY (UPPER(NAME))',
    CreateTableStatement(T)) > 0, 'computed column with no type');

  T.Columns[3] := Col('UPPER_NAME', 'VARCHAR(60)', True, '0', 'UPPER(NAME)');
  Check(Pos('UPPER_NAME VARCHAR(60) COMPUTED BY (UPPER(NAME))',
    CreateTableStatement(T)) > 0,
    'a computed column takes neither default nor not null');

  { A name the user quoted keeps its case; a bare one is upper-cased, so
    'id' and 'ID' mean the same column. }
  SetLength(T.Columns, 2);
  T.Columns[0] := Col('id', 'INTEGER');
  T.Columns[1] := Col('"mixed Case"', 'INTEGER');
  Check(Pos('  ID INTEGER', CreateTableStatement(T)) > 0,
    'a bare lower-case column name is upper-cased, not quoted');
  Check(Pos('  "mixed Case" INTEGER', CreateTableStatement(T)) > 0,
    'a quoted column name keeps its case');

  T.Columns := nil;
  CheckEqual('a table with no columns yields nothing',
    CreateTableStatement(T), '');
  WriteLn;
end;

{ CREATE DATABASE: clause order, quoting, and what is left out. }
procedure TestCreateDatabase;
begin
  WriteLn('CREATE DATABASE');
  CheckEqual('every clause, in the order Firebird wants',
    CreateDatabaseStatement('localhost/3050:C:\db\new.fdb', 'SYSDBA',
      'masterkey', 8192, 'utf8'),
    'CREATE DATABASE ''localhost/3050:C:\db\new.fdb'' USER ''SYSDBA'' '
    + 'PASSWORD ''masterkey'' PAGE_SIZE 8192 DEFAULT CHARACTER SET UTF8');
  CheckEqual('empty values leave their clauses out',
    CreateDatabaseStatement('/data/x.fdb', '', '', 0, ''),
    'CREATE DATABASE ''/data/x.fdb''');
  CheckEqual('an apostrophe in the path or password is doubled',
    CreateDatabaseStatement('C:\O''Brien\x.fdb', 'U', 'it''s', 0, ''),
    'CREATE DATABASE ''C:\O''''Brien\x.fdb'' USER ''U'' '
    + 'PASSWORD ''it''''s''');
  Check(IsValidPageSize(0), 'page size 0 means the server default');
  Check(IsValidPageSize(16384), '16384 is a page size');
  Check(not IsValidPageSize(1024), '1024 is too small for Firebird 3+');
  Check(not IsValidPageSize(5000), '5000 is not a power of two');
  WriteLn;
end;

{ Script as ALTER: which CREATE is rewritten, and which is left alone. }
procedure TestCreateOrAlter;
const
  Nl = LineEnding;
var
  Ddl: string;
begin
  WriteLn('CREATE OR ALTER');

  CheckEqual('a view is rewritten',
    CreateOrAlterScript(mntView, 'CREATE VIEW V (A) AS SELECT 1 FROM T;'),
    'CREATE OR ALTER VIEW V (A) AS SELECT 1 FROM T;');
  CheckEqual('the keyword is matched whatever its case',
    CreateOrAlterScript(mntView, 'create view V AS SELECT 1 FROM T;'),
    'CREATE OR ALTER VIEW V AS SELECT 1 FROM T;');

  Ddl := 'SET TERM ^ ;' + Nl + 'CREATE PROCEDURE P' + Nl + 'AS' + Nl +
    'BEGIN' + Nl + '  EXECUTE STATEMENT ''CREATE PROCEDURE X AS BEGIN END'';' +
    Nl + 'END^' + Nl + 'SET TERM ; ^';
  CheckEqual('a procedure is rewritten after SET TERM, and a CREATE inside '
    + 'its body is not',
    CreateOrAlterScript(mntProcedure, Ddl),
    'SET TERM ^ ;' + Nl + 'CREATE OR ALTER PROCEDURE P' + Nl + 'AS' + Nl +
    'BEGIN' + Nl + '  EXECUTE STATEMENT ''CREATE PROCEDURE X AS BEGIN END'';' +
    Nl + 'END^' + Nl + 'SET TERM ; ^');

  CheckEqual('leading blanks are kept',
    CreateOrAlterScript(mntTriggerDML, '  CREATE TRIGGER TR FOR T'),
    '  CREATE OR ALTER TRIGGER TR FOR T');
  CheckEqual('only the first CREATE is rewritten',
    CreateOrAlterScript(mntException,
      'CREATE EXCEPTION E ''a'';' + Nl + 'CREATE EXCEPTION F ''b'';'),
    'CREATE OR ALTER EXCEPTION E ''a'';' + Nl + 'CREATE EXCEPTION F ''b'';');

  Ddl := 'CREATE PACKAGE PK AS BEGIN END^' + Nl +
    'CREATE PACKAGE BODY PK AS BEGIN END^';
  CheckEqual('a package header is altered and its body recreated',
    CreateOrAlterScript(mntPackage, Ddl),
    'CREATE OR ALTER PACKAGE PK AS BEGIN END^' + Nl +
    'RECREATE PACKAGE BODY PK AS BEGIN END^');

  CheckEqual('a name that merely starts with the keyword is not a match',
    CreateOrAlterScript(mntPackage, 'CREATE PACKAGES_LOG'), '');
  CheckEqual('a table has no CREATE OR ALTER',
    CreateOrAlterScript(mntTable, 'CREATE TABLE T (A INTEGER);'), '');
  Check(not CanScriptAlter(mntGenerator),
    'a sequence is not offered: CREATE OR ALTER SEQUENCE restarts it');
  Check(not CanScriptAlter(mntDomain), 'a domain has no CREATE OR ALTER');
  Check(CanScriptAlter(mntFunctionSQL), 'a PSQL function can be altered');
  CheckEqual('DDL with no CREATE for the kind yields nothing',
    CreateOrAlterScript(mntView, 'COMMENT ON VIEW V IS ''x'';'), '');
  WriteLn;
end;

begin
  Failures := 0;
  WriteLn('Generated DDL');
  WriteLn;

  TestDrops;
  TestSimpleObjects;
  TestDomains;
  TestStrippers;
  TestIndexes;
  TestTables;
  TestCreateOrAlter;
  TestCreateDatabase;

  if Failures = 0 then
    WriteLn('all DDL checks passed')
  else
  begin
    WriteLn(Failures, ' check(s) failed');
    Halt(1);
  end;
end.
