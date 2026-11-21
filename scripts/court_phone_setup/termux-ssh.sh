#!/bin/sh
# Runs on the phone as the Termux user: sh /data/local/tmp/termux-ssh.sh
# shellcheck shell=sh
export PREFIX=/data/data/com.termux/files/usr HOME=/data/data/com.termux/files/home
export PATH=$PREFIX/bin LD_LIBRARY_PATH=$PREFIX/lib TMPDIR=$PREFIX/tmp LANG=en_US.UTF-8
mkdir -p "$HOME/.ssh" "$TMPDIR"
yes | apt-get update -o Dpkg::Options::=--force-confnew 2>&1 | tail -3
DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confnew openssh 2>&1 | tail -3
cat /data/local/tmp/keys >> "$HOME/.ssh/authorized_keys"
sort -u -o "$HOME/.ssh/authorized_keys" "$HOME/.ssh/authorized_keys"
chmod 700 "$HOME/.ssh"; chmod 600 "$HOME/.ssh/authorized_keys"
pkill sshd; sshd && echo SSHD_UP
