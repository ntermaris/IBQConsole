{==============================================================================
  Unit:        MetaRoot
  Purpose:     The root of the object tree. Owns the registration store and
               turns it into server nodes and embedded database nodes.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils, MetaItem, MetaServer, MetaDatabase, MetaTypes,
               Identifier, RegistrationStore, ServerRegistration,
               ConnectionProfile
==============================================================================}
unit MetaRoot;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, MetaItem, MetaServer, MetaDatabase, MetaTypes, Identifier,
  RegistrationStore, ServerRegistration, ConnectionProfile;

type
  { TMetaRoot
    The invisible top of the tree. Owns the registration store, so the tree and
    the configuration file can never drift apart. }
  TMetaRoot = class(TMetaItem)
  private
    FStore: TRegistrationStore;
  protected
    procedure LoadChildren; override;
  public
    constructor Create; reintroduce;
    destructor Destroy; override;

    { Reads the registration file and rebuilds the tree from it. }
    procedure LoadRegistrations;
    { Writes the registration file if anything changed. }
    procedure SaveRegistrations;

    { Registers a server and adds it to the tree.

      Parameters:
        ARegistration - The registration; the store takes ownership.

      Returns:
        The new server node. }
    function RegisterServer(
      ARegistration: TServerRegistration): TMetaServer;

    { Registers an embedded database and adds it to the tree.

      Parameters:
        AProfile - The profile; the store takes ownership and forces its mode
                   to cmEmbedded.

      Returns:
        The new database node. }
    function RegisterEmbedded(AProfile: TConnectionProfile): TMetaDatabase;

    { Removes a server registration and its node.

      Parameters:
        AServer - The node to remove. Its registration is freed with it. }
    procedure UnregisterServer(AServer: TMetaServer);

    { The registration store; owned by this root. }
    property Store: TRegistrationStore read FStore;
  end;

implementation

{------------------------------------------------------------------------------
  TMetaRoot.Create
  ----------------------------------------------------------------------------
  Creates the root and its empty registration store.

  Notes:
    Does not read the file: LoadRegistrations does that, so a caller can point
    the store at a different file first, which is what the import preview and
    the tests both need.
------------------------------------------------------------------------------}
constructor TMetaRoot.Create;
begin
  inherited Create(nil, mntRoot, TIdentifier.Empty);
  FStore := TRegistrationStore.Create;
end;

{------------------------------------------------------------------------------
  TMetaRoot.Destroy
  ----------------------------------------------------------------------------
  Frees the children first, then the store.

  Notes:
    Order matters. Server and database nodes hold references into the store's
    registrations; freeing the store first would leave them dangling for the
    length of the inherited destructor.
------------------------------------------------------------------------------}
destructor TMetaRoot.Destroy;
begin
  ClearChildren;
  FreeAndNil(FStore);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TMetaRoot.LoadRegistrations
  ----------------------------------------------------------------------------
  Reads the registration file and rebuilds the tree.

  Raises:
    EIbqConfigError - The file exists but cannot be parsed.
------------------------------------------------------------------------------}
procedure TMetaRoot.LoadRegistrations;
begin
  FStore.Load;
  Invalidate;
end;

{------------------------------------------------------------------------------
  TMetaRoot.SaveRegistrations
  ----------------------------------------------------------------------------
  Writes the registration file if anything changed.

  Raises:
    EIbqConfigError - The file cannot be written.
------------------------------------------------------------------------------}
procedure TMetaRoot.SaveRegistrations;
begin
  FStore.SaveIfModified;
end;

{------------------------------------------------------------------------------
  TMetaRoot.RegisterServer
  ----------------------------------------------------------------------------
  Adds a server registration and its tree node.

  Parameters:
    ARegistration - The registration; the store takes ownership.

  Returns:
    The new server node, already attached to the tree.
------------------------------------------------------------------------------}
function TMetaRoot.RegisterServer(
  ARegistration: TServerRegistration): TMetaServer;
begin
  FStore.AddServer(ARegistration);
  Result := TMetaServer.CreateForRegistration(Self, ARegistration);
  AddChild(Result);
  NotifyObservers;
end;

{------------------------------------------------------------------------------
  TMetaRoot.RegisterEmbedded
  ----------------------------------------------------------------------------
  Adds an embedded database registration and its tree node.

  Parameters:
    AProfile - The profile; the store takes ownership.

  Returns:
    The new database node, attached directly to the root because an embedded
    database has no server above it.
------------------------------------------------------------------------------}
function TMetaRoot.RegisterEmbedded(
  AProfile: TConnectionProfile): TMetaDatabase;
begin
  FStore.AddEmbedded(AProfile);
  Result := TMetaDatabase.CreateForProfile(Self, AProfile, nil, False);
  AddChild(Result);
  NotifyObservers;
end;

{------------------------------------------------------------------------------
  TMetaRoot.UnregisterServer
  ----------------------------------------------------------------------------
  Removes a server registration and its node.

  Parameters:
    AServer - The node to remove. Nil is ignored.

  Notes:
    The node is dropped by rebuilding the children rather than by deleting one
    entry, because the store owns the registration and the tree must not be
    left holding a pointer into a freed object for even one statement.
------------------------------------------------------------------------------}
procedure TMetaRoot.UnregisterServer(AServer: TMetaServer);
var
  I: Integer;
begin
  if AServer = nil then
    Exit;

  for I := 0 to FStore.ServerCount - 1 do
  begin
    if FStore.Servers[I] = AServer.Registration then
    begin
      FStore.DeleteServer(I);
      Break;
    end;
  end;

  Invalidate;
end;

{------------------------------------------------------------------------------
  TMetaRoot.LoadChildren
  ----------------------------------------------------------------------------
  Builds a node per registered server and per registered embedded database.

  Notes:
    Embedded databases hang directly off the root, beside the servers, because
    they genuinely have no server. That is also why the whole Server menu and
    every maintenance command is hidden for them - see ConnectionProfile
    HasServer.
------------------------------------------------------------------------------}
procedure TMetaRoot.LoadChildren;
var
  I: Integer;
begin
  for I := 0 to FStore.ServerCount - 1 do
    AddChild(TMetaServer.CreateForRegistration(Self, FStore.Servers[I]));

  for I := 0 to FStore.EmbeddedCount - 1 do
    AddChild(TMetaDatabase.CreateForProfile(Self, FStore.Embedded[I], nil, False));
end;

end.
