{==============================================================================
  Unit:        frmBlobEditor
  Purpose:     Views and edits the contents of one BLOB column: as text, as a
               hex dump, or as an image.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  LCL, DB, LanguageHandle, BinaryFormat

  A grid cell cannot show a BLOB, so it shows "(BLOB)" and this dialog does the
  work. Which view opens first is decided by DetectBinaryKind - by the content,
  not by the column's declared sub-type, because a SUB_TYPE 0 column routinely
  holds a PNG and a SUB_TYPE 1 column routinely holds something that is not
  text at all.

  Text is the only view that edits. Hex is a reader: a hex editor that writes
  is a different program, and an accidental keystroke in one is unrecoverable.
  Loading a file replaces the whole value, which is how a BLOB is normally
  changed anyway.
==============================================================================}
unit frmBlobEditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ComCtrls, ExtCtrls, StdCtrls,
  Dialogs, DB, ExtDlgs,
  LanguageHandle, BinaryFormat;

type

  { TfrmIbqBlobEditor
    Shows one BLOB. Text / Hex / Image tabs, with load and save. }
  TfrmIbqBlobEditor = class(TForm, ILocalizable)
    pgcViews: TPageControl;
    tabText: TTabSheet;
    memText: TMemo;
    tabHex: TTabSheet;
    memHex: TMemo;
    tabImage: TTabSheet;
    scrImage: TScrollBox;
    imgPreview: TImage;
    pnlBottom: TPanel;
    lblInfo: TLabel;
    btnLoad: TButton;
    btnSave: TButton;
    btnOK: TButton;
    btnCancel: TButton;
    dlgOpenBlob: TOpenDialog;
    dlgSaveBlob: TSaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure memTextChange(Sender: TObject);
  private
    FBytes: TBytes;
    FKind: TBinaryKind;
    FReadOnly: Boolean;
    FTextEdited: Boolean;
    procedure ShowContent;
    procedure ShowImage;
    function TextAsBytes: TBytes;
  public
    { Re-reads every caption from the active language. Part of ILocalizable. }
    procedure LoadLangStr;

    { Puts a value into the dialog.

      Parameters:
        ABytes    - The BLOB's content.
        AReadOnly - True to forbid editing. }
    procedure LoadFromBytes(const ABytes: TBytes; AReadOnly: Boolean);

    { The value as it stands after the user's edits. }
    function ResultBytes: TBytes;
    { True when the user changed anything. }
    function Modified: Boolean;
  end;

{ Shows one BLOB field and, on OK, writes the edited value back.

  Parameters:
    AField    - The field to show. Must not be nil.
    AReadOnly - True to open read-only; also forced when the field itself is
                read-only or its dataset cannot be edited.

  Returns:
    True when the field was changed and written.

  Notes:
    Writing puts the dataset into edit state if it is not already, so changing
    a BLOB behaves like changing any other cell - staged until the grid's
    Commit. }
function EditBlobField(AField: TField; AReadOnly: Boolean): Boolean;

implementation

{$R *.lfm}

{------------------------------------------------------------------------------
  EditBlobField
  ----------------------------------------------------------------------------
  See the interface section for the description.
------------------------------------------------------------------------------}
function EditBlobField(AField: TField; AReadOnly: Boolean): Boolean;
var
  Dialog: TfrmIbqBlobEditor;
  Stream: TStream;
  Content, Edited: TBytes;
  Locked: Boolean;
begin
  Result := False;
  if AField = nil then
    Exit;

  Locked := AReadOnly or AField.ReadOnly or (AField.DataSet = nil) or
    not AField.DataSet.CanModify;

  Content := nil;
  if not AField.IsNull then
  begin
    Stream := AField.DataSet.CreateBlobStream(AField, bmRead);
    try
      Content := StreamToBytes(Stream);
    finally
      Stream.Free;
    end;
  end;

  Dialog := TfrmIbqBlobEditor.Create(nil);
  try
    Dialog.LoadFromBytes(Content, Locked);
    if Dialog.ShowModal <> mrOK then
      Exit;
    if Locked or not Dialog.Modified then
      Exit;

    Edited := Dialog.ResultBytes;

    if not (AField.DataSet.State in [dsEdit, dsInsert]) then
      AField.DataSet.Edit;

    Stream := AField.DataSet.CreateBlobStream(AField, bmWrite);
    try
      if Length(Edited) > 0 then
        Stream.WriteBuffer(Edited[0], Length(Edited));
    finally
      Stream.Free;
    end;

    Result := True;
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.FormCreate
  ----------------------------------------------------------------------------
  Applies the active language.
------------------------------------------------------------------------------}
procedure TfrmIbqBlobEditor.FormCreate(Sender: TObject);
begin
  ApplyLocaleTo(Self);
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.LoadLangStr
  ----------------------------------------------------------------------------
  Re-reads every caption from the active language file.
------------------------------------------------------------------------------}
procedure TfrmIbqBlobEditor.LoadLangStr;
begin
  Caption := LangStr('frmBlobEditor.caption', 'BLOB contents');
  tabText.Caption := LangStr('blob.text', 'Text');
  tabHex.Caption := LangStr('blob.hex', 'Hex');
  tabImage.Caption := LangStr('blob.image', 'Image');
  btnLoad.Caption := LangStr('blob.load', 'Load from file...');
  btnSave.Caption := LangStr('blob.save', 'Save to file...');
  btnOK.Caption := LangStr('btnOK.caption', 'OK');
  btnCancel.Caption := LangStr('btnCancel.caption', 'Cancel');
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.LoadFromBytes
  ----------------------------------------------------------------------------
  Puts a value into the dialog.

  Parameters:
    ABytes    - The content.
    AReadOnly - True to forbid editing.
------------------------------------------------------------------------------}
procedure TfrmIbqBlobEditor.LoadFromBytes(const ABytes: TBytes;
  AReadOnly: Boolean);
begin
  FBytes := ABytes;
  FReadOnly := AReadOnly;
  FTextEdited := False;
  FKind := DetectBinaryKind(FBytes);
  ShowContent;
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.ShowContent
  ----------------------------------------------------------------------------
  Fills the three views and picks which one to open on.

  Notes:
    The hex view is capped. A BLOB can hold hundreds of megabytes, and turning
    all of it into sixteen-byte lines would hang the window for minutes to show
    something nobody will scroll through. The cap is reported in the dump
    itself, so a truncated view never passes for a complete one.

    Text editing is disabled for content that is not text, because retyping a
    JPEG through a memo would corrupt it silently.
------------------------------------------------------------------------------}
procedure TfrmIbqBlobEditor.ShowContent;
const
  HexLimit = 64 * 1024;
var
  Editable: Boolean;
  Content: string;
  I: Integer;
begin
  Content := '';
  SetLength(Content, Length(FBytes));
  for I := 0 to High(FBytes) do
    Content[I + 1] := Chr(FBytes[I]);

  memText.Lines.Text := Content;
  memHex.Lines.Text := HexDump(FBytes, HexLimit);

  Editable := (not FReadOnly) and (FKind in [bkEmpty, bkText]);
  memText.ReadOnly := not Editable;

  ShowImage;

  tabImage.TabVisible := BinaryKindIsImage(FKind);

  lblInfo.Caption := LangStrFormat('blob.info',
    [BinaryKindName(FKind), Length(FBytes)],
    '%s, %d byte(s)');

  if FReadOnly then
    lblInfo.Caption := lblInfo.Caption + '  -  ' +
      LangStr('blob.readOnly', 'read only')
  else if not Editable then
    lblInfo.Caption := lblInfo.Caption + '  -  ' +
      LangStr('blob.binaryNotEditable',
        'binary content: replace it with Load from file');

  btnSave.Enabled := Length(FBytes) > 0;
  btnLoad.Enabled := not FReadOnly;
  btnOK.Enabled := not FReadOnly;

  if BinaryKindIsImage(FKind) then
    pgcViews.ActivePage := tabImage
  else if FKind in [bkEmpty, bkText] then
    pgcViews.ActivePage := tabText
  else
    pgcViews.ActivePage := tabHex;
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.ShowImage
  ----------------------------------------------------------------------------
  Loads the content into the image preview when it is a picture.

  Notes:
    A failed load is reported on the info line rather than raised. Bytes that
    begin with a PNG signature are not guaranteed to be a whole valid PNG, and
    a truncated image in a database is a thing that happens.
------------------------------------------------------------------------------}
procedure TfrmIbqBlobEditor.ShowImage;
var
  Stream: TMemoryStream;
begin
  imgPreview.Picture.Clear;
  if not BinaryKindIsImage(FKind) then
    Exit;

  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(FBytes[0], Length(FBytes));
    Stream.Position := 0;
    try
      imgPreview.Picture.LoadFromStream(Stream);
      imgPreview.Width := imgPreview.Picture.Width;
      imgPreview.Height := imgPreview.Picture.Height;
    except
      on E: Exception do
      begin
        imgPreview.Picture.Clear;
        lblInfo.Caption := LangStrFormat('blob.imageFailed', [E.Message],
          'The image could not be displayed: %s');
      end;
    end;
  finally
    Stream.Free;
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.TextAsBytes
  ----------------------------------------------------------------------------
  Returns the text view's contents as bytes.
------------------------------------------------------------------------------}
function TfrmIbqBlobEditor.TextAsBytes: TBytes;
var
  Content: string;
  I: Integer;
begin
  Result := nil;
  Content := memText.Lines.Text;
  SetLength(Result, Length(Content));
  for I := 1 to Length(Content) do
    Result[I - 1] := Ord(Content[I]);
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.memTextChange
  ----------------------------------------------------------------------------
  Records that the text was edited.
------------------------------------------------------------------------------}
procedure TfrmIbqBlobEditor.memTextChange(Sender: TObject);
begin
  if not memText.ReadOnly then
    FTextEdited := True;
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.btnLoadClick
  ----------------------------------------------------------------------------
  Replaces the whole value with a file's contents.
------------------------------------------------------------------------------}
procedure TfrmIbqBlobEditor.btnLoadClick(Sender: TObject);
var
  Stream: TFileStream;
begin
  dlgOpenBlob.Title := LangStr('blob.loadTitle', 'Load BLOB from file');
  if not dlgOpenBlob.Execute then
    Exit;

  try
    Stream := TFileStream.Create(dlgOpenBlob.FileName, fmOpenRead or
      fmShareDenyWrite);
    try
      FBytes := StreamToBytes(Stream);
    finally
      Stream.Free;
    end;
    FKind := DetectBinaryKind(FBytes);
    FTextEdited := True;
    ShowContent;
  except
    on E: Exception do
      MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.btnSaveClick
  ----------------------------------------------------------------------------
  Writes the value to a file.

  Notes:
    Saves the ORIGINAL bytes, or the edited text when the text view was
    changed - never the hex dump, which is a rendering and not the content.
------------------------------------------------------------------------------}
procedure TfrmIbqBlobEditor.btnSaveClick(Sender: TObject);
var
  Stream: TFileStream;
  Content: TBytes;
begin
  Content := ResultBytes;
  if Length(Content) = 0 then
    Exit;

  dlgSaveBlob.Title := LangStr('blob.saveTitle', 'Save BLOB to file');

  { The extension follows the detected content, so saving a PNG out of a
    SUB_TYPE 0 column proposes .png rather than .bin. }
  case FKind of
    bkPng:  dlgSaveBlob.DefaultExt := 'png';
    bkJpeg: dlgSaveBlob.DefaultExt := 'jpg';
    bkGif:  dlgSaveBlob.DefaultExt := 'gif';
    bkBmp:  dlgSaveBlob.DefaultExt := 'bmp';
    bkPdf:  dlgSaveBlob.DefaultExt := 'pdf';
    bkZip:  dlgSaveBlob.DefaultExt := 'zip';
    bkText: dlgSaveBlob.DefaultExt := 'txt';
  else
    dlgSaveBlob.DefaultExt := 'bin';
  end;

  if not dlgSaveBlob.Execute then
    Exit;

  try
    Stream := TFileStream.Create(dlgSaveBlob.FileName, fmCreate);
    try
      Stream.WriteBuffer(Content[0], Length(Content));
    finally
      Stream.Free;
    end;
  except
    on E: Exception do
      MessageDlg(Caption, E.Message, mtError, [mbOK], 0);
  end;
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.ResultBytes
  ----------------------------------------------------------------------------
  Returns the value as it stands after the user's edits.

  Returns:
    The text view's contents when the text was edited, otherwise the bytes as
    loaded - so opening a JPEG and pressing OK cannot rewrite it through the
    text memo.
------------------------------------------------------------------------------}
function TfrmIbqBlobEditor.ResultBytes: TBytes;
begin
  if FTextEdited and not memText.ReadOnly then
    Result := TextAsBytes
  else
    Result := FBytes;
end;

{------------------------------------------------------------------------------
  TfrmIbqBlobEditor.Modified
  ----------------------------------------------------------------------------
  Returns True when the user changed anything.
------------------------------------------------------------------------------}
function TfrmIbqBlobEditor.Modified: Boolean;
begin
  Result := FTextEdited;
end;

end.
