{==============================================================================
  Unit:        StatisticsService
  Purpose:     Produces a database statistics report through the Services API.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, ServiceRunner

  IBConsole equivalent: frmuDBStatistics. This is what `gstat` prints.

  WHY THIS IS THE FIRST THING TO LOOK AT
  When a database "has become slow", the header page alone answers most of it:
  the sweep interval, the gap between the oldest and next transaction, the
  number of page buffers, whether forced writes are on. The index statistics
  answer the rest, by showing which index has gone lopsided and needs
  rebuilding.

  So this returns text rather than a parsed structure, and the report is shown
  as the server wrote it. A prettier parsed view would be a v2 feature; a
  wrong parse of a report the user could have read himself would be worse than
  useless.

  Statistics do not lock the database and cannot damage it - unlike everything
  else in this folder, this one is always safe to run.
==============================================================================}
unit StatisticsService;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IBXServices, ServiceRunner;

type
  { Which parts of the report to ask for.

    stoDataPages       - per-table data page statistics
    stoHeaderPages     - the header page only; the quick answer, and the one
                         that needs no scan of the database
    stoIndexPages      - per-index statistics, including depth and the
                         distribution that shows a lopsided index
    stoSystemRelations - include the RDB$ tables in the report }
  TStatisticsOption = (stoDataPages, stoHeaderPages, stoIndexPages,
    stoSystemRelations);
  TStatisticsOptions = set of TStatisticsOption;

type
  { TStatisticsService
    One statistics report on one database. }
  TStatisticsService = class(TServiceTask)
  private
    FDatabasePath: string;
    FOptions: TStatisticsOptions;
  protected
    { Creates the statistics service on the worker's connection. }
    function CreateService(
      AConnection: TIBXServicesConnection): TIBXCustomService; override;
    { Names the database and applies the chosen parts. }
    procedure Configure(AService: TIBXCustomService); override;
  public
    constructor Create;

    { Returns 'Statistics for <database>'. }
    function Describe: string; override;
    { Returns why the report cannot be produced, or an empty string. }
    function Validate: string; override;

    { Full path of the database, or its alias. }
    property DatabasePath: string read FDatabasePath write FDatabasePath;

    { Which parts of the report to ask for. Defaults to the header page and
      index statistics: the two that answer the question that is usually being
      asked, without reading every data page of a large database. }
    property Options: TStatisticsOptions read FOptions write FOptions;
  end;

implementation

{------------------------------------------------------------------------------
  TStatisticsService.Create
  ----------------------------------------------------------------------------
  Creates a report of the header page and the index statistics.
------------------------------------------------------------------------------}
constructor TStatisticsService.Create;
begin
  inherited Create;
  FOptions := [stoHeaderPages, stoIndexPages];
end;

{------------------------------------------------------------------------------
  TStatisticsService.Describe
  ----------------------------------------------------------------------------
  Returns 'Statistics for <database>'.
------------------------------------------------------------------------------}
function TStatisticsService.Describe: string;
begin
  Result := 'Statistics for ' + FDatabasePath;
end;

{------------------------------------------------------------------------------
  TStatisticsService.Validate
  ----------------------------------------------------------------------------
  Returns why the report cannot be produced, or an empty string.
------------------------------------------------------------------------------}
function TStatisticsService.Validate: string;
begin
  if Trim(FDatabasePath) = '' then
    Exit('No database has been named.');
  if FOptions = [] then
    Exit('No part of the report has been chosen.');
  Result := '';
end;

{------------------------------------------------------------------------------
  TStatisticsService.CreateService
  ----------------------------------------------------------------------------
  Creates the statistics service on the worker's connection.

  Parameters:
    AConnection - The worker thread's services connection.

  Returns:
    The service to execute.
------------------------------------------------------------------------------}
function TStatisticsService.CreateService(
  AConnection: TIBXServicesConnection): TIBXCustomService;
var
  Service: TIBXStatisticalService;
begin
  Service := TIBXStatisticalService.Create(nil);
  Service.ServicesConnection := AConnection;
  Result := Service;
end;

{------------------------------------------------------------------------------
  TStatisticsService.Configure
  ----------------------------------------------------------------------------
  Names the database and applies the chosen parts.

  Parameters:
    AService - What CreateService returned.
------------------------------------------------------------------------------}
procedure TStatisticsService.Configure(AService: TIBXCustomService);
var
  Service: TIBXStatisticalService;
  IbxOptions: TStatOptions;
begin
  Service := AService as TIBXStatisticalService;
  Service.DatabaseName := FDatabasePath;

  IbxOptions := [];
  if stoDataPages in FOptions then
    Include(IbxOptions, DataPages);
  if stoHeaderPages in FOptions then
    Include(IbxOptions, HeaderPages);
  if stoIndexPages in FOptions then
    Include(IbxOptions, IndexPages);
  if stoSystemRelations in FOptions then
    Include(IbxOptions, SystemRelations);
  Service.Options := IbxOptions;
end;

end.
