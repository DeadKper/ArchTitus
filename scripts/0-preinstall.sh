#!/usr/bin/env bash
#-------------------------------------------------------------------------
#   █████╗ ██████╗  ██████╗██╗  ██╗████████╗██╗████████╗██╗   ██╗███████╗
#  ██╔══██╗██╔══██╗██╔════╝██║  ██║╚══██╔══╝██║╚══██╔══╝██║   ██║██╔════╝
#  ███████║██████╔╝██║     ███████║   ██║   ██║   ██║   ██║   ██║███████╗
#  ██╔══██║██╔══██╗██║     ██╔══██║   ██║   ██║   ██║   ██║   ██║╚════██║
#  ██║  ██║██║  ██║╚██████╗██║  ██║   ██║   ██║   ██║   ╚██████╔╝███████║
#  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝   ╚═╝    ╚═════╝ ╚══════╝
#-------------------------------------------------------------------------
#github-action genshdoc
#
# @file Preinstall
# @brief Contains the steps necessary to configure and pacstrap the install to selected drive. 
echo -ne "
-------------------------------------------------------------------------
   █████╗ ██████╗  ██████╗██╗  ██╗████████╗██╗████████╗██╗   ██╗███████╗
  ██╔══██╗██╔══██╗██╔════╝██║  ██║╚══██╔══╝██║╚══██╔══╝██║   ██║██╔════╝
  ███████║██████╔╝██║     ███████║   ██║   ██║   ██║   ██║   ██║███████╗
  ██╔══██║██╔══██╗██║     ██╔══██║   ██║   ██║   ██║   ██║   ██║╚════██║
  ██║  ██║██║  ██║╚██████╗██║  ██║   ██║   ██║   ██║   ╚██████╔╝███████║
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝   ╚═╝    ╚═════╝ ╚══════╝
-------------------------------------------------------------------------
                    Automated Arch Linux Installer
-------------------------------------------------------------------------

Setting up mirrors for optimal download
"
source $CONFIGS_DIR/setup.conf
iso=$(curl -4 ifconfig.co/country-iso)
timedatectl set-ntp true
pacman -S --noconfirm archlinux-keyring #update keyrings to latest to prevent packages failing to install
pacman -S --noconfirm --needed pacman-contrib terminus-font
setfont ter-v22b
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
pacman -S --noconfirm --needed reflector rsync grub
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
echo -ne "
-------------------------------------------------------------------------
                    Setting up $iso mirrors for faster downloads
-------------------------------------------------------------------------
"
reflector -a 48 -c $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
mkdir /mnt &>/dev/null # Hiding error message if any
echo -ne "
-------------------------------------------------------------------------
                    Installing Prerequisites
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc lvm2
echo -ne "
-------------------------------------------------------------------------
                    Formating Disk
-------------------------------------------------------------------------
"
umount -A --recursive /mnt # make sure everything is unmounted before we start
# disk prep
sgdisk -Z ${DISK} # zap all on disk
sgdisk -a 2048 -o ${DISK} # new gpt disk 2048 alignment

# create partitions
sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOSBOOT' ${DISK} # partition 1 (BIOS Boot Partition)
sgdisk -n 2::+300M --typecode=2:ef00 --change-name=2:'EFIBOOT' ${DISK} # partition 2 (UEFI Boot Partition)
if  [[ "${FS}" == "lvm" ]]; then
    sgdisk -n 3::-0 --typecode=3:8e00 --change-name=3:'LVM' ${DISK} # partition 3 (LVM), default start, remaining
else
    if [[ "$EXT_HOME" == "yes" ]]; then
        sgdisk -n 3::+${ROOT_SIZE}G --typecode=3:8300 --change-name=3:'ROOT' ${DISK} # partition 3 (Root), default start, remaining
        sgdisk -n 3::-0 --typecode=3:8302 --change-name=3:'HOME' ${DISK} # partition 4 (Home), default start, remaining
    else
        sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' ${DISK} # partition 3 (Root), default start, remaining
    fi
fi
if [[ ! -d "/sys/firmware/efi" ]]; then # Checking for bios system
    sgdisk -A 1:set:2 ${DISK}
fi
partprobe ${DISK} # reread partition table to ensure it is correct

# make filesystems
echo -ne "
-------------------------------------------------------------------------
                    Creating Filesystems
-------------------------------------------------------------------------
"
# Set default variables for lvm installation
lvmroot="/dev/arch/root"
lvmhome="/dev/arch/home"
# @description Create default lvm group and it's partitions
createlvmgroup () {
    pvcreate ${partition3}
    vgcreate arch ${partition3}
    if  [[ "${EXT_HOME}" == "yes" ]]; then
        lvcreate --size 64G --name root arch
        lvcreate --extents 100%FREE --name home arch
    else
        lvcreate --extents 100%FREE --name root arch
    fi
    modprobe dm_mod
    vgscan # Just to print the group, not really necessary
    vgchange -ay
}
# @description Creates the btrfs subvolumes. 
createsubvolumes () {
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@tmp
    btrfs subvolume create /mnt/@.snapshots

    if  [[ "${EXT_HOME}" == "no" ]]; then
        btrfs subvolume create /mnt/@home
    fi
}
# @description Mount all btrfs subvolumes after root has been mounted.
mountallsubvol () {
    mount -o ${MOUNT_OPTIONS},subvol=@tmp ${partition3} /mnt/tmp
    mount -o ${MOUNT_OPTIONS},subvol=@var ${partition3} /mnt/var
    mount -o ${MOUNT_OPTIONS},subvol=@.snapshots ${partition3} /mnt/.snapshots

    if  [[ "${EXT_HOME}" == "no" ]]; then
        mount -o ${MOUNT_OPTIONS},subvol=@home ${partition3} /mnt/home
    fi
}

# @description BTRFS subvolulme creation and mounting. 
subvolumesetup () {
# create nonroot subvolumes
    createsubvolumes     
# unmount root to remount with subvolume 
    umount /mnt
# mount @ subvolume
    mount -o ${MOUNT_OPTIONS},subvol=@ ${partition3} /mnt
# make directories home, .snapshots, var, tmp
    mkdir -p /mnt/{home,var,tmp,.snapshots}
# mount subvolumes
    mountallsubvol
}

homesetup () {
    if [[ "${EXT_HOME}" ]]; then
        mkfs.ext4 -L HOME ${partition4}
        mount ${partition4} /mnt/home
    fi
}

if [[ "${DISK}" =~ "nvme" ]]; then
    nvme="p"
else
    nvme=""
fi

partition2=${DISK}${nvme}2

if  [[ "${FS}" == "lvm" ]]; then
    partition3=${lvmroot}
    partition4=${lvmhome}
else
    partition3=${DISK}${nvme}3
    partition4=${DISK}${nvme}4
fi

mkfs.vfat -F32 -n "EFIBOOT" ${partition2}
if  [[ "${FS}" == "lvm" ]]; then
    createlvmgroup
    mkfs.btrfs -L ROOT ${partition3} -f
    mount -t btrfs ${partition3} /mnt
    subvolumesetup
    homesetup
elif [[ "${FS}" == "btrfs" ]]; then
    mkfs.btrfs -L ROOT ${partition3} -f
    mount -t btrfs ${partition3} /mnt
    subvolumesetup
    homesetup
elif [[ "${FS}" == "ext4" ]]; then
    mkfs.ext4 -L ROOT ${partition3}
    mount -t ext4 ${partition3} /mnt
    homesetup
elif [[ "${FS}" == "luks" ]]; then
# enter luks password to cryptsetup and format root partition
    echo -n "${LUKS_PASSWORD}" | cryptsetup -y -v luksFormat ${partition3} -
# open luks container and ROOT will be place holder 
    echo -n "${LUKS_PASSWORD}" | cryptsetup open ${partition3} ROOT -
# now format that container
    mkfs.btrfs -L ROOT ${partition3}
# create subvolumes for btrfs
    mount -t btrfs ${partition3} /mnt
    subvolumesetup
# store uuid of encrypted partition for grub
    echo ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value ${partition3}) >> $CONFIGS_DIR/setup.conf
fi

# mount target
mkdir -p /mnt/boot/efi
mount -t vfat -L EFIBOOT /mnt/boot/

if ! grep -qs '/mnt' /proc/mounts; then
    echo "Drive is not mounted can not continue"
    echo "Rebooting in 3 Seconds ..." && sleep 1
    echo "Rebooting in 2 Seconds ..." && sleep 1
    echo "Rebooting in 1 Second ..." && sleep 1
    reboot now
fi
echo -ne "
-------------------------------------------------------------------------
                    Arch Install on Main Drive
-------------------------------------------------------------------------
"
pacstrap /mnt base base-devel linux linux-firmware vim nano lvm2 sudo archlinux-keyring wget libnewt --noconfirm --needed
echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
cp -R ${SCRIPT_DIR} /mnt/root/ArchTitus
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

genfstab -L /mnt >> /mnt/etc/fstab
echo " 
  Generated /etc/fstab:
"
cat /mnt/etc/fstab
echo -ne "
-------------------------------------------------------------------------
                    GRUB BIOS Bootloader Install & Check
-------------------------------------------------------------------------
"
if [[ ! -d "/sys/firmware/efi" ]]; then
    grub-install --boot-directory=/mnt/boot ${DISK}
else
    pacstrap /mnt efibootmgr --noconfirm --needed
fi
echo -ne "
-------------------------------------------------------------------------
                    Checking for low memory systems <8G
-------------------------------------------------------------------------
"
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[  $TOTAL_MEM -lt 8000000 ]]; then
    # Put swap into the actual system, not into RAM disk, otherwise there is no point in it, it'll cache RAM into RAM. So, /mnt/ everything.
    mkdir -p /mnt/opt/swap # make a dir that we can apply NOCOW to to make it btrfs-friendly.
    chattr +C /mnt/opt/swap # apply NOCOW, btrfs needs that.
    dd if=/dev/zero of=/mnt/opt/swap/swapfile bs=1M count=2048 status=progress
    chmod 600 /mnt/opt/swap/swapfile # set permissions.
    chown root /mnt/opt/swap/swapfile
    mkswap /mnt/opt/swap/swapfile
    swapon /mnt/opt/swap/swapfile
    # The line below is written to /mnt/ but doesn't contain /mnt/, since it's just / for the system itself.
    echo "/opt/swap/swapfile	none	swap	sw	0	0" >> /mnt/etc/fstab # Add swap to fstab, so it KEEPS working after installation.
fi
echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 1-setup.sh
-------------------------------------------------------------------------
"
