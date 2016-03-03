#!/usr/bin/env bash
set -ex
export HOME=/home/hadoop

# Download and install SRA Tools
curl -O http://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/2.5.7/sratoolkit.2.5.7-centos_linux64.tar.gz
tar xvzf sratoolkit.2.5.7-centos_linux64.tar.gz
sudo ln -s $(pwd)/sratoolkit.2.5.7-centos_linux64/bin/fastq-dump /usr/local/bin

# Set up two workspaces: an insecure one and a secure one
mkdir -p /mnt/space/sra_workspace/insecure
mkdir -p ~/.ncbi
# The following code ensures that the fastq-dump's cache is disabled to save space on local disks
cat >~/.ncbi/user-settings.mkfg <<EOF
/repository/user/cache-disabled = "true"
/repository/user/main/public/root = "/mnt/space/sra_workspace/insecure"
EOF
mkdir -p /mnt/space/sra_workspace/secure
$(pwd)/sratoolkit.2.5.7-centos_linux64/bin/vdb-config --import /mnt/space/DBGAP.ngc /mnt/space/sra_workspace/secure
cat >.fix_config.py <<EOF
\"""
.fix_config.py

Makes sure cache is disabled in vdb-config file
\"""

import sys

for line in sys.stdin:
    tokens = [token.strip() for token in line.split('=')]
    if tokens and tokens[0].endswith('cache-disabled'):
        print tokens[0] + ' = "true"'
    elif tokens and tokens[0].endswith('cache-enabled'):
        print tokens[0] + ' = "false"'
    else:
        print line,
EOF
cat ~/.ncbi/user-settings.mkfg | python .fix_config.py >new-user-settings.mkfg
cp new-user-settings.mkfg ~/.ncbi/user-settings.mkfg
sudo ln -s /home/hadoop/.ncbi /home/.ncbi
