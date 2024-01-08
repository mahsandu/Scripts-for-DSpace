#!/bin/bash

# Define some variables
ds_home="/home/iubar/repository"
ds_live="/home/iubar/repository/live-repository"
tomcat_home="/home/iubar/tomcat"
ds_user="iubar"
ds_group="iubar"
ds_src_url="https://codeload.github.com/DSpace/DSpace/tar.gz/refs/tags/dspace-7.6"

#Solr Variables
solr_home="/opt/solr"
solr_version="8.11.2"
solr_install_dir="$solr_home"
solr_port="8983"
core_name="iubar"  # Replace with your desired Solr core name
solr_user="solr"  # Replace with a non-root user for Solr
server_ip="10.50.200.69"

# Create a system user for DSpace
useradd -m -d "$ds_home" -s /bin/bash -U -c "DSpace User" "$ds_user"

# Install required software
apt-get update
apt-get -y install openjdk-17-jdk maven ant wget curl git

# Add PostgreSQL APT repository and install PostgreSQL
apt-get -y install postgresql postgresql-client postgresql-contrib
# Configure PostgreSQL
sudo -u postgres createuser -U postgres -d -A -P "$ds_user"
sudo -u postgres createdb -U postgres -O "$ds_user" "$ds_user"
sudo -u postgres psql -U postgres -d "$ds_user" -c "CREATE EXTENSION pgcrypto;"


#Install Solr

# Function to log messages with timestamps
log() {
  echo "$(date +"%Y-%m-%d %T") - $1"
}

# Check if Solr is already installed
if [ -d "$solr_install_dir/solr-$solr_version" ]; then
  log "Solr $solr_version is already installed. Exiting."
  exit 0
fi

# Create Solr installation directory
log "Creating Solr installation directory..."
mkdir -p "$solr_install_dir"

# Check if the directory creation was successful
if [ $? -ne 0 ]; then
  log "Error creating Solr installation directory. Exiting."
  exit 1
fi

# Download Solr
log "Downloading Solr $solr_version..."
wget "https://archive.apache.org/dist/lucene/solr/$solr_version/solr-$solr_version.tgz" -P /tmp

# Check if the download was successful
if [ $? -ne 0 ]; then
  log "Error downloading Solr. Exiting."
  exit 1
fi

# Extract Solr
log "Extracting Solr archive..."
tar -zxvf "/tmp/solr-$solr_version.tgz" -C "$solr_install_dir"

# Check if the extraction was successful
if [ $? -ne 0 ]; then
  log "Error extracting Solr archive. Exiting."
  exit 1
fi

# Create a non-root user for Solr
log "Creating Solr user..."
useradd -m -U -s /bin/false "$solr_user"

# Set correct ownership and permissions
log "Setting ownership and permissions..."
chown -R "$solr_user:$solr_user" "$solr_install_dir/solr-$solr_version"

# Create the Solr init.d script
SOLR_INIT_SCRIPT="/etc/init.d/solr"
SOLR_DEFAULT_START="2 3 4 5"
SOLR_DEFAULT_STOP="0 1 6"

# Check if the script already exists
if [ -e "$SOLR_INIT_SCRIPT" ]; then
  log "Solr init.d script already exists at $SOLR_INIT_SCRIPT. Aborting."
  exit 1
fi

# Create the Solr init.d script
cat <<EOL > "$SOLR_INIT_SCRIPT"
#!/bin/bash
### BEGIN INIT INFO
# Provides:          solr
# Required-Start:    \$remote_fs \$syslog
# Required-Stop:     \$remote_fs \$syslog
# Default-Start:     $SOLR_DEFAULT_START
# Default-Stop:      $SOLR_DEFAULT_STOP
# Short-Description: Apache Solr is an open source search platform built on Apache Lucene.
# Description:       Apache Solr is an open source search platform built on Apache Lucene.
### END INIT INFO

SOLR_HOME="$solr_install_dir/solr-$solr_version"
SOLR_USER="$solr_user"
SOLR_START_CMD="\${SOLR_HOME}/bin/solr start -p $solr_port"
SOLR_STOP_CMD="\${SOLR_HOME}/bin/solr stop"
SOLR_STATUS_CMD="\${SOLR_HOME}/bin/solr status"

start() {
    echo -n "Starting Solr: "
    su - \${SOLR_USER} -c "\${SOLR_START_CMD}"
    echo
}

stop() {
    echo -n "Stopping Solr: "
    su - \${SOLR_USER} -c "\${SOLR_STOP_CMD}"
    echo
}

status() {
    echo -n "Checking Solr status: "
    su - \${SOLR_USER} -c "\${SOLR_STATUS_CMD}"
    echo
}

case "\$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOL

# Make the script executable
chmod +x "$SOLR_INIT_SCRIPT"

#Set Necessary Permissions
chown -R "$solr_user:$solr_user" "$solr_install_dir/solr-$solr_version"

# Start Solr as a non-root user
log "Starting Solr service..."

systemctl enable --now solr.service

# Create a Solr core for DSpace
log "Creating Solr core '$core_name' for DSpace..."
sudo -u "$solr_user" "$solr_install_dir/solr-$solr_version/bin/solr" create_core -c "$core_name" -d "$solr_home" -p "$solr_port"

# Enable Solr core for DSpace in Solr configuration
dspace_core_config="$solr_install_dir/solr-$solr_version/server/solr/$core_name/core.properties"
echo "name=$core_name" > "$dspace_core_config"

# Check if Solr service is running
if systemctl is-active solr.service; then
    log "Solr service is running."
else
    log "Solr service is not running."
fi
solr_version=$(systemctl show -p Version solr.service)
log "Solr $solr_version has been installed, configured and is running. Please check in the browser http://"$server_ip":"$solr_port"/solr/#/"


# Download DSpace source code
mkdir -p "$ds_home"
cd "$ds_home"
wget "$ds_src_url"
mv DSpace-dspace-7.6 DSpace-7.6-release.tar.gz
tar -zxvf DSpace-7.6-release.tar.gz
rm DSpace-7.6-release.tar.gz
cd DSpace-dspace-7.6
$ds_src_dir=pwd

# Configure DSpace
sudo cp -r config/local.cfg.EXAMPLE config/local.cfg
sudo cp -r config/modules/default.cfg.EXAMPLE config/modules/default.cfg

# Your additional configuration lines
additional_config="
dspace.dir=$ds_live
dspace.server.url = http://localhost:8080/server
dspace.ui.url = http://localhost:4000
dspace.name = IUB Academic Repository
assetstore.dir = \${dspace.dir}/assetstore
#solr.server = http://localhost:8983/solr
db.url = jdbc:postgresql://localhost:5432/\"$ds_user\"
db.username = \"$ds_user\"
db.password = \"$ds_user\"2010
#mail.server = smtp.example.com
#mail.server.username = myusername
#mail.server.password = mypassword
#mail.server.port = 25
#mail.from.address = dspace-noreply@myu.edu
#feedback.recipient = dspace-help@myu.edu
#mail.admin = dspace-help@myu.edu
#mail.helpdesk = \${mail.admin}
#mail.helpdesk.name = Help Desk
#alert.recipient = \${mail.admin}
#registration.notify =
#handle.canonical.prefix = https://hdl.handle.net/
#handle.canonical.prefix = http://hdl.handle.net/
#handle.prefix = 123456789
"

# Update the local.cfg file
while read -r line; do
  if [[ "$line" == *"#"* ]]; then
    # Ignore comments
    continue
  fi
  key=$(echo "$line" | cut -d'=' -f 1 | tr -d '[:space:]')
  if [[ ! -z "$key" ]]; then
    # Check if the key already exists
    grep -q "^$key=" "$ds_home/config/local.cfg"
    if [ $? -eq 0 ]; then
      # The key already exists, update the line
      sed -i "s/^$key=.*/$line/" "$ds_home/config/local.cfg"
    else
      # The key does not exist, append the line
      echo "$line" >> "$ds_home/config/local.cfg"
    fi
  fi
done <<< "$additional_config"

echo "Configuration lines have been added or updated in local.cfg."

sudo  mvn clean
sudo  mvn package
cd "$ds_live/bin"
sudo  ./dspace database migrate
sudo  ./dspace create-administrator
sudo  ./dspace run

# Create a system user for Tomcat
useradd -m -U -d "$TOMCAT_HOME" -s /bin/false -U -c "Apache Tomcat User" $ds_user

# Create the Tomcat directory and download Tomcat
mkdir -p $tomcat_home
cd $tomcat_home

# Scrape the latest Tomcat version from the Apache website
LATEST_VERSION=$(curl -s https://tomcat.apache.org/download-90.cgi | grep -o '9\.[0-9]\{1,2\}\.[0-9]\{1,2\}' | head -1)

# Replace the URL with the latest Tomcat version download link
TOMCAT_URL="https://downloads.apache.org/tomcat/tomcat-9/v$LATEST_VERSION/bin/apache-tomcat-$LATEST_VERSION.tar.gz"

wget "$TOMCAT_URL" -O tomcat.tar.gz
tar -xf tomcat.tar.gz --strip-components=1
rm tomcat.tar.gz

# Set permissions for the Tomcat directory
chown -R $ds_user:$ds_group $tomcat_home

# Create a systemd service file for Tomcat
cat <<EOF > /etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=$ds_user
Group=$ds_group
Environment=CATALINA_HOME=$tomcat_home
Environment=CATALINA_PID=$tomcat_home/temp/tomcat.pid
ExecStart=$tomcat_home/bin/startup.sh
ExecStop=$tomcat_home/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Tomcat
systemctl daemon-reload
systemctl start tomcat
systemctl enable tomcat

# Configure Tomcat to run as $ds_user
echo "CATALINA_PID=\"$tomcat_home/temp/tomcat.pid\"" >> /etc/default/tomcat9
echo "CATALINA_HOME=\"$tomcat_home\"" >> /etc/default/tomcat9
echo "CATALINA_BASE=\"$tomcat_home\"" >> /etc/default/tomcat9
echo "tomcat_user=$ds_user" >> /etc/default/tomcat9

# Modify Tomcat configuration for UTF-8 support
echo 'JAVA_OPTS="-Xmx512M -Xms64M -Dfile.encoding=UTF-8"' >> /etc/default/tomcat9
sed -i '/<Connector port="8080"/ a \    URIEncoding="UTF-8"' /etc/tomcat9/server.xml

# Clean up
cd "$ds_home"
chown -R "$ds_user:$ds_group" .
rm -rf /tmp/dspace

echo "DSpace 7.6 has been successfully installed and configured with JDK 17, PostgreSQL 15, Tomcat 9, and is running as $ds_user."

# Check if PostgreSQL service is running
if systemctl is-active --quiet postgresql; then
    echo "PostgreSQL service is running."
else
    echo "PostgreSQL service is not running."
fi

# Check if the DSpace database exists
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$ds_user"; then
    echo "DSpace database '$ds_user' exists."
else
    echo "DSpace database '$ds_user' does not exist."
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
