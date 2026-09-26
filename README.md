# IBQConsole

A Firebird database editor and administration console for Windows and Linux,
written in Free Pascal / Lazarus.

IBQConsole takes **the interaction model of IBConsole** — a tree of servers and
databases, property pages, the Server → Database → Maintenance menu spine — and
**the feature set of FlameRobin**. A user who knows IBConsole should be
productive within five minutes.

> Status: pre-release (0.1). Connect, browse, SQL editing, data editing, DDL
> editing and server administration are implemented. Icons, the user manual
> and installers are still to come — see [Roadmap](#roadmap).

## Features

- **Servers and databases** — register servers and databases (remote, local or
  embedded), each server with its own `fbclient` library, so Firebird 3, 4 and 5
  can be open side by side in one process. Import existing registrations from
  FlameRobin and IBConsole.
- **Object tree** — lazily loaded, so a database with thousands of objects stays
  responsive; per-branch refresh; name filter (Ctrl+Shift+F); optional system
  objects.
- **Property pages** — properties, columns, parameters, indexes, constraints,
  triggers, source, dependencies, permissions, data and DDL, one tab per detail.
- **SQL editor** — Firebird syntax highlighting per server version, execute
  statement (F5) or script (F9, honours `SET TERM`), Data / Messages / Plan /
  Statistics tabs, own transaction with commit/rollback, persistent history.
- **Data editing** — editable grid for tables with a primary key (read-only, with
  the reason shown, otherwise), BLOB editor with text/hex/image views, export to
  CSV, TSV, JSON, HTML, Markdown and INSERT statements.
- **Script as…** — SELECT, INSERT, UPDATE, DELETE, MERGE, EXECUTE, CREATE,
  ALTER (`CREATE OR ALTER`) and DROP, generated into an editor tab, never run
  automatically.
- **DDL editing** — create, alter and drop tables, domains, indexes, sequences,
  exceptions and roles, each with the exact statement shown before it runs.
- **Databases** — connect, connect as another user or role, create and drop.
- **Administration** (Services API) — backup, restore, validation, sweep,
  statistics, server log, shutdown/startup, user management, limbo-transaction
  recovery and connected users.
- **Localisation** — runtime language switching from `.lng` files; English is
  built in and a complete Greek translation ships in `lang/`.

### Supported servers

Firebird **3.0, 4.0 and 5.0** — tested live against 3.0.14, 4.0.7 and 5.0.4.
Firebird 6.0 (SQL schemas) has a metadata provider but has not yet been tested
against a server. SQL dialect 1 databases are refused with an explanation.

## Building

### Requirements

| | Version |
|---|---|
| Free Pascal | 3.2.2 |
| Lazarus | 3.x or 4.x |
| [IBX for Lazarus](https://www.mwasoftware.co.uk/ibx) | 2.7.11 (`ibnongui` package + FBIntf, from the Online Package Manager) |
| Firebird client | `fbclient` 3.0 or later |

On Linux the LCL `gtk2` widgetset and the gtk2 development libraries are also
needed.

### Build

Open `IBQConsole.lpi` in Lazarus and run, or from the command line:

```sh
lazbuild --build-mode=debug_win     IBQConsole.lpi
lazbuild --build-mode=release_win   IBQConsole.lpi
lazbuild --build-mode=debug_linux   --widgetset=gtk2 IBQConsole.lpi
lazbuild --build-mode=release_linux --widgetset=gtk2 IBQConsole.lpi
```

If Lazarus is installed in a non-default location (for example with
fpcupdeluxe), add `--pcp=<path to its config directory>`.

The executable is written to `bin/<mode>/`. A clean build reports **0 warnings
and 0 hints** apart from the two `fpc.cfg` notices (11030/11031).

Detailed notes — package registration on Linux, the multi-version Firebird test
rig, known pitfalls — are in [`documentation/dev/building.md`](documentation/dev/building.md).

### Tests

The offline test programs in `tests/` are plain console programs, for example:

```sh
fpc -Mobjfpc -Sh -FUout -FEout -Fuunits/core -Fuunits/sql -Fuunits/model \
    -Fuunits/ddl -Fuunits/db tests/TestDdlStatements.pas
./out/TestDdlStatements
```

`utils/langcheck.pas` checks a language file against the keys the source
actually uses: `langcheck lang/Greek.lng . --dynamic node.`

## Project layout

```
forms/          every form and frame (.pas + .lfm)
units/core/     configuration, logging, localisation, registration storage
units/db/       Firebird access: connection profiles, database context,
                version-specific metadata SQL providers (FB3/4/5/6)
units/model/    the metadata object model behind the tree
units/ddl/      DDL statement builders
units/services/ Services API wrappers (backup, restore, users, ...)
units/sql/      identifiers, keywords, script generation, statement splitter
lang/           language files
resources/      .rc resource script (compiled into IBQConsole.res)
tests/          offline test programs
utils/          build and language tools
documentation/  developer notes; user manual to follow
```

## Contributing

Read [`SPECIFICATION.md`](SPECIFICATION.md) for the architecture and decisions,
and [`PASCAL-LAZARUS-RULES.md`](PASCAL-LAZARUS-RULES.md) for the coding standard
before writing code. In short: one class per unit, every routine documented,
controls live in the `.lfm`, no SQL in forms, LF line endings, and the build
stays at zero warnings and zero hints.

## Roadmap

- Remaining main-window items: database properties and registration info,
  connection diagnostics, Window and Help menus, About dialog, a shared
  `TActionList` for all commands
- Icon set compiled into the executable
- User manual (Sphinx → PDF)
- Installers for Windows and Linux
- Live testing against Firebird 6.0

## Author

Alexandros Ntermaris
