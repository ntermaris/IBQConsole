{==============================================================================
  Program:     IBQConsole
  Purpose:     A Firebird database editor and administration console.
               IBConsole's interaction model, FlameRobin's feature set.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  See:         SPECIFICATION.md, ../PASCAL-LAZARUS-RULES.md
==============================================================================}
program IBQConsole;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,          // LCL widgetset - must stay first among LCL units
  Forms,
  SysUtils,
  // forms
  frmMain,
  frmServerRegistration,
  frmDatabaseRegistration,
  fraObjectPage,
  fraDataGrid,
  frmBlobEditor,
  frmSqlEditor,
  frmStatementHistory,
  frmTransactionRecovery,
  frmConnectedUsers,
  frmImportRegistrations,
  frmDdlPreview,
  frmPreferences,
  frmServerProperties,
  frmObjectEditor,
  // core
  LanguageHandle,
  LangFileIO,
  AppLog,
  AppConfig,
  IbqError,
  MetaSubject,
  RegistrationStore,
  StatementHistory,
  DataExport,
  BinaryFormat,
  // sql
  Identifier,
  SqlStatementSplitter,
  ScriptGenerator,
  FirebirdKeywords,
  // model
  MetaTypes,
  MetaItem,
  MetaCollection,
  MetaRoot,
  MetaServer,
  MetaDatabase,
  // db
  ServerVersion,
  FeatureSet,
  ConnectionProfile,
  ServerRegistration,
  MetadataSqlProvider,
  MetadataSqlProviderFB3,
  MetadataSqlProviderFB4,
  MetadataSqlProviderFB5,
  MetadataSqlProviderFB6,
  MetadataSqlProviderFactory,
  // services
  TransactionRecoveryService,
  AttachmentService,
  RegistrationImporter,
  // ddl
  DdlStatements;

{$R *.res}

{------------------------------------------------------------------------------
  StartUpLanguage
  ----------------------------------------------------------------------------
  Chooses the language to start in.

  Returns:
    The language name recorded in preferences.xml, or English when there is
    no file yet. An unknown name falls back to English inside SetLanguage, so
    this can never leave the interface untranslated.

  Notes:
    Loading the preferences is the first thing the program does, because the
    language has to be chosen before any form is built: a form translates
    itself as it is created, and re-translating afterwards would show the
    user a flash of the wrong language.
------------------------------------------------------------------------------}
function StartUpLanguage: string;
begin
  Config.Load;
  Result := Config.Language;
end;

begin
  RequireDerivedFormResource := True;
  Application.Scaled:=True;
  Application.Initialize;

  SetLanguage(StartUpLanguage);

  Application.CreateForm(TfrmIbqMain, frmIbqMain);
  Application.Run;
end.
