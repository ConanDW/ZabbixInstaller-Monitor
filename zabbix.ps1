<#
    .SYNOPSIS
        Monitoring - Windows - Zabbix - Cameron Day - Chris Bledsoe
    .DESCRIPTION
        This script will monitor if Zabbix is installed and configured correctly. Will also install or unistall zabbix as needed.
        Copyright 2024 Cameron Day, Chris Bledsoe
    .NOTES
        2024-02-21: Added upgrade and monitor functions.
        2024-02-20: Initial version
#>
#region - DECLORATIONS
$script:diag = $null
$script:blnWARN = $false
$script:blnBREAK = $false
$script:zabbixInstalled = Get-Service "Zabbix Agent 2" -ErrorAction SilentlyContinue
$script:mode = $env:mode
$script:dattoCustomerName = $env:CS_PROFILE_NAME
$script:hostname = $env:COMPUTERNAME
$script:serverHostnameOrIP = $env:serverHostnameOrIP
$script:pskID = $env:pskID
$script:pskValue = $env:pskValue
$installFolder = "C:\IT\Zabbix"
$logFile = "C:\IT\Log\Zabbix.log"
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
      $script:diag += "`r`n$($strLineSeparator)`r`n$($(get-date)) - Zabbix_Monitor - NO ARGUMENTS PASSED, END SCRIPT`r`n`r`n"
      write-output "$($strLineSeparator)`r`n$($(get-date)) - Zabbix_Monitor - NO ARGUMENTS PASSED, END SCRIPT`r`n"
    }
    2 {
      #'ERRRET'=2 - END SCRIPT
      $script:blnBREAK = $true
      $script:diag += "`r`n$($strLineSeparator)`r`n$($(get-date)) - Zabbix_Monitor - ($($strModule)) :"
      $script:diag += "`r`n$($strLineSeparator)`r`n`t$($strErr), END SCRIPT`r`n`r`n"
      write-output "$($strLineSeparator)`r`n$($(get-date)) - Zabbix_Monitor - ($($strModule)) :"
      write-output "$($strLineSeparator)`r`n`t$($strErr), END SCRIPT`r`n`r`n"
    }
    3 {
      #'ERRRET'=3
      $script:blnWARN = $false
      $script:diag += "`r`n$($strLineSeparator)`r`n$($(get-date)) - Zabbix_Monitor - $($strModule) :"
      $script:diag += "`r`n$($strLineSeparator)`r`n`t$($strErr)"
      write-output "$($strLineSeparator)`r`n$($(get-date)) - Zabbix_Monitor - $($strModule) :"
      write-output "$($strLineSeparator)`r`n`t$($strErr)"
    }
    default {
      #'ERRRET'=4+
      $script:blnBREAK = $false
      $script:diag += "`r`n$($strLineSeparator)`r`n$($(get-date)) - Zabbix_Monitor - $($strModule) :"
      $script:diag += "`r`n$($strLineSeparator)`r`n`t$($strErr)"
      write-output "$($strLineSeparator)`r`n$($(get-date)) - Zabbix_Monitor - $($strModule) :"
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
}

function run-Download {
  logERR 3 "Starting deploy"
  $pkg = "C:\IT\Zabbix_Agent_2.msi"
  $taskdiag = "Downloading and Deploying Zabbix 2`r`n$($strLineSeparator)"
  logERR 3 "Downloading Zabbix" "Line 88 - $($taskdiag)"
  try { Invoke-WebRequest -uri "$($zabbixDownload)" -OutFile "$($pkg)" } catch {
    $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
    $taskdiag = "Failed to Download Zabbix 2`r`n$($strLineSeparator)"
    logERR 2 "run-Download" "Line 92 - $($taskdiag)`r`n$($err)`r`n$($strLineSeparator)"
  }
}

function run-Deploy {
  try {
    $params = "/l*v $($logFile) "
    $params += "HOSTNAME=`"$($script:dattoCustomerName) - $($script:hostname)`" LISTENPORT=10050 ENABLEPATH=1 "
    #$params += "HOSTMETADATA=windows"
    $params += "SERVER=$($script:serverHostnameOrIP) SERVERACTIVE=$($script:serverHostnameOrIP) INSTALLFOLDER=`"$($installFolder)`" "
    $params += "TLSCONNECT=psk TLSACCEPT=psk TLSPSKIDENTITY=$($script:pskID) TLSPSKVALUE=$($script:pskValue) /qn"
    $taskdiag = Start-Process -FilePath $pkg -ArgumentList "$($params)" -PassThru -Wait
  } catch {
    $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
    $taskdiag += "`r`nFailed to Install Zabbix 2`r`n$($strLineSeparator)"
    logERR 2 "run-Deploy" "Line 106 - $($taskdiag)`r`n$($err)`r`n$($strLineSeparator)"
  }
  Start-Sleep -seconds 30
}

function run-Remove {
  $taskdiag += "`r`nRemoving Zabbix`r`n$($strLineSeparator)"
  logERR 3 "run-Remove" "Line 135 - $($taskdiag)"
  $regPath = get-itemproperty -path 'HKLM:\SOFTWARE\Zabbix SIA\Zabbix Agent 2 (64-bit)' -name 'ProductCode'
  $regPath.ProductCode
  Start-Process -FilePath "C:\Windows\system32\msiexec.exe" -ArgumentList "/x $($regPath.ProductCode) /qn" -PassThru -Wait
  rm $installFolder -Recurse -Force
}

function run-Monitor {
  if ($($script:zabbixInstalled.Status) -eq "Stopped") {
    $taskdiag = "Warning! Service is not started : `r`nAttempting to start`r`n$($strLineSeparator)"
    logERR 3 "Monitor Mode" "Line 153 - $($taskdiag)"
    try {Start-Service -Name $($script:zabbixInstalled.Name)} catch {
      $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
      $taskdiag += "`r`nFailed to Start Zabbix Service`r`n$($strLineSeparator)"
      logERR 2 "Monitor Mode" "Line 157 - $($taskdiag)`r`n$($err)`r`n$($strLineSeparator)"
    }
    #& "c:\IT\Zabbix\zabbix_agent2.exe -c c:\IT\Zabbix\zabbix_agent2.conf -i"
  }
  if ($($script:zabbixInstalled.Status) -eq "Running") { 
    $taskdiag = "$($script:zabbixInstalled.Name) is started : `r`nAttempting to start`r`n$($strLineSeparator)"
    logERR 3 "Monitor Mode" "Line 163 - $($taskdiag)" 
    
  }
  $taskdiag = "Begin Verification of Correct Configuration : `r`n$($strLineSeparator)"
  logERR 3 "Monitor Mode" "Line 166 - $($taskdiag)" 
  <#If ($params) {
    
  }#>
}
#endregion - FUNCTIONS

#region - SCRIPT
$ScrptStartTime = (get-date -format "yyyy-MM-dd HH:mm:ss").ToString()
$script:sw = [Diagnostics.Stopwatch]::StartNew()
dir-Check
switch ($script:mode) {
  "Deploy" {
    $taskdiag = "Downloading Zabbix 2`r`n$($strLineSeparator)"
    logERR 3 "run-Download" "Line 168 - $($taskdiag)"
    run-Download
    $taskdiag = "Deploying Zabbix 2`r`n$($strLineSeparator)"
    logERR 3 "run-Deploy" "Line 171 - $($taskdiag)"
    run-Deploy
    $script:zabbixInstalled = Get-Service "Zabbix Agent 2" 
    Restart-Service -Name $($script:zabbixInstalled.Name)
    if ($($script:zabbixInstalled.Status) -eq "Stopped") {
      $taskdiag = "Warning! Service is not started : `r`nAttempting to start`r`n$($strLineSeparator)"
      logERR 3 "Deploy Mode" "Line 177 - $($taskdiag)"
      #Write-Warning "Service is not started : `r`n Attempting to start"
      Start-Service -Name $($script:zabbixInstalled.Name)
      #& "c:\IT\Zabbix\zabbix_agent2.exe -c c:\IT\Zabbix\zabbix_agent2.conf -i"
    }
    if ($($script:zabbixInstalled.Status) -eq "Running") { Write-Output "Zabbix is running" }
    $strOUT = $taskdiag
    write-DRMMAlert "$($strOUT)"
    write-DRMMDiag "$($strOUT)`r`n$($strModule)`r`n$($strErr)"
  }
  "Remove" {
    run-Remove
    $strOUT = $taskdiag
    write-DRMMAlert "$($strOUT)"
    write-DRMMDiag "$($strOUT)`r`n$($strModule)`r`n$($strErr)"
  }
  "Upgrade" {
    run-Remove -wait
    Start-Sleep -Seconds 2
    run-Download -wait
    run-Deploy
    $strOUT = $taskdiag
    write-DRMMAlert "$($strOUT)"
    write-DRMMDiag "$($strOUT)`r`n$($strModule)`r`n$($strErr)"
  }
  "Monitor" {
    dir-Check
    if (-not (test-path -path "C:\IT\Zabbix")) { 
      $taskdiag = "No C:\IT\Zabbix dir Means that Zabbix was not Installed Correctly : Rerunning Download/Deploy`r`n$($strLineSeparator)"
      logERR 3 "Monitor Mode" "Line 213 - $($taskdiag)"
      run-Download
      run-Deploy 
    }
    run-Monitor
    $strOUT = $taskdiag
    write-DRMMAlert "$($strOUT)"
    write-DRMMDiag "$($strOUT)`r`n$($strModule)`r`n$($strErr)"
  }
}
#endregion - SCRIPT
#check if dir is there, if service is there, check config file and make sure the hostname string and server string match our expectates.
