#!/bin/bash
################################################
### Performance Arch Linux Installation	     ###
### Stage Zero Disk prep and preboot install ###
### by: Liz Boudreau		   	     ###
### License: GPL-2.0		   	     ###
################################################

### This script will do a fully automated installation of void linux from the command line
### it is meant to be run from a live installation image of void linux
### this script was designed and tested with the void linux image released in 2025 and assumes Linux 6.12
### it seems that there's issues with setting a user password from chroot wrapper automated commands. so it will have to be done after installing with a quick chrooting in and setting it before rebooting
### This script is a work in progress, use at your own risk. It is not supported. Issues will be ignored.
### Sources used for creating this script: man-pages, void linux manual, and https://github.com/dylanbegin/void-install.git

### The target system will have the following installation features and qualities
### a single volume inside a LUKS2 partition, ZRAM and swapfile will be used for swap
### An EFI partition containining the kernel and initramfs images
### limine bootloader

### EFI Stub, secure boot and TPM2 unlock would be nice, but to simplify the installation process. that will be left to post-installation to simplify this installation script

### to run this script, run the following manually:
### # mkdir /install
### # cd /install
### # xbps-install -Sfyu xbps
### # xbps-install -Sfy parted git vim efibootmgr #vim is for checking scripts
### # git clone https://github.com/jerod256/voidinstall.git
### # cd voidinstall
### # chmod +x prebootinstall.sh
### # ./prebootinstall.sh

mkdir -p /root/void-install/
touch /root/void-install/install.log
{
### set global variables
arch=x86_64
mirror="https://repo-default.voidlinux.org/current"
mirror_nonfree="https://repo-default.voidlinux.org/current/nonfree"

### variables to be set (with defaults)
default_efi_name="vda1"
default_install_name="vda2"
LANG="en_US.UTF-8"
default_host="laptop"
default_USER="lizluv"
default_PASSWD="1234"
default_CRYPTPASS="56789"

### packages to be loaded into the live session for installation (seems to be required manually before this script is run)
#pkg_preinst="parted git"
#package list for basic system setup
#pkg_base="base-system cryptsetup efibootmgr nftables sbctl vim git lvm2 grub-x86_64-efi sbsigntool efitools tpm2-tools"
pkg_base="base-system cryptsetup nftables vim git limine efibootmgr seatd bluez pipewire wireplumber greetd tuigreet ufw base-devel tlp tlp-pd wget curl btop udisks2 connman cronie dbus socklog-void ntp"
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

### enter swap size
echo -n "Enter the size of the swap file in gigabytes"
read temp_swapsize
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

### 5. cryptsetup passphrase, will be used to decrypt root drive
while true; do
	echo -n "Enter encryption passphrase"
	read -s CRYPTPASS1

	echo -n "Verify passphrase"
	read -s CRYPTPASS2

	if [ "$PASS1" = "$PASS2" ]; then
		echo "Passphrase successfully set."
		break
	else
		echo "Match failed. Try again."
	fi
done


### Enters into disk preparation:
#echo "Formatting the disk $disk..."
#dd if=/dev/zero of=/dev/${disk} bs=1M count=100

### Create a new gpt partition table
#echo "Creating GPT partition table on $disk..."
#parted -s /dev/${disk} mklabel gpt

### Create efi partition
#echo "Creating $disk EFI partition..."
#parted -s -a optimal /dev/${disk} mkpart primary fat32 2048s $efi_size

#start_efipos=$(numfmt --from=iec $efi_size)
#size2add=$(numfmt --from=iec $default_install_size)

#endpos_byte=$((start_efipos + size2add))
#endpos=$(numfmt --to=iec $endpos_byte)

### Create root partition
#echo "Creating linux partition on rest of free space..."
#parted -s -a optimal /dev/${disk} mkpart primary ext4 $start_efipos $endpos_byte

### Set esp flag on efi partition
#echo "Setting esp flag on EFI partition..."
#parted -s /dev/${disk} set 1 esp on

### Encrypt root partition
echo "Encrypt root partition with LUKS2 aes-512..."
echo "$CRYPTPASS1" | cryptsetup --label crypt --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 1000 --use-random luksFormat /dev/${default_install_name}

### Open encrypted partition
echo "Opening crypt partition..."
echo "$CRYPTPASS1" | cryptsetup open --allow-discards --type luks /dev/${default_install_name} cryptroot


### LVM Setup - a legacy implementation discarded as overcomplicating and not needed for my purposes
### Make root partition into an LV group
#echo "creating logical volume group on root partition..."
#vgcreate cryptgroup /dev/mapper/cryptroot 
#echo "creating root logical volume..."
#lvcreate --name root -L 10G cryptgroup
#echo "creating swap logical volume..."
#lvcreate --name swap -L 4G cryptgroup
#echo "creating home logical volume..."
#lvcreate --name home -l 80%FREE cryptgroup

#echo "Creating EFI filesystem FAT32..."
#mkfs.fat -F 32 -n EFI /dev/${disk}1
#mkfs.ext4 -L ROOT /dev/mapper/cryptroot

#echo "creating root filesystem ext4..."
#mkfs.ext4 -L root /dev/cryptgroup/root
#echo "creating swap filesystem..."
#mkswap /dev/cryptgroup/swap
#echo "mounting swap volume..."
#swapon /dev/cryptgroup/swap
#echo "creating home filesystem ext4..."
#mkfs.ext4 -L home /dev/cryptgroup/home

### mount root and home
#echo "mounting root to target filesystem..."
#mount /dev/cryptgroup/root /mnt

#echo "mounting home to target filesystem..."
#mkdir -p /mnt/home
#mount /dev/cryptgroup/home /mnt/home

# since the intention is to use an EFI stub for boot, only create a /mnt/boot folder and mount to EFI partition
#echo "mounting EFI stub directory..."
#mkdir -p /mnt/boot/efi
#mount /dev/${disk}1 /mnt/boot/efi
### END OF LVM SETUP

# mount the LUKS volume
echo "creating root filesystem..."
mkfs.ext4 /dev/mapper/cryptroot
echo "mounting root filesystem..."
mount /dev/mapper/cryptroot /mnt

# mount the FAT32 /boot outside the LUKS partition
echo "Creating EFI filesystem FAT32..."
mkfs.fat -F 32 -n EFI /dev/${default_efi_name}
echo "mounting EFI stub directory..."
mkdir -p /mnt/boot/efi
mount /dev/${default_efi_name} /mnt/boot

##### SWAP Setup
### Swap file setup
swapbitsize=(numfmt --from=iec {$swap_size}k)
### create empty swap file
dd if=/dev/zero of=/mnt/swapfile bs=1M count=$swapbitsize
mkswap /mnt/swapfile
chmod 0600 /mnt/swapfile
swapon /mnt/swapfile
### zswap setup - setting up zswap in post boot setup since the intention is to install a new kernel, the zswap setup will be done then only for the new kernel


### make the folder for the xbps keys and copy them over
echo "copying over xbps keys"
mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/

### installation of base system and packages
echo "installing base system..."
xbps-install -Sy -R $mirror -R $mirror_nonfree -r /mnt $pkg_base


### generate the filesystem tble
echo "generting filesystem table..."
xgenfstab /mnt > /mnt/etc/fstab
### next I need to replace the boot sector label from the /dev/** to its UUID
### first find the UUID
BOOT_UUID=$(blkid -s UUID -o value /dev/${default_efi_name})
### next inject the UUID into the UUID
sed -i "s|/dev/$default_efi_name|UUID=$BOOT_UUID/g" /mnt/etc/fstab


### set permissions for the root
chroot /mnt chown root:root /
chroot /mnt chmod 755 /
chroot /mnt chpasswd <<< "root:$PASS1"
echo $default_host > /mnt/etc/hostname

### set locales and languages
echo "LANG=en_US.UTF-8" > /mnt/etc/local.conf
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/default/libc-locales
chroot /mnt xbps-reconfigure -f glibc-locales

### setup primary user
chroot /mnt useradd -m -G wheel,audio,video,cdrom,optical,storage,kvm,input,plugdev,users,xbuilder,bluetooth,_pipewire,_seatd -s /bin/bash $USER
chroot /mnt /bin/bash <<EOF
echo "$USER:$PASS1" | chpasswd
EOF
chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

### copy over system /etc files for configuration later
cp -rf /install/voidinstall/etc/* /mnt/etc/

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

/Void Linux (Encrypted)
    protocol: linux
    path: boot():/vmlinuz-6.12.77_1
    module_path: boot():/initramfs-6.12.77_1.img
    cmdline: rd.luks.uuid=$TARGET_UUID rd.luks.name=$TARGET_UUID=cryptroot root=/dev/mapper/cryptroot rd.luks.allow-discards rw loglevel=7 zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold zswap.max_pool_percent=25 zswap.shrinker_enabled=1
EOF

### then place the limine EFI image into the correct folder in the /boot partition so the BIOS knows how to find limine
mkdir -p /mnt/boot/EFI/limine/
cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/EFI/limine/

### then use the efibootmgr tool to make an entry in the BIOS for limine
efibootmgr --create --label "Void Linux" --loader '\EFI\limine\BOOTX64.EFI' --disk /dev/${default_efi_name} --part 1

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

} 2>&1 | tee /root/void-install/install.log
mkdir -p /mnt/etc/install_log/
cp /root/void-install/install.log /mnt/etc/install_.log

### to finish installation run manually
### chroot in
### # xchroot /mnt
### [xchroot /mnt] # passwd jerec
### [xchroot /mnt] # exit
### chroot /mnt xbps-reconfigure -fa
### #umount -R /mnt

### to do
### 1. fix efibootmgr command
### 2. ensure /etc/ copy works
