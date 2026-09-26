{==============================================================================
  Unit:        MetaTypes
  Purpose:     The node type enumeration of the metadata tree, and the helpers
               that answer questions about a node type without a case statement
               at every call site.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils

  Replaces IBConsole's 39 integer constants (NODE_SERVERS..NODE_UNK in
  zluGlobal.pas) and its parallel NODE_ARRAY of display names. Modelled on
  FlameRobin's NodeType enum in metadata/metadataitem.h, which distinguishes an
  item type from the collection ("folder") node that holds items of that type.
==============================================================================}
unit MetaTypes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  { TMetaNodeType
    Every kind of node the object tree can hold. Names ending in a plural are
    collection nodes: the folders that group items of the singular type. }
  TMetaNodeType = (
    mntUnknown,
    mntRoot,
    mntServer,
    mntDatabase,
    mntSchema,           mntSchemas,           // FB6+
    mntDomain,           mntDomains,
    mntSysDomain,        mntSysDomains,
    mntTable,            mntTables,
    mntGTT,              mntGTTs,              // global temporary tables
    mntSysTable,         mntSysTables,
    mntView,             mntViews,
    mntProcedure,        mntProcedures,
    mntFunctionSQL,      mntFunctionSQLs,      // FB3+ PSQL functions
    mntUDF,              mntUDFs,              // legacy external functions
    mntPackage,          mntPackages,          // FB3+
    mntTriggerDML,       mntTriggersDML,
    mntTriggerDB,        mntTriggersDB,
    mntTriggerDDL,       mntTriggersDDL,
    mntGenerator,        mntGenerators,
    mntException,        mntExceptions,
    mntIndex,            mntIndices,
    mntSysIndex,         mntSysIndices,
    mntRole,             mntRoles,
    mntUser,             mntUsers,
    mntCharacterSet,     mntCharacterSets,
    mntCollation,        mntCollations,
    mntPublication,      mntPublications,      // FB4+
    mntBlobFilter,       mntBlobFilters,
    mntColumn,           mntColumns,
    mntParameter,        mntParameters,
    mntConstraintPK,
    mntConstraintFK,
    mntConstraintUnique,
    mntConstraintCheck,
    mntConstraints,
    mntDependency,
    mntBackupAlias,      mntBackupAliases,     // kept from IBConsole
    mntServerLog                               // kept from IBConsole
  );

  TMetaNodeTypes = set of TMetaNodeType;

const
  { Collection nodes: the folders in the tree. }
  MetaCollectionTypes: TMetaNodeTypes = [
    mntSchemas, mntDomains, mntSysDomains, mntTables, mntGTTs, mntSysTables,
    mntViews, mntProcedures, mntFunctionSQLs, mntUDFs, mntPackages,
    mntTriggersDML, mntTriggersDB, mntTriggersDDL, mntGenerators, mntExceptions,
    mntIndices, mntSysIndices, mntRoles, mntUsers, mntCharacterSets,
    mntCollations, mntPublications, mntBlobFilters, mntColumns, mntParameters,
    mntConstraints, mntBackupAliases
  ];

  { Node types that represent an object living inside a database and therefore
    have DDL, dependencies and (usually) permissions. }
  MetaDatabaseObjectTypes: TMetaNodeTypes = [
    mntSchema, mntDomain, mntSysDomain, mntTable, mntGTT, mntSysTable, mntView,
    mntProcedure, mntFunctionSQL, mntUDF, mntPackage, mntTriggerDML,
    mntTriggerDB, mntTriggerDDL, mntGenerator, mntException, mntIndex,
    mntSysIndex, mntRole, mntCharacterSet, mntCollation, mntPublication,
    mntBlobFilter
  ];

  { Node types whose data can be browsed in a grid. }
  MetaBrowsableTypes: TMetaNodeTypes = [
    mntTable, mntGTT, mntSysTable, mntView
  ];

  { Node types that belong to the system rather than to the user. }
  MetaSystemTypes: TMetaNodeTypes = [
    mntSysDomain, mntSysDomains, mntSysTable, mntSysTables, mntSysIndex,
    mntSysIndices
  ];

{ Returns True when ANodeType is a collection ("folder") node. }
function IsCollectionType(ANodeType: TMetaNodeType): Boolean;

{ Returns True when ANodeType is a database object with DDL of its own. }
function IsDatabaseObjectType(ANodeType: TMetaNodeType): Boolean;

{ Returns True when rows of ANodeType can be shown in the data grid. }
function IsBrowsableType(ANodeType: TMetaNodeType): Boolean;

{ Returns True when ANodeType represents a system object, hidden unless the
  user turned on "Show system objects". }
function IsSystemType(ANodeType: TMetaNodeType): Boolean;

{ Returns the collection type that holds items of ANodeType, or mntUnknown
  when the type has no folder (for example mntDatabase). }
function CollectionTypeOf(ANodeType: TMetaNodeType): TMetaNodeType;

{ Returns the item type held by the collection ANodeType, or mntUnknown when
  ANodeType is not a collection. }
function ItemTypeOf(ANodeType: TMetaNodeType): TMetaNodeType;

{ Returns the language key for ANodeType's display name, e.g. 'node.tables'.
  Pass the result to LangStr together with the English default from
  DefaultNodeCaption. }
function NodeCaptionKey(ANodeType: TMetaNodeType): string;

{ Returns the English display name of ANodeType, used as the fallback text of
  the LangStr lookup. }
function DefaultNodeCaption(ANodeType: TMetaNodeType): string;

implementation

type
  { One row of the type table: an item type, its collection type, the language
    key suffix and the English caption of the collection. }
  TNodePair = record
    ItemType: TMetaNodeType;
    CollectionType: TMetaNodeType;
    KeySuffix: string;
    CollectionCaption: string;
    ItemCaption: string;
  end;

const
  { Every item/collection pairing in one place. Adding an object type means
    adding one row here, not editing a case statement in five units. }
  NodePairs: array[0..27] of TNodePair = (
    (ItemType: mntSchema;       CollectionType: mntSchemas;
     KeySuffix: 'schemas';      CollectionCaption: 'Schemas';
     ItemCaption: 'Schema'),
    (ItemType: mntDomain;       CollectionType: mntDomains;
     KeySuffix: 'domains';      CollectionCaption: 'Domains';
     ItemCaption: 'Domain'),
    (ItemType: mntSysDomain;    CollectionType: mntSysDomains;
     KeySuffix: 'sysdomains';   CollectionCaption: 'System Domains';
     ItemCaption: 'System Domain'),
    (ItemType: mntTable;        CollectionType: mntTables;
     KeySuffix: 'tables';       CollectionCaption: 'Tables';
     ItemCaption: 'Table'),
    (ItemType: mntGTT;          CollectionType: mntGTTs;
     KeySuffix: 'gtts';         CollectionCaption: 'Temporary Tables';
     ItemCaption: 'Temporary Table'),
    (ItemType: mntSysTable;     CollectionType: mntSysTables;
     KeySuffix: 'systemtables'; CollectionCaption: 'System Tables';
     ItemCaption: 'System Table'),
    (ItemType: mntView;         CollectionType: mntViews;
     KeySuffix: 'views';        CollectionCaption: 'Views';
     ItemCaption: 'View'),
    (ItemType: mntProcedure;    CollectionType: mntProcedures;
     KeySuffix: 'procedures';   CollectionCaption: 'Stored Procedures';
     ItemCaption: 'Stored Procedure'),
    (ItemType: mntFunctionSQL;  CollectionType: mntFunctionSQLs;
     KeySuffix: 'functions';    CollectionCaption: 'Functions';
     ItemCaption: 'Function'),
    (ItemType: mntUDF;          CollectionType: mntUDFs;
     KeySuffix: 'udfs';         CollectionCaption: 'External Functions';
     ItemCaption: 'External Function'),
    (ItemType: mntPackage;      CollectionType: mntPackages;
     KeySuffix: 'packages';     CollectionCaption: 'Packages';
     ItemCaption: 'Package'),
    (ItemType: mntTriggerDML;   CollectionType: mntTriggersDML;
     KeySuffix: 'triggers';     CollectionCaption: 'Triggers';
     ItemCaption: 'Trigger'),
    (ItemType: mntTriggerDB;    CollectionType: mntTriggersDB;
     KeySuffix: 'dbtriggers';   CollectionCaption: 'Database Triggers';
     ItemCaption: 'Database Trigger'),
    (ItemType: mntTriggerDDL;   CollectionType: mntTriggersDDL;
     KeySuffix: 'ddltriggers';  CollectionCaption: 'DDL Triggers';
     ItemCaption: 'DDL Trigger'),
    (ItemType: mntGenerator;    CollectionType: mntGenerators;
     KeySuffix: 'generators';   CollectionCaption: 'Generators';
     ItemCaption: 'Generator'),
    (ItemType: mntException;    CollectionType: mntExceptions;
     KeySuffix: 'exceptions';   CollectionCaption: 'Exceptions';
     ItemCaption: 'Exception'),
    (ItemType: mntIndex;        CollectionType: mntIndices;
     KeySuffix: 'indices';      CollectionCaption: 'Indexes';
     ItemCaption: 'Index'),
    (ItemType: mntSysIndex;     CollectionType: mntSysIndices;
     KeySuffix: 'sysindices';   CollectionCaption: 'System Indexes';
     ItemCaption: 'System Index'),
    (ItemType: mntRole;         CollectionType: mntRoles;
     KeySuffix: 'roles';        CollectionCaption: 'Roles';
     ItemCaption: 'Role'),
    (ItemType: mntUser;         CollectionType: mntUsers;
     KeySuffix: 'users';        CollectionCaption: 'Users';
     ItemCaption: 'User'),
    (ItemType: mntCharacterSet; CollectionType: mntCharacterSets;
     KeySuffix: 'charactersets'; CollectionCaption: 'Character Sets';
     ItemCaption: 'Character Set'),
    (ItemType: mntCollation;    CollectionType: mntCollations;
     KeySuffix: 'collations';   CollectionCaption: 'Collations';
     ItemCaption: 'Collation'),
    (ItemType: mntPublication;  CollectionType: mntPublications;
     KeySuffix: 'publications'; CollectionCaption: 'Publications';
     ItemCaption: 'Publication'),
    (ItemType: mntBlobFilter;   CollectionType: mntBlobFilters;
     KeySuffix: 'blobfilters';  CollectionCaption: 'Blob Filters';
     ItemCaption: 'Blob Filter'),
    (ItemType: mntColumn;       CollectionType: mntColumns;
     KeySuffix: 'columns';      CollectionCaption: 'Columns';
     ItemCaption: 'Column'),
    (ItemType: mntParameter;    CollectionType: mntParameters;
     KeySuffix: 'parameters';   CollectionCaption: 'Parameters';
     ItemCaption: 'Parameter'),
    (ItemType: mntUnknown;      CollectionType: mntConstraints;
     KeySuffix: 'constraints';  CollectionCaption: 'Constraints';
     ItemCaption: 'Constraint'),
    (ItemType: mntBackupAlias;  CollectionType: mntBackupAliases;
     KeySuffix: 'backupaliases'; CollectionCaption: 'Backup Aliases';
     ItemCaption: 'Backup Alias')
  );

{------------------------------------------------------------------------------
  IsCollectionType
  ----------------------------------------------------------------------------
  Returns True when ANodeType is a folder node rather than an object.
------------------------------------------------------------------------------}
function IsCollectionType(ANodeType: TMetaNodeType): Boolean;
begin
  Result := ANodeType in MetaCollectionTypes;
end;

{------------------------------------------------------------------------------
  IsDatabaseObjectType
  ----------------------------------------------------------------------------
  Returns True when ANodeType is an object inside a database, and therefore has
  DDL, dependencies and usually permissions.
------------------------------------------------------------------------------}
function IsDatabaseObjectType(ANodeType: TMetaNodeType): Boolean;
begin
  Result := ANodeType in MetaDatabaseObjectTypes;
end;

{------------------------------------------------------------------------------
  IsBrowsableType
  ----------------------------------------------------------------------------
  Returns True when rows of ANodeType can be shown in the data grid.
------------------------------------------------------------------------------}
function IsBrowsableType(ANodeType: TMetaNodeType): Boolean;
begin
  Result := ANodeType in MetaBrowsableTypes;
end;

{------------------------------------------------------------------------------
  IsSystemType
  ----------------------------------------------------------------------------
  Returns True when ANodeType is a system object, hidden unless the user turned
  on "Show system objects".
------------------------------------------------------------------------------}
function IsSystemType(ANodeType: TMetaNodeType): Boolean;
begin
  Result := ANodeType in MetaSystemTypes;
end;

{------------------------------------------------------------------------------
  CollectionTypeOf
  ----------------------------------------------------------------------------
  Finds the folder type that holds items of a given type.

  Parameters:
    ANodeType - An item type.

  Returns:
    The matching collection type, or mntUnknown when the type has no folder.
------------------------------------------------------------------------------}
function CollectionTypeOf(ANodeType: TMetaNodeType): TMetaNodeType;
var
  I: Integer;
begin
  for I := Low(NodePairs) to High(NodePairs) do
  begin
    if NodePairs[I].ItemType = ANodeType then
      Exit(NodePairs[I].CollectionType);
  end;
  Result := mntUnknown;
end;

{------------------------------------------------------------------------------
  ItemTypeOf
  ----------------------------------------------------------------------------
  Finds the item type held by a folder.

  Parameters:
    ANodeType - A collection type.

  Returns:
    The matching item type, or mntUnknown when ANodeType is not a collection
    or holds more than one type (the constraints folder).
------------------------------------------------------------------------------}
function ItemTypeOf(ANodeType: TMetaNodeType): TMetaNodeType;
var
  I: Integer;
begin
  for I := Low(NodePairs) to High(NodePairs) do
  begin
    if NodePairs[I].CollectionType = ANodeType then
      Exit(NodePairs[I].ItemType);
  end;
  Result := mntUnknown;
end;

{------------------------------------------------------------------------------
  NodeCaptionKey
  ----------------------------------------------------------------------------
  Returns the language-file key for a node type's caption.

  Parameters:
    ANodeType - The type to name.

  Returns:
    A key such as 'node.tables'. Types outside the pairing table get a key
    derived from the enumeration name, so nothing is ever unnamed.
------------------------------------------------------------------------------}
function NodeCaptionKey(ANodeType: TMetaNodeType): string;
var
  I: Integer;
begin
  for I := Low(NodePairs) to High(NodePairs) do
  begin
    if NodePairs[I].CollectionType = ANodeType then
      Exit('node.' + NodePairs[I].KeySuffix);
    if NodePairs[I].ItemType = ANodeType then
      Exit('node.' + NodePairs[I].KeySuffix + '.item');
  end;

  case ANodeType of
    mntRoot:      Result := 'node.root';
    mntServer:    Result := 'node.server';
    mntDatabase:  Result := 'node.database';
    mntServerLog: Result := 'node.serverlog';
  else
    Result := 'node.unknown';
  end;
end;

{------------------------------------------------------------------------------
  DefaultNodeCaption
  ----------------------------------------------------------------------------
  Returns the English caption of a node type.

  Parameters:
    ANodeType - The type to name.

  Returns:
    The English text, used as the LangStr fallback so an untranslated tree is
    still readable.
------------------------------------------------------------------------------}
function DefaultNodeCaption(ANodeType: TMetaNodeType): string;
var
  I: Integer;
begin
  for I := Low(NodePairs) to High(NodePairs) do
  begin
    if NodePairs[I].CollectionType = ANodeType then
      Exit(NodePairs[I].CollectionCaption);
    if NodePairs[I].ItemType = ANodeType then
      Exit(NodePairs[I].ItemCaption);
  end;

  case ANodeType of
    mntRoot:             Result := 'Firebird Servers';
    mntServer:           Result := 'Server';
    mntDatabase:         Result := 'Database';
    mntServerLog:        Result := 'Server Log';
    mntConstraintPK:     Result := 'Primary Key';
    mntConstraintFK:     Result := 'Foreign Key';
    mntConstraintUnique: Result := 'Unique Constraint';
    mntConstraintCheck:  Result := 'Check Constraint';
    mntDependency:       Result := 'Dependency';
  else
    Result := 'Unknown';
  end;
end;

end.
