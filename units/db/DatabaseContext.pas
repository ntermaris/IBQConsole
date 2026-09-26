{==============================================================================
  Unit:        DatabaseContext
  Purpose:     One attachment to one database: the connection, its two
               transactions, the detected version and the metadata SQL provider
               chosen for it.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, IB, IBDatabase, IBSQL, IBExtract, IbqError, AppLog,
               ConnectionProfile, ServerVersion, MetadataSqlProvider,
               MetadataSqlProviderFactory, DatabaseRow

  This is the ONLY place, together with units/services, where IBX appears.
  Everything above it works with plain records and strings.

  THE TWO TRANSACTIONS
  Inherited from IBConsole, which had this right (TRA_DDL and TRA_DFLT in
  zluGlobal.pas):

    MetaTransaction  read committed, rec_version, READ ONLY, nowait
                     every metadata query. Never blocks and is never blocked,
                     so browsing the tree cannot be held up by somebody else's
                     open transaction, and cannot hold up theirs.

    DdlTransaction   snapshot, write, wait
                     DDL only, committed immediately after each statement.

  A SQL editor window gets a third transaction of its own, which it controls
  explicitly. That is what stops a user's uncommitted work from freezing the
  object tree.
==============================================================================}
unit DatabaseContext;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IB, IBDatabase, IBSQL, IBExtract,
  IbqError, AppLog, ConnectionProfile, ServerVersion, MetadataSqlProvider,
  MetadataSqlProviderFactory, DatabaseRow, FbClientLocator;

type
  { TDatabaseContext
    Owns one attachment. Created disconnected; Connect attaches, reads the
    version and builds the SQL provider. }
  TDatabaseContext = class(TObject)
  private
    FProfile: TConnectionProfile;
    FClientLibrary: string;
    FDatabase: TIBDatabase;
    FMetaTransaction: TIBTransaction;
    FDdlTransaction: TIBTransaction;
    FServerVersion: TServerVersion;
    FSqlProvider: TMetadataSqlProvider;
    FSqlDialect: Integer;
    procedure ConfigureAttachment(const APassword: string);
    procedure ConfigureTransactions;
    procedure ReadDatabaseInfo;
    procedure ReadEngineVersion;
    procedure CheckDialect;
    function TranslateError(E: Exception; const ASql: string): EIbqDatabaseError;
  public
    constructor Create(AProfile: TConnectionProfile;
      const AClientLibrary: string);
    destructor Destroy; override;

    { Attaches to the database, detects the version and prepares the metadata
      SQL.

      Parameters:
        APassword - The password to attach with. Never stored here.

      Raises:
        EIbqDatabaseError - The attachment failed; carries the full Firebird
                            status vector.
        EIbqUnsupported   - The server is older than Firebird 3.0, or the
                            database is SQL dialect 1 (see CheckDialect). }
    procedure Connect(const APassword: string);
    { Rolls back both transactions and detaches. Safe when not connected. }
    procedure Disconnect;
    { True while attached. }
    function IsConnected: Boolean;

    { Runs a metadata collection query and returns its rows.

      Parameters:
        ASql - A query obeying the three-column contract documented in
               MetadataSqlProvider.

      Returns:
        The rows, in the order the query produced them.

      Raises:
        EIbqDatabaseError - The query failed; carries the status vector and the
                            statement text. }
    function FetchCollection(const ASql: string): TMetaRowArray;

    { Runs any query and returns the whole result set as text.

      Parameters:
        ASql - Any SELECT. An empty string yields an empty table rather than
               an error, so a property page can ask for something the server
               version does not provide.

      Returns:
        Column names and rows. Nulls come back as empty strings.

      Raises:
        EIbqDatabaseError - The query failed. }
    function FetchTable(const ASql: string): TDataTable;

    { Returns the DDL that would recreate one object.

      Parameters:
        AObjectKind - Which IBX extract category the object belongs to.
        AObjectName - Bare object name, or an empty string for the whole
                      database.

      Returns:
        The statements, one per line.

      Raises:
        EIbqDatabaseError - The extraction failed. }
    function ExtractDdl(AObjectKind: TExtractObjectTypes;
      const AObjectName: string): string;

    { Runs a query expected to yield one row of one column.

      Parameters:
        ASql     - The query.
        ADefault - Returned when the query yields no row or a null.

      Returns:
        The value as text. }
    function FetchScalar(const ASql: string;
      const ADefault: string = ''): string;

    { Runs one statement that changes the database and commits it.

      Parameters:
        ASql - A single statement, without a terminator.

      Raises:
        EIbqDatabaseError - The statement failed. Nothing is left uncommitted:
                            the transaction is rolled back first.

      Notes:
        This runs on the DDL transaction - snapshot, write, wait - and commits
        immediately, which is what a statement like CREATE USER wants: it is
        not part of anything the user is composing, and leaving it open would
        hold a lock on the security database.

        It is deliberately NOT a general statement runner. Anything the user
        typed goes through TSqlSession, on that editor's own transaction, under
        the user's own Commit and Rollback. }
    procedure ExecuteDdl(const ASql: string);

    { Runs a query on a transaction of its own, started and committed for this
      call alone.

      Parameters:
        ASql - The query.

      Returns:
        The rows.

      Raises:
        EIbqDatabaseError - The query failed.

      Notes:
        For the virtual tables - SEC$USERS, and the MON$ monitoring tables -
        whose contents Firebird materialises ONCE per transaction and then
        holds still. The standing metadata transaction is long-lived by design,
        so on it a user created a moment ago is invisible and an attachment
        that has just disconnected is still listed. Read committed does not
        help: the snapshot of these tables is taken when the transaction first
        touches them, not per statement.

        Ordinary metadata goes through FetchTable, which shares the standing
        transaction and is cheaper. }
    function FetchTableFresh(const ASql: string): TDataTable;

    { The registration this attachment was made from; not owned. }
    property Profile: TConnectionProfile read FProfile;
    { The client library in use, or empty for the system default. }
    property ClientLibrary: string read FClientLibrary;
    { The detected engine version; unknown while disconnected. }
    property Version: TServerVersion read FServerVersion;
    { The metadata SQL for this server; nil while disconnected. }
    property SqlProvider: TMetadataSqlProvider read FSqlProvider;
    { The database's SQL dialect, 0 while disconnected. }
    property SqlDialect: Integer read FSqlDialect;
    { The attachment itself. Exposed so a SqlSession can open its own
      transaction on the same connection; nothing above units/db may touch
      it, and nothing else in units/db should need to. }
    property Attachment: TIBDatabase read FDatabase;
    { The read-only metadata transaction. }
    property MetaTransaction: TIBTransaction read FMetaTransaction;
    { The read-write DDL transaction. }
    property DdlTransaction: TIBTransaction read FDdlTransaction;
  end;

implementation

const
  { The only dialect IBQConsole supports. Dialect 1 changes identifier rules,
    NUMERIC semantics, date handling and the meaning of double quotes; see
    SPECIFICATION.md 5.7 for why it is refused rather than half-supported. }
  RequiredSqlDialect = 3;

{------------------------------------------------------------------------------
  TDatabaseContext.Create
  ----------------------------------------------------------------------------
  Creates a disconnected context.

  Parameters:
    AProfile        - The registration to attach with; not owned here, and must
                      outlive this object.
    AClientLibrary  - Full path of the fbclient to load, or an empty string to
                      use the system default. Comes from the SERVER
                      registration for a server-backed database - see
                      TMetaDatabase.EffectiveClientLibrary.
------------------------------------------------------------------------------}
constructor TDatabaseContext.Create(AProfile: TConnectionProfile;
  const AClientLibrary: string);
begin
  inherited Create;
  FProfile := AProfile;
  FClientLibrary := AClientLibrary;
  FServerVersion := UnknownServerVersion;
  FSqlDialect := 0;

  FDatabase := TIBDatabase.Create(nil);
  FDatabase.LoginPrompt := False;

  FMetaTransaction := TIBTransaction.Create(nil);
  FDdlTransaction := TIBTransaction.Create(nil);
  FMetaTransaction.DefaultDatabase := FDatabase;
  FDdlTransaction.DefaultDatabase := FDatabase;
  FDatabase.DefaultTransaction := FMetaTransaction;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.Destroy
  ----------------------------------------------------------------------------
  Detaches and releases the IBX components.
------------------------------------------------------------------------------}
destructor TDatabaseContext.Destroy;
begin
  try
    Disconnect;
  except
    // a failure while shutting down must not stop the object being freed
  end;

  FreeAndNil(FSqlProvider);
  FreeAndNil(FDdlTransaction);
  FreeAndNil(FMetaTransaction);
  FreeAndNil(FDatabase);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.ConfigureAttachment
  ----------------------------------------------------------------------------
  Fills in the connection string, the client library and the DPB.

  Parameters:
    APassword - The password to attach with.

  Notes:
    FirebirdLibraryPathName is set per database, which IBX 2.7 supports by
    loading a separate IFirebirdLibrary for each. That is what allows one
    session to hold connections to a Firebird 3, a 4 and a 5 server at the same
    time, each through its own client.
------------------------------------------------------------------------------}
procedure TDatabaseContext.ConfigureAttachment(const APassword: string);
begin
  if FClientLibrary <> '' then
  begin
    { Pin before use: see FbClientLocator.PinClientLibrary for the crash this
      avoids when an older client is loaded after a newer one. }
    PinClientLibrary(FClientLibrary);
    FDatabase.FirebirdLibraryPathName := FClientLibrary;
  end;

  FDatabase.DatabaseName := FProfile.ConnectionString;

  FDatabase.Params.Clear;
  if FProfile.UserName <> '' then
    FDatabase.Params.Add('user_name=' + FProfile.UserName);
  if APassword <> '' then
    FDatabase.Params.Add('password=' + APassword);
  if FProfile.CharacterSet <> '' then
    FDatabase.Params.Add('lc_ctype=' + FProfile.CharacterSet);
  if FProfile.Role <> '' then
    FDatabase.Params.Add('sql_role_name=' + FProfile.Role);
  if FProfile.PageBuffers > 0 then
    FDatabase.Params.Add('num_buffers=' + IntToStr(FProfile.PageBuffers));
end;

{------------------------------------------------------------------------------
  TDatabaseContext.ConfigureTransactions
  ----------------------------------------------------------------------------
  Sets the parameters of the two standing transactions.

  Notes:
    The metadata transaction is read committed AND read only AND nowait. All
    three matter: read committed so it sees other people's committed DDL
    without restarting, read only so it never holds back garbage collection,
    and nowait so a lock conflict fails immediately instead of freezing the
    tree.
------------------------------------------------------------------------------}
procedure TDatabaseContext.ConfigureTransactions;
begin
  FMetaTransaction.Params.Clear;
  FMetaTransaction.Params.Add('read_committed');
  FMetaTransaction.Params.Add('rec_version');
  FMetaTransaction.Params.Add('nowait');
  FMetaTransaction.Params.Add('read');

  FDdlTransaction.Params.Clear;
  FDdlTransaction.Params.Add('concurrency');
  FDdlTransaction.Params.Add('wait');
  FDdlTransaction.Params.Add('write');
end;

{------------------------------------------------------------------------------
  TDatabaseContext.Connect
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The order is deliberate: attach, start the metadata transaction, read the
    dialect, refuse dialect 1 BEFORE anything else runs. A dialect 1 database
    would give confusing failures from queries written for dialect 3, so the
    refusal has to come first.
------------------------------------------------------------------------------}
procedure TDatabaseContext.Connect(const APassword: string);
begin
  if IsConnected then
    Exit;

  ConfigureAttachment(APassword);
  ConfigureTransactions;

  try
    FDatabase.Connected := True;
  except
    on E: Exception do
      raise TranslateError(E, '');
  end;

  try
    FMetaTransaction.StartTransaction;

    ReadDatabaseInfo;
    CheckDialect;
    ReadEngineVersion;

    FreeAndNil(FSqlProvider);
    FSqlProvider := CreateMetadataSqlProvider(FServerVersion);

    Log.InfoFmt('Connected to %s as %s (%s, dialect %d)',
      [FProfile.ConnectionString, FProfile.UserName,
       FServerVersion.DisplayText, FSqlDialect]);
  except
    on E: Exception do
    begin
      Disconnect;
      raise;
    end;
  end;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.Disconnect
  ----------------------------------------------------------------------------
  Rolls back both transactions and detaches.

  Notes:
    Rolls back rather than commits. Nothing this class runs on its own
    transactions needs committing - metadata reads are read only and DDL is
    committed statement by statement - so anything still open at disconnect is
    unfinished work, and discarding it is the safe reading.
------------------------------------------------------------------------------}
procedure TDatabaseContext.Disconnect;
begin
  if (FDdlTransaction <> nil) and FDdlTransaction.InTransaction then
    FDdlTransaction.Rollback;
  if (FMetaTransaction <> nil) and FMetaTransaction.InTransaction then
    FMetaTransaction.Rollback;

  if (FDatabase <> nil) and FDatabase.Connected then
  begin
    FDatabase.Connected := False;
    Log.InfoFmt('Disconnected from %s', [FProfile.ConnectionString]);
  end;

  FreeAndNil(FSqlProvider);
  FServerVersion := UnknownServerVersion;
  FSqlDialect := 0;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.IsConnected
  ----------------------------------------------------------------------------
  Returns True while attached.
------------------------------------------------------------------------------}
function TDatabaseContext.IsConnected: Boolean;
begin
  Result := (FDatabase <> nil) and FDatabase.Connected;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.ReadDatabaseInfo
  ----------------------------------------------------------------------------
  Reads dialect and ODS version from MON$DATABASE.

  Notes:
    Uses a provider built for the minimum supported version, because the real
    provider cannot be chosen until the engine version is known, and the
    MON$DATABASE query is identical on every supported version anyway.
------------------------------------------------------------------------------}
procedure TDatabaseContext.ReadDatabaseInfo;
var
  Query: TIBSQL;
  Sql: string;
  Bootstrap: TMetadataSqlProvider;
  BootVersion: TServerVersion;
begin
  BootVersion := ParseEngineVersion('3.0.0');
  Bootstrap := CreateMetadataSqlProvider(BootVersion);
  try
    Sql := Bootstrap.DatabaseInfoSQL;
  finally
    Bootstrap.Free;
  end;

  Query := TIBSQL.Create(nil);
  try
    Query.Database := FDatabase;
    Query.Transaction := FMetaTransaction;
    Query.SQL.Text := Sql;
    try
      Query.ExecQuery;
      if not Query.EOF then
      begin
        FSqlDialect := Query.FieldByName('SQL_DIALECT').AsInteger;
        FServerVersion.OdsMajor := Query.FieldByName('ODS_MAJOR').AsInteger;
        FServerVersion.OdsMinor := Query.FieldByName('ODS_MINOR').AsInteger;
      end;
    except
      on E: Exception do
        raise TranslateError(E, Sql);
    end;
  finally
    Query.Free;
  end;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.CheckDialect
  ----------------------------------------------------------------------------
  Refuses a database that is not SQL dialect 3.

  Raises:
    EIbqUnsupported - The database is dialect 1 or 2. The message names the
                      gfix migration rather than only stating the refusal,
                      because a user meeting this needs the next step, not a
                      verdict.
------------------------------------------------------------------------------}
procedure TDatabaseContext.CheckDialect;
begin
  if FSqlDialect = RequiredSqlDialect then
    Exit;

  if FSqlDialect = 0 then
    Exit;      // could not be read; do not refuse on a missing fact

  raise EIbqUnsupported.CreateFmt(
    'The database %s uses SQL dialect %d. IBQConsole requires dialect %d.' +
    LineEnding + LineEnding +
    'A dialect 1 database can be migrated with' + LineEnding +
    '    gfix -sql_dialect 3 <database>' + LineEnding +
    'after checking that no "double quoted strings" and no dialect 1 DATE ' +
    'columns are in use.',
    [FProfile.ConnectionString, FSqlDialect, RequiredSqlDialect]);
end;

{------------------------------------------------------------------------------
  TDatabaseContext.ReadEngineVersion
  ----------------------------------------------------------------------------
  Reads the engine version string and parses it.

  Notes:
    Keeps the ODS numbers already read by ReadDatabaseInfo, which the parse
    would otherwise clear.
------------------------------------------------------------------------------}
procedure TDatabaseContext.ReadEngineVersion;
var
  Bootstrap: TMetadataSqlProvider;
  Sql, VersionText: string;
  OdsMajor, OdsMinor: Integer;
begin
  Bootstrap := CreateMetadataSqlProvider(ParseEngineVersion('3.0.0'));
  try
    Sql := Bootstrap.EngineVersionSQL;
  finally
    Bootstrap.Free;
  end;

  OdsMajor := FServerVersion.OdsMajor;
  OdsMinor := FServerVersion.OdsMinor;

  VersionText := FetchScalar(Sql, '');
  FServerVersion := ParseEngineVersion(VersionText, OdsMajor, OdsMinor);
end;

{------------------------------------------------------------------------------
  TDatabaseContext.FetchScalar
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TDatabaseContext.FetchScalar(const ASql: string;
  const ADefault: string): string;
var
  Query: TIBSQL;
begin
  Result := ADefault;

  Query := TIBSQL.Create(nil);
  try
    Query.Database := FDatabase;
    Query.Transaction := FMetaTransaction;
    Query.SQL.Text := ASql;
    try
      Query.ExecQuery;
      if (not Query.EOF) and (Query.Current.Count > 0) and
         (not Query.Fields[0].IsNull) then
        Result := Query.Fields[0].AsString;
    except
      on E: Exception do
        raise TranslateError(E, ASql);
    end;
  finally
    Query.Free;
  end;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.ExecuteDdl
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The rollback in the failure path is not decoration. The DDL transaction is
    long-lived - it belongs to the context, not to the statement - so a failed
    statement that left it open would make the NEXT one fail too, with an error
    about the previous one that nobody could interpret.
------------------------------------------------------------------------------}
procedure TDatabaseContext.ExecuteDdl(const ASql: string);
var
  Query: TIBSQL;
begin
  Query := TIBSQL.Create(nil);
  try
    Query.Database := FDatabase;
    Query.Transaction := FDdlTransaction;
    Query.SQL.Text := ASql;
    try
      if not FDdlTransaction.InTransaction then
        FDdlTransaction.StartTransaction;
      Query.ExecQuery;
      FDdlTransaction.Commit;
      Log.Statement(ASql);
    except
      on E: Exception do
      begin
        if FDdlTransaction.InTransaction then
          FDdlTransaction.Rollback;
        raise TranslateError(E, ASql);
      end;
    end;
  finally
    Query.Free;
  end;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.FetchTableFresh
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The transaction is its own object rather than the standing DDL one: that
    one is a write transaction and would take a lock this read has no business
    taking, and it may be in use.
------------------------------------------------------------------------------}
function TDatabaseContext.FetchTableFresh(const ASql: string): TDataTable;
var
  Transaction: TIBTransaction;
  Query: TIBSQL;
  ColumnCount, RowIndex, I: Integer;
begin
  Result := Default(TDataTable);
  if Trim(ASql) = '' then
    Exit;

  Transaction := TIBTransaction.Create(nil);
  Query := TIBSQL.Create(nil);
  try
    Transaction.DefaultDatabase := FDatabase;
    Transaction.Params.Clear;
    Transaction.Params.Add('read_committed');
    Transaction.Params.Add('rec_version');
    Transaction.Params.Add('nowait');
    Transaction.Params.Add('read');

    Query.Database := FDatabase;
    Query.Transaction := Transaction;
    Query.SQL.Text := ASql;

    try
      Transaction.StartTransaction;
      Query.ExecQuery;

      ColumnCount := Query.MetaData.Count;
      SetLength(Result.ColumnNames, ColumnCount);
      for I := 0 to ColumnCount - 1 do
        Result.ColumnNames[I] := Trim(Query.MetaData[I].GetAliasName);

      RowIndex := 0;
      while not Query.EOF do
      begin
        if RowIndex = Length(Result.Rows) then
          SetLength(Result.Rows, Length(Result.Rows) * 2 + 32);
        SetLength(Result.Rows[RowIndex], ColumnCount);
        for I := 0 to ColumnCount - 1 do
        begin
          if Query.Fields[I].IsNull then
            Result.Rows[RowIndex][I] := ''
          else
            Result.Rows[RowIndex][I] := Query.Fields[I].AsString;
        end;
        Inc(RowIndex);
        Query.Next;
      end;
      SetLength(Result.Rows, RowIndex);

      Query.Close;
      Transaction.Commit;
    except
      on E: Exception do
      begin
        if Transaction.InTransaction then
          Transaction.Rollback;
        raise TranslateError(E, ASql);
      end;
    end;
  finally
    Query.Free;
    Transaction.Free;
  end;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.FetchCollection
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Reads by column position, not by name, because that is exactly what the
    column contract promises: schema, name, id. A provider that changed the
    order would break here loudly rather than quietly returning nulls.
------------------------------------------------------------------------------}
function TDatabaseContext.FetchCollection(const ASql: string): TMetaRowArray;
var
  Query: TIBSQL;
  Count: Integer;
begin
  Result := nil;
  Count := 0;

  Query := TIBSQL.Create(nil);
  try
    Query.Database := FDatabase;
    Query.Transaction := FMetaTransaction;
    Query.SQL.Text := ASql;
    try
      Query.ExecQuery;
      while not Query.EOF do
      begin
        if Count = Length(Result) then
          SetLength(Result, Length(Result) * 2 + 64);

        if Query.Fields[0].IsNull then
          Result[Count].SchemaName := ''
        else
          Result[Count].SchemaName := Query.Fields[0].AsString;

        Result[Count].ObjectName := Query.Fields[1].AsString;

        if Query.Fields[2].IsNull then
          Result[Count].ObjectId := -1
        else
          Result[Count].ObjectId := Query.Fields[2].AsInteger;

        Inc(Count);
        Query.Next;
      end;
    except
      on E: Exception do
        raise TranslateError(E, ASql);
    end;
  finally
    Query.Free;
  end;

  SetLength(Result, Count);
end;

{------------------------------------------------------------------------------
  TDatabaseContext.FetchTable
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Column names come from the statement's own metadata, so a property page
    shows whatever the query chose to call things and no mapping table is
    needed between the two.
------------------------------------------------------------------------------}
function TDatabaseContext.FetchTable(const ASql: string): TDataTable;
var
  Query: TIBSQL;
  ColumnCount, RowIndex, I: Integer;
begin
  Result := Default(TDataTable);
  if Trim(ASql) = '' then
    Exit;

  Query := TIBSQL.Create(nil);
  try
    Query.Database := FDatabase;
    Query.Transaction := FMetaTransaction;
    Query.SQL.Text := ASql;
    try
      Query.ExecQuery;

      { Column names come from MetaData, not from Current. Current is the
        CURRENT ROW, and touching it on an empty result set raises "End of
        file" - which would turn every query that legitimately returns nothing
        into an error. MetaData describes the statement and is valid whether or
        not any row came back. }
      ColumnCount := Query.MetaData.Count;
      SetLength(Result.ColumnNames, ColumnCount);
      for I := 0 to ColumnCount - 1 do
        Result.ColumnNames[I] := Trim(Query.MetaData[I].GetAliasName);

      RowIndex := 0;
      while not Query.EOF do
      begin
        if RowIndex = Length(Result.Rows) then
          SetLength(Result.Rows, Length(Result.Rows) * 2 + 32);
        SetLength(Result.Rows[RowIndex], ColumnCount);

        for I := 0 to ColumnCount - 1 do
        begin
          if Query.Fields[I].IsNull then
            Result.Rows[RowIndex][I] := ''
          else
            Result.Rows[RowIndex][I] := Query.Fields[I].AsString;
        end;

        Inc(RowIndex);
        Query.Next;
      end;
      SetLength(Result.Rows, RowIndex);
    except
      on E: Exception do
        raise TranslateError(E, ASql);
    end;
  finally
    Query.Free;
  end;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.ExtractDdl
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Uses IBX's TIBExtract rather than a generator of our own. For M2, where the
    DDL tab only has to SHOW correct statements, borrowing a well-tested
    extractor is better than writing a second one badly. The visitors in
    units/ddl take over when DDL has to be composed rather than reproduced -
    ALTER statements, and "Script as..." - because those need the object model,
    not a text dump.

    Runs on the metadata transaction, so extracting DDL cannot block anyone.
------------------------------------------------------------------------------}
function TDatabaseContext.ExtractDdl(AObjectKind: TExtractObjectTypes;
  const AObjectName: string): string;
var
  Extract: TIBExtract;
begin
  Result := '';
  if not IsConnected then
    Exit;

  Extract := TIBExtract.Create(nil);
  try
    Extract.Database := FDatabase;
    Extract.Transaction := FMetaTransaction;
    Extract.CaseSensitiveObjectNames := True;
    Extract.IncludeMetaDataComments := True;
    try
      Extract.ExtractObject(AObjectKind, AObjectName);
      Result := Extract.Items.Text;
    except
      on E: Exception do
        raise TranslateError(E, 'extract ' + AObjectName);
    end;
  finally
    Extract.Free;
  end;
end;

{------------------------------------------------------------------------------
  TDatabaseContext.TranslateError
  ----------------------------------------------------------------------------
  Turns an IBX exception into an EIbqDatabaseError carrying the whole status
  vector.

  Parameters:
    E    - The exception IBX raised.
    ASql - The statement that failed, or an empty string.

  Returns:
    A new EIbqDatabaseError for the caller to raise.

  Notes:
    Firebird reports an error as a chain of messages, and the first one is
    usually the least informative: "Dynamic SQL Error" tells nobody anything,
    while the third line names the actual token. Keeping every line is the
    whole point of this method, and of EIbqDatabaseError.FullText.
------------------------------------------------------------------------------}
function TDatabaseContext.TranslateError(E: Exception;
  const ASql: string): EIbqDatabaseError;
var
  Lines: TStringList;
  StatusLines: TStringArray;
  SqlCode, GdsCode: Integer;
  I: Integer;
begin
  SqlCode := 0;
  GdsCode := 0;
  StatusLines := nil;

  if E is EIBInterBaseError then
  begin
    SqlCode := EIBInterBaseError(E).SQLCode;
    GdsCode := EIBInterBaseError(E).IBErrorCode;
  end
  else if E is EIBError then
    SqlCode := EIBError(E).SQLCode;

  Lines := TStringList.Create;
  try
    Lines.Text := E.Message;
    SetLength(StatusLines, Lines.Count);
    for I := 0 to Lines.Count - 1 do
      StatusLines[I] := Lines[I];
  finally
    Lines.Free;
  end;

  Result := EIbqDatabaseError.Create(E.Message, SqlCode, GdsCode,
    StatusLines, ASql);

  Log.ErrorWithStatement(Result.FullText, ASql);
end;

end.
