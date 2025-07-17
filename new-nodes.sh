#!/bin/bash
#Defaults:
BASE_IMAGE=base
STATED_LOCATION=/mnt/pve-node-states/

#Help Menu:
show_help() {
    cat << EOF
Usage: ${0##*/} [OPTIONS] {node names}

Options:
  -h, --help                 	Show this help message and exit
  -b, --baseImage IMAGE      	Specify the base image (default=base)
  -l, --statedLocation PATH	Specify the location of the stated nfs (default=/mnt/pve-node-states/)

Examples:
  ${0##*/} -b base -l /mnt/pve-node-states/ z-01
  ${0##*/} --baseImage gpu-base --statedLocation /mnt/pve-node-states/ z-01-gpu
  ${0##*/} --baseImage=deb-base --statedLocation=/mnt/pve-node-states/ z-01-deb
EOF
}

#
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
        -b|--baseImage)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                BASE_IMAGE="$2"
                echo -e "\nUsing base image $2\n"
		shift 2
            else
                echo "ERROR: --baseImage requires a value."
                exit 1
            fi
            ;;
        --baseImage=*)
            BASE_IMAGE="${1#*=}"
	    echo -e "\nUsing base image ${1#*=}\n"
            shift
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


#Making new node(s):
for node in "$@"; do
  if [[ ${node:0:1} != "-" ]]; then
    echo -e "\n========= $node ========="
    echo -e "\nCreating node $node"
    wwctl node add $node
    echo -e "\nCopying base fs to $node's fs"
    rsync -a $STATED_LOCATION/{$BASE_IMAGE,$node}/
    echo -e "\nCompleted $node's fs" 
  fi
done
