{==============================================================================
  Unit:        SecurityService
  Purpose:     Lists, creates, alters and drops server users.
  Author:      Alexandros Ntermaris
  Created:     2026-08-21
  Depends on:  Classes, SysUtils, IBXServices, DatabaseContext, DatabaseRow,
               FeatureSet, ServerRegistration, ServiceConnection, Identifier,
               IbqError, AppLog

  IBConsole equivalent: frmuUser. FlameRobin equivalent: UserDialog.

  TWO WAYS TO MANAGE USERS, AND THE OLD ONE IS NOT ENOUGH
  The Services API has had user management since InterBase: isc_action_svc_
  add_user and friends, which IBX wraps as TIBXSecurityService. From Firebird 3
  it is no longer the whole picture. Firebird 3 introduced pluggable user
  managers - Srp by default, Legacy_UserManager for compatibility - and the
  Services API talks to whichever ONE the server names first in its
  UserManager list. Users held by any other plugin are invisible to it, and a
  user created through it lands in a plugin the administrator may not have
  meant.

  SQL user management - CREATE USER, ALTER USER, DROP USER and the SEC$USERS
  view - goes through the same code path the server itself uses, sees every
  plugin, and reports which plugin each user belongs to.

  So: SQL when there is a connected database to run it on, the Services API
  only when there is not. Which one is in use is not hidden - TSecurityService.
  Source says so, and the dialog shows it, because "this list may be
  incomplete" is something a user managing accounts is entitled to know.

  WHY THE SQL PATH NEEDS A DATABASE
  CREATE USER is a statement, and a statement needs an attachment. Any database
  on the server will do - the users belong to the server, not to the database -
  which is why the dialog is happy to be opened from any connected database
  under that server.

  PASSWORDS ARE NEVER READ BACK
  Firebird does not store them recoverably and neither does this. A password
  can be set and replaced; it cannot be shown. An empty password on modify
  means "leave it alone", never "clear it".
==============================================================================}
unit SecurityService;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, IBXServices,
  DatabaseContext, DatabaseRow, FeatureSet, ServerRegistration,
  ServiceConnection, Identifier, IbqError, AppLog;

type
  { Which of the two mechanisms a service instance is using. }
  TUserSource = (
    usSql,        // CREATE USER / SEC$USERS, through a database attachment
    usServices    // the Services API, through a service attachment
  );

  { One user account. A record: it is a snapshot of what the server said, is
    copied freely and owns nothing. }
  TUserAccount = record
    UserName: string;
    FirstName: string;
    MiddleName: string;
    LastName: string;
    { True when the account may log in. Firebird 3 and later; always True on
      the Services API path, which cannot see the flag. }
    Active: Boolean;
    { True when the user holds the RDB$ADMIN role automatically. }
    AdminRole: Boolean;
    { The user manager plugin holding this account, e.g. Srp. Empty on the
      Services API path. }
    Plugin: string;
    { Free-text comment. }
    Description: string;
    { Legacy user and group ids. Meaningful only on the Services API path
      against an old security database; -1 when not applicable. }
    UserId: Integer;
    GroupId: Integer;

    { Returns 'SYSDBA (John Smith)', or just the name when there is none. }
    function DisplayName: string;
  end;

  TUserAccountArray = array of TUserAccount;

type
  { TSecurityService
    User management for one server.

    Create it with a connected TDatabaseContext for the SQL path, or with a
    registration and password for the Services API path. It owns neither the
    context nor the registration. }
  TSecurityService = class(TObject)
  private
    FContext: TDatabaseContext;
    FRegistration: TServerRegistration;
    FPassword: string;
    FSource: TUserSource;
    function ListViaSql: TUserAccountArray;
    function ListViaServices: TUserAccountArray;
    procedure ExecuteViaServices(AAction: TSecurityAction;
      const AUser: TUserAccount; const APassword: string);
    function QuotedName(const AUserName: string): string;
    function NameClause(const AKeyword, AValue: string;
      AInclude: Boolean): string;
  public
    { Creates a service that manages users through SQL.

      Parameters:
        AContext - A connected database on the server whose users are to be
                   managed. Not owned. }
    constructor CreateForDatabase(AContext: TDatabaseContext);

    { Creates a service that manages users through the Services API.

      Parameters:
        ARegistration - The server. Not owned.
        APassword     - The password to attach with. }
    constructor CreateForServer(ARegistration: TServerRegistration;
      const APassword: string);

    { Which mechanism this instance uses. }
    function Source: TUserSource;

    { Returns why users cannot be managed here, or an empty string.

      Notes:
        Checked before the dialog opens, so a server that cannot answer says so
        once rather than failing on every button. }
    function Unavailable: string;

    { Returns every user the server will show us.

      Notes:
        An ordinary user sees only their own account. That is the server
        enforcing its rules, not a failure, and the caller should present it as
        such. }
    function ListUsers: TUserAccountArray;

    { Creates a user.

      Parameters:
        AUser     - The account to create; UserName is required.
        APassword - The password; required. }
    procedure AddUser(const AUser: TUserAccount; const APassword: string);

    { Changes a user.

      Parameters:
        AUser     - The account, identified by UserName.
        APassword - A new password, or an empty string to leave it alone. }
    procedure ModifyUser(const AUser: TUserAccount; const APassword: string);

    { Removes a user.

      Parameters:
        AUserName - Whose account to remove. }
    procedure DeleteUser(const AUserName: string);
  end;

{ Returns an empty account with the defaults a new user should start from. }
function EmptyUserAccount: TUserAccount;

implementation

{------------------------------------------------------------------------------
  TUserAccount.DisplayName
  ----------------------------------------------------------------------------
  Returns 'SYSDBA (John Smith)', or just the name when there is none.
------------------------------------------------------------------------------}
function TUserAccount.DisplayName: string;
var
  Full: string;
begin
  Full := Trim(Trim(FirstName) + ' ' + Trim(MiddleName) + ' ' + Trim(LastName));
  if Full = '' then
    Result := UserName
  else
    Result := UserName + ' (' + Full + ')';
end;

{------------------------------------------------------------------------------
  EmptyUserAccount
  ----------------------------------------------------------------------------
  Returns an empty account with the defaults a new user should start from.

  Notes:
    Active, because an account created inactive would be a puzzle; without the
    admin role, because that is the safe default and the one the user must ask
    for deliberately.
------------------------------------------------------------------------------}
function EmptyUserAccount: TUserAccount;
begin
  Result := Default(TUserAccount);
  Result.Active := True;
  Result.AdminRole := False;
  Result.UserId := -1;
  Result.GroupId := -1;
end;

{------------------------------------------------------------------------------
  TSecurityService.CreateForDatabase
  ----------------------------------------------------------------------------
  Creates a service that manages users through SQL.

  Parameters:
    AContext - A connected database on the server. Not owned.
------------------------------------------------------------------------------}
constructor TSecurityService.CreateForDatabase(AContext: TDatabaseContext);
begin
  inherited Create;
  if AContext = nil then
    raise EIbqError.Create('TSecurityService needs a database context.');
  FContext := AContext;
  FSource := usSql;
end;

{------------------------------------------------------------------------------
  TSecurityService.CreateForServer
  ----------------------------------------------------------------------------
  Creates a service that manages users through the Services API.

  Parameters:
    ARegistration - The server. Not owned.
    APassword     - The password to attach with.
------------------------------------------------------------------------------}
constructor TSecurityService.CreateForServer(
  ARegistration: TServerRegistration; const APassword: string);
begin
  inherited Create;
  if ARegistration = nil then
    raise EIbqError.Create('TSecurityService needs a server registration.');
  FRegistration := ARegistration;
  FPassword := APassword;
  FSource := usServices;
end;

{------------------------------------------------------------------------------
  TSecurityService.Source
  ----------------------------------------------------------------------------
  Returns which mechanism this instance uses.
------------------------------------------------------------------------------}
function TSecurityService.Source: TUserSource;
begin
  Result := FSource;
end;

{------------------------------------------------------------------------------
  TSecurityService.Unavailable
  ----------------------------------------------------------------------------
  Returns why users cannot be managed here, or an empty string.
------------------------------------------------------------------------------}
function TSecurityService.Unavailable: string;
begin
  Result := '';

  if FSource = usSql then
  begin
    if (FContext = nil) or not FContext.IsConnected then
      Exit('The database is not connected.');
    if not SupportsFeature(FContext.Version, dbfSqlUserManagement) then
      Exit('This server is too old for SQL user management.');
  end;
end;

{------------------------------------------------------------------------------
  TSecurityService.QuotedName
  ----------------------------------------------------------------------------
  Returns a user name in the form a statement can carry.

  Parameters:
    AUserName - The name as the user typed or as the server reported it.

  Returns:
    The name, quoted when it needs to be.

  Notes:
    User names follow the same rules as any other identifier from Firebird 3
    on: unquoted ones are folded to upper case, quoted ones are not. Passing a
    lower-case name unquoted and then looking for it in SEC$USERS as typed is
    the classic way to "create a user that does not exist".
------------------------------------------------------------------------------}
function TSecurityService.QuotedName(const AUserName: string): string;
begin
  Result := TIdentifier.FromUserInput(AUserName).Quoted;
end;

{------------------------------------------------------------------------------
  TSecurityService.NameClause
  ----------------------------------------------------------------------------
  Returns ' KEYWORD ''value''' or an empty string.

  Parameters:
    AKeyword  - FIRSTNAME, MIDDLENAME or LASTNAME.
    AValue    - What to set it to.
    AInclude  - False to leave the clause out entirely.

  Notes:
    On ALTER, leaving a clause out means "do not change it", while including it
    empty means "clear it". Both are wanted, so the caller decides which with
    AInclude rather than this guessing from an empty string.
------------------------------------------------------------------------------}
function TSecurityService.NameClause(const AKeyword, AValue: string;
  AInclude: Boolean): string;
begin
  if not AInclude then
    Exit('');
  Result := ' ' + AKeyword + ' ' + QuotedStr(AValue);
end;

{------------------------------------------------------------------------------
  TSecurityService.ListUsers
  ----------------------------------------------------------------------------
  Returns every user the server will show us.
------------------------------------------------------------------------------}
function TSecurityService.ListUsers: TUserAccountArray;
begin
  if FSource = usSql then
    Result := ListViaSql
  else
    Result := ListViaServices;
end;

{------------------------------------------------------------------------------
  TSecurityService.ListViaSql
  ----------------------------------------------------------------------------
  Reads the users from SEC$USERS.

  Returns:
    The accounts, ordered by name.
------------------------------------------------------------------------------}
function TSecurityService.ListViaSql: TUserAccountArray;
var
  Table: TDataTable;
  Row: Integer;
begin
  Result := nil;

  { FetchTableFresh, not FetchTable. Firebird materialises SEC$USERS once per
    transaction, so on the standing metadata transaction a user created a
    moment ago would be missing from the list that is supposed to prove the
    creation worked. Verified against Firebird 5.0.4: same attachment, new
    transaction, and the new user appears. }
  Table := FContext.FetchTableFresh(FContext.SqlProvider.UserAccountsSQL);

  SetLength(Result, Table.RowCount);
  for Row := 0 to Table.RowCount - 1 do
  begin
    Result[Row] := EmptyUserAccount;
    Result[Row].UserName := TrimRight(Table.Value(Row, 'USER_NAME'));
    Result[Row].FirstName := TrimRight(Table.Value(Row, 'FIRST_NAME'));
    Result[Row].MiddleName := TrimRight(Table.Value(Row, 'MIDDLE_NAME'));
    Result[Row].LastName := TrimRight(Table.Value(Row, 'LAST_NAME'));
    Result[Row].Active := SameText(Trim(Table.Value(Row, 'IS_ACTIVE')), 'YES');
    Result[Row].AdminRole :=
      SameText(Trim(Table.Value(Row, 'ADMIN_ROLE')), 'YES');
    Result[Row].Plugin := TrimRight(Table.Value(Row, 'PLUGIN_NAME'));
    Result[Row].Description :=
      TrimRight(Table.Value(Row, 'USER_DESCRIPTION'));
  end;
end;

{------------------------------------------------------------------------------
  TSecurityService.ListViaServices
  ----------------------------------------------------------------------------
  Reads the users through the Services API.

  Returns:
    The accounts, in the order the server returned them.

  Notes:
    IBX exposes the list as a dataset rather than as records, and the columns
    are the legacy security database's: no plugin, no active flag. They are
    filled in with the honest defaults - Active True, Plugin empty - and the
    caller shows the source so nobody reads that empty column as "no plugin".
------------------------------------------------------------------------------}
function TSecurityService.ListViaServices: TUserAccountArray;
var
  Connection: TServiceConnection;
  Users: TIBXServicesUserList;
  Service: TIBXSecurityService;
  Count: Integer;
begin
  Result := nil;
  Connection := TServiceConnection.Create(FRegistration);
  Service := nil;
  Users := nil;
  try
    Connection.Connect(FPassword);

    Service := TIBXSecurityService.Create(nil);
    Service.ServicesConnection := Connection.Connection;

    Users := TIBXServicesUserList.Create(nil);
    Users.Source := Service;
    Users.Active := True;

    Count := 0;
    Users.First;
    while not Users.Eof do
    begin
      SetLength(Result, Count + 1);
      Result[Count] := EmptyUserAccount;
      Result[Count].UserName :=
        TrimRight(Users.FieldByName('SEC$USER_NAME').AsString);
      Result[Count].FirstName :=
        TrimRight(Users.FieldByName('SEC$FIRST_NAME').AsString);
      Result[Count].MiddleName :=
        TrimRight(Users.FieldByName('SEC$MIDDLE_NAME').AsString);
      Result[Count].LastName :=
        TrimRight(Users.FieldByName('SEC$LAST_NAME').AsString);
      Inc(Count);
      Users.Next;
    end;
  finally
    if Users <> nil then
    begin
      Users.Active := False;
      Users.Free;
    end;
    Service.Free;
    Connection.Free;
  end;
end;

{------------------------------------------------------------------------------
  TSecurityService.AddUser
  ----------------------------------------------------------------------------
  Creates a user.

  Parameters:
    AUser     - The account to create; UserName is required.
    APassword - The password; required.
------------------------------------------------------------------------------}
procedure TSecurityService.AddUser(const AUser: TUserAccount;
  const APassword: string);
var
  Sql: string;
begin
  if Trim(AUser.UserName) = '' then
    raise EIbqError.Create('A user needs a name.');
  if APassword = '' then
    raise EIbqError.Create('A new user needs a password.');

  if FSource = usServices then
  begin
    ExecuteViaServices(ActionAddUser, AUser, APassword);
    Exit;
  end;

  Sql := 'CREATE USER ' + QuotedName(AUser.UserName) +
    ' PASSWORD ' + QuotedStr(APassword) +
    NameClause('FIRSTNAME', AUser.FirstName, Trim(AUser.FirstName) <> '') +
    NameClause('MIDDLENAME', AUser.MiddleName, Trim(AUser.MiddleName) <> '') +
    NameClause('LASTNAME', AUser.LastName, Trim(AUser.LastName) <> '');

  if AUser.Active then
    Sql := Sql + ' ACTIVE'
  else
    Sql := Sql + ' INACTIVE';

  if AUser.AdminRole then
    Sql := Sql + ' GRANT ADMIN ROLE';

  FContext.ExecuteDdl(Sql);
  Log.Info('User created: ' + AUser.UserName);
end;

{------------------------------------------------------------------------------
  TSecurityService.ModifyUser
  ----------------------------------------------------------------------------
  Changes a user.

  Parameters:
    AUser     - The account, identified by UserName.
    APassword - A new password, or an empty string to leave it alone.

  Notes:
    The name clauses are always included, because this comes from a dialog that
    showed the user their current values: a field the user cleared means
    "clear it", and leaving the clause out would silently ignore that.
------------------------------------------------------------------------------}
procedure TSecurityService.ModifyUser(const AUser: TUserAccount;
  const APassword: string);
var
  Sql: string;
begin
  if Trim(AUser.UserName) = '' then
    raise EIbqError.Create('A user needs a name.');

  if FSource = usServices then
  begin
    ExecuteViaServices(ActionModifyUser, AUser, APassword);
    Exit;
  end;

  Sql := 'ALTER USER ' + QuotedName(AUser.UserName) + ' SET';

  if APassword <> '' then
    Sql := Sql + ' PASSWORD ' + QuotedStr(APassword);

  Sql := Sql +
    NameClause('FIRSTNAME', AUser.FirstName, True) +
    NameClause('MIDDLENAME', AUser.MiddleName, True) +
    NameClause('LASTNAME', AUser.LastName, True);

  if AUser.Active then
    Sql := Sql + ' ACTIVE'
  else
    Sql := Sql + ' INACTIVE';

  if AUser.AdminRole then
    Sql := Sql + ' GRANT ADMIN ROLE'
  else
    Sql := Sql + ' REVOKE ADMIN ROLE';

  FContext.ExecuteDdl(Sql);
  Log.Info('User changed: ' + AUser.UserName);
end;

{------------------------------------------------------------------------------
  TSecurityService.DeleteUser
  ----------------------------------------------------------------------------
  Removes a user.

  Parameters:
    AUserName - Whose account to remove.

  Notes:
    Whether the user still owns objects is not checked here. Firebird allows a
    user who owns tables to be dropped, and second-guessing that would mean
    scanning the metadata of every database on the server - which this cannot
    see and should not pretend to.
------------------------------------------------------------------------------}
procedure TSecurityService.DeleteUser(const AUserName: string);
var
  Account: TUserAccount;
begin
  if Trim(AUserName) = '' then
    raise EIbqError.Create('A user needs a name.');

  if FSource = usServices then
  begin
    Account := EmptyUserAccount;
    Account.UserName := AUserName;
    ExecuteViaServices(ActionDeleteUser, Account, '');
    Exit;
  end;

  FContext.ExecuteDdl('DROP USER ' + QuotedName(AUserName));
  Log.Info('User dropped: ' + AUserName);
end;

{------------------------------------------------------------------------------
  TSecurityService.ExecuteViaServices
  ----------------------------------------------------------------------------
  Performs one user action through the Services API.

  Parameters:
    AAction   - Add, modify or delete.
    AUser     - The account.
    APassword - The password, where the action takes one.

  Notes:
    A fresh attachment per action. These are single, quick calls, and holding a
    service attachment open between them would keep a lock on the security
    database for as long as the dialog stayed on screen.
------------------------------------------------------------------------------}
procedure TSecurityService.ExecuteViaServices(AAction: TSecurityAction;
  const AUser: TUserAccount; const APassword: string);
var
  Connection: TServiceConnection;
  Service: TIBXSecurityService;
begin
  Connection := TServiceConnection.Create(FRegistration);
  Service := nil;
  try
    Connection.Connect(FPassword);

    Service := TIBXSecurityService.Create(nil);
    Service.ServicesConnection := Connection.Connection;
    Service.UserName := AUser.UserName;

    if AAction <> ActionDeleteUser then
    begin
      Service.FirstName := AUser.FirstName;
      Service.MiddleName := AUser.MiddleName;
      Service.LastName := AUser.LastName;
      if APassword <> '' then
        Service.Password := APassword;
    end;

    case AAction of
      ActionAddUser:    Service.AddUser;
      ActionModifyUser: Service.ModifyUser;
      ActionDeleteUser: Service.DeleteUser;
    end;

    Log.Info('User action through the Services API: ' + AUser.UserName);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

end.
