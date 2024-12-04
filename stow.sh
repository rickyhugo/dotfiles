#!/bin/bash

set -e

cd config
stow --verbose --target="$HOME" --restow -- */
