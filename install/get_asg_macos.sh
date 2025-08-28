#!/bin/sh

set -eu

echo "Installing ASG"
cd ~

if ! command -v curl > /dev/null; then
    echo " Please install 'curl' on your system using your favourite package manager. "
    exit 1
fi

download_url=$(curl -L -s https://api.github.com/repos/vanyle/asg/releases/latest | grep "macos-amd64.tar.gz" | sed -n '2p' | grep -o -E 'https?://[^"]+')

echo "Fetching $download_url"

curl -L $download_url > asg.tar.gz && tar xzf asg.tar.gz
rm -rf ~/.asg
mv build ~/.asg
rm asg.tar.gz
rm -rf build

export PATH="$HOME/.asg:$PATH"

echo "You're all set! You can now run 'asg'."
echo "If you want to add asg to your path, add the following to your .zshrc"
echo "export PATH=\"$HOME/.asg:\$PATH\""