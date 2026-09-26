{==============================================================================
  Unit:        DataEditor
  Purpose:     An updatable dataset over one table, with its own transaction:
               what the Data tab binds a grid to.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, DB, IBDatabase, IBCustomDataSet,
               IbqError, AppLog, Identifier

  WHY A THIRD TRANSACTION AGAIN
  Browsing data read-only runs on the context's metadata transaction, which is
  READ ONLY on purpose. Editing cannot: it needs a read-write transaction that
  the user controls, exactly as a SQL editor does. So an editable grid owns one,
  and closing the tab rolls it back.

  WHY THE UPDATE SQL IS GENERATED HERE
  IBX does not derive DML from a SELECT at run time - its design-time editor
  does that. So the four statements are built here, using IBX's convention that
  a parameter named OLD_<column> carries the value the row had before the edit
  (IBCustomDataSet.pas line 4351). That convention is an IBX detail and is why
  this generation does not live in units/sql/ScriptGenerator, which builds
  statements for a human to read.

  WHEN EDITING IS REFUSED
  Without a primary key there is no way to name the row being changed, and an
  UPDATE that matches on every column would quietly change duplicates too. The
  dataset is then opened read-only and ReadOnlyReason says why - shown in the
  grid's status strip rather than left for the user to discover by trying.
==============================================================================}
unit DataEditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DB, IBDatabase, IBCustomDataSet,
  IbqError, AppLog, Identifier;

type
  { TDataEditor
    An updatable dataset over one relation. Owns its transaction and its
    dataset; the caller owns this object. }
  TDataEditor = class(TObject)
  private
    FDatabase: TIBDatabase;
    FTransaction: TIBTransaction;
    FDataSet: TIBDataSet;
    FRelation: TIdentifier;
    FCanEdit: Boolean;
    FReadOnlyReason: string;
    FRowLimit: Integer;
    procedure BuildStatements(AColumns, AUpdatableColumns,
      AKeyColumns: TStrings);
    function ParamList(AColumns: TStrings; const APrefix: string;
      const ASeparator: string = ', '): string;
    function KeyMatch(AKeyColumns: TStrings): string;
    function GetDataset: TDataSet;
  public
    constructor Create(ADatabase: TIBDatabase; const ARelation: TIdentifier;
      AColumns, AUpdatableColumns, AKeyColumns: TStrings;
      AAllowEditing: Boolean; const ARefusalReason: string;
      ARowLimit: Integer);
    destructor Destroy; override;

    { Starts the transaction and opens the dataset.

      Raises:
        EIbqDatabaseError - The select failed. }
    procedure Open;
    { Closes the dataset without committing. }
    procedure Close;

    { Writes any pending edit, then commits.

      Notes:
        Posts first: a grid leaves the current row in edit state until focus
        moves, and a user who presses Commit means the row they are looking at
        as well. }
    procedure Commit;
    { Discards every change made since the last commit. }
    procedure Rollback;

    { True while a transaction is open. }
    function InTransaction: Boolean;
    { True when the dataset holds an unposted edit or insert. }
    function HasPendingEdit: Boolean;

    { The dataset, as the base type. Exposed this way so the UI can bind a
      TDataSource to it without ever naming an IBX class - see the layering
      rule in SPECIFICATION.md 3. }
    property Dataset: TDataSet read GetDataset;
    { True when rows can be changed. }
    property CanEdit: Boolean read FCanEdit;
    { Why editing is refused, or an empty string when it is allowed. }
    property ReadOnlyReason: string read FReadOnlyReason;
    { The relation being edited. }
    property Relation: TIdentifier read FRelation;
  end;

implementation

{------------------------------------------------------------------------------
  TDataEditor.Create
  ----------------------------------------------------------------------------
  Builds the dataset and its statements.

  Parameters:
    ADatabase         - The attachment; owned by the database context.
    ARelation         - The table or view.
    AColumns          - Every column, in table order; used by the SELECT.
    AUpdatableColumns - Columns that may be written: everything except
                        computed columns, which Firebird rejects in an INSERT
                        or UPDATE.
    AKeyColumns       - Primary key columns, or empty.
    AAllowEditing     - False to force read-only regardless of the key.
    ARefusalReason    - Why editing is refused when AAllowEditing is False.
    ARowLimit         - How many rows the SELECT asks for.
------------------------------------------------------------------------------}
constructor TDataEditor.Create(ADatabase: TIBDatabase;
  const ARelation: TIdentifier;
  AColumns, AUpdatableColumns, AKeyColumns: TStrings;
  AAllowEditing: Boolean; const ARefusalReason: string;
  ARowLimit: Integer);
begin
  inherited Create;
  FDatabase := ADatabase;
  FRelation := ARelation;
  FRowLimit := ARowLimit;

  FCanEdit := AAllowEditing and (AKeyColumns <> nil) and
    (AKeyColumns.Count > 0) and (AUpdatableColumns <> nil) and
    (AUpdatableColumns.Count > 0);

  if FCanEdit then
    FReadOnlyReason := ''
  else if not AAllowEditing then
    FReadOnlyReason := ARefusalReason
  else if (AKeyColumns = nil) or (AKeyColumns.Count = 0) then
    FReadOnlyReason := 'no primary key - rows cannot be identified, read only'
  else
    FReadOnlyReason := 'no updatable columns, read only';

  FTransaction := TIBTransaction.Create(nil);
  FTransaction.DefaultDatabase := FDatabase;
  FTransaction.Params.Clear;
  FTransaction.Params.Add('concurrency');
  FTransaction.Params.Add('wait');
  if FCanEdit then
    FTransaction.Params.Add('write')
  else
    FTransaction.Params.Add('read');

  FDataSet := TIBDataSet.Create(nil);
  FDataSet.Database := FDatabase;
  FDataSet.Transaction := FTransaction;

  BuildStatements(AColumns, AUpdatableColumns, AKeyColumns);
end;

{------------------------------------------------------------------------------
  TDataEditor.Destroy
  ----------------------------------------------------------------------------
  Closes everything and rolls back.

  Notes:
    Rolls back rather than commits, for the same reason a SQL editor does:
    closing a tab is not a decision to save what is in it.
------------------------------------------------------------------------------}
destructor TDataEditor.Destroy;
begin
  try
    if (FDataSet <> nil) and FDataSet.Active then
    begin
      if FDataSet.State in [dsEdit, dsInsert] then
        FDataSet.Cancel;
      FDataSet.Close;
    end;
    if (FTransaction <> nil) and FTransaction.InTransaction then
      FTransaction.Rollback;
  except
    // shutting down: never let cleanup stop the object being freed
  end;

  FreeAndNil(FDataSet);
  FreeAndNil(FTransaction);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TDataEditor.GetDataset
  ----------------------------------------------------------------------------
  Returns the dataset as the base type.

  Notes:
    A getter rather than reading the field directly, because the field is an
    IBX class and the property is deliberately declared as TDataSet - that
    widening is what lets the UI bind a TDataSource without naming IBX.
------------------------------------------------------------------------------}
function TDataEditor.GetDataset: TDataSet;
begin
  Result := FDataSet;
end;

{------------------------------------------------------------------------------
  TDataEditor.ParamList
  ----------------------------------------------------------------------------
  Builds a list of named parameters for a set of columns.

  Parameters:
    AColumns   - The columns.
    APrefix    - Prefix for the parameter name, '' or 'OLD_'.
    ASeparator - Text between entries.

  Returns:
    ':A, :B, :C'.
------------------------------------------------------------------------------}
function TDataEditor.ParamList(AColumns: TStrings; const APrefix: string;
  const ASeparator: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to AColumns.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ASeparator;
    Result := Result + ':' + APrefix + AColumns[I];
  end;
end;

{------------------------------------------------------------------------------
  TDataEditor.KeyMatch
  ----------------------------------------------------------------------------
  Builds the WHERE clause identifying the row being updated or deleted.

  Parameters:
    AKeyColumns - The primary key columns.

  Returns:
    'WHERE K1 = :OLD_K1 AND K2 = :OLD_K2'.

  Notes:
    OLD_ is IBX's convention for the value the row held before the edit. Using
    the new value here would fail to find the row whenever the key itself was
    changed.
------------------------------------------------------------------------------}
function TDataEditor.KeyMatch(AKeyColumns: TStrings): string;
var
  I: Integer;
begin
  Result := ' WHERE ';
  for I := 0 to AKeyColumns.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ' AND ';
    Result := Result + TIdentifier.FromDatabase(AKeyColumns[I]).Quoted +
      ' = :OLD_' + AKeyColumns[I];
  end;
end;

{------------------------------------------------------------------------------
  TDataEditor.BuildStatements
  ----------------------------------------------------------------------------
  Generates the select and, when editing is allowed, the three DML statements.

  Parameters:
    AColumns          - Every column, for the SELECT.
    AUpdatableColumns - Columns that may be written.
    AKeyColumns       - Primary key columns.

  Notes:
    The SELECT asks for FIRST n rather than fetching everything: a grid over a
    forty-million-row table must not try to be a report writer. Anything beyond
    the limit is a job for the SQL editor.

    RefreshSQL re-reads one row after a post, which is what makes a trigger's
    or a default's effect appear in the grid without a full requery.
------------------------------------------------------------------------------}
procedure TDataEditor.BuildStatements(AColumns, AUpdatableColumns,
  AKeyColumns: TStrings);
var
  I: Integer;
  ColumnText, Assignments, Name_: string;
begin
  Name_ := FRelation.QualifiedQuoted;

  ColumnText := '';
  for I := 0 to AColumns.Count - 1 do
  begin
    if I > 0 then
      ColumnText := ColumnText + ', ';
    ColumnText := ColumnText +
      TIdentifier.FromDatabase(AColumns[I]).Quoted;
  end;

  FDataSet.SelectSQL.Text :=
    Format('SELECT FIRST %d %s FROM %s', [FRowLimit, ColumnText, Name_]);

  if not FCanEdit then
    Exit;

  ColumnText := '';
  for I := 0 to AUpdatableColumns.Count - 1 do
  begin
    if I > 0 then
      ColumnText := ColumnText + ', ';
    ColumnText := ColumnText +
      TIdentifier.FromDatabase(AUpdatableColumns[I]).Quoted;
  end;

  FDataSet.InsertSQL.Text :=
    'INSERT INTO ' + Name_ + ' (' + ColumnText + ') VALUES (' +
    ParamList(AUpdatableColumns, '') + ')';

  Assignments := '';
  for I := 0 to AUpdatableColumns.Count - 1 do
  begin
    if I > 0 then
      Assignments := Assignments + ', ';
    Assignments := Assignments +
      TIdentifier.FromDatabase(AUpdatableColumns[I]).Quoted +
      ' = :' + AUpdatableColumns[I];
  end;

  FDataSet.ModifySQL.Text :=
    'UPDATE ' + Name_ + ' SET ' + Assignments + KeyMatch(AKeyColumns);

  FDataSet.DeleteSQL.Text :=
    'DELETE FROM ' + Name_ + KeyMatch(AKeyColumns);

  ColumnText := '';
  for I := 0 to AColumns.Count - 1 do
  begin
    if I > 0 then
      ColumnText := ColumnText + ', ';
    ColumnText := ColumnText +
      TIdentifier.FromDatabase(AColumns[I]).Quoted;
  end;

  FDataSet.RefreshSQL.Text :=
    'SELECT ' + ColumnText + ' FROM ' + Name_ + KeyMatch(AKeyColumns);
end;

{------------------------------------------------------------------------------
  TDataEditor.Open
  ----------------------------------------------------------------------------
  Starts the transaction and opens the dataset.

  Raises:
    EIbqDatabaseError - The select failed; carries the statement text.
------------------------------------------------------------------------------}
procedure TDataEditor.Open;
begin
  if FDataSet.Active then
    Exit;

  try
    if not FTransaction.InTransaction then
      FTransaction.StartTransaction;
    FDataSet.Open;
    Log.InfoFmt('Data grid opened on %s (%s)',
      [FRelation.DisplayName,
       BoolToStr(FCanEdit, 'editable', 'read only')]);
  except
    on E: Exception do
    begin
      if FTransaction.InTransaction then
        FTransaction.Rollback;
      raise EIbqDatabaseError.Create(E.Message, 0, 0, nil,
        FDataSet.SelectSQL.Text);
    end;
  end;
end;

{------------------------------------------------------------------------------
  TDataEditor.Close
  ----------------------------------------------------------------------------
  Closes the dataset, cancelling any unposted edit.
------------------------------------------------------------------------------}
procedure TDataEditor.Close;
begin
  if not FDataSet.Active then
    Exit;
  if FDataSet.State in [dsEdit, dsInsert] then
    FDataSet.Cancel;
  FDataSet.Close;
end;

{------------------------------------------------------------------------------
  TDataEditor.Commit
  ----------------------------------------------------------------------------
  Posts any pending edit and commits.

  Raises:
    EIbqDatabaseError - The post or the commit failed.
------------------------------------------------------------------------------}
procedure TDataEditor.Commit;
begin
  try
    if FDataSet.Active and (FDataSet.State in [dsEdit, dsInsert]) then
      FDataSet.Post;

    if FTransaction.InTransaction then
    begin
      FTransaction.Commit;
      Log.InfoFmt('Data grid: committed changes to %s',
        [FRelation.DisplayName]);
    end;
  except
    on E: Exception do
      raise EIbqDatabaseError.Create(E.Message, 0, 0, nil, '');
  end;
end;

{------------------------------------------------------------------------------
  TDataEditor.Rollback
  ----------------------------------------------------------------------------
  Discards every change since the last commit.

  Notes:
    Cancels the in-progress edit first, otherwise the dataset would try to post
    it while the transaction is being rolled out from under it.
------------------------------------------------------------------------------}
procedure TDataEditor.Rollback;
begin
  if FDataSet.Active and (FDataSet.State in [dsEdit, dsInsert]) then
    FDataSet.Cancel;

  if FTransaction.InTransaction then
  begin
    FTransaction.Rollback;
    Log.InfoFmt('Data grid: rolled back changes to %s',
      [FRelation.DisplayName]);
  end;
end;

{------------------------------------------------------------------------------
  TDataEditor.InTransaction
  ----------------------------------------------------------------------------
  Returns True while a transaction is open.
------------------------------------------------------------------------------}
function TDataEditor.InTransaction: Boolean;
begin
  Result := (FTransaction <> nil) and FTransaction.InTransaction;
end;

{------------------------------------------------------------------------------
  TDataEditor.HasPendingEdit
  ----------------------------------------------------------------------------
  Returns True when the dataset holds an unposted edit or insert.
------------------------------------------------------------------------------}
function TDataEditor.HasPendingEdit: Boolean;
begin
  Result := (FDataSet <> nil) and FDataSet.Active and
    (FDataSet.State in [dsEdit, dsInsert]);
end;

end.
