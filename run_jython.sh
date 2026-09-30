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
#   CLEAR_CACHE=1                               restart PostgreSQL and clear the OS file cache
#                                               before every run (asks for your password once)
#
# Examples:
#   SIZE=5 ./run_jython.sh both          # paper's params-5 data set, both programs
#   SIZE=5 RUNS=3 ./run_jython.sh 2      # parallel version three times
#
# Every run is appended to run/results.csv (shared with run_cpython.sh) with its time,
# memory, disk I/O, row counts and a description of the machine and PostgreSQL settings.
#
# Overview of what the script does, in order:
#   1. prerequisites  check Java/psql, download Jython, the JDBC driver and pygrametl if missing
#   2. database       make sure the PostgreSQL user and database "chr" exist
#   3. data           generate the input CSV files (only when the size changed or REGEN=1)
#   4. setup          record Jython/Java versions, load the shared measuring code
#   5. run            for each run: recreate the tables, (clear caches), run + measure, save a row

# Stop at the first error (-e), treat unset variables as errors (-u),
# and let a pipeline fail if any command in it fails (-o pipefail).
set -euo pipefail

# ---------------------------------------------------------------- settings
# "${VAR:-default}" means: use $VAR if it is set, otherwise the default.
# That is how SIZE=5 RUNS=7 ./run_jython.sh overrides the defaults.
HERE="$(cd "$(dirname "$0")" && pwd)"          # .../pygrametl/exaprogs (the folder of this script)
REPO="$(dirname "$HERE")"                       # parent folder (a pygrametl checkout, if exaprogs sits in one)
LIB="${LIB:-$HERE/lib}"                         # downloaded .jar files and pygrametl go here
WORK="$HERE/run"                                # generated data, logs and results.csv go here
SIZE="${SIZE:-small}"
RUNS="${RUNS:-1}"
WHICH="${1:-both}"                              # first command-line argument: 1, 2 or both

# Jython is a Python 2.7 implementation written in Java, shipped as one .jar file.
# The PostgreSQL JDBC driver is the Java library the programs use to talk to the database.
JYTHON_JAR="${JYTHON_JAR:-$LIB/jython-standalone-2.7.4.jar}"
PG_JAR="${PG_JAR:-$LIB/postgresql-42.7.4.jar}"
MAVEN=https://repo1.maven.org/maven2            # central download site for Java libraries

# ---------------------------------------------------------------- prerequisites
# "command -v X" checks that program X is installed; "|| { ...; exit 1; }" stops with a hint if not.
command -v java >/dev/null || { echo "Java not found. Install it: brew install openjdk (then follow brew's PATH hint)"; exit 1; }
command -v psql >/dev/null || { echo "psql not found. Install PostgreSQL: brew install postgresql@16 && brew services start postgresql@16"; exit 1; }

# Download the two .jar files only the first time ("[ -f file ] ||" = only if the file is missing)
mkdir -p "$LIB" "$WORK"
[ -f "$JYTHON_JAR" ] || { echo "Downloading Jython 2.7.4 ..."; curl -fsSL -o "$JYTHON_JAR" "$MAVEN/org/python/jython-standalone/2.7.4/jython-standalone-2.7.4.jar"; }
[ -f "$PG_JAR" ]     || { echo "Downloading PostgreSQL JDBC driver ..."; curl -fsSL -o "$PG_JAR" "$MAVEN/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar"; }

# pygrametl source code for Jython: use the pygrametl checkout this folder sits in (if any),
# otherwise download pygrametl 2.9 from PyPI into lib/. PYGRAMETL_SRC=... overrides both.
# Jython cannot use pip packages installed for CPython, so it gets its own plain copy of
# the source code: a .whl file is just a zip archive, so "unzip" extracts the .py files.
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
# The full command, piece by piece:
#   env JYTHONPATH=...               where "import pygrametl" looks (replaces sys.path.append('/home/chr/code'))
#   java                             start the Java virtual machine
#   --enable-native-access=...       silences a warning from newer Java versions
#   ${JAVA_OPTS:-}                   optional extra Java options, e.g. JAVA_OPTS=-Xmx4g for more memory
#   -cp "jython.jar:postgresql.jar"  the classpath: where Java finds Jython and the JDBC driver
#   org.python.util.jython           the Java class that starts the Jython interpreter
# It is stored in an array so that it can be run directly and also passed to measure() below.
JYTHON_CMD=(env JYTHONPATH="$PYGRAMETL_SRC" java --enable-native-access=ALL-UNNAMED ${JAVA_OPTS:-} -cp "$JYTHON_JAR:$PG_JAR" org.python.util.jython)
jython() { "${JYTHON_CMD[@]}" "$@"; }          # so we can simply write: jython file.py

# ---------------------------------------------------------------- database
# The example programs hard-code jdbc:postgresql://localhost/chr?user=chr,
# so we create a role and a database called "chr" instead of editing them.
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
cd "$WORK"
if [ "$SIZE" = small ]; then
  printf 'toplevels=2\ndomains=10\npages=20\nmonths=3\ntests=5\n' > params.py    # tiny set for quick tests
else
  cp "$HERE/datagenerator/params-$SIZE.py" params.py
fi
# Regenerate only if asked (REGEN=1), if there is no data yet, or if the size changed since last time.
# .params.used remembers which params.py the current CSV files were made with ("cmp -s" compares files).
if [ "${REGEN:-0}" = 1 ] || [ ! -f DownloadLog.csv ] || ! cmp -s params.py .params.used; then
  echo "Generating data (SIZE=$SIZE) ..."
  rm -f params.pyc params\$py.class              # delete compiled copies so the new params.py is used
  # Run the generator from the work dir so that it picks up params.py there
  cp "$HERE/datagenerator/datagenerator.py" .
  jython datagenerator.py
  cp params.py .params.used
fi
# "wc -l" counts lines; minus 1 for the header line
echo "Input: $(($(wc -l < DownloadLog.csv) - 1)) downloads, $(($(wc -l < TestResults.csv) - 1)) test results  (SIZE=$SIZE)"

# ---------------------------------------------------------------- setup
# Record exact versions so results can be compared and reproduced later
JAVA_VERSION=$(java -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')
RUNTIME_VERSION="Jython $(jython -c 'import sys; print(sys.version.split()[0])' 2>/dev/null | tail -1) on Java $JAVA_VERSION"
echo "Runtime: $RUNTIME_VERSION"

# Load the measuring code shared with run_cpython.sh (". file" = run it inside this script,
# so its functions become available here). Both scripts measure in exactly the same way.
. "$HERE/bench_common.sh"
collect_machine_info       # CPU, cores, RAM, OS, PostgreSQL version and settings
init_results_file          # create run/results.csv with its header if needed
init_cache_clearing        # only with CLEAR_CACHE=1: ask for the sudo password once

# ---------------------------------------------------------------- run
# run 1 -> pygrametl1.py (sequential), run 2 -> pygrametl2.py (parallel), each RUNS times
run() {
  local prog="pygrametl$1.py" i
  for i in $(seq 1 "$RUNS"); do
    echo
    echo "=== $prog  (run $i of $RUNS) ==="
    # Start every run from empty tables: starschema.sql drops and recreates the star schema.
    # The grep hides PostgreSQL's harmless "table does not exist, skipping" style notices.
    psql -q -h localhost -U chr -d chr -f "$HERE/starschema.sql" 2>&1 | grep -v -e NOTICE -e DETAIL -e '^drop cascades' || true
    clear_caches            # does nothing unless CLEAR_CACHE=1 (see bench_common.sh)

    # Run the ETL program and measure it: wall-clock time, CPU time, memory and disk I/O.
    # Only the program itself is timed, not the table setup or cache clearing above.
    # The program's own messages (incl. Java warnings) go to run/last_run.log
    if ! measure last_run.log "${JYTHON_CMD[@]}" "$HERE/$prog"; then
      echo "$prog FAILED. Its output:"; cat last_run.log; exit 1
    fi
    DB_MB=$(db_size_mb)     # size of the loaded data warehouse
    count_results           # row counts, to check that every program loaded the same data
    print_result            # show the numbers on screen
    record_result jython "pygrametl$1" "$i" "$RUNTIME_VERSION"    # append one row to results.csv
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
