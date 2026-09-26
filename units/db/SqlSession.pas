{==============================================================================
  Unit:        SqlSession
  Purpose:     One SQL editor's connection to a database: its own transaction,
               under the user's explicit control, and the execution of
               statements on it.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, DateUtils, IB, IBDatabase, IBSQL,
               IbqError, AppLog, DatabaseRow, SqlStatementSplitter

  WHY AN EDITOR GETS ITS OWN TRANSACTION
  The database context keeps two standing transactions: a read-only one for
  metadata and a short-lived one for DDL. A SQL editor cannot use either.

  It cannot use the metadata transaction because that one is read only and
  must never be held open - browsing the tree would stop working the moment a
  user left an UPDATE uncommitted. It cannot share the DDL transaction because
  that one is committed after every statement, which would silently commit the
  user's work.

  So each editor window gets a third transaction that it starts, commits and
  rolls back on the user's command, and nothing else touches. This is exactly
  what IBConsole's ISQL window did, and the reason it could leave a lock
  sitting on a table without freezing its own object tree.
==============================================================================}
unit SqlSession;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, DateUtils, IB, IBDatabase, IBSQL,
  IbqError, AppLog, DatabaseRow, SqlStatementSplitter;

type
  { What one executed statement produced. }
  TSqlExecResult = record
    { The statement as sent to the server. }
    Sql: string;
    { Readable statement kind: SELECT, INSERT, DDL and so on. }
    StatementKind: string;
    { True when the statement returned a result set. }
    ReturnsData: Boolean;
    { The rows fetched. Empty for a statement that returns none. }
    Data: TDataTable;
    { True when fetching stopped at the row limit rather than at the end. }
    Truncated: Boolean;
    { Rows the statement affected, or -1 when not applicable. }
    RowsAffected: Int64;
    { Per-operation counts the engine reported. Firebird counts the operations
      it actually performed, which is not the same as the rows the statement
      names: an UPDATE that fires a trigger inserting a log row reports both an
      update and an insert. That is exactly what makes these worth showing. }
    SelectCount: Integer;
    InsertCount: Integer;
    UpdateCount: Integer;
    DeleteCount: Integer;
    { True when the engine supplied the per-operation counts. }
    HasCounts: Boolean;
    { The prepared statement's access plan. }
    Plan: string;
    { How long execution and fetching took. }
    ElapsedMs: Int64;
    { The line to show on the Messages tab. }
    Message: string;
    { True when the statement failed. }
    Failed: Boolean;

    { Returns a one-line summary for the Messages tab. }
    function Summary: string;
    { Returns the multi-line text for the Statistics tab. }
    function Statistics: string;
  end;

  TSqlExecResultArray = array of TSqlExecResult;

  { Raised once per statement while a script runs, so the editor can report
    progress and let the user cancel. Set AContinue to False to stop. }
  TSqlScriptProgress = procedure(AIndex, ACount: Integer;
    const AResult: TSqlExecResult; var AContinue: Boolean) of object;

const
  { How many rows a SELECT fetches before stopping. A SQL editor is not a
    report writer; fetching four million rows into a grid nobody will scroll
    is a way to make the program appear to hang. The editor offers "fetch
    more" instead. }
  DefaultFetchLimit = 1000;

type
  { TSqlSession
    One editor's execution context. Created by TDatabaseContext, which owns the
    attachment; this class owns only its transaction. }
  TSqlSession = class(TObject)
  private
    FDatabase: TIBDatabase;
    FTransaction: TIBTransaction;
    FFetchLimit: Integer;
    FAutoCommitDdl: Boolean;
    function DescribeStatementKind(AType: TIBSQLStatementTypes): string;
    function TranslateError(E: Exception; const ASql: string): EIbqDatabaseError;
  public
    constructor Create(ADatabase: TIBDatabase);
    destructor Destroy; override;

    { Starts the transaction if it is not already running. }
    procedure EnsureTransaction;
    { Commits the user's work. Does nothing when no transaction is open. }
    procedure Commit;
    { Discards the user's work. Does nothing when no transaction is open. }
    procedure Rollback;
    { True while the editor is holding an open transaction. }
    function InTransaction: Boolean;

    { Executes one statement.

      Parameters:
        ASql - A single statement, without a terminator.

      Returns:
        What it produced. A failed statement returns a result with Failed set
        and the error in Message, rather than raising: a script must be able to
        report a failure and carry on if the user asked it to. }
    function Execute(const ASql: string): TSqlExecResult;

    { Executes every statement in a script, in order.

      Parameters:
        AScript     - The script text; SET TERM is honoured.
        AOnProgress - Raised after each statement; may stop the run.
        AStopOnError - True to stop at the first failure.

      Returns:
        One result per statement executed, including the failed one when the
        run stopped early. }
    function ExecuteScript(const AScript: string;
      AOnProgress: TSqlScriptProgress;
      AStopOnError: Boolean): TSqlExecResultArray;

    { How many rows a SELECT fetches. }
    property FetchLimit: Integer read FFetchLimit write FFetchLimit;
    { True to commit automatically after a DDL statement, as isql does. }
    property AutoCommitDdl: Boolean read FAutoCommitDdl write FAutoCommitDdl;
  end;

implementation

{------------------------------------------------------------------------------
  TSqlExecResult.Summary
  ----------------------------------------------------------------------------
  Returns the one-line summary shown on the Messages tab.
------------------------------------------------------------------------------}
function TSqlExecResult.Summary: string;
begin
  if Failed then
    Exit(Message);

  if ReturnsData then
  begin
    Result := Format('%s: %d row(s)', [StatementKind, Data.RowCount]);
    if Truncated then
      Result := Result + ' (more available)';
  end
  else if RowsAffected >= 0 then
    Result := Format('%s: %d row(s) affected', [StatementKind, RowsAffected])
  else
    Result := StatementKind + ': ok';

  Result := Result + Format('  [%d ms]', [ElapsedMs]);
end;

{------------------------------------------------------------------------------
  TSqlExecResult.Statistics
  ----------------------------------------------------------------------------
  Returns the multi-line text shown on the Statistics tab.

  Returns:
    Statement kind, elapsed time, rows fetched or affected, and the engine's
    per-operation counts when it supplied them.

  Notes:
    IBConsole's ISQL window had a Statistics tab and it was genuinely useful,
    because the per-operation counts show work the statement text does not: an
    UPDATE that reports an insert as well has fired a trigger, and that is
    usually the answer to "why is this slow".
------------------------------------------------------------------------------}
function TSqlExecResult.Statistics: string;
begin
  Result :=
    'Statement    : ' + StatementKind + LineEnding +
    'Elapsed      : ' + IntToStr(ElapsedMs) + ' ms' + LineEnding;

  if ReturnsData then
  begin
    Result := Result + 'Rows fetched : ' + IntToStr(Data.RowCount);
    if Truncated then
      Result := Result + ' (stopped at the fetch limit; more are available)';
    Result := Result + LineEnding;
    Result := Result + 'Columns      : ' + IntToStr(Data.ColumnCount) +
      LineEnding;
  end
  else if RowsAffected >= 0 then
    Result := Result + 'Rows affected: ' + IntToStr(RowsAffected) + LineEnding;

  if HasCounts then
  begin
    Result := Result + LineEnding +
      'Operations performed by the engine' + LineEnding +
      '  select   : ' + IntToStr(SelectCount) + LineEnding +
      '  insert   : ' + IntToStr(InsertCount) + LineEnding +
      '  update   : ' + IntToStr(UpdateCount) + LineEnding +
      '  delete   : ' + IntToStr(DeleteCount) + LineEnding;
  end;

  if Trim(Plan) <> '' then
    Result := Result + LineEnding + 'Plan' + LineEnding + Plan + LineEnding;

  if Failed then
    Result := Result + LineEnding + 'The statement failed.' + LineEnding;
end;

{------------------------------------------------------------------------------
  TSqlSession.Create
  ----------------------------------------------------------------------------
  Creates a session on an existing attachment.

  Parameters:
    ADatabase - The attachment, owned by the database context. Must outlive
                this session.

  Notes:
    The transaction is concurrency/write/wait: a snapshot, so the user sees a
    consistent picture for as long as they keep it open, and waiting rather
    than failing on a lock conflict, because in an editor the user would rather
    wait for a lock than have a statement fail immediately.
------------------------------------------------------------------------------}
constructor TSqlSession.Create(ADatabase: TIBDatabase);
begin
  inherited Create;
  FDatabase := ADatabase;
  FFetchLimit := DefaultFetchLimit;
  FAutoCommitDdl := True;

  FTransaction := TIBTransaction.Create(nil);
  FTransaction.DefaultDatabase := FDatabase;
  FTransaction.Params.Clear;
  FTransaction.Params.Add('concurrency');
  FTransaction.Params.Add('wait');
  FTransaction.Params.Add('write');
end;

{------------------------------------------------------------------------------
  TSqlSession.Destroy
  ----------------------------------------------------------------------------
  Rolls back anything still open and releases the transaction.

  Notes:
    Rolls back rather than commits. Closing an editor window is not a decision
    to save the work in it, and guessing otherwise on the user's behalf is how
    a tool writes something nobody asked for.
------------------------------------------------------------------------------}
destructor TSqlSession.Destroy;
begin
  try
    if (FTransaction <> nil) and FTransaction.InTransaction then
      FTransaction.Rollback;
  except
    // shutting down: a failure here must not stop the object being freed
  end;
  FreeAndNil(FTransaction);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TSqlSession.EnsureTransaction
  ----------------------------------------------------------------------------
  Starts the transaction if it is not already running.
------------------------------------------------------------------------------}
procedure TSqlSession.EnsureTransaction;
begin
  if not FTransaction.InTransaction then
    FTransaction.StartTransaction;
end;

{------------------------------------------------------------------------------
  TSqlSession.Commit
  ----------------------------------------------------------------------------
  Commits the user's work.
------------------------------------------------------------------------------}
procedure TSqlSession.Commit;
begin
  if FTransaction.InTransaction then
  begin
    FTransaction.Commit;
    Log.Info('SQL editor: committed');
  end;
end;

{------------------------------------------------------------------------------
  TSqlSession.Rollback
  ----------------------------------------------------------------------------
  Discards the user's work.
------------------------------------------------------------------------------}
procedure TSqlSession.Rollback;
begin
  if FTransaction.InTransaction then
  begin
    FTransaction.Rollback;
    Log.Info('SQL editor: rolled back');
  end;
end;

{------------------------------------------------------------------------------
  TSqlSession.InTransaction
  ----------------------------------------------------------------------------
  Returns True while a transaction is open.
------------------------------------------------------------------------------}
function TSqlSession.InTransaction: Boolean;
begin
  Result := (FTransaction <> nil) and FTransaction.InTransaction;
end;

{------------------------------------------------------------------------------
  TSqlSession.DescribeStatementKind
  ----------------------------------------------------------------------------
  Returns a readable name for a prepared statement's kind.

  Parameters:
    AType - What IBX reported after preparing.
------------------------------------------------------------------------------}
function TSqlSession.DescribeStatementKind(
  AType: TIBSQLStatementTypes): string;
begin
  case AType of
    SQLSelect, SQLSelectForUpdate: Result := 'SELECT';
    SQLInsert:                     Result := 'INSERT';
    SQLUpdate:                     Result := 'UPDATE';
    SQLDelete:                     Result := 'DELETE';
    SQLDDL:                        Result := 'DDL';
    SQLExecProcedure:              Result := 'EXECUTE PROCEDURE';
    SQLSetGenerator:               Result := 'SET GENERATOR';
    SQLCommit:                     Result := 'COMMIT';
    SQLRollback:                   Result := 'ROLLBACK';
    SQLStartTransaction:           Result := 'SET TRANSACTION';
    SQLSavePoint:                  Result := 'SAVEPOINT';
  else
    Result := 'STATEMENT';
  end;
end;

{------------------------------------------------------------------------------
  TSqlSession.TranslateError
  ----------------------------------------------------------------------------
  Turns an IBX exception into an EIbqDatabaseError carrying the status vector.

  Parameters:
    E    - The exception IBX raised.
    ASql - The statement that failed.

  Returns:
    A new EIbqDatabaseError. Not raised here: the caller decides whether a
    failure stops the script.
------------------------------------------------------------------------------}
function TSqlSession.TranslateError(E: Exception;
  const ASql: string): EIbqDatabaseError;
var
  Lines: TStringList;
  StatusLines: TStringArray;
  SqlCode, GdsCode, I: Integer;
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
end;

{------------------------------------------------------------------------------
  TSqlSession.Execute
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The plan is read after Prepare and before ExecQuery, because that is when
    it exists and because a statement that fails to execute has still been
    planned - showing the plan of a statement that then failed is often exactly
    what explains the failure.
------------------------------------------------------------------------------}
function TSqlSession.Execute(const ASql: string): TSqlExecResult;
var
  Query: TIBSQL;
  Started: TDateTime;
  ColumnCount, RowIndex, I: Integer;
  Error: EIbqDatabaseError;
begin
  Result := Default(TSqlExecResult);
  Result.Sql := ASql;
  Result.RowsAffected := -1;
  Result.StatementKind := 'STATEMENT';

  if Trim(ASql) = '' then
  begin
    Result.Message := 'empty statement';
    Exit;
  end;

  Started := Now;
  EnsureTransaction;

  Query := TIBSQL.Create(nil);
  try
    Query.Database := FDatabase;
    Query.Transaction := FTransaction;
    Query.SQL.Text := ASql;

    try
      Query.Prepare;
      Result.StatementKind := DescribeStatementKind(Query.SQLStatementType);
      try
        Result.Plan := Query.Plan;
      except
        Result.Plan := '';        // not every statement kind has a plan
      end;

      Query.ExecQuery;

      Result.ReturnsData := Query.SQLStatementType in
        [SQLSelect, SQLSelectForUpdate, SQLExecProcedure];

      if Result.ReturnsData then
      begin
        ColumnCount := Query.MetaData.Count;
        SetLength(Result.Data.ColumnNames, ColumnCount);
        for I := 0 to ColumnCount - 1 do
          Result.Data.ColumnNames[I] := Trim(Query.MetaData[I].GetAliasName);

        if Query.SQLStatementType = SQLExecProcedure then
        begin
          { EXECUTE PROCEDURE opens no cursor, so EOF is True the moment it
            returns and the fetch loop below would read nothing. Its output
            parameters are one row, already sitting in Fields (IBSQL.pas:756,
            where FResults comes from Execute rather than OpenCursor). Read
            them directly. }
          SetLength(Result.Data.Rows, 1);
          SetLength(Result.Data.Rows[0], ColumnCount);
          for I := 0 to ColumnCount - 1 do
          begin
            if Query.Fields[I].IsNull then
              Result.Data.Rows[0][I] := ''
            else
              Result.Data.Rows[0][I] := Query.Fields[I].AsString;
          end;
          Result.RowsAffected := Query.RowsAffected;
        end
        else
        begin
          RowIndex := 0;
          while (not Query.EOF) and (RowIndex < FFetchLimit) do
          begin
            if RowIndex = Length(Result.Data.Rows) then
              SetLength(Result.Data.Rows, Length(Result.Data.Rows) * 2 + 64);
            SetLength(Result.Data.Rows[RowIndex], ColumnCount);
            for I := 0 to ColumnCount - 1 do
            begin
              if Query.Fields[I].IsNull then
                Result.Data.Rows[RowIndex][I] := ''
              else
                Result.Data.Rows[RowIndex][I] := Query.Fields[I].AsString;
            end;
            Inc(RowIndex);
            Query.Next;
          end;
          SetLength(Result.Data.Rows, RowIndex);
          Result.Truncated := not Query.EOF;
        end;
      end
      else
        Result.RowsAffected := Query.RowsAffected;

      if Query.Statement <> nil then
        Result.HasCounts := Query.Statement.GetRowsAffected(
          Result.SelectCount, Result.InsertCount,
          Result.UpdateCount, Result.DeleteCount);

      Result.ElapsedMs := MilliSecondsBetween(Now, Started);
      Result.Message := Result.Summary;
      Log.Statement(ASql);

      if FAutoCommitDdl and (Query.SQLStatementType = SQLDDL) then
        Commit;
    except
      on E: Exception do
      begin
        Result.Failed := True;
        Result.ElapsedMs := MilliSecondsBetween(Now, Started);
        Error := TranslateError(E, ASql);
        try
          Result.Message := Error.FullText;
        finally
          Error.Free;
        end;
        Log.ErrorWithStatement(Result.Message, ASql);
      end;
    end;
  finally
    Query.Free;
  end;
end;

{------------------------------------------------------------------------------
  TSqlSession.ExecuteScript
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Every statement is executed on the SAME transaction, so a script is one
    unit of work unless it commits itself. That is what makes "run this script,
    look at the result, then decide whether to commit" possible - and it is the
    behaviour a DDL script needs, because half-applied DDL is worse than none.
------------------------------------------------------------------------------}
function TSqlSession.ExecuteScript(const AScript: string;
  AOnProgress: TSqlScriptProgress;
  AStopOnError: Boolean): TSqlExecResultArray;
var
  Statements: TSqlStatementArray;
  I, Count: Integer;
  Continue_: Boolean;
begin
  Result := nil;
  Statements := SplitSqlScript(AScript);
  if Length(Statements) = 0 then
    Exit;

  SetLength(Result, Length(Statements));
  Count := 0;
  Continue_ := True;

  for I := Low(Statements) to High(Statements) do
  begin
    Result[Count] := Execute(Statements[I].Text);
    Inc(Count);

    if Assigned(AOnProgress) then
      AOnProgress(I + 1, Length(Statements), Result[Count - 1], Continue_);

    if not Continue_ then
      Break;
    if AStopOnError and Result[Count - 1].Failed then
      Break;
  end;

  SetLength(Result, Count);
end;

end.
