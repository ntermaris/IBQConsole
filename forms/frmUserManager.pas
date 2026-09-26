{==============================================================================
  Unit:        frmUserManager
  Purpose:     Lists the server's users and lets them be created, changed and
               removed.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  LCL, LanguageHandle, MetaDatabase, ServerRegistration,
               SecurityService

  IBConsole equivalent: frmuUser. FlameRobin equivalent: UserDialog.

  ONE WINDOW, NOT TWO
  IBConsole had a list window that opened an edit window. Here the list and the
  fields are on the same form: selecting a user fills the fields, New clears
  them, Save writes them back. For a form with six fields, a second window is
  ceremony - and the list beside the fields is what makes it obvious that the
  admin flag belongs to a person rather than to the dialog.

  THE PASSWORD FIELD IS ALWAYS BLANK
  It is blank when an existing user is selected because Firebird cannot tell us
  the password, and there is nothing to show. Left blank on Save it means
  "leave the password alone"; filled in, it replaces it. A new user must have
  one.

  WHICH MECHANISM IS IN USE IS SHOWN
  Through a connected database this uses SQL and sees every user manager
  plugin. Through a server with no connected database it falls back to the
  Services API, which sees only the first plugin the server names - so the
  header says which one is in use rather than presenting a possibly partial
  list as the whole truth.
==============================================================================}
unit frmUserManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Grids, Dialogs,
  LanguageHandle, AppLog, MetaDatabase, ServerRegistration, SecurityService;

type
  { TfrmIbqUserManager
    The user-management dialog. }
  TfrmIbqUserManager = class(TForm, ILocalizable)
    pnlHeader: TPanel;
    lblServer: TLabel;
    lblServerValue: TLabel;
    lblSource: TLabel;
    grdUsers: TStringGrid;
    splUsers: TSplitter;
    pnlEdit: TPanel;
    grpUser: TGroupBox;
    lblUserName: TLabel;
    edtUserName: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblConfirm: TLabel;
    edtConfirm: TEdit;
    lblFirstName: TLabel;
    edtFirstName: TEdit;
    lblMiddleName: TLabel;
    edtMiddleName: TEdit;
    lblLastName: TLabel;
    edtLastName: TEdit;
    chkActive: TCheckBox;
    chkAdminRole: TCheckBox;
    lblPlugin: TLabel;
    lblPluginValue: TLabel;
    lblPasswordNote: TLabel;
    pnlButtons: TPanel;
    lblStatus: TLabel;
    btnNew: TButton;
    btnSave: TButton;
    btnDelete: TButton;
    btnRefresh: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure grdUsersSelection(Sender: TObject; aCol, aRow: Integer);
    procedure btnNewClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
  private
    FService: TSecurityService;
    FOwnsService: Boolean;
    FUsers: TUserAccountArray;
    FIsNew: Boolean;
    procedure LoadUsers;
    procedure ShowAccount(const AAccount: TUserAccount);
    function AccountFromFields: TUserAccount;
    function SelectedAccount(out AAccount: TUserAccount): Boolean;
    procedure SetEditingNew(AIsNew: Boolean);
    procedure ReportError(E: Exception);
  public
    destructor Destroy; override;

    { Prepares the dialog.

      Parameters:
        AService     - The service to work through. Taken over when
                       AOwnsService is True.
        AOwnsService - True when this form should free AService.
        ACaption     - The server, for the header. }
    procedure PrepareFor(AService: TSecurityService; AOwnsService: Boolean;
      const ACaption: string);

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

{ Shows the user manager for the server a connected database belongs to.

  Parameters:
    ADatabase - A CONNECTED database on the server whose users are wanted. Any
                database on that server will do: the accounts belong to the
                server. }
procedure UserManagerDialog(ADatabase: TMetaDatabase);

{ Shows the user manager for a server with no connected database, through the
  Services API.

  Parameters:
    ARegistration - The server.
    APassword     - The password to attach with. }
procedure ServerUserManagerDialog(ARegistration: TServerRegistration;
  const APassword: string);

implementation

{$R *.lfm}

const
  { Columns of the user grid. }
  ColName = 0;
  ColFullName = 1;
  ColActive = 2;
  ColAdmin = 3;
  ColPlugin = 4;

{------------------------------------------------------------------------------
  UserManagerDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure UserManagerDialog(ADatabase: TMetaDatabase);
var
  Dialog: TfrmIbqUserManager;
  Service: TSecurityService;
begin
  if (ADatabase = nil) or not ADatabase.IsConnected then
    Exit;

  Service := ADatabase.CreateSecurityService;
  if Service = nil then
    Exit;

  Dialog := TfrmIbqUserManager.Create(nil);
  try
    Dialog.PrepareFor(Service, True, ADatabase.ServerReg.TreeCaption);
    Dialog.ShowModal;
  finally
    Dialog.Free;      // frees the service with it
  end;
end;

{------------------------------------------------------------------------------
  ServerUserManagerDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure ServerUserManagerDialog(ARegistration: TServerRegistration;
  const APassword: string);
var
  Dialog: TfrmIbqUserManager;
begin
  if ARegistration = nil then
    Exit;

  Dialog := TfrmIbqUserManager.Create(nil);
  try
    Dialog.PrepareFor(
      TSecurityService.CreateForServer(ARegistration, APassword), True,
      ARegistration.TreeCaption);
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.Destroy
  ----------------------------------------------------------------------------
  Releases the service when this form owns it.
------------------------------------------------------------------------------}
destructor TfrmIbqUserManager.Destroy;
begin
  if FOwnsService then
    FreeAndNil(FService);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.LoadLangStr;
begin
  Caption := LangStr('frmUserManager.caption', 'Users');

  lblServer.Caption := LangStr('maint.server', 'Server');

  grpUser.Caption := LangStr('user.details', 'User');
  lblUserName.Caption := LangStr('user.name', 'User name');
  lblPassword.Caption := LangStr('maint.password', 'Password');
  lblConfirm.Caption := LangStr('user.confirm', 'Confirm');
  lblFirstName.Caption := LangStr('user.firstName', 'First name');
  lblMiddleName.Caption := LangStr('user.middleName', 'Middle name');
  lblLastName.Caption := LangStr('user.lastName', 'Last name');
  chkActive.Caption := LangStr('user.active', 'Active');
  chkAdminRole.Caption := LangStr('user.adminRole', 'Administrator');
  lblPlugin.Caption := LangStr('user.plugin', 'Plugin');
  lblPasswordNote.Caption := LangStr('user.passwordNote',
    'Leave the password empty to keep the current one. Firebird never gives ' +
    'a password back, so there is nothing to show here.');

  btnNew.Caption := LangStr('user.new', 'New');
  btnSave.Caption := LangStr('user.save', 'Save');
  btnDelete.Caption := LangStr('user.delete', 'Delete');
  btnRefresh.Caption := LangStr('btnRefresh.caption', 'Refresh');
  btnClose.Caption := LangStr('btnClose.caption', 'Close');

  if grdUsers.ColCount >= 5 then
  begin
    grdUsers.Cells[ColName, 0] := LangStr('user.name', 'User name');
    grdUsers.Cells[ColFullName, 0] := LangStr('user.fullName', 'Full name');
    grdUsers.Cells[ColActive, 0] := LangStr('user.active', 'Active');
    grdUsers.Cells[ColAdmin, 0] := LangStr('user.adminRole', 'Administrator');
    grdUsers.Cells[ColPlugin, 0] := LangStr('user.plugin', 'Plugin');
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.PrepareFor
  ----------------------------------------------------------------------------
  Prepares the dialog.

  Parameters:
    AService     - The service to work through.
    AOwnsService - True when this form should free AService.
    ACaption     - The server, for the header.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.PrepareFor(AService: TSecurityService;
  AOwnsService: Boolean; const ACaption: string);
var
  Reason: string;
begin
  FService := AService;
  FOwnsService := AOwnsService;
  lblServerValue.Caption := ACaption;

  if FService = nil then
    Exit;

  if FService.Source = usSql then
    lblSource.Caption := LangStr('user.sourceSql',
      'Through the connected database: every user manager plugin is visible.')
  else
    lblSource.Caption := LangStr('user.sourceServices',
      'Through the Services API: only the server''s first user manager ' +
      'plugin is visible, and the active flag is not reported.');

  Reason := FService.Unavailable;
  if Reason <> '' then
  begin
    lblStatus.Caption := Reason;
    btnNew.Enabled := False;
    btnSave.Enabled := False;
    btnDelete.Enabled := False;
    btnRefresh.Enabled := False;
    Exit;
  end;

  LoadUsers;
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.LoadUsers
  ----------------------------------------------------------------------------
  Reads the users and fills the grid.

  Notes:
    An empty list is not an error. A user who is not an administrator is shown
    only their own account by the server, and on some configurations not even
    that - so the status line says what happened rather than leaving an empty
    grid to be read as a failure.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.LoadUsers;
var
  Row: Integer;
begin
  if FService = nil then
    Exit;

  try
    FUsers := FService.ListUsers;
  except
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;

  grdUsers.BeginUpdate;
  try
    grdUsers.ColCount := 5;
    grdUsers.RowCount := Length(FUsers) + 1;
    grdUsers.FixedRows := 1;

    for Row := 0 to High(FUsers) do
    begin
      grdUsers.Cells[ColName, Row + 1] := FUsers[Row].UserName;
      grdUsers.Cells[ColFullName, Row + 1] :=
        Trim(Trim(FUsers[Row].FirstName) + ' ' +
             Trim(FUsers[Row].MiddleName) + ' ' + Trim(FUsers[Row].LastName));
      if FUsers[Row].Active then
        grdUsers.Cells[ColActive, Row + 1] := LangStr('word.yes', 'Yes')
      else
        grdUsers.Cells[ColActive, Row + 1] := LangStr('word.no', 'No');
      if FUsers[Row].AdminRole then
        grdUsers.Cells[ColAdmin, Row + 1] := LangStr('word.yes', 'Yes')
      else
        grdUsers.Cells[ColAdmin, Row + 1] := LangStr('word.no', 'No');
      grdUsers.Cells[ColPlugin, Row + 1] := FUsers[Row].Plugin;
    end;
  finally
    grdUsers.EndUpdate;
  end;

  if Length(FUsers) = 0 then
    lblStatus.Caption := LangStr('user.noneVisible',
      'The server showed no users. Only an administrator sees other people''s ' +
      'accounts.')
  else
    lblStatus.Caption := LangStrFormat('user.count', [Length(FUsers)],
      '%d user(s)');

  if Length(FUsers) > 0 then
  begin
    grdUsers.Row := 1;
    ShowAccount(FUsers[0]);
  end
  else
    ShowAccount(EmptyUserAccount);

  SetEditingNew(False);
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.ShowAccount
  ----------------------------------------------------------------------------
  Fills the fields from one account.

  Parameters:
    AAccount - What to show.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.ShowAccount(const AAccount: TUserAccount);
begin
  edtUserName.Text := Trim(AAccount.UserName);
  edtFirstName.Text := Trim(AAccount.FirstName);
  edtMiddleName.Text := Trim(AAccount.MiddleName);
  edtLastName.Text := Trim(AAccount.LastName);
  chkActive.Checked := AAccount.Active;
  chkAdminRole.Checked := AAccount.AdminRole;
  lblPluginValue.Caption := Trim(AAccount.Plugin);

  { never carried over from the previous selection }
  edtPassword.Text := '';
  edtConfirm.Text := '';
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.AccountFromFields
  ----------------------------------------------------------------------------
  Builds an account from what is on the form.

  Returns:
    The account. The password is NOT part of it; it is passed separately,
    because an account is something to show and a password is not.
------------------------------------------------------------------------------}
function TfrmIbqUserManager.AccountFromFields: TUserAccount;
begin
  Result := EmptyUserAccount;
  Result.UserName := Trim(edtUserName.Text);
  Result.FirstName := Trim(edtFirstName.Text);
  Result.MiddleName := Trim(edtMiddleName.Text);
  Result.LastName := Trim(edtLastName.Text);
  Result.Active := chkActive.Checked;
  Result.AdminRole := chkAdminRole.Checked;
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.SelectedAccount
  ----------------------------------------------------------------------------
  Returns the account the grid row points at.

  Parameters:
    AAccount - Receives the account.

  Returns:
    True when a user row is selected.
------------------------------------------------------------------------------}
function TfrmIbqUserManager.SelectedAccount(out AAccount: TUserAccount): Boolean;
var
  Index: Integer;
begin
  AAccount := EmptyUserAccount;
  Index := grdUsers.Row - 1;
  Result := (Index >= 0) and (Index <= High(FUsers));
  if Result then
    AAccount := FUsers[Index];
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.SetEditingNew
  ----------------------------------------------------------------------------
  Switches between editing an existing user and entering a new one.

  Parameters:
    AIsNew - True while a new user is being entered.

  Notes:
    The name is read-only for an existing user. Firebird has no rename: writing
    a different name would create a second account and leave the first one
    exactly where it was, which is not what anyone typing over a name means.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.SetEditingNew(AIsNew: Boolean);
begin
  FIsNew := AIsNew;
  edtUserName.ReadOnly := not AIsNew;
  btnDelete.Enabled := not AIsNew;
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.grdUsersSelection
  ----------------------------------------------------------------------------
  Shows the account of the row the user moved to.

  Parameters:
    aRow - The row now selected.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.grdUsersSelection(Sender: TObject;
  aCol, aRow: Integer);
var
  Index: Integer;
begin
  Index := aRow - 1;
  if (Index < 0) or (Index > High(FUsers)) then
    Exit;
  ShowAccount(FUsers[Index]);
  SetEditingNew(False);
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.btnNewClick
  ----------------------------------------------------------------------------
  Clears the fields for a new user.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.btnNewClick(Sender: TObject);
begin
  ShowAccount(EmptyUserAccount);
  SetEditingNew(True);
  lblStatus.Caption := LangStr('user.entering',
    'Enter the new user and press Save.');
  edtUserName.SetFocus;
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.btnSaveClick
  ----------------------------------------------------------------------------
  Creates or changes the user on the form.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.btnSaveClick(Sender: TObject);
var
  Account: TUserAccount;
  Password: string;
begin
  if FService = nil then
    Exit;

  Account := AccountFromFields;
  Password := edtPassword.Text;

  if Account.UserName = '' then
  begin
    MessageDlg(Caption, LangStr('msg.userNeedsName', 'A user needs a name.'),
      mtInformation, [mbOK], 0);
    edtUserName.SetFocus;
    Exit;
  end;

  if Password <> edtConfirm.Text then
  begin
    MessageDlg(Caption,
      LangStr('msg.passwordsDiffer', 'The two passwords are not the same.'),
      mtInformation, [mbOK], 0);
    edtConfirm.SetFocus;
    Exit;
  end;

  if FIsNew and (Password = '') then
  begin
    MessageDlg(Caption,
      LangStr('msg.newUserNeedsPassword', 'A new user needs a password.'),
      mtInformation, [mbOK], 0);
    edtPassword.SetFocus;
    Exit;
  end;

  try
    if FIsNew then
      FService.AddUser(Account, Password)
    else
      FService.ModifyUser(Account, Password);
  except
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;

  LoadUsers;
  lblStatus.Caption := LangStrFormat('user.saved', [Account.UserName],
    'Saved %s.');
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.btnDeleteClick
  ----------------------------------------------------------------------------
  Removes the selected user, after asking.

  Notes:
    The question names the user. Dropping the wrong account is not something
    that shows up until somebody cannot log in.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.btnDeleteClick(Sender: TObject);
var
  Account: TUserAccount;
begin
  if (FService = nil) or not SelectedAccount(Account) then
    Exit;

  if MessageDlg(Caption,
    LangStrFormat('msg.confirmDropUser', [Trim(Account.UserName)],
      'Delete the user %s?' + LineEnding + LineEnding +
      'Anything they own stays where it is; only the account goes.'),
    mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  try
    FService.DeleteUser(Account.UserName);
  except
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;

  LoadUsers;
  lblStatus.Caption := LangStrFormat('user.deleted', [Trim(Account.UserName)],
    'Deleted %s.');
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.btnRefreshClick
  ----------------------------------------------------------------------------
  Re-reads the list from the server.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.btnRefreshClick(Sender: TObject);
begin
  LoadUsers;
end;

{------------------------------------------------------------------------------
  TfrmIbqUserManager.ReportError
  ----------------------------------------------------------------------------
  Shows a failure and records it.

  Parameters:
    E - What went wrong.
------------------------------------------------------------------------------}
procedure TfrmIbqUserManager.ReportError(E: Exception);
begin
  Log.Error(E.Message);
  lblStatus.Caption := LangStr('user.failed', 'Failed.');
  MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
end;

end.
