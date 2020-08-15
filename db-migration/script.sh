#!/bin/sh
ROOTDIR=/var/lib/postgresql

echo "Removing connections and dropping database ..."
psql -U sonar postgres -f $ROOTDIR/migration-scripts/drop-table.sql

echo "Restoring database ..."
createdb -U sonar sonar
psql -U sonar sonar < $ROOTDIR/backups/db_dump.sql 

echo "Allowing connections back up ..."
psql -U sonar postgres -f $ROOTDIR/migration-scripts/allow-connections.sql
