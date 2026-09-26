{==============================================================================
  Unit:        DdlStatements
  Purpose:     Builds the CREATE, ALTER and DROP statements the DDL editing
               dialogs offer, from plain descriptions of what the user asked
               for.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  SysUtils, Classes, Identifier, MetaTypes

  IBConsole equivalent: the Create/Alter dialogs under each object folder.

  WHY THIS IS A STRING BUILDER AND NOT A DATABASE LAYER
  Nothing here talks to a server. Every routine turns a record into text, so
  the whole unit is testable without a database - which matters more here than
  almost anywhere else in the program, because a DDL statement that is subtly
  wrong does not fail politely: it either does nothing or changes the wrong
  thing, and the user finds out later.

  WHAT THE DIALOGS DO WITH THE RESULT
  They show it. Every DDL dialog in this program is a form over these
  functions with the generated statement visible in a preview, and the user
  presses Execute on a statement they can read. That is deliberate: the people
  who run a database console already know SQL, and a tool that hides what it
  is about to run teaches them nothing and earns no trust.

  A builder may return MORE THAN ONE statement, separated by ';' and a line
  break - creating a sequence with a starting value is two statements in every
  Firebird this program supports, and ALTER DOMAIN changes one property each.
  Callers run them through the same splitter the SQL editor uses.

  VERSION CAUTION
  Only syntax accepted by Firebird 3 and later is emitted, because that is the
  range the connection layer supports. Where a newer, shorter spelling exists
  (CREATE SEQUENCE ... START WITH, which is Firebird 4) the older two
  statement form is used instead: it is correct everywhere, and being correct
  everywhere is worth more than being terse on the newest server.
==============================================================================}
unit DdlStatements;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Identifier, MetaTypes;

type
  { One column of a table being created. }
  TDdlColumn = record
    { The column name, as the user typed it. }
    Name: string;
    { The type, already spelled the way Firebird wants it - 'VARCHAR(30)',
      'INTEGER', or the name of a domain. }
    DataType: string;
    { True when the column may not be null. }
    NotNull: Boolean;
    { A default, as a raw SQL expression: 0, CURRENT_DATE, 'x'. Empty for
      none. It is not quoted here, because whether it needs quoting depends on
      the type and only the user knows what they meant. }
    DefaultValue: string;
    { A COMPUTED BY expression. When set, the column is computed and the
      default and not-null settings do not apply. }
    ComputedBy: string;
    { A collation, empty for the type's own. }
    Collation: string;

    { Returns the column's part of a CREATE TABLE body. }
    function AsClause: string;
  end;

  TDdlColumnArray = array of TDdlColumn;

  { A table being created. }
  TDdlTable = record
    { The table's name. }
    Name: TIdentifier;
    { Its columns, in order. }
    Columns: TDdlColumnArray;
    { The columns making up the primary key, by name. Empty for no key. }
    PrimaryKey: TStringArray;
  end;

  { A domain being created or altered. }
  TDdlDomain = record
    { The domain's name. }
    Name: TIdentifier;
    { The underlying type. }
    DataType: string;
    { True when values may not be null. }
    NotNull: Boolean;
    { A default, as a raw SQL expression. Empty for none. }
    DefaultValue: string;
    { A CHECK condition WITHOUT the surrounding CHECK ( ). Empty for none. }
    CheckCondition: string;
    { A collation, empty for the type's own. }
    Collation: string;
  end;

  { An index being created. }
  TDdlIndex = record
    { The index's name. }
    Name: TIdentifier;
    { The table it indexes. }
    TableName: TIdentifier;
    { The columns it covers, by name. Ignored when ComputedBy is set. }
    Columns: TStringArray;
    { True for a unique index. }
    Unique: Boolean;
    { True to index in descending order. }
    Descending: Boolean;
    { An expression to index instead of columns. Empty for a plain index. }
    ComputedBy: string;
  end;

{ Returns AValue as a Firebird string literal, with quotes doubled. }
function SqlStringLiteral(const AValue: string): string;

{ Returns the expression out of a stored DEFAULT clause: Firebird keeps
  'DEFAULT 0' and the dialogs want '0'. }
function StripDefaultKeyword(const ASource: string): string;

{ Returns the condition out of a stored CHECK clause: Firebird keeps
  'CHECK (VALUE > 0)' and the dialogs want 'VALUE > 0'. }
function StripCheckKeyword(const ASource: string): string;

{ Returns a name the user typed, rendered the way every other name in this
  program is: upper-cased and bare when Firebird will accept it bare, kept
  verbatim and quoted when the user quoted it themselves. }
function UserName(const AText: string): string;

{ Returns the SQL keyword for an object kind - 'TABLE', 'PROCEDURE' - or an
  empty string for a kind that has no DROP of its own. }
function DropKeyword(ANodeType: TMetaNodeType): string;

{ Returns True when an object of this kind can be dropped by name. }
function CanDrop(ANodeType: TMetaNodeType): Boolean;

{ Returns 'DROP TABLE "X"', or an empty string for a kind that cannot be
  dropped. }
function DropStatement(ANodeType: TMetaNodeType;
  const AName: TIdentifier): string;

{ Returns the statements that create a sequence, and set its starting value
  when that is not zero. }
function CreateSequenceStatement(const AName: TIdentifier;
  AStartValue: Int64): string;

{ Returns the statement that restarts a sequence at a given value. }
function AlterSequenceStatement(const AName: TIdentifier;
  AStartValue: Int64): string;

{ Returns 'CREATE EXCEPTION "X" '...''. }
function CreateExceptionStatement(const AName: TIdentifier;
  const AMessage: string): string;

{ Returns 'ALTER EXCEPTION "X" '...''. }
function AlterExceptionStatement(const AName: TIdentifier;
  const AMessage: string): string;

{ Returns 'CREATE ROLE "X"'. }
function CreateRoleStatement(const AName: TIdentifier): string;

{ Returns the CREATE DOMAIN statement for ADomain. }
function CreateDomainStatement(const ADomain: TDdlDomain): string;

{ Returns the ALTER DOMAIN statements needed to turn AOld into ANew, one per
  property that differs. }
function AlterDomainStatements(const AOld, ANew: TDdlDomain): string;

{ Returns the CREATE INDEX statement for AIndex. }
function CreateIndexStatement(const AIndex: TDdlIndex): string;

{ Returns the CREATE TABLE statement for ATable. }
function CreateTableStatement(const ATable: TDdlTable): string;

{ Returns 'ALTER INDEX "X" ACTIVE' or '... INACTIVE'. }
function AlterIndexActiveStatement(const AName: TIdentifier;
  AActive: Boolean): string;

implementation

const
  { What separates one generated statement from the next. The SQL editor's
    splitter reads this exactly as it reads a typed script. }
  StatementBreak = ';' + LineEnding;

{------------------------------------------------------------------------------
  SqlStringLiteral
  ----------------------------------------------------------------------------
  Returns AValue as a Firebird string literal, with quotes doubled.

  Parameters:
    AValue - The text to quote.

  Returns:
    The literal including its surrounding apostrophes.

  Notes:
    An exception message or a default is user text and routinely contains an
    apostrophe. Doubling is Firebird's escape and the only one it has.
------------------------------------------------------------------------------}
function SqlStringLiteral(const AValue: string): string;
begin
  Result := '''' + StringReplace(AValue, '''', '''''', [rfReplaceAll]) + '''';
end;

{------------------------------------------------------------------------------
  StripDefaultKeyword
  ----------------------------------------------------------------------------
  Returns the expression out of a stored DEFAULT clause.

  Parameters:
    ASource - What RDB$DEFAULT_SOURCE held.

  Returns:
    The expression alone, or the input trimmed when it does not start with
    the keyword.

  Notes:
    Firebird stores the whole clause, keyword included, and CreateDomain
    writes the keyword back. Without this the keyword doubles every time a
    domain is read and rewritten - DEFAULT DEFAULT 0 - which Firebird
    rejects, and only on the second edit, which is the worst moment to find
    out.
------------------------------------------------------------------------------}
function StripDefaultKeyword(const ASource: string): string;
const
  Keyword = 'DEFAULT';
begin
  Result := Trim(ASource);
  if Length(Result) <= Length(Keyword) then
  begin
    Exit;
  end;
  if not SameText(Copy(Result, 1, Length(Keyword)), Keyword) then
  begin
    Exit;
  end;
  if not (Result[Length(Keyword) + 1] in [' ', #9, #10, #13, '(']) then
  begin
    Exit;
  end;
  Result := Trim(Copy(Result, Length(Keyword) + 1, MaxInt));
end;

{------------------------------------------------------------------------------
  StripCheckKeyword
  ----------------------------------------------------------------------------
  Returns the condition out of a stored CHECK clause.

  Parameters:
    ASource - What RDB$VALIDATION_SOURCE held.

  Returns:
    The condition alone, without the keyword and without the brackets that
    wrap the whole of it.

  Notes:
    The outer brackets come off only when the FIRST one closes at the very
    end. 'CHECK ((A > 0) AND (B > 0))' unwraps to '(A > 0) AND (B > 0)',
    while a condition whose first bracket closes early is left alone -
    stripping there would join two expressions into one and change what it
    means.
------------------------------------------------------------------------------}
function StripCheckKeyword(const ASource: string): string;
const
  Keyword = 'CHECK';
var
  Depth: Integer;
  I: Integer;
  CloseAt: Integer;
begin
  Result := Trim(ASource);
  if (Length(Result) > Length(Keyword)) and
     SameText(Copy(Result, 1, Length(Keyword)), Keyword) and
     (Result[Length(Keyword) + 1] in [' ', #9, #10, #13, '(']) then
  begin
    Result := Trim(Copy(Result, Length(Keyword) + 1, MaxInt));
  end;

  if (Length(Result) < 2) or (Result[1] <> '(') then
  begin
    Exit;
  end;

  Depth := 0;
  CloseAt := 0;
  for I := 1 to Length(Result) do
  begin
    if Result[I] = '(' then
    begin
      Inc(Depth);
    end
    else if Result[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        CloseAt := I;
        Break;
      end;
    end;
  end;

  if CloseAt = Length(Result) then
  begin
    Result := Trim(Copy(Result, 2, Length(Result) - 2));
  end;
end;

{------------------------------------------------------------------------------
  UserName
  ----------------------------------------------------------------------------
  Returns a name the user typed, rendered like every other name in the
  program.

  Parameters:
    AText - What the user typed into a name field.

  Returns:
    The name, bare when it can be and quoted when it must be.

  Notes:
    Quoting every name unconditionally would look harmless and is not: a
    column typed as 'id' would become "id" and stay lower case for ever,
    needing quotes in every statement written against it afterwards, while
    the table it sits in became ID. Names typed into this program mean the
    same thing wherever they are typed.
------------------------------------------------------------------------------}
function UserName(const AText: string): string;
begin
  Result := TIdentifier.FromUserInput(AText).QualifiedQuoted;
end;

{------------------------------------------------------------------------------
  TDdlColumn.AsClause
  ----------------------------------------------------------------------------
  Returns the column's part of a CREATE TABLE body.

  Returns:
    The column definition, without a trailing comma.

  Notes:
    A computed column takes neither a default nor NOT NULL: its value is the
    expression every time it is read, so there is nothing to default and
    nothing to withhold. Firebird rejects the combination rather than ignoring
    it, so the two are not emitted together.

    The order - type, DEFAULT, NOT NULL, COLLATE - is the order Firebird's
    parser expects. It is not interchangeable.
------------------------------------------------------------------------------}
function TDdlColumn.AsClause: string;
begin
  Result := UserName(Name);

  if Trim(ComputedBy) <> '' then
  begin
    if Trim(DataType) <> '' then
    begin
      Result := Result + ' ' + Trim(DataType);
    end;
    Result := Result + ' COMPUTED BY (' + Trim(ComputedBy) + ')';
    Exit;
  end;

  Result := Result + ' ' + Trim(DataType);

  if Trim(DefaultValue) <> '' then
  begin
    Result := Result + ' DEFAULT ' + Trim(DefaultValue);
  end;
  if NotNull then
  begin
    Result := Result + ' NOT NULL';
  end;
  if Trim(Collation) <> '' then
  begin
    Result := Result + ' COLLATE ' + UserName(Collation);
  end;
end;

{------------------------------------------------------------------------------
  DropKeyword
  ----------------------------------------------------------------------------
  Returns the SQL keyword for an object kind.

  Parameters:
    ANodeType - Which kind of object.

  Returns:
    'TABLE', 'PROCEDURE' and so on, or an empty string for a kind that has no
    DROP of its own - a folder, a column, a dependency.

  Notes:
    A global temporary table is dropped as a table; the "temporary" is a
    property of how it was created, not of what it is now.

    A system table or system index is deliberately absent: Firebird will
    refuse, and offering the command would be offering to break the database.
------------------------------------------------------------------------------}
function DropKeyword(ANodeType: TMetaNodeType): string;
begin
  case ANodeType of
    mntTable, mntGTT:
      Result := 'TABLE';
    mntView:
      Result := 'VIEW';
    mntProcedure:
      Result := 'PROCEDURE';
    mntFunctionSQL:
      Result := 'FUNCTION';
    mntUDF:
      Result := 'EXTERNAL FUNCTION';
    mntPackage:
      Result := 'PACKAGE';
    mntTriggerDML, mntTriggerDB, mntTriggerDDL:
      Result := 'TRIGGER';
    mntDomain:
      Result := 'DOMAIN';
    mntGenerator:
      Result := 'SEQUENCE';
    mntException:
      Result := 'EXCEPTION';
    mntIndex:
      Result := 'INDEX';
    mntRole:
      Result := 'ROLE';
    mntCollation:
      Result := 'COLLATION';
    mntBlobFilter:
      Result := 'FILTER';
    mntSchema:
      Result := 'SCHEMA';
  else
    Result := '';
  end;
end;

{------------------------------------------------------------------------------
  CanDrop
  ----------------------------------------------------------------------------
  Returns True when an object of this kind can be dropped by name.

  Parameters:
    ANodeType - Which kind of object.

  Returns:
    True when DropStatement will produce something.
------------------------------------------------------------------------------}
function CanDrop(ANodeType: TMetaNodeType): Boolean;
begin
  Result := DropKeyword(ANodeType) <> '';
end;

{------------------------------------------------------------------------------
  DropStatement
  ----------------------------------------------------------------------------
  Returns the DROP statement for one object.

  Parameters:
    ANodeType - Which kind of object.
    AName     - Its name.

  Returns:
    'DROP TABLE "CUSTOMER"', or an empty string when the kind cannot be
    dropped or the name is empty.
------------------------------------------------------------------------------}
function DropStatement(ANodeType: TMetaNodeType;
  const AName: TIdentifier): string;
var
  Keyword: string;
begin
  Result := '';
  Keyword := DropKeyword(ANodeType);
  if (Keyword = '') or AName.IsEmpty then
  begin
    Exit;
  end;
  Result := 'DROP ' + Keyword + ' ' + AName.QualifiedQuoted;
end;

{------------------------------------------------------------------------------
  CreateSequenceStatement
  ----------------------------------------------------------------------------
  Returns the statements that create a sequence, and set its starting value
  when that is not zero.

  Parameters:
    AName       - The sequence's name.
    AStartValue - Where it should start.

  Returns:
    One statement, or two separated by ';' and a line break.

  Notes:
    CREATE SEQUENCE ... START WITH is Firebird 4. The two-statement form works
    on every version this program connects to, so it is what is emitted - see
    the version caution in the unit header.
------------------------------------------------------------------------------}
function CreateSequenceStatement(const AName: TIdentifier;
  AStartValue: Int64): string;
begin
  if AName.IsEmpty then
  begin
    Exit('');
  end;
  Result := 'CREATE SEQUENCE ' + AName.QualifiedQuoted;
  if AStartValue <> 0 then
  begin
    Result := Result + StatementBreak +
      AlterSequenceStatement(AName, AStartValue);
  end;
end;

{------------------------------------------------------------------------------
  AlterSequenceStatement
  ----------------------------------------------------------------------------
  Returns the statement that restarts a sequence at a given value.

  Parameters:
    AName       - The sequence's name.
    AStartValue - The value it should next be at.

  Returns:
    'ALTER SEQUENCE "X" RESTART WITH 100', or an empty string for no name.

  Notes:
    WHAT THE VALUE MEANS CHANGED IN FIREBIRD 4. On 4 and later, RESTART WITH
    n makes n the NEXT value the sequence hands out. On Firebird 3 it sets
    the LAST value used, so the next one is n + 1.

    Verified against all three engines: after RESTART WITH 100,
    GEN_ID(seq, 0) reads 100 on 3.0.14 and 99 on 4.0.7 and 5.0.4.

    Nothing here compensates for the difference. The number the user typed
    is the number sent, because silently adjusting it would make the
    statement in the preview disagree with the statement that ran - and the
    preview is the thing they checked. The dialog says which way round it
    is for the server in front of them.
------------------------------------------------------------------------------}
function AlterSequenceStatement(const AName: TIdentifier;
  AStartValue: Int64): string;
begin
  if AName.IsEmpty then
  begin
    Exit('');
  end;
  Result := Format('ALTER SEQUENCE %s RESTART WITH %d',
    [AName.QualifiedQuoted, AStartValue]);
end;

{------------------------------------------------------------------------------
  CreateExceptionStatement
  ----------------------------------------------------------------------------
  Returns the CREATE EXCEPTION statement.

  Parameters:
    AName    - The exception's name.
    AMessage - Its default message.

  Returns:
    The statement, or an empty string for no name.
------------------------------------------------------------------------------}
function CreateExceptionStatement(const AName: TIdentifier;
  const AMessage: string): string;
begin
  if AName.IsEmpty then
  begin
    Exit('');
  end;
  Result := 'CREATE EXCEPTION ' + AName.QualifiedQuoted + ' ' +
    SqlStringLiteral(AMessage);
end;

{------------------------------------------------------------------------------
  AlterExceptionStatement
  ----------------------------------------------------------------------------
  Returns the ALTER EXCEPTION statement.

  Parameters:
    AName    - The exception's name.
    AMessage - Its new default message.

  Returns:
    The statement, or an empty string for no name.
------------------------------------------------------------------------------}
function AlterExceptionStatement(const AName: TIdentifier;
  const AMessage: string): string;
begin
  if AName.IsEmpty then
  begin
    Exit('');
  end;
  Result := 'ALTER EXCEPTION ' + AName.QualifiedQuoted + ' ' +
    SqlStringLiteral(AMessage);
end;

{------------------------------------------------------------------------------
  CreateRoleStatement
  ----------------------------------------------------------------------------
  Returns the CREATE ROLE statement.

  Parameters:
    AName - The role's name.

  Returns:
    The statement, or an empty string for no name.

  Notes:
    A role has nothing else to say about it at creation. What it may do comes
    from GRANT afterwards, which is the permissions page's business.
------------------------------------------------------------------------------}
function CreateRoleStatement(const AName: TIdentifier): string;
begin
  if AName.IsEmpty then
  begin
    Exit('');
  end;
  Result := 'CREATE ROLE ' + AName.QualifiedQuoted;
end;

{------------------------------------------------------------------------------
  CreateDomainStatement
  ----------------------------------------------------------------------------
  Returns the CREATE DOMAIN statement for ADomain.

  Parameters:
    ADomain - What to create.

  Returns:
    The statement, or an empty string when there is no name or no type.

  Notes:
    The clause order - type, DEFAULT, NOT NULL, CHECK, COLLATE - is what
    Firebird's parser expects and is not interchangeable.
------------------------------------------------------------------------------}
function CreateDomainStatement(const ADomain: TDdlDomain): string;
begin
  Result := '';
  if ADomain.Name.IsEmpty or (Trim(ADomain.DataType) = '') then
  begin
    Exit;
  end;

  Result := 'CREATE DOMAIN ' + ADomain.Name.QualifiedQuoted + ' AS ' +
    Trim(ADomain.DataType);

  if Trim(ADomain.DefaultValue) <> '' then
  begin
    Result := Result + ' DEFAULT ' + Trim(ADomain.DefaultValue);
  end;
  if ADomain.NotNull then
  begin
    Result := Result + ' NOT NULL';
  end;
  if Trim(ADomain.CheckCondition) <> '' then
  begin
    Result := Result + ' CHECK (' + Trim(ADomain.CheckCondition) + ')';
  end;
  if Trim(ADomain.Collation) <> '' then
  begin
    Result := Result + ' COLLATE ' + UserName(ADomain.Collation);
  end;
end;

{------------------------------------------------------------------------------
  AlterDomainStatements
  ----------------------------------------------------------------------------
  Returns the ALTER DOMAIN statements needed to turn AOld into ANew.

  Parameters:
    AOld - The domain as it is now.
    ANew - The domain as it should be.

  Returns:
    One statement per property that differs, separated by ';' and a line
    break. An empty string when nothing differs.

  Notes:
    Firebird alters one property per statement, so this is a list and not a
    single command. Emitting only what changed matters: ALTER DOMAIN ... TYPE
    is checked against every existing value and can fail on a table with
    millions of rows, so it must not be sent when the type did not change.

    A CHECK cannot be replaced in one step. The old one is dropped and the new
    one added, which is two statements and is why the constraint is handled
    last: if the type change fails, the check is still the one that matched
    the old type.
------------------------------------------------------------------------------}
function AlterDomainStatements(const AOld, ANew: TDdlDomain): string;
var
  Parts: TStringList;
  Name: string;
  I: Integer;
begin
  Result := '';
  if ANew.Name.IsEmpty then
  begin
    Exit;
  end;
  Name := ANew.Name.QualifiedQuoted;

  Parts := TStringList.Create;
  try
    if not SameText(Trim(AOld.DataType), Trim(ANew.DataType)) and
       (Trim(ANew.DataType) <> '') then
    begin
      Parts.Add('ALTER DOMAIN ' + Name + ' TYPE ' + Trim(ANew.DataType));
    end;

    if Trim(AOld.DefaultValue) <> Trim(ANew.DefaultValue) then
    begin
      if Trim(ANew.DefaultValue) = '' then
      begin
        Parts.Add('ALTER DOMAIN ' + Name + ' DROP DEFAULT');
      end
      else
      begin
        Parts.Add('ALTER DOMAIN ' + Name + ' SET DEFAULT ' +
          Trim(ANew.DefaultValue));
      end;
    end;

    if AOld.NotNull <> ANew.NotNull then
    begin
      if ANew.NotNull then
      begin
        Parts.Add('ALTER DOMAIN ' + Name + ' SET NOT NULL');
      end
      else
      begin
        Parts.Add('ALTER DOMAIN ' + Name + ' DROP NOT NULL');
      end;
    end;

    if Trim(AOld.CheckCondition) <> Trim(ANew.CheckCondition) then
    begin
      if Trim(AOld.CheckCondition) <> '' then
      begin
        Parts.Add('ALTER DOMAIN ' + Name + ' DROP CONSTRAINT');
      end;
      if Trim(ANew.CheckCondition) <> '' then
      begin
        Parts.Add('ALTER DOMAIN ' + Name + ' ADD CONSTRAINT CHECK (' +
          Trim(ANew.CheckCondition) + ')');
      end;
    end;

    for I := 0 to Parts.Count - 1 do
    begin
      if Result <> '' then
      begin
        Result := Result + StatementBreak;
      end;
      Result := Result + Parts[I];
    end;
  finally
    Parts.Free;
  end;
end;

{------------------------------------------------------------------------------
  CreateIndexStatement
  ----------------------------------------------------------------------------
  Returns the CREATE INDEX statement for AIndex.

  Parameters:
    AIndex - What to create.

  Returns:
    The statement, or an empty string when a name, a table, or something to
    index is missing.

  Notes:
    The order - UNIQUE, then ASC/DESC, then INDEX - is Firebird's, and putting
    DESC after INDEX is a syntax error rather than a stylistic choice.

    ASC is not emitted: it is the default, and saying it adds nothing to a
    statement the user is going to read.
------------------------------------------------------------------------------}
function CreateIndexStatement(const AIndex: TDdlIndex): string;
var
  I: Integer;
  Columns: string;
begin
  Result := '';
  if AIndex.Name.IsEmpty or AIndex.TableName.IsEmpty then
  begin
    Exit;
  end;
  if (Trim(AIndex.ComputedBy) = '') and (Length(AIndex.Columns) = 0) then
  begin
    Exit;
  end;

  Result := 'CREATE ';
  if AIndex.Unique then
  begin
    Result := Result + 'UNIQUE ';
  end;
  if AIndex.Descending then
  begin
    Result := Result + 'DESCENDING ';
  end;
  Result := Result + 'INDEX ' + AIndex.Name.QualifiedQuoted + ' ON ' +
    AIndex.TableName.QualifiedQuoted;

  if Trim(AIndex.ComputedBy) <> '' then
  begin
    Result := Result + ' COMPUTED BY (' + Trim(AIndex.ComputedBy) + ')';
    Exit;
  end;

  Columns := '';
  for I := 0 to High(AIndex.Columns) do
  begin
    if Columns <> '' then
    begin
      Columns := Columns + ', ';
    end;
    Columns := Columns + UserName(AIndex.Columns[I]);
  end;
  Result := Result + ' (' + Columns + ')';
end;

{------------------------------------------------------------------------------
  AlterIndexActiveStatement
  ----------------------------------------------------------------------------
  Returns the statement that activates or deactivates an index.

  Parameters:
    AName   - The index's name.
    AActive - True to activate, False to deactivate.

  Returns:
    The statement, or an empty string for no name.

  Notes:
    Reactivating an index rebuilds it, which is the usual reason to deactivate
    one first: a bulk load runs faster without the index maintained row by
    row.
------------------------------------------------------------------------------}
function AlterIndexActiveStatement(const AName: TIdentifier;
  AActive: Boolean): string;
begin
  if AName.IsEmpty then
  begin
    Exit('');
  end;
  Result := 'ALTER INDEX ' + AName.QualifiedQuoted;
  if AActive then
  begin
    Result := Result + ' ACTIVE';
  end
  else
  begin
    Result := Result + ' INACTIVE';
  end;
end;

{------------------------------------------------------------------------------
  CreateTableStatement
  ----------------------------------------------------------------------------
  Returns the CREATE TABLE statement for ATable.

  Parameters:
    ATable - What to create.

  Returns:
    The statement, laid out one column per line, or an empty string when there
    is no name or no column.

  Notes:
    The primary key is written as a table-level constraint even when it is one
    column, so that the generated statement has one shape rather than two and
    a second key column can be added by editing a list rather than by moving
    the keyword.

    The constraint is left unnamed. Firebird will name it, and inventing a
    name here would put our naming convention into the user's database.
------------------------------------------------------------------------------}
function CreateTableStatement(const ATable: TDdlTable): string;
var
  Lines: TStringList;
  I: Integer;
  Key: string;
begin
  Result := '';
  if ATable.Name.IsEmpty or (Length(ATable.Columns) = 0) then
  begin
    Exit;
  end;

  Lines := TStringList.Create;
  try
    for I := 0 to High(ATable.Columns) do
    begin
      if Trim(ATable.Columns[I].Name) = '' then
      begin
        Continue;
      end;
      Lines.Add('  ' + ATable.Columns[I].AsClause);
    end;

    if Lines.Count = 0 then
    begin
      Exit;
    end;

    Key := '';
    for I := 0 to High(ATable.PrimaryKey) do
    begin
      if Trim(ATable.PrimaryKey[I]) = '' then
      begin
        Continue;
      end;
      if Key <> '' then
      begin
        Key := Key + ', ';
      end;
      Key := Key + UserName(ATable.PrimaryKey[I]);
    end;
    if Key <> '' then
    begin
      Lines.Add('  PRIMARY KEY (' + Key + ')');
    end;

    Result := 'CREATE TABLE ' + ATable.Name.QualifiedQuoted + ' (' +
      LineEnding;
    for I := 0 to Lines.Count - 1 do
    begin
      Result := Result + Lines[I];
      if I < Lines.Count - 1 then
      begin
        Result := Result + ',';
      end;
      Result := Result + LineEnding;
    end;
    Result := Result + ')';
  finally
    Lines.Free;
  end;
end;

end.
