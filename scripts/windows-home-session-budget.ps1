# All times are absolute UTC Unix milliseconds; reserve45minutes before host cutoff.
function Get-WindowsHomeAdmissionDeadline {
 [CmdletBinding()]
 param([Parameter(Mandatory)][long]$NowMs,[Parameter(Mandatory)][long]$HostStopMs)
 $deadline=$HostStopMs-45*60*1000L
 if($NowMs -lt 0 -or $deadline -le $NowMs){throw 'Insufficient verified host time for a new publication.'}
 $deadline
}
