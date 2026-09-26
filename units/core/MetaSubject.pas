{==============================================================================
  Unit:        MetaSubject
  Purpose:     The change-notification mechanism the whole metadata model is
               built on. An object that can change descends from TMetaSubject;
               anything that displays it implements IMetaObserver.
  Author:      Alexandros Ntermaris
  Created:     2026-08-20
  Depends on:  Classes, SysUtils

  Ported from FlameRobin's core/Subject.h + core/Observer.h. This is the piece
  IBConsole lacked: it refreshed the tree by rebuilding branches by hand, which
  is why dropping an object there could leave a stale node or an open window
  pointing at something that no longer existed. Here the tree node, the open
  property page and the editor's autocomplete all observe the same item, so one
  NotifyObservers call keeps every view honest.

  Note on the coding rules: PASCAL-LAZARUS-RULES.md wants one public class per
  unit. IMetaObserver and TMetaSubject reference each other, so splitting them
  would create a circular unit reference - which the same rules forbid, and
  rightly. They stay together deliberately.
==============================================================================}
unit MetaSubject;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TMetaSubject = class;

  { IMetaObserver
    Implemented by anything that displays a metadata object and must react when
    it changes or goes away. }
  IMetaObserver = interface
    ['{3F8B21D4-6C57-4A19-9E02-5D7A4B6C8E13}']
    { The subject's contents changed and the view must be refreshed. }
    procedure SubjectChanged(ASubject: TMetaSubject);
    { The subject is being destroyed. The observer must drop every reference to
      it before returning; the pointer is invalid afterwards. }
    procedure SubjectRemoved(ASubject: TMetaSubject);
  end;

  { TMetaSubject
    Base of every object that can be observed. Keeps a list of observers and
    tells them when something changed.

    Notification can be deferred: LockSubject increments a counter and
    UnlockSubject decrements it, firing a single notification on the way back
    to zero if anything changed meanwhile. Loading two thousand columns
    therefore repaints the view once, not two thousand times. }
  TMetaSubject = class(TObject)
  private
    FObservers: TInterfaceList;
    FLockCount: Integer;
    FChangedWhileLocked: Boolean;
  protected
    { Called just before observers are told about a change. Descendants may
      override it to refresh derived state first. }
    procedure DoBeforeNotify; virtual;
  public
    constructor Create;
    destructor Destroy; override;

    { Registers AObserver. Adding the same observer twice is harmless: the
      second call does nothing. }
    procedure AttachObserver(AObserver: IMetaObserver);
    { Unregisters AObserver. Removing an observer that is not attached is
      harmless. }
    procedure DetachObserver(AObserver: IMetaObserver);
    { Unregisters every observer without notifying them. }
    procedure DetachAllObservers;

    { Tells every observer the subject changed, or records that it did when the
      subject is locked. }
    procedure NotifyObservers;

    { Defers notification until the matching UnlockSubject. Calls nest. }
    procedure LockSubject;
    { Ends one level of deferral, notifying observers if anything changed while
      locked and this was the outermost lock. }
    procedure UnlockSubject;

    { True while notification is deferred. }
    function IsLocked: Boolean;
    { How many observers are attached. }
    function ObserverCount: Integer;
  end;

implementation

{------------------------------------------------------------------------------
  TMetaSubject.Create
  ----------------------------------------------------------------------------
  Creates a subject with no observers.
------------------------------------------------------------------------------}
constructor TMetaSubject.Create;
begin
  inherited Create;
  FObservers := TInterfaceList.Create;
  FLockCount := 0;
  FChangedWhileLocked := False;
end;

{------------------------------------------------------------------------------
  TMetaSubject.Destroy
  ----------------------------------------------------------------------------
  Tells every observer the subject is going away, then releases the list.

  Notes:
    The list is walked backwards because SubjectRemoved is expected to detach
    the observer, which shortens the list underneath us.
------------------------------------------------------------------------------}
destructor TMetaSubject.Destroy;
var
  I: Integer;
  Observer: IMetaObserver;
begin
  if FObservers <> nil then
  begin
    for I := FObservers.Count - 1 downto 0 do
    begin
      if Supports(FObservers[I], IMetaObserver, Observer) then
        Observer.SubjectRemoved(Self);
    end;
    FObservers.Clear;
    FreeAndNil(FObservers);
  end;
  inherited Destroy;
end;

{------------------------------------------------------------------------------
  TMetaSubject.DoBeforeNotify
  ----------------------------------------------------------------------------
  Hook called immediately before observers are notified. Does nothing here.
------------------------------------------------------------------------------}
procedure TMetaSubject.DoBeforeNotify;
begin
  // nothing by default
end;

{------------------------------------------------------------------------------
  TMetaSubject.AttachObserver
  ----------------------------------------------------------------------------
  Registers an observer.

  Parameters:
    AObserver - The observer to add. Nil and duplicates are ignored.
------------------------------------------------------------------------------}
procedure TMetaSubject.AttachObserver(AObserver: IMetaObserver);
begin
  if AObserver = nil then
    Exit;
  if FObservers.IndexOf(AObserver) < 0 then
    FObservers.Add(AObserver);
end;

{------------------------------------------------------------------------------
  TMetaSubject.DetachObserver
  ----------------------------------------------------------------------------
  Unregisters an observer.

  Parameters:
    AObserver - The observer to remove. Nil and unknown observers are ignored.
------------------------------------------------------------------------------}
procedure TMetaSubject.DetachObserver(AObserver: IMetaObserver);
var
  Index: Integer;
begin
  if (AObserver = nil) or (FObservers = nil) then
    Exit;
  Index := FObservers.IndexOf(AObserver);
  if Index >= 0 then
    FObservers.Delete(Index);
end;

{------------------------------------------------------------------------------
  TMetaSubject.DetachAllObservers
  ----------------------------------------------------------------------------
  Removes every observer without notifying them.
------------------------------------------------------------------------------}
procedure TMetaSubject.DetachAllObservers;
begin
  if FObservers <> nil then
    FObservers.Clear;
end;

{------------------------------------------------------------------------------
  TMetaSubject.NotifyObservers
  ----------------------------------------------------------------------------
  Tells every observer the subject changed.

  Notes:
    Does nothing but set a flag while the subject is locked; the notification
    then happens once when the outermost UnlockSubject runs. The observer list
    is walked backwards so that an observer detaching itself in response does
    not make the loop skip its neighbour.
------------------------------------------------------------------------------}
procedure TMetaSubject.NotifyObservers;
var
  I: Integer;
  Observer: IMetaObserver;
begin
  if FLockCount > 0 then
  begin
    FChangedWhileLocked := True;
    Exit;
  end;

  DoBeforeNotify;

  for I := FObservers.Count - 1 downto 0 do
  begin
    if I >= FObservers.Count then
      Continue;
    if Supports(FObservers[I], IMetaObserver, Observer) then
      Observer.SubjectChanged(Self);
  end;
end;

{------------------------------------------------------------------------------
  TMetaSubject.LockSubject
  ----------------------------------------------------------------------------
  Defers notification until the matching UnlockSubject. Calls nest.
------------------------------------------------------------------------------}
procedure TMetaSubject.LockSubject;
begin
  Inc(FLockCount);
end;

{------------------------------------------------------------------------------
  TMetaSubject.UnlockSubject
  ----------------------------------------------------------------------------
  Ends one level of deferral.

  Notes:
    Fires a single notification when the outermost lock is released and
    something changed meanwhile. Unbalanced calls are clamped at zero rather
    than allowed to go negative, because a stuck negative count would silence
    the object permanently - a bug that is very hard to see.
------------------------------------------------------------------------------}
procedure TMetaSubject.UnlockSubject;
begin
  if FLockCount > 0 then
    Dec(FLockCount);

  if (FLockCount = 0) and FChangedWhileLocked then
  begin
    FChangedWhileLocked := False;
    NotifyObservers;
  end;
end;

{------------------------------------------------------------------------------
  TMetaSubject.IsLocked
  ----------------------------------------------------------------------------
  Returns True while notification is deferred.
------------------------------------------------------------------------------}
function TMetaSubject.IsLocked: Boolean;
begin
  Result := FLockCount > 0;
end;

{------------------------------------------------------------------------------
  TMetaSubject.ObserverCount
  ----------------------------------------------------------------------------
  Returns how many observers are attached.
------------------------------------------------------------------------------}
function TMetaSubject.ObserverCount: Integer;
begin
  if FObservers = nil then
    Result := 0
  else
    Result := FObservers.Count;
end;

end.
