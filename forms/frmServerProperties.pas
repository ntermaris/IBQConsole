{==============================================================================
  Unit:        frmServerProperties
  Purpose:     Shows what is registered about a server and what that server
               reports about itself through the Services Manager.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, Forms, Controls, Graphics, Grids, StdCtrls,
               ExtCtrls, Dialogs, LanguageHandle, AppLog, IbqError,
               ServerRegistration, ServiceConnection, FbClientLocator

  IBConsole equivalent: Server > Properties.

  Two halves, and the split is the point. The REGISTRATION half is what this
  program was told - host, port, user, which client library to load - and is
  shown immediately, without a password and without the server having to be
  running. The SERVER half is what the server says about itself, and needs an
  attachment to its Services Manager.

  Showing the first half regardless is deliberate: the moment a user most
  wants to look at a server's properties is when it will not answer, and a
  dialog that refuses to open until the server responds is useless exactly
  then. A failed read fills the status line and leaves the registration half
  on screen.
==============================================================================}
unit frmServerProperties;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Grids, StdCtrls, ExtCtrls,
  Dialogs,
  LanguageHandle, AppLog, ServerRegistration, ServiceConnection,
  FbClientLocator;

type
  { TfrmIbqServerProperties
    The server properties dialog.

    Borrows the registration it is given and never frees it; it belongs to the
    registration store. The service attachment is opened and closed inside a
    single read, so the dialog holds no connection while it sits open. }
  TfrmIbqServerProperties = class(TForm, ILocalizable)
    pnlHeader: TPanel;
    lblServer: TLabel;
    lblServerValue: TLabel;
    lblUser: TLabel;
    edtUser: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    btnRead: TButton;
    grdProperties: TStringGrid;
    pnlButtons: TPanel;
    lblStatus: TLabel;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnReadClick(Sender: TObject);
    procedure grdPropertiesPrepareCanvas(Sender: TObject; aCol, aRow: Integer;
      aState: TGridDrawState);
  private
    FRegistration: TServerRegistration;
    FSectionRows: array of Integer;
    { Empties the grid and forgets which rows were section headings. }
    procedure ClearRows;
    { Appends a heading row and remembers it so it can be drawn in bold. }
    procedure AddSection(const ACaption: string);
    { Appends one name/value row. An empty value is written as a dash, so a
      row never looks like it failed to render. }
    procedure AddRow(const AName, AValue: string);
    { True when ARow was added by AddSection. }
    function IsSectionRow(ARow: Integer): Boolean;
    { Moves the highlight off the first section heading onto the first real
      value, so the grid does not open with a heading looking selected. }
    procedure SelectFirstValueRow;
    { Fills the grid with the registration half, which needs no server. }
    procedure ShowRegistration;
    { Appends the server half, read through a Services Manager attachment. }
    procedure ReadServerInfo(const APassword: string);
    { Logs an error, shows it, and says so on the status line. }
    procedure ReportError(E: Exception);
  public
    { Prepares the dialog for one server.

      Parameters:
        ARegistration - The server to describe. Borrowed, never freed here.
        APassword     - Password to read the server half with. When empty the
                        registration half is shown and nothing is attempted,
                        which is what happens when the user dismisses the
                        password prompt. }
    procedure PrepareFor(ARegistration: TServerRegistration;
      const APassword: string);

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

{ Shows the properties dialog for a registered server.

  Parameters:
    ARegistration - The server to describe. Does nothing when nil.
    APassword     - Password for the Services Manager, or '' to show only what
                    is registered. }
procedure ServerPropertiesDialog(ARegistration: TServerRegistration;
  const APassword: string);

implementation

{$R *.lfm}

const
  { Columns of the property grid. }
  ColName = 0;
  ColValue = 1;

{------------------------------------------------------------------------------
  ServerPropertiesDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure ServerPropertiesDialog(ARegistration: TServerRegistration;
  const APassword: string);
var
  Dialog: TfrmIbqServerProperties;
begin
  if ARegistration = nil then
  begin
    Exit;
  end;

  Dialog := TfrmIbqServerProperties.Create(nil);
  try
    Dialog.PrepareFor(ARegistration, APassword);
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.

  Parameters:
    Sender - The form.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.

  Notes:
    The grid is refilled rather than relabelled, because its first column is
    text like any caption and there is no way to translate it in place.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.LoadLangStr;
begin
  Caption := LangStr('frmServerProperties.caption', 'Server Properties');

  lblServer.Caption := LangStr('srvprop.server', 'Server');
  lblUser.Caption := LangStr('srvprop.user', 'User');
  lblPassword.Caption := LangStr('srvprop.password', 'Password');
  btnRead.Caption := LangStr('srvprop.read', 'Read');
  btnClose.Caption := LangStr('btnClose.caption', 'Close');

  grdProperties.Cells[ColName, 0] := LangStr('srvprop.colName', 'Property');
  grdProperties.Cells[ColValue, 0] := LangStr('srvprop.colValue', 'Value');

  if FRegistration <> nil then
  begin
    ShowRegistration;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.PrepareFor
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.PrepareFor(
  ARegistration: TServerRegistration; const APassword: string);
begin
  FRegistration := ARegistration;
  lblServerValue.Caption := FRegistration.TreeCaption;
  edtUser.Text := FRegistration.UserName;

  ShowRegistration;

  if APassword <> '' then
  begin
    ReadServerInfo(APassword);
  end
  else
  begin
    lblStatus.Caption := LangStr('srvprop.needPassword',
      'Enter the password and press Read to ask the server about itself.');
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.ClearRows
  ----------------------------------------------------------------------------
  Empties the grid and forgets which rows were section headings.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.ClearRows;
begin
  grdProperties.RowCount := 1;
  SetLength(FSectionRows, 0);
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.AddSection
  ----------------------------------------------------------------------------
  Appends a heading row and remembers it so it can be drawn in bold.

  Parameters:
    ACaption - The heading text.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.AddSection(const ACaption: string);
var
  Row: Integer;
begin
  Row := grdProperties.RowCount;
  grdProperties.RowCount := Row + 1;
  grdProperties.Cells[ColName, Row] := ACaption;
  grdProperties.Cells[ColValue, Row] := '';

  SetLength(FSectionRows, Length(FSectionRows) + 1);
  FSectionRows[High(FSectionRows)] := Row;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.AddRow
  ----------------------------------------------------------------------------
  Appends one name/value row.

  Parameters:
    AName  - What the value is.
    AValue - The value. An empty one is written as a dash.

  Notes:
    A dash rather than a blank cell, because a server legitimately reports
    nothing for some of these - Firebird 3 gives no message file location -
    and an empty cell reads as a bug in the dialog rather than as an answer.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.AddRow(const AName, AValue: string);
var
  Row: Integer;
begin
  Row := grdProperties.RowCount;
  grdProperties.RowCount := Row + 1;
  grdProperties.Cells[ColName, Row] := AName;
  if Trim(AValue) = '' then
  begin
    grdProperties.Cells[ColValue, Row] := '-';
  end
  else
  begin
    grdProperties.Cells[ColValue, Row] := AValue;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.IsSectionRow
  ----------------------------------------------------------------------------
  Returns True when ARow was added by AddSection.

  Parameters:
    ARow - Row index in the grid.

  Returns:
    True for a heading row.
------------------------------------------------------------------------------}
function TfrmIbqServerProperties.IsSectionRow(ARow: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(FSectionRows) to High(FSectionRows) do
  begin
    if FSectionRows[I] = ARow then
    begin
      Exit(True);
    end;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.SelectFirstValueRow
  ----------------------------------------------------------------------------
  Moves the highlight off the first section heading onto the first real value.

  Notes:
    A grid always has a current row, and row 1 is always a heading here. A
    highlighted heading reads as something the user clicked, in a dialog where
    nothing is meant to be clickable.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.SelectFirstValueRow;
begin
  if grdProperties.RowCount > 2 then
  begin
    grdProperties.Row := 2;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.grdPropertiesPrepareCanvas
  ----------------------------------------------------------------------------
  Draws section headings in bold.

  Parameters:
    aCol   - Column being drawn.
    aRow   - Row being drawn.
    aState - Draw state, unused.

  Notes:
    Serves grdProperties.OnPrepareCanvas. Two sections in one flat list read
    far better than two grids, and this is the whole cost of having them.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.grdPropertiesPrepareCanvas(Sender: TObject;
  aCol, aRow: Integer; aState: TGridDrawState);
begin
  if IsSectionRow(aRow) then
  begin
    grdProperties.Canvas.Font.Style :=
      grdProperties.Canvas.Font.Style + [fsBold];
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.ShowRegistration
  ----------------------------------------------------------------------------
  Fills the grid with the registration half, which needs no server.

  Notes:
    The client library gets its version read here rather than being shown as a
    bare path. Which fbclient a registration loads is the difference between
    reaching this server and reaching another one, so naming the version is
    the point of showing the row at all.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.ShowRegistration;
var
  Info: TFbClientInfo;
  ClientText: string;
begin
  ClearRows;
  AddSection(LangStr('srvprop.registration', 'Registration'));
  AddRow(LangStr('srvprop.displayName', 'Display name'),
    FRegistration.DisplayName);
  AddRow(LangStr('srvprop.host', 'Host'), FRegistration.Host);
  AddRow(LangStr('srvprop.port', 'Port'), IntToStr(FRegistration.Port));
  AddRow(LangStr('srvprop.userName', 'User name'), FRegistration.UserName);

  ClientText := FRegistration.ClientLibrary;
  if ClientText = '' then
  begin
    ClientText := LangStr('srvprop.clientDefault',
      'not set - the system default is used');
  end
  else if ReadClientInfo(ClientText, Info) then
  begin
    ClientText := Info.DisplayText;
  end;
  AddRow(LangStr('srvprop.clientLibrary', 'Client library'), ClientText);

  AddRow(LangStr('srvprop.databaseCountReg', 'Registered databases'),
    IntToStr(FRegistration.DatabaseCount));
  AddRow(LangStr('srvprop.description', 'Description'),
    FRegistration.Description);

  SelectFirstValueRow;
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.ReadServerInfo
  ----------------------------------------------------------------------------
  Appends the server half, read through a Services Manager attachment.

  Parameters:
    APassword - Password to attach with. Never stored.

  Notes:
    The attachment is opened and closed inside this routine. A properties
    dialog left open for an hour must not hold a service attachment open for
    an hour - and the Services Manager is also how a maintenance task is
    cancelled, by detaching from it, so an idle one is not free.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.ReadServerInfo(const APassword: string);
var
  Service: TServiceConnection;
  Info: TServerInfo;
  I: Integer;
begin
  ShowRegistration;
  lblStatus.Caption := LangStr('srvprop.reading', 'Reading...');
  Application.ProcessMessages;

  Service := TServiceConnection.Create(FRegistration);
  try
    try
      Service.Connect(APassword);
      Info := Service.Info;
      Service.Disconnect;
    except
      on E: Exception do
      begin
        ReportError(E);
        Exit;
      end;
    end;
  finally
    Service.Free;
  end;

  AddSection(LangStr('srvprop.server', 'Server'));
  AddRow(LangStr('srvprop.version', 'Version'), Info.VersionText);
  AddRow(LangStr('srvprop.engine', 'Engine'), Info.Version.DisplayText);
  AddRow(LangStr('srvprop.implementation', 'Implementation'),
    Info.ImplementationText);
  AddRow(LangStr('srvprop.serviceVersion', 'Services protocol'),
    IntToStr(Info.ServiceVersion));
  AddRow(LangStr('srvprop.baseLocation', 'Install directory'),
    Info.BaseLocation);
  AddRow(LangStr('srvprop.lockLocation', 'Lock directory'),
    Info.LockFileLocation);
  AddRow(LangStr('srvprop.messageLocation', 'Message file'),
    Info.MessageFileLocation);
  AddRow(LangStr('srvprop.securityDatabase', 'Security database'),
    Info.SecurityDatabase);
  AddRow(LangStr('srvprop.attachments', 'Attachments'),
    IntToStr(Info.AttachmentCount));

  AddSection(LangStrFormat('srvprop.openDatabases', [Info.DatabaseCount],
    'Open databases (%d)'));
  if Length(Info.DatabaseNames) = 0 then
  begin
    AddRow('', LangStr('srvprop.noneOpen', 'None'));
  end
  else
  begin
    for I := Low(Info.DatabaseNames) to High(Info.DatabaseNames) do
    begin
      AddRow(IntToStr(I + 1), Info.DatabaseNames[I]);
    end;
  end;

  grdProperties.AutoSizeColumn(ColName);
  lblStatus.Caption := LangStr('srvprop.read.ok', 'Read from the server.');
  Log.Info(Format('server properties read for %s',
    [FRegistration.TreeCaption]));
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.btnReadClick
  ----------------------------------------------------------------------------
  Reads the server half using the password on the form.

  Parameters:
    Sender - The Read button.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.btnReadClick(Sender: TObject);
begin
  if edtPassword.Text = '' then
  begin
    lblStatus.Caption := LangStr('srvprop.needPassword',
      'Enter the password and press Read to ask the server about itself.');
    edtPassword.SetFocus;
    Exit;
  end;

  ReadServerInfo(edtPassword.Text);
end;

{------------------------------------------------------------------------------
  TfrmIbqServerProperties.ReportError
  ----------------------------------------------------------------------------
  Logs an error, shows it, and says so on the status line.

  Parameters:
    E - The exception to report.
------------------------------------------------------------------------------}
procedure TfrmIbqServerProperties.ReportError(E: Exception);
begin
  Log.Error(E.Message);
  lblStatus.Caption := LangStr('srvprop.read.failed',
    'The server could not be read.');
  MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
end;

end.
