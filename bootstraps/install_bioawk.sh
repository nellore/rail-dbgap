#!/usr/bin/env bash
set -ex
export HOME=/home/hadoop

curl -OL https://github.com/lh3/bioawk/archive/master.zip
unzip master.zip
cd bioawk-master
sudo yum install -y flex bison
sudo yum install -y flex
sudo yum install -y byacc
make
sudo ln -s $(pwd)/bioawk /usr/local/bin
