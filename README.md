# pygrametl example programs: Jython vs. CPython

The example ETL programs from the paper *"Easy and Effective Parallel Programmable ETL"*
(C. Thomsen and T. B. Pedersen, DOLAP 2011), made runnable today on both **Jython**
(as in the paper) and **CPython 3**, with scripts to run and time them.

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
| `run_jython.sh` | Runs and measures the Jython programs |
| `run_cpython.sh` | Runs and measures the CPython programs |
| `bench_common.sh` | Measuring code shared by both run scripts (sourced, not run directly): timing, memory, PostgreSQL monitoring, cache clearing, `results.csv` |
| `setup_pg_monitoring.sh` | One-time PostgreSQL setup for SQL statement and disk I/O times (optional) |
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

Everything else is downloaded by the scripts on first use: Jython 2.7.4, the PostgreSQL JDBC
driver, pygrametl 2.9 and psycopg2. The measuring code also needs a `python3` on the PATH
(any version; macOS has one).

Only one PostgreSQL version may run at a time: if several Homebrew versions are started, they
compete for port 5432 and the benchmarks may silently use the wrong one (check with
`brew services list`; the version is recorded in `results.csv`).

Optional but recommended: [uv](https://docs.astral.sh/uv/) (`brew install uv`). If it is
installed, `run_cpython.sh` uses it to create `.venv-3.14t` with the same Python version on
every machine: by default the free-threaded build of 3.14 (no GIL); `PY_VERSION=3.14` gives the
normal build with the GIL in `.venv-3.14`. Without uv
it falls back to `python3 -m venv .venv` and pip.

The programs connect to `jdbc:postgresql://localhost/chr?user=chr` (hard-coded by the original
author), so the scripts create a PostgreSQL user and database called `chr` if they are missing.

## Running

```bash
chmod +x run_jython.sh run_cpython.sh setup_pg_monitoring.sh    # once

./run_jython.sh both                     # Jython: sequential + parallel
./run_cpython.sh both                    # CPython: sequential + parallel
```

The first argument picks the program: `1` (sequential), `2` (parallel) or `both` (default).

Options (environment variables, put them before the command):

| Variable | Meaning | Default |
|---|---|---|
| `SIZE` | `small`, or `5`, `25`, `50`, `100` for `datagenerator/params-N.py` | `small` |
| `RUNS` | how many times to run each program | `1` |
| `REGEN` | `1` = regenerate the CSV files | `0` |
| `CLEAR_CACHE` | `1` = restart PostgreSQL and clear the OS file cache before every run ("cold" runs; asks for your password once) | `0` |
| `PG_MONITOR` | `0` = don't monitor PostgreSQL during the runs | `1` |
| `UNLOGGED` | `1` = create the tables as UNLOGGED (PostgreSQL writes no WAL for them); recorded as `unlogged_tables=on` in `pg_settings` | `0` |
| `PY_VERSION` | CPython version when uv is used, e.g. `3.14` (normal build with GIL), `3.13`; a `t` at the end means free-threaded | `3.14t` |
| `PYTHON` | CPython interpreter to use instead of the `.venv` one | |
| `JAVA_OPTS` | extra Java options for Jython, e.g. `-Xmx5g` (more memory); recorded in `runtime_version` | |
| `PG_RESTART_CMD` | command to restart PostgreSQL for `CLEAR_CACHE=1`, if not a Homebrew service or `systemctl` | |
| `TIMER_PYTHON` | `python3` used by the measuring code | `python3` on the PATH |

Example: the paper's smallest data set (1 million downloads, 5 million facts), seven runs each:

```bash
SIZE=5 RUNS=7 ./run_jython.sh both
SIZE=5 RUNS=7 ./run_cpython.sh both
SIZE=5 RUNS=7 CLEAR_CACHE=1 ./run_cpython.sh both    # cold runs
SIZE=5 RUNS=7 PY_VERSION=3.14 ./run_cpython.sh 2     # parallel version on the normal (GIL) Python
```

Before every run the tables are dropped and recreated (`starschema.sql`), so all runs start
from an empty data warehouse. Only the ETL program itself is timed.

With the default `small` data set, the expected result is 801 page versions, 6000 facts
and 33385 total errors; with `SIZE=5` it is 599059 page versions, 5000000 facts and 26862851
total errors. The row counts must be identical for all four programs on the same data set.

## Measurements

Every run prints a summary and is appended as one row to `run/results.csv` (shared by both
scripts; runs from one script invocation share a `run_id`). The columns are:

| Group | Columns |
|---|---|
| Run | `timestamp`, `run_id`, `runtime` (jython/cpython), `program`, `size`, `run` |
| Time | `real_s` (wall-clock), `user_s`, `sys_s` (CPU time of the ETL program and all its processes) |
| Memory | `peak_rss_total_mb` (all processes together), `max_rss_single_mb` (largest single process) |
| Disk | `fs_reads`, `fs_writes` (block I/O operations; often 0 on macOS), `db_size_mb` (size of the loaded tables) |
| Check | `page_versions`, `facts`, `total_errors` |
| Database connection, sampled about once per second | `pg_busy_pct` (working), split into `pg_cpu_pct`, `pg_io_pct` (waiting for disk), `pg_lock_pct`, `pg_other_pct`; `pg_waiting_for_etl_pct` (idle, waiting for the ETL program) |
| PostgreSQL work | `pg_cpu_s` (CPU time of all PostgreSQL processes), `pg_stmt_time_s`, `pg_stmt_calls` (SQL statements), `pg_io_time_s` (time reading/writing data files), `pg_wal_mb` (WAL written), `pg_checkpoints`, `pg_checkpoints_forced`, `pg_cache_hit_pct`, `pg_blocks_read` |
| Setup | `cache_cleared`, `host`, `os`, `cpu`, `cores`, `ram_gb`, `runtime_version` (e.g. `CPython 3.14.7 free-threaded (uv)`), `postgres_version`, `pg_settings` (main PostgreSQL settings) |

Values that cannot be measured are written as `NA`. If the columns change in a new version
of the scripts, the old file is renamed to `run/results-old-<date>.csv`.

`pg_stmt_time_s`, `pg_stmt_calls` and `pg_io_time_s` need a one-time PostgreSQL setup
(it enables the `pg_stat_statements` extension and `track_io_timing`, and restarts PostgreSQL):

```bash
./setup_pg_monitoring.sh           # once
./setup_pg_monitoring.sh --undo    # back to the previous configuration
```

With it, the 15 slowest SQL statements of every run are also saved in
`run/pg_statements/<run_id>_<runtime>_<program>_run<N>.txt`.

Other files in `run/`: the generated `DownloadLog.csv` and `TestResults.csv`, and
`last_run.log` with the output of the last program run (look here if a run fails).


## Credits and license

`pygrametl1.py`, `pygrametl2.py`, `datagenerator/`, `starschema.sql` and the `.ktr` files are the
example programs by Christian Thomsen from the [pygrametl](https://github.com/chrthomsen/pygrametl)
repository. `pygrametl2.py` and the data generator are licensed under the GNU General Public
License version 2; the CPython versions are derived from them. pygrametl itself is BSD-licensed.
