#!/bin/bash
#Defaults:
STATED_LOCATION=/mnt/pve-node-states/

#Help Menu:
show_help() {
    cat << EOF
Usage: ${0##*/} [OPTIONS] {node names}

Options:
  -h, --help                 	Show this help message and exit
  -l, --statedLocation PATH	Specify the location of the stated nfs (default=/mnt/pve-node-states/)

Examples:
  ${0##*/} -l /mnt/pve-node-states/
  ${0##*/} --statedLocation /mnt/pve-node-states/
  ${0##*/} --statedLocation=/mnt/pve-node-states/
EOF
}

#
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
	-l|--statedLocation)
	    if [[ -n "$2" && ! "$2" =~ ^- ]]; then
		STATED_LOCATION="$2"
		echo -e "\nUsing stated location $2\n"
		shift 2
	    else
		echo "ERROR: --statedLocation requires a value."
		exit 1
	    fi
	    ;;
	--statedLocation=*)
	    STATED_LOCATION="${1#*=}"
	    echo -e "\n Using stated location $2\n"
	    shift
	    ;;
    esac
done


echo "Building all overlays"
wwctl overlay build

for node in $(echo "$(wwctl node list -j)" | jq -r 'keys[]'); do
    echo "Updating overlays for $node"
    cat /opt/warewulf/var/warewulf/provision/overlays/$node/__SYSTEM__.img | cpio -idD $STATED_LOCATION/$node/
    cat /opt/warewulf/var/warewulf/provision/overlays/$node/__RUNTIME__.img | cpio -idD $STATED_LOCATION/$node/
done
