# pygrametl parallel ETL on macOS (Apple M2): same tests as tests_22_10_26.md

The same benchmarks as in `tests_22_10_26.md`, repeated on a different machine: pygrametl's
example ETL program (from the 2011 paper *Easy and Effective Parallel Programmable ETL*) on
CPython 3.14 and 3.15, with and without the GIL, using PostgreSQL and psycopg 3, with the
`auto-backend` branch of pygrametl (threads or processes).

## 1. Setup

| Item | Value |
|---|---|
| CPU | Apple M2, 8 cores |
| RAM | 8 GB |
| OS | macOS `26.3 Beta` |
| PostgreSQL | 18.6 (Homebrew), tuned settings: max_wal_size=4GB, shared_buffers=1GB (defaults: 1GB, 128MB) |
| Data | The paper's SIZE=5 dataset: 1,000,000 downloads, 5,000,000 test results |
| Correct result | 599,059 page versions, 5,000,000 facts, total errors 26,862,851 |
| Python 3.14 | 3.14.7 (uv): regular build in `.venv314-pg3`, free-threaded build (3.14t) in `.venv314t-pg3` |
| Python 3.15 | 3.15.0rc1 (uv, release candidate): regular build in `.venv315-pg3`, free-threaded build (3.15t) in `.venv315t-pg3` |
| Database driver | psycopg 3.3.6: `psycopg[binary]` on the regular builds, `psycopg[c]` built from source on the free-threaded builds |
| pygrametl | branch `auto-backend` of <https://github.com/CS-IT-09/pygrametl> (commit `2d86bf3`), installed editable in all four venvs |
| Conditions | other apps closed, laptop plugged in |

## 2. How the runs were made

Exactly the commands from section 3 of `tests_22_10_26.md`: `bench.py` resets the tables, runs
the program once, and prints wall-clock, user and system CPU time, PostgreSQL time
(`pg_stat_database.active_time`) and the rows loaded. Each version was run 3 times, from the
`run` folder with the venv active; the output is saved in `run/results_314.txt` and
`run/results_315.txt`.

## 3. Results

Rows are in the order they were run. Wall time is shown for each of the 3 runs and as the mean;
the other columns are means of the 3 runs. CPU is user + system, and "cores busy" is CPU divided
by wall-clock.

### Python 3.14

| Build | Version | Wall per run (s) | Mean wall (s) | User (s) | Sys (s) | CPU (s) | PostgreSQL (s) | Cores busy |
|---|---|---|---|---|---|---|---|---|
| Regular | Sequential (first block) | 97.10 / 97.87 / 95.16 | 96.7 | 47.4 | 8.7 | 56.1 | 24.3 | 0.58 |
| Regular | Multiprocessing | 82.36 / 79.30 / 81.49 | 81.1 | 118.5 | 30.1 | 148.6 | 25.5 | 1.83 |
| Free-threaded | Sequential (first block) | 100.42 / 101.59 / 99.81 | 100.6 | 50.0 | 9.0 | 59.0 | 24.7 | 0.59 |
| Free-threaded | Processes, GIL on | 83.20 / 82.27 / 84.05 | 83.2 | 128.7 | 30.7 | 159.5 | 26.0 | 1.92 |
| Free-threaded | Processes, GIL off | 88.13 / 85.55 / 85.32 | 86.3 | 138.3 | 29.3 | 167.5 | 26.7 | 1.94 |
| Free-threaded | Threads, GIL on | 115.80 / 118.45 / 116.96 | 117.1 | 85.3 | 19.7 | 105.0 | 25.5 | 0.90 |
| Free-threaded | Threads, GIL off | 70.99 / 70.73 / 71.47 | 71.1 | 92.4 | 25.0 | 117.5 | 25.1 | 1.65 |
| Free-threaded | Sequential (last block) | 99.59 / 100.58 / 99.36 | 99.8 | 49.8 | 8.9 | 58.7 | 24.6 | 0.59 |
| Regular | Sequential (last block) | 98.34 / 98.00 / 98.39 | 98.2 | 47.6 | 8.8 | 56.5 | 25.2 | 0.57 |

### Python 3.15

| Build | Version | Wall per run (s) | Mean wall (s) | User (s) | Sys (s) | CPU (s) | PostgreSQL (s) | Cores busy |
|---|---|---|---|---|---|---|---|---|
| Regular | Sequential (first block) | 98.30 / 97.04 / 97.97 | 97.8 | 47.7 | 8.7 | 56.4 | 24.6 | 0.58 |
| Regular | Multiprocessing | 80.14 / 80.81 / 80.26 | 80.4 | 117.7 | 30.2 | 147.9 | 25.2 | 1.84 |
| Free-threaded | Sequential (first block) | 99.41 / 98.70 / 99.18 | 99.1 | 49.3 | 8.7 | 58.0 | 24.7 | 0.59 |
| Free-threaded | Processes, GIL on | 81.38 / 82.93 / 81.44 | 81.9 | 127.9 | 30.8 | 158.7 | 25.3 | 1.94 |
| Free-threaded | Processes, GIL off | 84.98 / 83.61 / 85.94 | 84.8 | 135.5 | 29.1 | 164.6 | 26.0 | 1.94 |
| Free-threaded | Threads, GIL on | 113.61 / 115.78 / 116.28 | 115.2 | 84.2 | 19.6 | 103.8 | 24.9 | 0.90 |
| Free-threaded | Threads, GIL off* | 70.90 / 70.29 / 71.24 | 70.8 | 94.3 | 21.5 | 115.8 | 25.0 | 1.64 |
| Free-threaded | Sequential (last block) | 98.92 / 100.60 / 99.02 | 99.5 | 49.4 | 8.8 | 58.2 | 24.8 | 0.59 |
| Regular | Sequential (last block) | 97.94 / 97.93 / 98.91 | 98.3 | 47.9 | 8.8 | 56.7 | 25.0 | 0.58 |

## 4. What the tables show

- **Threads with the GIL off are the fastest configuration:** 71.1 s on 3.14t and 70.8 s on
  3.15t, 29% faster than sequential on the same build (100.2 s and 99.3 s, means of both blocks)
  and 28% faster than sequential on the regular build.
- **Threads beat processes when the GIL is off:** 17 to 18% faster (86.3 and 84.8 s) using 30%
  less CPU (117.5 and 115.8 s against 167.5 and 164.6 s).
- **The GIL decides whether threads work:** with it on, threads are 39% slower (117.1 and 115.2 s),
  use less than one core (0.90), and are 16 to 17% slower than sequential.
- **Processes are 14 to 18% faster than sequential** on every build and both Python versions,
  at 2.6 to 2.9 times the CPU.
- **The GIL barely matters for processes,** but GIL off is consistently 3.5 to 3.7% *slower*
  (3.14t: 86.3 against 83.2 s; 3.15t: 84.8 against 81.9 s).
- **The free-threaded build costs 1 to 3% for sequential code** (3.14: 2.8%, 3.15: 1.3%).
- **3.15 behaves like 3.14:** every configuration is within 0 to 2% of its 3.14 time, which
  is within the drift between sessions.
- **PostgreSQL time is 24 to 27 s in every configuration,** so the differences come from the
  ETL program, not the database.

## 5. Notes and limits

Ratios to sequential on the same build, Python 3.14 (positive = faster than sequential):

| Version | Apple M2, macOS (this file) | Intel i7, WSL2 |
|---|---|---|
| Multiprocessing (regular build) | 17% faster | 26% slower |
| Processes, GIL on (free-threaded) | 17% faster | 23% slower |
| Threads, GIL on | 17% slower | 43% slower |
| **Threads, GIL off** | **29% faster** | **about equal (0.2% faster)** |

- **The main conclusions agree:** the GIL decides whether threads work, threads beat processes
  when the GIL is off, and 3.15 behaves like 3.14.
- **The big difference is the size of the gain:** on the M2 every parallel version except
  threads with the GIL on beats sequential; on the i7 none did. Possible reasons: twice as
  many cores (8 against 4), no WSL2 overhead, different PostgreSQL versions (18.6 against 16.15)
  and possibly settings.
- **PostgreSQL time is the same on both machines** (about 25 s), so the difference comes from how
  fast the ETL program itself runs in parallel.