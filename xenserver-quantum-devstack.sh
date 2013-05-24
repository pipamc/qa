#!/bin/bash

set -eux

function print_usage_and_die
{
cat >&2 << EOF
usage: $0 XENSERVER_IP XENSERVER_PASS

A simple script to setup a XenServer installation with Quantum.

positional arguments:
 XENSERVER_IP     The IP address of the XenServer
 XENSERVER_PASS   The root password for the XenServer
 GITHUB_USER      The github user to use for temporary branches

An example run:

./$0 10.219.10.25 mypassword citrix-openstack
EOF
exit 1
}

XENSERVER_IP="${1-$(print_usage_and_die)}"
XENSERVER_PASS="${2-$(print_usage_and_die)}"
GITHUB_USER="${3-$(print_usage_and_die)}"

function create_branch() {
    local source_repo
    local target_repo
    local branchname

    source_repo="$1"
    target_repo="$2"
    branchname="$3"

    local tmpdir

    branchname=$(date +%s)

    tmpdir=$(mktemp -d)
    (
        cd $tmpdir
        git clone "$source_repo" repo
        cd repo
        git checkout -b "$branchname"
        git remote add target_repo "$target_repo"

        ( echo "set -exu"; cat ) | bash -s --
        git push target_repo "$branchname"
    )
    rm -rf "$tmpdir"
}

# Create custom devstack branch
devstack_branch=$(date +%s)
create_branch \
    "https://github.com/openstack-dev/devstack.git" \
    "git@github.com:$GITHUB_USER/devstack.git" \
    "$devstack_branch" << EOF
git fetch https://review.openstack.org/openstack-dev/devstack refs/changes/92/28692/6 && git cherry-pick FETCH_HEAD
EOF

# Create custom quantum branch
quantum_branch=$(date +%s)
create_branch \
    "https://github.com/openstack/quantum.git" \
    "git@github.com:$GITHUB_USER/quantum.git" \
    "$quantum_branch" << EOF
git fetch https://review.openstack.org/openstack/quantum refs/changes/22/15022/13 && git cherry-pick FETCH_HEAD
EOF

ssh -q \
    -o Batchmode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "root@$XENSERVER_IP" bash -s -- << EOF
set -exu
rm -rf "devstack-$devstack_branch"
wget -qO - https://github.com/$GITHUB_USER/devstack/archive/$devstack_branch.tar.gz |
    tar -xzf -
cd "devstack-$devstack_branch"

cat << LOCALRC_CONTENT_ENDS_HERE > localrc
# Passwords
MYSQL_PASSWORD=citrix
SERVICE_TOKEN=citrix
ADMIN_PASSWORD=citrix
SERVICE_PASSWORD=citrix
RABBIT_PASSWORD=citrix
GUEST_PASSWORD=citrix
XENAPI_PASSWORD="$XENSERVER_PASS"
SWIFT_HASH="66a3d6b56c1f479c8b4e70ab5c2000f5"

# Tempest
DEFAULT_INSTANCE_TYPE="m1.small"

# Compute settings
EXTRA_OPTS=("xenapi_disable_agent=True")
API_RATE_LIMIT=False
VIRT_DRIVER=xenserver

# Cinder settings
VOLUME_BACKING_FILE_SIZE=10000M

# Networking
MGT_IP="dhcp"

PUB_IP=172.24.4.10
PUB_NETMASK=255.255.255.0

# Expose OpenStack services on management interface
HOST_IP_IFACE=eth2

# OpenStack VM settings
OSDOMU_MEM_MB=4096
UBUNTU_INST_RELEASE=precise
UBUNTU_INST_IFACE="eth2"
OSDOMU_VDI_GB=40

# Exercise settings
ACTIVE_TIMEOUT=500
TERMINATE_TIMEOUT=500

# DevStack settings
LOGFILE=/tmp/devstack/log/stack.log
SCREEN_LOGDIR=/tmp/devstack/log/
VERBOSE=False

# XenAPI specific
XENAPI_CONNECTION_URL="http://$XENSERVER_IP"
VNCSERVER_PROXYCLIENT_ADDRESS="$XENSERVER_IP"

# Custom branches
QUANTUM_REPO=https://github.com/$GITHUB_USER/quantum.git
QUANTUM_BRANCH=$quantum_branch
Q_PLUGIN=openvswitch
MULTI_HOST=False
ENABLED_SERVICES+=,tempest,quantum,q-svc,q-agt,q-dhcp,q-l3,q-meta,q-domua,-n-net

# Disable security groups
Q_USE_SECGROUP=False

# Workaround
os_VENDOR="Some value"

# Citrix specific settings to speed up Ubuntu install (Remove them)
UBUNTU_INST_HTTP_HOSTNAME="mirror.anl.gov"
UBUNTU_INST_HTTP_DIRECTORY="/pub/ubuntu"
UBUNTU_INST_HTTP_PROXY="http://gold.eng.hq.xensource.com:8000"

# With XenServer single box install, VLANs need to be enabled
ENABLE_TENANT_VLANS="True"
OVS_VLAN_RANGES="physnet1:1000:1024"

LOCALRC_CONTENT_ENDS_HERE

cd tools/xen
./install_os_domU.sh
EOF
