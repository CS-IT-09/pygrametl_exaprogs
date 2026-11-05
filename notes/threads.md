# pygrametl parallel ETL: sequential vs multiprocessing vs threads (modified pygrametl)

Benchmarks of pygrametl's example ETL program (from the 2011 paper *Easy and Effective
Parallel Programmable ETL*) on CPython 3.14 (free-threaded build) with PostgreSQL. It compares:

- the **sequential** program,
- pygrametl's existing **multiprocessing** parallel program,
- a **multithreaded** version, made by modifying pygrametl itself.

## 1. Machine

| Item | Value |
|---|---|
| CPU | Intel Core i7-1185G7 @ 3.00 GHz (11th gen), 4 cores / 8 threads, 1 socket |
| RAM | 7.6 GiB (7,784 MiB) available to WSL2, plus 2 GiB swap |
| OS | Ubuntu 24.04 under WSL2 (kernel 6.6.87.2-microsoft-standard-WSL2) |
| Disk | WSL2 virtual disk, 1 TB (about 930 GB free) |
| PostgreSQL | 16.15 (Ubuntu package), default configuration unless stated |
| Python | 3.14.7 free-threaded build, in `.venv314t-threads` (created with `uv`; confirm with `python --version`) |
| pygrametl | 2.9 source (repository commit `35cf1c4`) plus the thread-mode changes, installed editable |
| Database driver | psycopg2, built from source (no binary wheel exists for the free-threaded build) |
| Data | The paper's SIZE=5 dataset: 1,000,000 downloads, 5,000,000 test results (made with the paper's generator under Jython 2.7.4 / OpenJDK 21) |

**Correct result for every run:** 599,059 page versions, 5,000,000 facts, total errors 26,862,851.

## 2. Sequential vs multiprocessing vs threads

All three ran in `.venv314t-threads`, with `-X gil=0` (GIL off), 3 runs each, on the default
PostgreSQL configuration. The sequential program was measured at the start and at the end of
the session. Means of 3 runs; CPU is user + system; "cores busy" is CPU divided by wall-clock.

| Version | Wall (s) | Wall range | User (s) | Sys (s) | CPU (s) | PostgreSQL (s) | Cores busy |
|---|---|---|---|---|---|---|---|
| Sequential (first block) | 218.7 | 217.2–220.6 | 88.4 | 28.5 | 116.9 | 51.4 | 0.53 |
| Multiprocessing | 262.0 | 259.6–263.3 | 308.5 | 82.8 | 391.3 | 71.1 | 1.49 |
| **Threads (modified pygrametl)** | **212.6** | 209.9–214.3 | 199.8 | 58.9 | 258.8 | 64.5 | 1.22 |
| Sequential (last block) | 214.6 | 212.8–217.6 | 87.6 | 28.1 | 115.7 | 50.2 | 0.54 |

- **Multiprocessing is 20 to 22% slower than sequential**, with 3.4 times the CPU.
- **Threads are 19% faster than multiprocessing** and use 34% less CPU.
- **Threads only slightly beat sequential:** 1.9% faster than the two sequential blocks together (216.6 s), at 2.2 times the CPU. Across all six blocks in sections 6 and 7 they were 0.1 to 4.9% faster, about 3% on average. That is a small gain, not a real speedup.
- **The session was stable:** the first and last sequential blocks differ by 1.9%.
- "PostgreSQL" is the time PostgreSQL spent executing statements (`pg_stat_database.active_time`).

## 3. How to run each version 3 times

**Needed first:** PostgreSQL running, role/database `chr` and the schema file `starschema.sql`
next to `bench.py`, the SIZE=5 CSV files in the `run` folder, and `bench.py` one folder above
`run`. `bench.py` resets the tables, runs the program once, and prints wall-clock, user and
system CPU time, PostgreSQL time and the rows loaded.

Open a terminal, activate the venv, and go to the `run` folder:

```bash
source ~/Master_Thesis/pygrametl_exaprogs/.venv314t-threads/bin/activate
cd ~/Master_Thesis/pygrametl_exaprogs/run
```

Then run the three commands, one at a time, each as **one line**. Wait for the prompt to
return before starting the next.

```bash
# sequential, 3 runs (about 11 minutes)
unset PYGRAMETL_THREADS; for i in 1 2 3; do echo "=== sequential, run $i of 3 ==="; python ../bench.py python -X gil=0 ../pygrametl1_cpython.py; done

# multiprocessing, 3 runs (about 13 minutes)
unset PYGRAMETL_THREADS; for i in 1 2 3; do echo "=== multiprocessing, run $i of 3 ==="; python ../bench.py python -X gil=0 ../pygrametl2_cpython.py; done

# threads (modified pygrametl), 3 runs (about 11 minutes)
for i in 1 2 3; do echo "=== threads, run $i of 3 ==="; PYGRAMETL_THREADS=1 python ../bench.py python -X gil=0 ../pygrametl2_cpython.py; done
```

- **The multiprocessing and the thread commands run the same script** (`pygrametl2_cpython.py`). Only `PYGRAMETL_THREADS=1` in front of the thread command differs.
- **`-X gil=0` is on all three** so the GIL setting is the same and only the code differs.
- **After each run,** check that the last line reads `loaded: 599059 page versions, 5000000 facts`.
- **Leave the laptop alone while it runs:** plugged in and set to Best performance. A run slows down if other programs compete for the CPU.
- **To also run the sequential version at the end** (to check for drift), repeat the first command.

## 4. How to use the modified pygrametl

The modified pygrametl is the `threads-backend` branch of the organization's fork,
<https://github.com/CS-IT-09/pygrametl> (forked from `chrthomsen/pygrametl`). The branch has
one commit ("Feature: Thread working with Cpython") on top of repository commit `35cf1c4`,
which is identical to the pygrametl 2.9 on PyPI, so results stay comparable with an
unmodified 2.9.

**1. Clone the branch.** The repository is public, so no login is needed:

```bash
cd ~/Master_Thesis
git clone --branch threads-backend https://github.com/CS-IT-09/pygrametl.git pygrametl-threads
```

With an SSH key set up, use `git@github.com:CS-IT-09/pygrametl.git` instead. Check the clone:

```bash
cd pygrametl-threads
git branch --show-current     # threads-backend
git log --oneline -2          # your commit on top of "Update version number to 2.9 (#93)"
```

Optional, to follow the original project later:
`git remote add upstream https://github.com/chrthomsen/pygrametl.git`.

**2. Install it** into its own venv (the old `.venv314t` with the PyPI 2.9 stays untouched):

```bash
sudo apt install libpq-dev build-essential          # needed to build psycopg2
cd ~/Master_Thesis/pygrametl_exaprogs
uv venv --python 3.14t .venv314t-threads
uv pip install --python .venv314t-threads/bin/python psycopg2 -e ~/Master_Thesis/pygrametl-threads
```

The install is editable, so edits in the clone take effect immediately.

**Only want to use it, without a clone?** Install straight from GitHub instead of the last
line above (a normal, non-editable install of the branch):

```bash
uv pip install --python .venv314t-threads/bin/python psycopg2 "git+https://github.com/CS-IT-09/pygrametl.git@threads-backend"
```

**Switch to threads with an environment variable,** `PYGRAMETL_THREADS=1`, set before Python
starts (pygrametl reads it when it is imported). Without it, pygrametl behaves exactly like
2.9 (multiprocessing). Programs do not change: the same `pygrametl2_cpython.py` runs in both
modes.

```bash
PYGRAMETL_THREADS=1 python -X gil=0 ../pygrametl2_cpython.py     # threads
python -X gil=0 ../pygrametl2_cpython.py                         # multiprocessing (default)
```

**Always add `-X gil=0` when using threads on the free-threaded build.** Importing psycopg2
turns the GIL back on, and threads with the GIL on are slower than multiprocessing
(270 s against 249 s in an earlier test).

**Three quick checks** (venv active):

```bash
python -c "import pygrametl; print(pygrametl.__file__)"
PYGRAMETL_THREADS=1 python -c "import pygrametl.parallel as p; print(p.multiprocessing.__name__)"
python -X gil=0 -c "import psycopg2, sys; print(sys._is_gil_enabled())"
```

They should print a path inside `pygrametl-threads`, `pygrametl.jythonmultiprocessing`
(and `multiprocessing` without the variable), and `False`.

To see exactly what was changed: `git -C ~/Master_Thesis/pygrametl-threads diff 35cf1c4 HEAD`.

## 5. How the multithreading was made to work

**Starting point.** On CPython, pygrametl's parallel module (`Decoupled*`, `ProcessSource`,
the shared connection) always uses `multiprocessing`. On Jython it uses threads, through a
small stand-in module, `jythonmultiprocessing.py`, that provides `Process`, `Queue`,
`JoinableQueue` and `Value` on top of threads. The idea was to reuse that stand-in on CPython,
and the free-threaded build is what makes it worthwhile: threads can run in parallel there.

| File | Change | Why |
|---|---|---|
| `jythonmultiprocessing.py` | `Value` falls back to a pure-Python class; the `daemon`/`name` property overrides are kept for Jython only | The old file imported a Java class (fails on CPython) and overrode properties that Python 3 threads already have |
| `parallel.py` (backend choice) | Use the thread stand-in when `PYGRAMETL_THREADS=1` | Selects threads instead of processes |
| `parallel.py` (`_getexitfunction`) | In thread mode, exit with `sys.stderr.flush()` and `os._exit(1)` | pygrametl halts the whole program when a worker fails by killing the process group, which is wrong when all workers are threads |
| `parallel.py` (after `_getexcepthook`) | In thread mode, set `threading.excepthook` to the same halting hook | pygrametl uses `sys.excepthook`, which is not called for exceptions in threads. Without this a crashing worker thread dies silently and the program hangs forever |
| `datasources.py` | `ProcessSource` uses the thread stand-in in thread mode; `import sqlite3` stays outside the `if` | Same backend choice. Moving `sqlite3` inside would break `SQLTransformingSource` |
| `tables.py` (optional, **not included** in the branch) | Would allow decoupling `SubprocessFactTable` in thread mode | Consistency only; the benchmark scripts don't use this class |

**Other things that mattered**

- **The GIL trap.** psycopg2 does not declare itself safe without the GIL, so importing it silently re-enables the GIL even on the free-threaded build. `-X gil=0` forces it off. As far as the code shows, all database calls go through the one shared-connection thread, so psycopg2 is only used from one thread, but this was not instrumented.
- **psycopg2 has no wheel for the free-threaded build,** so it is compiled from source.
- **An opt-in environment variable** keeps the default behaviour identical to pygrametl 2.9.

**How it was tested.** In a sandbox, on a 120,000-fact dataset and the unmodified parallel
script: thread mode with the GIL off (3 runs, correct counts); default mode unchanged;
thread mode on a regular GIL Python; a crashing worker exits with code 1 instead of hanging;
Jython, where the shim and the original parallel ETL program still work. On the benchmark
machine every SIZE=5 run loaded the correct page and fact counts.

This replaces an earlier prototype that patched pygrametl from outside at run time; it
produced the same relationships between the three versions.

## 6. Default configuration vs the max_wal_size / shared_buffers sweep

Defaults are `max_wal_size = 1GB` and `shared_buffers = 128MB`. Each configuration ran the
sequential and the thread version 3 times each (same commands as section 3). Wall-clock in
seconds, mean with range in brackets. "Control" is a default-configuration block measured
right after the sweep, in the same session.

| max_wal_size | shared_buffers | Sequential | Threads | Threads vs sequential | Sequential vs control | Threads vs control |
|---|---|---|---|---|---|---|
| 1GB (default, earlier block) | 128MB | 216.6 [212.8–220.6] | 212.6 [209.9–214.3] | −1.9% | n/a | n/a |
| 1GB (default, control) | 128MB | 223.0 [218.9–231.0] | 222.8 [217.1–226.7] | −0.1% | n/a | n/a |
| 4GB | 128MB | 232.0 [229.7–236.3] | 222.3 [220.4–224.0] | −4.2% | +4.1% | −0.2% |
| 1GB | 1GB | 227.4 [225.5–229.5] | 221.0 [217.5–223.2] | −2.8% | +2.0% | −0.8% |
| 4GB | 1GB | 228.0 [226.3–231.0] | 218.8 [216.4–220.4] | −4.1% | +2.3% | −1.8% |

- **No setting, and no combination, made a measurable difference.** The three tuned configurations are within about 2% of each other (sequential 227 to 232 s, threads 219 to 222 s), which is within the run-to-run noise.
- **The earlier default block was faster than the control by 3 to 5%.** The control falls in the range of the tuned runs, so that gap is drift in the machine, not an effect of the settings.
- **Expected:** the load writes about 1 GB of WAL, and the working set is small.

**How it was applied** (restart is needed for `shared_buffers`; check with `show`):

```bash
sudo -u postgres psql -c "ALTER SYSTEM SET max_wal_size = '4GB'"
sudo -u postgres psql -c "ALTER SYSTEM SET shared_buffers = '1GB'"
sudo service postgresql restart
psql -h localhost -U chr -d chr -c "show max_wal_size" -c "show shared_buffers"
# back to the defaults:
sudo -u postgres psql -c "ALTER SYSTEM RESET max_wal_size"
sudo -u postgres psql -c "ALTER SYSTEM RESET shared_buffers"
sudo service postgresql restart
```

## 7. Default configuration vs the pgtune configuration

Generated with <https://pgtune.leopard.in.ua/>: PostgreSQL 16, Linux, **Data warehouse**,
8 GB RAM, 8 CPUs, SSD storage, data size 1x–3x RAM, connections left at the default. The
output was saved as `/etc/postgresql/16/main/conf.d/pgtune.conf` and applied with a restart.

| Configuration | Sequential (s) | Threads (s) | Threads vs sequential | CPU seq / threads (s) | PostgreSQL seq / threads (s) |
|---|---|---|---|---|---|
| Default (earlier block) | 216.6 | 212.6 | −1.9% | 116.3 / 258.8 | 50.8 / 64.5 |
| Default (control) | 223.0 [218.9–231.0] | 222.8 [217.1–226.7] | −0.1% | 121.8 / 280.7 | 52.1 / 68.0 |
| **pgtune** | 218.3 [212.9–225.6] | 207.7 [205.8–210.0] | −4.9% | 121.1 / 262.3 | 50.7 / 62.5 |

- **pgtune against the control:** sequential −2.1%, threads −6.8%. **Against the earlier default block:** sequential +0.8%, threads −2.3%.
- **No measurable effect.** The two baselines differ from each other by more than pgtune differs from either, and the sequential block has a 9 s outlier (third run, 225.6 s).

Settings changed (default → pgtune). "Relevant" means it could plausibly affect a load of
single-row inserts and updates plus one bulk `COPY` through one connection:

| Setting | Default | pgtune | Relevant to this load? |
|---|---|---|---|
| `shared_buffers` | 128MB | 2GB | Yes (1GB tested alone: no effect) |
| `min_wal_size` / `max_wal_size` | 80MB / 1GB | 4GB / 16GB | Yes (4GB tested alone: no effect) |
| `wal_buffers` | 4MB | 16MB | Possibly, a little |
| `wal_compression` | off | lz4 | Possibly (less WAL, more CPU) |
| `effective_cache_size` | 4GB | 6GB | No (planner hint) |
| `maintenance_work_mem` | 64MB | 1GB | No (index builds, vacuum) |
| `work_mem` | 4MB | 21845kB | No (sorts, hashes) |
| `default_statistics_target` | 100 | 500 | No (planner statistics) |
| `effective_io_concurrency` | 1 | 200 | No (bitmap scans) |
| `max_connections` | 100 | 40 | No (one connection) |
| `max_parallel_workers_per_gather` / `max_parallel_maintenance_workers` | 2 / 2 | 4 / 4 | No (no parallel queries) |
| `checkpoint_completion_target`, `random_page_cost`, `huge_pages`, `max_worker_processes`, `max_parallel_workers` | unchanged | unchanged | No |

**How to check it is active** (after `sudo service postgresql restart`):

```bash
psql -h localhost -U chr -d chr -c "show shared_buffers" -c "show max_wal_size" -c "show wal_compression"
sudo -u postgres psql -c "select name, setting, unit, sourcefile from pg_settings where sourcefile like '%conf.d%' order by name"
```

The values should read 2GB, 16GB and lz4, and the second query should list about 18 rows
ending in `conf.d/pgtune.conf`. (A normal role cannot see `sourcefile`, so the second query
runs as `postgres`.) To go back: `sudo rm /etc/postgresql/16/main/conf.d/pgtune.conf`, then
`sudo service postgresql restart`.

## Notes and limits

- **One machine,** a laptop under WSL2. Block means moved by up to 5 to 10% between measurement times with no change to the code, so compare configurations only within one table or session.
- **The harness prints page and fact counts, not the error total.** Check the total (26,862,851) once for the modified-pygrametl thread version: `psql -h localhost -U chr -d chr -c "select sum(errors) from pygrametlexa.testresults"` right after a thread run.
- **The earlier analysis** (why one shared database connection appears to limit the speed, and the statement counts) is in `README_prev.md`.