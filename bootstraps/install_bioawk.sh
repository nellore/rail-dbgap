#!/usr/bin/env bash
git clone https://github.com/lh3/bioawk
cd bioawk
make
sudo ln -s ./bioawk /usr/local/bin
