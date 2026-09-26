{==============================================================================
  Unit:        DatabaseRow
  Purpose:     The neutral row type the database layer hands upwards. Carries
               exactly the three columns of the metadata column contract and
               nothing else.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  (nothing)

  This tiny unit is what keeps the layering honest. The model needs the rows a
  collection query produced; it must not learn about TIBSQL to get them, and
  the database layer must not learn about TMetaCollection to deliver them. A
  plain array of records satisfies both.
==============================================================================}
unit DatabaseRow;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils;

type
  TStringGridRow = array of string;

  { TDataTable
    A whole result set as text: column names and rows of strings.

    Property pages show metadata, they do not compute with it, so text is the
    right currency. Using it here means a detail query can return any shape at
    all without the model or the UI learning a database type - the same reason
    TMetaRow exists for collection queries, generalised.

    Nulls arrive as an empty string. Where the difference between NULL and ''
    matters - which for metadata is rare, but real for a column default - the
    query is expected to make it explicit, for example with COALESCE or a CASE
    that yields a marker. }
  TDataTable = record
    ColumnNames: array of string;
    Rows: array of TStringGridRow;

    { Number of rows held. }
    function RowCount: Integer;
    { Number of columns held. }
    function ColumnCount: Integer;
    { True when the result set has no rows. }
    function IsEmpty: Boolean;
    { Index of the named column, or -1. Case-insensitive. }
    function ColumnIndex(const AName: string): Integer;
    { The value at ARowIndex in the named column, or an empty string when the
      column or the row does not exist. }
    function Value(ARowIndex: Integer; const AColumnName: string): string;
    { The value at ARowIndex, AColumnIndex, or an empty string when out of
      range. }
    function ValueAt(ARowIndex, AColumnIndex: Integer): string;
  end;

type
  { One row of a metadata collection query, in the order fixed by the column
    contract in MetadataSqlProvider. }
  TMetaRow = record
    { Column 1: the object's schema, empty before Firebird 6. }
    SchemaName: string;
    { Column 2: the object's name, still space padded as CHAR columns are. }
    ObjectName: string;
    { Column 3: the RDB$ id, or -1 when the type has none. }
    ObjectId: Integer;
  end;

  TMetaRowArray = array of TMetaRow;

implementation

{------------------------------------------------------------------------------
  TDataTable.RowCount
  ----------------------------------------------------------------------------
  Returns how many rows the result set holds.
------------------------------------------------------------------------------}
function TDataTable.RowCount: Integer;
begin
  Result := Length(Rows);
end;

{------------------------------------------------------------------------------
  TDataTable.ColumnCount
  ----------------------------------------------------------------------------
  Returns how many columns the result set holds.
------------------------------------------------------------------------------}
function TDataTable.ColumnCount: Integer;
begin
  Result := Length(ColumnNames);
end;

{------------------------------------------------------------------------------
  TDataTable.IsEmpty
  ----------------------------------------------------------------------------
  Returns True when there are no rows.
------------------------------------------------------------------------------}
function TDataTable.IsEmpty: Boolean;
begin
  Result := Length(Rows) = 0;
end;

{------------------------------------------------------------------------------
  TDataTable.ColumnIndex
  ----------------------------------------------------------------------------
  Finds a column by name.

  Parameters:
    AName - Column name, compared without regard to case.

  Returns:
    The zero-based index, or -1 when there is no such column.
------------------------------------------------------------------------------}
function TDataTable.ColumnIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := Low(ColumnNames) to High(ColumnNames) do
  begin
    if SameText(ColumnNames[I], AName) then
      Exit(I);
  end;
  Result := -1;
end;

{------------------------------------------------------------------------------
  TDataTable.Value
  ----------------------------------------------------------------------------
  Reads one cell by column name.

  Parameters:
    ARowIndex   - Zero-based row.
    AColumnName - Column name, compared without regard to case.

  Returns:
    The cell's text, or an empty string when the row or column does not exist.

  Notes:
    Returns empty rather than raising, because a property page asking for a
    column its server version does not have is normal, not a defect.
------------------------------------------------------------------------------}
function TDataTable.Value(ARowIndex: Integer;
  const AColumnName: string): string;
begin
  Result := ValueAt(ARowIndex, ColumnIndex(AColumnName));
end;

{------------------------------------------------------------------------------
  TDataTable.ValueAt
  ----------------------------------------------------------------------------
  Reads one cell by position.

  Parameters:
    ARowIndex    - Zero-based row.
    AColumnIndex - Zero-based column.

  Returns:
    The cell's text, or an empty string when either index is out of range.
------------------------------------------------------------------------------}
function TDataTable.ValueAt(ARowIndex, AColumnIndex: Integer): string;
begin
  if (ARowIndex < 0) or (ARowIndex > High(Rows)) then
    Exit('');
  if (AColumnIndex < 0) or (AColumnIndex > High(Rows[ARowIndex])) then
    Exit('');
  Result := Rows[ARowIndex][AColumnIndex];
end;

end.
