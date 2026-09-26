#!/bin/sh
# =============================================================================
#  Rebuilds IBQConsole.res from resources/IBQConsole.rc.
#
#  Run this after adding an icon or changing the version information. The
#  resulting .res is linked by the {$R *.res} in IBQConsole.lpr, so every image
#  ships inside the executable and nothing is loaded from disk.
#
#  Uses fpcres rather than windres: windres shells out to the gcc preprocessor,
#  which is not present in every FPC install, while fpcres compiles .rc files
#  on its own.
# =============================================================================
set -e

FPCRES="${FPCRES:-fpcres}"

if ! command -v "$FPCRES" >/dev/null 2>&1; then
  echo "ERROR: fpcres not found. Set the FPCRES environment variable to its path." >&2
  exit 1
fi

cd "$(dirname "$0")/.."
"$FPCRES" -of res -o IBQConsole.res resources/IBQConsole.rc
echo "IBQConsole.res rebuilt."
