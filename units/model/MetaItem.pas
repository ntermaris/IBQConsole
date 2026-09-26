{==============================================================================
  Unit:        MetaItem
  Purpose:     Base class of every object in the metadata tree: servers,
               databases, folders and the objects inside them. Holds identity,
               parentage, children and the lazy-load state machine.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, contnrs, MetaSubject, MetaTypes, Identifier

  Modelled on FlameRobin's metadata/metadataitem.h. The load-state machine is
  the reason the tool stays usable on a database with thousands of objects:
  expanding a database reads nothing, expanding a folder reads that folder's
  list, and selecting an object reads that object's properties. Nothing else
  is ever fetched.

  Note on the coding rules: TMetaItemList lives in this unit rather than its
  own, because a list of items and an item that owns a list of items reference
  each other. Splitting them would need a circular unit reference.
==============================================================================}
unit MetaItem;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, MetaSubject, MetaTypes, Identifier;

type
  TMetaItem = class;

  { TMetaItemList
    An owning list of metadata items. Freeing the list frees the items, which
    is what makes a tree of items collapse cleanly from the root. }
  TMetaItemList = class(TFPObjectList)
  private
    function GetItem(AIndex: Integer): TMetaItem;
  public
    constructor Create(AOwnsObjects: Boolean = True);
    { The item at AIndex, already typed. }
    property Items[AIndex: Integer]: TMetaItem read GetItem; default;
  end;

  { How far a piece of an item has been read from the database. }
  TMetaLoadState = (
    mlsNotLoaded,     // never asked for
    mlsLoading,       // a load is in progress; guards against re-entry
    mlsLoaded,        // present and current
    mlsUnavailable    // tried, and this server cannot supply it
  );

  { TMetaItem
    One node of the metadata tree.

    Ownership: an item owns its children and is owned by its parent. The root
    owns everything. Nothing else may free an item.

    Notification: an item is a TMetaSubject. Views attach as observers rather
    than being told to refresh by whoever changed the data. }
  TMetaItem = class(TMetaSubject)
  private
    FParent: TMetaItem;
    FNodeType: TMetaNodeType;
    FIdentifier: TIdentifier;
    FObjectId: Integer;
    FDescription: string;
    FChildren: TMetaItemList;
    FChildrenState: TMetaLoadState;
    FPropertiesState: TMetaLoadState;
    FDescriptionState: TMetaLoadState;
    function GetChildCount: Integer;
    function GetChild(AIndex: Integer): TMetaItem;
  protected
    { Reads this item's children from the database. The base implementation
      does nothing, so an item with no children needs no override. Descendants
      must add children with AddChild and must not touch the load state, which
      EnsureChildrenLoaded manages. }
    procedure LoadChildren; virtual;
    { Reads this item's own properties. Same contract as LoadChildren. }
    procedure LoadProperties; virtual;
    { Reads this item's RDB$DESCRIPTION. Same contract as LoadChildren. }
    procedure LoadDescription; virtual;
    { Sets the name. Protected because a rename must go through the DDL that
      performs it, never by assignment. }
    procedure SetIdentifier(const AValue: TIdentifier);
    { Sets the description field without marking the item changed; used by
      LoadDescription implementations. }
    procedure SetLoadedDescription(const AValue: string);
  public
    constructor Create(AParent: TMetaItem; ANodeType: TMetaNodeType;
      const AIdentifier: TIdentifier); virtual;
    destructor Destroy; override;

    { Reads the children if they have not been read yet. Safe to call as often
      as you like; the work happens once. }
    procedure EnsureChildrenLoaded;
    { Reads the properties if they have not been read yet. }
    procedure EnsurePropertiesLoaded;
    { Reads the description if it has not been read yet. }
    procedure EnsureDescriptionLoaded;

    { Throws away everything cached about this item and its children and tells
      observers. The next Ensure call reads afresh. This is what a Refresh
      command and a successful DDL statement both call. }
    procedure Invalidate;
    { Throws away the children only, keeping this item's own properties. }
    procedure InvalidateChildren;

    { Adds AChild and takes ownership of it. Returns AChild for chaining. }
    function AddChild(AChild: TMetaItem): TMetaItem;
    { Frees every child and marks the children not loaded. }
    procedure ClearChildren;
    { Returns the child whose name matches AName, or nil. }
    function FindChild(const AName: string): TMetaItem;
    { Returns the first child of ANodeType, or nil. Used to reach a known
      folder, for example the Tables folder of a database. }
    function FindChildOfType(ANodeType: TMetaNodeType): TMetaItem;

    { True when this item is a folder rather than an object. }
    function IsCollection: Boolean;
    { True when this item belongs to the system rather than to the user. }
    function IsSystem: Boolean;
    { The topmost ancestor. }
    function RootItem: TMetaItem;
    { The nearest ancestor of ANodeType, or nil. Used by an object to reach its
      database without every class holding a back-pointer. }
    function AncestorOfType(ANodeType: TMetaNodeType): TMetaItem;

    { The text shown in the tree. Objects show their name; folders show their
      translated type caption. }
    function DisplayName: string; virtual;
    { The statement that would create this object. Empty when the type has no
      DDL of its own. }
    function GetCreateSQL: string; virtual;
    { The statement that would drop this object. }
    function GetDropSQL: string; virtual;

    { The owning item, nil for the root. }
    property Parent: TMetaItem read FParent;
    { What kind of node this is. }
    property NodeType: TMetaNodeType read FNodeType;
    { The object's name, quoting- and schema-aware. }
    property Ident: TIdentifier read FIdentifier;
    { RDB$ object id, or -1 when the type has none. }
    property ObjectId: Integer read FObjectId write FObjectId;
    { RDB$DESCRIPTION, read on demand. }
    property Description: string read FDescription write FDescription;

    { The children, loaded or not. Use EnsureChildrenLoaded first. }
    property Children: TMetaItemList read FChildren;
    { How many children are currently held. }
    property ChildCount: Integer read GetChildCount;
    { The child at AIndex. }
    property Child[AIndex: Integer]: TMetaItem read GetChild;

    { How far the children have been read. }
    property ChildrenState: TMetaLoadState read FChildrenState;
    { How far the properties have been read. }
    property PropertiesState: TMetaLoadState read FPropertiesState;
  end;

implementation

{ ---------------------------------------------------------------------------
  TMetaItemList
  --------------------------------------------------------------------------- }

{------------------------------------------------------------------------------
  TMetaItemList.Create
  ----------------------------------------------------------------------------
  Creates the list.

  Parameters:
    AOwnsObjects - True (the default) to free the items with the list.
------------------------------------------------------------------------------}
constructor TMetaItemList.Create(AOwnsObjects: Boolean);
begin
  inherited Create(AOwnsObjects);
end;

{------------------------------------------------------------------------------
  TMetaItemList.GetItem
  ----------------------------------------------------------------------------
  Returns the item at AIndex, typed.

  Parameters:
    AIndex - Zero-based position.

  Returns:
    The item.

  Raises:
    EListError - AIndex is out of range.
------------------------------------------------------------------------------}
function TMetaItemList.GetItem(AIndex: Integer): TMetaItem;
begin
  Result := TMetaItem(inherited Items[AIndex]);
end;

{ ---------------------------------------------------------------------------
  TMetaItem
  --------------------------------------------------------------------------- }

{------------------------------------------------------------------------------
  TMetaItem.Create
  ----------------------------------------------------------------------------
  Creates an item and attaches it to its parent.

  Parameters:
    AParent     - The owning item, or nil for the root. The new item is NOT
                  added to AParent's child list here: the parent adds it with
                  AddChild when it is ready to, so a half-built item is never
                  visible in the tree.
    ANodeType   - What kind of node this is.
    AIdentifier - The object's name; empty for folders.
------------------------------------------------------------------------------}
constructor TMetaItem.Create(AParent: TMetaItem; ANodeType: TMetaNodeType;
  const AIdentifier: TIdentifier);
begin
  inherited Create;
  FParent := AParent;
  FNodeType := ANodeType;
  FIdentifier := AIdentifier;
  FObjectId := -1;
  FChildren := TMetaItemList.Create(True);
  FChildrenState := mlsNotLoaded;
  FPropertiesState := mlsNotLoaded;
  FDescriptionState := mlsNotLoaded;
end;

{------------------------------------------------------------------------------
  TMetaItem.Destroy
  ----------------------------------------------------------------------------
  Frees the children, then lets TMetaSubject tell the observers.
------------------------------------------------------------------------------}
destructor TMetaItem.Destroy;
begin
  FreeAndNil(FChildren);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TMetaItem.GetChildCount
  ----------------------------------------------------------------------------
  Returns how many children are currently held.

  Notes:
    Does not load them. A folder that has never been expanded reports 0, which
    is why the tree shows a stub expander for unloaded collections instead of
    asking this.
------------------------------------------------------------------------------}
function TMetaItem.GetChildCount: Integer;
begin
  if FChildren = nil then
    Result := 0
  else
    Result := FChildren.Count;
end;

{------------------------------------------------------------------------------
  TMetaItem.GetChild
  ----------------------------------------------------------------------------
  Returns the child at AIndex.

  Parameters:
    AIndex - Zero-based position.

  Returns:
    The child item.

  Raises:
    EListError - AIndex is out of range.
------------------------------------------------------------------------------}
function TMetaItem.GetChild(AIndex: Integer): TMetaItem;
begin
  Result := FChildren[AIndex];
end;

{------------------------------------------------------------------------------
  TMetaItem.LoadChildren
  ----------------------------------------------------------------------------
  Reads this item's children. Does nothing in the base class.
------------------------------------------------------------------------------}
procedure TMetaItem.LoadChildren;
begin
  // leaf items have nothing to load
end;

{------------------------------------------------------------------------------
  TMetaItem.LoadProperties
  ----------------------------------------------------------------------------
  Reads this item's own properties. Does nothing in the base class.
------------------------------------------------------------------------------}
procedure TMetaItem.LoadProperties;
begin
  // nothing beyond the name by default
end;

{------------------------------------------------------------------------------
  TMetaItem.LoadDescription
  ----------------------------------------------------------------------------
  Reads RDB$DESCRIPTION. Does nothing in the base class.
------------------------------------------------------------------------------}
procedure TMetaItem.LoadDescription;
begin
  // not every type has a description
end;

{------------------------------------------------------------------------------
  TMetaItem.SetIdentifier
  ----------------------------------------------------------------------------
  Replaces the name and tells observers.

  Parameters:
    AValue - The new name.

  Notes:
    Protected: a rename is a DDL operation, and the model must be updated by
    the code that ran the DDL, not by assigning to a property from the UI.
------------------------------------------------------------------------------}
procedure TMetaItem.SetIdentifier(const AValue: TIdentifier);
begin
  if FIdentifier.SameAs(AValue) then
    Exit;
  FIdentifier := AValue;
  NotifyObservers;
end;

{------------------------------------------------------------------------------
  TMetaItem.SetLoadedDescription
  ----------------------------------------------------------------------------
  Stores a description read from the database.

  Parameters:
    AValue - The text read from RDB$DESCRIPTION.

  Notes:
    Does not notify: the caller is inside EnsureDescriptionLoaded, which
    notifies once when the load finishes.
------------------------------------------------------------------------------}
procedure TMetaItem.SetLoadedDescription(const AValue: string);
begin
  FDescription := AValue;
end;

{------------------------------------------------------------------------------
  TMetaItem.EnsureChildrenLoaded
  ----------------------------------------------------------------------------
  Reads the children if they have not been read.

  Notes:
    The mlsLoading state guards against re-entry: a loader that touches the
    tree while loading would otherwise recurse. A failed load leaves the state
    at mlsNotLoaded so a retry is possible, and lets the exception through -
    swallowing it here would leave an empty folder with no explanation.
------------------------------------------------------------------------------}
procedure TMetaItem.EnsureChildrenLoaded;
begin
  if FChildrenState in [mlsLoading, mlsLoaded, mlsUnavailable] then
    Exit;

  FChildrenState := mlsLoading;
  LockSubject;
  try
    try
      LoadChildren;
      FChildrenState := mlsLoaded;
    except
      FChildrenState := mlsNotLoaded;
      raise;
    end;
  finally
    UnlockSubject;
  end;
  NotifyObservers;
end;

{------------------------------------------------------------------------------
  TMetaItem.EnsurePropertiesLoaded
  ----------------------------------------------------------------------------
  Reads this item's properties if they have not been read.
------------------------------------------------------------------------------}
procedure TMetaItem.EnsurePropertiesLoaded;
begin
  if FPropertiesState in [mlsLoading, mlsLoaded, mlsUnavailable] then
    Exit;

  FPropertiesState := mlsLoading;
  try
    LoadProperties;
    FPropertiesState := mlsLoaded;
  except
    FPropertiesState := mlsNotLoaded;
    raise;
  end;
  NotifyObservers;
end;

{------------------------------------------------------------------------------
  TMetaItem.EnsureDescriptionLoaded
  ----------------------------------------------------------------------------
  Reads RDB$DESCRIPTION if it has not been read.
------------------------------------------------------------------------------}
procedure TMetaItem.EnsureDescriptionLoaded;
begin
  if FDescriptionState in [mlsLoading, mlsLoaded, mlsUnavailable] then
    Exit;

  FDescriptionState := mlsLoading;
  try
    LoadDescription;
    FDescriptionState := mlsLoaded;
  except
    FDescriptionState := mlsNotLoaded;
    raise;
  end;
end;

{------------------------------------------------------------------------------
  TMetaItem.Invalidate
  ----------------------------------------------------------------------------
  Discards everything cached about this item and tells observers.

  Notes:
    Called after a successful DDL statement and by the Refresh command. The
    children are freed rather than reloaded here: the next expand reloads them,
    which keeps a refresh of a collapsed branch free.
------------------------------------------------------------------------------}
procedure TMetaItem.Invalidate;
begin
  ClearChildren;
  FPropertiesState := mlsNotLoaded;
  FDescriptionState := mlsNotLoaded;
  NotifyObservers;
end;

{------------------------------------------------------------------------------
  TMetaItem.InvalidateChildren
  ----------------------------------------------------------------------------
  Discards the children only, keeping this item's own properties.
------------------------------------------------------------------------------}
procedure TMetaItem.InvalidateChildren;
begin
  ClearChildren;
  NotifyObservers;
end;

{------------------------------------------------------------------------------
  TMetaItem.AddChild
  ----------------------------------------------------------------------------
  Adds a child and takes ownership of it.

  Parameters:
    AChild - The item to add. Nil is ignored.

  Returns:
    AChild, so a caller can create and add in one expression.
------------------------------------------------------------------------------}
function TMetaItem.AddChild(AChild: TMetaItem): TMetaItem;
begin
  Result := AChild;
  if AChild = nil then
    Exit;
  FChildren.Add(AChild);
end;

{------------------------------------------------------------------------------
  TMetaItem.ClearChildren
  ----------------------------------------------------------------------------
  Frees every child and marks the children not loaded.

  Notes:
    Each child's destructor tells its own observers it is going away, so an
    open property page for a dropped object closes itself.
------------------------------------------------------------------------------}
procedure TMetaItem.ClearChildren;
begin
  if FChildren <> nil then
    FChildren.Clear;
  FChildrenState := mlsNotLoaded;
end;

{------------------------------------------------------------------------------
  TMetaItem.FindChild
  ----------------------------------------------------------------------------
  Finds a child by name.

  Parameters:
    AName - The bare object name to look for, compared case-sensitively as
            Firebird itself compares names.

  Returns:
    The child, or nil when there is none. Does not load the children.
------------------------------------------------------------------------------}
function TMetaItem.FindChild(const AName: string): TMetaItem;
var
  I: Integer;
begin
  for I := 0 to ChildCount - 1 do
  begin
    if Child[I].Ident.AsString = AName then
      Exit(Child[I]);
  end;
  Result := nil;
end;

{------------------------------------------------------------------------------
  TMetaItem.FindChildOfType
  ----------------------------------------------------------------------------
  Finds the first child of a given node type.

  Parameters:
    ANodeType - The type to look for, normally a folder type.

  Returns:
    The child, or nil when there is none.
------------------------------------------------------------------------------}
function TMetaItem.FindChildOfType(ANodeType: TMetaNodeType): TMetaItem;
var
  I: Integer;
begin
  for I := 0 to ChildCount - 1 do
  begin
    if Child[I].NodeType = ANodeType then
      Exit(Child[I]);
  end;
  Result := nil;
end;

{------------------------------------------------------------------------------
  TMetaItem.IsCollection
  ----------------------------------------------------------------------------
  Returns True when this item is a folder rather than an object.
------------------------------------------------------------------------------}
function TMetaItem.IsCollection: Boolean;
begin
  Result := IsCollectionType(FNodeType);
end;

{------------------------------------------------------------------------------
  TMetaItem.IsSystem
  ----------------------------------------------------------------------------
  Returns True when this item belongs to the system rather than to the user.
------------------------------------------------------------------------------}
function TMetaItem.IsSystem: Boolean;
begin
  Result := IsSystemType(FNodeType);
end;

{------------------------------------------------------------------------------
  TMetaItem.RootItem
  ----------------------------------------------------------------------------
  Returns the topmost ancestor, which is Self when there is no parent.
------------------------------------------------------------------------------}
function TMetaItem.RootItem: TMetaItem;
begin
  Result := Self;
  while Result.FParent <> nil do
    Result := Result.FParent;
end;

{------------------------------------------------------------------------------
  TMetaItem.AncestorOfType
  ----------------------------------------------------------------------------
  Walks up the tree looking for an ancestor of a given type.

  Parameters:
    ANodeType - The type to look for, typically mntDatabase or mntServer.

  Returns:
    The ancestor, or nil when there is none. Self is not considered.
------------------------------------------------------------------------------}
function TMetaItem.AncestorOfType(ANodeType: TMetaNodeType): TMetaItem;
begin
  Result := FParent;
  while (Result <> nil) and (Result.NodeType <> ANodeType) do
    Result := Result.Parent;
end;

{------------------------------------------------------------------------------
  TMetaItem.DisplayName
  ----------------------------------------------------------------------------
  Returns the text shown in the tree.

  Returns:
    The object's name for an object; the English type caption for a folder.

  Notes:
    Folders are translated at the point of display, not here: this unit knows
    nothing about the UI or the language files, and the tree looks the caption
    up through NodeCaptionKey and DefaultNodeCaption.
------------------------------------------------------------------------------}
function TMetaItem.DisplayName: string;
begin
  if IsCollection or FIdentifier.IsEmpty then
    Result := DefaultNodeCaption(FNodeType)
  else
    Result := FIdentifier.DisplayName;
end;

{------------------------------------------------------------------------------
  TMetaItem.GetCreateSQL
  ----------------------------------------------------------------------------
  Returns the statement that would create this object.

  Returns:
    An empty string in the base class. Descendants that have DDL override it,
    or are visited by TDdlCreateVisitor.
------------------------------------------------------------------------------}
function TMetaItem.GetCreateSQL: string;
begin
  Result := '';
end;

{------------------------------------------------------------------------------
  TMetaItem.GetDropSQL
  ----------------------------------------------------------------------------
  Returns the statement that would drop this object.

  Returns:
    'DROP <type> <name>' for the types that support it, otherwise an empty
    string.
------------------------------------------------------------------------------}
function TMetaItem.GetDropSQL: string;
var
  Keyword: string;
begin
  case FNodeType of
    mntTable, mntGTT:  Keyword := 'TABLE';
    mntView:           Keyword := 'VIEW';
    mntProcedure:      Keyword := 'PROCEDURE';
    mntFunctionSQL:    Keyword := 'FUNCTION';
    mntUDF:            Keyword := 'EXTERNAL FUNCTION';
    mntPackage:        Keyword := 'PACKAGE';
    mntTriggerDML,
    mntTriggerDB,
    mntTriggerDDL:     Keyword := 'TRIGGER';
    mntGenerator:      Keyword := 'SEQUENCE';
    mntException:      Keyword := 'EXCEPTION';
    mntDomain:         Keyword := 'DOMAIN';
    mntIndex:          Keyword := 'INDEX';
    mntRole:           Keyword := 'ROLE';
    mntCollation:      Keyword := 'COLLATION';
    mntSchema:         Keyword := 'SCHEMA';
    mntPublication:    Keyword := 'PUBLICATION';
    mntBlobFilter:     Keyword := 'FILTER';
  else
    Exit('');
  end;

  Result := 'DROP ' + Keyword + ' ' + FIdentifier.QualifiedQuoted;
end;

end.
