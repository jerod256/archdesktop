#!/bin/bash
################################################
### Performance Arch Linux Installation	     ###
### Stage Zero Disk prep and preboot install ###
### by: Liz Boudreau		   	     ###
### License: GPL-2.0		   	     ###
################################################

### This script will do a fully automated installation of Arch Linux from the command line
### it is meant to be run from a live installation image of Arch Linux
### this script was designed and tested with the Arch Linux image released in April of 2026 and assumes Linux 6.19
### remember to chroot in at the end, change the password and regenerate the initramfs

### This script is a work in progress, use at your own risk. It is not supported. Issues will be ignored.
### Sources used for creating this script: man-pages, Arch Linux wiki and I used my voidinstall script as a starting point

### The target system will have the following installation features and qualities
### a single volume for all root folders inside a physical partition formatted for ext4, ZRAM will be used for swap
### An EFI partition containining the kernel and initramfs images
### limine bootloader in the EFI partition

### security features are not investigated with this installation. do not use if security is a concern.

### to run this script, run the following manually:
### # mkdir /install
### # cd /install
### # pacman -S git vim efibootmgr #vim is for checking scripts
### # git clone https://github.com/jerod256/archdesktop.git
### # cd archdesktop
### # chmod +x prebootinstall.sh
### # ./prebootinstall.sh

mkdir -p /root/void-install/
touch /root/arch-install/install.log
{

### variables to be set (with defaults)
default_efi_name="vda1"
default_install_name="vda2"
LANG="en_US.UTF-8"
default_host="archdesktop"
default_USER="lizluv"
default_PASSWD="1234"
default_CRYPTPASS="56789"

### packages to be loaded into the live session for installation (seems to be required manually before this script is run)
#pkg_preinst="parted git"
#package list for basic system setup
#pkg_base="base-system cryptsetup efibootmgr nftables sbctl vim git lvm2 grub-x86_64-efi sbsigntool efitools tpm2-tools"
pkg_base="iptables-nft vim git limine efibootmgr pipewire wireplumber greetd tuigreet ufw base-devel wget curl btop udisks2 dhcpcd dbus"
### for gaming distro adjust package list to:
### consider doing away with greetd and tuigreet and use auto start scripts (like xinitrc).
### use dhcpcd if desktop and remove connman.
### remove bluez.
### remove tlp and tlp-pd if desktop

### gathers information
### 1. target disk label
lsblk
echo -n "Enter the name of the target boot partition as shown above"
read default_efi_name
echo
echo

### 2. EFI partition name
echo -n "Enter the name of the target root partition as shown above"
read default_install_name
echo
echo

### 3. User name
echo -n "Enter the username [leave blank for default]"
read temp_username
USER="${temp_username:-$default_USER}"
echo
echo


### 4. user password (also will be used for root)
while true; do
	echo -n "Enter password"
	read -s PASS1

	echo -n "Verify password"
	read -s PASS2

	if [ "$PASS1" = "$PASS2" ]; then
		echo "Password successfully set."
		break
	else
		echo "Match failed. Try again."
	fi
done

# mount the root volume
echo "creating root filesystem..."
mkfs.ext4 /dev/${default_install_name}
echo "mounting root filesystem..."
mount /dev/${default_install_name} /mnt

# mount the FAT32 /boot 
echo "Creating EFI filesystem FAT32..."
mkfs.fat -F 32 -n EFI /dev/${default_efi_name}
echo "mounting EFI stub directory..."
mkdir -p /mnt/boot/efi
mount /dev/${default_efi_name} /mnt/boot


### installation of base system and packages
echo "installing base system..."
pacstrap -K /mnt base $pkg_base


### generate the filesystem tble
echo "generting filesystem table..."
genfstab -U /mnt >> /mnt/etc/fstab
### next I need to replace the boot sector label from the /dev/** to its UUID
### first find the UUID
BOOT_UUID=$(blkid -s UUID -o value /dev/${default_efi_name})
### next inject the UUID into the UUID
#sed -i "s|/dev/$default_efi_name|UUID=$BOOT_UUID/g" /mnt/etc/fstab


### set permissions for the root
chroot /mnt chown root:root /
chroot /mnt chmod 755 /
chroot /mnt chpasswd <<< "root:$PASS1"
echo $default_host > /mnt/etc/hostname

chroot /mnt ln -sf /mnt/usr/share/zoneinfo/Canada/Eastern /mnt/etc/localtime

chroot /mnt hwclock --systohc

chroot /mnt locale-gen
### set locales and languages
echo "LANG=en_US.UTF-8" > /mnt/etc/local.conf

chroot /mnt systemctl enable dhcpcd.service
chroot /mnt systemctl disable nftables.service
chroot /mnt systemctl disable iptables.service
chroot /mnt systemctl enable ufw.service
chroot /mnt systemctl enable greetd.service


### setup primary user
chroot /mnt useradd -m -G wheel,audio,video,cdrom,optical,storage,kvm,input,plugdev,users,bluetooth,_pipewire -s /bin/bash $USER
chroot /mnt /bin/bash <<EOF
echo "$USER:$PASS1" | chpasswd
EOF
chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

### copy over system /etc files for configuration later
cp -rf /install/archdesktop/etc/greetd /mnt/etc/

chroot /mnt mkinitcpio -P

#####################################################
##### Zen Kernel Installation         ###############
#####################################################
#
### install zen kernel
chroot /mnt pacman -S linux-zen linux-zen-headers
### check to ensure linux-zen is in the boot partition
chroot /mnt mkinitcpio -P

#####################################################
##### zram swap setup                 ###############
#####################################################
#
### zram setup via udev rule as per arch wiki
touch /mnt/etc/modules-load.d/zram.conf
echo "zram" >> /mnt/etc/modules-load.d/zram.conf

touch /mnt/etc/udev/rules.d/99-zram.rules
cat <<EOF > /mnt/etc/udev/rules.d/99-zram.rules
ACTION=="add", KERNEL=="zram0", ATTR{initstate}=="0", ATTR{comp_algorithm}="zstd", ATTR{disksize}="4G", TAG+="systemd"
EOF

echo "/dev/zram0 none swap defaults,discard,pri=100,x-systemd.makefs 0 0" >> /mnt/etc/fstab

#####################################################
##### Boot options: limine bootloader ###############
#####################################################
#
### limine setup

### first get the UUID of the physical root partition (holds encrypted root cryptroot inside)
TARGET_UUID=$(blkid -s UUID -o value /dev/${default_install_name})

### then create the limine config file which includes the kernel command line
cat <<EOF > /mnt/boot/limine.conf
timeout: 5
verbose: yes

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz
    module_path: boot():/initramfs.img
    cmdline: root=UUID=$TARGET_UUID rw loglevel=7
EOF

### then place the limine EFI image into the correct folder in the /boot partition so the BIOS knows how to find limine
mkdir -p /mnt/boot/EFI/limine/
cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/EFI/limine/

### then use the efibootmgr tool to make an entry in the BIOS for limine
efibootmgr --create --label "Arch Linux" --loader '\EFI\limine\BOOTX64.EFI' --disk /dev/${default_efi_name} --part 1

### a temporary block of code to make sure entries are properly captured
echo $PASS1
echo $USER
echo $CRYPTPASS1
echo $disk
# remember to delete afterwards
lsblk

### wipes passwords so they don't exist in memory
unset PASS1
unset PASS2
unset CRYPTPASS1
unset CRYPTPASS2

} 2>&1 | tee /root/archdesktop/install.log
mkdir -p /mnt/etc/install_log/
cp /root/archdesktop/install.log /mnt/etc/install_.log

### to finish installation run manually
### chroot in
### # arch-chroot /mnt
### [arch-chroot /mnt] # passwd jerec
### [arch-chroot /mnt] # exit
### chroot /mnt mkinitcpio -P
### #umount -R /mnt

### to do
### 1. Kernel Upgrade to the Zen Kernel
### 2. Change swap arrangement to zram
### https://wiki.archlinux.org/title/Zram
