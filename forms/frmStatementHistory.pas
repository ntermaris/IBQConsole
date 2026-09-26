{==============================================================================
  Unit:        frmStatementHistory
  Purpose:     Browses the statements executed in past sessions and lets one be
               brought back into the editor.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  LCL, LanguageHandle, StatementHistory
==============================================================================}
unit frmStatementHistory;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  LanguageHandle, StatementHistory;

type

  { TfrmIbqStatementHistory
    A filter box over the remembered statements, with the full text of the
    selected one shown underneath. }
  TfrmIbqStatementHistory = class(TForm, ILocalizable)
    lblFilter: TLabel;
    edtFilter: TEdit;
    lstStatements: TListBox;
    splPreview: TSplitter;
    memPreview: TMemo;
    lblDetail: TLabel;
    bvlButtons: TBevel;
    btnUse: TButton;
    btnClear: TButton;
    btnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure edtFilterChange(Sender: TObject);
    procedure lstStatementsClick(Sender: TObject);
    procedure lstStatementsDblClick(Sender: TObject);
    procedure btnClearClick(Sender: TObject);
  private
    FSelectedSql: string;
    procedure RefreshList;
    function SelectedEntry: TStatementHistoryEntry;
  public
    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { The statement the user chose, or an empty string. }
    property SelectedSql: string read FSelectedSql;
  end;

{ Shows the history and returns the statement the user picked.

  Parameters:
    ASql - Receives the chosen statement; untouched when nothing was chosen.

  Returns:
    True when the user picked a statement. }
function ChooseStatementFromHistory(out ASql: string): Boolean;

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  ChooseStatementFromHistory
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function ChooseStatementFromHistory(out ASql: string): Boolean;
var
  Dialog: TfrmIbqStatementHistory;
begin
  ASql := '';
  Dialog := TfrmIbqStatementHistory.Create(nil);
  try
    Result := (Dialog.ShowModal = mrOK) and (Dialog.SelectedSql <> '');
    if Result then
      ASql := Dialog.SelectedSql;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqStatementHistory.FormCreate
  ----------------------------------------------------------------------------
  Fills the list and applies the active language.
------------------------------------------------------------------------------}
procedure TfrmIbqStatementHistory.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
  RefreshList;
end;

{------------------------------------------------------------------------------
  TfrmIbqStatementHistory.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.
------------------------------------------------------------------------------}
procedure TfrmIbqStatementHistory.LoadLangStr;
begin
  Caption := LangStr('frmStatementHistory.caption', 'Statement History');
  lblFilter.Caption := LangStr('history.filter', 'Containing');
  btnUse.Caption := LangStr('history.use', 'Use');
  btnClear.Caption := LangStr('history.clear', 'Clear history');
  btnCancel.Caption := LangStr('btnCancel.caption', 'Cancel');
end;

{------------------------------------------------------------------------------
  TfrmIbqStatementHistory.RefreshList
  ----------------------------------------------------------------------------
  Refills the list from the history, honouring the filter.

  Notes:
    Each list item carries the history position in its Objects slot, so the
    full statement can be reached however the list has been filtered.
------------------------------------------------------------------------------}
procedure TfrmIbqStatementHistory.RefreshList;
begin
  lstStatements.Items.BeginUpdate;
  try
    History.Search(edtFilter.Text, lstStatements.Items);
  finally
    lstStatements.Items.EndUpdate;
  end;

  if lstStatements.Items.Count > 0 then
    lstStatements.ItemIndex := 0;
  lstStatementsClick(nil);
end;

{------------------------------------------------------------------------------
  TfrmIbqStatementHistory.SelectedEntry
  ----------------------------------------------------------------------------
  Returns the history entry the list selection points at.

  Returns:
    The entry, or nil when nothing is selected.
------------------------------------------------------------------------------}
function TfrmIbqStatementHistory.SelectedEntry: TStatementHistoryEntry;
var
  EntryIndex: Integer;
begin
  Result := nil;
  if lstStatements.ItemIndex < 0 then
    Exit;

  EntryIndex := PtrInt(lstStatements.Items.Objects[lstStatements.ItemIndex]);
  if (EntryIndex >= 0) and (EntryIndex < History.Count) then
    Result := History[EntryIndex];
end;

{------------------------------------------------------------------------------
  TfrmIbqStatementHistory.lstStatementsClick
  ----------------------------------------------------------------------------
  Shows the full text and details of the selected statement.
------------------------------------------------------------------------------}
procedure TfrmIbqStatementHistory.lstStatementsClick(Sender: TObject);
var
  Entry: TStatementHistoryEntry;
  Outcome: string;
begin
  Entry := SelectedEntry;

  if Entry = nil then
  begin
    memPreview.Lines.Clear;
    lblDetail.Caption := '';
    FSelectedSql := '';
    Exit;
  end;

  memPreview.Lines.Text := Entry.Sql;
  FSelectedSql := Entry.Sql;

  if Entry.Succeeded then
    Outcome := LangStr('history.ok', 'succeeded')
  else
    Outcome := LangStr('history.failed', 'FAILED');

  lblDetail.Caption := Format('%s   %s   %d ms   %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.Executed),
     Entry.Database, Entry.ElapsedMs, Outcome]);
end;

{------------------------------------------------------------------------------
  TfrmIbqStatementHistory.lstStatementsDblClick
  ----------------------------------------------------------------------------
  Accepts the double-clicked statement.
------------------------------------------------------------------------------}
procedure TfrmIbqStatementHistory.lstStatementsDblClick(Sender: TObject);
begin
  if SelectedEntry <> nil then
    ModalResult := mrOK;
end;

{------------------------------------------------------------------------------
  TfrmIbqStatementHistory.edtFilterChange
  ----------------------------------------------------------------------------
  Re-applies the filter as the user types.
------------------------------------------------------------------------------}
procedure TfrmIbqStatementHistory.edtFilterChange(Sender: TObject);
begin
  RefreshList;
end;

{------------------------------------------------------------------------------
  TfrmIbqStatementHistory.btnClearClick
  ----------------------------------------------------------------------------
  Forgets every remembered statement, after confirming.

  Notes:
    Confirmed because it cannot be undone and the history is the only copy of
    statements the user never saved anywhere.
------------------------------------------------------------------------------}
procedure TfrmIbqStatementHistory.btnClearClick(Sender: TObject);
begin
  if MessageDlg(Caption,
    LangStrFormat('history.confirmClear', [History.Count],
      'Forget all %d remembered statements?' + LineEnding +
      'This cannot be undone.'),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  History.Clear;
  History.SaveIfModified;
  RefreshList;
end;

end.
