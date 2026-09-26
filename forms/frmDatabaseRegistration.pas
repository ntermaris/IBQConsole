{==============================================================================
  Unit:        frmDatabaseRegistration
  Purpose:     Registers a database, or edits an existing registration.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  LCL, LanguageHandle, ConnectionProfile, ServerRegistration,
               FbClientLocator

  Like the server dialog, this records where a database is; it does not connect.

  The client library row appears only for an embedded database. A database on a
  server takes its client from the SERVER registration, because the library is
  loaded once for the connection to that server - see
  TMetaDatabase.EffectiveClientLibrary.
==============================================================================}
unit frmDatabaseRegistration;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  LanguageHandle, ConnectionProfile, ServerRegistration, FbClientLocator;

type

  { TfrmIbqDatabaseRegistration
    Collects everything needed to open one database. }
  TfrmIbqDatabaseRegistration = class(TForm, ILocalizable)
    lblName: TLabel;
    edtName: TEdit;
    lblMode: TLabel;
    cbxMode: TComboBox;
    lblPath: TLabel;
    edtPath: TEdit;
    btnBrowsePath: TButton;
    lblUser: TLabel;
    edtUser: TEdit;
    lblRole: TLabel;
    edtRole: TEdit;
    chkRoleCaseSensitive: TCheckBox;
    lblCharset: TLabel;
    cbxCharset: TComboBox;
    lblPageBuffers: TLabel;
    edtPageBuffers: TEdit;
    lblPasswordStorage: TLabel;
    cbxPasswordStorage: TComboBox;
    lblClientLib: TLabel;
    cbxClientLib: TComboBox;
    btnBrowseClient: TButton;
    lblHint: TLabel;
    dlgOpenDatabase: TOpenDialog;
    dlgOpenClient: TOpenDialog;
    bvlButtons: TBevel;
    btnOK: TButton;
    btnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure cbxModeChange(Sender: TObject);
    procedure btnBrowsePathClick(Sender: TObject);
    procedure btnBrowseClientClick(Sender: TObject);
  private
    FClients: TFbClientList;
    function SelectedMode: TConnectionMode;
    procedure UpdateModeDependentControls;
  public
    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { Copies a profile into the fields, for editing. }
    procedure LoadFrom(AProfile: TConnectionProfile);
    { Copies the fields back into a profile, after OK. }
    procedure SaveTo(AProfile: TConnectionProfile);
  end;

{ Shows the dialog and, on OK, fills AProfile from it.

  Parameters:
    AProfile - Filled in on OK; untouched on Cancel.
    AServer  - The server the database will be registered under, or nil when
               registering an embedded database. Supplies the default user name
               and the host and port that go into the profile.

  Returns:
    True when the user pressed OK. }
function EditDatabaseRegistration(AProfile: TConnectionProfile;
  AServer: TServerRegistration): Boolean;

implementation

{$R *.lfm}

const
  { Character sets offered in the drop-down. Not the complete Firebird list -
    52 entries would be a wall of noise - but the ones actually chosen, with
    UTF8 first because it is the right answer unless there is a reason. }
  CommonCharacterSets: array[0..9] of string = (
    'UTF8', 'NONE', 'WIN1252', 'WIN1253', 'WIN1251', 'WIN1250',
    'ISO8859_1', 'ISO8859_7', 'ASCII', 'UTF-8'
  );

{------------------------------------------------------------------------------
  EditDatabaseRegistration
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Host and port are taken from the server rather than asked for again: a
    database registered under a server is by definition on that server, and a
    second copy of the address would be one more thing to keep in step.
------------------------------------------------------------------------------}
function EditDatabaseRegistration(AProfile: TConnectionProfile;
  AServer: TServerRegistration): Boolean;
var
  Dialog: TfrmIbqDatabaseRegistration;
begin
  Dialog := TfrmIbqDatabaseRegistration.Create(nil);
  try
    if (AServer <> nil) and (AProfile.UserName = '') then
      AProfile.UserName := AServer.UserName;

    Dialog.LoadFrom(AProfile);
    Result := Dialog.ShowModal = mrOK;

    if Result then
    begin
      Dialog.SaveTo(AProfile);
      if (AServer <> nil) and (AProfile.Mode <> cmEmbedded) then
      begin
        AProfile.Host := AServer.Host;
        AProfile.Port := AServer.Port;
      end;
    end;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.FormCreate
  ----------------------------------------------------------------------------
  Fills the drop-downs and applies the active language.
------------------------------------------------------------------------------}
procedure TfrmIbqDatabaseRegistration.FormCreate(Sender: TObject);
var
  I: Integer;
begin
  FClients := DetectClients;

  cbxCharset.Items.BeginUpdate;
  try
    cbxCharset.Items.Clear;
    for I := Low(CommonCharacterSets) to High(CommonCharacterSets) do
      cbxCharset.Items.Add(CommonCharacterSets[I]);
  finally
    cbxCharset.Items.EndUpdate;
  end;

  cbxClientLib.Items.BeginUpdate;
  try
    cbxClientLib.Items.Clear;
    cbxClientLib.Items.Add('');
    for I := Low(FClients) to High(FClients) do
      cbxClientLib.Items.Add(FClients[I].Path);
  finally
    cbxClientLib.Items.EndUpdate;
  end;

  ApplyLocaleTo(Self);
  UpdateModeDependentControls;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.

  Notes:
    The mode drop-down is rebuilt here rather than in the LFM, because its
    entries are translated text and would otherwise stay English after a
    language change. The selected index is preserved across the rebuild.
------------------------------------------------------------------------------}
procedure TfrmIbqDatabaseRegistration.LoadLangStr;
var
  KeepIndex: Integer;
begin
  Caption := LangStr('frmDatabaseRegistration.caption', 'Register Database');
  lblName.Caption := LangStr('lblName.caption', 'Display name');
  lblMode.Caption := LangStr('lblMode.caption', 'Connection');
  lblPath.Caption := LangStr('lblPath.caption', 'Database file');
  lblUser.Caption := LangStr('lblUser.caption', 'User name');
  lblRole.Caption := LangStr('lblRole.caption', 'Role');
  chkRoleCaseSensitive.Caption :=
    LangStr('chkRoleCaseSensitive.caption', 'Case sensitive');
  lblCharset.Caption := LangStr('lblCharset.caption', 'Character set');
  lblPageBuffers.Caption :=
    LangStr('lblPageBuffers.caption', 'Page buffers');
  lblPasswordStorage.Caption :=
    LangStr('lblPasswordStorage.caption', 'Password');
  lblClientLib.Caption := LangStr('lblClientLib.caption', 'Client library');
  btnBrowsePath.Caption := LangStr('btnBrowse.caption', 'Browse...');
  btnBrowseClient.Caption := LangStr('btnBrowse.caption', 'Browse...');
  btnOK.Caption := LangStr('btnOK.caption', 'OK');
  btnCancel.Caption := LangStr('btnCancel.caption', 'Cancel');

  KeepIndex := cbxMode.ItemIndex;
  cbxMode.Items.BeginUpdate;
  try
    cbxMode.Items.Clear;
    cbxMode.Items.Add(LangStr('mode.remote', 'Remote server (TCP)'));
    cbxMode.Items.Add(LangStr('mode.local', 'Local server'));
    cbxMode.Items.Add(LangStr('mode.embedded', 'Embedded - no server'));
  finally
    cbxMode.Items.EndUpdate;
  end;
  if KeepIndex < 0 then
    KeepIndex := 0;
  cbxMode.ItemIndex := KeepIndex;

  KeepIndex := cbxPasswordStorage.ItemIndex;
  cbxPasswordStorage.Items.BeginUpdate;
  try
    cbxPasswordStorage.Items.Clear;
    cbxPasswordStorage.Items.Add(
      LangStr('password.none', 'Ask every time (recommended)'));
    cbxPasswordStorage.Items.Add(
      LangStr('password.session', 'Remember for this session'));
  finally
    cbxPasswordStorage.Items.EndUpdate;
  end;
  if KeepIndex < 0 then
    KeepIndex := 0;
  cbxPasswordStorage.ItemIndex := KeepIndex;

  UpdateModeDependentControls;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.SelectedMode
  ----------------------------------------------------------------------------
  Returns the connection mode currently chosen.

  Returns:
    The mode; cmRemote when nothing is selected.
------------------------------------------------------------------------------}
function TfrmIbqDatabaseRegistration.SelectedMode: TConnectionMode;
begin
  case cbxMode.ItemIndex of
    1: Result := cmLocal;
    2: Result := cmEmbedded;
  else
    Result := cmRemote;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.UpdateModeDependentControls
  ----------------------------------------------------------------------------
  Shows the rows that apply to the chosen connection mode.

  Notes:
    The client library row is shown only for an embedded database. For a
    database on a server the library belongs to the server registration, and
    offering it here would invite two answers to one question.

    The hint line explains what the mode means, because "Local server" and
    "Embedded" look interchangeable and are not: the first still needs a
    running Firebird service, the second does not and cannot use the Services
    API at all.
------------------------------------------------------------------------------}
procedure TfrmIbqDatabaseRegistration.UpdateModeDependentControls;
var
  IsEmbedded: Boolean;
begin
  IsEmbedded := SelectedMode = cmEmbedded;

  lblClientLib.Visible := IsEmbedded;
  cbxClientLib.Visible := IsEmbedded;
  btnBrowseClient.Visible := IsEmbedded;

  // the file is on this machine for local and embedded, on the server for remote
  btnBrowsePath.Visible := SelectedMode <> cmRemote;

  case SelectedMode of
    cmRemote:
      lblHint.Caption := LangStr('hint.remote',
        'The path is the database file as the SERVER sees it, or an alias ' +
        'defined on the server.');
    cmLocal:
      lblHint.Caption := LangStr('hint.local',
        'A local server connection still needs a running Firebird service ' +
        'on this machine.');
    cmEmbedded:
      lblHint.Caption := LangStr('hint.embedded',
        'The embedded engine opens the file directly. No server is involved, ' +
        'so backup, restore, validation and user management are unavailable, ' +
        'and only one program may hold the file open.');
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.cbxModeChange
  ----------------------------------------------------------------------------
  Refreshes the mode-dependent rows.
------------------------------------------------------------------------------}
procedure TfrmIbqDatabaseRegistration.cbxModeChange(Sender: TObject);
begin
  UpdateModeDependentControls;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.btnBrowsePathClick
  ----------------------------------------------------------------------------
  Lets the user pick a database file from this machine.
------------------------------------------------------------------------------}
procedure TfrmIbqDatabaseRegistration.btnBrowsePathClick(Sender: TObject);
begin
  dlgOpenDatabase.Title := LangStr('dlgOpenDatabase.title',
    'Select the database file');
  dlgOpenDatabase.FileName := Trim(edtPath.Text);
  if dlgOpenDatabase.Execute then
    edtPath.Text := dlgOpenDatabase.FileName;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.btnBrowseClientClick
  ----------------------------------------------------------------------------
  Lets the user pick the embedded client library from disk.
------------------------------------------------------------------------------}
procedure TfrmIbqDatabaseRegistration.btnBrowseClientClick(Sender: TObject);
begin
  dlgOpenClient.Title := LangStr('dlgOpenClient.title',
    'Select the Firebird client library');
  dlgOpenClient.FileName := Trim(cbxClientLib.Text);
  if dlgOpenClient.Execute then
    cbxClientLib.Text := dlgOpenClient.FileName;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.LoadFrom
  ----------------------------------------------------------------------------
  Copies a profile into the dialog's fields.

  Parameters:
    AProfile - The profile to show. Nil leaves the defaults in place.
------------------------------------------------------------------------------}
procedure TfrmIbqDatabaseRegistration.LoadFrom(AProfile: TConnectionProfile);
begin
  if AProfile = nil then
    Exit;

  edtName.Text := AProfile.DisplayName;
  edtPath.Text := AProfile.DatabasePath;
  edtUser.Text := AProfile.UserName;
  edtRole.Text := AProfile.Role;
  chkRoleCaseSensitive.Checked := AProfile.UseCaseSensitiveRole;
  cbxClientLib.Text := AProfile.ClientLibrary;

  cbxCharset.Text := AProfile.CharacterSet;
  if cbxCharset.Text = '' then
    cbxCharset.Text := DefaultCharacterSet;

  if AProfile.PageBuffers > 0 then
    edtPageBuffers.Text := IntToStr(AProfile.PageBuffers)
  else
    edtPageBuffers.Text := '';

  case AProfile.Mode of
    cmLocal:    cbxMode.ItemIndex := 1;
    cmEmbedded: cbxMode.ItemIndex := 2;
  else
    cbxMode.ItemIndex := 0;
  end;

  if AProfile.PasswordStorage = psSessionOnly then
    cbxPasswordStorage.ItemIndex := 1
  else
    cbxPasswordStorage.ItemIndex := 0;

  UpdateModeDependentControls;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.SaveTo
  ----------------------------------------------------------------------------
  Copies the dialog's fields into a profile.

  Parameters:
    AProfile - Receives the values. Nil is ignored.

  Notes:
    The client library is written only for an embedded database. For any other
    mode it is cleared, so a profile that was once embedded and has been
    changed to remote does not keep a stale path that nothing would ever use.
------------------------------------------------------------------------------}
procedure TfrmIbqDatabaseRegistration.SaveTo(AProfile: TConnectionProfile);
begin
  if AProfile = nil then
    Exit;

  AProfile.DisplayName := Trim(edtName.Text);
  AProfile.Mode := SelectedMode;
  AProfile.DatabasePath := Trim(edtPath.Text);
  AProfile.UserName := Trim(edtUser.Text);
  AProfile.Role := Trim(edtRole.Text);
  AProfile.UseCaseSensitiveRole := chkRoleCaseSensitive.Checked;
  AProfile.CharacterSet := Trim(cbxCharset.Text);
  AProfile.PageBuffers := StrToIntDef(Trim(edtPageBuffers.Text), 0);

  if AProfile.Mode = cmEmbedded then
    AProfile.ClientLibrary := Trim(cbxClientLib.Text)
  else
    AProfile.ClientLibrary := '';

  if cbxPasswordStorage.ItemIndex = 1 then
    AProfile.PasswordStorage := psSessionOnly
  else
    AProfile.PasswordStorage := psDoNotStore;
end;

{------------------------------------------------------------------------------
  TfrmIbqDatabaseRegistration.btnOKClick
  ----------------------------------------------------------------------------
  Validates the fields and closes the dialog when they are usable.

  Notes:
    Validation is done by building a throwaway profile and asking
    TConnectionProfile.Validate, so the dialog and the connection layer can
    never disagree about what counts as a usable registration.
------------------------------------------------------------------------------}
procedure TfrmIbqDatabaseRegistration.btnOKClick(Sender: TObject);
var
  Candidate: TConnectionProfile;
  Reason: string;
  Valid: Boolean;
begin
  Candidate := TConnectionProfile.Create;
  try
    SaveTo(Candidate);
    // Validate checks the host for a remote profile; the real host comes from
    // the server registration after OK, so supply a placeholder here.
    if Candidate.Mode = cmRemote then
      Candidate.Host := 'localhost';
    Valid := Candidate.Validate(Reason);
  finally
    Candidate.Free;
  end;

  if not Valid then
  begin
    MessageDlg(Caption, Reason, mtWarning, [mbOK], 0);
    if Trim(edtPath.Text) = '' then
      edtPath.SetFocus
    else
      edtUser.SetFocus;
    Exit;
  end;

  ModalResult := mrOK;
end;

end.
