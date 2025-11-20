#!/bin/bash

# Update and upgrade the system
echo "Updating package list..."
apt update -y
echo "Upgrading packages..."
apt upgrade -y

clear

# Install GUI
echo "Installing LXQT and SDDM..."
apt install lxqt sddm -y

# Install Neofetch
echo "Installing Neofetch..."
apt install neofetch -y

clear

# Run Neofetch to display system information
echo "Running Neofetch..."
neofetch

# XRDP Setup
echo "Installing RDP"
apt install xrdp -y
sudo service xrdp start

# Install Tailscale
echo "Installing Tailscale"
curl -fsSL https://tailscale.com/install.sh | sh
echo "Starting Tailscale"
tailscale up

reboot
