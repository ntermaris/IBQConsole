{==============================================================================
  Unit:        frmObjectEditor
  Purpose:     Collects what is needed to create or alter a table, domain,
               index, sequence, exception or role, and runs the statement it
               builds.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
               ComCtrls, Grids, Dialogs, LanguageHandle, AppLog, MetaTypes,
               MetaDatabase, Identifier, DdlStatements

  IBConsole equivalent: the Create dialog under each object folder.

  CREATE AND ALTER ARE THE SAME FORM
  Altering shows the same fields filled in with what the object is now, so
  the two are one dialog rather than two that drift apart. What differs is
  the statement built at the end: creating writes one CREATE, while altering
  compares the fields against what was read and writes only the ALTER
  statements for what the user actually changed. Change nothing and the
  preview is empty and Execute is disabled - there is no statement for
  altering a domain to what it already was, and sending one anyway would make
  Firebird re-check every value in every table using it.

  A name cannot be edited while altering. Firebird's ALTER statements for
  these kinds cannot rename, so an editable name field would offer something
  the Execute button could not deliver.

  ONE FORM, ONE TAB PER KIND
  Six object kinds share this dialog because they share its shape: a few
  fields, a statement, a button. Every tab is in the designer and is shown or
  hidden with TabVisible, per rule 7.2 - a tab that only exists at run time
  cannot be laid out, and these need laying out more than they need
  separating.

  THE PREVIEW IS THE POINT
  The generated statement is visible and updates as the fields are typed, so
  the dialog teaches the SQL rather than replacing it. It is read-only here,
  unlike the one in frmDdlPreview: the fields above are the way to change it,
  and an edited preview that the next keystroke overwrites would be a trap.

  WHAT THIS DIALOG DOES NOT DO
  Views, procedures, triggers and functions are not here. Their bodies are
  programs, and a one-line edit box is the wrong tool for a program - those go
  to the SQL editor with a template, which is where they can be written,
  reformatted and run against a live database. See the Object menu.
==============================================================================}
unit frmObjectEditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Grids, Dialogs,
  LanguageHandle, AppLog, MetaTypes, MetaDatabase, Identifier, DdlStatements;

type
  { Whether the dialog is creating an object or changing one. }
  TObjectEditorMode = (
    emCreate,
    emAlter
  );

  { TfrmIbqObjectEditor
    The create-object dialog.

    Owns nothing: the database is injected and stays owned by the model. }
  TfrmIbqObjectEditor = class(TForm, ILocalizable)
    pnlHeader: TPanel;
    lblDatabase: TLabel;
    lblDatabaseValue: TLabel;
    pgcKind: TPageControl;
    tabTable: TTabSheet;
    lblTblName: TLabel;
    edtTblName: TEdit;
    lblTblColumns: TLabel;
    grdColumns: TStringGrid;
    lblTblPrimaryKey: TLabel;
    edtTblPrimaryKey: TEdit;
    lblTblHint: TLabel;
    tabDomain: TTabSheet;
    lblDomName: TLabel;
    edtDomName: TEdit;
    lblDomType: TLabel;
    edtDomType: TEdit;
    chkDomNotNull: TCheckBox;
    lblDomDefault: TLabel;
    edtDomDefault: TEdit;
    lblDomCheck: TLabel;
    edtDomCheck: TEdit;
    lblDomCollation: TLabel;
    edtDomCollation: TEdit;
    lblDomHint: TLabel;
    tabIndex: TTabSheet;
    lblIdxName: TLabel;
    edtIdxName: TEdit;
    lblIdxTable: TLabel;
    edtIdxTable: TEdit;
    lblIdxColumns: TLabel;
    edtIdxColumns: TEdit;
    chkIdxUnique: TCheckBox;
    chkIdxDescending: TCheckBox;
    chkIdxActive: TCheckBox;
    lblIdxComputed: TLabel;
    edtIdxComputed: TEdit;
    lblIdxHint: TLabel;
    tabSequence: TTabSheet;
    lblSeqName: TLabel;
    edtSeqName: TEdit;
    lblSeqStart: TLabel;
    edtSeqStart: TEdit;
    lblSeqHint: TLabel;
    tabException: TTabSheet;
    lblExcName: TLabel;
    edtExcName: TEdit;
    lblExcMessage: TLabel;
    edtExcMessage: TEdit;
    lblExcHint: TLabel;
    tabRole: TTabSheet;
    lblRoleName: TLabel;
    edtRoleName: TEdit;
    lblRoleHint: TLabel;
    splPreview: TSplitter;
    pnlPreview: TPanel;
    lblPreview: TLabel;
    memPreview: TMemo;
    pnlButtons: TPanel;
    lblStatus: TLabel;
    btnExecute: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FieldChanged(Sender: TObject);
    procedure grdColumnsEditingDone(Sender: TObject);
    procedure btnExecuteClick(Sender: TObject);
  private
    FDatabase: TMetaDatabase;
    FNodeType: TMetaNodeType;
    FMode: TObjectEditorMode;
    FObjectName: string;
    FOriginalDomain: TDdlDomain;
    FCreated: Boolean;
    { Fills the fields with what the object is now, for altering. }
    function LoadCurrent: Boolean;
    { Locks the fields that altering cannot change. }
    procedure ApplyModeToFields;
    { Returns the ALTER statements for what the user changed. }
    function BuildAlterStatement: string;
    { Returns the CREATE statement the fields describe. }
    function BuildCreateStatement: string;
    { Shows the one tab this dialog was opened for and hides the rest. }
    procedure ShowOnlyTabFor(ANodeType: TMetaNodeType);
    { Returns the statement the dialog would run, for whichever mode it is
      in. }
    function BuildStatement: string;
    { Reads the column grid into a column array. }
    function ReadColumns: TDdlColumnArray;
    { Returns the comma-separated text of AEdit as a name array. }
    function SplitNames(const AText: string): TStringArray;
    { Rewrites the preview and enables Execute when there is something to run. }
    procedure UpdatePreview;
    { Logs an error and shows it. }
    procedure ReportError(E: Exception);
  public
    { Prepares the dialog for one kind of object.

      Parameters:
        ADatabase   - The database to work in. Not owned.
        ANodeType   - Which kind of object.
        AMode       - Creating a new one, or altering an existing one.
        AObjectName - Bare name of the object being altered; ignored when
                      creating.

      Returns:
        True when the dialog is ready. False when altering and the object
        could not be read back, in which case there is nothing to show. }
    function PrepareFor(ADatabase: TMetaDatabase; ANodeType: TMetaNodeType;
      AMode: TObjectEditorMode; const AObjectName: string = ''): Boolean;

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { True when something was created or changed, so the caller knows to
      re-read the tree. }
    property Created: Boolean read FCreated;
  end;

{ Returns True when this dialog can create an object of the given kind. }
function CanCreateHere(ANodeType: TMetaNodeType): Boolean;

{ Returns True when this dialog can alter an object of the given kind. }
function CanAlterHere(ANodeType: TMetaNodeType): Boolean;

{ Shows the create dialog for one kind of object.

  Parameters:
    ADatabase - The database to create in.
    ANodeType - Which kind of object.

  Returns:
    True when something was created. }
function NewObjectDialog(ADatabase: TMetaDatabase;
  ANodeType: TMetaNodeType): Boolean;

{ Shows the alter dialog for one existing object.

  Parameters:
    ADatabase   - The database the object lives in.
    ANodeType   - Which kind of object.
    AObjectName - Its bare name.

  Returns:
    True when something was changed. }
function AlterObjectDialog(ADatabase: TMetaDatabase;
  ANodeType: TMetaNodeType; const AObjectName: string): Boolean;

implementation

{$R *.lfm}

const
  { Columns of the column grid. }
  ColColName = 0;
  ColColType = 1;
  ColColNotNull = 2;
  ColColDefault = 3;
  ColColComputed = 4;
  ColColCount = 5;
  { How many blank column rows a new table starts with. }
  StartingColumnRows = 8;

{------------------------------------------------------------------------------
  CanCreateHere
  ----------------------------------------------------------------------------
  Returns True when this dialog can create an object of the given kind.

  Parameters:
    ANodeType - Which kind of object, or the folder that holds them.

  Returns:
    True for the six kinds that have a tab.

  Notes:
    Accepts a folder as well as an object, because the natural place to ask
    for a new table is the Tables folder.
------------------------------------------------------------------------------}
function CanCreateHere(ANodeType: TMetaNodeType): Boolean;
begin
  Result := ANodeType in [mntTable, mntTables, mntDomain, mntDomains,
    mntIndex, mntIndices, mntGenerator, mntGenerators,
    mntException, mntExceptions, mntRole, mntRoles];
end;

{------------------------------------------------------------------------------
  NewObjectDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function NewObjectDialog(ADatabase: TMetaDatabase;
  ANodeType: TMetaNodeType): Boolean;
var
  Dialog: TfrmIbqObjectEditor;
begin
  Result := False;
  if (ADatabase = nil) or not ADatabase.IsConnected then
  begin
    Exit;
  end;
  if not CanCreateHere(ANodeType) then
  begin
    Exit;
  end;

  Dialog := TfrmIbqObjectEditor.Create(nil);
  try
    if Dialog.PrepareFor(ADatabase, ANodeType, emCreate) then
    begin
      Dialog.ShowModal;
      Result := Dialog.Created;
    end;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  CanAlterHere
  ----------------------------------------------------------------------------
  Returns True when this dialog can alter an object of the given kind.

  Parameters:
    ANodeType - Which kind of object.

  Returns:
    True for the four kinds Firebird has an ALTER statement for.

  Notes:
    Fewer kinds than can be created. A table is altered column by column
    with ALTER TABLE, which is a different dialog's worth of work and is
    not pretended at here; a role has nothing alterable at all. Both go to
    the SQL editor, where the DDL is already offered.
------------------------------------------------------------------------------}
function CanAlterHere(ANodeType: TMetaNodeType): Boolean;
begin
  Result := ANodeType in [mntDomain, mntGenerator, mntException,
    mntIndex];
end;

{------------------------------------------------------------------------------
  AlterObjectDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function AlterObjectDialog(ADatabase: TMetaDatabase;
  ANodeType: TMetaNodeType; const AObjectName: string): Boolean;
var
  Dialog: TfrmIbqObjectEditor;
begin
  Result := False;
  if (ADatabase = nil) or not ADatabase.IsConnected then
  begin
    Exit;
  end;
  if not CanAlterHere(ANodeType) then
  begin
    Exit;
  end;

  Dialog := TfrmIbqObjectEditor.Create(nil);
  try
    if Dialog.PrepareFor(ADatabase, ANodeType, emAlter, AObjectName) then
    begin
      Dialog.ShowModal;
      Result := Dialog.Created;
    end;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.

  Parameters:
    Sender - The form.
------------------------------------------------------------------------------}
procedure TfrmIbqObjectEditor.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language.
------------------------------------------------------------------------------}
procedure TfrmIbqObjectEditor.LoadLangStr;
begin
  Caption := LangStr('frmObjectEditor.caption', 'New Object');
  lblDatabase.Caption := LangStr('maint.database', 'Database');
  lblPreview.Caption := LangStr('ddl.preview', 'Statement');

  tabTable.Caption := LangStr('new.table', 'Table');
  lblTblName.Caption := LangStr('new.name', 'Name');
  lblTblColumns.Caption := LangStr('new.columns', 'Columns');
  lblTblPrimaryKey.Caption := LangStr('new.primaryKey', 'Primary key');
  lblTblHint.Caption := LangStr('new.tableHint',
    'One column per row; blank rows are ignored. The primary key is a ' +
    'comma-separated list of column names. A computed column takes neither ' +
    'a default nor NOT NULL.');

  tabDomain.Caption := LangStr('new.domain', 'Domain');
  lblDomName.Caption := LangStr('new.name', 'Name');
  lblDomType.Caption := LangStr('new.type', 'Type');
  chkDomNotNull.Caption := LangStr('new.notNull', 'Not null');
  lblDomDefault.Caption := LangStr('new.default', 'Default');
  lblDomCheck.Caption := LangStr('new.check', 'Check');
  lblDomCollation.Caption := LangStr('new.collation', 'Collation');
  lblDomHint.Caption := LangStr('new.domainHint',
    'The check condition goes in without the surrounding CHECK ( ), and ' +
    'refers to the value being checked as VALUE.');

  tabIndex.Caption := LangStr('new.index', 'Index');
  lblIdxName.Caption := LangStr('new.name', 'Name');
  lblIdxTable.Caption := LangStr('new.onTable', 'On table');
  lblIdxColumns.Caption := LangStr('new.columns', 'Columns');
  chkIdxUnique.Caption := LangStr('new.unique', 'Unique');
  chkIdxDescending.Caption := LangStr('new.descending', 'Descending');
  lblIdxComputed.Caption := LangStr('new.computedBy', 'Computed by');
  lblIdxHint.Caption := LangStr('new.indexHint',
    'Columns are comma-separated. An expression in Computed by replaces ' +
    'them and indexes the expression instead.');

  tabSequence.Caption := LangStr('new.sequence', 'Sequence');
  lblSeqName.Caption := LangStr('new.name', 'Name');
  lblSeqStart.Caption := LangStr('new.startValue', 'Start value');
  lblSeqHint.Caption := LangStr('new.sequenceHint',
    'A start value other than zero is a second statement. On Firebird 4 and ' +
    'later the value you type is the next number the sequence hands out; on ' +
    'Firebird 3 it is the last one used, so the next is one higher.');

  tabException.Caption := LangStr('new.exception', 'Exception');
  lblExcName.Caption := LangStr('new.name', 'Name');
  lblExcMessage.Caption := LangStr('new.message', 'Message');
  lblExcHint.Caption := LangStr('new.exceptionHint',
    'The message is the default text raised with the exception. An ' +
    'apostrophe in it is escaped for you.');

  tabRole.Caption := LangStr('new.role', 'Role');
  lblRoleName.Caption := LangStr('new.name', 'Name');
  lblRoleHint.Caption := LangStr('new.roleHint',
    'A role has nothing else to set at creation. What it may do comes from ' +
    'GRANT afterwards.');

  btnExecute.Caption := LangStr('ddl.execute', 'Execute');
  btnClose.Caption := LangStr('btnClose.caption', 'Close');

  if grdColumns.ColCount >= ColColCount then
  begin
    grdColumns.Cells[ColColName, 0] := LangStr('new.colName', 'Name');
    grdColumns.Cells[ColColType, 0] := LangStr('new.colType', 'Type');
    grdColumns.Cells[ColColNotNull, 0] :=
      LangStr('new.colNotNull', 'Not null');
    grdColumns.Cells[ColColDefault, 0] := LangStr('new.colDefault', 'Default');
    grdColumns.Cells[ColColComputed, 0] :=
      LangStr('new.colComputed', 'Computed by');
  end;

  UpdatePreview;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.PrepareFor
  ----------------------------------------------------------------------------
  Prepares the dialog for one kind of object.

  Parameters:
    ADatabase - The database to create in. Not owned.
    ANodeType - Which kind of object to create.
------------------------------------------------------------------------------}
function TfrmIbqObjectEditor.PrepareFor(ADatabase: TMetaDatabase;
  ANodeType: TMetaNodeType; AMode: TObjectEditorMode;
  const AObjectName: string): Boolean;
begin
  FDatabase := ADatabase;      // injected, NOT owned
  FNodeType := ANodeType;
  FMode := AMode;
  FObjectName := AObjectName;
  FCreated := False;
  FOriginalDomain := Default(TDdlDomain);

  if ADatabase <> nil then
  begin
    lblDatabaseValue.Caption := ADatabase.DisplayName;
  end;

  grdColumns.RowCount := StartingColumnRows + 1;
  grdColumns.FixedRows := 1;

  ShowOnlyTabFor(ANodeType);

  Result := True;
  if FMode = emAlter then
  begin
    Result := LoadCurrent;
    if not Result then
    begin
      Exit;
    end;
  end;

  ApplyModeToFields;
  UpdatePreview;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.LoadCurrent
  ----------------------------------------------------------------------------
  Fills the fields with what the object is now, for altering.

  Returns:
    True when the object was read. False when it was not, which is reported
    here and leaves the caller with nothing to show.

  Notes:
    The domain is kept as it was read, in FOriginalDomain, because the ALTER
    statements are the DIFFERENCE between that and what the user leaves in
    the fields. Without the original there is nothing to compare against and
    every property would be rewritten whether or not it changed.
------------------------------------------------------------------------------}
function TfrmIbqObjectEditor.LoadCurrent: Boolean;
var
  MessageText: string;
  IsActive: Boolean;
  CurrentValue: Int64;
begin
  Result := False;
  if FDatabase = nil then
  begin
    Exit;
  end;

  case FNodeType of
    mntDomain:
      begin
        Result := FDatabase.FetchDomainDefinition(FObjectName,
          FOriginalDomain);
        if Result then
        begin
          edtDomName.Text := FObjectName;
          edtDomType.Text := FOriginalDomain.DataType;
          chkDomNotNull.Checked := FOriginalDomain.NotNull;
          edtDomDefault.Text := FOriginalDomain.DefaultValue;
          edtDomCheck.Text := FOriginalDomain.CheckCondition;
          edtDomCollation.Text := FOriginalDomain.Collation;
        end;
      end;

    mntException:
      begin
        Result := FDatabase.FetchExceptionMessage(FObjectName, MessageText);
        if Result then
        begin
          edtExcName.Text := FObjectName;
          edtExcMessage.Text := MessageText;
        end;
      end;

    mntIndex:
      begin
        Result := FDatabase.FetchIndexActive(FObjectName, IsActive);
        if Result then
        begin
          edtIdxName.Text := FObjectName;
          chkIdxActive.Checked := IsActive;
        end;
      end;

    mntGenerator:
      begin
        { A sequence that cannot be read is still worth offering: the
          restart value is what the user is setting, not what it was. }
        FDatabase.FetchSequenceValue(FObjectName, CurrentValue);
        edtSeqName.Text := FObjectName;
        edtSeqStart.Text := IntToStr(CurrentValue);
        Result := True;
      end;
  else
    Result := False;
  end;

  if not Result then
  begin
    MessageDlg(Caption,
      LangStrFormat('alter.notFound', [FObjectName],
        'The server did not return a definition for %s. It may have been '
        + 'dropped since the tree was last read.'),
      mtWarning, [mbOK], 0);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.ApplyModeToFields
  ----------------------------------------------------------------------------
  Locks the fields that altering cannot change.

  Notes:
    Read-only rather than hidden, so that the name of the thing being
    altered stays on screen: a dialog that changes something without
    naming it is a dialog you have to remember your way around.

    An index's columns, uniqueness and direction are locked too. Firebird
    has no statement that changes them - that is a drop and a create - and
    an editable field the Execute button ignores is worse than a locked one.
------------------------------------------------------------------------------}
procedure TfrmIbqObjectEditor.ApplyModeToFields;
var
  Altering: Boolean;
begin
  Altering := FMode = emAlter;

  edtDomName.ReadOnly := Altering;
  edtExcName.ReadOnly := Altering;
  edtIdxName.ReadOnly := Altering;
  edtSeqName.ReadOnly := Altering;
  edtTblName.ReadOnly := Altering;
  edtRoleName.ReadOnly := Altering;

  edtIdxTable.Enabled := not Altering;
  edtIdxColumns.Enabled := not Altering;
  edtIdxComputed.Enabled := not Altering;
  chkIdxUnique.Enabled := not Altering;
  chkIdxDescending.Enabled := not Altering;
  chkIdxActive.Visible := Altering;

  if Altering then
  begin
    Caption := LangStrFormat('alter.caption', [FObjectName],
      'Alter %s');
    lblIdxHint.Caption := LangStr('alter.indexHint',
      'Only the active flag can be altered. Changing an index''s columns '
      + 'or its uniqueness means dropping it and creating it again.');
    lblSeqHint.Caption := LangStr('alter.sequenceHint',
      'On Firebird 4 and later the value you type is the next number handed '
      + 'out; on Firebird 3 it is the last one used, so the next is one '
      + 'higher. Lowering it below rows that already exist will hand out '
      + 'keys that are already taken.');
    lblDomHint.Caption := LangStr('alter.domainHint',
      'Only what you change is written. Changing the type re-checks every '
      + 'value in every table using this domain, which on a large table '
      + 'is not quick.');
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.ShowOnlyTabFor
  ----------------------------------------------------------------------------
  Shows the one tab this dialog was opened for and hides the rest.

  Parameters:
    ANodeType - Which kind of object, or the folder that holds them.

  Notes:
    Hiding rather than removing, so every tab stays in the designer and stays
    editable there.
------------------------------------------------------------------------------}
procedure TfrmIbqObjectEditor.ShowOnlyTabFor(ANodeType: TMetaNodeType);
var
  I: Integer;
  Wanted: TTabSheet;
begin
  case ANodeType of
    mntTable, mntTables:
      Wanted := tabTable;
    mntDomain, mntDomains:
      Wanted := tabDomain;
    mntIndex, mntIndices:
      Wanted := tabIndex;
    mntGenerator, mntGenerators:
      Wanted := tabSequence;
    mntException, mntExceptions:
      Wanted := tabException;
    mntRole, mntRoles:
      Wanted := tabRole;
  else
    Wanted := nil;
  end;

  for I := 0 to pgcKind.PageCount - 1 do
  begin
    pgcKind.Pages[I].TabVisible := pgcKind.Pages[I] = Wanted;
  end;

  if Wanted <> nil then
  begin
    pgcKind.ActivePage := Wanted;
    Caption := LangStrFormat('new.captionFor', [Wanted.Caption], 'New %s');
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.SplitNames
  ----------------------------------------------------------------------------
  Returns the comma-separated text of a field as a name array.

  Parameters:
    AText - What the user typed, names separated by commas.

  Returns:
    The names, with blanks dropped. An empty array when there are none.
------------------------------------------------------------------------------}
function TfrmIbqObjectEditor.SplitNames(const AText: string): TStringArray;
var
  List: TStringList;
  I: Integer;
begin
  Result := nil;
  List := TStringList.Create;
  try
    List.StrictDelimiter := True;
    List.Delimiter := ',';
    List.DelimitedText := AText;
    for I := 0 to List.Count - 1 do
    begin
      if Trim(List[I]) = '' then
      begin
        Continue;
      end;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Trim(List[I]);
    end;
  finally
    List.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.ReadColumns
  ----------------------------------------------------------------------------
  Reads the column grid into a column array.

  Returns:
    One entry per row that names a column. Rows with no name are skipped, so
    the grid can have as many spare rows as it likes.
------------------------------------------------------------------------------}
function TfrmIbqObjectEditor.ReadColumns: TDdlColumnArray;
var
  Row: Integer;
  ColumnName: string;
begin
  Result := nil;
  for Row := 1 to grdColumns.RowCount - 1 do
  begin
    ColumnName := Trim(grdColumns.Cells[ColColName, Row]);
    if ColumnName = '' then
    begin
      Continue;
    end;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Name := ColumnName;
    Result[High(Result)].DataType :=
      Trim(grdColumns.Cells[ColColType, Row]);
    Result[High(Result)].NotNull :=
      SameText(Trim(grdColumns.Cells[ColColNotNull, Row]), 'Y') or
      SameText(Trim(grdColumns.Cells[ColColNotNull, Row]),
        LangStr('word.yes', 'Yes'));
    Result[High(Result)].DefaultValue :=
      Trim(grdColumns.Cells[ColColDefault, Row]);
    Result[High(Result)].ComputedBy :=
      Trim(grdColumns.Cells[ColColComputed, Row]);
    Result[High(Result)].Collation := '';
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.BuildCreateStatement
  ----------------------------------------------------------------------------
  Returns the CREATE statement the fields describe.

  Returns:
    The statement, or an empty string when the fields do not yet describe one
    - which is the ordinary state of a dialog that has just opened.
------------------------------------------------------------------------------}
function TfrmIbqObjectEditor.BuildCreateStatement: string;
var
  Table: TDdlTable;
  Domain: TDdlDomain;
  Index: TDdlIndex;
begin
  Result := '';

  case FNodeType of
    mntTable, mntTables:
      begin
        Table.Name := TIdentifier.FromUserInput(edtTblName.Text);
        Table.Columns := ReadColumns;
        Table.PrimaryKey := SplitNames(edtTblPrimaryKey.Text);
        Result := CreateTableStatement(Table);
      end;

    mntDomain, mntDomains:
      begin
        Domain.Name := TIdentifier.FromUserInput(edtDomName.Text);
        Domain.DataType := edtDomType.Text;
        Domain.NotNull := chkDomNotNull.Checked;
        Domain.DefaultValue := edtDomDefault.Text;
        Domain.CheckCondition := edtDomCheck.Text;
        Domain.Collation := edtDomCollation.Text;
        Result := CreateDomainStatement(Domain);
      end;

    mntIndex, mntIndices:
      begin
        Index.Name := TIdentifier.FromUserInput(edtIdxName.Text);
        Index.TableName := TIdentifier.FromUserInput(edtIdxTable.Text);
        Index.Columns := SplitNames(edtIdxColumns.Text);
        Index.Unique := chkIdxUnique.Checked;
        Index.Descending := chkIdxDescending.Checked;
        Index.ComputedBy := edtIdxComputed.Text;
        Result := CreateIndexStatement(Index);
      end;

    mntGenerator, mntGenerators:
      begin
        Result := CreateSequenceStatement(
          TIdentifier.FromUserInput(edtSeqName.Text),
          StrToInt64Def(Trim(edtSeqStart.Text), 0));
      end;

    mntException, mntExceptions:
      begin
        Result := CreateExceptionStatement(
          TIdentifier.FromUserInput(edtExcName.Text), edtExcMessage.Text);
      end;

    mntRole, mntRoles:
      begin
        Result := CreateRoleStatement(
          TIdentifier.FromUserInput(edtRoleName.Text));
      end;
  else
    Result := '';
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.BuildAlterStatement
  ----------------------------------------------------------------------------
  Returns the ALTER statements for what the user changed.

  Returns:
    The statements, or an empty string when nothing was changed - which is
    what disables Execute, because there is no statement for altering
    something to what it already is.
------------------------------------------------------------------------------}
function TfrmIbqObjectEditor.BuildAlterStatement: string;
var
  Domain: TDdlDomain;
begin
  Result := '';
  case FNodeType of
    mntDomain:
      begin
        Domain.Name := TIdentifier.FromDatabase(FObjectName);
        Domain.DataType := edtDomType.Text;
        Domain.NotNull := chkDomNotNull.Checked;
        Domain.DefaultValue := edtDomDefault.Text;
        Domain.CheckCondition := edtDomCheck.Text;
        Domain.Collation := edtDomCollation.Text;
        Result := AlterDomainStatements(FOriginalDomain, Domain);
      end;

    mntException:
      begin
        Result := AlterExceptionStatement(
          TIdentifier.FromDatabase(FObjectName), edtExcMessage.Text);
      end;

    mntIndex:
      begin
        Result := AlterIndexActiveStatement(
          TIdentifier.FromDatabase(FObjectName), chkIdxActive.Checked);
      end;

    mntGenerator:
      begin
        Result := AlterSequenceStatement(
          TIdentifier.FromDatabase(FObjectName),
          StrToInt64Def(Trim(edtSeqStart.Text), 0));
      end;
  else
    Result := '';
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.BuildStatement
  ----------------------------------------------------------------------------
  Returns the statement the dialog would run, for whichever mode it is in.

  Returns:
    The statement, or an empty string when there is nothing to run.
------------------------------------------------------------------------------}
function TfrmIbqObjectEditor.BuildStatement: string;
begin
  if FMode = emAlter then
  begin
    Result := BuildAlterStatement;
  end
  else
  begin
    Result := BuildCreateStatement;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.UpdatePreview
  ----------------------------------------------------------------------------
  Rewrites the preview and enables Execute when there is something to run.
------------------------------------------------------------------------------}
procedure TfrmIbqObjectEditor.UpdatePreview;
var
  Statement: string;
begin
  Statement := BuildStatement;
  memPreview.Lines.Text := Statement;
  btnExecute.Enabled := (Statement <> '') and (FDatabase <> nil);
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.FieldChanged
  ----------------------------------------------------------------------------
  Rebuilds the preview whenever any field changes.

  Parameters:
    Sender - Whichever edit or check box was touched; they all share this.
------------------------------------------------------------------------------}
procedure TfrmIbqObjectEditor.FieldChanged(Sender: TObject);
begin
  UpdatePreview;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.grdColumnsEditingDone
  ----------------------------------------------------------------------------
  Rebuilds the preview after a grid cell is edited.

  Parameters:
    Sender - The column grid.

  Notes:
    A grid reports the finished edit rather than each keystroke, so the
    preview follows a cell at a time. Adding a row when the last one fills up
    means the grid never runs out without the user asking for more.
------------------------------------------------------------------------------}
procedure TfrmIbqObjectEditor.grdColumnsEditingDone(Sender: TObject);
begin
  if Trim(grdColumns.Cells[ColColName, grdColumns.RowCount - 1]) <> '' then
  begin
    grdColumns.RowCount := grdColumns.RowCount + 1;
  end;
  UpdatePreview;
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.ReportError
  ----------------------------------------------------------------------------
  Logs an error and shows it.

  Parameters:
    E - What went wrong.
------------------------------------------------------------------------------}
procedure TfrmIbqObjectEditor.ReportError(E: Exception);
begin
  Log.Error(E.Message);
  lblStatus.Caption := LangStr('ddl.failed', 'Failed.');
  MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
end;

{------------------------------------------------------------------------------
  TfrmIbqObjectEditor.btnExecuteClick
  ----------------------------------------------------------------------------
  Runs the generated statement and closes when it worked.

  Parameters:
    Sender - The Execute button.

  Notes:
    Stays open on failure with the fields as they were, because the usual next
    move is to correct one of them - a type that does not exist, a table that
    is spelled differently - and retype nothing else.
------------------------------------------------------------------------------}
procedure TfrmIbqObjectEditor.btnExecuteClick(Sender: TObject);
var
  Statement: string;
  Done: Integer;
begin
  Statement := BuildStatement;
  if (Statement = '') or (FDatabase = nil) then
  begin
    Exit;
  end;

  try
    Done := FDatabase.ExecuteDdlScript(Statement);
  except
    on E: Exception do
    begin
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

  FCreated := True;
  Log.InfoFmt('Ran %d DDL statement(s) from the object editor', [Done]);
  ModalResult := mrOk;
end;

end.
