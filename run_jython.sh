#!/usr/bin/env bash
# Runs the original pygrametl example programs (pygrametl1.py / pygrametl2.py)
# with Jython + JDBC + PostgreSQL, exactly as written in the paper.
#
# Usage (from anywhere):
#   ./run_jython.sh 1        # sequential version
#   ./run_jython.sh 2        # parallel version
#   ./run_jython.sh both     # run both and compare
#
# Optional environment variables:
#   SIZE=small (default) | 5 | 25 | 50 | 100   dataset size (numbers = datagenerator/params-N.py)
#   REGEN=1                                     regenerate the CSV files even if they exist
#   RUNS=3                                      run each program N times (default 1)
#
# Examples:
#   SIZE=5 ./run_jython.sh both          # paper's params-5 data set, both programs
#   SIZE=5 RUNS=3 ./run_jython.sh 2      # parallel version three times
#
# Every run is appended to run/results.csv (shared with run_cpython.sh).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"          # .../pygrametl/exaprogs
REPO="$(dirname "$HERE")"                       # parent folder (a pygrametl checkout, if exaprogs sits in one)
LIB="${LIB:-$HERE/lib}"
WORK="$HERE/run"
SIZE="${SIZE:-small}"
RUNS="${RUNS:-1}"
WHICH="${1:-both}"

JYTHON_JAR="${JYTHON_JAR:-$LIB/jython-standalone-2.7.4.jar}"
PG_JAR="${PG_JAR:-$LIB/postgresql-42.7.4.jar}"
MAVEN=https://repo1.maven.org/maven2

# ---------------------------------------------------------------- prerequisites
command -v java >/dev/null || { echo "Java not found. Install it: brew install openjdk (then follow brew's PATH hint)"; exit 1; }
command -v psql >/dev/null || { echo "psql not found. Install PostgreSQL: brew install postgresql@16 && brew services start postgresql@16"; exit 1; }

mkdir -p "$LIB" "$WORK"
[ -f "$JYTHON_JAR" ] || { echo "Downloading Jython 2.7.4 ..."; curl -fsSL -o "$JYTHON_JAR" "$MAVEN/org/python/jython-standalone/2.7.4/jython-standalone-2.7.4.jar"; }
[ -f "$PG_JAR" ]     || { echo "Downloading PostgreSQL JDBC driver ..."; curl -fsSL -o "$PG_JAR" "$MAVEN/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar"; }

# pygrametl source code for Jython: use the pygrametl checkout this folder sits in (if any),
# otherwise download pygrametl 2.9 from PyPI into lib/. PYGRAMETL_SRC=... overrides both.
if [ -z "${PYGRAMETL_SRC:-}" ]; then
  if [ -f "$REPO/pygrametl/__init__.py" ]; then
    PYGRAMETL_SRC="$REPO"
  else
    PYGRAMETL_SRC="$LIB/pygrametl-2.9"
    if [ ! -f "$PYGRAMETL_SRC/pygrametl/__init__.py" ]; then
      echo "Downloading pygrametl 2.9 ..."
      python3 -m pip download -q --disable-pip-version-check --no-deps -d "$LIB" pygrametl==2.9
      unzip -q -o "$LIB/pygrametl-2.9-py3-none-any.whl" -d "$PYGRAMETL_SRC"
    fi
  fi
fi

# Jython runs on the JVM; pygrametl is found through JYTHONPATH, the JDBC driver through the classpath.
jython() { JYTHONPATH="$PYGRAMETL_SRC" java --enable-native-access=ALL-UNNAMED ${JAVA_OPTS:-} -cp "$JYTHON_JAR:$PG_JAR" org.python.util.jython "$@"; }

# ---------------------------------------------------------------- database
# The example programs hard-code jdbc:postgresql://localhost/chr?user=chr,
# so we create a role and a database called "chr" instead of editing them.
if ! psql -h localhost -d postgres -Atc "select 1 from pg_roles where rolname='chr'" | grep -q 1; then
  echo "Creating PostgreSQL role 'chr' ..."
  psql -h localhost -d postgres -qc "create role chr login"
fi
if ! psql -h localhost -d postgres -Atc "select 1 from pg_database where datname='chr'" | grep -q 1; then
  echo "Creating database 'chr' ..."
  psql -h localhost -d postgres -qc "create database chr owner chr"
fi

# ---------------------------------------------------------------- data
cd "$WORK"
if [ "$SIZE" = small ]; then
  printf 'toplevels=2\ndomains=10\npages=20\nmonths=3\ntests=5\n' > params.py
else
  cp "$HERE/datagenerator/params-$SIZE.py" params.py
fi
if [ "${REGEN:-0}" = 1 ] || [ ! -f DownloadLog.csv ] || ! cmp -s params.py .params.used; then
  echo "Generating data (SIZE=$SIZE) ..."
  rm -f params.pyc params\$py.class
  # Run the generator from the work dir so that it picks up params.py there
  cp "$HERE/datagenerator/datagenerator.py" .
  jython datagenerator.py
  cp params.py .params.used
fi
echo "Input: $(($(wc -l < DownloadLog.csv) - 1)) downloads, $(($(wc -l < TestResults.csv) - 1)) test results  (SIZE=$SIZE)"

[ -f results.csv ] || echo "timestamp,runtime,program,size,run,real_s,user_s,sys_s,page_versions,facts,total_errors" > results.csv

# ---------------------------------------------------------------- run
run() {
  local prog="pygrametl$1.py" i
  for i in $(seq 1 "$RUNS"); do
    echo
    echo "=== $prog  (run $i of $RUNS) ==="
    psql -q -h localhost -U chr -d chr -f "$HERE/starschema.sql" 2>&1 | grep -v -e NOTICE -e DETAIL -e '^drop cascades' || true

    # Time the program: wall-clock (real) and CPU time (user + sys).
    # The program's own messages go to run/last_run.log; the timing to run/.time
    local TIMEFORMAT='%R %U %S'
    if ! { time jython "$HERE/$prog" >last_run.log 2>&1 ; } 2>.time; then
      echo "$prog FAILED. Its output:"; cat last_run.log; exit 1
    fi
    read -r real user sys < .time

    local counts
    counts=$(psql -h localhost -U chr -d chr -Atc "set search_path to pygrametlexa;
      select (select count(*) from page), (select count(*) from testresults), (select sum(errors) from testresults);" | tail -1)
    IFS='|' read -r pages facts errors <<< "$counts"

    echo "Finished: real ${real}s   CPU ${user}s user + ${sys}s sys"
    echo "Result:   $pages page versions, $facts facts, $errors total errors"
    echo "$(date '+%Y-%m-%d %H:%M:%S'),jython,pygrametl$1,$SIZE,$i,$real,$user,$sys,$pages,$facts,$errors" >> results.csv
  done
}

case "$WHICH" in
  1|2) run "$WHICH" ;;
  both) run 1; run 2 ;;
  *) echo "Usage: $0 [1|2|both]"; exit 1 ;;
esac

echo
echo "All runs are logged in $WORK/results.csv"
