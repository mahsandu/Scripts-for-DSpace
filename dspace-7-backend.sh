#!/bin/bash

# Define some variables
ds_home="/home/iubar/repository"
ds_live="/home/iubar/repository/live-repository"
tomcat_home="/home/iubar/TOMCAT"
solr_home="/home/iubar/SOLR"
ds_user="iubar"
ds_group="iubar"
ds_src_url="https://codeload.github.com/DSpace/DSpace/tar.gz/refs/tags/dspace-7.6"

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

# Download Solr
solr_version="9.4.0"
solr_install_dir="$solr_home"
solr_port="8983"

wget "https://archive.apache.org/dist/lucene/solr/$solr_version/solr-$solr_version.tgz" -P /tmp
tar -zxvf "/tmp/solr-$solr_version.tgz" -C "$solr_install_dir"
rm "/tmp/solr-$solr_version.tgz"

# Modify Solr's solrconfig.xml for Solr 9.0.0
solr_config_file="$solr_install_dir/solr-$solr_version/server/solr/configsets/_default/conf/solrconfig.xml"
sed -i 's|<lib dir="${solr.install.dir}/contrib/analysis-extras/lib/|<lib dir="${solr.install.dir}/server/solr-webapp/webapp/WEB-INF/lib/|' "$solr_config_file"
sed -i 's|<lib dir="${solr.install.dir}/contrib/analysis-extras/lucene-libs/|<lib dir="${solr.install.dir}/server/solr-webapp/webapp/WEB-INF/lib/|' "$solr_config_file"
sed -i 's|<lib dir="${solr.install.dir}/contrib/extraction/lib" />|<lib dir="${solr.install.dir}/server/solr-webapp/webapp/WEB-INF/lib/extract" />|' "$solr_config_file"

# Start Solr
"$solr_install_dir/solr-$solr_version/bin/solr" start -p $solr_port

# Create a Solr core for DSpace
"$solr_install_dir/solr-$solr_version/bin/solr" create_core -c $ds_user -d "$solr_home" -p $solr_port

# Enable Solr core for DSpace in Solr configuration
dspace_core_config="$solr_install_dir/solr-$solr_version/server/solr/$ds_user/core.properties"
echo "name=$ds_user" > "$dspace_core_config"

# Check if Solr service is running
if ps aux | grep -v grep | grep -q "solr"; then
    echo "Solr service is running on port $solr_port."
else
    echo "Solr service is not running."
fi

echo "Solr $solr_version has been installed, configured for DSpace, and is running."


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
