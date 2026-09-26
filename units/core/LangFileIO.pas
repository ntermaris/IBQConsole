{==============================================================================
  Unit:        LangFileIO
  Purpose:     Byte-safe reading and updating of the [Strings] section of a
               .lng language file. Used by the translation editor and by the
               key-extraction utility. Everything the routines do not change -
               BOM, line endings, comments, other sections, untouched keys - is
               preserved exactly, so a translator's file never gets reformatted
               behind their back.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils
  Origin:      Ported from Teramon's units/langfileio.pas.

  Note: reading for display goes through LanguageHandle.LangStr, which caches.
  This unit is for editing files, not for looking strings up at runtime.
==============================================================================}
unit LangFileIO;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { One key/value pair from the [Strings] section. }
  TLangEntry = record
    Key: string;
    Value: string;
  end;

  TLangEntries = array of TLangEntry;

{ Reads the key/value pairs of the [Strings] section of APath, in file order.

  Parameters:
    APath - Full path of the .lng file.

  Returns:
    The entries found. An empty array when the file or the section is missing.

  Notes:
    Splits on the FIRST '=' so a value may contain further '=' characters.
    Blank lines and ';' comment lines are skipped. }
function ReadLangStrings(const APath: string): TLangEntries;

{ Writes changes back into the [Strings] section of APath.

  Parameters:
    APath    - Full path of the .lng file.
    AChanges - Entries to write. An existing key (matched case-insensitively)
               has its line replaced; a new key is appended at the end of the
               [Strings] section.

  Notes:
    Does nothing when AChanges is empty. Creates a [Strings] section when the
    file has none. Every other byte of the file is preserved. }
procedure UpdateLangStrings(const APath: string; const AChanges: TLangEntries);

implementation

{------------------------------------------------------------------------------
  ReadBytes
  ----------------------------------------------------------------------------
  Reads a whole file into a byte array.

  Parameters:
    APath - File to read.

  Returns:
    The file's bytes; empty when the file is empty.

  Raises:
    EFOpenError - The file cannot be opened.
------------------------------------------------------------------------------}
function ReadBytes(const APath: string): TBytes;
var
  Stream: TFileStream;
begin
  Result := nil;
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[0], Stream.Size);
  finally
    Stream.Free;
  end;
end;

{------------------------------------------------------------------------------
  WriteBytes
  ----------------------------------------------------------------------------
  Replaces a file's contents with the given bytes.

  Parameters:
    APath  - File to write.
    ABytes - Contents to write.
------------------------------------------------------------------------------}
procedure WriteBytes(const APath: string; const ABytes: TBytes);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(APath, fmCreate);
  try
    if Length(ABytes) > 0 then
      Stream.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    Stream.Free;
  end;
end;

{------------------------------------------------------------------------------
  DecodeFile
  ----------------------------------------------------------------------------
  Loads a .lng file as lines, remembering how it was encoded.

  Parameters:
    APath   - File to read.
    AHadBom - Receives True when the file started with a UTF-8 BOM.
    ANewLine - Receives the file's line ending, CR/LF or LF.

  Returns:
    The file's lines. Caller frees.

  Notes:
    The UTF-8 bytes are moved into the string as-is rather than going through
    TEncoding. TEncoding.GetString yields a UnicodeString, and assigning that
    to a string converts through the system codepage - which silently destroys
    Greek and every other non-Latin-1 script outside an LCL application. Since
    the rest of the program treats string as UTF-8 bytes, a raw move is both
    correct and exact.
------------------------------------------------------------------------------}
function DecodeFile(const APath: string; out AHadBom: Boolean;
  out ANewLine: string): TStringList;
var
  Bytes: TBytes;
  Text: string;
  Offset, Count: Integer;
begin
  Text := '';
  Bytes := ReadBytes(APath);
  AHadBom := (Length(Bytes) >= 3) and (Bytes[0] = $EF) and
    (Bytes[1] = $BB) and (Bytes[2] = $BF);

  if AHadBom then
    Offset := 3
  else
    Offset := 0;

  Count := Length(Bytes) - Offset;
  SetLength(Text, Count);
  if Count > 0 then
    Move(Bytes[Offset], Text[1], Count);

  if Pos(#13#10, Text) > 0 then
    ANewLine := #13#10
  else
    ANewLine := #10;

  Result := TStringList.Create;
  Result.LineBreak := ANewLine;
  Result.TrailingLineBreak := False;
  Result.Text := Text;
end;

{------------------------------------------------------------------------------
  EncodeFile
  ----------------------------------------------------------------------------
  Writes lines back out with the encoding they were read with.

  Parameters:
    APath    - File to write.
    ALines   - Lines to write.
    AHadBom  - Write a UTF-8 BOM when True.
    ANewLine - Line ending to use.
------------------------------------------------------------------------------}
procedure EncodeFile(const APath: string; ALines: TStringList;
  AHadBom: Boolean; const ANewLine: string);
var
  Data: TBytes;
  Text: string;
  Offset, Count: Integer;
begin
  Data := nil;
  ALines.LineBreak := ANewLine;
  ALines.TrailingLineBreak := False;
  Text := ALines.Text;
  Count := Length(Text);

  if AHadBom then
    Offset := 3
  else
    Offset := 0;

  SetLength(Data, Offset + Count);
  if AHadBom then
  begin
    Data[0] := $EF;
    Data[1] := $BB;
    Data[2] := $BF;
  end;
  if Count > 0 then
    Move(Text[1], Data[Offset], Count);

  WriteBytes(APath, Data);
end;

{------------------------------------------------------------------------------
  FindStringsSection
  ----------------------------------------------------------------------------
  Locates the [Strings] section within a loaded file.

  Parameters:
    ALines - The file's lines.
    AFirst - Receives the index of the first line after the section header,
             or -1 when there is no [Strings] section.
    ALast  - Receives the exclusive end index: the next section header, or the
             line count.
------------------------------------------------------------------------------}
procedure FindStringsSection(ALines: TStringList; out AFirst, ALast: Integer);
var
  I: Integer;
  Trimmed: string;
begin
  AFirst := -1;
  ALast := ALines.Count;

  for I := 0 to ALines.Count - 1 do
  begin
    if LowerCase(Trim(ALines[I])) = '[strings]' then
    begin
      AFirst := I + 1;
      Break;
    end;
  end;

  if AFirst < 0 then
    Exit;

  for I := AFirst to ALines.Count - 1 do
  begin
    Trimmed := Trim(ALines[I]);
    if (Length(Trimmed) >= 2) and (Trimmed[1] = '[') and
       (Trimmed[Length(Trimmed)] = ']') then
    begin
      ALast := I;
      Exit;
    end;
  end;
end;

{------------------------------------------------------------------------------
  ReadLangStrings
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function ReadLangStrings(const APath: string): TLangEntries;
var
  Lines: TStringList;
  First, Last, I, SplitAt, Count: Integer;
  HadBom: Boolean;
  NewLine, Line: string;
begin
  Result := nil;
  if not FileExists(APath) then
    Exit;

  Lines := DecodeFile(APath, HadBom, NewLine);
  try
    FindStringsSection(Lines, First, Last);
    if First < 0 then
      Exit;

    Count := 0;
    SetLength(Result, Last - First);
    for I := First to Last - 1 do
    begin
      Line := Lines[I];
      if (Trim(Line) = '') or (Copy(TrimLeft(Line), 1, 1) = ';') then
        Continue;
      SplitAt := Pos('=', Line);
      if SplitAt <= 1 then
        Continue;
      Result[Count].Key := Trim(Copy(Line, 1, SplitAt - 1));
      Result[Count].Value := Copy(Line, SplitAt + 1, MaxInt);
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Lines.Free;
  end;
end;

{------------------------------------------------------------------------------
  UpdateLangStrings
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure UpdateLangStrings(const APath: string; const AChanges: TLangEntries);
var
  Lines: TStringList;
  First, Last, I, SplitAt, C: Integer;
  HadBom, Found: Boolean;
  NewLine: string;
begin
  if Length(AChanges) = 0 then
    Exit;

  Lines := DecodeFile(APath, HadBom, NewLine);
  try
    FindStringsSection(Lines, First, Last);
    if First < 0 then
    begin
      Lines.Add('[Strings]');
      First := Lines.Count;
      Last := Lines.Count;
    end;

    for C := 0 to High(AChanges) do
    begin
      Found := False;
      for I := First to Last - 1 do
      begin
        SplitAt := Pos('=', Lines[I]);
        if (SplitAt > 1) and SameText(Trim(Copy(Lines[I], 1, SplitAt - 1)),
          AChanges[C].Key) then
        begin
          Lines[I] := AChanges[C].Key + '=' + AChanges[C].Value;
          Found := True;
          Break;
        end;
      end;

      if not Found then
      begin
        Lines.Insert(Last, AChanges[C].Key + '=' + AChanges[C].Value);
        Inc(Last);
      end;
    end;

    EncodeFile(APath, Lines, HadBom, NewLine);
  finally
    Lines.Free;
  end;
end;

end.
