# this script is used to check the memory usage of a given virtual machine - it is intended to be used with Nagios in tandem with custom object variables

param(
    [string]$vmName = ""
)

$vm = get-vm $vmName

if ($vm.DynamicMemoryEnabled) {
    $memoryPercentUsed = $vm.MemoryAssigned/$vm.MemoryMaximum
    if($memoryPercentUsed -le .85) {
        write-host "Memory usage out of maximum is" ("{0:P0}" -f $memorypercentused)
        exit 0
    } elseif ($memoryPercentUsed -le .9) {
        write-host "Memory usage out of maximum is" ("{0:P0}" -f $memorypercentused)
        exit 1
    } else {
        write-host "Memory usage out of maximum is" ("{0:P0}" -f $memorypercentused)
        exit 2
    }
} else {
    write-host "VM is not using dynamic memory"
    exit 3
}

write-host "Cannot determine VM status"
exit 3