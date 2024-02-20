#region - DECLORATIONS
$script:diag = $null
$script:blnWARN = $false
$script:blnBREAK = $false
$script:zabbixInstalled = Get-Service "Zabbix Agent 2" -ErrorAction SilentlyContinue
$script:mode = $env:mode
$script:dattoCustomerName = $env:CS_PROFILE_NAME
$script:hostname = $env:COMPUTERNAME
$script:serverHostnameOrIP = $env:serverHostnameOrIP
$zabbixDownload = "https://cdn.zabbix.com/zabbix/binaries/stable/6.4/6.4.11/zabbix_agent2-6.4.11-windows-amd64-openssl.msi"
$strLineSeparator = "----------------------------------"
#endregion - DECLORATIONS
#region - FUNCTIONS
function write-DRMMDiag ($messages) {
  write-output "<-Start Diagnostic->"
  foreach ($message in $messages) { $message }
  write-output "<-End Diagnostic->"
} ## write-DRMMDiag
function write-DRMMAlert ($message) {
  write-output "<-Start Result->"
  write-output "Alert=$($message)"
  write-output "<-End Result->"
} ## write-DRMMAlert
function StopClock {
  #Stop script execution time calculation
  $script:sw.Stop()
  $Days = $sw.Elapsed.Days
  $Hours = $sw.Elapsed.Hours
  $Minutes = $sw.Elapsed.Minutes
  $Seconds = $sw.Elapsed.Seconds
  $Milliseconds = $sw.Elapsed.Milliseconds
  $ScriptStopTime = (get-date -format "yyyy-MM-dd HH:mm:ss").ToString()
  write-output "`r`nTotal Execution Time - $($Minutes) Minutes : $($Seconds) Seconds : $($Milliseconds) Milliseconds`r`n"
  $script:diag += "`r`n`r`nTotal Execution Time - $($Minutes) Minutes : $($Seconds) Seconds : $($Milliseconds) Milliseconds`r`n"
}
function logERR ($intSTG, $strModule, $strErr) {
  $script:blnWARN = $true
  #CUSTOM ERROR CODES
  switch ($intSTG) {
    1 {
      #'ERRRET'=1 - NOT ENOUGH ARGUMENTS, END SCRIPT
      $script:blnBREAK = $true
      $script:diag += "`r`n$($strLineSeparator)`r`n$($(get-date)) - Zabbix - NO ARGUMENTS PASSED, END SCRIPT`r`n`r`n"
      write-output "$($strLineSeparator)`r`n$($(get-date)) - Zabbix - NO ARGUMENTS PASSED, END SCRIPT`r`n"
    }
    2 {
      #'ERRRET'=2 - END SCRIPT
      $script:blnBREAK = $true
      $script:diag += "`r`n$($strLineSeparator)`r`n$($(get-date)) - Zabbix - ($($strModule)) :"
      $script:diag += "`r`n$($strLineSeparator)`r`n`t$($strErr), END SCRIPT`r`n`r`n"
      write-output "$($strLineSeparator)`r`n$($(get-date)) - Zabbix - ($($strModule)) :"
      write-output "$($strLineSeparator)`r`n`t$($strErr), END SCRIPT`r`n`r`n"
    }
    3 {
      #'ERRRET'=3
      $script:blnWARN = $false
      $script:diag += "`r`n$($strLineSeparator)`r`n$($(get-date)) - Zabbix - $($strModule) :"
      $script:diag += "`r`n$($strLineSeparator)`r`n`t$($strErr)"
      write-output "$($strLineSeparator)`r`n$($(get-date)) - Zabbix - $($strModule) :"
      write-output "$($strLineSeparator)`r`n`t$($strErr)"
    }
    default {
      #'ERRRET'=4+
      $script:blnBREAK = $false
      $script:diag += "`r`n$($strLineSeparator)`r`n$($(get-date)) - Zabbix - $($strModule) :"
      $script:diag += "`r`n$($strLineSeparator)`r`n`t$($strErr)"
      write-output "$($strLineSeparator)`r`n$($(get-date)) - Zabbix - $($strModule) :"
      write-output "$($strLineSeparator)`r`n`t$($strErr)"
    }
  }
}
function dir-Check () {
  #CHECK 'PERSISTENT' FOLDERS
  if (-not (test-path -path "C:\temp")) { new-item -path "C:\temp" -itemtype directory -force }
  if (-not (test-path -path "C:\IT")) { new-item -path "C:\IT" -itemtype directory -force }
  if (-not (test-path -path "C:\IT\Log")) { new-item -path "C:\IT\Log" -itemtype directory -force }
  if (-not (test-path -path "C:\IT\Scripts")) { new-item -path "C:\IT\Scripts" -itemtype directory -force }
  if (-not (test-path -path "C:\IT\Zabbix")) { new-item -path "C:\IT\Zabbix" -itemtype directory -force | out-string }
}
function downloadAndDeploy {
  logERR 3 "Starting deploy"
  $pkg = "C:\IT\Zabbix_Agent_2.msi"
  $logFile = "C:\IT\Log\Zabbix.log"
  $taskdiag = "Downloading and Deploying Zabbix 2`r`n$($strLineSeparator)"
  logERR 3 "Downloading Zabbix" "Line 89 - $($taskdiag)"
  try { Invoke-WebRequest -uri "$($zabbixDownload)" -OutFile "$($pkg)" } catch {
    $taskdiag = "Failed to Download Zabbix 2`r`n$($strLineSeparator)"
    logERR 1 "downloadAndDeploy" "Line 22 - $($taskdiag)"
  }
  try { $taskdiag = Start-Process -FilePath $pkg -ArgumentList "/l*v $($logFile) SERVER=$($script:serverHostnameOrIP) /qn" -PassThru -Wait } catch {
    $taskdiag += "`r`nFailed to Install Zabbix 2`r`n$($strLineSeparator)"
    logERR 1 "downloadAndDeploy" "Line 26 - $($taskdiag)"
  }
  Start-Sleep -seconds 30 
  try { cp -Path "C:\Program Files\Zabbix Agent 2\*" -Destination "C:\IT\Zabbix" -Recurse -Force } catch {
    mkdir C:\IT\Zabbix 
    $taskdiag = "Failed to Copy Zabbix 2`r`n$($strLineSeparator)"
    logERR 1 "downloadAndDeploy" "Line 28 - $($taskdiag)"
  }
  try {
    $oldConf = "C:\IT\Zabbix\zabbix_agent2.conf"
    rm $oldConf -Force
    $conf = "C:\IT\Zabbix\zabbix_agent2.conf"
    Invoke-WebRequest -uri "https://raw.githubusercontent.com/CW-Khristos/RMM/dev/Zabbix/zabbix_agent2.conf" -OutFile "$($conf)"
    $confContent = cat $conf
    $confContent = $confContent | Out-String
    $newConf = ($confContent.Replace( "[HOSTNAME]", "$($script:dattoCustomerName - $($script:hostname))")).Replace("[SERVER]", "$($script:serverHostnameOrIP)")
    #"Hostname=$($env:CS_PROFILE_NAME - $($hostname))"
    $newConf | Set-Content -Path $conf
  } catch {
    $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
    $taskdiag = "Failed to Edit Config File : This may have to be done manually`r`n$($strLineSeparator)"
    logERR 3 "downloadAndDeploy" "Line 33 - $($taskdiag)`r`n$($err)`r`n$($strLineSeparator)"
  }
  #not really sure if we have to do this above step to set conf file, might just be a step for Zabbix 1 not Zabbix 2. 
}
function removeZabbix {
  logERR 3 "Attempting to unistall"
  $regPath = get-itemproperty -path 'HKLM:\SOFTWARE\Zabbix SIA\Zabbix Agent 2 (64-bit)' -name 'ProductCode'
  $regPath.ProductCode
  Start-Process -FilePath "C:\Windows\system32\msiexec.exe" -ArgumentList "/x $($regPath.ProductCode) /qn" -PassThru -Wait
  rm "C:\IT\Zabbix" -Recurse -Force
}
#endregion - FUNCTIONS
#region - SCRIPT
$ScrptStartTime = (get-date -format "yyyy-MM-dd HH:mm:ss").ToString()
$script:sw = [Diagnostics.Stopwatch]::StartNew()
dir-Check
if ($script:Mode -eq "Deploy") {
  $taskdiag = "Downloading and Deploying Zabbix 2`r`n$($strLineSeparator)"
  logERR 3 "downloadAndDeploy - $($taskdiag)"
  downloadAndDeploy
  $script:zabbixInstalled = Get-Service "Zabbix Agent 2" 
  Restart-Service -Name $($script:zabbixInstalled.Name)
  if ($($script:zabbixInstalled.Status) -eq "Stopped") {
    Write-Warning "Service is not started : `r`n Attempting to start"
    & "c:\IT\Zabbix\zabbix_agent2.exe -c c:\IT\Zabbix\zabbix_agent2.conf -i"
  }
  if ($($script:zabbixInstalled.Status) -eq "Running") { Write-Output "Zabbix is running" }
}
if ($script:Mode -eq "Remove") {
  removeZabbix
}
#endregion - SCRIPT
#check if dir is there, if service is there, check config file and make sure the hostname string and server string match our expectates.
