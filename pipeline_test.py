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