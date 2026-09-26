{==============================================================================
  Unit:        frmMain
  Purpose:     The main window: object tree on the left, workspace tabs on the
               right, log panel at the bottom, status bar underneath. Follows
               IBConsole's menu spine, without its MDI.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  LCL, LanguageHandle, AppLog, IbqError, MetaItem, MetaTypes,
               MetaRoot, MetaServer, MetaDatabase, MetaCollection,
               ServerRegistration, ConnectionProfile, frmServerRegistration

  The tree is filled lazily. A node that can have children is given a single
  placeholder child so that it shows an expander; the real children are read
  the first time the user expands it. That is what keeps the window usable
  against a database with thousands of objects.
==============================================================================}
unit frmMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, Menus, ComCtrls, ExtCtrls,
  StdCtrls,
  LanguageHandle, AppLog, IbqError, MetaItem, MetaTypes, MetaRoot, MetaServer,
  MetaDatabase, MetaCollection, ServerRegistration, ConnectionProfile,
  StatementHistory, ScriptGenerator,
  frmServerRegistration, frmDatabaseRegistration, fraObjectPage, frmSqlEditor,
  frmExecuteRoutine, frmMaintenance, frmUserManager,
  frmTransactionRecovery, frmConnectedUsers, frmImportRegistrations,
  frmDdlPreview, frmObjectEditor, DdlStatements, AppConfig,
  frmPreferences, frmServerProperties;

type

  { TfrmIbqMain
    The application's main window. Owns the metadata root and the tree that
    displays it; every other window is a page inside pgcWorkspace. }
  TfrmIbqMain = class(TForm, ILocalizable)
    mnuMain: TMainMenu;
    mnuConsole: TMenuItem;
    mnuRegisterServer: TMenuItem;
    mnuRegisterDatabase: TMenuItem;
    mnuImportRegistrations: TMenuItem;
    sepConsole1: TMenuItem;
    mnuPreferences: TMenuItem;
    sepConsole2: TMenuItem;
    mnuExit: TMenuItem;
    mnuView: TMenuItem;
    mnuRefresh: TMenuItem;
    mnuShowSystem: TMenuItem;
    mnuShowLog: TMenuItem;
    mnuServer: TMenuItem;
    mnuServerConnect: TMenuItem;
    mnuServerDisconnect: TMenuItem;
    mnuServerProperties: TMenuItem;
    mnuServerLog: TMenuItem;
    mnuServerUsers: TMenuItem;
    mnuUnregisterServer: TMenuItem;
    mnuDatabase: TMenuItem;
    mnuDbConnect: TMenuItem;
    mnuDbDisconnect: TMenuItem;
    mnuUnregisterDatabase: TMenuItem;
    sepDatabase1: TMenuItem;
    mnuMaintenance: TMenuItem;
    mnuBackup: TMenuItem;
    mnuRestore: TMenuItem;
    mnuSweep: TMenuItem;
    mnuValidate: TMenuItem;
    mnuStatistics: TMenuItem;
    mnuTransactionRecovery: TMenuItem;
    mnuConnectedUsers: TMenuItem;
    sepMaintenance1: TMenuItem;
    mnuDbUsers: TMenuItem;
    mnuExtractMetadata: TMenuItem;
    mnuObject: TMenuItem;
    mnuObjRefresh: TMenuItem;
    mnuObjProperties: TMenuItem;
    mnuObjDdlToEditor: TMenuItem;
    sepObject1: TMenuItem;
    mnuObjNew: TMenuItem;
    mnuObjAlter: TMenuItem;
    mnuObjDrop: TMenuItem;
    mnuScriptAs: TMenuItem;
    mnuObjExecute: TMenuItem;
    mnuTools: TMenuItem;
    mnuNewSqlEditor: TMenuItem;
    mnuLanguage: TMenuItem;
    mnuOptions: TMenuItem;
    mnuHelp: TMenuItem;
    mnuAbout: TMenuItem;
    popTree: TPopupMenu;
    popConnect: TMenuItem;
    popDisconnect: TMenuItem;
    popSep1: TMenuItem;
    popNew: TMenuItem;
    popAlter: TMenuItem;
    popDrop: TMenuItem;
    popSep2: TMenuItem;
    popProperties: TMenuItem;
    popDdlToEditor: TMenuItem;
    popExecute: TMenuItem;
    popSep3: TMenuItem;
    popMaintenance: TMenuItem;
    popBackup: TMenuItem;
    popRestore: TMenuItem;
    popValidate: TMenuItem;
    popSweep: TMenuItem;
    popStatistics: TMenuItem;
    popSepM1: TMenuItem;
    popRecovery: TMenuItem;
    popConnUsers: TMenuItem;
    popUsers: TMenuItem;
    popExtract: TMenuItem;
    popSep4: TMenuItem;
    popRegisterDb: TMenuItem;
    popUnregDb: TMenuItem;
    popUnregSrv: TMenuItem;
    popServerProperties: TMenuItem;
    popServerLog: TMenuItem;
    popSep5: TMenuItem;
    popRefresh: TMenuItem;

    tvObjects: TTreeView;
    splTree: TSplitter;
    pnlLog: TPanel;
    memLog: TMemo;
    splLog: TSplitter;
    pgcWorkspace: TPageControl;
    stbMain: TStatusBar;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure mnuExitClick(Sender: TObject);
    procedure mnuShowLogClick(Sender: TObject);
    procedure mnuShowSystemClick(Sender: TObject);
    procedure mnuRefreshClick(Sender: TObject);
    procedure mnuAboutClick(Sender: TObject);
    procedure mnuRegisterServerClick(Sender: TObject);
    procedure mnuUnregisterServerClick(Sender: TObject);
    procedure mnuDbConnectClick(Sender: TObject);
    procedure mnuDbDisconnectClick(Sender: TObject);
    procedure mnuRegisterDatabaseClick(Sender: TObject);
    procedure mnuUnregisterDatabaseClick(Sender: TObject);
    procedure mnuNotImplementedClick(Sender: TObject);
    procedure tvObjectsExpanding(Sender: TObject; Node: TTreeNode;
      var AllowExpansion: Boolean);
    procedure tvObjectsSelectionChanged(Sender: TObject);
    procedure tvObjectsDblClick(Sender: TObject);
    procedure mnuObjPropertiesClick(Sender: TObject);
    procedure mnuNewSqlEditorClick(Sender: TObject);
    procedure mnuExtractMetadataClick(Sender: TObject);
    procedure ScriptAsItemClick(Sender: TObject);
    procedure mnuObjExecuteClick(Sender: TObject);
    procedure mnuMaintenanceItemClick(Sender: TObject);
    procedure mnuTransactionRecoveryClick(Sender: TObject);
    procedure mnuConnectedUsersClick(Sender: TObject);
    procedure mnuImportRegistrationsClick(Sender: TObject);
    procedure mnuObjDropClick(Sender: TObject);
    procedure mnuObjNewClick(Sender: TObject);
    procedure mnuObjAlterClick(Sender: TObject);
    procedure mnuPreferencesClick(Sender: TObject);
    procedure mnuObjDdlToEditorClick(Sender: TObject);
    procedure popTreePopup(Sender: TObject);
    procedure mnuServerPropertiesClick(Sender: TObject);
    procedure mnuServerLogClick(Sender: TObject);
    procedure mnuUsersClick(Sender: TObject);
  private
    FMetaRoot: TMetaRoot;
    FShowSystemObjects: Boolean;
    procedure BuildLanguageMenu;
    procedure ApplyPreferences;
    procedure TidySeparators(AItems: TMenuItem);
    procedure BuildScriptAsMenu;
    function DatabaseOfSelection: TMetaDatabase;
    function SelectedDatabase: TMetaDatabase;
    procedure OpenSqlEditorWith(ADatabase: TMetaDatabase;
      const ACaption, AText: string);
    procedure LanguageItemClick(Sender: TObject);
    procedure RebuildTree;
    procedure PopulateNode(ATreeNode: TTreeNode; AItem: TMetaItem);
    function AddTreeNode(AParent: TTreeNode; AItem: TMetaItem): TTreeNode;
    function CanHaveChildren(AItem: TMetaItem): Boolean;
    function SelectedItem: TMetaItem;
    function SelectedServer: TMetaServer;
    function NodeCaption(AItem: TMetaItem): string;
    procedure OpenObjectPage(AItem: TMetaItem);
    procedure ObjectPageCloseRequest(Sender: TObject);
    function FindObjectPage(AItem: TMetaItem): TTabSheet;
    procedure LogLine(ASeverity: TLogSeverity; const ATimestamp: TDateTime;
      const AText: string);
    procedure ReportError(E: Exception);
    procedure UpdateStatusBar;
    procedure UpdateMenuState;
  public
    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;
  end;

var
  frmIbqMain: TfrmIbqMain;

implementation

{$R *.lfm}

const
  { Caption of the placeholder child that gives an unexpanded node its
    expander. Replaced by the real children on first expand. }
  PlaceholderCaption = '...';

{------------------------------------------------------------------------------
  TfrmIbqMain.FormCreate
  ----------------------------------------------------------------------------
  Builds the window and loads the registrations.

  Notes:
    A registration file that cannot be parsed is reported and then ignored, so
    a corrupt file leaves the user with an empty tree they can rebuild rather
    than a program that will not start.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.FormCreate(Sender: TObject);
begin
  { The preferences were read before this form existed, in the program's
    StartUpLanguage, so they are simply obeyed here. }
  FShowSystemObjects := Config.ShowSystemObjects;

  Log.OnLine := @LogLine;
  Log.Info('IBQConsole started');

  FMetaRoot := TMetaRoot.Create;
  try
    FMetaRoot.LoadRegistrations;
    Log.InfoFmt('Registrations loaded from %s',
      [FMetaRoot.Store.FileName]);
  except
    on E: Exception do
      ReportError(E);
  end;

  ApplyPreferences;
  BuildLanguageMenu;
  BuildScriptAsMenu;
  RebuildTree;
  UpdateStatusBar;
  UpdateMenuState;

  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.FormClose
  ----------------------------------------------------------------------------
  Saves the registrations before the window goes away.

  Parameters:
    CloseAction - Left untouched; a failed save must not stop the program from
                  closing, only warn.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  { The statement history is saved here rather than as each statement runs:
    writing a file on every F5 would be a measurable cost on a fast query, and
    losing the last few statements to a crash is a smaller harm than that. }
  try
    History.SaveIfModified;
  except
    on E: Exception do
      Log.Error(E.Message);
  end;

  { RestoredLeft and friends rather than Left and Width: when the window is
    maximised those report the whole screen, and restoring to them next time
    would leave a window that cannot be un-maximised back to anything sane. }
  Config.StoreWindowState(RestoredLeft, RestoredTop, RestoredWidth,
    RestoredHeight, WindowState = wsMaximized);
  Config.ShowLog := mnuShowLog.Checked;
  Config.ShowSystemObjects := FShowSystemObjects;
  try
    Config.SaveIfModified;
  except
    on E: Exception do
      Log.Error(E.Message);
  end;

  try
    FMetaRoot.SaveRegistrations;
  except
    on E: Exception do
      MessageDlg(Caption,
        LangStrFormat('msg.saveRegistrationsFailed', [E.Message],
          'The registrations could not be saved:' + LineEnding + '%s'),
        mtWarning, [mbOK], 0);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.FormDestroy
  ----------------------------------------------------------------------------
  Releases the metadata tree and stops feeding the log panel.

  Notes:
    The log outlives the form, so its event must be cleared before the form
    goes away or a late line would write into a freed memo.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.FormDestroy(Sender: TObject);
begin
  Log.OnLine := nil;
  tvObjects.Items.Clear;
  FreeAndNil(FMetaRoot);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.

  Notes:
    The English text passed as the second argument IS the English version of
    the program: there is no English.lng. A key missing from a translation
    therefore falls back to correct English rather than showing the key.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.LoadLangStr;
begin
  Caption := LangStr('frmMain.caption', 'IBQConsole');

  mnuConsole.Caption := LangStr('mnuConsole.caption', '&Console');
  mnuRegisterServer.Caption :=
    LangStr('mnuRegisterServer.caption', 'Register &Server...');
  mnuRegisterDatabase.Caption :=
    LangStr('mnuRegisterDatabase.caption', 'Register &Database...');
  mnuImportRegistrations.Caption :=
    LangStr('mnuImportRegistrations.caption', 'Import Registrations...');
  mnuPreferences.Caption := LangStr('mnuPreferences.caption', '&Preferences...');
  mnuExit.Caption := LangStr('mnuExit.caption', 'E&xit');

  mnuView.Caption := LangStr('mnuView.caption', '&View');
  mnuRefresh.Caption := LangStr('mnuRefresh.caption', '&Refresh');
  mnuShowSystem.Caption :=
    LangStr('mnuShowSystem.caption', 'Show &System Objects');
  mnuShowLog.Caption := LangStr('mnuShowLog.caption', 'Show &Log');

  mnuServer.Caption := LangStr('mnuServer.caption', '&Server');
  mnuServerConnect.Caption := LangStr('mnuServerConnect.caption', '&Connect');
  mnuServerDisconnect.Caption :=
    LangStr('mnuServerDisconnect.caption', '&Disconnect');
  mnuServerProperties.Caption :=
    LangStr('mnuServerProperties.caption', 'P&roperties...');
  mnuUnregisterServer.Caption :=
    LangStr('mnuUnregisterServer.caption', '&Unregister');

  mnuDatabase.Caption := LangStr('mnuDatabase.caption', '&Database');
  mnuDbConnect.Caption := LangStr('mnuDbConnect.caption', '&Connect');
  mnuDbDisconnect.Caption := LangStr('mnuDbDisconnect.caption', '&Disconnect');
  mnuUnregisterDatabase.Caption :=
    LangStr('mnuUnregisterDatabase.caption', '&Unregister');
  mnuMaintenance.Caption := LangStr('mnuMaintenance.caption', '&Maintenance');
  mnuBackup.Caption := LangStr('mnuBackup.caption', '&Backup...');
  mnuRestore.Caption := LangStr('mnuRestore.caption', '&Restore...');
  mnuSweep.Caption := LangStr('mnuSweep.caption', '&Sweep...');
  mnuValidate.Caption := LangStr('mnuValidate.caption', '&Validate...');
  mnuStatistics.Caption := LangStr('mnuStatistics.caption', 'S&tatistics...');
  mnuTransactionRecovery.Caption :=
    LangStr('mnuTransactionRecovery.caption', 'T&ransaction Recovery...');
  mnuConnectedUsers.Caption :=
    LangStr('mnuConnectedUsers.caption', '&Connected Users...');
  mnuServerLog.Caption := LangStr('mnuServerLog.caption', 'View &Log...');
  mnuServerUsers.Caption := LangStr('mnuUsers.caption', '&Users...');
  mnuDbUsers.Caption := LangStr('mnuUsers.caption', '&Users...');
  mnuExtractMetadata.Caption :=
    LangStr('mnuExtractMetadata.caption', 'E&xtract Metadata...');

  mnuObject.Caption := LangStr('mnuObject.caption', '&Object');
  mnuObjRefresh.Caption := LangStr('mnuObjRefresh.caption', 'Re&fresh');
  mnuObjProperties.Caption :=
    LangStr('mnuObjProperties.caption', 'P&roperties...');
  mnuScriptAs.Caption := LangStr('mnuScriptAs.caption', '&Script as');
  mnuObjExecute.Caption := LangStr('mnuObjExecute.caption', '&Execute...');
  mnuObjDrop.Caption := LangStr('mnuObjDrop.caption', '&Drop...');
  mnuObjNew.Caption := LangStr('mnuObjNew.caption', '&New...');
  mnuObjAlter.Caption := LangStr('mnuObjAlter.caption', '&Alter...');
  mnuObjDdlToEditor.Caption :=
    LangStr('mnuObjDdlToEditor.caption', 'Open DDL in SQL &Editor');

  mnuTools.Caption := LangStr('mnuTools.caption', '&Tools');
  mnuNewSqlEditor.Caption :=
    LangStr('mnuNewSqlEditor.caption', 'New &SQL Editor');
  mnuLanguage.Caption := LangStr('mnuLanguage.caption', '&Language');
  mnuOptions.Caption := LangStr('mnuOptions.caption', '&Options...');

  mnuHelp.Caption := LangStr('mnuHelp.caption', '&Help');
  mnuAbout.Caption := LangStr('mnuAbout.caption', '&About...');

  { The popup reuses the menu bar's language keys: the same command should
    read the same way wherever the user meets it. }
  popConnect.Caption := LangStr('mnuDbConnect.caption', '&Connect');
  popDisconnect.Caption := LangStr('mnuDbDisconnect.caption', '&Disconnect');
  popNew.Caption := LangStr('mnuObjNew.caption', '&New...');
  popAlter.Caption := LangStr('mnuObjAlter.caption', '&Alter...');
  popDrop.Caption := LangStr('mnuObjDrop.caption', '&Drop...');
  popProperties.Caption :=
    LangStr('mnuObjProperties.caption', 'P&roperties...');
  popDdlToEditor.Caption :=
    LangStr('mnuObjDdlToEditor.caption', 'Open DDL in SQL &Editor');
  popExecute.Caption := LangStr('mnuObjExecute.caption', '&Execute...');
  popMaintenance.Caption := LangStr('mnuMaintenance.caption', '&Maintenance');
  popBackup.Caption := LangStr('mnuBackup.caption', '&Backup...');
  popRestore.Caption := LangStr('mnuRestore.caption', '&Restore...');
  popValidate.Caption := LangStr('mnuValidate.caption', '&Validate...');
  popSweep.Caption := LangStr('mnuSweep.caption', '&Sweep...');
  popStatistics.Caption := LangStr('mnuStatistics.caption', 'S&tatistics...');
  popRecovery.Caption :=
    LangStr('mnuTransactionRecovery.caption', 'T&ransaction Recovery...');
  popConnUsers.Caption :=
    LangStr('mnuConnectedUsers.caption', '&Connected Users...');
  popUsers.Caption := LangStr('mnuUsers.caption', '&Users...');
  popExtract.Caption :=
    LangStr('mnuExtractMetadata.caption', 'E&xtract Metadata...');
  popRegisterDb.Caption :=
    LangStr('mnuRegisterDatabase.caption', 'Register &Database...');
  popUnregDb.Caption :=
    LangStr('mnuUnregisterDatabase.caption', '&Unregister');
  popUnregSrv.Caption :=
    LangStr('mnuUnregisterServer.caption', '&Unregister');
  popServerProperties.Caption :=
    LangStr('mnuServerProperties.caption', 'P&roperties...');
  popServerLog.Caption := LangStr('mnuServerLog.caption', 'View &Log...');
  popRefresh.Caption := LangStr('mnuRefresh.caption', '&Refresh');

  RebuildTree;
  UpdateStatusBar;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.BuildLanguageMenu
  ----------------------------------------------------------------------------
  Fills Tools > Language with the languages found in the lang folder.

  Notes:
    Built at run time rather than at design time, so dropping a new .lng file
    beside the executable adds a language with no rebuild - which is the whole
    point of the .lng approach.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.BuildLanguageMenu;
var
  Languages: TStringList;
  Item: TMenuItem;
  I: Integer;
begin
  mnuLanguage.Clear;

  Languages := TStringList.Create;
  try
    ListAvailableLanguages(Languages);
    for I := 0 to Languages.Count - 1 do
    begin
      Item := TMenuItem.Create(Self);
      Item.Caption := Languages[I];
      Item.RadioItem := True;
      Item.GroupIndex := 1;
      Item.Checked := SameText(Languages[I], CurrentLanguage);
      Item.OnClick := @LanguageItemClick;
      mnuLanguage.Add(Item);
    end;
  finally
    Languages.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.LanguageItemClick
  ----------------------------------------------------------------------------
  Switches the interface language.

  Parameters:
    Sender - The clicked Tools > Language item; its caption is the language
             name.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.LanguageItemClick(Sender: TObject);
begin
  if not (Sender is TMenuItem) then
    Exit;

  SetLanguage(TMenuItem(Sender).Caption);
  Log.InfoFmt('Language changed to %s', [CurrentLanguage]);
  { Remembered, so the choice survives a restart. Written at close with
    everything else rather than now: this is a preference, not a document. }
  Config.Language := CurrentLanguage;
  BuildLanguageMenu;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.NodeCaption
  ----------------------------------------------------------------------------
  Returns the text to show in the tree for one model item.

  Parameters:
    AItem - The item to name.

  Returns:
    For a folder, the translated type caption; for an object, its name. The
    model deliberately knows nothing about the language files, so the lookup
    happens here.
------------------------------------------------------------------------------}
function TfrmIbqMain.NodeCaption(AItem: TMetaItem): string;
begin
  if AItem.IsCollection then
    Result := LangStr(NodeCaptionKey(AItem.NodeType),
      DefaultNodeCaption(AItem.NodeType))
  else
    Result := AItem.DisplayName;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.CanHaveChildren
  ----------------------------------------------------------------------------
  Decides whether a node should show an expander before it has been expanded.

  Parameters:
    AItem - The model item behind the node.

  Returns:
    True for servers, folders, and connected databases.

  Notes:
    A disconnected database returns False, so the user is not invited to expand
    something that would need a connection they have not asked for yet. This is
    the whole of the lazy-loading contract as far as the tree is concerned.
------------------------------------------------------------------------------}
function TfrmIbqMain.CanHaveChildren(AItem: TMetaItem): Boolean;
begin
  if AItem = nil then
    Exit(False);

  if AItem is TMetaDatabase then
    Exit(TMetaDatabase(AItem).IsConnected);

  Result := (AItem.NodeType = mntServer) or AItem.IsCollection or
    (AItem.NodeType = mntRoot);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.AddTreeNode
  ----------------------------------------------------------------------------
  Adds one tree node for one model item.

  Parameters:
    AParent - The tree node to add under, or nil for a top-level node.
    AItem   - The model item; stored in the node's Data.

  Returns:
    The new tree node.

  Notes:
    The node points at the item. The item never points back at the node: it
    publishes changes through TMetaSubject and the tree listens. That is what
    lets the same object be shown in the tree and on a property page at once.
------------------------------------------------------------------------------}
function TfrmIbqMain.AddTreeNode(AParent: TTreeNode;
  AItem: TMetaItem): TTreeNode;
begin
  Result := tvObjects.Items.AddChildObject(AParent, NodeCaption(AItem), AItem);

  if CanHaveChildren(AItem) then
    tvObjects.Items.AddChild(Result, PlaceholderCaption);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.PopulateNode
  ----------------------------------------------------------------------------
  Fills a tree node with the children of its model item.

  Parameters:
    ATreeNode - The node to fill; its existing children are removed first.
    AItem     - The model item whose children to show.

  Notes:
    System objects are filtered here rather than in the model, so toggling the
    Show System Objects command is a redraw and not a re-read.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.PopulateNode(ATreeNode: TTreeNode; AItem: TMetaItem);
var
  I: Integer;
  Child: TMetaItem;
begin
  if ATreeNode <> nil then
    ATreeNode.DeleteChildren;

  for I := 0 to AItem.ChildCount - 1 do
  begin
    Child := AItem.Child[I];
    if Child.IsSystem and not FShowSystemObjects then
      Continue;
    AddTreeNode(ATreeNode, Child);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.RebuildTree
  ----------------------------------------------------------------------------
  Rebuilds the whole tree from the metadata root.

  Notes:
    Everything collapses, which is acceptable for a full refresh and is what
    IBConsole did. Refreshing one branch without disturbing the rest is a
    per-node operation and belongs on the Object menu.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.RebuildTree;
begin
  if FMetaRoot = nil then
    Exit;

  tvObjects.Items.BeginUpdate;
  try
    tvObjects.Items.Clear;
    FMetaRoot.EnsureChildrenLoaded;
    PopulateNode(nil, FMetaRoot);
  finally
    tvObjects.Items.EndUpdate;
  end;

  UpdateMenuState;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.tvObjectsExpanding
  ----------------------------------------------------------------------------
  Loads a node's real children the first time it is expanded.

  Parameters:
    Node           - The node being expanded.
    AllowExpansion - Set to False when the load failed, so the node does not
                     open onto an empty and unexplained list.

  Notes:
    A node is recognised as unexpanded by its single placeholder child. The
    load is where a metadata query actually happens, and where a failure is
    reported - which is why the expansion is refused rather than silently
    showing nothing.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.tvObjectsExpanding(Sender: TObject; Node: TTreeNode;
  var AllowExpansion: Boolean);
var
  Item: TMetaItem;
begin
  AllowExpansion := True;

  if (Node = nil) or (Node.Data = nil) then
    Exit;

  if (Node.Count <> 1) or (Node.Items[0].Text <> PlaceholderCaption) then
    Exit;

  Item := TMetaItem(Node.Data);

  Screen.Cursor := crHourGlass;
  tvObjects.Items.BeginUpdate;
  try
    try
      Item.EnsureChildrenLoaded;
      PopulateNode(Node, Item);
    except
      on E: Exception do
      begin
        AllowExpansion := False;
        ReportError(E);
      end;
    end;
  finally
    tvObjects.Items.EndUpdate;
    Screen.Cursor := crDefault;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.tvObjectsSelectionChanged
  ----------------------------------------------------------------------------
  Updates the menus and status bar for the newly selected node.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.tvObjectsSelectionChanged(Sender: TObject);
begin
  UpdateMenuState;
  UpdateStatusBar;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.tvObjectsDblClick
  ----------------------------------------------------------------------------
  Opens the property page for the double-clicked object.

  Notes:
    Double-clicking a folder is left to the tree, which expands it. Only an
    object opens a page.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.tvObjectsDblClick(Sender: TObject);
begin
  OpenObjectPage(SelectedItem);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuObjPropertiesClick
  ----------------------------------------------------------------------------
  Opens the property page for the selected object.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuObjPropertiesClick(Sender: TObject);
begin
  OpenObjectPage(SelectedItem);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.SelectedItem
  ----------------------------------------------------------------------------
  Returns the model item behind the selected tree node, or nil.
------------------------------------------------------------------------------}
function TfrmIbqMain.SelectedItem: TMetaItem;
begin
  if (tvObjects.Selected = nil) or (tvObjects.Selected.Data = nil) then
    Result := nil
  else
    Result := TMetaItem(tvObjects.Selected.Data);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.SelectedServer
  ----------------------------------------------------------------------------
  Returns the server node the selection belongs to, or nil.

  Notes:
    Walks up from the selection, so the Server menu applies while a database or
    an object under that server is selected - which is how IBConsole behaved
    and what a user expects.
------------------------------------------------------------------------------}
function TfrmIbqMain.SelectedServer: TMetaServer;
var
  Item: TMetaItem;
begin
  Item := SelectedItem;
  if Item = nil then
    Exit(nil);

  if Item is TMetaServer then
    Exit(TMetaServer(Item));

  Item := Item.AncestorOfType(mntServer);
  if Item is TMetaServer then
    Result := TMetaServer(Item)
  else
    Result := nil;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.UpdateMenuState
  ----------------------------------------------------------------------------
  Enables the commands that apply to the current selection.

  Notes:
    The Maintenance submenu is hidden rather than disabled for an embedded
    database: the embedded engine has no Services API at all, so those commands
    do not exist there, and showing them greyed would misrepresent that as a
    permission or state problem.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.UpdateMenuState;
var
  Item: TMetaItem;
  Database: TMetaDatabase;
  HasServer: Boolean;
begin
  Item := SelectedItem;
  Database := nil;
  if Item is TMetaDatabase then
    Database := TMetaDatabase(Item);

  mnuServerProperties.Enabled := SelectedServer <> nil;
  mnuUnregisterServer.Enabled := (Item is TMetaServer);
  mnuServerConnect.Enabled := SelectedServer <> nil;
  mnuServerDisconnect.Enabled :=
    (SelectedServer <> nil) and SelectedServer.IsConnected;

  mnuDbConnect.Enabled := (Database <> nil) and not Database.IsConnected;
  mnuDbDisconnect.Enabled := (Database <> nil) and Database.IsConnected;
  mnuUnregisterDatabase.Enabled := Database <> nil;

  HasServer := (Database = nil) or Database.Profile.HasServer;
  mnuMaintenance.Visible := HasServer;

  mnuServerLog.Enabled := SelectedServer <> nil;
  mnuServerUsers.Enabled := SelectedServer <> nil;
  mnuDbUsers.Enabled := (Database <> nil) and Database.IsConnected;

  mnuObjRefresh.Enabled := Item <> nil;
  mnuObjProperties.Enabled := (Item <> nil) and not Item.IsCollection;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuRegisterServerClick
  ----------------------------------------------------------------------------
  Registers a new server.

  Notes:
    A registration that duplicates an existing host and port is refused rather
    than merged: two entries for one server would each carry their own database
    list and quietly diverge.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuRegisterServerClick(Sender: TObject);
var
  Registration: TServerRegistration;
begin
  Registration := TServerRegistration.Create;
  try
    if not EditServerRegistration(Registration) then
    begin
      Registration.Free;
      Exit;
    end;

    if FMetaRoot.Store.FindServer(Registration.Host,
      Registration.Port) <> nil then
    begin
      MessageDlg(Caption,
        LangStrFormat('msg.serverAlreadyRegistered',
          [Registration.Host, Registration.Port],
          'A server at %s port %d is already registered.'),
        mtWarning, [mbOK], 0);
      Registration.Free;
      Exit;
    end;

    FMetaRoot.RegisterServer(Registration);
    Log.InfoFmt('Registered server %s:%d',
      [Registration.Host, Registration.Port]);
  except
    on E: Exception do
    begin
      Registration.Free;
      ReportError(E);
      Exit;
    end;
  end;

  RebuildTree;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuUnregisterServerClick
  ----------------------------------------------------------------------------
  Removes the selected server registration, after confirming.

  Notes:
    Unregistering removes only IBQConsole's record of the server. It is worth
    saying so in the prompt: the word "remove" beside a database name reads as
    something far more destructive than it is.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuUnregisterServerClick(Sender: TObject);
var
  Server: TMetaServer;
begin
  if not (SelectedItem is TMetaServer) then
    Exit;

  Server := TMetaServer(SelectedItem);

  if MessageDlg(Caption,
    LangStrFormat('msg.confirmUnregisterServer', [Server.DisplayName],
      'Remove the registration for "%s"?' + LineEnding +
      'Only IBQConsole''s record of the server is removed. Nothing on the ' +
      'server itself is changed.'),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Log.InfoFmt('Unregistered server %s', [Server.DisplayName]);
  FMetaRoot.UnregisterServer(Server);
  RebuildTree;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuRegisterDatabaseClick
  ----------------------------------------------------------------------------
  Registers a database under the selected server, or as an embedded database.

  Notes:
    The server is taken from the selection, so the command applies while a
    database or an object under that server is selected too, not only the
    server node itself. With nothing selected the only thing that can be
    registered is an embedded database, which needs no server - so that is
    what the dialog offers, rather than refusing outright.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuRegisterDatabaseClick(Sender: TObject);
var
  Server: TMetaServer;
  Profile: TConnectionProfile;
  Registration: TServerRegistration;
begin
  Server := SelectedServer;

  Profile := TConnectionProfile.Create;
  try
    if Server = nil then
    begin
      Registration := nil;
      Profile.Mode := cmEmbedded;
    end
    else
    begin
      Registration := Server.Registration;
      Profile.Host := Registration.Host;
      Profile.Port := Registration.Port;
    end;

    if not EditDatabaseRegistration(Profile, Registration) then
    begin
      Profile.Free;
      Exit;
    end;

    if Profile.Mode = cmEmbedded then
    begin
      FMetaRoot.RegisterEmbedded(Profile);
      Log.InfoFmt('Registered embedded database %s',
        [Profile.DatabasePath]);
    end
    else
    begin
      if Registration = nil then
      begin
        MessageDlg(Caption,
          LangStr('msg.noServerSelected',
            'Select a server first, or choose the embedded connection type.'),
          mtWarning, [mbOK], 0);
        Profile.Free;
        Exit;
      end;

      if Registration.IndexOfPath(Profile.DatabasePath) >= 0 then
      begin
        MessageDlg(Caption,
          LangStrFormat('msg.databaseAlreadyRegistered',
            [Profile.DatabasePath],
            'A database with the path "%s" is already registered on this ' +
            'server.'),
          mtWarning, [mbOK], 0);
        Profile.Free;
        Exit;
      end;

      Registration.AddDatabase(Profile);
      FMetaRoot.Store.MarkModified;
      Log.InfoFmt('Registered database %s', [Profile.ConnectionString]);
    end;
  except
    on E: Exception do
    begin
      Profile.Free;
      ReportError(E);
      Exit;
    end;
  end;

  RebuildTree;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuUnregisterDatabaseClick
  ----------------------------------------------------------------------------
  Removes the selected database registration, after confirming.

  Notes:
    Says plainly that nothing on the server is touched. "Remove" next to a
    database name reads as something far more destructive than it is, and a
    user who misreads it once will not trust the command again.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuUnregisterDatabaseClick(Sender: TObject);
var
  Database: TMetaDatabase;
  Server: TMetaServer;
  Index: Integer;
begin
  if not (SelectedItem is TMetaDatabase) then
    Exit;

  Database := TMetaDatabase(SelectedItem);

  if MessageDlg(Caption,
    LangStrFormat('msg.confirmUnregisterDatabase',
      [Database.DisplayName],
      'Remove the registration for "%s"?' + LineEnding +
      'Only IBQConsole''s record of the database is removed. The database ' +
      'file itself is not touched.'),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  if Database.IsConnected then
    Database.Disconnect;

  if Database.Profile.Mode = cmEmbedded then
  begin
    for Index := 0 to FMetaRoot.Store.EmbeddedCount - 1 do
    begin
      if FMetaRoot.Store.Embedded[Index] = Database.Profile then
      begin
        FMetaRoot.Store.DeleteEmbedded(Index);
        Break;
      end;
    end;
  end
  else
  begin
    Server := SelectedServer;
    if Server = nil then
      Exit;
    Index := Server.Registration.IndexOfPath(Database.Profile.DatabasePath);
    if Index >= 0 then
    begin
      Server.Registration.DeleteDatabase(Index);
      FMetaRoot.Store.MarkModified;
    end;
  end;

  Log.InfoFmt('Unregistered database %s', [Database.DisplayName]);
  FMetaRoot.Invalidate;
  RebuildTree;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuDbConnectClick
  ----------------------------------------------------------------------------
  Connects the selected database and expands its node.

  Notes:
    The password is asked for every time, held in a local, and never written
    anywhere - the default policy of SPECIFICATION.md 9.1. Stored credentials
    arrive with the master-password store; until then, prompting is the only
    behaviour, and it is the safe one.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuDbConnectClick(Sender: TObject);
var
  Database: TMetaDatabase;
  Password: string;
  Node: TTreeNode;
begin
  if not (SelectedItem is TMetaDatabase) then
    Exit;

  Database := TMetaDatabase(SelectedItem);
  if Database.IsConnected then
    Exit;

  Password := PasswordBox(
    LangStr('frmMain.caption', 'IBQConsole'),
    LangStrFormat('msg.passwordPrompt',
      [Database.Profile.UserName, Database.Profile.ConnectionString],
      'Password for %s on %s:'));

  if Password = '' then
    Exit;

  Node := tvObjects.Selected;
  Screen.Cursor := crHourGlass;
  try
    try
      Database.Connect(Password);
    except
      on E: Exception do
      begin
        ReportError(E);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
    Password := '';
  end;

  // the node can have children now, so it needs its expander back
  if Node <> nil then
  begin
    Node.DeleteChildren;
    tvObjects.Items.AddChild(Node, PlaceholderCaption);
    Node.Expand(False);
  end;

  UpdateMenuState;
  UpdateStatusBar;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuDbDisconnectClick
  ----------------------------------------------------------------------------
  Disconnects the selected database and collapses its node.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuDbDisconnectClick(Sender: TObject);
var
  Database: TMetaDatabase;
  Node: TTreeNode;
begin
  if not (SelectedItem is TMetaDatabase) then
    Exit;

  Database := TMetaDatabase(SelectedItem);
  if not Database.IsConnected then
    Exit;

  Node := tvObjects.Selected;
  Database.Disconnect;

  if Node <> nil then
  begin
    Node.Collapse(True);
    Node.DeleteChildren;
  end;

  UpdateMenuState;
  UpdateStatusBar;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuRefreshClick
  ----------------------------------------------------------------------------
  Rebuilds the whole tree.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuRefreshClick(Sender: TObject);
begin
  RebuildTree;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.DatabaseOfSelection
  ----------------------------------------------------------------------------
  Returns the database the selection belongs to, connected or not.

  Returns:
    The database node the selection sits under - the node itself when a
    database is selected - or nil when the selection is a server, the root,
    or nothing at all.

  Notes:
    Separate from SelectedDatabase because the two callers want different
    things. A command needs a database it can actually run against, so
    SelectedDatabase refuses a disconnected one. The status bar needs to
    DESCRIBE the selection, including saying that the database it is under is
    not connected, which it cannot do if it is handed nil for that case.
------------------------------------------------------------------------------}
function TfrmIbqMain.DatabaseOfSelection: TMetaDatabase;
var
  Item: TMetaItem;
begin
  Result := nil;
  Item := SelectedItem;
  if Item = nil then
    Exit;

  if Item is TMetaDatabase then
    Result := TMetaDatabase(Item)
  else
  begin
    Item := Item.AncestorOfType(mntDatabase);
    if Item is TMetaDatabase then
      Result := TMetaDatabase(Item);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.SelectedDatabase
  ----------------------------------------------------------------------------
  Returns the connected database the selection belongs to.

  Returns:
    The database node, or nil when the selection is not under a connected
    database.
------------------------------------------------------------------------------}
function TfrmIbqMain.SelectedDatabase: TMetaDatabase;
begin
  Result := DatabaseOfSelection;
  if (Result <> nil) and not Result.IsConnected then
    Result := nil;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.OpenSqlEditorWith
  ----------------------------------------------------------------------------
  Opens a SQL editor tab holding the given text.

  Parameters:
    ADatabase - The database the editor runs against.
    ACaption  - The tab's caption.
    AText     - The text to put in the editor.

  Notes:
    Generated statements land in an editor rather than on the clipboard,
    because they are meant to be edited before being run - a generated UPDATE
    in particular should never be one keystroke away from executing.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.OpenSqlEditorWith(ADatabase: TMetaDatabase;
  const ACaption, AText: string);
var
  Sheet: TTabSheet;
  Editor: TfraSqlEditor;
begin
  if ADatabase = nil then
    Exit;

  Sheet := pgcWorkspace.AddTabSheet;
  Sheet.Caption := ACaption;

  Editor := TfraSqlEditor.Create(Self);
  Editor.Parent := Sheet;
  Editor.Align := alClient;
  Editor.AttachTo(ADatabase);
  Editor.LoadLangStr;
  Editor.Editor.Text := AText;
  Editor.Editor.Modified := False;

  pgcWorkspace.ActivePage := Sheet;
  Editor.Editor.SetFocus;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.BuildScriptAsMenu
  ----------------------------------------------------------------------------
  Fills Object > Script as with one item per statement kind.

  Notes:
    Built at run time so the captions come from the language file and so the
    kinds stay in step with TScriptKind rather than with a hand-drawn menu.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.BuildScriptAsMenu;
var
  Kind: TScriptKind;
  Item: TMenuItem;
begin
  mnuScriptAs.Clear;
  for Kind := Low(TScriptKind) to High(TScriptKind) do
  begin
    Item := TMenuItem.Create(Self);
    Item.Caption := ScriptKindCaption(Kind);
    Item.Tag := Ord(Kind);
    Item.OnClick := @ScriptAsItemClick;
    mnuScriptAs.Add(Item);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.ScriptAsItemClick
  ----------------------------------------------------------------------------
  Generates a statement for the selected object and opens it in an editor.

  Parameters:
    Sender - The Script as item; its Tag is the TScriptKind ordinal.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.ScriptAsItemClick(Sender: TObject);
var
  Database: TMetaDatabase;
  Item: TMetaItem;
  Kind: TScriptKind;
  Sql: string;
begin
  if not (Sender is TMenuItem) then
    Exit;

  Item := SelectedItem;
  Database := SelectedDatabase;
  if (Item = nil) or (Database = nil) or Item.IsCollection then
  begin
    MessageDlg(Caption,
      LangStr('msg.scriptNeedsObject',
        'Select an object in a connected database first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Kind := TScriptKind(TMenuItem(Sender).Tag);

  Screen.Cursor := crHourGlass;
  try
    try
      Sql := Database.GenerateScript(Kind, Item.NodeType,
        Item.Ident.AsString);
    except
      on E: Exception do
      begin
        ReportError(E);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  if Trim(Sql) = '' then
  begin
    MessageDlg(Caption,
      LangStrFormat('msg.scriptNotApplicable',
        [ScriptKindCaption(Kind), Item.DisplayName],
        '%s cannot be generated for "%s".'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  OpenSqlEditorWith(Database,
    ScriptKindCaption(Kind) + ' - ' + Item.DisplayName, Sql);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuUsersClick
  ----------------------------------------------------------------------------
  Opens the user manager, through whichever route the selection offers.

  Notes:
    A connected database gives the SQL route, which sees every user manager
    plugin. A server node with nothing connected under it gives the Services
    API route, which sees only the first plugin - so a connected database is
    preferred whenever there is one, and the dialog says which route it took.

    Users belong to the SERVER either way. Opening this from a database is not
    a claim that the accounts are the database's; it is only where the
    statement runs.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuUsersClick(Sender: TObject);
var
  Database: TMetaDatabase;
  Server: TMetaServer;
  Password: string;
begin
  Database := SelectedDatabase;

  if (Database <> nil) and Database.IsConnected then
  begin
    try
      UserManagerDialog(Database);
    except
      on E: Exception do
        ReportError(E);
    end;
    Exit;
  end;

  Server := SelectedServer;
  if Server = nil then
  begin
    MessageDlg(Caption,
      LangStr('msg.usersNeedServer',
        'Select a server, or a connected database, in the tree first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Password := PasswordBox(
    LangStr('frmUserManager.caption', 'Users'),
    LangStrFormat('msg.passwordPrompt',
      [Server.Registration.UserName, Server.Registration.TreeCaption],
      'Password for %s on %s:'));
  if Password = '' then
    Exit;

  try
    try
      ServerUserManagerDialog(Server.Registration, Password);
    except
      on E: Exception do
        ReportError(E);
    end;
  finally
    Password := '';
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuMaintenanceItemClick
  ----------------------------------------------------------------------------
  Opens the maintenance dialog for the selected database.

  Parameters:
    Sender - The menu item; its Tag is the TMaintenanceCommand ordinal.

  Notes:
    The database need not be connected. A restore over a database and a full
    validation both REQUIRE that it is not, so refusing to open the dialog for
    a disconnected database would refuse exactly the case that matters.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuMaintenanceItemClick(Sender: TObject);
var
  Database: TMetaDatabase;
begin
  if not (Sender is TMenuItem) then
    Exit;

  { DatabaseOfSelection, not SelectedDatabase: these commands run through
    the Services API and do not need an attachment. Insisting on one
    refused the two cases that matter most - a restore over a database and
    a full validation both REQUIRE that nothing is connected to it. }
  Database := DatabaseOfSelection;
  if Database = nil then
  begin
    MessageDlg(Caption,
      LangStr('msg.maintenanceNeedsDatabase',
        'Select a database in the tree first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  try
    MaintenanceDialog(Database,
      TMaintenanceCommand(TMenuItem(Sender).Tag));
  except
    on E: Exception do
      ReportError(E);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuTransactionRecoveryClick
  ----------------------------------------------------------------------------
  Opens the transaction recovery dialog for the selected database.

  Parameters:
    Sender - The Transaction Recovery menu item.

  Notes:
    Not routed through mnuMaintenanceItemClick, because recovery is not one
    of the streaming maintenance commands: it lists what is in limbo, waits
    for the administrator to decide each transaction, and only then acts.

    The database need not be connected. One with limbo transactions is often
    one nobody can work in, which is the case that matters.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuTransactionRecoveryClick(Sender: TObject);
var
  Database: TMetaDatabase;
begin
  { Through the Services API, so no attachment is needed - and a database
    with limbo transactions is often one nobody can work in. }
  Database := DatabaseOfSelection;
  if Database = nil then
  begin
    MessageDlg(Caption,
      LangStr('msg.maintenanceNeedsDatabase',
        'Select a database in the tree first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  try
    TransactionRecoveryDialog(Database);
  except
    on E: Exception do
      ReportError(E);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuConnectedUsersClick
  ----------------------------------------------------------------------------
  Shows who is connected to the selected database.

  Parameters:
    Sender - The Connected Users menu item.

  Notes:
    The only Maintenance entry that REQUIRES a connected database, because
    MON$ATTACHMENTS is read through an attachment to the database itself
    rather than through the Services API. Refusing early says so once,
    instead of opening a dialog that can only report the same thing.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuConnectedUsersClick(Sender: TObject);
var
  Database: TMetaDatabase;
begin
  Database := SelectedDatabase;
  if Database = nil then
  begin
    MessageDlg(Caption,
      LangStr('msg.maintenanceNeedsDatabase',
        'Select a database in the tree first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  try
    ConnectedUsersDialog(Database);
  except
    on E: Exception do
      ReportError(E);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuImportRegistrationsClick
  ----------------------------------------------------------------------------
  Offers to import the registrations FlameRobin and IBConsole already hold.

  Parameters:
    Sender - The Import Registrations menu item.

  Notes:
    Reloads the tree only when something was actually imported. The importer
    writes the registration file itself, so the model is re-read from it
    rather than being patched in place - there is one description of what is
    registered, and it is that file.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuImportRegistrationsClick(Sender: TObject);
var
  Imported: Integer;
begin
  try
    Imported := ImportRegistrationsDialog(FMetaRoot.Store);
  except
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;

  if Imported > 0 then
  begin
    FMetaRoot.LoadRegistrations;
    RebuildTree;
    Log.InfoFmt('Imported %d registration(s)', [Imported]);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuObjDropClick
  ----------------------------------------------------------------------------
  Drops the selected object, after showing the statement that will do it.

  Parameters:
    Sender - The Drop menu item.

  Notes:
    Refuses the kinds that have no DROP of their own - a folder, a column, a
    system table - rather than generating something Firebird would reject.
    The system tables are the case that matters: dropping one would break the
    database, and Firebird's refusal is not something to find out by trying.

    The tree is re-read only when something actually ran, so cancelling costs
    nothing.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuObjDropClick(Sender: TObject);
var
  Item: TMetaItem;
  Database: TMetaDatabase;
  Statement: string;
begin
  Item := SelectedItem;
  Database := SelectedDatabase;

  if (Item = nil) or (Database = nil) or not Database.IsConnected then
  begin
    MessageDlg(Caption,
      LangStr('msg.dropNeedsObject',
        'Select an object in a connected database first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  if not CanDrop(Item.NodeType) then
  begin
    MessageDlg(Caption,
      LangStr('msg.cannotDrop',
        'That is not something this program will drop. Folders, columns and '
        + 'the system objects are not yours to remove.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Statement := DropStatement(Item.NodeType, Item.Ident);
  if Statement = '' then
  begin
    Exit;
  end;

  try
    if DdlPreviewDialog(Database,
      LangStr('ddl.dropCaption', 'Drop'),
      LangStrFormat('ddl.dropWhat', [Item.DisplayName],
        'Drop %s from the database.'),
      LangStr('ddl.dropWarning',
        'This cannot be undone, and anything depending on it will stop '
        + 'working. Firebird refuses the drop outright when something else '
        + 'still needs it.'),
      Statement) then
    begin
      RebuildTree;
    end;
  except
    on E: Exception do
      ReportError(E);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuObjNewClick
  ----------------------------------------------------------------------------
  Creates an object of the kind the selection names.

  Parameters:
    Sender - The New menu item.

  Notes:
    The kind comes from whatever is selected, and a FOLDER counts: the
    natural place to ask for a new table is the Tables folder, not an
    existing table. Kinds whose body is a program - views, procedures,
    triggers, functions - are not offered here and are written in the SQL
    editor instead, which is what Open DDL in SQL Editor is for.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuObjNewClick(Sender: TObject);
var
  Item: TMetaItem;
  Database: TMetaDatabase;
begin
  Item := SelectedItem;
  Database := SelectedDatabase;

  if (Item = nil) or (Database = nil) or not Database.IsConnected then
  begin
    MessageDlg(Caption,
      LangStr('msg.newNeedsSelection',
        'Select a folder or an object in a connected database first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  if not CanCreateHere(Item.NodeType) then
  begin
    MessageDlg(Caption,
      LangStr('msg.cannotCreateHere',
        'This dialog creates tables, domains, indexes, sequences, '
        + 'exceptions and roles. A view, procedure, trigger or function '
        + 'is written in the SQL editor: pick one and use Open DDL in '
        + 'SQL Editor for a starting point.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  try
    if NewObjectDialog(Database, Item.NodeType) then
    begin
      RebuildTree;
    end;
  except
    on E: Exception do
      ReportError(E);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuObjDdlToEditorClick
  ----------------------------------------------------------------------------
  Opens the selected object's DDL in a SQL editor tab.

  Parameters:
    Sender - The Open DDL in SQL Editor menu item.

  Notes:
    This is how a procedure, trigger, view or function is altered: its
    source is a program, and the place to edit a program is the editor,
    with the highlighter, the splitter and a transaction the user
    controls. The tab opens unexecuted - nothing here is one keystroke
    from running.

    It works for every kind, not only the ones with a body. For a table
    the DDL is the CREATE statement, which is a starting point for an
    ALTER rather than something to re-run, and the tab is captioned DDL
    rather than Alter so that it does not promise otherwise.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuObjDdlToEditorClick(Sender: TObject);
var
  Item: TMetaItem;
  Database: TMetaDatabase;
  Ddl: string;
begin
  Item := SelectedItem;
  Database := SelectedDatabase;

  if (Item = nil) or (Database = nil) or not Database.IsConnected then
  begin
    MessageDlg(Caption,
      LangStr('msg.ddlNeedsObject',
        'Select an object in a connected database first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    try
      Ddl := Database.FetchObjectDdl(Item.NodeType, Item.Ident.AsString);
    except
      on E: Exception do
      begin
        ReportError(E);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  if Trim(Ddl) = '' then
  begin
    MessageDlg(Caption,
      LangStr('msg.noDdlForObject',
        'The server returned no DDL for that object.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  OpenSqlEditorWith(Database,
    LangStrFormat('ddl.editorTab', [Item.DisplayName], 'DDL - %s'), Ddl);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuObjAlterClick
  ----------------------------------------------------------------------------
  Alters the selected object.

  Parameters:
    Sender - The Alter menu item.

  Notes:
    Only the kinds Firebird has a usable ALTER for: a domain, a sequence,
    an exception and an index's active flag. A table is altered column by
    column and a view or procedure is rewritten whole, so both are sent to
    the SQL editor with their DDL rather than to a dialog that could only
    do part of the job.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuObjAlterClick(Sender: TObject);
var
  Item: TMetaItem;
  Database: TMetaDatabase;
begin
  Item := SelectedItem;
  Database := SelectedDatabase;

  if (Item = nil) or (Database = nil) or not Database.IsConnected then
  begin
    MessageDlg(Caption,
      LangStr('msg.alterNeedsObject',
        'Select an object in a connected database first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  if not CanAlterHere(Item.NodeType) then
  begin
    MessageDlg(Caption,
      LangStr('msg.cannotAlterHere',
        'This dialog alters domains, sequences, exceptions and an index'#39's '
        + 'active flag. For anything else use Open DDL in SQL Editor and '
        + 'edit the statement there.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  try
    if AlterObjectDialog(Database, Item.NodeType,
      Item.Ident.AsString) then
    begin
      RebuildTree;
    end;
  except
    on E: Exception do
      ReportError(E);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.ApplyPreferences
  ----------------------------------------------------------------------------
  Puts the window and the panels where the preferences say.

  Notes:
    A stored position is used only when it is at least partly on a screen
    that exists now. A window remembered on a second monitor that has since
    been unplugged would otherwise open where nobody can reach it, which is
    a support call rather than a preference.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.ApplyPreferences;
var
  OnScreen: Boolean;
begin
  mnuShowLog.Checked := Config.ShowLog;
  pnlLog.Visible := Config.ShowLog;
  splLog.Visible := Config.ShowLog;
  mnuShowSystem.Checked := Config.ShowSystemObjects;

  if not Config.HasWindowState then
  begin
    Exit;
  end;

  OnScreen := (Config.WindowLeft < Screen.DesktopLeft +
      Screen.DesktopWidth) and
    (Config.WindowLeft + Config.WindowWidth > Screen.DesktopLeft) and
    (Config.WindowTop < Screen.DesktopTop + Screen.DesktopHeight) and
    (Config.WindowTop + Config.WindowHeight > Screen.DesktopTop);

  if OnScreen then
  begin
    SetBounds(Config.WindowLeft, Config.WindowTop, Config.WindowWidth,
      Config.WindowHeight);
  end;

  if Config.WindowMaximized then
  begin
    WindowState := wsMaximized;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuPreferencesClick
  ----------------------------------------------------------------------------
  Opens the preferences and obeys whatever changed.

  Parameters:
    Sender - The Preferences or the Options menu item; both come here,
             because IBConsole put the same dialog in two menus and users
             look for it in both.

  Notes:
    The tree is rebuilt only when the system-objects setting actually
    changed. Rebuilding it regardless would collapse every expanded node
    for a font change, and re-reading a large schema is not free.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuPreferencesClick(Sender: TObject);
var
  SystemBefore: Boolean;
begin
  SystemBefore := Config.ShowSystemObjects;

  try
    if not PreferencesDialog then
    begin
      Exit;
    end;
  except
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;

  mnuShowLog.Checked := Config.ShowLog;
  pnlLog.Visible := Config.ShowLog;
  splLog.Visible := Config.ShowLog;

  if Config.ShowSystemObjects <> SystemBefore then
  begin
    FShowSystemObjects := Config.ShowSystemObjects;
    mnuShowSystem.Checked := FShowSystemObjects;
    RebuildTree;
  end;

  BuildLanguageMenu;
  UpdateMenuState;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.TidySeparators
  ----------------------------------------------------------------------------
  Hides the separators that would have nothing to separate.

  Parameters:
    AItems - The menu whose items have just been shown or hidden.

  Notes:
    A context menu that hides what does not apply ends up with separators at
    the top, at the bottom, or two in a row - which looks like the menu is
    broken rather than tailored. A separator earns its place only when there
    is a visible item both above and below it.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.TidySeparators(AItems: TMenuItem);
var
  I: Integer;
  SeenVisible: Boolean;
  LastSeparator: Integer;
begin
  SeenVisible := False;
  LastSeparator := -1;

  for I := 0 to AItems.Count - 1 do
  begin
    if AItems[I].Caption = '-' then
    begin
      { Visible only when something visible came before it. }
      AItems[I].Visible := SeenVisible;
      if AItems[I].Visible then
      begin
        LastSeparator := I;
        SeenVisible := False;
      end;
    end
    else if AItems[I].Visible then
    begin
      SeenVisible := True;
    end;
  end;

  { Nothing visible after the last separator, so it is a trailing one. }
  if (LastSeparator >= 0) and not SeenVisible then
  begin
    AItems[LastSeparator].Visible := False;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.popTreePopup
  ----------------------------------------------------------------------------
  Shows the commands that apply to the node under the cursor.

  Parameters:
    Sender - The tree's popup menu.

  Notes:
    Every item here runs the SAME handler as its counterpart on the menu
    bar. The popup is a second way to reach the commands, not a second
    implementation of them: anything else would drift the moment one of the
    two was changed.

    The tree has RightClickSelect set, so the node under the cursor is
    already the selected one by the time this runs, and every handler acts
    on the selection exactly as it does from the menu bar. Without that a
    right-click would offer commands for one node and run them on another.

    Items are hidden rather than disabled. A context menu is meant to be
    read at a glance, and a list of greyed-out commands makes the two that
    do apply harder to find, not easier.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.popTreePopup(Sender: TObject);
var
  Item: TMetaItem;
  Database: TMetaDatabase;
  Connected: Boolean;
  IsObject: Boolean;
  OnServer: Boolean;
begin
  Item := SelectedItem;
  Database := DatabaseOfSelection;
  Connected := (Database <> nil) and Database.IsConnected;
  OnServer := SelectedServer <> nil;

  { An object is something with a name of its own: not a folder, not the
    database, not the server, not the root. }
  IsObject := (Item <> nil) and not Item.IsCollection and
    not (Item is TMetaServer) and not (Item is TMetaDatabase) and
    not (Item is TMetaRoot);

  popConnect.Visible := (Item is TMetaDatabase) and
    not TMetaDatabase(Item).IsConnected;
  popDisconnect.Visible := (Item is TMetaDatabase) and
    TMetaDatabase(Item).IsConnected;

  popNew.Visible := Connected and (Item <> nil) and
    CanCreateHere(Item.NodeType);
  popAlter.Visible := Connected and IsObject and CanAlterHere(Item.NodeType);
  popDrop.Visible := Connected and IsObject and CanDrop(Item.NodeType);

  popProperties.Visible := Connected and IsObject;
  popDdlToEditor.Visible := Connected and IsObject;
  popExecute.Visible := Connected and IsObject and
    (Item.NodeType in [mntProcedure, mntFunctionSQL, mntUDF]);

  { Maintenance runs through the Services API, which an embedded database
    has no access to, and does not need the database to be connected. }
  popMaintenance.Visible := (Database <> nil) and
    (Database.Profile <> nil) and Database.Profile.HasServer;
  popRecovery.Visible := popMaintenance.Visible;
  popConnUsers.Visible := Connected;
  popUsers.Visible := popMaintenance.Visible;
  popExtract.Visible := Connected;
  if popMaintenance.Visible then
  begin
    TidySeparators(popMaintenance);
  end;

  popRegisterDb.Visible := OnServer;
  popServerProperties.Visible := Item is TMetaServer;
  popServerLog.Visible := OnServer;
  popUnregDb.Visible := Item is TMetaDatabase;
  popUnregSrv.Visible := Item is TMetaServer;

  popRefresh.Visible := True;

  TidySeparators(popTree.Items);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuServerPropertiesClick
  ----------------------------------------------------------------------------
  Shows the selected server's properties.

  Parameters:
    Sender - The menu item, from either the Server menu or the tree popup.

  Notes:
    The password is asked for here rather than inside the dialog, the same way
    Server > Users... and Server > View Log... ask, so that a server command
    behaves the same whichever one is chosen.

    Dismissing the prompt still opens the dialog, with an empty password. That
    is deliberate: the registration half - host, port, user, which client
    library gets loaded - is worth seeing on its own, and is exactly what a
    user wants when the server is not answering and they are trying to work
    out why.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuServerPropertiesClick(Sender: TObject);
var
  Server: TMetaServer;
  Password: string;
begin
  Server := SelectedServer;
  if Server = nil then
  begin
    MessageDlg(Caption,
      LangStr('msg.serverPropsNeedServer',
        'Select a server in the tree first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Password := PasswordBox(
    LangStr('frmServerProperties.caption', 'Server Properties'),
    LangStrFormat('msg.passwordPrompt',
      [Server.Registration.UserName, Server.Registration.TreeCaption],
      'Password for %s on %s:'));

  try
    try
      ServerPropertiesDialog(Server.Registration, Password);
    except
      on E: Exception do
        ReportError(E);
    end;
  finally
    Password := '';
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuServerLogClick
  ----------------------------------------------------------------------------
  Fetches and shows the selected server's log.

  Notes:
    A server command, not a database one: firebird.log belongs to the server
    and is most wanted precisely when no database on it will open.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuServerLogClick(Sender: TObject);
var
  Server: TMetaServer;
begin
  Server := SelectedServer;
  if Server = nil then
  begin
    MessageDlg(Caption,
      LangStr('msg.serverLogNeedsServer',
        'Select a server in the tree first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  try
    ServerMaintenanceDialog(Server.Registration, Server.Registration.UserName,
      mcServerLog);
  except
    on E: Exception do
      ReportError(E);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuObjExecuteClick
  ----------------------------------------------------------------------------
  Opens the execute dialog for the selected procedure or function.

  Notes:
    Only routines can be executed, so anything else is refused with a message
    rather than by a greyed-out menu item: the tree selection changes far more
    often than the menu is opened, and a message that says why is more use than
    an item that silently does nothing.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuObjExecuteClick(Sender: TObject);
var
  Database: TMetaDatabase;
  Item: TMetaItem;
begin
  Item := SelectedItem;
  Database := SelectedDatabase;

  if (Item = nil) or (Database = nil) or Item.IsCollection or
    not (Item.NodeType in [mntProcedure, mntFunctionSQL, mntUDF]) then
  begin
    MessageDlg(Caption,
      LangStr('msg.executeNeedsRoutine',
        'Select a procedure or a function in a connected database first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  try
    ExecuteRoutineDialog(Database, Item.NodeType, Item.Ident.AsString);
  except
    on E: Exception do
      ReportError(E);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuExtractMetadataClick
  ----------------------------------------------------------------------------
  Extracts the whole database's DDL into a new SQL editor tab.

  Notes:
    Opened in an EDITOR rather than a read-only viewer, which is what IBConsole
    did with View Metadata. The extracted script is most useful when it can be
    edited and run: that is how a schema gets copied to another database, and
    the SET TERM statements it contains are exactly what the editor's splitter
    was built to handle.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuExtractMetadataClick(Sender: TObject);
var
  Item: TMetaItem;
  Database: TMetaDatabase;
  Sheet: TTabSheet;
  Editor: TfraSqlEditor;
  Ddl: string;
begin
  Item := SelectedItem;
  Database := nil;

  if Item is TMetaDatabase then
    Database := TMetaDatabase(Item)
  else if Item <> nil then
  begin
    Item := Item.AncestorOfType(mntDatabase);
    if Item is TMetaDatabase then
      Database := TMetaDatabase(Item);
  end;

  if (Database = nil) or not Database.IsConnected then
  begin
    MessageDlg(Caption,
      LangStr('msg.extractNeedsConnection',
        'Select a connected database first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    try
      Ddl := Database.FetchDatabaseDdl;
    except
      on E: Exception do
      begin
        ReportError(E);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  Sheet := pgcWorkspace.AddTabSheet;
  Sheet.Caption := LangStrFormat('extract.tabCaption', [Database.DisplayName],
    'Metadata - %s');

  Editor := TfraSqlEditor.Create(Self);
  Editor.Parent := Sheet;
  Editor.Align := alClient;
  Editor.AttachTo(Database);
  Editor.LoadLangStr;
  Editor.Editor.Text := Ddl;
  Editor.Editor.Modified := False;

  pgcWorkspace.ActivePage := Sheet;
  Log.InfoFmt('Extracted metadata for %s (%d characters)',
    [Database.DisplayName, Length(Ddl)]);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuNewSqlEditorClick
  ----------------------------------------------------------------------------
  Opens a SQL editor on the selected database.

  Notes:
    The database is taken from the selection by walking up, so the command
    works while any object under it is selected. An editor needs a CONNECTED
    database, because its whole purpose is to run statements; offering one on a
    disconnected registration would only produce an editor that cannot execute.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuNewSqlEditorClick(Sender: TObject);
var
  Item: TMetaItem;
  Database: TMetaDatabase;
  Sheet: TTabSheet;
  Editor: TfraSqlEditor;
begin
  Item := SelectedItem;
  Database := nil;

  if Item is TMetaDatabase then
    Database := TMetaDatabase(Item)
  else if Item <> nil then
  begin
    Item := Item.AncestorOfType(mntDatabase);
    if Item is TMetaDatabase then
      Database := TMetaDatabase(Item);
  end;

  if (Database = nil) or not Database.IsConnected then
  begin
    MessageDlg(Caption,
      LangStr('msg.editorNeedsConnection',
        'Select a connected database first.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  Sheet := pgcWorkspace.AddTabSheet;
  Sheet.Caption := LangStrFormat('sql.tabCaption', [Database.DisplayName],
    'SQL - %s');

  Editor := TfraSqlEditor.Create(Self);
  Editor.Parent := Sheet;
  Editor.Align := alClient;
  Editor.AttachTo(Database);
  Editor.LoadLangStr;

  pgcWorkspace.ActivePage := Sheet;
  Editor.Editor.SetFocus;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.FindObjectPage
  ----------------------------------------------------------------------------
  Finds the workspace tab already showing an object.

  Parameters:
    AItem - The object to look for.

  Returns:
    The tab, or nil when the object is not open.
------------------------------------------------------------------------------}
function TfrmIbqMain.FindObjectPage(AItem: TMetaItem): TTabSheet;
var
  I, J: Integer;
  Sheet: TTabSheet;
  Page: TfraObjectPage;
begin
  for I := 0 to pgcWorkspace.PageCount - 1 do
  begin
    Sheet := pgcWorkspace.Pages[I];
    for J := 0 to Sheet.ControlCount - 1 do
    begin
      if Sheet.Controls[J] is TfraObjectPage then
      begin
        Page := TfraObjectPage(Sheet.Controls[J]);
        if Page.Item = AItem then
          Exit(Sheet);
      end;
    end;
  end;
  Result := nil;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.OpenObjectPage
  ----------------------------------------------------------------------------
  Opens, or brings forward, the property page for one object.

  Parameters:
    AItem - The object to show. Folders and unconnected databases are ignored.

  Notes:
    An object already open is brought forward rather than opened twice. Two
    tabs for one table would each observe it and each rebuild on every change,
    and the user would have no way to tell them apart.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.OpenObjectPage(AItem: TMetaItem);
var
  Sheet: TTabSheet;
  Page: TfraObjectPage;
begin
  if (AItem = nil) or AItem.IsCollection then
    Exit;
  if AItem.NodeType in [mntRoot, mntServer] then
    Exit;

  Sheet := FindObjectPage(AItem);
  if Sheet <> nil then
  begin
    pgcWorkspace.ActivePage := Sheet;
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    Sheet := pgcWorkspace.AddTabSheet;
    Sheet.Caption := AItem.DisplayName;

    Page := TfraObjectPage.Create(Self);
    Page.Parent := Sheet;
    Page.Align := alClient;
    Page.OnCloseRequest := @ObjectPageCloseRequest;
    try
      Page.ShowItem(AItem);
    except
      on E: Exception do
      begin
        Sheet.Free;
        ReportError(E);
        Exit;
      end;
    end;

    pgcWorkspace.ActivePage := Sheet;
  finally
    Screen.Cursor := crDefault;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.ObjectPageCloseRequest
  ----------------------------------------------------------------------------
  Closes a property page whose object has gone away.

  Parameters:
    Sender - The page asking to be closed.

  Notes:
    The tab is released rather than freed outright: this runs from inside the
    object's destructor, and freeing a control while it is in the middle of
    handling a notification is how you get a use-after-free that only shows up
    on someone else's machine.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.ObjectPageCloseRequest(Sender: TObject);
var
  Page: TfraObjectPage;
begin
  if not (Sender is TfraObjectPage) then
    Exit;

  Page := TfraObjectPage(Sender);
  if Page.Parent is TTabSheet then
    Application.ReleaseComponent(Page.Parent);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.LogLine
  ----------------------------------------------------------------------------
  Appends one line to the log panel.

  Parameters:
    ASeverity  - Kind of line; reserved for colouring once the plain memo is
                 replaced by a coloured control.
    ATimestamp - When the line was produced.
    AText      - The text.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.LogLine(ASeverity: TLogSeverity;
  const ATimestamp: TDateTime; const AText: string);
var
  Prefix: string;
begin
  if memLog = nil then
    Exit;

  case ASeverity of
    lsStatement: Prefix := 'SQL ';
    lsWarning:   Prefix := 'WARN ';
    lsError:     Prefix := 'ERROR ';
  else
    Prefix := '';
  end;

  memLog.Lines.Add(FormatDateTime('hh:nn:ss', ATimestamp) + '  ' +
    Prefix + AText);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.ReportError
  ----------------------------------------------------------------------------
  Shows an error to the user and records it in the log.

  Parameters:
    E - The exception to report.

  Notes:
    A database error is shown through FullText, which includes every line of
    the Firebird status vector. The first line alone is usually the least
    informative one, and tools that show only it are the reason Firebird has a
    reputation for unhelpful errors.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.ReportError(E: Exception);
var
  ErrorText: string;
begin
  if E is EIbqDatabaseError then
    ErrorText := EIbqDatabaseError(E).FullText
  else
    ErrorText := E.Message;

  Log.Error(ErrorText);
  MessageDlg(LangStr('frmMain.caption', 'IBQConsole'), ErrorText,
    mtError, [mbOK], 0);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.UpdateStatusBar
  ----------------------------------------------------------------------------
  Refreshes the status bar from the current selection.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.UpdateStatusBar;
var
  Database: TMetaDatabase;
begin
  { The database the selection is UNDER, not only a selected database node.
    Selecting a table inside a connected database used to report 'Not
    connected', which is the opposite of the truth and was on screen for
    almost every click, since the thing a user selects is usually an object
    rather than the database itself. }
  Database := DatabaseOfSelection;

  if Database <> nil then
  begin
    if Database.IsConnected then
    begin
      stbMain.Panels[0].Text := Database.Profile.ConnectionString;
      stbMain.Panels[1].Text := Database.Profile.UserName;
      stbMain.Panels[2].Text := Database.Version.DisplayText;
    end
    else
    begin
      stbMain.Panels[0].Text := Database.Profile.ConnectionString;
      stbMain.Panels[1].Text :=
        LangStr('status.notConnected', 'Not connected');
      stbMain.Panels[2].Text := '';
    end;
  end
  else
  begin
    stbMain.Panels[0].Text := LangStr('status.noConnection', 'Not connected');
    stbMain.Panels[1].Text := '';
    stbMain.Panels[2].Text := '';
  end;

  stbMain.Panels[3].Text := CurrentLanguage;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuExitClick
  ----------------------------------------------------------------------------
  Closes the application.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuExitClick(Sender: TObject);
begin
  Close;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuShowLogClick
  ----------------------------------------------------------------------------
  Shows or hides the log panel at the bottom of the window.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuShowLogClick(Sender: TObject);
begin
  pnlLog.Visible := mnuShowLog.Checked;
  splLog.Visible := mnuShowLog.Checked;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuShowSystemClick
  ----------------------------------------------------------------------------
  Turns display of system objects on or off.

  Notes:
    Each connected database is told as well, because whether the system folders
    exist at all is decided when its folder list is built, not when the tree is
    drawn.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuShowSystemClick(Sender: TObject);
var
  I, J: Integer;
  Child: TMetaItem;
begin
  FShowSystemObjects := mnuShowSystem.Checked;

  for I := 0 to FMetaRoot.ChildCount - 1 do
  begin
    Child := FMetaRoot.Child[I];
    if Child is TMetaDatabase then
      TMetaDatabase(Child).ShowSystemObjects := FShowSystemObjects
    else
    begin
      for J := 0 to Child.ChildCount - 1 do
      begin
        if Child.Child[J] is TMetaDatabase then
          TMetaDatabase(Child.Child[J]).ShowSystemObjects :=
            FShowSystemObjects;
      end;
    end;
  end;

  RebuildTree;
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuAboutClick
  ----------------------------------------------------------------------------
  Shows the about box.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuAboutClick(Sender: TObject);
begin
  MessageDlg(LangStr('about.title', 'About IBQConsole'),
    LangStr('about.text',
      'IBQConsole' + LineEnding +
      'A Firebird database editor.' + LineEnding + LineEnding +
      'Milestone M1 - registrations and object tree.'),
    mtInformation, [mbOK], 0);
end;

{------------------------------------------------------------------------------
  TfrmIbqMain.mnuNotImplementedClick
  ----------------------------------------------------------------------------
  Placeholder handler for the commands that arrive in later milestones.

  Parameters:
    Sender - The menu item that was clicked; its caption names the command.
------------------------------------------------------------------------------}
procedure TfrmIbqMain.mnuNotImplementedClick(Sender: TObject);
var
  CommandName: string;
begin
  if Sender is TMenuItem then
    CommandName := StringReplace(TMenuItem(Sender).Caption, '&', '',
      [rfReplaceAll])
  else
    CommandName := '';

  MessageDlg(LangStr('frmMain.caption', 'IBQConsole'),
    LangStrFormat('msg.notImplemented', [CommandName],
      '%s is not available yet in this build.'),
    mtInformation, [mbOK], 0);
end;

end.
