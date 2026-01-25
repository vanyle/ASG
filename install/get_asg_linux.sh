#!/bin/sh

set -eu

echo "Installing ASG"
cd ~

if ! command -v curl > /dev/null; then
    echo " Please install 'curl' on your system using your favourite package manager. "
    exit 1
fi

download_url=$(curl -L -s https://api.github.com/repos/vanyle/asg/releases/latest | grep "linux-amd64.tar.gz" | sed -n '2p' | grep -o -E 'https?://[^"]+')

echo "Fetching $download_url"

curl -L $download_url > asg.tar.gz && tar xzf asg.tar.gz
rm -f ~/.local/bin/asg
rm -rf ~/.local/share/asg
mkdir -p ~/.local/share/asg
mkdir -p ~/.local/bin
mv build ~/.local/share/asg
rm -f asg.tar.gz
rm -rf build
mv ~/.local/share/asg/build/asg ~/.local/bin/
mv ~/.local/share/asg/build/assets ~/.local/share/asg/assets

export PATH="$HOME/.local/bin:$PATH"

echo "You're all set! You can now run 'asg'."
echo "If you want to add asg to your path, add the following to your .bashrc / .zshrc"
echo "export PATH=\"$HOME/.local/bin:\$PATH\""
echo "Note: You might not need to, ~/.local/bin might already be in your path"
