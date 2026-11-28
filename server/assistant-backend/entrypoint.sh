#!/usr/bin/env sh
set -eu
if [ "${SKIP_PRISMA_MIGRATE:-false}" != "true" ]; then
  npx prisma migrate deploy
fi
exec node dist/main
