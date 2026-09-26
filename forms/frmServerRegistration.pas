{==============================================================================
  Unit:        frmServerRegistration
  Purpose:     Registers a Firebird server, or edits an existing registration.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  LCL, LanguageHandle, ServerRegistration, ConnectionProfile,
               FbClientLocator

  Registering a server records where it is and which client library to reach it
  with. It does not connect: IBConsole behaved the same way, and it is what
  lets a user set up a list of servers once and connect to them individually
  later.

  The client library matters as soon as more than one Firebird version is
  installed. A machine can run 3.0 on 3050, 4.0 on 3051 and 5.0 on 3052; which
  fbclient is found first on the system path is then an accident, and the wrong
  one gives confusing failures rather than a clear "wrong version" message.
==============================================================================}
unit frmServerRegistration;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  LanguageHandle, ServerRegistration, ConnectionProfile, FbClientLocator;

type

  { TfrmIbqServerRegistration
    Collects the name, host, port, default user and client library of a
    server. }
  TfrmIbqServerRegistration = class(TForm, ILocalizable)
    lblName: TLabel;
    edtName: TEdit;
    lblHost: TLabel;
    edtHost: TEdit;
    lblPort: TLabel;
    edtPort: TEdit;
    lblUser: TLabel;
    edtUser: TEdit;
    lblDescription: TLabel;
    edtDescription: TEdit;
    lblClientLib: TLabel;
    cbxClientLib: TComboBox;
    btnBrowseClient: TButton;
    lblClientInfo: TLabel;
    dlgOpenClient: TOpenDialog;
    bvlButtons: TBevel;
    btnOK: TButton;
    btnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure btnBrowseClientClick(Sender: TObject);
    procedure cbxClientLibChange(Sender: TObject);
  private
    FClients: TFbClientList;
    procedure FillClientList;
    procedure UpdateClientInfo;
  public
    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { Copies a registration into the fields, for editing. }
    procedure LoadFrom(ARegistration: TServerRegistration);
    { Copies the fields back into a registration, after OK. }
    procedure SaveTo(ARegistration: TServerRegistration);
  end;

{ Shows the dialog and, on OK, fills ARegistration from it.

  Parameters:
    ARegistration - Filled in on OK; untouched on Cancel.

  Returns:
    True when the user pressed OK. }
function EditServerRegistration(
  ARegistration: TServerRegistration): Boolean;

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  EditServerRegistration
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function EditServerRegistration(
  ARegistration: TServerRegistration): Boolean;
var
  Dialog: TfrmIbqServerRegistration;
begin
  Dialog := TfrmIbqServerRegistration.Create(nil);
  try
    Dialog.LoadFrom(ARegistration);
    Result := Dialog.ShowModal = mrOK;
    if Result then
      Dialog.SaveTo(ARegistration);
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerRegistration.FormCreate
  ----------------------------------------------------------------------------
  Detects the installed client libraries and applies the active language.
------------------------------------------------------------------------------}
procedure TfrmIbqServerRegistration.FormCreate(Sender: TObject);
begin
  FClients := DetectClients;
  FillClientList;
  ApplyLocaleTo(Self);
  UpdateClientInfo;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerRegistration.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.
------------------------------------------------------------------------------}
procedure TfrmIbqServerRegistration.LoadLangStr;
begin
  Caption := LangStr('frmServerRegistration.caption', 'Register Server');
  lblName.Caption := LangStr('lblName.caption', 'Display name');
  lblHost.Caption := LangStr('lblHost.caption', 'Host');
  lblPort.Caption := LangStr('lblPort.caption', 'Port');
  lblUser.Caption := LangStr('lblUser.caption', 'Default user');
  lblDescription.Caption := LangStr('lblDescription.caption', 'Description');
  lblClientLib.Caption := LangStr('lblClientLib.caption', 'Client library');
  btnBrowseClient.Caption := LangStr('btnBrowseClient.caption', 'Browse...');
  btnOK.Caption := LangStr('btnOK.caption', 'OK');
  btnCancel.Caption := LangStr('btnCancel.caption', 'Cancel');
  UpdateClientInfo;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerRegistration.FillClientList
  ----------------------------------------------------------------------------
  Puts every detected client library into the drop-down.

  Notes:
    The list holds bare paths rather than descriptions, so whatever the user
    sees is exactly what gets stored, and a path typed or pasted by hand is
    treated no differently from one that was detected. The version of the
    current entry is shown separately by UpdateClientInfo.

    The first entry is empty and means "let the system search path decide",
    which is the right default on a machine with only one Firebird.
------------------------------------------------------------------------------}
procedure TfrmIbqServerRegistration.FillClientList;
var
  I: Integer;
begin
  cbxClientLib.Items.BeginUpdate;
  try
    cbxClientLib.Items.Clear;
    cbxClientLib.Items.Add('');
    for I := Low(FClients) to High(FClients) do
      cbxClientLib.Items.Add(FClients[I].Path);
  finally
    cbxClientLib.Items.EndUpdate;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerRegistration.UpdateClientInfo
  ----------------------------------------------------------------------------
  Describes the client library currently named in the drop-down.

  Notes:
    Reads the version from the file rather than from the detected list, so a
    path the user typed is described too. A path that does not exist is said to
    be missing here, at registration time, instead of failing later as an
    obscure connection error.
------------------------------------------------------------------------------}
procedure TfrmIbqServerRegistration.UpdateClientInfo;
var
  Path: string;
  Info: TFbClientInfo;
begin
  Path := Trim(cbxClientLib.Text);

  if Path = '' then
  begin
    lblClientInfo.Caption := LangStrFormat('msg.clientDefault',
      [DefaultClientFileName],
      'Using the system default: the first %s found on the search path.');
    Exit;
  end;

  if not FileExists(Path) then
  begin
    lblClientInfo.Caption := LangStr('msg.clientMissing',
      'This file does not exist.');
    Exit;
  end;

  ReadClientInfo(Path, Info);
  if Info.VersionText <> '' then
    lblClientInfo.Caption := LangStrFormat('msg.clientVersion',
      [Info.VersionText], 'Firebird client version %s')
  else
    lblClientInfo.Caption := LangStr('msg.clientUnknownVersion',
      'The version of this library could not be read.');
end;

{------------------------------------------------------------------------------
  TfrmIbqServerRegistration.cbxClientLibChange
  ----------------------------------------------------------------------------
  Refreshes the description under the drop-down.
------------------------------------------------------------------------------}
procedure TfrmIbqServerRegistration.cbxClientLibChange(Sender: TObject);
begin
  UpdateClientInfo;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerRegistration.btnBrowseClientClick
  ----------------------------------------------------------------------------
  Lets the user pick a client library from disk.
------------------------------------------------------------------------------}
procedure TfrmIbqServerRegistration.btnBrowseClientClick(Sender: TObject);
begin
  dlgOpenClient.Title := LangStr('dlgOpenClient.title',
    'Select the Firebird client library');
  dlgOpenClient.FileName := Trim(cbxClientLib.Text);

  if dlgOpenClient.Execute then
  begin
    cbxClientLib.Text := dlgOpenClient.FileName;
    UpdateClientInfo;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerRegistration.LoadFrom
  ----------------------------------------------------------------------------
  Copies a registration into the dialog's fields.

  Parameters:
    ARegistration - The registration to show. Nil leaves the defaults in place.
------------------------------------------------------------------------------}
procedure TfrmIbqServerRegistration.LoadFrom(
  ARegistration: TServerRegistration);
begin
  if ARegistration = nil then
    Exit;

  edtName.Text := ARegistration.DisplayName;
  edtHost.Text := ARegistration.Host;
  edtPort.Text := IntToStr(ARegistration.Port);
  edtUser.Text := ARegistration.UserName;
  edtDescription.Text := ARegistration.Description;
  cbxClientLib.Text := ARegistration.ClientLibrary;
  UpdateClientInfo;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerRegistration.SaveTo
  ----------------------------------------------------------------------------
  Copies the dialog's fields into a registration.

  Parameters:
    ARegistration - Receives the values. Nil is ignored.
------------------------------------------------------------------------------}
procedure TfrmIbqServerRegistration.SaveTo(
  ARegistration: TServerRegistration);
begin
  if ARegistration = nil then
    Exit;

  ARegistration.DisplayName := Trim(edtName.Text);
  ARegistration.Host := Trim(edtHost.Text);
  ARegistration.Port := StrToIntDef(Trim(edtPort.Text), DefaultFirebirdPort);
  ARegistration.UserName := Trim(edtUser.Text);
  ARegistration.Description := Trim(edtDescription.Text);
  ARegistration.ClientLibrary := Trim(cbxClientLib.Text);
end;

{------------------------------------------------------------------------------
  TfrmIbqServerRegistration.btnOKClick
  ----------------------------------------------------------------------------
  Validates the fields and closes the dialog when they are usable.

  Notes:
    A named client library that does not exist is refused outright. A missing
    library surfaces at connect time as a load failure with no useful text, so
    catching it here is worth the extra dialog.
------------------------------------------------------------------------------}
procedure TfrmIbqServerRegistration.btnOKClick(Sender: TObject);
var
  Port: Integer;
  ClientPath: string;
begin
  if Trim(edtHost.Text) = '' then
  begin
    MessageDlg(Caption,
      LangStr('msg.hostRequired', 'A server needs a host name or address.'),
      mtWarning, [mbOK], 0);
    edtHost.SetFocus;
    Exit;
  end;

  Port := StrToIntDef(Trim(edtPort.Text), -1);
  if (Port <= 0) or (Port > 65535) then
  begin
    MessageDlg(Caption,
      LangStr('msg.portRange', 'The port must be between 1 and 65535.'),
      mtWarning, [mbOK], 0);
    edtPort.SetFocus;
    Exit;
  end;

  ClientPath := Trim(cbxClientLib.Text);
  if (ClientPath <> '') and not FileExists(ClientPath) then
  begin
    MessageDlg(Caption,
      LangStrFormat('msg.clientNotFound', [ClientPath],
        'The client library "%s" does not exist.' + LineEnding +
        'Leave the field empty to use the system default.'),
      mtWarning, [mbOK], 0);
    cbxClientLib.SetFocus;
    Exit;
  end;

  ModalResult := mrOK;
end;

end.
