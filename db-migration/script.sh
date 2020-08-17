#!/bin/sh
ROOTDIR=/var/lib/postgresql

echo "[$(date)] INFO: Removing connections and dropping database ..."
psql -U sonar postgres -f $ROOTDIR/migration-scripts/drop-table.sql

echo "[$(date)] INFO: Restoring database ..."
createdb -U sonar sonar
psql -U sonar sonar < $ROOTDIR/backups/db_dump.sql 

echo "[$(date)] INFO: Allowing connections back up ..."
psql -U sonar postgres -f $ROOTDIR/migration-scripts/allow-connections.sql
