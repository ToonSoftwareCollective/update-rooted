#!/bin/sh

echo "==================================================================================================================================================================="
echo "Welcome to the rooted Toon upgrade script. This script will try to upgrade your Toon using your original connection with Eneco. It will start the VPN if necessary."
echo "Please be advised that running this script is at your own risk!"
echo ""
echo "Version: 4.81  - TheHogNL - 07-08-2024"
echo ""
echo "==================================================================================================================================================================="
echo ""

# YJB 19102018 usage function
usage() {
	echo ""
	echo `basename $0`" [OPTION]

	This script will try to upgrade your Toon using your original
	connection with Eneco.
	!!Running this script is at your own risk!!

	Options:
	-v <version> Upgrade to a specific version
	-a Activation only
	-d Skip starting VPN
	-s <url> provide custom repo url
	-f Only fix files without a version update
	-u unattended mode (always answer with yes) 
	-o only startup vpn and then quit (allows manual package downloads using opkg) 
	-c request new VPN certificates
	-h Display this help text
	"
}


autoUpdate() {
	MD5ME=`/usr/bin/md5sum $0 | cut -d\  -f1`
	MD5ONLINE=`curl --compressed -Nks https://raw.githubusercontent.com/ToonSoftwareCollective/update-rooted/main/update-rooted.md5 | cut -d\  -f1`
	if [ !  "$MD5ME" == "$MD5ONLINE" ]
	then
		echo "Warning: there is a new version of update-rooted.sh available! Do you want me to download it for you (yes/no)?" 
		if ! $UNATTENDED ; then read QUESTION ; fi	
		if [  "$QUESTION" == "yes" ] &&  ! $UNATTENDED #no auto update in unattended mode
		then
			curl --compressed -Nks https://raw.githubusercontent.com/ToonSoftwareCollective/update-rooted/main/update-rooted.sh -o $0
			echo "Ok I downloaded the update. Restarting..." 
			/bin/sh $0 $@
			exit
		fi
	fi
}


fixGlobalsFile() {
	#determine where this Toon is storing the apps
	APPDIR='/qmf/qml/apps'
	if [ ! -d "$APPDIR" ]
	then
		APPDIR='/HCBv2/qml/apps/'
	fi

	#determine where this Toon is storing the base dir
	BASEDIR='/qmf/qml/qb/base'
	if [ ! -d "$APPDIR" ]
	then
		BASEDIR='/HCBv2/qml/qb/base'
	fi

	for app in `find $APPDIR -maxdepth 1 -type l | sed 's/.*apps\///'`
	do
		if ! ( grep -q $app $BASEDIR/Globals.qml )
		then
			echo "Restoring $app in Globals.qml"
			sed -i '/"clock",/a\                                                "'$app'",' $BASEDIR/Globals.qml
		fi
	done
}

fixInternetSettingsApp() {
	settingsfile="/HCBv2/qml/apps/internetSettings/InternetSettingsApp.qml"
	if ! grep -q "if ( smStatus == _ST_INTERNET ) { smStatus = _ST_TUNNEL;" $settingsfile
	then
		echo "Modification in InternetSettingsApp.qml is missing. Fixing it now."
		sed -i '/smStatus = parseInt(statemachine)/a\  if ( smStatus == _ST_INTERNET ) { smStatus = _ST_TUNNEL; }' $settingsfile
	fi
}

editVPNconnection(){
	#disableVPN for rooted toons
	#enables ovpn if it is already disabled
	sed -i 's~#ovpn:235~ovpn:235~g' /etc/inittab
	#disables ovpn if it's enabled
	sed -i 's~ovpn:235~#ovpn:235~g' /etc/inittab
}

editSerialConnection(){
	# Adds serial connection
	# remove existing serial connection if needed
	sed -i '/# add serial/d' /etc/inittab
	sed -i '/gett:235:respawn/d' /etc/inittab
	# adding new serial connection:
	sed -i '/qtqt:245/a\# add serial console access:\ngett:235:respawn:/sbin/getty -L 115200 ttymxc0 vt102' /etc/inittab
}

editTimeServer() {
	#edit time server
	sed -i '/#server time.quby.nl minpoll 8/d' /etc/chrony.conf
	sed -i 's~server time.quby.nl minpoll 8~#server time.quby.nl minpoll 8\nserver 0.nl.pool.ntp.org minpoll 8\nserver 1.nl.pool.ntp.org minpoll 8\nserver 2.nl.pool.ntp.org minpoll 8\nserver 3.nl.pool.ntp.org minpoll 8~g' /etc/chrony.conf
	sed -i 's~server time-iot.hub.quby.com minpoll 8~#server time.quby.nl minpoll 8\nserver 0.nl.pool.ntp.org minpoll 8\nserver 1.nl.pool.ntp.org minpoll 8\nserver 2.nl.pool.ntp.org minpoll 8\nserver 3.nl.pool.ntp.org minpoll 8~g' /etc/chrony.conf
	sed -i '/#initstepslew .* time.quby.nl/d' /etc/chrony.conf
	sed -i 's~initstepslew .* time.quby.nl~#initstepslew 30 time.quby.nl\ninitstepslew 30 0.nl.pool.ntp.org\ninitstepslew 30 1.nl.pool.ntp.org\ninitstepslew 30 2.nl.pool.ntp.org\ninitstepslew 30 3.nl.pool.ntp.org~g' /etc/chrony.conf
	sed -i 's~initstepslew .* time-iot.hub.quby.com~#initstepslew 30 time.quby.nl\ninitstepslew 30 0.nl.pool.ntp.org\ninitstepslew 30 1.nl.pool.ntp.org\ninitstepslew 30 2.nl.pool.ntp.org\ninitstepslew 30 3.nl.pool.ntp.org~g' /etc/chrony.conf
	#removing stupid local binding of chrony
	sed -i '/bindaddress/d' /etc/chrony.conf
	sed -i '/bindcmdaddress/d' /etc/chrony.conf
}

editHostfile(){
	#edit hosts file
	#remove current comment lines + resolve ping.quby.nl to localhost
	sed -i '/ping.quby.nl/d' /etc/hosts
	echo '127.0.0.1    ping.quby.nl' >> /etc/hosts
	sed -i '/api.quby.io/d' /etc/hosts
	echo '127.0.0.1    api.quby.io' >> /etc/hosts
}

disableGoogleDNS() {
	if [ $ARCH == "nxt" ]
	then
		mount -o remount,rw /mnt/persist/
		touch /mnt/persist/udhcpc-skip-prepend-google-pub-dns
		mount -o remount,ro /mnt/persist/
	else
		touch /mnt/persist/udhcpc-skip-prepend-google-pub-dns
	fi
}

editQMFConfigFile(){
	#removing data gathering by quby
	if [ -L /HCBv2/etc/qmf_tenant.xml ] 
	then
		sed -i '/datalab.toon.eu/d' /qmf/var/tenantdir/qmf_tenant.xml
		sed -i '/bd.toon.eu/d' /qmf/var/tenantdir/qmf_tenant.xml
		sed -i '/quby.count.ly/d' /qmf/var/tenantdir/qmf_tenant.xml
	else
		sed -i '/datalab.toon.eu/d' /HCBv2/etc/qmf_tenant.xml
		sed -i '/bd.toon.eu/d' /HCBv2/etc/qmf_tenant.xml
		sed -i '/quby.count.ly/d' /HCBv2/etc/qmf_tenant.xml
	fi
	#whitelisting web service
	sed -i 's/<enforceWhitelist>1/<enforceWhitelist>0/' /HCBv2/etc/qmf_release.xml
}

editTenantSettingsFile(){
	#disabling subscription features
	cp -L /HCBv2/qml/config/TenantSettings.json /HCBv2/qml/config/TenantSettings.json.save
	TENANTFILE="/HCBv2/qml/config/TenantSettings.json"
	if [ -L /HCBv2/qml/config/TenantSettings.json ] 
	then
		TENANTFILE="/qmf/var/tenantdir/TenantSettings.json"
	fi
	sed -i 's/"appBenchmarkEnabled" *: true/"appBenchmarkEnabled": false/' $TENANTFILE 
	sed -i 's/"appCustomerServiceEnabled" *: true/"appCustomerServiceEnabled": false/' $TENANTFILE  
	sed -i 's/"appBoilerMonitorEnabled" *: true/"appBoilerMonitorEnabled": false/' $TENANTFILE 
	sed -i 's/"appWhatIsNewEnabled" *: true/"appWhatIsNewEnabled": false/' $TENANTFILE 
	sed -i 's/"appWhatIsToonEnabled" *: true/"appWhatIsToonEnabled": false/' $TENANTFILE
	sed -i 's/"appStatusUsageEnabled" *: true/"appStatusUsageEnabled": false/' $TENANTFILE
	sed -i 's/"appUpsellEnabled" *: true/"appUpsellEnabled": false/' $TENANTFILE
	sed -i 's/"appHeatingOverviewEnabled" *: true/"appHeatingOverviewEnabled": false/' $TENANTFILE
	sed -i 's/"appWeather" *: "weather"/"appWeather": ""/' $TENANTFILE
	sed -i 's/"appWeather" *: "weatherInt"/"appWeather": ""/' $TENANTFILE
	#add english translations if nl_NL is only language (like in eneco toon tenant)
	sed -i 's/"nl_NL"$/"nl_NL","en_GB"/' $TENANTFILE
	#remove feature boilermonitoring and wastechekers as these are only for subscription users and it slows down booting if not disabled
	sed -i 's/<feature>boilerMonitoring<\/feature>//' $TENANTFILE
	sed -i 's/<feature>wasteChecker<\/feature>//' $TENANTFILE
	#remove weather tenant setting also, without removing this the toon boots slowly
	sed -i 's/"appWeather" *: "weather"/"appWeather": ""/' $TENANTFILE 
}

checkCApem() {
        UPDATECA=false
        SHA256ONLINE=`curl -Nks https://curl.se/ca/cacert.pem.sha256 | cut -d\  -f1`
        SHA256CURRENT='false'
        if [ -f /usr/local/share/ca-certificates/mozilla.crt ]
        then
                SHA256CURRENT=`/usr/bin/sha256sum /usr/local/share/ca-certificates/mozilla.crt | cut -d\  -f1`
        fi
        if [ !  "$SHA256CURRENT" == "$SHA256ONLINE" ] && [ -n "$SHA256ONLINE" ]
        then
                echo "There is a new version of the Mozilla CA pem file. Downloading it!"
                /usr/bin/curl -Nks https://curl.se/ca/cacert.pem -o /tmp/mozilla.crt
                SHA256NEW=`/usr/bin/sha256sum /tmp/mozilla.crt | cut -d\  -f1`
                if [ "$SHA256ONLINE" == "$SHA256NEW" ]
                then
                        echo "Download ok! Replacing Mozilla CA pem file!"
                        mv -f /tmp/mozilla.crt /usr/local/share/ca-certificates/mozilla.crt
                        UPDATECA=true
                fi
        fi

        if [ "$UPDATECA" = true ]
        then
                /usr/sbin/update-ca-certificates
        fi
}

disableHapps() {
	#don't need to start these on rooted toons
	rm -f /HCBv2/etc/start.d/happ_weather
	rm -f /HCBv2/etc/start.d/happ_kpi
	rm -f /HCBv2/etc/start.d/hcb_log
	sed -i '/happ_kpi/d' /HCBv2/etc/qmf_hardware.xml
	sed -i '/happ_weather/d' /HCBv2/etc/qmf_hardware.xml

}

disableNmbd() {
	#disable samba nmbd
	sed -i '/CONFIG_FILE/a\\n#TSC mod, do not start nmbd\nexit 0' /etc/init.d/samba
}

editWifiPM(){
	#creating file to disable wifi powermanagment after reboot
	echo "/sbin/wl PM 0" > /etc/udhcpc.d/90tsc	
	chmod +x /etc/udhcpc.d/90tsc
}

editAutoBrightness(){
	#set feature auto brightness on toon2 if not exists
	if ! cat /qmf/config/config_happ_scsync.xml | tr -d '\040\011\012\015'  | grep -q "<feature>displayAutoBrightness"
	then
		sed -i 's/<\/features>/<feature>displayAutoBrightness<\/feature><\/features>/' /qmf/config/config_happ_scsync.xml 
	fi
}

checkJSON() {
	if ! grep -q sensors /qmf/etc/lighttpd/lighttpd.conf
	then
		# remove possible backup
		rm -f /qmf/etc/lighttpd/lighttpd.conf.backup
		# make backup
		/bin/cp /qmf/etc/lighttpd/lighttpd.conf /qmf/etc/lighttpd/lighttpd.conf.backup

		if grep -q application/json /qmf/etc/lighttpd/lighttpd.conf  #first repair old patch
		then
			sed -i 's~#""~""~g' /qmf/etc/lighttpd/lighttpd.conf
			sed -i '/application\/json/d' /qmf/etc/lighttpd/lighttpd.conf
		fi

		# add new line
		sed -i '/".tar.bz2"/a\  ".json"              =>      "application/json",' /qmf/etc/lighttpd/lighttpd.conf
		sed -i '/".tar.bz2"/a\  "sensors"            =>      "application/json",' /qmf/etc/lighttpd/lighttpd.conf
	fi
}

editActivation() {
	#remove AWS IOT token file and restart bxtproxy
	if [ -f /qmf/var/hcb_bxtproxy-oidcIdToken.json ]
	then
		rm -f  /qmf/var/hcb_bxtproxy-oidcIdToken.json
		killall -9 hcb_bxtproxy
	fi
	#editing config_happ_scsync.xml for activation
	sed -i 's~Standalone~Toon~g' /qmf/config/config_happ_scsync.xml
	sed -i 's~<activated>0</activated>~<activated>1</activated>~g' /qmf/config/config_happ_scsync.xml
	sed -i 's~<wizardDone>0</wizardDone>~<wizardDone>1</wizardDone>~g' /qmf/config/config_happ_scsync.xml
	sed -i 's~<SoftwareUpdates>0</SoftwareUpdates>~<SoftwareUpdates>1</SoftwareUpdates>~g' /qmf/config/config_happ_scsync.xml
	sed -i 's~<ElectricityDisplay>0</ElectricityDisplay>~<ElectricityDisplay>1</ElectricityDisplay>~g' /qmf/config/config_happ_scsync.xml
	sed -i 's~<GasDisplay>0</GasDisplay>~<GasDisplay>1</GasDisplay>~g' /qmf/config/config_happ_scsync.xml
	sed -i -e 's/\(<EndDate>\).*\(<\/EndDate>\)/<EndDate>-1<\/EndDate>/g' /qmf/config/config_happ_scsync.xml
}

removeNetworkErrorNotifications() {
	notificationsbarfile="/qmf/qml/qb/notifications/NotificationBar.qml"
	if ! grep -q "mod to remove" $notificationsbarfile
	then
		echo "Modification in NotificationBar.qml is missing. Fixing it now."
		sed -i '/function show/a\ //mod to remove network errors in notification bar\nnotifications.removeByTypeSubType("error","network");\n//end mod' $notificationsbarfile
	fi
}

installToonStoreApps() {
	#we assume that all symbolic linked dirs are toonstore installed apps - IS THAT OK?
	#toonstore is mandatory, if not yet installed, install it anyway
	for a in toonstore `find /qmf/qml/apps -type l | sed 's#/qmf/qml/apps/##' | grep -v toonstore`
	do
		latestapp=`curl -NLks "https://api.github.com/repos/ToonSoftwareCollective/$a/releases/latest" | grep tag_name | cut -d\: -f2 | sed 's/.*"\(.*\)".*/\1/'`
		if [ -s /HCBv2/qml/apps/$a/version.txt ] 
		then
			currentapp=`cat /HCBv2/qml/apps/$a/version.txt`
		else
			#allow install new version if current version isn't known
			currentapp=""
		fi
		if [ -n "$latestapp" ] && [ ! "$latestapp" == "$currentapp" ]
		then
			echo -n "-- Updating custom app $a to release $latestapp ... "
			TARBALL=`curl -NLks "https://api.github.com/repos/ToonSoftwareCollective/$a/releases/latest" | grep tarball | sed 's/.*: "\(.*\)".*/\1/'`	
			rm -rf /tmp/$a-install
			mkdir -p /tmp/$a-install
		        curl -NLks "$TARBALL" -o /tmp/$a-install/$a.tar.gz
		        cd /tmp/$a-install/
		        if tar zxf $a.tar.gz
			then
			        RESULT=`opkg list-installed $a`
			        if [ -n "${RESULT}" ]
			        then
			                opkg remove $a
			        fi
			        #then remove every existing app version of the app
			        rm -rf /qmf/qml/apps/$a*

       		                APPDIR=`find /tmp/$a-install/ -type d -maxdepth 1 -mindepth 1`
	                        mv $APPDIR /qmf/qml/apps/$a-$latestapp
	                        #and make a symlink for the app to the appversion
	                        ln -s /qmf/qml/apps/$a-$latestapp /qmf/qml/apps/$a
	                        echo "DONE"
			else
				echo "FAILED"
			fi

		fi
	done
}


getVersion() {
	VERSIONS=`/usr/bin/curl -Nks --compressed "https://raw.githubusercontent.com/ToonSoftwareCollective/update-rooted/main/toonversions" | /usr/bin/tr '\n\r' ' ' | /bin/grep STARTTOONVERSIONS | /bin/sed 's/.*#STARTTOONVERSIONS//' | /bin/sed 's/#ENDTOONVERSIONS.*//' | xargs`

	if [ "$VERSIONS" == "" ]
	then
		echo "Could not determine available versions from online sources. Using older well known verion list."
		#online versions list not available, falling back to a small well known list
		VERSIONS="2.9.26 3.0.29 3.0.32 3.1.22 3.2.14 3.2.18 3.3.8 3.4.4 3.5.4 3.6.3 3.7.8 3.7.9 4.3.20 4.4.21 4.7.23 4.8.25 4.9.23 4.10.6 4.11.6 4.12.0 4.13.6 4.13.7 4.15.2 4.15.6 4.16.8 4.18.8 4.19.10"
	fi

	#determine current version
	RUNNINGVERSION=`opkg list-installed base-$ARCH-\* | sed -r -e "s/base-$ARCH-([a-z]{3})\s-\s([0-9]*\.[0-9]*\.[0-9]*)-.*/\2/"`

	#determine current OPKG latest version
	OPKGVERSION=`opkg list base-$ARCH-\* | sed -r -e "s/base-$ARCH-([a-z]{3})\s-\s([0-9]*\.[0-9]*\.[0-9]*)-.*/\2/" | sort -t'.' -k1n,1n -k2n,2n -k3n,3n | tail -n1`

	if [ ! "$OPKGVERSION" == "" ]  && [ ! "$RUNNINGVERSION" == "$OPKGVERSION" ]
	then
		echo "Your Toon already tried downloading version $OPKGVERSION before. Need to force this version!"
		VERSION="$OPKGVERSION"
		return
	fi

	if echo $VERSIONS| grep -qE  "[0-9]+\.[0-9]+\.[0-9]+"
	then
		echo "You are currently running version $RUNNINGVERSION on a $ARCH with flavour $FLAV"
	else
		echo "Unable to determine your current running version!"
		echo "DEBUG information:"
		echo "Detected: $RUNNINGVERSION"
		echo "Available: $VERSIONS"
		/usr/bin/opkg list-installed base-$ARCH-\*
		echo "END DEBUG information"
		if $UNATTENDED
		then
			/qmf/bin/bxt -d :happ_usermsg -s Notification -n CreateNotification -a type -v tsc -a subType -v notify -a text -v "Huidige Toon firmware onbekend. Kan geen nieuwe firmware hiervoor vinden." >/dev/null 2>&1
			echo "action=Failed&item=100&items=100&pkg=" > /tmp/update.status.vars
		fi
		exit
	fi

	echo ""
	echo "Available versions: $VERSIONS"
	echo ""
	if ! $UNATTENDED
	then
		echo "Which version do you want to upgrade to?" 
		read VERSION
		while [ "$VERSION" == "" ]  || ! ( echo $VERSION | grep -qe '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' )  || ! (echo $VERSIONS| grep -q $VERSION)
		do
			echo "Please enter a valid version!"
			read VERSION
		done
	else
		#determine latest version in unattended mode
		VERSION=${VERSIONS##* }	
		echo "Unattended selected version $VERSION"
	fi

	#determine current and next version levels and if it is allowed to upgrade to it
	CURVERS_MAJOR="`echo $RUNNINGVERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\1,p'`"
	CURVERS_MINOR="`echo $RUNNINGVERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\2,p'`"
	CURVERS_BUILD="`echo $RUNNINGVERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\3,p'`"
	VERS_MAJOR="`echo $VERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\1,p'`"
	VERS_MINOR="`echo $VERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\2,p'`"
	VERS_BUILD="`echo $VERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\3,p'`"

	if [ $VERS_MAJOR -gt $CURVERS_MAJOR ] || [ $VERS_MAJOR -eq $CURVERS_MAJOR -a $VERS_MINOR -gt $CURVERS_MINOR ] || [ $VERS_MAJOR -eq $CURVERS_MAJOR -a $VERS_MINOR -eq $CURVERS_MINOR -a $VERS_BUILD -gt $CURVERS_BUILD ]
	then
		if [ "$ARCH" == "qb2" ] && [ $CURVERS_MAJOR -lt 5 ] && [ $VERS_MAJOR -ge 5 ] && [ "$VERSION" != "5.0.4" ] && [ "$VERSION" != "5.0.6" ]
		then
			echo "You need to upgrade to 5.0.6 first due to possible disk space issues! Selecting this version for you."
			VERSION="5.0.6"
		elif [ "$ARCH" == "nxt" ] && [ "$VERSION" == "5.28.6" ] && ( [ $CURVERS_MAJOR -lt 5 ] || ( [ $CURVERS_MAJOR -eq 5 ] && [ $CURVERS_MINOR -lt 25 ] ) ) 
		then
			echo "You need to upgrade to 5.25.8 first due to problems with upgrade to 5.28.6 from your current version!" 
			VERSION="5.25.8"
		else
			echo "Alright, I will try to upgrade to" $VERSION
		fi
	else
		if $UNATTENDED
		then
			/qmf/bin/bxt -d :happ_usermsg -s Notification -n CreateNotification -a type -v tsc -a subType -v notify -a text -v "Er is geen Toon firmware update gevonden" >/dev/null 2>&1
			echo "action=Failed&item=100&items=100&pkg=" > /tmp/update.status.vars
		else
			echo "Smartass.. "$VERSION" is not an upgrade for "$RUNNINGVERSION"!"
		fi
		exit

	fi
}

getArch() {
	#determine current architecture
	if grep -q nxt /etc/opkg/arch.conf
	then
		ARCH="nxt"
	else
		ARCH="qb2"
		#if running on a toon 1 (qb2) free up cache memory faster as updating the toon is memory intensive
		echo 200 > /proc/sys/vm/vfs_cache_pressure
		sync; echo 3 > /proc/sys/vm/drop_caches
	fi
}

getFlav() {
	#determine current flavour
	FLAV=`opkg list-installed base-$ARCH-\* | sed -r -e "s/base-$ARCH-([a-z]{3})\s-\s([0-9]*\.[0-9]*\.[0-9]*)-.*/\1/"`
	if [ "$FLAV" == "" ]
	then
		echo "There is no base file installed? Try to get flavour from ready to install files."
		FLAV=`opkg list base-$ARCH-\* | sed -r -e "s/base-$ARCH-([a-z]{3})\s-\s([0-9]*\.[0-9]*\.[0-9]*)-.*/\1/" | sort | tail -n1`
		if [ "$FLAV" == "" ]
		then
			echo "Could not determine you current running flavour."
			echo "DEBUG:"
			opkg list base-\*
        		exitFail
		fi
	fi
}

makeBackupUpdate() {
	#save current iptables config 
	/usr/sbin/iptables-save > /root/iptables.save

	#and backup the default iptables file and passwd file
	if [ ! -f /etc/default/iptables.conf ] 
	then 
		echo "Your default iptables.conf (firewall configuration) is missing. I will restore it from the current running firewall config."
		/usr/sbin/iptables-save > /etc/default/iptables.conf
	fi
	/bin/cp /etc/default/iptables.conf /root/iptables.backup
	if [ ! -f /etc/passwd ] 
	then
		echo "Your password file (/etc/passwd) is missing. Please fix this before running this script."
		exit
	fi
	/bin/cp /etc/passwd /root/passwd.backup 

	sync
}

makeBackupFixFiles() {
	#backup inittab
	echo creating backup of inittab...
	cp /etc/inittab /root/inittab.save

	#backup chrony.conf
	echo creating backup of chrony.conf...
	cp /etc/chrony.conf /root/chrony.save

	#backup hosts
	echo creating backup of hosts...
	cp /etc/hosts /root/hosts.save

	#backup scsync
	echo creating backup of config_happ_scsync.xml...
	cp /mnt/data/qmf/config/config_happ_scsync.xml /root/config_happ_scsync.save

	#backup qmf tenant file
	echo creating backup of qmf_tenant.xml.save ...
	cp /HCBv2/etc/qmf_tenant.xml /HCBv2/etc/qmf_tenant.xml.save
	
	#move backup files into folder
	mkdir -p /root/backup_files/
	mv /root/chrony.save /root/backup_files/chrony.save
	mv /root/config_happ_scsync.save /root/backup_files/config_happ_scsync.save
	mv /root/hosts.save /root/backup_files/hosts.save
	mv /root/inittab.save /root/backup_files/inittab.save
	mv /root/iptables.backup /root/backup_files/iptables.backup
	mv /root/iptables.save /root/backup_files/iptables.save
	mv /root/passwd.backup /root/backup_files/passwd.backup
	
	sync
}

checkFixedFiles() {
	#check modified files for 0 size, if yes announce this and try to restore
	for file in /etc/inittab /etc/chrony.conf /etc/hosts /mnt/data/qmf/config/config_happ_scsync.xml /HCBv2/etc/qmf_tenant.xml
	do
		if [ ! -s $file ] 
		then
			echo "File $file was modified but result is an empty file! Trying to restore!"
			restorefile="$file.save"
			cp $restorefile $file
			sync
			if [ -s $file ] 
			then
				echo "Restore of $file is good. But modifying failed. Try to rerun the script with -f"
			else
				echo "Restore of $file is failed! Result is also empty! Please check this file before rebooting!"
			fi
		fi
	done
}
checkOVPN() {
	value=$( grep -ic "ovpn:2" /etc/inittab )
	if [ $value -ge 1 ]
	then
	  if [ $value -eq 1 ] #1x gevonden
	  then
			value=$( grep -ic "#ovpn" /etc/inittab )
			if [ $value -eq 1 ]
			then
				GREEN='\033[0;32m' # Green
				NC='\033[0m' # No Color
				echo -e "${GREEN}OVPN DISABLED${NC}"
			else
				RED='\033[0;31m' # Red
				NC='\033[0m' # No Color
				echo -e "${RED}OVPN ENABLED${NC}"
			fi
	  elif [ $value -eq 2 ] #2x+ gevonden
	  then
				RED='\033[0;33m' # Red
				NC='\033[0m' # No Color
				echo -e "${RED}Multiple entries found, please manually edit inittab file!${NC}"
	  else
		echo "overige"
		fi
	fi 
	}

initializeFirewall() {
	#create a new iptables chain for this upgrade process and insert it in front of all rules
	/usr/sbin/iptables -N UPDATE-INPUT
	/usr/sbin/iptables -I INPUT -j UPDATE-INPUT

	#allow icmp (ping) always, or else openvpn will restart all the time do to internal toon ping checks
	/usr/sbin/iptables -A UPDATE-INPUT -p icmp -j ACCEPT
	#drop all VPN traffic (for now)
	/usr/sbin/iptables -A UPDATE-INPUT -i tap+ -j DROP
	/usr/sbin/iptables -A UPDATE-INPUT -i tun+ -j DROP
}

enableVPN() {
	#check if feed host is configured and there is a active route toward the host
	#if openvpn is already running we don't need to start it manually, the FEEDROUTE should be there 
	FEEDROUTE=`ip route | /bin/grep ^172.*via.*tap0 | /usr/bin/awk '{print $1}'| /usr/bin/awk 'BEGIN {FS="."}; {print $1"."$2"."$3}'`
	COUNT=0
	while [ "$FEEDROUTE" == "" ] ; do
		killall -9 openvpn 2>/dev/null
		if [ $COUNT -gt 10 ] 
		then
			echo "Could not enable VPN in a normal reasonable time!"
			echo "DEBUG information:"
			ip route
			/bin/cat /etc/hosts
			echo "END DEBUG information"
			exitFail
		fi
		COUNT=$((COUNT+1))
		/bin/echo "Now starting the VPN tunnel and waiting for it to be alive and configured..."
		/usr/sbin/openvpn --config /etc/openvpn/vpn.conf --verb 0 >/dev/null --daemon 
		/bin/sleep 10
		FEEDROUTE=`ip route | /bin/grep ^172.*via.*tap0 | /usr/bin/awk '{print $1}'| /usr/bin/awk 'BEGIN {FS="."}; {print $1"."$2"."$3}'`
	done
	/bin/echo "Tunnel is alive and configured."
	#set the feedhost
        FEEDHOST=$FEEDROUTE.1
	#and overwrite the entry in the hosts file as some old toons do not do this properly
	sed -i '/feed/d' /etc/hosts
	echo "$FEEDHOST         feed.hae.int    feed" >> /etc/hosts
	#allow traffic from the vpn only from the feed host, and only if it is from the www port
	#this blocks other traffic, most important blocking the service center so other changes are not pushed
	/usr/sbin/iptables -I UPDATE-INPUT -p tcp -s $FEEDHOST -m tcp --sport 80 -j ACCEPT
}

downloadUpgradeFile() {
	#try to get the upgrade file from the feed host
	/usr/bin/wget  $SOURCE/$ARCH/upgrade/upgrade-$ARCH.sh -O $PKGCACHE/upgrade-$ARCH.sh -T 5 -t 5 --retry-connrefused -o /dev/null
	RESULT=$?

	if [ ! $RESULT == 0 ] ; then
		echo "Could not download the upgrade script from the source." 
		exitFail
	fi

	#check if there is a valid upgrade script
	if [ "$ARCH" == "nxt" ] 
	then
		MD5SCRIPT="c5f3918503643c1d04aeba1b8eff89a2"
	else
		MD5SCRIPT="34db70c584e9a75bd8404bb306a4ee5a"
	fi
	MD5NOW=`/usr/bin/md5sum $PKGCACHE/upgrade-$ARCH.sh | cut -d\  -f1`
	if [ !  "$MD5NOW" == "$MD5SCRIPT" ]  && $ORIGINALSOURCE
	then
		echo "Warning: upgrade script from Eneco server is changed. Do you want to continue downloading the files (if not sure, type no and report in the forums)?" 
		if ! $UNATTENDED ; then read QUESTION; fi	
		if [ ! "$QUESTION" == "yes" ] || $UNATTENDED  #also exit when untattended
		then
			exitFail
		fi
	fi

	#remove auto execute feature
	/bin/sed -i 's/^\(FEATURES=.*\)AUTO_EXECUTE/\1/' $PKGCACHE/upgrade-$ARCH.sh 

	#make sure the upgrade script doesn't reboot the device after finishing
	/bin/sed -i '/shutdown/c\#rkemoved shutdown' $PKGCACHE/upgrade-$ARCH.sh 

	#removing the curl logging post to the servic center
	/bin/sed -i '/curl.*31080/c\echo ""' $PKGCACHE/upgrade-$ARCH.sh
	/bin/sed -i '/grep -v LogMessageResponse/d' $PKGCACHE/upgrade-$ARCH.sh

	#removing the pre exit BXT request (do not show restarting during update)
	/bin/sed -i 's/-n InitiatePreExit/-n InitiatePreExit -t/' $PKGCACHE/upgrade-$ARCH.sh

}

startPrepare() {
	echo "Upgrade script downloaded. We need to download the upgrade files first. No upgrade is done yet. Do you want me to download the files (yes) or quit (anything else)?"
	if ! $UNATTENDED ; then read QUESTION; fi	
	if [ ! "$QUESTION" == "yes" ] 
	then
		exitFail
	fi

	echo "Starting the upgrade prepare option which downloads all necessary files. No upgrade is done yet."

	if [ "$ARCH" == "qb2" ]
	then
		echo -n "First removing some files to free some disk space. "
		#first remove backups and zips for resources/drawables
		rm -f /HCBv2/qml/resources-static*.rcc.*
		rm -f /HCBv2/qml/drawables*.rcc.*
		if readlink -f /HCBv2/qml/resources.rcc | grep -q ebl
		then
			echo "Removed 'base' resource files because this toon is using 'ebl' resource files."
			rm -f /HCBv2/qml/resources-static-base.*
			rm -f /HCBv2/qml/drawables-base.*
		else
			echo "Removed 'ebl' resource files because this toon is using 'base' resource files."
			rm -f /HCBv2/qml/resources-static-ebl.*
			rm -f /HCBv2/qml/drawables-ebl.*
		fi
	fi
	

	/bin/sh $PKGCACHE/upgrade-$ARCH.sh $ARCH $FLAV $VERSION prepare &
	DOWNLOAD_PID=$!
	showStatus $DOWNLOAD_PID

	if ! wait $DOWNLOAD_PID
	then
		echo "Prepare failed. Please check the logs at $PKGCACHE/upgrade-$ARCH.sh.log"
		exitFail
	fi

	echo "Done preparing."

	#check disk size after download
	FREESPACE=`df $PKGCACHE | awk '/[0-9]%/{print $(NF-2)}'`
	if [ $FREESPACE -lt 5000 ] 
	then
		echo "After downloading the files the free space on the Toon is less then 5000 KB. This could cause the upgrade to fail. Do you still want to continue (yes)?"
		if ! $UNATTENDED ; then read QUESTION; fi	
		if [ ! "$QUESTION" == "yes" ]  || $UNATTENDED #fail if unattended
		then
			exitFail
		fi
	fi
}

startUpgrade() {
	echo "Are your sure you want to upgrade to" $VERSION" (yes)? This is the last moment you can stop the upgrade. Answer with 'yes' will start the upgrade."
	if ! $UNATTENDED ; then read QUESTION; fi	
	if [ ! "$QUESTION" == "yes" ] 
	then
		exitFail
	fi

	echo "Starting the upgrade now! Just wait a while... It can take a few minutes."

	if [ "$VERSION" == "5.0.4" ] && [ "$ARCH" == "qb2" ]
	then
		#deleting logfiles to free up space needed for this update on a qb2
		rm -f /HCBv2/log/*
		rm -f $PKGCACHE/*.log
	fi

	/bin/sh $PKGCACHE/upgrade-$ARCH.sh $ARCH $FLAV $VERSION execute &
	UPGRADE_PID=$!
	showStatus $UPGRADE_PID

	if ! wait $UPGRADE_PID
	then
		echo "Upgrade failed. Please check the logs at $PKGCACHE/upgrade-$ARCH.sh.log"
		exitFail
	fi

        echo "Installing curl as in some update it is removed due to buggy dependencies..."
        opkg install curl

	VERS_MAJOR="`echo $VERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\1,p'`"
        if [ $VERS_MAJOR -gt 4 ]
        then
        	echo "Installing QT5 websockets"
        	opkg install libqt5websockets5
	fi

	echo "Upgrade done!" 
}

showStatus() {
	STATUS_PID=$1
	DOTS="   ..."
	PERC=0
	SECONDS=0
	while [ $PERC -lt 100 ] && [ -e /proc/$STATUS_PID ] && [ $SECONDS -lt 900 ]
	do
		PERC="`sed /tmp/update.status.vars -n -r -e 's,^.+item=(.+?)&items=(.+?)&.+$,\1,p' 2>/dev/null`"
		PERC="${PERC:-0}"

		# do not append newline, \r to beginning of line after print, append space to overwrite prev-longer-sentences
		echo -n -e "Progress: $PERC% ${DOTS:0:3}    \r"

		# shift right
		DOTS="${DOTS:5:1}${DOTS:0:5}"
		sleep 1 >/dev/null 2>&1 || read -t 1 < /dev/tty5  #during busybox update sleep fails, so failover to read with 1 sec timeout, tty5 never gives any input
		SECONDS=$((SECONDS+1))
	done

	while [ -e /proc/$STATUS_PID ] && [ $SECONDS -lt 900 ]
	do
		echo -n -e "Waiting to finish. Sometimes this takes a minute or two  ${DOTS:0:3}    \r"
		DOTS="${DOTS:5:1}${DOTS:0:5}"
		sleep 1 >/dev/null 2>&1 || read -t 1  < /dev/tty5  #during busybox update sleep fails, so failover to read with 1 sec timeout, tty5 never gives any input
		SECONDS=$((SECONDS+1))
	done


	if [ $SECONDS -ge 900 ]
	then
		kill -9 $STATUS_PID
		echo "Killing process... took to long!"
	fi

	echo ""
	rm -f /tmp/update.status.vars
}

restoreBackup() {
	echo "Restoring your iptables and passwd files so you can login again after rebooting."
	/bin/cp /root/iptables.backup /etc/default/iptables.conf
	/bin/cp /root/passwd.backup /etc/passwd 

	#cleaning up
	/usr/bin/killall -9 openvpn
	/usr/sbin/iptables-restore <  /root/iptables.save

	sync
}

exitFail() {
	echo "Quitting the upgrade. It was a nice try tho..."
	/usr/bin/killall -9 openvpn
	/usr/sbin/iptables-restore <  /root/iptables.save
	if $UNATTENDED
	then
		/qmf/bin/bxt -d :happ_usermsg -s Notification -n CreateNotification -a type -v tsc -a subType -v notify -a text -v "Er ging iets mis bij het updaten van Toon Firmware. Controleer logs." >/dev/null 2>&1
		echo "action=Failed&item=100&items=100&pkg=" > /tmp/update.status.vars
	fi
	exit
}

installTSCscript() {
	#install boot script to download TSC helper script if necessary
	echo "if [ ! -s /usr/bin/tsc ] || grep -q no-check-certificate /usr/bin/tsc ; then /usr/bin/curl -Nks --retry 5 --connect-timeout 2 https://raw.githubusercontent.com/ToonSoftwareCollective/tscSettings/main/tsc -o /usr/bin/tsc ; chmod +x /usr/bin/tsc ; fi ; if ! grep -q tscs /etc/inittab ; then sed -i '/qtqt/a\ tscs:245:respawn:/usr/bin/tsc >/var/log/tsc 2>&1' /etc/inittab ; if grep -q tscs /etc/inittab ; then init q ; fi ; fi" > /etc/rc5.d/S99tsc.sh
	chmod +x /etc/rc5.d/S99tsc.sh
	#fix TSC helper script download location (if necessary)
	sed -i 's/IgorYbema/ToonSoftwareCollective/' /etc/rc5.d/S99tsc.sh

	#download or update TSC helper script
	/usr/bin/curl --compressed -fNks  --retry 5 --connect-timeout 2 https://raw.githubusercontent.com/ToonSoftwareCollective/tscSettings/main/tsc -o /usr/bin/tsc.new
	RESULT=$?

	if [ ! $RESULT == 0 ]
	then
		echo "[ERROR] Could not download TSC script from github!" 
	else
		#check for valid download
		CURRENTTIME=`date +%s`
		MD5TSCONLINE=`curl -Nks https://raw.githubusercontent.com/ToonSoftwareCollective/tscSettings/main/tsc.md5?$CURRENTTIME | cut -d\  -f1`
		MD5TSCNOW=`/usr/bin/md5sum /usr/bin/tsc.new | cut -d\  -f1`
		if [ "$MD5TSCNOW" == "$MD5TSCONLINE" ] && [ -n "$MD5TSCONLINE" ]
		then
			mv /usr/bin/tsc.new /usr/bin/tsc
			chmod +x /usr/bin/tsc
		fi
	
		#install tsc in inittab to run continously from boot
		if ! grep -q tscs /etc/inittab
		then
			sed -i '/qtqt/a\tscs:245:respawn:/usr/bin/tsc >/var/log/tsc 2>&1' /etc/inittab
			init q
		fi
	fi
}

downloadResourceFile() {
	#first install TSC script to make sure it does not conflict with update script
	installTSCscript

	RESOURCEFILEURL="https://raw.githubusercontent.com/ToonSoftwareCollective/resourcefiles/main/resources-$ARCH-$RUNNINGVERSION.zip"
	/usr/bin/curl  --compressed -fNks  --retry 5 --connect-timeout 2  $RESOURCEFILEURL -o /tmp/resources-$ARCH-$RUNNINGVERSION.zip
	RESULT=$?

	if [ ! $RESULT == 0 ]
	then 
		echo "[ERROR] Could not download a resources.rcc file for this version! Continuing, but your custom apps probably dont work anymore" 
	else 
		mv /qmf/qml/resources-static-base.rcc /qmf/qml/resources-static-base.rcc.backup
		mv /qmf/qml/resources-static-ebl.rcc /qmf/qml/resources-static-ebl.rcc.backup
		/usr/bin/unzip -oq /tmp/resources-$ARCH-$RUNNINGVERSION.zip -d /qmf/qml
	fi
}

overrideFirewallAlways () {
	echo "sed -i '/-A INPUT -j HCB-INPUT/a\#override to allow all input\n-I INPUT -j ACCEPT' /etc/default/iptables.conf" > /etc/rcS.d/S39fixiptables
	/bin/chmod +x /etc/rcS.d/S39fixiptables
}

fixFiles() {
	#get the current, just installed, version (also necessary when -f is called)
	RUNNINGVERSION=`opkg list-installed base-$ARCH-\* | sed -r -e "s/base-$ARCH-([a-z]{3})\s-\s([0-9]*\.[0-9]*\.[0-9]*)-.*/\2/"`
	VERS_MAJOR="`echo $RUNNINGVERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\1,p'`"
	VERS_MINOR="`echo $RUNNINGVERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\2,p'`"
	VERS_BUILD="`echo $RUNNINGVERSION | sed -n -r -e 's,([0-9]+).([0-9]+).([0-9]+),\3,p'`"

	if [ $ARCH == "nxt" ]
	then 
		#from version 4.16 we need to download resources.rcc mod
		if [ $VERS_MAJOR -gt 4 ] || [ $VERS_MAJOR -eq 4 -a $VERS_MINOR -ge 16 ]
		then 
			echo "FIXING: Downloading resources.rcc TSC mod for this version $RUNNINGVERSION."
			downloadResourceFile
		else 
			echo "FIXING: Trying to fix Global.qml now to add all the Toonstore installed apps again." 
			fixGlobalsFile
			echo "FIXING: Now fixing internet settings app to fake ST_TUNNEL mode."
			fixInternetSettingsApp
			echo "FIXING: Now modifying notifications bar to not show any network errors" 
			removeNetworkErrorNotifications
		fi
		#not installing apps anymore on versions lower then fw 5
		if [ $VERS_MAJOR -gt 4 ]
		then 
			echo "FIXING: Now updating all toonstore installed apps"
			installToonStoreApps
		fi
		#dropbear is not needed, no rooted toon2 without working dropbear exists
		echo "EDITING: Time server, removes unnecessary link to Quby"
		editTimeServer
		echo "EDITING: Hosts file, removes unnecessary link to Quby"
		editHostfile
		echo "EDITING: Disable add google DNS on top of resolv.conf" 
		disableGoogleDNS
		echo "EDITING: disable ovpn connection to quby"
		editVPNconnection
		echo "EDITING: Activating Toon, enabling ElectricityDisplay and GasDisplay"
		editActivation
		echo "EDITING: removing data gathering by Quby and whitelisting web services" 
		editQMFConfigFile
		echo "EDITING: add disable power management wifi on Toon2" 
		editWifiPM
		echo "EDITING: add autobrightness feature on Toon2" 
		editAutoBrightness
		echo "EDITING: disabling Eneco subscription feature apps which are not working on rooted toons"
		editTenantSettingsFile
		echo "EDITING: disabling KPI and weather happ as these are not necessary on rooted toons" 
		disableHapps
		echo "EDITING: download certificate store pem file"
		checkCApem
		echo "EDITING: lighttpd so tsc/sensors is viewable via a browser"
		checkJSON
	else
		#from version 4.16 we need to download resources.rcc mod
		if [ $VERS_MAJOR -gt 4 ] || [ $VERS_MAJOR -eq 4 -a $VERS_MINOR -ge 16 ]
		then 
			echo "FIXING: Downloading resources.rcc TSC mod for this version $RUNNINGVERSION."
			downloadResourceFile
		else 
			echo "FIXING: Trying to fix Global.qml now to add all the Toonstore installed apps again." 
			fixGlobalsFile
			echo "FIXING: Now fixing internet settings app to fake ST_TUNNEL mode."
			fixInternetSettingsApp
			echo "FIXING: Now modifying notifications bar to not show any network errors" 
			removeNetworkErrorNotifications
		fi
		#not installing apps anymore on versions lower then fw 5
		if [ $VERS_MAJOR -gt 4 ]
		then 
			echo "FIXING: Now updating all toonstore installed apps"
			installToonStoreApps
		fi
		echo "EDITING: Time server, removes unnecessary link to Quby"
		editTimeServer
		echo "EDITING: Hosts file, removes unnecessary link to Quby"
		editHostfile
		echo "EDITING: Disable add google DNS on top of resolv.conf" 
		disableGoogleDNS
		echo "EDITING: disable ovpn connection to quby"
		editVPNconnection
		echo "EDITING: Activating Toon, enabling ElectricityDisplay and GasDisplay"
		editActivation
		echo "EDITING: removing data gathering by Quby and whitelisting web services" 
		editQMFConfigFile
		echo "EDITING: disabling Eneco subscription feature apps to free up memory on this toon 1" 
		editTenantSettingsFile
		echo "EDITING: disabling KPI and weather happ as these are not necessary on rooted toons" 
		disableHapps
		echo "EDITING: disabling samba nmbd on toon 1 as probably it is not necessary"
		disableNmbd
		echo "EDITING: download certificate store pem file"
		checkCApem
	fi
}

setOpkgFeedFiles() {
	BASE_FEED_URL="http://feed.hae.int/feeds"
	RUNNINGVERSION=`opkg list-installed base-$ARCH-\* | sed -r -e "s/base-$ARCH-([a-z]{3})\s-\s([0-9]*\.[0-9]*\.[0-9]*)-.*/\2/"`

	# set extra pkg system feeds
	EXTRA_FEEDS="`wget -q "${BASE_FEED_URL}/${ARCH}/${FLAV}/${RUNNINGVERSION}/SystemFeed" -O -`"
	if [ "$EXTRA_FEEDS" = "" ]
	then
		echo "Failed retrieving '${BASE_FEED_URL}/${ARCH}/${FLAV}/${RUNNINGVERSION}/SystemFeed', trying again verbosely:"
		wget "${BASE_FEED_URL}/${ARCH}/${FLAV}/${RUNNINGVERSION}/SystemFeed" -O - 2>&1
		exitFail
	fi

	#set correct feed location for initial install
	rm -f /etc/opkg/*-feed.conf /var/lib/opkg/lists/*
	echo "src/gz base ${BASE_FEED_URL}/${ARCH}/${FLAV}/${RUNNINGVERSION}" > /etc/opkg/base-feed.conf
	echo "$EXTRA_FEEDS" | {
	while read EF
	do
		EF_NAME="`echo "$EF" | cut -d ' ' -f1`"
		EF_PATH="`echo "$EF" | cut -d ' ' -f2`"
		echo "src/gz ${EF_NAME} ${BASE_FEED_URL}/${ARCH}/${EF_PATH}" > /etc/opkg/${EF_NAME}-feed.conf
	done;
	}

	echo ">> configured opkg feeds:"
	cat /etc/opkg/*-feed.conf
}

checkVPNcertificates() {
	#first check for empty vpn.conf on a qb2
	if grep -q qb2 /etc/opkg/arch.conf
	then
		echo "Check vpn.conf"
       		cp /etc/openvpn/vpn.conf /tmp/vpn.conf
		if grep -q tap0 /tmp/vpn.conf 
			then
				echo "The vpn.conf seems ok, continuing..."
			else
				echo "vpn.conf is empty, restoring it for you..."
				#create a new vpn.conf
				REALHOSTNAMEVPN=`find /etc/openvpn/vpn -maxdepth 1 -name "eneco*.crt" | cut -d\/ -f5 | cut -d\. -f1`
				echo "Creating new vpn.conf with hostname: $REALHOSTNAMEVPN"
				cat <<'EOT' > /tmp/vpn.conf
tls-client
dev tap0
proto tcp-client
#port handled by vpn_port.conf
config /etc/openvpn/vpn_port.conf
pull
ca      /etc/openvpn/vpn/ca.crt
cert    /etc/openvpn/vpn/blabla.crt
key     /etc/openvpn/vpn/blabla.key
tls-auth /etc/openvpn/vpn/ta.key 1
persist-key
persist-tun
ping 10
ping-restart 60
tls-exit
writepid /var/run/openvpn-vpn.pid
management 127.0.0.1 8000
#management-hold set dynamically by netcon if needed
verb 1
# Empty
EOT
				sed -i "s~blabla~$REALHOSTNAMEVPN~g" /tmp/vpn.conf
				cp /tmp/vpn.conf /etc/openvpn/vpn.conf
				echo "New vpn.conf with hostname: $REALHOSTNAMEVPN created"
		fi
	fi


	NEEDVPNUPDATE=false
	if grep -q nxt /etc/opkg/arch.conf
	then
		if openssl x509 -in /etc/openvpn/certs/device.crt -noout -issuer | grep -q "Prodrive"
                then
			NEEDVPNUPDATE=true
                fi
	else
        	#get real hostname (don't believe $HOSTNAME is always correct on rooted toons)
        	REALHOSTNAME=`find /etc/openvpn/vpn -maxdepth 1 -name "eneco*.crt" | cut -d\/ -f5 | cut -d\. -f1`
                if openssl x509 -in /etc/openvpn/vpn/$REALHOSTNAME.crt -noout -issuer | grep -q "Home Automation"
                then
			NEEDVPNUPDATE=true
                fi
	fi

        if [ "$NEEDVPNUPDATE" = true ]
	then
		echo "This toon contains old VPN certificates. Need to request new certificates!"
                requestVPNCertificates
	else
		echo "This toon does not contain old VPN certficates. Not necessary to update VPN certificates."
	fi

}

requestVPNCertificates() {
	#for a toon2 only replace the ta-ene.key and let the software update to 5.49.16 to request the certificates
	if grep -q nxt /etc/opkg/arch.conf
	then
       		TASYMLINK=`readlink -f /etc/openvpn/certs/ta-ene.key`
        	if [ ! "$TASYMLIK" == "/mnt/persist/etc/openvpn/certs/ta.key" ]
        	then
                	echo "Updating ta-ene.key symlink on this Toon2. This will be enough to be able to use VPN again. Please update the firmware asap to update the VPN certificates!"
                	cd /etc/openvpn/certs/
                	rm ta-ene.key
                	ln -s /mnt/persist/etc/openvpn/certs/ta.key ta-ene.key
        	else
                	echo "The ta-ene.key symlink is already correct on this toon 2. Please just update to the most recent firmware to update the VPN certificates!"
        	fi
	else
		#for the toon1 we need to request the certs ourselves
        	echo "We are on a Toon 1 so we need to request new certificates before being able to create a VPN connection..."
        	mkdir -p /root/newvpn

        	#Generate a new key
        	openssl genpkey  -outform PEM  -out /root/newvpn/device.key  -algorithm RSA  -pkeyopt rsa_keygen_bits:2048

        	#create the file /root/newvpn/openssl-client.cnf with the following text context (between the EOT's)
        	cat <<'EOT' > /root/newvpn/openssl-client.cnf
[ req ]
distinguished_name=dn
[ dn ]
# Empty
EOT
        	#get real hostname (don't believe $HOSTNAME is always correct on rooted toons)
        	REALHOSTNAME=`find /etc/openvpn/vpn -maxdepth 1 -name "eneco*.crt" | cut -d\/ -f5 | cut -d\. -f1`

        	#generate a certificate signing request, make sure toon hostname is set to original hostname and not your own
        	openssl req  -config /root/newvpn/openssl-client.cnf  -outform PEM  -out /root/newvpn/device.csr  -subj "/O=Quby B.V./CN=$REALHOSTNAME"  -key /root/newvpn/device.key -new

        	#put old certificate and CSR into a JSON blob
        	OLDCERT=$(cat /etc/openvpn/vpn/$REALHOSTNAME.crt | sed 's/$/\\n'/ | tr -d '\n')

        	#and then add CSR and create JSON blob
        	CSR=$(cat /root/newvpn/device.csr  | sed 's/$/\\n'/ | tr -d '\n')
        	JSON="{\"deviceCrt\": \"$OLDCERT\",\"deviceCsr\": \"$CSR\"}"

        	#send this to the certificate signing server
        	echo "New VPN certificate request created and now sending the request to Eneco..."
		sed -i '/api.quby.io/d' /etc/hosts
        	IFS="" ; curl -fNks 'https://api.quby.io/account/signcertificate' --location --request POST --write-out %{http_code} --header 'Content-Type: application/json' --data-raw $JSON -o /root/newvpn/new.json

        	#seperate the content of the result JSON to create new certificate files
		if [ -f /root/newvpn/new.json ]
		then
        		cat /root/newvpn/new.json | sed 's/.*\"cert\":\"\(.*\)\",\"tlsKey.*/\1/' | sed 's/\\n/\n/g' > /root/newvpn/device.crt
        		cat /root/newvpn/new.json | sed 's/.*\"tlsKey\":\"\(.*\)\",\"ca.*/\1/' | sed 's/\\n/\n/g'  > /root/newvpn/ta.key
        		cat /root/newvpn/new.json | sed 's/.*\"ca\":\"\(.*\)\"}].*/\1/' | sed 's/\\n/\n/g' > /root/newvpn/server-ca-bundle
		else
                	echo "Failed to request and update the VPN certificates!"
			exit
		fi

        	#then check certificate for validity
        	MD5CRT=`openssl x509 -noout -modulus -in /root/newvpn/device.crt | openssl md5`
        	MD5KEY=`openssl rsa -noout -modulus -in /root/newvpn/device.key | openssl md5`
        	if [ "$MD5CRT" == "$MD5KEY" ]
        	then
                	#replace existings certs finally
                	echo "Request successful and updating the VPN certificates now..."
                	cd /etc/openvpn/vpn
                	mv ca.crt ca.crt.bak
                	mv $REALHOSTNAME.crt $REALHOSTNAME.crt.bak
                	mv $REALHOSTNAME.key $REALHOSTNAME.key.bak
                	mv ta.key ta.key.bak
                	mv /root/newvpn/device.crt $REALHOSTNAME.crt
                	mv /root/newvpn/device.key $REALHOSTNAME.key
                	mv /root/newvpn/server-ca-bundle ca.crt
                	mv /root/newvpn/ta.key ta.key
			#remove old options in vpn.conf
			cp /etc/openvpn/vpn.conf /tmp/vpn.conf
			sed -i '/dh1024/d' /tmp/vpn.conf
			sed -i '/VPN-Eneco/d' /tmp/vpn.conf
			cp /tmp/vpn.conf /etc/openvpn/vpn.conf
			sync ; sync
        	else
                	echo "Failed to request and update the VPN certificates!"
			exit
        	fi
	fi
}


#main

UNATTENDED=false
ONLYVPNSTART=false
STEP=0
VERSION=""
SOURCE="http://feed.hae.int/feeds"
ORIGINALSOURCE=true	
ENABLEVPN=true
PROGARGS="$@"


#get options
while getopts ":v:s:abcfduho" opt $PROGARGS
do
	case $opt in
		v)
			echo "Forcing version: $OPTARG"
			VERSION=$OPTARG
			;;
		s)
			echo "Forcing source: $OPTARG"
			SOURCE=$OPTARG
			ORIGINALSOURCE=false	
			;;
		a)
			echo "Auto activation"
			editActivation
			exit
			;;
		u)
			echo "Unattended mode"
			UNATTENDED=true
			QUESTION="yes"
			;;
		o)
			echo "Only start VPN and then quit"
			ONLYVPNSTART=true
			VERSION="none"
			;;
		d)
			echo "Skip starting VPN"
			ENABLEVPN=false
			;;
		c)
			echo "Requesting new VPN certificates"
			checkVPNcertificates
			exit
			;;
		f)
			echo "Only fixing files."
			getArch
			makeBackupUpdate
			makeBackupFixFiles
			fixFiles
			checkFixedFiles
			echo "Finished fixing files!"
			exit
			;;
		h)      usage
			exit 1
			;;
		\?)
			echo "Invalid option: -$OPTARG"
			exit
			;;
	esac
done

#get recent version of this script
autoUpdate $PROGARGS

#determine where this Toon is storing the update files
PKGCACHE='/mnt/data/update'
if ! strings /HCBv2/sbin/hcb_config | grep -q -e "^${PKGCACHE}\$"
then
	#this toon still uses the old PKGCACHE
	PKGCACHE='/HCBv2/tmp/opkg-cache'
else
	#make sure this old dir doesn't exists anymore so we don't accidently start a very old update script (and we don't care about old logs)
	rm -rf /HCBv2/tmp/opkg-cache
fi
#check if the cache dir is already there, create it otherwise (should normally be there always)
if [ ! -d $PKGCACHE ] 
then
	mkdir -p $PKGCACHE
fi

STATUSFILE="$PKGCACHE/updated-rooted.status"
#check previous running script
if [ -f $STATUSFILE ]  && ! $UNATTENED #no resume in unattended mode
then
	echo "Detected an unclean abort of previous running update script. Do you want me to resume (yes) or restart (no)?"
	read RESUME
	if [ "$RESUME" == "yes" ] 
	then 
		echo "Ok, resuming. Trying to determine last step."
		STEP=`cat $PKGCACHE/updated-rooted.status | sed -n -r -e 's,([0-9]+);([0-9]+\.[0-9]+\.[0-9]+);(.*);(.*),\1,p'`
		VERSION=`cat $PKGCACHE/updated-rooted.status | sed -n -r -e 's,([0-9]+);([0-9]+\.[0-9]+\.[0-9]+);(.*);(.*),\2,p'`
		FLAV=`cat $PKGCACHE/updated-rooted.status | sed -n -r -e 's,([0-9]+);([0-9]+\.[0-9]+\.[0-9]+);(.*);(.*),\3,p'`
		ARCH=`cat $PKGCACHE/updated-rooted.status | sed -n -r -e 's,([0-9]+);([0-9]+\.[0-9]+\.[0-9]+);(.*);(.*),\4,p'`
		echo "Resuming at step $STEP and we where installing version $VERSION with flavour $FLAV in a $ARCH system"
	fi
	# remove statusfile so we don't restart at the same point the next time
	rm -f $STATUSFILE
fi

if [ $STEP -lt 1 ] 
then
	STEP=1;
	#get the architecture
	getArch
	#get the current flavour
	getFlav
	#we need to determine current version and to which version we want to upgrade to
	if [ "$VERSION" == "" ]
	then 
		#echo "Currently the Eneco server (their update script) is broken. This is causing update issue from earlier versions to 5.0.4. Canceling the updaten now until they fixed this."
		#exit
		getVersion
	fi
	echo "$STEP;$VERSION;$FLAV;$ARCH" > $STATUSFILE
fi

if [ $STEP -lt 2 ] 
then
	STEP=2;
	#then we make a backup of some important files, just to be sure
	makeBackupUpdate
	echo "$STEP;$VERSION;$FLAV;$ARCH" > $STATUSFILE
fi

#even if we resume we need to make sure we have the firewall in place and renable the VPN
#before opening the connection to Eneco's network we prepare the firewall to only allow access from/to the download server
if $ENABLEVPN
then
	#check if VPN certificates needs updating
	checkVPNcertificates
	#put some firewall rules inplace before starting VPN to block service center traffic
	initializeFirewall
	#now we are ready to try to start the VPN
	enableVPN
	if $ONLYVPNSTART
	then
		setOpkgFeedFiles
		echo "VPN is started, OPKG sources should now be available for you. Good luck!"
		echo "If you are done with manual package downloading, just reboot and the VPN should be closed again."
		exit
	fi
fi

if [ $STEP -lt 3 ] 
then
	STEP=3;
	#we are ready to download the eneco upgrade script
	downloadUpgradeFile
	echo "$STEP;$VERSION;$FLAV;$ARCH" > $STATUSFILE
fi

if [ $STEP -lt 4 ] 
then
	STEP=4;
	#if the script is ok, we start downloading the updates (prepare)
	startPrepare
	echo "$STEP;$VERSION;$FLAV;$ARCH" > $STATUSFILE
fi

if [ $STEP -lt 5 ] 
then
	STEP=5;
	#and if that is succesfull we start the upgrade
	startUpgrade
	echo "$STEP;$VERSION;$FLAV;$ARCH" > $STATUSFILE
fi


if [ $STEP -lt 6 ] 
then
	STEP=6;
	#finally we restore the important files
	restoreBackup
	echo "$STEP;$VERSION;$FLAV;$ARCH" > $STATUSFILE
fi


if [ $STEP -lt 7 ]
then
	STEP=7;
	#some other fixing needs to be done after an upgrade
	echo "Upgrade is done. However each firmware upgrade will revert the changes to some files needed for a working rooted Toon. Do you want me me to try and fix a few well known issue's for you right now?"
	if ! $UNATTENDED ; then read QUESTION ; fi
	if [ "$QUESTION" == "yes" ] 
	then
		makeBackupFixFiles
		fixFiles
		checkFixedFiles
		checkOVPN
	fi
	echo "$STEP;$VERSION;$FLAV;$ARCH" > $STATUSFILE
fi

# sync the filesystem
sync ; sync

echo "Everything done! You should reboot now! Do NOT power cycle! Just issue the 'reboot' command in your shell. Power cycling can cause file system problems."

#remove statusfile
rm -f $STATUSFILE

if $UNATTENDED
then
	#reboot in autattended mode
	shutdown -r now
fi
