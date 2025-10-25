#!/bin/bash
echo "Entry point to CKG Docker"
cd /CKG

echo "Detecting public IP address for Neo4j configuration"
# Try to get EC2 public IP with IMDSv2 token
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
if [ -n "$TOKEN" ]; then
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
else
    # Fallback to IMDSv1
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
fi

if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "metadata_unavailable" ]; then
    echo "Detected public IP: $PUBLIC_IP"
    echo "Updating Neo4j configuration with advertised address"

    # Update bolt advertised_address in neo4j.conf
    if grep -q "^dbms.connector.bolt.advertised_address=" /etc/neo4j/neo4j.conf; then
        sed -i "s|^dbms.connector.bolt.advertised_address=.*|dbms.connector.bolt.advertised_address=${PUBLIC_IP}:7687|" /etc/neo4j/neo4j.conf
    elif grep -q "^#dbms.connector.bolt.advertised_address=" /etc/neo4j/neo4j.conf; then
        sed -i "s|^#dbms.connector.bolt.advertised_address=.*|dbms.connector.bolt.advertised_address=${PUBLIC_IP}:7687|" /etc/neo4j/neo4j.conf
    else
        echo "dbms.connector.bolt.advertised_address=${PUBLIC_IP}:7687" >> /etc/neo4j/neo4j.conf
    fi

    # Update http advertised_address in neo4j.conf
    if grep -q "^dbms.connector.http.advertised_address=" /etc/neo4j/neo4j.conf; then
        sed -i "s|^dbms.connector.http.advertised_address=.*|dbms.connector.http.advertised_address=${PUBLIC_IP}:7474|" /etc/neo4j/neo4j.conf
    elif grep -q "^#dbms.connector.http.advertised_address=" /etc/neo4j/neo4j.conf; then
        sed -i "s|^#dbms.connector.http.advertised_address=.*|dbms.connector.http.advertised_address=${PUBLIC_IP}:7474|" /etc/neo4j/neo4j.conf
    else
        echo "dbms.connector.http.advertised_address=${PUBLIC_IP}:7474" >> /etc/neo4j/neo4j.conf
    fi

    echo "Neo4j will advertise at: bolt://${PUBLIC_IP}:7687 and http://${PUBLIC_IP}:7474"
else
    echo "WARNING: Could not detect public IP. Neo4j will use default advertised address (localhost)"
fi

echo "Starting Neo4j"
service neo4j start &
service neo4j status

while ! [[ `wget -S --spider http://localhost:7474  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; do
echo "Database not ready"
sleep 45
done

echo "Database ready"
echo "Creating Test user in the database"
python3 ckg/graphdb_builder/builder/create_user.py -u test_user -d test_user -n test -e test@ckg.com -a test -p 12345678

echo "Running jupyterHub"
jupyterhub -f /etc/jupyterhub/jupyterhub.py --no-ssl &

echo "Running redis-server"
service redis-server start

echo "Running celery queues"
cd ckg/report_manager
celery -A ckg.report_manager.worker worker --loglevel=INFO --concurrency=1 -E -Q creation --uid 1500 --gid nginx &
celery -A ckg.report_manager.worker worker --loglevel=INFO --concurrency=3 -E -Q compute --uid 1500 --gid nginx &
celery -A ckg.report_manager.worker worker --loglevel=INFO --concurrency=1 -E -Q update --uid 1500 --gid nginx &

echo "Initiating CKG app"
cd /CKG
nginx && uwsgi --ini /etc/uwsgi/apps-enabled/uwsgi.ini --uid 1500 --gid nginx
