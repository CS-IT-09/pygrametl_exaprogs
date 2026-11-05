import subprocess
import resource
import sys
import time
import os


cmd = sys.argv[1:]      # the program to run


# How to connect to the database: psql as user chr to database chr.
PSQL = ["psql", "-h", "localhost", "-U", "chr", "-d", "chr", "-A", "-t"]

# starschema.sql is in the same folder as this file
SCHEMA_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "schema", "starschema.sql")

def sql(query):                          
    #Run one SQL query and return its result as text
    result = subprocess.run(PSQL + ["-c", query], capture_output=True, text=True, check=True)
    return result.stdout.strip()


def reset_tables():            
    #Drop and recreate the star schema, so the run starts from empty tables
    subprocess.run(PSQL + ["-v", "ON_ERROR_STOP=1", "-f", SCHEMA_FILE],
                   capture_output=True, check=True)


def postgres_times_ms():
    # Session, active and idle-in-transaction time of database chr so far (milliseconds)
    # Added session time, active time, idle in transation time.
    row = sql("select session_time, active_time, idle_in_transaction_time from pg_stat_database where datname = 'chr'")
    return [float(value) for value in row.split("|")]


reset_tables()  # start from empty tables
time.sleep(1)  # wait a second to make sure PostgreSQL has updated its statistics


pg_before = postgres_times_ms()

cpu_before = resource.getrusage(resource.RUSAGE_CHILDREN)
start = time.perf_counter()
subprocess.run(cmd, check=True)
end = time.perf_counter()
cpu_after = resource.getrusage(resource.RUSAGE_CHILDREN)

time.sleep(1)  # wait a second to make sure PostgreSQL has updated its statistics
pg_after = postgres_times_ms()


user_time = cpu_after.ru_utime - cpu_before.ru_utime
system_time = cpu_after.ru_stime - cpu_before.ru_stime
session_time, postgres_time, idle_in_transaction_time = [(after - before) / 1000.0 for before, after in zip(pg_before, pg_after)]  # convert from milliseconds to seconds

print(f"wall-clock time: {end - start:.2f} s")
print(f"user time: {user_time:.2f} s")
print(f"system time: {system_time:.2f} s")
print(f"PostgreSQL time: {postgres_time:.2f} s")
print(f"PostgreSQL waiting for client (idle in transaction): {idle_in_transaction_time:.2f} s")
print(f"PostgreSQL session time: {session_time:.2f} s")

pages = sql("select count(*) from pygrametlexa.page")
facts = sql("select count(*) from pygrametlexa.testresults")

print(f"loaded: {pages} page versions, {facts} facts") 