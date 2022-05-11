# Preinstall

Contains the steps necessary to configure and pacstrap the install to selected drive. 

# Overview

Create default lvm group and it's partitions


# Functions
* [createsubvolumes()](#createsubvolumes)
* [mountallsubvol()](#mountallsubvol)
* [subvolumesetup()](#subvolumesetup)


## createsubvolumes()

Creates the btrfs subvolumes. 

## mountallsubvol()

Mount all btrfs subvolumes after root has been mounted.

## subvolumesetup()

BTRFS subvolulme creation and mounting. 


