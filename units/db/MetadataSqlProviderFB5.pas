{==============================================================================
  Unit:        MetadataSqlProviderFB5
  Purpose:     Metadata SQL for Firebird 5.0. Inherits Firebird 4.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  MetadataSqlProviderFB4

  Firebird 5 changes nothing about WHICH objects exist, so no collection query
  differs from Firebird 4. What it adds is detail on existing objects:
    - RDB$INDICES.RDB$CONDITION_SOURCE, the WHERE clause of a partial index
    - the profiler tables PLG$PROF_*
    - EXPLAIN plans
  Those are read by the index property page and the SQL editor, in M2 and M3.

  This class exists anyway rather than mapping Firebird 5 onto the Firebird 4
  provider, so that the version-to-provider mapping stays one to one and the
  first Firebird 5 difference has an obvious home.
==============================================================================}
unit MetadataSqlProviderFB5;

{$mode objfpc}{$H+}

interface

uses
  MetadataSqlProviderFB4;

type
  { TMetadataSqlProviderFB5
    Firebird 5.0 metadata queries. Identical to Firebird 4 for collections;
    adds the partial-index condition to the index detail. }
  TMetadataSqlProviderFB5 = class(TMetadataSqlProviderFB4)
  public
    function IndexInfoSQL(const AObjectName: string): string; override;
  end;

implementation

uses
  SysUtils, StrUtils;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB5.IndexInfoSQL
  ----------------------------------------------------------------------------
  Adds the partial-index condition to the inherited index description.

  Parameters:
    AObjectName - The index's bare name.

  Returns:
    The Firebird 4 query with one more row appended.

  Notes:
    RDB$CONDITION_SOURCE holds the WHERE clause of a partial index and exists
    only from Firebird 5, so this cannot live in the base query: on an older
    server it would fail with "column unknown" rather than simply showing
    nothing.

    The extra row is spliced in before the inherited ORDER BY, which is the
    same technique used for the type expression in the Firebird 4 provider.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB5.IndexInfoSQL(
  const AObjectName: string): string;
var
  Inherited_, Extra: string;
  OrderPos: Integer;
begin
  Inherited_ := inherited IndexInfoSQL(AObjectName);

  Extra :=
    ' UNION ALL SELECT ''Partial index condition'',' +
    ' COALESCE(TRIM(CAST(i.RDB$CONDITION_SOURCE AS VARCHAR(1000))), ''(none)''), 9' +
    ' FROM RDB$INDICES i WHERE i.RDB$INDEX_NAME = ' + QuotedStr(AObjectName);

  OrderPos := RPos(' ORDER BY ', Inherited_);
  if OrderPos > 0 then
    Result := Copy(Inherited_, 1, OrderPos - 1) + Extra +
      Copy(Inherited_, OrderPos, MaxInt)
  else
    Result := Inherited_ + Extra;
end;

end.
