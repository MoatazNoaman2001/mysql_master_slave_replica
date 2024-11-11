#!/bin/bash

docker-compose down -v
rm -rf ./master/data/* ./slave/data/*
docker-compose build
docker-compose up -d

# Set permissions for the MySQL configuration file on both master and slave containers
docker exec mysql_master chmod 644 /etc/mysql/conf.d/mysql.conf.cnf
docker exec mysql_slave chmod 644 /etc/mysql/conf.d/mysql.conf.cnf

# Wait until the MySQL master server is fully started and ready
until docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_master database connection..."
    sleep 4
done

# Create the replication user on the master server
priv_stmt='CREATE USER "mydb_slave_user"@"%" IDENTIFIED BY "mydb_slave_pwd"; GRANT REPLICATION SLAVE ON *.* TO "mydb_slave_user"@"%"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt'"

# Wait until the MySQL slave server is fully started and ready
until docker exec mysql_slave sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave database connection..."
    sleep 4
done

# Retrieve the master status information
MS_STATUS=`docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

# Configure and start the slave
start_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql_master',MASTER_USER='mydb_slave_user',MASTER_PASSWORD='mydb_slave_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave_cmd='export MYSQL_PWD=111; mysql -u root -e "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'
docker exec mysql_slave sh -c "$start_slave_cmd"

# Check the slave status
docker exec mysql_slave sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G'"
