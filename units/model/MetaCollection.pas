{==============================================================================
  Unit:        MetaCollection
  Purpose:     A folder node in the object tree: Tables, Views, Procedures and
               the rest. Holds the query that fills it and the type of the
               items it will hold.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils, MetaItem, MetaTypes, Identifier

  A collection does not know how to talk to a database. It knows WHICH query
  fills it, and asks its owner to run that query through OnLoadItems. That is
  what keeps the model free of IBX while still driving the whole tree.
==============================================================================}
unit MetaCollection;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, MetaItem, MetaTypes, Identifier;

type
  TMetaCollection = class;

  { Raised by a collection when it needs to be filled. The handler runs the
    collection's Sql and calls AddItem for each row. }
  TMetaCollectionLoadEvent = procedure(ACollection: TMetaCollection) of object;

  { TMetaCollection
    A folder node. Its children are all of one type, given by ItemType. }
  TMetaCollection = class(TMetaItem)
  private
    FItemType: TMetaNodeType;
    FSql: string;
    FOnLoadItems: TMetaCollectionLoadEvent;
    FLoadFailure: string;
  protected
    procedure LoadChildren; override;
  public
    constructor CreateCollection(AParent: TMetaItem;
      ACollectionType, AItemType: TMetaNodeType; const ASql: string);

    { Creates an item from one row of the collection's query and adds it.

      Parameters:
        ASchemaName - Column 1 of the query; empty before Firebird 6.
        AObjectName - Column 2, the object's name, padding and all.
        AObjectId   - Column 3, or -1 when the type has no id.

      Returns:
        The new item, already owned by this collection. }
    function AddItem(const ASchemaName, AObjectName: string;
      AObjectId: Integer): TMetaItem;

    { True when this folder should be shown at all. A folder whose query is
      empty belongs to a feature the connected server does not have, and the
      tree must not show it - hidden, not empty. }
    function IsAvailable: Boolean;

    { The type of the items this folder holds. }
    property ItemType: TMetaNodeType read FItemType;
    { The query that fills this folder, from the version's SQL provider. }
    property Sql: string read FSql write FSql;
    { Runs the query. Assigned by the owning database. }
    property OnLoadItems: TMetaCollectionLoadEvent read FOnLoadItems
      write FOnLoadItems;
    { Why the last load failed, or empty. Shown in place of the item list so a
      permission error does not look like an empty folder. }
    property LoadFailure: string read FLoadFailure write FLoadFailure;
  end;

implementation

{------------------------------------------------------------------------------
  TMetaCollection.CreateCollection
  ----------------------------------------------------------------------------
  Creates a folder node.

  Parameters:
    AParent          - The database or object that owns this folder.
    ACollectionType  - The folder's own node type, e.g. mntTables.
    AItemType        - The type of item it will hold, e.g. mntTable.
    ASql             - The query that fills it, from the SQL provider. An
                       empty string marks the folder unavailable.
------------------------------------------------------------------------------}
constructor TMetaCollection.CreateCollection(AParent: TMetaItem;
  ACollectionType, AItemType: TMetaNodeType; const ASql: string);
begin
  inherited Create(AParent, ACollectionType, TIdentifier.Empty);
  FItemType := AItemType;
  FSql := ASql;
  FLoadFailure := '';
end;

{------------------------------------------------------------------------------
  TMetaCollection.LoadChildren
  ----------------------------------------------------------------------------
  Fills the folder by asking its owner to run the query.

  Notes:
    A failure is recorded in LoadFailure and re-raised. The tree shows the
    recorded text under the folder, because a folder that silently comes back
    empty when the user lacks rights is actively misleading - this is what
    SEC$USERS does to a non-administrator.
------------------------------------------------------------------------------}
procedure TMetaCollection.LoadChildren;
begin
  FLoadFailure := '';

  if not IsAvailable then
    Exit;

  if not Assigned(FOnLoadItems) then
    Exit;

  try
    FOnLoadItems(Self);
  except
    on E: Exception do
    begin
      FLoadFailure := E.Message;
      raise;
    end;
  end;
end;

{------------------------------------------------------------------------------
  TMetaCollection.AddItem
  ----------------------------------------------------------------------------
  Creates and adds one item from a query row.

  Parameters:
    ASchemaName - Schema name, or empty on servers without schemas.
    AObjectName - The object's name; CHAR padding is removed by TIdentifier.
    AObjectId   - RDB$ id, or -1.

  Returns:
    The new item.

  Notes:
    Builds a plain TMetaItem. The specialised classes - TMetaTable and the
    rest - arrive with the property pages in M2, and replace this call without
    changing anything the tree does.
------------------------------------------------------------------------------}
function TMetaCollection.AddItem(const ASchemaName, AObjectName: string;
  AObjectId: Integer): TMetaItem;
var
  NewIdent: TIdentifier;
  Item: TMetaItem;
begin
  if Trim(ASchemaName) = '' then
    NewIdent := TIdentifier.FromDatabase(AObjectName)
  else
    NewIdent := TIdentifier.FromDatabaseQualified(ASchemaName, AObjectName);

  Item := TMetaItem.Create(Self, FItemType, NewIdent);
  Item.ObjectId := AObjectId;
  Result := AddChild(Item);
end;

{------------------------------------------------------------------------------
  TMetaCollection.IsAvailable
  ----------------------------------------------------------------------------
  Returns True when this folder applies to the connected server.

  Returns:
    False when the folder has no query, which is how a SQL provider reports
    that the server does not have this feature at all.
------------------------------------------------------------------------------}
function TMetaCollection.IsAvailable: Boolean;
begin
  Result := Trim(FSql) <> '';
end;

end.
