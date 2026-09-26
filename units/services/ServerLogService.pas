{==============================================================================
  Unit:        ServerLogService
  Purpose:     Fetches the server's log file (firebird.log) through the
               Services API.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, ServiceRunner

  IBConsole equivalent: Server > View Logfile. FlameRobin has no equivalent -
  this is one of the IBConsole ideas worth keeping (§4.1).

  WHY IT MATTERS
  When a database has been shut down uncleanly, when a sweep has failed, when
  the engine has caught an internal error, it says so in firebird.log and
  nowhere else. Being able to read it without a shell on the server - which the
  person diagnosing the problem often does not have - is most of the value of
  an administration tool.

  It is a whole-file read, not a tail: the Services API offers no way to ask
  for the last N lines. On a server that has been up for years the log can run
  to megabytes, which is a reason to show it in a window with a search box,
  not a reason to avoid fetching it.
==============================================================================}
unit ServerLogService;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IBXServices, ServiceRunner;

type
  { TServerLogService
    Fetches the log of the server the runner is attached to. }
  TServerLogService = class(TServiceTask)
  protected
    { Creates the log service on the worker's connection. }
    function CreateService(
      AConnection: TIBXServicesConnection): TIBXCustomService; override;
  public
    { Returns 'Server log'. }
    function Describe: string; override;
  end;

implementation

{------------------------------------------------------------------------------
  TServerLogService.Describe
  ----------------------------------------------------------------------------
  Returns 'Server log'.

  Notes:
    No database is named, because none is involved: the log belongs to the
    server. This is the one task here whose Validate has nothing to check.
------------------------------------------------------------------------------}
function TServerLogService.Describe: string;
begin
  Result := 'Server log';
end;

{------------------------------------------------------------------------------
  TServerLogService.CreateService
  ----------------------------------------------------------------------------
  Creates the log service on the worker's connection.

  Parameters:
    AConnection - The worker thread's services connection.

  Returns:
    The service to execute.
------------------------------------------------------------------------------}
function TServerLogService.CreateService(
  AConnection: TIBXServicesConnection): TIBXCustomService;
var
  Service: TIBXLogService;
begin
  Service := TIBXLogService.Create(nil);
  Service.ServicesConnection := AConnection;
  Result := Service;
end;

end.
