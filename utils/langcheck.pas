{==============================================================================
  Program:     langcheck
  Purpose:     Compares the LangStr keys the program actually asks for against
               the keys a language file supplies, and reports both gaps.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21

  Why this exists: a missing key is invisible. LangStr falls back to the
  English text compiled into the call, which is exactly the right behaviour at
  run time and exactly the wrong behaviour when you are trying to find out how
  much of a translation is done - the program looks finished and is not. A key
  that no longer exists is invisible for the opposite reason: nothing ever
  reads it, so nothing ever complains, and the file grows a tail of dead
  entries that later translators dutifully translate.

  Usage:
    langcheck <language-file> [source-root] [--list] [--dynamic <prefix>]

    langcheck lang/Greek.lng
    langcheck lang/Greek.lng . --list
    langcheck lang/Greek.lng . --dynamic node.

  Exit code 0 when every key the source asks for is present, 1 otherwise, so
  it can gate a release build. Keys present but unused are reported and do NOT
  fail the run: they are untidy rather than broken, and a translator part-way
  through a rename should not be blocked by them.

  The scanner is deliberately literal. It finds LangStr( and LangStrFormat(
  and reads the first string literal after the bracket, handling Pascal's
  doubled-apostrophe escape. It does not evaluate expressions: a key built at
  run time cannot be checked by reading the source, and this reports what it
  can see rather than pretending to more.

  Some keys ARE built at run time and are perfectly real - the node.* captions
  come from NodeCaptionKey, one per object kind. --dynamic names a prefix whose
  keys are known to be built that way, so that supplying them is not reported
  as waste. It does not make them checkable: nothing here can tell whether the
  set is complete, only that what is there was meant.
==============================================================================}
program langcheck;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes;

var
  UsedKeys: TStringList;
  FileKeys: TStringList;
  ShowList: Boolean;
  DynamicPrefixes: TStringList;

{ Returns True when AText has APattern at position APos, ignoring case. }
function MatchesAt(const AText, APattern: string; APos: Integer): Boolean;
begin
  Result := (APos > 0) and (APos + Length(APattern) - 1 <= Length(AText)) and
    SameText(Copy(AText, APos, Length(APattern)), APattern);
end;

{ Returns True when the character before APos cannot be part of an identifier,
  so that LangStr is found but MyLangStr is not. }
function StartsWord(const AText: string; APos: Integer): Boolean;
begin
  if APos <= 1 then
    Exit(True);
  Result := not (AText[APos - 1] in
    ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']);
end;

{ Reads the Pascal string literal starting at APos, which must be an
  apostrophe, and advances APos past it. Doubled apostrophes become one. }
function ReadLiteral(const AText: string; var APos: Integer): string;
begin
  Result := '';
  if (APos > Length(AText)) or (AText[APos] <> '''') then
    Exit;
  Inc(APos);
  while APos <= Length(AText) do
  begin
    if AText[APos] = '''' then
    begin
      if (APos < Length(AText)) and (AText[APos + 1] = '''') then
      begin
        Result := Result + '''';
        Inc(APos, 2);
        Continue;
      end;
      Inc(APos);
      Exit;
    end;
    Result := Result + AText[APos];
    Inc(APos);
  end;
end;

{ Returns True when AKey starts with one of the prefixes named by --dynamic,
  meaning it is built at run time and supplying it is not waste. }
function HasDynamicPrefix(const AKey: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if DynamicPrefixes = nil then
    Exit;
  for I := 0 to DynamicPrefixes.Count - 1 do
    if (DynamicPrefixes[I] <> '') and
       SameText(Copy(AKey, 1, Length(DynamicPrefixes[I])),
         DynamicPrefixes[I]) then
      Exit(True);
end;

{ Records every key one source file asks for. }
procedure ScanSource(const AFileName: string);
var
  Source: string;
  Stream: TStringList;
  P: Integer;
  Key: string;

  { Advances P past spaces and line breaks. }
  procedure SkipBlanks;
  begin
    while (P <= Length(Source)) and (Source[P] in [' ', #9, #10, #13]) do
      Inc(P);
  end;

begin
  Stream := TStringList.Create;
  try
    Stream.LoadFromFile(AFileName);
    Source := Stream.Text;
  finally
    Stream.Free;
  end;

  P := 1;
  while P <= Length(Source) do
  begin
    if (Source[P] in ['L', 'l']) and StartsWord(Source, P) and
       (MatchesAt(Source, 'LangStrFormat', P) or
        MatchesAt(Source, 'LangStr', P)) then
    begin
      if MatchesAt(Source, 'LangStrFormat', P) then
        Inc(P, Length('LangStrFormat'))
      else
        Inc(P, Length('LangStr'));

      SkipBlanks;
      if (P <= Length(Source)) and (Source[P] = '(') then
      begin
        Inc(P);
        SkipBlanks;
        if (P <= Length(Source)) and (Source[P] = '''') then
        begin
          Key := ReadLiteral(Source, P);
          if (Key <> '') and (UsedKeys.IndexOf(Key) < 0) then
            UsedKeys.Add(Key);
        end;
      end;
      Continue;
    end;
    Inc(P);
  end;
end;

{ Records every key a language file supplies. }
procedure ScanLanguageFile(const AFileName: string);
var
  Lines: TStringList;
  I, Eq: Integer;
  Line, Key: string;
begin
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(AFileName);
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line[1] = ';') or (Line[1] = '[') then
        Continue;
      Eq := Pos('=', Line);
      if Eq <= 1 then
        Continue;
      Key := Trim(Copy(Line, 1, Eq - 1));
      { The section keys are settings, not translated strings. }
      if SameText(Key, 'LangID') or SameText(Key, 'DialogFontName') or
         SameText(Key, 'DialogFontSize') then
        Continue;
      if FileKeys.IndexOf(Key) < 0 then
        FileKeys.Add(Key);
    end;
  finally
    Lines.Free;
  end;
end;

{ Scans every .pas and .lpr under a directory. }
procedure ScanTree(const ARoot: string);
var
  Search: TSearchRec;
  Path: string;
begin
  Path := IncludeTrailingPathDelimiter(ARoot);

  if FindFirst(Path + '*', faAnyFile, Search) = 0 then
  begin
    try
      repeat
        if (Search.Name = '.') or (Search.Name = '..') then
          Continue;
        if (Search.Attr and faDirectory) <> 0 then
        begin
          { lib and bin hold build output: the same sources compiled, which
            would double every count.

            tests and utils are skipped because they are not the shipped
            interface. A test deliberately asks for a key that no file
            supplies, to prove the fallback works; counting that as a
            missing translation would make a passing test look like an
            untranslated program. }
          if SameText(Search.Name, 'lib') or SameText(Search.Name, 'bin') or
             SameText(Search.Name, 'backup') or
             SameText(Search.Name, 'tests') or
             SameText(Search.Name, 'utils') then
            Continue;
          ScanTree(Path + Search.Name);
        end
        else if SameText(ExtractFileExt(Search.Name), '.pas') or
                SameText(ExtractFileExt(Search.Name), '.lpr') then
        begin
          ScanSource(Path + Search.Name);
        end;
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
  end;
end;

var
  LangFile: string;
  Root: string;
  I: Integer;
  Missing: TStringList;
  Unused: TStringList;

begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: langcheck <language-file> [source-root] [--list]');
    Halt(2);
  end;

  LangFile := ParamStr(1);
  Root := '.';
  ShowList := False;
  UsedKeys := TStringList.Create;
  FileKeys := TStringList.Create;
  DynamicPrefixes := TStringList.Create;
  I := 2;
  while I <= ParamCount do
  begin
    if SameText(ParamStr(I), '--list') then
      ShowList := True
    else if SameText(ParamStr(I), '--dynamic') and (I < ParamCount) then
    begin
      Inc(I);
      DynamicPrefixes.Add(ParamStr(I));
    end
    else
      Root := ParamStr(I);
    Inc(I);
  end;

  if not FileExists(LangFile) then
  begin
    WriteLn('no such language file: ', LangFile);
    Halt(2);
  end;

  Missing := TStringList.Create;
  Unused := TStringList.Create;
  try
    UsedKeys.Sorted := False;
    ScanTree(Root);
    ScanLanguageFile(LangFile);

    UsedKeys.Sort;
    FileKeys.Sort;

    for I := 0 to UsedKeys.Count - 1 do
      if FileKeys.IndexOf(UsedKeys[I]) < 0 then
        Missing.Add(UsedKeys[I]);

    for I := 0 to FileKeys.Count - 1 do
      if (UsedKeys.IndexOf(FileKeys[I]) < 0) and
         not HasDynamicPrefix(FileKeys[I]) then
        Unused.Add(FileKeys[I]);

    WriteLn(Format('%s', [LangFile]));
    WriteLn(Format('  %d key(s) asked for by the program', [UsedKeys.Count]));
    WriteLn(Format('  %d key(s) supplied by the file', [FileKeys.Count]));
    WriteLn(Format('  %d missing, %d supplied but never asked for',
      [Missing.Count, Unused.Count]));

    if ShowList then
    begin
      if Missing.Count > 0 then
      begin
        WriteLn;
        WriteLn('missing:');
        for I := 0 to Missing.Count - 1 do
          WriteLn('  ', Missing[I]);
      end;
      if Unused.Count > 0 then
      begin
        WriteLn;
        WriteLn('supplied but never asked for:');
        for I := 0 to Unused.Count - 1 do
          WriteLn('  ', Unused[I]);
      end;
    end;

    WriteLn;
    if Missing.Count = 0 then
    begin
      WriteLn('every key the program asks for is translated');
    end
    else
    begin
      WriteLn(Missing.Count, ' key(s) fall back to English');
      Halt(1);
    end;
  finally
    Unused.Free;
    Missing.Free;
    DynamicPrefixes.Free;
    FileKeys.Free;
    UsedKeys.Free;
  end;
end.
