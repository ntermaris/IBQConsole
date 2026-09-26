{==============================================================================
  Unit:        SqlStatementSplitter
  Purpose:     Splits a SQL script into individual statements, honouring
               SET TERM, string literals, quoted identifiers and comments.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils

  Why this is not a call to Split(script, ';'):

    - A semicolon inside a string literal, a quoted identifier or a comment is
      not a terminator.
    - PSQL bodies CONTAIN semicolons. A procedure cannot be sent to the server
      one semicolon at a time, which is why SET TERM exists, and why any tool
      that cannot honour it is unable to run the scripts its own DDL extractor
      produces.
    - Firebird's q-string literals, written q'(...)' with any delimiter, can
      contain absolutely anything.

  The splitter is deliberately a lexer over the script rather than a parser of
  it: it must survive statements it does not understand, including ones from a
  future Firebird version.
==============================================================================}
unit SqlStatementSplitter;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils;

type
  { One statement found in a script. }
  TSqlStatement = record
    { The statement text, without its terminator, trimmed. }
    Text: string;
    { 1-based line in the script where the statement starts. }
    StartLine: Integer;
    { 0-based character offset of the first character of the statement. }
    StartOffset: Integer;
    { 0-based character offset one past the statement's terminator. }
    EndOffset: Integer;
    { True when the statement is empty after trimming. }
    function IsEmpty: Boolean;
  end;

  TSqlStatementArray = array of TSqlStatement;

const
  { The terminator a script starts with, until SET TERM says otherwise. }
  DefaultTerminator = ';';

{ Splits a script into statements.

  Parameters:
    AScript - The whole script text.

  Returns:
    The statements, in order. SET TERM statements are consumed and do not
    appear in the result: they are instructions to the client, not to the
    server, and sending one to Firebird is an error. Empty statements - the
    text between two consecutive terminators - are dropped. }
function SplitSqlScript(const AScript: string): TSqlStatementArray;

{ Finds the statement containing a caret position.

  Parameters:
    AScript     - The whole script text.
    ACharIndex  - 0-based caret offset.
    AStatement  - Receives the statement found.

  Returns:
    True when a statement contains or immediately follows the caret. This is
    what Execute (F5) uses: the user puts the caret anywhere in a statement and
    runs that one. }
function StatementAtOffset(const AScript: string; ACharIndex: Integer;
  out AStatement: TSqlStatement): Boolean;

implementation

type
  { Scanner state while walking the script. }
  TScanState = (
    ssNormal,          // ordinary SQL text
    ssLineComment,     // after -- until end of line
    ssBlockComment,    // inside a slash-star comment
    ssString,          // inside a single-quoted literal
    ssQuotedName,      // inside a double-quoted identifier
    ssQString          // inside a q'X...X' literal
  );

{------------------------------------------------------------------------------
  TSqlStatement.IsEmpty
  ----------------------------------------------------------------------------
  Returns True when the statement has no text.
------------------------------------------------------------------------------}
function TSqlStatement.IsEmpty: Boolean;
begin
  Result := Trim(Text) = '';
end;

{------------------------------------------------------------------------------
  ClosingDelimiterFor
  ----------------------------------------------------------------------------
  Returns the character that closes a q-string opened with AOpen.

  Parameters:
    AOpen - The character straight after the opening quote of q'...

  Returns:
    The matching bracket for a bracketing character, otherwise AOpen itself.

  Notes:
    Firebird's alternative quoting uses the character after q' as the
    delimiter, except that the four bracket pairs close with their partner:
    an opening brace is closed by a closing brace, not by another opening one.
------------------------------------------------------------------------------}
function ClosingDelimiterFor(AOpen: Char): Char;
begin
  case AOpen of
    '(': Result := ')';
    '{': Result := '}';
    '[': Result := ']';
    '<': Result := '>';
  else
    Result := AOpen;
  end;
end;

{------------------------------------------------------------------------------
  MatchesAt
  ----------------------------------------------------------------------------
  Tests whether AText contains AWord at APos, without regard to case.

  Parameters:
    AText - The text to look in.
    APos  - 1-based position to test at.
    AWord - The word to look for.

  Returns:
    True on a match.
------------------------------------------------------------------------------}
function MatchesAt(const AText: string; APos: Integer;
  const AWord: string): Boolean;
begin
  if APos + Length(AWord) - 1 > Length(AText) then
    Exit(False);
  Result := SameText(Copy(AText, APos, Length(AWord)), AWord);
end;

{------------------------------------------------------------------------------
  IsWordBoundary
  ----------------------------------------------------------------------------
  Returns True when the character at APos is not part of an identifier, or the
  position is outside the text.

  Parameters:
    AText - The text.
    APos  - 1-based position.
------------------------------------------------------------------------------}
function IsWordBoundary(const AText: string; APos: Integer): Boolean;
begin
  if (APos < 1) or (APos > Length(AText)) then
    Exit(True);
  Result := not (AText[APos] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']);
end;

{------------------------------------------------------------------------------
  TryReadSetTerm
  ----------------------------------------------------------------------------
  Recognises a SET TERM statement at APos and reads the new terminator.

  Parameters:
    AScript       - The script.
    APos          - 1-based position to test; must be at a token start.
    ANewTerminator - Receives the new terminator on success.
    ANextPos      - Receives the position just past the whole SET TERM
                    statement, including its own terminator.

  Returns:
    True when a SET TERM statement was recognised and consumed.

  Notes:
    The form is  SET TERM <new> <old>  where <old> is the terminator currently
    in force. Both are read as runs of non-space characters, because a
    terminator can be any punctuation - ^ and !! are both common.
------------------------------------------------------------------------------}
function TryReadSetTerm(const AScript: string; APos: Integer;
  out ANewTerminator: string; out ANextPos: Integer): Boolean;
var
  P, Len: Integer;
  NewTerm: string;
begin
  Result := False;
  ANewTerminator := '';
  ANextPos := APos;
  Len := Length(AScript);

  if not MatchesAt(AScript, APos, 'SET') then
    Exit;
  if not IsWordBoundary(AScript, APos + 3) then
    Exit;

  P := APos + 3;
  while (P <= Len) and (AScript[P] in [' ', #9, #13, #10]) do
    Inc(P);

  if not MatchesAt(AScript, P, 'TERM') then
    Exit;
  if not IsWordBoundary(AScript, P + 4) then
    Exit;

  P := P + 4;
  while (P <= Len) and (AScript[P] in [' ', #9, #13, #10]) do
    Inc(P);

  NewTerm := '';
  while (P <= Len) and not (AScript[P] in [' ', #9, #13, #10]) do
  begin
    NewTerm := NewTerm + AScript[P];
    Inc(P);
  end;

  if NewTerm = '' then
    Exit;

  { Skip the trailing old terminator and the rest of the line. Whatever
    follows the new terminator on this line is the old one, and it has already
    done its job by ending this statement. }
  while (P <= Len) and not (AScript[P] in [#13, #10]) do
    Inc(P);

  ANewTerminator := NewTerm;
  ANextPos := P;
  Result := True;
end;

{------------------------------------------------------------------------------
  SplitSqlScript
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    One pass, tracking which lexical construct the scanner is inside. A
    terminator only ends a statement in ssNormal state, which is what makes a
    semicolon inside a string, a comment or a PSQL body harmless.
------------------------------------------------------------------------------}
function SplitSqlScript(const AScript: string): TSqlStatementArray;
var
  Pos_, Len, Line, StatementStart, StatementLine, Count: Integer;
  State: TScanState;
  Terminator: string;
  QStringCloser: Char;
  NewTerm: string;
  NextPos: Integer;

  procedure EmitStatement(AEndPos: Integer);
  var
    Text: string;
  begin
    Text := Trim(Copy(AScript, StatementStart, AEndPos - StatementStart));
    if Text <> '' then
    begin
      if Count = Length(Result) then
        SetLength(Result, Length(Result) * 2 + 16);
      Result[Count].Text := Text;
      Result[Count].StartLine := StatementLine;
      Result[Count].StartOffset := StatementStart - 1;
      Result[Count].EndOffset := AEndPos - 1;
      Inc(Count);
    end;
  end;

  procedure BeginStatement(AAtPos: Integer);
  begin
    StatementStart := AAtPos;
    StatementLine := Line;
  end;

begin
  Result := nil;
  Count := 0;
  Len := Length(AScript);
  if Len = 0 then
    Exit;

  StatementStart := 1;
  StatementLine := 1;
  Pos_ := 1;
  Line := 1;
  State := ssNormal;
  Terminator := DefaultTerminator;
  QStringCloser := #0;
  BeginStatement(1);

  while Pos_ <= Len do
  begin
    if AScript[Pos_] = #10 then
      Inc(Line);

    case State of
      ssNormal:
        begin
          { A statement that has not started yet starts at the first character
            that is not whitespace, so leading blank lines are not counted as
            part of it. }
          if (StatementStart = Pos_) and (AScript[Pos_] in [' ', #9, #13, #10]) then
          begin
            Inc(Pos_);
            BeginStatement(Pos_);
            Continue;
          end;

          if (AScript[Pos_] = '-') and (Pos_ < Len) and
             (AScript[Pos_ + 1] = '-') then
          begin
            State := ssLineComment;
            Inc(Pos_, 2);
            Continue;
          end;

          if (AScript[Pos_] = '/') and (Pos_ < Len) and
             (AScript[Pos_ + 1] = '*') then
          begin
            State := ssBlockComment;
            Inc(Pos_, 2);
            Continue;
          end;

          if AScript[Pos_] = '"' then
          begin
            State := ssQuotedName;
            Inc(Pos_);
            Continue;
          end;

          { q'X...X' - the delimiter is whatever follows the quote }
          if (AScript[Pos_] in ['q', 'Q']) and (Pos_ + 2 <= Len) and
             (AScript[Pos_ + 1] = '''') and
             IsWordBoundary(AScript, Pos_ - 1) then
          begin
            QStringCloser := ClosingDelimiterFor(AScript[Pos_ + 2]);
            State := ssQString;
            Inc(Pos_, 3);
            Continue;
          end;

          if AScript[Pos_] = '''' then
          begin
            State := ssString;
            Inc(Pos_);
            Continue;
          end;

          if TryReadSetTerm(AScript, Pos_, NewTerm, NextPos) then
          begin
            Terminator := NewTerm;
            Pos_ := NextPos;
            BeginStatement(Pos_);
            Continue;
          end;

          if MatchesAt(AScript, Pos_, Terminator) then
          begin
            EmitStatement(Pos_);
            Inc(Pos_, Length(Terminator));
            BeginStatement(Pos_);
            Continue;
          end;

          Inc(Pos_);
        end;

      ssLineComment:
        begin
          if AScript[Pos_] = #10 then
            State := ssNormal;
          Inc(Pos_);
        end;

      ssBlockComment:
        begin
          if (AScript[Pos_] = '*') and (Pos_ < Len) and
             (AScript[Pos_ + 1] = '/') then
          begin
            State := ssNormal;
            Inc(Pos_, 2);
          end
          else
            Inc(Pos_);
        end;

      ssString:
        begin
          if AScript[Pos_] = '''' then
          begin
            { '' inside a literal is an escaped quote, not the end }
            if (Pos_ < Len) and (AScript[Pos_ + 1] = '''') then
              Inc(Pos_, 2)
            else
            begin
              State := ssNormal;
              Inc(Pos_);
            end;
          end
          else
            Inc(Pos_);
        end;

      ssQuotedName:
        begin
          if AScript[Pos_] = '"' then
          begin
            if (Pos_ < Len) and (AScript[Pos_ + 1] = '"') then
              Inc(Pos_, 2)
            else
            begin
              State := ssNormal;
              Inc(Pos_);
            end;
          end
          else
            Inc(Pos_);
        end;

      ssQString:
        begin
          if (AScript[Pos_] = QStringCloser) and (Pos_ < Len) and
             (AScript[Pos_ + 1] = '''') then
          begin
            State := ssNormal;
            Inc(Pos_, 2);
          end
          else
            Inc(Pos_);
        end;
    end;
  end;

  { Whatever is left after the last terminator is a statement too: a script
    whose final statement has no terminator is common and must still run. }
  if StatementStart <= Len then
    EmitStatement(Len + 1);

  SetLength(Result, Count);
end;

{------------------------------------------------------------------------------
  StatementAtOffset
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    A caret sitting just past a statement's terminator belongs to that
    statement, not to the next one: after typing 'SELECT 1;' the caret is past
    the semicolon, and F5 must run what was just typed rather than nothing.
------------------------------------------------------------------------------}
function StatementAtOffset(const AScript: string; ACharIndex: Integer;
  out AStatement: TSqlStatement): Boolean;
var
  Statements: TSqlStatementArray;
  I: Integer;
begin
  AStatement := Default(TSqlStatement);
  Statements := SplitSqlScript(AScript);
  if Length(Statements) = 0 then
    Exit(False);

  for I := Low(Statements) to High(Statements) do
  begin
    if (ACharIndex >= Statements[I].StartOffset) and
       (ACharIndex <= Statements[I].EndOffset) then
    begin
      AStatement := Statements[I];
      Exit(True);
    end;
  end;

  { Past the end of the last statement: run that one. }
  if ACharIndex > Statements[High(Statements)].EndOffset then
  begin
    AStatement := Statements[High(Statements)];
    Exit(True);
  end;

  AStatement := Statements[Low(Statements)];
  Result := True;
end;

end.
