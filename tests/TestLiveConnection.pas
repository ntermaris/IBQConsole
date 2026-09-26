{==============================================================================
  Program:     TestLiveConnection
  Purpose:     Drives the database layer against a real Firebird 3, 4 and 5
               server, each through its OWN client library, in one process.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21

  Why this exists: everything in tests/ up to now runs without a server, which
  is what makes those tests cheap and repeatable - and also what stops them
  saying anything about the half of the program that attaches to Firebird.
  This one needs the rig described in documentation/dev/building.md and is the
  Linux counterpart of the Windows runs recorded in that file's §5.2.

  Three things are being checked, and only the first is obvious:

  1. That each version attaches, reports its own engine and ODS version, and
     lists the folders its feature set says it should have.
  2. That THREE different client libraries can live in one process. This is
     the assumption the whole per-registration-client design rests on
     (SPECIFICATION.md §5.6.1); if it were false the program would need one
     process per server version.
  3. That the process still EXITS CLEANLY afterwards. On Windows, connecting
     to a newer server and then an older one crashed at finalisation with an
     access violation - after every visible result was already correct
     (building.md §5.6). Nothing in the output revealed it; only the exit code
     did. So this program checks its own teardown by having a teardown worth
     checking, and the runner must look at the exit code, not just the text.

  Usage:
    TestLiveConnection [<rig root>]

  The rig root defaults to /mnt/Data/Firebird/linux and is expected to hold
  fb3/, fb4/ and fb5/ with a lib/libfbclient.so each, plus the databases under
  data/fbN/. Pass a different root to run it against another layout.
==============================================================================}
program TestLiveConnection;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes,
  ConnectionProfile, DatabaseContext, ServerVersion, FeatureSet,
  FbClientLocator, MetadataSqlProvider,
  MetaTypes, MetaItem, MetaCollection, MetaDatabase,
  IbqError;

type
  { One server of the rig: which version it is, where it listens, and which
    client library and database belong to it. }
  TRigInstance = record
    Major: Integer;
    Minor: Integer;
    Port: Integer;
    ClientLibrary: string;
    DatabasePath: string;
  end;

const
  DefaultRigRoot = '/mnt/Data/Firebird/linux';
  RigUser        = 'SYSDBA';
  RigPassword    = 'masterkey';
  RigDatabase    = 'EMPTEST.FDB';

var
  Failures: Integer = 0;
  Rig: array[0..2] of TRigInstance;

{------------------------------------------------------------------------------
  Fail
  ----------------------------------------------------------------------------
  Reports a failed expectation and counts it.

  Parameters:
    AWhat - What was expected, in the same wording as the passing case.
------------------------------------------------------------------------------}
procedure Fail(const AWhat: string);
begin
  WriteLn('  FAIL  ', AWhat);
  Inc(Failures);
end;

{------------------------------------------------------------------------------
  Check
  ----------------------------------------------------------------------------
  Reports a condition either way, so the output lists what was proved and not
  only what broke.

  Parameters:
    ACondition - The expectation.
    AWhat      - How to describe it.
------------------------------------------------------------------------------}
procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
  begin
    WriteLn('  ok    ', AWhat);
  end
  else
  begin
    Fail(AWhat);
  end;
end;

{------------------------------------------------------------------------------
  BuildRig
  ----------------------------------------------------------------------------
  Fills the Rig array from a root directory.

  Parameters:
    ARoot - Directory holding fb3/, fb4/, fb5/ and data/.

  Notes:
    Paths are built with PathDelim rather than written out, so the same
    program describes a Windows rig if one is ever pointed at it.
------------------------------------------------------------------------------}
procedure BuildRig(const ARoot: string);
var
  Root: string;
  I: Integer;
  Majors: array[0..2] of Integer = (3, 4, 5);
  Minors: array[0..2] of Integer = (0, 0, 0);
  Ports: array[0..2] of Integer = (3050, 3051, 3052);
begin
  Root := IncludeTrailingPathDelimiter(ARoot);
  for I := 0 to 2 do
  begin
    Rig[I].Major := Majors[I];
    Rig[I].Minor := Minors[I];
    Rig[I].Port := Ports[I];
    Rig[I].ClientLibrary := Format('%sfb%d%slib%slibfbclient.so',
      [Root, Majors[I], PathDelim, PathDelim]);
    Rig[I].DatabasePath := Format('%sdata%sfb%d%s%s',
      [Root, PathDelim, Majors[I], PathDelim, RigDatabase]);
  end;
end;

{------------------------------------------------------------------------------
  ProfileFor
  ----------------------------------------------------------------------------
  Builds a remote connection profile for one rig instance.

  Parameters:
    AInstance - The server to describe.

  Returns:
    A new profile. The caller frees it.

  Notes:
    TCP to localhost rather than a local attachment, for the reason given in
    building.md §5.13: a local attachment goes through the machine's default
    Firebird installation, which on a machine running three of them is the
    wrong server two times out of three.
------------------------------------------------------------------------------}
function ProfileFor(const AInstance: TRigInstance): TConnectionProfile;
begin
  Result := TConnectionProfile.Create;
  Result.DisplayName := Format('FB%d', [AInstance.Major]);
  Result.Mode := cmRemote;
  Result.Host := 'localhost';
  Result.Port := AInstance.Port;
  Result.DatabasePath := AInstance.DatabasePath;
  Result.UserName := RigUser;
  Result.ClientLibrary := AInstance.ClientLibrary;
end;

{------------------------------------------------------------------------------
  ReportDetectedClients
  ----------------------------------------------------------------------------
  Prints what FbClientLocator finds on this machine without being told where
  to look.

  Notes:
    Informational, not an expectation. The rig lives outside every search root
    the locator knows, so finding nothing here is the correct answer and says
    something useful: on Linux a registration must name its client library,
    because auto-detection only covers the packaged and /opt layouts.
------------------------------------------------------------------------------}
procedure ReportDetectedClients;
var
  Clients: TFbClientList;
  I: Integer;
begin
  WriteLn;
  WriteLn('Client libraries found by auto-detection');
  WriteLn;
  Clients := DetectClients;
  if Length(Clients) = 0 then
  begin
    WriteLn('  none - the rig is outside every search root, so a ',
            'registration must name its own client');
  end
  else
  begin
    for I := Low(Clients) to High(Clients) do
    begin
      WriteLn('  ', Clients[I].DisplayText);
    end;
  end;
end;

{------------------------------------------------------------------------------
  CheckClientReadable
  ----------------------------------------------------------------------------
  Checks that the locator can read a client library it is handed directly.

  Parameters:
    AInstance - The server whose library to read.

  Notes:
    Separate from detection: a Linux shared object usually carries no version
    resource, so ReadClientInfo falls back to parsing the folder name. That
    fallback is the reason a rig laid out as fb3/ fb4/ fb5/ still shows the
    right version in the registration dialog.
------------------------------------------------------------------------------}
procedure CheckClientReadable(const AInstance: TRigInstance);
var
  Info: TFbClientInfo;
begin
  if not FileExists(AInstance.ClientLibrary) then
  begin
    Fail(Format('client library exists: %s', [AInstance.ClientLibrary]));
    Exit;
  end;

  ReadClientInfo(AInstance.ClientLibrary, Info);
  Check(Info.Major = AInstance.Major,
    Format('client library reads as major %d (got %d) - %s',
      [AInstance.Major, Info.Major, Info.DisplayText]));
end;

{------------------------------------------------------------------------------
  CheckFeatureGating
  ----------------------------------------------------------------------------
  Checks the version-gated feature flags for one server.

  Parameters:
    AVersion - The version read from the live attachment.
    AMajor   - The major version expected.

  Notes:
    Three flags, one per gate that actually changes what the user sees:
    publications appear at FB4, partial indexes at FB5, and schemas at FB6 -
    which no server here has, so that one must be false everywhere.
------------------------------------------------------------------------------}
procedure CheckFeatureGating(const AVersion: TServerVersion; AMajor: Integer);
begin
  Check(SupportsFeature(AVersion, dbfPublications) = (AMajor >= 4),
    Format('dbfPublications is %s on FB%d',
      [BoolToStr(AMajor >= 4, 'True', 'False'), AMajor]));
  Check(SupportsFeature(AVersion, dbfPartialIndexes) = (AMajor >= 5),
    Format('dbfPartialIndexes is %s on FB%d',
      [BoolToStr(AMajor >= 5, 'True', 'False'), AMajor]));
  Check(not SupportsFeature(AVersion, dbfSchemas),
    Format('dbfSchemas is False on FB%d', [AMajor]));
end;

{------------------------------------------------------------------------------
  CheckAttachment
  ----------------------------------------------------------------------------
  Attaches to one server and checks what it reports about itself.

  Parameters:
    AInstance - The server to attach to.

  Notes:
    Everything here is read from the live attachment: the engine version and
    ODS come from MON$DATABASE, the dialect from the attachment itself, and
    the SQL provider is chosen from the version rather than from anything the
    caller declared. That is the point - a version the program guessed would
    prove nothing.
------------------------------------------------------------------------------}
procedure CheckAttachment(const AInstance: TRigInstance);
var
  Profile: TConnectionProfile;
  Context: TDatabaseContext;
begin
  WriteLn;
  WriteLn(Format('FB%d  port %d  client %s',
    [AInstance.Major, AInstance.Port, AInstance.ClientLibrary]));
  WriteLn;

  Profile := ProfileFor(AInstance);
  try
    Context := TDatabaseContext.Create(Profile, AInstance.ClientLibrary);
    try
      try
        Context.Connect(RigPassword);
      except
        on E: Exception do
        begin
          Fail(Format('attached to FB%d - %s: %s',
            [AInstance.Major, E.ClassName, E.Message]));
          Exit;
        end;
      end;

      Check(Context.IsConnected, Format('attached to FB%d', [AInstance.Major]));
      Check(Context.Version.Major = AInstance.Major,
        Format('engine reports major %d (got %s)',
          [AInstance.Major, Context.Version.DisplayText]));
      Check(Context.Version.OdsMajor > 0,
        Format('ODS read from the server: %d.%d',
          [Context.Version.OdsMajor, Context.Version.OdsMinor]));
      Check(Context.SqlDialect = 3,
        Format('SQL dialect 3 (got %d)', [Context.SqlDialect]));
      Check(Context.SqlProvider <> nil,
        Format('a metadata SQL provider was built: %s',
          [Context.SqlProvider.ClassName]));

      CheckFeatureGating(Context.Version, AInstance.Major);

      Context.Disconnect;
      Check(not Context.IsConnected,
        Format('detached from FB%d', [AInstance.Major]));
    finally
      Context.Free;
    end;
  finally
    Profile.Free;
  end;
end;

{------------------------------------------------------------------------------
  CountObjects
  ----------------------------------------------------------------------------
  Loads every folder of a connected database and totals what they hold.

  Parameters:
    ADatabase - A connected model node.
    AFolders  - Receives the number of folders.

  Returns:
    The total number of objects across every folder.

  Notes:
    The tree never does this - it loads a folder when the user opens it. Doing
    it here is deliberate: a folder whose SQL is wrong for this server version
    fails when it is opened, and opening all of them is the only way to find
    that out without clicking through the program.
------------------------------------------------------------------------------}
function CountObjects(ADatabase: TMetaDatabase; out AFolders: Integer): Integer;
var
  I: Integer;
  Folder: TMetaItem;
begin
  Result := 0;
  ADatabase.EnsureChildrenLoaded;
  AFolders := ADatabase.ChildCount;

  for I := 0 to ADatabase.ChildCount - 1 do
  begin
    Folder := ADatabase.Child[I];
    Folder.EnsureChildrenLoaded;
    Inc(Result, Folder.ChildCount);

    if (Folder is TMetaCollection) and
       (TMetaCollection(Folder).LoadFailure <> '') then
    begin
      Fail(Format('folder %s loaded - %s',
        [DefaultNodeCaption(Folder.NodeType),
         TMetaCollection(Folder).LoadFailure]));
    end;
  end;
end;

{------------------------------------------------------------------------------
  CheckFolders
  ----------------------------------------------------------------------------
  Connects the model to one server and checks the folders it produces.

  Parameters:
    AInstance - The server to browse.

  Notes:
    The Publications folder is the one that must be ABSENT on Firebird 3 -
    absent, not present and empty. A folder a server cannot answer for is a
    folder the user should not be invited to open.
------------------------------------------------------------------------------}
procedure CheckFolders(const AInstance: TRigInstance);
var
  Profile: TConnectionProfile;
  Database: TMetaDatabase;
  Folders, Objects: Integer;
  HasPublications: Boolean;
begin
  Profile := ProfileFor(AInstance);
  try
    Database := TMetaDatabase.CreateForProfile(nil, Profile);
    try
      try
        Database.Connect(RigPassword);
      except
        on E: Exception do
        begin
          Fail(Format('model connected to FB%d - %s: %s',
            [AInstance.Major, E.ClassName, E.Message]));
          Exit;
        end;
      end;

      Objects := CountObjects(Database, Folders);
      WriteLn(Format('  %d folders, %d objects', [Folders, Objects]));

      Check(Folders > 0, Format('FB%d produced folders', [AInstance.Major]));
      Check(Objects > 0,
        Format('FB%d folders hold objects', [AInstance.Major]));

      HasPublications :=
        Database.FindChildOfType(mntPublications) <> nil;
      Check(HasPublications = (AInstance.Major >= 4),
        Format('Publications folder is %s on FB%d',
          [BoolToStr(AInstance.Major >= 4, 'present', 'absent'),
           AInstance.Major]));

      Database.Disconnect;
      Check(not Database.IsConnected,
        Format('model detached from FB%d', [AInstance.Major]));
    finally
      Database.Free;
    end;
  finally
    Profile.Free;
  end;
end;

{------------------------------------------------------------------------------
  CheckNewestThenOldest
  ----------------------------------------------------------------------------
  Attaches to the newest server and then to the oldest, in one process.

  Notes:
    This is the sequence that crashed on Windows at finalisation
    (building.md §5.6) and the reason FbClientLocator.PinClientLibrary exists.
    Nothing here can assert the absence of that crash: it happens after the
    last line of output, so the CHECK IS THE EXIT CODE of this program. The
    ordering is what matters - newer client loaded first, older one after it.
------------------------------------------------------------------------------}
procedure CheckNewestThenOldest;
var
  Order: array[0..1] of Integer = (2, 0);      // FB5 then FB3
  I: Integer;
  Profile: TConnectionProfile;
  Context: TDatabaseContext;
begin
  WriteLn;
  WriteLn('Newest client then oldest, in one process');
  WriteLn;

  for I := 0 to 1 do
  begin
    Profile := ProfileFor(Rig[Order[I]]);
    try
      Context := TDatabaseContext.Create(Profile, Rig[Order[I]].ClientLibrary);
      try
        Context.Connect(RigPassword);
        Check(Context.Version.Major = Rig[Order[I]].Major,
          Format('FB%d attached second-hand: %s',
            [Rig[Order[I]].Major, Context.Version.DisplayText]));
        Context.Disconnect;
      finally
        Context.Free;
      end;
    finally
      Profile.Free;
    end;
  end;

  WriteLn('  the remaining check is this program''s exit code');
end;

{------------------------------------------------------------------------------
  CheckConnectionStrings
  ----------------------------------------------------------------------------
  Checks that a remote profile always names its port.

  Notes:
    The port used to be left out when it was 3050, on the grounds that 3050 is
    the default. It is not ours to call default: the client library resolves a
    portless 'host:path' using the RemoteServicePort in ITS OWN firebird.conf,
    and on this rig that is 3051 for the Firebird 4 client and 3052 for the
    Firebird 5 one. A profile aimed at 3050 therefore reached a different
    server, and the error came back from the wrong machine looking entirely
    plausible. This is a string check, not a connection, because the whole
    point is that the connection SUCCEEDS against the wrong server.
------------------------------------------------------------------------------}
procedure CheckConnectionStrings;
var
  Profile: TConnectionProfile;
  I: Integer;
begin
  WriteLn;
  WriteLn('Connection strings name their port');
  WriteLn;

  for I := 0 to High(Rig) do
  begin
    Profile := ProfileFor(Rig[I]);
    try
      Check(Pos('/' + IntToStr(Rig[I].Port) + ':', Profile.ConnectionString) > 0,
        Format('FB%d: %s', [Rig[I].Major, Profile.ConnectionString]));
    finally
      Profile.Free;
    end;
  end;
end;

{------------------------------------------------------------------------------
  CheckOlderClientNewerServer
  ----------------------------------------------------------------------------
  Attaches to Firebird 4 and 5 using the Firebird 3 client library.

  Notes:
    Firebird supports an older client against a newer server, and a machine
    with one client and several servers is the ordinary case - so this is not
    an exotic combination, it is the one a user falls into by not thinking
    about client libraries at all.

    It did not work. The attachment succeeded and the FIRST query on the new
    attachment failed with "Data type unknown", because DatabaseInfoSQL asked
    for MON$CREATION_DATE, which is TIMESTAMP on Firebird 3 and TIMESTAMP WITH
    TIME ZONE from Firebird 4, along with three other columns nothing read.
    The symptom appeared at connect time and named no column, so it read as a
    broken metadata layer rather than as one avoidable SELECT.

    This is the regression guard: the bootstrap query must stay readable by
    the oldest supported client talking to the newest supported server.
------------------------------------------------------------------------------}
procedure CheckOlderClientNewerServer;
var
  I: Integer;
  Profile: TConnectionProfile;
  Context: TDatabaseContext;
begin
  WriteLn;
  WriteLn('Firebird 3 client against newer servers');
  WriteLn;

  for I := 1 to High(Rig) do
  begin
    Profile := ProfileFor(Rig[I]);
    try
      Profile.ClientLibrary := Rig[0].ClientLibrary;
      Context := TDatabaseContext.Create(Profile, Rig[0].ClientLibrary);
      try
        try
          Context.Connect(RigPassword);
          Check(Context.Version.Major = Rig[I].Major,
            Format('FB3 client reached FB%d: %s',
              [Rig[I].Major, Context.Version.DisplayText]));
          Check(Context.SqlDialect = 3, 'and read the dialect through it');
          Context.Disconnect;
        except
          on E: Exception do
            Fail(Format('FB3 client reached FB%d - %s',
              [Rig[I].Major,
               StringReplace(Trim(E.Message), LineEnding, ' | ',
                 [rfReplaceAll])]));
        end;
      finally
        Context.Free;
      end;
    finally
      Profile.Free;
    end;
  end;
end;

{------------------------------------------------------------------------------
  CheckRefusals
  ----------------------------------------------------------------------------
  Checks that a bad attachment is reported rather than crashed on.

  Notes:
    A wrong password and a missing database are the two failures a user hits
    first. Both must come back as EIbqDatabaseError carrying the server's own
    words, because a dialog that says only "could not connect" sends people to
    the wrong place.
------------------------------------------------------------------------------}
procedure CheckRefusals;
var
  Profile: TConnectionProfile;
  Context: TDatabaseContext;
  Reported: string;
begin
  WriteLn;
  WriteLn('Refusals');
  WriteLn;

  Profile := ProfileFor(Rig[2]);
  try
    Context := TDatabaseContext.Create(Profile, Rig[2].ClientLibrary);
    try
      Reported := '';
      try
        Context.Connect('definitely-not-the-password');
      except
        on E: EIbqDatabaseError do
          Reported := E.Message;
        on E: Exception do
          Reported := E.ClassName + ': ' + E.Message;
      end;
      Check(Reported <> '', 'a wrong password is refused');
      Check(not Context.IsConnected, 'and leaves the context disconnected');
      if Reported <> '' then
      begin
        WriteLn('        ', StringReplace(Trim(Reported), LineEnding, ' | ',
          [rfReplaceAll]));
      end;
    finally
      Context.Free;
    end;
  finally
    Profile.Free;
  end;

  Profile := ProfileFor(Rig[2]);
  try
    Profile.DatabasePath := Profile.DatabasePath + '.no-such-file';
    Context := TDatabaseContext.Create(Profile, Rig[2].ClientLibrary);
    try
      Reported := '';
      try
        Context.Connect(RigPassword);
      except
        on E: Exception do
          Reported := E.Message;
      end;
      Check(Reported <> '', 'a missing database is refused');
      if Reported <> '' then
      begin
        WriteLn('        ', StringReplace(Trim(Reported), LineEnding, ' | ',
          [rfReplaceAll]));
      end;
    finally
      Context.Free;
    end;
  finally
    Profile.Free;
  end;
end;

var
  RigRoot: string;
  I: Integer;

begin
  if ParamCount >= 1 then
  begin
    RigRoot := ParamStr(1);
  end
  else
  begin
    RigRoot := DefaultRigRoot;
  end;

  WriteLn('Live connection test - rig at ', RigRoot);
  BuildRig(RigRoot);

  ReportDetectedClients;

  WriteLn;
  WriteLn('Client libraries named by a registration');
  WriteLn;
  for I := 0 to High(Rig) do
  begin
    CheckClientReadable(Rig[I]);
  end;

  for I := 0 to High(Rig) do
  begin
    CheckAttachment(Rig[I]);
    CheckFolders(Rig[I]);
  end;

  CheckConnectionStrings;
  CheckOlderClientNewerServer;
  CheckNewestThenOldest;
  CheckRefusals;

  WriteLn;
  if Failures = 0 then
  begin
    WriteLn('every live check passed');
    ExitCode := 0;
  end
  else
  begin
    WriteLn(Failures, ' check(s) failed');
    ExitCode := 1;
  end;
end.
