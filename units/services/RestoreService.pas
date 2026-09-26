{==============================================================================
  Unit:        RestoreService
  Purpose:     Restores a database from a backup through the Services API.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, ServiceRunner

  IBConsole equivalent: frmuDBRestore. FlameRobin equivalent: RestoreFrame.

  THE ONE DESTRUCTIVE COMMAND IN THE PROGRAM
  Every other maintenance command can be run again if it goes wrong. A restore
  with Replace overwrites a live database, and there is no undo. So:

  - the default is rdoCreateNew, which REFUSES to overwrite an existing file
  - rdoReplace is never set by this class, only by a caller that has asked the
    user in as many words
  - the database being restored over must not be attached; the server refuses
    otherwise, and that refusal is a safety feature, not an obstacle to work
    around

  Both the backup file and the database path are paths on the SERVER, for the
  same reason as in BackupService.
==============================================================================}
unit RestoreService;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IBXServices, ServiceRunner;

type
  { What a restore may be asked to do differently.

    rdoCreateNew        - create the database, failing if it already exists.
                          The safe default.
    rdoReplace          - overwrite an existing database. Destructive.
    rdoDeactivateIndexes- restore without building indexes; they are left
                          inactive for the user to activate afterwards. Used to
                          get a database with a corrupt index back at all.
    rdoNoShadow         - do not recreate the shadow files
    rdoNoValidityCheck  - do not restore validity constraints, so data that no
                          longer satisfies a CHECK can still be loaded
    rdoOneRelationAtATime - commit after each table; slower, but a failure
                          leaves what was already loaded
    rdoUseAllSpace      - fill data pages completely instead of leaving the
                          usual free space; smaller, and right for a database
                          that will be read-only
    rdoMetadataOnly     - schema without data }
  TDbRestoreOption = (rdoCreateNew, rdoReplace, rdoDeactivateIndexes,
    rdoNoShadow, rdoNoValidityCheck, rdoOneRelationAtATime, rdoUseAllSpace,
    rdoMetadataOnly);
  TDbRestoreOptions = set of TDbRestoreOption;

type
  { TRestoreService
    One restore. Fill in the properties, hand it to a TServiceRunner. }
  TRestoreService = class(TServiceTask)
  private
    FDatabasePath: string;
    FBackupFiles: TStringList;
    FOptions: TDbRestoreOptions;
    FVerbose: Boolean;
    FPageSize: Integer;
    FPageBuffers: Integer;
  protected
    { Creates the server-side restore service on the worker's connection. }
    function CreateService(
      AConnection: TIBXServicesConnection): TIBXCustomService; override;
    { Applies the paths and options to the service object. }
    procedure Configure(AService: TIBXCustomService); override;
  public
    constructor Create;
    destructor Destroy; override;

    { Returns 'Restore of <database>'. }
    function Describe: string; override;

    { Returns why the restore cannot start, or an empty string. }
    function Validate: string; override;

    { True when this restore will overwrite an existing database. }
    function IsDestructive: Boolean;

    { Sets a single backup file to restore from.

      Parameters:
        APath - Full path of the backup file, on the SERVER. }
    procedure SetSingleFile(const APath: string);

    { Full path the database is to be created at, on the SERVER. }
    property DatabasePath: string read FDatabasePath write FDatabasePath;

    { The backup file or files to read. }
    property BackupFiles: TStringList read FBackupFiles;

    { What the restore should do differently. Defaults to [rdoCreateNew]. }
    property Options: TDbRestoreOptions read FOptions write FOptions;

    { True to have the server report every step. }
    property Verbose: Boolean read FVerbose write FVerbose;

    { Page size for the new database, 0 to keep the backup's. }
    property PageSize: Integer read FPageSize write FPageSize;

    { Default page-buffer cache for the new database, 0 to keep the backup's. }
    property PageBuffers: Integer read FPageBuffers write FPageBuffers;
  end;

implementation

{------------------------------------------------------------------------------
  TRestoreService.Create
  ----------------------------------------------------------------------------
  Creates a restore that will create a new database and refuse to overwrite.
------------------------------------------------------------------------------}
constructor TRestoreService.Create;
begin
  inherited Create;
  FBackupFiles := TStringList.Create;
  FOptions := [rdoCreateNew];
  FVerbose := True;
end;

{------------------------------------------------------------------------------
  TRestoreService.Destroy
  ----------------------------------------------------------------------------
  Releases the file list.
------------------------------------------------------------------------------}
destructor TRestoreService.Destroy;
begin
  FreeAndNil(FBackupFiles);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TRestoreService.Describe
  ----------------------------------------------------------------------------
  Returns 'Restore of <database>'.
------------------------------------------------------------------------------}
function TRestoreService.Describe: string;
begin
  Result := 'Restore of ' + FDatabasePath;
  if IsDestructive then
    Result := Result + ' (replacing the existing database)';
end;

{------------------------------------------------------------------------------
  TRestoreService.Validate
  ----------------------------------------------------------------------------
  Returns why the restore cannot start, or an empty string.
------------------------------------------------------------------------------}
function TRestoreService.Validate: string;
begin
  if Trim(FDatabasePath) = '' then
    Exit('No database has been named.');
  if FBackupFiles.Count = 0 then
    Exit('No backup file has been named.');
  if (rdoCreateNew in FOptions) and (rdoReplace in FOptions) then
    Exit('Create and replace cannot both be asked for.');
  Result := '';
end;

{------------------------------------------------------------------------------
  TRestoreService.IsDestructive
  ----------------------------------------------------------------------------
  Returns True when this restore will overwrite an existing database.

  Notes:
    Exists so a dialog can word its confirmation honestly, and so the model can
    refuse to run one without having asked.
------------------------------------------------------------------------------}
function TRestoreService.IsDestructive: Boolean;
begin
  Result := rdoReplace in FOptions;
end;

{------------------------------------------------------------------------------
  TRestoreService.SetSingleFile
  ----------------------------------------------------------------------------
  Sets a single backup file to restore from.

  Parameters:
    APath - Full path of the backup file, on the SERVER.
------------------------------------------------------------------------------}
procedure TRestoreService.SetSingleFile(const APath: string);
begin
  FBackupFiles.Clear;
  if Trim(APath) <> '' then
    FBackupFiles.Add(APath);
end;

{------------------------------------------------------------------------------
  TRestoreService.CreateService
  ----------------------------------------------------------------------------
  Creates the server-side restore service on the worker's connection.

  Parameters:
    AConnection - The worker thread's services connection.

  Returns:
    The service to execute.
------------------------------------------------------------------------------}
function TRestoreService.CreateService(
  AConnection: TIBXServicesConnection): TIBXCustomService;
var
  Service: TIBXServerSideRestoreService;
begin
  Service := TIBXServerSideRestoreService.Create(nil);
  Service.ServicesConnection := AConnection;
  Result := Service;
end;

{------------------------------------------------------------------------------
  TRestoreService.Configure
  ----------------------------------------------------------------------------
  Applies the paths and options to the service object.

  Parameters:
    AService - What CreateService returned.

  Notes:
    DatabaseFiles, not DatabaseName: a restore may create a multi-file
    database, so IBX takes the target as a list. A single entry is the normal
    case and is what SetSingleFile's counterpart here produces.
------------------------------------------------------------------------------}
procedure TRestoreService.Configure(AService: TIBXCustomService);
var
  Service: TIBXServerSideRestoreService;
  IbxOptions: IBXServices.TRestoreOptions;
begin
  Service := AService as TIBXServerSideRestoreService;

  Service.DatabaseFiles.Clear;
  Service.DatabaseFiles.Add(FDatabasePath);
  Service.BackupFiles.Assign(FBackupFiles);
  Service.Verbose := FVerbose;
  if FPageSize > 0 then
    Service.PageSize := FPageSize;
  if FPageBuffers > 0 then
    Service.PageBuffers := FPageBuffers;

  IbxOptions := [];
  if rdoCreateNew in FOptions then
    Include(IbxOptions, IBXServices.CreateNewDB);
  if rdoReplace in FOptions then
    Include(IbxOptions, IBXServices.Replace);
  if rdoDeactivateIndexes in FOptions then
    Include(IbxOptions, IBXServices.DeactivateIndexes);
  if rdoNoShadow in FOptions then
    Include(IbxOptions, IBXServices.NoShadow);
  if rdoNoValidityCheck in FOptions then
    Include(IbxOptions, IBXServices.NoValidityCheck);
  if rdoOneRelationAtATime in FOptions then
    Include(IbxOptions, IBXServices.OneRelationAtATime);
  if rdoUseAllSpace in FOptions then
    Include(IbxOptions, IBXServices.UseAllSpace);
  if rdoMetadataOnly in FOptions then
    Include(IbxOptions, IBXServices.RestoreMetaDataOnly);
  Service.Options := IbxOptions;
end;

end.
