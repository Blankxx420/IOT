#!/bin/bash

echo 'rc_cgroup_mode="unified"' >> /etc/rc.conf
sudo sed -i 's/quiet rootfstype=ext4/quiet rootfstype=ext4 cgroup_no_v1=all/' /boot/extlinux.conf