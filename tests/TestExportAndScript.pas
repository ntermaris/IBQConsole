{==============================================================================
  Program:     TestExportAndScript
  Purpose:     Covers the escaping rules of every export format and the shape
               of every generated script.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20

  Escaping bugs do not raise errors. They produce a file that opens and is
  quietly wrong, so every rule needs a test with the awkward character in it.
==============================================================================}
program TestExportAndScript;
{$mode objfpc}{$H+}
uses SysUtils, Classes, DatabaseRow, DataExport, ScriptGenerator, Identifier;

var
  Passed, Failed: Integer;

procedure Check(const ACase, AActual, AExpectedSubstring: string);
begin
  if Pos(AExpectedSubstring, AActual) > 0 then
  begin
    Inc(Passed);
    WriteLn(Format('  ok    %s', [ACase]));
  end
  else
  begin
    Inc(Failed);
    WriteLn(Format('  FAIL  %s', [ACase]));
    WriteLn('        wanted to find: ', AExpectedSubstring);
    WriteLn('        in            : ', StringReplace(Copy(AActual, 1, 220),
      LineEnding, ' | ', [rfReplaceAll]));
  end;
end;

procedure CheckAbsent(const ACase, AActual, AForbidden: string);
begin
  if Pos(AForbidden, AActual) = 0 then
  begin
    Inc(Passed);
    WriteLn(Format('  ok    %s', [ACase]));
  end
  else
  begin
    Inc(Failed);
    WriteLn(Format('  FAIL  %s  (found forbidden "%s")', [ACase, AForbidden]));
  end;
end;

function AwkwardTable: TDataTable;
begin
  Result := Default(TDataTable);
  SetLength(Result.ColumnNames, 3);
  Result.ColumnNames[0] := 'ID';
  Result.ColumnNames[1] := 'NAME';
  Result.ColumnNames[2] := 'NOTE';
  SetLength(Result.Rows, 2);

  SetLength(Result.Rows[0], 3);
  Result.Rows[0][0] := '1';
  Result.Rows[0][1] := 'Smith, John';           { comma }
  Result.Rows[0][2] := 'he said "hi"';          { double quotes }

  SetLength(Result.Rows[1], 3);
  Result.Rows[1][0] := '2';
  Result.Rows[1][1] := 'O''Brien';              { single quote }
  Result.Rows[1][2] := 'a | b' + #9 + 'c' + #10 + 'd <b>&</b>';
end;

var
  T: TDataTable;
  Cols, Keys, NoKeys, Params: TStringList;
  Rel: TIdentifier;
  S: string;
begin
  Passed := 0; Failed := 0;
  T := AwkwardTable;

  WriteLn('Export escaping');
  WriteLn;
  S := ExportDataTable(T, efCsv);
  Check('CSV quotes a field with a comma', S, '"Smith, John"');
  Check('CSV doubles inner quotes', S, '"he said ""hi"""');
  Check('CSV quotes a field with a newline', S, '"a | b');

  S := ExportDataTable(T, efTsv);
  Check('TSV quotes a field containing a tab', S, '"a | b');
  CheckAbsent('TSV does not quote a plain comma field',
    ExportDataTable(T, efTsv), '"Smith, John"');

  S := ExportDataTable(T, efJson);
  Check('JSON escapes double quotes', S, '\"hi\"');
  Check('JSON escapes newline', S, '\n');
  Check('JSON escapes tab', S, '\t');
  Check('JSON leaves single quote alone', S, 'O''Brien');

  S := ExportDataTable(T, efHtml);
  Check('HTML escapes ampersand', S, '&amp;');
  Check('HTML escapes less-than', S, '&lt;b&gt;');
  CheckAbsent('HTML leaves no raw tag from data', S, '<b>&</b>');

  S := ExportDataTable(T, efMarkdown);
  Check('Markdown escapes pipe', S, 'a \| b');
  Check('Markdown replaces newline with break', S, '<br>');
  Check('Markdown has a separator row', S, '|---|');

  S := ExportDataTable(T, efInsert, 'CUSTOMER');
  Check('INSERT names the table', S, 'INSERT INTO CUSTOMER (ID, NAME, NOTE)');
  Check('INSERT doubles single quotes', S, '''O''''Brien''');
  Check('INSERT ends each statement', S, ');');

  WriteLn;
  WriteLn('Script generation');
  WriteLn;

  Cols := TStringList.Create;
  Keys := TStringList.Create;
  NoKeys := TStringList.Create;
  Params := TStringList.Create;
  try
    Cols.Add('ID'); Cols.Add('NAME'); Cols.Add('Odd Name');
    Keys.Add('ID');
    Params.Add('FROM_DATE'); Params.Add('TO_DATE');
    Rel := TIdentifier.FromDatabase('CUSTOMER');

    S := GenerateRelationScript(skSelect, Rel, Cols, Keys);
    Check('SELECT limits rows', S, 'SELECT FIRST 100');
    Check('SELECT quotes only the odd name', S, '"Odd Name"');
    CheckAbsent('SELECT does not quote a plain name', S, '"ID"');

    S := GenerateRelationScript(skInsert, Rel, Cols, Keys);
    Check('INSERT lists columns', S, 'INSERT INTO CUSTOMER (');
    Check('INSERT uses named placeholders', S, ':NAME');

    S := GenerateRelationScript(skUpdate, Rel, Cols, Keys);
    Check('UPDATE assigns columns', S, 'NAME = :NAME');
    Check('UPDATE keys off the primary key', S, 'WHERE ID = :ID');

    S := GenerateRelationScript(skUpdate, Rel, Cols, NoKeys);
    Check('UPDATE without a key leaves a placeholder',
      S, 'WHERE /* no primary key');

    S := GenerateRelationScript(skDelete, Rel, Cols, NoKeys);
    Check('DELETE without a key leaves a placeholder',
      S, 'WHERE /* no primary key');

    S := GenerateRelationScript(skMerge, Rel, Cols, Keys);
    Check('MERGE matches on the key', S, 'tgt.ID = src.ID');
    Check('MERGE updates non-key columns', S, 'tgt.NAME = src.NAME');
    CheckAbsent('MERGE never updates the key itself', S, 'tgt.ID = src.ID,');

    S := GenerateRelationScript(skMerge, Rel, Cols, NoKeys);
    Check('MERGE without a key refuses', S, 'needs a primary key');

    S := GenerateExecuteScript(TIdentifier.FromDatabase('CALC_TOTAL'), Params);
    Check('EXECUTE names the procedure', S, 'EXECUTE PROCEDURE CALC_TOTAL');
    Check('EXECUTE lists parameters', S, '(:FROM_DATE, :TO_DATE)');

    S := GenerateExecuteScript(TIdentifier.FromDatabase('NO_ARGS'), nil);
    CheckAbsent('EXECUTE with no parameters has no brackets', S, '(');

    WriteLn;
    WriteLn('Typed literals');
    WriteLn;
    Check('empty means NULL', SqlLiteralForType('', 'INTEGER'), 'NULL');
    Check('the word null means NULL', SqlLiteralForType('null', 'VARCHAR(9)'), 'NULL');
    Check('integer passes through', SqlLiteralForType('42', 'INTEGER'), '42');
    Check('numeric passes through', SqlLiteralForType('1.5', 'NUMERIC(9,2)'), '1.5');
    Check('varchar is quoted', SqlLiteralForType('abc', 'VARCHAR(30)'), '''abc''');
    Check('varchar 007 keeps its zeros',
      SqlLiteralForType('007', 'VARCHAR(10)'), '''007''');
    Check('integer 007 is not quoted',
      SqlLiteralForType('007', 'INTEGER'), '007');
    Check('quote in a value is doubled',
      SqlLiteralForType('O''Brien', 'VARCHAR(30)'), '''O''''Brien''');
    Check('timestamp is quoted',
      SqlLiteralForType('2026-08-20 10:00', 'TIMESTAMP'), '''2026-08-20 10:00''');
    Check('boolean true', SqlLiteralForType('true', 'BOOLEAN'), 'TRUE');
    Check('boolean from 0', SqlLiteralForType('0', 'BOOLEAN'), 'FALSE');

    WriteLn;
    WriteLn('Routine calls');
    WriteLn;
    Params.Clear;
    Params.Add('42'); Params.Add('''abc''');
    Check('executable procedure uses EXECUTE PROCEDURE',
      BuildRoutineCall(TIdentifier.FromDatabase('P'), Params, False),
      'EXECUTE PROCEDURE P (42, ''abc'')');
    Check('selectable procedure uses SELECT',
      BuildRoutineCall(TIdentifier.FromDatabase('P'), Params, True),
      'SELECT * FROM P (42, ''abc'')');
    Params.Clear;
    CheckAbsent('no arguments means no brackets',
      BuildRoutineCall(TIdentifier.FromDatabase('P'), Params, False), '(');
  finally
    Cols.Free; Keys.Free; NoKeys.Free; Params.Free;
  end;

  WriteLn;
  WriteLn(Format('passed %d, failed %d', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
