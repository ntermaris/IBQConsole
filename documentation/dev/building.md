# Building IBQConsole

Developer notes. The user manual lives in `documentation/source/` and is a
different document.

---

## 1. Prerequisites

| Requirement | Status on this machine | Notes |
|---|---|---|
| Free Pascal 3.2.2 | present — `C:\lazarus\fpc\bin\x86_64-win64\fpc.exe` | fpcupdeluxe install |
| Lazarus + LCL (prebuilt) | present — `C:\lazarus\lazarus`, LCL units under `lcl\units\x86_64-win64` | |
| **IBX for Lazarus** | **installed — IBX4Lazarus 2.7.11** via OPM, at `C:\Lazarus\config_lazarus\onlinepackagemanager\packages\IBX4Lazarus` | Project requires the **`ibnongui`** package (not `ibexpress`): we create connections in code and supply our own dialogs, so the GUI half is dead weight. |
| FBIntf | installed alongside IBX, at `…\packages\FBIntf` | Supplies `IB.pas`, `IFirebirdAPI`, `EIBInterBaseError` |
| Firebird clients | 4 found — see §5.0 | 3.0.14, 4.0.7, 5.0.4 |

---

## 2. Building

### From the IDE

Open `IBQConsole.lpi` in Lazarus and press Run. Unit paths are already set in
the project options:

```
forms;units/core;units/sql;units/model;units/db;units/ddl;units/services;lib
```

### Build modes

| Mode | Target | Checks / debug info | Optimisation | Status |
|---|---|---|---|---|
| `debug_win` *(default)* | x86_64-win64 | range, overflow, I/O, stack; DWARF3; heaptrc; trashed variables | none | ✅ builds & runs |
| `release_win` | x86_64-win64 | none; symbols stripped | `-O3`, smart-linked | ✅ builds & runs |
| `debug_linux` | x86_64-linux, gtk2 | range, overflow, I/O, stack; DWARF3; heaptrc | none | ✅ builds & runs (§2.1) |
| `release_linux` | x86_64-linux, gtk2 | none; symbols stripped | `-O3`, smart-linked | ✅ builds & runs (§2.1) |

```bat
lazbuild --build-mode=debug_win     IBQConsole.lpi
lazbuild --build-mode=release_win   IBQConsole.lpi
lazbuild --build-mode=debug_linux   IBQConsole.lpi
lazbuild --build-mode=release_linux IBQConsole.lpi
```

Each mode writes to **its own** directory — `bin/<mode>/IBQConsole[.exe]` and
`lib/<mode>/` — so a release build never overwrites a debug one and the two
never share stale `.ppu` files. Both trees are disposable and git-ignored.

Size comparison: `debug_win` 59.0 MB / `release_win` 6.4 MB;
`debug_linux` 50.0 MB / `release_linux` 6.5 MB.

### 2.1 The Linux build

Both Linux modes build, and the program runs. This is a **native** build on
Linux, not a cross-build from Windows; cross-compiling was tried first and
abandoned, because linking a gtk2 program needs the target system's
development libraries and that is the fiddly half of the job.

The machine used:

| Requirement | Version | Location |
|---|---|---|
| Ubuntu | 26.04 LTS | — |
| Lazarus | 4.8 (fpcupdeluxe) | `~/Lazarus/lazarus` |
| FPC | x86_64-linux | `~/Lazarus/fpc/bin/x86_64-linux/fpc.sh` |
| LCL widgetset | **gtk2**, prebuilt | `~/Lazarus/lazarus/lcl/units/x86_64-linux/gtk2` |
| gtk2 development libraries | 2.24.33 | system |
| **IBX4Lazarus** | **2.7.11 build 1673** — same as Windows | `~/Lazarus/config_lazarus/onlinepackagemanager/packages/IBX4Lazarus` |
| **FBIntf** | from the same OPM repository | `…/packages/FBIntf` |

IBX is not in the Ubuntu archive and was not installed here. It came from the
Online Package Manager repository, which is where the Windows copy came from
too, so both platforms build against the same source:

```sh
curl -LO https://packages.lazarus-ide.org/FBIntf.zip
curl -LO https://packages.lazarus-ide.org/IBX4Lazarus.zip
# both hashes checked against packagelist.json from the same host
unzip -q FBIntf.zip IBX4Lazarus.zip -d ~/Lazarus/config_lazarus/onlinepackagemanager/packages/
```

`lazbuild` needs the packages **registered** before it will resolve
`ibnongui` from the `.lpi`. Registering a package link is enough — the IDE
itself does not have to be rebuilt, because `ibnongui` is a runtime package
and nothing in the project needs its design-time half:

```sh
P=~/Lazarus/config_lazarus/onlinepackagemanager/packages
lazbuild --add-package-link $P/FBIntf/fbintf.lpk
lazbuild --add-package-link $P/IBX4Lazarus/ibnongui.lpk
lazbuild --widgetset=gtk2 $P/FBIntf/fbintf.lpk
lazbuild --widgetset=gtk2 $P/IBX4Lazarus/ibnongui.lpk
```

Then the project builds with the same command as on Windows:

```sh
lazbuild --build-mode=debug_linux   --widgetset=gtk2 IBQConsole.lpi
lazbuild --build-mode=release_linux --widgetset=gtk2 IBQConsole.lpi
```

Both modes: **0 errors, 0 warnings, 0 hints** — the only hints emitted are
11030 and 11031, the compiler announcing that it read `fpc.cfg`.

### 2.2 The one thing the Linux compiler found

The Windows build was clean, so the two hints below had never been seen:

```
units/core/RegistrationImporter.pas(196,3) Hint: (5028) Local const "IBConsoleServersKey" is not used
units/core/RegistrationImporter.pas(198,3) Hint: (5028) Local const "IBConsoleDatabasesKey" is not used
```

Both name registry keys, both are read only by the IBConsole importer, and
that whole reader is inside `{$IFDEF WINDOWS}` — there is no registry to read
anywhere else. The constants were outside it. They are now declared in their
own `{$IFDEF WINDOWS} const` block, which is where anything naming a registry
key belongs.

Worth recording because it is the argument for building on both platforms
rather than one: a second target compiles the *other* half of every `{$IFDEF}`
and reports what the first one could not see.

### 2.3 What was verified on Linux

- Both build modes clean, from a wiped `bin/` and `lib/`.
- The program starts, draws its main window, menus, object tree, log panel
  and status bar, and stays up.
- `GetAppConfigDir` resolves correctly: the log reads *"Registrations loaded
  from `/home/alex/.config/IBQConsole/registrations.xml`"* — the same code that
  writes to `%APPDATA%` on Windows, with no path built by hand.
- `LanguageDir` finds the project's `lang/` by walking up from `bin/<mode>/`,
  so a development build is translated without a deployment step. Started
  with `Language=Greek` in `preferences.xml`, the whole interface came up in
  Greek and the saved window geometry was applied.
- **All seven offline test suites compiled and passed natively** — the same
  counts as on Windows:

| Suite | Result |
|---|---|
| `TestSqlSplitter` | passed 19, failed 0 |
| `TestBinaryFormat` | passed 25, failed 0 |
| `TestDdlStatements` | all DDL checks passed (71) |
| `TestExportAndScript` | passed 48, failed 0 |
| `TestSqlAliases` | no reserved-word aliases found, FB3/4/5/6 |
| `TestRegistrationImport` | all registration import checks passed (21) |
| `TestLanguageFile` | 483 keys, all checks passed |

Two of them need unit paths the others do not — `laz2_DOM` from LazUtils and
`Interfaces` from the LCL:

```sh
LZ=~/Lazarus/lazarus
fpc -Mobjfpc -Sh -O3 -FUout -FEout \
    -Fuunits/core -Fuunits/db -Fuunits/sql -Fuunits/model -Fuunits/ddl -Fuunits/services \
    -Fu$LZ/components/lazutils/lib/x86_64-linux \
    -Fu$LZ/lcl/units/x86_64-linux -Fu$LZ/lcl/units/x86_64-linux/gtk2 \
    tests/TestLanguageFile.pas
```

`TestLanguageFile` reads `lang/` **relative to its own executable**, so it must
be built somewhere that rule can reach the project's `lang/` — `-FEout` in the
project root does; a scratch directory elsewhere does not, and the failure it
produces (*"Greek is offered"* failing, nine checks down) looks like a
translation defect rather than a misplaced binary.

### 2.4 What could NOT be tested on Linux

**The server side was closed on the same day** — a Firebird 3/4/5 rig now
exists on this machine and §5.15 records what it found. What remains untested
on Linux is the layer above connect and browse: the SQL editor, the services
layer, user management and the DDL dialogs have not been driven against a
Linux server, and no GUI interaction has been automated at all, because
nothing on this box can drive a click.

**The Windows build was not re-run after the `{$IFDEF}` fix in §2.2.** There is
no win64 cross-compiler in this Linux install (no `ppcrossx64`, no win64 RTL),
so it could only be checked by reading: the two constants moved into a block
that Windows still compiles, and nothing outside `{$IFDEF WINDOWS}` refers to
them. Re-run `lazbuild --build-mode=debug_win` on Windows to confirm it.

### Verifying a clean build

`PASCAL-LAZARUS-RULES.md` §10 requires zero warnings and zero hints. To check:

```powershell
lazbuild --build-mode=debug_win IBQConsole.lpi 2>&1 | Select-String "Hint: \(\d"
```

The only two hints that should appear are `11030` and `11031` — the compiler
announcing that it read `fpc.cfg`. Anything else is a defect to fix, not to
ignore.

---

## 3. The resource file

`IBQConsole.lpr` links `{$R *.res}`, which expects `IBQConsole.res` in the
project root. It is generated from `resources/IBQConsole.rc`:

```bat
utils\build-res.bat        rem Windows
```
```sh
utils/build-res.sh         # Linux
```

Run it after adding an icon or changing the version information.

**Why `fpcres` and not `windres`:** `windres` shells out to the gcc
preprocessor (`cpp`), which is absent from a plain fpcupdeluxe install and
fails with `gcc: installation problem, cannot exec 'cpp'`. `fpcres` compiles
`.rc` files on its own and is shipped with FPC, so it works everywhere the
compiler works.

`IBQConsole.res` is a build artifact but **is** committed, so a fresh checkout
builds without running the script first.

---

## 4. IBX for Lazarus

Installed: **IBX4Lazarus 2.7.11** (MWA Software), via Online Package Manager.

The project requires **`ibnongui`**, not `ibexpress`. `ibexpress` adds IBX's own
login and dialog forms, which we do not use — connections are created in code
and every dialog is ours. Requiring the non-GUI package keeps the dependency
surface to what is actually used.

Units that matter, all under `runtime/nongui/`:

| Unit | What we use it for |
|---|---|
| `IBDatabase` | `TIBDatabase`, `TIBTransaction` — the attachment and the two standing transactions |
| `IBSQL` | `TIBSQL` — every metadata query |
| `IBCustomDataSet` | `TIBDataSet` — the editable data grid, from M4 |
| `IBExtract` | whole-database DDL extraction, from M2 |
| `IBXServices` | the modern Services API — backup, restore, validate, from M5 |

`IBServices` (the *legacy* Services API) lives under `runtime/legacy/` in a
separate `ibLegacyServices` package. Prefer `IBXServices`; the legacy unit is
only for servers the modern one cannot reach.

Errors come from FBIntf's `IB.pas`: `EIBError` carries `SQLCode`, and
`EIBInterBaseError` adds `IBErrorCode` and an `IStatus`. `TDatabaseContext`
maps both onto `EIbqDatabaseError`, keeping **every** line of the status vector
— see §11 of `PASCAL-LAZARUS-RULES.md` and `TDatabaseContext.TranslateError`.

### Firebird 6 — still untested

No Firebird 6 server exists on this machine, so the FB6 provider and IBX's
handling of `RDB$SCHEMA_NAME` remain unverified. This is now the only part of
decisions D1/D4 not demonstrated. The fallback is unchanged: `SPECIFICATION.md`
§3 rule 2 confines IBX to `units/db/` and `units/services/`, so raw `fbclient`
calls can be substituted there without touching the model or the UI.

---

## 5. Suppressed compiler messages

The project passes `-vm5023,5024`. Both suppressions are deliberate and
narrow:

| Code | Message | Why it is suppressed |
|---|---|---|
| 5023 | *Unit "X" not used in IBQConsole* | `IBQConsole.lpr` lists every project unit so that `lazbuild` compiles all of them and a broken unit is caught immediately, even before anything references it. The hint fires on units that are compiled but not yet called — which is the intended state during early milestones, not a defect. |
| 5024 | *Parameter "Sender" not used* | Every LCL event handler receives `Sender` whether it needs it or not. The signature is fixed by the framework. |

Nothing else is suppressed. If a new suppression is ever proposed, it belongs
in this table with its reason, or it does not go in.

---

## 5.0 The local test rig — Firebird 3, 4 and 5 side by side

`C:\firebird\` holds three self-contained servers, each with its own
`firebird.conf`, security database and **its own `fbclient.dll`**:

| Path | Version | Port | ODS | Test database |
|---|---|---|---|---|
| `C:\firebird\FB3\` | 3.0.14 | 3050 | 12.0 | `C:\firebird\db\test3.fdb` |
| `C:\firebird\FB4\` | 4.0.7 | 3051 | 13.0 | `C:\firebird\db\test4.fdb` |
| `C:\firebird\FB5\` | 5.0.4 | 3052 | 13.1 | `C:\firebird\db\test5.fdb` |

Credentials `SYSDBA` / `masterkey` (throwaway rig — never reachable from a
network). Start with `C:\firebird\start-all.bat`, stop with `stop-all.bat`.

A larger real database is available at
`D:\work\AMetro\DB\line4a20260121.FDB` (2.6 GB, 154 tables, FB 3.0) served by
the separately installed `Firebird_3_0` instance on the default port.

### Why the client library is part of a registration

With three Firebird versions installed, **whichever `fbclient` appears first on
the system search path wins** — which on a developer's machine is an accident,
not a decision. A registration therefore names the client library to use.

`units/db/FbClientLocator.pas` finds them. Verified output on this machine:

```
detected 4 client library file(s):
  [5.0] Firebird 5.0.4.1812    -  C:\firebird\FB5\fbclient.dll
  [4.0] Firebird 4.0.7.3271    -  C:\firebird\FB4\fbclient.dll
  [3.0] Firebird 3.0.14.33856  -  C:\firebird\FB3\fbclient.dll
  [3.0] Firebird 3.0.14.33856  -  C:\Program Files\Firebird\Firebird_3_0\fbclient.dll
```

Search order puts the application's own directory first, so a portable install
shipping its own Firebird always wins. Versions are read from the file's
version resource (`fileinfo` + `winpeimagereader`), falling back to parsing the
folder name (`FB5`, `Firebird_3_0`) when a file carries no version — which is
the normal case for a Linux shared object.

**A newer client reaches an older server.** The 5.0 client talks to 3.0, 4.0
and 5.0. The reverse does not hold. `BestClientFor` prefers an exact major
match and falls back to the newest available.

### ✅ Several client libraries in one process — confirmed

IBX 2.7.11 gives every `TIBDatabase` its own `FirebirdLibraryPathName` and
loads a **separate `IFirebirdLibrary` per attachment**
(`IBDatabase.pas:1363` — `fblib := IB.LoadFBLibrary(...)`).

Verified live — one process, three servers, three clients:

```
port 3050  client C:\firebird\FB3\fbclient.dll  -> Firebird 3.0.14 (ODS 12.0)
           18 folders, no Publications folder
port 3051  client C:\firebird\FB4\fbclient.dll  -> Firebird 4.0.7  (ODS 13.0)
           19 folders, Publications appears
port 3052  client C:\firebird\FB5\fbclient.dll  -> Firebird 5.0.4  (ODS 13.1)
           19 folders, partial-index gate on
```

Feature gating behaved exactly as designed: `dbfPublications` false on FB3 and
true from FB4, `dbfPartialIndexes` true only on FB5 — and the Publications
folder is **absent** on FB3, not present-but-empty.

---

## 5.1 Verifying the metadata SQL against a real server

`utils/dumpsql.pas` prints the queries a given provider version produces, as an
isql script. The SQL comes from the **real provider classes**, so a query that
passes here is the query the program will actually send.

```powershell
fpc -Mobjfpc -Sh -FUout -FEout `
    -Fuunits\core -Fuunits\db -Fuunits\sql utils\dumpsql.pas
.\out\dumpsql.exe 3 0 > fb3.sql          # or 4 0 / 5 0 / 6 0
```

Write the file **without a BOM** — isql rejects one with
`Token unknown - line 1, column 1`. Then:

```powershell
& "C:\Program Files\Firebird\Firebird_3_0\isql.exe" `
    -user SYSDBA -password <pw> -i fb3.sql "localhost:<path to .fdb>"
```

### Results on Firebird 3.0.14 (2026-08-20)

Test database: `D:\work\AMetro\DB\line4a20260121.FDB`, 2.6 GB, 154 tables.

- **All 26 queries executed with no error.**
- Column contract confirmed: `SCHEMA_NAME` comes back `<null>`, `OBJ_NAME` and
  `OBJ_ID` populated, so a loader written once works on every version.
- `Schemas` and `Publications` correctly reported as unavailable on FB3.

Three filters cross-checked against independent counts, because each could
silently drop rows rather than fail loudly:

| Filter | Check | Result |
|---|---|---|
| Tables | my filter vs *all* non-system non-view relations | **154 = 154** — no rows lost to the `RDB$RELATION_TYPE` test |
| Triggers | DML + Database + DDL vs total | **190 = 190 + 0 + 0** — the three-way split is exhaustive and non-overlapping |
| Domains | my filter vs non-system `RDB$FIELDS` | 0 of 2972 — **correct**: every entry is an `RDB$n` column descriptor, and this database has no user domains. Firebird forbids user objects named `RDB$…`, so the name test cannot over-filter. |

---

## 5.2 Live connection results

`TDatabaseContext` driven against the rig and the production database.

### One process, three servers, three clients

```
port 3050  FB3\fbclient.dll  ->  Firebird 3.0.14 (ODS 12.0)   18 folders
port 3051  FB4\fbclient.dll  ->  Firebird 4.0.7  (ODS 13.0)   19 folders  (+Publications)
port 3052  FB5\fbclient.dll  ->  Firebird 5.0.4  (ODS 13.1)   19 folders  (+partial-index gate)
```

Every attach reported its own version, built its own SQL provider, listed its
folders and disconnected cleanly.

### Against the 2.6 GB production database

`D:\work\AMetro\DB\line4a20260121.FDB`, Firebird 3.0.14:

| Step | Time | Result |
|---|---|---|
| connect (attach + dialect check + version) | **102 ms** | Firebird 3.0.14 (ODS 12.0) |
| build folder nodes | **0 ms** | 18 folders, **0 objects read** |
| load *every* folder (never done by the tree) | **23 ms** | 1084 objects |

The middle row is the lazy-loading contract holding: expanding the database
node costs nothing because no object list is fetched until a folder is opened.
Object counts match the independent isql cross-checks in §5.1 exactly — 154
tables, 190 triggers.

### Dialect 1 refusal (D6) — verified

Tested against a real dialect 1 database, created for the purpose and then
deleted. To recreate it:

```sql
-- isql -q -i mkd1.sql
SET SQL DIALECT 1;
CREATE DATABASE 'localhost/3050:C:\firebird\db\d1test.fdb'
  USER 'SYSDBA' PASSWORD 'masterkey';
```

## 5.3 M2 — object detail queries verified

Every detail query was run against the 2.6 GB production database before any UI
was written on top of it. Two defects surfaced that way, and a third from
reading the results rather than watching for errors:

| Defect | Symptom | Fix |
|---|---|---|
| `AS POSITION` in the trigger query | `Token unknown - POSITION` | POSITION is reserved; aliased `TRIGGER_POSITION` |
| `FetchTable` read `Query.Current` | `End of file` on any query returning **no rows** | Column names now come from `Query.MetaData`, valid with zero rows |
| Privileges matched by name only | Character set `ASCII` reported the identically-named collation's grant too | `RDB$USER_PRIVILEGES` mixes all object kinds; `PrivilegesSQL` now filters on `RDB$OBJECT_TYPE` |

Object type codes, confirmed on 3.0.14: 0 relation, 2 trigger, 5 procedure,
7 exception, 9 domain, 10 index, 11 character set, 13 role, 14 generator,
15 external function, 17 collation, 18 package.

### Tabs produced, one object per folder

```
Table            AGGREGATION_SETTINGS   Properties Columns(7) Indexes(1) Constraints(2)
                                        Triggers(1) UsedBy(1) Permissions(19) DDL
View             INCLINOMETERREADINGS…  Properties Columns(10) Source DependsOn(9)
                                        UsedBy(16) Permissions(5) DDL
Stored Procedure ALARMID                Properties Parameters(3) Source DependsOn(4)
                                        Permissions(5) DDL
Trigger          AGGREGATION_SETTINGS_BI Properties Source DependsOn(2) DDL
Generator        AGS_CODES_ID_GEN       Properties UsedBy(1) Permissions(1) DDL
Character Set    ASCII                  Properties Permissions(1)
```

A detail that returns no rows produces **no tab** — the absence is the answer,
at a glance rather than several clicks.

---

## 5.4 M3 — SQL editor

### Statement splitter

`units/sql/SqlStatementSplitter.pas` is a lexer over the script, not a parser
of it: it must survive statements it does not understand, including from a
future Firebird. `tests/TestSqlSplitter.pas` covers 19 cases, all passing at
`-O3` as well as unoptimised:

```
lazbuild is not needed - compile the test directly:
  fpc -Mobjfpc -Sh -O3 -FUout -FEout -Fuunits\sql tests\TestSqlSplitter.pas
  out\TestSqlSplitter.exe
```

Cases that matter, and why:

| Case | Why it would break a naive split on ';' |
|---|---|
| `'a;b;c'` | semicolon inside a string literal |
| `'it''s; here'` | doubled quote is an escape, not a close |
| `"we;ird"` | semicolon inside a quoted identifier |
| `-- drop this; and that` | semicolon in a line comment |
| `/* a; b; c */` | semicolon in a block comment |
| `q'{a;b}'`, `q'!a;b!'` | Firebird alternative quoting, any delimiter |
| `SET TERM ^ ;` … `END^` | PSQL bodies **contain** semicolons |
| `SELECT qty FROM T;` | an identifier starting with q is not a q-string |

Without SET TERM support a tool cannot run the scripts its own DDL extractor
produces, which is why this is not optional.

### Execution, verified against Firebird 5.0.4

```
SELECT literal        SELECT: 1 row(s) [0 ms]   plan: Select Expression -> Table "RDB$DATABASE" Full Scan
syntax error          SQLCODE -104, GDSCODE 335544569, "Token unknown - line 1, column 1 - SELCT"
missing table         SQLCODE -204, "Table unknown - NO_SUCH_TABLE - At line 1, column 15"
INSERT                INSERT: 1 row(s) affected
verify inside tx      count = 1        <- the editor's own transaction sees its own work
rollback              count = 0        <- and nothing else does
script with SET TERM  [1] DDL  [2] SELECT (1 row from the new procedure)  [3] DDL
```

The middle rows are the transaction contract holding: an editor's uncommitted
INSERT is visible to itself and vanishes on rollback, while the object tree
reads on the context's separate read-only transaction and is unaffected.

### Two deprecated APIs avoided

SynEdit marks **both** `SelStart` and `RowColToCharIndex` deprecated and "very
slow" — they exist only for SynMemo compatibility and walk the whole buffer.
`TfraSqlEditor.CaretCharOffset` sums the lines above the caret instead, which
is what the splitter needs and no more.

---

## 5.5 M3 gaps closed — history, statistics, file open/save

### Statement history

`units/core/StatementHistory.pas`, persisted as `history.xml` beside the
registrations. Verified round trip:

```
4 adds, one an exact repeat of the previous -> 3 entries   (repeats suppressed)
search "hello" -> 2 hits;  search "" -> 3 hits (all)
saved, cleared, reloaded  -> 3 entries, timestamps/database/elapsed/outcome intact
   UPDATE HELLO SET TXT = 'x'      7 ms  ok=True
   SELCT bad syntax                1 ms  ok=False      <- failures ARE kept
   SELECT ID, TXT FROM HELLO       3 ms  ok=True
```

Two deliberate behaviours: pressing F5 four times without editing leaves **one**
entry, not four; and a statement that FAILED is still remembered, because the
one a user wants back is often the one that did not work.

Saved on shutdown rather than per statement — writing a file on every F5 is a
measurable cost on a fast query, and losing the last few statements to a crash
is the smaller harm.

### Statistics tab

`TIBSQL.Statement` exposes `IStatement.GetRowsAffected(var Select, Insert,
Update, Delete)`, which is the per-operation count the engine actually
performed. Verified:

```
Statement    : SELECT            Statement    : INSERT
Rows fetched : 1                 Rows affected: 1
Operations performed             Operations performed
  select : 1                       select : 0
  insert : 0                       insert : 1
```

Worth showing because the counts reveal work the statement text does not: an
UPDATE that also reports an insert has fired a trigger, which is usually the
answer to "why is this slow".

### File open and save

Open prompts before discarding unsaved editor text; Save remembers the file
name for the next save. `.sql` is the default extension.

---

## 5.6 A crash found by checking exit codes

Every earlier smoke test **killed** the program rather than closing it, and the
console tests printed their output before anything went wrong. Checking exit
codes rather than output found this:

```
FB3 then FB5   exit 0
FB5 then FB5   exit 0
FB5 then FB3   exit 217   EAccessViolation during finalisation
```

Connecting to a **newer** Firebird and then to an **older** one crashes the
process at exit — after all work has completed correctly and after the last
line of output. The database layer loads a client library per connection and
releases it when the connection closes, so the older client is loaded into a
process that has already loaded and unloaded a newer one; something in that
sequence leaves a pointer into an unmapped image, and it is touched at
shutdown.

This is a defect below us, in the client libraries or FBIntf. The fix is
`FbClientLocator.PinClientLibrary`: take one extra reference to each client
library the first time it is used, and never release it, so every image stays
mapped for the life of the process. Verified — every previously crashing case
now exits 0, and the GUI closed with `WM_CLOSE` (not killed) also exits 0.

Cost: a few megabytes of address space per distinct client **actually used**.
Libraries are pinned on first use, not all at startup.

Worth stating plainly: this would have shipped. It only appears when a user
connects to a newer server and then an older one in the same session, which is
exactly what a developer with a version rig does, and the program would have
appeared to work perfectly right up to the moment they closed it.

---

## 5.7 A guard for reserved-word aliases

`AS POSITION` and `AS VALUE` both shipped and both failed at run time with
`Token unknown`. The keyword list needed to catch them was already in the
program — it just was not being consulted.

`tests/TestSqlAliases.pas` now walks every query from all four providers and
checks each `AS <word>` against `FirebirdKeywords.IsReservedWord`:

```
fpc -Mobjfpc -Sh -FUout -FEout -Fuunits\db -Fuunits\core -Fuunits\sql     tests\TestSqlAliases.pas
out\TestSqlAliases.exe        ->  no reserved-word aliases found
```

It skips `CAST(x AS VARCHAR(12))`, where the word after `AS` is a type name:
a cast's type is followed by `(` or `)`, an alias by a comma or whitespace.
Without that one distinction every CAST in the program reports a false
positive — the first version of this test produced 300 of them.

---

## 5.8 M4 — exports and "Script as..."

### Exports

`units/core/DataExport.pas` turns a `TDataTable` into CSV, TSV, JSON, HTML,
Markdown or INSERT statements. Pure text transformation with no UI and no
database, so the same code serves the SQL editor's grid and a property page's
Data tab, and every escaping rule is testable without a server.

Escaping is the whole job, and each format has exactly one way to go wrong -
a value containing the character that separates values:

| Format | The trap |
|---|---|
| CSV | a comma, quote or newline in a field (RFC 4180 quoting) |
| TSV | a tab or newline in a field |
| JSON | quote, backslash, and control characters below space |
| HTML | `&` first, then `<` `>` and quotes |
| Markdown | a pipe, which would end the cell |
| INSERT | a single quote, which would end the literal |

Getting these wrong does not raise an error. It produces a file that opens and
is quietly wrong, which is worse - hence a test per rule with the awkward
character actually in the data.

Everything is written as a string literal in INSERT output, numbers included:
guessing which columns are numeric from text alone gets a VARCHAR holding
`'007'` wrong, and it would silently become `7`.

### "Script as..."

`units/sql/ScriptGenerator.pas` builds SELECT / INSERT / UPDATE / DELETE /
MERGE / EXECUTE. Borrowed from FlameRobin, where it is among the most-used
commands, for a plain reason: nobody wants to type forty column names, and
getting one wrong in an UPDATE changes the wrong rows.

The safety rule is in `KeyPredicate`: an UPDATE or DELETE always gets a WHERE
clause built from the primary key, and when there is no primary key the clause
is emitted as `WHERE /* no primary key - complete this condition */`. That
does not parse, so running it unedited gives a syntax error. **An UPDATE with
no WHERE that looks finished is a loaded gun**, and omitting the clause
entirely was never an option.

MERGE never puts the key columns in its UPDATE SET list, and refuses outright
when there is no key to match on.

Generated statements open in a SQL **editor**, not on the clipboard: they are
meant to be edited before running.

### Verified against the production schema

```
SELECT   FIRST 100, all 7 columns, ran -> SELECT: 0 row(s) [6 ms]
INSERT   named placeholders :ID, :FUNC_TYPE, ...
UPDATE   assignments plus WHERE ID = :ID           <- real primary key
DELETE   DELETE FROM AGGREGATION_SETTINGS WHERE ID = :ID
MERGE    ON tgt.ID = src.ID, key excluded from UPDATE SET
EXECUTE  EXECUTE PROCEDURE ALARMID (:PNTID3, :DATEMEAS1)   <- real IN params
```

All six export formats verified on real rows, including `MON$` names that
contain a `$`.

`tests/TestExportAndScript.pas` — 34 cases, all passing at `-O3`.

---

## 5.9 M4 — the editable data grid

`units/db/DataEditor.pas` wraps a `TIBDataSet` with its own read-write
transaction; `forms/fraDataGrid.pas` binds a `TDBGrid` to it. The Data tab of a
table property page is now that grid.

### Three things that had to be got right

**The update SQL is generated here, not by IBX.** IBX derives DML from a SELECT
only in its design-time editor, so the four statements are built at run time
using IBX's convention that a parameter named `OLD_<column>` carries the value
the row held before the edit (`IBCustomDataSet.pas:4351`). Matching on the new
value would fail to find the row whenever the key itself was edited.

**Computed columns are excluded from INSERT and UPDATE.** Firebird rejects
them, so including one would make every post fail rather than merely ignoring
the column. `RefreshSQL` then re-reads the row after a post, which is how the
server-computed value appears in the grid.

**No primary key means read-only, and it says so.** Without a key there is no
way to name the row being changed, and an UPDATE matching on every column would
quietly change duplicates too. The grid still opens and still shows the rows;
the status strip reads *"no primary key - rows cannot be identified, read
only"*. Discovering that by typing and having the post fail would be worse.

Views are read-only for now with a stated reason. Firebird can update a simple
view, but deciding which from metadata alone means parsing the view body, and
being wrong means either refusing something that works or generating DML that
fails at post time.

### Verified round trip

Against a throwaway table on the FB5 rig, created and dropped by the test:

```
CREATE TABLE IBQ_EDIT_TEST (ID INTEGER NOT NULL PRIMARY KEY,
                            TXT VARCHAR(40), DOUBLED COMPUTED BY (ID * 2))

CanEdit = True, 2 rows, 3 fields
UPDATE   -> TXT = 'ONE EDITED'
INSERT   -> rows 2 -> 3
           computed column DOUBLED for ID=3 -> 6
DELETE   -> rows 3 -> 2
ROLLBACK -> TXT still 'ONE EDITED'   (the discarded edit never landed)

table with no primary key:
CanEdit = False
reason  = "no primary key - rows cannot be identified, read only"
still opened and readable
```

The computed column is the load-bearing line: `DOUBLED = 6` proves both that
computed columns were kept out of the INSERT and that `RefreshSQL` brought the
server's value back.

### Layering held

`TDataEditor.Dataset` is declared as **`TDataSet`**, not `TIBDataSet`, so
`fraDataGrid` binds a `TDataSource` without ever naming an IBX class. That
needed a getter rather than a plain field read - a property cannot widen its
field's type - which is a small price for keeping `SPECIFICATION.md` §3 rule 2
intact where a data-aware control meets the database layer.

---

## 5.10 M4 — the BLOB editor

`units/core/BinaryFormat.pas` answers the two questions a BLOB raises before
anything can be shown: what is this, and what does it look like? Both are
answered without a database or a window, so both are tested -
`tests/TestBinaryFormat.pas`, 25 cases.

**Detection is by content, not by declared sub-type.** A Firebird
`BLOB SUB_TYPE 0` routinely holds a PNG and a `SUB_TYPE 1` routinely holds
something that is not text at all. What the column claims is a hint; the first
bytes are evidence. PNG, JPEG, GIF, BMP, ICO, PDF and ZIP are recognised by
signature; anything with a byte below space that is not tab, CR or LF is binary;
a NUL settles it.

`forms/frmBlobEditor` shows the value as Text, Hex or Image and opens on
whichever fits. Three deliberate limits:

- **Hex is read-only.** A hex editor that writes is a different program, and an
  accidental keystroke in one is unrecoverable.
- **Text editing is disabled for binary content**, because retyping a JPEG
  through a memo corrupts it silently.
- **The hex view is capped at 64 KB** and says so in the dump. A truncated view
  that passes for a complete one is how wrong conclusions get drawn.

### Verified round trip

A real 67-byte PNG written into a `SUB_TYPE 0` column and read back:

```
NOTE detected as: text, 17 bytes          <- SUB_TYPE 1 holding real text
wrote a 67 byte PNG into PIC
read back 67 bytes, detected as PNG image
byte-for-byte identical: True

00000000  89 50 4E 47 0D 0A 1A 0A  00 00 00 0D 49 48 44 52  |.PNG........IHDR|
00000010  00 00 00 01 00 00 00 01  08 06 00 00 00 1F 15 C4  |................|
... 32 of 67 bytes shown
```

---

## 5.11 Every form is now designer-editable

`PASCAL-LAZARUS-RULES.md` §7.1 now requires controls to live in the `.lfm`, not
be created in code. Three frames were built entirely at run time and have been
converted:

| Form | Was | Now |
|---|---|---|
| `fraDataGrid` | toolbar, grid, data source, dialog all in `BuildControls` | 11 design-time components |
| `frmSqlEditor` | 8 buttons, SynEdit, highlighter, 4 result tabs, 3 dialogs in code | 25 design-time components |
| `fraObjectPage` | page control and every tab created per object kind | 27 design-time components, 13 tabs toggled with `TabVisible` |

Totals across all eight forms: **174 design-time components, zero controls
created in code.**

The object page is the interesting one. Its tabs genuinely differ per object
kind, which was the original argument for building them at run time. Putting all
thirteen in the designer and toggling `TabVisible` keeps the behaviour that
matters — **a detail with no rows still shows no tab** — while making the layout
editable. A hidden tab lays out correctly and can be adjusted visually; a tab
that only exists at run time cannot.

Two kinds of run-time creation remain, and both are the documented exception in
§7.2 — the *number* is not known until run time and depends on data:

- one menu item per `.lng` file found, and per `TScriptKind` value
- one workspace tab per object the user opens, each holding a frame

The nested data grid inside `fraObjectPage` is also created in code, because the
designer does not place a frame inside a frame. The **panel that holds it is in
the designer**, so the layout is still editable; only the nested frame is
instantiated.

## 5.12 M4 — the Execute dialog

`Object > Execute...` runs the selected procedure with values the user types.
It is the other half of `Script as... EXECUTE`: that one writes the call for
someone to fill in and run in the editor, this one fills it in and runs it.

### Selectable or executable is read, not guessed

A selectable procedure must be called `SELECT * FROM P(...)`, an executable one
`EXECUTE PROCEDURE P(...)`, and calling either the wrong way simply fails. The
tempting shortcut — "it has output parameters, so it is selectable" — is wrong:
an executable procedure may have output parameters too, and the test procedure
below deliberately does.

The answer is in `RDB$PROCEDURES.RDB$PROCEDURE_TYPE` (1 = selectable,
2 = executable), read by `MetadataSqlProvider.RoutineTypeSQL` and surfaced as
`TMetaDatabase.IsSelectableRoutine`.

### Values are quoted by declared type

Every entered value goes through `ScriptGenerator.SqlLiteralForType`, which
decides quoting from the parameter's **declared type**, never from what the
value looks like. A `VARCHAR(10)` given `007` must arrive as `'007'`; the same
text in an `INTEGER` must arrive as `7`. Guessing from appearance loses the
leading zeros of every product code and account number in the database.

### An IBX behaviour that silently returned nothing

`EXECUTE PROCEDURE` opens **no cursor**. `TIBSQL.ExecQuery` takes the else
branch at `IBSQL.pas:756` and sets `FResults` from `FStatement.Execute`, leaving
`FResultSet` nil — so `TIBSQL.EOF` (`IBSQL.pas:795`) is True immediately and a
normal fetch loop reads zero rows. The output parameters are already sitting in
`Fields`.

`TSqlSession.Execute` now reads that single row directly for
`SQLExecProcedure`. Before the fix the dialog ran procedures correctly and
showed no output at all — and so did the SQL editor, for anyone who typed an
`EXECUTE PROCEDURE` by hand.

### Verified against Firebird 5.0.4

Two procedures created on the rig, one executable **with** an output parameter
and one selectable; 11 checks, all passing, rig dropped clean afterwards:

```
kind detection    executable procedure is not selectable / selectable is
call building     EXECUTE PROCEDURE IBQ_EXEC_P (7, '007')   <- varchar keeps its zeros
                  SELECT * FROM IBQ_SEL_P (3)
execution         selectable returned 3 rows, third row is 3
                  executable ran, output parameter came back = '007/7'
                  its write is visible inside the transaction
                  rollback discarded it
failure path      SQLCODE -413 conversion error from string "x" - reported, no crash
```

The dialog holds the routine's work in **its own transaction** until the user
commits or rolls back, and warns on close if something is left uncommitted. A
procedure that writes has to be undoable from the place that ran it.

---

## 5.13 M5 — the services layer

Everything in `units/services/` talks to a **server**, not a database. That is
the whole reason the folder exists: `TIBXServicesConnection` attaches to a
Services Manager, and a restore, a shutdown or a server log cannot be asked of
a database attachment at all.

### The server-level connect, outstanding since M1

`units/services/ServiceConnection.pas` — `TServiceConnection`. One per
registered server; attaches with the **server's** client library (the same
per-server rule as everywhere else), reports version, install locations,
security database and how many databases are open.

Verified attaching to Firebird **3.0.14, 4.0.7 and 5.0.4 in one process**, each
through its own `fbclient`, detaching cleanly, exit code 0:

```
port 3052  client C:\firebird\FB5\fbclient.dll   WI-V5.0.4.1812 Firebird 5.0   parsed 5.0.4
port 3050  client C:\firebird\FB3\fbclient.dll   WI-V3.0.14.33856 Firebird 3.0  parsed 3.0.14
port 3051  client C:\firebird\FB4\fbclient.dll   WI-V4.0.7.3271 Firebird 4.0   parsed 4.0.7
wrong password -> SQLCODE -902, GDSCODE 335544472, full status vector, IsConnected FALSE
```

`Protocol` is **TCP even for localhost**. `Local` would attach through the
machine's default Firebird installation — which, on a machine running three of
them, is the wrong server two times out of three.

The client library is pinned here exactly as `TDatabaseContext` pins it (§5.6).
A service attachment loads a client the same way a database attachment does, so
it can trigger the same unload-order crash.

### One runner, one thread, one attachment per task

`units/services/ServiceRunner.pas` — `TServiceTask` (what to run) and
`TServiceRunner` (how). A runner opens **its own** service attachment for the
duration of one task, because cancelling a Firebird service means *detaching
from it* — there is no stop verb — and a shared attachment would take the
user's other windows down with it.

Cancellation happens inside the line callback: IBX calls `OnGetNextLine` from
its own read loop, so raising `EIbqCancelled` there is the only way out of a
service that is still producing output.

No IBX type crosses the runner's interface, so a form can own one.

### The tasks

| Unit | Class | IBX service used |
|---|---|---|
| `BackupService.pas` | `TBackupService` | `TIBXServerSideBackupService` |
| `RestoreService.pas` | `TRestoreService` | `TIBXServerSideRestoreService` |
| `ValidationService.pas` | `TValidationService` | `TIBXValidationService` / `TIBXOnlineValidationService` |
| `SweepService.pas` | `TSweepService` | `TIBXValidationService` with `SweepDB` |
| `StatisticsService.pas` | `TStatisticsService` | `TIBXStatisticalService` |
| `ServerLogService.pas` | `TServerLogService` | `TIBXLogService` |
| `ShutdownService.pas` | `TShutdownService`, `TStartupService` | `TIBXConfigService` |

Every option set is **our own enum**, mapped to IBX's in `Configure`. That is
what keeps `IBXServices` out of the dialog that draws the checkboxes.

Shutdown and startup are single calls, not streams, which is why
`TServiceTask.CreateService` returns the wider `TIBXCustomService` and
`TServiceTask.Run` is overridable.

### Verified against Firebird 5.0.4, end to end

Backup → restore → validate → sweep → statistics → server log, all through the
threaded runner, 14 checks, rig dropped clean afterwards:

```
backup            43 lines, 116 ms   gbak:readied database ... for backup
restore           32 lines, 137 ms   gbak:opened file ... transportable backup
full validation    1 line,   50 ms
sweep              1 line,   49 ms
statistics        31 lines,  26 ms   Database "C:\FIREBIRD\DB\IBQ_M5_RESTORED.FDB"
server log        60 lines,  27 ms
refusals          empty database name refused before the thread starts
                  missing database -> GDSCODE 335544344, I/O error, reported not crashed
```

### One dialog, six commands

`forms/frmMaintenance.pas` + `.lfm` — **76 design-time components**, every page
in the designer, the one for the command shown and the rest hidden with
`TabVisible` (§7.2). IBConsole had a separate form per command and
re-implemented the output pane, the Start/Cancel pair and the close-while-running
question in each of them.

Two commands can destroy data and both are named in their confirmation: a
restore with **Replace**, and a validation with **Mend**. "Are you sure?" tells
nobody anything.

Wired into `Database > Maintenance` (Backup, Restore, Validate, Sweep,
Statistics) and `Server > View Log`. The whole Maintenance menu stays hidden for
an embedded database, which has no server to ask.

### Forms are checked by streaming them

`.lfm` and `.pas` can disagree — a control in the designer file with no
published field, a handler name that does not exist — and the compiler will not
say so. A small program using the **`nogui`-free win32 LCL** creates each form,
which streams its `.lfm` and raises on any mismatch:

```
frmExecuteRoutine  18 components
frmMaintenance     76 components
frmMain            56 components, maintenance items wired to the right Tags
```

---

## 5.14 M5 — user management

`units/services/SecurityService.pas` — `TSecurityService`, and
`forms/frmUserManager.pas` + `.lfm` (32 design-time components).

### Why the Services API alone is not enough

The Services API has had user management since InterBase, and IBX wraps it as
`TIBXSecurityService`. From Firebird 3 it stopped being the whole picture:
user managers became pluggable (Srp by default, Legacy_UserManager for
compatibility), and the Services API talks to whichever **one** the server
names first in its `UserManager` list. Accounts held by any other plugin are
invisible to it, and a user created through it lands in whichever plugin the
server picked — not necessarily the one the administrator meant.

SQL user management — `CREATE USER`, `ALTER USER`, `DROP USER`, `SEC$USERS` —
goes through the path the engine itself uses, sees every plugin, and reports
which plugin each account belongs to.

So the rule is: **SQL when there is a connected database to run it on, the
Services API only when there is not**, and the dialog says which one it used.
A list that may be partial is not presented as the whole truth.

`CREATE USER` is a statement, so the SQL path needs an attachment — any
database on the server will do, because the accounts belong to the server.

### A transaction bug this found

The first live run created a user successfully and then could not find it in
the list. Not a caching mistake of ours: Firebird materialises `SEC$USERS`
**once per transaction**, and the metadata transaction is long-lived by design.
Read committed does not help — the snapshot is taken when the transaction first
touches the table, not per statement.

Proved with three reads after one `CREATE USER`, on Firebird 5.0.4:

```
after, same context:      IBQ_TEST_USER SYSDBA                  (2)   <- missing
after, new transaction:   IBQ_PROBE_USER IBQ_TEST_USER SYSDBA   (3)   <- there
after, new attachment:    IBQ_PROBE_USER IBQ_TEST_USER SYSDBA   (3)   <- there
```

The fix is `TDatabaseContext.FetchTableFresh`, which runs a query on a
transaction started and committed for that call alone. It exists for exactly
this class of table and the **`MON$` monitoring tables have the same
behaviour** — which is why the connected-users view, still to come, will use it
too. Ordinary metadata still goes through `FetchTable` and the standing
transaction, which is cheaper.

`TDatabaseContext.ExecuteDdl` was added alongside it: one statement on the DDL
transaction, committed at once, rolled back on failure. Deliberately not a
general statement runner — anything the user typed still goes through
`TSqlSession`, on that editor's own transaction, under the user's own Commit
and Rollback.

### What the columns are, and what is not there

`SEC$USERS` is identical on Firebird 3, 4 and 5: `SEC$USER_NAME`,
`SEC$FIRST_NAME`, `SEC$MIDDLE_NAME`, `SEC$LAST_NAME`, `SEC$ACTIVE`,
`SEC$ADMIN`, `SEC$DESCRIPTION`, `SEC$PLUGIN`. Verified against all three.

There is **no user id and no group id**. They existed in the legacy security
database and the Services API still reports them; the SQL view does not carry
them and a modern plugin does not have them. A column showing a permanent zero
would be worse than no column.

`SEC$ACTIVE` and `SEC$ADMIN` are BOOLEAN, and a boolean read as text is not the
same string on every client, so `UserAccountsSQL` renders them as YES/NO.

The provider already had a `UsersSQL` — the Users *folder* in the tree, which
answers the collection contract of names only. The new one is
`UserAccountsSQL`, and the two are documented against each other so the next
reader does not merge them.

### Verified against Firebird 3.0.14, 4.0.7 and 5.0.4 — 65 checks

Each server got the full cycle through the SQL path, plus the Services API path
on Firebird 5:

```
list           SYSDBA present, active, administrator, plugin = Srp
create         first and last name come back, active, not an administrator
modify         first name changed, middle name set, LAST NAME CLEARED,
               made inactive, granted the admin role - all in one ALTER
modify again   with an empty password: accepted, the account still exists
drop           gone from the list
refusals       unnamed user refused; no password refused;
               dropping a missing user -> GDSCODE 336723990,
               "record not found for user: IBQ_NO_SUCH_USER_AT_ALL"
Services API   SYSDBA listed through TIBXServicesUserList
```

The cleared last name is the case worth having: on `ALTER`, leaving a clause
out means "do not change it" while including it empty means "clear it". The
dialog showed the user their current values, so a field they emptied must
clear — `ModifyUser` always includes the name clauses, and `AddUser` only
includes the ones that have something in them.

The rig was left with `SYSDBA` alone on all three servers.

**What was not tested live:** *creating, changing and deleting* through the
Services API path. Listing through it was verified; the write operations were
not, because the only servers here are Firebird 3, 4 and 5, all running Srp,
where the SQL path is the one that gets used. That path exists for a server
older than anything on this rig, and it is exercised for the first time by
whoever has one. It is noted here rather than presented as verified.

### The dialog

One window: the list, and the fields beside it. IBConsole had a list window
that opened an edit window; for six fields that is ceremony, and the list next
to the fields is what makes it obvious the admin flag belongs to a person.

- the password box is **always blank** — Firebird cannot give a password back.
  Blank on Save means "keep the current one"; a new user must have one
- passwords are typed twice and compared before anything is sent
- the user name is read-only for an existing account: Firebird has no rename,
  and typing over a name would create a *second* account
- delete asks, and names the account in the question
- an empty list says "only an administrator sees other people's accounts"
  rather than leaving an empty grid to be read as a failure

Wired into **Database > Maintenance > Users...** (SQL path, needs the database
connected) and **Server > Users...** (Services API path, prompts for the
password).

---

---

## 5.15 M7 — the Linux rig, and the three defects it found

A second rig now runs on Linux: Firebird 3.0.14, 4.0.7 and 5.0.4 side by side
under `/mnt/Data/Firebird/linux`, ports 3050/3051/3052, each with its own
`firebird.conf`, security database, lock directory and `libfbclient.so`,
started as an unprivileged user with nothing installed system-wide. Its
`README.md` documents the isolation. Each instance holds its own `EMPTEST.FDB`
restored by its own `gbak`, because an ODS 12 file cannot be opened by a
Firebird 4 or 5 engine.

`tests/TestLiveConnection.pas` drives the database layer against all three. It
is the first test in `tests/` that needs a server, and it is the Linux
counterpart of §5.2:

```sh
fpc -Mobjfpc -Sh -FUout -FEout \
    -Fuunits/core -Fuunits/db -Fuunits/sql -Fuunits/model -Fuunits/ddl -Fuunits/services \
    -Fu$LZ/components/lazutils/lib/x86_64-linux \
    -Fu$PK/FBIntf/lib/x86_64-linux \
    -Fu$PK/IBX4Lazarus/runtime/nongui/lib/x86_64-linux \
    tests/TestLiveConnection.pas
out/TestLiveConnection [<rig root>]
```

**Check the exit code, not only the output.** The last thing it does is attach
to the newest server and then the oldest, which is the sequence that crashed
at finalisation on Windows (§5.6) — after every visible result was already
correct. On Linux that sequence exits 0, so `PinClientLibrary` holds here too.

### The three defects

All three were invisible on Windows, and none of them is a Linux bug. Each is
a wrong assumption that the Windows rig happened never to contradict.

| # | Defect | Why Windows never showed it |
|---|---|---|
| 1 | `DatabaseInfoSQL` selected `MON$CREATION_DATE` | The Windows FB4/FB5 runs used each server's own client; only an **older client against a newer server** fails |
| 2 | `ConnectionString` omitted the port when it was 3050 | Every Windows client had `RemoteServicePort = 3050`, so the omission was harmless there |
| 3 | `VersionFromPath` could not read a Linux client's version | A Windows client sits in `FB5\fbclient.dll` and carries a version resource; a Unix one sits in `fb5/lib/` and carries neither |

**1. A Firebird 3 client could not connect to a Firebird 4 or 5 server.**
The attachment succeeded and then the *first* query on it failed:

```
Engine Code: 335544573  Data type unknown
When Executing: SELECT d.MON$SQL_DIALECT ... d.MON$CREATION_DATE ... FROM MON$DATABASE d
```

`MON$DATABASE.MON$CREATION_DATE` is field type 35 (`TIMESTAMP`) on Firebird 3
and type 29 (`TIMESTAMP WITH TIME ZONE`) from Firebird 4 — confirmed by
reading `RDB$FIELDS` on all three servers. A Firebird 3 client cannot
represent it.

The query is the bootstrap read, run before the engine version is known and
therefore built from the *minimum-version* provider, on the comment's stated
grounds that "the MON$DATABASE query is identical on every supported version
anyway". That was false. It also selected `MON$PAGE_SIZE`,
`MON$FORCED_WRITES`, `MON$READ_ONLY` and `MON$CREATION_DATE` — **four columns
no code anywhere reads**. Removing them fixes it: the query now selects the
three it uses, and the rule is written down that this one query must stay
readable by the oldest supported client talking to the newest supported
server.

This is SPECIFICATION.md §16's "FB4 time-zone types" risk arriving, and not in
the grid where it was expected — in the connect path, where it stopped the
database node expanding at all.

**2. A connection aimed at port 3050 could reach a different server.**
`ConnectionString` omitted the port when it equalled 3050, "the default". The
default is not ours to assume: a portless `host:path` is resolved by the
`RemoteServicePort` in the `firebird.conf` belonging to **the client library
this attachment loads**. On this rig the Firebird 4 client's default is 3051.
So a profile pointing at 3050 opened a database on the Firebird 4 server, and
returned this:

```
unsupported on-disk structure for file .../data/fb3/EMPTEST.FDB; found 12.0, support 13.0
```

An entirely plausible error, from the wrong machine. The port is now always
written. Note the routine's own comment already said the `host/port:` form was
chosen deliberately over `host:path`; the code contradicted it.

**3. Every Linux client library reported version 0.** `ReadClientInfo` falls
back to parsing the folder name when a file has no version resource — which is
always, for an ELF shared object. It parsed the *immediate* parent, which on
Unix is `lib`, not `fb5`. So the registration dialog offered a list of client
libraries it could not tell apart.

Three changes: the parent folder is stepped over when it is `lib`, `lib64` or
`bin`; a versioned soname beside the library is read first, because
`libfbclient.so.3.0.14` states the version exactly where the folder name only
implies the major; and `ScanRoot` now probes `<root>/<sub>/lib/` as well, so
the Unix equivalent of `C:\firebird\FB5\fbclient.dll` is actually found.
Detection now reports `Firebird 3.0.14`, `4.0.7`, `5.0.4` from the file names.

A fourth, smaller one: `TMetaDatabase.EffectiveClientLibrary` returned `''`
for a remote profile with no server registration, handing the choice to
whichever `libfbclient` the loader reached first. The tree always has a
registration so the UI never took that path, but a test did, and `''` is
exactly the accident §5.6.1 exists to prevent. It now falls back to the
profile's own library.

### Results after the fixes

Every check passes and the process exits 0:

```
clients        Firebird 3.0.14 / 4.0.7 / 5.0.4 read from the .so names
FB3  3050      ODS 12.0  dialect 3  TMetadataSqlProviderFB3  18 folders, 286 objects
FB4  3051      ODS 13.0  dialect 3  TMetadataSqlProviderFB4  19 folders, 286 objects
FB5  3052      ODS 13.1  dialect 3  TMetadataSqlProviderFB5  19 folders, 286 objects
gating         dbfPublications false on FB3, true from FB4
               dbfPartialIndexes true only on FB5;  dbfSchemas false everywhere
               the Publications folder is ABSENT on FB3, not present-and-empty
FB3 client ->  FB4 and FB5, both attached and read through  <- defect 1's guard
newest first   FB5 then FB3 in one process, exit 0          <- §5.6 still fixed
refusals       wrong password -> GDSCODE 335544472, the server's own wording
               missing database -> GDSCODE 335544344, I/O error, no crash
```

### Against the 2.3 GB production database

`/mnt/Data/databases/line4_20251121.fdb`, the Linux copy of the database used
in §5.2, through the Firebird 3 client:

| Step | Remote (3050) | Local | Windows (§5.2) |
|---|---|---|---|
| connect | **78 ms** | 19 ms | 102 ms |
| build folder nodes | **0 ms**, 18 folders, 0 objects read | 0 ms | 0 ms |
| load every folder | **18 ms**, 1084 objects | 10 ms | 23 ms |

154 tables, 190 triggers, 314 indexes, 162 generators — **identical to the
Windows counts**, which is the useful part: the same metadata SQL against the
same database on a different operating system returns the same schema. The
0 ms middle row is the lazy-loading contract holding here as well.

### A fourth defect, found by opening the dialog

`Server > Properties…` filled in correctly and the debugger stopped anyway:

```
Project IBQConsole raised exception class 'EResourceReaderNotFoundException'
with message: Cannot find resource reader for extension '.14'
```

The registration named `libfbclient.so.3.0.14` — the versioned file rather
than the symlink, which is the one that looks most specific when picking from
a file dialog. `ExtractFileExt` of that is **`.14`**, `TResources.LoadFromFile`
finds no reader for it, and raises.

Two things were wrong, and the visible one was the smaller.

**`TFileVersionInfo` was being used as a test rather than a reader.** It
raises when asked about a file it has no reader for, and on Linux that is
*every* call — the extension is `.so`, or worse `.14`. The raise was caught
and the fallback was correct, so the program behaved and nothing was ever
reported. But `PASCAL-LAZARUS-RULES.md` §9 forbids exceptions as normal
control flow for exactly this reason: anyone running under the debugger got a
notification every time a client library was listed, from the registration
dialog as well as this one. `CanCarryVersionResource` now gates the call on an
extension that could actually hold a version resource — `.dll` or `.exe` — so
the reader is asked only when there is something to read. The `try..except`
stays, for a malformed DLL, which is a real error rather than the normal case.
`elfreader` left the uses clause with it: an ELF built by GCC carries no
VERSIONINFO, so registering a reader for it never bought anything.

**The version was thrown away when it was in plain sight.** `libfbclient.so.3.0.14`
states the version in its own name, and the code went looking at the folder
instead, reporting `Firebird 3.0` and losing the patch level. `NumericTail`
now reads it off the file name first, requiring at least three numeric parts
so that `libfbclient.so.2` — the soname, where 2 is the API generation — is
not read as Firebird 2.

Every name form now resolves, and none of them raises:

```
libfbclient.so           -> 3.0.14   (versioned sibling in the same folder)
libfbclient.so.3.0.14    -> 3.0.14   (read from the name itself)
libfbclient.so.2         -> 3.0      (soname ignored; folder name used)
```

Worth keeping because of how it surfaced: the feature worked, the values on
screen were all correct, and the only symptom was a debugger notification.
Run under the debugger at least once, or this class of thing ships.

### One thing that is worse on Linux, and stays that way

With **two different client library versions loaded in one process**, a failing
attachment can report the wrong error:

```
one client  (FB5, FB5)   -> I/O error during "open" operation ... No such file or directory
two clients (FB3, FB5)   -> Error loading plugin Engine13
                            -libEngine13.so: undefined symbol: fb_dsql_set_timeout
```

The Firebird 5 engine plugin is dlopen'd while an older `libfbclient` is
already in the process, and resolves `fb_dsql_set_timeout` — an export added
in Firebird 4 — against the wrong one. Windows has no equivalent, because each
DLL carries its own import table.

It affects **error text only**: every successful attachment in the table above
was made with several clients loaded. There is no fix on our side; it is
inside Firebird's plugin loading, reached through FBIntf. Recorded rather than
worked around, so the next person to see that message knows it means "the file
is not there" and not "the installation is broken".

---

## 6. Current state — M0-M6 done, M7 in progress

`SPECIFICATION.md` §15 is the authoritative milestone record; this section is
the build-and-verification view of the same work, and the narrative below is
kept in the order things were demonstrated rather than rewritten each time.

Built clean on **both** platforms - `debug_win`, `release_win`, `debug_linux`
and `release_linux`, 0 errors, 0 warnings, 0 code hints. There is now a
Firebird 3/4/5 rig on **each** platform (§5.0 Windows, §5.15 Linux), and
connect-and-browse is verified against both. The layers above that - SQL
editor, services, user management, DDL dialogs - are still verified on Windows
only.

- **M3** — SQL editor: SynEdit with a Firebird highlighter whose dialect
  follows the server version, Execute (F5) on the statement under the caret or
  the selection, Run script (F9) honouring SET TERM, Data / Messages / Plan
  tabs, its own transaction with Commit and Rollback and a coloured indicator
- **M2** — object property pages, per-object DDL via `TIBExtract`
- **M1** — registrations, per-server client libraries, connect/disconnect,
  lazy object tree, dialect-3 enforcement
- **M0** — build modes, localisation, icons plumbing

M3 is now feature-complete against the specification: SynEdit editor,
execute statement / script with SET TERM, Data / Messages / Plan / Statistics
tabs, its own transaction with Commit and Rollback, statement history, and
file open/save.

M4 so far:

- **BLOB editor**: text / hex / image views, load and save, content-based format
  detection; opened by double-clicking a BLOB cell
- **Every form editable in the Lazarus designer** (§5.11)
- **Editable data grid** on the Data tab: insert, update, delete, with Commit /
  Rollback / Refresh and a read-only fallback that states its reason
- Export from the grid as well as from the SQL editor
- Exports in six formats, from the SQL editor's Export button; the format
  follows the file extension the user chooses, so there is no separate dropdown
  to fall out of step with the file name
- **Object > Script as** builds SELECT / INSERT / UPDATE / DELETE / MERGE /
  EXECUTE from the real column list and primary key
- Index property page now shows table, columns, uniqueness, direction, activity,
  selectivity, the constraint it backs, expression source, and — on Firebird 5
  only — the partial-index condition
- **Object > Execute...** runs a procedure with typed-in values, in its own
  transaction, selectable or executable read from the catalogue (§5.12)

M5 so far (§5.13):

- **Server-level connect** through the Services API — the item outstanding
  since M1 — verified against Firebird 3, 4 and 5 in one process
- **`TServiceRunner`**: every maintenance command on a worker thread, output
  streamed line by line, cancellable, each run on its own attachment
- **Backup, restore, validation (full and online), sweep, statistics, server
  log, shutdown and startup**, each a task class with its own plain-Pascal
  option set
- **One maintenance dialog** for all of them, 76 design-time components, wired
  into Database > Maintenance and Server > View Log
- **User management** (§5.14): SQL through a connected database, Services API
  as the fallback, verified across Firebird 3, 4 and 5

Still to do in M5: limbo transaction recovery, and the connected-users view.
- **Extract Metadata** on the Database → Maintenance menu opens the whole
  database's DDL in a SQL editor tab, so it can be edited and run rather than
  only read (662,554 characters from the production database)
- **Data tab** on tables and views: the first 200 rows, read-only, on the
  read-only metadata transaction so browsing can never hold a lock. This is the
  start of M4; the editable grid still needs its own transaction and an
  updatable dataset

Outstanding:
- **Firebird 6 untested** — no server available (§4). The one part of D1/D4
  still undemonstrated.
- **On Linux, only connect and browse are verified** (§5.15). SQL execution,
  the services layer, user management and the DDL dialogs have not been run
  against a Linux server, and no GUI interaction has been automated.
- **A misleading error message on Linux** when two client library versions are
  loaded at once (§5.15, last part). No fix available on our side.
- **M6 (DDL editing) has not been run against a live server** — 71 offline
  checks pass, no statement has yet been executed by a Firebird engine.
- **M7 remains**: `icons/` is empty, `documentation/source/` has no Sphinx
  manual, and there are no installers for either platform.
