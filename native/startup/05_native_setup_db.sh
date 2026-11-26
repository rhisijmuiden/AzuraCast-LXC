#!/bin/bash
# AzuraCast-LXC: replaces the Docker image's 05_setup_db.sh (which needs the MariaDB Docker
# entrypoint). Creates the data directory, database and user, imports the initial schema on a
# fresh install and runs mariadb-upgrade after a MariaDB package upgrade.
set -e

if [ ! -f /etc/supervisor/minimal.conf.d/mariadb.conf ]; then
    echo "MariaDB disabled (external database). Skipping DB initialization..."
    exit 0
fi

DB_NAME="${MYSQL_DATABASE:-azuracast}"
DB_USER="${MYSQL_USER:-azuracast}"
DB_PASS="${MYSQL_PASSWORD:?MYSQL_PASSWORD is not set in /etc/azuracast/azuracast.env}"
SOCKET=/run/mysqld/mysqld.sock

if [ ! -d /var/lib/mysql/mysql ]; then
    echo "Initializing MariaDB data directory..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db --auth-root-authentication-method=socket >/dev/null
fi

echo "Starting temporary MariaDB for setup..."
gosu mysql mariadbd --skip-networking --socket="$SOCKET" &
DB_PID=$!

for _ in $(seq 1 60); do
    if mariadb-admin --socket="$SOCKET" ping >/dev/null 2>&1; then break; fi
    sleep 1
done
mariadb-admin --socket="$SOCKET" ping >/dev/null 2>&1 || { echo "MariaDB did not start."; kill "$DB_PID" || true; exit 1; }

mariadb-upgrade --socket="$SOCKET" --silent >/dev/null 2>&1 || true

esc_pass=$(printf '%s' "$DB_PASS" | sed "s/'/''/g")
mariadb --socket="$SOCKET" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${esc_pass}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${esc_pass}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${esc_pass}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${esc_pass}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

TABLES=$(mariadb --socket="$SOCKET" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'")
if [ "$TABLES" = "0" ] && [ -f /usr/local/share/azuracast/db.sql ]; then
    echo "Importing initial database schema..."
    mariadb --socket="$SOCKET" "$DB_NAME" </usr/local/share/azuracast/db.sql
fi

mariadb-admin --socket="$SOCKET" shutdown
wait "$DB_PID" || true
echo "Database ready."
