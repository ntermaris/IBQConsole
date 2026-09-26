{==============================================================================
  Unit:        DataExport
  Purpose:     Turns a result set into CSV, TSV, JSON, HTML, Markdown or INSERT
               statements.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, DatabaseRow

  Pure text transformation over a TDataTable, with no UI and no database, so
  the same code serves the SQL editor's result grid and a property page's Data
  tab, and so every escaping rule can be tested without a server.

  ESCAPING IS THE WHOLE JOB
  Each format has exactly one way to go wrong, and it is always the same kind
  of mistake - a value containing the character that separates values:

    CSV       a comma, a quote or a newline inside a field
    TSV       a tab or a newline inside a field
    JSON      a quote, a backslash or a control character
    HTML      & < > and quotes
    Markdown  a pipe, which would end the cell
    INSERT    a single quote, which would end the literal

  Getting these wrong does not produce an error. It produces a file that opens
  and is quietly wrong, which is worse.
==============================================================================}
unit DataExport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DatabaseRow;

type
  { The formats a result set can be written as. }
  TExportFormat = (
    efCsv,        // comma separated, RFC 4180 quoting
    efTsv,        // tab separated
    efJson,       // array of objects
    efHtml,       // a table element
    efMarkdown,   // a pipe table
    efInsert      // INSERT statements
  );

{ Returns the file extension for a format, without the dot. }
function ExportFormatExtension(AFormat: TExportFormat): string;

{ Returns the file dialog filter for a format. }
function ExportFormatFilter(AFormat: TExportFormat): string;

{ Returns the human-readable name of a format. }
function ExportFormatName(AFormat: TExportFormat): string;

{ Converts a result set to text.

  Parameters:
    ATable       - The rows to write.
    AFormat      - What to write them as.
    ARelationName - Table name used by the INSERT format; ignored by the
                   others. Pass the quoted, schema-qualified name.

  Returns:
    The whole export as one string. An empty result set still produces a
    header for the formats that have one, because an empty CSV with column
    names is a valid and useful thing to hand somebody. }
function ExportDataTable(const ATable: TDataTable; AFormat: TExportFormat;
  const ARelationName: string = 'TABLE_NAME'): string;

{ Writes a result set to a file.

  Parameters:
    ATable        - The rows to write.
    AFormat       - What to write them as.
    AFileName     - Destination, overwritten if it exists.
    ARelationName - As for ExportDataTable.

  Raises:
    EFCreateError - The file cannot be written. }
procedure SaveDataTable(const ATable: TDataTable; AFormat: TExportFormat;
  const AFileName: string; const ARelationName: string = 'TABLE_NAME');

implementation

{------------------------------------------------------------------------------
  ExportFormatExtension
  ----------------------------------------------------------------------------
  Returns the file extension for a format, without the dot.
------------------------------------------------------------------------------}
function ExportFormatExtension(AFormat: TExportFormat): string;
begin
  case AFormat of
    efCsv:      Result := 'csv';
    efTsv:      Result := 'tsv';
    efJson:     Result := 'json';
    efHtml:     Result := 'html';
    efMarkdown: Result := 'md';
    efInsert:   Result := 'sql';
  else
    Result := 'txt';
  end;
end;

{------------------------------------------------------------------------------
  ExportFormatName
  ----------------------------------------------------------------------------
  Returns the human-readable name of a format.
------------------------------------------------------------------------------}
function ExportFormatName(AFormat: TExportFormat): string;
begin
  case AFormat of
    efCsv:      Result := 'CSV';
    efTsv:      Result := 'Tab separated';
    efJson:     Result := 'JSON';
    efHtml:     Result := 'HTML';
    efMarkdown: Result := 'Markdown';
    efInsert:   Result := 'INSERT statements';
  else
    Result := 'Text';
  end;
end;

{------------------------------------------------------------------------------
  ExportFormatFilter
  ----------------------------------------------------------------------------
  Returns the file dialog filter for a format.
------------------------------------------------------------------------------}
function ExportFormatFilter(AFormat: TExportFormat): string;
begin
  Result := Format('%s|*.%s|All files|*.*',
    [ExportFormatName(AFormat), ExportFormatExtension(AFormat)]);
end;

{------------------------------------------------------------------------------
  CsvField
  ----------------------------------------------------------------------------
  Quotes one field for CSV, per RFC 4180.

  Parameters:
    AValue     - The field's text.
    ADelimiter - The separator in use, so the same routine serves TSV.

  Returns:
    The field, wrapped in double quotes and with inner quotes doubled, when it
    contains the delimiter, a quote, a carriage return or a line feed.
    Otherwise the value unchanged.
------------------------------------------------------------------------------}
function CsvField(const AValue: string; ADelimiter: Char): string;
var
  NeedsQuotes: Boolean;
  I: Integer;
begin
  NeedsQuotes := False;
  for I := 1 to Length(AValue) do
  begin
    if (AValue[I] = ADelimiter) or (AValue[I] = '"') or
       (AValue[I] = #13) or (AValue[I] = #10) then
    begin
      NeedsQuotes := True;
      Break;
    end;
  end;

  if not NeedsQuotes then
    Exit(AValue);

  Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"';
end;

{------------------------------------------------------------------------------
  JsonString
  ----------------------------------------------------------------------------
  Escapes one value as a JSON string, including the surrounding quotes.

  Parameters:
    AValue - The text to escape.

  Returns:
    A valid JSON string literal.

  Notes:
    Control characters below space must be escaped or the JSON is invalid, and
    a value read from a CHAR column can contain them. \u form is used for the
    ones without a short escape.
------------------------------------------------------------------------------}
function JsonString(const AValue: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := '"';
  for I := 1 to Length(AValue) do
  begin
    Ch := AValue[I];
    case Ch of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #8:   Result := Result + '\b';
      #9:   Result := Result + '\t';
      #10:  Result := Result + '\n';
      #12:  Result := Result + '\f';
      #13:  Result := Result + '\r';
    else
      if Ch < ' ' then
        Result := Result + '\u' + LowerCase(IntToHex(Ord(Ch), 4))
      else
        Result := Result + Ch;
    end;
  end;
  Result := Result + '"';
end;

{------------------------------------------------------------------------------
  HtmlText
  ----------------------------------------------------------------------------
  Escapes one value for HTML text content.

  Parameters:
    AValue - The text to escape.

  Returns:
    The text with &, <, > and quotes replaced by entities. The ampersand must
    be replaced FIRST or the other replacements would be escaped again.
------------------------------------------------------------------------------}
function HtmlText(const AValue: string): string;
begin
  Result := StringReplace(AValue, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
end;

{------------------------------------------------------------------------------
  MarkdownCell
  ----------------------------------------------------------------------------
  Escapes one value for a Markdown pipe table cell.

  Parameters:
    AValue - The text to escape.

  Returns:
    The text with pipes escaped and newlines replaced by a break, because a
    pipe table cell cannot contain a real line break.
------------------------------------------------------------------------------}
function MarkdownCell(const AValue: string): string;
begin
  Result := StringReplace(AValue, '|', '\|', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '<br>', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '<br>', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '<br>', [rfReplaceAll]);
end;

{------------------------------------------------------------------------------
  SqlLiteral
  ----------------------------------------------------------------------------
  Renders one value as a SQL string literal.

  Parameters:
    AValue - The text.

  Returns:
    The value in single quotes with inner quotes doubled.

  Notes:
    Everything is written as a string literal, including numbers. Firebird
    converts a string to a number on assignment, and guessing which columns are
    numeric from text alone would get it wrong for a VARCHAR holding '007' -
    which would silently become 7.
------------------------------------------------------------------------------}
function SqlLiteral(const AValue: string): string;
begin
  Result := '''' + StringReplace(AValue, '''', '''''', [rfReplaceAll]) + '''';
end;

{------------------------------------------------------------------------------
  ExportSeparated
  ----------------------------------------------------------------------------
  Writes a result set as CSV or TSV.

  Parameters:
    ATable     - The rows.
    ADelimiter - The separator.
    AOutput    - Receives the lines.
------------------------------------------------------------------------------}
procedure ExportSeparated(const ATable: TDataTable; ADelimiter: Char;
  AOutput: TStrings);
var
  R, C: Integer;
  Line: string;
begin
  Line := '';
  for C := 0 to ATable.ColumnCount - 1 do
  begin
    if C > 0 then
      Line := Line + ADelimiter;
    Line := Line + CsvField(ATable.ColumnNames[C], ADelimiter);
  end;
  AOutput.Add(Line);

  for R := 0 to ATable.RowCount - 1 do
  begin
    Line := '';
    for C := 0 to ATable.ColumnCount - 1 do
    begin
      if C > 0 then
        Line := Line + ADelimiter;
      Line := Line + CsvField(TrimRight(ATable.ValueAt(R, C)), ADelimiter);
    end;
    AOutput.Add(Line);
  end;
end;

{------------------------------------------------------------------------------
  ExportDataTable
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function ExportDataTable(const ATable: TDataTable; AFormat: TExportFormat;
  const ARelationName: string): string;
var
  Output: TStringList;
  R, C: Integer;
  Line, Columns: string;
begin
  Output := TStringList.Create;
  try
    case AFormat of
      efCsv:
        ExportSeparated(ATable, ',', Output);

      efTsv:
        ExportSeparated(ATable, #9, Output);

      efJson:
        begin
          Output.Add('[');
          for R := 0 to ATable.RowCount - 1 do
          begin
            Line := '  {';
            for C := 0 to ATable.ColumnCount - 1 do
            begin
              if C > 0 then
                Line := Line + ', ';
              Line := Line + JsonString(ATable.ColumnNames[C]) + ': ' +
                JsonString(TrimRight(ATable.ValueAt(R, C)));
            end;
            Line := Line + '}';
            if R < ATable.RowCount - 1 then
              Line := Line + ',';
            Output.Add(Line);
          end;
          Output.Add(']');
        end;

      efHtml:
        begin
          Output.Add('<table>');
          Output.Add('  <thead>');
          Line := '    <tr>';
          for C := 0 to ATable.ColumnCount - 1 do
            Line := Line + '<th>' + HtmlText(ATable.ColumnNames[C]) + '</th>';
          Output.Add(Line + '</tr>');
          Output.Add('  </thead>');
          Output.Add('  <tbody>');
          for R := 0 to ATable.RowCount - 1 do
          begin
            Line := '    <tr>';
            for C := 0 to ATable.ColumnCount - 1 do
              Line := Line + '<td>' +
                HtmlText(TrimRight(ATable.ValueAt(R, C))) + '</td>';
            Output.Add(Line + '</tr>');
          end;
          Output.Add('  </tbody>');
          Output.Add('</table>');
        end;

      efMarkdown:
        begin
          Line := '|';
          for C := 0 to ATable.ColumnCount - 1 do
            Line := Line + ' ' + MarkdownCell(ATable.ColumnNames[C]) + ' |';
          Output.Add(Line);

          Line := '|';
          for C := 0 to ATable.ColumnCount - 1 do
            Line := Line + '---|';
          Output.Add(Line);

          for R := 0 to ATable.RowCount - 1 do
          begin
            Line := '|';
            for C := 0 to ATable.ColumnCount - 1 do
              Line := Line + ' ' +
                MarkdownCell(TrimRight(ATable.ValueAt(R, C))) + ' |';
            Output.Add(Line);
          end;
        end;

      efInsert:
        begin
          Columns := '';
          for C := 0 to ATable.ColumnCount - 1 do
          begin
            if C > 0 then
              Columns := Columns + ', ';
            Columns := Columns + ATable.ColumnNames[C];
          end;

          for R := 0 to ATable.RowCount - 1 do
          begin
            Line := 'INSERT INTO ' + ARelationName + ' (' + Columns +
              ') VALUES (';
            for C := 0 to ATable.ColumnCount - 1 do
            begin
              if C > 0 then
                Line := Line + ', ';
              Line := Line + SqlLiteral(TrimRight(ATable.ValueAt(R, C)));
            end;
            Output.Add(Line + ');');
          end;
        end;
    end;

    Result := Output.Text;
  finally
    Output.Free;
  end;
end;

{------------------------------------------------------------------------------
  SaveDataTable
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure SaveDataTable(const ATable: TDataTable; AFormat: TExportFormat;
  const AFileName: string; const ARelationName: string);
var
  Output: TStringList;
begin
  Output := TStringList.Create;
  try
    Output.Text := ExportDataTable(ATable, AFormat, ARelationName);
    Output.SaveToFile(AFileName);
  finally
    Output.Free;
  end;
end;

end.
