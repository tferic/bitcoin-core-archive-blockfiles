#!/bin/bash

# This script is meant to move large bitcoin blockchain files to 
# a separate archive disk, assuming that the main disk is an SSD
# with limited space.
# The script will create symlinks linking from the main disk to 
# the archive disk, in a way that the bitcoin-core software will still
# be able to access the archived files, maintaining the status of 
# a bitcoin full node.

# For the time being, this script is meant to run only while the  
# bitcoin-core software is stopped.

# This software is opensource, published under the MIT terms of license
# https://opensource.org/licenses/MIT

# Written by Toni Feric, 2022

VERSION="0.03"

# Block of variables that are user modifiable

# Main Working directory of bitcoin-core, where it is storing its data
BITCOIN_CORE_DATA_DIR='/home/bitcoin/.bitcoin'

# Archive directory (mounted on another disk)
ARCHIVE_DIR='/local/bitcoin/.bitcoin/blocks'

# Maximum disk usage of archive disk (Use% in df)
PERC_MAX_DISKUSAGE_ARCHIVE=97

# How many blk files should be retained within the bitcoin-core main directory (prefer newest)
RETAIN_LATEST_BLK_VERSIONS=1000

# Path of rsync program
BIN_RSYNC='/usr/bin/rsync'

# Date/Time format for log output
DATE_TIME_FORMAT='%Y-%m-%d %H:%M:%S'


# internal-only variables. No need for users to modify.
BITCOIN_BLOCKS_DIR="$BITCOIN_CORE_DATA_DIR/blocks"
ARCHIVEABLE_STUB='blk'
ARCHIVEABLE_STUB_PATTERN="${ARCHIVEABLE_STUB}*.dat"
sN="`basename $0`"

function dt () {
	# Return formatted date/time stamp
	date +"$DATE_TIME_FORMAT"'   '
}

function get_diskusage_archive () {
	# Returns disk usage of archive disk as percent number
	# Pass archive directory as argument
	# Return disk usage 
	df $1 | awk '{print $(NF-1)}' | egrep '[0-9][0-9]*%' | head -1 | sed 's/%//g'
}

function check_diskusage_archive () {
	# Checks if the archive disk has enough space
	# Pass archive directory as argument
	# Return Boolean
	if [ `get_diskusage_archive "$1"` -le "$PERC_MAX_DISKUSAGE_ARCHIVE" ] ; then
		return 0
	else
		return 1
	fi
}

function check_bitcoin_running () {
	# Check if bitcoin-core is running
	# Return Boolean
	local bitcoin_procs="`ps -eo cmd | egrep -v "$sN|grep" | egrep 'bitcoin-core|bitcoin-qt' | wc -l`"
	if [ "$bitcoin_procs" -gt 0 ] ; then
		# Found bitcoin processes running (Return True)
		return 0
	else
		# No bitcoin processes running (Return False)
		return 1
	fi
}

function verify_allowed_to_execute () {
	# Verify if this script is allowed to execute

	# Exit if another instance of this script is already running
	if pidof -x $sN -o %PPID > /dev/null
	then
		echo "`dt`ERROR: Another instance of this script is already running. Only one instance is allowed to run. Exiting."
		exit 1
	fi

	# Exit if bitcoin-core is still running. This script must operate while bitcoin-core is stopped.
	if `check_bitcoin_running` ; then
		echo "`dt`ERROR: bitcoin-core is still running."
		echo "`dt`ERROR: To run this script, please stop bitcoin-core first. Exiting."
		exit 1
	fi
	
	# Exit if there is not enough disk space on the archive disk
	if ! `check_diskusage_archive "$ARCHIVE_DIR"` ; then
		echo "`dt`ERROR: Not enough disk space on $ARCHIVE_DIR. (Threshold=${PERC_MAX_DISKUSAGE_ARCHIVE}%) Exiting."
		df -Ph "$ARCHIVE_DIR" | egrep 'Use%|[0-9][0-9]%' | awk -v time="`dt`" '{print time"       "$0}'
		exit 1
	fi
	
	# Exit if the blk file count in the main directory is lower than the threshold
	local realfiles_count=`get_list_matching_realfiles "$BITCOIN_BLOCKS_DIR" "$ARCHIVEABLE_STUB_PATTERN" | wc -l`
	if [ $realfiles_count -le "$RETAIN_LATEST_BLK_VERSIONS" ] ; then
		echo "`dt`INFO: Nothing to do. Number of real blk files ($realfiles_count) not above threshold ($RETAIN_LATEST_BLK_VERSIONS)."
		exit 1
	fi

	# Check if required software components are installed (dependencies)
	if [ ! -x "$BIN_RSYNC" ] ; then
		echo "`dt`ERROR: rsync is not installed or not in specified path $BIN_RSYNC. Please make sure to install and specify its path correctly in the variable BIN_RSYNC. Exiting."
		exit 1
	fi
}

function get_list_matching_realfiles () {
	# Get list of real files of a certain pattern in a directory (ignoring symlinks)
	# Pass arguments to function:
	# - $1: directory path
	# - $2: search pattern
	local dir=$1
	local pat=$2
	find $dir -type f -name "$pat"
}

function get_list_matching_realfiles_archivable () {
	# Get list of archivable real files of a certain pattern in a directory (ignoring symlinks)
	# Pass arguments to function:
	# - $1: directory path
	# - $2: search pattern
	local dir=$1
	local pat=$2
	local file_list=`get_list_matching_realfiles "$dir" "$pat"`
	local file_list_count=`get_list_matching_realfiles "$dir" "$pat" | wc -l`
	local archivable_count=$(expr $file_list_count - $RETAIN_LATEST_BLK_VERSIONS)
	get_list_matching_realfiles "$dir" "$pat" | sort | head -"$archivable_count"
}

function process_archivable_files () {
	# Process the list of real block files, that are entitled for archiving
	# Pass arguments to function:
	# - $1: directory path
	# - $2: search pattern
	# - $3: archive path
	# - $4: retain minimum number of versions in real dir
	local dir=$1
	local pat=$2
	local archdir=$3
	local retain_c=$4
	local count_files_archived=0	
	for file in `get_list_matching_realfiles_archivable "$dir" "$pat"`
	do
		local file_base="`basename $file`"
		local file_dir="`dirname $file`"
		echo "`dt`INFO: Found archivable file: $file"
		if `check_diskusage_archive "$archdir"` ; then
			echo "`dt`INFO:     Copying file $file to $archdir ..."
			copy_to_archive "$file" "$archdir"
		else
			echo "`dt`ERROR:    Not enough disk space on $archdir. (Threshold=${PERC_MAX_DISKUSAGE_ARCHIVE}%). Aboring script execution. Exiting."
			df -Ph "$archdir" | egrep 'Use%|[0-9][0-9]%' | awk -v time="`dt`" '{print time"       "$0}'
			exit 1
		fi
		echo "`dt`INFO:     Creating symlink for file $file"
		replace_file_with_symlink "$file" "$archdir"
		count_files_archived=$(expr $count_files_archived + 1)
	done
}

function copy_to_archive () {
	# Copy file to archive directory in a consistent manner
	# Pass arguments to function:
	# - $1: file to copy
	# - $2: destination directory (archive path)
	local f=$1
	local destdir=$2
	$BIN_RSYNC -a $f $destdir | awk -v time="`dt`" '{print time"copy_to_archive: "$0}'
}

function replace_file_with_symlink () {
	# Delete given file, and replace it with a symlink pointing to that file in another directory
	# Pass arguments to function:
	# - $1: file to replace by symlink (use full path)
	# - $2: destination directory (archive path)
	local f=$1
	local destdir=$2
	local srcdir=`dirname "$f"`
	local srcfile=`basename "$f"`
	local destfile="$destdir/$srcfile"
	if [ -f $destfile ] ; then
		( cd $srcdir && rm -f $f && ln -s $destfile )
		if [ -h $f ] ; then
			return 0
		else
			echo "`dt`ERROR: replace_file_with_symlink(): Symbolic link was not created. Exiting."
			exit 1
		fi
	else
		echo "`dt`ERROR: Destination file $destfile does not exist. Exiting."
		exit 1
	fi
}

# MAIN section
verify_allowed_to_execute
process_archivable_files "$BITCOIN_BLOCKS_DIR" "$ARCHIVEABLE_STUB_PATTERN" "$ARCHIVE_DIR" "$RETAIN_LATEST_BLK_VERSIONS"


