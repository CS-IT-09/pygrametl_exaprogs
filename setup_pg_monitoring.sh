#!/usr/bin/env bash
# One-time PostgreSQL setup for the database measurements in run_jython.sh / run_cpython.sh:
#   - loads the pg_stat_statements extension (time spent per SQL statement); needs a restart
#   - turns on track_io_timing (time PostgreSQL spends reading/writing data files)
#   - lets the user "chr" read all statistics and reset pg_stat_statements
#
# Run it once:   ./setup_pg_monitoring.sh
# Undo:          ./setup_pg_monitoring.sh --undo
#
# Must be run as a PostgreSQL superuser. With Homebrew's PostgreSQL that is your macOS user,
# which is what psql uses by default.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/bench_common.sh"          # for restart_postgres

ADMIN=(psql -h localhost -d postgres -X -q -A -t)

"${ADMIN[@]}" -c "select 1" >/dev/null 2>&1 || {
  echo "Cannot connect to PostgreSQL. Is it running?  brew services start postgresql@18"; exit 1; }
[ "$("${ADMIN[@]}" -c "select rolsuper from pg_roles where rolname = current_user")" = t ] || {
  echo "This must be run as a PostgreSQL superuser (with Homebrew: your macOS user)."; exit 1; }

if [ "${1:-}" = "--undo" ]; then
  echo "Removing the monitoring settings ..."
  cur=$("${ADMIN[@]}" -c "show shared_preload_libraries")
  new=$(echo "$cur" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^pg_stat_statements$' | paste -sd, - || true)
  if [ -n "$new" ]; then
    "${ADMIN[@]}" -c "alter system set shared_preload_libraries = '$new'"
  else
    "${ADMIN[@]}" -c "alter system reset shared_preload_libraries"
  fi
  "${ADMIN[@]}" -c "alter system reset track_io_timing"
  psql -h localhost -d chr -X -q -c "drop extension if exists pg_stat_statements" 2>/dev/null || true
  echo "Restarting PostgreSQL ..."
  restart_postgres
  echo "Done. PostgreSQL is back to its previous configuration."
  exit 0
fi

# The database and user the example programs use
if ! "${ADMIN[@]}" -c "select 1 from pg_roles where rolname = 'chr'" | grep -q 1; then
  "${ADMIN[@]}" -c "create role chr login"
fi
if ! "${ADMIN[@]}" -c "select 1 from pg_database where datname = 'chr'" | grep -q 1; then
  "${ADMIN[@]}" -c "create database chr owner chr"
fi

# 1. Load pg_stat_statements at server start (keeps any libraries already configured)
restart_needed=0
cur=$("${ADMIN[@]}" -c "show shared_preload_libraries")
nospaces=$(echo "$cur" | tr -d ' ')
case ",$nospaces," in
  *,pg_stat_statements,*) echo "pg_stat_statements is already loaded." ;;
  *)
    new="${cur:+$cur,}pg_stat_statements"
    "${ADMIN[@]}" -c "alter system set shared_preload_libraries = '$new'"
    echo "Configured shared_preload_libraries = '$new'"
    restart_needed=1 ;;
esac

# 2. Measure the time spent on disk I/O (no restart needed)
"${ADMIN[@]}" -c "alter system set track_io_timing = on"
"${ADMIN[@]}" -c "select pg_reload_conf()" >/dev/null

if [ "$restart_needed" = 1 ]; then
  echo "Restarting PostgreSQL to load pg_stat_statements ..."
  restart_postgres
fi

# 3. Create the extension in database chr and give user chr access to the statistics
psql -h localhost -d chr -X -q -c "create extension if not exists pg_stat_statements"
psql -h localhost -d chr -X -q -c "grant pg_read_all_stats to chr"
psql -h localhost -d chr -X -q <<'SQL'
do $$
declare f regprocedure;
begin
  for f in select oid::regprocedure from pg_proc where proname = 'pg_stat_statements_reset' loop
    execute format('grant execute on function %s to chr', f);
  end loop;
end $$;
SQL

echo
echo "Done. Check: $(psql -h localhost -U chr -d chr -X -A -t -c "select 'track_io_timing=' || current_setting('track_io_timing') || ', pg_stat_statements=' || (select extversion from pg_extension where extname = 'pg_stat_statements')")"
echo "The run scripts will now also measure SQL statement times and I/O time."
echo "To undo: ./setup_pg_monitoring.sh --undo"
