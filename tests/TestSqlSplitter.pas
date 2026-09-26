program TestSqlSplitter;
{$mode objfpc}{$H+}
uses SysUtils, SqlStatementSplitter;

var
  Passed, Failed: Integer;

procedure Check(const ACase, AScript: string; AExpected: Integer;
  const AExpectFirst: string = '');
var
  S: TSqlStatementArray;
  Ok: Boolean;
  Detail: string;
begin
  S := SplitSqlScript(AScript);
  Ok := Length(S) = AExpected;
  Detail := '';
  if Ok and (AExpectFirst <> '') then
  begin
    Ok := Pos(UpperCase(AExpectFirst), UpperCase(S[0].Text)) > 0;
    if not Ok then Detail := ' first="' + Copy(S[0].Text, 1, 60) + '"';
  end;
  if Ok then
  begin
    Inc(Passed);
    WriteLn(Format('  ok    %-46s -> %d', [ACase, Length(S)]));
  end
  else
  begin
    Inc(Failed);
    WriteLn(Format('  FAIL  %-46s -> %d, expected %d%s',
      [ACase, Length(S), AExpected, Detail]));
  end;
end;

const
  NL = #13#10;
begin
  Passed := 0; Failed := 0;
  WriteLn('SQL statement splitter');
  WriteLn;

  Check('two simple statements', 'SELECT 1 FROM RDB$DATABASE; SELECT 2 FROM RDB$DATABASE;', 2);
  Check('no trailing terminator', 'SELECT 1 FROM RDB$DATABASE', 1);
  Check('empty script', '', 0);
  Check('only whitespace', '   ' + NL + '  ', 0);
  Check('consecutive terminators', 'SELECT 1;;;SELECT 2;', 2);

  Check('semicolon in string literal',
    'INSERT INTO T VALUES (''a;b;c'');', 1);
  Check('escaped quote in literal',
    'INSERT INTO T VALUES (''it''''s; here'');', 1);
  Check('semicolon in quoted identifier',
    'SELECT "we;ird" FROM T;', 1);
  Check('escaped double quote',
    'SELECT "a""b;c" FROM T;', 1);

  Check('semicolon in line comment',
    '-- drop this; and that' + NL + 'SELECT 1;', 1, 'SELECT 1');
  Check('semicolon in block comment',
    '/* a; b; c */ SELECT 1;', 1, 'SELECT 1');
  Check('block comment spanning lines',
    '/* one' + NL + 'two; three' + NL + '*/ SELECT 1;', 1);

  Check('q-string with braces',
    'INSERT INTO T VALUES (q''{a;b}'');', 1);
  Check('q-string with bang delimiter',
    'INSERT INTO T VALUES (q''!a;b!'');', 1);

  Check('SET TERM around a procedure',
    'SET TERM ^ ;' + NL +
    'CREATE PROCEDURE P AS BEGIN' + NL +
    '  SELECT 1 FROM RDB$DATABASE;' + NL +
    '  SELECT 2 FROM RDB$DATABASE;' + NL +
    'END^' + NL +
    'SET TERM ; ^' + NL +
    'SELECT 9 FROM RDB$DATABASE;', 2, 'CREATE PROCEDURE');

  Check('SET TERM with !! terminator',
    'SET TERM !! ;' + NL +
    'CREATE TRIGGER T AS BEGIN a; b; END!!' + NL +
    'SET TERM ; !!', 1);

  Check('two procedures under SET TERM',
    'SET TERM ^ ;' + NL +
    'CREATE PROCEDURE A AS BEGIN x; END^' + NL +
    'CREATE PROCEDURE B AS BEGIN y; END^' + NL +
    'SET TERM ; ^', 2);

  Check('SET TERM does not appear in output',
    'SET TERM ^ ;' + NL + 'SELECT 1^' + NL + 'SET TERM ; ^', 1, 'SELECT 1');

  Check('identifier starting with q is not a q-string',
    'SELECT qty FROM T; SELECT 2 FROM T;', 2);

  WriteLn;
  WriteLn(Format('passed %d, failed %d', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
