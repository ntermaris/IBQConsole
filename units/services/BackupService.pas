{==============================================================================
  Unit:        BackupService
  Purpose:     Backs a database up through the Services API, on the server.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, ServiceRunner

  IBConsole equivalent: frmuDBBackup. FlameRobin equivalent: BackupFrame.

  SERVER-SIDE, NOT CLIENT-SIDE
  IBX offers both. Server-side writes the backup file on the server machine
  with the server's own privileges; client-side streams it back over the wire
  to a file here. Server-side is what gbak and IBConsole do, it is far faster
  over a network, and it is what a scheduled backup on the server needs.

  The consequence is worth stating plainly to the user, and the dialog does:
  **the backup path is a path on the server**, not on this machine. A user who
  types D:\backups on a Linux server gets an error from the server, and that is
  the correct behaviour - guessing a translation would put the backup somewhere
  nobody expects.

  OPTIONS ARE OUR OWN ENUM
  TBackupOption belongs to IBX. Repeating it here costs a mapping function and
  keeps IBX out of every dialog that offers a checkbox, which is the layering
  rule the whole program is built on.
==============================================================================}
unit BackupService;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IBXServices, ServiceRunner;

type
  { What a backup may be asked to do differently. Named TDbBackupOption rather
    than TBackupOption because IBX already has a type by that name and the two
    would shadow each other in this unit, which is exactly the confusion the
    mapping below exists to prevent.

    bkoIgnoreChecksums    - carry on past a bad page checksum
    bkoIgnoreLimbo        - ignore transactions left in limbo
    bkoMetadataOnly       - schema without a single row of data
    bkoNoGarbageCollect   - do not collect garbage while reading; faster, and
                            the usual choice for a routine backup
    bkoOldMetadataDesc    - write metadata in the pre-Firebird description form
    bkoNonTransportable   - platform-specific format; smaller and faster, but
                            restorable only on the same architecture
    bkoConvertExtTables   - turn external tables into internal ones
    bkoNoDbTriggers       - do not fire database-level triggers }
  TDbBackupOption = (bkoIgnoreChecksums, bkoIgnoreLimbo, bkoMetadataOnly,
    bkoNoGarbageCollect, bkoOldMetadataDesc, bkoNonTransportable,
    bkoConvertExtTables, bkoNoDbTriggers);
  TDbBackupOptions = set of TDbBackupOption;

type
  { TBackupService
    One backup. Fill in the properties, hand it to a TServiceRunner. }
  TBackupService = class(TServiceTask)
  private
    FDatabasePath: string;
    FBackupFiles: TStringList;
    FOptions: TDbBackupOptions;
    FVerbose: Boolean;
    FBlockingFactor: Integer;
  protected
    { Creates the server-side backup service on the worker's connection. }
    function CreateService(
      AConnection: TIBXServicesConnection): TIBXCustomService; override;
    { Applies the paths and options to the service object. }
    procedure Configure(AService: TIBXCustomService); override;
  public
    constructor Create;
    destructor Destroy; override;

    { Returns 'Backup of <database>'. }
    function Describe: string; override;

    { Returns why the backup cannot start, or an empty string. }
    function Validate: string; override;

    { Sets a single backup file, the common case.

      Parameters:
        APath - Full path of the backup file, on the SERVER. }
    procedure SetSingleFile(const APath: string);

    { Full path of the database to back up, or its alias. }
    property DatabasePath: string read FDatabasePath write FDatabasePath;

    { Backup files, one per line, in the form the Services API wants:
      either 'path' or 'path=size', where size lets a backup be split across
      several files. Use SetSingleFile unless splitting. }
    property BackupFiles: TStringList read FBackupFiles;

    { What the backup should do differently. }
    property Options: TDbBackupOptions read FOptions write FOptions;

    { True to have the server report every step. Left on by default: the
      output IS the reassurance that a long backup is progressing. }
    property Verbose: Boolean read FVerbose write FVerbose;

    { Backup blocking factor, 0 to let the server decide. }
    property BlockingFactor: Integer read FBlockingFactor write FBlockingFactor;
  end;

implementation

{------------------------------------------------------------------------------
  TBackupService.Create
  ----------------------------------------------------------------------------
  Creates a backup with no files chosen and verbose output on.
------------------------------------------------------------------------------}
constructor TBackupService.Create;
begin
  inherited Create;
  FBackupFiles := TStringList.Create;
  FVerbose := True;
end;

{------------------------------------------------------------------------------
  TBackupService.Destroy
  ----------------------------------------------------------------------------
  Releases the file list.
------------------------------------------------------------------------------}
destructor TBackupService.Destroy;
begin
  FreeAndNil(FBackupFiles);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TBackupService.Describe
  ----------------------------------------------------------------------------
  Returns 'Backup of <database>'.
------------------------------------------------------------------------------}
function TBackupService.Describe: string;
begin
  Result := 'Backup of ' + FDatabasePath;
end;

{------------------------------------------------------------------------------
  TBackupService.Validate
  ----------------------------------------------------------------------------
  Returns why the backup cannot start, or an empty string.

  Notes:
    Only what can be judged from here is checked. Whether the server can write
    to the path is the server's answer to give, and it gives a good one.
------------------------------------------------------------------------------}
function TBackupService.Validate: string;
begin
  if Trim(FDatabasePath) = '' then
    Exit('No database has been named.');
  if FBackupFiles.Count = 0 then
    Exit('No backup file has been named.');
  Result := '';
end;

{------------------------------------------------------------------------------
  TBackupService.SetSingleFile
  ----------------------------------------------------------------------------
  Sets a single backup file, the common case.

  Parameters:
    APath - Full path of the backup file, on the SERVER.
------------------------------------------------------------------------------}
procedure TBackupService.SetSingleFile(const APath: string);
begin
  FBackupFiles.Clear;
  if Trim(APath) <> '' then
    FBackupFiles.Add(APath);
end;

{------------------------------------------------------------------------------
  TBackupService.CreateService
  ----------------------------------------------------------------------------
  Creates the server-side backup service on the worker's connection.

  Parameters:
    AConnection - The worker thread's services connection.

  Returns:
    The service to execute.
------------------------------------------------------------------------------}
function TBackupService.CreateService(
  AConnection: TIBXServicesConnection): TIBXCustomService;
var
  Service: TIBXServerSideBackupService;
begin
  Service := TIBXServerSideBackupService.Create(nil);
  Service.ServicesConnection := AConnection;
  Result := Service;
end;

{------------------------------------------------------------------------------
  TBackupService.Configure
  ----------------------------------------------------------------------------
  Applies the paths and options to the service object.

  Parameters:
    AService - What CreateService returned.
------------------------------------------------------------------------------}
procedure TBackupService.Configure(AService: TIBXCustomService);
var
  Service: TIBXServerSideBackupService;
  IbxOptions: IBXServices.TBackupOptions;
begin
  Service := AService as TIBXServerSideBackupService;

  Service.DatabaseName := FDatabasePath;
  Service.BackupFiles.Assign(FBackupFiles);
  Service.Verbose := FVerbose;
  if FBlockingFactor > 0 then
    Service.BlockingFactor := FBlockingFactor;

  IbxOptions := [];
  if bkoIgnoreChecksums in FOptions then
    Include(IbxOptions, IBXServices.IgnoreChecksums);
  if bkoIgnoreLimbo in FOptions then
    Include(IbxOptions, IBXServices.IgnoreLimbo);
  if bkoMetadataOnly in FOptions then
    Include(IbxOptions, IBXServices.MetadataOnly);
  if bkoNoGarbageCollect in FOptions then
    Include(IbxOptions, IBXServices.NoGarbageCollection);
  if bkoOldMetadataDesc in FOptions then
    Include(IbxOptions, IBXServices.OldMetadataDesc);
  if bkoNonTransportable in FOptions then
    Include(IbxOptions, IBXServices.NonTransportable);
  if bkoConvertExtTables in FOptions then
    Include(IbxOptions, IBXServices.ConvertExtTables);
  if bkoNoDbTriggers in FOptions then
    Include(IbxOptions, IBXServices.NoDBTriggers);
  Service.Options := IbxOptions;
end;

end.
