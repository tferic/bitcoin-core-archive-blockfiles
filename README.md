# bitcoin-core-archive-blockfiles
## Overview
This is a helper script in the context of running a bitcoin-core node on a small computer with limited resources.  
It tries to address the following problem:
- bitcoin-core runs on a small computer with limited resources
- main data disk is typically a fast, but small SSD disk
- you want to run a bitcoin **full** node, but the SSD disk is too small
- the computer has access to another, slower but bigger storage medium
- you want to move older bitcoin block files to another storage medium, but the bitcoin-core software should still have access to them, maintaining the status of a bitcoin **full** node.  

The other storage medium could be a magnetic disk, or external USB disk, or network attached volume (NFS, Synology, etc.), for example.  

## How to use
1. Copy this script to the computer that runs bitcoin-core.
2. Edit the local copy of the script in an editor, and adjust the customizable variables to your own needs.
3. Stop the bitcoin-core software
4. Run the script either manually, or scheduled via cron. (you may want to capture the output into a log file)
5. Start the bitcoin-core software

### Variables to adjust
```
BITCOIN_CORE_DIR
```
Specify the directory (full path), which is used by the bitcoin-core software. It would typically be on the small/fast local disk.
```
ARCHIVE_DIR
```
Specify the directory (full path), which should be used to hold the bitcoin block files `blk*.dat`. Make sure the path already exists and is owned by the correct user:group.  
```
PERC_MAX_DISKUSAGE_ARCHIVE
```
Maximum disk usage (in percentage, whithout the % character) of the archive disk volume. The script will refuse to run if the disk's usage is above this specified value.  
```
RETAIN_LATEST_BLK_VERSIONS
```
Keep this number of bitcoin block files (`blk*.dat`) on the main/fast/small disk, preferring the most recent versions. All older versions will be "archived". If this value is set too high (e.g. 20000), the script should not do any changes.
```
BIN_RSYNC
```
Path of your `rsync` program. If it is not alread installed, install it by using `yum install rsync` or `apt install rsync`. Use `which rsync` to get the correct full path, and add it to this variable.  


## Requirements
- Computer with two data volumes, a small/fast one, and a large one
- `rsync` must be installed
