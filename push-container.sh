#!/bin/bash
#Defaults:
CONTAINER_NAME=pve-ib
STATED_LOCATION=/mnt/pve-node-states/base/

#Help Menu:
show_help() {
    cat << EOF
Usage: ${0##*/} [OPTIONS] {node names}

Options:
  -h, --help                    Show this help message and exit
  -n, --containerName NAME      Specify the resulting container's name (default=pve-ib)
  -l, --statedLocation PATH	Specify the location of the base states (default=/mnt/pve-node-states/base/)

Examples:
  ${0##*/} -n pve-ib -l /mnt/pve-node-states/base/
  ${0##*/} --containerName gpu-base --statedLocation /mnt/pve-node-states/gpu-base/
  ${0##*/} --containerName=deb-base --statedLocation=/mnt/pve-node-states/deb-base/
EOF
}

#
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--containerName)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                CONTAINER_NAME="$2"
                echo -e "\nUsing containerName $2\n"
                shift 2
            else
                echo "ERROR: --containerName requires a value."
                exit 1
            fi
            ;;
        --containerName=*)
            CONTAINER_NAME="${1#*=}"
            echo -e "\nUsing container name ${1#*=}\n"
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


### --------------- Container Stuff
loading_animation() {
    ##tput csr 0 $(($LINES-3))
    tput sc
    local -a spinner=('|' '/' '-' '\')
    while :; do
        for i in "${spinner[@]}"; do
	    setterm -cursor off
	    echo "$( tput cup $LINES 0 )$1 $i            $( tput rc))"
	    sleep 0.2
    	done
    done
}

echo -e "\n--- Pushing changes to warewulf for $CONTAINER_NAME. (this may take some time)..."

sleep 1
loading_animation "Part I: Building Docker container" &
SPIN_PID=$!
docker build -t $CONTAINER_NAME .
kill "$SPIN_PID"

loading_animation "Part II: Saving Docker container" &
SPIN_PID=$!
docker save {,-o}$CONTAINER_NAME
kill "$SPIN_PID"

clear
loading_animation "Part III: Importing Docker container to warewulf" &
SPIN_PID=$!
wwctl image import $CONTAINER_NAME --force
kill "$SPIN_PID"

clear
loading_animation "Part IV: Building warewulf container" &
SPIN_PID=$!
wwctl image build $CONTAINER_NAME
kill "$SPIN_PID"

clear
loading_animation "Part V: (re)Building overlays for pre-existing nodes" &
SPIN_PID=$!
wwctl overlay build
kill "$SPIN_PID"

clear
echo -e "\n--- Completed pushing $CONTAINER_NAME to warewulf"

setterm -cursor on

### --------------- Initial State Configuration

push_initial_state() {
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
        	$STATED_LOCATION/etc/ ;
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
        	$STATED_LOCATION/var/lib/ ;
	done

	mkdir -p $STATED_LOCATION/var/lib/rrdcached
}

echo -e "\n\n"
read -p "Would you like to push the stated contents of $CONTAINER_NAME to $STATED_LOCATION? y/N: " input
case "$input" in
    y|Y|yes|Yes)
	echo -e "\nChose yes to pushing stated contents."
	push_initial_state
	exit 0
	;;
    *)
	echo -e "\nChose no to pushing stated contents."
	exit 1
	;;
esac
