#!/usr/bin/env pwsh

$start_path = $PWD

Write-Output "Installing ASG"
cd $HOME

$download_url = (Invoke-WebRequest "https://api.github.com/repos/vanyle/asg/releases/latest" | select -ExpandProperty "content" | ConvertFrom-Json | select -ExpandProperty "assets" | select -ExpandProperty "browser_download_url" |  Select-String -Pattern "windows").toString()

Invoke-WebRequest $download_url -OutFile asg.tar.gz
tar xzf asg.tar.gz
Move-Item -Path build -Destination .asg
Remove-Item -Path asg.tar.gz

$env:Path += ";$HOME\.asg"

cd $start_path
Write-Output "You're all set! You can now run 'asg' to see the available commands"
Write-Output "You might want to add $HOME\.asg to your PATH"
