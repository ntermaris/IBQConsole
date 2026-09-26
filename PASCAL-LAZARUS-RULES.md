# Pascal / Lazarus Development Rules

Standard rules for every Free Pascal / Lazarus project.
Copy this file into the root of a new project (optionally rename it `CLAUDE.md`
so an assistant picks it up automatically) and follow it from the first commit.

---

## 1. Project folder structure

Source is **never** dumped in the project root. Every project uses this layout:

```
<ProjectRoot>/
├── forms/            # Every TForm / TFrame / TDataModule: .pas + .lfm pairs
├── units/            # Every non-visual unit: classes, types, helpers, DB layer
├── documentation/    # Sphinx sources (.rst) -> PDF user manual
├── resources/        # .rc, .res, icons, images, .po translation files
├── lib/              # Third-party units not installed as packages
├── bin/              # Build output (ignored by version control)
├── backup/           # Lazarus .~pas backups (ignored by version control)
├── MyProject.lpi     # Project file
├── MyProject.lpr     # Program file
└── PASCAL-LAZARUS-RULES.md
```

Rules:

- `forms/` holds **only** units that own a `.lfm`. Nothing else.
- `units/` holds everything else. Subfolders are allowed when the project grows:
  `units/db/`, `units/core/`, `units/utils/`.
- Register both paths in *Project Options → Paths → Other unit files*:
  `forms;units;units/db;units/core;units/utils;lib`
- Set *Target file name* to `bin/$(TargetCPU)-$(TargetOS)/MyProject`.
- Set *Unit output directory* to `lib/$(TargetCPU)-$(TargetOS)` — compiler artifacts,
  kept out of the repo.
- Paths inside the project must be **relative**. Never commit absolute paths like `D:\...`.

---

## 2. One class per unit

- **One public class per unit.** The unit name matches the class name without the `T`
  prefix: class `TCustomerRepository` → unit `units/CustomerRepository.pas`.
- Helper types that exist only to serve that class (records, enums, small exception
  classes) may live in the same unit. Anything reused elsewhere gets its own unit.
- Forms are the same rule applied to UI: `TfrmCustomerEdit` → `forms/frmCustomerEdit.pas`.
- No circular unit references. If two units need each other, the shared piece belongs
  in a third unit (usually a types/interfaces unit).
- `uses` in the **interface** section holds only what the interface section needs.
  Everything else goes in the **implementation** `uses`.

---

## 3. Unit skeleton

Every unit starts from this template:

```pascal
{==============================================================================
  Unit:        CustomerRepository
  Purpose:     Reads and writes customer records from the Firebird database.
  Author:      <name>
  Created:     2026-08-20
  Depends on:  SQLdb, DBTypes
==============================================================================}
unit CustomerRepository;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SQLdb, DBTypes;

type
  { TCustomerRepository
    Data-access object for the CUSTOMER table. Owns no connection; the
    connection is injected through the constructor and stays owned by the caller. }
  TCustomerRepository = class(TObject)
  private
    FConnection: TSQLConnection;
    FLastError: string;
    { Builds the SELECT statement for the given filter expression. }
    function BuildSelectSQL(const AFilter: string): string;
  protected
    { Raises EDatabaseError when the injected connection is not open. }
    procedure RaiseIfNotConnected;
  public
    constructor Create(AConnection: TSQLConnection);
    destructor Destroy; override;

    { Loads one customer by primary key. Returns False when no row matches. }
    function LoadById(const AId: Integer; out ACustomer: TCustomer): Boolean;
    { Inserts or updates the customer. Returns False and fills LastError on failure. }
    function Save(const ACustomer: TCustomer): Boolean;

    { Message of the last failed operation; empty when the last call succeeded. }
    property LastError: string read FLastError;
  end;

implementation

{ ... }

end.
```

Mandatory:

- `{$mode objfpc}{$H+}` at the top of every unit (`{$mode delphi}` only when porting
  Delphi code, and then consistently across the whole project).
- File header block naming the unit, its purpose and its dependencies.
- Sections in this order: `private`, `protected`, `public`, `published`.

---

## 4. Clean class design

- **Fields are always `private`** and prefixed with `F`: `FCustomerName`.
- External access goes through **properties**, never through raw fields:
  `property CustomerName: string read FCustomerName write SetCustomerName;`
- A class does one thing. If a class name needs "And" or "Manager" to describe it,
  split it.
- **Constructor/destructor pairing:** everything created in `Create` is freed in
  `Destroy`. Always `override` and always call `inherited`:

```pascal
constructor TCustomerRepository.Create(AConnection: TSQLConnection);
begin
  inherited Create;
  FConnection := AConnection;      // injected, NOT owned
  FCache := TStringList.Create;    // owned
end;

destructor TCustomerRepository.Destroy;
begin
  FCache.Free;
  FConnection := nil;              // not ours to free
  inherited Destroy;
end;
```

- **Ownership must be obvious.** Document in the class comment which references the
  class frees and which it merely borrows.
- Every allocation is protected by `try..finally`:

```pascal
var
  Query: TSQLQuery;
begin
  Query := TSQLQuery.Create(nil);
  try
    Query.DataBase := FConnection;
    // ...
  finally
    Query.Free;
  end;
end;
```

- Prefer composition over deep inheritance. Three levels below `TObject` is a smell.
- Use `TObject`-descended classes, not `object` (obsolete) and not bare pointers.
- Use interfaces (`IInterface`) when you need pluggable behaviour or reference counting.
- No global variables. Shared state lives in a singleton class or is passed explicitly.
- Public methods validate their arguments and raise a typed exception on failure:
  `EInvalidCustomer = class(EAppError);`

---

## 5. Documentation in code — every routine, no exceptions

Every `function`, `procedure`, `constructor`, `destructor` and property accessor carries
a description. Use this format directly **above the implementation**:

```pascal
{------------------------------------------------------------------------------
  LoadById
  ----------------------------------------------------------------------------
  Loads a single customer by primary key.

  Parameters:
    AId       - Primary key of the customer to load. Must be > 0.
    ACustomer - Receives the loaded record. Undefined when the result is False.

  Returns:
    True when a row was found, False when no row matched AId.

  Raises:
    EDatabaseError - Connection is closed or the query failed.

  Notes:
    Does not use the cache; always hits the database.
------------------------------------------------------------------------------}
function TCustomerRepository.LoadById(const AId: Integer;
  out ACustomer: TCustomer): Boolean;
begin
  ...
end;
```

Rules:

- **Every** routine gets the block. A one-line getter gets a one-line description, but
  it gets one.
- Omit the `Parameters:` / `Returns:` / `Raises:` sections only when they are empty.
- In the **interface** section, add a short `{ }` comment above each declaration saying
  what it does in one sentence — that is what the reader of the API sees.
- Describe **what and why**, not how. `// increment i` is noise; delete it.
- Comment the class itself with a `{ TClassName ... }` block above the declaration.
- Update the comment in the same edit that changes the code. A stale comment is a bug.
- Event handlers get a comment too, saying which control and event they serve:
  `{ Enables the Save button once a required field is filled. }`

---

## 6. Naming conventions

| Item | Convention | Example |
|---|---|---|
| Unit | PascalCase, matches main class | `CustomerRepository.pas` |
| Class | `T` + PascalCase | `TCustomerRepository` |
| Interface | `I` + PascalCase | `ICustomerSource` |
| Exception | `E` + PascalCase | `ECustomerNotFound` |
| Private field | `F` + PascalCase | `FCustomerName` |
| Parameter | `A` + PascalCase | `ACustomerId` |
| Local variable | PascalCase | `RowCount` |
| Constant | PascalCase or UPPER_CASE, consistent per project | `MaxRetries` |
| Enum type | `T` + PascalCase; values prefixed | `TSortOrder = (soAsc, soDesc)` |
| Form class | `Tfrm` + PascalCase | `TfrmCustomerEdit` |
| Data module | `Tdm` + PascalCase | `TdmMain` |
| Frame | `Tfra` + PascalCase | `TfraAddress` |
| Global function | Verb first | `FormatCurrencyValue` |

Control naming on forms — prefix by type, always renamed from the default:
`btnSave`, `edtName`, `lblTotal`, `cbxCountry`, `grdCustomers`, `pnlTop`, `memNotes`,
`chkActive`, `dtpBirthDate`, `actSaveRecord`. Never ship `Button1`.

---

## 7. Forms

### 7.1 Controls belong on the form, not in code

**Every control is placed in the designer and lives in the `.lfm`.** Do not create
controls with `TSomething.Create(Self)` in `FormCreate` or a `BuildControls` method.

The reason is simple and non-negotiable: a form whose controls exist only in code
**cannot be opened in the Lazarus form designer**. Nobody can nudge a button,
re-anchor a panel, check the tab order, or see the layout without running the
program. That turns every cosmetic change into a compile-and-run cycle, and it
makes the form unmaintainable by anyone who did not write it.

```pascal
// WRONG - invisible to the designer
FGrid := TStringGrid.Create(Self);
FGrid.Parent := Self;
FGrid.Align := alClient;

// RIGHT - drop it on the form, then just use it
grdColumns.Align := alClient;     // set in the Object Inspector, not here
```

- Controls are declared in the **published** section of the form class, exactly as
  the designer writes them. Never in `private`.
- Properties that never change — `Align`, `Anchors`, `Font`, `Caption`, `Options` —
  are set **in the Object Inspector**, not in code.
- Only *state* is set in code: enabling, visibility, captions from the language
  file, and data.

### 7.2 The one exception: genuinely data-driven repetition

Creating controls at run time is allowed only when the **number** of them is not
known until run time and depends on data:

- one menu item per language file found in `lang/`
- one menu item per enum value, where adding a value must not mean editing a menu
- one tab per object kind, where the set differs per database object

Everything that is always there — the page control those tabs live in, the grid,
the memo, the toolbar, the buttons, the dialogs — goes in the `.lfm`.

Where a fixed set of tabs varies by context, put **all** of them in the designer
and toggle `TabVisible`. A hidden tab still lays out correctly and can still be
edited visually; a tab that only exists at run time cannot.

### 7.3 The rest

- Forms handle **UI only**: display, input validation, event wiring. Business logic and
  database access live in `units/`, called from the form.
- A form never contains an SQL string. Ever.
- Never reference one form's controls from another form (`frmA.edtName.Text` is banned).
  Expose a property or pass a data object.
- Auto-create only the main form. Every other form is created and freed on demand:

```pascal
{ Opens the customer editor modally and returns True when the user saved. }
function EditCustomer(var ACustomer: TCustomer): Boolean;
var
  Form: TfrmCustomerEdit;
begin
  Form := TfrmCustomerEdit.Create(nil);
  try
    Form.LoadFrom(ACustomer);
    Result := Form.ShowModal = mrOK;
    if Result then
      Form.SaveTo(ACustomer);
  finally
    Form.Free;
  end;
end;
```

- Use `TAction` / `TActionList` for anything reachable from more than one place
  (menu + toolbar + shortcut). The handler lives on the action, not on the button.
- Set anchors / `AutoSize` / layout so forms survive resizing and DPI scaling. Do not
  position controls by hard-coded pixel arithmetic at runtime.
- Keep the `.lfm` clean: delete controls you stopped using, don't just hide them.
- No long-running work on the main thread — use a thread with a visible progress indicator.

---

## 8. Code style

- Indentation: **2 spaces**, never tabs.
- Keywords lowercase (`begin`, `end`, `if`, `for`), identifiers PascalCase.
- `begin`/`end` on their own lines; always use them for multi-statement blocks, and
  prefer them even for single-statement `if` bodies.
- One statement per line. Max line length 100 characters.
- Blank line between routines; no blank line right after `begin`.
- One `var` section per routine, at the top of the routine (objfpc mode).
- `case` statements always have an `else` branch (even if it just raises).
- Avoid `with` — it hides which object a member belongs to.
- Avoid `goto`, mid-flow `exit` in complex routines, and nested routines deeper than one level.
- String comparisons use `SameText` / `CompareText`, not `=` on mixed case.
- Never leave `Result` unassigned on any path.
- Format with **Jedi Code Formatter** (*Source → JEDI Code Format*) using a settings
  file committed to `documentation/dev/jcfsettings.cfg`, so everyone formats identically.

---

## 9. Error handling

- Raise typed exceptions derived from a project base: `EAppError = class(Exception)`.
- `try..finally` for cleanup, `try..except` only where you can actually handle the error.
- Never swallow exceptions with an empty `except end`. If it is intentional, comment why.
- Do not use exceptions for normal control flow — return `Boolean` + `out` parameter
  for "not found" style cases.
- Log before re-raising; show a user-friendly message at the UI boundary only.

---

## 10. Cross-platform & compiler hygiene

- Compile with warnings and hints on; the project must build **0 warnings, 0 hints**.
- Use `PathDelim`, `IncludeTrailingPathDelimiter`, `GetAppConfigDir` — never hard-code
  `\` or `/` or `C:\`.
- Use `{$IFDEF WINDOWS}` / `{$IFDEF UNIX}` only in a dedicated platform unit, not
  scattered through business logic.
- `SysUtils.Format` for message building, never `+` chains for user-visible text.
- Use UTF-8 strings consistently (`{$H+}` plus LazUTF8 helpers where needed).

---

## 11. User manual — `documentation/` (Sphinx → PDF)

The application manual lives in `documentation/` as **reStructuredText**, built with
**Sphinx** into a PDF. It is written alongside the feature, not after release.

### 11.1 Layout

```
documentation/
├── source/
│   ├── conf.py              # Sphinx configuration
│   ├── index.rst            # Root toctree
│   ├── introduction.rst
│   ├── installation.rst
│   ├── getting-started.rst
│   ├── user-guide/
│   │   ├── index.rst
│   │   ├── main-window.rst
│   │   ├── customers.rst
│   │   └── reports.rst
│   ├── reference/
│   │   ├── index.rst
│   │   ├── menus.rst
│   │   ├── shortcuts.rst
│   │   └── error-messages.rst
│   ├── troubleshooting.rst
│   ├── glossary.rst
│   ├── changelog.rst
│   ├── _static/             # Custom CSS, logo
│   └── _images/             # Screenshots (PNG), one per figure
├── dev/                     # Developer notes, jcfsettings.cfg, diagrams
├── requirements.txt         # sphinx, sphinx-rtd-theme, ...
├── Makefile                 # make latexpdf / make html
├── make.bat                 # Windows equivalent
└── build/                   # Generated output — ignored by version control
```

### 11.2 Rules

- **One `.rst` file per form or major feature.** The file is named after the feature in
  lower-kebab-case (`customer-editor.rst`), and mirrors the app's menu structure so a
  user can navigate the manual the way they navigate the program.
- Every `.rst` file starts with a title underlined with `=`, and a one-paragraph summary
  of what the screen or feature is for before any step-by-step content.
- Heading underline order is fixed project-wide: `=` title, `-` section,
  `~` subsection, `^` sub-subsection.
- Every chapter is reachable from a `toctree`. No orphan files.
- Screenshots go in `source/_images/`, PNG, named after the form
  (`frm-customer-edit.png`), and are always inserted with a caption via `.. figure::`,
  never a bare `.. image::`.
- Use semantic roles instead of quotes for UI elements:
  `:menuselection:`File --> Export``, `:guilabel:`Save``, `:kbd:`Ctrl+S``,
  `:file:`config.ini``.
- Use the standard admonitions — `.. note::`, `.. warning::`, `.. tip::` — for anything
  the user could get wrong. Warnings for destructive actions (delete, overwrite, restore).
- Line-wrap at 100 characters. One sentence per line is preferred: it keeps diffs readable.
- Version-specific text is tagged with `.. versionadded::` / `.. versionchanged::`
  carrying the app version number.
- Reusable strings (product name, version) are defined once in `conf.py` via `rst_epilog`
  substitutions and referenced as `|product|`, `|version|` — never retyped.
- `changelog.rst` gets an entry for every released version.

### 11.3 Minimum `conf.py` for PDF output

```python
project   = 'MyProject'
author    = '<name>'
release   = '1.0.0'
language  = 'en'

extensions = ['sphinx.ext.todo', 'sphinx.ext.imgmath']
templates_path = ['_templates']
exclude_patterns = []

html_theme = 'sphinx_rtd_theme'
html_static_path = ['_static']

# --- PDF (LaTeX) ---------------------------------------------------------
latex_engine = 'pdflatex'          # use 'xelatex' for non-Latin alphabets
latex_documents = [
    ('index', 'MyProject.tex', 'MyProject User Manual', author, 'manual'),
]
latex_elements = {
    'papersize':  'a4paper',
    'pointsize':  '11pt',
    'figure_align': 'H',
    'preamble': r'''
\usepackage{graphicx}
''',
}

rst_epilog = """
.. |product| replace:: MyProject
"""
```

### 11.4 Building

```bash
# once
python -m pip install -r documentation/requirements.txt   # needs a LaTeX distribution
                                                          # (MiKTeX on Windows, TeX Live on Linux)
# PDF
cd documentation && make latexpdf     # Windows: make.bat latexpdf
# output: documentation/build/latex/MyProject.pdf

# HTML preview while writing
cd documentation && make html
```

- The manual must build **without warnings** (`sphinx-build -W` in CI).
- Commit `.rst`, `conf.py`, `_static/`, `_images/`, `requirements.txt`, `Makefile`.
  Never commit `documentation/build/`.
- A feature is not done until its chapter exists and the PDF builds.

---

## 12. Version control

`.gitignore`:

```
bin/
lib/
backup/
documentation/build/
*.ppu
*.o
*.compiled
*.or
*.a
*.exe
*.dbg
*.lps
*.bak
*.~*
```

Commit `.lpi`, `.lpr`, `.pas`, `.lfm`, `.res`, `.rc` and everything under
`documentation/source/`. Never commit `.lps` (per-user session state) or build output.

---

## 13. Definition of done — checklist

- [ ] New form in `forms/`, new non-visual unit in `units/`
- [ ] One public class per unit; unit named after the class
- [ ] Unit header block filled in
- [ ] All fields `private` + `F` prefix, exposed via properties
- [ ] Every created object freed in the destructor or a `try..finally`
- [ ] **Every** function/procedure has its description block
- [ ] Interface-section declarations have a one-line comment
- [ ] Controls renamed from the defaults with the correct prefix
- [ ] No SQL or business logic inside a form unit
- [ ] Builds with zero warnings and zero hints
- [ ] Formatted with the shared JCF settings
- [ ] Manual chapter written in `documentation/source/`, linked in a `toctree`
- [ ] `make latexpdf` produces the PDF with no Sphinx warnings
