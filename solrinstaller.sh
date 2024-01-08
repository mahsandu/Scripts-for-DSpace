#!/bin/bash

# Define some variables
solr_home="/opt/solr"
solr_version="8.11.2"
solr_install_dir="$solr_home"
solr_port="8983"
core_name="iubar"  # Replace with your desired Solr core name
solr_user="iubar"  # Replace with a non-root user for Solr
server_ip="10.50.200.69"

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
