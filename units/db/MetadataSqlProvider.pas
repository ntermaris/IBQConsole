{==============================================================================
  Unit:        MetadataSqlProvider
  Purpose:     Abstract base of the version-specific metadata SQL providers.
               Every RDB$ query in IBQConsole comes from one of these classes
               and from nowhere else.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils, ServerVersion

  This is the unit that makes "supports Firebird 3 through 6" tractable. The
  system tables differ between versions in ways that are not cosmetic - most of
  all in Firebird 6, where every object gains a schema and names become two
  part. Concentrating the SQL here means a version difference is a small
  override in one file instead of a version test at three hundred call sites.

  THE COLUMN CONTRACT
  Every collection query returns exactly three columns, in this order:

    1  SCHEMA_NAME  VARCHAR  - the object's schema, NULL before Firebird 6
    2  OBJ_NAME     CHAR     - the object's name, space padded
    3  OBJ_ID       INTEGER  - the RDB$ id, or NULL when the type has none

  Because Firebird 3 to 5 return a literal NULL for column 1, a loader is
  written once and works against every version. Names are NOT trimmed in SQL:
  TIdentifier.FromDatabase removes CHAR padding, and doing it in one place is
  cheaper than a TRIM() on every row of every query.
==============================================================================}
unit MetadataSqlProvider;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ServerVersion;

type
  { Which family of triggers a query should return. }
  TTriggerKind = (tkDML, tkDatabase, tkDDL);

  { The kinds of object that carry PSQL or view source, and a description.
    Deliberately narrower than TMetaNodeType: this unit describes SQL, and
    must not depend on the model's node enumeration. }
  TSourceObjectKind = (
    sokTable, sokView, sokProcedure, sokFunction, sokTrigger, sokPackage,
    sokException, sokDomain, sokGenerator, sokIndex, sokRole,
    sokCharacterSet, sokCollation
  );

  { TMetadataSqlProvider
    Supplies the metadata SQL for one connected server version.

    Never instantiated directly - ask TMetadataSqlProviderFactory for the
    provider matching a TServerVersion. }
  TMetadataSqlProvider = class(TObject)
  private
    FVersion: TServerVersion;
  protected
    { The expression yielding the schema name for a query whose main table has
      alias AAlias. Firebird 3 to 5 have no schemas and return a typed NULL;
      Firebird 6 overrides this to return the real column. }
    function SchemaColumnExpr(const AAlias: string): string; virtual;
    { The standard "not a system object" predicate for AAlias. }
    function UserObjectPredicate(const AAlias: string): string; virtual;
    { The standard "is a system object" predicate for AAlias. }
    function SystemObjectPredicate(const AAlias: string): string; virtual;
    { Builds the three-column SELECT list described in the column contract. }
    function SelectList(const AAlias, ANameColumn, AIdColumn: string): string;
  public
    constructor Create(const AVersion: TServerVersion);

    { True when this server qualifies objects with a schema, which changes how
      a loader reads column 1 and how DDL is generated. }
    function HasSchemas: Boolean; virtual;

    // -- connection interrogation ------------------------------------------

    { Returns the engine version string, e.g. '5.0.1'. One row, one column. }
    function EngineVersionSQL: string; virtual;
    { Returns SQL dialect, ODS major and ODS minor from MON$DATABASE. Used by
      the dialect check that refuses dialect 1 databases. }
    function DatabaseInfoSQL: string; virtual;

    // -- collections -------------------------------------------------------

    { Persistent and external tables. }
    function TablesSQL: string; virtual; abstract;
    { Global temporary tables. }
    function GlobalTemporaryTablesSQL: string; virtual; abstract;
    { System tables. }
    function SystemTablesSQL: string; virtual; abstract;
    { Views. }
    function ViewsSQL: string; virtual; abstract;
    { Stored procedures that are not inside a package. }
    function ProceduresSQL: string; virtual; abstract;
    { PSQL functions that are not inside a package. }
    function FunctionsSQL: string; virtual; abstract;
    { Declared external functions (legacy UDFs). }
    function ExternalFunctionsSQL: string; virtual; abstract;
    { Packages. }
    function PackagesSQL: string; virtual; abstract;
    { Triggers of one family. }
    function TriggersSQL(AKind: TTriggerKind): string; virtual; abstract;
    { Sequences (generators). }
    function GeneratorsSQL: string; virtual; abstract;
    { Exceptions. }
    function ExceptionsSQL: string; virtual; abstract;
    { Domains created by the user. }
    function DomainsSQL: string; virtual; abstract;
    { Domains created by the system. }
    function SystemDomainsSQL: string; virtual; abstract;
    { Indexes created by the user. }
    function IndicesSQL: string; virtual; abstract;
    { Indexes created by the system, which are the ones backing constraints. }
    function SystemIndicesSQL: string; virtual; abstract;
    { Roles. }
    function RolesSQL: string; virtual; abstract;
    { Character sets. }
    function CharacterSetsSQL: string; virtual; abstract;
    { Collations. }
    function CollationsSQL: string; virtual; abstract;
    { Blob filters. }
    function BlobFiltersSQL: string; virtual; abstract;
    { Users, from the security database. }
    function UsersSQL: string; virtual; abstract;
    { Publications. Empty string before Firebird 4. }
    function PublicationsSQL: string; virtual;
    { Schemas. Empty string before Firebird 6. }
    function SchemasSQL: string; virtual;

    // -- object detail -----------------------------------------------------
    //
    // Unlike the collection queries above, these have no fixed column shape:
    // a property page shows whatever columns the query returns. They take the
    // object name as a literal rather than a parameter, so the SQL that ran
    // can be shown in the log and pasted into an editor unchanged; every
    // caller passes a name that came from RDB$ and went back out through
    // TIdentifier, so it cannot carry an injection.

    { Columns of a table or view, with type, nullability, default, collation
      and - from Firebird 3 - identity information. }
    function RelationColumnsSQL(const AObjectName: string): string;
      virtual; abstract;
    { Indexes on a table, with uniqueness, direction, selectivity, activity and
      the constraint each one backs. }
    function RelationIndicesSQL(const AObjectName: string): string;
      virtual; abstract;
    { Constraints on a table: primary key, foreign key, unique and check. }
    function RelationConstraintsSQL(const AObjectName: string): string;
      virtual; abstract;
    { Triggers on a table or view. }
    function RelationTriggersSQL(const AObjectName: string): string;
      virtual; abstract;
    { Parameters of a procedure or function. }
    function RoutineParametersSQL(const AObjectName: string): string;
      virtual; abstract;
    { The PSQL or view source of one object. }
    function ObjectSourceSQL(ANodeType: TSourceObjectKind;
      const AObjectName: string): string; virtual; abstract;
    { What this object depends on, or what depends on it.

      Parameters:
        AObjectName - The object.
        ADependedOn    - True for "what this object uses", False for "what
                         uses this object". }
    function DependenciesSQL(const AObjectName: string;
      ADependedOn: Boolean): string; virtual; abstract;
    { Privileges granted on one object.

      Parameters:
        AObjectName - The object.
        AKind       - What kind of object it is. Required, not cosmetic:
                      RDB$USER_PRIVILEGES holds grants for EVERY kind of
                      object in one table and distinguishes them by
                      RDB$OBJECT_TYPE, so filtering on the name alone would
                      show a generator's grants on a table of the same
                      name. }
    function PrivilegesSQL(const AObjectName: string;
      AKind: TSourceObjectKind): string; virtual; abstract;
    { Whether a procedure is selectable (returns a set, needs SELECT) or
      executable (returns at most one row, needs EXECUTE PROCEDURE).
      One row, one column named ROUTINE_TYPE: 1 selectable, 2 executable. }
    function RoutineTypeSQL(const AObjectName: string): string;
      virtual; abstract;
    { One index's own properties: table, uniqueness, direction, activity,
      segments, selectivity and the constraint it backs. }
    function IndexInfoSQL(const AObjectName: string): string;
      virtual; abstract;
    { The description (RDB$DESCRIPTION) of one object. }
    function DescriptionSQL(ANodeType: TSourceObjectKind;
      const AObjectName: string): string; virtual; abstract;
    { Every user the security database holds, as the CURRENT attachment can see
      them.

      Columns: USER_NAME, FIRST_NAME, MIDDLE_NAME, LAST_NAME, IS_ACTIVE,
      ADMIN_ROLE, PLUGIN_NAME, USER_DESCRIPTION.

      Notes:
        SEC$USERS is not an RDB$ table and not part of the database's own
        metadata: it is a view onto whatever user-manager plugin the server was
        configured with. A user who is not an administrator sees exactly one
        row - themselves - and that is the server's decision, not a bug here. }
    function UserAccountsSQL: string; virtual; abstract;

    { Every attachment currently connected to THIS database.

      Columns: ATTACHMENT_ID, USER_NAME, ROLE_NAME, REMOTE_ADDRESS,
               REMOTE_PROCESS, CONNECTED_AT, ATTACHMENT_STATE, IS_SELF.

      Notes:
        MON$ATTACHMENTS is a virtual table: the server materialises it when
        the transaction first reads it and then holds it still, which is why
        the caller must use FetchTableFresh and not the standing metadata
        transaction.

        The column set is deliberately narrow - these are the columns
        corroborated across every Firebird version this program supports.
        Firebird 4 adds wire-compression and timeout columns; they are not
        selected here because they could not be checked against a live FB4
        server, and a wrong column name in a monitoring query fails the whole
        list rather than one cell. Add them in a FB4 override when there is a
        server to verify against.

        IS_SELF marks the caller's own attachment, so the dialog can refuse
        to disconnect the session the user is sitting in. }
    function AttachmentsSQL: string; virtual; abstract;

    { The current definition of one domain, as one row.

      Parameters:
        AName - Bare name of the domain.

      Columns: DATA_TYPE, NOT_NULL, DEFAULT_SOURCE, CHECK_SOURCE, COLLATION.

      Notes:
        DEFAULT_SOURCE and CHECK_SOURCE come back as Firebird stored them,
        which is the whole clause including its keyword - 'DEFAULT 0', not
        '0'. Stripping that is the caller's job and is done in one place, in
        DdlStatements, so that both halves of a round trip agree. }
    function DomainDefinitionSQL(const AName: string): string;
      virtual; abstract;

    { The default message of one exception, as one row.

      Parameters:
        AName - Bare name of the exception.

      Columns: MESSAGE_TEXT. }
    function ExceptionDefinitionSQL(const AName: string): string;
      virtual; abstract;

    { Whether one index is active, as one row.

      Parameters:
        AName - Bare name of the index.

      Columns: IS_ACTIVE, TABLE_NAME.

      Notes:
        Only the active flag, because it is the only thing ALTER INDEX can
        change. Firebird has no statement that alters an index's columns or
        its uniqueness: that is a drop and a create, and pretending otherwise
        in a dialog would be a lie the server then refuses. }
    function IndexStateSQL(const AName: string): string; virtual; abstract;

    { The current value of one sequence, as one row.

      Parameters:
        AName - Bare name of the sequence.

      Columns: CURRENT_VALUE.

      Notes:
        Read with GEN_ID(name, 0). Incrementing by zero is how Firebird is
        asked for the current value without consuming one, and it is the only
        way: RDB$GENERATORS records the value the sequence STARTED at, not
        where it has got to. }
    function SequenceValueSQL(const AName: string): string;
      virtual; abstract;

    { The version this provider was built for. }
    property Version: TServerVersion read FVersion;
  end;

implementation

{------------------------------------------------------------------------------
  TMetadataSqlProvider.Create
  ----------------------------------------------------------------------------
  Creates a provider for one server version.

  Parameters:
    AVersion - The connected server's version, already detected.
------------------------------------------------------------------------------}
constructor TMetadataSqlProvider.Create(const AVersion: TServerVersion);
begin
  inherited Create;
  FVersion := AVersion;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProvider.HasSchemas
  ----------------------------------------------------------------------------
  Returns True when this server qualifies objects with a schema.

  Returns:
    False here; the Firebird 6 provider overrides it.
------------------------------------------------------------------------------}
function TMetadataSqlProvider.HasSchemas: Boolean;
begin
  Result := False;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProvider.SchemaColumnExpr
  ----------------------------------------------------------------------------
  Returns the expression that yields column 1 of the column contract.

  Parameters:
    AAlias - Alias of the query's main table.

  Returns:
    A typed NULL on servers without schemas, so that every collection query
    has the same shape on every version.
------------------------------------------------------------------------------}
function TMetadataSqlProvider.SchemaColumnExpr(const AAlias: string): string;
begin
  Result := 'CAST(NULL AS VARCHAR(63))';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProvider.UserObjectPredicate
  ----------------------------------------------------------------------------
  Returns the predicate selecting objects that belong to the user.

  Parameters:
    AAlias - Alias of the table holding RDB$SYSTEM_FLAG.

  Notes:
    COALESCE is required, not defensive habit: RDB$SYSTEM_FLAG is NULL rather
    than 0 for a great many rows, and "RDB$SYSTEM_FLAG = 0" silently loses
    them. This is one of the most common bugs in home-grown Firebird tools.
------------------------------------------------------------------------------}
function TMetadataSqlProvider.UserObjectPredicate(const AAlias: string): string;
begin
  Result := 'COALESCE(' + AAlias + '.RDB$SYSTEM_FLAG, 0) = 0';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProvider.SystemObjectPredicate
  ----------------------------------------------------------------------------
  Returns the predicate selecting objects that belong to the system.

  Parameters:
    AAlias - Alias of the table holding RDB$SYSTEM_FLAG.
------------------------------------------------------------------------------}
function TMetadataSqlProvider.SystemObjectPredicate(
  const AAlias: string): string;
begin
  Result := 'COALESCE(' + AAlias + '.RDB$SYSTEM_FLAG, 0) <> 0';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProvider.SelectList
  ----------------------------------------------------------------------------
  Builds the three-column SELECT list of the column contract.

  Parameters:
    AAlias       - Alias of the main table.
    ANameColumn  - Unqualified name of the column holding the object name.
    AIdColumn    - Unqualified name of the id column, or an empty string when
                   the type has no id, in which case a NULL is selected.

  Returns:
    'SELECT <schema>, a.NAME AS OBJ_NAME, a.ID AS OBJ_ID'.
------------------------------------------------------------------------------}
function TMetadataSqlProvider.SelectList(const AAlias, ANameColumn,
  AIdColumn: string): string;
var
  IdExpr: string;
begin
  if AIdColumn = '' then
    IdExpr := 'CAST(NULL AS INTEGER)'
  else
    IdExpr := AAlias + '.' + AIdColumn;

  Result :=
    'SELECT ' + SchemaColumnExpr(AAlias) + ' AS SCHEMA_NAME, ' +
    AAlias + '.' + ANameColumn + ' AS OBJ_NAME, ' +
    IdExpr + ' AS OBJ_ID';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProvider.EngineVersionSQL
  ----------------------------------------------------------------------------
  Returns the query yielding the engine version string.

  Returns:
    A one-row, one-column query. Available from Firebird 2.1 onwards, so it is
    safe on every supported server.
------------------------------------------------------------------------------}
function TMetadataSqlProvider.EngineVersionSQL: string;
begin
  Result :=
    'SELECT RDB$GET_CONTEXT(''SYSTEM'', ''ENGINE_VERSION'') AS ENGINE_VERSION ' +
    'FROM RDB$DATABASE';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProvider.DatabaseInfoSQL
  ----------------------------------------------------------------------------
  Returns the query yielding dialect and ODS version.

  Returns:
    One row with SQL_DIALECT, ODS_MAJOR, ODS_MINOR. The dialect drives the
    refusal of dialect 1 databases; the ODS is shown in the status bar.

  Notes:
    Three columns, and deliberately no more. This query is the FIRST thing
    run on a new attachment, before the engine version is known, so it is
    built from the minimum-version provider and must therefore be readable by
    the OLDEST client the program supports talking to the NEWEST server.

    It used to select MON$PAGE_SIZE, MON$FORCED_WRITES, MON$READ_ONLY and
    MON$CREATION_DATE as well. Nothing ever read them, and MON$CREATION_DATE
    is TIMESTAMP on Firebird 3 but TIMESTAMP WITH TIME ZONE from Firebird 4 -
    a type a Firebird 3 client cannot represent. The result was that a
    Firebird 3 client could not connect to a Firebird 4 or 5 server at all:
    the attachment succeeded and then this query failed with "Data type
    unknown" (SQLCODE 335544573), which reads like a defect in the metadata
    layer rather than in the four columns nobody wanted.

    If a database property page ever needs page size, forced writes, read-only
    or the creation date, they belong in a separate query on the REAL provider
    - chosen after the version is known - with the FB4 override casting
    MON$CREATION_DATE back to TIMESTAMP.
------------------------------------------------------------------------------}
function TMetadataSqlProvider.DatabaseInfoSQL: string;
begin
  Result :=
    'SELECT d.MON$SQL_DIALECT AS SQL_DIALECT, ' +
    'd.MON$ODS_MAJOR AS ODS_MAJOR, ' +
    'd.MON$ODS_MINOR AS ODS_MINOR ' +
    'FROM MON$DATABASE d';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProvider.PublicationsSQL
  ----------------------------------------------------------------------------
  Returns the publications query.

  Returns:
    An empty string here. Servers older than Firebird 4 have no publications,
    and an empty string is the signal that the folder must not appear at all -
    the UI contract in SPECIFICATION.md 5.3 hides unsupported features rather
    than showing them empty.
------------------------------------------------------------------------------}
function TMetadataSqlProvider.PublicationsSQL: string;
begin
  Result := '';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProvider.SchemasSQL
  ----------------------------------------------------------------------------
  Returns the schemas query.

  Returns:
    An empty string before Firebird 6, with the same meaning as in
    PublicationsSQL.
------------------------------------------------------------------------------}
function TMetadataSqlProvider.SchemasSQL: string;
begin
  Result := '';
end;

end.
