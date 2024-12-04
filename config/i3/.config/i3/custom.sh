#!/bin/bash

# keyboard
setxkbmap -layout us,se -option 'grp:alt_shift_toggle' -option compose:ralt

# key repeat (<milliseconds_before_repeating> <repetitions_per_second>)
xset r rate 220 150

# touchpad
touchpad="Synaptics TM3625-010"
xinput set-prop "$touchpad" "libinput Natural Scrolling Enabled" 1
xinput set-prop "$touchpad" "libinput Accel Speed" 0.75
xinput set-prop "$touchpad" "libinput Tapping Enabled" 1

# proper screen locking
xautolock -detectsleep -time 3 -locker \"i3lock -c 000000\"
