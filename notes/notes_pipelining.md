# Why parallel work does not help on my machine, and what pipelining could change

## 1. The answer in 30 seconds

- On my laptop (Intel i7-1185G7, 4 cores, Ubuntu under WSL2) no parallel version of the ETL program beats the sequential one. Threads with the GIL off match it (within 2%), processes are 22 to 27% slower, threads with the GIL on are 43 to 49% slower. Same on Python 3.14 and 3.15 (with psycopg 3).
- The reason is the **single shared database connection**. Every statement (about 1,000,000 inserts and updates) goes through one connection, one at a time. The thread that runs them spends 83% of the run inside `execute()` (send the statement, wait for Postgres to answer), and together with the Postgres process it keeps one core busy about 100% of the time. The other threads are only 14 to 21% busy. Helpers cannot make that exchange faster, so there is almost nothing left for them to overlap.
- The single connection is the paper's deliberate choice (one transaction, so a failed load rolls back completely). I want to keep it.
- A test without pygrametl shows that sending the same statements in **pipeline mode** (the program does not wait for each answer, same connection, same transaction) is **6.1 times faster** on my machine. I have not yet tried it in pygrametl. I want the supervisors' opinion first.
- On my colleague's Apple M2 the same code makes threads 29% faster than sequential. Why is still a hypothesis (section 8 lists the tests that would settle it).

## 2. Background

- The program loads 5,000,000 test results and about 600,000 page versions into a PostgreSQL star schema. About **1,000,000 single-row INSERT/UPDATE statements** on the `page` table go through the database one at a time (the timing in T4 below counts 998,131 statements through the shared connection).
- In the 2011 paper (Section 5) the parallel version shares one connection between all workers, for transactional safety, and rejects one connection per worker (resource use, risk of inconsistency). The pygrametl source and docs say the same.
- In the code, a worker's `execute()` only puts the statement on a queue and returns. One **server thread** takes the statements from the queue and runs them one by one on the real connection. That thread is the "connection thread" below.
- I modified pygrametl so its parallel parts can run on threads (free-threaded Python) as well as processes, chosen from the GIL state, and ported the benchmarks to psycopg 3.

## 3. Results

Time relative to the sequential run on the same Python build; a minus sign means faster. Sequential time: 186 to 202 s on my laptop, about 100 s on the M2.

| Version | My laptop, 3.14 | My laptop, 3.15 | Colleague's M2, 3.14 |
|---|---|---|---|
| Multiprocessing, regular build | +26.2% | +27.0% | −16.9% |
| Processes, GIL on | +23.5% | +26.5% | −17.0% |
| Processes, GIL off | +21.7% | +24.3% | −13.9% |
| Threads, GIL on | +43.2% | +49.4% | +16.8% |
| **Threads, GIL off** | **−0.4%** | **+1.7%** | **−29.1%** |

On both machines threads with the GIL off are the fastest parallel version, processes are in the middle, and threads with the GIL on are the slowest. Full tables with every run are in `README.md`.

## 4. The tests, with the exact commands

Each test says what it shows, how to run it, what I got, and how to read it. Scripts longer than a few lines are in the appendix. Unless it says otherwise, run from `~/Master_Thesis/pygrametl_exaprogs/run` with the right venv active (`.venv314-pg3` or `.venv315.pg3` for the regular builds, `.venv314t-pg3` or `.venv315t-pg3` for the free-threaded ones).

### T1. The benchmark runs (what happens)

**Shows:** how each version compares with sequential. `bench.py` resets the tables, runs the program once, and prints wall-clock time, user and system CPU time, PostgreSQL time and the rows loaded. Paste each command as one line.

Regular build, no flags:
```bash
for i in 1 2 3; do echo "=== sequential, run $i of 3 ==="; python ../bench.py python ../pygrametl1_pg3.py; done
for i in 1 2 3; do echo "=== multiprocessing, run $i of 3 ==="; python ../bench.py python ../pygrametl2_pg3.py; done
```

Free-threaded build:
```bash
for i in 1 2 3; do echo "=== sequential, run $i of 3 ==="; python ../bench.py python -X gil=0 ../pygrametl1_pg3.py; done
for i in 1 2 3; do echo "=== processes, GIL on, run $i of 3 ==="; PYGRAMETL_PARALLEL=processes python ../bench.py python -X gil=1 ../pygrametl2_pg3.py; done
for i in 1 2 3; do echo "=== processes, GIL off, run $i of 3 ==="; PYGRAMETL_PARALLEL=processes python ../bench.py python -X gil=0 ../pygrametl2_pg3.py; done
for i in 1 2 3; do echo "=== threads, GIL on, run $i of 3 ==="; PYGRAMETL_PARALLEL=threads python ../bench.py python -X gil=1 ../pygrametl2_pg3.py; done
for i in 1 2 3; do echo "=== threads, GIL off, run $i of 3 ==="; PYGRAMETL_PARALLEL=threads python ../bench.py python -X gil=0 ../pygrametl2_pg3.py; done
```


### T2. CPU per thread during a run (is the connection busy?)

**Shows:** whether the connection thread and the Postgres process are busy all the time. Two terminals.

Terminal 1, start the run:
```bash
PYGRAMETL_PARALLEL=threads python ../bench.py python -X gil=0 ../pygrametl2_pg3.py
```
Terminal 2, within about 15 seconds of starting:
```bash
PID=$(pgrep -n -f pygrametl2_pg3.py)
BE=$(psql -h localhost -U chr -d chr -tAc "select pid from pg_stat_activity where datname='chr' and backend_type='client backend' and pid <> pg_backend_pid()")
echo $PID $BE
top -H -b -d 10 -n 18 -p $PID,$BE > threads_pg3.txt
```


**Results:**

| Log | Connection thread | Postgres | Sum |
|---|---|---|---|
| `threads_pg3.txt` (psycopg 3, threads, GIL off) | 57.5% | 42.3% | **99.8%** (98.9 to 100.7) |

In `threads_pg3.txt` the other threads are the two page workers (21% each), the fact-table worker and the data source (14% each), the main thread (16%) and the sequence factory (0%). The machine is about 76% idle.

**How to show it:** open the file, go to the second block (12:32:02) and point at the two rows, PID 3299 (`Process+`, the connection thread) at 57.2% and PID 3298 (`postgres`) at 41.7%. Their sum is 98.9%. Show two more blocks (12:33:12: 58.1 + 41.9 = 100.0; 12:34:42: 56.8 + 42.5 = 99.3). In `top -H`, each row is a thread, and `%CPU` is the share of one core used in the last 10 s.

**Limits:** it shows CPU time, not waiting. Which thread is which is inferred from the order the threads were created.

### T3. What could pipelining give? (no pygrametl involved)

**Shows:** how fast the same statements run over one connection in the way pygrametl does it (one at a time) and in pipeline mode (same connection, same transaction). The script is in Appendix A. It uses its own table `bench_page` in database `chr`, about 5 minutes.

**Result on my machine:**

| Mode | Time | Statements per second |
|---|---|---|
| One statement at a time (what pygrametl does) | 114.6 s | 8,707 |
| Pipeline mode, same connection and transaction | 18.8 s | 53,068 |

Pipeline mode is **6.09 times as fast** and the row counts were correct (599,059 inserted, 399,059 updated). This is a ceiling, not a promise: it removes the waiting for each answer, and nothing else.

### T4. Where does the connection thread spend its time?

**Shows:** how much of a real run the connection thread spends waiting for work, executing statements, and collecting results. This is a **temporary** edit of `pygrametl/parallel.py` for one run, and the code is in Appendix B. Then run once (and do not use this run in the benchmark tables):
```bash
PYGRAMETL_PARALLEL=threads python ../bench.py python -X gil=0 ../pygrametl2_pg3.py
```
It prints a `[shared connection]` line twice (the script commits twice); the second line has the final totals. Restore the original afterwards:
```bash
git checkout -- pygrametl/parallel.py
```

**Result on my machine:** `998131 statements: waiting for work 19.8 s, executing 165.6 s, fetching results 2.7 s`, in a run of 199.3 s.

| Part | Time | Share of the run |
|---|---|---|
| Executing statements (send, wait for Postgres, receive) | 165.6 s | 83% |
| Fetching results | 2.7 s | 1% |
| Waiting for work (thread idle) | 19.8 s | 10% |
| Not counted (probably the bulk-load COPY) | about 11 s | 6% |

This is a direct measurement: the connection thread is idle only about 10% of the time. Per statement, `execute` takes about 166 µs inside pygrametl, against about 115 µs for the bare one-at-a-time loop in T3, so about 50 µs per statement comes from pygrametl itself.

## 5. The argument, step by step

1. The program does two kinds of work: **A**, the Python work on the data, and **B**, the exchange with the database through one connection, one statement at a time.
2. Parallel helpers can do A while B is going on, but they cannot make B faster, because with one connection the statements still go through one at a time.
3. Measured on my machine: the connection thread and Postgres together are busy about 100% of the time (T2), and the connection thread spends 83% of the run executing statements and only 10% waiting for work (T4). So B takes almost the whole run, and little of A is left to overlap.
4. The parallel versions add costs (handing rows between threads or processes: 2.2 times the CPU for threads, 3.1 to 3.3 times for processes). That cancels the small saving for threads and makes processes slower.

A small example: a 100 s job with 97 s that cannot be split cannot go below 97 s, however many helpers it has.

## 6. What pipelining would change (and what it would not)

- **What it is.** The program sends statements without waiting for each answer; Postgres still executes them one after another, in order, on the same connection and in the same transaction. Only the idle waiting between statements disappears. It works with ordinary blocking code and does not need async/await.
- **Why it matters here.** T3 shows the bare exchange is about 6 times faster in pipeline mode, and T4 shows the connection thread spends most of its time in exactly that step.
- **Rough ceiling for the threaded run,** from the log: the connection thread used about 107 s of CPU and Postgres about 78 s, out of about 185 s. If the two overlapped completely, the run could approach the busier side, about 110 s instead of 200 s. This is an optimistic upper bound, not a prediction.
- **Fairness.** The sequential program uses the same connection, so it should get pipelining too. Otherwise part of the gain would be credited to threads. After that, I expect threads' advantage to stay modest (perhaps 10 to 20%), because the connection thread's own Python work cannot be spread over threads. This is an estimate.
- **Safety.** By design it keeps the same connection, the same order and one transaction: errors are reported later, but nothing is committed after one, and the bulk load (COPY) must run with the pipeline closed. This would be tested properly if pipelining goes ahead.



**A side finding (seen in the test environment):** if a statement fails, multiprocessing mode hangs forever, in the unmodified pygrametl 2.9 as well. Thread mode halts with exit code 1.

## 7. Questions for the supervisors

1. Is pipelining in scope? It keeps one connection and one transaction, but it changes how the shared-connection thread talks to Postgres and delays error reporting.
2. Is it acceptable to add an opt-in option to pygrametl's public `ConnectionWrapper` (and a small change to the shared-connection server), or should it be a separate wrapper class?
3. Should the sequential version get pipelining too, so the comparison with threads is fair? (I think yes.)
4. How does this relate to the async/await step of the proposal, and to my colleague's psycopg 3 async port?
5. Was pipelining or batching considered in 2011? Would you want it contributed upstream?
6. Should I also look at batching (many rows per statement)? It is a bigger change (pygrametl's slowly changing dimension inserts one row per statement), and it also keeps one transaction.
7. Is the explanation in section 5 convincing, or which test would you want before accepting it? (The strongest remaining test would be to make the exchange shorter and see the run get faster.)

## 8. Tests for my colleague with the M2, and why

His numbers differ from mine in two ways: everything is about twice as fast, and the parallel versions beat sequential. My explanation is that on his machine the exchange with the database takes a smaller share of the run. These tests would check that. In order of value; the scripts are the same ones I ran.

**C1. The bare-connection test (Appendix A).** *Why:* it measures what one statement costs over the connection on his machine and how much pipelining gains. On mine: 8,707 statements per second one at a time, 6.09 times faster pipelined. If his one-at-a-time rate is much higher and his pipelining gain much smaller, round trips are cheaper there and waiting is a smaller part of his run. About 3 to 5 minutes. He may need to change the connection string in the script (`host=localhost dbname=chr user=chr`).

**C2. Timing of the connection thread during a threaded run (T4 / Appendix B).** *Why:* it measures directly whether his connection thread ever idles. It also prints how many statements went through the connection, which confirms he runs the same workload (mine: 998,131). On mine it waited for work only 19.8 s of 199 s. If his "waiting for work" is a large part of his 71 s run, the connection is not saturated there, which would explain why parallel helps him. If it is also small, my explanation needs rethinking. It needs the same temporary edit of `pygrametl/parallel.py` in his clone, and this works on macOS (T2's `top -H` does not).
```bash
PYGRAMETL_PARALLEL=threads python ../bench.py python -X gil=0 ../pygrametl2_pg3.py
git checkout -- pygrametl/parallel.py      # afterwards
```

**C3. His setup, to rule out differences in the code or the database.** *Why:* if his Postgres, Python or code differs from mine, the comparison is not like for like.
```bash
python -c "import sys, sysconfig, psycopg; print(sys.version.split()[0], 'free-threaded build:', bool(sysconfig.get_config_var('Py_GIL_DISABLED')), 'psycopg', psycopg.__version__, psycopg.pq.__impl__)"
git rev-parse --short HEAD
git branch --show-current
psql -h localhost -d chr -c "select version()" -c "show shared_buffers" -c "show max_wal_size"
sw_vers
pmset -g batt
```
(Adjust the user and database names if his differ.) Also: how Postgres is installed (Homebrew, Postgres.app or Docker; Docker would be a virtual machine too), whether Low Power Mode was off, whether he checked that the error total is 26,862,851, and his 3.15 results if he has them.

He does not need to run the per-thread `top -H` log; C2 answers the same question more directly.

## 9. Measured and inferred

| Claim | Status |
|---|---|
| Threads ≈ sequential and processes slower on my laptop | **Measured** (many blocks, two Python versions) |
| The connection thread and Postgres are busy about 100% together | **Measured** (CPU time, T2) |
| The connection thread spends 83% of the run in `execute` and 10% waiting for work | **Measured** (T4, one run) |
| Pipeline mode is 6.1 times faster on a bare connection | **Measured** (T3, one run) |
| The two sides strictly take turns | Inferred (one connection by design, plus T2) |
| Pipelining would speed up the real ETL, by how much | **Not tested**; the 110 s figure is an optimistic ceiling |
| Why the M2 behaves differently | **Hypothesis**; tests in section 8 |

## 10. Limits

- Two machines only. My laptop runs Ubuntu inside WSL2, which adds a virtualization layer.
- T3 and T4 are single runs, and T2 is one log of one run. Repeating them would show their spread.
- The pipelining prototype was tested in a separate test environment on a small dataset, not on my laptop, so it is evidence that the idea works correctly, not a speed result.

---

## Appendix: scripts

### A. One statement at a time against pipeline mode (any venv with psycopg 3)

```bash
python - << 'EOF'
import sys, time, datetime, psycopg
DSN = "host=localhost dbname=chr user=chr"
N_INS, N_UPD = 599_059, 399_059
d = datetime.date(2003, 1, 1)
rows = [(i, f"http://www.domain{i%2000}.tl{i%7}/page{i}.html", 1000 + i % 9000, f"www.domain{i%2000}.tl{i%7}",
         f"tl{i%7}", "SomeServer/1.0", "SomeServer", d, None, 1) for i in range(N_INS)]
upd = [(datetime.date(2003, 2, 1), i) for i in range(N_UPD)]
SETUP = """drop table if exists bench_page;
create table bench_page(pageid int primary key, url varchar, size int, domain varchar, topleveldomain varchar,
  serverversion varchar, server varchar, validfrom date, validto date, version int);
create index bench_url_idx on bench_page(url, version desc);"""
INS = "insert into bench_page values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)"
UPD = "update bench_page set validto=%s where pageid=%s"

def fresh():
    with psycopg.connect(DSN, autocommit=True) as c:
        c.execute(SETUP)

def timed(label, fn):
    fresh()
    t = time.perf_counter(); fn(); dt = time.perf_counter() - t
    print(f"{label:48s} {dt:7.1f} s   ({(N_INS + N_UPD) / dt:8.0f} statements/s)")
    return dt

def one_at_a_time():
    with psycopg.connect(DSN) as c:
        cur = c.cursor()
        for r in rows:
            cur.execute(INS, r)
        for u in upd:
            cur.execute(UPD, u)

def pipelined():
    with psycopg.connect(DSN) as c:
        with c.pipeline() as p:
            cur = c.cursor()
            for i, r in enumerate(rows):
                cur.execute(INS, r)
                if i % 1000 == 0:
                    p.sync()
            for i, u in enumerate(upd):
                cur.execute(UPD, u)
                if i % 1000 == 0:
                    p.sync()

a = timed("one statement at a time (what pygrametl does)", one_at_a_time)
b = timed("pipeline mode, same connection and transaction", pipelined)
print(f"pipeline mode is {a / b:.2f}x as fast")
with psycopg.connect(DSN) as c:
    print("rows after the pipelined run:", c.execute("select count(*), count(validto) from bench_page").fetchone())
EOF
```
The last line should read `(599059, 399059)`.

### B. Temporary timing of the connection thread

In `pygrametl/parallel.py`, replace the whole `worker` method of `class SharedConnectionWrapperServer` with this, run once (T4), then restore with `git checkout -- pygrametl/parallel.py`:
```python
    def worker(self):
        sys.excepthook = _getexcepthook()
        # TODO: Improved error handling such that an exception can be passed on
        # to the responsible client. It is, however, likely that we cannot
        # continue using the shared DB connection after the exception
        # occured...
        import time

        t_wait = t_exec = t_fetch = 0.0  # TEMPORARY MEASUREMENT
        statements = 0
        while True:
            t0 = time.perf_counter()
            (client, method, args) = self.__toserver.get()
            t_wait += time.perf_counter() - t0
            if method == "#get":
                self.__senddata(client, *args)
            elif method.startswith("_userfunc_"):
                target = getattr(self, method)
                target(*args)
                self.__toclients[client].put("USERFUNC")
            elif method == "close":
                target = getattr(self.__wrapped, method)
                target(*args)  # Probably no arguments anyway, but ...
            else:  # it must be a function from the wrapped ConnectionWrapper
                target = getattr(self.__wrapped, method)
                t1 = time.perf_counter()
                target(*args)
                t2 = time.perf_counter()
                res = self.__wrapped.fetchalltuples()
                if not isinstance(res, list):
                    # In __senddata we pop/del from a list so a tuple won't
                    # work
                    res = list(res)
                self.__results[client] = (self.__wrapped.resultnames(), res)
                t_exec += t2 - t1
                t_fetch += time.perf_counter() - t2
                statements += 1
                if method == "commit":
                    print(
                        "[shared connection] %d statements: waiting for work %.1f s, "
                        "executing %.1f s, fetching results %.1f s"
                        % (statements, t_wait, t_exec, t_fetch),
                        file=sys.stderr,
                    )
            self.__toserver.task_done()
            if method == "close":
                return
```