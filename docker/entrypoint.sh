#!/bin/sh
set -eu

cd /host

echo "[demo] waiting for postgres..."
until pg_isready -h db -p 5432 -U escalated >/dev/null 2>&1; do sleep 1; done

echo "[demo] working around duplicate gem migration version 041"
GEM_MIGRATIONS=$(bundle show escalated)/db/migrate
if [ -f "$GEM_MIGRATIONS/041_create_escalated_workflows.rb" ]; then
    mv "$GEM_MIGRATIONS/041_create_escalated_workflows.rb" \
       "$GEM_MIGRATIONS/044_create_escalated_workflows.rb" || true
fi

echo "[demo] db:prepare"
bin/rails db:drop db:create db:migrate db:seed RAILS_ENV=demo 2>&1 || echo "[demo] db steps failed"

echo "[demo] ready"
exec "$@"
