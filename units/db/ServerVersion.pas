{==============================================================================
  Unit:        ServerVersion
  Purpose:     Identifies the connected Firebird engine and its on-disk
               structure version, so the rest of the program can gate features
               and pick the right metadata SQL provider.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils
==============================================================================}
unit ServerVersion;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils;

type
  { TServerVersion
    Engine and ODS version of one connection. A record rather than a class:
    it is copied freely, has no identity and owns nothing. }
  TServerVersion = record
    Major: Integer;
    Minor: Integer;
    Release: Integer;
    OdsMajor: Integer;
    OdsMinor: Integer;
    IsFirebird: Boolean;
    RawVersion: string;

    { Returns True when the engine is at least AMajor.AMinor. }
    function AtLeast(AMajor: Integer; AMinor: Integer = 0): Boolean;
    { Returns 'Firebird 5.0.1 (ODS 13.1)' for display in the status bar. }
    function DisplayText: string;
    { Returns True when nothing has been detected yet. }
    function IsUnknown: Boolean;
  end;

const
  { The oldest engine IBQConsole supports. Older servers are refused with a
    message naming this version. }
  MinimumSupportedMajor = 3;
  MinimumSupportedMinor = 0;

{ Builds a TServerVersion from the engine version string.

  Parameters:
    AEngineVersion - Value of rdb$get_context('SYSTEM', 'ENGINE_VERSION'),
                     e.g. '5.0.1'. An unparseable value yields a record whose
                     IsUnknown is True rather than an exception.
    AOdsMajor      - MON$DATABASE.MON$ODS_MAJOR, or 0 when not read yet.
    AOdsMinor      - MON$DATABASE.MON$ODS_MINOR, or 0 when not read yet.

  Returns:
    The parsed version. }
function ParseEngineVersion(const AEngineVersion: string;
  AOdsMajor: Integer = 0; AOdsMinor: Integer = 0): TServerVersion;

{ Returns an empty, not-yet-detected version. }
function UnknownServerVersion: TServerVersion;

implementation

{------------------------------------------------------------------------------
  TServerVersion.AtLeast
  ----------------------------------------------------------------------------
  Compares the engine version against a minimum.

  Parameters:
    AMajor - Required major version.
    AMinor - Required minor version, 0 when any minor will do.

  Returns:
    True when the engine is AMajor.AMinor or newer. Always False while the
    version is unknown, so a feature is never enabled on a guess.
------------------------------------------------------------------------------}
function TServerVersion.AtLeast(AMajor: Integer; AMinor: Integer): Boolean;
begin
  if IsUnknown then
    Exit(False);
  if Major <> AMajor then
    Result := Major > AMajor
  else
    Result := Minor >= AMinor;
end;

{------------------------------------------------------------------------------
  TServerVersion.DisplayText
  ----------------------------------------------------------------------------
  Renders the version for the status bar.

  Returns:
    'Firebird 5.0.1 (ODS 13.1)', omitting the ODS part when it is not known,
    or 'unknown' before detection.
------------------------------------------------------------------------------}
function TServerVersion.DisplayText: string;
begin
  if IsUnknown then
    Exit('unknown');

  if IsFirebird then
    Result := 'Firebird '
  else
    Result := 'InterBase ';

  Result := Result + Format('%d.%d.%d', [Major, Minor, Release]);

  if OdsMajor > 0 then
    Result := Result + Format(' (ODS %d.%d)', [OdsMajor, OdsMinor]);
end;

{------------------------------------------------------------------------------
  TServerVersion.IsUnknown
  ----------------------------------------------------------------------------
  Returns True while no version has been detected.
------------------------------------------------------------------------------}
function TServerVersion.IsUnknown: Boolean;
begin
  Result := Major = 0;
end;

{------------------------------------------------------------------------------
  NextNumber
  ----------------------------------------------------------------------------
  Removes and returns the leading run of digits of AText.

  Parameters:
    AText - On entry the remaining text; on exit the text after the digits and
            the one separator that followed them.

  Returns:
    The number read, or 0 when AText does not start with a digit.
------------------------------------------------------------------------------}
function NextNumber(var AText: string): Integer;
var
  Digits: string;
begin
  Digits := '';
  while (AText <> '') and (AText[1] in ['0'..'9']) do
  begin
    Digits := Digits + AText[1];
    Delete(AText, 1, 1);
  end;

  if (AText <> '') and not (AText[1] in ['0'..'9']) then
    Delete(AText, 1, 1);

  Result := StrToIntDef(Digits, 0);
end;

{------------------------------------------------------------------------------
  ParseEngineVersion
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function ParseEngineVersion(const AEngineVersion: string;
  AOdsMajor: Integer; AOdsMinor: Integer): TServerVersion;
var
  Remaining: string;
begin
  Result := UnknownServerVersion;
  Result.RawVersion := AEngineVersion;
  Result.OdsMajor := AOdsMajor;
  Result.OdsMinor := AOdsMinor;

  Remaining := Trim(AEngineVersion);
  if Remaining = '' then
    Exit;

  Result.Major := NextNumber(Remaining);
  Result.Minor := NextNumber(Remaining);
  Result.Release := NextNumber(Remaining);

  { ENGINE_VERSION exists only on Firebird. InterBase never reports through
    this path, so anything that parsed is a Firebird engine. }
  Result.IsFirebird := Result.Major > 0;
end;

{------------------------------------------------------------------------------
  UnknownServerVersion
  ----------------------------------------------------------------------------
  Returns a zeroed version whose IsUnknown is True.
------------------------------------------------------------------------------}
function UnknownServerVersion: TServerVersion;
begin
  Result := Default(TServerVersion);
  Result.IsFirebird := True;
end;

end.
