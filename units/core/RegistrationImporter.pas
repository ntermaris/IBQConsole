{==============================================================================
  Unit:        RegistrationImporter
  Purpose:     Finds servers and databases already registered in FlameRobin and
               in IBConsole, and copies the ones the user picks into our own
               registration store.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, laz2_DOM, laz2_XMLRead, Registry (Windows),
               RegistrationStore, ServerRegistration, ConnectionProfile,
               IbqError, AppLog

  IBConsole equivalent: none - IBConsole never imported anything.

  READ-ONLY, ALWAYS (D5)
  Nothing here opens a file or a registry key for writing. Both tools have to
  keep working afterwards, and a user who tries the import is by definition
  not yet committed to this program: breaking the tool they still rely on
  would be the worst possible first impression.

  PASSWORDS ARE NOT IMPORTED (§9.1a)
  FlameRobin stores a password in fr_databases.conf and this reader walks
  straight past it. Copying it would spread a secret into a second file the
  user has not been asked about, and would do it silently. They re-enter it
  once, per database, and that is the correct cost.

  WHY THE FORMATS ARE HARD-CODED HERE
  Both are other programs' private formats, read by inspection of their source
  rather than from a published contract:

    FlameRobin  <root><server><name|host|port>, each with <database> children
                carrying <name|path|charset|username|role|fbclient>. Verified
                against Root::save() in FlameRobin 26.8.3.

    IBConsole   HKCU\Software\Borland\InterBase\IBConsole\Servers\<server>,
                values ServerName, Protocol, UserName, Description; databases
                in the Databases subkey with DatabaseFiles, CharacterSet,
                Role, Username. Verified against zluPersistent.pas and
                frmuMain.pas in the IBConsole source. Note the Borland level
                in the path, which §9.2 of the specification omits.

  So everything is read defensively: a missing element or value is a default,
  never an exception. Another program's configuration is not ours to validate,
  and a single odd entry must not cost the user the other thirteen.
==============================================================================}
unit RegistrationImporter;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, laz2_DOM, laz2_XMLRead,
  RegistrationStore, ServerRegistration, ConnectionProfile, IbqError, AppLog;

type
  { Which program a candidate was found in. }
  TImportSource = (
    isFlameRobin,
    isIBConsole
  );

  { One thing that could be imported: a server, or a database on one.

    A record: it is a snapshot of what another program's configuration said,
    is copied freely and owns nothing. }
  TImportCandidate = record
    { Where it was found. }
    Source: TImportSource;
    { True for a server, False for a database. }
    IsServer: Boolean;
    { The server's name, and for a database the name of the server it belongs
      to - which is how the two are tied together. }
    ServerName: string;
    { The server's host, empty for a local one. }
    Host: string;
    { The server's port, 0 when the source did not say. }
    Port: Integer;
    { How to reach it. }
    Mode: TConnectionMode;
    { The database's name, empty for a server. }
    DatabaseName: string;
    { The database's path as the other program recorded it. }
    DatabasePath: string;
    { The user name recorded, if any. Never a password. }
    UserName: string;
    { The role recorded, if any. }
    Role: string;
    { The connection character set recorded, if any. }
    CharacterSet: string;
    { The client library recorded, if any. FlameRobin only. }
    ClientLibrary: string;
    { Free-text note recorded, if any. }
    Description: string;
    { True when the user has ticked it in the preview. Everything not already
      registered starts ticked. }
    Selected: Boolean;
    { Why this cannot or need not be imported, empty when it can. Set when the
      same server or database is registered here already. }
    Skip: string;

    { Returns a one-line description for the preview list. }
    function Describe: string;
  end;

  TImportCandidateArray = array of TImportCandidate;

  { TRegistrationImporter
    Reads other programs' registrations and merges the chosen ones into ours.

    Owns nothing: the store is injected and stays owned by the caller. }
  TRegistrationImporter = class(TObject)
  private
    FStore: TRegistrationStore;
    FCandidates: TImportCandidateArray;
    FFlameRobinPath: string;
    { Appends one candidate to FCandidates. }
    procedure Add(const ACandidate: TImportCandidate);
    { Returns an empty candidate with the defaults a new one starts from. }
    function EmptyCandidate(ASource: TImportSource): TImportCandidate;
    { Reads FlameRobin's fr_databases.conf, if it is there. }
    procedure ScanFlameRobin;
    { Reads IBConsole's registry branch, if it is there. }
    procedure ScanIBConsole;
    { Returns the text of ANode's first child element named AName. }
    function ChildText(ANode: TDOMNode; const AName: string;
      const ADefault: string = ''): string;
    { Fills in Skip for everything already registered here. }
    procedure MarkAlreadyRegistered;
    { Returns the server registration a candidate belongs to, creating it when
      it is not there yet. }
    function ServerFor(const ACandidate: TImportCandidate;
      var ACreated: Integer): TServerRegistration;
    { Returns AName, or AName with a numeric suffix when the server already
      holds that database name. }
    function UniqueName(AServer: TServerRegistration;
      const AName: string): string;
  public
    { Creates an importer that will merge into one store.

      Parameters:
        AStore - Where imported registrations go. Not owned; must outlive
                 this object. }
    constructor Create(AStore: TRegistrationStore);

    { Returns the full path of FlameRobin's registration file for this user,
      whether or not it exists. }
    class function FlameRobinConfigPath: string;

    { Returns everything both sources offer, already marked with what is
      registered here.

      Returns:
        The candidates, servers before their databases. An empty array when
        neither program has been used on this machine, which is a normal
        answer and not an error. }
    function Scan: TImportCandidateArray;

    { Copies the ticked candidates into the store.

      Parameters:
        ACandidates - What Scan returned, with Selected edited by the user.

      Returns:
        How many databases were added. Servers created along the way are not
        counted: they are a consequence of importing a database, not the
        point of it.

      Notes:
        Saves the store once at the end, and only when something changed. }
    function Import(const ACandidates: TImportCandidateArray): Integer;

    { Where FlameRobin's registration file is read from.

      Starts at FlameRobinConfigPath, which is where FlameRobin actually
      keeps it. Settable so that the reader can be tested against a file
      written for the purpose, instead of only against whatever happens to
      be installed on the machine running the test. }
    property FlameRobinPath: string read FFlameRobinPath
      write FFlameRobinPath;
  end;

{ Returns the name of a source, for a preview column. }
function ImportSourceName(ASource: TImportSource): string;

implementation

{$IFDEF WINDOWS}
uses
  Registry;
{$ENDIF}

const
  { Firebird's default port, used when a source names none. }
  DefaultFirebirdPort = 3050;

{$IFDEF WINDOWS}
const
  { Where IBConsole keeps its registrations. The Borland level is real and is
    missing from the specification's summary; it is in zluPersistent.pas.
    Windows only: there is no registry to read anywhere else, so the whole
    IBConsole reader is compiled out on other platforms. }
  IBConsoleServersKey = 'Software\Borland\InterBase\IBConsole\Servers';
  { The subkey of a server key holding its database aliases. }
  IBConsoleDatabasesKey = 'Databases';
{$ENDIF}

{------------------------------------------------------------------------------
  ImportSourceName
  ----------------------------------------------------------------------------
  Returns the name of a source, for a preview column.

  Parameters:
    ASource - Which program.

  Returns:
    The program's name.
------------------------------------------------------------------------------}
function ImportSourceName(ASource: TImportSource): string;
begin
  case ASource of
    isFlameRobin:
      Result := 'FlameRobin';
  else
    Result := 'IBConsole';
  end;
end;

{------------------------------------------------------------------------------
  TImportCandidate.Describe
  ----------------------------------------------------------------------------
  Returns a one-line description for the preview list.

  Returns:
    The server's name and address, or the database's name and path.
------------------------------------------------------------------------------}
function TImportCandidate.Describe: string;
begin
  if IsServer then
  begin
    if Host = '' then
    begin
      Result := Format('%s (local)', [ServerName]);
    end
    else
    begin
      Result := Format('%s (%s:%d)', [ServerName, Host, Port]);
    end;
  end
  else
  begin
    Result := Format('%s - %s', [DatabaseName, DatabasePath]);
  end;
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.Create
  ----------------------------------------------------------------------------
  Creates an importer that will merge into one store.

  Parameters:
    AStore - Where imported registrations go. Not owned.

  Raises:
    EIbqError - AStore is nil.
------------------------------------------------------------------------------}
constructor TRegistrationImporter.Create(AStore: TRegistrationStore);
begin
  inherited Create;
  if AStore = nil then
  begin
    raise EIbqError.Create('TRegistrationImporter needs a registration store.');
  end;
  FStore := AStore;      // injected, NOT owned
  FFlameRobinPath := FlameRobinConfigPath;
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.FlameRobinConfigPath
  ----------------------------------------------------------------------------
  Returns the full path of FlameRobin's registration file for this user.

  Returns:
    The path, whether or not the file is there.

  Notes:
    FlameRobin puts it in the user's local application data on Windows and in
    a dot-directory at home on Unix. GetAppConfigDir would give OUR directory,
    so the location is built from the environment instead - which is the one
    place this program is allowed to know where another program keeps things.
------------------------------------------------------------------------------}
class function TRegistrationImporter.FlameRobinConfigPath: string;
var
  Base: string;
begin
  {$IFDEF WINDOWS}
  Base := GetEnvironmentVariable('APPDATA');
  if Base = '' then
  begin
    Exit('');
  end;
  Result := IncludeTrailingPathDelimiter(Base) + 'flamerobin' + PathDelim +
    'fr_databases.conf';
  {$ELSE}
  Base := GetEnvironmentVariable('HOME');
  if Base = '' then
  begin
    Exit('');
  end;
  Result := IncludeTrailingPathDelimiter(Base) + '.flamerobin' + PathDelim +
    'fr_databases.conf';
  {$ENDIF}
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.EmptyCandidate
  ----------------------------------------------------------------------------
  Returns an empty candidate with the defaults a new one starts from.

  Parameters:
    ASource - Which program it came from.

  Returns:
    A candidate with everything cleared and Selected True.
------------------------------------------------------------------------------}
function TRegistrationImporter.EmptyCandidate(
  ASource: TImportSource): TImportCandidate;
begin
  Result.Source := ASource;
  Result.IsServer := False;
  Result.ServerName := '';
  Result.Host := '';
  Result.Port := 0;
  Result.Mode := cmRemote;
  Result.DatabaseName := '';
  Result.DatabasePath := '';
  Result.UserName := '';
  Result.Role := '';
  Result.CharacterSet := '';
  Result.ClientLibrary := '';
  Result.Description := '';
  Result.Selected := True;
  Result.Skip := '';
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.Add
  ----------------------------------------------------------------------------
  Appends one candidate to FCandidates.

  Parameters:
    ACandidate - What to append.
------------------------------------------------------------------------------}
procedure TRegistrationImporter.Add(const ACandidate: TImportCandidate);
begin
  SetLength(FCandidates, Length(FCandidates) + 1);
  FCandidates[High(FCandidates)] := ACandidate;
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.ChildText
  ----------------------------------------------------------------------------
  Returns the text of ANode's first child element named AName.

  Parameters:
    ANode    - The element to look under.
    AName    - The child element wanted.
    ADefault - What to return when there is no such child.

  Returns:
    The child's text, trimmed, or ADefault.

  Notes:
    FlameRobin writes its values as child elements rather than attributes, and
    omits ones it has nothing for. A missing child is therefore ordinary and
    returns the default rather than raising.
------------------------------------------------------------------------------}
function TRegistrationImporter.ChildText(ANode: TDOMNode;
  const AName: string; const ADefault: string): string;
var
  Child: TDOMNode;
begin
  Result := ADefault;
  if ANode = nil then
  begin
    Exit;
  end;
  Child := ANode.FirstChild;
  while Child <> nil do
  begin
    if (Child.NodeType = ELEMENT_NODE) and SameText(Child.NodeName, AName) then
    begin
      Exit(Trim(Child.TextContent));
    end;
    Child := Child.NextSibling;
  end;
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.ScanFlameRobin
  ----------------------------------------------------------------------------
  Reads FlameRobin's fr_databases.conf, if it is there.

  Notes:
    A file that will not parse is logged and skipped, not raised: the user
    asked what could be imported, and the answer "nothing from FlameRobin" is
    a better one than a parse error about a file they did not write.

    The <password> element is deliberately not read. See the unit header.
------------------------------------------------------------------------------}
procedure TRegistrationImporter.ScanFlameRobin;
var
  Path: string;
  Doc: TXMLDocument;
  ServerNode: TDOMNode;
  DbNode: TDOMNode;
  Candidate: TImportCandidate;
  ServerName: string;
  Host: string;
  Port: Integer;
begin
  Path := FFlameRobinPath;
  if (Path = '') or not FileExists(Path) then
  begin
    Exit;
  end;

  Doc := nil;
  try
    try
      ReadXMLFile(Doc, Path);
    except
      on E: Exception do
      begin
        Log.Warning(Format('FlameRobin registrations at %s could not be read: %s',
          [Path, E.Message]));
        Exit;
      end;
    end;

    if (Doc = nil) or (Doc.DocumentElement = nil) then
    begin
      Exit;
    end;

    ServerNode := Doc.DocumentElement.FirstChild;
    while ServerNode <> nil do
    begin
      if (ServerNode.NodeType = ELEMENT_NODE) and
         SameText(ServerNode.NodeName, 'server') then
      begin
        ServerName := ChildText(ServerNode, 'name');
        Host := ChildText(ServerNode, 'host');
        Port := StrToIntDef(ChildText(ServerNode, 'port'), 0);
        if Port = 0 then
        begin
          Port := DefaultFirebirdPort;
        end;
        if ServerName = '' then
        begin
          if Host = '' then
          begin
            ServerName := 'Local';
          end
          else
          begin
            ServerName := Host;
          end;
        end;

        Candidate := EmptyCandidate(isFlameRobin);
        Candidate.IsServer := True;
        Candidate.ServerName := ServerName;
        Candidate.Host := Host;
        Candidate.Port := Port;
        if Host = '' then
        begin
          Candidate.Mode := cmLocal;
        end
        else
        begin
          Candidate.Mode := cmRemote;
        end;
        Add(Candidate);

        DbNode := ServerNode.FirstChild;
        while DbNode <> nil do
        begin
          if (DbNode.NodeType = ELEMENT_NODE) and
             SameText(DbNode.NodeName, 'database') then
          begin
            Candidate := EmptyCandidate(isFlameRobin);
            Candidate.IsServer := False;
            Candidate.ServerName := ServerName;
            Candidate.Host := Host;
            Candidate.Port := Port;
            if Host = '' then
            begin
              Candidate.Mode := cmLocal;
            end
            else
            begin
              Candidate.Mode := cmRemote;
            end;
            Candidate.DatabasePath := ChildText(DbNode, 'path');
            Candidate.DatabaseName := ChildText(DbNode, 'name');
            if Candidate.DatabaseName = '' then
            begin
              Candidate.DatabaseName :=
                ExtractFileName(Candidate.DatabasePath);
            end;
            Candidate.CharacterSet := ChildText(DbNode, 'charset');
            Candidate.UserName := ChildText(DbNode, 'username');
            Candidate.Role := ChildText(DbNode, 'role');
            Candidate.ClientLibrary := ChildText(DbNode, 'fbclient');
            if Candidate.DatabasePath <> '' then
            begin
              Add(Candidate);
            end;
          end;
          DbNode := DbNode.NextSibling;
        end;
      end;
      ServerNode := ServerNode.NextSibling;
    end;
  finally
    Doc.Free;
  end;
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.ScanIBConsole
  ----------------------------------------------------------------------------
  Reads IBConsole's registry branch, if it is there.

  Notes:
    Windows only, and the one place in the program that touches the registry.
    On any other platform IBConsole cannot have been run, so there is nothing
    to look for and the routine does nothing.

    Opened read-only. IBConsole is still a working program on machines that
    have it, and this must not disturb it.
------------------------------------------------------------------------------}
procedure TRegistrationImporter.ScanIBConsole;
{$IFDEF WINDOWS}
var
  Reg: TRegistry;
  Servers: TStringList;
  Databases: TStringList;
  Candidate: TImportCandidate;
  ServerIndex: Integer;
  DbIndex: Integer;
  ServerName: string;
  Host: string;
  Protocol: Integer;
  Mode: TConnectionMode;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  Reg := TRegistry.Create(KEY_READ);
  Servers := TStringList.Create;
  Databases := TStringList.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(IBConsoleServersKey) then
    begin
      Exit;
    end;
    Reg.GetKeyNames(Servers);
    Reg.CloseKey;

    for ServerIndex := 0 to Servers.Count - 1 do
    begin
      ServerName := Servers[ServerIndex];
      if ServerName = '' then
      begin
        Continue;
      end;

      Host := '';
      Protocol := 3;      // Local, which is IBConsole's own default
      if Reg.OpenKeyReadOnly(IBConsoleServersKey + PathDelim + ServerName) then
      begin
        if Reg.ValueExists('ServerName') then
        begin
          Host := Trim(Reg.ReadString('ServerName'));
        end;
        if Reg.ValueExists('Protocol') then
        begin
          Protocol := Reg.ReadInteger('Protocol');
        end;

        Candidate := EmptyCandidate(isIBConsole);
        Candidate.IsServer := True;
        Candidate.ServerName := ServerName;
        if Reg.ValueExists('UserName') then
        begin
          Candidate.UserName := Trim(Reg.ReadString('UserName'));
        end
        else if Reg.ValueExists('Username') then
        begin
          Candidate.UserName := Trim(Reg.ReadString('Username'));
        end;
        if Reg.ValueExists('Description') then
        begin
          Candidate.Description := Trim(Reg.ReadString('Description'));
        end;
        Reg.CloseKey;

        { Protocol 0 is TCP; 1 named pipe and 2 SPX are network protocols
          Firebird no longer speaks, so they become TCP too - the host is
          right even when the transport named is long gone. 3 is Local. }
        if Protocol = 3 then
        begin
          Mode := cmLocal;
          Host := '';
        end
        else
        begin
          Mode := cmRemote;
          if Host = '' then
          begin
            Host := ServerName;
          end;
        end;

        Candidate.Host := Host;
        Candidate.Mode := Mode;
        if Mode = cmRemote then
        begin
          Candidate.Port := DefaultFirebirdPort;
        end;
        Add(Candidate);

        Databases.Clear;
        if Reg.OpenKeyReadOnly(IBConsoleServersKey + PathDelim + ServerName +
          PathDelim + IBConsoleDatabasesKey) then
        begin
          Reg.GetKeyNames(Databases);
          Reg.CloseKey;
        end;

        for DbIndex := 0 to Databases.Count - 1 do
        begin
          if not Reg.OpenKeyReadOnly(IBConsoleServersKey + PathDelim +
            ServerName + PathDelim + IBConsoleDatabasesKey + PathDelim +
            Databases[DbIndex]) then
          begin
            Continue;
          end;
          try
            Candidate := EmptyCandidate(isIBConsole);
            Candidate.IsServer := False;
            Candidate.ServerName := ServerName;
            Candidate.Host := Host;
            Candidate.Mode := Mode;
            if Mode = cmRemote then
            begin
              Candidate.Port := DefaultFirebirdPort;
            end;
            Candidate.DatabaseName := Databases[DbIndex];
            if Reg.ValueExists('DatabaseFiles') then
            begin
              { IBConsole stores a multi-file database as one line per file.
                The first is the one to connect to; the secondary files are
                the server's business, not the client's. }
              Candidate.DatabasePath :=
                Trim(TrimRight(Reg.ReadString('DatabaseFiles')));
              if Pos(#13, Candidate.DatabasePath) > 0 then
              begin
                Candidate.DatabasePath :=
                  Trim(Copy(Candidate.DatabasePath, 1,
                    Pos(#13, Candidate.DatabasePath) - 1));
              end;
              if Pos(#10, Candidate.DatabasePath) > 0 then
              begin
                Candidate.DatabasePath :=
                  Trim(Copy(Candidate.DatabasePath, 1,
                    Pos(#10, Candidate.DatabasePath) - 1));
              end;
            end;
            if Reg.ValueExists('CharacterSet') then
            begin
              Candidate.CharacterSet := Trim(Reg.ReadString('CharacterSet'));
            end;
            if Reg.ValueExists('Role') then
            begin
              Candidate.Role := Trim(Reg.ReadString('Role'));
            end;
            if Reg.ValueExists('Username') then
            begin
              Candidate.UserName := Trim(Reg.ReadString('Username'));
            end;
            if Candidate.DatabasePath <> '' then
            begin
              Add(Candidate);
            end;
          finally
            Reg.CloseKey;
          end;
        end;
      end;
    end;
  finally
    Databases.Free;
    Servers.Free;
    Reg.Free;
  end;
  {$ENDIF}
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.MarkAlreadyRegistered
  ----------------------------------------------------------------------------
  Fills in Skip for everything already registered here.

  Notes:
    Servers are matched by host and port and databases by server and path, as
    §9.2 requires. Something already registered is left in the list, greyed
    rather than hidden: "you already have this" is an answer, and removing the
    row would look like the import had missed it.
------------------------------------------------------------------------------}
procedure TRegistrationImporter.MarkAlreadyRegistered;
var
  I: Integer;
  Server: TServerRegistration;
begin
  for I := 0 to High(FCandidates) do
  begin
    Server := FStore.FindServer(FCandidates[I].Host, FCandidates[I].Port);
    if FCandidates[I].IsServer then
    begin
      if Server <> nil then
      begin
        FCandidates[I].Skip := 'Already registered';
        FCandidates[I].Selected := False;
      end;
    end
    else
    begin
      if (Server <> nil) and
         (Server.IndexOfPath(FCandidates[I].DatabasePath) >= 0) then
      begin
        FCandidates[I].Skip := 'Already registered';
        FCandidates[I].Selected := False;
      end;
    end;
  end;
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.Scan
  ----------------------------------------------------------------------------
  Returns everything both sources offer, already marked with what is
  registered here.

  Returns:
    The candidates, servers before their databases. Empty when neither program
    has been used on this machine.
------------------------------------------------------------------------------}
function TRegistrationImporter.Scan: TImportCandidateArray;
begin
  FCandidates := nil;
  ScanFlameRobin;
  ScanIBConsole;
  MarkAlreadyRegistered;
  Log.InfoFmt('Registration import: %d candidate(s) found',
    [Length(FCandidates)]);
  Result := FCandidates;
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.UniqueName
  ----------------------------------------------------------------------------
  Returns AName, or AName with a numeric suffix when the server already holds
  that database name.

  Parameters:
    AServer - The server the database is going under.
    AName   - The name wanted.

  Returns:
    A name no database on AServer is using.

  Notes:
    §9.2: a name collision gets a suffix, never an overwrite. The path is what
    identifies a database; the name is only what the user reads, so renaming
    the newcomer costs nothing and losing the existing one would cost a lot.
------------------------------------------------------------------------------}
function TRegistrationImporter.UniqueName(AServer: TServerRegistration;
  const AName: string): string;
var
  Suffix: Integer;
  Base: string;
begin
  Base := AName;
  if Base = '' then
  begin
    Base := 'Database';
  end;
  Result := Base;
  Suffix := 1;
  while AServer.FindByName(Result) <> nil do
  begin
    Inc(Suffix);
    Result := Format('%s (%d)', [Base, Suffix]);
  end;
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.ServerFor
  ----------------------------------------------------------------------------
  Returns the server registration a candidate belongs to, creating it when it
  is not there yet.

  Parameters:
    ACandidate - The candidate wanting a server.
    ACreated   - Incremented when a server had to be created.

  Returns:
    The server registration, never nil.

  Notes:
    A database whose server was not ticked still needs one, so importing a
    database implies importing its server. That is why servers are not counted
    as imported items: the count the user is told is the count of databases
    they will see.
------------------------------------------------------------------------------}
function TRegistrationImporter.ServerFor(const ACandidate: TImportCandidate;
  var ACreated: Integer): TServerRegistration;
var
  Server: TServerRegistration;
begin
  Result := FStore.FindServer(ACandidate.Host, ACandidate.Port);
  if Result <> nil then
  begin
    Exit;
  end;

  Server := TServerRegistration.Create;
  Server.DisplayName := ACandidate.ServerName;
  Server.Host := ACandidate.Host;
  Server.Port := ACandidate.Port;
  Server.UserName := ACandidate.UserName;
  Server.Description := ACandidate.Description;
  Result := FStore.AddServer(Server);
  Inc(ACreated);
end;

{------------------------------------------------------------------------------
  TRegistrationImporter.Import
  ----------------------------------------------------------------------------
  Copies the ticked candidates into the store.

  Parameters:
    ACandidates - What Scan returned, with Selected edited by the user.

  Returns:
    How many databases were added.

  Raises:
    EIbqConfigError - The store could not be saved.

  Notes:
    Servers are created first so that a database ticked without its server
    still lands somewhere sensible. Nothing is written when nothing was
    ticked, so a user who opens the dialog and changes their mind leaves no
    trace.
------------------------------------------------------------------------------}
function TRegistrationImporter.Import(
  const ACandidates: TImportCandidateArray): Integer;
var
  I: Integer;
  Created: Integer;
  Server: TServerRegistration;
  Profile: TConnectionProfile;
begin
  Result := 0;
  Created := 0;

  for I := 0 to High(ACandidates) do
  begin
    if not ACandidates[I].Selected then
    begin
      Continue;
    end;
    if ACandidates[I].Skip <> '' then
    begin
      Continue;
    end;
    if ACandidates[I].IsServer then
    begin
      ServerFor(ACandidates[I], Created);
    end;
  end;

  for I := 0 to High(ACandidates) do
  begin
    if not ACandidates[I].Selected then
    begin
      Continue;
    end;
    if ACandidates[I].Skip <> '' then
    begin
      Continue;
    end;
    if ACandidates[I].IsServer then
    begin
      Continue;
    end;

    Server := ServerFor(ACandidates[I], Created);
    if Server.IndexOfPath(ACandidates[I].DatabasePath) >= 0 then
    begin
      Continue;
    end;

    Profile := TConnectionProfile.Create;
    Profile.DisplayName := UniqueName(Server, ACandidates[I].DatabaseName);
    Profile.Mode := ACandidates[I].Mode;
    Profile.Host := ACandidates[I].Host;
    Profile.Port := ACandidates[I].Port;
    Profile.DatabasePath := ACandidates[I].DatabasePath;
    Profile.UserName := ACandidates[I].UserName;
    Profile.Role := ACandidates[I].Role;
    Profile.CharacterSet := ACandidates[I].CharacterSet;
    Profile.ClientLibrary := ACandidates[I].ClientLibrary;
    { No password, ever. See the unit header. }
    Profile.Password := '';
    Profile.PasswordStorage := psDoNotStore;
    Server.AddDatabase(Profile);
    Inc(Result);
  end;

  if (Result > 0) or (Created > 0) then
  begin
    FStore.MarkModified;
    FStore.Save;
    Log.InfoFmt('Imported %d database(s) and %d server(s)', [Result, Created]);
  end;
end;

end.
