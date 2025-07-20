# pve-ww

Externally stated Proxmox Cluster Net-booting using Warewulf 4

**Warning:** This repo is a Work In Progress. While success has been had, this repo only acts as a guide. Much attention to detail and knowledge of your environment is necessary

Current feature-set:
- Warewulf overlays for individual node configuration
- Stated Proxmox config using nfs (over RDMA)
- Automation Scripts
	- `./push-container`: Automation for building docker image, importing to warewulf, and re-building in warewulf
	- `./new-nodes`: Automation for creating new nodes and rsync base fs to new fs
	- `./update-overlays`: Automation for (re)building overlays and uploading them to nodes' fs

Future feature-set:
- Initial node state automation
- LDAP
- CEPH

![](https://github.com/Higgigamer19/pve-ww/blob/main/pve-ww_480p.gif)

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
apt install \
    golang \
    make \
    build-essential \
    git \
    nfs-kernel-server \
    tftpd-hpa \
    isc-dhcp-server \
    jq
```

Download Warewulf's tarball, extract it, and install it.

```bash
git clone -b v4.6.x https://github.com/warewulf/warewulf.git /opt/warewulf/src
cd /opt/warewulf/src
make all PREFIX=/opt/warewulf -j$(nproc) 
make install PREFIX=/opt/warewulf
echo 'PATH=$PATH:/opt/warewulf/bin' > /etc/profile.d/ww.sh
go clean -modcache
```

### 1.2. Install Docker

Debian maintains a very out-of-date, minimal build of docker. A modern fully-featured build can be installed by using docker's apt reposiotory. Since we only need Docker to pull and build container images, we will use Debian's build.

```bash
apt install docker.io
```

### 1.3. Install iPXE

Building warewulf from source does not include iPXE, so we also need to build it from source. Thankfully, the warewulf repo includes a script that does this.

```bash
mkdir -p /usr/local/share/ipxe
/opt/warewulf/src/scripts/build-ipxe.sh
```

**Note:** the iPXE source tree has changed the name of the build output file. If warewulf complains about a missing `ipxe-snponly-x86_64.efi` during the `wwctl configure --all` stage, run the following command:
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
    systemd name: isc-dhcp-server
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

### 1.5. Configure DHCP Interfaces

By default, the dhcp server will attempt to initialize on all interfaces for both ipv4 and ipv6. since our configuration doesn't include ipv6, we'll need to modify this. edit the following line in `/etc/defaults/isc-dhcp-server`:

```conf
INTERFACESv4="ens18"
```

where ens18 is the warewulf hosts ip network device.

### 1.6. Fixing Debian tftp

Debian's build of tftp has some strange defaults we'll need to change in order for our nodes to boot. Modify `/etc/defaults/tftpd-hpa` to be the following, replace {NODE_IP} with the ip of the node:
```conf
# /etc/default/tftpd-hpa

TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot/"
TFTP_ADDRESS="{NODE_IP}:69"
TFTP_OPTIONS="--secure"
```

Then restart the service with the following command:

```bash
systemctl restart tftpd-hpa
```

### 1.7. Bootstrap Warewulf

Now that the main config is done, we need to start the services and boostrap warewulf on the host. Run the following command to do this. 

```bash
systemctl enable tftpd-hpa warewulfd nfs-server --now
wwctl configure --all
```

## 2. NFS Configuration

### 2.1. NFS Configuration

Warewulf manages NFS for the cluster. Definitions can be found in `/opt/warewulf/etc/warewulf/warewulf.conf`. These nfs shares won't be satisfactory for what we're doing. If using a storage appliance or other node for NFS storage, add the following lines to `/etc/exports` on your storage box. If you plan on using the warewulf node, append the changes to `/opt/warewulf/share/warewulf/overlays/host/rootfs/etc/exports.ww` on your warewulf box.

```exports
"/desired/path/to/node/states"\
	192.168.1.0/24(sec=sys,rw,no_root_squash,no_subtree_check)\
	192.168.50.0/24(sec=sys,rw,no_root_squash,no_subtree_check)
```
In our case, `192.168.1.0/24` is our IP subnet, and `192.168.50.0/24` is our IB subnet, change accordingly.

Run the following command to make the changes take place:

```bash
systemctl restart nfs-server
```

### 2.2. NFS Mount for Warewulf Node (OPTIONAL)

If, and only if, you have a dedicated storage box your using for your pve states, lets mount it to our Warewulf node. Add the following line to `/etc/fstab` in your Warewulf box:

```fstab
{IP_ADDR}:/desired/path/to/node/states /mnt/pve-node-states nfs defaults 0 0
```

Where {IP_ADDR} is the ip address to your storage box.

Run the following command to mount the newly added nfs to your Warewulf box:

```bash
mount -a
```

## 3. Image Configuration

### 3.1. Image root password creation

In the dockerfile, we've included a line that sets the root password to 'changeme'; the following command will generate a hash of your desired password

```bash
openssl passwd -6 --salt $(uuidgen)
```

**Note:** if uuidgen isn't present on the system, install it (`apt install uuid-runtime`) or replace it with any random string.

### 3.2. Pushing the container

Building the node images is very straight-forward; the process is as follows:
1. Build the container from dockerfile
2. Export the container to file
3. Import the file into warewulf
4. Build the image provisions for sucessful net-booting

This process can take quite a while, depending on network speed, disk speed, and CPU performance. To avoid babysitting the process, I've written a script and included it in the root of this repo. To build the container from end-to-end, run the following:

```bash
./push-container.sh
```

## 4. Overlay Configuration

Create the overlays w/ the following:

```bash
for overlay in fstab resolv interfaces ;
do
    wwctl overlay create pve-$overlay ;
done
```

Examples for these overlays can be found in the `overlays` subdir of this repo. overlay files can be found at `/opt/warewulf/var/warewulf/overlays`. instructions for managing overlays through warewulf can be found in [warewulf's docs](https://warewulf.org/docs/v4.6.x/overlays/overlays.html)

## 5. Initial State Configuration

Since the nodes are stated using files on an nfs mount, we need to provide the node's initial state for first boot. Thankfully, its initial state happens to be the same as if we didn't mount over the container. In this section, I'm going to refer to the root of our node states dir as `/mnt/pve-node-states`, if yours is different, please mount it or change accordingly.

Since We'll be doing this more than once, I'm going create a `/mnt/pve-node-states/base` dir that we'll copy for each node

```bash
for dir in \
    network \
    pam.d \
    ssh \
    corosync \
    iproute2 \
    apt ;
do 
    rsync -va --mkpath \
        /opt/warewulf/var/warewulf/chroots/pve-ib/rootfs/etc/$dir \
        /mnt/pve-node-states/base/etc/ ;
done

for dir in \
    ceph \
    corosync \
    lxc \
    pve-cluster \
    pve-firewall \
    pve-manager \
    qemu-server ;
do 
    rsync -va --mkpath \
        /opt/warewulf/var/warewulf/chroots/pve-ib/rootfs/var/lib/$dir \
        /mnt/pve-node-states/base/var/lib/ ;
done

mkdir -p /mnt/pve-node-states/base/var/lib/rrdcached
```

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
    - pve-interfaces
```

Next we'll need to configure our network devices: again, issue the profile edit command and modify to reflect the following:
```yaml
default:
  network devices:
    default:
      type: ethernet
      device: enp1s0
    ib:
      type: infiniband
      device: ibp33s0
```

Finally, We'll set the container image w/ this last change:
```yaml
default:
  image name: pve-ib
```

## 7. Warewulf Node Configuration

### 7.1. Deploying a Single Node

We let the profile do most of our config. config for nodes are only node-specific:

First, let's add a node with our script:
```bash
./new-nodes.sh z-01
```
**NOTE:** Change default base image (`base`) with `-b {baseImage}` and default stated location (`/mnt/pve-node-states`) with `-l {statedLocation}`.

Now, let's edit it's config to be appropriate, issue `wwctl node edit z-01`, and change the following lines:

```yaml
z-01:
  network devices:
    default:
      ipaddr: 192.168.1.110
    ib:
      ipaddr: 192.168.50.110
```

Finally, we need to extract the overlay provisions for that node into the dir using one of the included scripts:

```bash
./update-overlays
```
**NOTE:** Change default stated location (`/mnt/pve-node-states`) with `-l {statedLocation}`.

And finally, we'll set our node to 'discoverable' so warewulf will assign it the next hardware address that queries iPXE

```bash
wwctl node set --discoverable z-01
```

### 7.2. Deploying Multiple Nodes At Once

So you want to bring up an entire proxmox cluster at once? We can do that! First we need to add the respective nodes, in our case z-01 through z-04. Run the following script:

```bash
./new-nodes.sh z-{01..04}
```

Now modify each node's IP config by running the following command:

```bash
wwctl node set z-{01..04} \
--ipaddr=192.168.1.{110,120,210,220}

wwctl node set z-{01..04} \
--netname=ib \
--ipaddr=192.168.50.{110,120,210,220}
```

Next, build and upload their overlays by running this script:

```bash
./update-overlays
```

Finally, set the nodes discoverable and they are ready to boot. Note: if you want to control which physical node is which virtual node, set them discoverable and boot them one at a time.

```bash
wwctl node set z-{01..04} --discoverable
```

## 8. First Boot

At this point, everything should be ready for you to power on your first Proxmox node. Ensure the node is set to PXE boot in the BIOS and watch it go. It should end up at a tty screen that shows the node's IP, and you should be able to login to the webgui. 

If you'd like to ensure it properly net-booted via warewulf, run the following command:

```bash
wwctl node status
```

It should end up on "\_\_RUNTIME__.img.gz"

## 9. Enrolling Nodes In A Cluster

So far, we have one or more netbooted hypervisors; they are currently all independent on one another. To utilize pve's strongest suit, we need to enroll them in a cluster.

**Note:** It is recommended to have 1-3 fully-stated (standard install) proxmox node to ensure quorum is maintained in a failure state. 

Preferably on a fully-stated node, run the following:
```bash
pvecm create {CLUSTER}
```

Where {CLUSTER} is the desired name. 

Then, on all other nodes, run:

```bash
pvecm add {IP_ADDR}
pvecm updatecerts --force
```
where {IP_ADDR} is the ip or hostname of any node already enrolled.

Finally, run:

```bash
pvecm status
```

to ensure everything is working as intended

## 10. Final Notes

When added to a cluster, there is a known bug where the network devices wont show up in the GUI, to fix this, make a dummy network device (we always do vmbr1) and it will fix the issues. We have not done scaled testing so please don't deploy mission critical VMs on this solution, although we believe it would be safe, there might be something we overlooked. 

Finally, we would like to thank you for using our solution and we hope this was what you were looking for. If you have any suggestions or issues, please post them in issues and we will try to fix/integrate when we can.


