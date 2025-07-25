FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN sed '0,/deb.debian.org/s//atl.mirrors.clouvider.net/' /etc/apt/sources.list.d/debian.sources -i

# --- 1. Tools ---
RUN apt-get update && apt-get install -y \
    sudo \
    openssh-server \
    net-tools \
    iproute2 \
    pciutils \
    lvm2 \
    nfs-common \
    multipath-tools \
    ifupdown \
    rsync \
    curl \
    vim \
    tmux \
    less \
    htop \
    sysstat \
    cron \
    ipmitool \
    smartmontools \
    lm-sensors \
    iputils-ping

# --- 2. Proxmox Setup ---
RUN apt-get update && \
    apt-get install -y gnupg curl wget lsb-release ca-certificates && \
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list && \
    curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
RUN apt-get update && \
    apt-get install -y proxmox-ve

# --- 3. PVE Post-Install Helper Script ---
# -- 3.1 Correcting PVE Sources --
RUN cat <<EOF >/etc/apt/sources.list 
deb http://deb.debian.org/debian bookworm main contrib 
deb http://deb.debian.org/debian bookworm-updates main contrib 
deb http://security.debian.org/debian-security bookworm-security main contrib 
EOF
RUN echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' >/etc/apt/apt.conf.d/no-bookworm-firmware.conf

# -- 3.2 Disabling 'pve-enterprise' repository --
RUN rm /etc/apt/sources.list.d/pve-enterprise.list 

# -- 3.3 Correcting ceph package repositories --
RUN cat <<EOF >/etc/apt/sources.list.d/ceph.list 
# deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise 
# deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription 
# deb https://enterprise.proxmox.com/debian/ceph-reef bookworm enterprise 
# deb http://download.proxmox.com/debian/ceph-reef bookworm no-subscription 
EOF

# -- 3.4 Disabling subscription nag --
RUN echo "DPkg::Post-Invoke { \"dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ \$? -eq 1 ]; then { echo 'Removing subscription nag from UI...'; sed -i '/.*data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi\"; };" >/etc/apt/apt.conf.d/no-nag-script
RUN apt --reinstall install proxmox-widget-toolkit &>/dev/null

# -- 3.5 Updating Proxmox --
RUN apt-get update &>/dev/null
RUN apt-get -y dist-upgrade &>/dev/null

# --- 4. Configure root password and SSH ---
# RUN echo "root:changeme" | chpasswd
RUN usermod -p '$6$2bb08fba-4413-4f$81cUIgoLs4cuu35ao7O07SCqprmk7cTHiCCk9g35Aak8QlRBXIhkTbwHHAUr1twLQ89ml63B2NvlAsWS82Tm80' root

# --- 5. Infiniband installation ---
RUN sudo apt-get install -y rdma-core libibverbs1 librdmacm1 \
libibmad5 libibumad3 librdmacm1 ibverbs-providers rdmacm-utils \
infiniband-diags libfabric1 ibverbs-utils tuned

# --- 6. Putting this here since it kernel panics in an overlay ---
RUN sed -i '/After=network.target/a RequiresMountsFor=/var/lib/pve-cluster' /lib/systemd/system/pve-cluster.service

# --- 7. Clean up ---
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 8. Default systemd entrypoint (for WW4 netboot) ---
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
