{==============================================================================
  Unit:        FeatureSet
  Purpose:     Maps engine version to available features, in one table, so that
               "does this server have packages?" is answered the same way
               everywhere instead of by scattered version comparisons.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils, ServerVersion, IbqError

  UI contract: a feature the server does not have is HIDDEN, not shown greyed
  out. A Firebird 3 database must not display an empty Publications folder.
==============================================================================}
unit FeatureSet;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ServerVersion, IbqError;

type
  { TDbFeature
    Everything IBQConsole does that is not available on every supported
    server. }
  TDbFeature = (
    dbfPackages,            // FB3+  PSQL packages
    dbfSqlFunctions,        // FB3+  PSQL functions, as opposed to UDFs
    dbfIdentityColumns,     // FB3+  GENERATED ... AS IDENTITY
    dbfSqlUserManagement,   // FB3+  CREATE USER / SEC$USERS
    dbfBooleanType,         // FB3+  BOOLEAN
    dbfDdlTriggers,         // FB3+  as exposed through RDB$TRIGGERS
    dbfDecFloat,            // FB4+  DECFLOAT(16|34)
    dbfInt128,              // FB4+  INT128 / NUMERIC(38)
    dbfTimeZones,           // FB4+  TIME/TIMESTAMP WITH TIME ZONE
    dbfPublications,        // FB4+  logical replication
    dbfSqlSecurity,         // FB4+  SQL SECURITY DEFINER/INVOKER
    dbfGeneratorIncrement,  // FB4+  sequences with a step
    dbfPartialIndexes,      // FB5+  CREATE INDEX ... WHERE
    dbfParallelWorkers,     // FB5+  parallel backup, sweep, index build
    dbfProfiler,            // FB5+  PLG$PROF_* tables
    dbfExplainPlan,         // FB5+  EXPLAIN
    dbfSchemas              // FB6+  SQL schemas, two-part object names
  );

  TDbFeatures = set of TDbFeature;

{ Returns True when AVersion's engine provides AFeature.

  Parameters:
    AVersion - The connected server's version.
    AFeature - The feature to test.

  Returns:
    False whenever the version is still unknown, so nothing is enabled on a
    guess. }
function SupportsFeature(const AVersion: TServerVersion;
  AFeature: TDbFeature): Boolean;

{ Returns every feature AVersion provides. Useful for building the tree once
  instead of testing feature by feature. }
function FeaturesOf(const AVersion: TServerVersion): TDbFeatures;

{ Returns the human-readable name of AFeature, for error messages. }
function FeatureName(AFeature: TDbFeature): string;

{ Returns 'Firebird 4.0' - the version AFeature first appeared in. }
function FeatureRequirementText(AFeature: TDbFeature): string;

{ Raises EIbqUnsupported when AVersion does not provide AFeature. Call this at
  the top of any operation that would otherwise fail with a confusing Firebird
  syntax error.

  Raises:
    EIbqUnsupported - The server is too old for AFeature. }
procedure RequireFeature(const AVersion: TServerVersion; AFeature: TDbFeature);

implementation

type
  { The version a feature first appeared in. }
  TFeatureRequirement = record
    Feature: TDbFeature;
    Major: Integer;
    Minor: Integer;
    Name: string;
  end;

const
  { The whole version-gating policy of the program, in one table. }
  FeatureRequirements: array[TDbFeature] of TFeatureRequirement = (
    (Feature: dbfPackages;           Major: 3; Minor: 0; Name: 'packages'),
    (Feature: dbfSqlFunctions;       Major: 3; Minor: 0; Name: 'SQL functions'),
    (Feature: dbfIdentityColumns;    Major: 3; Minor: 0; Name: 'identity columns'),
    (Feature: dbfSqlUserManagement;  Major: 3; Minor: 0; Name: 'SQL user management'),
    (Feature: dbfBooleanType;        Major: 3; Minor: 0; Name: 'the BOOLEAN type'),
    (Feature: dbfDdlTriggers;        Major: 3; Minor: 0; Name: 'DDL triggers'),
    (Feature: dbfDecFloat;           Major: 4; Minor: 0; Name: 'DECFLOAT'),
    (Feature: dbfInt128;             Major: 4; Minor: 0; Name: 'INT128'),
    (Feature: dbfTimeZones;          Major: 4; Minor: 0; Name: 'time zones'),
    (Feature: dbfPublications;       Major: 4; Minor: 0; Name: 'publications'),
    (Feature: dbfSqlSecurity;        Major: 4; Minor: 0; Name: 'SQL SECURITY'),
    (Feature: dbfGeneratorIncrement; Major: 4; Minor: 0; Name: 'sequence increments'),
    (Feature: dbfPartialIndexes;     Major: 5; Minor: 0; Name: 'partial indexes'),
    (Feature: dbfParallelWorkers;    Major: 5; Minor: 0; Name: 'parallel workers'),
    (Feature: dbfProfiler;           Major: 5; Minor: 0; Name: 'the profiler'),
    (Feature: dbfExplainPlan;        Major: 5; Minor: 0; Name: 'EXPLAIN plans'),
    (Feature: dbfSchemas;            Major: 6; Minor: 0; Name: 'SQL schemas')
  );

{------------------------------------------------------------------------------
  SupportsFeature
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function SupportsFeature(const AVersion: TServerVersion;
  AFeature: TDbFeature): Boolean;
begin
  Result := AVersion.AtLeast(FeatureRequirements[AFeature].Major,
    FeatureRequirements[AFeature].Minor);
end;

{------------------------------------------------------------------------------
  FeaturesOf
  ----------------------------------------------------------------------------
  Collects every feature the server provides.

  Parameters:
    AVersion - The connected server's version.

  Returns:
    The set of available features; empty when the version is unknown.
------------------------------------------------------------------------------}
function FeaturesOf(const AVersion: TServerVersion): TDbFeatures;
var
  Feature: TDbFeature;
begin
  Result := [];
  for Feature := Low(TDbFeature) to High(TDbFeature) do
  begin
    if SupportsFeature(AVersion, Feature) then
      Include(Result, Feature);
  end;
end;

{------------------------------------------------------------------------------
  FeatureName
  ----------------------------------------------------------------------------
  Returns the human-readable name of a feature, for error messages.
------------------------------------------------------------------------------}
function FeatureName(AFeature: TDbFeature): string;
begin
  Result := FeatureRequirements[AFeature].Name;
end;

{------------------------------------------------------------------------------
  FeatureRequirementText
  ----------------------------------------------------------------------------
  Returns the engine version a feature first appeared in, as 'Firebird 4.0'.
------------------------------------------------------------------------------}
function FeatureRequirementText(AFeature: TDbFeature): string;
begin
  Result := Format('Firebird %d.%d', [FeatureRequirements[AFeature].Major,
    FeatureRequirements[AFeature].Minor]);
end;

{------------------------------------------------------------------------------
  RequireFeature
  ----------------------------------------------------------------------------
  Guards an operation that needs a feature the server may not have.

  Parameters:
    AVersion - The connected server's version.
    AFeature - The feature the caller is about to use.

  Raises:
    EIbqUnsupported - AVersion does not provide AFeature. The message names
                      both the feature and the version that introduced it, so
                      the user learns why rather than seeing a syntax error.
------------------------------------------------------------------------------}
procedure RequireFeature(const AVersion: TServerVersion; AFeature: TDbFeature);
begin
  if SupportsFeature(AVersion, AFeature) then
    Exit;

  raise EIbqUnsupported.CreateFmt(
    'This server does not support %s. %s or newer is required; ' +
    'the connected server reports %s.',
    [FeatureName(AFeature), FeatureRequirementText(AFeature),
     AVersion.DisplayText]);
end;

end.
