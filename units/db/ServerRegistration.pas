{==============================================================================
  Unit:        ServerRegistration
  Purpose:     One registered Firebird server and the databases registered
               under it.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, contnrs, ConnectionProfile

  Mirrors IBConsole's TibcServerNode without its Win32 tree handles and without
  a live TIBServerProperties hanging off it: this is configuration only, and
  the connection lives in units/db/DatabaseContext.
==============================================================================}
unit ServerRegistration;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, ConnectionProfile;

type
  { TServerRegistration
    A registered server and its databases. Owns the profiles it holds. }
  TServerRegistration = class(TObject)
  private
    FDisplayName: string;
    FHost: string;
    FPort: Integer;
    FUserName: string;
    FDescription: string;
    FClientLibrary: string;
    FDatabases: TFPObjectList;
    function GetDatabaseCount: Integer;
    function GetDatabase(AIndex: Integer): TConnectionProfile;
  public
    constructor Create;
    destructor Destroy; override;

    { Adds AProfile and takes ownership. Returns AProfile. }
    function AddDatabase(AProfile: TConnectionProfile): TConnectionProfile;
    { Removes and frees the profile at AIndex. }
    procedure DeleteDatabase(AIndex: Integer);
    { Returns the index of the profile whose path matches APath, or -1. }
    function IndexOfPath(const APath: string): Integer;
    { Returns the profile whose display name matches AName, or nil. }
    function FindByName(const AName: string): TConnectionProfile;

    { The text shown in the tree: the display name, or host:port. }
    function TreeCaption: string;
    { True when AHost and APort name this same server, used to avoid creating
      a duplicate registration on import. }
    function Matches(const AHost: string; APort: Integer): Boolean;

    { The name shown in the tree. }
    property DisplayName: string read FDisplayName write FDisplayName;
    { Host name or address. }
    property Host: string read FHost write FHost;
    { Port; DefaultFirebirdPort unless changed. }
    property Port: Integer read FPort write FPort;
    { Default user name for databases registered under this server. }
    property UserName: string read FUserName write FUserName;
    { Free-text note shown on the server's property page. }
    property Description: string read FDescription write FDescription;
    { Full path of the fbclient library to reach this server with, or empty to
      let the system search path decide. Set it when several Firebird versions
      are installed side by side: the first fbclient on the path is rarely the
      right one for a given server. }
    property ClientLibrary: string read FClientLibrary write FClientLibrary;

    { How many databases are registered here. }
    property DatabaseCount: Integer read GetDatabaseCount;
    { The database at AIndex. }
    property Databases[AIndex: Integer]: TConnectionProfile read GetDatabase;
  end;

implementation

{------------------------------------------------------------------------------
  TServerRegistration.Create
  ----------------------------------------------------------------------------
  Creates an empty registration for localhost on the default port.
------------------------------------------------------------------------------}
constructor TServerRegistration.Create;
begin
  inherited Create;
  FHost := 'localhost';
  FPort := DefaultFirebirdPort;
  FDatabases := TFPObjectList.Create(True);
end;

{------------------------------------------------------------------------------
  TServerRegistration.Destroy
  ----------------------------------------------------------------------------
  Frees the registered database profiles.
------------------------------------------------------------------------------}
destructor TServerRegistration.Destroy;
begin
  FreeAndNil(FDatabases);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TServerRegistration.GetDatabaseCount
  ----------------------------------------------------------------------------
  Returns how many databases are registered under this server.
------------------------------------------------------------------------------}
function TServerRegistration.GetDatabaseCount: Integer;
begin
  Result := FDatabases.Count;
end;

{------------------------------------------------------------------------------
  TServerRegistration.GetDatabase
  ----------------------------------------------------------------------------
  Returns the profile at AIndex.

  Parameters:
    AIndex - Zero-based position.

  Raises:
    EListError - AIndex is out of range.
------------------------------------------------------------------------------}
function TServerRegistration.GetDatabase(AIndex: Integer): TConnectionProfile;
begin
  Result := TConnectionProfile(FDatabases[AIndex]);
end;

{------------------------------------------------------------------------------
  TServerRegistration.AddDatabase
  ----------------------------------------------------------------------------
  Adds a database profile and takes ownership of it.

  Parameters:
    AProfile - The profile to add. Nil is ignored.

  Returns:
    AProfile, so the caller can create and add in one expression.
------------------------------------------------------------------------------}
function TServerRegistration.AddDatabase(
  AProfile: TConnectionProfile): TConnectionProfile;
begin
  Result := AProfile;
  if AProfile = nil then
    Exit;
  FDatabases.Add(AProfile);
end;

{------------------------------------------------------------------------------
  TServerRegistration.DeleteDatabase
  ----------------------------------------------------------------------------
  Removes and frees the profile at AIndex.

  Parameters:
    AIndex - Zero-based position. Out-of-range values are ignored rather than
             raising, because this is called from a UI where the list may have
             changed underneath the user.
------------------------------------------------------------------------------}
procedure TServerRegistration.DeleteDatabase(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FDatabases.Count) then
    FDatabases.Delete(AIndex);
end;

{------------------------------------------------------------------------------
  TServerRegistration.IndexOfPath
  ----------------------------------------------------------------------------
  Finds a registered database by its path.

  Parameters:
    APath - The database path or alias, compared without regard to case.

  Returns:
    The index, or -1 when there is no match.

  Notes:
    Case-insensitive because the path is a file name on the server, and the
    two systems we import from are inconsistent about case.
------------------------------------------------------------------------------}
function TServerRegistration.IndexOfPath(const APath: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FDatabases.Count - 1 do
  begin
    if SameText(Databases[I].DatabasePath, APath) then
      Exit(I);
  end;
  Result := -1;
end;

{------------------------------------------------------------------------------
  TServerRegistration.FindByName
  ----------------------------------------------------------------------------
  Finds a registered database by its display name.

  Parameters:
    AName - The display name, compared without regard to case.

  Returns:
    The profile, or nil.
------------------------------------------------------------------------------}
function TServerRegistration.FindByName(
  const AName: string): TConnectionProfile;
var
  I: Integer;
begin
  for I := 0 to FDatabases.Count - 1 do
  begin
    if SameText(Databases[I].DisplayName, AName) then
      Exit(Databases[I]);
  end;
  Result := nil;
end;

{------------------------------------------------------------------------------
  TServerRegistration.TreeCaption
  ----------------------------------------------------------------------------
  Returns the text shown in the object tree for this server.

  Returns:
    The display name, or 'host:port' when none was given.
------------------------------------------------------------------------------}
function TServerRegistration.TreeCaption: string;
begin
  if FDisplayName <> '' then
    Exit(FDisplayName);

  if FPort = DefaultFirebirdPort then
    Result := FHost
  else
    Result := FHost + ':' + IntToStr(FPort);
end;

{------------------------------------------------------------------------------
  TServerRegistration.Matches
  ----------------------------------------------------------------------------
  Returns True when AHost and APort name this same server.

  Parameters:
    AHost - Host name or address, compared without regard to case.
    APort - Port; 0 means "the default".

  Notes:
    Used by the registration importer to merge rather than duplicate.
------------------------------------------------------------------------------}
function TServerRegistration.Matches(const AHost: string;
  APort: Integer): Boolean;
var
  WantedPort: Integer;
begin
  WantedPort := APort;
  if WantedPort <= 0 then
    WantedPort := DefaultFirebirdPort;

  Result := SameText(FHost, AHost) and (FPort = WantedPort);
end;

end.
