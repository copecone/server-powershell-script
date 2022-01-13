$plugins = @(
  'https://github.com/monun/auto-reloader/releases/latest/download/AutoReloader.jar'
)

$script = $PSCommandPath
$server_folder = ".$(Split-Path $script -LeafBase)"

if (!(Test-Path -Path $server_folder))
{
  New-Item -Path . -Name $server_folder -ItemType "directory"
}

$start_script = "start.ps1"
$start_config = "$start_script.conf"

if (!(Test-Path -Path "$server_folder/$start_script")) {
  if (Test-Path -Path ".server/$start_script") {
    Copy-Item ".server/$start_script" "$server_folder/$start_script"
  } else {
    Invoke-WebRequest -OutFile "$server_folder/$start_script" -Uri "https://raw.githubusercontent.com/monun/server-script/paper/.server/$start_script"
  }
}

Set-Location "$server_folder"
$default_config = @"
version=1.18.1
build=latest
debug=true
debug_port=5005
backup=false
force_restart=false
memory=16
plugins=(
$(foreach ($plugin in $plugins) {
  Write-Output "  `"$plugin`""
})
)
"@

if (!(Test-Path "$start_config")) {
  $default_config | Out-File -FilePath $start_config
}

Invoke-Expression -Command "./$start_script launch"
Set-Location ..

<#
plugins=(
  'https://github.com/monun/auto-reloader/releases/latest/download/AutoReloader.jar'
)

script=$(basename "$0")
server_folder=".${script%.*}"
mkdir -p "$server_folder"

start_script="start.sh"
start_config="$start_script.conf"

if [ ! -f "$server_folder/$start_script" ]; then
  if [ -f ".server/$start_script" ]; then
    cp ".server/$start_script" "$server_folder/$start_script"
  else
    wget -qc -P "$server_folder" -N "https://raw.githubusercontent.com/monun/server-script/paper/.server/$start_script"
  fi
fi

cd "$server_folder" || exit

if [ ! -f "$start_config" ]; then
  cat <<EOF >$start_config
version=1.18.1
build=latest
debug=true
debug_port=5005
backup=false
force_restart=false
memory=16
plugins=(
EOF
  for plugin in "${plugins[@]}"; do
    echo "  \"$plugin\"" >>$start_config
  done
  echo ")" >>$start_config
fi

chmod +x ./$start_script
./$start_script launch

#>