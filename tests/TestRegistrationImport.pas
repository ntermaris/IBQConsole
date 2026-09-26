{==============================================================================
  Program:     TestRegistrationImport
  Purpose:     Checks that FlameRobin registrations are read correctly, that
               passwords are never carried across, and that importing twice
               does not duplicate or overwrite anything.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21

  Why this exists: the importer reads another program's private file format,
  worked out by reading FlameRobin's Root::save(). Nothing warns us if that
  reading is wrong - a mistake shows up as an import that silently produces
  nothing, or worse, as a password copied into our own configuration. Both are
  cheap to test against a file written here and expensive to notice in the
  field.

  The IBConsole half cannot be tested this way: it reads the Windows registry
  by a fixed key, and writing to HKCU to test it would do to the user's
  machine exactly what the importer promises never to do.
==============================================================================}
program TestRegistrationImport;
{$mode objfpc}{$H+}
uses SysUtils, Classes,
     RegistrationStore, RegistrationImporter, ServerRegistration,
     ConnectionProfile;

var
  Failures: Integer;
  WorkDir: string;

{ Reports a failed expectation. }
procedure Fail(const AWhat: string);
begin
  WriteLn('  FAIL  ', AWhat);
  Inc(Failures);
end;

{ Checks a condition and reports it either way. }
procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    WriteLn('  ok    ', AWhat)
  else
    Fail(AWhat);
end;

{ Writes a FlameRobin registration file with two servers, three databases and
  a password that must not survive the import. }
procedure WriteFlameRobinFile(const APath: string);
var
  F: TStringList;
begin
  F := TStringList.Create;
  try
    F.Add('<?xml version="1.0" encoding="UTF-8"?>');
    F.Add('<root>');
    F.Add('  <nextId>7</nextId>');
    F.Add('  <server>');
    F.Add('    <name>Production</name>');
    F.Add('    <host>db.example.com</host>');
    F.Add('    <port>3051</port>');
    F.Add('    <database>');
    F.Add('      <id>1</id>');
    F.Add('      <name>Ledger</name>');
    F.Add('      <path>/var/fb/ledger.fdb</path>');
    F.Add('      <charset>UTF8</charset>');
    F.Add('      <username>SYSDBA</username>');
    F.Add('      <password>masterkey</password>');
    F.Add('      <role>ADMINROLE</role>');
    F.Add('      <fbclient>/opt/fb5/lib/libfbclient.so</fbclient>');
    F.Add('    </database>');
    F.Add('    <database>');
    F.Add('      <id>2</id>');
    F.Add('      <name>Archive</name>');
    F.Add('      <path>/var/fb/archive.fdb</path>');
    F.Add('      <charset>WIN1252</charset>');
    F.Add('      <username>ARCHIVER</username>');
    F.Add('      <password>hunter2</password>');
    F.Add('    </database>');
    F.Add('  </server>');
    F.Add('  <server>');
    F.Add('    <name>Local</name>');
    F.Add('    <host></host>');
    F.Add('    <port></port>');
    F.Add('    <database>');
    F.Add('      <id>3</id>');
    F.Add('      <path>C:\data\scratch.fdb</path>');
    F.Add('    </database>');
    F.Add('  </server>');
    F.Add('</root>');
    F.SaveToFile(APath);
  finally
    F.Free;
  end;
end;

{ Returns the candidate for the named database, or raises when absent. }
function FindDatabase(const ACandidates: TImportCandidateArray;
  const AName: string): TImportCandidate;
var
  I: Integer;
begin
  for I := 0 to High(ACandidates) do
    if (not ACandidates[I].IsServer) and (ACandidates[I].DatabaseName = AName) then
      Exit(ACandidates[I]);
  raise Exception.CreateFmt('no candidate named %s', [AName]);
end;

{ Counts the candidates that are databases. }
function DatabaseCount(const ACandidates: TImportCandidateArray): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(ACandidates) do
    if not ACandidates[I].IsServer then
      Inc(Result);
end;

{ Reads back every profile the store holds, across all its servers. }
function StoredProfileCount(AStore: TRegistrationStore): Integer;
var
  S: Integer;
begin
  Result := 0;
  for S := 0 to AStore.ServerCount - 1 do
    Inc(Result, AStore.Servers[S].DatabaseCount);
end;

var
  Store: TRegistrationStore;
  Importer: TRegistrationImporter;
  Candidates: TImportCandidateArray;
  Cand: TImportCandidate;
  ConfPath: string;
  Imported: Integer;
  Server: TServerRegistration;
  Profile: TConnectionProfile;
  I: Integer;
  SawPassword: Boolean;

begin
  Failures := 0;
  WriteLn('Registration import');
  WriteLn;

  WorkDir := IncludeTrailingPathDelimiter(GetTempDir) +
    'ibq_import_test' + PathDelim;
  ForceDirectories(WorkDir);
  ConfPath := WorkDir + 'fr_databases.conf';
  WriteFlameRobinFile(ConfPath);

  Store := TRegistrationStore.Create;
  Importer := nil;
  try
    { A store of our own in the temp directory, so the real registration file
      is never touched by the test. }
    Store.FileName := WorkDir + 'registrations.xml';
    if FileExists(Store.FileName) then
      DeleteFile(Store.FileName);
    Store.Clear;

    Importer := TRegistrationImporter.Create(Store);
    Importer.FlameRobinPath := ConfPath;
    Candidates := Importer.Scan;

    Check(DatabaseCount(Candidates) = 3,
      Format('three databases found (got %d)', [DatabaseCount(Candidates)]));

    Cand := FindDatabase(Candidates, 'Ledger');
    Check(Cand.DatabasePath = '/var/fb/ledger.fdb', 'path read');
    Check(Cand.CharacterSet = 'UTF8', 'charset read');
    Check(Cand.UserName = 'SYSDBA', 'username read');
    Check(Cand.Role = 'ADMINROLE', 'role read');
    Check(Cand.ClientLibrary = '/opt/fb5/lib/libfbclient.so',
      'client library read');
    Check(Cand.Host = 'db.example.com', 'host inherited from server');
    Check(Cand.Port = 3051, 'port inherited from server');
    Check(Cand.Mode = cmRemote, 'remote mode for a server with a host');

    { A database with no <name> falls back to the file name. }
    Cand := FindDatabase(Candidates, 'scratch.fdb');
    Check(Cand.DatabasePath = 'C:\data\scratch.fdb', 'unnamed database path');
    Check(Cand.Mode = cmLocal, 'local mode for a server with no host');
    Check(Cand.Port = 3050, 'default port when the file gives none');

    Imported := Importer.Import(Candidates);
    Check(Imported = 3, Format('three databases imported (got %d)',
      [Imported]));
    Check(Store.ServerCount = 2,
      Format('two servers created (got %d)', [Store.ServerCount]));
    Check(StoredProfileCount(Store) = 3, 'three profiles stored');

    { The whole point: no password anywhere in the store. }
    SawPassword := False;
    for I := 0 to Store.ServerCount - 1 do
    begin
      Server := Store.Servers[I];
      for Imported := 0 to Server.DatabaseCount - 1 do
      begin
        Profile := Server.Databases[Imported];
        if Profile.Password <> '' then
          SawPassword := True;
      end;
    end;
    Check(not SawPassword, 'no password was imported');

    { Scanning again must see everything as already registered, and importing
      again must add nothing. }
    Candidates := Importer.Scan;
    SawPassword := False;      // reused as "saw an importable candidate"
    for I := 0 to High(Candidates) do
      if Candidates[I].Skip = '' then
        SawPassword := True;
    Check(not SawPassword, 'a second scan marks everything already registered');

    Imported := Importer.Import(Candidates);
    Check(Imported = 0, Format('a second import adds nothing (got %d)',
      [Imported]));
    Check(StoredProfileCount(Store) = 3, 'still three profiles after re-import');

    { A file that is not XML at all must be skipped, not raised. }
    Importer.FlameRobinPath := WorkDir + 'broken.conf';
    with TStringList.Create do
    try
      Add('this is not xml');
      SaveToFile(WorkDir + 'broken.conf');
    finally
      Free;
    end;
    try
      Candidates := Importer.Scan;
      Check(DatabaseCount(Candidates) = 0,
        'a malformed file yields nothing and does not raise');
    except
      on E: Exception do
        Fail('a malformed file raised ' + E.ClassName);
    end;

    { A path that does not exist is the ordinary case on most machines. }
    Importer.FlameRobinPath := WorkDir + 'absent.conf';
    Candidates := Importer.Scan;
    Check(DatabaseCount(Candidates) = 0, 'a missing file yields nothing');

  finally
    Importer.Free;
    Store.Free;
  end;

  WriteLn;
  if Failures = 0 then
    WriteLn('all registration import checks passed')
  else
  begin
    WriteLn(Failures, ' check(s) failed');
    Halt(1);
  end;
end.
