{==============================================================================
  Unit:        frmExecuteRoutine
  Purpose:     Runs a stored procedure with values the user types, and shows
               what it returned.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  LCL, LanguageHandle, MetaDatabase, MetaTypes, SqlSession,
               ScriptGenerator, DatabaseRow, Identifier

  "Script as... EXECUTE" writes the call for a user to fill in and run in the
  editor. This dialog is the other half: type the values, press Execute, see
  the result. It is what turns a procedure from something to read into
  something to try.

  Selectable procedures are called with SELECT, executable ones with EXECUTE
  PROCEDURE. Which is which comes from RDB$PROCEDURE_TYPE, not from whether
  the procedure has output parameters - plenty of executable procedures have
  them, and calling either kind the wrong way simply fails.

  The call runs in its own transaction, held open until the user commits or
  rolls back, because a procedure that writes must be undoable from here.
==============================================================================}
unit frmExecuteRoutine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Grids, StdCtrls, ExtCtrls,
  ComCtrls, Dialogs,
  LanguageHandle, MetaDatabase, MetaTypes, SqlSession, ScriptGenerator,
  DatabaseRow, Identifier;

type

  { TfrmIbqExecuteRoutine
    Parameter entry, the generated call, and the result. }
  TfrmIbqExecuteRoutine = class(TForm, ILocalizable)
    pnlTop: TPanel;
    lblRoutine: TLabel;
    lblKind: TLabel;
    grdParams: TStringGrid;
    splStatement: TSplitter;
    pgcResults: TPageControl;
    tabStatement: TTabSheet;
    memStatement: TMemo;
    tabResults: TTabSheet;
    grdResults: TStringGrid;
    tabMessages: TTabSheet;
    memMessages: TMemo;
    pnlBottom: TPanel;
    btnExecute: TButton;
    btnCommit: TButton;
    btnRollback: TButton;
    btnClose: TButton;
    lblTransaction: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure btnExecuteClick(Sender: TObject);
    procedure btnCommitClick(Sender: TObject);
    procedure btnRollbackClick(Sender: TObject);
    procedure grdParamsEditingDone(Sender: TObject);
    procedure grdParamsSelectEditor(Sender: TObject; aCol, aRow: Integer;
      var Editor: TWinControl);
  private
    FDatabase: TMetaDatabase;
    FRoutine: TIdentifier;
    FSelectable: Boolean;
    FSession: TSqlSession;
    FInputCount: Integer;
    procedure LoadParameters(ANodeType: TMetaNodeType;
      const AObjectName: string);
    function BuildStatement: string;
    procedure ShowGrid(const ATable: TDataTable);
    procedure UpdateStatement;
    procedure UpdateTransactionState;
  public
    destructor Destroy; override;

    { Prepares the dialog for one routine.

      Parameters:
        ADatabase   - The connected database.
        ANodeType   - The routine's kind.
        AObjectName - Its bare name. }
    procedure PrepareFor(ADatabase: TMetaDatabase; ANodeType: TMetaNodeType;
      const AObjectName: string);

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

{ Shows the execute dialog for one routine.

  Parameters:
    ADatabase   - The connected database.
    ANodeType   - The routine's kind; anything that is not a procedure or
                  function is ignored.
    AObjectName - Its bare name. }
procedure ExecuteRoutineDialog(ADatabase: TMetaDatabase;
  ANodeType: TMetaNodeType; const AObjectName: string);

implementation

{$R *.lfm}

const
  { Columns of the parameter grid. }
  ColName = 0;
  ColDirection = 1;
  ColType = 2;
  ColValue = 3;

{------------------------------------------------------------------------------
  ExecuteRoutineDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure ExecuteRoutineDialog(ADatabase: TMetaDatabase;
  ANodeType: TMetaNodeType; const AObjectName: string);
var
  Dialog: TfrmIbqExecuteRoutine;
begin
  if (ADatabase = nil) or not ADatabase.IsConnected then
    Exit;
  if not (ANodeType in [mntProcedure, mntFunctionSQL, mntUDF]) then
    Exit;

  Dialog := TfrmIbqExecuteRoutine.Create(nil);
  try
    Dialog.PrepareFor(ADatabase, ANodeType, AObjectName);
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language and sets up the parameter grid's headings.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.Destroy
  ----------------------------------------------------------------------------
  Releases the session, which rolls back anything left uncommitted.
------------------------------------------------------------------------------}
destructor TfrmIbqExecuteRoutine.Destroy;
begin
  FreeAndNil(FSession);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.FormClose
  ----------------------------------------------------------------------------
  Warns when the routine's work has not been committed.

  Parameters:
    CloseAction - Left alone; the warning informs, it does not block. A user
                  who wants to discard the work should be able to just close.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  if (FSession <> nil) and FSession.InTransaction then
  begin
    if MessageDlg(Caption,
      LangStr('exec.confirmDiscard',
        'The procedure ran but its work has not been committed.' + LineEnding +
        'Close and discard it?'),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      CloseAction := caNone;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.LoadLangStr;
begin
  Caption := LangStr('frmExecuteRoutine.caption', 'Execute Procedure');
  btnExecute.Caption := LangStr('exec.execute', 'Execute');
  btnCommit.Caption := LangStr('exec.commit', 'Commit');
  btnRollback.Caption := LangStr('exec.rollback', 'Rollback');
  btnClose.Caption := LangStr('btnClose.caption', 'Close');

  tabStatement.Caption := LangStr('exec.statement', 'Statement');
  tabResults.Caption := LangStr('exec.results', 'Results');
  tabMessages.Caption := LangStr('tab.messages', 'Messages');

  if grdParams.ColCount >= 4 then
  begin
    grdParams.Cells[ColName, 0] := LangStr('exec.param', 'Parameter');
    grdParams.Cells[ColDirection, 0] := LangStr('exec.direction', 'Direction');
    grdParams.Cells[ColType, 0] := LangStr('exec.type', 'Type');
    grdParams.Cells[ColValue, 0] := LangStr('exec.value', 'Value');
  end;

  UpdateTransactionState;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.PrepareFor
  ----------------------------------------------------------------------------
  Prepares the dialog for one routine.

  Parameters:
    ADatabase   - The connected database.
    ANodeType   - The routine's kind.
    AObjectName - Its bare name.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.PrepareFor(ADatabase: TMetaDatabase;
  ANodeType: TMetaNodeType; const AObjectName: string);
begin
  FDatabase := ADatabase;
  FRoutine := TIdentifier.FromDatabase(AObjectName);
  FSelectable := (ANodeType = mntProcedure) and
    ADatabase.IsSelectableRoutine(AObjectName);

  lblRoutine.Caption := FRoutine.DisplayName;
  if FSelectable then
    lblKind.Caption := LangStr('exec.selectable',
      'Selectable procedure - called with SELECT')
  else
    lblKind.Caption := LangStr('exec.executable',
      'Executable procedure - called with EXECUTE PROCEDURE');

  LoadParameters(ANodeType, AObjectName);
  UpdateStatement;
  UpdateTransactionState;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.LoadParameters
  ----------------------------------------------------------------------------
  Fills the parameter grid.

  Parameters:
    ANodeType   - The routine's kind.
    AObjectName - Its bare name.

  Notes:
    Input parameters come first and are the only editable rows; outputs are
    listed too, so the user can see what to expect back, but their Value cell
    stays empty and read-only.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.LoadParameters(ANodeType: TMetaNodeType;
  const AObjectName: string);
var
  Table: TDataTable;
  Row, Target: Integer;
  Direction: string;
begin
  Table := FDatabase.FetchDetail(odParameters, ANodeType, AObjectName);

  grdParams.BeginUpdate;
  try
    grdParams.ColCount := 4;
    grdParams.RowCount := Table.RowCount + 1;
    grdParams.FixedRows := 1;

    FInputCount := 0;
    Target := 1;

    { inputs first }
    for Row := 0 to Table.RowCount - 1 do
    begin
      Direction := Trim(Table.Value(Row, 'DIRECTION'));
      if not SameText(Direction, 'IN') then
        Continue;
      grdParams.Cells[ColName, Target] := Trim(Table.Value(Row, 'PARAM_NAME'));
      grdParams.Cells[ColDirection, Target] := Direction;
      grdParams.Cells[ColType, Target] := Trim(Table.Value(Row, 'DATA_TYPE'));
      grdParams.Cells[ColValue, Target] := '';
      Inc(Target);
      Inc(FInputCount);
    end;

    for Row := 0 to Table.RowCount - 1 do
    begin
      Direction := Trim(Table.Value(Row, 'DIRECTION'));
      if SameText(Direction, 'IN') then
        Continue;
      grdParams.Cells[ColName, Target] := Trim(Table.Value(Row, 'PARAM_NAME'));
      grdParams.Cells[ColDirection, Target] := Direction;
      grdParams.Cells[ColType, Target] := Trim(Table.Value(Row, 'DATA_TYPE'));
      grdParams.Cells[ColValue, Target] := '';
      Inc(Target);
    end;

    grdParams.Cells[ColName, 0] := LangStr('exec.param', 'Parameter');
    grdParams.Cells[ColDirection, 0] := LangStr('exec.direction', 'Direction');
    grdParams.Cells[ColType, 0] := LangStr('exec.type', 'Type');
    grdParams.Cells[ColValue, 0] := LangStr('exec.value', 'Value');

    grdParams.ColWidths[ColName] := 200;
    grdParams.ColWidths[ColDirection] := 90;
    grdParams.ColWidths[ColType] := 180;
    grdParams.ColWidths[ColValue] := 260;
  finally
    grdParams.EndUpdate;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.BuildStatement
  ----------------------------------------------------------------------------
  Builds the call from the values in the grid.

  Returns:
    The statement to run.

  Notes:
    Every value is rendered through SqlLiteralForType, so quoting follows the
    parameter's DECLARED type rather than what the value looks like. That is
    what keeps a VARCHAR parameter given 007 from arriving as the number 7.
------------------------------------------------------------------------------}
function TfrmIbqExecuteRoutine.BuildStatement: string;
var
  Arguments: TStringList;
  Row: Integer;
begin
  Arguments := TStringList.Create;
  try
    for Row := 1 to FInputCount do
      Arguments.Add(SqlLiteralForType(grdParams.Cells[ColValue, Row],
        grdParams.Cells[ColType, Row]));
    Result := BuildRoutineCall(FRoutine, Arguments, FSelectable);
  finally
    Arguments.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.UpdateStatement
  ----------------------------------------------------------------------------
  Refreshes the statement preview.

  Notes:
    Shown before it runs, and kept in step as values are typed, because a user
    about to run a procedure that writes should be able to read exactly what is
    going to be sent.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.UpdateStatement;
begin
  memStatement.Lines.Text := BuildStatement;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.grdParamsEditingDone
  ----------------------------------------------------------------------------
  Refreshes the statement after a value is typed.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.grdParamsEditingDone(Sender: TObject);
begin
  UpdateStatement;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.grdParamsSelectEditor
  ----------------------------------------------------------------------------
  Allows typing only in the Value cell of an input parameter.

  Parameters:
    aCol, aRow - The cell about to be edited.
    Editor     - The editor control; set to nil to refuse the edit.

  Notes:
    The name, direction and type columns describe what the database declared
    and are not the user's to change, and an output parameter has no value to
    supply. Refusing the editor is friendlier than accepting a change and
    silently ignoring it.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.grdParamsSelectEditor(Sender: TObject;
  aCol, aRow: Integer; var Editor: TWinControl);
begin
  if (aCol <> ColValue) or (aRow < 1) or (aRow > FInputCount) then
    Editor := nil;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.ShowGrid
  ----------------------------------------------------------------------------
  Fills the result grid.

  Parameters:
    ATable - The rows returned.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.ShowGrid(const ATable: TDataTable);
var
  R, C: Integer;
begin
  grdResults.BeginUpdate;
  try
    grdResults.Clear;
    grdResults.FixedRows := 0;
    grdResults.ColCount := ATable.ColumnCount;
    grdResults.RowCount := ATable.RowCount + 1;
    if ATable.ColumnCount > 0 then
      grdResults.FixedRows := 1;

    for C := 0 to ATable.ColumnCount - 1 do
    begin
      grdResults.Cells[C, 0] := ATable.ColumnNames[C];
      grdResults.ColWidths[C] := 160;
    end;

    for R := 0 to ATable.RowCount - 1 do
      for C := 0 to ATable.ColumnCount - 1 do
        grdResults.Cells[C, R + 1] := TrimRight(ATable.ValueAt(R, C));
  finally
    grdResults.EndUpdate;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.btnExecuteClick
  ----------------------------------------------------------------------------
  Runs the routine and shows what came back.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.btnExecuteClick(Sender: TObject);
var
  ExecResult: TSqlExecResult;
  Statement: string;
begin
  if FDatabase = nil then
    Exit;

  if FSession = nil then
    FSession := FDatabase.CreateSqlSession;
  if FSession = nil then
    Exit;

  Statement := BuildStatement;
  memStatement.Lines.Text := Statement;

  Screen.Cursor := crHourGlass;
  try
    ExecResult := FSession.Execute(Statement);
  finally
    Screen.Cursor := crDefault;
  end;

  memMessages.Lines.Add(ExecResult.Message);

  if ExecResult.Failed then
    pgcResults.ActivePage := tabMessages
  else
  begin
    ShowGrid(ExecResult.Data);
    if ExecResult.Data.ColumnCount > 0 then
      pgcResults.ActivePage := tabResults
    else
      pgcResults.ActivePage := tabMessages;
  end;

  UpdateTransactionState;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.btnCommitClick
  ----------------------------------------------------------------------------
  Commits whatever the routine wrote.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.btnCommitClick(Sender: TObject);
begin
  if FSession = nil then
    Exit;
  try
    FSession.Commit;
    memMessages.Lines.Add(LangStr('sql.committed', 'Committed.'));
  except
    on E: Exception do
      memMessages.Lines.Add(E.Message);
  end;
  UpdateTransactionState;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.btnRollbackClick
  ----------------------------------------------------------------------------
  Discards whatever the routine wrote.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.btnRollbackClick(Sender: TObject);
begin
  if FSession = nil then
    Exit;
  try
    FSession.Rollback;
    memMessages.Lines.Add(LangStr('sql.rolledBack', 'Rolled back.'));
  except
    on E: Exception do
      memMessages.Lines.Add(E.Message);
  end;
  UpdateTransactionState;
end;

{------------------------------------------------------------------------------
  TfrmIbqExecuteRoutine.UpdateTransactionState
  ----------------------------------------------------------------------------
  Refreshes the transaction indicator and the Commit/Rollback buttons.

  Notes:
    Coloured, like the SQL editor's, and for the same reason: a procedure that
    wrote something and has not been committed is the one piece of state a user
    can lose work to.
------------------------------------------------------------------------------}
procedure TfrmIbqExecuteRoutine.UpdateTransactionState;
var
  Open: Boolean;
begin
  Open := (FSession <> nil) and FSession.InTransaction;

  btnCommit.Enabled := Open;
  btnRollback.Enabled := Open;

  if Open then
  begin
    lblTransaction.Caption := LangStr('sql.transactionOpen',
      'Transaction open - uncommitted changes');
    lblTransaction.Font.Color := clMaroon;
  end
  else
  begin
    lblTransaction.Caption := LangStr('sql.noTransaction', 'No transaction');
    lblTransaction.Font.Color := clGrayText;
  end;
end;

end.
