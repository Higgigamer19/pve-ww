# pve-ww

Current feature-set:
- Warewulf overlays for individual node configuration
- Stated Proxmox config using nfs (over RDMA)
- Automation for building docker image, importing to warewulf, and re-building in warewulf

Future feature-set:
- LDAP
- CEPH

## Requirements:

For the node / VM running these services, we are using Debian Trixie, but you can use any distro you want. We highly recommend running these services in a VM as they do not require much resources to operate. 
Minimum VM allocation:
- 4 cores
- 16GB ram
- 64GB disk
    
**Note:** While possible to run these services on debian 12.0, it's not recommended since warewulf's dependency: go is out of date

## Warewulf, Docker, and iPXE Install 

### Step 1. Install Warewulf

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

### Step 2. Install Docker

Debian maintains a very out-of-date, minimal build of docker. A modern fully-featured build can be installed by using docker's apt reposiotory. Since we only need Docker to pull and build container images, we will use Debian's build.

```bash
apt install docker
```

### Step 3. Install iPXE

Building warewulf from source does not include iPXE, so we are going to need to also build it from source. Thankfully, the warewulf repo includes a script that does this.

```bash
/opt/warewulf/src/scripts/build-ipxe.sh
sed -i 's/\/opt\/warewulf\/ipxe/\/usr\/local\/share\/ipxe/'
```

**Note:** the iPXE source tree has changed the name of the build output file. If warewulf complains about a missing `ipxe-snponly-x86_64.efi` during the `wwctl configure all` stage, run the following command:
```bash
cp /usr/local/share/ipxe/bin-x86_64-efi-snponly.efi /var/lib/tftpboot/ipxe-snponly-x86_64.efi
```
Re-run `wwctl configure tftp` and ensure the error went away

## NFS Configuration

Warewulf manages NFS for the cluster. Definitions can be found in `/opt/warewulf/etc/warewulf/warewulf.conf`. These nfs shares won't be satisfactory for what we're doing. If using a storage appliance or other node for NFS storage, add the following lines to `/etc/exports`, if you plan on using the warewulf node, append the changes to `/opt/warewulf/share/warewulf/overlays/host/rootfs/etc/exports.ww`

```exports
"/desired/path/to/node/states"\
	192.168.1.0/24(sec=sys,rw,no_root_squash,no_subtree_check)\
	192.168.50.0/24(sec=sys,rw,no_root_squash,no_subtree_check)
```
In our case, `192.168.1.0/24` is our IP subnet, and `192.168.50.0/24` is our IB subnet, change accordingly.

## Overlays

The following overlays need to be created:
- pve-fstab
- pve-resolv
- pve-interfaces

Examples for these overlays can be found in the `overlays` subdir of this repo

## Initial State Configuration

## Warewulf Node Configuration

## First boot / enroll into cluster
