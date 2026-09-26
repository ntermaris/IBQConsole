{==============================================================================
  Unit:        FirebirdKeywords
  Purpose:     The Firebird reserved word list, and the single question the
               rest of the program asks about it: is this identifier a reserved
               word, and therefore does it have to be quoted?
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils

  The list covers Firebird 5.0 and is a superset of 3.0 and 4.0. Treating a
  word as reserved when the connected server does not reserve it costs only a
  pair of quotes; missing one produces invalid SQL. The list therefore errs
  towards including.
==============================================================================}
unit FirebirdKeywords;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ Returns True when AWord is a Firebird reserved word, compared without regard
  to case. }
function IsReservedWord(const AWord: string): Boolean;

{ Fills AList with every reserved word, uppercase. Used by the SQL editor's
  syntax highlighter and autocomplete. }
procedure ListReservedWords(AList: TStrings);

implementation

const
  ReservedWords: array[0..219] of string = (
    'ADD', 'ADMIN', 'ALL', 'ALTER', 'AND', 'ANY', 'AS', 'AT', 'AVG',
    'BEGIN', 'BETWEEN', 'BIGINT', 'BINARY', 'BIT_LENGTH', 'BLOB', 'BOOLEAN',
    'BOTH', 'BY',
    'CALL', 'CASE', 'CAST', 'CHAR', 'CHAR_LENGTH', 'CHARACTER',
    'CHARACTER_LENGTH', 'CHECK', 'CLOSE', 'COLLATE', 'COLUMN', 'COMMENT',
    'COMMIT', 'CONNECT', 'CONSTRAINT', 'CORR', 'COUNT', 'COVAR_POP',
    'COVAR_SAMP', 'CREATE', 'CROSS', 'CURRENT', 'CURRENT_CONNECTION',
    'CURRENT_DATE', 'CURRENT_ROLE', 'CURRENT_TIME', 'CURRENT_TIMESTAMP',
    'CURRENT_TRANSACTION', 'CURRENT_USER', 'CURSOR',
    'DATE', 'DAY', 'DEC', 'DECFLOAT', 'DECIMAL', 'DECLARE', 'DEFAULT',
    'DELETE', 'DELETING', 'DETERMINISTIC', 'DISCONNECT', 'DISTINCT', 'DOUBLE',
    'DROP',
    'ELSE', 'END', 'ESCAPE', 'EXECUTE', 'EXISTS', 'EXTERNAL', 'EXTRACT',
    'FALSE', 'FETCH', 'FILTER', 'FLOAT', 'FOR', 'FOREIGN', 'FROM', 'FULL',
    'FUNCTION',
    'GDSCODE', 'GLOBAL', 'GRANT', 'GROUP',
    'HAVING', 'HOUR',
    'IF', 'IN', 'INDEX', 'INNER', 'INSENSITIVE', 'INSERT', 'INSERTING', 'INT',
    'INT128', 'INTEGER', 'INTO', 'IS',
    'JOIN',
    'LATERAL', 'LEADING', 'LEFT', 'LIKE', 'LOCAL', 'LOCALTIME',
    'LOCALTIMESTAMP', 'LONG', 'LOWER',
    'MAX', 'MERGE', 'MIN', 'MINUTE', 'MONTH',
    'NATIONAL', 'NATURAL', 'NCHAR', 'NO', 'NOT', 'NULL', 'NUMERIC',
    'OCTET_LENGTH', 'OF', 'OFFSET', 'ON', 'ONLY', 'OPEN', 'OR', 'ORDER',
    'OUTER', 'OVER',
    'PARAMETER', 'PLAN', 'POSITION', 'POST_EVENT', 'PRECISION', 'PRIMARY',
    'PROCEDURE', 'PUBLICATION',
    'RDB$DB_KEY', 'RDB$ERROR', 'RDB$GET_CONTEXT', 'RDB$RECORD_VERSION',
    'RDB$ROLE_NAME', 'RDB$SET_CONTEXT', 'RDB$SYSTEM_PRIVILEGE', 'REAL',
    'RECORD_VERSION', 'RECREATE', 'RECURSIVE', 'REFERENCES', 'REGR_AVGX',
    'REGR_AVGY', 'REGR_COUNT', 'REGR_INTERCEPT', 'REGR_R2', 'REGR_SLOPE',
    'REGR_SXX', 'REGR_SXY', 'REGR_SYY', 'RELEASE', 'RESETTING', 'RETURN',
    'RETURNING_VALUES', 'RETURNS', 'REVOKE', 'RIGHT', 'ROLLBACK', 'ROW',
    'ROW_COUNT', 'ROWS',
    'SAVEPOINT', 'SCHEMA', 'SCROLL', 'SECOND', 'SELECT', 'SENSITIVE', 'SET',
    'SIMILAR', 'SMALLINT', 'SOME', 'SQLCODE', 'SQLSTATE', 'START',
    'STDDEV_POP', 'STDDEV_SAMP', 'SUM',
    'TABLE', 'THEN', 'TIME', 'TIMESTAMP', 'TIMEZONE_HOUR', 'TIMEZONE_MINUTE',
    'TO', 'TRAILING', 'TRIGGER', 'TRIM', 'TRUE',
    'UNBOUNDED', 'UNION', 'UNIQUE', 'UNKNOWN', 'UPDATE', 'UPDATING', 'UPPER',
    'USER', 'USING',
    'VALUE', 'VALUES', 'VAR_POP', 'VAR_SAMP', 'VARBINARY', 'VARCHAR',
    'VARIABLE', 'VARYING', 'VIEW',
    'WHEN', 'WHERE', 'WHILE', 'WINDOW', 'WITH', 'WITHOUT',
    'YEAR'
  );

var
  { Sorted lookup built once at startup. }
  KeywordIndex: TStringList = nil;

{------------------------------------------------------------------------------
  BuildIndex
  ----------------------------------------------------------------------------
  Builds the sorted lookup list on first use.

  Notes:
    Sorting at run time rather than maintaining the array in sorted order keeps
    the source list readable and grouped by letter, and removes a whole class
    of maintenance bug: a word added in the wrong place would otherwise become
    invisible to a binary search.
------------------------------------------------------------------------------}
procedure BuildIndex;
var
  I: Integer;
begin
  if KeywordIndex <> nil then
    Exit;

  KeywordIndex := TStringList.Create;
  KeywordIndex.CaseSensitive := False;
  KeywordIndex.Duplicates := dupIgnore;
  for I := Low(ReservedWords) to High(ReservedWords) do
    KeywordIndex.Add(ReservedWords[I]);
  KeywordIndex.Sorted := True;
end;

{------------------------------------------------------------------------------
  IsReservedWord
  ----------------------------------------------------------------------------
  Answers whether a word must be quoted to be used as an identifier.

  Parameters:
    AWord - The word to test. Case is ignored.

  Returns:
    True when AWord is reserved by Firebird.
------------------------------------------------------------------------------}
function IsReservedWord(const AWord: string): Boolean;
begin
  if AWord = '' then
    Exit(False);
  BuildIndex;
  Result := KeywordIndex.IndexOf(AWord) >= 0;
end;

{------------------------------------------------------------------------------
  ListReservedWords
  ----------------------------------------------------------------------------
  Copies every reserved word into AList, uppercase and sorted.

  Parameters:
    AList - Receives the words. Cleared first.
------------------------------------------------------------------------------}
procedure ListReservedWords(AList: TStrings);
begin
  BuildIndex;
  AList.Assign(KeywordIndex);
end;

finalization
  FreeAndNil(KeywordIndex);

end.
