{==============================================================================
  Unit:        ServiceConnection
  Purpose:     The server-level connection: an attachment to the Firebird
               Services Manager rather than to a database.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, IB, IBXServices, ServerRegistration,
               ServerVersion, FbClientLocator, IbqError, AppLog

  WHY A SECOND KIND OF CONNECTION EXISTS
  Everything in units/db attaches to a *database*. Backup, restore, validate,
  statistics, sweep, shutdown, user management and the server log do not: they
  are asked of a *server*, over a separate attachment to its Services Manager,
  and several of them are impossible over a database attachment by definition -
  restoring a database you are connected to, or shutting one down, cannot be
  done from inside it.

  So one TServiceConnection belongs to one registered server, is opened when
  the user connects to that server, and is shared by every service the user
  then runs against it.

  EMBEDDED HAS NO SERVICES
  An embedded database has no server process to ask, so it has no service
  connection and the whole maintenance menu is hidden for it (D7). That is a
  property of Firebird, not a limitation here.

  THE CLIENT LIBRARY IS THE SERVER'S
  Which fbclient reaches this server is a property of the SERVER registration,
  never of a database under it, and the same rule holds here: the path comes
  from TServerRegistration.ClientLibrary. Attaching to a 5.0 services manager
  through a 3.0 client fails, and it fails with a message about the protocol
  version that explains nothing to the user, so this is worth getting right.
==============================================================================}
unit ServiceConnection;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, IB, IBXServices,
  ServerRegistration, ServerVersion, FbClientLocator, IbqError, AppLog;

type
  { What the Services Manager reports about the server it belongs to.
    A record: it is a snapshot, copied freely and owning nothing. }
  TServerInfo = record
    { Full version banner, e.g. 'WI-V5.0.4.1657 Firebird 5.0'. }
    VersionText: string;
    { The build the server runs, e.g. 'Firebird/Windows/AMD/Intel/x64'. }
    ImplementationText: string;
    { Version of the services protocol itself, not of the engine. }
    ServiceVersion: Integer;
    { Engine version, parsed out of VersionText. }
    Version: TServerVersion;
    { How many databases the server currently has open. }
    DatabaseCount: Integer;
    { How many attachments those databases hold between them. }
    AttachmentCount: Integer;
    { Full path of each open database. }
    DatabaseNames: array of string;
    { Where the server is installed. }
    BaseLocation: string;
    { Where its lock file lives. }
    LockFileLocation: string;
    { Where its message file lives. }
    MessageFileLocation: string;
    { The security database holding its users. }
    SecurityDatabase: string;

    { Returns True when nothing has been read yet. }
    function IsEmpty: Boolean;
  end;

  { TServiceConnection
    One attachment to one server's Services Manager.

    Created for a TServerRegistration, which it does NOT own: the registration
    outlives the connection and is what the user edits. }
  TServiceConnection = class(TObject)
  private
    FRegistration: TServerRegistration;
    FConnection: TIBXServicesConnection;
    FProperties: TIBXServerProperties;
    FInfo: TServerInfo;
    FInfoRead: Boolean;
    FUserName: string;
    procedure ReadServerInfo;
    function TranslateError(E: Exception; const AWhat: string): EIbqDatabaseError;
  public
    { Creates a connection for one registered server, without opening it.

      Parameters:
        ARegistration - The server to attach to. Not owned; must outlive this
                        object. }
    constructor Create(ARegistration: TServerRegistration);
    destructor Destroy; override;

    { Attaches to the server's Services Manager.

      Parameters:
        APassword - The password for the registration's user name.

      Notes:
        Does nothing when already connected. Raises EIbqDatabaseError with the
        full status vector when the server refuses. }
    procedure Connect(const APassword: string);

    { Detaches. Safe to call when not connected. }
    procedure Disconnect;

    { True while attached. }
    function IsConnected: Boolean;

    { Returns what the server reports about itself, reading it on first use.

      Notes:
        The result is cached until Disconnect, because the version and install
        locations cannot change under a live attachment. The attachment counts
        can, so callers that show them live should call Refresh first. }
    function Info: TServerInfo;

    { Discards the cached server information so the next Info re-reads it. }
    procedure Refresh;

    { The registration this connection belongs to. }
    property Registration: TServerRegistration read FRegistration;

    { The user name the attachment was made with. }
    property UserName: string read FUserName;

    { The IBX connection, for the other units in units/services to hang their
      service objects on.

      This is the one place the services layer shares an IBX type, and it does
      not leave the layer: no form ever sees this property, because no form
      uses this unit - they talk to the model, which talks to the runner. }
    property Connection: TIBXServicesConnection read FConnection;
  end;

implementation

{------------------------------------------------------------------------------
  TServerInfo.IsEmpty
  ----------------------------------------------------------------------------
  Returns True when nothing has been read yet.
------------------------------------------------------------------------------}
function TServerInfo.IsEmpty: Boolean;
begin
  Result := (VersionText = '') and (ImplementationText = '');
end;

{------------------------------------------------------------------------------
  TServiceConnection.Create
  ----------------------------------------------------------------------------
  Creates a connection for one registered server, without opening it.

  Parameters:
    ARegistration - The server to attach to. Not owned.
------------------------------------------------------------------------------}
constructor TServiceConnection.Create(ARegistration: TServerRegistration);
begin
  inherited Create;
  if ARegistration = nil then
    raise EIbqError.Create('TServiceConnection needs a server registration.');

  FRegistration := ARegistration;

  FConnection := TIBXServicesConnection.Create(nil);
  FConnection.LoginPrompt := False;

  FProperties := TIBXServerProperties.Create(nil);
  FProperties.ServicesConnection := FConnection;
end;

{------------------------------------------------------------------------------
  TServiceConnection.Destroy
  ----------------------------------------------------------------------------
  Detaches and releases the IBX objects.

  Notes:
    The service objects are freed before the connection they registered
    themselves with, so the connection is not left holding a dangling
    IIBXServicesClient.
------------------------------------------------------------------------------}
destructor TServiceConnection.Destroy;
begin
  try
    Disconnect;
  except
    on E: Exception do
      Log.Warning('Service disconnect failed: ' + E.Message);
  end;
  FreeAndNil(FProperties);
  FreeAndNil(FConnection);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TServiceConnection.Connect
  ----------------------------------------------------------------------------
  Attaches to the server's Services Manager.

  Parameters:
    APassword - The password for the registration's user name.

  Notes:
    Protocol is TCP even for localhost. The alternative, Local, attaches
    through the machine's default installation and would silently reach the
    wrong server on a machine running three of them - which is exactly the
    test rig, and exactly the mistake this program exists to avoid.
------------------------------------------------------------------------------}
procedure TServiceConnection.Connect(const APassword: string);
begin
  if IsConnected then
    Exit;

  FUserName := FRegistration.UserName;
  if FUserName = '' then
    FUserName := 'SYSDBA';

  { Pin before use, for the same reason TDatabaseContext does: unloading one
    Firebird client while another is loaded crashes the process at exit. A
    service attachment loads a client exactly as a database attachment does. }
  PinClientLibrary(FRegistration.ClientLibrary);

  FConnection.FirebirdLibraryPathName := FRegistration.ClientLibrary;
  FConnection.Protocol := TCP;
  FConnection.ServerName := FRegistration.Host;
  if FRegistration.Port > 0 then
    FConnection.PortNo := IntToStr(FRegistration.Port)
  else
    FConnection.PortNo := '';

  FConnection.Params.Clear;
  FConnection.Params.Values['user_name'] := FUserName;
  FConnection.Params.Values['password'] := APassword;

  try
    FConnection.Connected := True;
  except
    on E: Exception do
      raise TranslateError(E, 'Cannot attach to the Services Manager on ' +
        FRegistration.TreeCaption);
  end;

  FInfoRead := False;
  Log.Info('Service attachment opened: ' + FRegistration.TreeCaption +
    ' as ' + FUserName);
end;

{------------------------------------------------------------------------------
  TServiceConnection.Disconnect
  ----------------------------------------------------------------------------
  Detaches. Safe to call when not connected.
------------------------------------------------------------------------------}
procedure TServiceConnection.Disconnect;
begin
  FInfoRead := False;
  FInfo := Default(TServerInfo);
  if (FConnection <> nil) and FConnection.Connected then
  begin
    FConnection.Connected := False;
    Log.Info('Service attachment closed: ' + FRegistration.TreeCaption);
  end;
end;

{------------------------------------------------------------------------------
  TServiceConnection.IsConnected
  ----------------------------------------------------------------------------
  Returns True while attached.
------------------------------------------------------------------------------}
function TServiceConnection.IsConnected: Boolean;
begin
  Result := (FConnection <> nil) and FConnection.Connected;
end;

{------------------------------------------------------------------------------
  TServiceConnection.Info
  ----------------------------------------------------------------------------
  Returns what the server reports about itself, reading it on first use.
------------------------------------------------------------------------------}
function TServiceConnection.Info: TServerInfo;
begin
  if IsConnected and not FInfoRead then
    ReadServerInfo;
  Result := FInfo;
end;

{------------------------------------------------------------------------------
  TServiceConnection.Refresh
  ----------------------------------------------------------------------------
  Discards the cached server information so the next Info re-reads it.
------------------------------------------------------------------------------}
procedure TServiceConnection.Refresh;
begin
  FInfoRead := False;
end;

{------------------------------------------------------------------------------
  TServiceConnection.ReadServerInfo
  ----------------------------------------------------------------------------
  Reads the version, attachment counts and install locations.

  Notes:
    The engine version is taken from TIBXServicesConnection.ServerVersionNo,
    which IBX has already parsed out of the banner. Parsing 'WI-V5.0.4.1657
    Firebird 5.0' here as well would be a second implementation of the same
    fiddly job, and the two would disagree the first time a platform prefix
    changed.

    Each of the three reads is guarded separately: a server may refuse the
    config-params query to a non-privileged user while happily answering the
    version, and losing the version because of that would be absurd.
------------------------------------------------------------------------------}
procedure TServiceConnection.ReadServerInfo;
var
  I: Integer;
begin
  FInfo := Default(TServerInfo);

  try
    FInfo.VersionText := FProperties.VersionInfo.ServerVersion;
    FInfo.ImplementationText := FProperties.VersionInfo.ServerImplementation;
    FInfo.ServiceVersion := FProperties.VersionInfo.ServiceVersion;
  except
    on E: Exception do
      Log.Warning('Server version unavailable: ' + E.Message);
  end;

  FInfo.Version := UnknownServerVersion;
  FInfo.Version.RawVersion := FInfo.VersionText;
  FInfo.Version.Major := FConnection.ServerVersionNo[1];
  FInfo.Version.Minor := FConnection.ServerVersionNo[2];
  FInfo.Version.Release := FConnection.ServerVersionNo[3];
  FInfo.Version.IsFirebird := FInfo.Version.Major > 0;

  try
    FInfo.DatabaseCount := FProperties.DatabaseInfo.NoOfDatabases;
    FInfo.AttachmentCount := FProperties.DatabaseInfo.NoOfAttachments;
    SetLength(FInfo.DatabaseNames, Length(FProperties.DatabaseInfo.DbName));
    for I := 0 to High(FProperties.DatabaseInfo.DbName) do
      FInfo.DatabaseNames[I] := FProperties.DatabaseInfo.DbName[I];
  except
    on E: Exception do
      Log.Warning('Attached database list unavailable: ' + E.Message);
  end;

  try
    FInfo.BaseLocation := FProperties.ConfigParams.BaseLocation;
    FInfo.LockFileLocation := FProperties.ConfigParams.LockFileLocation;
    FInfo.MessageFileLocation := FProperties.ConfigParams.MessageFileLocation;
    FInfo.SecurityDatabase := FProperties.ConfigParams.SecurityDatabaseLocation;
  except
    on E: Exception do
      Log.Warning('Server configuration unavailable: ' + E.Message);
  end;

  FInfoRead := True;
end;

{------------------------------------------------------------------------------
  TServiceConnection.TranslateError
  ----------------------------------------------------------------------------
  Turns an IBX exception into an EIbqDatabaseError carrying the status vector.

  Parameters:
    E     - What IBX raised.
    AWhat - What was being attempted, used as the message's first line.

  Returns:
    The exception to raise. The caller raises it; this only builds it.
------------------------------------------------------------------------------}
function TServiceConnection.TranslateError(E: Exception;
  const AWhat: string): EIbqDatabaseError;
var
  Lines: TStringList;
  StatusLines: TStringArray;
  SqlCode, GdsCode, I: Integer;
begin
  SqlCode := 0;
  GdsCode := 0;
  StatusLines := nil;

  if E is EIBInterBaseError then
  begin
    SqlCode := EIBInterBaseError(E).SQLCode;
    GdsCode := EIBInterBaseError(E).IBErrorCode;
  end
  else if E is EIBError then
    SqlCode := EIBError(E).SQLCode;

  Lines := TStringList.Create;
  try
    Lines.Text := E.Message;
    SetLength(StatusLines, Lines.Count + 1);
    StatusLines[0] := AWhat;
    for I := 0 to Lines.Count - 1 do
      StatusLines[I + 1] := Lines[I];
  finally
    Lines.Free;
  end;

  Result := EIbqDatabaseError.Create(AWhat, SqlCode, GdsCode, StatusLines, '');
  Log.Error(Result.FullText);
end;

end.
