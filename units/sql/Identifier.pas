{==============================================================================
  Unit:        Identifier
  Purpose:     A Firebird object name that knows its own quoting and schema
               rules. Every name in the metadata model is a TIdentifier and
               never a raw string.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils, FirebirdKeywords

  Why this exists: quoting, case folding and (from Firebird 6) two-part
  schema-qualified names are decisions that must be made identically in every
  generated statement. Concentrating them here is what makes FB6 schema support
  a change to one unit rather than to every DDL generator in the program.

  Firebird rules this implements:
    - An unquoted identifier is folded to upper case by the engine, so names
      stored in RDB$ are upper case unless they were created quoted.
    - A name may be written without quotes only when it consists of A-Z, 0-9,
      _ and $, starts with a letter, and is not a reserved word.
    - Inside a quoted name, a double quote is written twice.
    - RDB$ name columns are CHAR and come back space-padded; the padding is
      never part of the name.
==============================================================================}
unit Identifier;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, FirebirdKeywords;

type
  { TIdentifier
    One object name, optionally qualified by a schema. A record because a name
    has no identity of its own and is copied constantly. }
  TIdentifier = record
  private
    FName: string;
    FSchema: string;
  public
    { Builds an identifier from a name as stored in the database. Trailing
      padding from CHAR columns is removed; the case is kept exactly. }
    class function FromDatabase(const AName: string): TIdentifier; static;

    { Builds a schema-qualified identifier from names as stored in the
      database. Used on Firebird 6 and newer. }
    class function FromDatabaseQualified(const ASchema,
      AName: string): TIdentifier; static;

    { Builds an identifier from text the user typed. A "quoted" value keeps its
      case exactly; anything else is folded to upper case, which is what the
      engine would have done. }
    class function FromUserInput(const AText: string): TIdentifier; static;

    { Returns an empty identifier. }
    class function Empty: TIdentifier; static;

    { Returns True when no name is set. }
    function IsEmpty: Boolean;

    { Returns True when the name cannot be written without double quotes. }
    function NeedsQuoting: Boolean;

    { The bare name, exactly as stored. Never use this to build SQL. }
    function AsString: string;

    { The name ready to paste into a statement: quoted when it has to be,
      bare when it does not. }
    function Quoted: string;

    { The schema-qualified name ready to paste into a statement. Falls back to
      Quoted when there is no schema. }
    function QualifiedQuoted: string;

    { The name as shown in the tree and on property pages: SCHEMA.NAME, with
      no quotes, because quotes are noise to a reader. }
    function DisplayName: string;

    { Returns True when both identifiers name the same object. Comparison is
      case-sensitive, because in Firebird "Name" and NAME are different
      objects. }
    function SameAs(const AOther: TIdentifier): Boolean;

    { The bare name as stored in RDB$. }
    property Name: string read FName;
    { The schema, or an empty string on Firebird 5 and older. }
    property Schema: string read FSchema;
  end;

{ Returns AName wrapped in double quotes, with inner quotes doubled. Exposed
  for the few places that must quote a name they did not get as a
  TIdentifier, such as literal system table names. }
function QuoteName(const AName: string): string;

{ Returns True when AName can be written in SQL without double quotes. }
function IsPlainName(const AName: string): Boolean;

implementation

{------------------------------------------------------------------------------
  QuoteName
  ----------------------------------------------------------------------------
  Wraps a name in double quotes, doubling any quote inside it.

  Parameters:
    AName - The bare name.

  Returns:
    The quoted name, including the surrounding quotes.
------------------------------------------------------------------------------}
function QuoteName(const AName: string): string;
begin
  Result := '"' + StringReplace(AName, '"', '""', [rfReplaceAll]) + '"';
end;

{------------------------------------------------------------------------------
  IsPlainName
  ----------------------------------------------------------------------------
  Decides whether a name is writable without quotes.

  Parameters:
    AName - The bare name.

  Returns:
    True when AName is upper case, made only of A-Z, 0-9, _ and $, starts with
    a letter, and is not a reserved word.
------------------------------------------------------------------------------}
function IsPlainName(const AName: string): Boolean;
var
  I: Integer;
begin
  if AName = '' then
    Exit(False);

  if not (AName[1] in ['A'..'Z']) then
    Exit(False);

  for I := 2 to Length(AName) do
  begin
    if not (AName[I] in ['A'..'Z', '0'..'9', '_', '$']) then
      Exit(False);
  end;

  Result := not IsReservedWord(AName);
end;

{------------------------------------------------------------------------------
  TIdentifier.FromDatabase
  ----------------------------------------------------------------------------
  Builds an identifier from a name read out of a system table.

  Parameters:
    AName - The RDB$ column value, possibly space-padded.

  Returns:
    The identifier, with padding removed and case preserved.
------------------------------------------------------------------------------}
class function TIdentifier.FromDatabase(const AName: string): TIdentifier;
begin
  Result.FName := TrimRight(AName);
  Result.FSchema := '';
end;

{------------------------------------------------------------------------------
  TIdentifier.FromDatabaseQualified
  ----------------------------------------------------------------------------
  Builds a schema-qualified identifier from system table values.

  Parameters:
    ASchema - RDB$SCHEMA_NAME, possibly space-padded or empty.
    AName   - The object name, possibly space-padded.

  Returns:
    The identifier. An empty schema yields an unqualified identifier, so the
    same call works against every supported server version.
------------------------------------------------------------------------------}
class function TIdentifier.FromDatabaseQualified(const ASchema,
  AName: string): TIdentifier;
begin
  Result.FName := TrimRight(AName);
  Result.FSchema := TrimRight(ASchema);
end;

{------------------------------------------------------------------------------
  TIdentifier.FromUserInput
  ----------------------------------------------------------------------------
  Builds an identifier from text a user typed into a dialog.

  Parameters:
    AText - The typed text. Surrounding double quotes mean "this exact case";
            anything else is folded to upper case as the engine would.

  Returns:
    The identifier. A quoted empty string yields an empty identifier rather
    than a name of two quote characters.
------------------------------------------------------------------------------}
class function TIdentifier.FromUserInput(const AText: string): TIdentifier;
var
  Text: string;
begin
  Text := Trim(AText);
  Result.FSchema := '';

  if (Length(Text) >= 2) and (Text[1] = '"') and (Text[Length(Text)] = '"') then
  begin
    Text := Copy(Text, 2, Length(Text) - 2);
    Result.FName := StringReplace(Text, '""', '"', [rfReplaceAll]);
  end
  else
    Result.FName := UpperCase(Text);
end;

{------------------------------------------------------------------------------
  TIdentifier.Empty
  ----------------------------------------------------------------------------
  Returns an identifier with no name and no schema.
------------------------------------------------------------------------------}
class function TIdentifier.Empty: TIdentifier;
begin
  Result.FName := '';
  Result.FSchema := '';
end;

{------------------------------------------------------------------------------
  TIdentifier.IsEmpty
  ----------------------------------------------------------------------------
  Returns True when no name is set.
------------------------------------------------------------------------------}
function TIdentifier.IsEmpty: Boolean;
begin
  Result := FName = '';
end;

{------------------------------------------------------------------------------
  TIdentifier.NeedsQuoting
  ----------------------------------------------------------------------------
  Returns True when the name cannot appear in SQL without double quotes.
------------------------------------------------------------------------------}
function TIdentifier.NeedsQuoting: Boolean;
begin
  Result := not IsPlainName(FName);
end;

{------------------------------------------------------------------------------
  TIdentifier.AsString
  ----------------------------------------------------------------------------
  Returns the bare name.

  Notes:
    For comparison and display only. Building SQL from this instead of from
    Quoted is the bug this whole unit exists to prevent.
------------------------------------------------------------------------------}
function TIdentifier.AsString: string;
begin
  Result := FName;
end;

{------------------------------------------------------------------------------
  TIdentifier.Quoted
  ----------------------------------------------------------------------------
  Returns the name ready to be pasted into a statement.

  Returns:
    The bare name when it is a plain upper-case identifier, otherwise the name
    in double quotes. An empty identifier yields an empty string.
------------------------------------------------------------------------------}
function TIdentifier.Quoted: string;
begin
  if FName = '' then
    Exit('');

  if IsPlainName(FName) then
    Result := FName
  else
    Result := QuoteName(FName);
end;

{------------------------------------------------------------------------------
  TIdentifier.QualifiedQuoted
  ----------------------------------------------------------------------------
  Returns the schema-qualified name ready to be pasted into a statement.

  Returns:
    'SCHEMA.NAME' with each part quoted as needed, or just the name when there
    is no schema.
------------------------------------------------------------------------------}
function TIdentifier.QualifiedQuoted: string;
var
  QuotedSchema: string;
begin
  if FSchema = '' then
    Exit(Quoted);

  if IsPlainName(FSchema) then
    QuotedSchema := FSchema
  else
    QuotedSchema := QuoteName(FSchema);

  Result := QuotedSchema + '.' + Quoted;
end;

{------------------------------------------------------------------------------
  TIdentifier.DisplayName
  ----------------------------------------------------------------------------
  Returns the name as shown to the user.

  Returns:
    'SCHEMA.NAME', or just the name when there is no schema. Never quoted:
    quotes are noise on screen, and the tree is not SQL.
------------------------------------------------------------------------------}
function TIdentifier.DisplayName: string;
begin
  if FSchema = '' then
    Result := FName
  else
    Result := FSchema + '.' + FName;
end;

{------------------------------------------------------------------------------
  TIdentifier.SameAs
  ----------------------------------------------------------------------------
  Compares two identifiers.

  Parameters:
    AOther - The identifier to compare with.

  Returns:
    True when schema and name match exactly.

  Notes:
    The comparison is case-sensitive on purpose. In Firebird a table created as
    "Customer" and one created as CUSTOMER are two different tables, and a
    case-insensitive match here would silently conflate them.
------------------------------------------------------------------------------}
function TIdentifier.SameAs(const AOther: TIdentifier): Boolean;
begin
  Result := (FName = AOther.FName) and (FSchema = AOther.FSchema);
end;

end.
