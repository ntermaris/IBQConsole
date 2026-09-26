{==============================================================================
  Unit:        frmSqlEditor
  Purpose:     The SQL editor: successor to IBConsole's ISQL window and to
               FlameRobin's ExecuteSqlFrame.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  LCL, SynEdit, SynHighlighterSQL, LanguageHandle, AppLog,
               MetaDatabase, SqlSession, SqlStatementSplitter, DatabaseRow

  Each editor owns its own transaction, started on the first statement and
  ended only when the user says so. The transaction indicator in the toolbar is
  therefore not decoration: it is the difference between work that is saved and
  work that is not, and the user must be able to see which at a glance.
==============================================================================}
unit frmSqlEditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ComCtrls, ExtCtrls, StdCtrls,
  Grids, Menus, Dialogs,
  SynEdit, SynHighlighterSQL, SynEditTypes,
  LanguageHandle, AppLog, MetaDatabase, SqlSession, SqlStatementSplitter,
  DatabaseRow, DataExport, StatementHistory, frmStatementHistory;

type

  { TfraSqlEditor
    One SQL editor page inside the main window's workspace. }
  TfraSqlEditor = class(TFrame, ILocalizable)
    pnlToolbar: TPanel;
    btnExecute: TButton;
    btnExecuteScript: TButton;
    btnCommit: TButton;
    btnRollback: TButton;
    btnHistory: TButton;
    btnOpen: TButton;
    btnSave: TButton;
    btnExport: TButton;
    lblTransaction: TLabel;
    synEditor: TSynEdit;
    synSqlHighlighter: TSynSQLSyn;
    splResults: TSplitter;
    pgcResults: TPageControl;
    tabData: TTabSheet;
    grdResults: TStringGrid;
    tabMessages: TTabSheet;
    memMessages: TMemo;
    tabPlan: TTabSheet;
    memPlan: TMemo;
    tabStatistics: TTabSheet;
    memStatistics: TMemo;
    dlgOpenScript: TOpenDialog;
    dlgSaveScript: TSaveDialog;
    dlgExportResults: TSaveDialog;
    procedure btnExecuteClick(Sender: TObject);
    procedure btnExecuteScriptClick(Sender: TObject);
    procedure btnCommitClick(Sender: TObject);
    procedure btnRollbackClick(Sender: TObject);
    procedure btnHistoryClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure synEditorKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
  private
    FDatabase: TMetaDatabase;
    FSession: TSqlSession;
    FLastData: TDataTable;
    FFileName: string;
    procedure RememberStatement(const ASql: string;
      const AResult: TSqlExecResult);
    procedure ShowResult(const AResult: TSqlExecResult);
    procedure ShowGrid(const ATable: TDataTable);
    procedure AddMessage(const AText: string);
    procedure UpdateTransactionState;
    function SelectedOrCurrentStatement: string;
    function CaretCharOffset: Integer;
  public
    destructor Destroy; override;

    { Attaches the editor to a connected database.

      Parameters:
        ADatabase - The database to run against; must be connected. }
    procedure AttachTo(ADatabase: TMetaDatabase);

    { Runs the statement under the caret, or the selection when there is one. }
    procedure ExecuteCurrent;
    { Runs every statement in the editor. }
    procedure ExecuteAll;

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { True while the editor is holding an open transaction. }
    function HasOpenTransaction: Boolean;

    { The database this editor runs against. }
    property Database: TMetaDatabase read FDatabase;
    { The editor control, so the main window can give it focus. }
    property Editor: TSynEdit read synEditor;
  end;

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  TfraSqlEditor.Destroy
  ----------------------------------------------------------------------------
  Releases the session, which rolls back anything the user left open.
------------------------------------------------------------------------------}
destructor TfraSqlEditor.Destroy;
begin
  FreeAndNil(FSession);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.AttachTo
  ----------------------------------------------------------------------------
  Attaches the editor to a connected database.

  Parameters:
    ADatabase - The database to run against.

  Notes:
    The highlighter dialect follows the server version, so Firebird 3 and 4
    keywords are coloured on the servers that actually have them.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.AttachTo(ADatabase: TMetaDatabase);
begin
  FreeAndNil(FSession);
  FDatabase := ADatabase;

  if (FDatabase = nil) or not FDatabase.IsConnected then
  begin
    UpdateTransactionState;
    Exit;
  end;

  FSession := FDatabase.CreateSqlSession;

  if FDatabase.Version.AtLeast(4) then
    synSqlHighlighter.SQLDialect := sqlFirebird40
  else if FDatabase.Version.AtLeast(3) then
    synSqlHighlighter.SQLDialect := sqlFirebird30
  else
    synSqlHighlighter.SQLDialect := sqlFirebird25;

  UpdateTransactionState;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.CaretCharOffset
  ----------------------------------------------------------------------------
  Returns the caret's 0-based character offset into the whole editor text.

  Notes:
    Computed here rather than with SynEdit's SelStart or RowColToCharIndex,
    both of which SynEdit marks deprecated AND "very slow" because they exist
    only for SynMemo compatibility. SynEdit works in x/y, so the conversion is
    ours to make - and it is a sum over the lines above the caret, which is
    exactly what is needed and no more.
------------------------------------------------------------------------------}
function TfraSqlEditor.CaretCharOffset: Integer;
var
  I, LineBreakLength: Integer;
begin
  Result := 0;
  LineBreakLength := Length(LineEnding);

  for I := 0 to synEditor.CaretY - 2 do
  begin
    if I > synEditor.Lines.Count - 1 then
      Break;
    Inc(Result, Length(synEditor.Lines[I]) + LineBreakLength);
  end;

  Inc(Result, synEditor.CaretX - 1);
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.SelectedOrCurrentStatement
  ----------------------------------------------------------------------------
  Returns the SQL that Execute should run.

  Returns:
    The selection when the user has selected text, otherwise the statement the
    caret sits in.

  Notes:
    Selecting text and pressing Execute must run exactly the selection, even
    when it is half a statement: the user asked for that, and refusing to obey
    a selection is more surprising than running something that fails.
------------------------------------------------------------------------------}
function TfraSqlEditor.SelectedOrCurrentStatement: string;
var
  Statement: TSqlStatement;
begin
  if synEditor.SelAvail and (Trim(synEditor.SelText) <> '') then
    Exit(synEditor.SelText);

  if StatementAtOffset(synEditor.Text, CaretCharOffset, Statement) then
    Result := Statement.Text
  else
    Result := '';
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.ExecuteCurrent
  ----------------------------------------------------------------------------
  Runs the statement under the caret, or the selection.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.ExecuteCurrent;
var
  Sql: string;
  ExecResult: TSqlExecResult;
begin
  if FSession = nil then
    Exit;

  Sql := Trim(SelectedOrCurrentStatement);
  if Sql = '' then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    ExecResult := FSession.Execute(Sql);
    RememberStatement(Sql, ExecResult);
    ShowResult(ExecResult);
  finally
    Screen.Cursor := crDefault;
    UpdateTransactionState;
  end;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.ExecuteAll
  ----------------------------------------------------------------------------
  Runs every statement in the editor, stopping at the first failure.

  Notes:
    Only the LAST statement's result set is shown in the grid, because a script
    is run for its effect rather than for its output; the Messages tab carries
    one line per statement, which is what tells the user what happened.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.ExecuteAll;
var
  Results: TSqlExecResultArray;
  I: Integer;
begin
  if FSession = nil then
    Exit;

  memMessages.Lines.Clear;
  Screen.Cursor := crHourGlass;
  try
    Results := FSession.ExecuteScript(synEditor.Text, nil, True);
    for I := Low(Results) to High(Results) do
    begin
      AddMessage(Format('[%d] %s', [I + 1, Results[I].Message]));
      RememberStatement(Results[I].Sql, Results[I]);
    end;

    if Length(Results) > 0 then
    begin
      ShowGrid(Results[High(Results)].Data);
      memPlan.Lines.Text := Results[High(Results)].Plan;
      memStatistics.Lines.Text := Results[High(Results)].Statistics;
      if Results[High(Results)].Failed then
        pgcResults.PageIndex := 1;
    end;
  finally
    Screen.Cursor := crDefault;
    UpdateTransactionState;
  end;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.ShowResult
  ----------------------------------------------------------------------------
  Displays one statement's result.

  Parameters:
    AResult - What the statement produced.

  Notes:
    A failure switches to the Messages tab. Leaving the user looking at a stale
    grid while the error sits on a tab they cannot see is how a tool gets a
    reputation for silently doing nothing.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.ShowResult(const AResult: TSqlExecResult);
begin
  AddMessage(AResult.Message);
  memPlan.Lines.Text := AResult.Plan;
  memStatistics.Lines.Text := AResult.Statistics;

  if AResult.Failed then
  begin
    pgcResults.PageIndex := 1;
    Exit;
  end;

  if AResult.ReturnsData then
  begin
    ShowGrid(AResult.Data);
    pgcResults.PageIndex := 0;
  end
  else
    pgcResults.PageIndex := 1;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.ShowGrid
  ----------------------------------------------------------------------------
  Fills the data grid from a result set.

  Parameters:
    ATable - The rows to show.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.ShowGrid(const ATable: TDataTable);
const
  MaxColumnWidth = 320;
var
  R, C, CellWidth: Integer;
begin
  grdResults.BeginUpdate;
  try
    grdResults.Clear;
    grdResults.FixedRows := 0;
    if ATable.ColumnCount = 0 then
    begin
      grdResults.ColCount := 0;
      grdResults.RowCount := 0;
      Exit;
    end;

    FLastData := ATable;
    grdResults.ColCount := ATable.ColumnCount;
    grdResults.RowCount := ATable.RowCount + 1;
    grdResults.FixedRows := 1;

    for C := 0 to ATable.ColumnCount - 1 do
      grdResults.Cells[C, 0] := ATable.ColumnNames[C];

    for R := 0 to ATable.RowCount - 1 do
      for C := 0 to ATable.ColumnCount - 1 do
        grdResults.Cells[C, R + 1] := TrimRight(ATable.ValueAt(R, C));

    for C := 0 to ATable.ColumnCount - 1 do
    begin
      CellWidth := grdResults.Canvas.TextWidth(ATable.ColumnNames[C]) + 24;
      for R := 0 to ATable.RowCount - 1 do
      begin
        if R > 40 then
          Break;
        if grdResults.Canvas.TextWidth(TrimRight(ATable.ValueAt(R, C))) + 24 >
           CellWidth then
          CellWidth := grdResults.Canvas.TextWidth(
            TrimRight(ATable.ValueAt(R, C))) + 24;
      end;
      if CellWidth > MaxColumnWidth then
        CellWidth := MaxColumnWidth;
      grdResults.ColWidths[C] := CellWidth;
    end;
  finally
    grdResults.EndUpdate;
  end;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.AddMessage
  ----------------------------------------------------------------------------
  Appends one line to the Messages tab.

  Parameters:
    AText - The line, which may itself span several lines.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.AddMessage(const AText: string);
begin
  memMessages.Lines.Add(AText);
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.UpdateTransactionState
  ----------------------------------------------------------------------------
  Refreshes the transaction indicator and the Commit/Rollback buttons.

  Notes:
    The indicator is coloured, not merely worded: an open transaction is the
    one piece of editor state a user can lose work to, and it has to be
    noticeable without being read.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.UpdateTransactionState;
var
  Open: Boolean;
begin
  Open := HasOpenTransaction;

  btnCommit.Enabled := Open;
  btnRollback.Enabled := Open;
  btnExecute.Enabled := FSession <> nil;
  btnExecuteScript.Enabled := FSession <> nil;

  if FSession = nil then
  begin
    lblTransaction.Caption := LangStr('sql.notConnected', 'Not connected');
    lblTransaction.Font.Color := clGrayText;
  end
  else if Open then
  begin
    lblTransaction.Caption :=
      LangStr('sql.transactionOpen', 'Transaction open - uncommitted changes');
    lblTransaction.Font.Color := clMaroon;
  end
  else
  begin
    lblTransaction.Caption := LangStr('sql.noTransaction', 'No transaction');
    lblTransaction.Font.Color := clGrayText;
  end;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.HasOpenTransaction
  ----------------------------------------------------------------------------
  Returns True while the editor holds an open transaction.
------------------------------------------------------------------------------}
function TfraSqlEditor.HasOpenTransaction: Boolean;
begin
  Result := (FSession <> nil) and FSession.InTransaction;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.RememberStatement
  ----------------------------------------------------------------------------
  Adds one executed statement to the history.

  Parameters:
    ASql    - The statement as executed.
    AResult - What it produced.

  Notes:
    Failed statements are remembered too. The statement a user most wants back
    is often the one that did not work.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.RememberStatement(const ASql: string;
  const AResult: TSqlExecResult);
var
  DatabaseName: string;
begin
  if FDatabase = nil then
    DatabaseName := ''
  else
    DatabaseName := FDatabase.DisplayName;

  History.Add(ASql, DatabaseName, AResult.ElapsedMs, not AResult.Failed);
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.btnHistoryClick
  ----------------------------------------------------------------------------
  Opens the statement history and inserts the chosen statement.

  Notes:
    The statement is appended rather than replacing what is in the editor:
    losing whatever the user was typing in order to recall something else would
    trade one loss for another.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.btnHistoryClick(Sender: TObject);
var
  Sql: string;
begin
  if not ChooseStatementFromHistory(Sql) then
    Exit;

  if Trim(synEditor.Text) = '' then
    synEditor.Text := Sql
  else
    synEditor.Text := synEditor.Text + LineEnding + LineEnding + Sql;

  synEditor.SetFocus;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.btnOpenClick
  ----------------------------------------------------------------------------
  Loads a script from a file into the editor.

  Notes:
    Replacing the editor's contents is confirmed when there is unsaved text,
    because a script typed and not saved is exactly the work this feature
    exists to protect.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.btnOpenClick(Sender: TObject);
begin
  if synEditor.Modified and (Trim(synEditor.Text) <> '') then
  begin
    if MessageDlg(LangStr('sql.openTitle', 'Open script'),
      LangStr('sql.confirmReplace',
        'The editor has unsaved changes. Replace them with the file?'),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;

  dlgOpenScript.Title := LangStr('sql.openTitle', 'Open script');
  if not dlgOpenScript.Execute then
    Exit;

  try
    synEditor.Lines.LoadFromFile(dlgOpenScript.FileName);
    FFileName := dlgOpenScript.FileName;
    synEditor.Modified := False;
    AddMessage(LangStrFormat('sql.opened', [FFileName], 'Opened %s'));
  except
    on E: Exception do
      MessageDlg(LangStr('sql.openTitle', 'Open script'), E.Message,
        mtError, [mbOK], 0);
  end;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.btnSaveClick
  ----------------------------------------------------------------------------
  Saves the editor's contents to a file.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.btnSaveClick(Sender: TObject);
begin
  dlgSaveScript.Title := LangStr('sql.saveTitle', 'Save script');
  dlgSaveScript.FileName := FFileName;
  if not dlgSaveScript.Execute then
    Exit;

  try
    synEditor.Lines.SaveToFile(dlgSaveScript.FileName);
    FFileName := dlgSaveScript.FileName;
    synEditor.Modified := False;
    AddMessage(LangStrFormat('sql.saved', [FFileName], 'Saved %s'));
  except
    on E: Exception do
      MessageDlg(LangStr('sql.saveTitle', 'Save script'), E.Message,
        mtError, [mbOK], 0);
  end;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.btnExportClick
  ----------------------------------------------------------------------------
  Writes the result grid to a file in a chosen format.

  Notes:
    The format is taken from the extension the user types or picks, so there is
    no separate format dropdown to get out of step with the file name. Choosing
    "report.md" gets a Markdown table; "report.json" gets JSON.

    Exports what was FETCHED, and says so when the fetch was capped. Silently
    writing the first thousand rows of a four-million-row table as if it were
    the whole thing is exactly the kind of quiet wrongness this must not do.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.btnExportClick(Sender: TObject);
var
  Format_: TExportFormat;
  Extension: string;
begin
  if FLastData.ColumnCount = 0 then
  begin
    MessageDlg(LangStr('sql.exportTitle', 'Export results'),
      LangStr('sql.nothingToExport', 'Run a query first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  dlgExportResults.Title := LangStr('sql.exportTitle', 'Export results');
  if not dlgExportResults.Execute then
    Exit;

  Extension := LowerCase(ExtractFileExt(dlgExportResults.FileName));
  if Extension = '.tsv' then
    Format_ := efTsv
  else if Extension = '.json' then
    Format_ := efJson
  else if (Extension = '.html') or (Extension = '.htm') then
    Format_ := efHtml
  else if Extension = '.md' then
    Format_ := efMarkdown
  else if Extension = '.sql' then
    Format_ := efInsert
  else
    Format_ := efCsv;

  try
    SaveDataTable(FLastData, Format_, dlgExportResults.FileName, 'TABLE_NAME');
    AddMessage(LangStrFormat('sql.exported',
      [FLastData.RowCount, ExportFormatName(Format_),
       dlgExportResults.FileName],
      'Exported %d row(s) as %s to %s'));
  except
    on E: Exception do
      MessageDlg(LangStr('sql.exportTitle', 'Export results'), E.Message,
        mtError, [mbOK], 0);
  end;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.btnExecuteClick
  ----------------------------------------------------------------------------
  Toolbar handler for Execute.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.btnExecuteClick(Sender: TObject);
begin
  ExecuteCurrent;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.btnExecuteScriptClick
  ----------------------------------------------------------------------------
  Toolbar handler for Run script.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.btnExecuteScriptClick(Sender: TObject);
begin
  ExecuteAll;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.btnCommitClick
  ----------------------------------------------------------------------------
  Toolbar handler for Commit.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.btnCommitClick(Sender: TObject);
begin
  if FSession = nil then
    Exit;
  try
    FSession.Commit;
    AddMessage(LangStr('sql.committed', 'Committed.'));
  except
    on E: Exception do
      AddMessage(E.Message);
  end;
  UpdateTransactionState;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.btnRollbackClick
  ----------------------------------------------------------------------------
  Toolbar handler for Rollback.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.btnRollbackClick(Sender: TObject);
begin
  if FSession = nil then
    Exit;
  try
    FSession.Rollback;
    AddMessage(LangStr('sql.rolledBack', 'Rolled back.'));
  except
    on E: Exception do
      AddMessage(E.Message);
  end;
  UpdateTransactionState;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.synEditorKeyDown
  ----------------------------------------------------------------------------
  Handles the execute shortcuts.

  Parameters:
    Key   - The key pressed; cleared when handled.
    Shift - Modifier keys.

  Notes:
    F5 and F9 rather than Ctrl+Enter: they are what IBConsole's ISQL window
    used, and what every other Firebird tool has used since.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.synEditorKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = 116) and (Shift = []) then        // F5
  begin
    Key := 0;
    ExecuteCurrent;
  end
  else if (Key = 120) and (Shift = []) then   // F9
  begin
    Key := 0;
    ExecuteAll;
  end
  else if (Key = Ord('H')) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    btnHistoryClick(nil);
  end;
end;

{------------------------------------------------------------------------------
  TfraSqlEditor.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.
------------------------------------------------------------------------------}
procedure TfraSqlEditor.LoadLangStr;
begin
  btnExecute.Caption := LangStr('sql.execute', 'Execute (F5)');
  btnExecuteScript.Caption := LangStr('sql.executeScript', 'Run script (F9)');
  btnCommit.Caption := LangStr('sql.commit', 'Commit');
  btnRollback.Caption := LangStr('sql.rollback', 'Rollback');
  btnHistory.Caption := LangStr('sql.history', 'History (Ctrl+H)');
  btnOpen.Caption := LangStr('sql.open', 'Open...');
  btnSave.Caption := LangStr('sql.save', 'Save...');
  btnExport.Caption := LangStr('sql.export', 'Export...');

  if pgcResults.PageCount >= 4 then
  begin
    pgcResults.Pages[0].Caption := LangStr('tab.data', 'Data');
    pgcResults.Pages[1].Caption := LangStr('tab.messages', 'Messages');
    pgcResults.Pages[2].Caption := LangStr('tab.plan', 'Plan');
    pgcResults.Pages[3].Caption := LangStr('tab.statistics', 'Statistics');
  end;

  UpdateTransactionState;
end;

end.
