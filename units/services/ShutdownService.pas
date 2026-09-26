{==============================================================================
  Unit:        ShutdownService
  Purpose:     Shuts a database down, and brings it back online, through the
               Services API.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, ServiceRunner

  IBConsole equivalent: frmuDBShutdown and Database > Restart.
  FlameRobin equivalent: ShutdownFrame and StartupFrame.

  WHAT SHUTDOWN MEANS HERE
  Not "stop the server". The server keeps running; one database stops accepting
  work. That is what makes a full validation or a restore-over possible, and it
  is the piece of the Services API that people most often reach for a shell to
  do.

  THREE WAYS TO ASK, AND THEY ARE NOT INTERCHANGEABLE
  - sdmDenyAttachment: no NEW connections. Existing ones carry on to the end of
    their work. The polite one; use it, with a timeout, and it usually
    succeeds.
  - sdmDenyTransaction: no new transactions either. Existing transactions may
    finish.
  - sdmForced: everyone is thrown off when the timeout expires, their open
    transactions rolled back. The one that always works and the one that loses
    somebody's afternoon.

  The timeout is how long the server waits for the polite outcome before giving
  up. A timeout of zero with sdmForced is an immediate eviction.

  BRINGING IT BACK IS NOT AUTOMATIC
  A shut-down database stays shut down across a server restart. Somebody must
  bring it online, which is what TStartupService does, and forgetting that is
  the classic way to turn a five-minute maintenance window into an outage.
==============================================================================}
unit ShutdownService;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IBXServices, ServiceRunner;

type
  { How hard to insist.

    sdmDenyAttachment  - refuse new connections
    sdmDenyTransaction - refuse new transactions as well
    sdmForced          - evict everyone when the timeout expires }
  TShutdownMode = (sdmDenyAttachment, sdmDenyTransaction, sdmForced);

type
  { TShutdownService
    Takes one database offline. }
  TShutdownService = class(TServiceTask)
  private
    FDatabasePath: string;
    FMode: TShutdownMode;
    FTimeoutSeconds: Integer;
  protected
    { Creates the configuration service on the worker's connection. }
    function CreateService(
      AConnection: TIBXServicesConnection): TIBXCustomService; override;
    { Names the database. }
    procedure Configure(AService: TIBXCustomService); override;
    { Performs the shutdown; there is no output to stream. }
    procedure Run(AService: TIBXCustomService); override;
  public
    constructor Create;

    { Returns 'Shutdown of <database>'. }
    function Describe: string; override;
    { Returns why the shutdown cannot start, or an empty string. }
    function Validate: string; override;

    { Full path of the database, or its alias. }
    property DatabasePath: string read FDatabasePath write FDatabasePath;
    { How hard to insist. Defaults to the polite one. }
    property Mode: TShutdownMode read FMode write FMode;
    { Seconds to wait before the mode is enforced. Defaults to 60. }
    property TimeoutSeconds: Integer read FTimeoutSeconds write FTimeoutSeconds;
  end;

  { TStartupService
    Brings one database back online. }
  TStartupService = class(TServiceTask)
  private
    FDatabasePath: string;
  protected
    { Creates the configuration service on the worker's connection. }
    function CreateService(
      AConnection: TIBXServicesConnection): TIBXCustomService; override;
    { Names the database. }
    procedure Configure(AService: TIBXCustomService); override;
    { Brings the database online; there is no output to stream. }
    procedure Run(AService: TIBXCustomService); override;
  public
    { Returns 'Bring <database> online'. }
    function Describe: string; override;
    { Returns why the startup cannot begin, or an empty string. }
    function Validate: string; override;

    { Full path of the database, or its alias. }
    property DatabasePath: string read FDatabasePath write FDatabasePath;
  end;

implementation

{------------------------------------------------------------------------------
  TShutdownService.Create
  ----------------------------------------------------------------------------
  Creates a shutdown that refuses new connections and waits a minute.
------------------------------------------------------------------------------}
constructor TShutdownService.Create;
begin
  inherited Create;
  FMode := sdmDenyAttachment;
  FTimeoutSeconds := 60;
end;

{------------------------------------------------------------------------------
  TShutdownService.Describe
  ----------------------------------------------------------------------------
  Returns 'Shutdown of <database>'.
------------------------------------------------------------------------------}
function TShutdownService.Describe: string;
begin
  Result := 'Shutdown of ' + FDatabasePath;
  if FMode = sdmForced then
    Result := Result + ' (forced)';
end;

{------------------------------------------------------------------------------
  TShutdownService.Validate
  ----------------------------------------------------------------------------
  Returns why the shutdown cannot start, or an empty string.
------------------------------------------------------------------------------}
function TShutdownService.Validate: string;
begin
  if Trim(FDatabasePath) = '' then
    Exit('No database has been named.');
  if FTimeoutSeconds < 0 then
    Exit('The timeout cannot be negative.');
  Result := '';
end;

{------------------------------------------------------------------------------
  TShutdownService.CreateService
  ----------------------------------------------------------------------------
  Creates the configuration service on the worker's connection.

  Parameters:
    AConnection - The worker thread's services connection.

  Returns:
    The service to execute.
------------------------------------------------------------------------------}
function TShutdownService.CreateService(
  AConnection: TIBXServicesConnection): TIBXCustomService;
var
  Service: TIBXConfigService;
begin
  Service := TIBXConfigService.Create(nil);
  Service.ServicesConnection := AConnection;
  Result := Service;
end;

{------------------------------------------------------------------------------
  TShutdownService.Configure
  ----------------------------------------------------------------------------
  Names the database.

  Parameters:
    AService - What CreateService returned.
------------------------------------------------------------------------------}
procedure TShutdownService.Configure(AService: TIBXCustomService);
begin
  (AService as TIBXConfigService).DatabaseName := FDatabasePath;
end;

{------------------------------------------------------------------------------
  TShutdownService.Run
  ----------------------------------------------------------------------------
  Performs the shutdown; there is no output to stream.

  Parameters:
    AService - What CreateService returned, already configured.

  Notes:
    The call blocks for up to TimeoutSeconds while the server waits for the
    users to leave, which is precisely why this runs on the worker thread like
    everything else here.
------------------------------------------------------------------------------}
procedure TShutdownService.Run(AService: TIBXCustomService);
var
  Service: TIBXConfigService;
  IbxMode: TDBShutdownMode;
begin
  Service := AService as TIBXConfigService;

  case FMode of
    sdmForced:          IbxMode := Forced;
    sdmDenyTransaction: IbxMode := DenyTransaction;
  else
    IbxMode := DenyAttachment;
  end;

  Service.ShutdownDatabase(IbxMode, FTimeoutSeconds);
end;

{------------------------------------------------------------------------------
  TStartupService.Describe
  ----------------------------------------------------------------------------
  Returns 'Bring <database> online'.
------------------------------------------------------------------------------}
function TStartupService.Describe: string;
begin
  Result := 'Bring ' + FDatabasePath + ' online';
end;

{------------------------------------------------------------------------------
  TStartupService.Validate
  ----------------------------------------------------------------------------
  Returns why the startup cannot begin, or an empty string.
------------------------------------------------------------------------------}
function TStartupService.Validate: string;
begin
  if Trim(FDatabasePath) = '' then
    Exit('No database has been named.');
  Result := '';
end;

{------------------------------------------------------------------------------
  TStartupService.CreateService
  ----------------------------------------------------------------------------
  Creates the configuration service on the worker's connection.

  Parameters:
    AConnection - The worker thread's services connection.

  Returns:
    The service to execute.
------------------------------------------------------------------------------}
function TStartupService.CreateService(
  AConnection: TIBXServicesConnection): TIBXCustomService;
var
  Service: TIBXConfigService;
begin
  Service := TIBXConfigService.Create(nil);
  Service.ServicesConnection := AConnection;
  Result := Service;
end;

{------------------------------------------------------------------------------
  TStartupService.Configure
  ----------------------------------------------------------------------------
  Names the database.

  Parameters:
    AService - What CreateService returned.
------------------------------------------------------------------------------}
procedure TStartupService.Configure(AService: TIBXCustomService);
begin
  (AService as TIBXConfigService).DatabaseName := FDatabasePath;
end;

{------------------------------------------------------------------------------
  TStartupService.Run
  ----------------------------------------------------------------------------
  Brings the database online; there is no output to stream.

  Parameters:
    AService - What CreateService returned, already configured.
------------------------------------------------------------------------------}
procedure TStartupService.Run(AService: TIBXCustomService);
begin
  (AService as TIBXConfigService).BringDatabaseOnline;
end;

end.
