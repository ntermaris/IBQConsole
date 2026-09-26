{==============================================================================
  Unit:        ConnectionProfile
  Purpose:     Everything needed to open one database: where it is, how to
               reach it, and who to connect as. One profile per registered
               database.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils

  A profile holds no connection and no IBX type. It is pure configuration, so
  it can be read from and written to the registration file without dragging the
  database layer into the config code.
==============================================================================}
unit ConnectionProfile;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { How the database is reached. }
  TConnectionMode = (
    cmRemote,     // over TCP: host/port/path
    cmLocal,      // local server, no network layer
    cmEmbedded    // embedded engine, no server at all
  );

  { What we are allowed to do with the password. }
  TPasswordStorage = (
    psDoNotStore,     // prompt every time - the default
    psSessionOnly,    // keep in memory until the program exits
    psEncrypted       // keep in the config file under the master password
  );

const
  { The port Firebird listens on unless told otherwise. }
  DefaultFirebirdPort = 3050;
  { The character set used when a registration does not name one. }
  DefaultCharacterSet = 'UTF8';

type
  { TConnectionProfile
    One registered database.

    Owns nothing but its own strings. The password field is transient: whether
    it survives a restart is decided by PasswordStorage, and writing it to disk
    is the registration store's decision, never this class's. }
  TConnectionProfile = class(TObject)
  private
    FDisplayName: string;
    FMode: TConnectionMode;
    FHost: string;
    FPort: Integer;
    FDatabasePath: string;
    FUserName: string;
    FPassword: string;
    FRole: string;
    FCharacterSet: string;
    FClientLibrary: string;
    FPageBuffers: Integer;
    FPasswordStorage: TPasswordStorage;
    FUseCaseSensitiveRole: Boolean;
  public
    constructor Create;

    { Copies every field of ASource into this profile. }
    procedure Assign(ASource: TConnectionProfile);
    { Returns an independent copy. The caller owns it. }
    function Clone: TConnectionProfile;

    { The connection string to hand to the database layer.

      Returns:
        'host/port:/path/to/db.fdb' for a remote connection, and the bare path
        for a local or embedded one. Firebird accepts the host/port form on
        every supported version, and unlike 'host:path' it copes with a Windows
        drive letter in the path without ambiguity. }
    function ConnectionString: string;

    { True when this profile talks to a server, and therefore when the Services
      API - backup, restore, validate, statistics, user management - is
      available at all. False for embedded. }
    function HasServer: Boolean;

    { The text shown in the tree for this database. }
    function TreeCaption: string;

    { Returns True when the profile is complete enough to attempt a connection,
      putting the reason in AReason when it is not.

      Parameters:
        AReason - Receives a human-readable explanation when the result is
                  False; cleared when the result is True. }
    function Validate(out AReason: string): Boolean;

    { The name shown in the tree and in dialogs. }
    property DisplayName: string read FDisplayName write FDisplayName;
    { How the database is reached. }
    property Mode: TConnectionMode read FMode write FMode;
    { Server host name or address; ignored unless Mode is cmRemote. }
    property Host: string read FHost write FHost;
    { Server port; ignored unless Mode is cmRemote. }
    property Port: Integer read FPort write FPort;
    { Path to the database file as the SERVER sees it, or an alias. }
    property DatabasePath: string read FDatabasePath write FDatabasePath;
    { User to connect as. }
    property UserName: string read FUserName write FUserName;
    { Password. Held in memory only; see PasswordStorage. }
    property Password: string read FPassword write FPassword;
    { Role to assume, or empty for none. }
    property Role: string read FRole write FRole;
    { Whether the role name is quoted, and so case sensitive. }
    property UseCaseSensitiveRole: Boolean read FUseCaseSensitiveRole
      write FUseCaseSensitiveRole;
    { Connection character set. }
    property CharacterSet: string read FCharacterSet write FCharacterSet;
    { Path to fbclient - EMBEDDED DATABASES ONLY.

      For a database reached through a server the library belongs to the server
      registration, because it is loaded once for the connection to that server
      and two databases on one server cannot sensibly use different clients.
      Ask TMetaDatabase.EffectiveClientLibrary rather than reading this field
      directly; it returns the server's value for server-backed databases and
      this one for embedded databases, which have no server. }
    property ClientLibrary: string read FClientLibrary write FClientLibrary;
    { Page buffer override, or 0 for the database's own setting. }
    property PageBuffers: Integer read FPageBuffers write FPageBuffers;
    { What may be done with the password. }
    property PasswordStorage: TPasswordStorage read FPasswordStorage
      write FPasswordStorage;
  end;

{ Returns the config-file token for AMode, e.g. 'embedded'. }
function ConnectionModeToStr(AMode: TConnectionMode): string;
{ Returns the mode for a config-file token, defaulting to cmRemote. }
function StrToConnectionMode(const AText: string): TConnectionMode;
{ Returns the config-file token for AStorage. }
function PasswordStorageToStr(AStorage: TPasswordStorage): string;
{ Returns the storage policy for a config-file token, defaulting to the safe
  psDoNotStore. }
function StrToPasswordStorage(const AText: string): TPasswordStorage;

implementation

{------------------------------------------------------------------------------
  ConnectionModeToStr
  ----------------------------------------------------------------------------
  Returns the config-file token for a connection mode.
------------------------------------------------------------------------------}
function ConnectionModeToStr(AMode: TConnectionMode): string;
begin
  case AMode of
    cmLocal:    Result := 'local';
    cmEmbedded: Result := 'embedded';
  else
    Result := 'remote';
  end;
end;

{------------------------------------------------------------------------------
  StrToConnectionMode
  ----------------------------------------------------------------------------
  Returns the connection mode for a config-file token.

  Parameters:
    AText - The token read from the registration file.

  Returns:
    The matching mode; cmRemote for anything unrecognised, because a wrong
    guess towards remote fails with a clear connection error rather than
    silently opening a file with the embedded engine.
------------------------------------------------------------------------------}
function StrToConnectionMode(const AText: string): TConnectionMode;
begin
  if SameText(AText, 'local') then
    Result := cmLocal
  else if SameText(AText, 'embedded') then
    Result := cmEmbedded
  else
    Result := cmRemote;
end;

{------------------------------------------------------------------------------
  PasswordStorageToStr
  ----------------------------------------------------------------------------
  Returns the config-file token for a password storage policy.
------------------------------------------------------------------------------}
function PasswordStorageToStr(AStorage: TPasswordStorage): string;
begin
  case AStorage of
    psSessionOnly: Result := 'session';
    psEncrypted:   Result := 'encrypted';
  else
    Result := 'none';
  end;
end;

{------------------------------------------------------------------------------
  StrToPasswordStorage
  ----------------------------------------------------------------------------
  Returns the password storage policy for a config-file token.

  Parameters:
    AText - The token read from the registration file.

  Returns:
    The matching policy; psDoNotStore for anything unrecognised. Failing
    towards not storing a password is the only safe direction.
------------------------------------------------------------------------------}
function StrToPasswordStorage(const AText: string): TPasswordStorage;
begin
  if SameText(AText, 'session') then
    Result := psSessionOnly
  else if SameText(AText, 'encrypted') then
    Result := psEncrypted
  else
    Result := psDoNotStore;
end;

{------------------------------------------------------------------------------
  TConnectionProfile.Create
  ----------------------------------------------------------------------------
  Creates a profile with the usual defaults: remote, port 3050, UTF8, password
  not stored.
------------------------------------------------------------------------------}
constructor TConnectionProfile.Create;
begin
  inherited Create;
  FMode := cmRemote;
  FHost := 'localhost';
  FPort := DefaultFirebirdPort;
  FCharacterSet := DefaultCharacterSet;
  FPasswordStorage := psDoNotStore;
  FPageBuffers := 0;
  FUseCaseSensitiveRole := False;
end;

{------------------------------------------------------------------------------
  TConnectionProfile.Assign
  ----------------------------------------------------------------------------
  Copies every field of another profile into this one.

  Parameters:
    ASource - The profile to copy. Nil is ignored.
------------------------------------------------------------------------------}
procedure TConnectionProfile.Assign(ASource: TConnectionProfile);
begin
  if ASource = nil then
    Exit;

  FDisplayName := ASource.FDisplayName;
  FMode := ASource.FMode;
  FHost := ASource.FHost;
  FPort := ASource.FPort;
  FDatabasePath := ASource.FDatabasePath;
  FUserName := ASource.FUserName;
  FPassword := ASource.FPassword;
  FRole := ASource.FRole;
  FCharacterSet := ASource.FCharacterSet;
  FClientLibrary := ASource.FClientLibrary;
  FPageBuffers := ASource.FPageBuffers;
  FPasswordStorage := ASource.FPasswordStorage;
  FUseCaseSensitiveRole := ASource.FUseCaseSensitiveRole;
end;

{------------------------------------------------------------------------------
  TConnectionProfile.Clone
  ----------------------------------------------------------------------------
  Returns an independent copy of this profile.

  Returns:
    A new profile. The caller owns it.

  Notes:
    Used by the registration dialog, which edits a clone and copies it back
    only when the user presses OK - so cancelling really does cancel.
------------------------------------------------------------------------------}
function TConnectionProfile.Clone: TConnectionProfile;
begin
  Result := TConnectionProfile.Create;
  Result.Assign(Self);
end;

{------------------------------------------------------------------------------
  TConnectionProfile.ConnectionString
  ----------------------------------------------------------------------------
  Builds the connection string for this profile.

  Returns:
    'host/port:/path' for remote, the bare path for local and embedded.

  Notes:
    The host/port form is used rather than the older 'host:path' because a
    Windows path contains a colon of its own: 'server:C:\db\x.fdb' is genuinely
    ambiguous, while 'server/3050:C:\db\x.fdb' is not.

    The port is ALWAYS written when the profile names one, including 3050.
    It used to be omitted as "the default", which is wrong twice over: the
    default is not ours to assume, it is whatever RemoteServicePort says in
    the firebird.conf belonging to the CLIENT LIBRARY this attachment loads.
    On a machine running several servers that is routinely not 3050, so
    omitting the port sent a connection the user had aimed at 3050 to a
    different server - silently, and with a plausible-looking error from the
    wrong machine. Writing four characters we could have left out is the whole
    cost of never having to think about that again, and it is the same
    argument as naming the client library instead of trusting the search path
    (SPECIFICATION.md §5.6.1).
------------------------------------------------------------------------------}
function TConnectionProfile.ConnectionString: string;
var
  HostPart: string;
begin
  if FMode <> cmRemote then
    Exit(FDatabasePath);

  HostPart := FHost;
  if HostPart = '' then
    HostPart := 'localhost';

  if FPort > 0 then
    HostPart := HostPart + '/' + IntToStr(FPort);

  Result := HostPart + ':' + FDatabasePath;
end;

{------------------------------------------------------------------------------
  TConnectionProfile.HasServer
  ----------------------------------------------------------------------------
  Returns True when a Firebird server is involved.

  Notes:
    Everything under Database - Maintenance depends on this. The embedded
    engine has no Services API at all, so backup, restore, validate,
    statistics, sweep, shutdown, user management and the server log are not
    merely disabled for an embedded database, they do not exist, and the UI
    hides them.
------------------------------------------------------------------------------}
function TConnectionProfile.HasServer: Boolean;
begin
  Result := FMode <> cmEmbedded;
end;

{------------------------------------------------------------------------------
  TConnectionProfile.TreeCaption
  ----------------------------------------------------------------------------
  Returns the text shown in the object tree for this database.

  Returns:
    The display name when one was given, otherwise the file name without its
    directory, otherwise a placeholder.
------------------------------------------------------------------------------}
function TConnectionProfile.TreeCaption: string;
begin
  if FDisplayName <> '' then
    Exit(FDisplayName);

  if FDatabasePath <> '' then
    Exit(ExtractFileName(FDatabasePath));

  Result := '(unnamed database)';
end;

{------------------------------------------------------------------------------
  TConnectionProfile.Validate
  ----------------------------------------------------------------------------
  Checks whether a connection can be attempted.

  Parameters:
    AReason - Receives the explanation when the profile is incomplete.

  Returns:
    True when the profile is usable.

  Notes:
    Deliberately does not check that the file exists: for a remote connection
    the path is meaningful on the server, not here, and testing it locally
    would reject every correct remote registration.
------------------------------------------------------------------------------}
function TConnectionProfile.Validate(out AReason: string): Boolean;
begin
  AReason := '';

  if Trim(FDatabasePath) = '' then
  begin
    AReason := 'No database file or alias has been given.';
    Exit(False);
  end;

  if FMode = cmRemote then
  begin
    if Trim(FHost) = '' then
    begin
      AReason := 'A remote connection needs a server host name.';
      Exit(False);
    end;
    if (FPort <= 0) or (FPort > 65535) then
    begin
      AReason := 'The port must be between 1 and 65535.';
      Exit(False);
    end;
  end;

  if (FMode = cmEmbedded) and not FileExists(FDatabasePath) then
  begin
    AReason := Format('The database file "%s" was not found. An embedded ' +
      'database is opened directly, so the path must be valid on this ' +
      'machine.', [FDatabasePath]);
    Exit(False);
  end;

  if (FMode <> cmEmbedded) and (Trim(FUserName) = '') then
  begin
    AReason := 'No user name has been given.';
    Exit(False);
  end;

  Result := True;
end;

end.
