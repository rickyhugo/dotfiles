#!/usr/bin/env bash

# Build the Docker image which will contain the binary.
docker build -t kmonad-builder github.com/kmonad/kmonad.git

# Spin up an ephemeral Docker container from the built image, to just copy the
# built binary to the host's current directory bind-mounted inside the
# container at /host/.
docker run --rm -it -v "$PWD":/host/ kmonad-builder bash -c 'cp -vp /root/.local/bin/kmonad /host/'

# Clean up build image, since it is no longer needed.
docker rmi kmonad-builder

# Move binary
sudo mv kmonad /usr/local/bin/kmonad

# Set up a systemd service for kmonad
sudo ln -s "$HOME"/.config/kmonad/kmonad.service /etc/systemd/system/kmonad.service
sudo systemctl daemon-reload
sudo systemctl enable kmonad.service
