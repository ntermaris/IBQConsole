{==============================================================================
  Unit:        TransactionRecoveryService
  Purpose:     Lists and resolves transactions left in limbo, through the
               Services API.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, ServerRegistration,
               ServiceConnection, IbqError, AppLog

  IBConsole equivalent: Database > Maintenance > Transaction Recovery.

  WHAT A LIMBO TRANSACTION IS
  A transaction that spans two databases is committed in two steps: every
  database is asked to prepare, and only when all of them have agreed is each
  told to commit. If the coordinator dies between those two steps the
  transaction is left prepared but undecided - in limbo. Its record versions
  are neither the old ones nor the new ones, and no ordinary query can settle
  them.

  Limbo transactions matter beyond the two-database case that creates them,
  because a sweep will not pass one: the oldest interesting transaction stops
  advancing, garbage accumulates behind it, and performance decays until
  somebody decides the undecided transaction's fate. That decision is what
  this unit exists to carry out.

  WHY THE SERVER'S RECOMMENDATION IS WORTH FOLLOWING
  For each transaction the server reports what the other participants did, and
  from that an Advice: commit or roll back. Following it makes this database
  agree with the others. Overriding it is legitimate - the administrator may
  know the other database has since been restored from a backup - but it is a
  decision to make deliberately, which is why the recommendation is reported
  and never silently applied.

  WHAT THE SERVICES API WILL AND WILL NOT DO
  One resolution request carries an action for EVERY transaction the server
  listed; there is no verb for "leave this one alone". IBX exposes no way to
  drop an entry from the list either - its dataset wrapper's Delete is a
  deliberate no-op. So Resolve acts on the whole list, each transaction
  getting the action carried in its own record. To leave a transaction in
  limbo, do not resolve at all. This is a property of the Services API, not a
  shortcut taken here, and the dialog says so.
==============================================================================}
unit TransactionRecoveryService;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, IBXServices,
  ServerRegistration, ServiceConnection, IbqError, AppLog;

type
  { What the server says has become of a transaction. }
  TLimboState = (
    lsLimbo,      // still undecided
    lsCommit,     // the other participants committed
    lsRollback,   // the other participants rolled back
    lsUnknown     // the server would not say
  );

  { What the server recommends doing about a transaction. }
  TLimboAdvice = (
    ldCommit,     // commit, to agree with the other participants
    ldRollback,   // roll back, to agree with the other participants
    ldUnknown     // the server has no recommendation
  );

  { What the administrator has decided to do about a transaction. The Services
    API offers these two and nothing else - notably no "leave alone". }
  TLimboAction = (
    laCommit,
    laRollback
  );

  { How a whole resolution request is to be decided. }
  TGlobalRecoveryAction = (
    graPerTransaction,   // each transaction carries its own action
    graCommitAll,        // commit every listed transaction
    graRollbackAll,      // roll back every listed transaction
    graRecoverTwoPhase   // let the server finish the two-phase commit itself
  );

  { One transaction in limbo. A record: it is a snapshot of what the server
    said, is copied freely and owns nothing. }
  TLimboTransaction = record
    { The transaction id, which is what the server is told to act on. }
    Id: Integer;
    { True when the transaction spanned more than one database, which is the
      case that creates limbo transactions in the first place. }
    MultiDatabase: Boolean;
    { The machine that started the transaction. }
    HostSite: string;
    { The other machine taking part, for a multi-database transaction. }
    RemoteSite: string;
    { The other database taking part, as that machine knows it. }
    RemoteDatabasePath: string;
    { What became of the transaction elsewhere. }
    State: TLimboState;
    { What the server recommends. }
    Advice: TLimboAdvice;
    { What will be done, once the administrator has chosen. Starts at the
      server's recommendation. }
    Action: TLimboAction;

    { Returns 'transaction 1234', for a log line. }
    function Describe: string;
  end;

  TLimboTransactionArray = array of TLimboTransaction;

  { TTransactionRecoveryService
    Limbo transaction recovery for one database.

    Owns nothing passed to it: the registration outlives this object and is
    what the user edits. }
  TTransactionRecoveryService = class(TObject)
  private
    FRegistration: TServerRegistration;
    FPassword: string;
    FDatabasePath: string;
    { Translates IBX's transaction state into ours. }
    function MapState(AState: TTransactionState): TLimboState;
    { Translates IBX's recommendation into ours. }
    function MapAdvice(AAdvice: TTransactionAdvise): TLimboAdvice;
    { Translates our global action into IBX's. }
    function MapGlobalAction(
      AAction: TGlobalRecoveryAction): TTransactionGlobalAction;
  public
    { Creates a service for one database on one server.

      Parameters:
        ARegistration - The server. Not owned; must outlive this object.
        APassword     - The password to attach with.
        ADatabasePath - The database, as the SERVER knows it. }
    constructor Create(ARegistration: TServerRegistration;
      const APassword, ADatabasePath: string);

    { Returns why limbo transactions cannot be managed here, or an empty
      string. }
    function Unavailable: string;

    { Returns every transaction the server reports as being in limbo, each
      with Action set to the server's recommendation. }
    function List: TLimboTransactionArray;

    { Resolves limbo transactions, reports what the server said into AOutput,
      and returns how many it was asked to resolve. }
    function Resolve(const ATransactions: TLimboTransactionArray;
      AGlobal: TGlobalRecoveryAction; AOutput: TStrings): Integer;

    { The server these transactions belong to. }
    property Registration: TServerRegistration read FRegistration;
    { The database, as the server knows it. }
    property DatabasePath: string read FDatabasePath;
  end;

implementation

{------------------------------------------------------------------------------
  TLimboTransaction.Describe
  ----------------------------------------------------------------------------
  Returns 'transaction 1234', for a log line.

  Returns:
    The transaction named by its id.
------------------------------------------------------------------------------}
function TLimboTransaction.Describe: string;
begin
  Result := Format('transaction %d', [Id]);
end;

{------------------------------------------------------------------------------
  TTransactionRecoveryService.Create
  ----------------------------------------------------------------------------
  Creates a service for one database on one server.

  Parameters:
    ARegistration - The server. Not owned.
    APassword     - The password to attach with.
    ADatabasePath - The database, as the server knows it.

  Raises:
    EIbqError - ARegistration is nil.
------------------------------------------------------------------------------}
constructor TTransactionRecoveryService.Create(
  ARegistration: TServerRegistration; const APassword, ADatabasePath: string);
begin
  inherited Create;
  if ARegistration = nil then
  begin
    raise EIbqError.Create(
      'TTransactionRecoveryService needs a server registration.');
  end;
  FRegistration := ARegistration;      // injected, NOT owned
  FPassword := APassword;
  FDatabasePath := ADatabasePath;
end;

{------------------------------------------------------------------------------
  TTransactionRecoveryService.MapState
  ----------------------------------------------------------------------------
  Translates IBX's transaction state into ours, so that no IBX type reaches a
  form.

  Parameters:
    AState - What IBX reported.

  Returns:
    The matching TLimboState; lsUnknown for anything unrecognised.
------------------------------------------------------------------------------}
function TTransactionRecoveryService.MapState(
  AState: TTransactionState): TLimboState;
begin
  case AState of
    LimboState:
      Result := lsLimbo;
    CommitState:
      Result := lsCommit;
    RollbackState:
      Result := lsRollback;
  else
    Result := lsUnknown;
  end;
end;

{------------------------------------------------------------------------------
  TTransactionRecoveryService.MapAdvice
  ----------------------------------------------------------------------------
  Translates IBX's recommendation into ours, so that no IBX type reaches a
  form.

  Parameters:
    AAdvice - What IBX reported.

  Returns:
    The matching TLimboAdvice; ldUnknown when the server had no advice.
------------------------------------------------------------------------------}
function TTransactionRecoveryService.MapAdvice(
  AAdvice: TTransactionAdvise): TLimboAdvice;
begin
  case AAdvice of
    CommitAdvise:
      Result := ldCommit;
    RollbackAdvise:
      Result := ldRollback;
  else
    Result := ldUnknown;
  end;
end;

{------------------------------------------------------------------------------
  TTransactionRecoveryService.MapGlobalAction
  ----------------------------------------------------------------------------
  Translates our global action into IBX's.

  Parameters:
    AAction - What the caller asked for.

  Returns:
    The matching TTransactionGlobalAction. graPerTransaction becomes
    NoGlobalAction, which is IBX's name for "each transaction decides".
------------------------------------------------------------------------------}
function TTransactionRecoveryService.MapGlobalAction(
  AAction: TGlobalRecoveryAction): TTransactionGlobalAction;
begin
  case AAction of
    graCommitAll:
      Result := CommitGlobal;
    graRollbackAll:
      Result := RollbackGlobal;
    graRecoverTwoPhase:
      Result := RecoverTwoPhaseGlobal;
  else
    Result := NoGlobalAction;
  end;
end;

{------------------------------------------------------------------------------
  TTransactionRecoveryService.Unavailable
  ----------------------------------------------------------------------------
  Returns why limbo transactions cannot be managed here, or an empty string.

  Returns:
    The reason, ready to show, or an empty string when the service is usable.

  Notes:
    Checked before the dialog opens, so a registration that cannot answer says
    so once rather than failing on every button.
------------------------------------------------------------------------------}
function TTransactionRecoveryService.Unavailable: string;
begin
  if Trim(FDatabasePath) = '' then
  begin
    Result := 'No database has been named. Limbo transactions belong to a ' +
      'database, so one has to be chosen before they can be listed.';
    Exit;
  end;
  Result := '';
end;

{------------------------------------------------------------------------------
  TTransactionRecoveryService.List
  ----------------------------------------------------------------------------
  Returns every transaction the server reports as being in limbo.

  Returns:
    The transactions, each with Action set to the server's recommendation. An
    empty array when there are none, which is the healthy case and not an
    error.

  Raises:
    EIbqDatabaseError - The server refused the attachment or the request.

  Notes:
    IBX fetches the list the first time its count is read, so the count is
    read once into a local and reused. Reading it again would go back to the
    server whenever the list came back empty.
------------------------------------------------------------------------------}
function TTransactionRecoveryService.List: TLimboTransactionArray;
var
  Connection: TServiceConnection;
  Service: TIBXLimboTransactionResolutionService;
  Info: TLimboTransactionInfo;
  Count: Integer;
  I: Integer;
begin
  Result := nil;
  Connection := TServiceConnection.Create(FRegistration);
  Service := nil;
  try
    Connection.Connect(FPassword);

    Service := TIBXLimboTransactionResolutionService.Create(nil);
    Service.ServicesConnection := Connection.Connection;
    Service.DatabaseName := FDatabasePath;

    Count := Service.LimboTransactionInfoCount;
    SetLength(Result, Count);

    for I := 0 to Count - 1 do
    begin
      Info := Service.LimboTransactionInfo[I];
      Result[I].Id := Info.ID;
      Result[I].MultiDatabase := Info.MultiDatabase;
      Result[I].HostSite := TrimRight(Info.HostSite);
      Result[I].RemoteSite := TrimRight(Info.RemoteSite);
      Result[I].RemoteDatabasePath := TrimRight(Info.RemoteDatabasePath);
      Result[I].State := MapState(Info.State);
      Result[I].Advice := MapAdvice(Info.Advise);
      if Result[I].Advice = ldRollback then
      begin
        Result[I].Action := laRollback;
      end
      else
      begin
        Result[I].Action := laCommit;
      end;
    end;
  finally
    Service.Free;
    Connection.Free;
  end;
end;

{------------------------------------------------------------------------------
  TTransactionRecoveryService.Resolve
  ----------------------------------------------------------------------------
  Resolves limbo transactions and reports what the server said.

  Parameters:
    ATransactions - The transactions as last listed, carrying the action
                    chosen for each. Matched to the server's own list by Id;
                    only used when AGlobal is graPerTransaction.
    AGlobal       - How to decide the request as a whole.
    AOutput       - Receives the server's output, line by line.

  Returns:
    How many transactions the server was asked to resolve. Zero when nothing
    was in limbo by the time the request was made, in which case AOutput is
    left alone.

  Raises:
    EIbqError         - AOutput is nil.
    EIbqDatabaseError - The server refused the attachment or the request.

  Notes:
    Re-reads the server's list rather than trusting ATransactions, because
    another administrator may have resolved something in between. A
    transaction that has appeared since the last List is resolved too, and
    carries its own recommendation, because the Services API cannot be asked
    to skip it.
------------------------------------------------------------------------------}
function TTransactionRecoveryService.Resolve(
  const ATransactions: TLimboTransactionArray;
  AGlobal: TGlobalRecoveryAction; AOutput: TStrings): Integer;
var
  Connection: TServiceConnection;
  Service: TIBXLimboTransactionResolutionService;
  Info: TLimboTransactionInfo;
  Count: Integer;
  I: Integer;
  J: Integer;
begin
  Result := 0;
  if AOutput = nil then
  begin
    raise EIbqError.Create('TTransactionRecoveryService.Resolve needs a ' +
      'string list to report into.');
  end;

  Connection := TServiceConnection.Create(FRegistration);
  Service := nil;
  try
    Connection.Connect(FPassword);

    Service := TIBXLimboTransactionResolutionService.Create(nil);
    Service.ServicesConnection := Connection.Connection;
    Service.DatabaseName := FDatabasePath;

    Count := Service.LimboTransactionInfoCount;
    if Count = 0 then
    begin
      Exit;
    end;

    Service.GlobalAction := MapGlobalAction(AGlobal);

    if AGlobal = graPerTransaction then
    begin
      for I := 0 to Count - 1 do
      begin
        Info := Service.LimboTransactionInfo[I];
        for J := 0 to High(ATransactions) do
        begin
          if ATransactions[J].Id = Info.ID then
          begin
            if ATransactions[J].Action = laRollback then
            begin
              Info.Action := RollbackAction;
            end
            else
            begin
              Info.Action := CommitAction;
            end;
            Break;
          end;
        end;
      end;
    end;

    Log.InfoFmt('Resolving %d limbo transaction(s) in %s',
      [Count, FDatabasePath]);
    Service.Execute(AOutput);
    Result := Count;
  finally
    Service.Free;
    Connection.Free;
  end;
end;

end.
