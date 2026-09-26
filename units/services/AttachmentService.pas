{==============================================================================
  Unit:        AttachmentService
  Purpose:     Lists the attachments connected to a database and disconnects
               one.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, DatabaseContext, DatabaseRow, IbqError,
               AppLog

  IBConsole equivalent: Database > Maintenance > Connected Users.

  WHY THIS IS SQL AND NOT THE SERVICES API
  Attachments belong to a database, not to a server: MON$ATTACHMENTS lists who
  is connected to the database being read, and no other. The Services API has
  no verb for any of it. So unlike backup, sweep or limbo recovery, this needs
  a CONNECTED database and works through ordinary SQL on it - which also means
  it is the one administration feature that is unavailable precisely when the
  database will not open.

  WHAT DISCONNECTING ACTUALLY DOES
  Deleting a row from MON$ATTACHMENTS is how Firebird spells "end that
  connection". The server cancels whatever the attachment was running and
  rolls back its open transactions; the client finds out when it next tries to
  use the connection, and gets an error rather than a tidy shutdown. It is a
  kill, not a request, and there is no undo - which is why the dialog confirms
  and names the user first.

  Whether it is permitted is the server's decision: an ordinary user may end
  only their own attachments, an administrator anyone's. A refusal comes back
  as a Firebird error and is reported as one, because "you may not do that" is
  information, not a malfunction.
==============================================================================}
unit AttachmentService;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils,
  DatabaseContext, DatabaseRow, IbqError, AppLog;

type
  { What an attachment is doing. }
  TAttachmentState = (
    asActive,   // running a statement
    asIdle      // connected, waiting
  );

  { One attachment connected to the database. A record: it is a snapshot of
    what the server said, is copied freely and owns nothing. }
  TAttachment = record
    { The attachment id, which is what the server is told to end. }
    Id: Int64;
    { Who is connected. }
    UserName: string;
    { The role they connected under, empty when none. }
    RoleName: string;
    { Where from, empty for an embedded or local attachment. }
    RemoteAddress: string;
    { The client program, as it reported itself. }
    RemoteProcess: string;
    { When the attachment was made, as the server formatted it. }
    ConnectedAt: string;
    { Running or idle. }
    State: TAttachmentState;
    { True for the attachment this program is asking through. Ending it would
      disconnect the user from the database they are looking at. }
    IsSelf: Boolean;

    { Returns 'SYSDBA (attachment 12)', for a confirmation or a log line. }
    function Describe: string;
  end;

  TAttachmentArray = array of TAttachment;

  { TAttachmentService
    The attachments of one connected database.

    Owns nothing: the context is injected and stays owned by the caller. }
  TAttachmentService = class(TObject)
  private
    FContext: TDatabaseContext;
  public
    { Creates a service for one connected database.

      Parameters:
        AContext - The database whose attachments are wanted. Not owned; must
                   outlive this object. }
    constructor Create(AContext: TDatabaseContext);

    { Returns why attachments cannot be listed here, or an empty string. }
    function Unavailable: string;

    { Returns every attachment currently connected to the database. }
    function List: TAttachmentArray;

    { Ends one attachment, disconnecting whoever holds it. }
    procedure Disconnect(AId: Int64);
  end;

implementation

{------------------------------------------------------------------------------
  TAttachment.Describe
  ----------------------------------------------------------------------------
  Returns 'SYSDBA (attachment 12)', for a confirmation or a log line.

  Returns:
    The user and the id, or just the id when the server named no user.
------------------------------------------------------------------------------}
function TAttachment.Describe: string;
begin
  if Trim(UserName) = '' then
  begin
    Result := Format('attachment %d', [Id]);
  end
  else
  begin
    Result := Format('%s (attachment %d)', [Trim(UserName), Id]);
  end;
end;

{------------------------------------------------------------------------------
  TAttachmentService.Create
  ----------------------------------------------------------------------------
  Creates a service for one connected database.

  Parameters:
    AContext - The database whose attachments are wanted. Not owned.

  Raises:
    EIbqError - AContext is nil.
------------------------------------------------------------------------------}
constructor TAttachmentService.Create(AContext: TDatabaseContext);
begin
  inherited Create;
  if AContext = nil then
  begin
    raise EIbqError.Create('TAttachmentService needs a database context.');
  end;
  FContext := AContext;      // injected, NOT owned
end;

{------------------------------------------------------------------------------
  TAttachmentService.Unavailable
  ----------------------------------------------------------------------------
  Returns why attachments cannot be listed here, or an empty string.

  Returns:
    The reason, ready to show, or an empty string when the service is usable.

  Notes:
    Checked before the dialog opens. A disconnected database is the ordinary
    case here, not an error worth an exception: nobody can be listed as
    connected to a database this program is not connected to either.
------------------------------------------------------------------------------}
function TAttachmentService.Unavailable: string;
begin
  if not FContext.IsConnected then
  begin
    Result := 'Connect to the database first. Attachments are read from the ' +
      'database itself, so listing them needs a connection to it.';
    Exit;
  end;
  Result := '';
end;

{------------------------------------------------------------------------------
  TAttachmentService.List
  ----------------------------------------------------------------------------
  Returns every attachment currently connected to the database.

  Returns:
    The attachments, oldest id first. Never empty in practice: the attachment
    doing the asking is one of them.

  Raises:
    EIbqDatabaseError - The query failed.

  Notes:
    FetchTableFresh, not FetchTable. Firebird materialises MON$ATTACHMENTS
    once per transaction, so on the standing metadata transaction an
    attachment that disconnected minutes ago would still be listed and a new
    one would be missing - which is exactly the opposite of what a live
    monitor is for.
------------------------------------------------------------------------------}
function TAttachmentService.List: TAttachmentArray;
var
  Table: TDataTable;
  Row: Integer;
begin
  Result := nil;
  Table := FContext.FetchTableFresh(FContext.SqlProvider.AttachmentsSQL);

  SetLength(Result, Table.RowCount);
  for Row := 0 to Table.RowCount - 1 do
  begin
    Result[Row].Id :=
      StrToInt64Def(Trim(Table.Value(Row, 'ATTACHMENT_ID')), 0);
    Result[Row].UserName := TrimRight(Table.Value(Row, 'USER_NAME'));
    Result[Row].RoleName := TrimRight(Table.Value(Row, 'ROLE_NAME'));
    Result[Row].RemoteAddress :=
      TrimRight(Table.Value(Row, 'REMOTE_ADDRESS'));
    Result[Row].RemoteProcess :=
      TrimRight(Table.Value(Row, 'REMOTE_PROCESS'));
    Result[Row].ConnectedAt := TrimRight(Table.Value(Row, 'CONNECTED_AT'));
    if SameText(Trim(Table.Value(Row, 'ATTACHMENT_STATE')), 'ACTIVE') then
    begin
      Result[Row].State := asActive;
    end
    else
    begin
      Result[Row].State := asIdle;
    end;
    Result[Row].IsSelf := SameText(Trim(Table.Value(Row, 'IS_SELF')), 'YES');
  end;
end;

{------------------------------------------------------------------------------
  TAttachmentService.Disconnect
  ----------------------------------------------------------------------------
  Ends one attachment, disconnecting whoever holds it.

  Parameters:
    AId - The attachment to end, as List reported it.

  Raises:
    EIbqError         - AId is not a usable attachment id.
    EIbqDatabaseError - The server refused, which includes the case where the
                        caller is not allowed to end somebody else's
                        attachment.

  Notes:
    Deleting the MON$ATTACHMENTS row is the documented way to end a
    connection. An id that has already gone deletes nothing and raises
    nothing, which is the right outcome: the goal was that it not be
    connected, and it is not.

    The id is an integer that came from the server and is formatted straight
    into the statement, so there is nothing here for a quoted string to go
    wrong with.
------------------------------------------------------------------------------}
procedure TAttachmentService.Disconnect(AId: Int64);
begin
  if AId <= 0 then
  begin
    raise EIbqError.CreateFmt('%d is not an attachment id.', [AId]);
  end;

  Log.InfoFmt('Disconnecting attachment %d', [AId]);
  FContext.ExecuteDdl(
    Format('DELETE FROM MON$ATTACHMENTS WHERE MON$ATTACHMENT_ID = %d', [AId]));
end;

end.
