{==============================================================================
  Unit:        FbClientLocator
  Purpose:     Finds the Firebird client libraries installed on this machine
               and reads their versions, so a server registration can name the
               exact client to talk to that server with.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, fileinfo, winpeimagereader/elfreader

  WHY A CLIENT LIBRARY PER SERVER
  A machine can run several Firebird versions side by side, each on its own
  port, each with its own fbclient. Leaving the choice to the system search
  path means the first fbclient found wins, which on a developer's machine is
  usually the wrong one. Naming the library in the registration removes the
  guesswork.

  TWO THINGS TO KNOW
  1. A NEWER client can talk to an OLDER server. A Firebird 5 client reaches
     3.0, 4.0 and 5.0 servers. The reverse is not true: a 3.0 client cannot
     attach to a 5.0 server's newer ODS features, and its Services API is the
     3.0 one. When in doubt, point everything at the newest client installed.
  2. Whether one process can hold SEVERAL different fbclient versions at once
     depends on the database layer. This unit only finds and describes the
     libraries; see documentation/dev/building.md for what IBX actually
     supports, which must be confirmed against a real IBX build.

  Platform note: reading a version resource is Windows-specific and is confined
  to ReadClientVersion below, which falls back to parsing the path elsewhere.
==============================================================================}
unit FbClientLocator;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DynLibs, fileinfo
  // A Windows client carries a VERSIONINFO resource and winpeimagereader
  // reads it. An ELF shared object built by GCC carries none - Firebird's
  // Linux client is built that way - so no reader is registered here and
  // TFileVersionInfo is never asked about a .so. The version comes from the
  // soname instead; see VersionFromSoName.
  {$IFDEF WINDOWS}, winpeimagereader{$ENDIF};

type
  { One Firebird client library found on this machine. }
  TFbClientInfo = record
    { Full path of the library file. }
    Path: string;
    { Version as reported by the file, e.g. '5.0.4.1812', or '' if unknown. }
    VersionText: string;
    { Major and minor version, 0 when they could not be determined. }
    Major: Integer;
    Minor: Integer;
    { Text for the registration dialog's list. }
    DisplayText: string;
  end;

  TFbClientList = array of TFbClientInfo;

{ Returns the platform's client library file name: 'fbclient.dll' on Windows,
  'libfbclient.so' elsewhere. }
function DefaultClientFileName: string;

{ Reads the version of a client library.

  Parameters:
    APath       - Full path of the library.
    AInfo       - Receives path, version and display text. Always filled in,
                  even when the version could not be read.

  Returns:
    True when a version was determined, False when only the path is known. }
function ReadClientInfo(const APath: string; out AInfo: TFbClientInfo): Boolean;

{ Finds every Firebird client library in the usual places.

  Returns:
    The libraries found, newest version first, with duplicates removed. An
    empty array is a normal result on a machine with no Firebird installed. }
function DetectClients: TFbClientList;

{ Fills AList with the display text of each detected client, and puts the
  matching path in each item's Objects slot as a shared string. Convenience for
  filling a combo box.

  Parameters:
    AList    - Receives one line per client. Cleared first.
    AClients - The clients to describe. }
procedure DescribeClients(AList: TStrings; const AClients: TFbClientList);

{ Returns the client from AClients whose major version is AMajor, or the newest
  one when there is no exact match, or an empty record when AClients is empty.

  Parameters:
    AClients - The detected clients.
    AMajor   - The server major version wanted. }
function BestClientFor(const AClients: TFbClientList;
  AMajor: Integer): TFbClientInfo;

{ Loads a client library and keeps it loaded for the rest of the process.

  Parameters:
    APath - Full path of the library. An empty path, a missing file, or a
            library already pinned, all do nothing.

  WHY THIS EXISTS
  Connecting to a NEWER Firebird and then to an OLDER one crashes the process
  at exit with an access violation - after all work has completed correctly.
  Reproduced against this machine's rig:

      FB3 then FB5   exits cleanly
      FB5 then FB5   exits cleanly
      FB5 then FB3   ACCESS VIOLATION during finalisation

  The database layer asks for a library per connection and releases it when the
  connection closes, so an older client gets loaded into a process that has
  already loaded and unloaded a newer one. Something in that sequence leaves a
  pointer into an unmapped image, and it is touched at shutdown.

  Taking an extra reference that is never released keeps every client library
  mapped for the life of the process, so the dangling pointer still points at
  readable memory. Verified: with pinning, FB5 then FB3 exits 0.

  This is a workaround for a defect below us, not a design. It costs a few
  megabytes of address space per distinct client actually used - libraries are
  pinned on first use, not all at startup. }
procedure PinClientLibrary(const APath: string);

implementation

var
  { Paths already pinned. Holds the library handles only to make it obvious
    they are deliberately never freed. }
  PinnedLibraries: TStringList = nil;

const
  { Directories searched for a client library, in order of preference. The
    application's own directory comes first so a portable install that ships
    its own Firebird wins over anything on the machine. }
  {$IFDEF WINDOWS}
  SearchRoots: array[0..3] of string = (
    'C:\firebird',
    'C:\Firebird',
    'C:\Program Files\Firebird',
    'C:\Program Files (x86)\Firebird'
  );
  {$ELSE}
  SearchRoots: array[0..4] of string = (
    '/opt/firebird',
    '/opt/firebird/lib',
    '/usr/lib/x86_64-linux-gnu',
    '/usr/local/lib',
    '/usr/lib'
  );
  {$ENDIF}

{------------------------------------------------------------------------------
  DefaultClientFileName
  ----------------------------------------------------------------------------
  Returns the platform's client library file name.
------------------------------------------------------------------------------}
function DefaultClientFileName: string;
begin
  {$IFDEF WINDOWS}
  Result := 'fbclient.dll';
  {$ELSE}
  Result := 'libfbclient.so';
  {$ENDIF}
end;

{------------------------------------------------------------------------------
  VersionFromPath
  ----------------------------------------------------------------------------
  Guesses a version from the directory a library sits in.

  Parameters:
    APath  - Full path of the library.
    AMajor - Receives the major version, or 0.
    AMinor - Receives the minor version, or 0.

  Notes:
    Handles the two layouts that actually occur: a side-by-side rig using
    FB3 / FB4 / FB5 folder names, and the Windows installer's Firebird_3_0.
    Used only when the file itself carries no version, which is the normal case
    for a shared object on Linux.

    A Unix install puts the library one level deeper than a Windows one -
    <root>/lib/libfbclient.so against <root>\fbclient.dll - so a parent folder
    called 'lib' or 'bin' is stepped over rather than parsed. Without that the
    version of every Linux client reads as 0, and the registration dialog
    offers a list of libraries it cannot tell apart.
------------------------------------------------------------------------------}
procedure VersionFromPath(const APath: string; out AMajor, AMinor: Integer);
var
  Folder, Parent: string;
  I: Integer;
  Digits: string;
begin
  AMajor := 0;
  AMinor := 0;

  Parent := ExcludeTrailingPathDelimiter(ExtractFilePath(APath));
  Folder := UpperCase(ExtractFileName(Parent));

  if (Folder = 'LIB') or (Folder = 'LIB64') or (Folder = 'BIN') then
  begin
    Folder := UpperCase(ExtractFileName(ExcludeTrailingPathDelimiter(
      ExtractFilePath(Parent))));
  end;

  // 'FIREBIRD_3_0' -> 3.0
  if Pos('FIREBIRD_', Folder) = 1 then
  begin
    Digits := Copy(Folder, Length('FIREBIRD_') + 1, MaxInt);
    AMajor := StrToIntDef(Copy(Digits, 1, 1), 0);
    if Length(Digits) >= 3 then
      AMinor := StrToIntDef(Copy(Digits, 3, 1), 0);
    Exit;
  end;

  // 'FB5' -> 5.0
  if (Pos('FB', Folder) = 1) and (Length(Folder) >= 3) then
  begin
    Digits := '';
    for I := 3 to Length(Folder) do
    begin
      if Folder[I] in ['0'..'9'] then
        Digits := Digits + Folder[I]
      else
        Break;
    end;
    AMajor := StrToIntDef(Digits, 0);
  end;
end;

{------------------------------------------------------------------------------
  CanCarryVersionResource
  ----------------------------------------------------------------------------
  Returns True when a file of this name could hold a Windows version resource.

  Parameters:
    APath - Full path of the library.

  Returns:
    True for '.dll' and '.exe', False for anything else.

  Notes:
    This exists to stop TFileVersionInfo being called when the answer is known
    in advance. Asked about a file it has no reader for, it RAISES - and for a
    Linux client that is every single call, because the name is either
    'libfbclient.so' or, worse, 'libfbclient.so.3.0.14', whose extension reads
    as '.14'. The raise was caught and the fallback was correct, so the program
    behaved; but PASCAL-LAZARUS-RULES.md §9 forbids exceptions as normal
    control flow, and anyone running under the debugger got an exception
    notification every time the registration dialog or the server properties
    dialog listed a client library.
------------------------------------------------------------------------------}
function CanCarryVersionResource(const APath: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  Result := (Ext = '.dll') or (Ext = '.exe');
end;


{------------------------------------------------------------------------------
  NumericTail
  ----------------------------------------------------------------------------
  Reads the version out of a versioned shared-object file name.

  Parameters:
    AName - File name alone, e.g. 'libfbclient.so.3.0.14'.
    ATail - Receives '3.0.14', or '' when the name carries no version.

  Returns:
    True when a version of at least three numeric parts follows '.so.'.

  Notes:
    Three parts, not one: 'libfbclient.so.2' is the soname, and 2 is the API
    generation, not the product version. Reporting Firebird 2 for a Firebird 5
    client would be worse than reporting nothing.
------------------------------------------------------------------------------}
function NumericTail(const AName: string; out ATail: string): Boolean;
var
  P, Parts, I: Integer;
  Suffix: string;
begin
  Result := False;
  ATail := '';

  P := Pos('.so.', LowerCase(AName));
  if P = 0 then
    Exit;

  Suffix := Copy(AName, P + Length('.so.'), MaxInt);
  if Suffix = '' then
    Exit;

  Parts := 1;
  for I := 1 to Length(Suffix) do
  begin
    if Suffix[I] = '.' then
      Inc(Parts)
    else if not (Suffix[I] in ['0'..'9']) then
      Exit;
  end;

  if Parts < 3 then
    Exit;

  ATail := Suffix;
  Result := True;
end;

{------------------------------------------------------------------------------
  VersionFromSoName
  ----------------------------------------------------------------------------
  Reads the version from a versioned shared-object name beside the library.

  Parameters:
    APath - Full path of the library, e.g. /opt/fb5/lib/libfbclient.so.
    AText - Receives '5.0.4', or '' when no versioned name is present.

  Notes:
    A Linux shared object carries no version resource, but it is almost always
    a symlink to one that spells the version out: libfbclient.so points at
    libfbclient.so.5.0.4 beside it. That name is the authoritative answer and
    it is free, so it is asked before falling back to guessing from the folder
    name - which only works for a rig laid out as fb3/ fb4/ fb5/ and says
    nothing about the patch level.

    The directory is scanned rather than the symlink resolved, so this also
    works when the library is a real file with a versioned sibling, and needs
    no platform unit. A suffix of at least three numeric parts is required:
    libfbclient.so.2 is a soname carrying the API version, not the product's.

    APath ITSELF is checked first, because a registration may name the
    versioned file rather than the symlink - the file picker offers both, and
    'libfbclient.so.3.0.14' is the one that looks most specific to a user
    choosing from a list. In that case the version is already in front of us
    and no directory scan is needed.
------------------------------------------------------------------------------}
procedure VersionFromSoName(const APath: string; out AText: string);
var
  Search: TSearchRec;
  Folder, Base, Suffix, Best: string;
  Parts, BestParts, I: Integer;
  Numeric: Boolean;
begin
  AText := '';
  Best := '';
  BestParts := 0;

  // the registration may name the versioned file itself
  if NumericTail(ExtractFileName(APath), Suffix) then
  begin
    AText := Suffix;
    Exit;
  end;

  Folder := IncludeTrailingPathDelimiter(ExtractFilePath(APath));
  Base := ExtractFileName(APath);

  if FindFirst(Folder + Base + '.*', faAnyFile, Search) <> 0 then
    Exit;
  try
    repeat
      Suffix := Copy(Search.Name, Length(Base) + 2, MaxInt);
      if Suffix = '' then
        Continue;

      Parts := 1;
      Numeric := True;
      for I := 1 to Length(Suffix) do
      begin
        if Suffix[I] = '.' then
          Inc(Parts)
        else if not (Suffix[I] in ['0'..'9']) then
        begin
          Numeric := False;
          Break;
        end;
      end;

      if Numeric and (Parts >= 3) and (Parts > BestParts) then
      begin
        Best := Suffix;
        BestParts := Parts;
      end;
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;

  AText := Best;
end;

{------------------------------------------------------------------------------
  ReadClientInfo
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Three sources, in decreasing order of authority: a Windows version
    resource, a versioned soname, and the folder the library sits in. The
    first is only attempted for a file that could carry one - see
    CanCarryVersionResource - because TFileVersionInfo raises when asked about
    anything else, and on Linux that would be every call.
------------------------------------------------------------------------------}
function ReadClientInfo(const APath: string; out AInfo: TFbClientInfo): Boolean;
var
  Reader: TFileVersionInfo;
  Text, SoName: string;
  Major, Minor: Integer;
begin
  AInfo := Default(TFbClientInfo);
  AInfo.Path := APath;
  Text := '';

  if CanCarryVersionResource(APath) then
  begin
    Reader := TFileVersionInfo.Create(nil);
    try
      try
        Reader.FileName := APath;
        Reader.ReadFileInfo;
        Text := Trim(Reader.VersionStrings.Values['ProductVersion']);
        if Text = '' then
          Text := Trim(Reader.VersionStrings.Values['FileVersion']);
      except
        // a .dll with no version resource, or a malformed one: not an error,
        // fall back to the name and the path below
        Text := '';
      end;
    finally
      Reader.Free;
    end;
  end;

  // 'WI-V5.0.4.1812' -> '5.0.4.1812'
  if (Length(Text) > 5) and (Copy(UpperCase(Text), 1, 4) = 'WI-V') then
    Text := Copy(Text, 5, MaxInt);

  AInfo.VersionText := Text;

  Major := 0;
  Minor := 0;
  if Text <> '' then
  begin
    Major := StrToIntDef(Copy(Text, 1, Pos('.', Text) - 1), 0);
    if Major > 0 then
      Minor := StrToIntDef(Copy(Text, Pos('.', Text) + 1, 1), 0);
  end;

  if Major = 0 then
  begin
    // a Linux client has no version resource but usually has a versioned
    // soname beside it, which is exact where the folder name is a guess
    VersionFromSoName(APath, SoName);
    if SoName <> '' then
    begin
      AInfo.VersionText := SoName;
      Major := StrToIntDef(Copy(SoName, 1, Pos('.', SoName) - 1), 0);
      if Major > 0 then
        Minor := StrToIntDef(Copy(SoName, Pos('.', SoName) + 1, 1), 0);
    end;
  end;

  if Major = 0 then
    VersionFromPath(APath, Major, Minor);

  AInfo.Major := Major;
  AInfo.Minor := Minor;

  if AInfo.VersionText <> '' then
    AInfo.DisplayText := Format('Firebird %s  -  %s', [AInfo.VersionText, APath])
  else if Major > 0 then
    AInfo.DisplayText := Format('Firebird %d.%d  -  %s', [Major, Minor, APath])
  else
    AInfo.DisplayText := APath;

  Result := Major > 0;
end;

{------------------------------------------------------------------------------
  AppendIfClient
  ----------------------------------------------------------------------------
  Adds one candidate path to the result when it exists and is not already held.

  Parameters:
    AResult - The list being built.
    APath   - Candidate full path.
------------------------------------------------------------------------------}
procedure AppendIfClient(var AResult: TFbClientList; const APath: string);
var
  I: Integer;
  Info: TFbClientInfo;
begin
  if not FileExists(APath) then
    Exit;

  for I := 0 to High(AResult) do
  begin
    if SameText(AResult[I].Path, APath) then
      Exit;
  end;

  ReadClientInfo(APath, Info);
  SetLength(AResult, Length(AResult) + 1);
  AResult[High(AResult)] := Info;
end;

{------------------------------------------------------------------------------
  ScanRoot
  ----------------------------------------------------------------------------
  Looks for a client library directly in a directory and one level below it.

  Parameters:
    AResult - The list being built.
    ARoot   - Directory to search.

  Notes:
    One level is enough for every layout that occurs in practice:
    C:\firebird\FB5\fbclient.dll, C:\Program Files\Firebird\Firebird_3_0\
    fbclient.dll, and /opt/firebird/lib/libfbclient.so. Recursing further would
    mostly find copies inside backup and example folders.

    A subdirectory's own lib/ is probed as well, because that is where a Unix
    install puts the library: the side-by-side rig that reads
    C:\firebird\FB5\fbclient.dll on Windows reads
    /opt/firebird/fb5/lib/libfbclient.so here. Without it, detection on Linux
    finds a single packaged install and nothing else, which makes the choice
    of client library - the thing a registration exists to pin down - a path
    the user has to type from memory.
------------------------------------------------------------------------------}
procedure ScanRoot(var AResult: TFbClientList; const ARoot: string);
var
  Root, FileName: string;
  Search: TSearchRec;
begin
  if not DirectoryExists(ARoot) then
    Exit;

  Root := IncludeTrailingPathDelimiter(ARoot);
  FileName := DefaultClientFileName;

  AppendIfClient(AResult, Root + FileName);

  if FindFirst(Root + '*', faDirectory, Search) = 0 then
  begin
    try
      repeat
        if ((Search.Attr and faDirectory) <> 0) and (Search.Name <> '.') and
           (Search.Name <> '..') then
        begin
          AppendIfClient(AResult,
            Root + Search.Name + PathDelim + FileName);
          AppendIfClient(AResult,
            Root + Search.Name + PathDelim + 'lib' + PathDelim + FileName);
        end;
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
  end;
end;

{------------------------------------------------------------------------------
  SortByVersionDescending
  ----------------------------------------------------------------------------
  Puts the newest client first.

  Parameters:
    AList - The list to sort in place.

  Notes:
    A plain insertion sort: the list has single digits of entries, and the
    order must be stable so that two clients of the same version keep the
    search order, which puts the application's own directory first.
------------------------------------------------------------------------------}
procedure SortByVersionDescending(var AList: TFbClientList);
var
  I, J: Integer;
  Item: TFbClientInfo;
begin
  for I := 1 to High(AList) do
  begin
    Item := AList[I];
    J := I - 1;
    while (J >= 0) and
          ((AList[J].Major < Item.Major) or
           ((AList[J].Major = Item.Major) and (AList[J].Minor < Item.Minor))) do
    begin
      AList[J + 1] := AList[J];
      Dec(J);
    end;
    AList[J + 1] := Item;
  end;
end;

{------------------------------------------------------------------------------
  DetectClients
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function DetectClients: TFbClientList;
var
  I: Integer;
begin
  Result := nil;

  // the application's own directory first: a portable install that ships its
  // own Firebird must win over anything else on the machine
  ScanRoot(Result, ExtractFilePath(ParamStr(0)));

  for I := Low(SearchRoots) to High(SearchRoots) do
    ScanRoot(Result, SearchRoots[I]);

  SortByVersionDescending(Result);
end;

{------------------------------------------------------------------------------
  DescribeClients
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure DescribeClients(AList: TStrings; const AClients: TFbClientList);
var
  I: Integer;
begin
  AList.Clear;
  for I := Low(AClients) to High(AClients) do
    AList.Add(AClients[I].DisplayText);
end;

{------------------------------------------------------------------------------
  BestClientFor
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Prefers an exact major-version match, because a registration that names a
    server's own client is the least surprising default. Falls back to the
    newest available, which can always reach an older server.
------------------------------------------------------------------------------}
function BestClientFor(const AClients: TFbClientList;
  AMajor: Integer): TFbClientInfo;
var
  I: Integer;
begin
  Result := Default(TFbClientInfo);
  if Length(AClients) = 0 then
    Exit;

  for I := Low(AClients) to High(AClients) do
  begin
    if AClients[I].Major = AMajor then
      Exit(AClients[I]);
  end;

  Result := AClients[0];      // sorted newest first
end;

{------------------------------------------------------------------------------
  PinClientLibrary
  ----------------------------------------------------------------------------
  See the interface section for the description, including why this is needed.

  Parameters:
    APath - Full path of the client library.

  Notes:
    The handle is never passed to UnloadLibrary. That is the entire point, and
    it is why this routine keeps its own list rather than reusing anything that
    might tidy up after itself.
------------------------------------------------------------------------------}
procedure PinClientLibrary(const APath: string);
var
  Handle: TLibHandle;
begin
  if Trim(APath) = '' then
    Exit;
  if not FileExists(APath) then
    Exit;

  if PinnedLibraries = nil then
  begin
    PinnedLibraries := TStringList.Create;
    PinnedLibraries.CaseSensitive := False;
    PinnedLibraries.Sorted := True;
    PinnedLibraries.Duplicates := dupIgnore;
  end;

  if PinnedLibraries.IndexOf(APath) >= 0 then
    Exit;

  Handle := LoadLibrary(APath);
  if Handle = NilHandle then
    Exit;      // the database layer will report the real failure when it tries

  PinnedLibraries.AddObject(APath, TObject(PtrInt(Handle)));
end;

finalization
  { The list is freed; the libraries in it are deliberately NOT unloaded. }
  FreeAndNil(PinnedLibraries);

end.