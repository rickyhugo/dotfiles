#!/usr/bin/env bash

set -e

# nerd symbols
curl -sL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz | sudo tar xf - -J -C /usr/share/fonts/

# font: Iosevka nerd font
curl -sL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/IosevkaTerm.tar.xz | sudo tar xf - -J -C /usr/share/fonts/

# font: Iosevka (non-patched)
wget -O Iosevka.zip https://github.com/be5invis/Iosevka/releases/download/v33.0.1/PkgTTC-Iosevka-33.0.1.zip
sudo unzip Iosevka.zip -d /usr/share/fonts
rm Iosevka.zip

# font: Jetbrains mono
curl -sL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | sudo tar xf - -J -C /usr/share/fonts/

# font: Jetbrains mono (non-patched)
wget https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip -O jetbrains.zip
sudo unzip jetbrains.zip -d /usr/share/fonts/
rm jetbrains.zip
