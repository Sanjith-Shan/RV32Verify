# Windows entry point: runs ./regress inside WSL2 (see README, "Windows").
$wslPath = (wsl.exe -d Ubuntu-24.04 -- wslpath -a ($PSScriptRoot -replace '\','/')).Trim()
wsl.exe -d Ubuntu-24.04 -- bash -c "cd '$wslPath' && ./regress $args"
exit $LASTEXITCODE
