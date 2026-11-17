#!/bin/sh
# Hoppscotch boot for Railway. The start command replaces the image ENTRYPOINT, so this script is the entrypoint:
# migrate, close onboarding, seed the administrator credentials, put the web app on Railway's PORT, start the AIO server.
set -eu

fail() { echo "hoppscotch boot: $*" >&2; exit 1; }

: "${DATABASE_URL:?set DATABASE_URL}"
: "${DATA_ENCRYPTION_KEY:?set DATA_ENCRYPTION_KEY}"
: "${HOPPSCOTCH_INFRA_TOKEN:?set HOPPSCOTCH_INFRA_TOKEN}"
: "${RAILWAY_PUBLIC_DOMAIN:?RAILWAY_PUBLIC_DOMAIN is empty: the service needs a public domain}"
[ "${#DATA_ENCRYPTION_KEY}" -eq 32 ] || fail "DATA_ENCRYPTION_KEY must be exactly 32 characters"
for v in HOPPSCOTCH_INFRA_TOKEN; do
  eval "val=\$$v"
  case "$val" in *[!A-Za-z0-9]*) fail "$v may only contain letters and digits";; esac
  [ "${#val}" -ge 32 ] || fail "$v must be at least 32 characters"
done

PUBLIC_PORT="${PORT:-8080}"
export PG_MODULE="$(ls -d /dist/backend/node_modules/.pnpm/pg@*/node_modules/pg | head -1)"
[ -n "$PG_MODULE" ] || fail "pg module not found in the image"

# The backend listens on 3170; Caddy takes Railway's PORT (the healthcheck and the edge both dial it).
export PORT=3170
BASE="https://$RAILWAY_PUBLIC_DOMAIN"
export VITE_BASE_URL="$BASE" VITE_SHORTCODE_BASE_URL="$BASE" VITE_ADMIN_URL="$BASE/admin"
export VITE_BACKEND_GQL_URL="$BASE/backend/graphql" VITE_BACKEND_API_URL="$BASE/backend/v1"
export VITE_BACKEND_WS_URL="wss://$RAILWAY_PUBLIC_DOMAIN/backend/graphql"
export WHITELISTED_ORIGINS="$BASE,app://hoppscotch,app://localhost_3200,http://localhost:3200"
export ENABLE_SUBPATH_BASED_ACCESS=true
unset HOPP_ALTERNATE_PORT HOPP_AIO_ALTERNATE_PORT

cd /dist/backend
n=0
until ./node_modules/.bin/prisma migrate deploy >/tmp/migrate.log 2>&1; do
  n=$((n+1)); [ "$n" -le 40 ] || { cat /tmp/migrate.log >&2; fail "migrations did not apply"; }
  sleep 3
done
echo "hoppscotch boot: migrations applied"

node /tmp/hoppscotch-seed.js pre

# The backend fills InfraConfig on its first start and then stops itself on purpose. Let that happen here, before the
# real start, so the container does not exit under Railway.
i=0
while [ "$(node /tmp/hoppscotch-seed.js count)" -lt 40 ]; do
  i=$((i+1)); [ "$i" -le 4 ] || fail "InfraConfig was not populated"
  echo "hoppscotch boot: populating InfraConfig (pass $i)"
  timeout 40 node /dist/backend/dist/src/main.js >/tmp/populate.log 2>&1 || true
done

node /tmp/hoppscotch-seed.js post
echo "hoppscotch boot: administrator and infra token seeded"

# Move Caddy to Railway's PORT and point it at the backend's new port.
sed -i -e "s|^:{\$HOPP_ALTERNATE_PORT:80} {|:$PUBLIC_PORT {|" -e 's|localhost:8080|localhost:3170|g' /etc/caddy/aio-subpath-access.Caddyfile
grep -q "^:$PUBLIC_PORT {" /etc/caddy/aio-subpath-access.Caddyfile || fail "could not rewrite the Caddyfile"

exec node /usr/src/app/aio_run.mjs
