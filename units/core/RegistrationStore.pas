{==============================================================================
  Unit:        RegistrationStore
  Purpose:     Loads and saves the registered servers, databases and embedded
               databases, as XML under the user's configuration directory.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, laz2_DOM, laz2_XMLRead, laz2_XMLWrite,
               IbqError, ConnectionProfile, ServerRegistration

  Not the Windows registry, which is where IBConsole kept this and which made
  its registrations unportable, invisible to the user and impossible to copy
  between machines. A file the user can find, read, back up and edit is worth
  more than a tidy API.

  Password policy: a password is written to this file ONLY when the profile
  says psEncrypted, and even then it is written through the master-password
  crypto in units/core/CryptoStore. psSessionOnly and psDoNotStore never reach
  the disk. See SPECIFICATION.md 9.1.
==============================================================================}
unit RegistrationStore;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, laz2_DOM, laz2_XMLRead, laz2_XMLWrite,
  IbqError, ConnectionProfile, ServerRegistration;

const
  { Name of the registration file inside the configuration directory. }
  RegistrationFileName = 'registrations.xml';
  { Bumped when the file layout changes in a way a reader must know about. }
  RegistrationFormatVersion = 1;

type
  { TRegistrationStore
    The registered servers and embedded databases. Owns everything it holds. }
  TRegistrationStore = class(TObject)
  private
    FServers: TFPObjectList;
    FEmbedded: TFPObjectList;
    FFileName: string;
    FModified: Boolean;
    function GetServerCount: Integer;
    function GetServer(AIndex: Integer): TServerRegistration;
    function GetEmbeddedCount: Integer;
    function GetEmbedded(AIndex: Integer): TConnectionProfile;
    procedure ReadServerNode(ANode: TDOMElement);
    procedure ReadDatabaseNode(ANode: TDOMElement;
      AServer: TServerRegistration);
    procedure ReadEmbeddedNode(ANode: TDOMElement);
    procedure WriteProfile(ADoc: TXMLDocument; AParent: TDOMElement;
      AProfile: TConnectionProfile; AWriteClient: Boolean);
  public
    constructor Create;
    destructor Destroy; override;

    { Adds a server registration and takes ownership. Returns it. }
    function AddServer(AServer: TServerRegistration): TServerRegistration;
    { Removes and frees the server at AIndex, with its databases. }
    procedure DeleteServer(AIndex: Integer);
    { Returns the registration for AHost/APort, or nil. }
    function FindServer(const AHost: string;
      APort: Integer): TServerRegistration;

    { Adds an embedded database profile and takes ownership. Returns it. }
    function AddEmbedded(AProfile: TConnectionProfile): TConnectionProfile;
    { Removes and frees the embedded database at AIndex. }
    procedure DeleteEmbedded(AIndex: Integer);

    { Discards everything held. }
    procedure Clear;

    { Reads the registrations from FileName.

      Notes:
        A missing file is not an error - it means a first run, and the store is
        simply left empty.

      Raises:
        EIbqConfigError - The file exists but cannot be parsed. }
    procedure Load;
    { Writes the registrations to FileName, creating the directory if needed.

      Raises:
        EIbqConfigError - The file cannot be written. }
    procedure Save;
    { Writes only when something changed since the last Load or Save. }
    procedure SaveIfModified;

    { Marks the store as needing a Save. }
    procedure MarkModified;

    { Full path of the registration file. }
    property FileName: string read FFileName write FFileName;
    { True when there are unsaved changes. }
    property Modified: Boolean read FModified;

    { How many servers are registered. }
    property ServerCount: Integer read GetServerCount;
    { The server at AIndex. }
    property Servers[AIndex: Integer]: TServerRegistration read GetServer;
    { How many embedded databases are registered. }
    property EmbeddedCount: Integer read GetEmbeddedCount;
    { The embedded database at AIndex. }
    property Embedded[AIndex: Integer]: TConnectionProfile read GetEmbedded;
  end;

{ Returns the directory holding IBQConsole's configuration, with a trailing
  path delimiter. Windows: %APPDATA%\IBQConsole\. Linux:
  ~/.config/ibqconsole/. }
function ConfigDir: string;

implementation

{------------------------------------------------------------------------------
  ConfigDir
  ----------------------------------------------------------------------------
  Returns the configuration directory.

  Returns:
    The path with a trailing delimiter. The directory is not created here;
    Save creates it when it first needs to write.
------------------------------------------------------------------------------}
function ConfigDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
end;

{------------------------------------------------------------------------------
  NodeAttr
  ----------------------------------------------------------------------------
  Reads one attribute of an element.

  Parameters:
    ANode     - The element.
    AName     - Attribute name.
    ADefault  - Returned when the attribute is absent.

  Returns:
    The attribute's value, or ADefault.
------------------------------------------------------------------------------}
function NodeAttr(ANode: TDOMElement; const AName: string;
  const ADefault: string = ''): string;
var
  Attr: TDOMNode;
begin
  if ANode = nil then
    Exit(ADefault);
  Attr := ANode.Attributes.GetNamedItem(AName);
  if Attr = nil then
    Result := ADefault
  else
    Result := Attr.NodeValue;
end;

{------------------------------------------------------------------------------
  NodeAttrInt
  ----------------------------------------------------------------------------
  Reads one attribute of an element as an integer.

  Parameters:
    ANode    - The element.
    AName    - Attribute name.
    ADefault - Returned when the attribute is absent or not a number.

  Returns:
    The value, or ADefault.
------------------------------------------------------------------------------}
function NodeAttrInt(ANode: TDOMElement; const AName: string;
  ADefault: Integer): Integer;
begin
  Result := StrToIntDef(NodeAttr(ANode, AName, ''), ADefault);
end;

{------------------------------------------------------------------------------
  NodeAttrBool
  ----------------------------------------------------------------------------
  Reads one attribute of an element as a boolean.

  Parameters:
    ANode    - The element.
    AName    - Attribute name.
    ADefault - Returned when the attribute is absent.

  Returns:
    True when the attribute reads 'true' or '1'.
------------------------------------------------------------------------------}
function NodeAttrBool(ANode: TDOMElement; const AName: string;
  ADefault: Boolean): Boolean;
var
  Text: string;
begin
  Text := NodeAttr(ANode, AName, '');
  if Text = '' then
    Exit(ADefault);
  Result := SameText(Text, 'true') or (Text = '1');
end;

{------------------------------------------------------------------------------
  SetAttr
  ----------------------------------------------------------------------------
  Writes one attribute of an element.

  Parameters:
    ANode  - The element.
    AName  - Attribute name.
    AValue - Value to write.
------------------------------------------------------------------------------}
procedure SetAttr(ANode: TDOMElement; const AName, AValue: string);
begin
  ANode.SetAttribute(AName, AValue);
end;

{------------------------------------------------------------------------------
  TRegistrationStore.Create
  ----------------------------------------------------------------------------
  Creates an empty store pointing at the default registration file.
------------------------------------------------------------------------------}
constructor TRegistrationStore.Create;
begin
  inherited Create;
  FServers := TFPObjectList.Create(True);
  FEmbedded := TFPObjectList.Create(True);
  FFileName := ConfigDir + RegistrationFileName;
  FModified := False;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.Destroy
  ----------------------------------------------------------------------------
  Frees the servers and embedded databases held.

  Notes:
    Does not save. A store that wrote itself out during destruction would
    persist changes made by a dialog the user cancelled, or by a failed import.
    Saving is always an explicit decision.
------------------------------------------------------------------------------}
destructor TRegistrationStore.Destroy;
begin
  FreeAndNil(FServers);
  FreeAndNil(FEmbedded);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.GetServerCount
  ----------------------------------------------------------------------------
  Returns how many servers are registered.
------------------------------------------------------------------------------}
function TRegistrationStore.GetServerCount: Integer;
begin
  Result := FServers.Count;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.GetServer
  ----------------------------------------------------------------------------
  Returns the server registration at AIndex.
------------------------------------------------------------------------------}
function TRegistrationStore.GetServer(AIndex: Integer): TServerRegistration;
begin
  Result := TServerRegistration(FServers[AIndex]);
end;

{------------------------------------------------------------------------------
  TRegistrationStore.GetEmbeddedCount
  ----------------------------------------------------------------------------
  Returns how many embedded databases are registered.
------------------------------------------------------------------------------}
function TRegistrationStore.GetEmbeddedCount: Integer;
begin
  Result := FEmbedded.Count;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.GetEmbedded
  ----------------------------------------------------------------------------
  Returns the embedded database profile at AIndex.
------------------------------------------------------------------------------}
function TRegistrationStore.GetEmbedded(AIndex: Integer): TConnectionProfile;
begin
  Result := TConnectionProfile(FEmbedded[AIndex]);
end;

{------------------------------------------------------------------------------
  TRegistrationStore.AddServer
  ----------------------------------------------------------------------------
  Adds a server registration and takes ownership.

  Parameters:
    AServer - The registration to add. Nil is ignored.

  Returns:
    AServer.
------------------------------------------------------------------------------}
function TRegistrationStore.AddServer(
  AServer: TServerRegistration): TServerRegistration;
begin
  Result := AServer;
  if AServer = nil then
    Exit;
  FServers.Add(AServer);
  MarkModified;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.DeleteServer
  ----------------------------------------------------------------------------
  Removes and frees the server at AIndex, together with its databases.

  Parameters:
    AIndex - Zero-based position; out-of-range values are ignored.
------------------------------------------------------------------------------}
procedure TRegistrationStore.DeleteServer(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FServers.Count) then
  begin
    FServers.Delete(AIndex);
    MarkModified;
  end;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.FindServer
  ----------------------------------------------------------------------------
  Finds a registered server by host and port.

  Parameters:
    AHost - Host name or address.
    APort - Port; 0 means the default.

  Returns:
    The registration, or nil.
------------------------------------------------------------------------------}
function TRegistrationStore.FindServer(const AHost: string;
  APort: Integer): TServerRegistration;
var
  I: Integer;
begin
  for I := 0 to FServers.Count - 1 do
  begin
    if Servers[I].Matches(AHost, APort) then
      Exit(Servers[I]);
  end;
  Result := nil;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.AddEmbedded
  ----------------------------------------------------------------------------
  Adds an embedded database profile and takes ownership.

  Parameters:
    AProfile - The profile to add; its Mode is forced to cmEmbedded.

  Returns:
    AProfile.
------------------------------------------------------------------------------}
function TRegistrationStore.AddEmbedded(
  AProfile: TConnectionProfile): TConnectionProfile;
begin
  Result := AProfile;
  if AProfile = nil then
    Exit;
  AProfile.Mode := cmEmbedded;
  FEmbedded.Add(AProfile);
  MarkModified;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.DeleteEmbedded
  ----------------------------------------------------------------------------
  Removes and frees the embedded database at AIndex.

  Parameters:
    AIndex - Zero-based position; out-of-range values are ignored.
------------------------------------------------------------------------------}
procedure TRegistrationStore.DeleteEmbedded(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FEmbedded.Count) then
  begin
    FEmbedded.Delete(AIndex);
    MarkModified;
  end;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.Clear
  ----------------------------------------------------------------------------
  Discards every server and embedded database held.
------------------------------------------------------------------------------}
procedure TRegistrationStore.Clear;
begin
  FServers.Clear;
  FEmbedded.Clear;
  MarkModified;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.MarkModified
  ----------------------------------------------------------------------------
  Records that the store has unsaved changes.
------------------------------------------------------------------------------}
procedure TRegistrationStore.MarkModified;
begin
  FModified := True;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.ReadDatabaseNode
  ----------------------------------------------------------------------------
  Reads one <database> element into a new profile under AServer.

  Parameters:
    ANode   - The <database> element.
    AServer - The server the database belongs to; supplies host and port.
------------------------------------------------------------------------------}
procedure TRegistrationStore.ReadDatabaseNode(ANode: TDOMElement;
  AServer: TServerRegistration);
var
  Profile: TConnectionProfile;
begin
  Profile := TConnectionProfile.Create;
  Profile.DisplayName := NodeAttr(ANode, 'name');
  Profile.DatabasePath := NodeAttr(ANode, 'path');
  Profile.Mode := StrToConnectionMode(NodeAttr(ANode, 'mode', 'remote'));
  Profile.Host := AServer.Host;
  Profile.Port := AServer.Port;
  Profile.UserName := NodeAttr(ANode, 'user', AServer.UserName);
  Profile.Role := NodeAttr(ANode, 'role');
  Profile.UseCaseSensitiveRole := NodeAttrBool(ANode, 'rolecasesensitive', False);
  Profile.CharacterSet := NodeAttr(ANode, 'charset', DefaultCharacterSet);
  Profile.PageBuffers := NodeAttrInt(ANode, 'pagebuffers', 0);
  Profile.PasswordStorage :=
    StrToPasswordStorage(NodeAttr(ANode, 'passwordstorage', 'none'));

  AServer.AddDatabase(Profile);
end;

{------------------------------------------------------------------------------
  TRegistrationStore.ReadServerNode
  ----------------------------------------------------------------------------
  Reads one <server> element and its <database> children.

  Parameters:
    ANode - The <server> element.
------------------------------------------------------------------------------}
procedure TRegistrationStore.ReadServerNode(ANode: TDOMElement);
var
  Server: TServerRegistration;
  Child: TDOMNode;
begin
  Server := TServerRegistration.Create;
  Server.DisplayName := NodeAttr(ANode, 'name');
  Server.Host := NodeAttr(ANode, 'host', 'localhost');
  Server.Port := NodeAttrInt(ANode, 'port', DefaultFirebirdPort);
  Server.UserName := NodeAttr(ANode, 'user');
  Server.Description := NodeAttr(ANode, 'description');
  Server.ClientLibrary := NodeAttr(ANode, 'clientlib');

  Child := ANode.FirstChild;
  while Child <> nil do
  begin
    if (Child.NodeType = ELEMENT_NODE) and
       SameText(Child.NodeName, 'database') then
      ReadDatabaseNode(TDOMElement(Child), Server);
    Child := Child.NextSibling;
  end;

  FServers.Add(Server);
end;

{------------------------------------------------------------------------------
  TRegistrationStore.ReadEmbeddedNode
  ----------------------------------------------------------------------------
  Reads one <database> element under <embedded>.

  Parameters:
    ANode - The <database> element.
------------------------------------------------------------------------------}
procedure TRegistrationStore.ReadEmbeddedNode(ANode: TDOMElement);
var
  Profile: TConnectionProfile;
begin
  Profile := TConnectionProfile.Create;
  Profile.Mode := cmEmbedded;
  Profile.DisplayName := NodeAttr(ANode, 'name');
  Profile.DatabasePath := NodeAttr(ANode, 'path');
  Profile.CharacterSet := NodeAttr(ANode, 'charset', DefaultCharacterSet);
  Profile.ClientLibrary := NodeAttr(ANode, 'clientlib');
  Profile.PageBuffers := NodeAttrInt(ANode, 'pagebuffers', 0);
  FEmbedded.Add(Profile);
end;

{------------------------------------------------------------------------------
  TRegistrationStore.Load
  ----------------------------------------------------------------------------
  Reads the registrations from FileName.

  Notes:
    A missing file leaves the store empty and is not an error: that is what a
    first run looks like.

  Raises:
    EIbqConfigError - The file exists but is not readable XML. The message
                      names the file, because the usual cause is a hand edit
                      and the user needs to know which file to fix.
------------------------------------------------------------------------------}
procedure TRegistrationStore.Load;
var
  Doc: TXMLDocument;
  Root, Section, Child: TDOMNode;
begin
  Clear;
  FModified := False;

  if not FileExists(FFileName) then
    Exit;

  Doc := nil;
  try
    try
      ReadXMLFile(Doc, FFileName);
    except
      on E: Exception do
        raise EIbqConfigError.CreateFmt(
          'The registration file "%s" could not be read: %s',
          [FFileName, E.Message]);
    end;

    Root := Doc.DocumentElement;
    if Root = nil then
      Exit;

    Section := Root.FirstChild;
    while Section <> nil do
    begin
      if Section.NodeType = ELEMENT_NODE then
      begin
        if SameText(Section.NodeName, 'servers') then
        begin
          Child := Section.FirstChild;
          while Child <> nil do
          begin
            if (Child.NodeType = ELEMENT_NODE) and
               SameText(Child.NodeName, 'server') then
              ReadServerNode(TDOMElement(Child));
            Child := Child.NextSibling;
          end;
        end
        else if SameText(Section.NodeName, 'embedded') then
        begin
          Child := Section.FirstChild;
          while Child <> nil do
          begin
            if (Child.NodeType = ELEMENT_NODE) and
               SameText(Child.NodeName, 'database') then
              ReadEmbeddedNode(TDOMElement(Child));
            Child := Child.NextSibling;
          end;
        end;
      end;
      Section := Section.NextSibling;
    end;
  finally
    Doc.Free;
  end;

  FModified := False;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.WriteProfile
  ----------------------------------------------------------------------------
  Writes one profile as a <database> element.

  Parameters:
    ADoc         - The document being built.
    AParent      - The element to append to.
    AProfile     - The profile to write.
    AWriteClient - True only for an embedded database. A database reached
                   through a server takes its client library from that server
                   and must not carry a copy: see the note below.

  Notes:
    The client library is a property of the SERVER, not of each database on it.
    Writing it per database would let the two drift apart, and would raise the
    question of what it should mean for two databases on one server to name
    different clients - which is not a question with a good answer, because the
    library is loaded once for the connection to that server. An embedded
    database is the exception: it has no server, so it carries its own.

    The password is never written here whatever the policy says. Encrypted
    storage goes through units/core/CryptoStore, which is not part of M1; until
    it exists, psEncrypted behaves as psDoNotStore, which errs in the safe
    direction.
------------------------------------------------------------------------------}
procedure TRegistrationStore.WriteProfile(ADoc: TXMLDocument;
  AParent: TDOMElement; AProfile: TConnectionProfile;
  AWriteClient: Boolean);
var
  Node: TDOMElement;
begin
  Node := ADoc.CreateElement('database');
  AParent.AppendChild(Node);

  SetAttr(Node, 'name', AProfile.DisplayName);
  SetAttr(Node, 'path', AProfile.DatabasePath);
  SetAttr(Node, 'mode', ConnectionModeToStr(AProfile.Mode));
  SetAttr(Node, 'user', AProfile.UserName);
  SetAttr(Node, 'charset', AProfile.CharacterSet);
  SetAttr(Node, 'passwordstorage',
    PasswordStorageToStr(AProfile.PasswordStorage));

  if AProfile.Role <> '' then
  begin
    SetAttr(Node, 'role', AProfile.Role);
    if AProfile.UseCaseSensitiveRole then
      SetAttr(Node, 'rolecasesensitive', 'true');
  end;
  if AWriteClient and (AProfile.ClientLibrary <> '') then
    SetAttr(Node, 'clientlib', AProfile.ClientLibrary);
  if AProfile.PageBuffers > 0 then
    SetAttr(Node, 'pagebuffers', IntToStr(AProfile.PageBuffers));
end;

{------------------------------------------------------------------------------
  TRegistrationStore.Save
  ----------------------------------------------------------------------------
  Writes the registrations to FileName.

  Raises:
    EIbqConfigError - The directory cannot be created or the file cannot be
                      written.
------------------------------------------------------------------------------}
procedure TRegistrationStore.Save;
var
  Doc: TXMLDocument;
  Root, ServersNode, EmbeddedNode, ServerNode: TDOMElement;
  I, J: Integer;
  Directory: string;
begin
  Directory := ExtractFilePath(FFileName);
  if (Directory <> '') and not DirectoryExists(Directory) then
  begin
    if not ForceDirectories(Directory) then
      raise EIbqConfigError.CreateFmt(
        'The configuration directory "%s" could not be created.', [Directory]);
  end;

  Doc := TXMLDocument.Create;
  try
    Root := Doc.CreateElement('ibqconsole');
    SetAttr(Root, 'version', IntToStr(RegistrationFormatVersion));
    Doc.AppendChild(Root);

    ServersNode := Doc.CreateElement('servers');
    Root.AppendChild(ServersNode);

    for I := 0 to FServers.Count - 1 do
    begin
      ServerNode := Doc.CreateElement('server');
      ServersNode.AppendChild(ServerNode);

      SetAttr(ServerNode, 'name', Servers[I].DisplayName);
      SetAttr(ServerNode, 'host', Servers[I].Host);
      SetAttr(ServerNode, 'port', IntToStr(Servers[I].Port));
      if Servers[I].UserName <> '' then
        SetAttr(ServerNode, 'user', Servers[I].UserName);
      if Servers[I].Description <> '' then
        SetAttr(ServerNode, 'description', Servers[I].Description);
      if Servers[I].ClientLibrary <> '' then
        SetAttr(ServerNode, 'clientlib', Servers[I].ClientLibrary);

      for J := 0 to Servers[I].DatabaseCount - 1 do
        WriteProfile(Doc, ServerNode, Servers[I].Databases[J], False);
    end;

    EmbeddedNode := Doc.CreateElement('embedded');
    Root.AppendChild(EmbeddedNode);
    for I := 0 to FEmbedded.Count - 1 do
      WriteProfile(Doc, EmbeddedNode, Embedded[I], True);

    try
      WriteXMLFile(Doc, FFileName);
    except
      on E: Exception do
        raise EIbqConfigError.CreateFmt(
          'The registration file "%s" could not be written: %s',
          [FFileName, E.Message]);
    end;
  finally
    Doc.Free;
  end;

  FModified := False;
end;

{------------------------------------------------------------------------------
  TRegistrationStore.SaveIfModified
  ----------------------------------------------------------------------------
  Writes the file only when something changed.
------------------------------------------------------------------------------}
procedure TRegistrationStore.SaveIfModified;
begin
  if FModified then
    Save;
end;

end.
