{==============================================================================
  Unit:        frmConnectedUsers
  Purpose:     Shows who is connected to a database and lets an administrator
               disconnect one of them.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
               Grids, Dialogs, LanguageHandle, AppLog, MetaDatabase,
               AttachmentService

  IBConsole equivalent: Database > Maintenance > Connected Users.

  The list is read through the connected database rather than the Services
  API, because attachments belong to a database. That makes this the one
  administration dialog that needs the database open - see AttachmentService
  for why.

  The dialog will not disconnect the session it is reading through. Doing so
  would work, and would drop the user out of the database they are looking at,
  so the row is marked and the button refuses it.
==============================================================================}
unit frmConnectedUsers;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Grids,
  Dialogs,
  LanguageHandle, AppLog, MetaDatabase, AttachmentService;

type
  { TfrmIbqConnectedUsers
    The connected-users dialog.

    Takes over the service it is given when told to, and frees it with
    itself. }
  TfrmIbqConnectedUsers = class(TForm, ILocalizable)
    pnlHeader: TPanel;
    lblDatabase: TLabel;
    lblDatabaseValue: TLabel;
    lblWarning: TLabel;
    grdAttachments: TStringGrid;
    pnlButtons: TPanel;
    lblStatus: TLabel;
    btnDisconnect: TButton;
    btnRefresh: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnDisconnectClick(Sender: TObject);
    procedure grdAttachmentsSelection(Sender: TObject; aCol, aRow: Integer);
  private
    FService: TAttachmentService;
    FOwnsService: Boolean;
    FAttachments: TAttachmentArray;
    { Reads the list from the database into FAttachments and the grid. }
    procedure LoadAttachments;
    { Writes FAttachments into the grid. }
    procedure FillGrid;
    { Returns the index into FAttachments of the selected row, or -1. }
    function SelectedIndex: Integer;
    { Enables the buttons that the current state allows. }
    procedure UpdateButtons;
    { Returns the localised name of a state. }
    function StateText(AState: TAttachmentState): string;
    { Logs an error and shows it. }
    procedure ReportError(E: Exception);
  public
    destructor Destroy; override;

    { Prepares the dialog.

      Parameters:
        AService     - The service to work through. Taken over when
                       AOwnsService is True.
        AOwnsService - True when this form should free AService.
        ACaption     - The database, for the header. }
    procedure PrepareFor(AService: TAttachmentService; AOwnsService: Boolean;
      const ACaption: string);

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

{ Shows the connected-users dialog for a database.

  Parameters:
    ADatabase - A CONNECTED database. Attachments are read from the database
                itself, so there is nothing to show for one that is not open. }
procedure ConnectedUsersDialog(ADatabase: TMetaDatabase);

implementation

{$R *.lfm}

const
  { Columns of the attachment grid. }
  ColAttId = 0;
  ColUser = 1;
  ColRole = 2;
  ColAddress = 3;
  ColProcess = 4;
  ColConnected = 5;
  ColState = 6;
  ColSession = 7;
  ColCount = 8;

{------------------------------------------------------------------------------
  ConnectedUsersDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure ConnectedUsersDialog(ADatabase: TMetaDatabase);
var
  Dialog: TfrmIbqConnectedUsers;
  Service: TAttachmentService;
begin
  if ADatabase = nil then
  begin
    Exit;
  end;

  if not ADatabase.IsConnected then
  begin
    MessageDlg(LangStr('frmConnectedUsers.caption', 'Connected Users'),
      LangStr('msg.attachmentsNeedConnection',
        'Connect to the database first. Attachments are read from the ' +
        'database itself, so listing them needs a connection to it.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Service := ADatabase.CreateAttachmentService;
  if Service = nil then
  begin
    Exit;
  end;

  Dialog := TfrmIbqConnectedUsers.Create(nil);
  try
    Dialog.PrepareFor(Service, True, ADatabase.DisplayName);
    Dialog.ShowModal;
  finally
    Dialog.Free;      // frees the service with it
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.

  Parameters:
    Sender - The form.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.Destroy
  ----------------------------------------------------------------------------
  Frees the service when this form was told to own it.
------------------------------------------------------------------------------}
destructor TfrmIbqConnectedUsers.Destroy;
begin
  if FOwnsService then
  begin
    FService.Free;
  end;
  FService := nil;
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language.

  Notes:
    Refills the grid afterwards, because the state and session columns hold
    translated words rather than data.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.LoadLangStr;
begin
  Caption := LangStr('frmConnectedUsers.caption', 'Connected Users');

  lblDatabase.Caption := LangStr('maint.database', 'Database');
  lblWarning.Caption := LangStr('attach.warning',
    'Disconnecting ends the connection at once and rolls back whatever it ' +
    'was doing. The client is not asked and cannot refuse.');

  btnDisconnect.Caption := LangStr('attach.disconnect', 'Disconnect');
  btnRefresh.Caption := LangStr('btnRefresh.caption', 'Refresh');
  btnClose.Caption := LangStr('btnClose.caption', 'Close');

  if grdAttachments.ColCount >= ColCount then
  begin
    grdAttachments.Cells[ColAttId, 0] := LangStr('attach.id', 'Attachment');
    grdAttachments.Cells[ColUser, 0] := LangStr('user.name', 'User name');
    grdAttachments.Cells[ColRole, 0] := LangStr('attach.role', 'Role');
    grdAttachments.Cells[ColAddress, 0] :=
      LangStr('attach.address', 'Address');
    grdAttachments.Cells[ColProcess, 0] :=
      LangStr('attach.process', 'Client program');
    grdAttachments.Cells[ColConnected, 0] :=
      LangStr('attach.connectedAt', 'Connected at');
    grdAttachments.Cells[ColState, 0] := LangStr('attach.state', 'State');
    grdAttachments.Cells[ColSession, 0] :=
      LangStr('attach.session', 'Session');
  end;

  FillGrid;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.PrepareFor
  ----------------------------------------------------------------------------
  Prepares the dialog.

  Parameters:
    AService     - The service to work through.
    AOwnsService - True when this form should free AService.
    ACaption     - The database, for the header.

  Notes:
    Reads the list straight away. Unlike the Services API dialogs there is no
    password to ask for: the database is already open.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.PrepareFor(AService: TAttachmentService;
  AOwnsService: Boolean; const ACaption: string);
begin
  FService := AService;
  FOwnsService := AOwnsService;
  lblDatabaseValue.Caption := ACaption;
  LoadAttachments;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.LoadAttachments
  ----------------------------------------------------------------------------
  Reads the list from the database into FAttachments and the grid.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.LoadAttachments;
var
  Reason: string;
begin
  if FService = nil then
  begin
    Exit;
  end;

  Reason := FService.Unavailable;
  if Reason <> '' then
  begin
    MessageDlg(Caption, Reason, mtInformation, [mbOK], 0);
    Exit;
  end;

  try
    FAttachments := FService.List;
  except
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;

  FillGrid;
  lblStatus.Caption := LangStrFormat('attach.count',
    [Length(FAttachments)], '%d attachment(s) connected.');
  UpdateButtons;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.FillGrid
  ----------------------------------------------------------------------------
  Writes FAttachments into the grid.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.FillGrid;
var
  Row: Integer;
begin
  grdAttachments.BeginUpdate;
  try
    grdAttachments.ColCount := ColCount;
    grdAttachments.RowCount := Length(FAttachments) + 1;
    grdAttachments.FixedRows := 1;

    for Row := 0 to High(FAttachments) do
    begin
      grdAttachments.Cells[ColAttId, Row + 1] :=
        IntToStr(FAttachments[Row].Id);
      grdAttachments.Cells[ColUser, Row + 1] := FAttachments[Row].UserName;
      grdAttachments.Cells[ColRole, Row + 1] := FAttachments[Row].RoleName;
      grdAttachments.Cells[ColAddress, Row + 1] :=
        FAttachments[Row].RemoteAddress;
      grdAttachments.Cells[ColProcess, Row + 1] :=
        FAttachments[Row].RemoteProcess;
      grdAttachments.Cells[ColConnected, Row + 1] :=
        FAttachments[Row].ConnectedAt;
      grdAttachments.Cells[ColState, Row + 1] :=
        StateText(FAttachments[Row].State);
      if FAttachments[Row].IsSelf then
      begin
        grdAttachments.Cells[ColSession, Row + 1] :=
          LangStr('attach.thisSession', 'This one');
      end
      else
      begin
        grdAttachments.Cells[ColSession, Row + 1] := '';
      end;
    end;
  finally
    grdAttachments.EndUpdate;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.SelectedIndex
  ----------------------------------------------------------------------------
  Returns the index into FAttachments of the selected row, or -1.

  Returns:
    The index, or -1 when the selection is the header row or the list is
    empty.
------------------------------------------------------------------------------}
function TfrmIbqConnectedUsers.SelectedIndex: Integer;
begin
  Result := grdAttachments.Row - 1;
  if (Result < 0) or (Result > High(FAttachments)) then
  begin
    Result := -1;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.UpdateButtons
  ----------------------------------------------------------------------------
  Enables the buttons that the current state allows.

  Notes:
    Disconnect stays disabled on our own attachment. Ending it would work and
    would drop this program out of the database, so the answer is to refuse
    rather than to warn.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.UpdateButtons;
var
  Index: Integer;
begin
  Index := SelectedIndex;
  btnDisconnect.Enabled := (Index >= 0) and not FAttachments[Index].IsSelf;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.StateText
  ----------------------------------------------------------------------------
  Returns the localised name of a state.

  Parameters:
    AState - What the attachment is doing.

  Returns:
    The name to show in the grid.
------------------------------------------------------------------------------}
function TfrmIbqConnectedUsers.StateText(AState: TAttachmentState): string;
begin
  case AState of
    asActive:
      Result := LangStr('attach.stateActive', 'Running');
  else
    Result := LangStr('attach.stateIdle', 'Idle');
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.ReportError
  ----------------------------------------------------------------------------
  Logs an error and shows it.

  Parameters:
    E - What went wrong.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.ReportError(E: Exception);
begin
  Log.Error(E.Message);
  lblStatus.Caption := LangStr('attach.failed', 'Failed.');
  MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.btnRefreshClick
  ----------------------------------------------------------------------------
  Re-reads the list of attachments.

  Parameters:
    Sender - The Refresh button.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.btnRefreshClick(Sender: TObject);
begin
  LoadAttachments;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.grdAttachmentsSelection
  ----------------------------------------------------------------------------
  Enables Disconnect once a row that is not our own is selected.

  Parameters:
    Sender - The grid.
    aCol   - The selected column; not used, the whole row is selected.
    aRow   - The selected row.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.grdAttachmentsSelection(Sender: TObject;
  aCol, aRow: Integer);
begin
  UpdateButtons;
end;

{------------------------------------------------------------------------------
  TfrmIbqConnectedUsers.btnDisconnectClick
  ----------------------------------------------------------------------------
  Ends the selected attachment, after asking whether that is meant.

  Parameters:
    Sender - The Disconnect button.

  Notes:
    The confirmation names the user, because an attachment id means nothing to
    the person deciding and a name means everything.
------------------------------------------------------------------------------}
procedure TfrmIbqConnectedUsers.btnDisconnectClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := SelectedIndex;
  if Index < 0 then
  begin
    Exit;
  end;

  if FAttachments[Index].IsSelf then
  begin
    Exit;
  end;

  if MessageDlg(Caption,
    LangStrFormat('attach.confirm', [FAttachments[Index].Describe],
      'Disconnect %s? Whatever it is doing is rolled back.'),
    mtWarning, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;

  try
    FService.Disconnect(FAttachments[Index].Id);
  except
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;

  lblStatus.Caption := LangStr('attach.disconnected', 'Disconnected.');
  LoadAttachments;
end;

end.
