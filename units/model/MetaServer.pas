{==============================================================================
  Unit:        MetaServer
  Purpose:     A registered Firebird server in the object tree. Its children
               are the databases registered under it.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils, MetaItem, MetaDatabase, MetaTypes, Identifier,
               ServerRegistration, ServiceConnection
==============================================================================}
unit MetaServer;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, MetaItem, MetaDatabase, MetaTypes, Identifier, ServerRegistration;

type
  { TMetaServer
    One registered server. Holds a reference to its registration, which is
    owned by the registration store, not by this node. }
  TMetaServer = class(TMetaItem)
  private
    FRegistration: TServerRegistration;
    FConnected: Boolean;
    FVersionText: string;
  protected
    procedure LoadChildren; override;
  public
    constructor CreateForRegistration(AParent: TMetaItem;
      ARegistration: TServerRegistration);

    { The text shown in the tree. }
    function DisplayName: string; override;
    { True once the Services API has been reached on this server. }
    function IsConnected: Boolean;

    { Logs in to the server's Services Manager, reads its version and marks
      the node connected.

      Parameters:
        APassword - The password for the registration's user name. Used for
                    this call only and never kept.

      Raises:
        EIbqDatabaseError - The server refused or could not be reached. }
    procedure Connect(const APassword: string);
    { Disconnects every connected database under this server, then marks the
      server itself disconnected. Safe when not connected. }
    procedure Disconnect;

    { Records that the server responded, with the version string it reported. }
    procedure MarkConnected(const AVersionText: string);
    { Records that the server is no longer reachable or was logged out of. }
    procedure MarkDisconnected;

    { The registration this node was built from; owned by the store. }
    property Registration: TServerRegistration read FRegistration;
    { The version string the server reported, or empty. }
    property VersionText: string read FVersionText;
  end;

implementation

uses
  ServiceConnection;

{------------------------------------------------------------------------------
  TMetaServer.CreateForRegistration
  ----------------------------------------------------------------------------
  Creates a server node.

  Parameters:
    AParent        - The root node.
    ARegistration  - The registration; must not be nil and is not owned here.
------------------------------------------------------------------------------}
constructor TMetaServer.CreateForRegistration(AParent: TMetaItem;
  ARegistration: TServerRegistration);
begin
  inherited Create(AParent, mntServer,
    TIdentifier.FromDatabase(ARegistration.TreeCaption));
  FRegistration := ARegistration;
  FConnected := False;
  FVersionText := '';
end;

{------------------------------------------------------------------------------
  TMetaServer.DisplayName
  ----------------------------------------------------------------------------
  Returns the text shown in the tree.

  Returns:
    The registration's caption: its display name, or host:port.
------------------------------------------------------------------------------}
function TMetaServer.DisplayName: string;
begin
  Result := FRegistration.TreeCaption;
end;

{------------------------------------------------------------------------------
  TMetaServer.IsConnected
  ----------------------------------------------------------------------------
  Returns True once the server has responded.
------------------------------------------------------------------------------}
function TMetaServer.IsConnected: Boolean;
begin
  Result := FConnected;
end;

{------------------------------------------------------------------------------
  TMetaServer.Connect
  ----------------------------------------------------------------------------
  Logs in to the Services Manager and records the version it reports.

  Parameters:
    APassword - The password for the registration's user name.

  Raises:
    EIbqDatabaseError - The server refused or could not be reached; the
                        message carries the full status vector.

  Notes:
    The service attachment is closed again as soon as the version is read.
    "Connected" here means the credentials were accepted and the server
    answered, not that an attachment is held: an idle service attachment ties
    up the Services Manager, which is also how a running maintenance task is
    cancelled, and the password is never kept to reopen one later. Every
    server command therefore still asks for the password itself, as
    SPECIFICATION.md 9.1 requires.
------------------------------------------------------------------------------}
procedure TMetaServer.Connect(const APassword: string);
var
  Service: TServiceConnection;
  Info: TServerInfo;
begin
  if FConnected then
    Exit;

  Service := TServiceConnection.Create(FRegistration);
  try
    Service.Connect(APassword);
    Info := Service.Info;
    Service.Disconnect;
  finally
    Service.Free;
  end;

  MarkConnected(Info.VersionText);
end;

{------------------------------------------------------------------------------
  TMetaServer.Disconnect
  ----------------------------------------------------------------------------
  Disconnects the databases under this server and then the server itself.

  Notes:
    Only children that were already loaded are visited. A server whose
    databases were never listed has none connected, and loading them here
    just to find that out would be wasted work.
------------------------------------------------------------------------------}
procedure TMetaServer.Disconnect;
var
  I: Integer;
  Database: TMetaDatabase;
begin
  if ChildrenState = mlsLoaded then
  begin
    for I := 0 to ChildCount - 1 do
    begin
      if not (Child[I] is TMetaDatabase) then
        Continue;
      Database := TMetaDatabase(Child[I]);
      if Database.IsConnected then
        Database.Disconnect;
    end;
  end;

  MarkDisconnected;
end;

{------------------------------------------------------------------------------
  TMetaServer.MarkConnected
  ----------------------------------------------------------------------------
  Records that the server responded.

  Parameters:
    AVersionText - The version string the server reported.
------------------------------------------------------------------------------}
procedure TMetaServer.MarkConnected(const AVersionText: string);
begin
  FConnected := True;
  FVersionText := AVersionText;
  NotifyObservers;
end;

{------------------------------------------------------------------------------
  TMetaServer.MarkDisconnected
  ----------------------------------------------------------------------------
  Records that the server is no longer reachable.

  Notes:
    The database children are kept: they are registrations, not live objects,
    and a user who logs out of a server should still see what is registered
    under it. Each database node drops its own contents through
    TMetaDatabase.MarkDisconnected.
------------------------------------------------------------------------------}
procedure TMetaServer.MarkDisconnected;
begin
  FConnected := False;
  FVersionText := '';
  NotifyObservers;
end;

{------------------------------------------------------------------------------
  TMetaServer.LoadChildren
  ----------------------------------------------------------------------------
  Creates one database node per registration.

  Notes:
    Needs no connection: these come from the registration file, which is why a
    user sees their databases the moment the program starts and only pays for a
    connection when they open one. IBConsole worked the same way and it is the
    right behaviour.
------------------------------------------------------------------------------}
procedure TMetaServer.LoadChildren;
var
  I: Integer;
begin
  for I := 0 to FRegistration.DatabaseCount - 1 do
    AddChild(TMetaDatabase.CreateForProfile(Self,
      FRegistration.Databases[I], FRegistration, False));
end;

end.
