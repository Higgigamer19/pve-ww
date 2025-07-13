#!/bin/bash
echo 'pushing changes to warewulf. (this may take some time)...'
docker build -t pve-ib .
docker save {,-o}pve-ib
wwctl import pve-ib --force
wwctl image build pve-ib
wwctl overlay build
