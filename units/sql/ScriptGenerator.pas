{==============================================================================
  Unit:        ScriptGenerator
  Purpose:     Builds the SELECT / INSERT / UPDATE / DELETE / MERGE / EXECUTE
               statements behind the "Script as..." command.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, Identifier

  Borrowed from FlameRobin, where "Script as..." is among the most-used
  commands, and for a plain reason: nobody wants to type forty column names,
  and getting one of them wrong in an UPDATE is how the wrong rows get changed.

  The generated statements are meant to be EDITED, not run blind. An UPDATE or
  DELETE is therefore emitted with a WHERE clause built from the primary key,
  and when there is no primary key the WHERE clause is emitted as a comment the
  user must complete - never omitted, because an UPDATE with no WHERE that
  looks finished is a loaded gun.
==============================================================================}
unit ScriptGenerator;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Identifier;

type
  { What kind of statement to build. }
  TScriptKind = (
    skSelect,      // SELECT FIRST n <columns> FROM <relation>
    skInsert,      // INSERT INTO <relation> (<columns>) VALUES (...)
    skUpdate,      // UPDATE <relation> SET ... WHERE <key>
    skDelete,      // DELETE FROM <relation> WHERE <key>
    skMerge,       // MERGE INTO <relation> USING ... ON ...
    skExecute      // EXECUTE PROCEDURE <name> (...)
  );

const
  { How many rows the generated SELECT asks for. Enough to see the shape of
    the data, few enough that running it by accident on a large table costs
    nothing. }
  DefaultSelectRowCount = 100;

{ Returns the menu caption for a script kind. }
function ScriptKindCaption(AKind: TScriptKind): string;

{ Builds a statement for one relation.

  Parameters:
    AKind      - Which statement to build.
    ARelation  - The relation, already schema-aware.
    AColumns   - Column names, in table order. Must not be empty except for
                 skExecute.
    AKeyColumns - Primary key column names, or empty when the relation has no
                 primary key.
    ARowCount  - Row limit for skSelect.

  Returns:
    The statement, formatted over several lines so it is readable when pasted
    into the editor. An empty string when the kind cannot be built from what
    was supplied. }
function GenerateRelationScript(AKind: TScriptKind;
  const ARelation: TIdentifier; AColumns, AKeyColumns: TStrings;
  ARowCount: Integer = DefaultSelectRowCount): string;

{ Renders one user-entered value as a SQL literal of the right shape.

  Parameters:
    AValue    - What the user typed. An empty string, or the word NULL in any
                case, yields NULL.
    ADataType - The parameter's declared type as rendered by the metadata
                query: 'VARCHAR(30)', 'INTEGER', 'TIMESTAMP' and so on.

  Returns:
    'NULL', a quoted literal, or the value unchanged for numeric types.

  Notes:
    Quoting is decided by the DECLARED type, not by what the value looks like.
    A VARCHAR parameter given 007 must be sent as '007'; deciding by
    appearance would send 7 and silently change the meaning. Single quotes in
    the value are doubled, which is also what stops a typed value from ending
    the literal early. }
function SqlLiteralForType(const AValue, ADataType: string): string;

{ Builds a call to a procedure with the given argument literals.

  Parameters:
    ARoutine    - The procedure.
    AArguments  - Already-rendered literals, in parameter order.
    ASelectable - True for a selectable procedure, which is called with SELECT.

  Returns:
    'SELECT * FROM P (a, b)' or 'EXECUTE PROCEDURE P (a, b)'. }
function BuildRoutineCall(const ARoutine: TIdentifier; AArguments: TStrings;
  ASelectable: Boolean): string;

{ Builds an EXECUTE PROCEDURE statement.

  Parameters:
    ARoutine       - The procedure.
    AInputParams   - Names of the input parameters, in order.

  Returns:
    'EXECUTE PROCEDURE NAME (:P1, :P2)', with the parameters left as named
    placeholders for the user to replace. }
function GenerateExecuteScript(const ARoutine: TIdentifier;
  AInputParams: TStrings): string;

implementation

const
  Indent = '  ';

{------------------------------------------------------------------------------
  ScriptKindCaption
  ----------------------------------------------------------------------------
  Returns the menu caption for a script kind.
------------------------------------------------------------------------------}
function ScriptKindCaption(AKind: TScriptKind): string;
begin
  case AKind of
    skSelect: Result := 'SELECT';
    skInsert: Result := 'INSERT';
    skUpdate: Result := 'UPDATE';
    skDelete: Result := 'DELETE';
    skMerge:  Result := 'MERGE';
    skExecute: Result := 'EXECUTE';
  else
    Result := '';
  end;
end;

{------------------------------------------------------------------------------
  QuotedColumn
  ----------------------------------------------------------------------------
  Returns one column name ready to paste into a statement.

  Parameters:
    AName - The bare column name as stored in RDB$.

  Returns:
    The name quoted only if it has to be, so ordinary statements stay readable
    and unusual names still work.
------------------------------------------------------------------------------}
function QuotedColumn(const AName: string): string;
begin
  Result := TIdentifier.FromDatabase(AName).Quoted;
end;

{------------------------------------------------------------------------------
  ColumnList
  ----------------------------------------------------------------------------
  Joins column names into a comma-separated list.

  Parameters:
    AColumns   - The names.
    APrefix    - Text put before each name, such as 'NEW.'.
    APerLine   - How many names per line; 0 puts them all on one line.

  Returns:
    The list, indented and wrapped.
------------------------------------------------------------------------------}
function ColumnList(AColumns: TStrings; const APrefix: string = '';
  APerLine: Integer = 4): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to AColumns.Count - 1 do
  begin
    if I > 0 then
    begin
      Result := Result + ',';
      if (APerLine > 0) and (I mod APerLine = 0) then
        Result := Result + LineEnding + Indent
      else
        Result := Result + ' ';
    end;
    Result := Result + APrefix + QuotedColumn(AColumns[I]);
  end;
end;

{------------------------------------------------------------------------------
  KeyPredicate
  ----------------------------------------------------------------------------
  Builds the WHERE clause matching one row by its key.

  Parameters:
    AKeyColumns - The key columns; may be empty.
    APrefix     - Table alias prefix for the left side, or an empty string.

  Returns:
    'WHERE A = :A AND B = :B', or a commented placeholder when there is no key.

  Notes:
    The placeholder is deliberately a comment that does not parse as a finished
    statement. A user who runs it gets a syntax error, which is the correct
    outcome: an UPDATE that silently affects every row is the single most
    destructive thing a tool like this can generate.
------------------------------------------------------------------------------}
function KeyPredicate(AKeyColumns: TStrings;
  const APrefix: string = ''): string;
var
  I: Integer;
begin
  if (AKeyColumns = nil) or (AKeyColumns.Count = 0) then
    Exit('WHERE /* no primary key - complete this condition */');

  Result := 'WHERE ';
  for I := 0 to AKeyColumns.Count - 1 do
  begin
    if I > 0 then
      Result := Result + LineEnding + Indent + '  AND ';
    Result := Result + APrefix + QuotedColumn(AKeyColumns[I]) +
      ' = :' + AKeyColumns[I];
  end;
end;

{------------------------------------------------------------------------------
  GenerateRelationScript
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function GenerateRelationScript(AKind: TScriptKind;
  const ARelation: TIdentifier; AColumns, AKeyColumns: TStrings;
  ARowCount: Integer): string;
var
  I: Integer;
  Name_, Assignments, Placeholders: string;
begin
  Result := '';
  Name_ := ARelation.QualifiedQuoted;

  if (AColumns = nil) or (AColumns.Count = 0) then
    Exit;

  case AKind of
    skSelect:
      Result :=
        Format('SELECT FIRST %d', [ARowCount]) + LineEnding +
        Indent + ColumnList(AColumns) + LineEnding +
        'FROM ' + Name_;

    skInsert:
      begin
        Placeholders := '';
        for I := 0 to AColumns.Count - 1 do
        begin
          if I > 0 then
          begin
            Placeholders := Placeholders + ',';
            if I mod 4 = 0 then
              Placeholders := Placeholders + LineEnding + Indent
            else
              Placeholders := Placeholders + ' ';
          end;
          Placeholders := Placeholders + ':' + AColumns[I];
        end;

        Result :=
          'INSERT INTO ' + Name_ + ' (' + LineEnding +
          Indent + ColumnList(AColumns) + LineEnding +
          ') VALUES (' + LineEnding +
          Indent + Placeholders + LineEnding +
          ')';
      end;

    skUpdate:
      begin
        Assignments := '';
        for I := 0 to AColumns.Count - 1 do
        begin
          if I > 0 then
            Assignments := Assignments + ',' + LineEnding + Indent;
          Assignments := Assignments + QuotedColumn(AColumns[I]) +
            ' = :' + AColumns[I];
        end;

        Result :=
          'UPDATE ' + Name_ + ' SET' + LineEnding +
          Indent + Assignments + LineEnding +
          KeyPredicate(AKeyColumns);
      end;

    skDelete:
      Result :=
        'DELETE FROM ' + Name_ + LineEnding +
        KeyPredicate(AKeyColumns);

    skMerge:
      begin
        if (AKeyColumns = nil) or (AKeyColumns.Count = 0) then
          Exit('/* MERGE needs a primary key to match on. */');

        Assignments := '';
        for I := 0 to AKeyColumns.Count - 1 do
        begin
          if I > 0 then
            Assignments := Assignments + LineEnding + Indent + '  AND ';
          Assignments := Assignments + 'tgt.' + QuotedColumn(AKeyColumns[I]) +
            ' = src.' + QuotedColumn(AKeyColumns[I]);
        end;

        Placeholders := '';
        for I := 0 to AColumns.Count - 1 do
        begin
          if AKeyColumns.IndexOf(AColumns[I]) >= 0 then
            Continue;                        // never update the key itself
          if Placeholders <> '' then
            Placeholders := Placeholders + ',' + LineEnding + Indent + Indent;
          Placeholders := Placeholders + 'tgt.' + QuotedColumn(AColumns[I]) +
            ' = src.' + QuotedColumn(AColumns[I]);
        end;

        Result :=
          'MERGE INTO ' + Name_ + ' AS tgt' + LineEnding +
          'USING (' + LineEnding +
          Indent + 'SELECT ' + ColumnList(AColumns, '', 0) +
            ' FROM ' + Name_ + LineEnding +
          ') AS src' + LineEnding +
          'ON ' + Assignments + LineEnding +
          'WHEN MATCHED THEN UPDATE SET' + LineEnding +
          Indent + Indent + Placeholders + LineEnding +
          'WHEN NOT MATCHED THEN INSERT (' + LineEnding +
          Indent + ColumnList(AColumns) + LineEnding +
          ') VALUES (' + LineEnding +
          Indent + ColumnList(AColumns, 'src.') + LineEnding +
          ')';
      end;
  end;
end;

{------------------------------------------------------------------------------
  SqlLiteralForType
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function SqlLiteralForType(const AValue, ADataType: string): string;
var
  Trimmed, TypeName: string;

  function TypeStartsWith(const APrefix: string): Boolean;
  begin
    Result := Copy(TypeName, 1, Length(APrefix)) = APrefix;
  end;

begin
  Trimmed := Trim(AValue);
  if (Trimmed = '') or SameText(Trimmed, 'NULL') then
    Exit('NULL');

  TypeName := UpperCase(Trim(ADataType));

  { Types whose values are written as quoted literals. BLOB is here because a
    text blob argument is given as a string; a binary one cannot be typed into
    a dialog at all. }
  if TypeStartsWith('CHAR') or TypeStartsWith('VARCHAR') or
     TypeStartsWith('BLOB') or TypeStartsWith('DATE') or
     TypeStartsWith('TIME') or TypeStartsWith('TIMESTAMP') then
    Exit('''' + StringReplace(Trimmed, '''', '''''', [rfReplaceAll]) + '''');

  { BOOLEAN takes the bare words. }
  if TypeStartsWith('BOOLEAN') then
  begin
    if SameText(Trimmed, 'TRUE') or (Trimmed = '1') then
      Exit('TRUE');
    if SameText(Trimmed, 'FALSE') or (Trimmed = '0') then
      Exit('FALSE');
    Exit('NULL');
  end;

  { Everything else is numeric and goes through unquoted. A value that is not
    actually a number will be rejected by the server, with a message naming the
    parameter - which is more useful than this function guessing. }
  Result := Trimmed;
end;

{------------------------------------------------------------------------------
  BuildRoutineCall
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function BuildRoutineCall(const ARoutine: TIdentifier; AArguments: TStrings;
  ASelectable: Boolean): string;
var
  I: Integer;
  Args: string;
begin
  Args := '';
  if AArguments <> nil then
  begin
    for I := 0 to AArguments.Count - 1 do
    begin
      if I > 0 then
        Args := Args + ', ';
      Args := Args + AArguments[I];
    end;
  end;

  if ASelectable then
    Result := 'SELECT * FROM ' + ARoutine.QualifiedQuoted
  else
    Result := 'EXECUTE PROCEDURE ' + ARoutine.QualifiedQuoted;

  if Args <> '' then
    Result := Result + ' (' + Args + ')';
end;

{------------------------------------------------------------------------------
  GenerateExecuteScript
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function GenerateExecuteScript(const ARoutine: TIdentifier;
  AInputParams: TStrings): string;
var
  I: Integer;
  Params: string;
begin
  Result := 'EXECUTE PROCEDURE ' + ARoutine.QualifiedQuoted;

  if (AInputParams = nil) or (AInputParams.Count = 0) then
    Exit;

  Params := '';
  for I := 0 to AInputParams.Count - 1 do
  begin
    if I > 0 then
      Params := Params + ', ';
    Params := Params + ':' + AInputParams[I];
  end;

  Result := Result + ' (' + Params + ')';
end;

end.
