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
# Every run is measured by bench.py (wall-clock time, CPU time, PostgreSQL busy time)
# and appended to run/results_simple.csv, which is shared with the other run script.
#
# Overview of what the script does, in order:
#   1. prerequisites  check Java/psql, download Jython, the JDBC driver and pygrametl if missing
#   2. database       make sure the PostgreSQL user and database "chr" exist
#   3. data           generate the input CSV files (only when the size changed or REGEN=1)
#   4. setup          record the runtime version
#   5. run            run bench.py, which recreates the tables and measures each run

# Stop at the first error (-e), treat unset variables as errors (-u),
# and let a pipeline fail if any command in it fails (-o pipefail).
set -euo pipefail

# ---------------------------------------------------------------- settings
# "${VAR:-default}" means: use $VAR if it is set, otherwise the default.
# That is how SIZE=5 RUNS=7 ./run_jython.sh overrides the defaults.
HERE="$(cd "$(dirname "$0")" && pwd)"          # .../pygrametl/exaprogs (the folder of this script)
REPO="$(dirname "$HERE")"                       # parent folder (a pygrametl checkout, if exaprogs sits in one)
LIB="${LIB:-$HERE/lib}"                         # downloaded .jar files and pygrametl go here
WORK="$HERE/run"                                # generated data, logs and results_simple.csv go here
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
command -v psql >/dev/null || { echo "psql not found. Install PostgreSQL: brew install postgresql@18 && brew services start postgresql@18"; exit 1; }

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
# It is stored in an array so that it can be run directly and also passed to bench.py below.
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
# Java options such as -Xmx (maximum memory) can change the timing, so they are recorded too
[ -z "${JAVA_OPTS:-}" ] || RUNTIME_VERSION="$RUNTIME_VERSION ($JAVA_OPTS)"
echo "Runtime: $RUNTIME_VERSION"

# ---------------------------------------------------------------- run
# Measure with bench.py: it recreates the empty tables before every run, runs the program
# RUNS times and records wall-clock time, CPU time and PostgreSQL busy time.
# The program's own messages (incl. Java warnings) go to run/last_run.log
run() {
  python3 "$HERE/bench.py" --name "jython-pygrametl$1" --runs "$RUNS" --runtime "$RUNTIME_VERSION" \
    --workdir "$WORK" -- "${JYTHON_CMD[@]}" "$HERE/pygrametl$1.py"
}

# Decide what to run from the first argument
case "$WHICH" in
  1|2) run "$WHICH" ;;
  both) run 1; run 2 ;;
  *) echo "Usage: $0 [1|2|both]"; exit 1 ;;
esac

echo
echo "All runs are logged in $WORK/results_simple.csv"
