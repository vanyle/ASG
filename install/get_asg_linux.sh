#!/bin/sh

set -eu

echo "Installing ASG"
cd ~
curl -L https://github.com/vanyle/ASG/releases/download/0.0.1/asg-0.0.1-linux-amd64.tar.gz > asg.tar.gz && tar xzf asg.tar.gz
mv build .asg
rm asg.tar.gz
rm -rf build
export PATH="~/.asg:$PATH"

echo "You're all set! You can now run 'asg' to see the available commands"
echo "If you want to add asg to your path, add the following to your .bashrc"
echo "export PATH=\"~/.asg:\$PATH\""