{==============================================================================
  Unit:        SweepService
  Purpose:     Sweeps a database through the Services API.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, ServiceRunner

  IBConsole equivalent: Maintenance > Sweep.

  WHAT A SWEEP IS FOR
  Firebird keeps the old versions of updated records until it is sure nobody
  can still see them. Records left behind by a transaction that was rolled back
  or never finished are not cleaned up by ordinary work, and they accumulate:
  the gap between the oldest interesting transaction and the newest grows, and
  every read has more versions to walk past. A sweep walks the whole database
  and removes them.

  It is a *read* of every page, so it is slow on a large database and it
  competes with real work. It is not dangerous - nothing is lost - but it is
  not something to fire during business hours on a 2.6 GB database.

  A sweep is a repair action with the sweep flag, which is why this looks like
  a stripped-down validation: that is what the Services API makes of it.
==============================================================================}
unit SweepService;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IBXServices, ServiceRunner;

type
  { TSweepService
    One sweep of one database. }
  TSweepService = class(TServiceTask)
  private
    FDatabasePath: string;
  protected
    { Creates the repair service used to sweep. }
    function CreateService(
      AConnection: TIBXServicesConnection): TIBXCustomService; override;
    { Names the database and asks for a sweep. }
    procedure Configure(AService: TIBXCustomService); override;
  public
    { Returns 'Sweep of <database>'. }
    function Describe: string; override;
    { Returns why the sweep cannot start, or an empty string. }
    function Validate: string; override;

    { Full path of the database, or its alias. }
    property DatabasePath: string read FDatabasePath write FDatabasePath;
  end;

implementation

{------------------------------------------------------------------------------
  TSweepService.Describe
  ----------------------------------------------------------------------------
  Returns 'Sweep of <database>'.
------------------------------------------------------------------------------}
function TSweepService.Describe: string;
begin
  Result := 'Sweep of ' + FDatabasePath;
end;

{------------------------------------------------------------------------------
  TSweepService.Validate
  ----------------------------------------------------------------------------
  Returns why the sweep cannot start, or an empty string.
------------------------------------------------------------------------------}
function TSweepService.Validate: string;
begin
  if Trim(FDatabasePath) = '' then
    Exit('No database has been named.');
  Result := '';
end;

{------------------------------------------------------------------------------
  TSweepService.CreateService
  ----------------------------------------------------------------------------
  Creates the repair service used to sweep.

  Parameters:
    AConnection - The worker thread's services connection.

  Returns:
    The service to execute.
------------------------------------------------------------------------------}
function TSweepService.CreateService(
  AConnection: TIBXServicesConnection): TIBXCustomService;
var
  Service: TIBXValidationService;
begin
  Service := TIBXValidationService.Create(nil);
  Service.ServicesConnection := AConnection;
  Result := Service;
end;

{------------------------------------------------------------------------------
  TSweepService.Configure
  ----------------------------------------------------------------------------
  Names the database and asks for a sweep.

  Parameters:
    AService - What CreateService returned.
------------------------------------------------------------------------------}
procedure TSweepService.Configure(AService: TIBXCustomService);
var
  Service: TIBXValidationService;
begin
  Service := AService as TIBXValidationService;
  Service.DatabaseName := FDatabasePath;
  Service.Options := [SweepDB];
end;

end.
