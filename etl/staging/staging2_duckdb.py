"""Leg 2 (parallel): copy each table from SQLite (staging.db) into PostgreSQL at the same time, using DuckDB."""
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import duckdb

STAGING = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'staging.db')  # made by leg 1  # made by leg 1
PG = "host=/tmp dbname=chr user=chr options=''-c maintenance_work_mem=512MB''"  # Unix socket, more memory for building indexes
SCHEMA = 'pygrametlexa'

# test is not copied: starschema.sql already inserts its 6 rows
TABLES = ['date', 'page', 'testresults']

# 4c: indexes are dropped before the copy and built again after it, which is cheaper than updating them per row.
# postgres_execute takes one statement per call, so each table has a list.
DROP_INDEXES = {
    'date': [f"ALTER TABLE {SCHEMA}.date DROP CONSTRAINT date_pkey"],
    'page': [f"ALTER TABLE {SCHEMA}.page DROP CONSTRAINT page_pkey",
             f"DROP INDEX {SCHEMA}.url_version_idx"],
    'testresults': [f"ALTER TABLE {SCHEMA}.testresults DROP CONSTRAINT testresults_pkey"],
}
CREATE_INDEXES = {
    'date': [f"ALTER TABLE {SCHEMA}.date ADD PRIMARY KEY (dateid)"],
    'page': [f"ALTER TABLE {SCHEMA}.page ADD PRIMARY KEY (pageid)",
             f"CREATE INDEX url_version_idx ON {SCHEMA}.page (url, version DESC)"],
    'testresults': [f"ALTER TABLE {SCHEMA}.testresults ADD PRIMARY KEY (pageid, testid, dateid)"],
}


def copy_table(table):
    # Own DuckDB connection per thread, so each table gets its own PostgreSQL session
    start = time.perf_counter()
    con = duckdb.connect()
    con.execute("LOAD sqlite; LOAD postgres;")
    con.execute(f"ATTACH '{STAGING}' AS lite (TYPE sqlite, READ_ONLY)")
    con.execute(f"ATTACH '{PG}' AS pg (TYPE postgres)")
    for statement in DROP_INDEXES[table]:
        con.execute(f"CALL postgres_execute('pg', '{statement}')")
    con.execute(f"INSERT INTO pg.{SCHEMA}.{table} BY NAME SELECT * FROM lite.{table}")
    copied = time.perf_counter()
    for statement in CREATE_INDEXES[table]:
        con.execute(f"CALL postgres_execute('pg', '{statement}')")
    con.close()
    end = time.perf_counter()
    print("[leg 2] %-12s copy %.1f s, indexes %.1f s, total %.1f s"
          % (table, copied - start, end - copied, end - start), file=sys.stderr)


def main():
    # DuckDB releases the GIL during execute, so the copies run in parallel
    with ThreadPoolExecutor(max_workers=len(TABLES)) as pool:
        for future in [pool.submit(copy_table, table) for table in TABLES]:
            future.result()  # re-raises an error from a thread


if __name__ == '__main__':
    main()