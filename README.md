# pve-ww

Current feature-set:
- Warewulf overlays for individual node configuration
- RDMA nfs for pve stated files (pve-cluster, ceph, corosync, etc.)
- Automation script for building image in docker, importing to warewulf, and re-building in warewulf

Future feature-set:
- LDAP
- CEPH

## Requirements:

For the node / VM running these services, we are using Debian 12.0, but you can use any distro you want. We highly recommend running these services in a VM as they do not require much resources to operate. 
Minimum VM allocation:
- 4 cores
- 16GB ram
- 64GB disk

## Part I: Warewulf, Docker, and iPXE Install 

### Step 1. Install Warewulf

Warewulf was the driving point of this project. It's purpose is to dynamically bring up multiple nodes at once with nearly identical configurations only varying via their overlays. So lets go ahead and get it installed why don't we. 

First the necessary packages.

```
apt install go make
```

Then we download Warewulf's tarball, extract it, and install it.

```
curl -LO https://github.com/warewulf/warewulf/releases/download/v4.6.2/warewulf-4.6.2.tar.gz
tar -xf warewulf-4.6.2.tar.gz
cd warewulf-4.6.2
make all -j$(nproc) && sudo make install -j$(nproc)
```

### Step 2. Install Docker

Now, normally we care if something is built from source, but we only need Docker to pull and build container images, so we are just going to install its package

```
apt install docker
```

### Step 3. Install iPXE

Building warewulf from source does not include iPXE, so we are going to need to also build it from source.

```
stuff for drew
```

## Part II: NFS Configuration

## Part III: Overlays

## Part IV: Warewulf Node Configuration

## Part V: First boot / enroll into cluster
