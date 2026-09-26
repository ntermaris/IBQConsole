{==============================================================================
  Unit:        IbqError
  Purpose:     The exception hierarchy of IBQConsole. Every error the program
               raises itself derives from EIbqError, so a handler can tell our
               errors apart from RTL and component errors.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  SysUtils
==============================================================================}
unit IbqError;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  { EIbqError
    Base of every error raised by IBQConsole itself. }
  EIbqError = class(Exception);

  { EIbqConfigError
    Configuration or registration file is missing, unreadable or malformed. }
  EIbqConfigError = class(EIbqError);

  { EIbqDatabaseError
    A Firebird operation failed. Carries the full status vector, not only the
    first line: the first line of a Firebird error is usually the least
    informative one, and discarding the rest is how tools become unhelpful. }
  EIbqDatabaseError = class(EIbqError)
  private
    FSqlCode: Integer;
    FGdsCode: Integer;
    FStatusLines: TStringArray;
    FStatement: string;
  public
    constructor Create(const AMessage: string; ASqlCode, AGdsCode: Integer;
      const AStatusLines: TStringArray; const AStatement: string = '');

    { The full error as shown to the user: every status line, and the failing
      statement when one is known. }
    function FullText: string;

    { Firebird SQLCODE, 0 when not applicable. }
    property SqlCode: Integer read FSqlCode;
    { Firebird GDSCODE (isc_* error number), 0 when not applicable. }
    property GdsCode: Integer read FGdsCode;
    { Every line of the interbase status vector, in order. }
    property StatusLines: TStringArray read FStatusLines;
    { The SQL statement that failed, when the error came from one. }
    property Statement: string read FStatement;
  end;

  { EIbqUnsupported
    The connected server does not support what was asked. Raised by the
    version-gating layer so the failure names the feature and the version. }
  EIbqUnsupported = class(EIbqError);

  { EIbqCancelled
    The user cancelled a long-running operation. Carries no error text: it is
    not a failure and must never be reported as one. }
  EIbqCancelled = class(EIbqError);

implementation

{------------------------------------------------------------------------------
  EIbqDatabaseError.Create
  ----------------------------------------------------------------------------
  Builds a database error from a Firebird failure.

  Parameters:
    AMessage     - Primary message, normally the first status line.
    ASqlCode     - Firebird SQLCODE, or 0.
    AGdsCode     - Firebird GDSCODE, or 0.
    AStatusLines - Every line of the status vector, in order. May be empty.
    AStatement   - The SQL that failed, when applicable.
------------------------------------------------------------------------------}
constructor EIbqDatabaseError.Create(const AMessage: string;
  ASqlCode, AGdsCode: Integer; const AStatusLines: TStringArray;
  const AStatement: string);
begin
  inherited Create(AMessage);
  FSqlCode := ASqlCode;
  FGdsCode := AGdsCode;
  FStatusLines := AStatusLines;
  FStatement := AStatement;
end;

{------------------------------------------------------------------------------
  EIbqDatabaseError.FullText
  ----------------------------------------------------------------------------
  Renders the complete error for display or for the log panel.

  Returns:
    Every status line on its own line, followed by the SQLCODE/GDSCODE when
    known and the failing statement when one was supplied.
------------------------------------------------------------------------------}
function EIbqDatabaseError.FullText: string;
var
  Line: string;
begin
  Result := '';

  if Length(FStatusLines) = 0 then
    Result := Message
  else
  begin
    for Line in FStatusLines do
    begin
      if Result <> '' then
        Result := Result + LineEnding;
      Result := Result + Line;
    end;
  end;

  if (FSqlCode <> 0) or (FGdsCode <> 0) then
    Result := Result + LineEnding +
      Format('SQLCODE %d, GDSCODE %d', [FSqlCode, FGdsCode]);

  if FStatement <> '' then
    Result := Result + LineEnding + LineEnding + FStatement;
end;

end.
