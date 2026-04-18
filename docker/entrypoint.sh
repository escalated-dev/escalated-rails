#!/bin/sh
set -eu

cd /host

echo "[demo] waiting for postgres..."
until pg_isready -h db -p 5432 -U escalated >/dev/null 2>&1; do sleep 1; done

echo "[demo] db:prepare"
bin/rails db:prepare 2>&1 || echo "[demo] db:prepare skipped/failed"

echo "[demo] ready"
exec "$@"
