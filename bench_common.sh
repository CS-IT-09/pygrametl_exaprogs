# bench_common.sh - measurement helpers shared by run_jython.sh and run_cpython.sh.
# This file is sourced (". bench_common.sh"), not run directly.
#
# Provides:
#   collect_machine_info      host/OS/CPU/RAM and PostgreSQL version + settings
#   init_results_file         results.csv with the current header
#   init_cache_clearing       asks for sudo once if CLEAR_CACHE=1
#   clear_caches              restart PostgreSQL + drop the OS file cache (if CLEAR_CACHE=1)
#   reset_schema SQL_FILE     recreate the empty tables (UNLOGGED tables if UNLOGGED=1)
#   measure LOG CMD...        run CMD, measure time, memory, disk I/O and PostgreSQL activity
#                             (needs python3 for the timer; any python3 works)
#   db_size_mb                size of the loaded data warehouse
#   record_result ...         append one row to results.csv
#
# PostgreSQL is monitored during every run (set PG_MONITOR=0 to switch it off):
# what the ETL's database connection is doing, PostgreSQL's CPU time, WAL written,
# checkpoints, cache hits and, after ./setup_pg_monitoring.sh, the time per SQL statement.
#
# Works with the bash 3.2 that ships with macOS and with Linux.

RESULTS_HEADER="timestamp,run_id,runtime,program,size,run,real_s,user_s,sys_s,peak_rss_total_mb,max_rss_single_mb,fs_reads,fs_writes,db_size_mb,page_versions,facts,total_errors,pg_busy_pct,pg_cpu_pct,pg_io_pct,pg_lock_pct,pg_other_pct,pg_waiting_for_etl_pct,pg_cpu_s,pg_stmt_time_s,pg_stmt_calls,pg_io_time_s,pg_wal_mb,pg_checkpoints,pg_checkpoints_forced,pg_cache_hit_pct,pg_blocks_read,cache_cleared,host,os,cpu,cores,ram_gb,runtime_version,postgres_version,pg_settings"
RUN_ID="$(date '+%Y%m%d-%H%M%S')"     # groups all runs of one script invocation
PSQL_CHR=(psql -h localhost -U chr -d chr -X -q -A -t)

# Make a value safe for a CSV field (no commas or newlines)
csvsafe() { printf '%s' "$*" | tr ',\n' '; '; }

# Run a query as user chr; prints NA if it fails
pgq() { "${PSQL_CHR[@]}" -F ' ' -c "$1" 2>/dev/null || echo NA; }

# ------------------------------------------------------------ machine info
collect_machine_info() {
  HOST=$(csvsafe "$(hostname -s 2>/dev/null || hostname)")
  case "$(uname -s)" in
    Darwin)
      OS="macOS $(sw_vers -productVersion)"
      CPU=$(sysctl -n machdep.cpu.brand_string)
      CORES=$(sysctl -n hw.ncpu)
      RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 )) ;;
    Linux)
      OS=$( (. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}") )
      CPU=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)
      CORES=$(nproc)
      RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo) ;;
    *)
      OS=$(uname -sr); CPU=unknown; CORES=unknown; RAM_GB=unknown ;;
  esac
  OS=$(csvsafe "$OS"); CPU=$(csvsafe "${CPU:-unknown}")
  PG_VERSION=$(pgq "show server_version" | awk '{print $1}')
  PG_VERSION_NUM=$(pgq "show server_version_num")
  PG_SETTINGS=$(csvsafe "$(pgq "select string_agg(name || '=' || current_setting(name), ' ' order by name)
      from pg_settings where name in ('shared_buffers','work_mem','maintenance_work_mem',
      'max_wal_size','checkpoint_timeout','synchronous_commit','fsync','wal_level',
      'track_io_timing','shared_preload_libraries')")")
  # Not a PostgreSQL setting, but part of the database setup, so it is recorded here too
  if [ "${UNLOGGED:-0}" = 1 ]; then
    PG_SETTINGS="$PG_SETTINGS unlogged_tables=on"
  else
    PG_SETTINGS="$PG_SETTINGS unlogged_tables=off"
  fi
  echo "Machine: $CPU, $CORES cores, $RAM_GB GB RAM, $OS"
  echo "PostgreSQL $PG_VERSION: $PG_SETTINGS"
  pg_monitor_check
}

# ------------------------------------------------------------ tables
# reset_schema SQL_FILE
# Drops and recreates the star schema, so every run starts from empty tables.
# With UNLOGGED=1 the tables are created as UNLOGGED: PostgreSQL then writes no WAL
# for them (faster, but their contents are lost after a crash; fine for benchmarks).
# The file itself is not changed. The grep hides harmless NOTICE messages.
reset_schema() {
  local sql=$1 wrong
  if [ "${UNLOGGED:-0}" = 1 ]; then
    sed 's/^\([[:space:]]*\)create table/\1create unlogged table/' "$sql" |
      psql -q -h localhost -U chr -d chr -f - 2>&1 | grep -v -e NOTICE -e DETAIL -e '^drop cascades' || true
  else
    psql -q -h localhost -U chr -d chr -f "$sql" 2>&1 | grep -v -e NOTICE -e DETAIL -e '^drop cascades' || true
  fi
  # Check that the tables really are (un)logged as requested
  if [ "${UNLOGGED:-0}" = 1 ]; then
    wrong=$(pgq "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'pygrametlexa' and c.relkind = 'r' and c.relpersistence <> 'u'")
  else
    wrong=$(pgq "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'pygrametlexa' and c.relkind = 'r' and c.relpersistence = 'u'")
  fi
  [ "$wrong" = 0 ] || { echo "The tables were not created as requested (UNLOGGED=${UNLOGGED:-0})"; exit 1; }
}

# ------------------------------------------------------------ results file
# Creates results.csv in the current directory. An existing file with an older
# header is renamed so no results are lost.
init_results_file() {
  if [ -f results.csv ] && [ "$(head -1 results.csv)" != "$RESULTS_HEADER" ]; then
    local old="results-old-$(date '+%Y%m%d-%H%M%S').csv"
    mv results.csv "$old"
    echo "Note: results.csv had an older format; it was renamed to $old"
  fi
  [ -f results.csv ] || echo "$RESULTS_HEADER" > results.csv
}

# ------------------------------------------------------------ cache clearing
# CLEAR_CACHE=1 makes every run start "cold": PostgreSQL is restarted (empties its
# shared buffers) and the operating system's file cache is dropped (needs sudo).
init_cache_clearing() {
  [ "${CLEAR_CACHE:-0}" = 1 ] || return 0
  echo "CLEAR_CACHE=1: sudo is needed to clear the OS file cache before each run."
  sudo -v
  # Keep the sudo ticket alive while this script runs (runs can take long)
  ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
}

restart_postgres() {
  if [ -n "${PG_RESTART_CMD:-}" ]; then
    eval "$PG_RESTART_CMD"
  elif [ "$(uname -s)" = Darwin ]; then
    local svc
    svc=$(brew services list 2>/dev/null | awk '/^postgresql/ && $2 == "started" {print $1; exit}')
    [ -n "$svc" ] || { echo "Could not find a running Homebrew PostgreSQL service (set PG_RESTART_CMD)"; exit 1; }
    brew services restart "$svc" >/dev/null
  else
    sudo systemctl restart postgresql
  fi
  local i=0
  until psql -h localhost -d postgres -Atc "select 1" >/dev/null 2>&1; do
    sleep 0.5; i=$((i + 1))
    [ "$i" -lt 120 ] || { echo "PostgreSQL did not come back after restart"; exit 1; }
  done
}

clear_caches() {
  [ "${CLEAR_CACHE:-0}" = 1 ] || return 0
  restart_postgres
  if [ "$(uname -s)" = Darwin ]; then
    sync; sudo purge
  else
    sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
  fi
}

# ------------------------------------------------------------ PostgreSQL monitoring
# Checks once which statistics are available.
pg_monitor_check() {
  HAVE_PGSS=0; HAVE_IO_TIMING=0
  [ "${PG_MONITOR:-1}" = 1 ] || { echo "PostgreSQL monitoring: off (PG_MONITOR=0)"; return 0; }
  if [ "$(pgq "select count(*) from pg_extension where extname = 'pg_stat_statements'")" = 1 ] &&
     [ "$(pgq "select pg_stat_statements_reset() is not null")" = t ]; then
    HAVE_PGSS=1
  fi
  [ "$(pgq "show track_io_timing")" = on ] && HAVE_IO_TIMING=1
  if [ "$HAVE_PGSS" = 1 ] && [ "$HAVE_IO_TIMING" = 1 ]; then
    echo "PostgreSQL monitoring: on (incl. SQL statement times and I/O timing)"
  else
    echo "PostgreSQL monitoring: on (basic). Run ./setup_pg_monitoring.sh once to also measure SQL statement and I/O times."
  fi
}

# Cumulative counters: blocks_read blocks_hit io_ms wal_bytes checkpoints_timed checkpoints_forced
pg_stats_snapshot() {
  local db io wal ckpt
  db=$(pgq "select blks_read, blks_hit from pg_stat_database where datname = 'chr'")
  io=$(pgq "select round((blk_read_time + blk_write_time)::numeric, 3) from pg_stat_database where datname = 'chr'")
  wal=$(pgq "select pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')")
  if [ "${PG_VERSION_NUM:-0}" -ge 170000 ] 2>/dev/null; then
    ckpt=$(pgq "select num_timed, num_requested from pg_stat_checkpointer")
  else
    ckpt=$(pgq "select checkpoints_timed, checkpoints_req from pg_stat_bgwriter")
  fi
  [ "$db" != NA ] || db="NA NA"
  [ "$ckpt" != NA ] || ckpt="NA NA"
  echo "$db $io $wal $ckpt"
}

# Keeps, per postgres process, the highest CPU time seen (state file .pgcpu: "pid seconds").
# Reads a "ps -o pid,ppid,rss,time,comm" snapshot from stdin.
pgcpu_update() {
  awk 'function secs(t,   d, x, a, n, s, i) {
         d = 0
         if (index(t, "-")) { split(t, x, "-"); d = x[1]; t = x[2] }
         n = split(t, a, ":"); s = 0
         for (i = 1; i <= n; i++) s = s * 60 + a[i]
         return d * 86400 + s
       }
       FILENAME == ".pgcpu" { m[$1] = $2; next }
       $5 ~ /(^|\/)postgres:?$/ { c = secs($4); if (!($1 in m) || c > m[$1]) m[$1] = c }
       END { for (p in m) print p, m[p] }' .pgcpu - > .pgcpu.new && mv .pgcpu.new .pgcpu
}

# One sample of what the ETL's database connection(s) are doing. One letter per connection:
# C = running on CPU, I = waiting for disk, L = waiting for a lock,
# O = other wait (e.g. WAL), E = idle, waiting for the ETL program
pg_sample_activity() {
  "${PSQL_CHR[@]}" -c "select coalesce(string_agg(case
        when state like 'idle%' then 'E'
        when wait_event_type is null then 'C'
        when wait_event_type = 'IO' then 'I'
        when wait_event_type in ('Lock', 'LWLock') then 'L'
        when wait_event_type = 'Client' then 'E'
        else 'O' end, ''), '')
      from pg_stat_activity
      where usename = 'chr' and datname = 'chr' and backend_type = 'client backend'
        and pid <> pg_backend_pid()" 2>/dev/null >> .pgact || true
}

pg_monitor_start() {
  [ "${PG_MONITOR:-1}" = 1 ] || return 0
  [ "$HAVE_PGSS" = 1 ] && pgq "select pg_stat_statements_reset()" >/dev/null
  PG_BEFORE=$(pg_stats_snapshot)
  rm -f .pgact; : > .pgact; : > .pgcpu
  ps -A -o pid= -o ppid= -o rss= -o time= -o comm= 2>/dev/null | pgcpu_update
  cp .pgcpu .pgcpu0
}

# pg_monitor_stop LABEL  - computes the PG_* results of the run
pg_monitor_stop() {
  local label=$1
  PG_BUSY=NA; PG_CPU_PCT=NA; PG_IO_PCT=NA; PG_LOCK_PCT=NA; PG_OTHER_PCT=NA; PG_WAIT_ETL=NA
  PG_CPU_S=NA; PG_STMT_S=NA; PG_STMT_CALLS=NA; PG_IO_S=NA; PG_WAL_MB=NA
  PG_CKPT=NA; PG_CKPT_FORCED=NA; PG_HIT_PCT=NA; PG_BLKS_READ=NA; PG_TOP_FILE=""
  [ "${PG_MONITOR:-1}" = 1 ] || return 0
  sleep 1                      # let PostgreSQL publish its statistics
  local after
  after=$(pg_stats_snapshot)

  # Connection state: percentage of samples per state
  read -r PG_BUSY PG_CPU_PCT PG_IO_PCT PG_LOCK_PCT PG_OTHER_PCT PG_WAIT_ETL < <(
    tr -d '\n' < .pgact | awk '{
      n = length($0)
      if (n == 0) { print "NA NA NA NA NA NA"; exit }
      split("C I L O E", k, " ")
      for (i = 1; i <= 5; i++) { s = $0; c[k[i]] = gsub(k[i], "", s) }
      printf "%.1f %.1f %.1f %.1f %.1f %.1f\n", 100*(n - c["E"])/n, 100*c["C"]/n, 100*c["I"]/n, 100*c["L"]/n, 100*c["O"]/n, 100*c["E"]/n
    }
    END { if (NR == 0) print "NA NA NA NA NA NA" }')

  # PostgreSQL CPU time during the run (all postgres processes)
  PG_CPU_S=$(awk 'FILENAME == ".pgcpu0" { b[$1] = $2; next }
                  { d = $2 - ($1 in b ? b[$1] : 0); if (d > 0) s += d }
                  END { printf "%.2f", s }' .pgcpu0 .pgcpu)

  # Differences of the cumulative counters
  read -r PG_BLKS_READ PG_HIT_PCT PG_IO_S PG_WAL_MB PG_CKPT PG_CKPT_FORCED < <(
    echo "$PG_BEFORE $after" | awk '
      function d(i) { return ($i == "NA" || $(i + 6) == "NA") ? "NA" : $(i + 6) - $i }
      {
        r = d(1); h = d(2)
        hit = (r == "NA" || h == "NA" || r + h == 0) ? "NA" : sprintf("%.2f", 100 * h / (r + h))
        io = d(3); if (io != "NA") io = sprintf("%.3f", io / 1000)
        wal = d(4); if (wal != "NA") wal = sprintf("%.1f", wal / 1048576)
        t = d(5); f = d(6); ck = (t == "NA" || f == "NA") ? "NA" : t + f
        print r, hit, io, wal, ck, f
      }')
  [ "$HAVE_IO_TIMING" = 1 ] || PG_IO_S=NA

  # Time per SQL statement (pg_stat_statements)
  if [ "$HAVE_PGSS" = 1 ]; then
    local filter="dbid = (select oid from pg_database where datname = 'chr')
        and userid = (select oid from pg_roles where rolname = 'chr')
        and query not like '%pg_stat%' and query not like '%pg_current_wal%'
        and query not like '%server_version%'"
    read -r PG_STMT_S PG_STMT_CALLS < <(pgq "select round(coalesce(sum(total_exec_time), 0)::numeric / 1000, 3),
        coalesce(sum(calls), 0) from pg_stat_statements where $filter")
    mkdir -p pg_statements
    PG_TOP_FILE="pg_statements/${RUN_ID}_${label}.txt"
    psql -h localhost -U chr -d chr -X -q -c "select calls, round(total_exec_time::numeric / 1000, 3) as total_s,
          round(mean_exec_time::numeric, 4) as mean_ms, rows,
          left(regexp_replace(query, '\s+', ' ', 'g'), 140) as statement
        from pg_stat_statements where $filter
        order by total_exec_time desc limit 15" > "$PG_TOP_FILE" 2>&1 || true
  fi
  rm -f .pgcpu .pgcpu0 .pgact
}

# ------------------------------------------------------------ measuring
# Sum of the resident memory (KB) of the descendants of process $1 (not $1 itself,
# which is only the small timer process). Reads a "ps -o pid,ppid,rss,..." snapshot from stdin.
tree_rss_kb() {
  awk -v root="$1" '
    { parent[$1] = $2; rss[$1] = $3 }
    END {
      inset[root] = 1; changed = 1
      while (changed) {
        changed = 0
        for (p in parent) if (!(p in inset) && (parent[p] in inset)) { inset[p] = 1; changed = 1 }
      }
      s = 0; for (p in inset) if (p != root && (p in rss)) s += rss[p]
      print s
    }'
}

# The timer: a small Python program that runs the command and measures it. Python's
# high-resolution clock gives the wall-clock time, and the operating system's resource
# counters (getrusage, the same source /usr/bin/time uses) give CPU time, peak memory
# and I/O of the command and all processes it started. This works identically on macOS
# and Linux and does not depend on the shell version.
# Usage: python3 -c "$TIMER_CODE" RESULT_FILE LOG_FILE CMD [ARGS...]
TIMER_CODE='import resource, subprocess, sys, time
out, log, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
with open(log, "wb") as f:
    t0 = time.perf_counter()
    try:
        rc = subprocess.call(cmd, stdout=f, stderr=subprocess.STDOUT)
    except OSError as e:
        f.write(("cannot run %s: %s\n" % (cmd[0], e)).encode())
        rc = 127
    real = time.perf_counter() - t0
r = resource.getrusage(resource.RUSAGE_CHILDREN)
maxkb = r.ru_maxrss / 1024 if sys.platform == "darwin" else r.ru_maxrss   # macOS: bytes, Linux: KB
with open(out, "w") as f:
    f.write("%.3f %.3f %.3f %d %d %d\n" % (real, r.ru_utime, r.ru_stime, maxkb, r.ru_inblock, r.ru_oublock))
sys.exit(rc if rc >= 0 else 128 - rc)
'

# measure LOG CMD [ARGS...]
# Runs CMD with its output in LOG and sets:
#   REAL USER SYS        wall-clock and CPU seconds (user + sys), 3 decimals
#   PEAK_TOTAL_MB        peak memory of all processes of CMD together (sampled every 0.2 s)
#   MAX_SINGLE_MB        peak memory of the largest single process (exact, from the OS)
#   FS_READS FS_WRITES   block I/O operations (from the OS; often 0 on macOS)
#   PG_*                 PostgreSQL measurements (see pg_monitor_stop); the top SQL
#                        statements are saved under the name in MEASURE_LABEL
# Returns CMD's exit status.
measure() {
  local log=$1; shift
  local tf=.time pid rc=0 peak=0 cur snap n=0 py maxkb
  py="${TIMER_PYTHON:-$(command -v python3 || true)}"
  [ -n "$py" ] || { echo "python3 is needed to measure the runs (set TIMER_PYTHON=/path/to/python3)"; return 1; }
  rm -f "$tf"
  pg_monitor_start

  "$py" -c "$TIMER_CODE" "$tf" "$log" "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    snap=$(ps -A -o pid= -o ppid= -o rss= -o time= -o comm= 2>/dev/null)
    cur=$(printf '%s\n' "$snap" | tree_rss_kb "$pid")
    if [ "${cur:-0}" -gt "$peak" ]; then peak=$cur; fi
    if [ "${PG_MONITOR:-1}" = 1 ]; then
      printf '%s\n' "$snap" | pgcpu_update
      n=$((n + 1))
      if [ $((n % 5)) -eq 1 ]; then pg_sample_activity; fi     # about once per second
    fi
    sleep 0.2
  done
  wait "$pid" || rc=$?
  pg_monitor_stop "${MEASURE_LABEL:-run}"

  REAL=NA; USER=NA; SYS=NA; maxkb=0; FS_READS=NA; FS_WRITES=NA
  [ -s "$tf" ] && read -r REAL USER SYS maxkb FS_READS FS_WRITES < "$tf"
  PEAK_TOTAL_MB=$(awk -v k="$peak" 'BEGIN {printf "%.1f", k/1024}')
  MAX_SINGLE_MB=$(awk -v k="$maxkb" 'BEGIN {printf "%.1f", k/1024}')
  return $rc
}

# Size of the data warehouse (all tables in pygrametlexa incl. indexes), in MB
db_size_mb() {
  pgq "select round(coalesce(sum(pg_total_relation_size(c.oid)), 0) / 1048576.0, 1)
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pygrametlexa' and c.relkind = 'r'"
}

# Row counts used to check that every program loaded the same data
count_results() {
  local counts
  counts=$(psql -h localhost -U chr -d chr -Atc "set search_path to pygrametlexa;
    select (select count(*) from page), (select count(*) from testresults), (select sum(errors) from testresults);" | tail -1)
  IFS='|' read -r PAGES FACTS ERRORS <<< "$counts"
}

# record_result RUNTIME PROGRAM RUN_NUMBER RUNTIME_VERSION
record_result() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'),$RUN_ID,$1,$2,$SIZE,$3,$REAL,$USER,$SYS,$PEAK_TOTAL_MB,$MAX_SINGLE_MB,$FS_READS,$FS_WRITES,$DB_MB,$PAGES,$FACTS,$ERRORS,$PG_BUSY,$PG_CPU_PCT,$PG_IO_PCT,$PG_LOCK_PCT,$PG_OTHER_PCT,$PG_WAIT_ETL,$PG_CPU_S,$PG_STMT_S,$PG_STMT_CALLS,$PG_IO_S,$PG_WAL_MB,$PG_CKPT,$PG_CKPT_FORCED,$PG_HIT_PCT,$PG_BLKS_READ,${CLEAR_CACHE:-0},$HOST,$OS,$CPU,$CORES,$RAM_GB,$(csvsafe "$4"),$PG_VERSION,$PG_SETTINGS" >> results.csv
}

# Print the measurements of the last run
print_result() {
  echo "Time:     real ${REAL}s   CPU ${USER}s user + ${SYS}s sys"
  local io="${FS_READS} reads / ${FS_WRITES} writes (I/O operations), "
  [ "$FS_READS" != NA ] || io=""
  echo "Memory:   peak ${PEAK_TOTAL_MB} MB (all processes), largest process ${MAX_SINGLE_MB} MB"
  echo "Disk:     ${io}data warehouse ${DB_MB} MB"
  if [ "${PG_MONITOR:-1}" = 1 ]; then
    echo "Database: connection busy ${PG_BUSY}% (CPU ${PG_CPU_PCT}%, disk ${PG_IO_PCT}%, locks ${PG_LOCK_PCT}%, other ${PG_OTHER_PCT}%), waiting for the ETL ${PG_WAIT_ETL}%"
    local extra=""
    [ "$PG_IO_S" = NA ] || extra=", disk wait ${PG_IO_S}s"
    echo "          PostgreSQL CPU ${PG_CPU_S}s${extra}, WAL ${PG_WAL_MB} MB, ${PG_CKPT} checkpoints (${PG_CKPT_FORCED} forced), cache hits ${PG_HIT_PCT}%"
    if [ -n "$PG_TOP_FILE" ]; then
      echo "          SQL statements: ${PG_STMT_S}s in ${PG_STMT_CALLS} calls (top 15: run/${PG_TOP_FILE})"
    fi
  fi
  echo "Result:   $PAGES page versions, $FACTS facts, $ERRORS total errors"
}
