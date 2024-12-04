#!/usr/bin/env bash

# INFO: find notification daemon:
# `grep -r org.freedesktop.Notifications /usr/share/dbus-1/services/`
sudo mv /usr/share/dbus-1/services/org.freedesktop.Notifications.service /usr/share/dbus-1/services/org.freedesktop.Notifications.service.disable
