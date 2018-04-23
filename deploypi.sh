#!/bin/bash

# Define colors to be used when echoing output
NC=`tput sgr0`;
BLACK=`tput setaf 0`;
RED=`tput setaf 1`;
GREEN=`tput setaf 2`;
YELLOW=`tput setaf 3`;
BLUE=`tput setaf 4`;
MAGENTA=`tput setaf 5`;
CYAN=`tput setaf 6`;
WHITE=`tput setaf 7`;

# define arrays of packages to install or remove
PKGRM=('nano' 'vim-tiny');
PKGADD=('neovim' 'mg' 'tmux' 'ranger' 'htop' 'ncdu' 'xorg' 'jwm' 'matchbox-window-manager' 'chromium-browser' 'wmctrl' 'xautomation');

# variable to get the pwd
SCRIPTDIR="$(cd "$(dirname "$0")"; pwd)";
SCRIPTNAME=$(basename "$0");
SCRIPTPATH=$SCRIPTDIR/$SCRIPTNAME;

# function to read in an answer from the user. keep looping until user
# enters valid answer.  returns 0 for yes, 1 for no or quit, and an
# error message for anything else (before re-looping)
ask () {
    while :
    do
	read -e -p "$1" ans;
	case $ans in
	    [yY]*)
		return 0
		break
		;;
	    [nN]*)
		return 1
		break
		;;
	    [qQ]*)
		exit 1
		break
		;;
	    *)
		echo "${RED}You must enter either y or n to continue.${NP}";
		echo "${RED}You can also enter q to quit the script.${NP}";
		;;
	esac;
    done
}

# function to update the system without any prompting from the user (-y)
update () {
    apt -y update;
    apt -y upgrade;
    apt -y dist-upgrade;
}

# function to remove packages. takes a package name as an argument.
remove () {
    apt -y purge $1;
}

# function to prune no longer needed packages and clean the package
# caches.
clean () {
    apt -y autoremove;
    apt -y autoclean;
    apt -y clean;
}

# function to install a package. takes the package name as an
# argument.
install () {
    apt -y install $1;
}

# function to create systemd autologin service file, which
# automatically logs a use into tty1. takes a user name as an
# argument.
autologin () {
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $1 --noclear %I $TERM
EOF
    cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf <<EOF
[Service]
TTYVTDisallocate=no
EOF
}

# function to create bash_profile that automatically starts the
# xserver if the $DISPLAY environmental variable is set (i.e. there is
# a display to output to), and the tty is tty1 (the tty autologin()
# logs us into).
autostartx () {
    cat > /home/$1/.bash_profile <<'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
startx -- -nocursor
fi
[ -f ~/.bashrc ] && source ~/.bashrc
EOF
}

# function to create an xsession configuration file that starts the
# window-manager and web browser. takes a user name as an argument.
autoxconf () {
    cat > /home/$1/.xinitrc <<'EOF'
#!/bin/sh
while true; do
xset -dpms
xset s off
# Start the window manager (remove "-use_cursor no" if you actually want mouse interaction)
matchbox-window-manager -use_titlebar no -use_cursor no &
# examples:
# chromium-browser  --app=https://support.mcsaatchi.com/helpdesk &
# chromium-browser --app=http://10.1.1.198/nagiosxi/includes/components/opscreen/opscreen.php &
# urls here
while :
do
echo &> /dev/null;
# titles here
done
done;
EOF
}

# function that checks what packages from the pre-defined script need
# to be installed or removed.
pkgs () {
    if [ ${#PKGRM[@]} -eq 0 ]; then
	echo "${CYAN}No packages to remove.${NC}";
    else
	doclean="false";
	for PKG in ${PKGRM[@]}; do
	    if dpkg-query -s $PKG &> /dev/null; then
		doclean="true";
		remove $PKG;
	    fi
	done
	# run clean function if we remove any packages.
	[ "$doclean" == "true" ] && clean
    fi

    if [ ${#PKGADD[@]} -eq 0 ]; then
	echo "${CYAN}No packages to install.${NC}";
    else
	for PKG in ${PKGADD[@]}; do
	    if ! dpkg-query -s $PKG &> /dev/null; then
		install $PKG;
	    fi
	done
    fi
}

# function to set up new user. read in user name, add user to
# specified groups and prompt for password.
user () {
    read -e -p "${GREEN}Enter User Name: ${NC}" -r USER;
    if id $USER >/dev/null 2>&1; then
	echo "${CYAN}admin user already exists.${NC}";
    else
	useradd -m -G adm,operator,systemd-journal,tty,dialout,cdrom,sudo,audio,www-data,video,plugdev,games,users,input,netdev,spi,i2c,gpio -s /bin/bash $USER;
	passwd $USER;
    fi
}

# function to change the devices hostname. read in hostname then echo
# it into /etc/hostname and /etc/hosts
hostname () {
    read -e -p "${GREEN}Enter hostname: ${NC}" -r HN;
    echo $HN | tee /etc/hostname &>/dev/null;
    sed -i '$ d' /etc/hosts;
    echo "127.0.0.1 $HN" | sudo tee -a /etc/hosts &>/dev/null;
    echo "${CYAN}Setting hostname complete. You will need to reboot for this change to take effect.${NC}";
}

# function to check for valid url. takes a string as an input and
# checks if contains the substring "http". This needs to be better!
# Should do a more advanced RegEx match...
urlcheck () {
    if echo "$1" | grep -q "http"; then
	return 0;
    else
	return 1;
    fi
}

# function to insert urls and wmctrl pattern matchs into xinitrc
# created by autoxconf.
config () {
    read -e -p "${GREEN}Enter the user you would like to give the configuration to: ${NC}" -r USER;
    valid_user=1;
    until [ $valid_user == 0 ]; do
	if id $USER > /dev/null 2>&1; then
	    valid_user=0;
	    autologin $USER;
	    autostartx $USER;
	    autoxconf $USER;
	    URLS=();
	    read -e -p "${GREEN}Enter URL to display: ${NC}" -r URL;
	    until [ "$URL" == "q" ] || [ "$URL" == "n" ]; do
		if urlcheck "$URL"; then
		    sed -i "/urls here/a\\chromium-browser --app=\"$URL\" &" /home/$USER/.xinitrc;
		    URLS+=($URL);
		else
		    echo "${RED}Not a valid URL. You numpty Bradley.${NP}";
		fi
		read -e -p "${GREEN}Enter another URL to display: (q to quit) ${NC}" -r URL;
	    done
	    if [ ${#URLS[@]} -gt 0 ]; then
		for url in ${URLS[@]}; do
		    read -e -p "${GREEN}Enter the page title of $url: ${NC}" -r title;
		    sed -i "/titles here/a\\wmctrl -R \"$title\"; xte \"key F5\"; sleep 30s;" /home/$USER/.xinitrc;
		done
	    fi
	    chown $USER:$USER /home/$USER/.xinitrc;
	    chown $USER:$USER /home/$USER/.bash_profile;
	else
	    echo "${RED}$USER doesn't exist.${NC}";
	    read -e -p "${GREEN}Enter the user you would like to give the configuration to: ${NC}" -r USER;
	fi
    done
}

reboot () {
    echo "${CYAN}Set up complete. Rebooting in 2 seconds ... Have a nice day.${NC}";
    sleep 2s;
    systemctl reboot;
}

usage () {
    echo -n "
$SCRIPTNAME [OPTION]

This script must be run with one of the following options.

Options:
  -a, --all          Executes all the commands in the order listed below.
  -A, --allyes       Executes all the commands accepting yes for all parameters.
  -u, --update       Updates all packages on the system.
  -i, --install      Installs and removes the pre-defined list of packages.
  -p, --password     Changes the default pi user password.
  -U, --user         Adds a new user to the system.
  -H, --hostname     Changes the systems hostname.
  -c, --config       Installs config files for a user to run in automated kiosk mode.
  -r, --reboot       Reboots the system.
  -h, --help         Display this help and exit.

"
}

update_question="${MAGENTA}Would you like to update your packages?${NC} ";
pkgs_question="${MAGENTA}Would you like to remove and install the pre-defined list of packages?${NC} ";
passwd_question="${MAGENTA}Would you like to change the default pi password?${NC} ";
user_question="${MAGENTA}Would you like to setup a new user?${NC} ";
hostname_question="${MAGENTA}Would you like to change the hostname?${NC} ";
config_question="${MAGENTA}Would you like to install configuration files to a user profile?${NC} ";
reboot_question="${MAGENTA}Would you like to reboot now?${NC} ";

if ! [ $(id -u) = 0 ]; then
    echo "${RED}This script must be run as root. Either run 'sudo -s' or prefix the script with sudo.${NC}";
    echo "${RED}eg: 'sudo /path/to/install.sh'${NC}";
    exit 1
fi

# install script if not already installed
if ! [ -x /usr/local/bin/$SCRIPTNAME ]; then
    chmod +x $SCRIPTPATH;
    cp $SCRIPTPATH /usr/local/bin/$SCRIPTNAME;
fi

case "$1" in
    -a|--all)
	ask "$update_question" && update
	ask "$pkgs_question" && pkgs
	ask "$passwd_question" && passwd pi
	while ask "$user_question"; do
	    user
	done
	ask "$hostname_question" && hostname
	ask "$config_question" && config
	ask "$reboot_question" && reboot
	;;
    -A|--allyes)
	update
	pkgs
	passwd pi
	while ask "$user_question"; do
	    user
	done
	hostname
	config
	ask "$reboot_question" && reboot
	;;
    -u|--update)
	update
	;;
    -i|--install)
	pkgs
	;;
    -p|--password)
	passwd pi
	;;
    -U|--user)
	user
	;;
    -H|--hostname)
	hostname
	;;
    -c|--config)
	config
	;;
    -r|--reboot)
	reboot
	;;
    -h|--help)
	usage
	;;
    *)
	usage
	;;
esac
