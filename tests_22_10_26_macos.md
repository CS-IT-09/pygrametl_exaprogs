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

## 4. What we can see

- **Threads with the GIL off are the fastest configuration:** 71.1 s on 3.14t and 70.8 s on
  3.15t, 29% faster than sequential on the same build (100.2 s and 99.3 s, means of both blocks)
  and 28% faster than sequential on the regular build.
- **Threads beat processes when the GIL is off:** 17 to 18% faster (86.3 and 84.8 s) using 30%
  less CPU (117.5 and 115.8 s against 167.5 and 164.6 s).




# PostgreSQL tunning SIZE = 25

## 1. The tunings

| # | Tuning | max_wal_size | shared_buffers | checkpoint_timeout | wal_compression | Tables |
|---|---|---|---|---|---|---|
| 1 | default | 1GB | 128MB | 5min | off | logged |
| 2 | wal4 | 4GB | 128MB | 5min | off | logged |
| 2b | wal8 | 8GB | 128MB | 5min | off | logged |
| 3 | wal16 | 16GB | 128MB | 30min | off | logged |
| 4a | buf1-wal1 | 1GB | 1GB | 5min | off | logged |
| 4b | buf1-wal4 | 4GB | 1GB | 5min | off | logged |
| 4c | buf1-wal8 | 8GB | 1GB | 5min | off | logged |
| 4d | buf1-wal16 | 16GB | 1GB | 30min | off | logged |
| **5a** | **buf2-wal1** | 1GB | 2GB | 5min | off | logged |
| 5b | buf2-wal4 | 4GB | 2GB | 5min | off | logged |
| 5c | buf2-wal8 | 8GB | 2GB | 5min | off | logged |
| 5d | buf2-wal16 | 16GB | 2GB | 30min | off | logged |
| 5d' | buf2-wal16, 5min | 16GB | 2GB | 5min | off | logged |
| 6a | buf3-wal1 | 1GB | 3GB | 5min | off | logged |
| 6b | buf3-wal4 | 4GB | 3GB | 5min | off | logged |
| 7 | unlogged | 1GB | 2GB | 5min | off | UNLOGGED |
| 8 | pgtune (wal + buf) | 16GB | 2GB | 5min | off | logged |
* PGTune's WAL and buffer settings: like 5d' plus min_wal_size=4GB (default 80MB) and
wal_buffers=16MB (default about 4MB);

## 2. Results

Wall time is shown for each of the 3 runs and as the mean; the other time columns are means
of the 3 runs. CPU is user + system, and "cores busy" is CPU divided by wall-clock. Forced
checkpoints and WAL are per run: (counter after − counter before) / 3.

| # | Tuning | Wall per run (s) | Mean wall (s) | User (s) | Sys (s) | CPU (s) | PostgreSQL (s) | Cores busy | Forced checkpoints | WAL (MB)
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | default | 787.89 / 752.99 / 813.57 | 784.8 | 452.0 | 100.9 | 552.9 | 468.4 | 0.70 | 27 | 15391
| 2 | wal4 | 657.94 / 683.28 / 726.83 | 689.4 | 453.1 | 102.4 | 555.5 | 391.0 | 0.81 | 2.7 | 8038
| 2b | wal8 | 736.65 / 682.93 / 674.62 | 698.1 | 448.8 | 102.3 | 551.0 | 386.0 | 0.79 | 0.3 | 8178
| 3 | wal16 | 707.56 / 556.99 / 514.67 | 593.1 | 459.3 | 103.8 | 563.1 | 333.4 | 0.95 | 0.7 | 4983
| 4a | buf1-wal1 | 365.08 / 371.63 / 368.31 | 368.3 | 449.0 | 103.8 | 552.8 | 159.1 | 1.50 | 27 | 15857
| 4b | buf1-wal4 | 362.72 / 364.06 / 363.98 | 363.6 | 465.6 | 108.5 | 574.1 | 140.0 | 1.58 | 3.0 | 7892 
| 4c | buf1-wal8 | 367.98 / 367.19 / 367.18 | 367.5 | 468.1 | 108.7 | 576.9 | 142.3 | 1.57 | 0 | 7084
| 4d | buf1-wal16 | 371.06 / 369.53 / 369.93 | 370.2 | 468.8 | 108.3 | 577.1 | 144.8 | 1.56 | 0 | 4583
| **5a** | **buf2-wal1** | 355.15 / 350.68 / 354.45 | 353.4 | 441.1 | 101.1 | 542.2 | 152.0 | 1.53 | 25.7 | 15825
| 5b | buf2-wal4 | 355.08 / 358.26 / 360.10 | 357.8 | 464.5 | 108.2 | 572.7 | 135.5 | 1.60 | 3.0 | 7941
| 5c | buf2-wal8 | 362.33 / 352.67 / 352.00 | 355.7 | 461.6 | 103.0 | 564.6 | 135.9 | 1.59 | 0 | 7374
| 5d | buf2-wal16 | 360.31 / 365.86 / 362.94 | 363.0 | 468.6 | 108.8 | 577.4 | 138.3 | 1.59 | 0 | 4597
| 5d'| buf2-wal16, 5min| 368.81 / 366.06 / 361.04 | 365.3 | 466.1 | 107.3 | 573.4 | 140.7 | 1.57 | 0 | 7107
| 6a | buf3-wal1 | 359.52 / 355.82 / 354.48 | 356.6 | 441.5 | 101.1 | 542.7 | 154.2 | 1.52 | 25.0 | 15231
| 6b | buf3-wal4 | 352.90 / 358.01 / 356.12 | 355.7 | 462.5 | 107.1 | 569.6 | 135.7 | 1.60 | 3.0 | 7623
| 7 | unlogged | 349.91 / 348.40 / 352.87 | 350.4 | 467.1 | 108.1 | 575.2 | 124.6 | 1.64 | 0 | 1
| 8 | pgtune (wal + buf) | 358.32 / 361.30 / 365.76 | 361.8 | 467.6 | 109.2 | 576.8 | 137.9 | 1.59 | 0 | 7111




## 3. Conclusion

I choose 5a: shared_buffers=2GB, max_wal_size=1GB, checkpoint_timeout=5min. It had the best mean time (353.4s), but slightly faster than other configurations. 

The bottleneck now, is the ETL program or the connection, and we will focus on it now.
