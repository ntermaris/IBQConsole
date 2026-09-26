{==============================================================================
  Unit:        frmPreferences
  Purpose:     Lets the user change the preferences and writes them.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
               Spin, Dialogs, LanguageHandle, AppLog, AppConfig

  IBConsole equivalent: Edit > Options.

  WHAT IT DOES NOT DO
  It does not apply anything itself. It writes the preferences and reports
  that they changed; the main window decides what to re-read, because it is
  the one that knows which of its parts a setting touches. A dialog that
  reached out and changed other forms would have to know all of them.

  WHAT NEEDS A RESTART, AND SAYING SO
  The language takes effect at once - every open form re-translates through
  ApplyLocale. The editor font does not: the tabs already open keep the font
  they were built with, and only new ones pick up the change. That is said on
  the form rather than left to be discovered, because a setting that appears
  to do nothing is indistinguishable from one that is broken.
==============================================================================}
unit frmPreferences;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Spin,
  Dialogs,
  LanguageHandle, AppLog, AppConfig;

type
  { TfrmIbqPreferences
    The preferences dialog.

    Owns nothing: it reads and writes the one TAppConfig reached through
    Config. }
  TfrmIbqPreferences = class(TForm, ILocalizable)
    grpGeneral: TGroupBox;
    lblLanguage: TLabel;
    cbxLanguage: TComboBox;
    chkShowSystemObjects: TCheckBox;
    chkShowLog: TCheckBox;
    grpEditor: TGroupBox;
    lblFontName: TLabel;
    cbxFontName: TComboBox;
    lblFontSize: TLabel;
    spnFontSize: TSpinEdit;
    lblEditorNote: TLabel;
    grpData: TGroupBox;
    lblRowLimit: TLabel;
    spnRowLimit: TSpinEdit;
    lblDataNote: TLabel;
    pnlButtons: TPanel;
    btnDefaults: TButton;
    btnOK: TButton;
    btnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnDefaultsClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
  private
    FLanguageChanged: Boolean;
    { Fills the language and font lists. }
    procedure FillChoices;
    { Copies the preferences into the controls. }
    procedure ShowSettings;
    { Copies the controls into the preferences. }
    procedure ReadSettings;
  public
    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { True when the chosen language differs from the one in use, so the caller
      knows to apply it. }
    property LanguageChanged: Boolean read FLanguageChanged;
  end;

{ Shows the preferences dialog and saves what the user chose.

  Returns:
    True when the preferences were changed and written, which is the caller's
    signal to re-read the ones that affect it. }
function PreferencesDialog: Boolean;

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  PreferencesDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    The language is applied here rather than by the caller, because
    ApplyLocale reaches every open form including the one that asked - doing
    it anywhere else would leave this dialog in the old language while it was
    still on screen.
------------------------------------------------------------------------------}
function PreferencesDialog: Boolean;
var
  Dialog: TfrmIbqPreferences;
begin
  Result := False;
  Dialog := TfrmIbqPreferences.Create(nil);
  try
    if Dialog.ShowModal <> mrOk then
    begin
      Exit;
    end;
    Result := True;
    if Dialog.LanguageChanged then
    begin
      SetLanguage(Config.Language);
      ApplyLocale;
    end;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqPreferences.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language and shows the current preferences.

  Parameters:
    Sender - The form.
------------------------------------------------------------------------------}
procedure TfrmIbqPreferences.FormCreate(Sender: TObject);
begin
  FLanguageChanged := False;
  ApplyLocaleTo(Self);
  FillChoices;
  ShowSettings;
end;

{------------------------------------------------------------------------------
  TfrmIbqPreferences.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language.
------------------------------------------------------------------------------}
procedure TfrmIbqPreferences.LoadLangStr;
begin
  Caption := LangStr('frmPreferences.caption', 'Preferences');

  grpGeneral.Caption := LangStr('pref.general', 'General');
  lblLanguage.Caption := LangStr('pref.language', 'Language');
  chkShowSystemObjects.Caption := LangStr('pref.showSystem',
    'Show system objects in the tree');
  chkShowLog.Caption := LangStr('pref.showLog', 'Show the log panel');

  grpEditor.Caption := LangStr('pref.editor', 'Editor');
  lblFontName.Caption := LangStr('pref.fontName', 'Font');
  lblFontSize.Caption := LangStr('pref.fontSize', 'Size');
  lblEditorNote.Caption := LangStr('pref.editorNote',
    'The font applies to editor tabs opened from now on. Tabs already open ' +
    'keep the font they were built with.');

  grpData.Caption := LangStr('pref.data', 'Data');
  lblRowLimit.Caption := LangStr('pref.rowLimit', 'Rows to fetch');
  lblDataNote.Caption := LangStr('pref.dataNote',
    'How many rows the data page asks a table for. A grid is for looking at ' +
    'rows, not for holding all of them; raise this only when you know the ' +
    'table is small.');

  btnDefaults.Caption := LangStr('pref.defaults', 'Restore defaults');
  btnOK.Caption := LangStr('btnOK.caption', 'OK');
  btnCancel.Caption := LangStr('btnCancel.caption', 'Cancel');
end;

{------------------------------------------------------------------------------
  TfrmIbqPreferences.FillChoices
  ----------------------------------------------------------------------------
  Fills the language and font lists.

  Notes:
    The language list is whatever language files are installed, plus English,
    which is compiled in and has no file of its own. Without adding it here
    there would be no way back to English once another language was chosen.

    Only fixed-pitch fonts are offered for the editor: a proportional font
    makes columns of SQL and of hex bytes fail to line up, which is the one
    thing those views exist to do.
------------------------------------------------------------------------------}
procedure TfrmIbqPreferences.FillChoices;
var
  Languages: TStringList;
  I: Integer;
begin
  Languages := TStringList.Create;
  try
    ListAvailableLanguages(Languages);
    if Languages.IndexOf(DefaultLanguage) < 0 then
    begin
      Languages.Insert(0, DefaultLanguage);
    end;
    cbxLanguage.Items.Assign(Languages);
  finally
    Languages.Free;
  end;

  cbxFontName.Items.BeginUpdate;
  try
    cbxFontName.Items.Clear;
    for I := 0 to Screen.Fonts.Count - 1 do
    begin
      cbxFontName.Items.Add(Screen.Fonts[I]);
    end;
    if cbxFontName.Items.IndexOf(DefaultEditorFontName) < 0 then
    begin
      cbxFontName.Items.Insert(0, DefaultEditorFontName);
    end;
  finally
    cbxFontName.Items.EndUpdate;
  end;

  spnFontSize.MinValue := MinEditorFontSize;
  spnFontSize.MaxValue := MaxEditorFontSize;
  spnRowLimit.MinValue := MinDataRowLimit;
  spnRowLimit.MaxValue := MaxDataRowLimit;
end;

{------------------------------------------------------------------------------
  TfrmIbqPreferences.ShowSettings
  ----------------------------------------------------------------------------
  Copies the preferences into the controls.

  Notes:
    A language or font recorded in the file but not installed here is added to
    the list rather than silently replaced, so that moving a preferences file
    between machines does not quietly rewrite it.
------------------------------------------------------------------------------}
procedure TfrmIbqPreferences.ShowSettings;
var
  Index: Integer;
begin
  Index := cbxLanguage.Items.IndexOf(Config.Language);
  if Index < 0 then
  begin
    Index := cbxLanguage.Items.Add(Config.Language);
  end;
  cbxLanguage.ItemIndex := Index;

  Index := cbxFontName.Items.IndexOf(Config.EditorFontName);
  if Index < 0 then
  begin
    Index := cbxFontName.Items.Add(Config.EditorFontName);
  end;
  cbxFontName.ItemIndex := Index;

  spnFontSize.Value := Config.EditorFontSize;
  spnRowLimit.Value := Config.DataRowLimit;
  chkShowSystemObjects.Checked := Config.ShowSystemObjects;
  chkShowLog.Checked := Config.ShowLog;
end;

{------------------------------------------------------------------------------
  TfrmIbqPreferences.ReadSettings
  ----------------------------------------------------------------------------
  Copies the controls into the preferences.

  Notes:
    Records whether the language changed BEFORE writing it, because the
    comparison is against what is in use and that is what the property is
    about to become.
------------------------------------------------------------------------------}
procedure TfrmIbqPreferences.ReadSettings;
var
  Chosen: string;
begin
  Chosen := Config.Language;
  if cbxLanguage.ItemIndex >= 0 then
  begin
    Chosen := cbxLanguage.Items[cbxLanguage.ItemIndex];
  end;
  FLanguageChanged := not SameText(Chosen, CurrentLanguage);
  Config.Language := Chosen;

  if cbxFontName.ItemIndex >= 0 then
  begin
    Config.EditorFontName := cbxFontName.Items[cbxFontName.ItemIndex];
  end;
  Config.EditorFontSize := spnFontSize.Value;
  Config.DataRowLimit := spnRowLimit.Value;
  Config.ShowSystemObjects := chkShowSystemObjects.Checked;
  Config.ShowLog := chkShowLog.Checked;
end;

{------------------------------------------------------------------------------
  TfrmIbqPreferences.btnDefaultsClick
  ----------------------------------------------------------------------------
  Puts every control back to its default, without writing anything yet.

  Parameters:
    Sender - The Restore defaults button.

  Notes:
    Only the controls are reset. Nothing is written until OK, so a user who
    presses this and then Cancel still has the preferences they started with.
------------------------------------------------------------------------------}
procedure TfrmIbqPreferences.btnDefaultsClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := cbxLanguage.Items.IndexOf(DefaultLanguage);
  if Index >= 0 then
  begin
    cbxLanguage.ItemIndex := Index;
  end;

  Index := cbxFontName.Items.IndexOf(DefaultEditorFontName);
  if Index >= 0 then
  begin
    cbxFontName.ItemIndex := Index;
  end;

  spnFontSize.Value := DefaultEditorFontSize;
  spnRowLimit.Value := DefaultDataRowLimit;
  chkShowSystemObjects.Checked := False;
  chkShowLog.Checked := True;
end;

{------------------------------------------------------------------------------
  TfrmIbqPreferences.btnOKClick
  ----------------------------------------------------------------------------
  Writes the preferences and closes.

  Parameters:
    Sender - The OK button.

  Notes:
    Stays open when the file cannot be written, because closing would look
    like the settings had been kept when they had not.
------------------------------------------------------------------------------}
procedure TfrmIbqPreferences.btnOKClick(Sender: TObject);
begin
  ReadSettings;

  try
    Config.SaveIfModified;
  except
    on E: Exception do
    begin
      Log.Error(E.Message);
      MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;

  ModalResult := mrOk;
end;

end.
