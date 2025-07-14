# pve-ww

Externally stated Proxmox Cluster Net-booting

**Warning:** This repo is a Work In Progress. While success has been had, this repo only acts as a guide. Much attention to detail and knowledge of your environment is necessary

Current feature-set:
- Warewulf overlays for individual node configuration
- Stated Proxmox config using nfs (over RDMA)
- Automation for building docker image, importing to warewulf, and re-building in warewulf

Future feature-set:
- Initial node state automation
- LDAP
- CEPH

## Requirements:

For the node / VM running these services, we are using Debian Trixie, but you can use any distro you want. We highly recommend running these services in a VM as they do not require much resources to operate. 
Minimum VM allocation:
- 4 cores
- 16GB ram
- 64GB disk
    
**Note:** While possible to run these services on debian 12.0, it's not recommended since warewulf's dependency: go is out of date

## 1. Warewulf, Docker, and iPXE Install 

### 1.1. Build & Install Warewulf

Warewulf is the driving point of this project. Its purpose is to dynamically net-boot multiple nodes at once with nearly identical configurations only varying via their overlays.

First, the necessary packages.

```bash
apt install go make
```

Download Warewulf's tarball, extract it, and install it.

```bash
curl -LO https://github.com/warewulf/warewulf/releases/download/v4.6.2/warewulf-4.6.2.tar.gz
tar -xf warewulf-4.6.2.tar.gz
cd warewulf-4.6.2
make all PREFIX=/opt/warewulf -j$(nproc) 
sudo make install PREFIX=/opt/warewulf
```

### 1.2. Install Docker

Debian maintains a very out-of-date, minimal build of docker. A modern fully-featured build can be installed by using docker's apt reposiotory. Since we only need Docker to pull and build container images, we will use Debian's build.

```bash
apt install docker
```

### 1.3. Install iPXE

Building warewulf from source does not include iPXE, so we also need to build it from source. Thankfully, the warewulf repo includes a script that does this.

```bash
/opt/warewulf/src/scripts/build-ipxe.sh
```

**Note:** the iPXE source tree has changed the name of the build output file. If warewulf complains about a missing `ipxe-snponly-x86_64.efi` during the `wwctl configure all` stage, run the following command:
```bash
cp /usr/local/share/ipxe/bin-x86_64-efi-snponly.efi /var/lib/tftpboot/ipxe-snponly-x86_64.efi
```
Re-run `wwctl configure tftp` and ensure the error went away

### 1.4. Warewulf Initial Config

Modify the following values in /opt/warewulf/etc/warewulf/warewulf.conf
```/opt/warewulf/etc/warewulf/warewulf.conf
ipaddr: 192.168.1.217 #ip of ww node
netmask: 255.255.255.0
network: 192.168.1.0 #ip subnet
dhcp:
    enabled: true
    template: default
    range start: 192.168.1.200
    range end: 192.168.1.255
    systemd name: dhcpd
tftp:
    enabled: true
    tftproot: /var/lib/tftpboot
    systemd name: tftpd-hpa
    ipxe:
        00:0B: arm64-efi/snponly.efi
        "00:00": undionly.kpxe
        "00:07": ipxe-snponly-x86_64.efi
        "00:09": ipxe-snponly-x86_64.efi
nfs:
    enabled: true
    export paths:
        - path: /home
          export options: rw,sync
        - path: /opt
          export options: ro,sync,no_root_squash
    systemd name: nfs-server
ssh:
    key types:
        - #remove dsa
paths:
    ipxesource: /usr/local/share/ipxe
```

### 1.5. Bootstrap warewulf

Now that the main config is done, we need to boostrap warewulf on the host. Run `wwctl configure all` to do this. 

## 2. NFS Configuration

Warewulf manages NFS for the cluster. Definitions can be found in `/opt/warewulf/etc/warewulf/warewulf.conf`. These nfs shares won't be satisfactory for what we're doing. If using a storage appliance or other node for NFS storage, add the following lines to `/etc/exports` on that box, if you plan on using the warewulf node, append the changes to `/opt/warewulf/share/warewulf/overlays/host/rootfs/etc/exports.ww`

```exports
"/desired/path/to/node/states"\
	192.168.1.0/24(sec=sys,rw,no_root_squash,no_subtree_check)\
	192.168.50.0/24(sec=sys,rw,no_root_squash,no_subtree_check)
```
In our case, `192.168.1.0/24` is our IP subnet, and `192.168.50.0/24` is our IB subnet, change accordingly.

## 3. Image Configuration

### 3.1. Image root password creation

In the dockerfile, we've included a line that sets the root password to 'changeme'; the following command will generate a hash of your desired password

```bash
openssl passwd -6 --salt $(uuidgen)
```

**Note:** if uuidgen isn't present on the system, install it or replace it with any random string.

### 3.2. Pushing the container

Building the node images is very straight-forward; the process is as follows:
1. Build the container from dockerfile
2. Export the container to file
3. Import the file into warewulf
4. Build the image provisions for sucessful net-booting

This process can take qutie a while, depending on network speed, disk speed, and CPU performance. To avoid babysitting the process, I've written a script and included it in the root of this repo. To build the container from end-to-end, run the following:

```bash
./push-container.sh
```

## 4. Overlay Configuration

The following overlays need to be created:
- pve-fstab
- pve-resolv
- pve-interfaces

Examples for these overlays can be found in the `overlays` subdir of this repo

**Note:** Ensure the network device in pve-interfaces matches what enumerates on your hardware.

## 5. Initial State Configuration

Since the nodes are stated using files on an nfs mount, we need to provide the node's initial state for first boot. Thankfully, its initial state happens to be the same as if we didn't mount over the container. In this section, I'm going to refer to the root of our node states dir as `/mnt/pve-node-states`, if yours is different, please mount it or change accordingly.

Since We'll be doing this more than once, I'm going create a `/mnt/pve-node-states/base` dir that we'll copy for each node

```bash
for dir in network pam.d multipath ssh corosync iproute2 apt; do rsync -va --mkpath /opt/warewulf/var/warewulf/chroots/pve-ib/rootfs/etc/$dir /mnt/pve-node-states/base/etc/; done
for dir in ceph corosync lxc pve-cluster pve-firewall pve-manager qemu-server rrdcached; do rsync -va --mkpath /opt/warewulf/var/warewulf/chroots/pve-ib/rootfs/var/lib/$dir /mnt/pve-node-states/base/var/lib/; done
```

Each node also has it's own overlay provisions that need to be copied. 

First, ensure overlays are build using `wwctl overlay build`, then, we'll copy the base dir to the dir of our future node, in this case, z-01

```bash
rsync -va /mnt/pve-node-states/{base,z-01}/
```

Finally, we need to extract the overlay provisions for that node into the dir as well.

```bash
cat /opt/warewulf/var/warewulf/provision/overlays/z-01/__SYSTEM__.img | cpio -ivdD /mnt/pve-node-states/z-01/
cat /opt/warewulf/var/warewulf/provision/overlays/z-01/__RUNTIME__.img | cpio -ivdD /mnt/pve-node-states/z-01/
```

Now our state should be ready for first boot

## 6. Warewulf Profile Configuration

Node definition configuration is straightforward. We'll be leveraging warewulf's default profile for most of the heavy lifting. 

First, we'll add our overlays. issue `wwctl profile edit default` and modify the section under overlays to be as follows:

```yaml
default:
  system overlay:
    - wwinit
    - wwclient
    - pve-fstab
    - hostname
    - ssh.host_keys
    - issue
    - pve-resolv
    - udev.netname
    - systemd.netname
    - ifcfg
    - wicked
    - ignition
    - proxmox.interfaces
```

Next we'll need to configure our network devices: again, issue the profile edit command and modify to reflect the following:
```yaml
default:
  network devices:
    ib:
      type: infiniband
      device: ib0
```

Finally, We'll set the container image w/ this last change:
```yaml
default:
  image name: pve-ib
```

## 7. Warewulf Node Configuration

We let the profile do most of our config. config for nodes are only node-specific:

First, let's add a node:
```bash
wwctl node add z-01
```

Now, let's edit it's config to be appropriate, issue `wwctl node edit z-01`, and change the following lines:

```yaml
z-01:
  network devices:
    default:
      ipaddr: 192.168.1.110
    ib:
      ipaddr: 192.168.50.110
```

And finally, we'll set our node to 'discoverable' so warewulf will assign it the next hardware address that queries iPXE

```bash
wwctl node set -discoverable z-01
```

## 8. Fixing Debian tftp

Debian's build of tftp has some strange defaults we'll need to change in order for our nodes to boot. Modify `/etc/defaults/tftpd-hpa` to be the following, replace {NODE_IP} with the ip of the node:
```conf
# /etc/default/tftpd-hpa

TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot/"
TFTP_ADDRESS="{NODE_IP}:69"
TFTP_OPTIONS="--secure"
```

Then restart the service.

## 9. First boot / enroll into cluster

At this point, Everything should be ready for you to power on your first Proxmox node. Ensure the node is set to PXE boot in the BIOS and watch it go. It should end up at a tty screen that shows the node's IP, and you should be able to login to the webgui. 

## 10. Enrolling Nodes in a cluster

So far, we have one or more netbooted hypervisors; they are currently all independent on one another. To utilize pve's strongest suit, we need to enroll them in a cluster.

**Note:** It is recommended to have 1-3 fully-stated (standard install) proxmox node to ensure quorum is maintained in a failure state. 

Preferably on a fully-stated node, run the following:
```bash
pvecm create {CLUSTER}
```

where {CLUSTER} is the desired name.

Then, on all other nodes, run:

```bash
pvecm add {IP_ADDR}
```
where {IP_ADDR} is the ip or hostname of any node already enroleld

Finally, run:

```bash
pvecm status
```

to ensure everything is working as intended