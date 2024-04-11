#! /bin/bash

# Install the required packages
#
cp /Brewfile ~/Brewfile
brew install

# Create LaunchAgents
#

# Asimov: tells time machine to ignore .gitignored files
# https://github.com/stevegrunwell/asimov
#
cp ./LaunchAgents/com.user.asimov.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u)~/Library/LaunchAgents/com.user.asimov.plist
