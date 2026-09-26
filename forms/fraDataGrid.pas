{==============================================================================
  Unit:        fraDataGrid
  Purpose:     The editable data grid: a DB grid over one table, with the
               transaction controls the editing needs.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  LCL, DB, DBGrids, LanguageHandle, MetaDatabase, MetaTypes,
               DataEditor, DataExport, DatabaseRow

  Binds to a TDataSource over a plain TDataSet. The dataset happens to be an
  IBX one, but this unit never says so - SPECIFICATION.md 3 rule 2 keeps IBX
  inside units/db, and TDataEditor.Dataset is deliberately typed as TDataSet
  so that rule survives contact with a data-aware control.

  The read-only case is not an error and is not hidden: a table with no primary
  key opens, shows its rows, and says in the status strip why it cannot be
  edited. Discovering that by typing and having the post fail would be worse.
==============================================================================}
unit fraDataGrid;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls, DB,
  DBGrids, Dialogs,
  LanguageHandle, AppConfig, MetaDatabase, MetaTypes, DataEditor,
  DataExport,
  DatabaseRow, frmBlobEditor;

type

  { TfraDataGrid
    An editable grid over one relation. Owns its data editor. }
  TfraDataGrid = class(TFrame, ILocalizable)
    pnlToolbar: TPanel;
    btnCommit: TButton;
    btnRollback: TButton;
    btnRefresh: TButton;
    btnInsert: TButton;
    btnDelete: TButton;
    btnExport: TButton;
    lblStatus: TLabel;
    grdData: TDBGrid;
    dsData: TDataSource;
    dlgExport: TSaveDialog;
    procedure btnCommitClick(Sender: TObject);
    procedure btnRollbackClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnInsertClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure dsDataStateChange(Sender: TObject);
    procedure grdDataDblClick(Sender: TObject);
  private
    FEditor: TDataEditor;
    FRelationName: string;
    procedure UpdateStatus;
    function CurrentDataAsTable: TDataTable;
  public
    destructor Destroy; override;

    { Opens the grid on one relation.

      Parameters:
        ADatabase   - The connected database.
        ANodeType   - The relation's kind.
        AObjectName - Its bare name.

      Returns nothing; failures are reported through the status strip and an
      error dialog, because a Data tab that refuses to appear is less useful
      than one that says what went wrong. }
    procedure OpenRelation(ADatabase: TMetaDatabase; ANodeType: TMetaNodeType;
      const AObjectName: string);

    { True when the grid holds uncommitted work. }
    function HasUncommittedChanges: Boolean;

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  TfraDataGrid.Destroy
  ----------------------------------------------------------------------------
  Releases the editor, which rolls back anything uncommitted.

  Notes:
    The grid is unbound first. A data-aware control still pointing at a dataset
    that is being torn down is a reliable way to fault during shutdown.
------------------------------------------------------------------------------}
destructor TfraDataGrid.Destroy;
begin
  if grdData <> nil then
    grdData.DataSource := nil;
  if dsData <> nil then
    dsData.DataSet := nil;
  FreeAndNil(FEditor);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.OpenRelation
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure TfraDataGrid.OpenRelation(ADatabase: TMetaDatabase;
  ANodeType: TMetaNodeType; const AObjectName: string);
begin
  grdData.DataSource := nil;
  dsData.DataSet := nil;
  FreeAndNil(FEditor);

  FRelationName := AObjectName;
  if ADatabase = nil then
  begin
    UpdateStatus;
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    try
      FEditor := ADatabase.CreateDataEditor(ANodeType, AObjectName,
        Config.DataRowLimit);
      if FEditor = nil then
      begin
        UpdateStatus;
        Exit;
      end;

      FEditor.Open;
      dsData.DataSet := FEditor.Dataset;
      grdData.DataSource := dsData;
      grdData.ReadOnly := not FEditor.CanEdit;
    except
      on E: Exception do
      begin
        FreeAndNil(FEditor);
        lblStatus.Caption := E.Message;
        lblStatus.Font.Color := clMaroon;
        MessageDlg(LangStr('grid.title', 'Data'), E.Message, mtError,
          [mbOK], 0);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  UpdateStatus;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.grdDataDblClick
  ----------------------------------------------------------------------------
  Opens the BLOB editor when the double-clicked cell holds a BLOB.

  Notes:
    A grid cell cannot show a BLOB - it shows "(BLOB)" or nothing - so the only
    way to see one is to open it. Double-click is the gesture every tool uses
    for this, and on a non-BLOB column it does nothing, which is what a user
    who double-clicked by accident expects.
------------------------------------------------------------------------------}
procedure TfraDataGrid.grdDataDblClick(Sender: TObject);
var
  Field: TField;
begin
  if (FEditor = nil) or not FEditor.Dataset.Active then
    Exit;
  if grdData.SelectedField = nil then
    Exit;

  Field := grdData.SelectedField;
  if not Field.IsBlob then
    Exit;

  try
    if EditBlobField(Field, not FEditor.CanEdit) then
      UpdateStatus;
  except
    on E: Exception do
      MessageDlg(LangStr('grid.title', 'Data'), E.Message, mtError, [mbOK], 0);
  end;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.UpdateStatus
  ----------------------------------------------------------------------------
  Refreshes the status strip and the buttons.

  Notes:
    The read-only reason is shown in full rather than as a generic "read only":
    "no primary key - rows cannot be identified" tells the user what to change,
    where the short form leaves them guessing.
------------------------------------------------------------------------------}
procedure TfraDataGrid.UpdateStatus;
var
  Editable, Pending: Boolean;
begin
  Editable := (FEditor <> nil) and FEditor.CanEdit;
  Pending := (FEditor <> nil) and FEditor.InTransaction;

  btnCommit.Enabled := Editable and Pending;
  btnRollback.Enabled := Editable and Pending;
  btnInsert.Enabled := Editable;
  btnDelete.Enabled := Editable;
  btnRefresh.Enabled := FEditor <> nil;
  btnExport.Enabled := (FEditor <> nil) and FEditor.Dataset.Active;

  if FEditor = nil then
  begin
    lblStatus.Caption := LangStr('grid.noData', 'No data.');
    lblStatus.Font.Color := clGrayText;
    Exit;
  end;

  if not FEditor.CanEdit then
  begin
    lblStatus.Caption := LangStrFormat('grid.readOnly',
      [FEditor.ReadOnlyReason], 'Read only: %s');
    lblStatus.Font.Color := clGrayText;
    Exit;
  end;

  if FEditor.HasPendingEdit then
  begin
    lblStatus.Caption := LangStr('grid.editing',
      'Editing a row - move off it or press Commit to write it.');
    lblStatus.Font.Color := clMaroon;
  end
  else if Pending then
  begin
    lblStatus.Caption := LangStr('grid.uncommitted',
      'Editable. Changes are not saved until you press Commit.');
    lblStatus.Font.Color := clMaroon;
  end
  else
  begin
    lblStatus.Caption := LangStr('grid.editable', 'Editable.');
    lblStatus.Font.Color := clGrayText;
  end;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.dsDataStateChange
  ----------------------------------------------------------------------------
  Keeps the status strip in step with the dataset's state.
------------------------------------------------------------------------------}
procedure TfraDataGrid.dsDataStateChange(Sender: TObject);
begin
  UpdateStatus;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.btnCommitClick
  ----------------------------------------------------------------------------
  Writes the pending edit and commits.
------------------------------------------------------------------------------}
procedure TfraDataGrid.btnCommitClick(Sender: TObject);
begin
  if FEditor = nil then
    Exit;
  try
    FEditor.Commit;
    FEditor.Open;
  except
    on E: Exception do
      MessageDlg(LangStr('grid.title', 'Data'), E.Message, mtError, [mbOK], 0);
  end;
  UpdateStatus;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.btnRollbackClick
  ----------------------------------------------------------------------------
  Discards every change, after confirming.
------------------------------------------------------------------------------}
procedure TfraDataGrid.btnRollbackClick(Sender: TObject);
begin
  if FEditor = nil then
    Exit;

  if MessageDlg(LangStr('grid.title', 'Data'),
    LangStr('grid.confirmRollback',
      'Discard every change made since the last commit?'),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  try
    FEditor.Rollback;
    FEditor.Open;
  except
    on E: Exception do
      MessageDlg(LangStr('grid.title', 'Data'), E.Message, mtError, [mbOK], 0);
  end;
  UpdateStatus;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.btnRefreshClick
  ----------------------------------------------------------------------------
  Re-reads the rows, discarding uncommitted work after confirming.
------------------------------------------------------------------------------}
procedure TfraDataGrid.btnRefreshClick(Sender: TObject);
begin
  if FEditor = nil then
    Exit;

  if FEditor.CanEdit and FEditor.InTransaction then
  begin
    if MessageDlg(LangStr('grid.title', 'Data'),
      LangStr('grid.confirmRefresh',
        'Refreshing discards uncommitted changes. Continue?'),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;

  try
    FEditor.Rollback;
    FEditor.Close;
    FEditor.Open;
  except
    on E: Exception do
      MessageDlg(LangStr('grid.title', 'Data'), E.Message, mtError, [mbOK], 0);
  end;
  UpdateStatus;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.btnInsertClick
  ----------------------------------------------------------------------------
  Starts a new row in the grid.
------------------------------------------------------------------------------}
procedure TfraDataGrid.btnInsertClick(Sender: TObject);
begin
  if (FEditor = nil) or not FEditor.CanEdit then
    Exit;
  try
    FEditor.Dataset.Append;
    if grdData.CanFocus then
      grdData.SetFocus;
  except
    on E: Exception do
      MessageDlg(LangStr('grid.title', 'Data'), E.Message, mtError, [mbOK], 0);
  end;
  UpdateStatus;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.btnDeleteClick
  ----------------------------------------------------------------------------
  Deletes the current row, after confirming.

  Notes:
    Confirmed even though the delete is only staged until Commit: a user who
    presses the button by accident and then presses Commit out of habit has
    lost a row, and the confirmation is the cheap half of that pair.
------------------------------------------------------------------------------}
procedure TfraDataGrid.btnDeleteClick(Sender: TObject);
begin
  if (FEditor = nil) or not FEditor.CanEdit then
    Exit;
  if not FEditor.Dataset.Active then
    Exit;
  if FEditor.Dataset.IsEmpty then
    Exit;

  if MessageDlg(LangStr('grid.title', 'Data'),
    LangStr('grid.confirmDelete',
      'Delete the current row?' + LineEnding +
      'The deletion is written when you press Commit.'),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  try
    FEditor.Dataset.Delete;
  except
    on E: Exception do
      MessageDlg(LangStr('grid.title', 'Data'), E.Message, mtError, [mbOK], 0);
  end;
  UpdateStatus;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.CurrentDataAsTable
  ----------------------------------------------------------------------------
  Copies the rows currently loaded into a plain result set.

  Returns:
    The rows as text, for the export routines.

  Notes:
    Walks the dataset with the bookmark preserved, so exporting does not move
    the user's cursor. The dataset is disabled during the walk, otherwise the
    grid would repaint once per row.
------------------------------------------------------------------------------}
function TfraDataGrid.CurrentDataAsTable: TDataTable;
var
  Data: TDataSet;
  Bookmark: TBookmark;
  RowIndex, I: Integer;
begin
  Result := Default(TDataTable);
  if (FEditor = nil) or not FEditor.Dataset.Active then
    Exit;

  Data := FEditor.Dataset;
  SetLength(Result.ColumnNames, Data.FieldCount);
  for I := 0 to Data.FieldCount - 1 do
    Result.ColumnNames[I] := Data.Fields[I].FieldName;

  Bookmark := Data.GetBookmark;
  Data.DisableControls;
  try
    Data.First;
    RowIndex := 0;
    while not Data.EOF do
    begin
      if RowIndex = Length(Result.Rows) then
        SetLength(Result.Rows, Length(Result.Rows) * 2 + 64);
      SetLength(Result.Rows[RowIndex], Data.FieldCount);
      for I := 0 to Data.FieldCount - 1 do
      begin
        if Data.Fields[I].IsNull then
          Result.Rows[RowIndex][I] := ''
        else
          Result.Rows[RowIndex][I] := Data.Fields[I].AsString;
      end;
      Inc(RowIndex);
      Data.Next;
    end;
    SetLength(Result.Rows, RowIndex);
  finally
    if Bookmark <> nil then
    begin
      Data.GotoBookmark(Bookmark);
      Data.FreeBookmark(Bookmark);
    end;
    Data.EnableControls;
  end;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.btnExportClick
  ----------------------------------------------------------------------------
  Writes the loaded rows to a file, in the format the extension names.
------------------------------------------------------------------------------}
procedure TfraDataGrid.btnExportClick(Sender: TObject);
var
  Table: TDataTable;
  Format_: TExportFormat;
  Extension: string;
begin
  if FEditor = nil then
    Exit;

  Table := CurrentDataAsTable;
  if Table.ColumnCount = 0 then
    Exit;

  dlgExport.Title := LangStr('grid.exportTitle', 'Export rows');
  dlgExport.FileName := FRelationName;
  if not dlgExport.Execute then
    Exit;

  Extension := LowerCase(ExtractFileExt(dlgExport.FileName));
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
      SaveDataTable(Table, Format_, dlgExport.FileName,
        FEditor.Relation.QualifiedQuoted);
      lblStatus.Caption := LangStrFormat('grid.exported',
        [Table.RowCount, dlgExport.FileName], 'Exported %d row(s) to %s');
      lblStatus.Font.Color := clGrayText;
    except
      on E: Exception do
        MessageDlg(LangStr('grid.title', 'Data'), E.Message, mtError,
          [mbOK], 0);
    end;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.HasUncommittedChanges
  ----------------------------------------------------------------------------
  Returns True when the grid holds work that would be lost.
------------------------------------------------------------------------------}
function TfraDataGrid.HasUncommittedChanges: Boolean;
begin
  Result := (FEditor <> nil) and FEditor.CanEdit and FEditor.InTransaction;
end;

{------------------------------------------------------------------------------
  TfraDataGrid.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.
------------------------------------------------------------------------------}
procedure TfraDataGrid.LoadLangStr;
begin
  btnCommit.Caption := LangStr('grid.commit', 'Commit');
  btnRollback.Caption := LangStr('grid.rollback', 'Rollback');
  btnRefresh.Caption := LangStr('grid.refresh', 'Refresh');
  btnInsert.Caption := LangStr('grid.insert', 'Insert row');
  btnDelete.Caption := LangStr('grid.delete', 'Delete row');
  btnExport.Caption := LangStr('grid.export', 'Export...');
  UpdateStatus;
end;

end.
