{==============================================================================
  Unit:        fraObjectPage
  Purpose:     The property page for one metadata object: the tabbed view that
               fills a workspace tab in the main window.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  LCL, LanguageHandle, MetaItem, MetaTypes, MetaDatabase,
               MetaSubject, DatabaseRow, fraDataGrid

  Every tab exists in the designer and is shown or hidden with TabVisible,
  rather than being created at run time. That is PASCAL-LAZARUS-RULES.md 7.1:
  a page built in code cannot be opened in the form designer, so nobody can
  adjust it without running the program.

  Hiding rather than creating also keeps the behaviour that matters: a detail
  with no rows shows NO tab. A table with no triggers should not offer a
  Triggers tab the user must click to discover is empty - the absence is the
  answer, at a glance.

  Everything here is read-only except the Data tab, which hosts the editable
  grid.
==============================================================================}
unit fraObjectPage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ComCtrls, Grids, StdCtrls, ExtCtrls,
  Graphics,
  LanguageHandle, MetaItem, MetaTypes, MetaDatabase, MetaSubject, DatabaseRow,
  fraDataGrid;

type

  { TfraObjectPage
    Shows one object. Observes it, so the page closes itself when the object is
    dropped or its database disconnects. }
  TfraObjectPage = class(TFrame, ILocalizable, IMetaObserver)
    pgcTabs: TPageControl;
    tabProperties: TTabSheet;
    grdProperties: TStringGrid;
    tabColumns: TTabSheet;
    grdColumns: TStringGrid;
    tabParameters: TTabSheet;
    grdParameters: TStringGrid;
    tabIndexInfo: TTabSheet;
    grdIndexInfo: TStringGrid;
    tabIndexes: TTabSheet;
    grdIndexes: TStringGrid;
    tabConstraints: TTabSheet;
    grdConstraints: TStringGrid;
    tabTriggers: TTabSheet;
    grdTriggers: TStringGrid;
    tabSource: TTabSheet;
    memSource: TMemo;
    tabDependsOn: TTabSheet;
    grdDependsOn: TStringGrid;
    tabUsedBy: TTabSheet;
    grdUsedBy: TStringGrid;
    tabPermissions: TTabSheet;
    grdPermissions: TStringGrid;
    tabData: TTabSheet;
    pnlData: TPanel;
    tabDdl: TTabSheet;
    memDdl: TMemo;
  private
    FItem: TMetaItem;
    FDatabase: TMetaDatabase;
    FDataGrid: TfraDataGrid;
    FOnCloseRequest: TNotifyEvent;
    procedure FillGrid(AGrid: TStringGrid; const ATable: TDataTable);
    procedure ShowDetailTab(ADetail: TObjectDetail; ASheet: TTabSheet;
      AGrid: TStringGrid; const ACaptionKey, ADefaultCaption: string);
    procedure ShowMemoTab(ASheet: TTabSheet; AMemo: TMemo;
      const ACaptionKey, ADefaultCaption, AText: string);
    procedure ShowPropertiesTab;
    procedure ShowDataTab;
    procedure RefreshTabs;
    procedure HideAllTabs;
  public
    destructor Destroy; override;

    { Shows AItem, replacing whatever was shown before.

      Parameters:
        AItem - The object to display. Must belong to a connected database. }
    procedure ShowItem(AItem: TMetaItem);

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { The subject changed: rebuild the tabs. Part of IMetaObserver. }
    procedure SubjectChanged(ASubject: TMetaSubject);
    { The subject is going away: ask to be closed. Part of IMetaObserver. }
    procedure SubjectRemoved(ASubject: TMetaSubject);

    { The object currently shown, or nil. }
    property Item: TMetaItem read FItem;
    { Raised when the page must close because its object is gone. }
    property OnCloseRequest: TNotifyEvent read FOnCloseRequest
      write FOnCloseRequest;
  end;

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  TfraObjectPage.Destroy
  ----------------------------------------------------------------------------
  Stops observing before the page goes away.

  Notes:
    Detaching matters: the object outlives the page, and a subject holding a
    freed observer would fault on the next change.
------------------------------------------------------------------------------}
destructor TfraObjectPage.Destroy;
begin
  if FItem <> nil then
    FItem.DetachObserver(Self);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.ShowItem
  ----------------------------------------------------------------------------
  Shows one object.

  Parameters:
    AItem - The object to display; nil clears the page.
------------------------------------------------------------------------------}
procedure TfraObjectPage.ShowItem(AItem: TMetaItem);
var
  Ancestor: TMetaItem;
begin
  if FItem <> nil then
    FItem.DetachObserver(Self);

  FItem := AItem;
  FDatabase := nil;

  if FItem <> nil then
  begin
    FItem.AttachObserver(Self);
    Ancestor := FItem.AncestorOfType(mntDatabase);
    if Ancestor is TMetaDatabase then
      FDatabase := TMetaDatabase(Ancestor);
  end;

  RefreshTabs;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.HideAllTabs
  ----------------------------------------------------------------------------
  Hides every tab, ready for RefreshTabs to show the ones that apply.
------------------------------------------------------------------------------}
procedure TfraObjectPage.HideAllTabs;
var
  I: Integer;
begin
  for I := 0 to pgcTabs.PageCount - 1 do
    pgcTabs.Pages[I].TabVisible := False;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.FillGrid
  ----------------------------------------------------------------------------
  Copies a result set into a grid.

  Parameters:
    AGrid  - The grid to fill.
    ATable - The result set.

  Notes:
    Column widths are measured from the first fifty rows rather than from every
    row: on a large result the difference is seconds, and beyond the first
    screenful nobody is measuring anyway.
------------------------------------------------------------------------------}
procedure TfraObjectPage.FillGrid(AGrid: TStringGrid; const ATable: TDataTable);
const
  MaxSampledRows = 50;
  MinColumnWidth = 60;
  MaxColumnWidth = 400;
var
  R, C, CellWidth, Sampled: Integer;
  CellText: string;
begin
  AGrid.BeginUpdate;
  try
    AGrid.Clear;
    AGrid.FixedRows := 0;
    AGrid.ColCount := ATable.ColumnCount;
    AGrid.RowCount := ATable.RowCount + 1;
    if ATable.ColumnCount > 0 then
      AGrid.FixedRows := 1;

    for C := 0 to ATable.ColumnCount - 1 do
      AGrid.Cells[C, 0] := ATable.ColumnNames[C];

    for R := 0 to ATable.RowCount - 1 do
      for C := 0 to ATable.ColumnCount - 1 do
        AGrid.Cells[C, R + 1] := TrimRight(ATable.ValueAt(R, C));

    Sampled := ATable.RowCount;
    if Sampled > MaxSampledRows then
      Sampled := MaxSampledRows;

    for C := 0 to ATable.ColumnCount - 1 do
    begin
      CellWidth := AGrid.Canvas.TextWidth(ATable.ColumnNames[C]);
      for R := 0 to Sampled - 1 do
      begin
        CellText := TrimRight(ATable.ValueAt(R, C));
        if AGrid.Canvas.TextWidth(CellText) > CellWidth then
          CellWidth := AGrid.Canvas.TextWidth(CellText);
      end;
      Inc(CellWidth, 20);
      if CellWidth < MinColumnWidth then
        CellWidth := MinColumnWidth;
      if CellWidth > MaxColumnWidth then
        CellWidth := MaxColumnWidth;
      AGrid.ColWidths[C] := CellWidth;
    end;
  finally
    AGrid.EndUpdate;
  end;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.ShowDetailTab
  ----------------------------------------------------------------------------
  Fills one detail tab and shows it, or leaves it hidden.

  Parameters:
    ADetail         - Which detail list.
    ASheet          - The tab to fill.
    AGrid           - The grid inside it.
    ACaptionKey     - Language key for the caption.
    ADefaultCaption - English caption.

  Notes:
    A failed query shows the tab with the error in it rather than killing the
    whole page: a user without rights to RDB$USER_PRIVILEGES should still see
    the columns of a table.
------------------------------------------------------------------------------}
procedure TfraObjectPage.ShowDetailTab(ADetail: TObjectDetail;
  ASheet: TTabSheet; AGrid: TStringGrid;
  const ACaptionKey, ADefaultCaption: string);
var
  Table: TDataTable;
begin
  ASheet.TabVisible := False;
  if (FDatabase = nil) or (FItem = nil) then
    Exit;

  try
    Table := FDatabase.FetchDetail(ADetail, FItem.NodeType,
      FItem.Ident.AsString);
  except
    on E: Exception do
    begin
      Table := Default(TDataTable);
      SetLength(Table.ColumnNames, 1);
      Table.ColumnNames[0] := LangStr('tab.error', 'Error');
      SetLength(Table.Rows, 1);
      SetLength(Table.Rows[0], 1);
      Table.Rows[0][0] := E.Message;
    end;
  end;

  if Table.RowCount = 0 then
    Exit;

  FillGrid(AGrid, Table);
  ASheet.Caption := LangStr(ACaptionKey, ADefaultCaption) +
    ' (' + IntToStr(Table.RowCount) + ')';
  ASheet.TabVisible := True;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.ShowMemoTab
  ----------------------------------------------------------------------------
  Fills one text tab and shows it, or leaves it hidden.

  Parameters:
    ASheet          - The tab.
    AMemo           - The memo inside it.
    ACaptionKey     - Language key for the caption.
    ADefaultCaption - English caption.
    AText           - The text; empty leaves the tab hidden.
------------------------------------------------------------------------------}
procedure TfraObjectPage.ShowMemoTab(ASheet: TTabSheet; AMemo: TMemo;
  const ACaptionKey, ADefaultCaption, AText: string);
begin
  if Trim(AText) = '' then
  begin
    AMemo.Lines.Clear;
    ASheet.TabVisible := False;
    Exit;
  end;

  AMemo.Lines.Text := AText;
  ASheet.Caption := LangStr(ACaptionKey, ADefaultCaption);
  ASheet.TabVisible := True;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.ShowPropertiesTab
  ----------------------------------------------------------------------------
  Fills the Properties tab, which every object has.

  Notes:
    A two-column name/value grid rather than laid-out labels, because the set
    of properties differs per object kind and a grid needs no per-kind form.
------------------------------------------------------------------------------}
procedure TfraObjectPage.ShowPropertiesTab;
var
  Table: TDataTable;

  procedure AddRow(const AName, AValue: string);
  var
    Index: Integer;
  begin
    Index := Length(Table.Rows);
    SetLength(Table.Rows, Index + 1);
    SetLength(Table.Rows[Index], 2);
    Table.Rows[Index][0] := AName;
    Table.Rows[Index][1] := AValue;
  end;

begin
  Table := Default(TDataTable);
  SetLength(Table.ColumnNames, 2);
  Table.ColumnNames[0] := LangStr('prop.name', 'Property');
  Table.ColumnNames[1] := LangStr('prop.value', 'Value');

  AddRow(LangStr('prop.objectName', 'Name'), FItem.Ident.DisplayName);
  AddRow(LangStr('prop.objectType', 'Type'),
    LangStr(NodeCaptionKey(FItem.NodeType),
      DefaultNodeCaption(FItem.NodeType)));
  if FItem.Ident.Schema <> '' then
    AddRow(LangStr('prop.schema', 'Schema'), FItem.Ident.Schema);
  if FItem.ObjectId >= 0 then
    AddRow(LangStr('prop.objectId', 'Internal id'), IntToStr(FItem.ObjectId));
  AddRow(LangStr('prop.quotedName', 'Quoted name'), FItem.Ident.Quoted);
  if FItem.Ident.NeedsQuoting then
    AddRow(LangStr('prop.needsQuoting', 'Needs quoting'),
      LangStr('common.yes', 'Yes'));
  if FDatabase <> nil then
    AddRow(LangStr('prop.database', 'Database'), FDatabase.DisplayName);
  if FItem.Description <> '' then
    AddRow(LangStr('prop.description', 'Description'), FItem.Description);

  FillGrid(grdProperties, Table);
  tabProperties.Caption := LangStr('tab.properties', 'Properties');
  tabProperties.TabVisible := True;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.ShowDataTab
  ----------------------------------------------------------------------------
  Puts the editable grid on the Data tab, for a table or view.

  Notes:
    The grid is a frame, and a frame inside a frame is not something the
    designer places, so it is created once into the design-time panel that
    holds it. That panel IS in the designer, which is what the rule asks for -
    the layout is editable, only the nested frame is instantiated in code.
------------------------------------------------------------------------------}
procedure TfraObjectPage.ShowDataTab;
begin
  tabData.TabVisible := False;
  if (FDatabase = nil) or (FItem = nil) then
    Exit;
  if not IsBrowsableType(FItem.NodeType) then
    Exit;

  if FDataGrid = nil then
  begin
    FDataGrid := TfraDataGrid.Create(Self);
    FDataGrid.Parent := pnlData;
    FDataGrid.Align := alClient;
  end;

  FDataGrid.LoadLangStr;
  FDataGrid.OpenRelation(FDatabase, FItem.NodeType, FItem.Ident.AsString);

  tabData.Caption := LangStr('tab.data', 'Data');
  tabData.TabVisible := True;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.RefreshTabs
  ----------------------------------------------------------------------------
  Fills every tab for the current object and hides the ones that do not apply.
------------------------------------------------------------------------------}
procedure TfraObjectPage.RefreshTabs;
begin
  pgcTabs.DisableAutoSizing;
  try
    HideAllTabs;

    if FItem = nil then
      Exit;

    ShowPropertiesTab;

    ShowDetailTab(odIndexInfo, tabIndexInfo, grdIndexInfo,
      'tab.indexInfo', 'Index');
    ShowDetailTab(odColumns, tabColumns, grdColumns, 'tab.columns', 'Columns');
    ShowDetailTab(odParameters, tabParameters, grdParameters,
      'tab.parameters', 'Parameters');
    ShowDetailTab(odIndices, tabIndexes, grdIndexes, 'tab.indexes', 'Indexes');
    ShowDetailTab(odConstraints, tabConstraints, grdConstraints,
      'tab.constraints', 'Constraints');
    ShowDetailTab(odTriggers, tabTriggers, grdTriggers,
      'tab.triggers', 'Triggers');

    if FDatabase <> nil then
    begin
      ShowMemoTab(tabSource, memSource, 'tab.source', 'Source',
        FDatabase.FetchSourceText(FItem.NodeType, FItem.Ident.AsString));

      ShowDetailTab(odDependsOn, tabDependsOn, grdDependsOn,
        'tab.dependsOn', 'Depends on');
      ShowDetailTab(odUsedBy, tabUsedBy, grdUsedBy, 'tab.usedBy', 'Used by');
      ShowDetailTab(odPrivileges, tabPermissions, grdPermissions,
        'tab.permissions', 'Permissions');

      ShowDataTab;

      ShowMemoTab(tabDdl, memDdl, 'tab.ddl', 'DDL',
        FDatabase.FetchObjectDdl(FItem.NodeType, FItem.Ident.AsString));
    end;

    pgcTabs.ActivePage := tabProperties;
  finally
    pgcTabs.EnableAutoSizing;
  end;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.LoadLangStr
  ----------------------------------------------------------------------------
  Rebuilds the tabs so their captions come from the new language.
------------------------------------------------------------------------------}
procedure TfraObjectPage.LoadLangStr;
begin
  RefreshTabs;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.SubjectChanged
  ----------------------------------------------------------------------------
  Rebuilds the page when the object it shows changed.

  Parameters:
    ASubject - The object; always the one this page shows.
------------------------------------------------------------------------------}
procedure TfraObjectPage.SubjectChanged(ASubject: TMetaSubject);
begin
  RefreshTabs;
end;

{------------------------------------------------------------------------------
  TfraObjectPage.SubjectRemoved
  ----------------------------------------------------------------------------
  Asks to be closed, because the object shown no longer exists.

  Parameters:
    ASubject - The object being destroyed.

  Notes:
    The reference is dropped BEFORE the close is requested, because the pointer
    is already invalid by the time this runs. This is what makes a dropped
    object close its own property page - the thing IBConsole never did, which
    is why it could leave a window pointing at nothing.
------------------------------------------------------------------------------}
procedure TfraObjectPage.SubjectRemoved(ASubject: TMetaSubject);
begin
  FItem := nil;
  FDatabase := nil;
  if Assigned(FOnCloseRequest) then
    FOnCloseRequest(Self);
end;

end.
