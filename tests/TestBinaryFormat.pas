{==============================================================================
  Program:     TestBinaryFormat
  Purpose:     Covers content detection and the hex dump.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
==============================================================================}
program TestBinaryFormat;
{$mode objfpc}{$H+}
uses SysUtils, Classes, BinaryFormat;

var
  Passed, Failed: Integer;

procedure Ok(const ACase: string; ACondition: Boolean; const ADetail: string = '');
begin
  if ACondition then
  begin
    Inc(Passed);
    WriteLn('  ok    ', ACase);
  end
  else
  begin
    Inc(Failed);
    WriteLn('  FAIL  ', ACase, '  ', ADetail);
  end;
end;

function Bytes(const AValues: array of Byte): TBytes;
var I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AValues));
  for I := 0 to High(AValues) do Result[I] := AValues[I];
end;

function TextBytes(const S: string): TBytes;
var I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(S));
  for I := 1 to Length(S) do Result[I - 1] := Ord(S[I]);
end;

var
  Empty: TBytes;
  Dump: string;
  Lines: TStringList;
begin
  Passed := 0; Failed := 0;
  Empty := nil;

  WriteLn('Content detection');
  WriteLn;
  Ok('empty is bkEmpty', DetectBinaryKind(Empty) = bkEmpty);
  Ok('plain text is bkText', DetectBinaryKind(TextBytes('hello world')) = bkText);
  Ok('text with tab and newline is still text',
     DetectBinaryKind(TextBytes('a' + #9 + 'b' + #13#10 + 'c')) = bkText);
  Ok('a NUL rules out text',
     DetectBinaryKind(Bytes([65, 0, 66])) = bkUnknown);
  Ok('PNG signature', DetectBinaryKind(
     Bytes([$89, $50, $4E, $47, $0D, $0A, $1A, $0A, 1, 2])) = bkPng);
  Ok('JPEG signature', DetectBinaryKind(Bytes([$FF, $D8, $FF, $E0, 1])) = bkJpeg);
  Ok('GIF signature', DetectBinaryKind(TextBytes('GIF89a...')) = bkGif);
  Ok('BMP signature', DetectBinaryKind(TextBytes('BM' + #0 + #0)) = bkBmp);
  Ok('PDF signature', DetectBinaryKind(TextBytes('%PDF-1.7')) = bkPdf);
  Ok('ZIP signature', DetectBinaryKind(Bytes([$50, $4B, $03, $04, 1])) = bkZip);
  Ok('PNG counts as an image', BinaryKindIsImage(bkPng));
  Ok('PDF does not count as an image', not BinaryKindIsImage(bkPdf));
  Ok('detection beats a text-looking prefix on a real PNG',
     DetectBinaryKind(Bytes([$89, $50, $4E, $47, $0D, $0A, $1A, $0A])) <> bkText);

  WriteLn;
  WriteLn('Hex dump');
  WriteLn;
  Ok('empty dumps to nothing', HexDump(Empty) = '');

  Dump := HexDump(TextBytes('Hello world!'));
  Lines := TStringList.Create;
  try
    Lines.Text := Dump;
    Ok('one short line', Lines.Count = 1, '(got ' + IntToStr(Lines.Count) + ')');
    Ok('starts with the offset', Pos('00000000', Lines[0]) = 1);
    Ok('has the hex bytes', Pos('48 65 6C 6C 6F', Lines[0]) > 0);
    Ok('has the printable column', Pos('|Hello world!|', Lines[0]) > 0);

    { exactly 16 bytes -> one full line, no padding }
    Lines.Text := HexDump(TextBytes('0123456789ABCDEF'));
    Ok('16 bytes is one line', Lines.Count = 1);
    Ok('16 bytes needs no pad', Pos('   |', Lines[0]) = 0,
       '(line: ' + Lines[0] + ')');

    { 17 bytes -> two lines, second padded }
    Lines.Text := HexDump(TextBytes('0123456789ABCDEFG'));
    Ok('17 bytes is two lines', Lines.Count = 2);
    Ok('second line offset is 16', Pos('00000010', Lines[1]) = 1);
    Ok('second line is padded', Pos('   ', Lines[1]) > 0);

    { non-printable becomes a dot }
    Lines.Text := HexDump(Bytes([65, 0, 66]));
    Ok('NUL shown as a dot in the text column', Pos('|A.B|', Lines[0]) > 0);

    { limit is reported, not silent }
    Lines.Text := HexDump(TextBytes('0123456789ABCDEFGHIJ'), 8);
    Ok('limit note is present', Pos('8 of 20 bytes shown', Lines.Text) > 0);
  finally
    Lines.Free;
  end;

  WriteLn;
  WriteLn(Format('passed %d, failed %d', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
