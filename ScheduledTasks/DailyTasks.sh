#! /bin/bash
#           _.====.._
#         ,:._       ~-_
#             `\        ~-_
#               | _  _  |  `.
#             ,/ /_)/ | |    ~-_
#    -..__..-''  \_ \_\ `_      ~~--..__...----... BigWave ...
#
#Scheduled Tasks DSpaces - DAILY TASKS
#
#Remember -> dos2unix & chmod +x script.sh commands 
#
if [ $EUID -ne 0 ]
then
echo "This script must be run as root!"  
else
########################## Modules #########################
DT_Permissions(){
	chmod -R 775 /dspace/log/ && chmod -R 775 /dspace/var/oai/ 
	rm -rf /dspace/log/*
	rm -rf /dspace/var/oai/requests/*
}
DT_Daily(){
	cd /home/dspace
	/dspace/bin/dspace oai import -c
	/dspace/bin/dspace index-discovery
	/dspace/bin/dspace stats-util -i
	/dspace/bin/dspace filter-media
	/dspace/bin/dspace curate -q admin_ui
	/dspace/bin/dspace sub-daily      
}
DT_Test(){
cat > /home/dspace/prueba_$(date +"%Y-%m-%d").txt << "EOF"
Esto es una prueba para saber si el user dspace funciona
EOF
}
########################## Exports #########################
export -f DT_Permissions
export -f DT_Daily
export -f DT_Test
############################################################################################
	if getent passwd | grep -c '^dspace:' > /dev/null 2>&1; then
		cd /home/dspace
		DT_Permissions
		su dspace -c "bash -c DT_Daily"
		chmod -R 775 /dspace/log/ && chmod -R 775 /dspace/var/oai/
	else
		echo "User doesn't exist...."
	fi
fi
