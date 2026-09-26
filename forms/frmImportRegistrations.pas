{==============================================================================
  Unit:        frmImportRegistrations
  Purpose:     Shows what FlameRobin and IBConsole have registered and imports
               the entries the user ticks.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
               ComCtrls, Dialogs, LanguageHandle, AppLog, RegistrationStore,
               RegistrationImporter

  IBConsole equivalent: none.

  A preview with checkboxes, never a silent bulk copy (D5, §9.2). The user is
  being offered somebody else's list of databases and may well want three of
  the fourteen; importing all of them and letting them delete the rest is the
  same work in the opposite direction, done to them rather than by them.

  Entries already registered here are listed too, greyed and unticked, with
  the reason in the last column. Hiding them would look like the scan had
  missed them.
==============================================================================}
unit frmImportRegistrations;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs,
  LanguageHandle, AppLog, RegistrationStore, RegistrationImporter;

type
  { TfrmIbqImportRegistrations
    The import preview dialog.

    Takes over the importer it is given when told to, and frees it with
    itself. }
  TfrmIbqImportRegistrations = class(TForm, ILocalizable)
    pnlHeader: TPanel;
    lblFound: TLabel;
    lblSources: TLabel;
    lvwCandidates: TListView;
    pnlButtons: TPanel;
    lblStatus: TLabel;
    btnAll: TButton;
    btnNone: TButton;
    btnImport: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnAllClick(Sender: TObject);
    procedure btnNoneClick(Sender: TObject);
    procedure btnImportClick(Sender: TObject);
  private
    FImporter: TRegistrationImporter;
    FOwnsImporter: Boolean;
    FCandidates: TImportCandidateArray;
    FImportedCount: Integer;
    { Writes FCandidates into the list view. }
    procedure FillList;
    { Ticks or unticks everything that can be imported. }
    procedure CheckAll(AChecked: Boolean);
    { Copies the tick marks back from the list view into FCandidates. }
    procedure ReadChecks;
    { Returns how many entries are ticked. }
    function CheckedCount: Integer;
    { Logs an error and shows it. }
    procedure ReportError(E: Exception);
  public
    destructor Destroy; override;

    { Prepares the dialog and shows what the importer found.

      Parameters:
        AImporter     - The importer to work through. Taken over when
                        AOwnsImporter is True.
        AOwnsImporter - True when this form should free AImporter.
        ACandidates   - What the importer's Scan returned. }
    procedure PrepareFor(AImporter: TRegistrationImporter;
      AOwnsImporter: Boolean; const ACandidates: TImportCandidateArray);

    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { How many databases the last Import added. Zero until the user presses
      Import, and zero afterwards if they ticked nothing. }
    property ImportedCount: Integer read FImportedCount;
  end;

{ Scans for other programs' registrations and offers to import them.

  Parameters:
    AStore - Where imported registrations go. Not owned.

  Returns:
    How many databases were imported; zero when nothing was found, nothing
    was ticked, or the user closed the dialog.

  Notes:
    Reports "nothing found" and returns rather than opening an empty dialog.
    Per §9.2 this path never errors: a machine with neither program on it is
    the ordinary case, not a fault. }
function ImportRegistrationsDialog(AStore: TRegistrationStore): Integer;

implementation

{$R *.lfm}

const
  { Columns of the candidate list. }
  ColSource = 0;
  ColKind = 1;
  ColName = 2;
  ColDetail = 3;
  ColStatus = 4;

{------------------------------------------------------------------------------
  ImportRegistrationsDialog
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function ImportRegistrationsDialog(AStore: TRegistrationStore): Integer;
var
  Importer: TRegistrationImporter;
  Candidates: TImportCandidateArray;
  Dialog: TfrmIbqImportRegistrations;
  Owned: Boolean;
begin
  Result := 0;
  if AStore = nil then
  begin
    Exit;
  end;

  Importer := TRegistrationImporter.Create(AStore);
  Owned := True;
  try
    Candidates := Importer.Scan;

    if Length(Candidates) = 0 then
    begin
      MessageDlg(LangStr('frmImportRegistrations.caption',
        'Import Registrations'),
        LangStr('import.nothingFound',
          'Nothing to import. No FlameRobin registration file and no ' +
          'IBConsole registry entries were found for this user.'),
        mtInformation, [mbOK], 0);
      Exit;
    end;

    Dialog := TfrmIbqImportRegistrations.Create(nil);
    try
      Dialog.PrepareFor(Importer, True, Candidates);
      Owned := False;      // the dialog owns it now
      Dialog.ShowModal;
      Result := Dialog.ImportedCount;
    finally
      Dialog.Free;         // frees the importer with it
    end;
  finally
    if Owned then
    begin
      Importer.Free;
    end;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.

  Parameters:
    Sender - The form.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.Destroy
  ----------------------------------------------------------------------------
  Frees the importer when this form was told to own it.
------------------------------------------------------------------------------}
destructor TfrmIbqImportRegistrations.Destroy;
begin
  if FOwnsImporter then
  begin
    FImporter.Free;
  end;
  FImporter := nil;
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language.

  Notes:
    Refills the list afterwards, because the Kind and Status columns hold
    translated words rather than data.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.LoadLangStr;
begin
  Caption := LangStr('frmImportRegistrations.caption',
    'Import Registrations');

  lblSources.Caption := LangStr('import.sources',
    'Read from FlameRobin''s fr_databases.conf and from IBConsole''s ' +
    'registry entries. Neither is changed, and passwords are never imported.');

  btnAll.Caption := LangStr('import.selectAll', 'Select all');
  btnNone.Caption := LangStr('import.selectNone', 'Select none');
  btnImport.Caption := LangStr('import.import', 'Import');
  btnClose.Caption := LangStr('btnClose.caption', 'Close');

  if lvwCandidates.Columns.Count > ColStatus then
  begin
    lvwCandidates.Columns[ColSource].Caption :=
      LangStr('import.colSource', 'Found in');
    lvwCandidates.Columns[ColKind].Caption :=
      LangStr('import.colKind', 'Kind');
    lvwCandidates.Columns[ColName].Caption :=
      LangStr('import.colName', 'Name');
    lvwCandidates.Columns[ColDetail].Caption :=
      LangStr('import.colDetail', 'Address or path');
    lvwCandidates.Columns[ColStatus].Caption :=
      LangStr('import.colStatus', 'Status');
  end;

  FillList;
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.PrepareFor
  ----------------------------------------------------------------------------
  Prepares the dialog and shows what the importer found.

  Parameters:
    AImporter     - The importer to work through.
    AOwnsImporter - True when this form should free AImporter.
    ACandidates   - What the importer's Scan returned.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.PrepareFor(
  AImporter: TRegistrationImporter; AOwnsImporter: Boolean;
  const ACandidates: TImportCandidateArray);
begin
  FImporter := AImporter;
  FOwnsImporter := AOwnsImporter;
  FCandidates := ACandidates;
  FImportedCount := 0;
  FillList;
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.FillList
  ----------------------------------------------------------------------------
  Writes FCandidates into the list view.

  Notes:
    A database is indented under its server by prefixing its name, because a
    list view in report mode has no hierarchy and the relationship is the one
    thing the user needs to see.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.FillList;
var
  I: Integer;
  Item: TListItem;
  Found: Integer;
begin
  Found := 0;

  lvwCandidates.Items.BeginUpdate;
  try
    lvwCandidates.Items.Clear;
    for I := 0 to High(FCandidates) do
    begin
      Item := lvwCandidates.Items.Add;
      Item.Caption := ImportSourceName(FCandidates[I].Source);

      if FCandidates[I].IsServer then
      begin
        Item.SubItems.Add(LangStr('import.kindServer', 'Server'));
        Item.SubItems.Add(FCandidates[I].ServerName);
        if FCandidates[I].Host = '' then
        begin
          Item.SubItems.Add(LangStr('import.localServer', 'Local'));
        end
        else
        begin
          Item.SubItems.Add(Format('%s:%d',
            [FCandidates[I].Host, FCandidates[I].Port]));
        end;
      end
      else
      begin
        Item.SubItems.Add(LangStr('import.kindDatabase', 'Database'));
        Item.SubItems.Add('    ' + FCandidates[I].DatabaseName);
        Item.SubItems.Add(FCandidates[I].DatabasePath);
        Inc(Found);
      end;

      if FCandidates[I].Skip = '' then
      begin
        Item.SubItems.Add('');
      end
      else
      begin
        Item.SubItems.Add(LangStr('import.alreadyRegistered',
          'Already registered'));
      end;

      Item.Checked := FCandidates[I].Selected;
    end;
  finally
    lvwCandidates.Items.EndUpdate;
  end;

  lblFound.Caption := LangStrFormat('import.found', [Found],
    '%d database(s) found.');
  lblStatus.Caption := '';
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.ReadChecks
  ----------------------------------------------------------------------------
  Copies the tick marks back from the list view into FCandidates.

  Notes:
    Read at the moment Import is pressed rather than tracked as the user
    clicks, because a list view reports a check change before and after the
    item is updated and only one of those is the truth.

    Item N is candidate N: FillList adds one item per candidate in order
    and the list is never sorted, so no tag on the item is needed to find
    its candidate again.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.ReadChecks;
var
  I: Integer;
begin
  for I := 0 to lvwCandidates.Items.Count - 1 do
  begin
    if I > High(FCandidates) then
    begin
      Break;
    end;
    FCandidates[I].Selected := lvwCandidates.Items[I].Checked;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.CheckedCount
  ----------------------------------------------------------------------------
  Returns how many entries are ticked.

  Returns:
    The number of ticked entries that can actually be imported.
------------------------------------------------------------------------------}
function TfrmIbqImportRegistrations.CheckedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FCandidates) do
  begin
    if FCandidates[I].Selected and (FCandidates[I].Skip = '') then
    begin
      Inc(Result);
    end;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.CheckAll
  ----------------------------------------------------------------------------
  Ticks or unticks everything that can be imported.

  Parameters:
    AChecked - True to tick, False to untick.

  Notes:
    Select all leaves the already-registered rows alone. Ticking them would
    promise something the import will not do.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.CheckAll(AChecked: Boolean);
var
  I: Integer;
begin
  for I := 0 to lvwCandidates.Items.Count - 1 do
  begin
    if I > High(FCandidates) then
    begin
      Break;
    end;
    if FCandidates[I].Skip <> '' then
    begin
      Continue;
    end;
    lvwCandidates.Items[I].Checked := AChecked;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.ReportError
  ----------------------------------------------------------------------------
  Logs an error and shows it.

  Parameters:
    E - What went wrong.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.ReportError(E: Exception);
begin
  Log.Error(E.Message);
  lblStatus.Caption := LangStr('import.failed', 'Failed.');
  MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.btnAllClick
  ----------------------------------------------------------------------------
  Ticks everything that can be imported.

  Parameters:
    Sender - The Select all button.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.btnAllClick(Sender: TObject);
begin
  CheckAll(True);
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.btnNoneClick
  ----------------------------------------------------------------------------
  Unticks everything.

  Parameters:
    Sender - The Select none button.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.btnNoneClick(Sender: TObject);
begin
  CheckAll(False);
end;

{------------------------------------------------------------------------------
  TfrmIbqImportRegistrations.btnImportClick
  ----------------------------------------------------------------------------
  Imports the ticked entries and closes.

  Parameters:
    Sender - The Import button.

  Notes:
    Closes on success, because the list it was showing is now out of date:
    everything on it would be marked "already registered" if it were rescanned.
------------------------------------------------------------------------------}
procedure TfrmIbqImportRegistrations.btnImportClick(Sender: TObject);
begin
  ReadChecks;

  if CheckedCount = 0 then
  begin
    MessageDlg(Caption,
      LangStr('import.nothingTicked',
        'Nothing is ticked, so there is nothing to import.'),
      mtInformation, [mbOK], 0);
    Exit;
  end;

  try
    FImportedCount := FImporter.Import(FCandidates);
  except
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;

  MessageDlg(Caption,
    LangStrFormat('import.done', [FImportedCount],
      '%d database(s) imported. Passwords were not imported: you will be ' +
      'asked for one the first time you connect.'),
    mtInformation, [mbOK], 0);

  ModalResult := mrOk;
end;

end.
