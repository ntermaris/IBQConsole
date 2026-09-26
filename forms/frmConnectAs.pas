{==============================================================================
  Unit:        frmConnectAs
  Purpose:     Asks for the user, password and role to attach to one database
               with, in place of the ones its registration names.
  Author:      Alexandros Ntermaris
  Created:     2026-09-26
  Depends on:  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, Dialogs,
               LanguageHandle

  IBConsole equivalent: Database > Connect As.

  The dialog only collects. It never touches the registration and never
  attaches: the caller hands the answers to TMetaDatabase.ConnectAs, which
  uses them for one connection and forgets them. Checking what a different
  user or role can see is the whole point of the command, and it would defeat
  that point if trying one quietly became the registered default.
==============================================================================}
unit frmConnectAs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, Dialogs,
  LanguageHandle;

type
  { TfrmIbqConnectAs
    Collects a user, password and role. Owns nothing. }
  TfrmIbqConnectAs = class(TForm, ILocalizable)
    lblDatabase: TLabel;
    lblUser: TLabel;
    edtUser: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblRole: TLabel;
    edtRole: TEdit;
    btnOK: TButton;
    btnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
  public
    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

{ Asks for the credentials to connect one database with.

  Parameters:
    ADatabaseCaption - What the database is called, shown at the top.
    AUserName        - In: the user to suggest. Out: the user entered.
    ARole            - In: the role to suggest. Out: the role entered.
    APassword        - Receives the password entered.

  Returns:
    True when the user pressed OK. }
function ConnectAsDialog(const ADatabaseCaption: string;
  var AUserName, ARole: string; out APassword: string): Boolean;

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  ConnectAsDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The password field is cleared before the form is freed, so the text does
    not linger in a control's buffer any longer than the call.
------------------------------------------------------------------------------}
function ConnectAsDialog(const ADatabaseCaption: string;
  var AUserName, ARole: string; out APassword: string): Boolean;
var
  Dialog: TfrmIbqConnectAs;
begin
  APassword := '';
  Dialog := TfrmIbqConnectAs.Create(nil);
  try
    Dialog.lblDatabase.Caption := ADatabaseCaption;
    Dialog.edtUser.Text := AUserName;
    Dialog.edtRole.Text := ARole;

    Result := Dialog.ShowModal = mrOK;
    if Result then
    begin
      AUserName := Trim(Dialog.edtUser.Text);
      ARole := Trim(Dialog.edtRole.Text);
      APassword := Dialog.edtPassword.Text;
    end;
    Dialog.edtPassword.Text := '';
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectAs.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.

  Parameters:
    Sender - The form.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectAs.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectAs.FormShow
  ----------------------------------------------------------------------------
  Puts the caret in the password field when a user is already suggested.

  Parameters:
    Sender - The form.

  Notes:
    The usual case is the suggested user with a different role, or a
    different user typed over the suggestion; either way the password is what
    is always typed, so it is where the caret goes when it can.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectAs.FormShow(Sender: TObject);
begin
  if Trim(edtUser.Text) = '' then
    ActiveControl := edtUser
  else
    ActiveControl := edtPassword;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectAs.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language.

  Notes:
    The database caption at the top is left alone: it was set by the caller
    and is a name, not text to translate.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectAs.LoadLangStr;
begin
  Caption := LangStr('frmConnectAs.caption', 'Connect As');
  lblUser.Caption := LangStr('lblUser.caption', 'User name');
  lblPassword.Caption := LangStr('maint.password', 'Password');
  lblRole.Caption := LangStr('lblRole.caption', 'Role');
  btnOK.Caption := LangStr('btnOK.caption', 'OK');
  btnCancel.Caption := LangStr('btnCancel.caption', 'Cancel');
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectAs.btnOKClick
  ----------------------------------------------------------------------------
  Closes the dialog once a user name has been given.

  Parameters:
    Sender - The OK button.

  Notes:
    An empty password is allowed through. The server decides whether it will
    accept one, and a trusted-authentication setup legitimately sends none;
    refusing here would second-guess the server's configuration.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectAs.btnOKClick(Sender: TObject);
begin
  if Trim(edtUser.Text) = '' then
  begin
    MessageDlg(Caption,
      LangStr('msg.userRequired', 'Enter the user name to connect as.'),
      mtWarning, [mbOK], 0);
    edtUser.SetFocus;
    Exit;
  end;

  ModalResult := mrOK;
end;

end.
