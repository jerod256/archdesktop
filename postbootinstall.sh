#!/bin/bash
######################################
###  ###
### by: Liz Boudreau		   ###
### License: GPL-2.0		   ###
######################################

### This script will do a fully automated installation of void linux from the command line
### this script is meant to be run after the first boot
### this script was designed and tested with the void linux image released in 2025 and assumes Linux 6.12

### This script is a work in progress, use at your own risk. It is not supported. Issues will be ignored.
### Sources used for creating this script: man-pages, void linux manual, and https://github.com/dylanbegin/void-install.git

### The target system will have the following installation features and qualities
### a single volume inside a LUKS2 partition, ZRAM and swapfile will be used for swap
### An EFI partition containining the kernel and initramfs images
### limine bootloader

##### Instructions for Running this script
### 1. Should be performed booting up into the target system - do no run in live session
### 2. run $ git clone https://github.com/jerod256/voidinstall.git
### 3. cd voidinstall
### 4. chmod +x postbootinstall.sh
### 5. setup and start services dbus and connmand in that order
### 6. make sure you read the postbootinstall.sh script, because the next part requires root access
### 7. sudo ./postbootinstall.sh

### THIS SCRIPT ASSUMES THE TARGET SYSTEM IS CONNECTED TO THE INTERNET VIA ETHERNET

### This script will setup:
### 1. setup services installed in preboot install
### 2. activate services
### 3. updates system via package manager
### 4. installs fonts
### 5. installs a graphical desktop environment (sway)
### 6. sets timezone (Canada/Eastern)
### 7. changes the user shell to fish
### 8. sets up a cron job to trim the SSDs

### package list for gui
pkg_gui_wl="xdg-desktop-portal-hyprland wmenu wl-clipboard hyprland hyprlock hyprpolkit grim slurp wiremix bluetui kitty foot ffmpeg firefox qutebrowser firejail mesa fastfetch yazi mako fish-shell steam"
### package list for fonts
pkg_fonts="dejavu-fonts-ttf xorg-fonts noto-fonts-ttf noto-fonts-cjk noto-fonts-emoji nerd-fonts"
### remove mesa and install nouveau for an nvidia GPU. this script will not deal with proprietary nvidia drivers
### add session for setting up pam_rundir and adding line:
### '-session optional pam_rundir.so' /etc/pam.d/system-login



### perform a system update. note if this fails its probably because the internet is not there
pacman -Syu


### install fonts and link
pacman -S $pkg_fonts
ln -s /usr/share/fontconfig/conf.avail/70-no-bitmaps-except-emoji.conf /etc/fonts/conf.d

### Install graphical system and apps
pacman -S $pkg_gui_wl

### setup a cron job to trim the SSDs
touch /etc/cron.weekly/fstrim
cat <<EOF > /etc/cron.weekly/fstrim
#!/bin/sh
/sbin/fstrim -a -v
EOF
chmod u+x /etc/cron.weekly/fstrim

### setting up fish as the default shell
#command -v fish | sudo tee -a /etc/shells
#chsh -s "$(command -v fish)" jerec

### Do later because of the complexity and/or risks:
### 1. Kernel update
### 2. Kernel parameter adjustments
### 3. dotfile update
### 4. neovim config clone
### 5. zswap - note that it is not enabled by default
### of these, zswap should be done earlier because of its crucial performance impact and the fact that void does not enable it by default
### might be a good idea to put the zswap into the bootloader with similar defaults to Arch Linux just to start, in the prebootinstall.sh. that way I don't have to ever worry about excessive disk swapping

##### Check after running this script:
### 1. services linked and running (use '# sv status /var/service/*' and 'ls /var/service/')
### 2. check time
### 3. check /etc/pam.d/system-login
### 4. check the cron job for fstrim
