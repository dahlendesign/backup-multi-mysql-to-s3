#! /bin/sh

set -e
i=$1

echo "Job $i started"

eval MYSQLDUMP_OPTIONS=\$MYSQLDUMP_OPTIONS_$i
eval MYSQLDUMP_DATABASE=\$MYSQLDUMP_DATABASE_$i
eval MYSQL_HOST=\$MYSQL_HOST_$i
eval MYSQL_PORT=\$MYSQL_PORT_$i
eval MYSQL_USER=\$MYSQL_USER_$i
eval MYSQL_PASSWORD=\$MYSQL_PASSWORD_$i
eval S3_ACCESS_KEY_ID=\$S3_ACCESS_KEY_ID_$i
eval S3_SECRET_ACCESS_KEY=\$S3_SECRET_ACCESS_KEY_$i
eval S3_BUCKET=\$S3_BUCKET_$i
eval S3_REGION=\$S3_REGION_$i
eval S3_ENDPOINT=\$S3_ENDPOINT_$i
eval S3_S3V4=\$S3_S3V4_$i
eval S3_PREFIX=\$S3_PREFIX_$i
eval S3_VERSIONING=\$S3_VERSIONING_$i
eval MULTI_FILES=\$MULTI_FILES_$i
#eval SCHEDULE=\$SCHEDULE_$i

if [ "${MYSQLDUMP_OPTIONS}" != "**None**" ]; then
  USE_MYSQLDUMP_OPTIONS=${MYSQLDUMP_OPTIONS}
else
  USE_MYSQLDUMP_OPTIONS=${MYSQLDUMP_OPTIONS_GLOBAL}
fi
if [ "${MYSQLDUMP_DATABASE}" != "**None**" ]; then
  USE_MYSQLDUMP_DATABASE=${MYSQLDUMP_DATABASE}
else
  USE_MYSQLDUMP_DATABASE=${MYSQLDUMP_DATABASE_GLOBAL}
fi
if [ "${MYSQL_HOST}" != "**None**" ]; then
  USE_MYSQL_HOST=${MYSQL_HOST}
else
  USE_MYSQL_HOST=${MYSQL_HOST_GLOBAL}
fi
if [ "${MYSQL_PORT}" != "**None**" ]; then
  USE_MYSQL_PORT=${MYSQL_PORT}
else
  USE_MYSQL_PORT=${MYSQL_PORT_GLOBAL}
fi
if [ "${MYSQL_USER}" != "**None**" ]; then
  USE_MYSQL_USER=${MYSQL_USER}
else
  USE_MYSQL_USER=${MYSQL_USER_GLOBAL}
fi
if [ "${MYSQL_PASSWORD}" != "**None**" ]; then
  USE_MYSQL_PASSWORD=${MYSQL_PASSWORD}
else
  USE_MYSQL_PASSWORD=${MYSQL_PASSWORD_GLOBAL}
fi
if [ "${S3_ACCESS_KEY_ID}" != "**None**" ]; then
  USE_S3_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID}
else
  USE_S3_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID_GLOBAL}
fi
if [ "${S3_SECRET_ACCESS_KEY}" != "**None**" ]; then
  USE_S3_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY}
else
  USE_S3_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY_GLOBAL}
fi
if [ "${S3_BUCKET}" != "**None**" ]; then
  USE_S3_BUCKET=${S3_BUCKET}
else
  USE_S3_BUCKET=${S3_BUCKET_GLOBAL}
fi
if [ "${S3_REGION}" != "**None**" ]; then
  USE_S3_REGION=${S3_REGION}
else
  USE_S3_REGION=${S3_REGION_GLOBAL}
fi
if [ "${S3_ENDPOINT}" != "**None**" ]; then
  USE_S3_ENDPOINT=${S3_ENDPOINT}
else
  USE_S3_ENDPOINT=${S3_ENDPOINT_GLOBAL}
fi
if [ "${S3_S3V4}" != "**None**" ]; then
  USE_S3_S3V4=${S3_S3V4}
else
  USE_S3_S3V4=${S3_S3V4_GLOBAL}
fi
if [ "${S3_PREFIX}" != "**None**" ]; then
  USE_S3_PREFIX=${S3_PREFIX}
else
  USE_S3_PREFIX=${S3_PREFIX_GLOBAL}
fi
if [ "${S3_VERSIONING}" != "**None**" ]; then
  USE_S3_VERSIONING=${S3_VERSIONING}
else
  USE_S3_VERSIONING=${S3_VERSIONING_GLOBAL}
fi
if [ "${MULTI_FILES}" != "**None**" ]; then
  USE_MULTI_FILES=${MULTI_FILES}
else
  USE_MULTI_FILES=${MULTI_FILES_GLOBAL}
fi

if [ "${USE_S3_ACCESS_KEY_ID}" == "**None**" ]; then
  echo " Warning: You did not set the S3_ACCESS_KEY_ID environment variable global or on job $i."
fi

if [ "${USE_S3_SECRET_ACCESS_KEY}" == "**None**" ]; then
  echo " Warning: You did not set the S3_SECRET_ACCESS_KEY environment variable global or on job $i."
fi

if [ "${USE_S3_BUCKET}" == "**None**" ]; then
  echo " You need to set the S3_BUCKET environment variable global or on job $i."
  exit 1
fi

if [ "${USE_MYSQL_HOST}" == "**None**" ]; then
  echo " You need to set the MYSQL_HOST environment variable global or on job $i."
  exit 1
fi

if [ "${USE_MYSQL_USER}" == "**None**" ]; then
  echo " You need to set the MYSQL_USER environment variable global or on job $i."
  exit 1
fi

if [ "${USE_MYSQL_PASSWORD}" == "**None**" ]; then
  echo " You need to set the MYSQL_PASSWORD environment variable or link to a container named MYSQL."
  exit 1
fi

if [ "${USE_S3_S3V4}" == "yes" ]; then
  aws configure set default.s3.signature_version s3v4
fi

export AWS_ACCESS_KEY_ID=$USE_S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$USE_S3_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$USE_S3_REGION

MYSQL_HOST_OPTS="-h $USE_MYSQL_HOST -P $USE_MYSQL_PORT -u$USE_MYSQL_USER -p$USE_MYSQL_PASSWORD"
DUMP_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")

copy_s3 () {
  SRC_FILE=$1
  DEST_FILE=$2

  if [ "${USE_S3_ENDPOINT}" == "**None**" ]; then
    AWS_ARGS=""
  else
    AWS_ARGS="--endpoint-url ${USE_S3_ENDPOINT}"
  fi

  echo " Uploading ${DEST_FILE} on S3..."

  cat $SRC_FILE | aws $AWS_ARGS s3 cp - s3://$USE_S3_BUCKET/$USE_S3_PREFIX/$DEST_FILE

  if [ $? != 0 ]; then
    >&2 echo " Error uploading ${DEST_FILE} on S3"
  fi

  rm $SRC_FILE
}
# Multi file: yes
if [ ! -z "$(echo $USE_MULTI_FILES | grep -i -E "(yes|true|1)")" ]; then
  if [ "${USE_MYSQLDUMP_DATABASE}" == "--all-databases" ]; then
    DATABASES=`mysql $MYSQL_HOST_OPTS -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys|innodb)"`
  else
    DATABASES=$USE_MYSQLDUMP_DATABASE
  fi

  for DB in $DATABASES; do
    echo " Creating individual dump of ${DB} from ${MYSQL_HOST}..."

    DUMP_FILE="/tmp/${DB}.sql.gz"

    mysqldump $MYSQL_HOST_OPTS $USE_MYSQLDUMP_OPTIONS --databases $DB | gzip > $DUMP_FILE

    if [ $? == 0 ]; then
      S3_FILE="${DUMP_START_TIME}.${DB}.sql.gz"

      copy_s3 $DUMP_FILE $S3_FILE
    else
      >&2 echo " Error creating dump of ${DB}"
    fi
  done
# Multi file: no
else
  echo " Creating dump for ${USE_MYSQLDUMP_DATABASE} from ${USE_MYSQL_HOST}..."

  DUMP_FILE="/tmp/dump-${USE_MYSQL_HOST}-${USE_MYSQLDUMP_DATABASE}.sql.gz"
  mysqldump $MYSQL_HOST_OPTS $USE_MYSQLDUMP_OPTIONS $USE_MYSQLDUMP_DATABASE | gzip > $DUMP_FILE

  if [ $? == 0 ]; then
    if [ ! -z "$(echo $USE_S3_VERSIONING | grep -i -E "(yes|true|1)")" ]; then
      S3_FILE="dump-${USE_MYSQL_HOST}-${USE_MYSQLDUMP_DATABASE}.sql.gz"
    else
      S3_FILE="dump-${USE_MYSQL_HOST}-${USE_MYSQLDUMP_DATABASE}-${DUMP_START_TIME}.sql.gz"
    fi

    copy_s3 $DUMP_FILE $S3_FILE
  else
    >&2 echo " Error creating dump of all databases"
  fi
fi

echo "Job $i finished"
