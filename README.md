# Update a rooted Toon 

When running this script on a rooted Toon (thermostat from Eneco - the Netherlands) it will try to connect to the Eneco VPN and upgrade your toon to the version you specify.
It will backup and repair important files which are overwritten by the upgrade. Also, it will block any other traffic over the VPN so no unwanted service center messages are received or transferred.

The script uses the Toon original files to upgrade the Toon so there is a good chance the upgrade works fine. However sometimes upgrade fails due to misconfigurations of rooted Toons.

## running the script

Download the script towards your Toon. The easiest way is just to use curl from your Toon:

`curl -Nks https://raw.githubusercontent.com/ToonSoftwareCollective/update-rooted/main/update-rooted.sh -o /root/update-rooted.sh`

Then run the script with:

`sh /root/update-rooted.sh`

## script options

The script without any option runs a normal upgrade. It first checks your current version and will ask you to which version you want to update.

With the option -v you can select a version number, ignoring any check if the version does exist and ignoring any required intermediate updates.

With the option -f you skip the entire update and do a fix local files only (patching important files on the Toon required for rooting which are overwritten with an upgrade).

With the option -d you can skip the VPN and firewall mods. The VPN isn't necessary if you choose another source with option -s (default source: http://feed.hae.int/feeds). This is only necessary if you have for example a test environment with own source files.

With the option -u you can run an unattended firmware upgrade. It will not ask for any questions and will fetch the latest possible firmware. It will also reboot after the upgrade. Use with care!

## observed issues

Users reported a few issues while running the update. Which include:

- Failed update due to low diskspace. Check (with df -h) if your Toon has enough diskspace for the upgrade. Exact numbers are not yet known but recommend to have at least 10MB diskspace on the Toon free.
- Failed update due to previous failed manual updates. If previous manual updates (without the script) failed to update the Toon, this script will probably also fail.
- Problems with connecting to the VPN. Some users have problems with their VPN keys and therefore cannot update using the Quby/Eneco sources anymore.
