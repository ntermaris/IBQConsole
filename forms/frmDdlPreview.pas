{==============================================================================
  Unit:        frmDdlPreview
  Purpose:     Shows a generated DDL statement and runs it when the user says
               so.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
               Dialogs, LanguageHandle, AppLog, MetaDatabase

  IBConsole equivalent: the confirmation shown before a Drop.

  WHY THE STATEMENT IS ALWAYS VISIBLE
  This is the one dialog every DDL command in the program passes through, and
  it shows the exact text that will be sent. A database console is used by
  people who read SQL, and a tool that says "are you sure?" without saying
  what it is about to do is asking them to trust it instead of letting them
  check it. Showing the statement also makes the answer to "what did that
  do?" available before the fact rather than after.

  The text is editable. Someone who spots that the generated statement is
  nearly right can finish it here rather than starting again in the dialog
  behind - and anything this program generates is a starting point, not a
  contract.

  RUNNING MORE THAN ONE STATEMENT
  A generated script can be several statements: a sequence with a starting
  value, a domain with three properties changed. They run in order through the
  same splitter the SQL editor uses, each committed as it goes, and the first
  failure stops the rest. Firebird has no transaction that would let the
  earlier ones be taken back, so the report says which ones did run.
==============================================================================}
unit frmDdlPreview;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Dialogs,
  LanguageHandle, AppLog, MetaDatabase;

type
  { TfrmIbqDdlPreview
    Shows a DDL statement and runs it.

    Owns nothing: the database is injected and stays owned by the model. }
  TfrmIbqDdlPreview = class(TForm, ILocalizable)
    pnlHeader: TPanel;
    lblWhat: TLabel;
    lblWarning: TLabel;
    memStatement: TMemo;
    pnlButtons: TPanel;
    lblStatus: TLabel;
    btnExecute: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnExecuteClick(Sender: TObject);
  private
    FDatabase: TMetaDatabase;
    FExecuted: Boolean;
    { Logs an error and shows it. }
    procedure ReportError(E: Exception);
  public
    { Prepares the dialog for one generated statement.

      Parameters:
        ADatabase  - The database to run against. Not owned.
        ACaption   - The dialog's title, naming the command.
        AWhat      - One line saying what is about to happen.
        AWarning   - A line in grey saying what cannot be undone, or an empty
                     string when nothing needs saying.
        AStatement - The statement, or several separated by ';'. }
    procedure PrepareFor(ADatabase: TMetaDatabase;
      const ACaption, AWhat, AWarning, AStatement: string);

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { True when something was actually run, so the caller knows whether the
      tree needs re-reading. }
    property Executed: Boolean read FExecuted;
  end;

{ Shows a generated statement and runs it if the user agrees.

  Parameters:
    ADatabase  - The database to run against.
    ACaption   - The dialog's title, naming the command.
    AWhat      - One line saying what is about to happen.
    AWarning   - A line in grey about what cannot be undone, or empty.
    AStatement - The statement, or several separated by ';'.

  Returns:
    True when something was run, which is the caller's signal to re-read
    whatever it was showing. }
function DdlPreviewDialog(ADatabase: TMetaDatabase;
  const ACaption, AWhat, AWarning, AStatement: string): Boolean;

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  DdlPreviewDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function DdlPreviewDialog(ADatabase: TMetaDatabase;
  const ACaption, AWhat, AWarning, AStatement: string): Boolean;
var
  Dialog: TfrmIbqDdlPreview;
begin
  Result := False;
  if (ADatabase = nil) or (Trim(AStatement) = '') then
  begin
    Exit;
  end;

  Dialog := TfrmIbqDdlPreview.Create(nil);
  try
    Dialog.PrepareFor(ADatabase, ACaption, AWhat, AWarning, AStatement);
    Dialog.ShowModal;
    Result := Dialog.Executed;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqDdlPreview.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.

  Parameters:
    Sender - The form.
------------------------------------------------------------------------------}
procedure TfrmIbqDdlPreview.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqDdlPreview.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language.

  Notes:
    The title and the two header lines are not touched: they were given by the
    caller, which said them in the active language already. Overwriting them
    here would replace a specific sentence with a generic one.
------------------------------------------------------------------------------}
procedure TfrmIbqDdlPreview.LoadLangStr;
begin
  btnExecute.Caption := LangStr('ddl.execute', 'Execute');
  btnClose.Caption := LangStr('btnClose.caption', 'Close');
end;

{------------------------------------------------------------------------------
  TfrmIbqDdlPreview.PrepareFor
  ----------------------------------------------------------------------------
  Prepares the dialog for one generated statement.

  Parameters:
    ADatabase  - The database to run against. Not owned.
    ACaption   - The dialog's title.
    AWhat      - One line saying what is about to happen.
    AWarning   - A line in grey, or an empty string.
    AStatement - The statement, or several separated by ';'.
------------------------------------------------------------------------------}
procedure TfrmIbqDdlPreview.PrepareFor(ADatabase: TMetaDatabase;
  const ACaption, AWhat, AWarning, AStatement: string);
begin
  FDatabase := ADatabase;      // injected, NOT owned
  FExecuted := False;

  Caption := ACaption;
  lblWhat.Caption := AWhat;
  lblWarning.Caption := AWarning;
  lblWarning.Visible := Trim(AWarning) <> '';

  memStatement.Lines.Text := AStatement;
  lblStatus.Caption := '';
  btnExecute.Enabled := FDatabase <> nil;
end;

{------------------------------------------------------------------------------
  TfrmIbqDdlPreview.ReportError
  ----------------------------------------------------------------------------
  Logs an error and shows it.

  Parameters:
    E - What went wrong.
------------------------------------------------------------------------------}
procedure TfrmIbqDdlPreview.ReportError(E: Exception);
begin
  Log.Error(E.Message);
  MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
end;

{------------------------------------------------------------------------------
  TfrmIbqDdlPreview.btnExecuteClick
  ----------------------------------------------------------------------------
  Runs the statement, or each statement in turn.

  Parameters:
    Sender - The Execute button.

  Notes:
    Closes only when everything ran. A failure leaves the dialog open with the
    text still in it, because the text is editable and the usual next move is
    to correct it and try again.

    When a later statement fails the earlier ones have already been
    committed. The model says so in the error text rather than letting the
    user assume the whole thing was undone.
------------------------------------------------------------------------------}
procedure TfrmIbqDdlPreview.btnExecuteClick(Sender: TObject);
var
  Done: Integer;
begin
  if FDatabase = nil then
  begin
    Exit;
  end;

  try
    Done := FDatabase.ExecuteDdlScript(memStatement.Lines.Text);
  except
    on E: Exception do
    begin
      lblStatus.Caption := LangStr('ddl.failed', 'Failed.');
      ReportError(E);
      Exit;
    end;
  end;

  if Done = 0 then
  begin
    lblStatus.Caption := LangStr('ddl.nothingToRun',
      'There is nothing to run.');
    Exit;
  end;

  FExecuted := True;
  Log.InfoFmt('Ran %d DDL statement(s)', [Done]);
  ModalResult := mrOk;
end;

end.
