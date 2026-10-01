#!/usr/bin/env bash
# Runs the CPython versions of the pygrametl example programs
# (pygrametl1_cpython.py / pygrametl2_cpython.py) against PostgreSQL.
#
# Usage (from anywhere):
#   ./run_cpython.sh 1        # sequential version
#   ./run_cpython.sh 2        # parallel version
#   ./run_cpython.sh both     # run both and compare (default)
#
# Optional environment variables:
#   SIZE=small (default) | 5 | 25 | 50 | 100   dataset size (numbers = datagenerator/params-N.py)
#   REGEN=1                                     regenerate the CSV files even if they exist
#   RUNS=3                                      run each program N times (default 1)
#   CLEAR_CACHE=1                               restart PostgreSQL and clear the OS file cache
#                                               before every run (asks for your password once)
#   PG_MONITOR=0                                don't monitor PostgreSQL during the runs
#                                               (./setup_pg_monitoring.sh once adds SQL statement times)
#   UNLOGGED=1                                  create the tables as UNLOGGED (no WAL; to measure
#                                               how much PostgreSQL's write work costs)
#   PY_VERSION=3.14t (default) | 3.14 | 3.13 ... Python version, used when uv is installed
#                                               (3.14t = free-threaded build, 3.14 = normal build with GIL)
#
# Examples:
#   SIZE=5 ./run_cpython.sh both          # paper's params-5 data set, both programs
#   SIZE=5 RUNS=3 ./run_cpython.sh 2      # parallel version three times
#   SIZE=5 PY_VERSION=3.14 ./run_cpython.sh 2    # parallel version on the normal (GIL) Python
#
# Every run is appended to run/results.csv (shared with run_jython.sh) with its time,
# memory, disk I/O, row counts and a description of the machine and PostgreSQL settings.
#
# Overview of what the script does, in order (same steps as run_jython.sh):
#   1. prerequisites  find/create the Python environment, install pygrametl and psycopg2 if missing
#   2. database       make sure the PostgreSQL user and database "chr" exist
#   3. data           generate the input CSV files (only when the size changed or REGEN=1)
#   4. setup          record the Python version, load the shared measuring code
#   5. run            for each run: recreate the tables, (clear caches), run + measure, save a row

# Stop at the first error (-e), treat unset variables as errors (-u),
# and let a pipeline fail if any command in it fails (-o pipefail).
set -euo pipefail

# ---------------------------------------------------------------- settings
# "${VAR:-default}" means: use $VAR if it is set, otherwise the default.
# That is how SIZE=5 RUNS=7 ./run_cpython.sh overrides the defaults.
HERE="$(cd "$(dirname "$0")" && pwd)"          # .../pygrametl/exaprogs (the folder of this script)
REPO="$(dirname "$HERE")"                       # parent folder (a pygrametl checkout, if exaprogs sits in one)
LIB="$HERE/lib"
WORK="$HERE/run"                                # generated data, logs and results.csv go here
SIZE="${SIZE:-small}"
RUNS="${RUNS:-1}"
WHICH="${1:-both}"                              # first command-line argument: 1, 2 or both

# Jython is only needed here to run the data generator (see "data" below), not the ETL programs
JYTHON_JAR="${JYTHON_JAR:-$LIB/jython-standalone-2.7.4.jar}"
MAVEN=https://repo1.maven.org/maven2            # central download site for Java libraries

# ---------------------------------------------------------------- prerequisites
# Python + pygrametl:
#  - inside a pygrametl checkout: use its .venv and its pygrametl source code
#  - standalone: use (or create) a virtual environment in exaprogs/ with the packages
#    in requirements.txt:
#      with uv installed:  exaprogs/.venv-$PY_VERSION, e.g. .venv-3.14t (created by uv)
#      without uv:         exaprogs/.venv (created by python3 -m venv)
#  - PY_VERSION=3.14t (default) picks the Python version when uv is used; uv downloads it
#    if it is not installed. 3.14t is the free-threaded build (no GIL); PY_VERSION=3.14
#    gives the normal build with the GIL, in its own .venv-3.14, so both can be compared.
#  - PYTHON=/path/to/python overrides the interpreter
# A .venv ("virtual environment") is a private Python installation in a folder, so the
# packages installed for this project do not mix with the rest of the system.
# uv (https://docs.astral.sh/uv/) is a fast replacement for venv + pip that can also
# download and install Python itself, so every machine gets the same Python version.
PY_VERSION="${PY_VERSION:-3.14t}"
HAVE_UV=0
command -v uv >/dev/null && HAVE_UV=1

PYGRAMETL_PATH=""
if [ -f "$REPO/pygrametl/__init__.py" ]; then
  PYGRAMETL_PATH="$REPO"
  PYTHON="${PYTHON:-$REPO/.venv/bin/python}"
fi
if [ -z "${PYTHON:-}" ]; then
  if [ "$HAVE_UV" = 1 ]; then
    VENV="$HERE/.venv-$PY_VERSION"
  else
    VENV="$HERE/.venv"
  fi
  PYTHON="$VENV/bin/python"
  if [ ! -x "$PYTHON" ]; then                   # first run: the environment does not exist yet
    echo "Creating a Python environment in $VENV ..."
    if [ "$HAVE_UV" = 1 ]; then
      # --managed-python: always use uv's own Python build (not e.g. Homebrew's), so every
      # machine runs the same build. "uv python install" downloads it if needed (does
      # nothing if it is already there). "+gil" then asks for the normal build: without
      # it uv may pick an installed free-threaded 3.14 for "3.14".
      # A version ending in "t" (3.14t) is the free-threaded build.
      case "$PY_VERSION" in
        *t) PY_REQUEST="$PY_VERSION" ;;
        *)  PY_REQUEST="$PY_VERSION+gil" ;;
      esac
      uv python install -q "$PY_VERSION"
      uv venv -q --managed-python --python "$PY_REQUEST" "$VENV"
    else
      python3 -m venv "$VENV"
    fi
  fi
fi
[ -x "$PYTHON" ] || { echo "Python not found at $PYTHON. Set PYTHON=/path/to/python"; exit 1; }

# Install packages into the environment of $PYTHON. uv environments have no pip
# inside them, so with uv we use "uv pip install --python ..." instead.
pip_install() {
  if [ "$HAVE_UV" = 1 ]; then
    uv pip install -q --python "$PYTHON" "$@"
  else
    "$PYTHON" -m pip install -q --disable-pip-version-check "$@"
  fi
}

# Install pygrametl into the environment only if "import pygrametl" fails
# (this is why the CPython programs do not need sys.path.append('/home/chr/code'))
if [ -z "$PYGRAMETL_PATH" ] && ! "$PYTHON" -c "import pygrametl" 2>/dev/null; then
  echo "Installing pygrametl 2.9 ..."
  pip_install "pygrametl==2.9"
fi
# PostgreSQL must be installed and running
command -v psql >/dev/null || { echo "psql not found. Install PostgreSQL: brew install postgresql@18 && brew services start postgresql@18"; exit 1; }
psql -h localhost -d postgres -Atc "select 1" >/dev/null 2>&1 || { echo "PostgreSQL is not running. Start it: brew services start postgresql@18"; exit 1; }

# psycopg2 is the PostgreSQL driver for CPython (the Jython programs use JDBC instead).
# "-binary" is the precompiled package, so no C compiler is needed.
if ! "$PYTHON" -c "import psycopg2" 2>/dev/null; then
  echo "Installing psycopg2-binary into $(dirname "$(dirname "$PYTHON")") ..."
  pip_install psycopg2-binary
fi

# ---------------------------------------------------------------- database
# The example programs connect to database "chr" as user "chr" (hard-coded by the
# original author), so we create them instead of editing the programs.
# Each check asks PostgreSQL's catalog whether it exists; "grep -q 1" is true if the query returned 1.
if ! psql -h localhost -d postgres -Atc "select 1 from pg_roles where rolname='chr'" | grep -q 1; then
  echo "Creating PostgreSQL role 'chr' ..."
  psql -h localhost -d postgres -qc "create role chr login"
fi
if ! psql -h localhost -d postgres -Atc "select 1 from pg_database where datname='chr'" | grep -q 1; then
  echo "Creating database 'chr' ..."
  psql -h localhost -d postgres -qc "create database chr owner chr"
fi

# ---------------------------------------------------------------- data
# The data generator (from the paper) writes two input files for the ETL programs:
#   DownloadLog.csv  one row per downloaded web page (used for the page dimension)
#   TestResults.csv  one row per test run on a page (becomes the facts)
# params.py decides how much data is generated; SIZE picks which params file to use.
# The data generator is Python 2 code, so it is run with Jython.
# Both scripts use the same run/ folder, so Jython and CPython load exactly the same files.
mkdir -p "$WORK"
cd "$WORK"
if [ "$SIZE" = small ]; then
  printf 'toplevels=2\ndomains=10\npages=20\nmonths=3\ntests=5\n' > params.py    # tiny set for quick tests
else
  [ -f "$HERE/datagenerator/params-$SIZE.py" ] || { echo "No such file: datagenerator/params-$SIZE.py"; exit 1; }
  cp "$HERE/datagenerator/params-$SIZE.py" params.py
fi
# Regenerate only if asked (REGEN=1), if there is no data yet, or if the size changed since last time.
# .params.used remembers which params.py the current CSV files were made with ("cmp -s" compares files).
if [ "${REGEN:-0}" = 1 ] || [ ! -f DownloadLog.csv ] || ! cmp -s params.py .params.used; then
  command -v java >/dev/null || { echo "Java is needed to generate data: brew install openjdk"; exit 1; }
  mkdir -p "$LIB"
  [ -f "$JYTHON_JAR" ] || { echo "Downloading Jython 2.7.4 (for the data generator) ..."; curl -fsSL -o "$JYTHON_JAR" "$MAVEN/org/python/jython-standalone/2.7.4/jython-standalone-2.7.4.jar"; }
  echo "Generating data (SIZE=$SIZE) ..."
  rm -f params.pyc 'params$py.class'            # delete compiled copies so the new params.py is used
  cp "$HERE/datagenerator/datagenerator.py" .
  java --enable-native-access=ALL-UNNAMED ${JAVA_OPTS:-} -cp "$JYTHON_JAR" org.python.util.jython datagenerator.py
  cp params.py .params.used
fi
# "wc -l" counts lines; minus 1 for the header line
DOWNLOADS=$(($(wc -l < DownloadLog.csv) - 1))
TESTS=$(($(wc -l < TestResults.csv) - 1))
echo "Input: $DOWNLOADS downloads, $TESTS test results  (SIZE=$SIZE)"

# ---------------------------------------------------------------- setup
# Record the exact Python version so results can be compared and reproduced later.
# It also notes a "free-threaded" build (Python without the GIL), since that would
# change how much the parallel program can gain.
# "(uv)" marks a Python installed by uv: it is built differently from e.g. Homebrew's
# Python, which can make a small difference in speed.
RUNTIME_VERSION="CPython $("$PYTHON" -c 'import sys; ft = hasattr(sys, "_is_gil_enabled") and not sys._is_gil_enabled(); print(sys.version.split()[0] + (" free-threaded" if ft else ""))')"
if grep -q '^uv = ' "$(dirname "$(dirname "$PYTHON")")/pyvenv.cfg" 2>/dev/null; then
  RUNTIME_VERSION="$RUNTIME_VERSION (uv)"
fi
echo "Runtime: $RUNTIME_VERSION"

# Load the measuring code shared with run_jython.sh (". file" = run it inside this script,
# so its functions become available here). Both scripts measure in exactly the same way.
. "$HERE/bench_common.sh"
collect_machine_info       # CPU, cores, RAM, OS, PostgreSQL version and settings
init_results_file          # create run/results.csv with its header if needed
init_cache_clearing        # only with CLEAR_CACHE=1: ask for the sudo password once

# ---------------------------------------------------------------- run
# run 1 -> pygrametl1_cpython.py (sequential), run 2 -> pygrametl2_cpython.py (parallel), each RUNS times
run() {
  local prog="pygrametl$1_cpython.py" i
  for i in $(seq 1 "$RUNS"); do
    echo
    echo "=== $prog  (run $i of $RUNS) ==="
    # Start every run from empty tables: starschema.sql drops and recreates the star schema
    # (as UNLOGGED tables if UNLOGGED=1; see reset_schema in bench_common.sh).
    reset_schema "$HERE/starschema.sql"
    clear_caches            # does nothing unless CLEAR_CACHE=1 (see bench_common.sh)

    # Run the ETL program with the .venv Python and measure it: wall-clock time, CPU time,
    # memory and disk I/O. Only the program itself is timed, not the setup above.
    # PYTHONPATH is only set when using a pygrametl checkout; otherwise it is empty and
    # pygrametl comes from the .venv.
    # The program's own messages go to run/last_run.log
    # Name for this run, used for the file with its slowest SQL statements (run/pg_statements/)
    MEASURE_LABEL="cpython_pygrametl$1_run$i"
    if ! measure last_run.log env PYTHONPATH="$PYGRAMETL_PATH" "$PYTHON" "$HERE/$prog"; then
      echo "$prog FAILED. Its output:"; cat last_run.log; exit 1
    fi
    DB_MB=$(db_size_mb)     # size of the loaded data warehouse
    count_results           # row counts, to check that every program loaded the same data
    print_result            # show the numbers on screen
    record_result cpython "pygrametl$1" "$i" "$RUNTIME_VERSION"   # append one row to results.csv
  done
}

# Decide what to run from the first argument
case "$WHICH" in
  1|2) run "$WHICH" ;;
  both) run 1; run 2 ;;
  *) echo "Usage: $0 [1|2|both]"; exit 1 ;;
esac

echo
echo "All runs are logged in $WORK/results.csv"
