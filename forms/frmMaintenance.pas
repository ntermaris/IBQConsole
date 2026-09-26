{==============================================================================
  Unit:        frmMaintenance
  Purpose:     One dialog for every Services API maintenance command: backup,
               restore, validation, sweep, statistics and the server log.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  LCL, LanguageHandle, MetaDatabase, ServerRegistration,
               ConnectionProfile, ServiceRunner and the task units

  WHY ONE DIALOG AND NOT SIX
  IBConsole had frmuDBBackup, frmuDBRestore, frmuDBValidation and the rest,
  and every one of them re-implemented the same three things: an output pane,
  a Start button that becomes a Cancel button, and the question of what to do
  when the user closes the window while the work is running.

  Here those three things exist once. What differs between the commands is a
  page of options, and that is exactly what a page control is for. Each page is
  in the designer; the dialog shows the one it was opened for and hides the
  rest, which is rule §7.2's "all of them in the designer, toggle TabVisible".

  THE PATHS ARE THE SERVER'S
  Every file name on these pages is a path on the SERVER. The dialog says so
  and does not offer a file browser for them, because browsing this machine
  would produce a path that means something else - or nothing - over there.
  The one exception is Save output, which writes a file here.
==============================================================================}
unit frmMaintenance;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs,
  LanguageHandle, AppLog, MetaDatabase, ServerRegistration, ConnectionProfile,
  ServiceRunner, BackupService, RestoreService, ValidationService,
  SweepService, StatisticsService, ServerLogService;

type
  { Which command the dialog was opened for. }
  TMaintenanceCommand = (mcBackup, mcRestore, mcValidate, mcSweep,
    mcStatistics, mcServerLog);

  { TfrmIbqMaintenance
    The maintenance dialog. }
  TfrmIbqMaintenance = class(TForm, ILocalizable)
    pnlHeader: TPanel;
    lblServer: TLabel;
    lblServerValue: TLabel;
    lblUser: TLabel;
    edtUser: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblServerPaths: TLabel;

    pgcCommand: TPageControl;

    tabBackup: TTabSheet;
    lblBackupDatabase: TLabel;
    edtBackupDatabase: TEdit;
    lblBackupFile: TLabel;
    edtBackupFile: TEdit;
    grpBackupOptions: TGroupBox;
    chkBackupNoGarbage: TCheckBox;
    chkBackupMetadataOnly: TCheckBox;
    chkBackupIgnoreChecksums: TCheckBox;
    chkBackupIgnoreLimbo: TCheckBox;
    chkBackupNonTransportable: TCheckBox;
    chkBackupConvertExternal: TCheckBox;
    chkBackupNoDbTriggers: TCheckBox;
    chkBackupVerbose: TCheckBox;

    tabRestore: TTabSheet;
    lblRestoreSource: TLabel;
    edtRestoreSource: TEdit;
    lblRestoreTarget: TLabel;
    edtRestoreTarget: TEdit;
    grpRestoreOptions: TGroupBox;
    chkRestoreReplace: TCheckBox;
    chkRestoreDeactivateIndexes: TCheckBox;
    chkRestoreNoShadow: TCheckBox;
    chkRestoreNoValidity: TCheckBox;
    chkRestoreOneRelation: TCheckBox;
    chkRestoreUseAllSpace: TCheckBox;
    chkRestoreMetadataOnly: TCheckBox;
    lblPageSize: TLabel;
    edtPageSize: TEdit;
    lblPageBuffers: TLabel;
    edtPageBuffers: TEdit;

    tabValidate: TTabSheet;
    lblValidateDatabase: TLabel;
    edtValidateDatabase: TEdit;
    rgpValidateMode: TRadioGroup;
    grpValidateOptions: TGroupBox;
    chkValidateStructures: TCheckBox;
    chkValidateFull: TCheckBox;
    chkValidateCheckDb: TCheckBox;
    chkValidateIgnoreChecksum: TCheckBox;
    chkValidateKillShadows: TCheckBox;
    chkValidateMend: TCheckBox;
    lblValidateWarning: TLabel;

    tabSweep: TTabSheet;
    lblSweepDatabase: TLabel;
    edtSweepDatabase: TEdit;
    lblSweepExplain: TLabel;

    tabStatistics: TTabSheet;
    lblStatsDatabase: TLabel;
    edtStatsDatabase: TEdit;
    grpStatsOptions: TGroupBox;
    chkStatsHeader: TCheckBox;
    chkStatsIndex: TCheckBox;
    chkStatsData: TCheckBox;
    chkStatsSystem: TCheckBox;

    tabServerLog: TTabSheet;
    lblServerLogExplain: TLabel;

    splOutput: TSplitter;
    pnlOutput: TPanel;
    memOutput: TMemo;
    pnlButtons: TPanel;
    lblStatus: TLabel;
    btnStart: TButton;
    btnCancel: TButton;
    btnSave: TButton;
    btnClose: TButton;
    dlgSaveOutput: TSaveDialog;

    procedure FormCreate(Sender: TObject);
    procedure StatsOptionClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure btnStartClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure rgpValidateModeClick(Sender: TObject);
  private
    FUpdatingStatsOptions: Boolean;
    FRegistration: TServerRegistration;
    FDatabasePath: string;
    FCommand: TMaintenanceCommand;
    FRunner: TServiceRunner;
    function BuildTask: TServiceTask;
    function BuildBackup: TServiceTask;
    function BuildRestore: TServiceTask;
    function BuildValidation: TServiceTask;
    function BuildStatistics: TServiceTask;
    procedure ShowOnlyTabFor(ACommand: TMaintenanceCommand);
    procedure SetRunningState(ARunning: Boolean);
    procedure HandleLine(Sender: TObject; const ALine: string);
    procedure HandleFinished(Sender: TObject; ASuccess, ACancelled: Boolean;
      const AError: string);
    function ConfirmDestructive: Boolean;
  public
    destructor Destroy; override;

    { Prepares the dialog for one command.

      Parameters:
        ARegistration - The server the command runs on.
        ADatabasePath - Path of the database, as the SERVER knows it. Empty for
                        the server log, which names no database.
        AUserName     - The user to attach as.
        ACommand      - Which command. }
    procedure PrepareFor(ARegistration: TServerRegistration;
      const ADatabasePath, AUserName: string; ACommand: TMaintenanceCommand);

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

{ Shows the maintenance dialog for a database command.

  Parameters:
    ADatabase - The database the command runs against. Its registration and
                path are taken from it; it need not be connected, and for a
                restore over it, it had better not be.
    ACommand  - Which command. }
procedure MaintenanceDialog(ADatabase: TMetaDatabase;
  ACommand: TMaintenanceCommand);

{ Shows the maintenance dialog for a server command.

  Parameters:
    ARegistration - The server.
    AUserName     - The user to attach as.
    ACommand      - Which command; only the ones that name no database make
                    sense here. }
procedure ServerMaintenanceDialog(ARegistration: TServerRegistration;
  const AUserName: string; ACommand: TMaintenanceCommand);

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  MaintenanceDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure MaintenanceDialog(ADatabase: TMetaDatabase;
  ACommand: TMaintenanceCommand);
var
  Dialog: TfrmIbqMaintenance;
begin
  if (ADatabase = nil) or (ADatabase.Profile = nil) then
    Exit;

  if not ADatabase.Profile.HasServer then
  begin
    MessageDlg(LangStr('frmMaintenance.caption', 'Maintenance'),
      LangStr('msg.noServicesForEmbedded',
        'An embedded database has no server, so it has no maintenance ' +
        'services. Register it under a server to back it up.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Dialog := TfrmIbqMaintenance.Create(nil);
  try
    Dialog.PrepareFor(ADatabase.ServerReg, ADatabase.Profile.DatabasePath,
      ADatabase.Profile.UserName, ACommand);
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  ServerMaintenanceDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure ServerMaintenanceDialog(ARegistration: TServerRegistration;
  const AUserName: string; ACommand: TMaintenanceCommand);
var
  Dialog: TfrmIbqMaintenance;
begin
  if ARegistration = nil then
    Exit;

  Dialog := TfrmIbqMaintenance.Create(nil);
  try
    Dialog.PrepareFor(ARegistration, '', AUserName, ACommand);
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.Destroy
  ----------------------------------------------------------------------------
  Stops a running task before releasing anything.
------------------------------------------------------------------------------}
destructor TfrmIbqMaintenance.Destroy;
begin
  FreeAndNil(FRunner);        // cancels and waits; see TServiceRunner.Destroy
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.LoadLangStr;
begin
  Caption := LangStr('frmMaintenance.caption', 'Maintenance');

  lblServer.Caption := LangStr('maint.server', 'Server');
  lblUser.Caption := LangStr('maint.user', 'User');
  lblPassword.Caption := LangStr('maint.password', 'Password');
  lblServerPaths.Caption := LangStr('maint.serverPaths',
    'Every file name below is a path on the server, not on this machine.');

  tabBackup.Caption := LangStr('maint.backup', 'Backup');
  lblBackupDatabase.Caption := LangStr('maint.database', 'Database');
  lblBackupFile.Caption := LangStr('maint.backupFile', 'Backup file');
  grpBackupOptions.Caption := LangStr('maint.options', 'Options');
  chkBackupNoGarbage.Caption := LangStr('maint.bkNoGarbage',
    'No garbage collection (faster)');
  chkBackupMetadataOnly.Caption := LangStr('maint.bkMetadataOnly',
    'Metadata only, no data');
  chkBackupIgnoreChecksums.Caption := LangStr('maint.bkIgnoreChecksums',
    'Ignore bad checksums');
  chkBackupIgnoreLimbo.Caption := LangStr('maint.bkIgnoreLimbo',
    'Ignore limbo transactions');
  chkBackupNonTransportable.Caption := LangStr('maint.bkNonTransportable',
    'Non-transportable format');
  chkBackupConvertExternal.Caption := LangStr('maint.bkConvertExternal',
    'Convert external tables to internal');
  chkBackupNoDbTriggers.Caption := LangStr('maint.bkNoDbTriggers',
    'Do not fire database triggers');
  chkBackupVerbose.Caption := LangStr('maint.verbose', 'Report every step');

  tabRestore.Caption := LangStr('maint.restore', 'Restore');
  lblRestoreSource.Caption := LangStr('maint.backupFile', 'Backup file');
  lblRestoreTarget.Caption := LangStr('maint.database', 'Database');
  grpRestoreOptions.Caption := LangStr('maint.options', 'Options');
  chkRestoreReplace.Caption := LangStr('maint.rsReplace',
    'Replace the existing database (destroys it)');
  chkRestoreDeactivateIndexes.Caption := LangStr('maint.rsDeactivateIndexes',
    'Leave indexes inactive');
  chkRestoreNoShadow.Caption := LangStr('maint.rsNoShadow',
    'Do not recreate shadows');
  chkRestoreNoValidity.Caption := LangStr('maint.rsNoValidity',
    'Do not restore validity constraints');
  chkRestoreOneRelation.Caption := LangStr('maint.rsOneRelation',
    'Commit after each table');
  chkRestoreUseAllSpace.Caption := LangStr('maint.rsUseAllSpace',
    'Fill pages completely');
  chkRestoreMetadataOnly.Caption := LangStr('maint.rsMetadataOnly',
    'Metadata only, no data');
  lblPageSize.Caption := LangStr('maint.pageSize', 'Page size');
  lblPageBuffers.Caption := LangStr('maint.pageBuffers', 'Page buffers');

  tabValidate.Caption := LangStr('maint.validate', 'Validation');
  lblValidateDatabase.Caption := LangStr('maint.database', 'Database');
  rgpValidateMode.Caption := LangStr('maint.validateMode', 'Kind');
  grpValidateOptions.Caption := LangStr('maint.options', 'Options');
  chkValidateStructures.Caption := LangStr('maint.vlStructures',
    'Validate record and page structures');
  chkValidateFull.Caption := LangStr('maint.vlFull',
    'Validate record fragments too (slower)');
  chkValidateCheckDb.Caption := LangStr('maint.vlCheckDb',
    'Check without repairing');
  chkValidateIgnoreChecksum.Caption := LangStr('maint.vlIgnoreChecksum',
    'Ignore bad checksums');
  chkValidateKillShadows.Caption := LangStr('maint.vlKillShadows',
    'Remove unavailable shadows');
  chkValidateMend.Caption := LangStr('maint.vlMend',
    'Mend: mark damaged records deleted (LOSES DATA)');
  lblValidateWarning.Caption := LangStr('maint.vlWarning',
    'A full validation needs exclusive access: every other connection must be ' +
    'gone. Online validation runs against a live database but repairs nothing.');

  tabSweep.Caption := LangStr('maint.sweep', 'Sweep');
  lblSweepDatabase.Caption := LangStr('maint.database', 'Database');
  lblSweepExplain.Caption := LangStr('maint.sweepExplain',
    'A sweep removes the record versions left behind by transactions that ' +
    'never finished. It reads every page, so it is slow on a large database ' +
    'and competes with real work - but it loses nothing.');

  tabStatistics.Caption := LangStr('maint.statistics', 'Statistics');
  lblStatsDatabase.Caption := LangStr('maint.database', 'Database');
  grpStatsOptions.Caption := LangStr('maint.options', 'Options');
  chkStatsHeader.Caption := LangStr('maint.stHeader',
    'Header page (fast, and usually enough)');
  chkStatsIndex.Caption := LangStr('maint.stIndex', 'Index statistics');
  chkStatsData.Caption := LangStr('maint.stData',
    'Data pages (reads the whole database)');
  chkStatsSystem.Caption := LangStr('maint.stSystem',
    'Include system tables');

  tabServerLog.Caption := LangStr('maint.serverLog', 'Server log');
  lblServerLogExplain.Caption := LangStr('maint.serverLogExplain',
    'Fetches firebird.log from the server. The whole file is read: the ' +
    'Services API offers no way to ask for only the last few lines.');

  btnStart.Caption := LangStr('maint.start', 'Start');
  btnCancel.Caption := LangStr('maint.cancel', 'Cancel');
  btnSave.Caption := LangStr('maint.saveOutput', 'Save output...');
  btnClose.Caption := LangStr('btnClose.caption', 'Close');
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.PrepareFor
  ----------------------------------------------------------------------------
  Prepares the dialog for one command.

  Parameters:
    ARegistration - The server the command runs on.
    ADatabasePath - Path of the database, as the SERVER knows it.
    AUserName     - The user to attach as.
    ACommand      - Which command.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.PrepareFor(ARegistration: TServerRegistration;
  const ADatabasePath, AUserName: string; ACommand: TMaintenanceCommand);
var
  Suggested: string;
begin
  FRegistration := ARegistration;
  FDatabasePath := ADatabasePath;
  FCommand := ACommand;

  lblServerValue.Caption := ARegistration.TreeCaption;
  edtUser.Text := AUserName;
  if edtUser.Text = '' then
    edtUser.Text := ARegistration.UserName;
  if edtUser.Text = '' then
    edtUser.Text := 'SYSDBA';

  edtBackupDatabase.Text := ADatabasePath;
  edtValidateDatabase.Text := ADatabasePath;
  edtSweepDatabase.Text := ADatabasePath;
  edtStatsDatabase.Text := ADatabasePath;
  edtRestoreTarget.Text := ADatabasePath;

  { A backup file suggested next to the database, with the database's own name.
    It is a guess about the server's file system, so it is only a suggestion in
    an editable field - never applied silently. }
  if ADatabasePath <> '' then
  begin
    Suggested := ChangeFileExt(ADatabasePath, '.fbk');
    edtBackupFile.Text := Suggested;
    edtRestoreSource.Text := Suggested;
  end;

  ShowOnlyTabFor(ACommand);
  SetRunningState(False);
  lblStatus.Caption := '';
  memOutput.Clear;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.ShowOnlyTabFor
  ----------------------------------------------------------------------------
  Shows the page belonging to ACommand and hides the others.

  Parameters:
    ACommand - Which command the dialog was opened for.

  Notes:
    Every page is in the designer; only its visibility varies. A page built at
    run time could not be laid out in the IDE, which is the rule this program
    follows everywhere (§7.1).
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.ShowOnlyTabFor(ACommand: TMaintenanceCommand);
begin
  tabBackup.TabVisible := ACommand = mcBackup;
  tabRestore.TabVisible := ACommand = mcRestore;
  tabValidate.TabVisible := ACommand = mcValidate;
  tabSweep.TabVisible := ACommand = mcSweep;
  tabStatistics.TabVisible := ACommand = mcStatistics;
  tabServerLog.TabVisible := ACommand = mcServerLog;

  case ACommand of
    mcBackup:     pgcCommand.ActivePage := tabBackup;
    mcRestore:    pgcCommand.ActivePage := tabRestore;
    mcValidate:   pgcCommand.ActivePage := tabValidate;
    mcSweep:      pgcCommand.ActivePage := tabSweep;
    mcStatistics: pgcCommand.ActivePage := tabStatistics;
    mcServerLog:  pgcCommand.ActivePage := tabServerLog;
  end;

  Caption := Caption + ' - ' + pgcCommand.ActivePage.Caption;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.rgpValidateModeClick
  ----------------------------------------------------------------------------
  Enables the full-validation options only in full mode.

  Notes:
    Online validation ignores them entirely. Leaving them enabled would suggest
    a mend that will not happen, which is the worst kind of wrong.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.rgpValidateModeClick(Sender: TObject);
begin
  grpValidateOptions.Enabled := rgpValidateMode.ItemIndex = 0;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.BuildBackup
  ----------------------------------------------------------------------------
  Builds the backup task from the page.

  Returns:
    The task, for the runner to own.
------------------------------------------------------------------------------}
function TfrmIbqMaintenance.BuildBackup: TServiceTask;
var
  Task: TBackupService;
  Options: TDbBackupOptions;
begin
  Task := TBackupService.Create;
  Task.DatabasePath := Trim(edtBackupDatabase.Text);
  Task.SetSingleFile(Trim(edtBackupFile.Text));
  Task.Verbose := chkBackupVerbose.Checked;

  Options := [];
  if chkBackupNoGarbage.Checked then Include(Options, bkoNoGarbageCollect);
  if chkBackupMetadataOnly.Checked then Include(Options, bkoMetadataOnly);
  if chkBackupIgnoreChecksums.Checked then Include(Options, bkoIgnoreChecksums);
  if chkBackupIgnoreLimbo.Checked then Include(Options, bkoIgnoreLimbo);
  if chkBackupNonTransportable.Checked then
    Include(Options, bkoNonTransportable);
  if chkBackupConvertExternal.Checked then Include(Options, bkoConvertExtTables);
  if chkBackupNoDbTriggers.Checked then Include(Options, bkoNoDbTriggers);
  Task.Options := Options;

  Result := Task;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.BuildRestore
  ----------------------------------------------------------------------------
  Builds the restore task from the page.

  Returns:
    The task, for the runner to own.
------------------------------------------------------------------------------}
function TfrmIbqMaintenance.BuildRestore: TServiceTask;
var
  Task: TRestoreService;
  Options: TDbRestoreOptions;
begin
  Task := TRestoreService.Create;
  Task.DatabasePath := Trim(edtRestoreTarget.Text);
  Task.SetSingleFile(Trim(edtRestoreSource.Text));
  Task.PageSize := StrToIntDef(Trim(edtPageSize.Text), 0);
  Task.PageBuffers := StrToIntDef(Trim(edtPageBuffers.Text), 0);

  if chkRestoreReplace.Checked then
    Options := [rdoReplace]
  else
    Options := [rdoCreateNew];

  if chkRestoreDeactivateIndexes.Checked then
    Include(Options, rdoDeactivateIndexes);
  if chkRestoreNoShadow.Checked then Include(Options, rdoNoShadow);
  if chkRestoreNoValidity.Checked then Include(Options, rdoNoValidityCheck);
  if chkRestoreOneRelation.Checked then Include(Options, rdoOneRelationAtATime);
  if chkRestoreUseAllSpace.Checked then Include(Options, rdoUseAllSpace);
  if chkRestoreMetadataOnly.Checked then Include(Options, rdoMetadataOnly);
  Task.Options := Options;

  Result := Task;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.BuildValidation
  ----------------------------------------------------------------------------
  Builds the validation task from the page.

  Returns:
    The task, for the runner to own.
------------------------------------------------------------------------------}
function TfrmIbqMaintenance.BuildValidation: TServiceTask;
var
  Task: TValidationService;
  Options: TValidationOptions;
begin
  Task := TValidationService.Create;
  Task.DatabasePath := Trim(edtValidateDatabase.Text);

  if rgpValidateMode.ItemIndex = 1 then
  begin
    Task.Mode := vlmOnline;
    Result := Task;
    Exit;
  end;

  Task.Mode := vlmFull;
  Options := [];
  if chkValidateStructures.Checked then Include(Options, vloValidateDb);
  if chkValidateFull.Checked then Include(Options, vloValidateFull);
  if chkValidateCheckDb.Checked then Include(Options, vloCheckDatabase);
  if chkValidateIgnoreChecksum.Checked then Include(Options, vloIgnoreChecksum);
  if chkValidateKillShadows.Checked then Include(Options, vloKillShadows);
  if chkValidateMend.Checked then Include(Options, vloMendDatabase);
  Task.Options := Options;

  Result := Task;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.BuildStatistics
  ----------------------------------------------------------------------------
  Builds the statistics task from the page.

  Returns:
    The task, for the runner to own.
------------------------------------------------------------------------------}
function TfrmIbqMaintenance.BuildStatistics: TServiceTask;
var
  Task: TStatisticsService;
  Options: TStatisticsOptions;
begin
  Task := TStatisticsService.Create;
  Task.DatabasePath := Trim(edtStatsDatabase.Text);

  Options := [];
  if chkStatsHeader.Checked then Include(Options, stoHeaderPages);
  if chkStatsIndex.Checked then Include(Options, stoIndexPages);
  if chkStatsData.Checked then Include(Options, stoDataPages);
  if chkStatsSystem.Checked then Include(Options, stoSystemRelations);
  Task.Options := Options;

  Result := Task;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.BuildTask
  ----------------------------------------------------------------------------
  Builds the task for the command the dialog was opened for.

  Returns:
    The task, for the runner to own.
------------------------------------------------------------------------------}
function TfrmIbqMaintenance.BuildTask: TServiceTask;
var
  Sweep: TSweepService;
begin
  case FCommand of
    mcBackup:     Result := BuildBackup;
    mcRestore:    Result := BuildRestore;
    mcValidate:   Result := BuildValidation;
    mcStatistics: Result := BuildStatistics;
    mcServerLog:  Result := TServerLogService.Create;
  else
    Sweep := TSweepService.Create;
    Sweep.DatabasePath := Trim(edtSweepDatabase.Text);
    Result := Sweep;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.ConfirmDestructive
  ----------------------------------------------------------------------------
  Asks before anything that cannot be undone.

  Returns:
    True when the user said yes, or when there was nothing to ask about.

  Notes:
    Two commands can destroy data: a restore that replaces a database, and a
    validation that mends one. Both are named in the question, because "Are you
    sure?" tells nobody anything.
------------------------------------------------------------------------------}
function TfrmIbqMaintenance.ConfirmDestructive: Boolean;
var
  Question: string;
begin
  Question := '';

  if (FCommand = mcRestore) and chkRestoreReplace.Checked then
    Question := LangStrFormat('msg.confirmReplace',
      [Trim(edtRestoreTarget.Text)],
      'This will DESTROY the database at %s and replace it with the backup.' +
      LineEnding + LineEnding + 'There is no undo. Continue?');

  if (FCommand = mcValidate) and chkValidateMend.Checked and
    (rgpValidateMode.ItemIndex = 0) then
    Question := LangStrFormat('msg.confirmMend',
      [Trim(edtValidateDatabase.Text)],
      'Mending %s marks damaged records as deleted. Data that cannot be read ' +
      'is LOST.' + LineEnding + LineEnding +
      'Take a backup first if you have not. Continue?');

  Result := (Question = '') or
    (MessageDlg(Caption, Question, mtWarning, [mbYes, mbNo], 0) = mrYes);
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.btnStartClick
  ----------------------------------------------------------------------------
  Starts the command.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.btnStartClick(Sender: TObject);
var
  Task: TServiceTask;
  Refusal: string;
begin
  if (FRunner <> nil) and FRunner.IsRunning then
    Exit;

  if edtPassword.Text = '' then
  begin
    MessageDlg(Caption,
      LangStr('msg.passwordNeeded',
        'The server needs a password before it will do anything.'),
      mtInformation, [mbOK], 0);
    edtPassword.SetFocus;
    Exit;
  end;

  if not ConfirmDestructive then
    Exit;

  FRegistration.UserName := Trim(edtUser.Text);

  Task := BuildTask;
  FreeAndNil(FRunner);
  FRunner := TServiceRunner.Create(FRegistration, edtPassword.Text, Task);
  FRunner.OnLine := @HandleLine;
  FRunner.OnFinished := @HandleFinished;

  memOutput.Clear;
  lblStatus.Caption := LangStr('maint.running', 'Running...');
  SetRunningState(True);

  Refusal := FRunner.Start;
  if Refusal <> '' then
  begin
    SetRunningState(False);
    lblStatus.Caption := Refusal;
    MessageDlg(Caption, Refusal, mtInformation, [mbOK], 0);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.btnCancelClick
  ----------------------------------------------------------------------------
  Asks the running command to stop.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.btnCancelClick(Sender: TObject);
begin
  if (FRunner = nil) or not FRunner.IsRunning then
    Exit;

  FRunner.Cancel;
  lblStatus.Caption := LangStr('maint.stopping', 'Stopping...');
  btnCancel.Enabled := False;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.btnSaveClick
  ----------------------------------------------------------------------------
  Saves the output to a file on this machine.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.btnSaveClick(Sender: TObject);
begin
  if memOutput.Lines.Count = 0 then
    Exit;
  if not dlgSaveOutput.Execute then
    Exit;
  memOutput.Lines.SaveToFile(dlgSaveOutput.FileName);
  lblStatus.Caption := LangStrFormat('maint.savedTo',
    [dlgSaveOutput.FileName], 'Saved to %s');
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.HandleLine
  ----------------------------------------------------------------------------
  Appends one line of output. Called on the main thread.

  Parameters:
    ALine - The line the service produced.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.HandleLine(Sender: TObject; const ALine: string);
begin
  memOutput.Lines.Add(ALine);
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.HandleFinished
  ----------------------------------------------------------------------------
  Reports the outcome. Called on the main thread.

  Parameters:
    ASuccess   - True when the command ran to completion.
    ACancelled - True when the user stopped it.
    AError     - The failure text, empty otherwise.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.HandleFinished(Sender: TObject;
  ASuccess, ACancelled: Boolean; const AError: string);
begin
  SetRunningState(False);

  if ASuccess then
    lblStatus.Caption := LangStr('maint.finished', 'Finished.')
  else if ACancelled then
  begin
    lblStatus.Caption := LangStr('maint.cancelled', 'Stopped by the user.');
    memOutput.Lines.Add('');
    memOutput.Lines.Add(LangStr('maint.cancelledNote',
      '*** Stopped. Whatever the command had already written - a backup file, ' +
      'a half-restored database - is incomplete and must not be relied on.'));
  end
  else
  begin
    lblStatus.Caption := LangStr('maint.failed', 'Failed.');
    memOutput.Lines.Add('');
    memOutput.Lines.Add(AError);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.SetRunningState
  ----------------------------------------------------------------------------
  Enables the buttons and pages that make sense while running, or not.

  Parameters:
    ARunning - True while the command is in flight.

  Notes:
    The options page is disabled rather than hidden: the user should be able to
    read what was asked for while it runs.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.SetRunningState(ARunning: Boolean);
begin
  btnStart.Enabled := not ARunning;
  btnCancel.Enabled := ARunning;
  btnSave.Enabled := not ARunning;
  pgcCommand.Enabled := not ARunning;
  edtPassword.Enabled := not ARunning;
  edtUser.Enabled := not ARunning;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.FormClose
  ----------------------------------------------------------------------------
  Refuses to close while a command is running.

  Parameters:
    CloseAction - Set to caNone when the user says to carry on.

  Notes:
    Closing would free the runner, which cancels - so the choice really is
    "stop the backup or leave the window open", and it is put in those words.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  if (FRunner = nil) or not FRunner.IsRunning then
    Exit;

  if MessageDlg(Caption,
    LangStr('msg.confirmStopOnClose',
      'This will stop the command that is running. Close anyway?'),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FRunner.Cancel;
    Log.Warning('Maintenance dialog closed while a task was running.');
  end
  else
    CloseAction := caNone;
end;

{------------------------------------------------------------------------------
  TfrmIbqMaintenance.StatsOptionClick
  ----------------------------------------------------------------------------
  Keeps the statistics options to a combination the server will accept.

  Parameters:
    Sender - Whichever of the four option boxes was clicked.

  Notes:
    The header page is asked for on its own or not at all. Firebird's
    statistics service refuses -h together with -d, -i, -s or -r, and says
    so with 'option -h is incompatible with options -a, -d, -i, -r, -s and
    -t' - which is accurate and arrives far too late, after the user has
    typed a password and pressed Start.

    So the rule is enforced here instead: ticking the header clears the
    others and greys them, and ticking any other clears the header. The
    boxes cannot be put into a combination that fails.

    At least one option stays ticked, because a statistics run that asks
    for nothing has nothing to report.

    Setting Checked in code raises OnClick again, so the flag stops this
    from re-entering itself while it is tidying up.
------------------------------------------------------------------------------}
procedure TfrmIbqMaintenance.StatsOptionClick(Sender: TObject);
begin
  if FUpdatingStatsOptions then
  begin
    Exit;
  end;

  FUpdatingStatsOptions := True;
  try
    if Sender = chkStatsHeader then
    begin
      if chkStatsHeader.Checked then
      begin
        chkStatsIndex.Checked := False;
        chkStatsData.Checked := False;
        chkStatsSystem.Checked := False;
      end;
    end
    else if (Sender is TCheckBox) and TCheckBox(Sender).Checked then
    begin
      chkStatsHeader.Checked := False;
    end;

    if not (chkStatsHeader.Checked or chkStatsIndex.Checked or
            chkStatsData.Checked or chkStatsSystem.Checked) then
    begin
      chkStatsHeader.Checked := True;
    end;

    chkStatsIndex.Enabled := not chkStatsHeader.Checked;
    chkStatsData.Enabled := not chkStatsHeader.Checked;
    chkStatsSystem.Enabled := not chkStatsHeader.Checked;
  finally
    FUpdatingStatsOptions := False;
  end;
end;

end.
