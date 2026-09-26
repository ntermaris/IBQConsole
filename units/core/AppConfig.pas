{==============================================================================
  Unit:        AppConfig
  Purpose:     The user's preferences, read at startup and written when they
               change.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, laz2_DOM, laz2_XMLRead, laz2_XMLWrite,
               IbqError, AppLog

  IBConsole equivalent: Edit > Options.

  WHERE IT LIVES
  preferences.xml, beside registrations.xml in the same configuration
  directory. Two files rather than one because they answer to different
  owners: the registrations are the user's data and are worth backing up,
  while the preferences are how this machine happens to be set up and are
  worth losing.

  EVERY SETTING HERE CHANGES SOMETHING
  There is no setting in this unit that nothing reads. A preferences dialog
  full of switches that do nothing is worse than no dialog at all, because it
  makes the whole program look like it is not listening. When a setting is
  added here, the code that obeys it is added in the same edit.

  A MISSING OR BROKEN FILE IS NOT AN ERROR
  First run has no file, and a file damaged by a disk or an editor is not
  something the user can act on. Either way the defaults are used and the
  program starts. Refusing to start because a preference could not be read
  would be losing the whole program to protect a font size.
==============================================================================}
unit AppConfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, laz2_DOM, laz2_XMLRead, laz2_XMLWrite,
  IbqError, AppLog;

const
  { Name of the preferences file inside the configuration directory. }
  PreferencesFileName = 'preferences.xml';

  { The language used until the user chooses another. }
  DefaultLanguage = 'English';
  { The font the SQL editor and the other code views start with. }
  DefaultEditorFontName = 'Courier New';
  { Its size in points. }
  DefaultEditorFontSize = 10;
  { How many rows the data grid asks a table for. }
  DefaultDataRowLimit = 500;
  { The smallest and largest row limits the dialog will accept. Below the
    first a grid is useless; above the second the wait is long enough that the
    user should be writing a query instead. }
  MinDataRowLimit = 1;
  MaxDataRowLimit = 100000;
  { The smallest and largest editor font sizes the dialog will accept. }
  MinEditorFontSize = 6;
  MaxEditorFontSize = 32;

type
  { TAppConfig
    The user's preferences.

    Owns nothing but its own file name. There is one instance, reached through
    the Config function, in the same way the log is reached through Log. }
  TAppConfig = class(TObject)
  private
    FFileName: string;
    FLanguage: string;
    FEditorFontName: string;
    FEditorFontSize: Integer;
    FDataRowLimit: Integer;
    FShowSystemObjects: Boolean;
    FShowLog: Boolean;
    FWindowLeft: Integer;
    FWindowTop: Integer;
    FWindowWidth: Integer;
    FWindowHeight: Integer;
    FWindowMaximized: Boolean;
    FModified: Boolean;
    { Returns the text of ANode's child element named AName. }
    function ChildText(ANode: TDOMNode; const AName: string): string;
    { Returns the child text as an integer, clamped between two bounds. }
    function ChildInt(ANode: TDOMNode; const AName: string;
      ADefault, AMin, AMax: Integer): Integer;
    { Returns the child text as a boolean. }
    function ChildBool(ANode: TDOMNode; const AName: string;
      ADefault: Boolean): Boolean;
    { Adds a child element holding a value. }
    procedure AddChild(ADoc: TXMLDocument; AParent: TDOMElement;
      const AName, AValue: string);
    procedure SetLanguage(const AValue: string);
    procedure SetEditorFontName(const AValue: string);
    procedure SetEditorFontSize(AValue: Integer);
    procedure SetDataRowLimit(AValue: Integer);
    procedure SetShowSystemObjects(AValue: Boolean);
    procedure SetShowLog(AValue: Boolean);
  public
    constructor Create;

    { Puts every setting back to the value it has on a fresh installation. }
    procedure ResetToDefaults;

    { Reads the preferences file, falling back to the defaults for anything
      missing.

      Notes:
        Never raises. A file that will not parse is logged and the defaults
        are used, because a preference is not worth failing to start over. }
    procedure Load;

    { Writes the preferences file.

      Raises:
        EIbqConfigError - The file cannot be written. }
    procedure Save;

    { Writes the file only when something changed since it was last read or
      written. }
    procedure SaveIfModified;

    { Records that something changed, so the next SaveIfModified writes. }
    procedure MarkModified;

    { Remembers where the main window was.

      Parameters:
        ALeft, ATop, AWidth, AHeight - The window's bounds when NOT maximised.
        AMaximized                   - True when it was maximised.

      Notes:
        The bounds are the restored ones even when the window is maximised, so
        that un-maximising after a restart puts the window back where the user
        left it rather than at some default. }
    procedure StoreWindowState(ALeft, ATop, AWidth, AHeight: Integer;
      AMaximized: Boolean);

    { True when a usable window position was read or stored. A first run has
      none, and the window should then position itself. }
    function HasWindowState: Boolean;

    { Full path of the preferences file. }
    property FileName: string read FFileName write FFileName;
    { True when something changed since the last read or write. }
    property Modified: Boolean read FModified;

    { The language to start in, by name, as the language files call it. }
    property Language: string read FLanguage write SetLanguage;
    { The font the SQL editor and the DDL views use. }
    property EditorFontName: string read FEditorFontName
      write SetEditorFontName;
    { Its size in points. }
    property EditorFontSize: Integer read FEditorFontSize
      write SetEditorFontSize;
    { How many rows the data grid asks a table for. }
    property DataRowLimit: Integer read FDataRowLimit write SetDataRowLimit;
    { True when the tree shows Firebird's own objects. }
    property ShowSystemObjects: Boolean read FShowSystemObjects
      write SetShowSystemObjects;
    { True when the log panel is open. }
    property ShowLog: Boolean read FShowLog write SetShowLog;

    { Where the main window was last. }
    property WindowLeft: Integer read FWindowLeft;
    property WindowTop: Integer read FWindowTop;
    property WindowWidth: Integer read FWindowWidth;
    property WindowHeight: Integer read FWindowHeight;
    { True when the main window was maximised. }
    property WindowMaximized: Boolean read FWindowMaximized;
  end;

{ Returns the application-wide preferences, creating them on first use. }
function Config: TAppConfig;

implementation

uses
  RegistrationStore;

var
  ConfigInstance: TAppConfig = nil;

{------------------------------------------------------------------------------
  Config
  ----------------------------------------------------------------------------
  Returns the single preferences object.

  Returns:
    The instance, created on first call and freed at shutdown.

  Notes:
    Created empty, at the defaults. Loading is the program's decision and
    happens once at startup, so that a unit reading a preference in its
    initialization cannot accidentally trigger a file read.
------------------------------------------------------------------------------}
function Config: TAppConfig;
begin
  if ConfigInstance = nil then
  begin
    ConfigInstance := TAppConfig.Create;
  end;
  Result := ConfigInstance;
end;

{------------------------------------------------------------------------------
  TAppConfig.Create
  ----------------------------------------------------------------------------
  Creates the preferences at their defaults, naming the file they live in.
------------------------------------------------------------------------------}
constructor TAppConfig.Create;
begin
  inherited Create;
  FFileName := ConfigDir + PreferencesFileName;
  ResetToDefaults;
  FModified := False;
end;

{------------------------------------------------------------------------------
  TAppConfig.ResetToDefaults
  ----------------------------------------------------------------------------
  Puts every setting back to the value it has on a fresh installation.

  Notes:
    Marks the preferences modified, so that pressing Restore Defaults and then
    OK actually writes them. Without that, resetting and saving would leave
    the old file in place and the reset would come undone at the next start.
------------------------------------------------------------------------------}
procedure TAppConfig.ResetToDefaults;
begin
  FLanguage := DefaultLanguage;
  FEditorFontName := DefaultEditorFontName;
  FEditorFontSize := DefaultEditorFontSize;
  FDataRowLimit := DefaultDataRowLimit;
  FShowSystemObjects := False;
  FShowLog := True;
  FWindowLeft := 0;
  FWindowTop := 0;
  FWindowWidth := 0;
  FWindowHeight := 0;
  FWindowMaximized := False;
  FModified := True;
end;

{------------------------------------------------------------------------------
  TAppConfig.MarkModified
  ----------------------------------------------------------------------------
  Records that something changed, so the next SaveIfModified writes.
------------------------------------------------------------------------------}
procedure TAppConfig.MarkModified;
begin
  FModified := True;
end;

{------------------------------------------------------------------------------
  TAppConfig.SetLanguage
  ----------------------------------------------------------------------------
  Sets the startup language, marking the preferences modified.

  Parameters:
    AValue - The language name, as the language files call it.
------------------------------------------------------------------------------}
procedure TAppConfig.SetLanguage(const AValue: string);
begin
  if FLanguage = AValue then
  begin
    Exit;
  end;
  FLanguage := AValue;
  FModified := True;
end;

{------------------------------------------------------------------------------
  TAppConfig.SetEditorFontName
  ----------------------------------------------------------------------------
  Sets the editor font, marking the preferences modified.

  Parameters:
    AValue - The font name; an empty one falls back to the default.
------------------------------------------------------------------------------}
procedure TAppConfig.SetEditorFontName(const AValue: string);
var
  Wanted: string;
begin
  Wanted := Trim(AValue);
  if Wanted = '' then
  begin
    Wanted := DefaultEditorFontName;
  end;
  if FEditorFontName = Wanted then
  begin
    Exit;
  end;
  FEditorFontName := Wanted;
  FModified := True;
end;

{------------------------------------------------------------------------------
  TAppConfig.SetEditorFontSize
  ----------------------------------------------------------------------------
  Sets the editor font size, marking the preferences modified.

  Parameters:
    AValue - The size in points, clamped to what the dialog allows.
------------------------------------------------------------------------------}
procedure TAppConfig.SetEditorFontSize(AValue: Integer);
var
  Wanted: Integer;
begin
  Wanted := AValue;
  if Wanted < MinEditorFontSize then
  begin
    Wanted := MinEditorFontSize;
  end;
  if Wanted > MaxEditorFontSize then
  begin
    Wanted := MaxEditorFontSize;
  end;
  if FEditorFontSize = Wanted then
  begin
    Exit;
  end;
  FEditorFontSize := Wanted;
  FModified := True;
end;

{------------------------------------------------------------------------------
  TAppConfig.SetDataRowLimit
  ----------------------------------------------------------------------------
  Sets how many rows the data grid fetches, marking the preferences modified.

  Parameters:
    AValue - The row count, clamped to what the dialog allows.
------------------------------------------------------------------------------}
procedure TAppConfig.SetDataRowLimit(AValue: Integer);
var
  Wanted: Integer;
begin
  Wanted := AValue;
  if Wanted < MinDataRowLimit then
  begin
    Wanted := MinDataRowLimit;
  end;
  if Wanted > MaxDataRowLimit then
  begin
    Wanted := MaxDataRowLimit;
  end;
  if FDataRowLimit = Wanted then
  begin
    Exit;
  end;
  FDataRowLimit := Wanted;
  FModified := True;
end;

{------------------------------------------------------------------------------
  TAppConfig.SetShowSystemObjects
  ----------------------------------------------------------------------------
  Sets whether the tree shows Firebird's own objects.

  Parameters:
    AValue - True to show them.
------------------------------------------------------------------------------}
procedure TAppConfig.SetShowSystemObjects(AValue: Boolean);
begin
  if FShowSystemObjects = AValue then
  begin
    Exit;
  end;
  FShowSystemObjects := AValue;
  FModified := True;
end;

{------------------------------------------------------------------------------
  TAppConfig.SetShowLog
  ----------------------------------------------------------------------------
  Sets whether the log panel is open.

  Parameters:
    AValue - True to show it.
------------------------------------------------------------------------------}
procedure TAppConfig.SetShowLog(AValue: Boolean);
begin
  if FShowLog = AValue then
  begin
    Exit;
  end;
  FShowLog := AValue;
  FModified := True;
end;

{------------------------------------------------------------------------------
  TAppConfig.StoreWindowState
  ----------------------------------------------------------------------------
  Remembers where the main window was.

  Parameters:
    ALeft, ATop, AWidth, AHeight - The restored bounds.
    AMaximized                   - True when it was maximised.
------------------------------------------------------------------------------}
procedure TAppConfig.StoreWindowState(ALeft, ATop, AWidth, AHeight: Integer;
  AMaximized: Boolean);
begin
  if (FWindowLeft = ALeft) and (FWindowTop = ATop) and
     (FWindowWidth = AWidth) and (FWindowHeight = AHeight) and
     (FWindowMaximized = AMaximized) then
  begin
    Exit;
  end;
  FWindowLeft := ALeft;
  FWindowTop := ATop;
  FWindowWidth := AWidth;
  FWindowHeight := AHeight;
  FWindowMaximized := AMaximized;
  FModified := True;
end;

{------------------------------------------------------------------------------
  TAppConfig.HasWindowState
  ----------------------------------------------------------------------------
  Returns True when a usable window position was read or stored.

  Returns:
    False on a first run, when the window should position itself.
------------------------------------------------------------------------------}
function TAppConfig.HasWindowState: Boolean;
begin
  Result := (FWindowWidth > 0) and (FWindowHeight > 0);
end;

{------------------------------------------------------------------------------
  TAppConfig.ChildText
  ----------------------------------------------------------------------------
  Returns the text of ANode's child element named AName.

  Parameters:
    ANode - The element to look under.
    AName - The child wanted.

  Returns:
    The child's text, trimmed, or an empty string when there is no such child.
------------------------------------------------------------------------------}
function TAppConfig.ChildText(ANode: TDOMNode; const AName: string): string;
var
  Child: TDOMNode;
begin
  Result := '';
  if ANode = nil then
  begin
    Exit;
  end;
  Child := ANode.FirstChild;
  while Child <> nil do
  begin
    if (Child.NodeType = ELEMENT_NODE) and SameText(Child.NodeName, AName) then
    begin
      Exit(Trim(Child.TextContent));
    end;
    Child := Child.NextSibling;
  end;
end;

{------------------------------------------------------------------------------
  TAppConfig.ChildInt
  ----------------------------------------------------------------------------
  Returns the child text as an integer, clamped between two bounds.

  Parameters:
    ANode    - The element to look under.
    AName    - The child wanted.
    ADefault - What to return when it is absent or not a number.
    AMin     - The smallest value accepted.
    AMax     - The largest value accepted.

  Returns:
    The value, never outside the bounds.

  Notes:
    Clamped rather than rejected, because a file edited by hand is the usual
    source of an out-of-range number and the user's intent is obvious.
------------------------------------------------------------------------------}
function TAppConfig.ChildInt(ANode: TDOMNode; const AName: string;
  ADefault, AMin, AMax: Integer): Integer;
begin
  Result := StrToIntDef(ChildText(ANode, AName), ADefault);
  if Result < AMin then
  begin
    Result := AMin;
  end;
  if Result > AMax then
  begin
    Result := AMax;
  end;
end;

{------------------------------------------------------------------------------
  TAppConfig.ChildBool
  ----------------------------------------------------------------------------
  Returns the child text as a boolean.

  Parameters:
    ANode    - The element to look under.
    AName    - The child wanted.
    ADefault - What to return when it is absent.

  Returns:
    True for 'true' or '1', False for anything else that was written.
------------------------------------------------------------------------------}
function TAppConfig.ChildBool(ANode: TDOMNode; const AName: string;
  ADefault: Boolean): Boolean;
var
  Text: string;
begin
  Text := ChildText(ANode, AName);
  if Text = '' then
  begin
    Exit(ADefault);
  end;
  Result := SameText(Text, 'true') or (Text = '1');
end;

{------------------------------------------------------------------------------
  TAppConfig.AddChild
  ----------------------------------------------------------------------------
  Adds a child element holding a value.

  Parameters:
    ADoc    - The document being built.
    AParent - The element to add to.
    AName   - The element name.
    AValue  - Its text.
------------------------------------------------------------------------------}
procedure TAppConfig.AddChild(ADoc: TXMLDocument; AParent: TDOMElement;
  const AName, AValue: string);
var
  Node: TDOMElement;
begin
  Node := ADoc.CreateElement(AName);
  Node.AppendChild(ADoc.CreateTextNode(AValue));
  AParent.AppendChild(Node);
end;

{------------------------------------------------------------------------------
  TAppConfig.Load
  ----------------------------------------------------------------------------
  Reads the preferences file, falling back to the defaults for anything
  missing.

  Notes:
    Never raises. Every value is read through a helper that supplies a default
    and clamps a range, so a file that is present but half-written still
    yields a usable set of preferences.
------------------------------------------------------------------------------}
procedure TAppConfig.Load;
var
  Doc: TXMLDocument;
  Root: TDOMNode;
begin
  ResetToDefaults;
  FModified := False;

  if not FileExists(FFileName) then
  begin
    Exit;
  end;

  Doc := nil;
  try
    try
      ReadXMLFile(Doc, FFileName);
    except
      on E: Exception do
      begin
        Log.Warning(Format('Preferences at %s could not be read (%s); ' +
          'the defaults are in use.', [FFileName, E.Message]));
        Exit;
      end;
    end;

    if (Doc = nil) or (Doc.DocumentElement = nil) then
    begin
      Exit;
    end;
    Root := Doc.DocumentElement;

    FLanguage := ChildText(Root, 'Language');
    if FLanguage = '' then
    begin
      FLanguage := DefaultLanguage;
    end;

    FEditorFontName := ChildText(Root, 'EditorFontName');
    if FEditorFontName = '' then
    begin
      FEditorFontName := DefaultEditorFontName;
    end;

    FEditorFontSize := ChildInt(Root, 'EditorFontSize',
      DefaultEditorFontSize, MinEditorFontSize, MaxEditorFontSize);
    FDataRowLimit := ChildInt(Root, 'DataRowLimit',
      DefaultDataRowLimit, MinDataRowLimit, MaxDataRowLimit);
    FShowSystemObjects := ChildBool(Root, 'ShowSystemObjects', False);
    FShowLog := ChildBool(Root, 'ShowLog', True);

    FWindowLeft := ChildInt(Root, 'WindowLeft', 0, -32000, 32000);
    FWindowTop := ChildInt(Root, 'WindowTop', 0, -32000, 32000);
    FWindowWidth := ChildInt(Root, 'WindowWidth', 0, 0, 32000);
    FWindowHeight := ChildInt(Root, 'WindowHeight', 0, 0, 32000);
    FWindowMaximized := ChildBool(Root, 'WindowMaximized', False);

    FModified := False;
  finally
    Doc.Free;
  end;
end;

{------------------------------------------------------------------------------
  TAppConfig.Save
  ----------------------------------------------------------------------------
  Writes the preferences file.

  Raises:
    EIbqConfigError - The directory or the file cannot be written.

  Notes:
    Creates the configuration directory when it is not there, which on a first
    run it is not.
------------------------------------------------------------------------------}
procedure TAppConfig.Save;
var
  Doc: TXMLDocument;
  Root: TDOMElement;
  Directory: string;
begin
  Directory := ExtractFilePath(FFileName);
  if (Directory <> '') and not DirectoryExists(Directory) then
  begin
    if not ForceDirectories(Directory) then
    begin
      raise EIbqConfigError.CreateFmt(
        'The configuration directory %s could not be created.', [Directory]);
    end;
  end;

  Doc := TXMLDocument.Create;
  try
    Root := Doc.CreateElement('IBQConsolePreferences');
    Doc.AppendChild(Root);

    AddChild(Doc, Root, 'Language', FLanguage);
    AddChild(Doc, Root, 'EditorFontName', FEditorFontName);
    AddChild(Doc, Root, 'EditorFontSize', IntToStr(FEditorFontSize));
    AddChild(Doc, Root, 'DataRowLimit', IntToStr(FDataRowLimit));
    AddChild(Doc, Root, 'ShowSystemObjects',
      LowerCase(BoolToStr(FShowSystemObjects, True)));
    AddChild(Doc, Root, 'ShowLog', LowerCase(BoolToStr(FShowLog, True)));
    AddChild(Doc, Root, 'WindowLeft', IntToStr(FWindowLeft));
    AddChild(Doc, Root, 'WindowTop', IntToStr(FWindowTop));
    AddChild(Doc, Root, 'WindowWidth', IntToStr(FWindowWidth));
    AddChild(Doc, Root, 'WindowHeight', IntToStr(FWindowHeight));
    AddChild(Doc, Root, 'WindowMaximized',
      LowerCase(BoolToStr(FWindowMaximized, True)));

    try
      WriteXMLFile(Doc, FFileName);
    except
      on E: Exception do
      begin
        raise EIbqConfigError.CreateFmt(
          'The preferences could not be written to %s: %s',
          [FFileName, E.Message]);
      end;
    end;
  finally
    Doc.Free;
  end;

  FModified := False;
end;

{------------------------------------------------------------------------------
  TAppConfig.SaveIfModified
  ----------------------------------------------------------------------------
  Writes the file only when something changed.

  Raises:
    EIbqConfigError - The file cannot be written.
------------------------------------------------------------------------------}
procedure TAppConfig.SaveIfModified;
begin
  if FModified then
  begin
    Save;
  end;
end;

finalization
  FreeAndNil(ConfigInstance);

end.
