#!/bin/sh
set -eu

cd /host

echo "[demo] waiting for postgres..."
until pg_isready -h db -p 5432 -U escalated >/dev/null 2>&1; do sleep 1; done

echo "[demo] db:prepare"
bin/rails db:drop db:create db:migrate db:seed RAILS_ENV=demo 2>&1 || echo "[demo] db steps failed"

echo "[demo] ready"
exec "$@"
