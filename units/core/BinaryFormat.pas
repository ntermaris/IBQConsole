{==============================================================================
  Unit:        BinaryFormat
  Purpose:     Renders arbitrary bytes as a hex dump, and recognises the common
               image and document formats from their leading bytes.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils

  A BLOB is bytes. Before anything can be shown usefully, two questions have to
  be answered: what is this, and what does it look like? Both are answered here
  rather than in the editor form, so both can be tested without a database or a
  window.

  Detection is by CONTENT, not by the column's declared sub-type. A Firebird
  BLOB SUB_TYPE 0 routinely holds a PNG, and SUB_TYPE 1 routinely holds
  something that is not text at all. What the column says it holds is a hint;
  what the first bytes say is evidence.
==============================================================================}
unit BinaryFormat;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { What the leading bytes suggest the content is. }
  TBinaryKind = (
    bkEmpty,
    bkText,        // no bytes that rule text out
    bkPng,
    bkJpeg,
    bkGif,
    bkBmp,
    bkIco,
    bkPdf,
    bkZip,         // also .docx, .xlsx, .odt - all zip containers
    bkUnknown      // binary, not recognised
  );

const
  { Bytes per line in a hex dump. Sixteen is the convention and fits a
    reasonable window without wrapping. }
  HexBytesPerLine = 16;

{ Returns the human-readable name of a content kind. }
function BinaryKindName(AKind: TBinaryKind): string;

{ Returns True when the kind is an image LCL can be asked to load. }
function BinaryKindIsImage(AKind: TBinaryKind): Boolean;

{ Guesses what the bytes are.

  Parameters:
    ABytes - The content; may be empty.

  Returns:
    The kind. bkText when nothing rules text out - see IsProbablyText for what
    that means. }
function DetectBinaryKind(const ABytes: TBytes): TBinaryKind;

{ Returns True when the bytes look like text rather than binary.

  Parameters:
    ABytes - The content.

  Notes:
    A byte below space that is not tab, carriage return or line feed is taken
    as proof of binary. That is the rule every hex editor uses, and it is right
    far more often than trusting a declared sub-type. A NUL in particular
    settles it: text does not contain NUL. }
function IsProbablyText(const ABytes: TBytes): Boolean;

{ Renders bytes as a classic hex dump.

  Parameters:
    ABytes     - The content.
    AMaxBytes  - Stop after this many bytes; 0 means no limit. A note is added
                 when the dump was cut short, because a hex view that silently
                 shows part of a blob is a way to draw the wrong conclusion.

  Returns:
    Lines of 'offset  hex bytes  |printable|'. }
function HexDump(const ABytes: TBytes; AMaxBytes: Integer = 0): string;

{ Reads a stream into a byte array.

  Parameters:
    AStream - Read from its current position to the end.

  Returns:
    The bytes; empty when there are none. }
function StreamToBytes(AStream: TStream): TBytes;

implementation

{------------------------------------------------------------------------------
  BinaryKindName
  ----------------------------------------------------------------------------
  Returns the human-readable name of a content kind.
------------------------------------------------------------------------------}
function BinaryKindName(AKind: TBinaryKind): string;
begin
  case AKind of
    bkEmpty:   Result := 'empty';
    bkText:    Result := 'text';
    bkPng:     Result := 'PNG image';
    bkJpeg:    Result := 'JPEG image';
    bkGif:     Result := 'GIF image';
    bkBmp:     Result := 'BMP image';
    bkIco:     Result := 'icon';
    bkPdf:     Result := 'PDF document';
    bkZip:     Result := 'ZIP container';
  else
    Result := 'binary';
  end;
end;

{------------------------------------------------------------------------------
  BinaryKindIsImage
  ----------------------------------------------------------------------------
  Returns True when the kind is an image the LCL can load.
------------------------------------------------------------------------------}
function BinaryKindIsImage(AKind: TBinaryKind): Boolean;
begin
  Result := AKind in [bkPng, bkJpeg, bkGif, bkBmp, bkIco];
end;

{------------------------------------------------------------------------------
  StartsWith
  ----------------------------------------------------------------------------
  Tests whether ABytes begins with a given byte sequence.

  Parameters:
    ABytes     - The content.
    ASignature - The bytes to look for at offset 0.

  Returns:
    True on a match.
------------------------------------------------------------------------------}
function StartsWith(const ABytes: TBytes;
  const ASignature: array of Byte): Boolean;
var
  I: Integer;
begin
  if Length(ABytes) < Length(ASignature) then
    Exit(False);
  for I := 0 to High(ASignature) do
  begin
    if ABytes[I] <> ASignature[I] then
      Exit(False);
  end;
  Result := True;
end;

{------------------------------------------------------------------------------
  IsProbablyText
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function IsProbablyText(const ABytes: TBytes): Boolean;
const
  { Enough to settle it. Scanning a 200 MB blob to answer a yes/no question
    the first kilobyte already answers would make opening one feel broken. }
  SampleLimit = 4096;
var
  I, Limit: Integer;
begin
  if Length(ABytes) = 0 then
    Exit(True);

  Limit := Length(ABytes);
  if Limit > SampleLimit then
    Limit := SampleLimit;

  for I := 0 to Limit - 1 do
  begin
    if (ABytes[I] < 32) and not (ABytes[I] in [9, 10, 13]) then
      Exit(False);
  end;
  Result := True;
end;

{------------------------------------------------------------------------------
  DetectBinaryKind
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function DetectBinaryKind(const ABytes: TBytes): TBinaryKind;
begin
  if Length(ABytes) = 0 then
    Exit(bkEmpty);

  if StartsWith(ABytes, [$89, $50, $4E, $47, $0D, $0A, $1A, $0A]) then
    Exit(bkPng);
  if StartsWith(ABytes, [$FF, $D8, $FF]) then
    Exit(bkJpeg);
  if StartsWith(ABytes, [$47, $49, $46, $38]) then          // GIF8
    Exit(bkGif);
  if StartsWith(ABytes, [$42, $4D]) then                    // BM
    Exit(bkBmp);
  if StartsWith(ABytes, [$00, $00, $01, $00]) then
    Exit(bkIco);
  if StartsWith(ABytes, [$25, $50, $44, $46]) then          // %PDF
    Exit(bkPdf);
  if StartsWith(ABytes, [$50, $4B, $03, $04]) then          // PK..
    Exit(bkZip);

  if IsProbablyText(ABytes) then
    Result := bkText
  else
    Result := bkUnknown;
end;

{------------------------------------------------------------------------------
  HexDump
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Built through a TStringList rather than by concatenating onto one string:
    a megabyte blob is sixty-five thousand lines, and repeated concatenation
    of a growing string turns that into minutes.
------------------------------------------------------------------------------}
function HexDump(const ABytes: TBytes; AMaxBytes: Integer): string;
var
  Lines: TStringList;
  Offset, I, Limit, Index: Integer;
  HexPart, TextPart: string;
  Value: Byte;
begin
  if Length(ABytes) = 0 then
    Exit('');

  Limit := Length(ABytes);
  if (AMaxBytes > 0) and (Limit > AMaxBytes) then
    Limit := AMaxBytes;

  Lines := TStringList.Create;
  try
    Offset := 0;
    while Offset < Limit do
    begin
      HexPart := '';
      TextPart := '';

      for I := 0 to HexBytesPerLine - 1 do
      begin
        Index := Offset + I;
        if Index < Limit then
        begin
          Value := ABytes[Index];
          HexPart := HexPart + IntToHex(Value, 2) + ' ';
          if (Value >= 32) and (Value < 127) then
            TextPart := TextPart + Chr(Value)
          else
            TextPart := TextPart + '.';
        end
        else
          HexPart := HexPart + '   ';

        if I = (HexBytesPerLine div 2) - 1 then
          HexPart := HexPart + ' ';
      end;

      Lines.Add(IntToHex(Offset, 8) + '  ' + HexPart + ' |' + TextPart + '|');
      Inc(Offset, HexBytesPerLine);
    end;

    if Limit < Length(ABytes) then
      Lines.Add(Format('... %d of %d bytes shown',
        [Limit, Length(ABytes)]));

    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

{------------------------------------------------------------------------------
  StreamToBytes
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function StreamToBytes(AStream: TStream): TBytes;
var
  Remaining: Int64;
begin
  Result := nil;
  if AStream = nil then
    Exit;

  Remaining := AStream.Size - AStream.Position;
  if Remaining <= 0 then
    Exit;

  SetLength(Result, Remaining);
  AStream.ReadBuffer(Result[0], Remaining);
end;

end.
