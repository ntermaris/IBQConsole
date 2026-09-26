{==============================================================================
  Program:     TestSqlAliases
  Purpose:     Checks that no metadata query aliases a column with a Firebird
               reserved word.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20

  Why this exists: 'AS POSITION' and 'AS VALUE' both shipped and both failed at
  run time with "Token unknown", because a reserved word cannot be a bare
  alias. The keyword list needed to catch it was already in the program - it
  just was not being consulted. This test consults it.
==============================================================================}
program TestSqlAliases;
{$mode objfpc}{$H+}
uses SysUtils, Classes, StrUtils,
     ServerVersion, MetadataSqlProvider, MetadataSqlProviderFactory,
     FirebirdKeywords;

var
  Failures: Integer;

{ Reports every ' AS <word>' in ASql whose word is reserved. }
procedure CheckAliases(const ALabel, ASql: string);
var
  P, Start: Integer;
  Word_: string;
  Upper: string;
begin
  if Trim(ASql) = '' then Exit;
  Upper := UpperCase(ASql);
  P := 1;
  repeat
    P := PosEx(' AS ', Upper, P);
    if P = 0 then Break;
    Inc(P, 4);
    Start := P;
    while (P <= Length(Upper)) and
          (Upper[P] in ['A'..'Z', '0'..'9', '_', '$']) do
      Inc(P);
    Word_ := Copy(Upper, Start, P - Start);

    { Skip CAST(x AS VARCHAR(12)) and CAST(x AS INTEGER): a cast's type name is
      followed by '(' or ')', while a column alias is followed by a comma or by
      whitespace before FROM/UNION/ORDER. That one character is the whole
      difference, and without it every CAST in the program reports a false
      positive. }
    while (P <= Length(Upper)) and (Upper[P] = ' ') do
      Inc(P);
    if (P <= Length(Upper)) and (Upper[P] in ['(', ')']) then
      Continue;

    if (Word_ <> '') and IsReservedWord(Word_) then
    begin
      WriteLn(Format('  FAIL  %-24s aliases a column "AS %s" (reserved)',
        [ALabel, Word_]));
      Inc(Failures);
    end;
  until P > Length(Upper);
end;

var
  Provider: TMetadataSqlProvider;
  Major: Integer;
  Kind: TTriggerKind;
  Sok: TSourceObjectKind;
  Tag: string;
begin
  Failures := 0;
  WriteLn('Reserved-word aliases in metadata SQL');
  WriteLn;

  for Major := 3 to 6 do
  begin
    Provider := CreateMetadataSqlProvider(
      ParseEngineVersion(Format('%d.0.0', [Major])));
    try
      Tag := 'FB' + IntToStr(Major) + ' ';
      CheckAliases(Tag + 'DatabaseInfo', Provider.DatabaseInfoSQL);
      CheckAliases(Tag + 'Tables', Provider.TablesSQL);
      CheckAliases(Tag + 'GTTs', Provider.GlobalTemporaryTablesSQL);
      CheckAliases(Tag + 'SystemTables', Provider.SystemTablesSQL);
      CheckAliases(Tag + 'Views', Provider.ViewsSQL);
      CheckAliases(Tag + 'Procedures', Provider.ProceduresSQL);
      CheckAliases(Tag + 'Functions', Provider.FunctionsSQL);
      CheckAliases(Tag + 'ExternalFuncs', Provider.ExternalFunctionsSQL);
      CheckAliases(Tag + 'Packages', Provider.PackagesSQL);
      for Kind := Low(TTriggerKind) to High(TTriggerKind) do
        CheckAliases(Tag + 'Triggers', Provider.TriggersSQL(Kind));
      CheckAliases(Tag + 'Generators', Provider.GeneratorsSQL);
      CheckAliases(Tag + 'Exceptions', Provider.ExceptionsSQL);
      CheckAliases(Tag + 'Domains', Provider.DomainsSQL);
      CheckAliases(Tag + 'SysDomains', Provider.SystemDomainsSQL);
      CheckAliases(Tag + 'Indices', Provider.IndicesSQL);
      CheckAliases(Tag + 'SysIndices', Provider.SystemIndicesSQL);
      CheckAliases(Tag + 'Roles', Provider.RolesSQL);
      CheckAliases(Tag + 'CharacterSets', Provider.CharacterSetsSQL);
      CheckAliases(Tag + 'Collations', Provider.CollationsSQL);
      CheckAliases(Tag + 'BlobFilters', Provider.BlobFiltersSQL);
      CheckAliases(Tag + 'Users', Provider.UsersSQL);
      CheckAliases(Tag + 'Publications', Provider.PublicationsSQL);
      CheckAliases(Tag + 'Schemas', Provider.SchemasSQL);
      CheckAliases(Tag + 'UserAccounts', Provider.UserAccountsSQL);
      CheckAliases(Tag + 'Attachments', Provider.AttachmentsSQL);

      CheckAliases(Tag + 'RelColumns', Provider.RelationColumnsSQL('T'));
      CheckAliases(Tag + 'RelIndices', Provider.RelationIndicesSQL('T'));
      CheckAliases(Tag + 'RelConstraints', Provider.RelationConstraintsSQL('T'));
      CheckAliases(Tag + 'RelTriggers', Provider.RelationTriggersSQL('T'));
      CheckAliases(Tag + 'Parameters', Provider.RoutineParametersSQL('P'));
      CheckAliases(Tag + 'DependsOn', Provider.DependenciesSQL('T', True));
      CheckAliases(Tag + 'UsedBy', Provider.DependenciesSQL('T', False));
      CheckAliases(Tag + 'IndexInfo', Provider.IndexInfoSQL('I'));
      for Sok := Low(TSourceObjectKind) to High(TSourceObjectKind) do
      begin
        CheckAliases(Tag + 'Privileges', Provider.PrivilegesSQL('X', Sok));
        CheckAliases(Tag + 'Source', Provider.ObjectSourceSQL(Sok, 'X'));
        CheckAliases(Tag + 'Description', Provider.DescriptionSQL(Sok, 'X'));
      end;
    finally
      Provider.Free;
    end;
    WriteLn('  checked FB', Major);
  end;

  WriteLn;
  if Failures = 0 then
    WriteLn('no reserved-word aliases found')
  else
  begin
    WriteLn(Failures, ' reserved-word alias(es) found');
    Halt(1);
  end;
end.
