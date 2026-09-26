{==============================================================================
  Unit:        frmCreateDatabase
  Purpose:     Collects what is needed to create a new database file on a
               registered server.
  Author:      Alexandros Ntermaris
  Created:     2026-09-26
  Depends on:  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, Dialogs,
               LanguageHandle, ConnectionProfile, DdlStatements

  IBConsole equivalent: Database > Create Database.

  The dialog only collects. The file is created by
  TMetaDatabase.CreateDatabaseFile, and registering it afterwards is the
  caller's business; the check box here only says whether the user wants
  that.

  Dialect is not offered. IBQConsole refuses dialect 1 databases outright
  (SPECIFICATION.md 5.7), so creating one would make a file this program
  could not open.
==============================================================================}
unit frmCreateDatabase;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, Dialogs,
  LanguageHandle, ConnectionProfile;

type
  { TfrmIbqCreateDatabase
    Collects a path, owner, page size and character set. Owns nothing. }
  TfrmIbqCreateDatabase = class(TForm, ILocalizable)
    lblServer: TLabel;
    lblPath: TLabel;
    edtPath: TEdit;
    lblPathHint: TLabel;
    lblUser: TLabel;
    edtUser: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblPageSize: TLabel;
    cbxPageSize: TComboBox;
    lblCharset: TLabel;
    cbxCharset: TComboBox;
    chkRegister: TCheckBox;
    btnOK: TButton;
    btnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
  private
    { Returns the chosen page size, 0 for the server's default. }
    function PageSize: Integer;
  public
    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

{ Asks where and how to create a new database.

  Parameters:
    AServerCaption - The server it will be created on, shown at the top.
    AProfile       - In: the user and character set to suggest. Out: the
                     path, user and character set entered. Not owned.
    APassword      - Receives the password entered.
    APageSize      - Receives the page size, 0 for the server's default.
    ARegister      - Receives whether the new database should be registered.

  Returns:
    True when the user pressed Create. }
function CreateDatabaseDialog(const AServerCaption: string;
  AProfile: TConnectionProfile; out APassword: string;
  out APageSize: Integer; out ARegister: Boolean): Boolean;

implementation

uses
  DdlStatements;

{$R *.lfm}

{------------------------------------------------------------------------------
  CreateDatabaseDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function CreateDatabaseDialog(const AServerCaption: string;
  AProfile: TConnectionProfile; out APassword: string;
  out APageSize: Integer; out ARegister: Boolean): Boolean;
var
  Dialog: TfrmIbqCreateDatabase;
begin
  APassword := '';
  APageSize := 0;
  ARegister := False;

  Dialog := TfrmIbqCreateDatabase.Create(nil);
  try
    Dialog.lblServer.Caption := AServerCaption;
    Dialog.edtPath.Text := AProfile.DatabasePath;
    Dialog.edtUser.Text := AProfile.UserName;
    if AProfile.CharacterSet <> '' then
      Dialog.cbxCharset.Text := AProfile.CharacterSet;

    Result := Dialog.ShowModal = mrOK;
    if Result then
    begin
      AProfile.DatabasePath := Trim(Dialog.edtPath.Text);
      AProfile.UserName := Trim(Dialog.edtUser.Text);
      AProfile.CharacterSet := UpperCase(Trim(Dialog.cbxCharset.Text));
      APassword := Dialog.edtPassword.Text;
      APageSize := Dialog.PageSize;
      ARegister := Dialog.chkRegister.Checked;
    end;
    Dialog.edtPassword.Text := '';
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqCreateDatabase.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.

  Parameters:
    Sender - The form.
------------------------------------------------------------------------------}
procedure TfrmIbqCreateDatabase.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqCreateDatabase.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language.

  Notes:
    Only the first page-size entry is text; the rest are numbers. It is
    replaced in place so the selection survives a language switch.
------------------------------------------------------------------------------}
procedure TfrmIbqCreateDatabase.LoadLangStr;
var
  Selected: Integer;
begin
  Caption := LangStr('frmCreateDatabase.caption', 'Create Database');
  lblPath.Caption := LangStr('createdb.path', 'Database file');
  lblPathHint.Caption := LangStr('createdb.pathHint',
    'The path as the server sees it, or an alias.');
  lblUser.Caption := LangStr('lblUser.caption', 'User name');
  lblPassword.Caption := LangStr('maint.password', 'Password');
  lblPageSize.Caption := LangStr('createdb.pageSize', 'Page size');
  lblCharset.Caption := LangStr('createdb.charset', 'Character set');
  chkRegister.Caption := LangStr('createdb.register',
    'Register the new database');
  btnOK.Caption := LangStr('createdb.create', 'Create');
  btnCancel.Caption := LangStr('btnCancel.caption', 'Cancel');

  Selected := cbxPageSize.ItemIndex;
  cbxPageSize.Items[0] := LangStr('createdb.defaultPageSize',
    'Server default');
  cbxPageSize.ItemIndex := Selected;
end;

{------------------------------------------------------------------------------
  TfrmIbqCreateDatabase.PageSize
  ----------------------------------------------------------------------------
  Returns the chosen page size.

  Returns:
    Bytes per page, or 0 when the first entry - the server's default - is
    chosen.
------------------------------------------------------------------------------}
function TfrmIbqCreateDatabase.PageSize: Integer;
begin
  if cbxPageSize.ItemIndex <= 0 then
    Result := 0
  else
    Result := StrToIntDef(cbxPageSize.Items[cbxPageSize.ItemIndex], 0);
end;

{------------------------------------------------------------------------------
  TfrmIbqCreateDatabase.btnOKClick
  ----------------------------------------------------------------------------
  Closes the dialog once a path and a user have been given.

  Parameters:
    Sender - The Create button.
------------------------------------------------------------------------------}
procedure TfrmIbqCreateDatabase.btnOKClick(Sender: TObject);
begin
  if Trim(edtPath.Text) = '' then
  begin
    MessageDlg(Caption,
      LangStr('msg.createPathRequired',
        'Enter the path of the new database file.'),
      mtWarning, [mbOK], 0);
    edtPath.SetFocus;
    Exit;
  end;

  if Trim(edtUser.Text) = '' then
  begin
    MessageDlg(Caption,
      LangStr('msg.userRequired', 'Enter the user name to connect as.'),
      mtWarning, [mbOK], 0);
    edtUser.SetFocus;
    Exit;
  end;

  // the list only offers valid sizes; this guards an edited .lfm
  if not IsValidPageSize(PageSize) then
  begin
    cbxPageSize.SetFocus;
    Exit;
  end;

  ModalResult := mrOK;
end;

end.
