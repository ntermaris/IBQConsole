{==============================================================================
  Unit:        MetadataSqlProviderFB6
  Purpose:     Metadata SQL for Firebird 6.0, where every object lives in a
               schema and names become two part.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  MetadataSqlProvider, MetadataSqlProviderFB5

  This unit is the payoff of the whole provider design. Firebird 6 adds
  RDB$SCHEMA_NAME to every metadata table, which in a naive tool would mean
  editing every query in the program. Here the base class builds its SELECT
  list through SchemaColumnExpr, so overriding that one method schema-qualifies
  every inherited query at once. The only genuinely new query is the list of
  schemas itself.
==============================================================================}
unit MetadataSqlProviderFB6;

{$mode objfpc}{$H+}

interface

uses
  MetadataSqlProviderFB5;

type
  { TMetadataSqlProviderFB6
    Firebird 6.0 metadata queries, schema aware. }
  TMetadataSqlProviderFB6 = class(TMetadataSqlProviderFB5)
  protected
    function SchemaColumnExpr(const AAlias: string): string; override;
  public
    function HasSchemas: Boolean; override;
    function SchemasSQL: string; override;
  end;

implementation

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB6.HasSchemas
  ----------------------------------------------------------------------------
  Returns True: this server qualifies objects with a schema.

  Notes:
    Loaders read this to decide whether to build identifiers with
    TIdentifier.FromDatabaseQualified, and the DDL generators read it to decide
    whether to emit two-part names.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB6.HasSchemas: Boolean;
begin
  Result := True;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB6.SchemaColumnExpr
  ----------------------------------------------------------------------------
  Returns the real schema column instead of the typed NULL used by older
  servers.

  Parameters:
    AAlias - Alias of the query's main table.

  Returns:
    '<alias>.RDB$SCHEMA_NAME'.

  Notes:
    Every inherited collection query builds its SELECT list through the base
    class's SelectList, which calls this. Overriding it here is therefore the
    entire schema-qualification change for tables, views, procedures,
    functions, packages, triggers, generators, exceptions, domains, indexes,
    roles, collations and filters together.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB6.SchemaColumnExpr(
  const AAlias: string): string;
begin
  Result := AAlias + '.RDB$SCHEMA_NAME';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB6.SchemasSQL
  ----------------------------------------------------------------------------
  Returns the query listing schemas.

  Returns:
    SQL obeying the column contract. A schema is not itself inside a schema,
    so column 1 is NULL here even on Firebird 6.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB6.SchemasSQL: string;
begin
  Result :=
    'SELECT CAST(NULL AS VARCHAR(63)) AS SCHEMA_NAME, ' +
    's.RDB$SCHEMA_NAME AS OBJ_NAME, ' +
    'CAST(NULL AS INTEGER) AS OBJ_ID ' +
    'FROM RDB$SCHEMAS s' +
    ' WHERE ' + UserObjectPredicate('s') +
    ' ORDER BY 2';
end;

end.
