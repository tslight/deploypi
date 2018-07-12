#!/usr/bin/env bash

set -eo pipefail # fail quickly and gracefully

###############################################################################
#                                  CONSTANTS                                  #
###############################################################################

# Define colors to be used when echoing output
readonly NC=$(tput sgr0)
readonly BLACK=$(tput setaf 0)
readonly RED=$(tput setaf 1)
readonly GREEN=$(tput setaf 2)
readonly YELLOW=$(tput setaf 3)
readonly BLUE=$(tput setaf 4)
readonly MAGENTA=$(tput setaf 5)
readonly CYAN=$(tput setaf 6)
readonly WHITE=$(tput setaf 7)

# define arrays of packages to install or remove
readonly PKGRM=(
    "nano"
    "vim-tiny"
)

readonly PKGADD=(
    "neovim"
    "emacs-nox"
    "ed"
    "tmux"
    "ranger"
    "htop"
    "ncdu"
    "xorg"
    "jwm"
    "matchbox-window-manager"
    "chromium-browser"
    "wmctrl"
    "xautomation"
)

# variable to get the pwd
readonly SCRIPTDIR="$(cd "$(dirname "$0")"; pwd)"
readonly SCRIPTNAME=$(basename "$0")
readonly SCRIPTPATH="$SCRIPTDIR/$SCRIPTNAME"

# variables to hold question strings and colors
readonly UPDATEQ="${MAGENTA}Would you like to update your packages?${NC} ";
readonly PKGSQ="${MAGENTA}Would you like to remove and install the pre-defined list of packages?${NC} ";
readonly PASSWDQ="${MAGENTA}Would you like to change the default pi password?${NC} ";
readonly USERQ="${MAGENTA}Would you like to setup a new user?${NC} ";
readonly HOSTNAMEQ="${MAGENTA}Would you like to change the hostname?${NC} ";
readonly CONFIGQ="${MAGENTA}Would you like to install configuration files to a user profile?${NC} ";
readonly REBOOTQ="${MAGENTA}Would you like to reboot now?${NC} ";

###############################################################################
#                                   GLOBALS                                   #
###############################################################################

# array to store urls entered by user in
declare -a URLS


###############################################################################
#                                    USAGE                                    #
###############################################################################
usage () {
    echo "
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


###############################################################################
#                                MISC FUNCTIONS                               #
###############################################################################

checkroot() {
    if [ "$(id -u)" -ne 0 ]; then
	echo "${RED}This script must be run as root. Either run 'sudo -s' or prefix the script with sudo.${NC}"
	echo "${RED}eg: 'sudo /path/to/install.sh'${NC}"
	usage
	exit 1
    fi
}

# function to read in an answer from the user. keep looping until user enters
# valid answer.  returns 0 for yes, 1 for no or quit, and an error message for
# anything else (before re-looping)
ask () {
    local question="$1"

    while :; do
	read -rep "$question" ans;
	case "$ans" in
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
		echo "${RED}You must enter either y or n to continue.${NP}"
		echo "${RED}You can also enter q to quit the script.${NP}"
		;;
	esac;
    done
}


###############################################################################
#                              PACKAGE MANAGEMENT                             #
###############################################################################

# install script if not already installed
installself() {
    if ! [ -x /usr/local/bin/"$SCRIPTNAME" ]; then
	chmod +x "$SCRIPTPATH"
	cp "$SCRIPTPATH" /usr/local/bin/"$SCRIPTNAME"
    fi
}

# function to update the system without any prompting from the user (-y)
update () {
    apt -y update
    apt -y upgrade
    apt -y dist-upgrade
}

# function to remove packages. takes a package name as an argument.
remove () {
    local pkg="$1"

    apt -y purge "$pkg"
}

# function to prune no longer needed packages and clean the package
# caches.
clean () {
    apt -y autoremove
    apt -y autoclean
    apt -y clean
}

# function to install a package. takes the package name as an
# argument.
install () {
    local pkg="$1"

    apt -y install "$pkg"
}

# function that checks what packages from the pre-defined script need
# to be installed or removed.
pkgs () {
    local doclean pkg

    if [ "${#PKGRM[@]}" -eq 0 ]; then
	echo "${CYAN}No packages to remove.${NC}";
    else
	doclean="false";
	for pkg in "${PKGRM[@]}"; do
	    if dpkg-query -s "$pkg" &> /dev/null; then
		doclean="true";
		remove "$pkg";
	    fi
	done
	# run clean function if we remove any packages.
	[ "$doclean" == "true" ] && clean
    fi

    if [ "${#PKGADD[@]}" -eq 0 ]; then
	echo "${CYAN}No packages to install.${NC}";
    else
	for pkg in "${PKGADD[@]}"; do
	    if ! dpkg-query -s "$pkg" &> /dev/null; then
		install "$pkg";
	    fi
	done
    fi
}


###############################################################################
#                               ADMIN FUNCTIONS                               #
###############################################################################

# function to set up new user. read in user name, add user to
# specified groups and prompt for password.
adduser () {
    local user

    read -rep "${GREEN}Enter User Name: ${NC}" user;
    if id "$user" >/dev/null 2>&1; then
	echo "${CYAN}$user already exists.${NC}";
    else
	useradd -m -G operator,systemd-journal,sudo,users,netdev -s /bin/bash "$user";
	passwd "$user";
    fi
}

# function to change the devices hostname. read in hostname then echo
# it into /etc/hostname and /etc/hosts
sethostname () {
    local hostname

    read -rep "${GREEN}Enter hostname: ${NC}" hostname;
    echo "$hostname" | tee /etc/hostname &>/dev/null;
    sed -i '$ d' /etc/hosts;
    echo "127.0.0.1 $hostname" | sudo tee -a /etc/hosts &>/dev/null;
    echo "${CYAN}Setting hostname complete. You will need to reboot for this change to take effect.${NC}";
}

reboot () {
    echo "${CYAN}Set up complete. Rebooting in 2 seconds ... Have a nice day.${NC}"
    sleep 2
    systemctl reboot
}


###############################################################################
#                                 URL PARSING                                  #
###############################################################################

switchurl() {
    local url="$1"

    read -rep "${GREEN}Enter the page title of $url: ${NC}" title
    read -rep "${GREEN}Time between refreshes (in seconds): ${NC}" time

    if [[ "$time" =~ ^[0-9]+$ ]]; then
	sed -i "/URLS/achromium-browser --app=\"$url\" &" /home/"$user"/.xinitrc
	sed -i "/TITLES/awhile \:\; do\nwmctrl -R \"$title\"\nxte \"key F5\"\nsleep ${time}s\ndone" /home/"$user"/.xinitrc
    else
	echo "${RED}Invalid time. Try again!${NC}"
	switchurl "$url"
    fi
}

addurls() {
    for url in "${URLS[@]}"; do
	if [[ "${#URLS[@]}" -gt 1 ]]; then
	    switchurl "$url"
	elif ask "${GREEN}Would you like to automatically refresh this page? ${NC}"; then
	    switchurl "$url"
	else
	    sed -i "/URLS/achromium-browser --app=\"$url\"" /home/"$user"/.xinitrc
	fi
    done
}

# function to check for valid url. takes a string as an input and checks if
# contains the substring "http". This needs to be better!  Should do a more
# advanced RegEx match...
checkurl () {
    local url="$1"

    if echo "$url" | grep -q "http"; then
	return 0;
    else
	return 1;
    fi
}

# continuously prompt for urls until the user quits, then return an array of
# entered urls.
geturls() {
    read -rep "${GREEN}Enter URL to display: ${NC}" url
    until [ "$url" == "q" ] || [ "$url" == "n" ]; do
	if checkurl "$url"; then
	    URLS+=("$url")
	else
	    echo "${RED}Not a valid URL. You numpty Bradley.${NP}"
	fi
	read -rep "${GREEN}Enter another URL to display: (q to quit) ${NC}" url
    done
}


###############################################################################
#                                CONFIG WRITING                               #
###############################################################################

# function to create systemd write_ttyconf service file, which
# automatically logs a use into tty1. takes a user name as an
# argument.
write_ttyconf () {
    local user="$1"
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $user --noclear %I $TERM
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
write_profile () {
    local user="$1"

    cat > /home/"$user"/.bash_profile <<'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
startx
fi
[ -f ~/.bashrc ] && source ~/.bashrc
EOF
}

# function to create an xsession configuration file that starts the
# window-manager and web browser. takes a user name as an argument.
write_xinitrc () {
    local user="$1"

    cat > /home/"$user"/.xinitrc <<'EOF'
#!/bin/sh
while :; do
xset -dpms; xset s off
matchbox-window-manager -use_titlebar no -use_cursor yes &
# URLS
# TITLES
done
EOF
}

# Wrapper function to write the necessary configuration files for automating the
# process of logging the user into tty1, and then starting and configuring the
# xsession.
installconfig () {
    local user url title
    local -i valid_user

    read -rep "${GREEN}Enter the user you would like to give the configuration to: ${NC}" user;
    valid_user=1;
    until [ "$valid_user" -eq 0 ]; do
	if id "$user" > /dev/null 2>&1; then
	    valid_user=0
	    write_ttyconf "$user"
	    write_profile "$user"
	    write_xinitrc "$user"
	    geturls
	    addurls "${URLS[@]}"
	    chown "$user":"$user" /home/"$user"/.xinitrc
	    chown "$user":"$user" /home/"$user"/.bash_profile
	else
	    echo "${RED}$user doesn't exist.${NC}";
	    read -rep "${GREEN}Enter the user you would like to give the configuration to: ${NC}" user
	fi
    done
}

main () {
    checkroot
    installself
    case "$@" in
	-a|--all)
	    ask "$UPDATEQ" && update
	    ask "$PKGSQ" && pkgs
	    ask "$PASSWDQ" && passwd pi
	    while ask "$USERQ"; do
		adduser
	    done
	    ask "$HOSTNAMEQ" && sethostname
	    ask "$CONFIGQ" && installconfig
	    ask "$REBOOTQ" && reboot
	    ;;
	-A|--allyes)
	    update
	    pkgs
	    passwd pi
	    while ask "$USERQ"; do
		user
	    done
	    hostname
	    config
	    ask "$REBOOTQ" && reboot
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
}

main "$@"
