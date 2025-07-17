#!/bin/bash
#Defaults:
BASE_IMAGE=base

#Help Menu:
show_help() {
    cat << EOF
Usage: ${0##*/} [OPTIONS]

Options:
  -h, --help                 Show this help message and exit
  -b, --baseImage IMAGE      Specify the base image (default=base)
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
                echo "Error: --baseImage requires a value."
                exit 1
            fi
            ;;
        --baseImage=*)
            BASE_IMAGE="${1#*=}"
	    echo -e "\nUsing base image ${1#*=}\n"
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
    rsync -a /mnt/pve-node-states/{$BASE_IMAGE,$node}/
    echo -e "\nCompleted $node's fs" 
  fi
done
