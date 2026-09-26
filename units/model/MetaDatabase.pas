{==============================================================================
  Unit:        MetaDatabase
  Purpose:     A registered database in the object tree. Owns its connection
               profile, its detected server version and the folder nodes that
               appear once it is connected.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils, MetaItem, MetaCollection, MetaTypes, Identifier,
               ConnectionProfile, ServerVersion, FeatureSet,
               MetadataSqlProvider, MetadataSqlProviderFactory

  Descendant of IBConsole's TibcDatabaseNode, minus the Win32 tree handles and
  minus the live TIBDatabase: the attachment lives in units/db/DatabaseContext
  and is attached here once it exists.

  A disconnected database has no children. Folders are built at connect time,
  from the SQL provider chosen for the server's actual version, so a Firebird 3
  database never shows a Publications folder and a Firebird 6 one gains
  Schemas without a line of conditional code in the tree.
==============================================================================}
unit MetaDatabase;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, MetaItem, MetaCollection, MetaTypes, Identifier,
  ConnectionProfile, ServerRegistration, ServerVersion, FeatureSet,
  MetadataSqlProvider, MetadataSqlProviderFactory,
  DatabaseContext, DatabaseRow, SqlSession, DataEditor, SecurityService,
  AttachmentService, ScriptGenerator, IbqError, SqlStatementSplitter,
  DdlStatements,
  Classes, IBExtract;

type
  { Which detail list a property page is asking for. }
  TObjectDetail = (
    odColumns, odIndices, odConstraints, odTriggers, odParameters,
    odDependsOn, odUsedBy, odPrivileges, odIndexInfo
  );

  { TMetaDatabase
    One registered database. }
  TMetaDatabase = class(TMetaItem)
  private
    FProfile: TConnectionProfile;
    FServerRegistration: TServerRegistration;
    FOwnsProfile: Boolean;
    FConnected: Boolean;
    FServerVersion: TServerVersion;
    FSqlProvider: TMetadataSqlProvider;
    FShowSystemObjects: Boolean;
    FContext: TDatabaseContext;
    FSessionProfile: TConnectionProfile;
    { Attaches through AProfile, which must outlive the attachment. }
    procedure AttachWith(AProfile: TConnectionProfile;
      const APassword: string);
    procedure AddCollection(ACollectionType, AItemType: TMetaNodeType;
      const ASql: string);
    procedure LoadCollectionItems(ACollection: TMetaCollection);
  protected
    procedure LoadChildren; override;
  public
    constructor CreateForProfile(AParent: TMetaItem;
      AProfile: TConnectionProfile;
      AServerRegistration: TServerRegistration = nil;
      AOwnsProfile: Boolean = False);
    destructor Destroy; override;

    { Attaches to the database and makes the folders appear.

      Parameters:
        APassword - The password to attach with; never stored.

      Raises:
        EIbqDatabaseError - The attachment failed.
        EIbqUnsupported   - The server is too old, or the database is not SQL
                            dialect 3. }
    procedure Connect(const APassword: string);

    { Attaches as a different user or role than the registration names, for
      this connection only.

      Parameters:
        AUserName - The user to attach as.
        APassword - Their password; never stored.
        ARole     - The role to assume, or an empty string for none.

      Raises:
        The same as Connect.

      Notes:
        The registration is not changed: disconnecting and connecting again
        goes back to the registered user. }
    procedure ConnectAs(const AUserName, APassword, ARole: string);

    { Detaches and drops everything read from the database. Safe when not
      connected. }
    procedure Disconnect;

    { The user the current attachment was made as - which after Connect As is
      not the registration's user - or the registered user when not
      connected. }
    function ConnectedUserName: string;

    { Creates a new database file on a server, or locally for embedded use.

      Parameters:
        AProfile            - Where and as whom; its DatabasePath, UserName
                              and CharacterSet are used. Not owned.
        AServerRegistration - The server it is created on, which decides the
                              client library; nil for an embedded database.
        APassword           - The owner's password; never stored.
        APageSize           - Bytes per page, or 0 for the server's default.

      Raises:
        EIbqDatabaseError - The server refused.

      Notes:
        Creates nothing in the tree. Registering the new file is the
        caller's decision. }
    class procedure CreateDatabaseFile(AProfile: TConnectionProfile;
      AServerRegistration: TServerRegistration; const APassword: string;
      APageSize: Integer);

    { Deletes this database from the server and leaves the node
      disconnected.

      Raises:
        EIbqError         - Not connected.
        EIbqDatabaseError - The server refused; the node stays connected. }
    procedure DropDatabase;

    { Records that the database is now attached, and with which version.

      Parameters:
        AVersion - The version detected on the attachment.

      Notes:
        Called by Connect. Exposed separately so a test can drive the model
        without a server. }
    procedure MarkConnected(const AVersion: TServerVersion);
    { Records that the database is no longer attached and drops the folders. }
    procedure MarkDisconnected;

    { The text shown in the tree. }
    function DisplayName: string; override;
    { True while attached. }
    function IsConnected: Boolean;

    { Runs one of the object-detail queries for ANodeType's object.

      Parameters:
        ADetail     - Which detail list is wanted.
        ANodeType   - The kind of object it belongs to.
        AObjectName - The object's bare name.

      Returns:
        The result set as text. An empty table when the detail does not apply
        to this kind of object, or the database is not connected - a property
        page asking for something that does not exist is normal, not an error.

      Raises:
        EIbqDatabaseError - The query failed. }
    function FetchDetail(ADetail: TObjectDetail; ANodeType: TMetaNodeType;
      const AObjectName: string): TDataTable;

    { Returns the PSQL or view source of one object, or an empty string when
      the kind has none. }
    function FetchSourceText(ANodeType: TMetaNodeType;
      const AObjectName: string): string;

    { Returns the DDL that would recreate one object, via IBX's extractor. }
    function FetchObjectDdl(ANodeType: TMetaNodeType;
      const AObjectName: string): string;

    { Returns the DDL of the whole database. }
    function FetchDatabaseDdl: string;

    { Runs one DDL statement against this database.

      Parameters:
        ASql - A single statement, without a terminator.

      Raises:
        EIbqError         - The database is not connected.
        EIbqDatabaseError - The statement failed.

      Notes:
        Commits on its own, on the DDL transaction. This is what the DDL
        editing dialogs run through, so that a form never holds a database
        context of its own. Anything the USER typed goes through the SQL
        editor's session instead, under their own commit and rollback. }
    procedure ExecuteDdl(const ASql: string);

    { Runs a generated DDL script, statement by statement.

      Parameters:
        ASql - One statement, or several separated by ';'.

      Returns:
        How many statements ran.

      Raises:
        EIbqDatabaseError - A statement failed. Everything before it has
                            already been committed and stays committed; the
                            count of those is in the exception message,
                            because Firebird cannot take DDL back and a
                            caller that reported a clean failure would be
                            lying.

      Notes:
        Split with the same splitter the SQL editor uses, so a generated
        script and a typed one are divided the same way. }
    function ExecuteDdlScript(const ASql: string): Integer;

    { Reads one domain's current definition.

      Parameters:
        AName   - Bare name of the domain.
        ADomain - Receives the definition; undefined when the result is
                  False.

      Returns:
        True when the domain was found. }
    function FetchDomainDefinition(const AName: string;
      out ADomain: TDdlDomain): Boolean;

    { Reads one exception's default message.

      Parameters:
        AName    - Bare name of the exception.
        AMessage - Receives the message.

      Returns:
        True when the exception was found. }
    function FetchExceptionMessage(const AName: string;
      out AMessage: string): Boolean;

    { Reads whether one index is active.

      Parameters:
        AName   - Bare name of the index.
        AActive - Receives True when the index is active.

      Returns:
        True when the index was found. }
    function FetchIndexActive(const AName: string;
      out AActive: Boolean): Boolean;

    { Reads one sequence's current value.

      Parameters:
        AName  - Bare name of the sequence.
        AValue - Receives the value the sequence has reached.

      Returns:
        True when it could be read. }
    function FetchSequenceValue(const AName: string;
      out AValue: Int64): Boolean;

    { Reads the first rows of a table or view, for the Data tab.

      Parameters:
        ANodeType   - Must be a browsable kind; anything else yields an empty
                      table.
        AObjectName - The relation's bare name.
        AMaxRows    - How many rows to fetch.

      Returns:
        The rows as text.

      Notes:
        Runs on the metadata transaction, which is READ ONLY: browsing data
        must never be able to hold a lock on a table the user is only looking
        at. Editing arrives in M4 and will need a transaction of its own.

      Raises:
        EIbqDatabaseError - The query failed. }
    function FetchRelationData(ANodeType: TMetaNodeType;
      const AObjectName: string; AMaxRows: Integer = 200): TDataTable;

    { Builds a SELECT / INSERT / UPDATE / DELETE / MERGE / EXECUTE statement
      for one object.

      Parameters:
        AKind       - Which statement to build.
        ANodeType   - What kind of object it is.
        AObjectName - The object's bare name.

      Returns:
        The statement, or an empty string when the kind does not apply to this
        object - a MERGE on a generator, say.

      Notes:
        The column list and the primary key are read from the database rather
        than assumed, which is the whole point: nobody wants to type forty
        column names, and an UPDATE with one of them wrong changes the wrong
        rows.

      Raises:
        EIbqDatabaseError - A metadata query failed. }
    function GenerateScript(AKind: TScriptKind; ANodeType: TMetaNodeType;
      const AObjectName: string): string;

    { True when a procedure is selectable and must be called with SELECT.

      Parameters:
        AObjectName - The procedure's bare name.

      Returns:
        True for a selectable procedure, False for an executable one and for
        anything that is not a procedure. }
    function IsSelectableRoutine(const AObjectName: string): Boolean;

    { Creates an updatable dataset over one table, for the Data tab.

      Parameters:
        ANodeType   - The relation's kind.
        AObjectName - Its bare name.
        ARowLimit   - How many rows to fetch.

      Returns:
        A new editor, or nil when the database is not connected or the object
        is not a relation. The CALLER owns it. The editor decides for itself
        whether editing is possible and says why not - see CanEdit and
        ReadOnlyReason.

      Notes:
        Computed columns are excluded from the writable set: Firebird rejects
        them in an INSERT or UPDATE, and including them would make every post
        fail rather than merely ignoring the column.

      Raises:
        EIbqDatabaseError - A metadata query failed. }
    function CreateDataEditor(ANodeType: TMetaNodeType;
      const AObjectName: string; ARowLimit: Integer = 500): TDataEditor;

    { Creates a SQL session on this database's attachment.

      Returns:
        A new session with its own transaction, or nil when the database is not
        connected. The CALLER owns it and must free it - normally an editor
        window, which frees the session when it closes and thereby rolls back
        anything the user left uncommitted. }
    function CreateSqlSession: TSqlSession;

    { Creates a user-management service that works through this database.

      Returns:
        The service, for the caller to free, or nil when not connected.

      Notes:
        Users belong to the SERVER, not to this database - any connected
        database on the same server manages the same accounts. The database is
        needed only because CREATE USER is a statement and a statement needs an
        attachment. }
    function CreateSecurityService: TSecurityService;

    { Creates a service for this database's attachments.

      Returns:
        The service, for the caller to free, or nil when not connected.

      Notes:
        Attachments belong to THIS database, unlike users: MON$ATTACHMENTS
        lists who is connected here and nowhere else, so the connection is
        the subject and not merely the means. }
    function CreateAttachmentService: TAttachmentService;

    { The fbclient library this database must be opened with.

      Returns:
        For a database on a server, the SERVER registration's library, because
        the client is loaded once per server connection. For an embedded
        database, its own, since it has no server. An empty string means the
        system default is to be used.

      Notes:
        This is the single place the question is answered. Nothing else should
        read TConnectionProfile.ClientLibrary directly. }
    function EffectiveClientLibrary: string;

    { The registration this node was built from. }
    property Profile: TConnectionProfile read FProfile;
    { The owning server's registration, or nil for an embedded database. }
    property ServerReg: TServerRegistration read FServerRegistration;
    { The detected server version; unknown while disconnected. }
    property Version: TServerVersion read FServerVersion;
    { The metadata SQL for this server's version; nil while disconnected. }
    property SqlProvider: TMetadataSqlProvider read FSqlProvider;
    { Whether system folders are built. Changing it rebuilds the folders. }
    property ShowSystemObjects: Boolean read FShowSystemObjects
      write FShowSystemObjects;
  end;

implementation

{------------------------------------------------------------------------------
  TMetaDatabase.CreateForProfile
  ----------------------------------------------------------------------------
  Creates a database node for a registration.

  Parameters:
    AParent      - The server node, or the root for an embedded database.
    AProfile     - The registration. Must not be nil.
    AServerRegistration - The owning server, or nil for an embedded database.
                   Supplies the client library; not owned here.
    AOwnsProfile - True when this node should free the profile. False when the
                   profile belongs to the registration store, which is the
                   normal case.
------------------------------------------------------------------------------}
constructor TMetaDatabase.CreateForProfile(AParent: TMetaItem;
  AProfile: TConnectionProfile; AServerRegistration: TServerRegistration;
  AOwnsProfile: Boolean);
begin
  inherited Create(AParent, mntDatabase,
    TIdentifier.FromDatabase(AProfile.TreeCaption));
  FProfile := AProfile;
  FServerRegistration := AServerRegistration;
  FOwnsProfile := AOwnsProfile;
  FConnected := False;
  FServerVersion := UnknownServerVersion;
  FSqlProvider := nil;
  FShowSystemObjects := False;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.Destroy
  ----------------------------------------------------------------------------
  Frees the SQL provider, and the profile when this node owns it.
------------------------------------------------------------------------------}
destructor TMetaDatabase.Destroy;
begin
  ClearChildren;
  FreeAndNil(FContext);
  FreeAndNil(FSessionProfile);
  FreeAndNil(FSqlProvider);
  if FOwnsProfile then
    FreeAndNil(FProfile);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.Connect
  ----------------------------------------------------------------------------
  Attaches to the database and makes the folders appear.

  Parameters:
    APassword - The password to attach with; held only for the length of the
                call.

  Raises:
    EIbqDatabaseError - The attachment failed; carries the status vector.
    EIbqUnsupported   - The server is older than Firebird 3.0, or the database
                        is not SQL dialect 3.

  Notes:
    A failed connect leaves the node exactly as it was, disconnected and with
    no context, rather than half attached.
------------------------------------------------------------------------------}
procedure TMetaDatabase.Connect(const APassword: string);
begin
  if IsConnected then
    Exit;

  FreeAndNil(FSessionProfile);
  AttachWith(FProfile, APassword);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.ConnectAs
  ----------------------------------------------------------------------------
  Attaches as a different user or role, for this connection only.

  Parameters:
    AUserName - The user to attach as.
    APassword - Their password; never stored.
    ARole     - The role to assume, or an empty string for none.

  Notes:
    A copy of the registration carries the other credentials, because the
    context borrows its profile for as long as it is attached. Changing the
    registration itself would be simpler and wrong: the next save would write
    a user the administrator only meant to try once into the file.
------------------------------------------------------------------------------}
procedure TMetaDatabase.ConnectAs(const AUserName, APassword, ARole: string);
var
  Session: TConnectionProfile;
begin
  if IsConnected then
    Exit;

  FreeAndNil(FSessionProfile);
  Session := FProfile.Clone;
  Session.UserName := AUserName;
  Session.Role := ARole;
  Session.Password := '';
  FSessionProfile := Session;
  try
    AttachWith(FSessionProfile, APassword);
  except
    FreeAndNil(FSessionProfile);
    raise;
  end;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.AttachWith
  ----------------------------------------------------------------------------
  Creates the context for a profile and attaches it.

  Parameters:
    AProfile  - The profile to attach with. Borrowed by the context, so it
                must outlive the attachment.
    APassword - The password; never stored.

  Raises:
    The same as Connect. The context is freed again on failure.
------------------------------------------------------------------------------}
procedure TMetaDatabase.AttachWith(AProfile: TConnectionProfile;
  const APassword: string);
begin
  FreeAndNil(FContext);
  FContext := TDatabaseContext.Create(AProfile, EffectiveClientLibrary);
  try
    FContext.Connect(APassword);
  except
    FreeAndNil(FContext);
    raise;
  end;

  MarkConnected(FContext.Version);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.Disconnect
  ----------------------------------------------------------------------------
  Detaches and drops everything read from the database.
------------------------------------------------------------------------------}
procedure TMetaDatabase.Disconnect;
begin
  FreeAndNil(FContext);
  // after the context: it borrows this profile until it is gone
  FreeAndNil(FSessionProfile);
  MarkDisconnected;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.CreateDatabaseFile
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The client library is chosen the same way EffectiveClientLibrary chooses
    it for a registered database, so the file is created by the very client
    that will later open it.
------------------------------------------------------------------------------}
class procedure TMetaDatabase.CreateDatabaseFile(AProfile: TConnectionProfile;
  AServerRegistration: TServerRegistration; const APassword: string;
  APageSize: Integer);
var
  Context: TDatabaseContext;
  ClientLibrary: string;
begin
  if (AProfile.Mode <> cmEmbedded) and (AServerRegistration <> nil) then
    ClientLibrary := AServerRegistration.ClientLibrary
  else
    ClientLibrary := AProfile.ClientLibrary;

  Context := TDatabaseContext.Create(AProfile, ClientLibrary);
  try
    Context.CreateDatabase(APassword, APageSize);
  finally
    Context.Free;
  end;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.DropDatabase
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The node is marked disconnected only after the server has agreed. A
    refused drop - another user still attached, say - leaves everything as it
    was, which is the only honest state to leave it in.
------------------------------------------------------------------------------}
procedure TMetaDatabase.DropDatabase;
begin
  if (FContext = nil) or not FContext.IsConnected then
    raise EIbqError.Create('The database is not connected.');

  FContext.DropDatabase;
  Disconnect;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.ConnectedUserName
  ----------------------------------------------------------------------------
  Returns the user the attachment was made as.

  Returns:
    The Connect As user while one is in use, otherwise the registration's.
------------------------------------------------------------------------------}
function TMetaDatabase.ConnectedUserName: string;
begin
  if FSessionProfile <> nil then
    Result := FSessionProfile.UserName
  else
    Result := FProfile.UserName;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.LoadCollectionItems
  ----------------------------------------------------------------------------
  Fills one folder by running its query through the attachment.

  Parameters:
    ACollection - The folder to fill; supplies the query and receives the
                  items.

  Notes:
    This method is the bridge between the two layers, and it is the reason the
    model never sees IBX: the context returns plain TMetaRow records and the
    folder turns them into items.
------------------------------------------------------------------------------}
procedure TMetaDatabase.LoadCollectionItems(ACollection: TMetaCollection);
var
  Rows: TMetaRowArray;
  I: Integer;
begin
  if (FContext = nil) or not FContext.IsConnected then
    Exit;

  Rows := FContext.FetchCollection(ACollection.Sql);
  for I := Low(Rows) to High(Rows) do
    ACollection.AddItem(Rows[I].SchemaName, Rows[I].ObjectName,
      Rows[I].ObjectId);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.MarkConnected
  ----------------------------------------------------------------------------
  Records a successful connection and prepares the metadata SQL.

  Parameters:
    AVersion - The version detected on the new attachment.

  Raises:
    EIbqUnsupported - The server is older than Firebird 3.0.
------------------------------------------------------------------------------}
procedure TMetaDatabase.MarkConnected(const AVersion: TServerVersion);
begin
  FServerVersion := AVersion;
  FreeAndNil(FSqlProvider);
  FSqlProvider := CreateMetadataSqlProvider(AVersion);
  FConnected := True;
  Invalidate;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.MarkDisconnected
  ----------------------------------------------------------------------------
  Records a disconnection and drops everything read from the database.

  Notes:
    Freeing the children tells every open property page for an object in this
    database that its subject is gone, so the pages close themselves rather
    than pointing at a dead connection.
------------------------------------------------------------------------------}
procedure TMetaDatabase.MarkDisconnected;
begin
  FConnected := False;
  FServerVersion := UnknownServerVersion;
  FreeAndNil(FSqlProvider);
  Invalidate;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.IsConnected
  ----------------------------------------------------------------------------
  Returns True while the database is attached.
------------------------------------------------------------------------------}
function TMetaDatabase.IsConnected: Boolean;
begin
  Result := FConnected;
end;

{------------------------------------------------------------------------------
  SourceKindOf
  ----------------------------------------------------------------------------
  Maps a tree node type onto the narrower kind the SQL layer understands.

  Parameters:
    ANodeType - The model's node type.
    AKind     - Receives the SQL layer's kind.

  Returns:
    True when the node type has a matching kind. False for the types that carry
    no source and no description of their own, such as folders.

  Notes:
    This mapping is the seam between the model's vocabulary and the SQL
    layer's. It exists so that MetadataSqlProvider does not have to depend on
    MetaTypes, which would drag the whole model into the database layer.
------------------------------------------------------------------------------}
function SourceKindOf(ANodeType: TMetaNodeType;
  out AKind: TSourceObjectKind): Boolean;
begin
  Result := True;
  case ANodeType of
    mntTable, mntGTT, mntSysTable: AKind := sokTable;
    mntView:                       AKind := sokView;
    mntProcedure:                  AKind := sokProcedure;
    mntFunctionSQL, mntUDF:        AKind := sokFunction;
    mntTriggerDML,
    mntTriggerDB,
    mntTriggerDDL:                 AKind := sokTrigger;
    mntPackage:                    AKind := sokPackage;
    mntException:                  AKind := sokException;
    mntDomain, mntSysDomain:       AKind := sokDomain;
    mntGenerator:                  AKind := sokGenerator;
    mntIndex, mntSysIndex:         AKind := sokIndex;
    mntRole:                       AKind := sokRole;
    mntCharacterSet:               AKind := sokCharacterSet;
    mntCollation:                  AKind := sokCollation;
  else
    AKind := sokTable;
    Result := False;
  end;
end;

{------------------------------------------------------------------------------
  ExtractKindOf
  ----------------------------------------------------------------------------
  Maps a tree node type onto IBX's extract category.

  Parameters:
    ANodeType - The model's node type.
    AKind     - Receives the extract category.

  Returns:
    True when the node type can be extracted on its own.
------------------------------------------------------------------------------}
function ExtractKindOf(ANodeType: TMetaNodeType;
  out AKind: TExtractObjectTypes): Boolean;
begin
  Result := True;
  case ANodeType of
    mntTable, mntGTT, mntSysTable: AKind := eoTable;
    mntView:                       AKind := eoView;
    mntProcedure:                  AKind := eoProcedure;
    mntFunctionSQL:                AKind := eoFunction;
    mntUDF:                        AKind := eoExternalFunction;
    mntPackage:                    AKind := eoPackage;
    mntTriggerDML,
    mntTriggerDB,
    mntTriggerDDL:                 AKind := eoTrigger;
    mntGenerator:                  AKind := eoGenerator;
    mntException:                  AKind := eoException;
    mntDomain, mntSysDomain:       AKind := eoDomain;
    mntRole:                       AKind := eoRole;
    mntBlobFilter:                 AKind := eoBLOBFilter;
    mntDatabase:                   AKind := eoDatabase;
  else
    AKind := eoDatabase;
    Result := False;
  end;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.FetchDetail
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Which details apply to which object kind is decided here rather than in the
    UI, so a property page can ask for anything and get an empty table when it
    does not apply. That keeps the tab-building code in the form simple and
    keeps the knowledge in the model.
------------------------------------------------------------------------------}
function TMetaDatabase.FetchDetail(ADetail: TObjectDetail;
  ANodeType: TMetaNodeType; const AObjectName: string): TDataTable;
var
  Sql: string;
  Kind: TSourceObjectKind;
  IsRelation, IsRoutine: Boolean;
begin
  Result := Default(TDataTable);
  if (FContext = nil) or not FContext.IsConnected or (AObjectName = '') then
    Exit;

  IsRelation := ANodeType in [mntTable, mntGTT, mntSysTable, mntView];
  IsRoutine := ANodeType in [mntProcedure, mntFunctionSQL, mntUDF];

  Sql := '';
  case ADetail of
    odColumns:
      if IsRelation then
        Sql := FSqlProvider.RelationColumnsSQL(AObjectName);
    odIndices:
      if IsRelation then
        Sql := FSqlProvider.RelationIndicesSQL(AObjectName);
    odConstraints:
      if IsRelation then
        Sql := FSqlProvider.RelationConstraintsSQL(AObjectName);
    odTriggers:
      if IsRelation then
        Sql := FSqlProvider.RelationTriggersSQL(AObjectName);
    odParameters:
      if IsRoutine then
        Sql := FSqlProvider.RoutineParametersSQL(AObjectName);
    odDependsOn:
      Sql := FSqlProvider.DependenciesSQL(AObjectName, True);
    odUsedBy:
      Sql := FSqlProvider.DependenciesSQL(AObjectName, False);
    odPrivileges:
      if SourceKindOf(ANodeType, Kind) then
        Sql := FSqlProvider.PrivilegesSQL(AObjectName, Kind);
    odIndexInfo:
      if ANodeType in [mntIndex, mntSysIndex] then
        Sql := FSqlProvider.IndexInfoSQL(AObjectName);
  end;

  if Sql = '' then
    Exit;

  Result := FContext.FetchTable(Sql);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.FetchSourceText
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TMetaDatabase.FetchSourceText(ANodeType: TMetaNodeType;
  const AObjectName: string): string;
var
  Kind: TSourceObjectKind;
  Sql: string;
begin
  Result := '';
  if (FContext = nil) or not FContext.IsConnected or (AObjectName = '') then
    Exit;
  if not SourceKindOf(ANodeType, Kind) then
    Exit;

  Sql := FSqlProvider.ObjectSourceSQL(Kind, AObjectName);
  if Sql = '' then
    Exit;

  Result := FContext.FetchScalar(Sql, '');
end;

{------------------------------------------------------------------------------
  TMetaDatabase.FetchObjectDdl
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TMetaDatabase.FetchObjectDdl(ANodeType: TMetaNodeType;
  const AObjectName: string): string;
var
  Kind: TExtractObjectTypes;
begin
  Result := '';
  if (FContext = nil) or not FContext.IsConnected then
    Exit;
  if not ExtractKindOf(ANodeType, Kind) then
    Exit;

  Result := FContext.ExtractDdl(Kind, AObjectName);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.FetchDatabaseDdl
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TMetaDatabase.FetchDatabaseDdl: string;
begin
  Result := '';
  if (FContext = nil) or not FContext.IsConnected then
    Exit;
  Result := FContext.ExtractDdl(eoDatabase, '');
end;

{------------------------------------------------------------------------------
  TMetaDatabase.ExecuteDdl
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure TMetaDatabase.ExecuteDdl(const ASql: string);
begin
  if (FContext = nil) or not FContext.IsConnected then
  begin
    raise EIbqError.Create('The database is not connected.');
  end;
  FContext.ExecuteDdl(ASql);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.ExecuteDdlScript
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TMetaDatabase.ExecuteDdlScript(const ASql: string): Integer;
var
  Statements: TSqlStatementArray;
  I: Integer;
begin
  Result := 0;
  Statements := SplitSqlScript(ASql);
  for I := 0 to High(Statements) do
  begin
    if Statements[I].IsEmpty then
    begin
      Continue;
    end;
    try
      ExecuteDdl(Statements[I].Text);
      Inc(Result);
    except
      on E: Exception do
      begin
        if Result > 0 then
        begin
          raise EIbqDatabaseError.Create(
            Format('%s'#13#10#13#10'%d earlier statement(s) ran and are '
              + 'committed; Firebird cannot take DDL back.',
              [E.Message, Result]), 0, 0, nil, Statements[I].Text);
        end;
        raise;
      end;
    end;
  end;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.FetchRelationData
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The row cap is applied with FIRST rather than by stopping the fetch, so the
    server sends only what is wanted. On a table of forty million rows the
    difference is the whole point.
------------------------------------------------------------------------------}
function TMetaDatabase.FetchRelationData(ANodeType: TMetaNodeType;
  const AObjectName: string; AMaxRows: Integer): TDataTable;
var
  RelationName: TIdentifier;
begin
  Result := Default(TDataTable);
  if (FContext = nil) or not FContext.IsConnected then
    Exit;
  if not IsBrowsableType(ANodeType) then
    Exit;
  if AMaxRows < 1 then
    Exit;

  RelationName := TIdentifier.FromDatabase(AObjectName);
  Result := FContext.FetchTable(Format('SELECT FIRST %d * FROM %s',
    [AMaxRows, RelationName.QualifiedQuoted]));
end;

{------------------------------------------------------------------------------
  TMetaDatabase.GenerateScript
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The primary key columns come from the constraints query, whose COLUMNS
    value is already a comma-separated list built by LIST() in the server. It
    is split back apart here rather than run as a second query.
------------------------------------------------------------------------------}
function TMetaDatabase.GenerateScript(AKind: TScriptKind;
  ANodeType: TMetaNodeType; const AObjectName: string): string;
var
  Detail: TDataTable;
  Columns, Keys: TStringList;
  Row: Integer;
  Relation: TIdentifier;
begin
  Result := '';
  if (FContext = nil) or not FContext.IsConnected then
    Exit;

  Relation := TIdentifier.FromDatabase(AObjectName);

  if AKind = skExecute then
  begin
    if not (ANodeType in [mntProcedure, mntFunctionSQL, mntUDF]) then
      Exit;
    Columns := TStringList.Create;
    try
      Detail := FetchDetail(odParameters, ANodeType, AObjectName);
      for Row := 0 to Detail.RowCount - 1 do
      begin
        if SameText(Trim(Detail.Value(Row, 'DIRECTION')), 'IN') then
          Columns.Add(Trim(Detail.Value(Row, 'PARAM_NAME')));
      end;
      Result := GenerateExecuteScript(Relation, Columns);
    finally
      Columns.Free;
    end;
    Exit;
  end;

  if not IsBrowsableType(ANodeType) then
    Exit;

  Columns := TStringList.Create;
  Keys := TStringList.Create;
  try
    Detail := FetchDetail(odColumns, ANodeType, AObjectName);
    for Row := 0 to Detail.RowCount - 1 do
      Columns.Add(Trim(Detail.Value(Row, 'COLUMN_NAME')));

    if Columns.Count = 0 then
      Exit;

    Detail := FetchDetail(odConstraints, ANodeType, AObjectName);
    for Row := 0 to Detail.RowCount - 1 do
    begin
      if SameText(Trim(Detail.Value(Row, 'CONSTRAINT_TYPE')), 'PRIMARY KEY') then
      begin
        Keys.CommaText := Trim(Detail.Value(Row, 'COLUMNS'));
        Break;
      end;
    end;

    Result := GenerateRelationScript(AKind, Relation, Columns, Keys);
  finally
    Columns.Free;
    Keys.Free;
  end;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.IsSelectableRoutine
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Defaults to False - executable - when the answer cannot be read. Calling an
    executable procedure with EXECUTE PROCEDURE is the safer wrong guess: it
    fails cleanly, where SELECT on an executable procedure fails with a message
    about the FROM clause that sends people looking in the wrong place.
------------------------------------------------------------------------------}
function TMetaDatabase.IsSelectableRoutine(const AObjectName: string): Boolean;
begin
  Result := False;
  if (FContext = nil) or not FContext.IsConnected then
    Exit;
  Result := FContext.FetchScalar(
    FSqlProvider.RoutineTypeSQL(AObjectName), '2') = '1';
end;

{------------------------------------------------------------------------------
  TMetaDatabase.CreateDataEditor
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    A VIEW is opened read-only. Firebird can update some views - a simple one
    over a single table - but deciding which from metadata alone means parsing
    the view body, and being wrong means either refusing something that works
    or generating DML that fails at post time. Read-only with a stated reason
    is the honest position until the view parser exists.
------------------------------------------------------------------------------}
function TMetaDatabase.CreateDataEditor(ANodeType: TMetaNodeType;
  const AObjectName: string; ARowLimit: Integer): TDataEditor;
var
  Detail: TDataTable;
  AllColumns, Updatable, Keys: TStringList;
  Row: Integer;
  AllowEditing: Boolean;
  Refusal, ColumnName: string;
begin
  Result := nil;
  if (FContext = nil) or not FContext.IsConnected then
    Exit;
  if not IsBrowsableType(ANodeType) then
    Exit;

  AllowEditing := ANodeType in [mntTable, mntGTT];
  if ANodeType = mntView then
    Refusal := 'views are opened read only in this build'
  else if ANodeType = mntSysTable then
    Refusal := 'system tables are read only'
  else
    Refusal := '';

  AllColumns := TStringList.Create;
  Updatable := TStringList.Create;
  Keys := TStringList.Create;
  try
    Detail := FetchDetail(odColumns, ANodeType, AObjectName);
    for Row := 0 to Detail.RowCount - 1 do
    begin
      ColumnName := Trim(Detail.Value(Row, 'COLUMN_NAME'));
      if ColumnName = '' then
        Continue;
      AllColumns.Add(ColumnName);
      if Trim(Detail.Value(Row, 'COMPUTED_SOURCE')) = '' then
        Updatable.Add(ColumnName);
    end;

    if AllColumns.Count = 0 then
      Exit;

    Detail := FetchDetail(odConstraints, ANodeType, AObjectName);
    for Row := 0 to Detail.RowCount - 1 do
    begin
      if SameText(Trim(Detail.Value(Row, 'CONSTRAINT_TYPE')), 'PRIMARY KEY') then
      begin
        Keys.CommaText := Trim(Detail.Value(Row, 'COLUMNS'));
        Break;
      end;
    end;

    Result := TDataEditor.Create(FContext.Attachment,
      TIdentifier.FromDatabase(AObjectName),
      AllColumns, Updatable, Keys, AllowEditing, Refusal, ARowLimit);
  finally
    AllColumns.Free;
    Updatable.Free;
    Keys.Free;
  end;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.CreateSqlSession
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The session gets the SAME attachment but its OWN transaction, which is what
    lets a user hold an uncommitted change in an editor without the object tree
    - which reads on the context's own read-only transaction - noticing or
    caring.
------------------------------------------------------------------------------}
function TMetaDatabase.CreateSqlSession: TSqlSession;
begin
  if (FContext = nil) or not FContext.IsConnected then
    Exit(nil);
  Result := TSqlSession.Create(FContext.Attachment);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.CreateSecurityService
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TMetaDatabase.CreateSecurityService: TSecurityService;
begin
  if (FContext = nil) or not FContext.IsConnected then
    Exit(nil);
  Result := TSecurityService.CreateForDatabase(FContext);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.CreateAttachmentService
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TMetaDatabase.CreateAttachmentService: TAttachmentService;
begin
  if (FContext = nil) or not FContext.IsConnected then
    Exit(nil);
  Result := TAttachmentService.Create(FContext);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.EffectiveClientLibrary
  ----------------------------------------------------------------------------
  Returns the fbclient library this database must be opened with.

  Returns:
    The owning server registration's library for a server-backed database, the
    profile's own for an embedded one, or an empty string meaning the system
    default.

  Notes:
    The library is a property of the server because it is loaded once for the
    connection to that server: two databases on one server cannot use different
    clients. An embedded database has no server, so it carries its own.
------------------------------------------------------------------------------}
function TMetaDatabase.EffectiveClientLibrary: string;
begin
  if FProfile.Mode = cmEmbedded then
    Exit(FProfile.ClientLibrary);

  if FServerRegistration <> nil then
    Exit(FServerRegistration.ClientLibrary);

  // No server registration: fall back to the profile's own library rather
  // than to '', which hands the choice to whichever fbclient the loader
  // reaches first - the accident SPECIFICATION.md §5.6.1 exists to prevent.
  // A profile imported from FlameRobin carries one, and the tree always has
  // a registration, so this is the path taken by tests and by anything that
  // drives the model directly.
  Result := FProfile.ClientLibrary;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.DisplayName
  ----------------------------------------------------------------------------
  Returns the text shown in the tree.

  Returns:
    The registration's caption. The connected/disconnected distinction is
    carried by the node's icon rather than by decorating the text, which is
    what IBConsole did and what keeps the tree readable.
------------------------------------------------------------------------------}
function TMetaDatabase.DisplayName: string;
begin
  Result := FProfile.TreeCaption;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.AddCollection
  ----------------------------------------------------------------------------
  Creates one folder node, unless the server does not support it.

  Parameters:
    ACollectionType - The folder's node type.
    AItemType       - The type of item it holds.
    ASql            - The query from the SQL provider; an empty string means
                      the feature does not exist on this server and the folder
                      is not created at all.
------------------------------------------------------------------------------}
procedure TMetaDatabase.AddCollection(ACollectionType,
  AItemType: TMetaNodeType; const ASql: string);
var
  Collection: TMetaCollection;
begin
  if Trim(ASql) = '' then
    Exit;

  Collection := TMetaCollection.CreateCollection(Self, ACollectionType,
    AItemType, ASql);
  Collection.OnLoadItems := @LoadCollectionItems;
  AddChild(Collection);
end;

{------------------------------------------------------------------------------
  TMetaDatabase.LoadChildren
  ----------------------------------------------------------------------------
  Builds the folder nodes for the connected server.

  Notes:
    A disconnected database has no children at all, so its node shows no
    expander and the user is not invited to open something that is not there.

    The order below is the order the folders appear in, and follows IBConsole's
    Domains-first arrangement rather than alphabetical order: it puts the
    things a developer opens most near the top.

    Folders for features the server lacks are never created, because the SQL
    provider returns an empty query for them - see SPECIFICATION.md 5.3.
------------------------------------------------------------------------------}
procedure TMetaDatabase.LoadChildren;
begin
  if not FConnected or (FSqlProvider = nil) then
    Exit;

  if SupportsFeature(FServerVersion, dbfSchemas) then
    AddCollection(mntSchemas, mntSchema, FSqlProvider.SchemasSQL);

  AddCollection(mntDomains, mntDomain, FSqlProvider.DomainsSQL);
  AddCollection(mntTables, mntTable, FSqlProvider.TablesSQL);
  AddCollection(mntGTTs, mntGTT, FSqlProvider.GlobalTemporaryTablesSQL);
  AddCollection(mntViews, mntView, FSqlProvider.ViewsSQL);
  AddCollection(mntProcedures, mntProcedure, FSqlProvider.ProceduresSQL);
  AddCollection(mntFunctionSQLs, mntFunctionSQL, FSqlProvider.FunctionsSQL);
  AddCollection(mntUDFs, mntUDF, FSqlProvider.ExternalFunctionsSQL);
  AddCollection(mntPackages, mntPackage, FSqlProvider.PackagesSQL);
  AddCollection(mntTriggersDML, mntTriggerDML,
    FSqlProvider.TriggersSQL(tkDML));
  AddCollection(mntTriggersDB, mntTriggerDB,
    FSqlProvider.TriggersSQL(tkDatabase));
  AddCollection(mntTriggersDDL, mntTriggerDDL,
    FSqlProvider.TriggersSQL(tkDDL));
  AddCollection(mntGenerators, mntGenerator, FSqlProvider.GeneratorsSQL);
  AddCollection(mntExceptions, mntException, FSqlProvider.ExceptionsSQL);
  AddCollection(mntIndices, mntIndex, FSqlProvider.IndicesSQL);
  AddCollection(mntRoles, mntRole, FSqlProvider.RolesSQL);
  AddCollection(mntPublications, mntPublication,
    FSqlProvider.PublicationsSQL);
  AddCollection(mntCharacterSets, mntCharacterSet,
    FSqlProvider.CharacterSetsSQL);
  AddCollection(mntCollations, mntCollation, FSqlProvider.CollationsSQL);
  AddCollection(mntBlobFilters, mntBlobFilter, FSqlProvider.BlobFiltersSQL);

  if FShowSystemObjects then
  begin
    AddCollection(mntSysTables, mntSysTable, FSqlProvider.SystemTablesSQL);
    AddCollection(mntSysDomains, mntSysDomain, FSqlProvider.SystemDomainsSQL);
    AddCollection(mntSysIndices, mntSysIndex, FSqlProvider.SystemIndicesSQL);
  end;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.FetchDomainDefinition
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    FetchTableFresh, not FetchTable. The standing metadata transaction took
    its snapshot before this dialog opened, so on it a domain altered a
    moment ago still reads the way it used to - and the value read here is
    about to be written back, which would quietly undo the other change.
------------------------------------------------------------------------------}
function TMetaDatabase.FetchDomainDefinition(const AName: string;
  out ADomain: TDdlDomain): Boolean;
var
  Table: TDataTable;
begin
  ADomain := Default(TDdlDomain);
  Result := False;
  if (FContext = nil) or not FContext.IsConnected then
  begin
    Exit;
  end;

  Table := FContext.FetchTableFresh(
    FSqlProvider.DomainDefinitionSQL(AName));
  if Table.RowCount = 0 then
  begin
    Exit;
  end;

  ADomain.Name := TIdentifier.FromDatabase(AName);
  ADomain.DataType := Trim(Table.Value(0, 'DATA_TYPE'));
  ADomain.NotNull := SameText(Trim(Table.Value(0, 'NOT_NULL')), 'YES');
  ADomain.DefaultValue :=
    StripDefaultKeyword(Table.Value(0, 'DEFAULT_SOURCE'));
  ADomain.CheckCondition :=
    StripCheckKeyword(Table.Value(0, 'CHECK_SOURCE'));
  ADomain.Collation := TrimRight(Table.Value(0, 'COLLATION'));
  Result := True;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.FetchExceptionMessage
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TMetaDatabase.FetchExceptionMessage(const AName: string;
  out AMessage: string): Boolean;
var
  Table: TDataTable;
begin
  AMessage := '';
  Result := False;
  if (FContext = nil) or not FContext.IsConnected then
  begin
    Exit;
  end;

  Table := FContext.FetchTableFresh(
    FSqlProvider.ExceptionDefinitionSQL(AName));
  if Table.RowCount = 0 then
  begin
    Exit;
  end;

  AMessage := TrimRight(Table.Value(0, 'MESSAGE_TEXT'));
  Result := True;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.FetchIndexActive
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TMetaDatabase.FetchIndexActive(const AName: string;
  out AActive: Boolean): Boolean;
var
  Table: TDataTable;
begin
  AActive := True;
  Result := False;
  if (FContext = nil) or not FContext.IsConnected then
  begin
    Exit;
  end;

  Table := FContext.FetchTableFresh(FSqlProvider.IndexStateSQL(AName));
  if Table.RowCount = 0 then
  begin
    Exit;
  end;

  AActive := SameText(Trim(Table.Value(0, 'IS_ACTIVE')), 'YES');
  Result := True;
end;

{------------------------------------------------------------------------------
  TMetaDatabase.FetchSequenceValue
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    An absent sequence makes GEN_ID a broken statement rather than an empty
    result, so the failure arrives as an exception. It is caught and
    reported as False, because the caller asked a question and 'there is no
    such sequence' is an answer to it.
------------------------------------------------------------------------------}
function TMetaDatabase.FetchSequenceValue(const AName: string;
  out AValue: Int64): Boolean;
var
  Table: TDataTable;
begin
  AValue := 0;
  Result := False;
  if (FContext = nil) or not FContext.IsConnected then
  begin
    Exit;
  end;

  try
    Table := FContext.FetchTableFresh(
      FSqlProvider.SequenceValueSQL(AName));
  except
    on E: Exception do
    begin
      { Reported as 'not found'; the caller offers a starting value of zero
        rather than refusing to open. }
      Exit;
    end;
  end;

  if Table.RowCount = 0 then
  begin
    Exit;
  end;

  AValue := StrToInt64Def(Trim(Table.Value(0, 'CURRENT_VALUE')), 0);
  Result := True;
end;

end.
