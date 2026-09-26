{==============================================================================
  Unit:        MetadataSqlProviderFB4
  Purpose:     Metadata SQL for Firebird 4.0. Inherits Firebird 3 and adds only
               what changed.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  MetadataSqlProvider, MetadataSqlProviderFB3

  What Firebird 4 adds that the tree can see:
    - RDB$PUBLICATIONS, the logical replication publications
    - RDB$SECURITY_CLASS work behind SQL SECURITY, which is a property rather
      than a new folder and therefore lands in M2, not here
  Data type additions (DECFLOAT, INT128, time zones) change how a column is
  described, not which objects exist, so they also belong to M2.
==============================================================================}
unit MetadataSqlProviderFB4;

{$mode objfpc}{$H+}

interface

uses
  MetadataSqlProviderFB3;

type
  { TMetadataSqlProviderFB4
    Firebird 4.0 metadata queries. }
  TMetadataSqlProviderFB4 = class(TMetadataSqlProviderFB3)
  protected
    function ColumnTypeExpr(const AFieldAlias: string): string; override;
  public
    function PublicationsSQL: string; override;
  end;

implementation

uses
  SysUtils, StrUtils;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB4.ColumnTypeExpr
  ----------------------------------------------------------------------------
  Extends the Firebird 3 type rendering with the types Firebird 4 added.

  Parameters:
    AFieldAlias - Alias of the RDB$FIELDS row in the calling query.

  Returns:
    The inherited CASE expression with the new field type codes handled.

  Notes:
    Rather than restate the whole CASE, the new cases are spliced in front of
    the inherited ELSE branch. The inherited expression is built by the base
    class and ends with 'ELSE ... END', so the insertion point is its last
    ' ELSE ' - a small piece of string surgery that is worth it to keep one
    copy of the twenty common types.

    Codes: 24 DECFLOAT(16), 25 DECFLOAT(34), 26 INT128, 28 TIME WITH TIME ZONE,
    29 TIMESTAMP WITH TIME ZONE.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB4.ColumnTypeExpr(
  const AFieldAlias: string): string;
var
  Inherited_, Extra, Precision, Scale: string;
  ElsePos: Integer;
begin
  Inherited_ := inherited ColumnTypeExpr(AFieldAlias);

  Precision := NumText('COALESCE(' + AFieldAlias + '.RDB$FIELD_PRECISION, 0)');
  Scale := NumText('(-COALESCE(' + AFieldAlias + '.RDB$FIELD_SCALE, 0))');

  Extra :=
    ' WHEN 24 THEN ''DECFLOAT(16)''' +
    ' WHEN 25 THEN ''DECFLOAT(34)''' +
    ' WHEN 26 THEN CASE WHEN COALESCE(' + AFieldAlias + '.RDB$FIELD_SCALE, 0) = 0' +
      ' THEN ''INT128''' +
      ' ELSE ''NUMERIC('' || ' + Precision + ' || '','' || ' + Scale + ' || '')'' END' +
    ' WHEN 28 THEN ''TIME WITH TIME ZONE''' +
    ' WHEN 29 THEN ''TIMESTAMP WITH TIME ZONE''';

  ElsePos := RPos(' ELSE ', Inherited_);
  if ElsePos > 0 then
    Result := Copy(Inherited_, 1, ElsePos - 1) + Extra +
      Copy(Inherited_, ElsePos, MaxInt)
  else
    Result := Inherited_;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB4.PublicationsSQL
  ----------------------------------------------------------------------------
  Returns the query listing replication publications.

  Returns:
    SQL obeying the column contract. RDB$PUBLICATIONS has no id column, so
    column 3 is NULL.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB4.PublicationsSQL: string;
begin
  Result :=
    SelectList('p', 'RDB$PUBLICATION_NAME', '') +
    ' FROM RDB$PUBLICATIONS p' +
    ' WHERE ' + UserObjectPredicate('p') +
    ' ORDER BY 2';
end;

end.
