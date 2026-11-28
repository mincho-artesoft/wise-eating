#!/bin/bash
# Runs a command against a throwaway local Postgres: a fresh data directory
# under .test-db/, a private port and socket, the migrations applied, then
# everything removed. Nothing touches another database.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
dir="$here/.test-db"
port="${TEST_PG_PORT:-55432}"
bin="$(dirname "$(command -v pg_ctl || echo /opt/homebrew/opt/postgresql@17/bin/pg_ctl)")"
rm -rf "$dir"; mkdir -p "$dir"
LC_ALL=C LANG=C "$bin/initdb" -D "$dir/data" -A trust -U postgres --locale=C -E UTF8 >/dev/null
LC_ALL=C "$bin/pg_ctl" -D "$dir/data" -o "-p $port -k $dir -c listen_addresses=''" -l "$dir/log" -w start >/dev/null
cleanup() { "$bin/pg_ctl" -D "$dir/data" -m fast -w stop >/dev/null 2>&1 || true; rm -rf "$dir"; }
trap cleanup EXIT
"$bin/createdb" -h "$dir" -p "$port" -U postgres ayura_test
export DATABASE_URL="postgresql://postgres@localhost:$port/ayura_test?host=$dir"
export NODE_ENV=test
cd "$here"
npx prisma migrate deploy >/dev/null
if [ "$1" = node ]; then shift; NODE_ENV=development node "$@"; else npx "$@"; fi
