{==============================================================================
  Unit:        frmTransactionRecovery
  Purpose:     Lists the transactions a database has left in limbo and lets the
               administrator decide each one.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
               Grids, Dialogs, LanguageHandle, AppLog, MetaDatabase,
               ServerRegistration, TransactionRecoveryService

  IBConsole equivalent: Database > Maintenance > Transaction Recovery.

  The dialog reads its list through the Services API, which needs a password
  the connected database cannot supply, so the credentials are typed here -
  exactly as the maintenance dialog does for the same reason.

  Resolving is not undoable and the Services API resolves the whole list at
  once. Both facts are stated on the form rather than buried here, because the
  person who needs to know them is the one looking at it.
==============================================================================}
unit frmTransactionRecovery;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Grids,
  Dialogs,
  LanguageHandle, AppLog, MetaDatabase, ServerRegistration,
  TransactionRecoveryService;

type
  { TfrmIbqTransactionRecovery
    The transaction recovery dialog.

    Owns no registration: it is passed one that outlives it. The service
    objects it uses are created for one operation and freed with it. }
  TfrmIbqTransactionRecovery = class(TForm, ILocalizable)
    pnlHeader: TPanel;
    lblServer: TLabel;
    lblServerValue: TLabel;
    lblDatabase: TLabel;
    lblDatabaseValue: TLabel;
    lblUser: TLabel;
    edtUser: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    pnlActions: TPanel;
    lblSetAction: TLabel;
    btnSetCommit: TButton;
    btnSetRollback: TButton;
    btnUseAdvice: TButton;
    lblAllOrNothing: TLabel;
    grdTransactions: TStringGrid;
    splOutput: TSplitter;
    pnlOutput: TPanel;
    lblOutput: TLabel;
    memOutput: TMemo;
    pnlButtons: TPanel;
    lblStatus: TLabel;
    lblGlobal: TLabel;
    cbxGlobalAction: TComboBox;
    btnApply: TButton;
    btnRefresh: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnSetCommitClick(Sender: TObject);
    procedure btnSetRollbackClick(Sender: TObject);
    procedure btnUseAdviceClick(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
    procedure cbxGlobalActionChange(Sender: TObject);
    procedure grdTransactionsSelection(Sender: TObject; aCol, aRow: Integer);
  private
    FRegistration: TServerRegistration;
    FDatabasePath: string;
    FTransactions: TLimboTransactionArray;
    { Builds a service from the registration and the typed credentials. }
    function CreateService: TTransactionRecoveryService;
    { Reads the list from the server into FTransactions and the grid. }
    procedure LoadTransactions;
    { Writes FTransactions into the grid. }
    procedure FillGrid;
    { Returns the index into FTransactions of the selected row, or -1. }
    function SelectedIndex: Integer;
    { Gives the selected transaction an action and shows it. }
    procedure SetActionForSelection(AAction: TLimboAction);
    { Returns the global action the combo box is showing. }
    function SelectedGlobalAction: TGlobalRecoveryAction;
    { Returns True and complains when no password has been typed. }
    function PasswordMissing: Boolean;
    { Enables the buttons that the current state allows. }
    procedure UpdateButtons;
    { Returns the localised name of a state. }
    function StateText(AState: TLimboState): string;
    { Returns the localised name of a recommendation. }
    function AdviceText(AAdvice: TLimboAdvice): string;
    { Returns the localised name of an action. }
    function ActionText(AAction: TLimboAction): string;
    { Logs an error and shows it. }
    procedure ReportError(E: Exception);
  public
    { Prepares the dialog for one database.

      Parameters:
        ARegistration - The server the database lives on. Not owned.
        ADatabasePath - The database, as the SERVER knows it.
        AUserName     - The user to attach as; the password is typed here. }
    procedure PrepareFor(ARegistration: TServerRegistration;
      const ADatabasePath, AUserName: string);

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

{ Shows the transaction recovery dialog for a database.

  Parameters:
    ADatabase - The database whose limbo transactions are wanted. It need not
                be connected: a database with limbo transactions is often one
                nobody can work in. }
procedure TransactionRecoveryDialog(ADatabase: TMetaDatabase);

implementation

{$R *.lfm}

const
  { Columns of the transaction grid. }
  ColId = 0;
  ColType = 1;
  ColState = 2;
  ColHost = 3;
  ColRemote = 4;
  ColRemoteDb = 5;
  ColAdvice = 6;
  ColAction = 7;
  ColCount = 8;

{------------------------------------------------------------------------------
  TransactionRecoveryDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure TransactionRecoveryDialog(ADatabase: TMetaDatabase);
var
  Dialog: TfrmIbqTransactionRecovery;
begin
  if (ADatabase = nil) or (ADatabase.Profile = nil) then
  begin
    Exit;
  end;

  if not ADatabase.Profile.HasServer then
  begin
    MessageDlg(LangStr('frmTransactionRecovery.caption',
      'Transaction Recovery'),
      LangStr('msg.noServicesForEmbedded',
        'An embedded database has no server, so it has no maintenance ' +
        'services. Register it under a server to back it up.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Dialog := TfrmIbqTransactionRecovery.Create(nil);
  try
    Dialog.PrepareFor(ADatabase.ServerReg, ADatabase.Profile.DatabasePath,
      ADatabase.Profile.UserName);
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.

  Parameters:
    Sender - The form.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language.

  Notes:
    The combo box is refilled rather than re-captioned, because its items are
    the names of TGlobalRecoveryAction and those are translated too. The
    selection is kept across the refill.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.LoadLangStr;
var
  Selected: Integer;
begin
  Caption := LangStr('frmTransactionRecovery.caption',
    'Transaction Recovery');

  lblServer.Caption := LangStr('maint.server', 'Server');
  lblDatabase.Caption := LangStr('maint.database', 'Database');
  lblUser.Caption := LangStr('maint.user', 'User');
  lblPassword.Caption := LangStr('maint.password', 'Password');

  lblSetAction.Caption := LangStr('limbo.setAction',
    'For the selected transaction:');
  btnSetCommit.Caption := LangStr('limbo.commit', 'Commit');
  btnSetRollback.Caption := LangStr('limbo.rollback', 'Roll back');
  btnUseAdvice.Caption := LangStr('limbo.useAdvice', 'Use recommendation');

  lblAllOrNothing.Caption := LangStr('limbo.allOrNothing',
    'Applying resolves every transaction listed, and cannot be undone. ' +
    'To leave one in limbo, do not apply at all.');

  lblOutput.Caption := LangStr('limbo.output', 'Server output');
  lblGlobal.Caption := LangStr('limbo.decideBy', 'Decide by');

  btnApply.Caption := LangStr('limbo.apply', 'Apply');
  btnRefresh.Caption := LangStr('btnRefresh.caption', 'Refresh');
  btnClose.Caption := LangStr('btnClose.caption', 'Close');

  Selected := cbxGlobalAction.ItemIndex;
  cbxGlobalAction.Items.BeginUpdate;
  try
    cbxGlobalAction.Items.Clear;
    cbxGlobalAction.Items.Add(LangStr('limbo.perTransaction',
      'The action chosen for each transaction'));
    cbxGlobalAction.Items.Add(LangStr('limbo.commitAll',
      'Commit them all'));
    cbxGlobalAction.Items.Add(LangStr('limbo.rollbackAll',
      'Roll them all back'));
    cbxGlobalAction.Items.Add(LangStr('limbo.recoverTwoPhase',
      'Let the server finish the two-phase commit'));
  finally
    cbxGlobalAction.Items.EndUpdate;
  end;
  if (Selected >= 0) and (Selected < cbxGlobalAction.Items.Count) then
  begin
    cbxGlobalAction.ItemIndex := Selected;
  end
  else
  begin
    cbxGlobalAction.ItemIndex := 0;
  end;

  if grdTransactions.ColCount >= ColCount then
  begin
    grdTransactions.Cells[ColId, 0] := LangStr('limbo.id', 'Transaction');
    grdTransactions.Cells[ColType, 0] := LangStr('limbo.type', 'Type');
    grdTransactions.Cells[ColState, 0] := LangStr('limbo.state', 'State');
    grdTransactions.Cells[ColHost, 0] := LangStr('limbo.hostSite', 'Host');
    grdTransactions.Cells[ColRemote, 0] :=
      LangStr('limbo.remoteSite', 'Remote host');
    grdTransactions.Cells[ColRemoteDb, 0] :=
      LangStr('limbo.remoteDatabase', 'Remote database');
    grdTransactions.Cells[ColAdvice, 0] :=
      LangStr('limbo.advice', 'Recommended');
    grdTransactions.Cells[ColAction, 0] := LangStr('limbo.action', 'Action');
  end;

  FillGrid;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.PrepareFor
  ----------------------------------------------------------------------------
  Prepares the dialog for one database.

  Parameters:
    ARegistration - The server the database lives on. Not owned.
    ADatabasePath - The database, as the server knows it.
    AUserName     - The user to attach as.

  Notes:
    Does not read the list. The password has not been typed yet, and asking
    for it by failing is not asking.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.PrepareFor(
  ARegistration: TServerRegistration;
  const ADatabasePath, AUserName: string);
begin
  FRegistration := ARegistration;      // injected, NOT owned
  FDatabasePath := ADatabasePath;

  if ARegistration <> nil then
  begin
    lblServerValue.Caption := ARegistration.TreeCaption;
  end
  else
  begin
    lblServerValue.Caption := '-';
  end;
  lblDatabaseValue.Caption := ADatabasePath;

  edtUser.Text := AUserName;
  if edtUser.Text = '' then
  begin
    if ARegistration <> nil then
    begin
      edtUser.Text := ARegistration.UserName;
    end;
  end;
  if edtUser.Text = '' then
  begin
    edtUser.Text := 'SYSDBA';
  end;

  lblStatus.Caption := LangStr('limbo.notListed',
    'Type the password and press Refresh to list the limbo transactions.');
  UpdateButtons;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.CreateService
  ----------------------------------------------------------------------------
  Builds a service from the registration and the typed credentials.

  Returns:
    A new service, which the caller frees. Nil when there is no registration.

  Notes:
    The user name is written back to the registration, as the maintenance
    dialog does, so that a correction typed here is the one used next time.
------------------------------------------------------------------------------}
function TfrmIbqTransactionRecovery.CreateService:
  TTransactionRecoveryService;
begin
  if FRegistration = nil then
  begin
    Exit(nil);
  end;
  FRegistration.UserName := Trim(edtUser.Text);
  Result := TTransactionRecoveryService.Create(FRegistration,
    edtPassword.Text, FDatabasePath);
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.PasswordMissing
  ----------------------------------------------------------------------------
  Returns True and complains when no password has been typed.

  Returns:
    True when the operation must not go ahead.
------------------------------------------------------------------------------}
function TfrmIbqTransactionRecovery.PasswordMissing: Boolean;
begin
  Result := edtPassword.Text = '';
  if Result then
  begin
    MessageDlg(Caption,
      LangStr('maint.needPassword', 'Type the password first.'),
      mtInformation, [mbOK], 0);
    edtPassword.SetFocus;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.LoadTransactions
  ----------------------------------------------------------------------------
  Reads the list from the server into FTransactions and the grid.

  Notes:
    An empty list is the healthy answer and is reported as such, not as a
    failure.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.LoadTransactions;
var
  Service: TTransactionRecoveryService;
  Reason: string;
begin
  Service := CreateService;
  if Service = nil then
  begin
    Exit;
  end;
  try
    Reason := Service.Unavailable;
    if Reason <> '' then
    begin
      MessageDlg(Caption, Reason, mtInformation, [mbOK], 0);
      Exit;
    end;

    try
      FTransactions := Service.List;
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

  FillGrid;

  if Length(FTransactions) = 0 then
  begin
    lblStatus.Caption := LangStr('limbo.none',
      'No transactions are in limbo.');
  end
  else
  begin
    lblStatus.Caption := LangStrFormat('limbo.count',
      [Length(FTransactions)], '%d transaction(s) in limbo.');
  end;
  UpdateButtons;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.FillGrid
  ----------------------------------------------------------------------------
  Writes FTransactions into the grid.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.FillGrid;
var
  Row: Integer;
begin
  grdTransactions.BeginUpdate;
  try
    grdTransactions.ColCount := ColCount;
    grdTransactions.RowCount := Length(FTransactions) + 1;
    grdTransactions.FixedRows := 1;

    for Row := 0 to High(FTransactions) do
    begin
      grdTransactions.Cells[ColId, Row + 1] :=
        IntToStr(FTransactions[Row].Id);
      if FTransactions[Row].MultiDatabase then
      begin
        grdTransactions.Cells[ColType, Row + 1] :=
          LangStr('limbo.multiDatabase', 'Multi-database');
      end
      else
      begin
        grdTransactions.Cells[ColType, Row + 1] :=
          LangStr('limbo.singleDatabase', 'Single database');
      end;
      grdTransactions.Cells[ColState, Row + 1] :=
        StateText(FTransactions[Row].State);
      grdTransactions.Cells[ColHost, Row + 1] := FTransactions[Row].HostSite;
      grdTransactions.Cells[ColRemote, Row + 1] :=
        FTransactions[Row].RemoteSite;
      grdTransactions.Cells[ColRemoteDb, Row + 1] :=
        FTransactions[Row].RemoteDatabasePath;
      grdTransactions.Cells[ColAdvice, Row + 1] :=
        AdviceText(FTransactions[Row].Advice);
      grdTransactions.Cells[ColAction, Row + 1] :=
        ActionText(FTransactions[Row].Action);
    end;
  finally
    grdTransactions.EndUpdate;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.SelectedIndex
  ----------------------------------------------------------------------------
  Returns the index into FTransactions of the selected row, or -1.

  Returns:
    The index, or -1 when the selection is the header row or the list is
    empty.
------------------------------------------------------------------------------}
function TfrmIbqTransactionRecovery.SelectedIndex: Integer;
begin
  Result := grdTransactions.Row - 1;
  if (Result < 0) or (Result > High(FTransactions)) then
  begin
    Result := -1;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.SetActionForSelection
  ----------------------------------------------------------------------------
  Gives the selected transaction an action and shows it.

  Parameters:
    AAction - What to do with it when Apply is pressed.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.SetActionForSelection(
  AAction: TLimboAction);
var
  Index: Integer;
begin
  Index := SelectedIndex;
  if Index < 0 then
  begin
    Exit;
  end;
  FTransactions[Index].Action := AAction;
  grdTransactions.Cells[ColAction, Index + 1] := ActionText(AAction);
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.SelectedGlobalAction
  ----------------------------------------------------------------------------
  Returns the global action the combo box is showing.

  Returns:
    The matching TGlobalRecoveryAction; graPerTransaction when nothing is
    selected, which is the safest of the four because it is the one the grid
    is showing.
------------------------------------------------------------------------------}
function TfrmIbqTransactionRecovery.SelectedGlobalAction:
  TGlobalRecoveryAction;
begin
  case cbxGlobalAction.ItemIndex of
    1:
      Result := graCommitAll;
    2:
      Result := graRollbackAll;
    3:
      Result := graRecoverTwoPhase;
  else
    Result := graPerTransaction;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.UpdateButtons
  ----------------------------------------------------------------------------
  Enables the buttons that the current state allows.

  Notes:
    The per-transaction buttons are pointless while a global action is
    chosen, because the global action overrides every one of them.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.UpdateButtons;
var
  HasRows: Boolean;
  PerTransaction: Boolean;
begin
  HasRows := Length(FTransactions) > 0;
  PerTransaction := SelectedGlobalAction = graPerTransaction;

  btnSetCommit.Enabled := HasRows and PerTransaction and (SelectedIndex >= 0);
  btnSetRollback.Enabled := btnSetCommit.Enabled;
  btnUseAdvice.Enabled := btnSetCommit.Enabled;
  btnApply.Enabled := HasRows;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.StateText
  ----------------------------------------------------------------------------
  Returns the localised name of a state.

  Parameters:
    AState - What the server said had become of the transaction.

  Returns:
    The name to show in the grid.
------------------------------------------------------------------------------}
function TfrmIbqTransactionRecovery.StateText(AState: TLimboState): string;
begin
  case AState of
    lsLimbo:
      Result := LangStr('limbo.stateLimbo', 'In limbo');
    lsCommit:
      Result := LangStr('limbo.stateCommit', 'Committed elsewhere');
    lsRollback:
      Result := LangStr('limbo.stateRollback', 'Rolled back elsewhere');
  else
    Result := LangStr('limbo.stateUnknown', 'Unknown');
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.AdviceText
  ----------------------------------------------------------------------------
  Returns the localised name of a recommendation.

  Parameters:
    AAdvice - What the server recommends.

  Returns:
    The name to show in the grid.
------------------------------------------------------------------------------}
function TfrmIbqTransactionRecovery.AdviceText(
  AAdvice: TLimboAdvice): string;
begin
  case AAdvice of
    ldCommit:
      Result := LangStr('limbo.commit', 'Commit');
    ldRollback:
      Result := LangStr('limbo.rollback', 'Roll back');
  else
    Result := LangStr('limbo.noAdvice', 'None');
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.ActionText
  ----------------------------------------------------------------------------
  Returns the localised name of an action.

  Parameters:
    AAction - What will be done with the transaction.

  Returns:
    The name to show in the grid.
------------------------------------------------------------------------------}
function TfrmIbqTransactionRecovery.ActionText(
  AAction: TLimboAction): string;
begin
  case AAction of
    laRollback:
      Result := LangStr('limbo.rollback', 'Roll back');
  else
    Result := LangStr('limbo.commit', 'Commit');
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.ReportError
  ----------------------------------------------------------------------------
  Logs an error and shows it.

  Parameters:
    E - What went wrong.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.ReportError(E: Exception);
begin
  Log.Error(E.Message);
  lblStatus.Caption := LangStr('limbo.failed', 'Failed.');
  MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.btnRefreshClick
  ----------------------------------------------------------------------------
  Re-reads the list of limbo transactions from the server.

  Parameters:
    Sender - The Refresh button.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.btnRefreshClick(Sender: TObject);
begin
  if PasswordMissing then
  begin
    Exit;
  end;
  memOutput.Clear;
  LoadTransactions;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.btnSetCommitClick
  ----------------------------------------------------------------------------
  Marks the selected transaction to be committed.

  Parameters:
    Sender - The Commit button.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.btnSetCommitClick(Sender: TObject);
begin
  SetActionForSelection(laCommit);
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.btnSetRollbackClick
  ----------------------------------------------------------------------------
  Marks the selected transaction to be rolled back.

  Parameters:
    Sender - The Roll back button.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.btnSetRollbackClick(Sender: TObject);
begin
  SetActionForSelection(laRollback);
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.btnUseAdviceClick
  ----------------------------------------------------------------------------
  Puts the selected transaction back on the server's recommendation.

  Parameters:
    Sender - The Use recommendation button.

  Notes:
    A transaction the server has no recommendation for is committed, which is
    the same default the server itself reports for one.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.btnUseAdviceClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := SelectedIndex;
  if Index < 0 then
  begin
    Exit;
  end;
  if FTransactions[Index].Advice = ldRollback then
  begin
    SetActionForSelection(laRollback);
  end
  else
  begin
    SetActionForSelection(laCommit);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.cbxGlobalActionChange
  ----------------------------------------------------------------------------
  Enables or disables the per-transaction buttons to match the choice.

  Parameters:
    Sender - The Decide by combo box.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.cbxGlobalActionChange(Sender: TObject);
begin
  UpdateButtons;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.grdTransactionsSelection
  ----------------------------------------------------------------------------
  Enables the per-transaction buttons once a transaction is selected.

  Parameters:
    Sender - The grid.
    aCol   - The selected column; not used, the whole row is selected.
    aRow   - The selected row.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.grdTransactionsSelection(
  Sender: TObject; aCol, aRow: Integer);
begin
  UpdateButtons;
end;

{------------------------------------------------------------------------------
  TfrmIbqTransactionRecovery.btnApplyClick
  ----------------------------------------------------------------------------
  Resolves the listed transactions, after asking whether that is meant.

  Parameters:
    Sender - The Apply button.

  Notes:
    The confirmation names the number of transactions and says the word
    "undone", because this is the one button in the dialog that changes
    anything and nothing puts it back.
------------------------------------------------------------------------------}
procedure TfrmIbqTransactionRecovery.btnApplyClick(Sender: TObject);
var
  Service: TTransactionRecoveryService;
  Resolved: Integer;
begin
  if Length(FTransactions) = 0 then
  begin
    Exit;
  end;
  if PasswordMissing then
  begin
    Exit;
  end;

  if MessageDlg(Caption,
    LangStrFormat('limbo.confirm', [Length(FTransactions)],
      'Resolve all %d listed transaction(s)? This cannot be undone.'),
    mtWarning, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;

  memOutput.Clear;
  Service := CreateService;
  if Service = nil then
  begin
    Exit;
  end;
  try
    try
      Resolved := Service.Resolve(FTransactions, SelectedGlobalAction,
        memOutput.Lines);
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

  if Resolved = 0 then
  begin
    lblStatus.Caption := LangStr('limbo.noneLeft',
      'Nothing was left in limbo by the time the request was made.');
  end
  else
  begin
    lblStatus.Caption := LangStrFormat('limbo.resolved', [Resolved],
      '%d transaction(s) resolved.');
  end;

  LoadTransactions;
end;

end.
