#!/usr/bin/env pwsh

Write-Output "Installing ASG"
cd $HOME
Invoke-WebRequest "https://github.com/vanyle/ASG/releases/download/0.2.2/asg-0.2.2-windows-amd64.tar.gz" -OutFile asg.tar.gz
tar xzf asg.tar.gz
Move-Item -Path build -Destination .asg
Remove-Item -Path asg.tar.gz

$env:Path += ";$HOME\.asg"

Write-Output "You're all set! You can now run 'asg' to see the available commands"
Write-Output "You might want to add $HOME\.asg to your PATH"
