{==============================================================================
  Unit:        MetadataSqlProviderFB3
  Purpose:     Metadata SQL for Firebird 3.0. This is the baseline every later
               provider inherits from and amends.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils, MetadataSqlProvider

  Firebird 3 is the oldest server IBQConsole supports, which buys a great deal:
  packages, PSQL functions with RDB$LEGACY_FLAG to tell them from UDFs, and
  SEC$USERS instead of the old services-only user list.
==============================================================================}
unit MetadataSqlProviderFB3;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, MetadataSqlProvider;

type
  { TMetadataSqlProviderFB3
    The Firebird 3.0 metadata queries. Every method returns SQL obeying the
    column contract documented in MetadataSqlProvider. }
  TMetadataSqlProviderFB3 = class(TMetadataSqlProvider)
  protected
    { The SQL expression that renders a column's data type as text, for a
      query whose RDB$FIELDS row has alias AFieldAlias.

      Firebird stores a type as a numeric code plus subtype, precision and
      scale; turning that back into 'VARCHAR(30)' or 'NUMERIC(15,2)' is a CASE
      expression that grows with every release. Factoring it out means Firebird
      4 adds DECFLOAT, INT128 and the time-zone types by overriding one method
      rather than by copying a hundred-line query. }
    function ColumnTypeExpr(const AFieldAlias: string): string; virtual;
    { Renders a numeric column as trimmed text, for building type names.

      Firebird pads a CAST to VARCHAR of a number, and concatenating that
      straight into a type name yields 'NUMERIC(15   ,2  )'. }
    function NumText(const AExpression: string): string;
  public
    function TablesSQL: string; override;
    function GlobalTemporaryTablesSQL: string; override;
    function SystemTablesSQL: string; override;
    function ViewsSQL: string; override;
    function ProceduresSQL: string; override;
    function FunctionsSQL: string; override;
    function ExternalFunctionsSQL: string; override;
    function PackagesSQL: string; override;
    function TriggersSQL(AKind: TTriggerKind): string; override;
    function GeneratorsSQL: string; override;
    function ExceptionsSQL: string; override;
    function DomainsSQL: string; override;
    function SystemDomainsSQL: string; override;
    function IndicesSQL: string; override;
    function SystemIndicesSQL: string; override;
    function RolesSQL: string; override;
    function CharacterSetsSQL: string; override;
    function CollationsSQL: string; override;
    function BlobFiltersSQL: string; override;
    function UsersSQL: string; override;

    function RelationColumnsSQL(const AObjectName: string): string; override;
    function RelationIndicesSQL(const AObjectName: string): string; override;
    function RelationConstraintsSQL(const AObjectName: string): string;
      override;
    function RelationTriggersSQL(const AObjectName: string): string; override;
    function RoutineParametersSQL(const AObjectName: string): string; override;
    function ObjectSourceSQL(ANodeType: TSourceObjectKind;
      const AObjectName: string): string; override;
    function DependenciesSQL(const AObjectName: string;
      ADependedOn: Boolean): string; override;
    function PrivilegesSQL(const AObjectName: string;
      AKind: TSourceObjectKind): string; override;
    function RoutineTypeSQL(const AObjectName: string): string; override;
    function IndexInfoSQL(const AObjectName: string): string; override;
    function DescriptionSQL(ANodeType: TSourceObjectKind;
      const AObjectName: string): string; override;
    function UserAccountsSQL: string; override;
    function AttachmentsSQL: string; override;
    function DomainDefinitionSQL(const AName: string): string; override;
    function ExceptionDefinitionSQL(const AName: string): string;
      override;
    function IndexStateSQL(const AName: string): string; override;
    function SequenceValueSQL(const AName: string): string; override;
  end;

implementation

const
  { Ordering is by the name column, which is column 2 of the contract. Sorting
    in the server rather than in the tree keeps a 4000-table list cheap. }
  OrderByName = ' ORDER BY 2';

  { RDB$RELATIONS.RDB$RELATION_TYPE values. }
  RelTypePersistent = 0;
  RelTypeExternal   = 2;
  RelTypeGttPreserve = 4;
  RelTypeGttDelete   = 5;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.TablesSQL
  ----------------------------------------------------------------------------
  Returns the query listing the user's persistent and external tables.

  Notes:
    Global temporary tables are excluded here and listed separately, because
    they behave differently enough that mixing them in one folder is unhelpful.
    Views are excluded by RDB$VIEW_BLR IS NULL as well as by relation type: on
    a database restored from an older ODS the type column can be NULL, and the
    BLR test is the one that is always right.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.TablesSQL: string;
begin
  Result :=
    SelectList('r', 'RDB$RELATION_NAME', 'RDB$RELATION_ID') +
    ' FROM RDB$RELATIONS r' +
    ' WHERE ' + UserObjectPredicate('r') +
    '   AND r.RDB$VIEW_BLR IS NULL' +
    '   AND COALESCE(r.RDB$RELATION_TYPE, 0) IN (' +
        IntToStr(RelTypePersistent) + ', ' + IntToStr(RelTypeExternal) + ')' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.GlobalTemporaryTablesSQL
  ----------------------------------------------------------------------------
  Returns the query listing global temporary tables, both ON COMMIT PRESERVE
  and ON COMMIT DELETE.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.GlobalTemporaryTablesSQL: string;
begin
  Result :=
    SelectList('r', 'RDB$RELATION_NAME', 'RDB$RELATION_ID') +
    ' FROM RDB$RELATIONS r' +
    ' WHERE ' + UserObjectPredicate('r') +
    '   AND r.RDB$RELATION_TYPE IN (' +
        IntToStr(RelTypeGttPreserve) + ', ' + IntToStr(RelTypeGttDelete) + ')' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.SystemTablesSQL
  ----------------------------------------------------------------------------
  Returns the query listing system tables, shown only when the user turns on
  "Show system objects".
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.SystemTablesSQL: string;
begin
  Result :=
    SelectList('r', 'RDB$RELATION_NAME', 'RDB$RELATION_ID') +
    ' FROM RDB$RELATIONS r' +
    ' WHERE ' + SystemObjectPredicate('r') +
    '   AND r.RDB$VIEW_BLR IS NULL' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.ViewsSQL
  ----------------------------------------------------------------------------
  Returns the query listing views.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.ViewsSQL: string;
begin
  Result :=
    SelectList('r', 'RDB$RELATION_NAME', 'RDB$RELATION_ID') +
    ' FROM RDB$RELATIONS r' +
    ' WHERE ' + UserObjectPredicate('r') +
    '   AND r.RDB$VIEW_BLR IS NOT NULL' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.ProceduresSQL
  ----------------------------------------------------------------------------
  Returns the query listing stored procedures.

  Notes:
    Procedures belonging to a package are excluded: they appear under their
    package, not at the top level, which is how they are named and dropped.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.ProceduresSQL: string;
begin
  Result :=
    SelectList('p', 'RDB$PROCEDURE_NAME', 'RDB$PROCEDURE_ID') +
    ' FROM RDB$PROCEDURES p' +
    ' WHERE ' + UserObjectPredicate('p') +
    '   AND p.RDB$PACKAGE_NAME IS NULL' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.FunctionsSQL
  ----------------------------------------------------------------------------
  Returns the query listing PSQL functions.

  Notes:
    RDB$LEGACY_FLAG = 0 is what separates a Firebird 3 PSQL function from a
    declared external function; both live in RDB$FUNCTIONS. RDB$FUNCTIONS has
    no id column, so column 3 of the contract is NULL here.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.FunctionsSQL: string;
begin
  Result :=
    SelectList('f', 'RDB$FUNCTION_NAME', '') +
    ' FROM RDB$FUNCTIONS f' +
    ' WHERE ' + UserObjectPredicate('f') +
    '   AND COALESCE(f.RDB$LEGACY_FLAG, 0) = 0' +
    '   AND f.RDB$PACKAGE_NAME IS NULL' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.ExternalFunctionsSQL
  ----------------------------------------------------------------------------
  Returns the query listing declared external functions (legacy UDFs).
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.ExternalFunctionsSQL: string;
begin
  Result :=
    SelectList('f', 'RDB$FUNCTION_NAME', '') +
    ' FROM RDB$FUNCTIONS f' +
    ' WHERE ' + UserObjectPredicate('f') +
    '   AND COALESCE(f.RDB$LEGACY_FLAG, 0) = 1' +
    '   AND f.RDB$PACKAGE_NAME IS NULL' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.PackagesSQL
  ----------------------------------------------------------------------------
  Returns the query listing packages.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.PackagesSQL: string;
begin
  Result :=
    SelectList('p', 'RDB$PACKAGE_NAME', '') +
    ' FROM RDB$PACKAGES p' +
    ' WHERE ' + UserObjectPredicate('p') +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.TriggersSQL
  ----------------------------------------------------------------------------
  Returns the query listing triggers of one family.

  Parameters:
    AKind - Which family to list.

  Notes:
    Firebird stores all three families in RDB$TRIGGERS and separates them by
    two facts: a DML trigger has a relation, the other two do not; and among
    those without a relation, database triggers use types 8192 to 8196 while
    DDL triggers use a bitmask from 16384 upwards. Testing the relation first
    and the type second is the combination that stays correct across 3 to 6.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.TriggersSQL(AKind: TTriggerKind): string;
var
  Predicate: string;
begin
  case AKind of
    tkDML:
      Predicate := 't.RDB$RELATION_NAME IS NOT NULL';
    tkDatabase:
      Predicate := 't.RDB$RELATION_NAME IS NULL' +
        ' AND t.RDB$TRIGGER_TYPE BETWEEN 8192 AND 8196';
    tkDDL:
      Predicate := 't.RDB$RELATION_NAME IS NULL' +
        ' AND t.RDB$TRIGGER_TYPE >= 16384';
  else
    Predicate := '1 = 0';
  end;

  Result :=
    SelectList('t', 'RDB$TRIGGER_NAME', '') +
    ' FROM RDB$TRIGGERS t' +
    ' WHERE ' + UserObjectPredicate('t') +
    '   AND ' + Predicate +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.GeneratorsSQL
  ----------------------------------------------------------------------------
  Returns the query listing sequences.

  Notes:
    The current value is deliberately not fetched here. Reading a generator's
    value has a side effect on some paths and is expensive across hundreds of
    rows; the value is read when the user opens the generator, or asks for
    "Show all values".
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.GeneratorsSQL: string;
begin
  Result :=
    SelectList('g', 'RDB$GENERATOR_NAME', 'RDB$GENERATOR_ID') +
    ' FROM RDB$GENERATORS g' +
    ' WHERE ' + UserObjectPredicate('g') +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.ExceptionsSQL
  ----------------------------------------------------------------------------
  Returns the query listing exceptions.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.ExceptionsSQL: string;
begin
  Result :=
    SelectList('e', 'RDB$EXCEPTION_NAME', 'RDB$EXCEPTION_NUMBER') +
    ' FROM RDB$EXCEPTIONS e' +
    ' WHERE ' + UserObjectPredicate('e') +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.DomainsSQL
  ----------------------------------------------------------------------------
  Returns the query listing domains the user created.

  Notes:
    Firebird creates an entry in RDB$FIELDS for every column of every table,
    named RDB$<n>. Those are not domains and must not be listed, which the
    name test excludes; RDB$SYSTEM_FLAG alone does not exclude them.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.DomainsSQL: string;
begin
  Result :=
    SelectList('f', 'RDB$FIELD_NAME', '') +
    ' FROM RDB$FIELDS f' +
    ' WHERE ' + UserObjectPredicate('f') +
    '   AND f.RDB$FIELD_NAME NOT STARTING WITH ''RDB$''' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.SystemDomainsSQL
  ----------------------------------------------------------------------------
  Returns the query listing the system's own domains.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.SystemDomainsSQL: string;
begin
  Result :=
    SelectList('f', 'RDB$FIELD_NAME', '') +
    ' FROM RDB$FIELDS f' +
    ' WHERE ' + SystemObjectPredicate('f') +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.IndicesSQL
  ----------------------------------------------------------------------------
  Returns the query listing indexes the user created.

  Notes:
    Indexes that back a PRIMARY KEY, UNIQUE or FOREIGN KEY constraint DO appear
    here, named RDB$PRIMARY1 and the like. That is not an oversight in the
    filter: Firebird records them with RDB$SYSTEM_FLAG = 0, so no system-flag
    test can separate them - verified against Firebird 3.0.14 and 5.0.4, where
    RDB$PRIMARY1 reports flag 0 while joining to a real constraint.

    Excluding them needs a join to RDB$RELATION_CONSTRAINTS on RDB$INDEX_NAME,
    which also gives the constraint each one belongs to. That arrives with the
    index property page in M2, where the information is worth showing rather
    than merely hiding.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.IndicesSQL: string;
begin
  Result :=
    SelectList('i', 'RDB$INDEX_NAME', 'RDB$INDEX_ID') +
    ' FROM RDB$INDICES i' +
    ' WHERE ' + UserObjectPredicate('i') +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.SystemIndicesSQL
  ----------------------------------------------------------------------------
  Returns the query listing system indexes.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.SystemIndicesSQL: string;
begin
  Result :=
    SelectList('i', 'RDB$INDEX_NAME', 'RDB$INDEX_ID') +
    ' FROM RDB$INDICES i' +
    ' WHERE ' + SystemObjectPredicate('i') +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.RolesSQL
  ----------------------------------------------------------------------------
  Returns the query listing roles.

  Notes:
    Firebird 3 added system roles such as RDB$ADMIN, which carry a system flag
    and are excluded here.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.RolesSQL: string;
begin
  Result :=
    SelectList('r', 'RDB$ROLE_NAME', '') +
    ' FROM RDB$ROLES r' +
    ' WHERE ' + UserObjectPredicate('r') +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.CharacterSetsSQL
  ----------------------------------------------------------------------------
  Returns the query listing character sets.

  Notes:
    Not filtered by system flag: every character set is a system object, and a
    list with nothing in it would be useless.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.CharacterSetsSQL: string;
begin
  Result :=
    SelectList('c', 'RDB$CHARACTER_SET_NAME', 'RDB$CHARACTER_SET_ID') +
    ' FROM RDB$CHARACTER_SETS c' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.CollationsSQL
  ----------------------------------------------------------------------------
  Returns the query listing collations.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.CollationsSQL: string;
begin
  Result :=
    SelectList('c', 'RDB$COLLATION_NAME', 'RDB$COLLATION_ID') +
    ' FROM RDB$COLLATIONS c' +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.BlobFiltersSQL
  ----------------------------------------------------------------------------
  Returns the query listing blob filters.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.BlobFiltersSQL: string;
begin
  Result :=
    SelectList('f', 'RDB$FUNCTION_NAME', '') +
    ' FROM RDB$FILTERS f' +
    ' WHERE ' + UserObjectPredicate('f') +
    OrderByName;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.UsersSQL
  ----------------------------------------------------------------------------
  Returns the query listing users.

  Notes:
    SEC$USERS is a virtual table backed by the active user manager plugin, so
    this reports the users the server will actually accept - unlike the old
    Services API call, which only ever saw the legacy security database. It
    requires administrator rights; an ordinary user gets an empty list rather
    than an error, which the Users folder must present as "no rights" and not
    as "no users".
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.UsersSQL: string;
begin
  Result :=
    'SELECT CAST(NULL AS VARCHAR(63)) AS SCHEMA_NAME, ' +
    'u.SEC$USER_NAME AS OBJ_NAME, ' +
    'CAST(NULL AS INTEGER) AS OBJ_ID ' +
    'FROM SEC$USERS u' +
    OrderByName;
end;

{ ---------------------------------------------------------------------------
  Object detail
  --------------------------------------------------------------------------- }

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.NumText
  ----------------------------------------------------------------------------
  Renders a numeric expression as trimmed text.

  Parameters:
    AExpression - Any numeric SQL expression.

  Returns:
    'TRIM(CAST(<expr> AS VARCHAR(12)))'.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.NumText(const AExpression: string): string;
begin
  Result := 'TRIM(CAST(' + AExpression + ' AS VARCHAR(12)))';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.ColumnTypeExpr
  ----------------------------------------------------------------------------
  Builds the CASE expression that renders a column's declared type as text.

  Parameters:
    AFieldAlias - Alias of the RDB$FIELDS row in the calling query.

  Returns:
    A SQL expression yielding 'VARCHAR(30)', 'NUMERIC(15,2)', 'BLOB SUB_TYPE 1'
    and so on.

  Notes:
    RDB$FIELD_SCALE is stored NEGATIVE, so a NUMERIC(15,2) has scale -2 and the
    rendered scale is its negation. Getting that backwards is the classic bug
    in home-grown versions of this query.

    Character length comes from RDB$CHARACTER_LENGTH, not RDB$FIELD_LENGTH:
    the latter is the byte length, so a UTF8 VARCHAR(30) would be reported as
    VARCHAR(120).
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.ColumnTypeExpr(
  const AFieldAlias: string): string;
var
  F, Precision, Scale, CharLen, SubType: string;
begin
  F := AFieldAlias;
  Precision := NumText('COALESCE(' + F + '.RDB$FIELD_PRECISION, 0)');
  Scale := NumText('(-COALESCE(' + F + '.RDB$FIELD_SCALE, 0))');
  CharLen := NumText('COALESCE(' + F + '.RDB$CHARACTER_LENGTH, 0)');
  SubType := NumText('COALESCE(' + F + '.RDB$FIELD_SUB_TYPE, 0)');

  Result :=
    'CASE ' + F + '.RDB$FIELD_TYPE' +
    ' WHEN 7 THEN CASE COALESCE(' + F + '.RDB$FIELD_SUB_TYPE, 0)' +
        ' WHEN 1 THEN ''NUMERIC('' || ' + Precision + ' || '','' || ' + Scale + ' || '')''' +
        ' WHEN 2 THEN ''DECIMAL('' || ' + Precision + ' || '','' || ' + Scale + ' || '')''' +
        ' ELSE ''SMALLINT'' END' +
    ' WHEN 8 THEN CASE COALESCE(' + F + '.RDB$FIELD_SUB_TYPE, 0)' +
        ' WHEN 1 THEN ''NUMERIC('' || ' + Precision + ' || '','' || ' + Scale + ' || '')''' +
        ' WHEN 2 THEN ''DECIMAL('' || ' + Precision + ' || '','' || ' + Scale + ' || '')''' +
        ' ELSE ''INTEGER'' END' +
    ' WHEN 16 THEN CASE COALESCE(' + F + '.RDB$FIELD_SUB_TYPE, 0)' +
        ' WHEN 1 THEN ''NUMERIC('' || ' + Precision + ' || '','' || ' + Scale + ' || '')''' +
        ' WHEN 2 THEN ''DECIMAL('' || ' + Precision + ' || '','' || ' + Scale + ' || '')''' +
        ' ELSE ''BIGINT'' END' +
    ' WHEN 10 THEN ''FLOAT''' +
    ' WHEN 27 THEN ''DOUBLE PRECISION''' +
    ' WHEN 12 THEN ''DATE''' +
    ' WHEN 13 THEN ''TIME''' +
    ' WHEN 35 THEN ''TIMESTAMP''' +
    ' WHEN 14 THEN ''CHAR('' || ' + CharLen + ' || '')''' +
    ' WHEN 37 THEN ''VARCHAR('' || ' + CharLen + ' || '')''' +
    ' WHEN 23 THEN ''BOOLEAN''' +
    ' WHEN 261 THEN ''BLOB SUB_TYPE '' || ' + SubType +
    ' ELSE ''UNKNOWN ('' || ' + NumText(F + '.RDB$FIELD_TYPE') + ' || '')''' +
    ' END';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.RelationColumnsSQL
  ----------------------------------------------------------------------------
  Returns the query listing a relation's columns.

  Parameters:
    AObjectName - Bare name of the table or view, as stored in RDB$.

  Notes:
    RDB$RELATION_FIELDS.RDB$NULL_FLAG overrides the domain's, so both are
    considered: a column is nullable only when neither says otherwise.

    DOMAIN is shown only when it is a real domain the user named. Every column
    has an entry in RDB$FIELDS, but for a column declared with an inline type
    that entry is auto-named RDB$n and is not a domain in any useful sense.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.RelationColumnsSQL(
  const AObjectName: string): string;
begin
  Result :=
    'SELECT rf.RDB$FIELD_POSITION + 1 AS POS,' +
    ' rf.RDB$FIELD_NAME AS COLUMN_NAME,' +
    ' ' + ColumnTypeExpr('f') + ' AS DATA_TYPE,' +
    ' CASE WHEN COALESCE(rf.RDB$NULL_FLAG, f.RDB$NULL_FLAG, 0) = 0' +
      ' THEN ''YES'' ELSE ''NO'' END AS NULLABLE,' +
    ' CASE WHEN f.RDB$FIELD_NAME STARTING WITH ''RDB$'' THEN ''''' +
      ' ELSE f.RDB$FIELD_NAME END AS DOMAIN_NAME,' +
    ' COALESCE(rf.RDB$DEFAULT_SOURCE, f.RDB$DEFAULT_SOURCE) AS COLUMN_DEFAULT,' +
    ' f.RDB$COMPUTED_SOURCE AS COMPUTED_SOURCE,' +
    ' cs.RDB$CHARACTER_SET_NAME AS CHARACTER_SET,' +
    ' co.RDB$COLLATION_NAME AS COLLATION,' +
    ' rf.RDB$DESCRIPTION AS DESCRIPTION' +
    ' FROM RDB$RELATION_FIELDS rf' +
    ' JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE' +
    ' LEFT JOIN RDB$CHARACTER_SETS cs' +
      ' ON cs.RDB$CHARACTER_SET_ID = f.RDB$CHARACTER_SET_ID' +
    ' LEFT JOIN RDB$COLLATIONS co' +
      ' ON co.RDB$COLLATION_ID = COALESCE(rf.RDB$COLLATION_ID, f.RDB$COLLATION_ID)' +
      ' AND co.RDB$CHARACTER_SET_ID = f.RDB$CHARACTER_SET_ID' +
    ' WHERE rf.RDB$RELATION_NAME = ' + QuotedStr(AObjectName) +
    ' ORDER BY rf.RDB$FIELD_POSITION';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.RelationIndicesSQL
  ----------------------------------------------------------------------------
  Returns the query listing a relation's indexes.

  Parameters:
    AObjectName - Bare name of the table.

  Notes:
    The segment list is assembled with LIST() over the index segments in field
    position order, so an index reads as 'COL_A, COL_B' rather than as one row
    per segment.

    CONSTRAINT names the constraint an index backs, which is what distinguishes
    RDB$PRIMARY1 from an index somebody created deliberately - see the note on
    IndicesSQL about why a system-flag test cannot do this.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.RelationIndicesSQL(
  const AObjectName: string): string;
begin
  Result :=
    'SELECT i.RDB$INDEX_NAME AS INDEX_NAME,' +
    ' CASE COALESCE(i.RDB$UNIQUE_FLAG, 0) WHEN 1 THEN ''YES'' ELSE ''NO'' END' +
      ' AS IS_UNIQUE,' +
    ' CASE COALESCE(i.RDB$INDEX_TYPE, 0) WHEN 1 THEN ''DESC'' ELSE ''ASC'' END' +
      ' AS DIRECTION,' +
    ' CASE COALESCE(i.RDB$INDEX_INACTIVE, 0) WHEN 1 THEN ''NO'' ELSE ''YES'' END' +
      ' AS ACTIVE,' +
    ' (SELECT LIST(TRIM(s.RDB$FIELD_NAME), '', '')' +
      ' FROM RDB$INDEX_SEGMENTS s' +
      ' WHERE s.RDB$INDEX_NAME = i.RDB$INDEX_NAME) AS SEGMENTS,' +
    ' i.RDB$STATISTICS AS SELECTIVITY,' +
    ' c.RDB$CONSTRAINT_NAME AS CONSTRAINT_NAME,' +
    ' i.RDB$DESCRIPTION AS DESCRIPTION' +
    ' FROM RDB$INDICES i' +
    ' LEFT JOIN RDB$RELATION_CONSTRAINTS c' +
      ' ON c.RDB$INDEX_NAME = i.RDB$INDEX_NAME' +
    ' WHERE i.RDB$RELATION_NAME = ' + QuotedStr(AObjectName) +
    ' ORDER BY 1';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.RelationConstraintsSQL
  ----------------------------------------------------------------------------
  Returns the query listing a relation's constraints.

  Parameters:
    AObjectName - Bare name of the table.

  Notes:
    CHECK constraints live in RDB$CHECK_CONSTRAINTS pointing at a trigger, and
    their text is on RDB$TRIGGERS.RDB$TRIGGER_SOURCE; the DISTINCT is needed
    because Firebird creates several triggers for one CHECK.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.RelationConstraintsSQL(
  const AObjectName: string): string;
begin
  Result :=
    'SELECT DISTINCT c.RDB$CONSTRAINT_NAME AS CONSTRAINT_NAME,' +
    ' TRIM(c.RDB$CONSTRAINT_TYPE) AS CONSTRAINT_TYPE,' +
    ' (SELECT LIST(TRIM(s.RDB$FIELD_NAME), '', '')' +
      ' FROM RDB$INDEX_SEGMENTS s' +
      ' WHERE s.RDB$INDEX_NAME = c.RDB$INDEX_NAME) AS COLUMNS,' +
    ' rc.RDB$RELATION_NAME AS REFERENCES_TABLE,' +
    ' (SELECT LIST(TRIM(s2.RDB$FIELD_NAME), '', '')' +
      ' FROM RDB$INDEX_SEGMENTS s2' +
      ' WHERE s2.RDB$INDEX_NAME = rc.RDB$INDEX_NAME) AS REFERENCES_COLUMNS,' +
    ' ref.RDB$UPDATE_RULE AS ON_UPDATE,' +
    ' ref.RDB$DELETE_RULE AS ON_DELETE,' +
    ' chk_trg.RDB$TRIGGER_SOURCE AS CHECK_SOURCE,' +
    ' c.RDB$INDEX_NAME AS INDEX_NAME' +
    ' FROM RDB$RELATION_CONSTRAINTS c' +
    ' LEFT JOIN RDB$REF_CONSTRAINTS ref' +
      ' ON ref.RDB$CONSTRAINT_NAME = c.RDB$CONSTRAINT_NAME' +
    ' LEFT JOIN RDB$RELATION_CONSTRAINTS rc' +
      ' ON rc.RDB$CONSTRAINT_NAME = ref.RDB$CONST_NAME_UQ' +
    ' LEFT JOIN RDB$CHECK_CONSTRAINTS chk' +
      ' ON chk.RDB$CONSTRAINT_NAME = c.RDB$CONSTRAINT_NAME' +
    ' LEFT JOIN RDB$TRIGGERS chk_trg' +
      ' ON chk_trg.RDB$TRIGGER_NAME = chk.RDB$TRIGGER_NAME' +
      ' AND chk_trg.RDB$TRIGGER_TYPE = 1' +
    ' WHERE c.RDB$RELATION_NAME = ' + QuotedStr(AObjectName) +
    ' ORDER BY 2, 1';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.RelationTriggersSQL
  ----------------------------------------------------------------------------
  Returns the query listing the triggers on a relation.

  Parameters:
    AObjectName - Bare name of the table or view.

  Notes:
    RDB$TRIGGER_TYPE encodes up to three actions in one number - a trigger can
    be BEFORE INSERT OR UPDATE - so the readable form is decoded here rather
    than shown as a bare integer the user would have to look up.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.RelationTriggersSQL(
  const AObjectName: string): string;
begin
  Result :=
    'SELECT t.RDB$TRIGGER_NAME AS TRIGGER_NAME,' +
    ' CASE WHEN MOD(t.RDB$TRIGGER_TYPE, 2) = 1 THEN ''BEFORE'' ELSE ''AFTER'' END' +
      ' AS TIMING,' +
    ' CASE t.RDB$TRIGGER_TYPE' +
      ' WHEN 1 THEN ''INSERT'' WHEN 2 THEN ''INSERT''' +
      ' WHEN 3 THEN ''UPDATE'' WHEN 4 THEN ''UPDATE''' +
      ' WHEN 5 THEN ''DELETE'' WHEN 6 THEN ''DELETE''' +
      ' WHEN 17 THEN ''INSERT OR UPDATE'' WHEN 18 THEN ''INSERT OR UPDATE''' +
      ' WHEN 25 THEN ''INSERT OR DELETE'' WHEN 26 THEN ''INSERT OR DELETE''' +
      ' WHEN 27 THEN ''UPDATE OR DELETE'' WHEN 28 THEN ''UPDATE OR DELETE''' +
      ' WHEN 113 THEN ''INSERT OR UPDATE OR DELETE''' +
      ' WHEN 114 THEN ''INSERT OR UPDATE OR DELETE''' +
      ' ELSE ''TYPE '' || ' + NumText('t.RDB$TRIGGER_TYPE') + ' END AS EVENT,' +
    { POSITION is a reserved word and cannot be a bare alias - verified, it
      fails with "Token unknown - POSITION". }
    ' t.RDB$TRIGGER_SEQUENCE AS TRIGGER_POSITION,' +
    ' CASE COALESCE(t.RDB$TRIGGER_INACTIVE, 0) WHEN 1 THEN ''NO'' ELSE ''YES'' END' +
      ' AS ACTIVE,' +
    ' t.RDB$DESCRIPTION AS DESCRIPTION' +
    ' FROM RDB$TRIGGERS t' +
    ' WHERE t.RDB$RELATION_NAME = ' + QuotedStr(AObjectName) +
    ' ORDER BY t.RDB$TRIGGER_SEQUENCE, 1';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.RoutineParametersSQL
  ----------------------------------------------------------------------------
  Returns the query listing a procedure's or function's parameters.

  Parameters:
    AObjectName - Bare name of the procedure or function.

  Notes:
    Procedures and functions keep their parameters in different tables, so this
    is a UNION ALL of the two. A function's return value appears in
    RDB$FUNCTION_ARGUMENTS with RDB$ARGUMENT_POSITION = 0 and is labelled
    RETURNS here rather than being hidden.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.RoutineParametersSQL(
  const AObjectName: string): string;
begin
  Result :=
    'SELECT pp.RDB$PARAMETER_NUMBER + 1 AS POS,' +
    ' pp.RDB$PARAMETER_NAME AS PARAM_NAME,' +
    ' CASE pp.RDB$PARAMETER_TYPE WHEN 0 THEN ''IN'' ELSE ''OUT'' END AS DIRECTION,' +
    ' ' + ColumnTypeExpr('f') + ' AS DATA_TYPE,' +
    ' CASE WHEN COALESCE(pp.RDB$NULL_FLAG, f.RDB$NULL_FLAG, 0) = 0' +
      ' THEN ''YES'' ELSE ''NO'' END AS NULLABLE,' +
    ' pp.RDB$DEFAULT_SOURCE AS PARAM_DEFAULT' +
    ' FROM RDB$PROCEDURE_PARAMETERS pp' +
    ' JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = pp.RDB$FIELD_SOURCE' +
    ' WHERE pp.RDB$PROCEDURE_NAME = ' + QuotedStr(AObjectName) +
    '   AND pp.RDB$PACKAGE_NAME IS NULL' +
    ' UNION ALL' +
    ' SELECT fa.RDB$ARGUMENT_POSITION AS POS,' +
    ' COALESCE(fa.RDB$ARGUMENT_NAME, ''(result)'') AS PARAM_NAME,' +
    ' CASE WHEN fa.RDB$ARGUMENT_POSITION = 0 THEN ''RETURNS'' ELSE ''IN'' END' +
      ' AS DIRECTION,' +
    ' ' + ColumnTypeExpr('f2') + ' AS DATA_TYPE,' +
    ' CASE WHEN COALESCE(fa.RDB$NULL_FLAG, 0) = 0 THEN ''YES'' ELSE ''NO'' END' +
      ' AS NULLABLE,' +
    ' fa.RDB$DEFAULT_SOURCE AS PARAM_DEFAULT' +
    ' FROM RDB$FUNCTION_ARGUMENTS fa' +
    ' JOIN RDB$FIELDS f2 ON f2.RDB$FIELD_NAME = fa.RDB$FIELD_SOURCE' +
    ' WHERE fa.RDB$FUNCTION_NAME = ' + QuotedStr(AObjectName) +
    '   AND fa.RDB$PACKAGE_NAME IS NULL' +
    ' ORDER BY 3, 1';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.ObjectSourceSQL
  ----------------------------------------------------------------------------
  Returns the query yielding one object's source text.

  Parameters:
    ANodeType   - What kind of object it is.
    AObjectName - Its bare name.

  Returns:
    A one-row, one-column query aliased SOURCE_TEXT, or an empty string for a
    kind that has no source.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.ObjectSourceSQL(ANodeType: TSourceObjectKind;
  const AObjectName: string): string;
begin
  case ANodeType of
    sokView:
      Result := 'SELECT r.RDB$VIEW_SOURCE AS SOURCE_TEXT FROM RDB$RELATIONS r' +
        ' WHERE r.RDB$RELATION_NAME = ' + QuotedStr(AObjectName);
    sokProcedure:
      Result := 'SELECT p.RDB$PROCEDURE_SOURCE AS SOURCE_TEXT' +
        ' FROM RDB$PROCEDURES p' +
        ' WHERE p.RDB$PROCEDURE_NAME = ' + QuotedStr(AObjectName);
    sokFunction:
      Result := 'SELECT f.RDB$FUNCTION_SOURCE AS SOURCE_TEXT' +
        ' FROM RDB$FUNCTIONS f' +
        ' WHERE f.RDB$FUNCTION_NAME = ' + QuotedStr(AObjectName);
    sokTrigger:
      Result := 'SELECT t.RDB$TRIGGER_SOURCE AS SOURCE_TEXT' +
        ' FROM RDB$TRIGGERS t' +
        ' WHERE t.RDB$TRIGGER_NAME = ' + QuotedStr(AObjectName);
    sokPackage:
      Result := 'SELECT p.RDB$PACKAGE_HEADER_SOURCE || ASCII_CHAR(10) ||' +
        ' COALESCE(p.RDB$PACKAGE_BODY_SOURCE, '''') AS SOURCE_TEXT' +
        ' FROM RDB$PACKAGES p' +
        ' WHERE p.RDB$PACKAGE_NAME = ' + QuotedStr(AObjectName);
  else
    Result := '';
  end;
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.DependenciesSQL
  ----------------------------------------------------------------------------
  Returns the query listing what an object uses, or what uses it.

  Parameters:
    AObjectName - The object.
    ADependedOn - True for "objects this one uses", False for "objects that use
                  this one".

  Notes:
    RDB$DEPENDENCIES reads in one direction only, so the two questions are the
    same table with the two name columns swapped. RDB$DEPENDENT_TYPE is decoded
    to a readable name; the numbers are the same list IBConsole hard-coded as
    DEP_TABLE, DEP_VIEW and so on in zluGlobal.pas.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.DependenciesSQL(const AObjectName: string;
  ADependedOn: Boolean): string;
var
  NameColumn, OtherColumn, TypeColumn: string;
begin
  if ADependedOn then
  begin
    NameColumn := 'd.RDB$DEPENDENT_NAME';
    OtherColumn := 'd.RDB$DEPENDED_ON_NAME';
    TypeColumn := 'd.RDB$DEPENDED_ON_TYPE';
  end
  else
  begin
    NameColumn := 'd.RDB$DEPENDED_ON_NAME';
    OtherColumn := 'd.RDB$DEPENDENT_NAME';
    TypeColumn := 'd.RDB$DEPENDENT_TYPE';
  end;

  Result :=
    'SELECT DISTINCT ' + OtherColumn + ' AS OBJECT_NAME,' +
    ' CASE ' + TypeColumn +
      ' WHEN 0 THEN ''Table'' WHEN 1 THEN ''View'' WHEN 2 THEN ''Trigger''' +
      ' WHEN 3 THEN ''Computed column'' WHEN 4 THEN ''Validation''' +
      ' WHEN 5 THEN ''Procedure'' WHEN 6 THEN ''Expression index''' +
      ' WHEN 7 THEN ''Exception'' WHEN 8 THEN ''User'' WHEN 9 THEN ''Column''' +
      ' WHEN 10 THEN ''Index'' WHEN 14 THEN ''Generator''' +
      ' WHEN 15 THEN ''UDF'' WHEN 17 THEN ''Collation''' +
      ' WHEN 18 THEN ''Package'' WHEN 19 THEN ''Package body''' +
      ' ELSE ''Type '' || ' + NumText(TypeColumn) + ' END AS OBJECT_TYPE,' +
    ' d.RDB$FIELD_NAME AS VIA_COLUMN' +
    ' FROM RDB$DEPENDENCIES d' +
    ' WHERE ' + NameColumn + ' = ' + QuotedStr(AObjectName) +
    ' ORDER BY 2, 1';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.PrivilegesSQL
  ----------------------------------------------------------------------------
  Returns the query listing the privileges granted on one object.

  Parameters:
    AObjectName - The object.

  Notes:
    One row per grantee and privilege, which is how Firebird stores it. The
    Permissions page pivots this into the grid IBConsole showed - object down
    the side, SELECT/INSERT/UPDATE/DELETE across the top - but the pivot is a
    display concern and stays in the UI.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.PrivilegesSQL(const AObjectName: string;
  AKind: TSourceObjectKind): string;
var
  TypeCode: Integer;
  TypeFilter: string;
begin
  { RDB$OBJECT_TYPE codes, confirmed against Firebird 3.0.14: 0 relation,
    2 trigger, 5 procedure, 7 exception, 9 domain, 10 index, 11 character set,
    13 role, 14 generator, 15 external function, 17 collation, 18 package.
    A kind with no code is not filtered, which is the old behaviour and is
    only correct when names cannot collide across kinds. }
  case AKind of
    sokTable, sokView:  TypeCode := 0;
    sokTrigger:         TypeCode := 2;
    sokProcedure:       TypeCode := 5;
    sokException:       TypeCode := 7;
    sokDomain:          TypeCode := 9;
    sokIndex:           TypeCode := 10;
    sokCharacterSet:    TypeCode := 11;
    sokRole:            TypeCode := 13;
    sokGenerator:       TypeCode := 14;
    sokFunction:        TypeCode := 15;
    sokCollation:       TypeCode := 17;
    sokPackage:         TypeCode := 18;
  else
    TypeCode := -1;
  end;

  if TypeCode >= 0 then
    TypeFilter := '   AND COALESCE(p.RDB$OBJECT_TYPE, 0) = ' +
      IntToStr(TypeCode)
  else
    TypeFilter := '';

  Result :=
    'SELECT p.RDB$USER AS GRANTEE,' +
    ' CASE p.RDB$USER_TYPE' +
      ' WHEN 8 THEN ''User'' WHEN 13 THEN ''Role'' WHEN 5 THEN ''Procedure''' +
      ' WHEN 2 THEN ''Trigger'' WHEN 15 THEN ''Function''' +
      ' ELSE ''Type '' || ' + NumText('p.RDB$USER_TYPE') + ' END AS GRANTEE_TYPE,' +
    ' CASE TRIM(p.RDB$PRIVILEGE)' +
      ' WHEN ''S'' THEN ''SELECT'' WHEN ''I'' THEN ''INSERT''' +
      ' WHEN ''U'' THEN ''UPDATE'' WHEN ''D'' THEN ''DELETE''' +
      ' WHEN ''R'' THEN ''REFERENCES'' WHEN ''X'' THEN ''EXECUTE''' +
      ' WHEN ''M'' THEN ''MEMBER OF'' WHEN ''G'' THEN ''USAGE''' +
      ' ELSE TRIM(p.RDB$PRIVILEGE) END AS PRIVILEGE,' +
    ' CASE COALESCE(p.RDB$GRANT_OPTION, 0) WHEN 0 THEN ''NO'' ELSE ''YES'' END' +
      ' AS GRANT_OPTION,' +
    ' p.RDB$GRANTOR AS GRANTOR,' +
    ' p.RDB$FIELD_NAME AS COLUMN_NAME' +
    ' FROM RDB$USER_PRIVILEGES p' +
    ' WHERE p.RDB$RELATION_NAME = ' + QuotedStr(AObjectName) +
    TypeFilter +
    ' ORDER BY 1, 3';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.RoutineTypeSQL
  ----------------------------------------------------------------------------
  Returns the query telling a selectable procedure from an executable one.

  Parameters:
    AObjectName - The procedure's bare name.

  Returns:
    One row, column ROUTINE_TYPE: 1 selectable, 2 executable.

  Notes:
    The difference decides the statement: a selectable procedure is called with
    SELECT ... FROM P(...) and yields a set; an executable one is called with
    EXECUTE PROCEDURE and yields at most one row. Calling either the wrong way
    fails, so this cannot be guessed from whether the procedure has output
    parameters - plenty of executable procedures have them.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.RoutineTypeSQL(
  const AObjectName: string): string;
begin
  Result :=
    'SELECT COALESCE(p.RDB$PROCEDURE_TYPE, 2) AS ROUTINE_TYPE' +
    ' FROM RDB$PROCEDURES p' +
    ' WHERE p.RDB$PROCEDURE_NAME = ' + QuotedStr(AObjectName);
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.IndexInfoSQL
  ----------------------------------------------------------------------------
  Returns the query describing one index.

  Parameters:
    AObjectName - The index's bare name.

  Notes:
    Presented as one row of name/value pairs rather than as a wide single row,
    because an index has a handful of properties of different shapes and a
    property page reads better as a list than as a row that scrolls sideways.

    CONSTRAINT is the important one: it is what distinguishes an index somebody
    created from one Firebird made to back a PRIMARY KEY, and no system-flag
    test can tell them apart - see the note on IndicesSQL.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.IndexInfoSQL(
  const AObjectName: string): string;
var
  Name_: string;
begin
  Name_ := QuotedStr(AObjectName);

  Result :=
    'SELECT ''Table'' AS ITEM_NAME, TRIM(i.RDB$RELATION_NAME) AS ITEM_VALUE,' +
      ' 1 AS SORT_ORDER' +
      ' FROM RDB$INDICES i WHERE i.RDB$INDEX_NAME = ' + Name_ +
    ' UNION ALL SELECT ''Columns'',' +
      ' (SELECT LIST(TRIM(s.RDB$FIELD_NAME), '', '')' +
      '  FROM RDB$INDEX_SEGMENTS s WHERE s.RDB$INDEX_NAME = ' + Name_ + '), 2' +
      ' FROM RDB$DATABASE' +
    ' UNION ALL SELECT ''Unique'',' +
      ' CASE COALESCE(i.RDB$UNIQUE_FLAG, 0) WHEN 1 THEN ''Yes'' ELSE ''No'' END, 3' +
      ' FROM RDB$INDICES i WHERE i.RDB$INDEX_NAME = ' + Name_ +
    ' UNION ALL SELECT ''Direction'',' +
      ' CASE COALESCE(i.RDB$INDEX_TYPE, 0) WHEN 1 THEN ''Descending''' +
      ' ELSE ''Ascending'' END, 4' +
      ' FROM RDB$INDICES i WHERE i.RDB$INDEX_NAME = ' + Name_ +
    ' UNION ALL SELECT ''Active'',' +
      ' CASE COALESCE(i.RDB$INDEX_INACTIVE, 0) WHEN 1 THEN ''No'' ELSE ''Yes'' END, 5' +
      ' FROM RDB$INDICES i WHERE i.RDB$INDEX_NAME = ' + Name_ +
    ' UNION ALL SELECT ''Selectivity'',' +
      ' TRIM(CAST(COALESCE(i.RDB$STATISTICS, 0) AS VARCHAR(32))), 6' +
      ' FROM RDB$INDICES i WHERE i.RDB$INDEX_NAME = ' + Name_ +
    ' UNION ALL SELECT ''Backs constraint'',' +
      ' COALESCE(TRIM(c.RDB$CONSTRAINT_NAME), ''(none)''), 7' +
      ' FROM RDB$INDICES i' +
      ' LEFT JOIN RDB$RELATION_CONSTRAINTS c' +
      '   ON c.RDB$INDEX_NAME = i.RDB$INDEX_NAME' +
      ' WHERE i.RDB$INDEX_NAME = ' + Name_ +
    ' UNION ALL SELECT ''Expression'',' +
      ' COALESCE(TRIM(CAST(i.RDB$EXPRESSION_SOURCE AS VARCHAR(1000))), ''(none)''), 8' +
      ' FROM RDB$INDICES i WHERE i.RDB$INDEX_NAME = ' + Name_ +
    ' ORDER BY 3';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.DescriptionSQL
  ----------------------------------------------------------------------------
  Returns the query yielding one object's RDB$DESCRIPTION.

  Parameters:
    ANodeType   - What kind of object it is.
    AObjectName - Its bare name.

  Returns:
    A one-row, one-column query aliased DESCRIPTION, or an empty string for a
    kind whose description is not read this way.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.DescriptionSQL(ANodeType: TSourceObjectKind;
  const AObjectName: string): string;
var
  Table, Column: string;
begin
  case ANodeType of
    sokTable, sokView:
      begin Table := 'RDB$RELATIONS';  Column := 'RDB$RELATION_NAME'; end;
    sokProcedure:
      begin Table := 'RDB$PROCEDURES'; Column := 'RDB$PROCEDURE_NAME'; end;
    sokFunction:
      begin Table := 'RDB$FUNCTIONS';  Column := 'RDB$FUNCTION_NAME'; end;
    sokTrigger:
      begin Table := 'RDB$TRIGGERS';   Column := 'RDB$TRIGGER_NAME'; end;
    sokPackage:
      begin Table := 'RDB$PACKAGES';   Column := 'RDB$PACKAGE_NAME'; end;
    sokException:
      begin Table := 'RDB$EXCEPTIONS'; Column := 'RDB$EXCEPTION_NAME'; end;
    sokDomain:
      begin Table := 'RDB$FIELDS';     Column := 'RDB$FIELD_NAME'; end;
    sokGenerator:
      begin Table := 'RDB$GENERATORS'; Column := 'RDB$GENERATOR_NAME'; end;
    sokIndex:
      begin Table := 'RDB$INDICES';    Column := 'RDB$INDEX_NAME'; end;
    sokRole:
      begin Table := 'RDB$ROLES';      Column := 'RDB$ROLE_NAME'; end;
  else
    Exit('');
  end;

  Result := 'SELECT x.RDB$DESCRIPTION AS DESCRIPTION FROM ' + Table + ' x' +
    ' WHERE x.' + Column + ' = ' + QuotedStr(AObjectName);
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.UserAccountsSQL
  ----------------------------------------------------------------------------
  Returns the query listing every user the current attachment can see, with all
  of their properties - as opposed to UsersSQL, which lists names only for the
  tree's Users folder and answers the collection contract.

  Returns:
    A query with the columns of the users contract.

  Notes:
    SEC$ACTIVE and SEC$ADMIN are BOOLEAN from Firebird 3 onwards, and a boolean
    read as text is not the same string on every client. They are turned into
    YES and NO here so the layer above never has to guess.

    There is no user id or group id. Those existed in the legacy security
    database and the Services API still reports them, but the SQL view does not
    carry them and a modern plugin does not have them at all. A column showing
    a permanent zero would be worse than no column.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.UserAccountsSQL: string;
begin
  Result :=
    'SELECT u.SEC$USER_NAME AS USER_NAME,' +
    ' u.SEC$FIRST_NAME AS FIRST_NAME,' +
    ' u.SEC$MIDDLE_NAME AS MIDDLE_NAME,' +
    ' u.SEC$LAST_NAME AS LAST_NAME,' +
    ' CASE WHEN u.SEC$ACTIVE THEN ''YES'' ELSE ''NO'' END AS IS_ACTIVE,' +
    ' CASE WHEN u.SEC$ADMIN THEN ''YES'' ELSE ''NO'' END AS ADMIN_ROLE,' +
    ' u.SEC$PLUGIN AS PLUGIN_NAME,' +
    ' u.SEC$DESCRIPTION AS USER_DESCRIPTION' +
    ' FROM SEC$USERS u' +
    ' ORDER BY 1';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.AttachmentsSQL
  ----------------------------------------------------------------------------
  Every attachment currently connected to this database.

  Returns:
    The query, aliased to the column names the service reads.

  Notes:
    MON$STATE is 1 for an attachment running a statement and 0 for one
    sitting idle. It can also be null, which falls to the same branch as 0:
    an attachment the server will not describe is not an active one.

    CURRENT_CONNECTION is the id of the attachment asking the question, so
    the comparison marks our own row without a second round trip.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.AttachmentsSQL: string;
begin
  Result :=
    'SELECT a.MON$ATTACHMENT_ID AS ATTACHMENT_ID,' +
    ' a.MON$USER AS USER_NAME,' +
    ' a.MON$ROLE AS ROLE_NAME,' +
    ' a.MON$REMOTE_ADDRESS AS REMOTE_ADDRESS,' +
    ' a.MON$REMOTE_PROCESS AS REMOTE_PROCESS,' +
    ' a.MON$TIMESTAMP AS CONNECTED_AT,' +
    ' CASE WHEN a.MON$STATE = 1 THEN ''ACTIVE'' ELSE ''IDLE'' END' +
    ' AS ATTACHMENT_STATE,' +
    ' CASE WHEN a.MON$ATTACHMENT_ID = CURRENT_CONNECTION' +
    ' THEN ''YES'' ELSE ''NO'' END AS IS_SELF' +
    ' FROM MON$ATTACHMENTS a' +
    ' ORDER BY a.MON$ATTACHMENT_ID';
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.DomainDefinitionSQL
  ----------------------------------------------------------------------------
  Returns the query giving one domain's current definition.

  Parameters:
    AName - Bare name of the domain.

  Returns:
    A query yielding one row, or none when there is no such domain.

  Notes:
    RDB$FIELDS is the domain table - a domain and a column's type are the
    same thing to Firebird - so the type expression the columns list already
    uses works here unchanged.

    The collation join needs the character set as well as the collation id,
    because collation ids are only unique within a character set. Joining on
    the id alone returns the wrong collation name for anything but the
    default character set.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.DomainDefinitionSQL(
  const AName: string): string;
begin
  Result :=
    'SELECT ' + ColumnTypeExpr('f') + ' AS DATA_TYPE,' +
    ' CASE WHEN COALESCE(f.RDB$NULL_FLAG, 0) = 0' +
      ' THEN ''NO'' ELSE ''YES'' END AS NOT_NULL,' +
    ' f.RDB$DEFAULT_SOURCE AS DEFAULT_SOURCE,' +
    ' f.RDB$VALIDATION_SOURCE AS CHECK_SOURCE,' +
    ' co.RDB$COLLATION_NAME AS COLLATION' +
    ' FROM RDB$FIELDS f' +
    ' LEFT JOIN RDB$COLLATIONS co' +
      ' ON co.RDB$COLLATION_ID = f.RDB$COLLATION_ID' +
      ' AND co.RDB$CHARACTER_SET_ID = f.RDB$CHARACTER_SET_ID' +
    ' WHERE f.RDB$FIELD_NAME = ' + QuotedStr(AName);
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.ExceptionDefinitionSQL
  ----------------------------------------------------------------------------
  Returns the query giving one exception's default message.

  Parameters:
    AName - Bare name of the exception.

  Returns:
    A query yielding one row, or none when there is no such exception.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.ExceptionDefinitionSQL(
  const AName: string): string;
begin
  Result :=
    'SELECT e.RDB$MESSAGE AS MESSAGE_TEXT' +
    ' FROM RDB$EXCEPTIONS e' +
    ' WHERE e.RDB$EXCEPTION_NAME = ' + QuotedStr(AName);
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.IndexStateSQL
  ----------------------------------------------------------------------------
  Returns the query saying whether one index is active.

  Parameters:
    AName - Bare name of the index.

  Returns:
    A query yielding one row, or none when there is no such index.

  Notes:
    The stored column is RDB$INDEX_INACTIVE, so the sense is inverted here
    rather than at every call site. It is also null on an index that has
    never been deactivated, which means active.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.IndexStateSQL(
  const AName: string): string;
begin
  Result :=
    'SELECT CASE WHEN COALESCE(i.RDB$INDEX_INACTIVE, 0) = 0' +
      ' THEN ''YES'' ELSE ''NO'' END AS IS_ACTIVE,' +
    ' i.RDB$RELATION_NAME AS TABLE_NAME' +
    ' FROM RDB$INDICES i' +
    ' WHERE i.RDB$INDEX_NAME = ' + QuotedStr(AName);
end;

{------------------------------------------------------------------------------
  TMetadataSqlProviderFB3.SequenceValueSQL
  ----------------------------------------------------------------------------
  Returns the query giving one sequence's current value.

  Parameters:
    AName - Bare name of the sequence.

  Returns:
    A query yielding one row.

  Raises:
    Nothing here, but the query itself fails on the server when there is no
    such sequence: GEN_ID names an object rather than matching a row, so an
    absent sequence is a broken statement and not an empty result.

  Notes:
    The name goes in as a QUOTED IDENTIFIER, not as a string literal, which
    is what makes this different from every other query in this unit. Any
    double quote inside the name is doubled, so a name that contains one
    cannot end the identifier early.
------------------------------------------------------------------------------}
function TMetadataSqlProviderFB3.SequenceValueSQL(
  const AName: string): string;
begin
  Result :=
    'SELECT GEN_ID("' +
    StringReplace(AName, '"', '""', [rfReplaceAll]) +
    '", 0) AS CURRENT_VALUE FROM RDB$DATABASE';
end;

end.
