{==============================================================================
  Unit:        LanguageHandle
  Purpose:     Runtime translation of the user interface from plain-text .lng
               language files. English text is embedded in the code as the
               default of every lookup, so no English.lng exists and an
               untranslated key always degrades to readable English.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  IniFiles, ActnList, Forms
  Origin:      Same logic as Teramon's units/languagehandle.pas, extended with
               ILocalizable so every open form re-translates on a language
               change, not just the main form.

  Note on the coding rules: PASCAL-LAZARUS-RULES.md wants one public class per
  unit. This unit is deliberately a set of global routines instead, to stay
  identical in use to the Teramon original (LangStr / ResetLang / LoadLangStr).
  The exception is intentional and limited to this unit.
==============================================================================}
unit LanguageHandle;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, ActnList, Forms;

type
  { ILocalizable
    Implemented by every form that has translatable text. ApplyLocale calls
    LoadLangStr on each open form that supports this interface, which is what
    makes switching language at runtime work without restarting.

    A form implements it by declaring the interface and one method:

      TfrmMain = class(TForm, ILocalizable)
      public
        procedure LoadLangStr;
      end; }
  ILocalizable = interface
    ['{7A1C4E62-9D3B-4F58-B0A1-2E6C5D8F4A31}']
    { Re-reads every caption, hint and column title from the active language. }
    procedure LoadLangStr;
  end;

const
  { Extension of a language file, e.g. lang/Greek.lng }
  LANG_FILE_EXT = '.lng';
  { Folder holding the language files, relative to the executable }
  LANG_FOLDER = 'lang';
  { INI section holding the translated strings }
  LANG_SECTION_STRINGS = 'Strings';
  { INI section holding per-language font overrides }
  LANG_SECTION_FONTS = 'Fonts';
  { Placeholder used inside a .lng value to mean a line break }
  LANG_NEWLINE_TOKEN = '$nl';

var
  { Full path of the language file currently in use. Empty means English. }
  LangFile: string = '';
  { Lazily created cache over LangFile. Never access directly - use LangStr. }
  LangIni: TMemIniFile = nil;

{ Returns the full path of the folder holding the .lng files. }
function LanguageDir: string;

{ Returns the name of the active language ('Greek'), or 'English' when no
  language file is loaded. }
function CurrentLanguage: string;

{ Fills AList with the names of the languages found in the language folder,
  without path or extension, sorted. 'English' is always the first entry
  because it needs no file. }
procedure ListAvailableLanguages(AList: TStrings);

{ Discards the cached language file and points at ANewLangFile. Pass an empty
  string to fall back to the English defaults compiled into the code. Does not
  refresh any form - call ApplyLocale afterwards, or use SetLanguage. }
procedure ResetLang(const ANewLangFile: string);

{ Switches to ALanguageName ('Greek', or 'English' for the built-in text) and
  re-translates every open form. This is the one call the Options dialog needs. }
procedure SetLanguage(const ALanguageName: string);

{ Returns the translated text for AKey.

  Parameters:
    AKey         - Key inside the [Strings] section, e.g. 'mnuFile.caption'.
    ADefaultText - English text to use when the key is missing. Always pass it;
                   it is the English version of the application.

  Returns:
    The translated text, with $nl expanded to a line break, or ADefaultText
    when the key is absent or empty. }
function LangStr(const AKey: string; const ADefaultText: string = ''): string;

{ Same as LangStr, with SysUtils.Format applied to the result.

  Parameters:
    AKey         - Key inside the [Strings] section.
    AArgs        - Format arguments.
    ADefaultText - English format string used when the key is missing. }
function LangStrFormat(const AKey: string; const AArgs: array of const;
  const ADefaultText: string = ''): string;

{ Returns a per-language font setting from the [Fonts] section.

  Parameters:
    AKey     - e.g. 'DialogFontName' or 'DialogFontSize'.
    ADefault - Value to return when the key or the file is missing. }
function LangFontStr(const AKey, ADefault: string): string;

{ Assigns caption and hint to AAction from one pipe-delimited key whose value
  has the form 'Caption|ShortCut|Hint'. Missing parts are left unchanged. }
procedure AssignActionText(AAction: TAction; const AKey: string);

{ Calls LoadLangStr on every open form that implements ILocalizable. Safe to
  call at any time; forms that do not implement it are skipped. }
procedure ApplyLocale;

{ Calls LoadLangStr on AForm alone, when it implements ILocalizable. Use this
  from a form's OnCreate so a newly opened form picks up the active language. }
procedure ApplyLocaleTo(AForm: TCustomForm);

{ Replaces every occurrence of AVarName in AText with ANewValue. }
function ChangeVar(const AText, AVarName, ANewValue: string): string;

{ Removes and returns everything in AText up to the first ADelim, leaving the
  remainder in AText. Returns all of AText when ADelim is not present. }
function ExtractStr(var AText: string; const ADelim: string): string;

implementation

{------------------------------------------------------------------------------
  LanguageDir
  ----------------------------------------------------------------------------
  Returns the full path of the folder holding the .lng files, with a trailing
  path delimiter.

  Returns:
    The first candidate folder that exists, or the one beside the executable
    when none does - so the answer is always a usable path to report.

  Notes:
    Beside the executable FIRST, because that is where a portable install
    keeps its translations and a deployed copy must never prefer some other
    folder that happens to be nearby.

    Then the two directories above it, which is where the project's own lang/
    sits when the program is run from bin/<mode>/ during development. Without
    this the built program silently found no language files at all and the
    menu offered only English - and because a missing translation falls back
    to English by design, nothing ever reported it. That is the whole reason
    this routine is more than one line.
------------------------------------------------------------------------------}
function LanguageDir: string;
var
  ExeDir: string;
  Candidate: string;
  Level: Integer;
begin
  ExeDir := ExtractFilePath(ParamStr(0));
  Result := IncludeTrailingPathDelimiter(ExeDir + LANG_FOLDER);

  Candidate := ExeDir;
  for Level := 0 to 2 do
  begin
    if DirectoryExists(Candidate + LANG_FOLDER) then
    begin
      Exit(IncludeTrailingPathDelimiter(Candidate + LANG_FOLDER));
    end;
    Candidate := IncludeTrailingPathDelimiter(
      ExpandFileName(Candidate + '..'));
  end;
end;

{------------------------------------------------------------------------------
  CreateLangIfNil
  ----------------------------------------------------------------------------
  Creates the TMemIniFile cache over LangFile on first use. A missing file is
  not an error: TMemIniFile yields an empty set of keys and every lookup then
  falls back to its English default.
------------------------------------------------------------------------------}
procedure CreateLangIfNil;
begin
  if LangIni = nil then
    LangIni := TMemIniFile.Create(LangFile);
end;

{------------------------------------------------------------------------------
  CurrentLanguage
  ----------------------------------------------------------------------------
  Returns the active language name, derived from the loaded file name.

  Returns:
    The file's base name ('Greek'), or 'English' when no file is loaded.
------------------------------------------------------------------------------}
function CurrentLanguage: string;
begin
  if LangFile = '' then
    Result := 'English'
  else
    Result := ChangeFileExt(ExtractFileName(LangFile), '');
end;

{------------------------------------------------------------------------------
  ListAvailableLanguages
  ----------------------------------------------------------------------------
  Fills AList with the selectable languages.

  Parameters:
    AList - Receives the language names. Cleared first.

  Notes:
    'English' is added unconditionally as the first entry because it is the
    text compiled into the program and needs no file on disk.
------------------------------------------------------------------------------}
procedure ListAvailableLanguages(AList: TStrings);
var
  Found: TStringList;
  Search: TSearchRec;
begin
  AList.Clear;
  AList.Add('English');

  Found := TStringList.Create;
  try
    Found.Sorted := True;
    if FindFirst(LanguageDir + '*' + LANG_FILE_EXT, faAnyFile, Search) = 0 then
    begin
      repeat
        if (Search.Attr and faDirectory) = 0 then
          Found.Add(ChangeFileExt(Search.Name, ''));
      until FindNext(Search) <> 0;
      FindClose(Search);
    end;
    AList.AddStrings(Found);
  finally
    Found.Free;
  end;
end;

{------------------------------------------------------------------------------
  ResetLang
  ----------------------------------------------------------------------------
  Drops the cached language file and points at a new one.

  Parameters:
    ANewLangFile - Full path of the .lng file, or an empty string for English.

  Notes:
    The new file is not read here; the next LangStr call reads it. Forms are
    not refreshed - call ApplyLocale, or use SetLanguage which does both.
------------------------------------------------------------------------------}
procedure ResetLang(const ANewLangFile: string);
begin
  FreeAndNil(LangIni);
  LangFile := ANewLangFile;
end;

{------------------------------------------------------------------------------
  SetLanguage
  ----------------------------------------------------------------------------
  Switches the whole user interface to another language, immediately.

  Parameters:
    ALanguageName - Language name without path or extension, e.g. 'Greek'.
                    'English' (or an empty string) restores the built-in text.

  Notes:
    A name with no matching file also falls back to English rather than
    showing raw keys.
------------------------------------------------------------------------------}
procedure SetLanguage(const ALanguageName: string);
var
  FileName: string;
begin
  if (ALanguageName = '') or SameText(ALanguageName, 'English') then
    ResetLang('')
  else
  begin
    FileName := LanguageDir + ALanguageName + LANG_FILE_EXT;
    if FileExists(FileName) then
      ResetLang(FileName)
    else
      ResetLang('');
  end;
  ApplyLocale;
end;

{------------------------------------------------------------------------------
  LangStr
  ----------------------------------------------------------------------------
  Looks up one translated string.

  Parameters:
    AKey         - Key inside [Strings].
    ADefaultText - English text used when the key is missing or empty.

  Returns:
    The translated text with $nl expanded to CR/LF, otherwise ADefaultText.

  Notes:
    A key may also be stored prefixed with 'n_' - the convention inherited from
    Teramon for entries a translator has reviewed but left in English. Both
    spellings are accepted.
------------------------------------------------------------------------------}
function LangStr(const AKey: string; const ADefaultText: string = ''): string;
var
  Value: string;
begin
  Result := ADefaultText;
  if AKey = '' then
    Exit;

  if LangFile = '' then
    Exit;                      // English: the default text is the answer

  CreateLangIfNil;
  Value := LangIni.ReadString(LANG_SECTION_STRINGS, AKey, '');
  if Value = '' then
    Value := LangIni.ReadString(LANG_SECTION_STRINGS, 'n_' + AKey, '');
  if Value = '' then
    Exit;                      // untranslated: keep the English default

  Result := ChangeVar(Value, LANG_NEWLINE_TOKEN, sLineBreak);
end;

{------------------------------------------------------------------------------
  LangStrFormat
  ----------------------------------------------------------------------------
  Looks up a translated format string and applies arguments to it.

  Parameters:
    AKey         - Key inside [Strings].
    AArgs        - Format arguments.
    ADefaultText - English format string used when the key is missing.

  Returns:
    The formatted text.

  Raises:
    EConvertError - The translated string has placeholders that do not match
                    AArgs. Caught and reported as the untranslated default, so
                    a bad translation cannot crash the program.
------------------------------------------------------------------------------}
function LangStrFormat(const AKey: string; const AArgs: array of const;
  const ADefaultText: string = ''): string;
var
  Template: string;
begin
  Template := LangStr(AKey, ADefaultText);
  try
    Result := Format(Template, AArgs);
  except
    on EConvertError do
      Result := Format(ADefaultText, AArgs);
  end;
end;

{------------------------------------------------------------------------------
  LangFontStr
  ----------------------------------------------------------------------------
  Reads a per-language font setting from the [Fonts] section.

  Parameters:
    AKey     - e.g. 'DialogFontName', 'DialogFontSize'.
    ADefault - Returned when the key or the language file is missing.

  Returns:
    The configured value, otherwise ADefault.

  Notes:
    Exists because some scripts need a different face or size to stay legible
    at the same control height.
------------------------------------------------------------------------------}
function LangFontStr(const AKey, ADefault: string): string;
begin
  if LangFile = '' then
    Exit(ADefault);
  CreateLangIfNil;
  Result := LangIni.ReadString(LANG_SECTION_FONTS, AKey, ADefault);
end;

{------------------------------------------------------------------------------
  AssignActionText
  ----------------------------------------------------------------------------
  Fills an action's caption and hint from a single pipe-delimited entry.

  Parameters:
    AAction - The action to update.
    AKey    - Key whose value reads 'Caption|ShortCut|Hint'. The shortcut part
              is reserved and currently ignored, exactly as in Teramon.

  Notes:
    An empty part leaves the corresponding property untouched, so a translator
    can supply a caption without having to restate the hint.
------------------------------------------------------------------------------}
procedure AssignActionText(AAction: TAction; const AKey: string);
var
  Remaining, ActionCaption, ActionHint: string;
begin
  Remaining := LangStr(AKey);
  if Remaining = '' then
    Exit;

  ActionCaption := ExtractStr(Remaining, '|');
  if ActionCaption <> '' then
    AAction.Caption := ActionCaption;

  ExtractStr(Remaining, '|');            // shortcut field, reserved

  ActionHint := Trim(ExtractStr(Remaining, '|'));
  if ActionHint <> '' then
    AAction.Hint := ActionHint;
end;

{------------------------------------------------------------------------------
  ApplyLocale
  ----------------------------------------------------------------------------
  Re-translates every open form that implements ILocalizable.

  Notes:
    Walks Screen.CustomForms so data modules and docked frames hosted in a form
    are covered through their owning form. Forms that do not implement the
    interface are skipped silently - that is not an error, many dialogs have no
    translatable text of their own.
------------------------------------------------------------------------------}
procedure ApplyLocale;
var
  I: Integer;
begin
  for I := 0 to Screen.CustomFormCount - 1 do
    ApplyLocaleTo(Screen.CustomForms[I]);
end;

{------------------------------------------------------------------------------
  ApplyLocaleTo
  ----------------------------------------------------------------------------
  Re-translates a single form.

  Parameters:
    AForm - The form to refresh. Ignored when nil or not localizable.

  Notes:
    Call this at the end of a form's OnCreate so a form opened after a language
    change starts in the right language.
------------------------------------------------------------------------------}
procedure ApplyLocaleTo(AForm: TCustomForm);
var
  Localizable: ILocalizable;
begin
  if AForm = nil then
    Exit;
  if Supports(AForm, ILocalizable, Localizable) then
    Localizable.LoadLangStr;
end;

{------------------------------------------------------------------------------
  ChangeVar
  ----------------------------------------------------------------------------
  Replaces every occurrence of a placeholder in a string.

  Parameters:
    AText     - Source text.
    AVarName  - Placeholder to look for, e.g. '$nl'.
    ANewValue - Replacement.

  Returns:
    The text with all occurrences replaced.
------------------------------------------------------------------------------}
function ChangeVar(const AText, AVarName, ANewValue: string): string;
begin
  Result := StringReplace(AText, AVarName, ANewValue, [rfReplaceAll]);
end;

{------------------------------------------------------------------------------
  ExtractStr
  ----------------------------------------------------------------------------
  Splits the first field off a delimited string.

  Parameters:
    AText  - On entry the full text; on exit everything after the first
             delimiter. Emptied when no delimiter is present.
    ADelim - The delimiter to split on.

  Returns:
    Everything before the first delimiter, or all of AText when absent.
------------------------------------------------------------------------------}
function ExtractStr(var AText: string; const ADelim: string): string;
var
  Position: Integer;
begin
  Position := Pos(ADelim, AText);
  if Position = 0 then
    Position := Length(AText) + 1;
  Result := Copy(AText, 1, Position - 1);
  AText := Copy(AText, Position + Length(ADelim), MaxInt);
end;

finalization
  FreeAndNil(LangIni);

end.
