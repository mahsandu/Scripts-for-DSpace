#!/bin/bash

# Define some variables
DS_HOME="/home/IUBAR/REPOSITORY"
TOMCAT_HOME="/home/IUBAR/TOMCAT"
SOLR_HOME="/home/IUBAR/SOLR"
DS_USER="IUBAR"
DS_GROUP="IUBAR"
DS_SRC_URL="https://codeload.github.com/DSpace/DSpace/tar.gz/refs/tags/dspace-7.6"

# Install required software
apt-get update
apt-get -y install openjdk-17-jdk maven ant wget curl

# Add PostgreSQL APT repository and install PostgreSQL

apt-get -y install postgresql postgresql-client postgresql-contrib

# Create a system user for DSpace
useradd -m -d "$DS_HOME" -s /bin/bash -U -c "DSpace User" "$DS_USER"

# Download DSpace source code  
mkdir -p "$DS_HOME"
cd "$DS_HOME"
wget "$DS_SRC_URL"
mv dspace-7.6 dspace-7.6-release.tar.gz
tar -zxvf dspace-7.6-release.tar.gz
rm dspace-7.6-release.tar.gz
cd DSpace-dspace-7.6

# Configure PostgreSQL
sudo -u postgres createuser -U postgres -d -A -P "$DS_USER"
sudo -u postgres createdb -U postgres -O "$DS_USER" "$DS_USER"
sudo -u postgres psql -U postgres -d "$DS_USER" -c "CREATE EXTENSION pgcrypto;"

# Configure DSpace
sudo  cp -r config/local.cfg.EXAMPLE config/local.cfg
sudo  cp -r config/modules/default.cfg.EXAMPLE config/modules/default.cfg
sudo  mvn clean
sudo  mvn package
sudo  ./dspace database migrate
sudo  ./dspace create-administrator
sudo  ./dspace run

# Define some variables
TOMCAT_USER="$DS_USER"
TOMCAT_GROUP="$DS_USER"

# Create a system user for Tomcat
useradd -m -U -d /opt/tomcat -s /bin/false -U -c "Apache Tomcat User" $TOMCAT_USER

# Create the Tomcat directory and download Tomcat
mkdir -p $TOMCAT_HOME
cd $TOMCAT_HOME

# Scrape the latest Tomcat version from the Apache website
LATEST_VERSION=$(curl -s https://tomcat.apache.org/download-90.cgi | grep -o '9\.[0-9]\{1,2\}\.[0-9]\{1,2\}' | head -1)

# Replace the URL with the latest Tomcat version download link
TOMCAT_URL="https://downloads.apache.org/tomcat/tomcat-9/v$LATEST_VERSION/bin/apache-tomcat-$LATEST_VERSION.tar.gz"

wget "$TOMCAT_URL" -O tomcat.tar.gz
tar -xf tomcat.tar.gz --strip-components=1
rm tomcat.tar.gz

# Set permissions for the Tomcat directory
chown -R $TOMCAT_USER:$TOMCAT_GROUP $TOMCAT_HOME

# Create a systemd service file for Tomcat
cat <<EOF > /etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=$TOMCAT_USER
Group=$TOMCAT_GROUP
Environment=CATALINA_HOME=$TOMCAT_HOME
Environment=CATALINA_PID=$TOMCAT_HOME/temp/tomcat.pid
ExecStart=$TOMCAT_HOME/bin/startup.sh
ExecStop=$TOMCAT_HOME/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Tomcat
systemctl daemon-reload
systemctl start tomcat
systemctl enable tomcat

# Print installation completion message
echo "Tomcat $TOMCAT_VERSION has been successfully installed."

# Configure Tomcat to run as $DS_USER
echo "CATALINA_PID=\"$TOMCAT_HOME/temp/tomcat.pid\"" >> /etc/default/tomcat9
echo "CATALINA_HOME=\"$TOMCAT_HOME\"" >> /etc/default/tomcat9
echo "CATALINA_BASE=\"$TOMCAT_HOME\"" >> /etc/default/tomcat9
echo "TOMCAT_USER=$DS_USER" >> /etc/default/tomcat9

# Modify Tomcat configuration for UTF-8 support
echo 'JAVA_OPTS="-Xmx512M -Xms64M -Dfile.encoding=UTF-8"' >> /etc/default/tomcat9
sed -i '/<Connector port="8080"/ a \    URIEncoding="UTF-8"' /etc/tomcat9/server.xml

# Clean up
cd "$DS_HOME"
chown -R "$DS_USER:$DS_GROUP" .
rm -rf /tmp/dspace

echo "DSpace 7.6 has been successfully installed and configured with JDK 17, PostgreSQL 15, Tomcat 9, and is running as $DS_USER."

# Check if PostgreSQL service is running
if systemctl is-active --quiet postgresql; then
    echo "PostgreSQL service is running."
else
    echo "PostgreSQL service is not running."
fi

# Check if the DSpace database exists
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DS_USER"; then
    echo "DSpace database '$DS_USER' exists."
else
    echo "DSpace database '$DS_USER' does not exist."
fi

# Check if Tomcat service is running
if systemctl is-active --quiet tomcat; then
    echo "Tomcat service is running."
else
    echo "Tomcat service is not running."
fi

# Check if Tomcat is listening on port 8080
if nc -z -v -w5 localhost 8080; then
    echo "Tomcat is listening on port 8080."
else
    echo "Tomcat is not listening on port 8080."
fi
# Check if DSpace is running
if curl -s --head --request GET http://localhost:8080/ | grep "HTTP/1.1 200 OK" > /dev/null; then
    echo "DSpace is running and accessible."
else
    echo "DSpace is not running or not accessible."
fi

  
  
