#!/usr/bin/env bash
# Starts the TAK Server database, setting the password from configuration.
# Safe on every start.
set -euo pipefail
: "${POSTGRES_PASSWORD:?}"

# Some image builds ship with an empty data folder. Create the database
# cluster on first start if it isn't there yet.
if [[ ! -f "$PGDATA/PG_VERSION" ]]; then
  echo "Creating database cluster in $PGDATA"
  initdb -D "$PGDATA" --no-locale -E UTF8
fi

# Default initdb listens on localhost only. TAK Server connects over the
# Docker network, and a reload does not apply listen_addresses.
conf="$PGDATA/postgresql.conf"
if [[ -f "$conf" ]] && grep -q "^listen_addresses" "$conf"; then
  sed -i "s/^listen_addresses.*/listen_addresses = '*'/" "$conf"
else
  echo "listen_addresses = '*'" >> "$conf"
fi
hba="$PGDATA/pg_hba.conf"
if [[ -f "$hba" ]] && ! grep -q "0.0.0.0/0" "$hba"; then
  printf '%s\n' "host all all 0.0.0.0/0 md5" "host all all ::/0 md5" >> "$hba"
fi

# The image restarts Postgres with systemctl. This container has no systemd,
# so that restart never happens and the new listen address never applies.
for script in /opt/tak/db-utils/*.sh; do
  [[ -f "$script" ]] || continue
  sed -i \
    -e "s|systemctl restart postgresql[^\"']*|pg_ctl -D \"$PGDATA\" -m fast -w restart|g" \
    -e "s|systemctl reload postgresql[^\"']*|pg_ctl -D \"$PGDATA\" reload|g" \
    "$script"
done

# An existing cot database makes the stock script wait for the word "erase"
# and then exit. Keep the database and let SchemaManager upgrade it.
setup=/opt/tak/db-utils/takserver-setup-db.sh
if [[ -f "$setup" ]]; then
  sed -i "s/echo \"User didn't say 'erase'. Aborting.\"/echo \"Keeping existing cot database.\"/" "$setup"
  sed -i "/Keeping existing cot database./{n;s/exit 1/exit 0/;}" "$setup"
fi

export envpass="$POSTGRES_PASSWORD"
exec /opt/tak/db-utils/configureInDocker.sh
