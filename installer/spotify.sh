#!/usr/bin/env bash

# spotify-client
curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
echo "deb http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
sudo apt-get update && sudo apt-get install spotify-client -y

# spotify-tui
cargo install spotify-tui

# spotifyd
sudo apt install libssl-dev libasound2-dev -y
cargo install spotifyd --locked
