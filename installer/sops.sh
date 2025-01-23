#!/usr/bin/env bash

# Download the binary
curl -LO https://github.com/getsops/sops/releases/download/v3.9.3/sops-v3.9.3.linux.amd64

# Move the binary in to your PATH
sudo mv sops-v3.9.3.linux.amd64 /usr/local/bin/sops

# Make the binary executable
sudo chmod +x /usr/local/bin/sops
