#!/usr/bin/env bash
# This code is based on http://bddubois-emr.s3.amazonaws.com/emr-volume-encryption.sh
set -ex

EPHEMERAL_MNT_DIRS=`awk '/mnt/{print $2}' < /proc/mounts`
ENCRYPTED_SIZE=8g
export PASSWORD=$(dd count=3 bs=16 if=/dev/urandom of=/dev/stdout 2>/dev/null | base64) PASSWORD_FILE="/tmp/pwd"
i=0
STATUS=0
TMPSIZE=40

echo ${PASSWORD} > $PASSWORD_FILE
if [ ! $? -eq 0 ]; then
  echo "ERROR: Failed to create password file"
  STATUS=1
fi

sudo modprobe loop

# Install cryptsetup
#THESE steps fail but its ok the clone in amazon ami already has this installed # #sudo yum -y update #sudo yum -y install cryptsetup

mychildren=""

if [ $STATUS -eq 0 ]; then
  for DIR in $EPHEMERAL_MNT_DIRS; do
    #
    # Set up some variables
    #
    ENCRYPTED_LOOPBACK_DIR=$DIR/encrypted_loopbacks
    ENCRYPTED_SPACE=$DIR/space
    DFS_DATA_DIR=$DIR/var/lib/hadoop/dfs
    TMP_DATA_DIR=$DIR/var/lib/hadoop/tmp
    S3_BUFFER_DIR=$DIR/var/lib/hadoop/s3
    ENCRYPTED_LOOPBACK_DEVICE=/dev/loop$i
    ENCRYPTED_NAME=crypt$i

    mkdir -p ${ENCRYPTED_SPACE}
    
    if [ $STATUS -eq 0 ]; then
      # Get the total number of blocks for this filesystem $DIR
      nblocks=`stat -f -c '%a' $DIR`
      # Get the block size (in bytes for this filesystem $DIR)
      bsize=`stat -f -c '%s' $DIR`
      # Calculate the mntsize in MB (divisible by 1000)
      mntsize=`expr $nblocks \* $bsize \/ 1000 \/ 1000 \/ 1000`
      # Make $TMPSIZE 1/10 of mntsize
      TMPSIZE=`expr $mntsize \/ 10`
      if [ ! $? -eq 0 ]; then
        echo "ERROR: Failed to get mount size"
        STATUS=1
      fi
      ENCRYPTED_SIZE=`expr $mntsize - $TMPSIZE`g
      if [ ! $? -eq 0 ]; then
        echo "ERROR: Failed to calculate encrypted size"
        STATUS=1
      fi
    fi

    #
    # Create directories
    #
    if [ $STATUS -eq 0 ]; then
      mkdir $ENCRYPTED_LOOPBACK_DIR
      if [ ! $? -eq 0 ]; then
        echo "ERROR: Failed to get create ENCRYPTED_LOOPBACK_DIR"
        STATUS=1
      else 
        echo SUCCESS: Created directory $ENCRYPTED_LOOPBACK_DIR
      fi
    fi
    #
    # Create loopback device
    #
    if [ $STATUS -eq 0 ]; then
      sudo fallocate -l $ENCRYPTED_SIZE $ENCRYPTED_LOOPBACK_DIR/encrypted_loopback.img
      if [ ! $? -eq 0 ]; then
        echo "ERROR: Failed to allocate $ENCRYPTED_SIZE $ENCRYPTED_LOOPBACK_DIR/encrypted_loopback.img"
        STATUS=1
      else
        echo SUCCESS: Allocated $ENCRYPTED_SIZE $ENCRYPTED_LOOPBACK_DIR/encrypted_loopback.img
      fi
    fi 
    if [ $STATUS -eq 0 ]; then
      sudo chown hadoop:hadoop $ENCRYPTED_LOOPBACK_DIR/encrypted_loopback.img
      if [ ! $? -eq 0 ]; then
        echo "ERROR: Failed to chown $ENCRYPTED_LOOPBACK_DIR/encrypted_loopback.img"
        STATUS=1
      else
        echo SUCCESS: chowned $ENCRYPTED_LOOPBACK_DIR/encrypted_loopback.img
      fi
    fi
    if [ $STATUS -eq 0 ]; then
      sudo losetup /dev/loop$i $ENCRYPTED_LOOPBACK_DIR/encrypted_loopback.img
      if [ ! $? -eq 0 ]; then
        echo "ERROR: Failed to losetup $ENCRYPTED_LOOPBACK_DIR/encrypted_loopback.img"
        STATUS=1
      else
        echo SUCCESS: losetup $ENCRYPTED_LOOPBACK_DIR/encrypted_loopback.img
      fi
    fi
    #
    # Set up LUKS
    #
    if [ $STATUS -eq 0 ]; then
      sudo cryptsetup luksFormat -q --key-file $PASSWORD_FILE $ENCRYPTED_LOOPBACK_DEVICE
      if [ ! $? -eq 0 ]; then
        echo "ERROR: Failed to  cryptsetup luksFormat -q --key-file $PASSWORD_FILE $ENCRYPTED_LOOPBACK_DEVICE"
        STATUS=1
      else
        echo SUCCESS: cryptsetup luksFormat 
      fi
    fi
    if [ $STATUS -eq 0 ]; then
      sudo cryptsetup luksOpen -q --key-file $PASSWORD_FILE $ENCRYPTED_LOOPBACK_DEVICE $ENCRYPTED_NAME
      if [ ! $? -eq 0 ]; then
        echo "ERROR: Failed to  cryptsetup luksOpen -q --key-file $PASSWORD_FILE $ENCRYPTED_LOOPBACK_DEVICE"
        STATUS=1
      else
        echo SUCCESS: cryptsetup luksopen
      fi
    fi

    #
    # Create file system
    #
    if [ $STATUS -eq 0 ]; then
    mycmd="sudo mkfs.ext4 -m 0 -E lazy_itable_init=1 /dev/mapper/$ENCRYPTED_NAME && sudo mount /dev/mapper/$ENCRYPTED_NAME $ENCRYPTED_SPACE && sudo mkdir -p $ENCRYPTED_SPACE/dfs && sudo mkdir -p $ENCRYPTED_SPACE/s3 && sudo mkdir -p $ENCRYPTED_SPACE/tmp/nm-local-dir && sudo rm -rf $S3_BUFFER_DIR && sudo ln -s $ENCRYPTED_SPACE/s3 $S3_BUFFER_DIR && sudo chown hadoop:hadoop $ENCRYPTED_SPACE/s3 && sudo chown hadoop:hadoop $S3_BUFFER_DIR && sudo rm -rf $DFS_DATA_DIR && sudo ln -s $ENCRYPTED_SPACE/dfs $DFS_DATA_DIR && sudo chown hadoop:hadoop $ENCRYPTED_SPACE/dfs && sudo chown hadoop:hadoop $DFS_DATA_DIR && sudo rm -rf $DFS_DATA_DIR/lost\+found && sudo rm -rf $TMP_DATA_DIR && sudo ln -s $ENCRYPTED_SPACE/tmp $TMP_DATA_DIR && sudo chown hadoop:hadoop $ENCRYPTED_SPACE/tmp && sudo chown hadoop:hadoop $TMP_DATA_DIR && sudo chown hadoop:hadoop $TMP_DATA_DIR/nm-local-dir && sudo echo iamdone-$ENCRYPTED_NAME && sudo chown -R hadoop:hadoop $ENCRYPTED_SPACE && sudo chmod -R 0755 $ENCRYPTED_SPACE && date "
    echo $mycmd
    eval $mycmd &
      if [ ! $? -eq 0 ]; then
        echo "ERROR: Failed to run the my cmd that follows $mycmd"
        STATUS=1
      else
        echo SUCCESS: MYCMD 
      fi
    fi

    mychildren="$mychildren $!"

    let i=i+1
done
fi

for mypid in $mychildren
do
    wait $mypid
done

sudo rm -f $PASSWORD_FILE

date
echo "everything done"
echo $STATUS STATUS
exit $STATUS
