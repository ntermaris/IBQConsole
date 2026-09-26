{==============================================================================
  Unit:        ValidationService
  Purpose:     Validates and repairs a database through the Services API.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, ServiceRunner

  IBConsole equivalent: frmuDBValidation. FlameRobin equivalent:
  MaintenanceFrame.

  TWO DIFFERENT COMMANDS WITH SIMILAR NAMES
  Firebird has two validations and they are not interchangeable:

  - **full validation** (this class, vlmFull) needs *exclusive access* to the
    database. Every other attachment must be gone. It checks structures no
    online check can, and it is the one that can mend.
  - **online validation** (vlmOnline) runs while users are connected, checks
    tables and indexes, and repairs nothing.

  Offering only one of them would be wrong: the online one cannot find what a
  user reports as corruption, and the full one cannot be run on a live system
  at four in the afternoon.

  MENDING IS NOT A ROUTINE OPTION
  vloMendDatabase makes the engine mark damaged records as deleted so the
  database can at least be backed up. It loses data. It belongs behind a
  question, after a backup, and never in a default.
==============================================================================}
unit ValidationService;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IBXServices, ServiceRunner;

type
  { Which validation to run.

    vlmFull   - full validation; requires exclusive access
    vlmOnline - online validation; runs against a live database }
  TValidationMode = (vlmFull, vlmOnline);

  { What a full validation should do.

    vloCheckDatabase   - check structures without repairing
    vloIgnoreChecksum  - carry on past bad page checksums
    vloKillShadows     - remove unavailable shadow files
    vloMendDatabase    - mark damaged records deleted so the database can be
                         backed up. LOSES DATA.
    vloValidateDb      - validate record and page structures
    vloValidateFull    - validate record fragments as well; slower and
                         thorough }
  TValidationOption = (vloCheckDatabase, vloIgnoreChecksum, vloKillShadows,
    vloMendDatabase, vloValidateDb, vloValidateFull);
  TValidationOptions = set of TValidationOption;

type
  { TValidationService
    One validation run, full or online. }
  TValidationService = class(TServiceTask)
  private
    FDatabasePath: string;
    FMode: TValidationMode;
    FOptions: TValidationOptions;
    FIncludeTables: string;
    FExcludeTables: string;
    FIncludeIndexes: string;
    FExcludeIndexes: string;
    FLockTimeout: Integer;
  protected
    { Creates the full or online validation service, per Mode. }
    function CreateService(
      AConnection: TIBXServicesConnection): TIBXCustomService; override;
    { Applies the database name and the options for the chosen mode. }
    procedure Configure(AService: TIBXCustomService); override;
  public
    constructor Create;

    { Returns 'Full validation of <database>' or the online equivalent. }
    function Describe: string; override;

    { Returns why the validation cannot start, or an empty string. }
    function Validate: string; override;

    { True when this run can lose data, which is exactly when mending is on. }
    function IsDestructive: Boolean;

    { Full path of the database, or its alias. }
    property DatabasePath: string read FDatabasePath write FDatabasePath;

    { Which validation to run. }
    property Mode: TValidationMode read FMode write FMode;

    { What a full validation should do. Ignored in online mode. }
    property Options: TValidationOptions read FOptions write FOptions;

    { Online mode only: a regular expression naming the tables to check, or
      empty for all of them. }
    property IncludeTables: string read FIncludeTables write FIncludeTables;
    { Online mode only: a regular expression naming tables to skip. }
    property ExcludeTables: string read FExcludeTables write FExcludeTables;
    { Online mode only: a regular expression naming the indexes to check. }
    property IncludeIndexes: string read FIncludeIndexes write FIncludeIndexes;
    { Online mode only: a regular expression naming indexes to skip. }
    property ExcludeIndexes: string read FExcludeIndexes write FExcludeIndexes;
    { Online mode only: seconds to wait for a lock on each table. }
    property LockTimeout: Integer read FLockTimeout write FLockTimeout;
  end;

implementation

{------------------------------------------------------------------------------
  TValidationService.Create
  ----------------------------------------------------------------------------
  Creates a full validation that checks without repairing.
------------------------------------------------------------------------------}
constructor TValidationService.Create;
begin
  inherited Create;
  FMode := vlmFull;
  FOptions := [vloValidateDb];
  FLockTimeout := 10;
end;

{------------------------------------------------------------------------------
  TValidationService.Describe
  ----------------------------------------------------------------------------
  Returns a one-line description of this run.
------------------------------------------------------------------------------}
function TValidationService.Describe: string;
begin
  if FMode = vlmOnline then
    Result := 'Online validation of ' + FDatabasePath
  else if vloMendDatabase in FOptions then
    Result := 'Full validation and mend of ' + FDatabasePath
  else
    Result := 'Full validation of ' + FDatabasePath;
end;

{------------------------------------------------------------------------------
  TValidationService.Validate
  ----------------------------------------------------------------------------
  Returns why the validation cannot start, or an empty string.
------------------------------------------------------------------------------}
function TValidationService.Validate: string;
begin
  if Trim(FDatabasePath) = '' then
    Exit('No database has been named.');
  if (FMode = vlmFull) and (FOptions = []) then
    Exit('No validation option has been chosen.');
  Result := '';
end;

{------------------------------------------------------------------------------
  TValidationService.IsDestructive
  ----------------------------------------------------------------------------
  Returns True when this run can lose data.
------------------------------------------------------------------------------}
function TValidationService.IsDestructive: Boolean;
begin
  Result := (FMode = vlmFull) and (vloMendDatabase in FOptions);
end;

{------------------------------------------------------------------------------
  TValidationService.CreateService
  ----------------------------------------------------------------------------
  Creates the full or online validation service, per Mode.

  Parameters:
    AConnection - The worker thread's services connection.

  Returns:
    The service to execute.
------------------------------------------------------------------------------}
function TValidationService.CreateService(
  AConnection: TIBXServicesConnection): TIBXCustomService;
var
  Full: TIBXValidationService;
  Online: TIBXOnlineValidationService;
begin
  if FMode = vlmOnline then
  begin
    Online := TIBXOnlineValidationService.Create(nil);
    Online.ServicesConnection := AConnection;
    Result := Online;
  end
  else
  begin
    Full := TIBXValidationService.Create(nil);
    Full.ServicesConnection := AConnection;
    Result := Full;
  end;
end;

{------------------------------------------------------------------------------
  TValidationService.Configure
  ----------------------------------------------------------------------------
  Applies the database name and the options for the chosen mode.

  Parameters:
    AService - What CreateService returned.
------------------------------------------------------------------------------}
procedure TValidationService.Configure(AService: TIBXCustomService);
var
  Full: TIBXValidationService;
  Online: TIBXOnlineValidationService;
  IbxOptions: TValidateOptions;
begin
  if AService is TIBXOnlineValidationService then
  begin
    Online := TIBXOnlineValidationService(AService);
    Online.DatabaseName := FDatabasePath;
    Online.IncludeTables := FIncludeTables;
    Online.ExcludeTables := FExcludeTables;
    Online.IncludeIndexes := FIncludeIndexes;
    Online.ExcludeIndexes := FExcludeIndexes;
    Online.LockTimeout := FLockTimeout;
    Exit;
  end;

  Full := AService as TIBXValidationService;
  Full.DatabaseName := FDatabasePath;

  IbxOptions := [];
  if vloCheckDatabase in FOptions then
    Include(IbxOptions, CheckDB);
  if vloIgnoreChecksum in FOptions then
    Include(IbxOptions, IgnoreChecksum);
  if vloKillShadows in FOptions then
    Include(IbxOptions, KillShadows);
  if vloMendDatabase in FOptions then
    Include(IbxOptions, MendDB);
  if vloValidateDb in FOptions then
    Include(IbxOptions, ValidateDB);
  if vloValidateFull in FOptions then
    Include(IbxOptions, ValidateFull);
  Full.Options := IbxOptions;
end;

end.
