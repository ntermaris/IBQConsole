{==============================================================================
  Unit:        MetadataSqlProviderFactory
  Purpose:     Picks the metadata SQL provider matching a server version. The
               only place in the program that knows the provider classes exist.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils, ServerVersion, IbqError, MetadataSqlProvider,
               MetadataSqlProviderFB3..FB6
==============================================================================}
unit MetadataSqlProviderFactory;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ServerVersion, IbqError, MetadataSqlProvider,
  MetadataSqlProviderFB3, MetadataSqlProviderFB4, MetadataSqlProviderFB5,
  MetadataSqlProviderFB6;

{ Creates the provider matching AVersion.

  Parameters:
    AVersion - The connected server's version, already detected.

  Returns:
    A new provider. The caller owns it; a TDatabaseContext frees it when it
    disconnects.

  Raises:
    EIbqUnsupported - The server is older than Firebird 3.0, or its version is
                      still unknown. }
function CreateMetadataSqlProvider(
  const AVersion: TServerVersion): TMetadataSqlProvider;

implementation

{------------------------------------------------------------------------------
  CreateMetadataSqlProvider
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    A version newer than the newest provider we know about gets the newest one
    rather than an error. A future Firebird 7 will be far closer to 6 than to
    nothing, and refusing to open a database because the tool has not been
    updated yet is worse than degrading gracefully. Anything the newer server
    added simply will not be listed.
------------------------------------------------------------------------------}
function CreateMetadataSqlProvider(
  const AVersion: TServerVersion): TMetadataSqlProvider;
begin
  if AVersion.IsUnknown then
    raise EIbqUnsupported.Create(
      'The server version has not been detected yet, so no metadata provider ' +
      'can be chosen. Connect first.');

  if not AVersion.AtLeast(MinimumSupportedMajor, MinimumSupportedMinor) then
    raise EIbqUnsupported.CreateFmt(
      'IBQConsole requires Firebird %d.%d or newer. This server reports %s.',
      [MinimumSupportedMajor, MinimumSupportedMinor, AVersion.DisplayText]);

  if AVersion.AtLeast(6) then
    Result := TMetadataSqlProviderFB6.Create(AVersion)
  else if AVersion.AtLeast(5) then
    Result := TMetadataSqlProviderFB5.Create(AVersion)
  else if AVersion.AtLeast(4) then
    Result := TMetadataSqlProviderFB4.Create(AVersion)
  else
    Result := TMetadataSqlProviderFB3.Create(AVersion);
end;

end.
