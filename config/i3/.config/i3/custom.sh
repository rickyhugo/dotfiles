#!/usr/bin/env bash

# keyboard
setxkbmap -layout us,se -option 'grp:alt_shift_toggle' -option compose:ralt # define compose key in order to enable world layer

# key repeat (<milliseconds_before_repeating> <repetitions_per_second>)
xset r rate 220 150

# touchpad
touchpad="VEN_04F3:00 04F3:311C Touchpad"
xinput set-prop "$touchpad" "libinput Natural Scrolling Enabled" 1
xinput set-prop "$touchpad" "libinput Tapping Enabled" 1

# proper screen locking
xautolock -detectsleep -time 3 -locker \"i3lock -c 000000\"
