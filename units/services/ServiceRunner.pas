{==============================================================================
  Unit:        ServiceRunner
  Purpose:     Runs one Services API task on a worker thread, streaming its
               output back to the user interface and allowing it to be
               cancelled.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, ServerRegistration,
               ServiceConnection, IbqError, AppLog

  WHY EVERY MAINTENANCE COMMAND GOES THROUGH HERE
  A backup of a 2.6 GB database takes minutes. Run on the main thread it
  freezes the window, Windows paints it grey and titles it "Not Responding",
  and the user - reasonably - kills the program in the middle of a restore.
  So every service runs on a thread, and the only thing the main thread does is
  append the lines it is handed.

  WHY EACH RUN GETS ITS OWN SERVICE ATTACHMENT
  Cancelling a running Firebird service means detaching from it: there is no
  "stop" verb in the Services API. If every task shared the server connection,
  cancelling a backup would also drop the user's server log window and any
  other task in flight.

  So a runner opens its own attachment for the duration and closes it at the
  end. This is what IBConsole did - each maintenance dialog attached for
  itself - and it also gives two tasks against the same server for free.

  WHAT A CALLER SEES
  Plain strings and booleans. No IBX type crosses this unit's interface, so a
  form can own a runner without breaking the layering rule.
==============================================================================}
unit ServiceRunner;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IBXServices,
  ServerRegistration, ServiceConnection, IbqError, AppLog;

type
  { Raised for each line the service produces. }
  TServiceLineEvent = procedure(Sender: TObject; const ALine: string) of object;

  { Raised once when the task stops, for any reason.

    Parameters:
      ASuccess   - True when the task ran to completion.
      ACancelled - True when the user stopped it; ASuccess is then False and
                   AError is empty, because a cancellation is not a failure.
      AError     - The full error text when ASuccess is False and the task was
                   not cancelled. }
  TServiceFinishedEvent = procedure(Sender: TObject; ASuccess, ACancelled: Boolean;
    const AError: string) of object;

  TServiceRunner = class;

  { TServiceTask
    What to run. One descendant per maintenance command, each in its own unit.

    The descendant is created and configured on the main thread - its
    properties are plain values typed by the user - but its two protected
    methods are called on the worker thread, with a connection that belongs to
    that thread. That split is the whole contract. }
  TServiceTask = class(TObject)
  protected
    { Creates the IBX service object for this task.

      Parameters:
        AConnection - The worker thread's services connection. The returned
                      object must be attached to it and is freed by the runner.

      Returns:
        The service to execute. TIBXCustomService rather than the narrower
        TIBXControlAndQueryService, because not every maintenance command
        streams output: a shutdown or a startup is a single call that either
        works or raises. }
    function CreateService(
      AConnection: TIBXServicesConnection): TIBXCustomService; virtual; abstract;

    { Applies this task's settings to the service object.

      Parameters:
        AService - What CreateService returned. }
    procedure Configure(AService: TIBXCustomService); virtual;

    { Performs the task.

      Parameters:
        AService - What CreateService returned, already configured.

      Notes:
        The default runs a streaming service to completion, which is what
        backup, restore, validation, statistics and the log all want. A task
        whose service is a single call - shutdown, startup - overrides this
        and makes that call. }
    procedure Run(AService: TIBXCustomService); virtual;
  public
    { Returns the one-line description written to the log when the task starts,
      e.g. 'Backup of C:\db\live.fdb'. }
    function Describe: string; virtual;

    { Returns an empty string when the task is ready to run, or the reason it
      is not - a missing file name, an unwritable directory.

      Notes:
        Checked on the main thread before the thread starts, so the user gets
        the message in the dialog they are looking at rather than in an output
        window that has just appeared. }
    function Validate: string; virtual;
  end;

  { TServiceRunner
    Runs one TServiceTask against one registered server. }
  TServiceRunner = class(TObject)
  private
    FRegistration: TServerRegistration;
    FPassword: string;
    FTask: TServiceTask;
    FOwnsTask: Boolean;
    FThread: TThread;
    FOutput: TStringList;
    FOnLine: TServiceLineEvent;
    FOnFinished: TServiceFinishedEvent;
    FCancelRequested: Boolean;
    FRunning: Boolean;
    FSuccess: Boolean;
    FError: string;
    procedure HandleLine(const ALine: string);
    procedure HandleFinished(ASuccess: Boolean; const AError: string);
  public
    { Creates a runner for one task against one server.

      Parameters:
        ARegistration - The server. Not owned; must outlive the runner.
        APassword     - The password to attach with.
        ATask         - What to run.
        AOwnsTask     - True when the runner should free ATask. }
    constructor Create(ARegistration: TServerRegistration;
      const APassword: string; ATask: TServiceTask; AOwnsTask: Boolean = True);
    destructor Destroy; override;

    { Starts the task.

      Returns:
        An empty string when it started, or the reason it did not - which is
        either Validate's answer or "already running".

      Notes:
        Returns as soon as the thread is running. Everything after that arrives
        through OnLine and OnFinished, on the main thread. }
    function Start: string;

    { Asks the task to stop.

      Notes:
        Returns immediately; OnFinished fires with ACancelled True once the
        thread has unwound. Firebird has no "stop this service" verb, so the
        thread stops reading output and detaches, which is what aborts the work
        on the server. A backup cancelled this way leaves a partial, unusable
        backup file - saying so is the caller's job. }
    procedure Cancel;

    { Blocks until the task has finished. For a console test or a modal dialog
      that must not close early; never call it from a paint handler. }
    procedure WaitForCompletion;

    { True between Start and OnFinished. }
    function IsRunning: Boolean;

    { Every line the task produced, in order. }
    property Output: TStringList read FOutput;
    { True when the last run completed. }
    property Success: Boolean read FSuccess;
    { The error text of the last run, empty when it succeeded. }
    property Error: string read FError;
    { True once Cancel has been called. }
    property Cancelled: Boolean read FCancelRequested;
    { The task being run. }
    property Task: TServiceTask read FTask;

    { Raised for each line of output, on the main thread. }
    property OnLine: TServiceLineEvent read FOnLine write FOnLine;
    { Raised once when the task stops, on the main thread. }
    property OnFinished: TServiceFinishedEvent read FOnFinished write FOnFinished;
  end;

implementation

type
  { TServiceThread
    The worker. Everything it touches - the attachment and the service object -
    it creates and destroys itself, so nothing is shared with the main thread
    except the strings passed through Synchronize. }
  TServiceThread = class(TThread)
  private
    FRunner: TServiceRunner;
    FConnection: TServiceConnection;
    FService: TIBXCustomService;
    FLine: string;
    FError: string;
    FSuccess: Boolean;
    procedure GetNextLine(Sender: TObject; var Line: string);
    procedure SyncLine;
    procedure SyncFinished;
  protected
    procedure Execute; override;
  public
    constructor Create(ARunner: TServiceRunner);
  end;

{------------------------------------------------------------------------------
  TServiceTask.Configure
  ----------------------------------------------------------------------------
  Applies this task's settings to the service object.

  Parameters:
    AService - What CreateService returned.

  Notes:
    Empty here: a task whose service needs no settings beyond the database name
    its CreateService already supplied - a sweep, the server log - does not
    have to override this.
------------------------------------------------------------------------------}
procedure TServiceTask.Configure(AService: TIBXCustomService);
begin
  { nothing by default }
end;

{------------------------------------------------------------------------------
  TServiceTask.Run
  ----------------------------------------------------------------------------
  Performs the task.

  Parameters:
    AService - What CreateService returned, already configured.

  Notes:
    Execute streams through OnGetNextLine; the TStrings it also fills is not
    needed, and passing nil keeps a long backup's output from being held twice.
------------------------------------------------------------------------------}
procedure TServiceTask.Run(AService: TIBXCustomService);
begin
  if AService is TIBXControlAndQueryService then
    TIBXControlAndQueryService(AService).Execute(nil)
  else
    raise EIbqError.Create(ClassName +
      ' must override Run: its service does not stream output.');
end;

{------------------------------------------------------------------------------
  TServiceTask.Describe
  ----------------------------------------------------------------------------
  Returns the one-line description written to the log when the task starts.
------------------------------------------------------------------------------}
function TServiceTask.Describe: string;
begin
  Result := ClassName;
end;

{------------------------------------------------------------------------------
  TServiceTask.Validate
  ----------------------------------------------------------------------------
  Returns an empty string when the task is ready to run, or the reason it is
  not.
------------------------------------------------------------------------------}
function TServiceTask.Validate: string;
begin
  Result := '';
end;

{------------------------------------------------------------------------------
  TServiceThread.Create
  ----------------------------------------------------------------------------
  Creates the worker, suspended.

  Parameters:
    ARunner - The runner that owns it and receives its output.
------------------------------------------------------------------------------}
constructor TServiceThread.Create(ARunner: TServiceRunner);
begin
  inherited Create(True);
  FRunner := ARunner;
  FreeOnTerminate := False;
end;

{------------------------------------------------------------------------------
  TServiceThread.GetNextLine
  ----------------------------------------------------------------------------
  Receives one line of service output.

  Parameters:
    Line - The line, as IBX read it.

  Notes:
    This is where cancellation happens. IBX calls this from inside its own read
    loop, so raising here unwinds out of Execute - which is the only way to
    stop a service that is producing output. The exception is caught in
    TServiceThread.Execute and turned into a cancellation, not a failure.
------------------------------------------------------------------------------}
procedure TServiceThread.GetNextLine(Sender: TObject; var Line: string);
begin
  if FRunner.FCancelRequested or Terminated then
    raise EIbqCancelled.Create('cancelled');

  FLine := Line;
  Synchronize(@SyncLine);
end;

{------------------------------------------------------------------------------
  TServiceThread.SyncLine
  ----------------------------------------------------------------------------
  Hands one line to the runner, on the main thread.
------------------------------------------------------------------------------}
procedure TServiceThread.SyncLine;
begin
  FRunner.HandleLine(FLine);
end;

{------------------------------------------------------------------------------
  TServiceThread.SyncFinished
  ----------------------------------------------------------------------------
  Reports the outcome to the runner, on the main thread.
------------------------------------------------------------------------------}
procedure TServiceThread.SyncFinished;
begin
  FRunner.HandleFinished(FSuccess, FError);
end;

{------------------------------------------------------------------------------
  TServiceThread.Execute
  ----------------------------------------------------------------------------
  Attaches, runs the task, detaches.

  Notes:
    The attachment, the service object and their destruction all live here so
    that no IBX object is ever touched by two threads. The detach in the
    finally block is what aborts the work on the server when the user cancels.
------------------------------------------------------------------------------}
procedure TServiceThread.Execute;
begin
  FSuccess := False;
  FError := '';
  FConnection := nil;
  FService := nil;
  try
    try
      FConnection := TServiceConnection.Create(FRunner.FRegistration);
      FConnection.Connect(FRunner.FPassword);

      FService := FRunner.FTask.CreateService(FConnection.Connection);
      if FService = nil then
        raise EIbqError.Create('The task produced no service object.');

      { Only a streaming service has lines to hand over - and only a streaming
        service can be cancelled, because the callback is where cancellation
        happens. A single-call command runs to its end or raises. }
      if FService is TIBXControlAndQueryService then
        TIBXControlAndQueryService(FService).OnGetNextLine := @GetNextLine;

      FRunner.FTask.Configure(FService);
      FRunner.FTask.Run(FService);
      FSuccess := not FRunner.FCancelRequested;
    except
      on E: EIbqCancelled do
        FSuccess := False;
      on E: EIbqDatabaseError do
        FError := E.FullText;
      on E: Exception do
        FError := E.Message;
    end;
  finally
    FreeAndNil(FService);
    FreeAndNil(FConnection);
    Synchronize(@SyncFinished);
  end;
end;

{------------------------------------------------------------------------------
  TServiceRunner.Create
  ----------------------------------------------------------------------------
  Creates a runner for one task against one server.

  Parameters:
    ARegistration - The server. Not owned.
    APassword     - The password to attach with.
    ATask         - What to run.
    AOwnsTask     - True when the runner should free ATask.
------------------------------------------------------------------------------}
constructor TServiceRunner.Create(ARegistration: TServerRegistration;
  const APassword: string; ATask: TServiceTask; AOwnsTask: Boolean);
begin
  inherited Create;
  if ARegistration = nil then
    raise EIbqError.Create('TServiceRunner needs a server registration.');
  if ATask = nil then
    raise EIbqError.Create('TServiceRunner needs a task.');

  FRegistration := ARegistration;
  FPassword := APassword;
  FTask := ATask;
  FOwnsTask := AOwnsTask;
  FOutput := TStringList.Create;
end;

{------------------------------------------------------------------------------
  TServiceRunner.Destroy
  ----------------------------------------------------------------------------
  Stops a running task and waits for it before releasing anything.

  Notes:
    Waiting is not optional. The thread holds a pointer to this object and
    calls into it through Synchronize; freeing the runner first would leave it
    writing into released memory.
------------------------------------------------------------------------------}
destructor TServiceRunner.Destroy;
begin
  if FThread <> nil then
  begin
    Cancel;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FreeAndNil(FOutput);
  if FOwnsTask then
    FreeAndNil(FTask);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TServiceRunner.Start
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function TServiceRunner.Start: string;
begin
  if FRunning then
    Exit('This task is already running.');

  Result := FTask.Validate;
  if Result <> '' then
    Exit;

  { A runner can be started again after it has finished; the previous thread
    object is only released here, once nothing can still be using it. }
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;

  FOutput.Clear;
  FCancelRequested := False;
  FSuccess := False;
  FError := '';
  FRunning := True;

  Log.Info('Service task started: ' + FTask.Describe);

  FThread := TServiceThread.Create(Self);
  FThread.Start;
end;

{------------------------------------------------------------------------------
  TServiceRunner.Cancel
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure TServiceRunner.Cancel;
begin
  if not FRunning then
    Exit;
  FCancelRequested := True;
  Log.Warning('Service task cancelled: ' + FTask.Describe);
end;

{------------------------------------------------------------------------------
  TServiceRunner.WaitForCompletion
  ----------------------------------------------------------------------------
  Blocks until the task has finished.

  Notes:
    CheckSynchronize is called in the wait loop so the lines the worker is
    handing over still arrive: without it a console caller would block the
    thread it is waiting for.
------------------------------------------------------------------------------}
procedure TServiceRunner.WaitForCompletion;
begin
  while FRunning do
  begin
    CheckSynchronize(50);
    if FThread = nil then
      Break;
  end;
end;

{------------------------------------------------------------------------------
  TServiceRunner.IsRunning
  ----------------------------------------------------------------------------
  Returns True between Start and OnFinished.
------------------------------------------------------------------------------}
function TServiceRunner.IsRunning: Boolean;
begin
  Result := FRunning;
end;

{------------------------------------------------------------------------------
  TServiceRunner.HandleLine
  ----------------------------------------------------------------------------
  Records one line and passes it on. Called on the main thread.

  Parameters:
    ALine - The line the service produced.
------------------------------------------------------------------------------}
procedure TServiceRunner.HandleLine(const ALine: string);
begin
  FOutput.Add(ALine);
  if Assigned(FOnLine) then
    FOnLine(Self, ALine);
end;

{------------------------------------------------------------------------------
  TServiceRunner.HandleFinished
  ----------------------------------------------------------------------------
  Records the outcome and reports it. Called on the main thread.

  Parameters:
    ASuccess - True when the task ran to completion.
    AError   - The failure text, empty on success or cancellation.
------------------------------------------------------------------------------}
procedure TServiceRunner.HandleFinished(ASuccess: Boolean; const AError: string);
begin
  FRunning := False;
  FSuccess := ASuccess;
  FError := AError;

  if ASuccess then
    Log.Info('Service task finished: ' + FTask.Describe)
  else if FCancelRequested then
    Log.Warning('Service task stopped by the user: ' + FTask.Describe)
  else
    Log.Error('Service task failed: ' + FTask.Describe + ' - ' + AError);

  if Assigned(FOnFinished) then
    FOnFinished(Self, ASuccess, FCancelRequested, AError);
end;

end.
