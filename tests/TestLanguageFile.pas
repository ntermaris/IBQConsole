{==============================================================================
  Program:     TestLanguageFile
  Purpose:     Checks that a language file actually loads and returns its
               translations, rather than silently falling back to English.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21

  Why this exists: LangStr is designed never to fail. A missing key, an
  unreadable file, a bad encoding - all of them return the English text
  compiled into the call, and the program looks perfectly healthy. That is the
  right behaviour for a user and the wrong one for a translator, because a
  file that does not parse at all is indistinguishable from one that does.

  So this asks the questions the running program cannot: did the file load,
  did a key come back in Greek rather than in English, did the $nl escape turn
  into a line break, and did a key that is NOT in the file fall back cleanly.

  Run from the project root, where lang/ is:
    fpc -Mobjfpc -Sh -FUout -FEout -Fuunits\core tests\TestLanguageFile.pas
    out\TestLanguageFile.exe
==============================================================================}
program TestLanguageFile;
{$mode objfpc}{$H+}
uses
  { Interfaces registers the widgetset. LanguageHandle re-translates open forms,
    so it reaches into the LCL and will not link without one, even here where
    no form is ever created. }
  Interfaces, SysUtils, Classes, LanguageHandle;

var
  Failures: Integer;

{ Reports a failed expectation. }
procedure Fail(const AWhat: string);
begin
  WriteLn('  FAIL  ', AWhat);
  Inc(Failures);
end;

{ Checks a condition and reports it either way. }
procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    WriteLn('  ok    ', AWhat)
  else
    Fail(AWhat);
end;

{ Returns True when AText holds at least one Greek letter. }
function LooksGreek(const AText: string): Boolean;
var
  I: Integer;
  Code: Word;
begin
  Result := False;
  I := 1;
  while I < Length(AText) do
  begin
    { UTF-8: Greek and Coptic is U+0370..U+03FF, which encodes as CE/CF
      followed by a continuation byte. That is enough to tell Greek from
      English without decoding the whole string. }
    Code := Ord(AText[I]);
    if (Code = $CE) or (Code = $CF) then
      Exit(True);
    Inc(I);
  end;
end;

var
  Languages: TStringList;
  Value: string;

begin
  Failures := 0;
  WriteLn('Language file');
  WriteLn;
  WriteLn('  language folder: ', LanguageDir);

  Languages := TStringList.Create;
  try
    ListAvailableLanguages(Languages);
    WriteLn('  languages found: ', Languages.CommaText);
    Check(Languages.IndexOf('Greek') >= 0, 'Greek is offered');
    Check(Languages.IndexOf('English') >= 0, 'English is always offered');
  finally
    Languages.Free;
  end;

  { Before loading anything, every key must give back its English default. }
  ResetLang('');
  Check(CurrentLanguage = 'English', 'English is the starting language');
  Check(LangStr('btnClose.caption', 'Close') = 'Close',
    'the English default is returned when no file is loaded');

  SetLanguage('Greek');
  Check(SameText(CurrentLanguage, 'Greek'), 'the Greek file loaded');

  { The point of the whole exercise: a key comes back translated. If the file
    failed to parse, every one of these silently returns the English text. }
  Value := LangStr('btnClose.caption', 'Close');
  Check(Value <> 'Close', 'btnClose.caption is not the English text');
  Check(LooksGreek(Value), 'btnClose.caption came back in Greek: ' + Value);

  Value := LangStr('mnuDatabase.caption', '&Database');
  Check(LooksGreek(Value), 'a menu caption is translated: ' + Value);

  Value := LangStr('node.tables', 'Tables');
  Check(LooksGreek(Value),
    'a key built at run time is translated: ' + Value);

  Value := LangStr('limbo.stateLimbo', 'In limbo');
  Check(LooksGreek(Value), 'a key added late is translated: ' + Value);

  Value := LangStr('pref.language', 'Language');
  Check(LooksGreek(Value), 'a preferences key is translated: ' + Value);

  { A format string must keep its placeholders, or LangStrFormat will raise
    at run time on an argument it cannot place. }
  Value := LangStr('msg.passwordPrompt', 'Password for %s on %s:');
  Check((Pos('%s', Value) > 0) and
    (Pos('%s', Value) <> LastDelimiter('%', Value)),
    'a two-placeholder message keeps both: ' + Value);
  Value := LangStr('attach.count', '%d attachment(s) connected.');
  Check(Pos('%d', Value) > 0, 'a numeric placeholder survives: ' + Value);

  { $nl is the file's way of writing a line break. }
  Value := LangStr('msg.saveRegistrationsFailed', 'x');
  Check(Pos(LineEnding, Value) > 0, 'the $nl escape became a line break');
  Check(Pos('$nl', Value) = 0, 'the $nl escape was consumed');

  { A key that is deliberately not in any file still answers. }
  Check(LangStr('no.such.key.exists', 'fallback text') = 'fallback text',
    'an unknown key falls back to its English default');

  { And switching back must undo it all. }
  SetLanguage('English');
  Check(LangStr('btnClose.caption', 'Close') = 'Close',
    'switching back to English restores the built-in text');

  WriteLn;
  if Failures = 0 then
    WriteLn('the language file loads and translates')
  else
  begin
    WriteLn(Failures, ' check(s) failed');
    Halt(1);
  end;
end.
