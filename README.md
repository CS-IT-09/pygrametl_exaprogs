# pygrametl example programs: Jython vs. CPython

The example ETL programs from the paper *"Easy and Effective Parallel Programmable ETL"*
(C. Thomsen and T. B. Pedersen, DOLAP 2011), made runnable today on both **Jython**
(as in the paper) and **CPython 3**, with a small Python tool (`bench.py`) to time them.

The programs load test results for web pages into a small star schema in PostgreSQL
(`starschema.sql`): a slowly changing `page` dimension, a `test` and a `date` dimension,
and the fact table `testresults`.

## Contents

| File | What it is |
|---|---|
| `pygrametl1.py` | Original sequential program (Jython, JDBC) |
| `pygrametl2.py` | Original parallel program (Jython, JDBC): `ProcessSource`, `DecoupledDimension`, `DimensionPartitioner`, `DecoupledFactTable`, shared connection |
| `pygrametl1_cpython.py` | CPython 3 version of `pygrametl1.py` (psycopg2) |
| `pygrametl2_cpython.py` | CPython 3 version of `pygrametl2.py` (psycopg2) |
| `starschema.sql` | Creates the `pygrametlexa` schema and its tables |
| `datagenerator/` | Generates the input CSV files; `params-N.py` are the data set sizes |
| `bench.py` | Runs one ETL program on empty tables and measures wall-clock time, CPU time and PostgreSQL time (see [Measuring](#measuring-benchpy)) |
| `run_jython.sh`, `run_cpython.sh` | Old run scripts. Their setup part (downloads, Python environment, database, data) is still a useful reference; their measuring part is out of date, **do not use them for now** (they will be replaced by a short setup script) |
| `setup_pg_monitoring.sh` | One-time PostgreSQL setup for the old, more detailed measuring (no longer used by the scripts) |
| `requirements.txt` | Python packages for the CPython versions (installed automatically) |
| `results.md` | Summary of the benchmark results |
| `pdi-1-conn.ktr`, `pdi-2-conns.ktr` | The same ETL flow in Pentaho Data Integration, used for comparison in the paper |

The CPython versions only change the platform-specific lines (database driver, bulk loader,
`open()` instead of `file()`); they are marked with `# CPython:` in the code.

## Requirements (macOS)

```bash
brew install openjdk postgresql@18
brew services start postgresql@18
```

The project also needs Jython 2.7.4, the PostgreSQL JDBC driver and pygrametl 2.9 in `lib/`,
and a Python environment (`.venv-3.14t`) with pygrametl and psycopg2. These are not in git; the
old run scripts download and create them on their first run. `bench.py` itself only needs a
`python3` on the PATH (any version; macOS has one) and `psql`.

Only one PostgreSQL version may run at a time: if several Homebrew versions are started, they
compete for port 5432 and the benchmarks may silently use the wrong one (check with
`brew services list`).

Optional but recommended: [uv](https://docs.astral.sh/uv/) (`brew install uv`). If it is
installed, `run_cpython.sh` uses it to create `.venv-3.14t` with the same Python version on
every machine: by default the free-threaded build of 3.14 (no GIL); `PY_VERSION=3.14` gives the
normal build with the GIL in `.venv-3.14`. Without uv
it falls back to `python3 -m venv .venv` and pip.

The programs connect to `jdbc:postgresql://localhost/chr?user=chr` (hard-coded by the original
author), so PostgreSQL needs a user and a database called `chr` (once per computer):

```bash
psql -h localhost -d postgres -c "create role chr login"
psql -h localhost -d postgres -c "create database chr owner chr"
```

## Generating the data

The programs read two CSV files from the folder they are started in: `DownloadLog.csv` (one
row per downloaded web page, for the page dimension) and `TestResults.csv` (one row per test
run, the facts). They are made by the data generator from the paper. Its settings file decides
the size: `datagenerator/params-N.py` with N = 5, 25, 50 or 100 (more months = more rows).

All commands below are run inside `run/`. For example, for `params-5` (1 million downloads,
5 million test results):

```bash
cd run
cp ../datagenerator/params-5.py params.py          # choose the size
cp ../datagenerator/datagenerator.py .             # the generator must sit next to params.py
rm -f 'params$py.class'                            # delete Jython's compiled copy of the old settings
java --enable-native-access=ALL-UNNAMED -cp ../lib/jython-standalone-2.7.4.jar org.python.util.jython datagenerator.py
wc -l DownloadLog.csv TestResults.csv              # params-5: 1000001 and 5000001 lines (incl. header)
```

The generator uses a fixed random seed, so the same params file always gives the same data.

## Running

From inside `run/` (where the CSV files are). Each command runs one program once and prints its
measurements; `bench.py` empties the tables before the run by itself.

**1. Jython, sequential** (`pygrametl1.py`):

```bash
python3 ../bench.py env JYTHONPATH=../lib/pygrametl-2.9 java --enable-native-access=ALL-UNNAMED -cp ../lib/jython-standalone-2.7.4.jar:../lib/postgresql-42.7.4.jar org.python.util.jython ../pygrametl1.py
```

**2. Jython, parallel** (`pygrametl2.py`):

```bash
python3 ../bench.py env JYTHONPATH=../lib/pygrametl-2.9 java --enable-native-access=ALL-UNNAMED -cp ../lib/jython-standalone-2.7.4.jar:../lib/postgresql-42.7.4.jar org.python.util.jython ../pygrametl2.py
```

**3. CPython, sequential** (`pygrametl1_cpython.py`):

```bash
python3 ../bench.py "$(cd .. && pwd)/.venv-3.14t/bin/python" ../pygrametl1_cpython.py
```

**4. CPython, parallel** (`pygrametl2_cpython.py`):

```bash
python3 ../bench.py "$(cd .. && pwd)/.venv-3.14t/bin/python" ../pygrametl2_cpython.py
```

Everything after `python3 ../bench.py` is the command that is timed:

| Part | Meaning |
|---|---|
| `env JYTHONPATH=../lib/pygrametl-2.9` | where Jython finds the pygrametl library |
| `java ... org.python.util.jython` | start Java and the Jython interpreter in it |
| `--enable-native-access=ALL-UNNAMED` | only hides a warning of newer Java versions |
| `-cp jython.jar:postgresql.jar` | the classpath: Jython itself and the PostgreSQL JDBC driver |
| `"$(cd .. && pwd)/.venv-3.14t/bin/python"` | the CPython interpreter of the project's environment, as a full path (with `../.venv-3.14t/...` Python 3.14 prints a harmless `sys.prefix` warning) |
| `../pygrametl1.py` etc. | the ETL program |

So the Jython times include starting Java and Jython (a few seconds). The remaining
`sun.misc.Unsafe` warnings from Java are harmless.

**Expected result:** with `params-5` every program must load **599059 page versions and
5000000 facts**; `bench.py` prints these counts after each run. If a program loads different
numbers, its time is not comparable.

**Note on the GIL:** `.venv-3.14t` is the free-threaded Python 3.14 (no GIL), but psycopg2 is
not marked as safe without the GIL, so Python **switches the GIL back on** when the programs
import it (`RuntimeWarning: The global interpreter lock (GIL) has been enabled ...`). The CPython
programs therefore run *with* the GIL unless `PYTHON_GIL=0` is set (at your own risk). This also
applies to the earlier CPython results in `results.md`.

**For results you report:** close other apps (browser, IDE), keep the laptop plugged in, let it
cool down first, and do not use database `chr` from anywhere else during a run. On a busy
laptop the same program took between 238 s and 299 s.

## Measuring (`bench.py`)

`bench.py` is a short Python script that uses only the standard library and `psql`. It is
used as `python3 bench.py <command to time>` and does, in this order:

1. **Recreate the empty tables** by running `starschema.sql` with `psql` (`-v ON_ERROR_STOP=1`,
   so a failed reset stops `bench.py`). This is setup and is not part of any measurement.
2. **Read the counters before the run:** PostgreSQL's busy time and the CPU time used so far.
3. **Run the program** with `subprocess.run(cmd, check=True)`, which waits until it has
   finished. If the program fails, `bench.py` stops with an error and reports no time.
4. **Wait one second** and read the counters again (see below).
5. **Count the loaded rows** (`page` and `testresults`) as a check.
6. **Print** the results.

It measures three things:

| Output | What it is | How it is measured |
|---|---|---|
| `wall-clock time` | how long the program took, as on a clock | `time.perf_counter()` before and after the run |
| `user time`, `system time` | CPU time of the program and all processes and threads it starts: *user* = its own code (e.g. pygrametl, Jython), *system* = the operating system working for it (reading files, network) | `resource.getrusage(RUSAGE_CHILDREN)` before and after: the operating system's counters, the same source as `/usr/bin/time` |
| `PostgreSQL time` | time PostgreSQL spent executing SQL statements in database `chr` | the column `active_time` of PostgreSQL's view `pg_stat_database` before and after (built into PostgreSQL 14+, no extension needed) |

All three are "after minus before" differences of running totals, so anything before the
run (such as the table reset) is not counted. The one-second wait is needed because a
PostgreSQL connection reports its statistics when it closes, just after the program ends.

**How to read the numbers:**

- For a **sequential** program, which either computes or waits:
  `wall-clock ≈ (user + system) + PostgreSQL time + the rest`, where *the rest* is mainly the
  round trips between the program and PostgreSQL. Example, Jython sequential with `params-5`:
  146 s computing + 68 s PostgreSQL + 24 s rest = 238 s.
- For a **parallel** program, computing and waiting overlap, and `user + system` can be
  **larger** than the wall-clock time (e.g. 4 cores busy for 10 s = 40 s CPU). That shows
  it really ran in parallel.

**Limits:**

- `PostgreSQL time` counts every connection to database `chr`, so nothing else should use it
  during a run. It includes `bench.py`'s own readings (a few milliseconds).
- `PostgreSQL time` is how long statements ran, not PostgreSQL's CPU time: a statement
  waiting for the disk also counts.
- The CPU time does not include PostgreSQL, which is a separate server process.

Older results from the previous, more detailed measuring tool are in `run/results.csv` and
`run/results-old-*.csv`.


## Credits and license

`pygrametl1.py`, `pygrametl2.py`, `datagenerator/`, `starschema.sql` and the `.ktr` files are the
example programs by Christian Thomsen from the [pygrametl](https://github.com/chrthomsen/pygrametl)
repository. `pygrametl2.py` and the data generator are licensed under the GNU General Public
License version 2; the CPython versions are derived from them. pygrametl itself is BSD-licensed.
