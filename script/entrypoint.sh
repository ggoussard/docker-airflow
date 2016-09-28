#!/usr/bin/env bash 

AIRFLOW_HOME="/usr/local/airflow"
CMD="airflow"
TRY_LOOP="10"

# wait for DB
if [ "$1" != "flower" ] ; then
  if [ -z $AIRFLOW__CORE__SQL_ALCHEMY_CONN ]; then
      CONNECTION_STRING=`grep sql_alchemy_conn $AIRFLOW_HOME/airflow.cfg | sed -e ' *sql_alchemy_conn\ = *//'`
  else
      CONNECTION_STRING=$AIRFLOW__CORE__SQL_ALCHEMY_CONN
  fi
  PARSED_CONN_STR=`echo $CONNECTION_STRING | \
      sed -n -e 's/\([^:]*\):\/\/\([^:]*\):\([^@]*\)@\([^:/]*\)[:/]*\([^\/]*\)\/\(.*\)/\1 \2 \3 \4 \5 \6/p' | \
      tr -s ' '`
  DB_HOST=`echo $PARSED_CONN_STR | cut -d ' ' -f 4`
  DB_PORT=`echo $PARSED_CONN_STR | cut -d ' ' -f 5`
  DB_SCHEME=`echo $PARSED_CONN_STR | cut -d ' ' -f 1`
  if `echo $CONNECTION_STRING | grep -q -o "/$DB_PORT$"`; then
      case `echo $DB_SCHEME | cut -d '+' -f 1` in
          'postgresql') 
              DB_PORT=5432
              ;;
          'mysql')
              DB_PORT=3306
              ;;
          * )
              echo "$(date) - unsupported parameter DB connection string ${$CONNECTION_STRING}"
              exit 1
      esac
  fi

  i=0
  while ! nc -z $DB_HOST $DB_PORT >/dev/null 2>&1 < /dev/null; do
    i=$((i+1))
    if [ $i -ge $TRY_LOOP ]; then
      echo "$(date) - ${DB_HOST}:${DB_PORT} still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for ${DB_HOST}:${DB_PORT}... $i/$TRY_LOOP"
    sleep 5
  done
  if [ "$1" = "webserver" ]; then
    echo "Initialize database..."
    $CMD initdb
  fi
  sleep 5
fi

# If we use docker-compose, we use Celery (rabbitmq container).
if [ "x$AIRFLOW__CORE__EXECUTOR" = "xCeleryExecutor" ]; then
# wait for rabbitmq
if [ -z $AIRFLOW__CORE__BROKER_URL ]; then
      connection_string=`grep broker_url $AIRFLOW_HOME/airflow.cfg | sed -e 's/ *broker_url\ = *//'`
  else
      connection_string=$AIRFLOW__CORE__BROKER_URL
  fi
  parsed_conn_str=`echo $connection_string | \
      sed -n -e 's/\([^:]*\):\/\/\([^:]*\):\([^@]*\)@\([^:/]*\)[:/]*\([^\/]*\)\/\(.*\)/\1 \2 \3 \4 \5 \6/p' | \
      tr -s ' '`
  broker_scheme=`echo $parsed_conn_str | cut -d ' ' -f 1`
  broker_username=`echo $parsed_conn_str | cut -d ' ' -f 2`
  broker_password=`echo $parsed_conn_str | cut -d ' ' -f 3`
  broker_host=`echo $parsed_conn_str | cut -d ' ' -f 4`
  broker_port=`echo $parsed_conn_str | cut -d ' ' -f 5`
  if `echo $connection_string | grep -q -o "/$broker_port$"`; then
      case `echo $broker_scheme | cut -d '+' -f 1` in
          'amqp') 
              broker_port=5672
              ;;
          * )
              echo "$(date) - unsupported parameter broker connection string ${$CONNECTION_STRING}"
              exit 1
      esac
  fi



  j=0
  while ! curl -sI -u $broker_username:$broker_password http://$broker_host:15672/api/whoami |grep '200 OK'; do
      j=$((j+1))
      if [ $j -ge $TRY_LOOP ]; then
        echo "$(date) - $broker_host still not reachable, giving up"
        exit 1
      fi
      echo "$(date) - waiting for RabbitMQ... $j/$TRY_LOOP"
      sleep 5
    done
fi
exec $CMD "$@"
