#!/bin/bash

echo "Building all overlays"
wwctl overlay build

for node in $(echo "$(wwctl node list -j)" | jq -r 'keys[]'); do
    echo "Updating overlays for $node"
    cat /opt/warewulf/var/warewulf/provision/overlays/$node/__SYSTEM__.img | cpio -idD /mnt/pve-node-states/$node/
    cat /opt/warewulf/var/warewulf/provision/overlays/$node/__RUNTIME__.img | cpio -idD /mnt/pve-node-states/$node/
done
