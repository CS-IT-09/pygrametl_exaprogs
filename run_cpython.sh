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
#
# Examples:
#   SIZE=5 ./run_cpython.sh both          # paper's params-5 data set, both programs
#   SIZE=5 RUNS=3 ./run_cpython.sh 2      # parallel version three times
#
# Every run is appended to run/results.csv so you can compare timings later.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"          # .../pygrametl/exaprogs
REPO="$(dirname "$HERE")"                       # parent folder (a pygrametl checkout, if exaprogs sits in one)
LIB="$HERE/lib"
WORK="$HERE/run"
SIZE="${SIZE:-small}"
RUNS="${RUNS:-1}"
WHICH="${1:-both}"

JYTHON_JAR="${JYTHON_JAR:-$LIB/jython-standalone-2.7.4.jar}"
MAVEN=https://repo1.maven.org/maven2

# ---------------------------------------------------------------- prerequisites
# Python + pygrametl:
#  - inside a pygrametl checkout: use its .venv and its pygrametl source code
#  - standalone: use (or create) exaprogs/.venv with the packages in requirements.txt
#  - PYTHON=/path/to/python overrides the interpreter
PYGRAMETL_PATH=""
if [ -f "$REPO/pygrametl/__init__.py" ]; then
  PYGRAMETL_PATH="$REPO"
  PYTHON="${PYTHON:-$REPO/.venv/bin/python}"
fi
if [ -z "${PYTHON:-}" ]; then
  PYTHON="$HERE/.venv/bin/python"
  if [ ! -x "$PYTHON" ]; then
    echo "Creating a Python environment in $HERE/.venv ..."
    python3 -m venv "$HERE/.venv"
  fi
fi
[ -x "$PYTHON" ] || { echo "Python not found at $PYTHON. Set PYTHON=/path/to/python"; exit 1; }
if [ -z "$PYGRAMETL_PATH" ] && ! "$PYTHON" -c "import pygrametl" 2>/dev/null; then
  echo "Installing pygrametl 2.9 ..."
  "$PYTHON" -m pip install -q --disable-pip-version-check "pygrametl==2.9"
fi
command -v psql >/dev/null || { echo "psql not found. Install PostgreSQL: brew install postgresql@18 && brew services start postgresql@18"; exit 1; }
psql -h localhost -d postgres -Atc "select 1" >/dev/null 2>&1 || { echo "PostgreSQL is not running. Start it: brew services start postgresql@18"; exit 1; }

if ! "$PYTHON" -c "import psycopg2" 2>/dev/null; then
  echo "Installing psycopg2-binary into $(dirname "$(dirname "$PYTHON")") ..."
  "$PYTHON" -m pip install -q --disable-pip-version-check psycopg2-binary
fi

# The example programs connect to database "chr" as user "chr"
if ! psql -h localhost -d postgres -Atc "select 1 from pg_roles where rolname='chr'" | grep -q 1; then
  echo "Creating PostgreSQL role 'chr' ..."
  psql -h localhost -d postgres -qc "create role chr login"
fi
if ! psql -h localhost -d postgres -Atc "select 1 from pg_database where datname='chr'" | grep -q 1; then
  echo "Creating database 'chr' ..."
  psql -h localhost -d postgres -qc "create database chr owner chr"
fi

# ---------------------------------------------------------------- data
# The data generator is Python 2 code, so it is run with Jython.
mkdir -p "$WORK"
cd "$WORK"
if [ "$SIZE" = small ]; then
  printf 'toplevels=2\ndomains=10\npages=20\nmonths=3\ntests=5\n' > params.py
else
  [ -f "$HERE/datagenerator/params-$SIZE.py" ] || { echo "No such file: datagenerator/params-$SIZE.py"; exit 1; }
  cp "$HERE/datagenerator/params-$SIZE.py" params.py
fi
if [ "${REGEN:-0}" = 1 ] || [ ! -f DownloadLog.csv ] || ! cmp -s params.py .params.used; then
  command -v java >/dev/null || { echo "Java is needed to generate data: brew install openjdk"; exit 1; }
  mkdir -p "$LIB"
  [ -f "$JYTHON_JAR" ] || { echo "Downloading Jython 2.7.4 (for the data generator) ..."; curl -fsSL -o "$JYTHON_JAR" "$MAVEN/org/python/jython-standalone/2.7.4/jython-standalone-2.7.4.jar"; }
  echo "Generating data (SIZE=$SIZE) ..."
  rm -f params.pyc 'params$py.class'
  cp "$HERE/datagenerator/datagenerator.py" .
  java --enable-native-access=ALL-UNNAMED ${JAVA_OPTS:-} -cp "$JYTHON_JAR" org.python.util.jython datagenerator.py
  cp params.py .params.used
fi
DOWNLOADS=$(($(wc -l < DownloadLog.csv) - 1))
TESTS=$(($(wc -l < TestResults.csv) - 1))
echo "Input: $DOWNLOADS downloads, $TESTS test results  (SIZE=$SIZE)"
echo "Python: $("$PYTHON" --version 2>&1)"

[ -f results.csv ] || echo "timestamp,runtime,program,size,run,real_s,user_s,sys_s,page_versions,facts,total_errors" > results.csv

# ---------------------------------------------------------------- run
run() {
  local prog="pygrametl$1_cpython.py" i
  for i in $(seq 1 "$RUNS"); do
    echo
    echo "=== $prog  (run $i of $RUNS) ==="
    psql -q -h localhost -U chr -d chr -f "$HERE/starschema.sql" 2>&1 | grep -v -e NOTICE -e DETAIL -e '^drop cascades' || true

    # Time the program: wall-clock (real) and CPU time (user + sys).
    # The program's own messages go to run/last_run.log; the timing to run/.time
    local TIMEFORMAT='%R %U %S'
    if ! { time PYTHONPATH="$PYGRAMETL_PATH" "$PYTHON" "$HERE/$prog" >last_run.log 2>&1 ; } 2>.time; then
      echo "$prog FAILED. Its output:"; cat last_run.log; exit 1
    fi
    read -r real user sys < .time

    local counts
    counts=$(psql -h localhost -U chr -d chr -Atc "set search_path to pygrametlexa;
      select (select count(*) from page), (select count(*) from testresults), (select sum(errors) from testresults);" | tail -1)
    IFS='|' read -r pages facts errors <<< "$counts"

    echo "Finished: real ${real}s   CPU ${user}s user + ${sys}s sys"
    echo "Result:   $pages page versions, $facts facts, $errors total errors"
    echo "$(date '+%Y-%m-%d %H:%M:%S'),cpython,pygrametl$1,$SIZE,$i,$real,$user,$sys,$pages,$facts,$errors" >> results.csv
  done
}

case "$WHICH" in
  1|2) run "$WHICH" ;;
  both) run 1; run 2 ;;
  *) echo "Usage: $0 [1|2|both]"; exit 1 ;;
esac

echo
echo "All runs are logged in $WORK/results.csv"
