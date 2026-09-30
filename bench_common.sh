# bench_common.sh - measurement helpers shared by run_jython.sh and run_cpython.sh.
# This file is sourced (". bench_common.sh"), not run directly.
#
# Provides:
#   collect_machine_info      host/OS/CPU/RAM and PostgreSQL version + settings
#   init_results_file         results.csv with the current header
#   init_cache_clearing       asks for sudo once if CLEAR_CACHE=1
#   clear_caches              restart PostgreSQL + drop the OS file cache (if CLEAR_CACHE=1)
#   measure LOG CMD...        run CMD, measure time, memory and disk I/O
#   db_size_mb                size of the loaded data warehouse
#   record_result ...         append one row to results.csv
#
# Works with the bash 3.2 that ships with macOS and with Linux.

RESULTS_HEADER="timestamp,run_id,runtime,program,size,run,real_s,user_s,sys_s,peak_rss_total_mb,max_rss_single_mb,fs_reads,fs_writes,db_size_mb,page_versions,facts,total_errors,cache_cleared,host,os,cpu,cores,ram_gb,runtime_version,postgres_version,pg_settings"
RUN_ID="$(date '+%Y%m%d-%H%M%S')"     # groups all runs of one script invocation

# Make a value safe for a CSV field (no commas or newlines)
csvsafe() { printf '%s' "$*" | tr ',\n' '; '; }

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
  PG_VERSION=$(psql -h localhost -U chr -d chr -Atc "show server_version" | awk '{print $1}')
  PG_SETTINGS=$(csvsafe "$(psql -h localhost -U chr -d chr -Atc "select string_agg(name || '=' || current_setting(name), ' ' order by name)
      from pg_settings where name in ('shared_buffers','work_mem','maintenance_work_mem',
      'max_wal_size','checkpoint_timeout','synchronous_commit','fsync','wal_level')")")
  echo "Machine: $CPU, $CORES cores, $RAM_GB GB RAM, $OS"
  echo "PostgreSQL $PG_VERSION: $PG_SETTINGS"
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

# ------------------------------------------------------------ measuring
# Sum of the resident memory (KB) of process $1 and all its descendants.
tree_rss_kb() {
  ps -A -o pid= -o ppid= -o rss= 2>/dev/null | awk -v root="$1" '
    { parent[$1] = $2; rss[$1] = $3 }
    END {
      inset[root] = 1; changed = 1
      while (changed) {
        changed = 0
        for (p in parent) if (!(p in inset) && (parent[p] in inset)) { inset[p] = 1; changed = 1 }
      }
      s = 0; for (p in inset) if (p in rss) s += rss[p]
      print s
    }'
}

# measure LOG CMD [ARGS...]
# Runs CMD with its output in LOG and sets:
#   REAL USER SYS        wall-clock and CPU seconds
#   PEAK_TOTAL_MB        peak memory of the whole process tree (sampled every 0.2 s)
#   MAX_SINGLE_MB        peak memory of the largest single process (from /usr/bin/time)
#   FS_READS FS_WRITES   file system / block I/O operations (from /usr/bin/time)
# Returns CMD's exit status.
measure() {
  local log=$1; shift
  local tf=.time pid rc=0 peak=0 cur mode
  rm -f "$tf"
  if [ -x /usr/bin/time ] && /usr/bin/time -f '%e' true >/dev/null 2>&1; then
    mode=gnu      # Linux (GNU time)
    /usr/bin/time -f '%e %U %S %M %I %O' sh -c 'exec "$@" >"$0" 2>&1' "$log" "$@" 2>"$tf" &
  elif [ -x /usr/bin/time ]; then
    mode=bsd      # macOS (BSD time)
    /usr/bin/time -l sh -c 'exec "$@" >"$0" 2>&1' "$log" "$@" 2>"$tf" &
  else
    mode=bash     # no /usr/bin/time: only times are available
    ( TIMEFORMAT='%R %U %S'; time "$@" >"$log" 2>&1 ) 2>"$tf" &
  fi
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    cur=$(tree_rss_kb "$pid")
    if [ "${cur:-0}" -gt "$peak" ]; then peak=$cur; fi
    sleep 0.2
  done
  wait "$pid" || rc=$?

  PEAK_TOTAL_MB=$(awk -v k="$peak" 'BEGIN {printf "%.1f", k/1024}')
  MAX_SINGLE_MB=NA; FS_READS=NA; FS_WRITES=NA
  case $mode in
    gnu)
      read -r REAL USER SYS maxkb FS_READS FS_WRITES < <(tail -1 "$tf")
      MAX_SINGLE_MB=$(awk -v k="$maxkb" 'BEGIN {printf "%.1f", k/1024}') ;;
    bsd)
      read -r REAL USER SYS < <(awk '/ real / {print $1, $3, $5}' "$tf")
      MAX_SINGLE_MB=$(awk '/maximum resident set size/ {printf "%.1f", $1/1048576}' "$tf")
      FS_READS=$(awk '/block input operations/ {print $1}' "$tf")
      FS_WRITES=$(awk '/block output operations/ {print $1}' "$tf") ;;
    bash)
      read -r REAL USER SYS < <(tail -1 "$tf") ;;
  esac
  return $rc
}

# Size of the data warehouse (all tables in pygrametlexa incl. indexes), in MB
db_size_mb() {
  psql -h localhost -U chr -d chr -Atc "select round(coalesce(sum(pg_total_relation_size(c.oid)), 0) / 1048576.0, 1)
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
  echo "$(date '+%Y-%m-%d %H:%M:%S'),$RUN_ID,$1,$2,$SIZE,$3,$REAL,$USER,$SYS,$PEAK_TOTAL_MB,$MAX_SINGLE_MB,$FS_READS,$FS_WRITES,$DB_MB,$PAGES,$FACTS,$ERRORS,${CLEAR_CACHE:-0},$HOST,$OS,$CPU,$CORES,$RAM_GB,$(csvsafe "$4"),$PG_VERSION,$PG_SETTINGS" >> results.csv
}

# Print the measurements of the last run
print_result() {
  echo "Time:     real ${REAL}s   CPU ${USER}s user + ${SYS}s sys"
  local single="${MAX_SINGLE_MB} MB" io="${FS_READS} reads / ${FS_WRITES} writes (I/O operations), "
  [ "$MAX_SINGLE_MB" != NA ] || single="n/a"
  [ "$FS_READS" != NA ] || io=""
  echo "Memory:   peak ${PEAK_TOTAL_MB} MB (all processes), largest process ${single}"
  echo "Disk:     ${io}data warehouse ${DB_MB} MB"
  echo "Result:   $PAGES page versions, $FACTS facts, $ERRORS total errors"
}
