#!/bin/sh
APP=$1
TEAM=$2
VERSION=$3
HOSTNAME=$4
CLUSTER_ID=c-jpxcn
PROJECT_ID=p-zwxgj

if [[ -z $APP || -z $TEAM || -z $VERSION || -z $HOSTNAME ]]; then
  echo 'One or more variables are undefined, exiting script ...'
  exit 1
fi

echo "Logging in to rancher ..."
rancher login https://rancher.cd.murex.com/ --token token-vkq9d:wg8gtt4gbgtk7nzfhlj4gs87dn4w2hxhd9qmcb9fmnqkllgx57792r --context $CLUSTER_ID:$PROJECT_ID

echo "Creating new SonarQube instance"
rancher app install --values /data/$TEAM/$APP/migration/myvals.yaml --set hostname="$HOSTNAME" --set team="$TEAM" --set sonarqube.image.tag="$VERSION-community"  --version 0.1.0 --namespace $APP $APP $TEAM-$APP

ansible-playbook /data/$TEAM/$APP/migration/check-readiness.yaml --extra-vars "web_context=/sonar hostname=$HOSTNAME"

echo "Getting $APP PV names for team $TEAM..."
CONF_PV=$(kubectl get --all-namespaces pvc -l app=$APP,team=$TEAM,type=conf -o jsonpath="{.items[0].spec.volumeName}")
DATA_PV=$(kubectl get --all-namespaces pvc -l app=$APP,team=$TEAM,type=data -o jsonpath="{.items[0].spec.volumeName}")
EXTENSIONS_PV=$(kubectl get --all-namespaces pvc -l app=$APP,team=$TEAM,type=extensions -o jsonpath="{.items[0].spec.volumeName}")
LOGS_PV=$(kubectl get --all-namespaces pvc -l app=$APP,team=$TEAM,type=logs -o jsonpath="{.items[0].spec.volumeName}")
PG_PV=$(kubectl get --all-namespaces pvc -l app=$APP,team=$TEAM,type=pg -o jsonpath="{.items[0].spec.volumeName}")
PG_DATA_PV=$(kubectl get --all-namespaces pvc -l app=$APP,team=$TEAM,type=pg-data -o jsonpath="{.items[0].spec.volumeName}")

echo "Finding path on nfs ..."
CONF_PATH=$(kubectl get --all-namespaces pv $CONF_PV -o jsonpath="{.spec.nfs.path}" | rev | cut -d "/" -f1 | rev)
DATA_PATH=$(kubectl get --all-namespaces pv $DATA_PV -o jsonpath="{.spec.nfs.path}" | rev | cut -d "/" -f1 | rev)
EXTENSIONS_PATH=$(kubectl get --all-namespaces pv $EXTENSIONS_PV -o jsonpath="{.spec.nfs.path}" | rev | cut -d "/" -f1 | rev)
LOGS_PATH=$(kubectl get --all-namespaces pv $LOGS_PV -o jsonpath="{.spec.nfs.path}" | rev | cut -d "/" -f1 | rev)
PG_PATH=$(kubectl get --all-namespaces pv $PG_PV -o jsonpath="{.spec.nfs.path}" | rev | cut -d "/" -f1 | rev)
PG_DATA_PATH=$(kubectl get --all-namespaces pv $PG_DATA_PV -o jsonpath="{.spec.nfs.path}" | rev | cut -d "/" -f1 | rev)

echo "Getting pod name ..."
POD=$(kubectl get pod --all-namespaces -l app=$APP,team=$TEAM -o jsonpath="{.items[0].metadata.name}")

if [[ -z $CONF_PATH || -z $DATA_PATH || -z $EXTENSIONS_PATH || -z $LOGS_PATH || -z $PG_PATH || -z $PG_DATA_PATH ]]; then
  echo 'One or more nfs paths are unset, exiting script ...'
  exit 1
fi

echo "Copying SonarQube files to nfs ..."
unzip /data/$TEAM/$APP/documents/$APP-$VERSION.zip -d /data/$TEAM/$APP/documents/
rm -rf /mnt/nfs/$DATA_PATH/* /mnt/nfs/$CONF_PATH/* /mnt/nfs/$EXTENSIONS_PATH/* /mnt/nfs/$LOGS_PATH/*
cp -r /data/$TEAM/$APP/documents/$APP-$VERSION/data/* /mnt/nfs/$DATA_PATH/
cp -r /data/$TEAM/$APP/documents/$APP-$VERSION/conf/* /mnt/nfs/$CONF_PATH/
cp -r /data/$TEAM/$APP/documents/$APP-$VERSION/extensions/* /mnt/nfs/$EXTENSIONS_PATH/
cp -r /data/$TEAM/$APP/documents/$APP-$VERSION/logs/* /mnt/nfs/$LOGS_PATH/

echo "Copying migration scripts and database dump to nfs ..."
if [ ! -d "/mnt/nfs/$PG_PATH/migration-scripts" ]; then
    echo "migration-scripts directory does not exist, creating directory ..."
    mkdir /mnt/nfs/$PG_PATH/migration-scripts
fi

if [ ! -d "/mnt/nfs/$PG_PATH/backups" ]; then
    echo "backups directory does not exist, creating directory ..."
    mkdir /mnt/nfs/$PG_PATH/backups
fi

cp -r /data/$TEAM/$APP/migration/db-migration/* /mnt/nfs/$PG_PATH/migration-scripts/
cp -r /data/$TEAM/$APP/documents/db_dump.sql /mnt/nfs/$PG_PATH/backups/
chmod +x /mnt/nfs/$PG_PATH/migration-scripts/script.sh

echo "Running migration scripts to restore database ..."
kubectl -n sonarqube exec $POD -c sonardb -- bash -c "cd /var/lib/postgresql/migration-scripts && ./script.sh"

echo "Cleaning up volume from migration scripts ..."
rm -rf /mnt/nfs/$PG_PATH/migration-scripts

echo "Restarting the service ..."
rancher app upgrade --values /data/$TEAM/$APP/migration/myvals.yaml --set replicaCount='0' --set hostname="$HOSTNAME" --set team="$TEAM" --set sonarqube.image.tag="$VERSION-community"  $TEAM-$APP 0.1.0
sleep 7s
rancher app upgrade --values /data/$TEAM/$APP/migration/myvals.yaml --set hostname="$HOSTNAME" --set team="$TEAM" --set sonarqube.image.tag="$VERSION-community"  $TEAM-$APP 0.1.0

echo "Rechecking readiness ..."
ansible-playbook /data/$TEAM/$APP/migration/check-readiness.yaml --extra-vars "web_context=/sonar hostname=$HOSTNAME"

echo "SonarQube successfully merged, you can now access it on http://$HOSTNAME/sonar !"