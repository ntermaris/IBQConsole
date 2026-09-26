{==============================================================================
  Unit:        AppLog
  Purpose:     The application log: every statement IBQConsole runs on the
               user's behalf, plus warnings and errors. Feeds the log panel at
               the bottom of the main window.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils

  Neither IBConsole nor a plain SQL tool shows the user what the program itself
  is doing. FlameRobin's log is one of its most-used features, because a user
  learning Firebird can read the statements the tool generates. Logging every
  statement is therefore a feature, not a debugging aid.
==============================================================================}
unit AppLog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { What kind of line this is; the log panel colours accordingly. }
  TLogSeverity = (lsInfo, lsStatement, lsWarning, lsError);

  { Raised for each new line so the UI can append without polling. }
  TLogLineEvent = procedure(ASeverity: TLogSeverity;
    const ATimestamp: TDateTime; const AText: string) of object;

  { TAppLog
    Collects log lines and hands them to whoever is displaying them. Holds at
    most MaxLines entries so a long session cannot grow without bound.

    Not thread-safe by design: worker threads report through Synchronize, so
    every call arrives on the main thread. }
  TAppLog = class(TObject)
  private
    FLines: TStringList;
    FMaxLines: Integer;
    FOnLine: TLogLineEvent;
    FEnabled: Boolean;
    procedure Add(ASeverity: TLogSeverity; const AText: string);
  public
    constructor Create;
    destructor Destroy; override;

    { Records an informational line: connected, disconnected, refreshed. }
    procedure Info(const AText: string);
    { Records an informational line built with Format. }
    procedure InfoFmt(const AText: string; const AArgs: array of const);
    { Records a statement the program executed. }
    procedure Statement(const ASql: string);
    { Records something the user should notice but that did not fail. }
    procedure Warning(const AText: string);
    { Records a failure. }
    procedure Error(const AText: string);
    { Records a failure together with the statement that caused it. }
    procedure ErrorWithStatement(const AText, ASql: string);

    { Empties the log. }
    procedure Clear;
    { Writes the whole log to a file, for attaching to a bug report. }
    procedure SaveToFile(const AFileName: string);

    { Every line held, oldest first, each already prefixed with its time. }
    property Lines: TStringList read FLines;
    { How many lines are kept before the oldest are discarded. }
    property MaxLines: Integer read FMaxLines write FMaxLines;
    { Set False to drop everything on the floor, for a benchmark run. }
    property Enabled: Boolean read FEnabled write FEnabled;
    { Raised for each new line. }
    property OnLine: TLogLineEvent read FOnLine write FOnLine;
  end;

{ Returns the application-wide log, creating it on first use. }
function Log: TAppLog;

implementation

var
  LogInstance: TAppLog = nil;

{------------------------------------------------------------------------------
  Log
  ----------------------------------------------------------------------------
  Returns the single application log.

  Returns:
    The instance, created on first call and freed at shutdown.
------------------------------------------------------------------------------}
function Log: TAppLog;
begin
  if LogInstance = nil then
    LogInstance := TAppLog.Create;
  Result := LogInstance;
end;

{------------------------------------------------------------------------------
  TAppLog.Create
  ----------------------------------------------------------------------------
  Creates an empty, enabled log holding up to 5000 lines.
------------------------------------------------------------------------------}
constructor TAppLog.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FMaxLines := 5000;
  FEnabled := True;
end;

{------------------------------------------------------------------------------
  TAppLog.Destroy
  ----------------------------------------------------------------------------
  Releases the held lines.
------------------------------------------------------------------------------}
destructor TAppLog.Destroy;
begin
  FreeAndNil(FLines);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TAppLog.Add
  ----------------------------------------------------------------------------
  Appends one line and tells the display about it.

  Parameters:
    ASeverity - Kind of line.
    AText     - The text, which may span several lines.

  Notes:
    Trims the oldest lines when the limit is passed. The event is raised even
    when the line was trimmed away immediately, because the display keeps its
    own scrollback.
------------------------------------------------------------------------------}
procedure TAppLog.Add(ASeverity: TLogSeverity; const AText: string);
var
  Now_: TDateTime;
begin
  if not FEnabled then
    Exit;

  Now_ := SysUtils.Now;
  FLines.Add(FormatDateTime('hh:nn:ss', Now_) + '  ' + AText);

  while FLines.Count > FMaxLines do
    FLines.Delete(0);

  if Assigned(FOnLine) then
    FOnLine(ASeverity, Now_, AText);
end;

{------------------------------------------------------------------------------
  TAppLog.Info
  ----------------------------------------------------------------------------
  Records an informational line.

  Parameters:
    AText - What happened.
------------------------------------------------------------------------------}
procedure TAppLog.Info(const AText: string);
begin
  Add(lsInfo, AText);
end;

{------------------------------------------------------------------------------
  TAppLog.InfoFmt
  ----------------------------------------------------------------------------
  Records an informational line built with Format.

  Parameters:
    AText - Format string.
    AArgs - Format arguments.
------------------------------------------------------------------------------}
procedure TAppLog.InfoFmt(const AText: string; const AArgs: array of const);
begin
  Add(lsInfo, Format(AText, AArgs));
end;

{------------------------------------------------------------------------------
  TAppLog.Statement
  ----------------------------------------------------------------------------
  Records a statement the program executed on the user's behalf.

  Parameters:
    ASql - The statement text, exactly as sent to the server.
------------------------------------------------------------------------------}
procedure TAppLog.Statement(const ASql: string);
begin
  Add(lsStatement, ASql);
end;

{------------------------------------------------------------------------------
  TAppLog.Warning
  ----------------------------------------------------------------------------
  Records something the user should notice that did not fail.

  Parameters:
    AText - The warning.
------------------------------------------------------------------------------}
procedure TAppLog.Warning(const AText: string);
begin
  Add(lsWarning, AText);
end;

{------------------------------------------------------------------------------
  TAppLog.Error
  ----------------------------------------------------------------------------
  Records a failure.

  Parameters:
    AText - The error, ideally the full status vector.
------------------------------------------------------------------------------}
procedure TAppLog.Error(const AText: string);
begin
  Add(lsError, AText);
end;

{------------------------------------------------------------------------------
  TAppLog.ErrorWithStatement
  ----------------------------------------------------------------------------
  Records a failure together with the statement that caused it.

  Parameters:
    AText - The error text.
    ASql  - The statement that failed.

  Notes:
    Logged as two entries rather than one so the user can copy the statement
    on its own and paste it straight into a SQL editor.
------------------------------------------------------------------------------}
procedure TAppLog.ErrorWithStatement(const AText, ASql: string);
begin
  Add(lsError, AText);
  if ASql <> '' then
    Add(lsStatement, ASql);
end;

{------------------------------------------------------------------------------
  TAppLog.Clear
  ----------------------------------------------------------------------------
  Empties the log.
------------------------------------------------------------------------------}
procedure TAppLog.Clear;
begin
  FLines.Clear;
end;

{------------------------------------------------------------------------------
  TAppLog.SaveToFile
  ----------------------------------------------------------------------------
  Writes the whole log to a file.

  Parameters:
    AFileName - Destination path, overwritten if it exists.

  Raises:
    EFCreateError - The file cannot be written.
------------------------------------------------------------------------------}
procedure TAppLog.SaveToFile(const AFileName: string);
begin
  FLines.SaveToFile(AFileName);
end;

finalization
  FreeAndNil(LogInstance);

end.
