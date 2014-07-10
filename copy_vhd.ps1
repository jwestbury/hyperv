param(
    [Alias('f')]
    [switch]$force,
    [Alias('p')]
    [string]$path = "\\path\to\server",
#    [Alias('vm')]
#    [string]$vmName,
    [Alias('vm')]
    $vmList = (""),
    [Alias('cp')]
    [string]$copyPath
)

if(!([System.Diagnostics.EventLog]::Exists("Scripts"))) {
    New-EventLog -LogName Scripts -Source VMBackup
} elseif (![System.Diagnostics.EventLog]::SourceExists("VMBackup")) {
    New-EventLog -LogName Scripts -Source VMBackup
}

#assign variables
$backupDir = $path;

write-host "Running VM backup utility";

foreach ($vmName in $vmList) {
    Write-EventLog -LogName Scripts -Source VMBackup -EntryType Information -EventId 2000 -Message "Backup job started for $vmName";

    Get-Job | Remove-Job; #if there are any leftover background jobs from a previous loop or previous instance of this script, remove them, or things will get very confusing very fast

    $vmName = Get-VM -name $vmName | Select -ExpandProperty Name; #this is kind of a dirty hack to capitalize the VM name properly for logging
    $vmObject = Get-VM -name $vmName;

    write-host "Current working VM: $vmName"; #our write-host commands won't ever be seen while running this as a scheduled task, but are useful for debugging and troubleshooting

    write-host "Testing VM export path.";
    
    if(!(test-path "$backupDir\$vmName")) { #check to see if we've already got a backup directory; if not...
        write-host "$backupDir\$vmName not found, creating . . . " -NoNewline; #...we make one.
   
        if(mkdir "$backupDir\$vmName") {
            Write-EventLog -LogName Scripts -Source VMBackup -EntryType Information -EventId 2203 -Message "Could not find $backupDir\$vnmame. Created.";
            write-host "created!";
        } else {
            Write-EventLog -LogName Scripts -Source VMBackup -EntryType Error -EventId 2215 -Message "Could not find $backupDir\$vnmame. Failed to create.";
            write-host "failed.";
            continue; #if we can't create the directory, skip to the next VM
        }
    }

    write-host "Tested VM path.";
    
    #STOP VM
    write-host "Stopping $vmName . . . " -NoNewline;

    if(($vmObject | Select -ExpandProperty State) -ne "Off" -and ($vmObject | Select -ExpandProperty State) -ne "Paused") {
        #we have to use a job to be able to time this out properly
        Start-Job -name stop -ArgumentList $vmName, $force -ScriptBlock {
            $vmName = $args[0]; $force = $args[1]; #in order to get external data into the job, we have to pass it in the form of arguments
            if($force) {
                Stop-VM -Name $vmName -Force;
            } else {
                Stop-VM -Name $vmName;
            }
        }
        Wait-Job -name stop -Timeout 300; #if stopping the VM takes longer than five minutes, exit the job
        Stop-Job -name stop; #this will kill the job after the timeout; if the job times out, its state will be "Stopped," otherwise it will be "Completed"

        if((Get-VM $vmname | Select -ExpandProperty State) -eq "Off") { #if the VM is in the "Off" state
            Write-EventLog -LogName Scripts -Source VMBackup -EntryType Information -EventId 2201 -Message "$vmName stopped successfully.";
        } else {
            if ((Get-Job | where Name -eq stop | select -ExpandProperty State) -ne "Completed") { #if the VM is in the "Off" state and the job did NOT complete, then it timed out
                Write-EventLog -LogName Scripts -Source VMBackup -EntryType Error -EventId 2210 -Message "$vmName failed to stop. Timed out.";
            } else { #if the VM isn't off but the stop-vm task is completed, we need to record an error and skip to the next VM in our list
                Write-EventLog -LogName Scripts -Source VMBackup -EntryType Error -EventId 2215 -Message "$vmName failed to stop: `n`n $($error[0])";
                write-host "$vmName failed to stop, skipping to next VM.";
                continue;
            }
        }

        if ((Get-Job | where Name -eq stop | select -ExpandProperty State) -ne "Completed") { #if the VM is NOT in the "Off" state, and the job did NOT complete
            Write-EventLog -LogName Scripts -Source VMBackup -EntryType Error -EventId 2210 -Message "$vmName failed to stop. Timed out.";
        } elseif (((Get-EventLog -LogName Scripts)[0] | Select -ExpandProperty EventID) -ne "2201") { #check the most recent log entry for "Scripts" and execute this block if it's not a successful VM stop
            write-host "$vmName failed to stop, skipping to next VM.";
            continue;
        }
    } else {
        #Write-EventLog -LogName Scripts -Source VMBackup -EntryType Information -EventId 2201 -Message "$vmName already stopped.";
        write-host "$vmName is already in 'Off' state.";
    }
   
    write-host "Exporting $vmName to $backupDir\$vmName . . . " -NoNewline;

    try {
        Export-VM -Path "$backupDir\$vmName" -VM $vmObject -ErrorAction Stop;
        Write-EventLog -LogName Scripts -Source VMBackup -EntryType Information -EventId 2203 -Message "Exported $vmName to $backupDir\$vmName successfully.";
        write-host "exported.";
    }
    catch {
        Write-EventLog -LogName Scripts -Source VMBackup -EntryType Error -EventId 2213 -Message "Failed to export $vmName to $backupDir\${$vmName}: $_";
        write-host "failed.";
    }
    
    write-host "Starting $vmName . . . " -NoNewline;

    #START VM
    Start-Job -name start -ArgumentList $vmName -ScriptBlock { #same deal as before: we have to use a job to implement a timeout
        $vmName = $args[0];
        Start-VM -Name $vmName
    }
    Wait-Job -name start -Timeout 300; #if starting the VM takes longer than five minutes, exit the job
    Stop-Job -name start;

    if((Get-VM $vmname | Select -ExpandProperty State) -eq "Running") { 
        Write-EventLog -LogName Scripts -Source VMBackup -EntryType Information -EventId 2200 -Message "$vmName started successfully.";
    } else {
        if ((Get-Job | Name -eq start | select -ExpandProperty State) -ne "Completed") {
            Write-EventLog -LogName Scripts -Source VMBackup -EntryType Error -EventId 2210 -Message "$vmName failed to start. Timed out.";
        } else { #if the VM is not running and the task is completed, record an error and skip to the next VM
            Write-EventLog -LogName Scripts -Source VMBackup -EntryType Error -EventId 2215 -Message "$vmName failed to start: `n`n $($error[0])";
            write-host "$vmName failed to start, skipping to next VM.";
            continue;
        }
    }

    if($copyPath) {
        Write-Host "Copying $backupDir\$vmName to $copyPath\$vmName . . ." -NoNewline;
        try {
            Copy-Item -Path "$backupDir\$vmName" -Destination "$copyPath\$vmName" -Recurse;
            Write-EventLog -LogName Scripts -Source VMBackup -EntryType Information -EventId 2204 -Message "Copied backup from $backupDir\$vmName to $copyPath\$vmName successfully.";
            $d = Get-Item "$copyPath\$vmname";
            $d.LastWriteTime = Get-Date; #copying a file doesn't change the directory's last mod/write time, so we have to do it manually
            write-host "copied.";
        }
        catch {
            Write-EventLog -LogName Scripts -Source VMBackup -EntryType Error -EventId 2214 -Message "Failed to copy from $backupDir\$vmName to $copyPath\${$vmName}: $_";
            write-host "failed.";
        }
    }
}

write-host "No further items, exiting script";

get-job | remove-job; #clear up any orphaned jobs, just in case