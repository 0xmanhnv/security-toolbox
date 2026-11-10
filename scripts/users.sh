#!/bin/sh
# Image build step (root): create the two non-root users the image runs as, with fixed
# UIDs/GIDs so a downstream image and the host can predict them.
#   runner    10001  a primary/service process (never root at run time)
#   sandbox   10002  a restricted user for running the bundled tools
# runner is also in the sandbox group so it can read and clean up files the tools write
# in shared directories (set up such dirs setgid, group sandbox, in a downstream image).
set -eux
groupadd -g 10001 runner
useradd -u 10001 -g 10001 -m -d /home/runner -s /usr/sbin/nologin runner
groupadd -g 10002 sandbox
useradd -u 10002 -g 10002 -m -d /home/sandbox -s /bin/bash sandbox
usermod -aG sandbox runner
chmod 0700 /home/runner /home/sandbox
# No setuid/setgid binaries in the image (no-new-privs keeps them inert as well).
find / -xdev -type f -perm /6000 -exec chmod ug-s {} + || true
mkdir -p /app/data /run/toolbox
