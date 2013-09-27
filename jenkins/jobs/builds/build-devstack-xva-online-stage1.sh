#/bin/bash

set -eux

XENSERVERHOST=$1
XENSERVERPASSWORD=$2
SETUPSCRIPT_URL="$3"
DEVSTAK_TGZ_URL="$4"

TEMPKEYFILE=$(mktemp)

# Prepare slave requirements
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install xcp-xe stunnel sshpass

rm -f install-devstack-xen.sh || true
wget -qO install-devstack-xen.sh "$SETUPSCRIPT_URL"
chmod 755 install-devstack-xen.sh
rm -f $TEMPKEYFILE
ssh-keygen -t rsa -N "" -f $TEMPKEYFILE
ssh-keyscan $XENSERVERHOST >> ~/.ssh/known_hosts
./install-devstack-xen.sh $XENSERVERHOST $XENSERVERPASSWORD $TEMPKEYFILE -d "$DEVSTAK_TGZ_URL"
