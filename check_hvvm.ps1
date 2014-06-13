# set our parameters - because NSClient doesn't support optional arguments, we use strings instead of switches
param(
    [string]$vmName = "",
    [Alias('mem')]
    [string]$checkMemory = "off",
    [Alias('net')]
    [string]$checkNet = "off"
)

$vm = get-vm $vmName

# define our variables
$nagStates = @{}
$nagExitString = ""
$memoryWarningThreshold = .85
$memoryCriticalThreshold = .9


if($checkMemory -eq "on") {
    if ($vm.DynamicMemoryEnabled) {
        # determine percentage of max memory currently allocated to the VM
        $memoryPercentUsed = $vm.MemoryAssigned/$vm.MemoryMaximum
        if($memoryPercentUsed -le $memoryWarningThreshold) {
            $nagExitString += "Memory usage out of maximum is " + ("{0:P0}" -f $memorypercentused) + ". "
            $nagStates.Set_Item("vmMem", 0)
        } elseif ($memoryPercentUsed -le $memoryCriticalThreshold) {
            $nagExitString += "Memory usage out of maximum is " + ("{0:P0}" -f $memorypercentused) + ". "
            $nagStates.Set_Item("vmMem", 1)
        } else {
            $nagExitString += "Memory usage out of maximum is " + ("{0:P0}" -f $memorypercentused) + ". "
            $nagStates.Set_Item("vmMem", 2)
        }
    } else {
        # if dynamic memory isn't in use, report back with unknown - this check shouldn't be used without dynamic memory
        $nagExitString += "VM is not using dynamic memory. "
        $nagStates.Set_Item("vmMem", 3)
    }
}

if($checkNet -eq "on") {
    $netNotOkay = $False
    $vm | Get-VMNetworkAdapter | ForEach-Object {
        if($_.Status -ne "Ok") {
            $nagExitString += "Network status not okay for $($_.SwitchName). "
            $netNotOkay = $True
            $nagStates.Set_Item("vmNet", 2)
        }
    }
    if(!$netNotOkay) {
        $nagExitString += "All network adapters are okay. "
        $nagStates.Set_Item("vmNet", 0)
    }
}

# output our status message for Nagios
write-host $nagExitString

# evaluate our nagStates hash table and define our exit code
if ($nagStates.values -eq 2) { exit 2 }
elseif ($nagStates.values -eq 1) { exit 1 }
else { exit 0 }