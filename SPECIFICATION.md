# IBQConsole — Specification

**A Firebird database editor and administration console for Windows and Linux, written in Free Pascal / Lazarus.**

Status: draft 3 · 2026-08-20
Coding standard: `../PASCAL-LAZARUS-RULES.md` (mandatory)

---

## 1. Positioning

IBQConsole takes **the interaction model of IBConsole** and **the feature set of FlameRobin**.

| Source | What we take | What we leave |
|---|---|---|
| **IBConsole 1.0** (Delphi/IBX, 2000) | Tree-of-servers-and-databases mental model, folder nodes, the Properties / Metadata / Permissions / Data / Dependencies tab layout, the Server → Database → Maintenance menu spine, the ISQL window with Data / Output / Statistics tabs | Registry-based storage, MDI, Win32-only `HTreeItem` handles, 39 flat node constants, InterBase-era feature gaps |
| **FlameRobin 26.8.3** (C++20/wx) | Rich node type model, lazy-loading metadata items with load-state, visitor-based DDL generation, "Script as…" generators, browse data, execute procedure, generator/index statistics, dependencies, monitors, the full admin service set | wxWidgets, HTML-template property pages, MCP/vector/AI features (post-v1), C++ idioms |

**Design sentence:** *A user who knows IBConsole must be productive in IBQConsole within five minutes, and must never have to leave it for something FlameRobin could do.*

---

## 2. Locked decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| D1 | Firebird access layer | **IBX for Lazarus** (MWA Software) | Direct descendant of IBConsole's own components (`TIBDatabase`, `TIBTransaction`, `TIBSQL`, `TIBDataSet`). Critically, it is the only Lazarus option with a full **Services API** wrapper — backup, restore, validate, statistics, user security, shutdown/startup — which *is* the IBConsole maintenance feature set. Also ships `TIBExtract` for DDL extraction. |
| D2 | UI shell | **Tree + tabbed right pane** | Single main window: object tree left, splitter, `TPageControl` right. Keeps IBConsole's model, avoids Lazarus MDI (Windows-only, semi-deprecated), works identically on Linux. |
| D3 | v1.0 scope | **Browse + SQL + core admin** | Registration, tree, property pages, data grid, SQL editor, DDL extraction, and backup/restore/sweep/validate/statistics/shutdown/users. |
| D4 | Targets | **Firebird 3.0 – 6.0, Windows + Linux** | Covers modern production. FB3 baseline removes legacy user-management quirks. FB6 SQL schemas supported. |
| D5 | Registration import | **Import FlameRobin and IBConsole registrations** | One-click migration for existing users of both tools. Read-only import; we never write back to their files. |
| D6 | SQL dialect 1 | **Refuse to connect** | Dialect 1 changes identifier rules, `NUMERIC` semantics, date/time types and `"quoted"` string meaning. Supporting it would contaminate `TIdentifier` and every numeric conversion for a shrinking legacy population. We detect it and explain it instead. |
| D7 | Embedded Firebird | **Supported** | Open a `.fdb` file directly with no server registered, via the embedded client. |
| D8 | Localisation | **Teramon's `.lng` system + `ApplyLocale`** — *built* | `LangStr(key, 'English default')` against UTF-8 INI language files, English compiled into the code so there is no `English.lng` and untranslated keys degrade to English. Runtime switching, no rebuild to add a language. Implemented in `units/core/LanguageHandle.pas` + `LangFileIO.pas` — see §11. |
| D9 | Icons | **Our own icon set, compiled into the executable** | Authored in `icons/`, compiled into a `.res` and linked in. No external image files to ship, lose, or license. |

### 2.1 Consequences of D4 that shape the code

FB 3 → 6 is not one metadata schema; it is four. The differences are not cosmetic:

- **FB 3.0** — packages, SQL (PSQL) functions, identity columns, `RDB$` security on users moved to `SEC$` tables, SQL user management (`CREATE USER`).
- **FB 4.0** — `DECFLOAT(16|34)`, `INT128`, `TIME/TIMESTAMP WITH TIME ZONE`, `RDB$PUBLICATIONS` (replication), `SQL SECURITY` clause, `RDB$TIME_ZONES`.
- **FB 5.0** — partial indexes (`RDB$INDICES.RDB$CONDITION_SOURCE`), parallel backup/sweep, profiler tables, `SKIP LOCKED`.
- **FB 6.0** — **SQL schemas**: system tables gain `RDB$SCHEMA_NAME`, object names become two-part, and every metadata query and every generated DDL statement must be schema-qualified.

→ Metadata SQL is therefore **not** hard-coded in the model classes. It comes from a version-specific provider (§5.4).

---

## 3. Architecture

Four layers, strictly one-directional (a layer may only use the ones below it):

```
┌──────────────────────────────────────────────┐
│  forms/           UI: main window, property  │  ← knows the model, never SQL
│                   pages, dialogs, editors    │
├──────────────────────────────────────────────┤
│  units/model/     Metadata object tree       │  ← TMetaItem hierarchy, DDL,
│                   (TMetaTable, TMetaView…)   │     load-state, notification
├──────────────────────────────────────────────┤
│  units/db/        Connections, transactions, │  ← IBX lives here and ONLY here
│  units/services/  metadata SQL, services     │
├──────────────────────────────────────────────┤
│  units/core/      Config, logging, errors,   │  ← no Firebird knowledge at all
│  units/sql/       identifiers, tokenizer     │
└──────────────────────────────────────────────┘
```

**Hard rules:**

1. No form unit contains an SQL string. Ever. (Rule already in `PASCAL-LAZARUS-RULES.md` §7.)
2. `IBDatabase`, `IBSQL`, `IBServices` appear in `units/db/` and `units/services/` **only**. If a form needs data it asks a model object or a repository.
3. The model layer knows nothing about `TTreeView`, `TPageControl` or any LCL control. It publishes changes; the UI subscribes.

### 3.1 Change notification

Ported from FlameRobin's Subject/Observer, in Pascal terms:

- `units/core/MetaSubject.pas` — `TMetaSubject`, holds a list of `IMetaObserver`.
- `units/core/MetaObserver.pas` — `IMetaObserver = interface` with `procedure SubjectChanged(ASubject: TMetaSubject); procedure SubjectRemoved(ASubject: TMetaSubject);`
- Every `TMetaItem` is a `TMetaSubject`. The tree node, the open property page and the SQL editor's autocomplete list all observe the same item, so a `DROP TABLE` executed in the editor refreshes the tree and closes the property tab automatically.

This is the single most important structural borrowing from FlameRobin, and the thing IBConsole did worst (it refreshed by rebuilding tree branches by hand).

---

## 4. Object model

### 4.1 Node types

One enum replaces IBConsole's 39 integer constants. Collection ("folder") nodes and item nodes are distinguished by naming, exactly as FlameRobin does:

```pascal
type
  TMetaNodeType = (
    mntUnknown,
    mntRoot, mntServer, mntDatabase,
    mntSchema,          mntSchemas,          // FB6+
    mntDomain,          mntDomains,
    mntSysDomain,       mntSysDomains,
    mntTable,           mntTables,
    mntGTT,             mntGTTs,             // global temporary tables
    mntSysTable,        mntSysTables,
    mntView,            mntViews,
    mntProcedure,       mntProcedures,
    mntFunctionSQL,     mntFunctionSQLs,     // FB3+ PSQL functions
    mntUDF,             mntUDFs,             // legacy external functions
    mntPackage,         mntPackages,         // FB3+
    mntTriggerDML,      mntTriggersDML,
    mntTriggerDB,       mntTriggersDB,
    mntTriggerDDL,      mntTriggersDDL,
    mntGenerator,       mntGenerators,
    mntException,       mntExceptions,
    mntIndex,           mntIndices,
    mntSysIndex,        mntSysIndices,
    mntRole,            mntRoles,
    mntUser,            mntUsers,
    mntCharacterSet,    mntCharacterSets,
    mntCollation,       mntCollations,
    mntPublication,     mntPublications,     // FB4+
    mntBlobFilter,      mntBlobFilters,
    mntColumn,          mntColumns,
    mntParameter,       mntParameters,
    mntConstraintPK,    mntConstraintFK,
    mntConstraintUnique, mntConstraintCheck,
    mntConstraints,
    mntDependency,
    mntBackupAlias,     mntBackupAliases,    // IBConsole concept, kept
    mntServerLog
  );
```

Kept from IBConsole and *not* in FlameRobin: `mntBackupAlias` / `mntBackupAliases` (a saved backup destination with source server + alias + file list) and `mntServerLog`. These are genuinely useful and cheap to keep.

### 4.2 Base class

`units/model/MetaItem.pas`:

```pascal
type
  TMetaLoadState = (mlsNotLoaded, mlsLoading, mlsLoaded, mlsUnavailable);

  { TMetaItem
    Base of every metadata object. Owns its children; the parent owns it.
    A MetaItem never touches the database directly — it asks its owning
    TDatabaseContext (see units/db) for a loader. }
  TMetaItem = class(TMetaSubject)
  private
    FParent: TMetaItem;
    FNodeType: TMetaNodeType;
    FName: TIdentifier;          // quoted/unquoted aware, schema aware
    FObjectId: Integer;
    FDescription: string;
    FChildrenState: TMetaLoadState;
    FPropertiesState: TMetaLoadState;
    FChildren: TMetaItemList;
  protected
    procedure LoadChildren; virtual;
    procedure LoadProperties; virtual;
    procedure LoadDescription; virtual;
  public
    constructor Create(AParent: TMetaItem; ANodeType: TMetaNodeType;
      const AName: string);
    destructor Destroy; override;

    function Database: TDatabaseContext; virtual;
    procedure EnsureChildrenLoaded;
    procedure EnsurePropertiesLoaded;
    procedure Invalidate;                  // drop caches, notify observers

    function GetCreateSQL: string; virtual;
    function GetAlterSQL: string; virtual;
    function GetDropSQL: string; virtual;
    function GetQuotedName: string;
    function GetDisplayName: string; virtual;
    function GetImageIndex: Integer; virtual;

    procedure Accept(AVisitor: TMetaVisitor); virtual;

    property Parent: TMetaItem read FParent;
    property NodeType: TMetaNodeType read FNodeType;
    property Name: TIdentifier read FName;
    property ObjectId: Integer read FObjectId;
    property Description: string read GetDescription write SetDescription;
    property Children: TMetaItemList read GetChildren;
  end;
```

**Lazy loading is the rule.** Expanding a database node must not read the whole schema. A folder node loads its item list on first expand; an item loads its properties on first selection. This is what makes the tool usable on a 4000-table database, and is exactly FlameRobin's `lsNotLoaded → lsLoadPending → lsLoaded` state machine.

### 4.3 Concrete classes — one per unit

`units/model/`, one public class per file (rules §2):

| Unit | Class | Notes |
|---|---|---|
| `MetaItem.pas` | `TMetaItem` | base, above |
| `MetaItemList.pas` | `TMetaItemList` | owning `TFPGObjectList` |
| `MetaCollection.pas` | `TMetaCollection` | folder node; knows its child node type and its loader |
| `MetaRoot.pas` | `TMetaRoot` | the registered-servers root |
| `MetaServer.pas` | `TMetaServer` | host, port, protocol, registered databases, backup aliases |
| `MetaDatabase.pas` | `TMetaDatabase` | owns the `TDatabaseContext`; the busiest class |
| `MetaSchema.pas` | `TMetaSchema` | FB6+ |
| `MetaRelation.pas` | `TMetaRelation` | shared base of table/view/GTT: has columns, triggers |
| `MetaTable.pas` | `TMetaTable` | + indices, constraints, `IsGTT`, `IsExternal`, temporal info |
| `MetaView.pas` | `TMetaView` | + source, `IsUpdatable` |
| `MetaColumn.pas` | `TMetaColumn` | type, domain, nullability, default, computed, identity, collation |
| `MetaDomain.pas` | `TMetaDomain` | |
| `MetaProcedure.pas` | `TMetaProcedure` | in/out parameters, source, package owner |
| `MetaFunction.pas` | `TMetaFunction` | PSQL function (FB3+) |
| `MetaUDF.pas` | `TMetaUDF` | legacy declared external function |
| `MetaPackage.pas` | `TMetaPackage` | header + body, contained procs/functions |
| `MetaTrigger.pas` | `TMetaTrigger` | DML / DB / DDL variants via `TTriggerKind` |
| `MetaGenerator.pas` | `TMetaGenerator` | value, increment (FB4+) |
| `MetaException.pas` | `TMetaException` | number, message |
| `MetaIndex.pas` | `TMetaIndex` | segments, unique, descending, active, selectivity, condition (FB5+) |
| `MetaConstraint.pas` | `TMetaConstraint` | PK / FK / UNIQUE / CHECK via `TConstraintKind` |
| `MetaRole.pas` | `TMetaRole` | |
| `MetaUser.pas` | `TMetaUser` | `SEC$USERS` on FB3+ |
| `MetaPrivilege.pas` | `TMetaPrivilege` | grantee, object, privilege bits, grant option |
| `MetaDependency.pas` | `TMetaDependency` | direction-aware |
| `MetaCharacterSet.pas` | `TMetaCharacterSet` | |
| `MetaCollation.pas` | `TMetaCollation` | |
| `MetaPublication.pas` | `TMetaPublication` | FB4+ |
| `MetaBackupAlias.pas` | `TMetaBackupAlias` | IBConsole concept |

### 4.4 Visitors

`units/model/MetaVisitor.pas` declares the abstract `TMetaVisitor` with one `VisitXxx` per concrete class. Three implementations in v1:

- `units/ddl/DdlCreateVisitor.pas` → `TDdlCreateVisitor` — produces `CREATE` DDL
- `units/ddl/DdlDropVisitor.pas` → `TDdlDropVisitor` — produces `DROP` DDL
- `forms/../ContextMenuVisitor.pas` → `TContextMenuVisitor` — builds the right-click menu per object type

This is straight from FlameRobin (`CreateDDLVisitor`, `ContextMenuMetadataItemVisitor`) and it is the right pattern: adding an object type means adding one class and one `Visit` method, not editing a 3000-line `case` statement — which is precisely what went wrong in IBConsole's `frmuMain.pas` (132 KB) and `zluDDLExtraction.pas` (115 KB).

---

## 5. Database layer (`units/db/`)

### 5.1 `TDatabaseContext` — `units/db/DatabaseContext.pas`

Direct descendant of IBConsole's `TibcDatabaseNode`, cleaned up. One per registered database.

Owns:

| Member | Purpose |
|---|---|
| `FDatabase: TIBDatabase` | the attachment |
| `FMetaTransaction: TIBTransaction` | **read committed, read-only** — all metadata browsing. Never blocks, never blocked. |
| `FDdlTransaction: TIBTransaction` | **snapshot, read-write, wait** — DDL execution, committed immediately after each statement |
| `FServerVersion: TServerVersion` | major.minor + ODS, filled at connect |
| `FSqlProvider: TMetadataSqlProvider` | version-specific SQL (§5.4) |
| `FCharacterSet, FRole, FUserName` | connection parameters |

IBConsole kept exactly this two-transaction split (`TRA_DDL` / `TRA_DFLT` in `zluGlobal.pas`) and it is correct — keep it. Each SQL editor window gets its **own** third transaction it controls explicitly, so a user's uncommitted work never blocks metadata browsing.

### 5.2 Version detection — `units/db/ServerVersion.pas`

```pascal
type
  TServerVersion = record
    Major, Minor: Integer;
    OdsMajor, OdsMinor: Integer;
    IsFirebird: Boolean;
    RawVersion: string;
    function AtLeast(AMajor, AMinor: Integer): Boolean;
  end;
```

### 5.3 Feature gating — `units/db/FeatureSet.pas`

```pascal
type
  TDbFeature = (
    dbfPackages,          // FB3+
    dbfSqlFunctions,      // FB3+
    dbfIdentityColumns,   // FB3+
    dbfSqlUserManagement, // FB3+
    dbfDecFloat,          // FB4+
    dbfInt128,            // FB4+
    dbfTimeZones,         // FB4+
    dbfPublications,      // FB4+
    dbfSqlSecurity,       // FB4+
    dbfPartialIndexes,    // FB5+
    dbfParallelWorkers,   // FB5+
    dbfSchemas            // FB6+
  );

  { Returns True when the connected server supports AFeature. }
  function Supports(const AVersion: TServerVersion; AFeature: TDbFeature): Boolean;
```

**UI contract:** features the server does not support are **hidden**, not disabled-and-greyed. A FB3 database must not show an empty "Publications" folder.

### 5.4 Metadata SQL providers — `units/db/`

```
MetadataSqlProvider.pas      TMetadataSqlProvider   (abstract; declares every query)
MetadataSqlProviderFB3.pas   TMetadataSqlProviderFB3
MetadataSqlProviderFB4.pas   TMetadataSqlProviderFB4  (inherits FB3, overrides what changed)
MetadataSqlProviderFB5.pas   TMetadataSqlProviderFB5
MetadataSqlProviderFB6.pas   TMetadataSqlProviderFB6  (schema-qualified everything)
MetadataSqlProviderFactory.pas  TMetadataSqlProviderFactory.CreateFor(AVersion)
```

Every RDB$ query in the product lives in exactly one of these five files. This is the single highest-value architectural decision in the spec: it turns "supports FB3–FB6" from a maintenance nightmare into five readable files.

### 5.5 Loaders — `units/db/`

`TMetaLoader` descendants that turn a result set into model objects: `TableLoader`, `ColumnLoader`, `IndexLoader`, `ProcedureLoader`, … Each is one unit, one class, and is the only code that knows both `TIBSQL` and `TMetaItem`.

### 5.6 Connection modes — `units/db/ConnectionProfile.pas`

A registered database carries a mode, and the mode decides the connection string and which client library is loaded:

```pascal
type
  TConnectionMode = (
    cmRemote,      // host:port:/path/to/db.fdb  — TCP, the normal case
    cmLocal,       // /path/to/db.fdb            — local server, no network
    cmEmbedded     // /path/to/db.fdb            — embedded engine, no server at all
  );
```

**Embedded (D7) specifics:**

- Requires `fbclient.dll` built with the embedded engine (Windows) or `libfbclient.so` + `libEngine13.so` (Linux). The client library path is a per-registration setting, defaulting to the application directory, so a user can ship IBQConsole with a private Firebird alongside it.
- Credentials are ignored by the engine but IBX still wants them; we send `SYSDBA` and suppress the login dialog.
- **The whole Server branch is unavailable** in embedded mode — no Services API, therefore no backup, restore, validate, statistics, sweep, shutdown, user management or server log. The tree shows an *Embedded Databases* root beside *Firebird Servers*, and the Database → Maintenance menu is hidden for those nodes (hidden, not greyed — §5.3 UI contract).
- Only one process may hold an embedded database open. The connect error for a locked file gets a specific, readable message rather than the raw Firebird status vector.
- The registration dialog gets an *Embedded* tab: database file, client library path, page buffers, and a "test open" button.

### 5.6.1 Client library per registration

A machine commonly runs several Firebird versions side by side, each on its own
port. Whichever `fbclient` is first on the system search path then decides which
client the program loads — an accident rather than a decision, and one that
produces confusing failures instead of a clear "wrong version" message.

Therefore **both a server registration and an embedded database profile carry a
`ClientLibrary` path**, stored as `clientlib` in `registrations.xml`. A database
registered under a server inherits the server's library unless it names its own.
An empty value means "use the system default", which is right on a machine with
one Firebird.

`units/db/FbClientLocator.pas` finds the installed libraries and reads their
versions, so the registration dialog offers a list rather than demanding a typed
path. Search order: the application's own directory first (a portable install
shipping its own Firebird must win), then the conventional install roots.

Two rules the UI depends on:

- **A newer client reaches an older server** — a 5.0 client talks to 3.0, 4.0
  and 5.0 servers; the reverse is not true. `BestClientFor` prefers an exact
  major-version match and falls back to the newest installed.
- **A named library that does not exist is refused at registration time**, not
  at connect time, where it would surface as an unreadable load failure.

Whether one process can hold several different client versions at once is a
property of the database layer and is listed as an open question in §18.

### 5.7 Dialect handling (D6)

`SELECT MON$SQL_DIALECT FROM MON$DATABASE` (FB2.1+) is read immediately after attach, before any metadata query runs.

- **Dialect 3** — normal operation.
- **Dialect 1** — the connection is closed and a dialog explains: *"EMPLOYEE.FDB uses SQL dialect 1. IBQConsole requires dialect 3. Dialect 1 databases can be migrated with `gfix -sql_dialect 3` after verifying that no `"double quoted strings"` or dialect-1 `DATE` columns are in use."* No read-only fallback, no partial mode — a half-working editor on a legacy database is worse than a clear refusal.
- **Dialect 2** — treated as dialect 1 (it exists only as a migration diagnostic mode).

The check lives in `TDatabaseContext.Connect` so every code path — tree connect, SQL editor, registration test — gets it for free.

---

## 6. Services layer (`units/services/`)

Thin, cancellable, threaded wrappers over IBX's `TIBBackupService` etc. One class per service, one unit each:

| Unit | Class | IBConsole equivalent | FlameRobin equivalent |
|---|---|---|---|
| `BackupService.pas` | `TBackupService` | `frmuDBBackup` | `BackupFrame` |
| `RestoreService.pas` | `TRestoreService` | `frmuDBRestore` | `RestoreFrame` |
| `ValidationService.pas` | `TValidationService` | `frmuDBValidation` | `MaintenanceFrame` |
| `StatisticsService.pas` | `TStatisticsService` | `frmuDBStatistics` | |
| `SweepService.pas` | `TSweepService` | Maintenance→Sweep | |
| `ShutdownService.pas` | `TShutdownService` | `frmuDBShutdown` | `ShutdownFrame` |
| `StartupService.pas` | `TStartupService` | Database Restart | `StartupFrame` |
| `SecurityService.pas` | `TSecurityService` | `frmuUser` | `UserDialog` |
| `TransactionRecoveryService.pas` | `TTransactionRecoveryService` | `frmuDBTransactions` | |
| `ServerLogService.pas` | `TServerLogService` | View Logfile | |

Common base `units/services/ServiceRunner.pas` → `TServiceRunner`:

- runs the service on a `TThread`
- streams output lines back to the UI via `Synchronize`
- exposes `Cancel`, `OnProgress`, `OnLine`, `OnFinished(ASuccess, AError)`
- the UI never calls a service method directly on the main thread

**Note on FB3+ user management:** `SecurityService` prefers SQL (`CREATE/ALTER/DROP USER`, `SEC$USERS`) when `dbfSqlUserManagement` is available and falls back to the Services API only for legacy servers. IBX's `TIBSecurityService` alone is not sufficient on FB3+ because it cannot see plugin-managed users.

---

## 7. SQL layer (`units/sql/`)

| Unit | Class | Purpose |
|---|---|---|
| `Identifier.pas` | `TIdentifier` | Quoting rules, case folding, dialect 1 vs 3, FB6 two-part `SCHEMA.OBJECT` names. Every name in the model is a `TIdentifier`, never a raw string — this is what makes FB6 schema support tractable. |
| `SqlTokenizer.pas` | `TSqlTokenizer` | Token stream; comments, strings, `q''` quoted literals |
| `SqlStatementSplitter.pas` | `TSqlStatementSplitter` | Splits a script into statements, **honouring `SET TERM`**. Required for running extracted DDL scripts. |
| `SqlStatementInfo.pas` | `TSqlStatementInfo` | Classifies a statement (DDL/DML/SELECT/EXECUTE BLOCK/transaction control) so the editor knows whether to show a grid, a row count, or a commit prompt |
| `SqlFormatter.pas` | `TSqlFormatter` | Optional pretty-printer (post-v1 acceptable) |
| `ScriptGenerator.pas` | `TScriptGenerator` | "Script as…" — SELECT FIRST 100 / INSERT / UPDATE / DELETE / MERGE / EXECUTE, from a `TMetaRelation` or `TMetaProcedure` |

---

## 8. User interface (`forms/`)

### 8.1 Main window — `forms/frmMain.pas`

```
┌─ IBQConsole ─────────────────────────────────────────────────────────┐
│ Console  View  Server  Database  Object  Tools  Window  Help          │  ← IBConsole's menu spine
├──────────────────────────────────────────────────────────────────────┤
│ [Register] [Connect] [Disconnect] │ [New SQL] [Execute] │ [Refresh]   │
├───────────────────┬──────────────────────────────────────────────────┤
│ ▼ Firebird Servers│ ┌ EMPLOYEE:CUSTOMER ─┬─ SQL Editor 1 ─┬─ … ─┐    │
│  ▼ localhost      │ │ Properties Columns Indexes Constraints    │    │
│    ▼ Databases    │ │ Triggers Dependencies Permissions Data DDL│    │
│      ▼ EMPLOYEE   │ ├───────────────────────────────────────────┤    │
│        ▶ Domains  │ │                                           │    │
│        ▼ Tables   │ │        (page for the selected tab)        │    │
│          CUSTOMER │ │                                           │    │
│          COUNTRY  │ │                                           │    │
│        ▶ Views    │ └───────────────────────────────────────────┘    │
│        ▶ Procedu… │                                                  │
│    ▶ Backup Alias │                                                  │
├───────────────────┴──────────────────────────────────────────────────┤
│ localhost:EMPLOYEE · SYSDBA · FB 5.0.1 · ODS 13.1 · UTF8 · Read only  │  ← status bar
└──────────────────────────────────────────────────────────────────────┘
```

- Left: `TTreeView` (`tvObjects`) driven by `units/model`. Each `TTreeNode.Data` holds the `TMetaItem` pointer; the item never holds the tree node — the tree observes the item.
- Right: `TPageControl` (`pgcWorkspace`) with closable tabs. Two tab kinds in v1: **object page** and **SQL editor**.
- Bottom (collapsible): log panel showing every statement the application itself executed. IBConsole had nothing like this and FlameRobin's log is one of its most-used features for learning what the tool is doing.
- Status bar: server, database, user, server version, ODS, charset, transaction state.

### 8.2 Menus (IBConsole's spine, FlameRobin's contents)

```
Console   Register Server… · Register Database… · Preferences… · Exit
View      Refresh · Show System Objects · Show Log Panel · Object Tree Filter…
Server    Connect · Disconnect · Properties… · Server Log… · Manage Users… ·
          Diagnose Connection… · Unregister
Database  Connect · Connect As… · Disconnect · Create Database… · Drop Database… ·
          Properties… · Registration Info… · Unregister
          Maintenance ▸ Backup… · Restore… · Sweep · Validate… · Statistics… ·
                        Shutdown… · Startup… · Transaction Recovery… ·
                        Connected Users… · Extract Metadata…
Object    Create New… · Alter… · Drop… · Refresh · Browse Data ·
          Script as ▸ SELECT (FIRST 100) · INSERT · UPDATE · DELETE · MERGE ·
                      CREATE · ALTER · DROP · EXECUTE
          Properties…
Tools     New SQL Editor · Configure External Tools… · Options…
Window    (open tabs) · Close All
Help      Contents · Firebird Language Reference · About…
```

All commands are `TAction`s on a single `TActionList` in `forms/dmActions.pas` (a data module), so tree context menu, main menu, toolbar and keyboard shortcut share one handler and one enabled-state calculation. IBConsole did this correctly (`dmActions`) — keep it.

### 8.3 Object property pages

One form per object family, hosted inside the workspace tab. Tabs per type — merging IBConsole's `frmuObjectWindow` tabs with FlameRobin's property frames:

| Object | Tabs |
|---|---|
| Database | Properties · Files & Shadows · Character Sets · Statistics · DDL |
| Table / GTT | Properties · Columns · Indexes · Constraints · Triggers · Dependencies · Permissions · **Data** · DDL |
| View | Properties · Columns · Source · Dependencies · Permissions · **Data** · DDL |
| Procedure | Properties · Parameters · Source · Dependencies · Permissions · DDL · **Execute** |
| Function (SQL) | Properties · Parameters · Source · Dependencies · Permissions · DDL · **Execute** |
| UDF | Properties · Declaration · Dependencies · DDL |
| Package | Properties · Header · Body · Contents · Dependencies · Permissions · DDL |
| Trigger | Properties · Source · Dependencies · DDL |
| Generator | Properties (value, increment) · Dependencies · DDL |
| Exception | Properties (number, message) · Dependencies · DDL |
| Domain | Properties · Used By · DDL |
| Index | Properties (segments, selectivity, condition) · DDL |
| Role | Properties · Members · Permissions · DDL |
| User | Properties · Roles · Granted Privileges |

Forms: `forms/frmObjectPageTable.pas`, `frmObjectPageView.pas`, … one class per unit per the rules. Shared behaviour in `forms/frmObjectPageBase.pas` → `TfrmObjectPageBase` (holds the `TMetaItem`, implements `IMetaObserver`, handles refresh/close-on-drop).

### 8.4 SQL editor — `forms/frmSqlEditor.pas`

The successor to IBConsole's ISQL window and FlameRobin's `ExecuteSqlFrame`.

- **Editor:** `TSynEdit` + `TSynSQLSyn` (dialect `sqlInterbase6`), keyword list extended per connected server version. Line numbers, current-line highlight, bracket matching, code folding on `BEGIN…END`.
- **Execute (F5)** — current statement; **Execute script (F9)** — all statements via `TSqlStatementSplitter` with `SET TERM` support.
- **Result tabs:** Data (grid) · Messages · Statistics · Plan.
- **Plan tab:** the prepared statement's `PLAN`, plus `EXPLAIN` output on FB5+.
- **Statistics tab:** fetch counts, reads/writes/inserts/updates/deletes, elapsed — IBConsole showed this and it is genuinely useful.
- **Own transaction**, with an explicit Commit / Rollback pair on the toolbar and a visible transaction-state indicator. Never auto-commit DML silently.
- **Statement history** persisted per database (FlameRobin's `StatementHistoryDialog`), searchable with Ctrl+H.
- Autocomplete on Ctrl+Space from the loaded model (tables → columns), no extra round-trip.

### 8.5 Data grid — `forms/framDataGrid.pas` (a `TFrame`)

Used by both the object **Data** tab and the SQL editor result tab.

- Backed by `TIBDataSet` with generated update SQL when the source is a single updatable relation with a primary key; **read-only** otherwise, with the reason shown in the status strip ("no primary key — read only").
- Lazy fetch: fetch N rows, fetch more on scroll; never `FetchAll` on a large table.
- BLOB cells: preview text inline, `…` button opens `forms/frmBlobEditor.pas` (text / hex / image views, load & save file).
- NULL rendered distinctly from empty string. This is a correctness issue, not cosmetics.
- Export: CSV, TSV, JSON, HTML, Markdown, and INSERT statements (v1). XLSX post-v1.
- Right-click: Copy cell / Copy row as INSERT / Set to NULL / Export…

### 8.6 Dialogs (v1)

`frmServerRegistration` · `frmDatabaseRegistration` · `frmConnectAs` · `frmCreateDatabase` ·
`frmBackup` · `frmRestore` · `frmValidate` · `frmStatistics` · `frmShutdown` · `frmStartup` ·
`frmUserManager` · `frmUserEdit` · `frmConnectedUsers` · `frmTransactionRecovery` ·
`frmExtractMetadata` · `frmExecuteRoutine` · `frmBlobEditor` · `frmPreferences` ·
`frmServerProperties` · `frmAbout` · `frmProgress` · `frmSelectObject`

`frmServerProperties` is **built**: `Server > Properties…` and the tree's
right-click on a server node. Two sections in one list — what the registration
says (host, port, user, and which client library gets loaded, with its version
read from the file) and what the server says through its Services Manager
(version banner, implementation, install/lock/message locations, security
database, attachment count and every open database). The registration half is
shown without a password and without the server running, because that is
precisely the state a user is in when they go looking at a server's
properties.

All descend from `forms/frmDialogBase.pas` → `TfrmDialogBase` (IBConsole had `frmuDlgClass`; FlameRobin has `BaseDialog` — same idea): consistent OK/Cancel placement, Escape handling, size persistence.

---

## 9. Configuration and registration storage

- **Location:** `GetAppConfigDir(False)` → `%APPDATA%\IBQConsole\` on Windows, `~/.config/ibqconsole/` on Linux. Never the registry (IBConsole's mistake — unportable and invisible to users).
- **Format:** XML via `laz2_DOM` / `laz2_XMLRead`. Two files:
  - `registrations.xml` — servers, databases, backup aliases
  - `preferences.xml` — UI state, editor settings, grid settings
- **Per-database settings** (default charset, role, editor font, statement history) hang off the database's registration entry, as FlameRobin does.

### 9.1 Password storage — explicit policy

Three options offered per registration, default **(a)**:

- **(a) Do not store** — prompt at connect. Default and recommended.
- **(b) Store for this session only** — kept in memory, discarded at exit.
- **(c) Store encrypted** — AES-256 under a master password entered once per session.

Obfuscation without a master password will **not** be offered. FlameRobin and IBConsole both effectively stored recoverable passwords; we will not repeat that and will not describe (c) as anything stronger than it is: anyone with the file *and* the master password gets the credentials.

### 9.2 Importing existing registrations (D5)

`units/core/RegistrationImporter.pas` → `TRegistrationImporter`, offered on first run ("We found 14 databases registered in FlameRobin. Import them?") and available any time from **Console → Import Registrations…**.

| Source | Location | Format |
|---|---|---|
| **FlameRobin** | `%APPDATA%\flamerobin\fr_databases.conf`, `~/.flamerobin/fr_databases.conf` | XML: `<database>` nodes with `name`, `path`, `charset`, `username`, `role`, nested under `<server>` with `host`/`port` |
| **IBConsole** | Registry `HKCU\Software\Borland\InterBase\IBConsole\Servers` — the `Borland` level is real; `gRegServersKey` is *declared* in `zluGlobal.pas` but built in `zluPersistent.pas` `InitRegistry`, which is where the full path is | Windows registry keys per server, with database aliases beneath |
| **IBExpert / IBQConsole itself** | user-selected file | Post-v1 |

Rules:

- **Read-only.** We never write to, move, or delete the other tool's configuration. Both tools must keep working afterwards.
- Passwords are **not** imported even when the source file contains them, per §9.1(a). The user re-enters them once.
- Import is a preview list with checkboxes, not a silent bulk copy. Name collisions get a suffix, never an overwrite.
- Servers are deduplicated by host+port; databases by server+path.
- If neither source exists, the menu item stays but reports "nothing found" — it never errors.

---

## 10. Threading model

| Work | Thread |
|---|---|
| Metadata loads (fast, indexed RDB$ queries) | Main thread, but with a busy cursor and a 250 ms "still working" indicator |
| Statement execution from the SQL editor | Worker thread; grid populated via `Synchronize` |
| Backup / restore / validate / statistics / sweep | Worker thread (`TServiceRunner`), output streamed live, cancellable |
| Full-database metadata extraction | Worker thread |

No `Application.ProcessMessages` loops (rules §7). Anything that can take longer than a second gets a real thread and a cancel button.

---

## 11. Localisation (D8) — **implemented**

The Teramon system, adopted as-is. Built and living in `units/core/LanguageHandle.pas` and `units/core/LangFileIO.pas`.

### 11.1 The idea

**English is the code.** Every lookup carries its English text as the default argument:

```pascal
mnuDatabase.Caption := LangStr('mnuDatabase.caption', '&Database');
```

There is therefore **no `English.lng`** to write, ship or keep in sync, and a key that is missing, empty or commented out silently yields correct English. A half-finished translation is always shippable — this is the property that makes the approach fast in practice, and it is why it beats gettext for a project this size.

### 11.2 Files

```
lang/
├── Greek.lng
└── <Language>.lng      ← drop a file in, it appears in the menu. No rebuild.
```

UTF-8 INI, `;` comments, two sections:

```ini
[Fonts]
DialogFontName=Segoe UI
DialogFontSize=9

[Strings]
LangID=1032
mnuDatabase.caption=&Βάση δεδομένων
msg.confirmDrop=Να διαγραφεί το αντικείμενο "%s";$nlΗ ενέργεια δεν αναιρείται.
```

`$nl` expands to a line break. `[Fonts]` exists because some scripts need a different face or size to stay legible at the same control height.

`LanguageDir` looks beside the executable first — a portable install keeps its translations with it — and then in the two directories above, which is where the project’s own `lang/` sits when the program runs from `bin/<mode>/`. Without that second part the built program found no language files at all and the menu offered only English; because a missing translation falls back to English by design, nothing ever reported it. `tests/TestLanguageFile.pas` exists to ask the question the running program cannot.

### 11.3 Key naming

| Kind | Pattern | Example |
|---|---|---|
| Control caption | `<ComponentName>.caption` | `mnuDbConnect.caption` |
| Control hint | `<ComponentName>.hint` | `tbBackup.hint` |
| Edit label | `<ComponentName>.caption.lbl` | `edtPort.caption.lbl` |
| Tree folder node | `node.<plural>` | `node.procedures` |
| Object page tab | `tab.<name>` | `tab.dependencies` |
| Runtime message | `msg.<purpose>` | `msg.dialectRefused` |
| Action (caption\|shortcut\|hint) | `act.<name>` | `act.backup` |

### 11.4 API — `units/core/LanguageHandle.pas`

```pascal
function  LangStr(const AKey: string; const ADefaultText: string = ''): string;
function  LangStrFormat(const AKey: string; const AArgs: array of const;
            const ADefaultText: string = ''): string;
function  LangFontStr(const AKey, ADefault: string): string;
procedure AssignActionText(AAction: TAction; const AKey: string);

procedure ResetLang(const ANewLangFile: string);
procedure SetLanguage(const ALanguageName: string);   // switch + refresh, one call
function  CurrentLanguage: string;
procedure ListAvailableLanguages(AList: TStrings);

procedure ApplyLocale;                                 // every open form
procedure ApplyLocaleTo(AForm: TCustomForm);           // one form
```

Kept from Teramon unchanged: the `LangStr(key, default)` signature, the `n_` prefix fallback for reviewed-but-untranslated keys, `$nl`, `ChangeVar`, `ExtractStr`, `AssignActionText`'s `Caption|ShortCut|Hint` value, and the lazily-created `TMemIniFile` cache.

### 11.5 The one addition: `ILocalizable`

Teramon calls `TMainfrm.LoadLangStr` by name, so only the main form re-translates. IBQConsole has dozens of forms open at once, so the call is made through an interface instead:

```pascal
ILocalizable = interface
  ['{7A1C4E62-9D3B-4F58-B0A1-2E6C5D8F4A31}']
  procedure LoadLangStr;
end;
```

- Every translatable form declares `TfrmX = class(TForm, ILocalizable)` and implements `LoadLangStr` — a flat list of `Control.Caption := LangStr('key', 'English')`, exactly as in Teramon's `frmmain.pas`.
- Every form calls `ApplyLocaleTo(Self)` at the end of `FormCreate`, so a form opened after a language change starts in the right language.
- `SetLanguage('Greek')` re-translates **every open form** through `Screen.CustomForms`, with no restart. That is the whole of the Options dialog's language handling.

`LoadLangStr` is also the single place a form's text is set, which means the `.lfm` captions are only ever the design-time English — they are never the source of truth at runtime.

### 11.6 Editing tools

- `units/core/LangFileIO.pas` — `ReadLangStrings` / `UpdateLangStrings`: byte-safe update of the `[Strings]` section. BOM, line endings, comments, other sections and untouched keys are preserved exactly, so a translator's file is never reformatted behind their back. (Ported from Teramon's `langfileio.pas`.)
- `forms/frmTranslationEditor.pas` — in-app editor listing every key with its English default beside the translation, saving through `LangFileIO`. Teramon has the equivalent; worth having here from M1 so translation happens while the forms are being built, not after.
- `utils/extract-lang-keys` — scans `forms/*.pas` for `LangStr('key', 'default')` calls and reports keys present in code but missing from a given `.lng`, and keys in the file no longer used. Run before a release.

### 11.7 Layout consequence

Greek runs roughly 20–30 % longer than English. Every caption-bearing control uses `AutoSize` and anchors from the moment the form is drawn (already `PASCAL-LAZARUS-RULES.md` §7). Retrofitting that after fifty forms exist is the expensive part of localisation — not the translating.

---

## 12. Icons and resources (D9)

- Icons are **ours**, authored in `icons/` as SVG source plus exported PNGs at 16/24/32/48 px for HiDPI.
- Exports are listed in `resources/IBQConsole.rc`, compiled to `resources/IBQConsole.res`, and linked with `{$R IBQConsole.res}`. **Nothing is loaded from disk at runtime** — no image folder to ship, lose, or have go missing on a user's machine.
- One `TImageList` per size, populated from the resource at startup by `units/core/IconStore.pas` → `TIconStore`, which maps `TMetaNodeType` → image index. That mapping is the only place node types and icons meet; IBConsole scattered `NODE_*_IMG` constants through `zluGlobal.pas` and we do not repeat that.
- Icon naming: `node_table_16.png`, `node_table_24.png`, `act_backup_24.png`, `state_connected_16.png`. Mechanical, so the `.rc` can be regenerated by script.
- A small `utils/build-icons.*` script rebuilds PNGs from SVG and regenerates the `.rc`, so adding an icon is one command.

---

## 13. Error handling

- Base `EIbqError = class(Exception)` in `units/core/IbqError.pas`; `EIbqDatabaseError` carries the Firebird SQLCODE, GDSCODE and the full IB error stack.
- Firebird errors are shown with **all** interbase status vector lines, not just the first — the first line is usually the least informative one.
- Every failed statement is written to the log panel with its SQL text, so the user can copy it.
- No empty `except` blocks.

---

## 14. Project layout

Per `PASCAL-LAZARUS-RULES.md` §1:

```
IBQConsole/
├── IBQConsole.lpi / .lpr
├── SPECIFICATION.md                  ← this file
├── forms/           frmMain, frmSqlEditor, frmObjectPage*, dialogs, dmActions
├── units/
│   ├── core/        IbqError, MetaSubject, MetaObserver, AppConfig, AppLog,
│   │                CryptoStore, LocaleManager, IconStore, RegistrationImporter,
│   │                FbTypeUtils
│   ├── sql/         Identifier, SqlTokenizer, SqlStatementSplitter, ScriptGenerator
│   ├── model/       MetaItem and the ~30 concrete metadata classes
│   ├── db/          DatabaseContext, ConnectionProfile, ServerVersion, FeatureSet,
│   │                MetadataSqlProviderFB3..FB6, loaders
│   ├── ddl/         DdlStatements (the planned visitor classes were superseded
│   │             by IBX TIBExtract for READING DDL; this builds it for writing)
│   └── services/    Backup/Restore/Validation/Statistics/Security/... + ServiceRunner
├── documentation/   Sphinx sources → PDF user manual (rules §11)
├── icons/           SVG sources + exported PNGs (16/24/32/48)          [D9]
├── languages/       en.lang, el.lang, …                                [D8]
├── resources/       IBQConsole.rc, IBQConsole.res (icons compiled in)
├── utils/           build-icons script, language-file key checker
├── lib/  bin/  backup/          (git-ignored)
```

---

## 15. Milestones

| M | Deliverable | Done when |
|---|---|---|
| **M0** | Skeleton — **mostly done** | ✅ Builds clean on Windows (0 errors/warnings/hints), main window runs, folder layout, `LanguageHandle` + `ApplyLocale` with runtime switching via Tools → Language, `AppLog` feeding the log panel, tree drawing from the metadata model, `.res` generated from `resources/IBQConsole.rc`. ✅ **Builds and runs on Linux too** — `debug_linux` and `release_linux`, native on Ubuntu 26.04 with Lazarus 4.8/gtk2 and the same IBX 2.7.11, 0 errors/warnings/hints; the program starts, `GetAppConfigDir` and `LanguageDir` resolve correctly and the Greek interface loads; all seven offline test suites pass natively. ✅ **Verified against a Firebird 3/4/5 rig on Linux too** — `tests/TestLiveConnection.pas`, all three attached through their own `libfbclient.so` in one process, correct engine/ODS/provider/feature gating, and the same 1084 objects from the same 2.3 GB production database as on Windows. It found three defects Windows could not (building.md §5.15). ⬜ On Linux only connect-and-browse is covered; SQL execution, services, user management and the DDL dialogs are still Windows-only. ⬜ **IBX not yet verified against a live FB6 server** (§16 risk 1) — see `documentation/dev/building.md` §2.1 and §4 |
| **M1** | Connect & browse — **done** | ✅ Metadata SQL providers FB3/4/5/6 + factory; connection profiles (remote/local/embedded); per-server client library with auto-detection; registration store (XML); model classes; lazy-expanding tree; server registration dialog; **`TDatabaseContext` with the two-transaction model, dialect-3 enforcement, version detection and full status-vector error reporting**; connect/disconnect from the tree. **Verified live against Firebird 3.0.14, 4.0.7 and 5.0.4 simultaneously, each through its own fbclient**, and against a 2.6 GB production database (1084 objects). ✅ Registration import (FlameRobin `fr_databases.conf` and the IBConsole registry branch, both read-only, passwords never carried across; 21 checks in `tests/TestRegistrationImport.pas`). ✅ Database registration dialog. ✅ Server-level connect (Services API) — done in M5 |
| **M2** | Properties & DDL — **done** | ✅ `fraObjectPage` with a tab per detail kind — properties, columns, parameters, index info, indexes, constraints, triggers, source, depends-on, used-by, permissions, data and DDL — each shown only for the objects that have it; ✅ whole-database script from **Database > Maintenance > Extract Metadata**. Note: `units/ddl/` stayed empty. The planned `DdlCreateVisitor`/`DdlDropVisitor`/`DdlScriptWriter` of §14 were superseded by IBX’s `TIBExtract`, which already renders every object kind and tracks the server version; writing a second DDL renderer to sit beside it would be two things to keep correct instead of one |
| **M3** | SQL editor — **done** | ✅ SynEdit with a Firebird highlighter tracking the server version; Execute (F5) on the statement under the caret or the selection; Run script (F9) honouring `SET TERM`; Data / Messages / Plan / Statistics tabs; own transaction with Commit/Rollback and a coloured indicator; statement history persisted across sessions (Ctrl+H); file open/save. Splitter covered by 19 tests in `tests/TestSqlSplitter.pas`; execution verified against Firebird 5.0.4 |
| **M4** | Data editing — **done** | ✅ Editable grid: `TDataEditor` (`units/db/`) gives one relation an updatable dataset on **its own transaction**, driving a `TDBGrid` in `fraDataGrid` with Insert, Delete, Commit, Rollback and Refresh. A relation with no primary key opens **read-only** with `ReadOnlyReason` shown in the status strip — an UPDATE matching on every column would silently change duplicate rows too. ✅ BLOB editor: text, hex and image views, load from and save to file, read-only when the grid is; reached by double-clicking a BLOB cell. 25 checks in `tests/TestBinaryFormat.pas`. ✅ Exports: CSV (RFC 4180 quoting), TSV, JSON, HTML, Markdown and INSERT statements, the save dialog’s filter matching `TExportFormat` one for one. ✅ **Script as…**: SELECT, INSERT, UPDATE, DELETE, MERGE and EXECUTE PROCEDURE, the submenu built one item per `TScriptKind` so adding a kind needs no menu edit; generated into an editor tab unexecuted. ✅ Execute procedure/function: `frmExecuteRoutine` for procedures, PSQL functions and legacy UDFs. Export and script generators covered by 48 checks in `tests/TestExportAndScript.pas` |
| **M5** | Administration — **done** | ✅ Server-level connect (Services API), `TServiceRunner` (threaded, streamed, cancellable), backup, restore, validation (full + online), sweep, statistics, server log, shutdown/startup, the maintenance dialog that drives them, user management (SQL through a connected database, Services API as the fallback), transaction recovery (limbo transactions listed with the server’s recommendation, resolved per transaction or globally, including two-phase recovery), and connected users (MON$ATTACHMENTS read through the connected database, with disconnect; the one administration feature that needs the database open, because attachments belong to a database and the Services API has no verb for them). |
| **M6** | DDL editing — **done** | ✅ `units/ddl/DdlStatements.pas` builds every statement, with 71 checks in `tests/TestDdlStatements.pas` covering clause ORDER (Firebird rejects `NOT NULL DEFAULT` and `INDEX ... DESCENDING`), quote escaping, identifier casing and the stored-clause strippers. ✅ **New** for table (column grid + primary key), domain, index, sequence, exception and role, each with a live preview. ✅ **Alter** for domain, sequence, exception and an index’s active flag — same form, fields filled from the object’s current definition, and only the properties actually changed are written (an unchanged domain produces no statement at all, because `ALTER DOMAIN ... TYPE` re-checks every value in every table using it). ✅ **Drop** for every droppable kind, statement shown first, refusing folders, columns and system objects. ✅ **Open DDL in SQL Editor** for every kind — the alter route for tables (column-by-column `ALTER TABLE`) and for views, procedures, triggers and functions, whose bodies are programs. ✅ Four definition queries on the provider (`DomainDefinitionSQL`, `ExceptionDefinitionSQL`, `IndexStateSQL`, `SequenceValueSQL`) and their model readers, all reading through `FetchTableFresh` so a dialog never writes back a stale snapshot. ⬜ Nothing here has been run against a live server |
| **M7** | Ship — **in progress** | ✅ Preferences: `units/core/AppConfig.pas` + `frmPreferences`, written to `preferences.xml` beside `registrations.xml`. Language, editor font and size, data-grid row limit, system objects, log panel and window position — every one of them read by something. Verified end to end: values survive a restart, a corrupt file falls back to defaults and still starts. **This also fixed the language never being remembered** — `StartUpLanguage` returned a hard-coded ‘English’. ✅ `el` translation: `lang/Greek.lng` complete — 483 keys, 0 missing, 0 stale, checked by `utils/langcheck.pas` (the §14 key checker) and loaded for real by `tests/TestLanguageFile.pas`. ⬜ Icon set: `icons/` is still empty and `resources/IBQConsole.rc` carries only version information. ⬜ PDF manual: `documentation/` holds only `dev/building.md`; no Sphinx sources, and neither sphinx-build nor a LaTeX toolchain is installed here, so “builds clean” could not be demonstrated even if written. ⬜ Installers: none. No NSIS, Inno Setup, dpkg-deb or rpmbuild on this machine, so a script could be written but never built or tested |

FB6 schema support is threaded through M1–M6 rather than being a milestone: because names are `TIdentifier` and SQL comes from a provider, it is a fifth provider plus a schema level in the tree, not a rewrite.

---

## 16. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **IBX for Lazarus coverage of FB6** (schemas, newest system tables) | Could block D4 | Verify at M0 with a FB6 server before committing further. Fallback: keep the DAL interface (`units/db/`) narrow enough that raw `fbclient` calls can be dropped in for what IBX misses. This is exactly why the layer boundary in §3 rule 2 is absolute. |
| FB4 `DECFLOAT` / `INT128` / time-zone types in the grid | Wrong values shown silently | Explicit conversion unit `units/core/FbTypeUtils.pas` with unit tests; render as text when no lossless Pascal type exists. FlameRobin needed `FRDecimal`/`FRInt128` for exactly this. **This risk has already arrived once, and not in the grid**: `MON$DATABASE.MON$CREATION_DATE` is `TIMESTAMP WITH TIME ZONE` from FB4, and selecting it in the bootstrap query stopped a FB3 client connecting to a FB4/FB5 server at all (building.md §5.15). It failed loudly rather than silently, but it shows the type change reaches further than the data grid — every query written against a system table needs the same question asked of it. |
| Large schemas (thousands of objects) | Unusable tree | Lazy loading is non-negotiable; tree filter box; virtual node population |
| Porting temptation | Copying IBConsole's 132 KB `frmuMain.pas` structure would poison the codebase | The old source is a **reference for behaviour**, not a source of code. Nothing is copy-pasted; the model/visitor architecture is FlameRobin's, not IBConsole's. |
| Scope creep from FlameRobin 26.8.3's newest features (MCP, vector/AI, schema diff) | Never ships | Explicitly post-v1, listed below |

---

## 17. Out of scope for v1 (candidate v2)

Schema compare & diff · test data generator · event monitor · session/transaction monitor (MON$) · replication status · backup scheduler · XLSX export · schema visualisation / ER diagram · temporal-table helpers · JSON field editor · vector/AI support · MCP server · Docker Firebird creation · dark theme/styling engine.

Each of these exists in FlameRobin 26.8.3 and can be ported later against the same model layer — which is the point of building the model layer properly first.

---

## 18. Resolved since draft 1

| Question | Resolution | Where |
|---|---|---|
| Import existing registrations? | **Yes** — FlameRobin `fr_databases.conf` + IBConsole registry, read-only, passwords excluded | D5, §9.2 |
| SQL dialect 1 databases? | **Refuse to connect**, with a message explaining the `gfix` migration | D6, §5.7 |
| Embedded Firebird? | **Supported** as a third connection mode; Server branch and all services hidden for it | D7, §5.6 |
| Localisation? | **Language files + `ApplyLocale`**, runtime switching, no rebuild per language | D8, §11 |
| Icons? | **Our own set** in `icons/`, compiled into `.res`, no runtime file loading | D9, §12 |
| Backup aliases & server log (IBConsole-only concepts)? | **Kept** — cheap and genuinely useful | §4.1 |

### Still open

1. **IBX for Lazarus FB6 coverage** — must be verified against a live FB6 server during M0. This is the one risk that could force a change to D1/D4. See §16.
2. **Master-password UX** — if §9.1(c) is enabled, when exactly is the master password prompted: at startup, or lazily at first connect that needs it?
### Closed in draft 4

- **Several client libraries in one process — CONFIRMED WORKING.** IBX 2.7.11 gives each `TIBDatabase` its own `FirebirdLibraryPathName` and loads a separate `IFirebirdLibrary` per attachment. Verified live: one process connected to Firebird 3.0.14 (port 3050) through `FB3\fbclient.dll`, 4.0.7 (3051) through `FB4\fbclient.dll` and 5.0.4 (3052) through `FB5\fbclient.dll`, in sequence, each reporting its own version and feature set. §5.6.1 stands as written.
- **IBX FB6 coverage risk (§16)** — partially retired. IBX attaches and reads metadata correctly on FB3/4/5 through the standard `TIBSQL` path, which is all the provider layer needs; FB6 schema columns remain untested only because no FB6 server exists locally.

### Closed in draft 3

- **Teramon localisation precedent** — resolved by reading `teramon/units/languagehandle.pas`, `units/langfileio.pas` and `forms/frmmain.pas`. The system is adopted essentially unchanged; §11 documents what was built and §11.5 the single addition (`ILocalizable`). Code: `units/core/LanguageHandle.pas`, `units/core/LangFileIO.pas`, sample `lang/Greek.lng`.
