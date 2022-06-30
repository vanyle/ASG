# Compile ASG (-d:release -d:danger)
nimble build --threads:on -d:release -d:danger -d:asyncBackend=chronos
# Launch it
Start-Process ./asg.exe -Argument "input website_output" 

# Perform a few modification to the input folder. The browser should be opened at localhost while doing this
# to test the websockets.

<#
Start-Sleep -Seconds 4
Write "Creating new file!"
New-Item -Path input/tmp.md -Force
Start-Sleep -Seconds 4
Write "Writing to file!"
Write "# Hello" > input/tmp.md
Start-Sleep -Seconds 4
Write "Deleting file!"
rm input/tmp.md
#>