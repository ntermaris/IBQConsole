{==============================================================================
  Unit:        StatementHistory
  Purpose:     Remembers the statements the user has executed, across sessions,
               so they can be found again.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils, contnrs, laz2_DOM, laz2_XMLRead,
               laz2_XMLWrite, IbqError

  FlameRobin's statement history is one of its most-used features, for a reason
  that has nothing to do with convenience: the statement a user wants back is
  usually the one they ran an hour ago and did not save, and without a history
  it is simply gone.

  Stored beside the registrations, in the user's own configuration directory,
  as XML they can read and delete. Never in a temporary file and never in the
  database.
==============================================================================}
unit StatementHistory;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, contnrs, laz2_DOM, laz2_XMLRead, laz2_XMLWrite,
  IbqError;

const
  { Name of the history file inside the configuration directory. }
  HistoryFileName = 'history.xml';
  { How many statements are kept before the oldest are discarded. }
  DefaultHistoryLimit = 500;
  { Statements longer than this are not remembered at all: a generated script
    of ten thousand lines is not something anyone recalls by scrolling, and
    keeping it would crowd out the statements they do want. }
  MaxRememberedLength = 20000;

type
  { TStatementHistoryEntry
    One remembered statement. }
  TStatementHistoryEntry = class(TObject)
  private
    FSql: string;
    FExecuted: TDateTime;
    FDatabase: string;
    FElapsedMs: Int64;
    FSucceeded: Boolean;
  public
    constructor Create(const ASql, ADatabase: string; AExecuted: TDateTime;
      AElapsedMs: Int64; ASucceeded: Boolean);

    { The statement squeezed onto one line, for a list box. }
    function OneLine(AMaxLength: Integer = 120): string;

    { The statement text as executed. }
    property Sql: string read FSql;
    { When it ran. }
    property Executed: TDateTime read FExecuted;
    { Which database it ran against. }
    property Database: string read FDatabase;
    { How long it took. }
    property ElapsedMs: Int64 read FElapsedMs;
    { False when the statement failed. }
    property Succeeded: Boolean read FSucceeded;
  end;

  { TStatementHistory
    The remembered statements, newest first. }
  TStatementHistory = class(TObject)
  private
    FEntries: TFPObjectList;
    FFileName: string;
    FLimit: Integer;
    FModified: Boolean;
    function GetCount: Integer;
    function GetEntry(AIndex: Integer): TStatementHistoryEntry;
  public
    constructor Create;
    destructor Destroy; override;

    { Remembers one statement.

      Parameters:
        ASql       - The statement as executed.
        ADatabase  - Which database it ran against.
        AElapsedMs - How long it took.
        ASucceeded - False when it failed.

      Notes:
        A statement identical to the most recent one is not added again:
        pressing F5 four times while adjusting nothing should leave one entry,
        not four. Failed statements ARE remembered - the one you want back is
        often the one that did not work. }
    procedure Add(const ASql, ADatabase: string; AElapsedMs: Int64;
      ASucceeded: Boolean);

    { Fills AIndexes with the positions of entries containing AText.

      Parameters:
        AText     - Text to look for, compared without regard to case. An empty
                    string matches everything.
        AIndexes  - Receives the matching positions, newest first. }
    procedure Search(const AText: string; AIndexes: TStrings);

    { Forgets everything. }
    procedure Clear;

    { Reads the history file. A missing file is not an error. }
    procedure Load;
    { Writes the history file if anything changed. }
    procedure SaveIfModified;

    { How many statements are remembered. }
    property Count: Integer read GetCount;
    { The entry at AIndex; 0 is the most recent. }
    property Entries[AIndex: Integer]: TStatementHistoryEntry read GetEntry;
      default;
    { Full path of the history file. }
    property FileName: string read FFileName write FFileName;
    { How many entries are kept. }
    property Limit: Integer read FLimit write FLimit;
  end;

{ Returns the application-wide statement history, creating it on first use. }
function History: TStatementHistory;

implementation

uses
  RegistrationStore;

var
  HistoryInstance: TStatementHistory = nil;

{------------------------------------------------------------------------------
  History
  ----------------------------------------------------------------------------
  Returns the single statement history.

  Returns:
    The instance, created and loaded on first call.
------------------------------------------------------------------------------}
function History: TStatementHistory;
begin
  if HistoryInstance = nil then
  begin
    HistoryInstance := TStatementHistory.Create;
    try
      HistoryInstance.Load;
    except
      // a damaged history file must never stop the program starting
    end;
  end;
  Result := HistoryInstance;
end;

{------------------------------------------------------------------------------
  TStatementHistoryEntry.Create
  ----------------------------------------------------------------------------
  Creates one remembered statement.

  Parameters:
    ASql       - The statement text.
    ADatabase  - The database it ran against.
    AExecuted  - When it ran.
    AElapsedMs - How long it took.
    ASucceeded - Whether it worked.
------------------------------------------------------------------------------}
constructor TStatementHistoryEntry.Create(const ASql, ADatabase: string;
  AExecuted: TDateTime; AElapsedMs: Int64; ASucceeded: Boolean);
begin
  inherited Create;
  FSql := ASql;
  FDatabase := ADatabase;
  FExecuted := AExecuted;
  FElapsedMs := AElapsedMs;
  FSucceeded := ASucceeded;
end;

{------------------------------------------------------------------------------
  TStatementHistoryEntry.OneLine
  ----------------------------------------------------------------------------
  Returns the statement squeezed onto a single line.

  Parameters:
    AMaxLength - Longest result; longer text is cut and an ellipsis added.

  Returns:
    The statement with runs of whitespace collapsed to single spaces, so a
    multi-line statement is recognisable in a one-line list.
------------------------------------------------------------------------------}
function TStatementHistoryEntry.OneLine(AMaxLength: Integer): string;
var
  I: Integer;
  WasSpace: Boolean;
  Ch: Char;
begin
  Result := '';
  WasSpace := False;

  for I := 1 to Length(FSql) do
  begin
    Ch := FSql[I];
    if Ch in [' ', #9, #13, #10] then
    begin
      if not WasSpace and (Result <> '') then
        Result := Result + ' ';
      WasSpace := True;
    end
    else
    begin
      Result := Result + Ch;
      WasSpace := False;
    end;
    if Length(Result) >= AMaxLength then
      Break;
  end;

  Result := TrimRight(Result);
  if Length(FSql) > Length(Result) then
    Result := Result + ' ...';
end;

{------------------------------------------------------------------------------
  TStatementHistory.Create
  ----------------------------------------------------------------------------
  Creates an empty history pointing at the default file.
------------------------------------------------------------------------------}
constructor TStatementHistory.Create;
begin
  inherited Create;
  FEntries := TFPObjectList.Create(True);
  FFileName := ConfigDir + HistoryFileName;
  FLimit := DefaultHistoryLimit;
  FModified := False;
end;

{------------------------------------------------------------------------------
  TStatementHistory.Destroy
  ----------------------------------------------------------------------------
  Releases the entries.

  Notes:
    Does not save. Saving on destruction would write during an unclean
    shutdown, when the in-memory state is the least trustworthy thing about the
    program.
------------------------------------------------------------------------------}
destructor TStatementHistory.Destroy;
begin
  FreeAndNil(FEntries);
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TStatementHistory.GetCount
  ----------------------------------------------------------------------------
  Returns how many statements are remembered.
------------------------------------------------------------------------------}
function TStatementHistory.GetCount: Integer;
begin
  Result := FEntries.Count;
end;

{------------------------------------------------------------------------------
  TStatementHistory.GetEntry
  ----------------------------------------------------------------------------
  Returns the entry at AIndex, 0 being the most recent.
------------------------------------------------------------------------------}
function TStatementHistory.GetEntry(
  AIndex: Integer): TStatementHistoryEntry;
begin
  Result := TStatementHistoryEntry(FEntries[AIndex]);
end;

{------------------------------------------------------------------------------
  TStatementHistory.Add
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
procedure TStatementHistory.Add(const ASql, ADatabase: string;
  AElapsedMs: Int64; ASucceeded: Boolean);
var
  Trimmed: string;
begin
  Trimmed := Trim(ASql);
  if Trimmed = '' then
    Exit;
  if Length(Trimmed) > MaxRememberedLength then
    Exit;

  if (FEntries.Count > 0) and (Entries[0].Sql = Trimmed) then
    Exit;

  FEntries.Insert(0, TStatementHistoryEntry.Create(Trimmed, ADatabase, Now,
    AElapsedMs, ASucceeded));

  while FEntries.Count > FLimit do
    FEntries.Delete(FEntries.Count - 1);

  FModified := True;
end;

{------------------------------------------------------------------------------
  TStatementHistory.Search
  ----------------------------------------------------------------------------
  See the interface section for the description.

  Notes:
    Positions are returned rather than entries, so the caller can show what it
    likes and still reach the full statement. The list is already newest first,
    so no sorting is needed.
------------------------------------------------------------------------------}
procedure TStatementHistory.Search(const AText: string; AIndexes: TStrings);
var
  I: Integer;
  Needle: string;
begin
  AIndexes.Clear;
  Needle := Trim(AText);

  for I := 0 to FEntries.Count - 1 do
  begin
    if (Needle = '') or
       (Pos(UpperCase(Needle), UpperCase(Entries[I].Sql)) > 0) then
      AIndexes.AddObject(Entries[I].OneLine, TObject(PtrInt(I)));
  end;
end;

{------------------------------------------------------------------------------
  TStatementHistory.Clear
  ----------------------------------------------------------------------------
  Forgets every remembered statement.
------------------------------------------------------------------------------}
procedure TStatementHistory.Clear;
begin
  FEntries.Clear;
  FModified := True;
end;

{------------------------------------------------------------------------------
  TStatementHistory.Load
  ----------------------------------------------------------------------------
  Reads the history file.

  Notes:
    A missing file means a first run. A malformed one is reported by raising,
    but the singleton accessor swallows that: a damaged history is an
    annoyance, not a reason to refuse to start.

  Raises:
    EIbqConfigError - The file exists but cannot be parsed.
------------------------------------------------------------------------------}
procedure TStatementHistory.Load;
var
  Doc: TXMLDocument;
  Root, Node: TDOMNode;
  Element: TDOMElement;
  Executed: TDateTime;
begin
  Clear;
  FModified := False;

  if not FileExists(FFileName) then
    Exit;

  Doc := nil;
  try
    try
      ReadXMLFile(Doc, FFileName);
    except
      on E: Exception do
        raise EIbqConfigError.CreateFmt(
          'The statement history file "%s" could not be read: %s',
          [FFileName, E.Message]);
    end;

    Root := Doc.DocumentElement;
    if Root = nil then
      Exit;

    Node := Root.FirstChild;
    while Node <> nil do
    begin
      if (Node.NodeType = ELEMENT_NODE) and
         SameText(Node.NodeName, 'statement') then
      begin
        Element := TDOMElement(Node);
        Executed := StrToFloatDef(Element.GetAttribute('executed'), 0);
        FEntries.Add(TStatementHistoryEntry.Create(
          Element.TextContent,
          Element.GetAttribute('database'),
          Executed,
          StrToInt64Def(Element.GetAttribute('elapsed'), 0),
          not SameText(Element.GetAttribute('failed'), 'true')));
      end;
      Node := Node.NextSibling;
    end;
  finally
    Doc.Free;
  end;

  FModified := False;
end;

{------------------------------------------------------------------------------
  TStatementHistory.SaveIfModified
  ----------------------------------------------------------------------------
  Writes the history file when something changed.

  Notes:
    The timestamp is written as a raw TDateTime rather than as formatted text,
    so that reading it back cannot depend on the user's locale. A history file
    copied between machines with different date settings must still load.

  Raises:
    EIbqConfigError - The file cannot be written.
------------------------------------------------------------------------------}
procedure TStatementHistory.SaveIfModified;
var
  Doc: TXMLDocument;
  Root, Node: TDOMElement;
  I: Integer;
  Directory: string;
begin
  if not FModified then
    Exit;

  Directory := ExtractFilePath(FFileName);
  if (Directory <> '') and not DirectoryExists(Directory) then
  begin
    if not ForceDirectories(Directory) then
      raise EIbqConfigError.CreateFmt(
        'The configuration directory "%s" could not be created.', [Directory]);
  end;

  Doc := TXMLDocument.Create;
  try
    Root := Doc.CreateElement('ibqconsole-history');
    Doc.AppendChild(Root);

    for I := 0 to FEntries.Count - 1 do
    begin
      Node := Doc.CreateElement('statement');
      Root.AppendChild(Node);
      Node.SetAttribute('executed', FloatToStr(Entries[I].Executed));
      Node.SetAttribute('database', Entries[I].Database);
      Node.SetAttribute('elapsed', IntToStr(Entries[I].ElapsedMs));
      if not Entries[I].Succeeded then
        Node.SetAttribute('failed', 'true');
      Node.AppendChild(Doc.CreateTextNode(Entries[I].Sql));
    end;

    try
      WriteXMLFile(Doc, FFileName);
    except
      on E: Exception do
        raise EIbqConfigError.CreateFmt(
          'The statement history file "%s" could not be written: %s',
          [FFileName, E.Message]);
    end;
  finally
    Doc.Free;
  end;

  FModified := False;
end;

finalization
  FreeAndNil(HistoryInstance);

end.
