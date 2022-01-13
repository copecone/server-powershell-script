$plugins = @(
  'https://github.com/monun/auto-reloader/releases/latest/download/AutoReloader.jar'
)

function loadConf($path) {
    return [string]$(((((((Get-Content -Path $path -Raw) -replace "(?<varn>[A-Za-z_]+)=", "`$`$`${varn}=") -replace "(?<varn>[A-Za-z_]+)=\(", "`${varn}=@(") -replace "(?<varn>[A-Za-z_]+)=(?<value>[\w\.]+)", "`${varn}=""`${value}""") -replace "(?<varn>[A-Za-z_]+)=""(?<value>[0-9]+)""", "`${varn}=`${value}") -replace "(?<varn>[A-Za-z_]+)=""false""", "`${varn}=`$false") -replace "(?<varn>[A-Za-z_]+)=""true""", "`${varn}=`$true")
}

function getFilenameOnUrl($url) {
    return $url.Substring($url.LastIndexOf("/") + 1)
}

function download($link, $path) {
    $filename = "$(getFilenameOnUrl $link)"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -OutFile "$path/$filename" -N "$link" 2>&1 | Select-String '([A-Z]:)?[\/\.\-\w]+\.jar'
    $ProgressPreference = 'Continue'
    return "$path/$filename"
}

if ( !($args[0] -eq "launch") )
{
    if ( !(Test-Path -Path "start") )
    {
        New-Item -Path . -Name "start"
    }
    exit
}

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

$loopCond = $true

while ($loopCond)
{
    if ( !(Test-Path -Path "$(Split-Path "$PSCommandPath" -LeafBase).sh.conf") )
    {
        $default_config | Out-File -FilePath "$(Split-Path "$PSCommandPath" -LeafBase).sh.conf"
    }

    Invoke-Expression (loadConf "$(Split-Path "$PSCommandPath" -LeafBase).sh.conf" | Out-String)

    # Print configurations
    Write-Output "version = $version"
    Write-Output "build = $build"
    Write-Output "debug = $debug"
    Write-Output "backup = $backup"
    Write-Output "force_restart = $force_restart"
    Write-Output "memory = ${memory}G"

    if (!(Test-Path -Path ".paper-api"))
    {
        New-Item -Path . -Name ".paper-api" -ItemType "directory"
    }

    $api = $( download "https://github.com/monun/paper-api/releases/latest/download/paper-api.jar" ".paper-api" )
    $server = $( java -jar "$api" -r download -v "$version" -b "$build" )
    Write-Output "server = $server"

    $jar_folder = "$($HOME -replace "\\", "/")/.minecraft/server"
    if (!(Test-Path -Path "$jar_folder"))
    {
        mkdir -p "$jar_folder"
    }

    if ( !(Test-Path -Path "$jar_folder/$(getFilenameOnUrl $server)") )
    {
        $jar = $( download "$server" "$jar_folder" )
    } else {
        $jar = "$jar_folder/$(getFilenameOnUrl $server)"
    }

    Write-Output "jar = $jar"

    # Download plugins
    if (!(Test-Path -Path "plugins"))
    {
        New-Item -Path . -Name "plugins" -ItemType "directory"
    }

    foreach ($plugin in $plugins)
    {
        $download_result = $( download "$plugin" "plugins" )
        Write-Output "$download_result <- $plugin"
    }

    $jvm_arguments = @(
    "-Xmx${memory}G"
    "-Xms${memory}G"
    "-XX:+ParallelRefProcEnabled"
    "-XX:MaxGCPauseMillis=200"
    "-XX:+UnlockExperimentalVMOptions"
    "-XX:+DisableExplicitGC"
    "-XX:+AlwaysPreTouch"
    "-XX:G1HeapWastePercent=5"
    "-XX:G1MixedGCCountTarget=4"
    "-XX:G1MixedGCLiveThresholdPercent=90"
    "-XX:G1RSetUpdatingPauseTimePercent=5"
    "-XX:SurvivorRatio=32"
    "-XX:+PerfDisableSharedMem"
    "-XX:MaxTenuringThreshold=1"
    "-Dusing.aikars.flags=https://mcflags.emc.gs"
    "-Daikars.new.flags=true"
    "-Dcom.mojang.eula.agree=true"
    )

    if ($memory -lt 12)
    {
        Write-Output "Use Aikar's standard memory options"
        $jvm_arguments += @(
            "-XX:G1NewSizePercent=30"
            "-XX:G1MaxNewSizePercent=40"
            "-XX:G1HeapRegionSize=8M"
            "-XX:G1ReservePercent=20"
            "-XX:InitiatingHeapOccupancyPercent=15"
        )
    }
    else
    {
        Write-Output "Use Aikar's Advanced memory options"
        $jvm_arguments += @(
            "-XX:G1NewSizePercent=40"
            "-XX:G1MaxNewSizePercent=50"
            "-XX:G1HeapRegionSize=16M"
            "-XX:G1ReservePercent=15"
            "-XX:InitiatingHeapOccupancyPercent=20"
        )
    }

    if ($debug)
    {
        $port_arguments = "$debug_port"

        $java_version = (Get-Command java | Select-Object -ExpandProperty Version).ToString()
        $java_version_9 = "9.0.0.0"

        if ($( @($java_version, $java_version_9) | %{ [System.Version]$_ } | sort )[0] -eq "$java_version_9")
        {
            Write-Output "DEBUG MODE: JDK9+"
            $port_arguments="*:$port_arguments"
        }
        else
        {
            Write-Output "DEBUG MODE: JDK8"
        }
        $jvm_arguments += @("-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=$port_arguments")
    }

    $jvm_arguments += @(
        "-jar"
        "$jar"
        "nogui"
    )

    $loopCond = $false
    java $jvm_arguments

    if ($backup)
    {
        $loopCond = $true
        Write-Output "Press Enter to start the backup immediately or Ctrl+C to cancel ``echo $'\n> '``"
        Start-Sleep -s 5

        echo 'Start the backup.'
        backup_file_name=$( date +"%y%m%d-%H%M%S" )
        mkdir -p '.backup'
        tar --exclude = './.backup' --exclude = '*.gz' --exclude = './cache' -zcf ".backup/$backup_file_name.tar.gz" .
        echo 'The backup is complete.'
    }

    if (Test-Path -Path "start")
    {
        continue
    } elseif ( $force_restart )
    {
        $loopCond = $true
        Write-Output "The server restarts. Press Enter to start immediately or Ctrl+C to cancel ``echo $'\n> '``"
        Start-Sleep -s 3
        continue
    }
}

<#
download() {
  wget -c --content-disposition -P "$2" -N "$1" 2>&1 | grep -Po '([A-Z]:)?[\/\.\-\w]+\.jar' | tail -1
}

if [[ $1 != launch ]]; then
  touch start
  exit
fi

# check java (https://stackoverflow.com/questions/7334754/correct-way-to-check-java-version-from-bash-script)
if type -p java; then
  echo "Found java executable in PATH"
  _java=java
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]]; then
  echo "Found java executable in JAVA_HOME"
  _java="$JAVA_HOME/bin/java"
else
  echo "Not found java"
  exit
fi

while :; do
  rm -f start

  script=$(basename "$0")
  script_config="./$script.conf"

  if [ ! -f "$script_config" ]; then
    cat <<EOT >"$script_config"
version=1.17.1
build=latest
debug=false
debug_port=5005
backup=false
force_restart=false
memory=16
plugins=()
EOT
  fi

  source "$script_config"

  # Print configurations
  echo "version = $version"
  echo "build = $build"
  echo "debug = $debug"
  echo "backup = $backup"
  echo "force_restart = $force_restart"
  echo "memory = ${memory}G"

  # Download paper-api
  mkdir -p ".paper-api"
  api=$(download "https://github.com/monun/paper-api/releases/latest/download/paper-api.jar" ".paper-api")
  server=$("$_java" -jar "$api" -r download -v "$version" -b "$build")
  echo "server = $server"

  jar_folder="$HOME/.minecraft/server/"
  mkdir -p "$jar_folder"
  jar=$(download "$server" "$jar_folder")

  echo "jar = $jar"

  # Download plugins
  mkdir -p "./plugins"
  for i in "${plugins[@]}"; do
    download_result=$(download "$i" "./plugins")
    echo "$download_result <- $i"
  done

  jvm_arguments=(
    "-Xmx${memory}G"
    "-Xms${memory}G"
    "-XX:+ParallelRefProcEnabled"
    "-XX:MaxGCPauseMillis=200"
    "-XX:+UnlockExperimentalVMOptions"
    "-XX:+DisableExplicitGC"
    "-XX:+AlwaysPreTouch"
    "-XX:G1HeapWastePercent=5"
    "-XX:G1MixedGCCountTarget=4"
    "-XX:G1MixedGCLiveThresholdPercent=90"
    "-XX:G1RSetUpdatingPauseTimePercent=5"
    "-XX:SurvivorRatio=32"
    "-XX:+PerfDisableSharedMem"
    "-XX:MaxTenuringThreshold=1"
    "-Dusing.aikars.flags=https://mcflags.emc.gs"
    "-Daikars.new.flags=true"
    "-Dcom.mojang.eula.agree=true"
  )

  if [[ $memory -lt 12 ]]; then
    echo "Use Aikar's standard memory options"
    jvm_arguments+=(
      "-XX:G1NewSizePercent=30"
      "-XX:G1MaxNewSizePercent=40"
      "-XX:G1HeapRegionSize=8M"
      "-XX:G1ReservePercent=20"
      "-XX:InitiatingHeapOccupancyPercent=15"
    )
  else
    echo "Use Aikar's Advanced memory options"
    jvm_arguments+=(
      "-XX:G1NewSizePercent=40"
      "-XX:G1MaxNewSizePercent=50"
      "-XX:G1HeapRegionSize=16M"
      "-XX:G1ReservePercent=15"
      "-XX:InitiatingHeapOccupancyPercent=20"
    )
  fi

  if [[ $debug == true ]]; then
    port_arguments="$debug_port"

    java_version=$("$_java" -version 2>&1 | awk -F '"' '/version/ {print $2}')
    java_version_9="9"

    if [ "$(printf '%s\n' "$java_version" "$java_version_9" | sort -V | head -n1)" = "$java_version_9" ]; then
      echo "DEBUG MODE: JDK9+"
      port_arguments="*:$port_arguments"
    else
      echo "DEBUG MODE: JDK8"
    fi

    jvm_arguments+=("-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=$port_arguments")
  fi

  jvm_arguments+=(
    "-jar"
    "$jar"
    "nogui"
  )

  "$_java" "${jvm_arguments[@]}"

  if [[ $backup = true ]]; then
    read -r -t 5 -p "Press Enter to start the backup immediately or Ctrl+C to cancel `echo $'\n> '`"
    echo 'Start the backup.'
    backup_file_name=$(date +"%y%m%d-%H%M%S")
    mkdir -p '.backup'
    tar --exclude='./.backup' --exclude='*.gz' --exclude='./cache' -zcf ".backup/$backup_file_name.tar.gz" .
    echo 'The backup is complete.'
  fi

  if [[ -f start ]]; then
    continue
  elif [[ $force_restart = true ]]; then
    read -r -t 3 -p "The server restarts. Press Enter to start immediately or Ctrl+C to cancel `echo $'\n> '`"
    continue
  else
    break
  fi
done
#>
