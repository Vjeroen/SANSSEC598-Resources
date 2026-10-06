<#
.SYNOPSIS
    SEC598 Lab 2.5 - Full parallel Atomic chain using PowerShell 7 parallel orchestration.

.DESCRIPTION
    Executes the Lab 2.5 data-dependent discovery/lateral-movement chain on two
    Windows endpoints in parallel using PowerShell 7 parallel orchestration and PSRemoting.

    Each remote endpoint writes its OWN evidence locally to:

        C:\Users\sec598admin\Desktop\lab25-results\parallel\<HOSTNAME>\

    Evidence filenames:
        parallel-chain_<timestamp>.json
        parallel-chain_<timestamp>.txt
        parallel-context_<timestamp>.json

    The parallel-chain JSON is deliberately a FLAT ARRAY of technique-result rows
    so the workbook comparison code can load it directly and search these fields:

        TechniqueId
        TestNumbers
        Detail
        Ok
        Captured

    Chain:
        T1082#1
        T1033#1
        T1016#1
        T1049#1
        T1057#1
        T1057#6
        T1018#16
        T1135#4
        T1021.002#1
        T1570       (native SMB marker copy)
        T1021.006   (native WinRM / Invoke-Command)
        T1047       (native CIM remote process)

.NOTES
    Requires PowerShell 7 on the orchestrator. Remote endpoints default to the
    existing Microsoft.PowerShell configuration (Windows PowerShell 5.1).
    Use -ConfigurationName PowerShell.7 for registered PowerShell 7 endpoints.

    Classroom/lab use only. Uses the explicitly supplied lab credential.
    No credential dumping, Pass-the-Hash, LSASS access, or Mimikatz.

.EXAMPLE
    . .\Invoke-ParallelAtomicWorkflow-Full.ps1

    $cred = Get-Credential -UserName 'sec598admin'

    Invoke-Lab25ParallelChain `
        -ComputerNames @('192.168.10.10','192.168.10.12') `
        -Credential $cred
#>

#requires -Version 7.0
function Invoke-Lab25ParallelChain {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateCount(2,2)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerNames,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential,

        # Literal default is required by the PowerShell 7 parallel orchestration parser.
        [string]$ResultsRoot = 'C:\Users\sec598admin\Desktop\lab25-results',

        [string]$AtomicModule = 'C:\AtomicRedTeam\invoke-atomicredteam\Invoke-AtomicRedTeam.psd1',

        [ValidateSet('IPC$','C$','ADMIN$')]
        [string]$ShareName = 'IPC$',

        [switch]$SkipAtomic,

        [ValidateRange(1,32)]
        [int]$ThrottleLimit = 2,

        [ValidateNotNullOrEmpty()]
        [string]$ConfigurationName = 'Microsoft.PowerShell',

        [switch]$SkipPivot
    )

    if ($ComputerNames[0] -eq $ComputerNames[1]) {
        throw 'Supply exactly two distinct ComputerNames.'
    }
    $ComputerNames | ForEach-Object -Parallel {
        $Computer = $_
        $Options = @{
            Target = $Computer
            AllTargets = @($using:ComputerNames)
            Cred = $using:Credential
            ResultsRoot = $using:ResultsRoot
            AtomicModule = $using:AtomicModule
            ShareName = $using:ShareName
            SkipAtomic = [bool]$using:SkipAtomic
            SkipPivot = [bool]$using:SkipPivot
            ConfigurationName = $using:ConfigurationName
        }
        try {
        Invoke-Command -ComputerName $Computer -Credential $using:Credential `
            -ConfigurationName $using:ConfigurationName -ArgumentList $Options -ErrorAction Stop -ScriptBlock {
            param($Options)
            $Target = $Options.Target
            $AllTargets = @($Options.AllTargets)
            $Cred = $Options.Cred
            $ResultsRoot = $Options.ResultsRoot
            $AtomicModule = $Options.AtomicModule
            $ShareName = $Options.ShareName
            $SkipAtomic = $Options.SkipAtomic
            $SkipPivot = $Options.SkipPivot
            $ConfigurationName = $Options.ConfigurationName
            $HostName = $env:COMPUTERNAME
            $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

            # Pick the other configured target as this host's peer.
            $PeerHost = $AllTargets |
                Where-Object { $_ -ne $Target } |
                Select-Object -First 1

            if (-not $PeerHost) {
                throw "Unable to determine peer host for $Target. Supply exactly two ComputerNames."
            }

            # Remote evidence MUST match the paths used by the workbook collection steps.
            $ParallelRoot = Join-Path $ResultsRoot 'parallel'
            $HostDir      = Join-Path $ParallelRoot $HostName

            # Ensure the complete evidence folder structure exists on the REMOTE endpoint.
            foreach ($PathToCreate in @($ResultsRoot, $ParallelRoot, $HostDir)) {
                if (-not (Test-Path -LiteralPath $PathToCreate)) {
                    $null = New-Item `
                        -ItemType Directory `
                        -Path $PathToCreate `
                        -Force `
                        -ErrorAction Stop
                }
            }

            if (-not (Test-Path -LiteralPath $HostDir)) {
                throw "Failed to create remote evidence directory: $HostDir"
            }

            Write-Host ("[{0}] Evidence directory ready: {1}" -f $HostName, $HostDir)

            $LogPath  = Join-Path $HostDir ("parallel-chain_{0}.txt" -f $Stamp)
            $JsonPath = Join-Path $HostDir ("parallel-chain_{0}.json" -f $Stamp)
            $CtxPath  = Join-Path $HostDir ("parallel-context_{0}.json" -f $Stamp)
            $ResPath  = Join-Path $HostDir ("atomic-res_{0}.txt" -f $Stamp)

            $Ctx = [ordered]@{
                Target        = $Target
                Hostname      = $HostName
                PeerHost      = $PeerHost
                Domain        = $env:USERDOMAIN
                DnsDomain     = $env:USERDNSDOMAIN
                User          = $null
                OsCaption     = $null
                PrimaryIPv4   = $null
                Subnet24      = $null
                RemoteIps     = @()
                OwningPids    = @()
                ProcessNames  = @()
                Computers     = @()
                ShareLines    = @()
                MappedRoot    = $null
                MarkerRemote  = $null
                WinRmOk       = $false
                CimRemoteOk   = $false
                AtomicReady   = $false
                Started       = (Get-Date).ToString('o')
                Ended         = $null
            }

            $StepResults = New-Object System.Collections.Generic.List[object]

            function Write-LabLog {
                param([string]$Message)

                $line = '[{0}] [{1}] {2}' -f (Get-Date -Format o), $HostName, $Message
                Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
                Write-Host $line
            }

            function Add-StepResult {
                param(
                    [string]$TechniqueId,
                    [int[]]$TestNumbers,
                    [bool]$Ok,
                    [string]$Detail,
                    $Captured
                )

                $StepResults.Add([pscustomobject]@{
                    TechniqueId = $TechniqueId
                    TestNumbers = if ($TestNumbers -and $TestNumbers.Count -gt 0) {
                        ($TestNumbers -join ',')
                    }
                    else {
                        ''
                    }
                    Hostname    = $HostName
                    Target      = $Target
                    PeerHost    = $PeerHost
                    Detail      = $Detail
                    Ok          = [bool]$Ok
                    Captured    = $Captured
                    Ended       = (Get-Date).ToString('o')
                }) | Out-Null

                Write-LabLog ("RESULT {0}#{1} Detail={2} Ok={3}" -f `
                    $TechniqueId,
                    ($(if ($TestNumbers) { $TestNumbers -join ',' } else { '-' })),
                    $Detail,
                    $Ok)
            }

            function Get-AtomicReady {
                if ($SkipAtomic) {
                    return $false
                }

                if (Get-Command Invoke-AtomicTest -ErrorAction SilentlyContinue) {
                    return $true
                }

                if (Test-Path -LiteralPath $AtomicModule) {
                    try {
                        Import-Module $AtomicModule -Scope Global -Force -ErrorAction Stop
                        return [bool](Get-Command Invoke-AtomicTest -ErrorAction SilentlyContinue)
                    }
                    catch {
                        Write-LabLog ("Atomic module import failed: {0}" -f $_.Exception.Message)
                        return $false
                    }
                }

                Write-LabLog ("Atomic module not found: {0}" -f $AtomicModule)
                return $false
            }

            function Invoke-AtomicToRes {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$TechniqueId,

                    [Parameter(Mandatory = $true)]
                    [int[]]$TestNumbers,

                    [hashtable]$InputArgs = $null
                )

                if (-not $Ctx.AtomicReady) {
                    throw 'Invoke-AtomicTest not available'
                }

                Write-LabLog ("Atomic START {0} test(s) {1}" -f $TechniqueId, ($TestNumbers -join ','))

                if ($InputArgs) {
                    Write-LabLog ("Atomic input keys: {0}" -f ($InputArgs.Keys -join ','))
                    Invoke-AtomicTest `
                        -AtomicTechnique $TechniqueId `
                        -TestNumbers $TestNumbers `
                        -InputArgs $InputArgs -ErrorAction Stop *>&1 |
                        Tee-Object -FilePath $ResPath |
                        ForEach-Object {
                            Write-Host ("[{0}] {1}" -f $HostName, $_)
                        }
                }
                else {
                    Invoke-AtomicTest `
                        -AtomicTechnique $TechniqueId `
                        -TestNumbers $TestNumbers -ErrorAction Stop *>&1 |
                        Tee-Object -FilePath $ResPath |
                        ForEach-Object {
                            Write-Host ("[{0}] {1}" -f $HostName, $_)
                        }
                }

                Write-LabLog ("Atomic END {0} test(s) {1}" -f $TechniqueId, ($TestNumbers -join ','))
            }

            function Get-ResText {
                if (-not (Test-Path -LiteralPath $ResPath)) {
                    return ''
                }

                return (Get-Content -LiteralPath $ResPath -Raw -ErrorAction SilentlyContinue)
            }

            Write-LabLog ("=== SEC598 Lab 2.5 parallel chain START target={0} peer={1} ===" -f $Target, $PeerHost)

            $Ctx.AtomicReady = Get-AtomicReady
            Write-LabLog ("AtomicReady={0}" -f $Ctx.AtomicReady)

            # -----------------------------------------------------------------
            # T1082#1 - System Information Discovery
            # -----------------------------------------------------------------
            try {
                if ($Ctx.AtomicReady) {
                    Invoke-AtomicToRes -TechniqueId 'T1082' -TestNumbers @(1)

                    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                    $Ctx.OsCaption = $os.Caption

                    $captured = [ordered]@{
                        Hostname    = $HostName
                        Domain      = $env:USERDOMAIN
                        DnsDomain   = $env:USERDNSDOMAIN
                        OsCaption   = $os.Caption
                        Version     = $os.Version
                        BuildNumber = $os.BuildNumber
                    }

                    Add-StepResult 'T1082' @(1) $true 'atomic_ok' $captured
                }
                else {
                    throw 'Atomic unavailable'
                }
            }
            catch {
                try {
                    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                    $Ctx.OsCaption = $os.Caption

                    Add-StepResult 'T1082' @(1) $true 'native_fallback' ([ordered]@{
                        Hostname    = $HostName
                        Domain      = $env:USERDOMAIN
                        DnsDomain   = $env:USERDNSDOMAIN
                        OsCaption   = $os.Caption
                        Version     = $os.Version
                        BuildNumber = $os.BuildNumber
                    })
                }
                catch {
                    Add-StepResult 'T1082' @(1) $false $_.Exception.Message $null
                }
            }

            # -----------------------------------------------------------------
            # T1033#1 - System Owner/User Discovery
            # -----------------------------------------------------------------
            try {
                if ($Ctx.AtomicReady) {
                    Invoke-AtomicToRes -TechniqueId 'T1033' -TestNumbers @(1)
                    $Ctx.User = (whoami).Trim()
                    Add-StepResult 'T1033' @(1) $true 'atomic_ok' ([ordered]@{ User = $Ctx.User })
                }
                else {
                    throw 'Atomic unavailable'
                }
            }
            catch {
                try {
                    $Ctx.User = (whoami).Trim()
                    Add-StepResult 'T1033' @(1) $true 'native_fallback' ([ordered]@{ User = $Ctx.User })
                }
                catch {
                    Add-StepResult 'T1033' @(1) $false $_.Exception.Message $null
                }
            }

            # -----------------------------------------------------------------
            # T1016#1 - System Network Configuration Discovery
            # -----------------------------------------------------------------
            try {
                if ($Ctx.AtomicReady) {
                    Invoke-AtomicToRes -TechniqueId 'T1016' -TestNumbers @(1)
                }
                else {
                    throw 'Atomic unavailable'
                }

                $ips = @(
                    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.IPAddress -notlike '127.*' -and
                        $_.IPAddress -notlike '169.254.*'
                    } |
                    Sort-Object InterfaceMetric
                )

                if ($ips.Count -gt 0) {
                    $Ctx.PrimaryIPv4 = $ips[0].IPAddress
                    $octets = $Ctx.PrimaryIPv4.Split('.')
                    if ($octets.Count -eq 4) {
                        $Ctx.Subnet24 = '{0}.{1}.{2}' -f $octets[0],$octets[1],$octets[2]
                    }
                }

                Add-StepResult 'T1016' @(1) $true 'atomic_ok' ([ordered]@{
                    PrimaryIPv4 = $Ctx.PrimaryIPv4
                    Subnet24    = $Ctx.Subnet24
                    Interfaces  = @($ips | Select-Object InterfaceAlias,IPAddress,PrefixLength)
                })
            }
            catch {
                try {
                    $ips = @(
                        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                        Where-Object {
                            $_.IPAddress -notlike '127.*' -and
                            $_.IPAddress -notlike '169.254.*'
                        } |
                        Sort-Object InterfaceMetric
                    )

                    if ($ips.Count -gt 0) {
                        $Ctx.PrimaryIPv4 = $ips[0].IPAddress
                        $octets = $Ctx.PrimaryIPv4.Split('.')
                        if ($octets.Count -eq 4) {
                            $Ctx.Subnet24 = '{0}.{1}.{2}' -f $octets[0],$octets[1],$octets[2]
                        }
                    }

                    Add-StepResult 'T1016' @(1) $true 'native_fallback' ([ordered]@{
                        PrimaryIPv4 = $Ctx.PrimaryIPv4
                        Subnet24    = $Ctx.Subnet24
                        Interfaces  = @($ips | Select-Object InterfaceAlias,IPAddress,PrefixLength)
                    })
                }
                catch {
                    Add-StepResult 'T1016' @(1) $false $_.Exception.Message $null
                }
            }

            # -----------------------------------------------------------------
            # T1049#1 - System Network Connections Discovery
            # -----------------------------------------------------------------
            try {
                if ($Ctx.AtomicReady) {
                    Invoke-AtomicToRes -TechniqueId 'T1049' -TestNumbers @(1)
                }
                else {
                    throw 'Atomic unavailable'
                }

                $netstat = @(netstat -ano)
                $ipsFound = New-Object System.Collections.Generic.List[string]
                $pidsFound = New-Object System.Collections.Generic.List[int]

                foreach ($line in $netstat) {
                    if ($line -match 'TCP\s+\S+\s+(\d+\.\d+\.\d+\.\d+):\d+\s+(\S+)\s+(\d+)') {
                        $remoteIp = $Matches[1]
                        $state = $Matches[2]
                        $pidValue = [int]$Matches[3]

                        if ($remoteIp -ne '0.0.0.0' -and
                            $remoteIp -ne '127.0.0.1' -and
                            $state -match 'ESTABLISHED|CLOSE_WAIT|SYN_SENT') {

                            if (-not $ipsFound.Contains($remoteIp)) {
                                $ipsFound.Add($remoteIp)
                            }
                        }

                        if ($pidValue -gt 0 -and
                            -not $pidsFound.Contains($pidValue) -and
                            $pidsFound.Count -lt 12) {

                            $pidsFound.Add($pidValue)
                        }
                    }
                }

                $Ctx.RemoteIps  = @($ipsFound | Select-Object -First 8)
                $Ctx.OwningPids = @($pidsFound | Select-Object -First 10)

                Add-StepResult 'T1049' @(1) $true 'atomic_ok' ([ordered]@{
                    RemoteIps  = $Ctx.RemoteIps
                    OwningPids = $Ctx.OwningPids
                })
            }
            catch {
                try {
                    $netstat = @(netstat -ano)
                    $Ctx.RemoteIps = @()
                    $Ctx.OwningPids = @()

                    Add-StepResult 'T1049' @(1) $true 'native_fallback' ([ordered]@{
                        Output = @($netstat | Select-Object -First 40)
                    })
                }
                catch {
                    Add-StepResult 'T1049' @(1) $false $_.Exception.Message $null
                }
            }

            # -----------------------------------------------------------------
            # T1057#1 - Process Discovery
            # -----------------------------------------------------------------
            try {
                if ($Ctx.AtomicReady) {
                    Invoke-AtomicToRes -TechniqueId 'T1057' -TestNumbers @(1)
                }
                else {
                    throw 'Atomic unavailable'
                }

                $names = New-Object System.Collections.Generic.List[string]

                if ($Ctx.OwningPids.Count -gt 0) {
                    Get-Process -Id $Ctx.OwningPids -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        if (-not $names.Contains($_.ProcessName)) {
                            $names.Add($_.ProcessName)
                        }
                    }
                }

                if ($names.Count -eq 0) {
                    Get-Process -ErrorAction SilentlyContinue |
                    Select-Object -First 10 |
                    ForEach-Object {
                        if (-not $names.Contains($_.ProcessName)) {
                            $names.Add($_.ProcessName)
                        }
                    }
                }

                $Ctx.ProcessNames = @($names | Select-Object -First 10)

                Add-StepResult 'T1057' @(1) $true 'atomic_ok' ([ordered]@{
                    ProcessNames = $Ctx.ProcessNames
                    SourcePids   = $Ctx.OwningPids
                })
            }
            catch {
                try {
                    $processes = @(Get-Process -ErrorAction Stop | Select-Object -First 10 Id,ProcessName)
                    $Ctx.ProcessNames = @($processes | Select-Object -ExpandProperty ProcessName)

                    Add-StepResult 'T1057' @(1) $true 'native_fallback' ([ordered]@{
                        Processes = $processes
                    })
                }
                catch {
                    Add-StepResult 'T1057' @(1) $false $_.Exception.Message $null
                }
            }

            # -----------------------------------------------------------------
            # T1057#6 - Process Discovery using a value from T1057#1/T1049
            # -----------------------------------------------------------------
            if ($Ctx.ProcessNames.Count -gt 0) {
                $ProcessToEnumerate = $Ctx.ProcessNames[0]

                try {
                    if ($Ctx.AtomicReady) {
                        Invoke-AtomicToRes `
                            -TechniqueId 'T1057' `
                            -TestNumbers @(6) `
                            -InputArgs @{ process_to_enumerate = $ProcessToEnumerate }

                        Add-StepResult 'T1057' @(6) $true 'atomic_ok' ([ordered]@{
                            process_to_enumerate = $ProcessToEnumerate
                        })
                    }
                    else {
                        throw 'Atomic unavailable'
                    }
                }
                catch {
                    try {
                        $p = Get-Process -Name $ProcessToEnumerate -ErrorAction SilentlyContinue |
                            Select-Object -First 5 Id,ProcessName

                        Add-StepResult 'T1057' @(6) $true 'native_fallback' ([ordered]@{
                            process_to_enumerate = $ProcessToEnumerate
                            Processes            = @($p)
                        })
                    }
                    catch {
                        Add-StepResult 'T1057' @(6) $false $_.Exception.Message $null
                    }
                }
            }
            else {
                Add-StepResult 'T1057' @(6) $false 'no_process_input' $null
            }

            if (-not $SkipPivot) {

                # -------------------------------------------------------------
                # T1018#16 - Remote System Discovery
                # -------------------------------------------------------------
                try {
                    if ($Ctx.AtomicReady) {
                        Invoke-AtomicToRes -TechniqueId 'T1018' -TestNumbers @(16)
                    }
                    else {
                        throw 'Atomic unavailable'
                    }

                    # Prefer deterministic classroom peer while still retaining
                    # discovered domain computers in the evidence.
                    $computers = @()

                    try {
                        $searcher = [adsisearcher]'(objectCategory=computer)'
                        $searcher.PropertiesToLoad.Add('name') | Out-Null

                        $computers = @(
                            $searcher.FindAll() |
                            ForEach-Object {
                                $n = $_.Properties['name']
                                if ($n) { $n[0] }
                            }
                        )
                    }
                    catch {
                        # Keep the configured configured peer if AD enumeration is unavailable.
                    }

                    if ($computers -notcontains $PeerHost) {
                        $computers += $PeerHost
                    }

                    $Ctx.Computers = @($computers | Select-Object -Unique)

                    Add-StepResult 'T1018' @(16) $true 'atomic_ok' ([ordered]@{
                        Computers = $Ctx.Computers
                        PeerHost  = $PeerHost
                    })
                }
                catch {
                    try {
                        $Ctx.Computers = @($PeerHost)

                        Add-StepResult 'T1018' @(16) $true 'native_fallback' ([ordered]@{
                            Computers = $Ctx.Computers
                            PeerHost  = $PeerHost
                        })
                    }
                    catch {
                        Add-StepResult 'T1018' @(16) $false $_.Exception.Message $null
                    }
                }

                # -------------------------------------------------------------
                # T1135#4 - Network Share Discovery against peer
                # -------------------------------------------------------------
                try {
                    if ($Ctx.AtomicReady) {
                        Invoke-AtomicToRes `
                            -TechniqueId 'T1135' `
                            -TestNumbers @(4) `
                            -InputArgs @{ computer_name = $PeerHost }

                        $shareOutput = @(net.exe view ("\\{0}" -f $PeerHost) 2>&1)
                        if ($LASTEXITCODE -ne 0) { throw ("net view failed ({0}): {1}" -f $LASTEXITCODE, ($shareOutput -join " ")) }
                        $Ctx.ShareLines = @($shareOutput | Select-Object -First 20)

                        Add-StepResult 'T1135' @(4) $true 'atomic_ok' ([ordered]@{
                            PeerHost   = $PeerHost
                            ShareLines = $Ctx.ShareLines
                        })
                    }
                    else {
                        throw 'Atomic unavailable'
                    }
                }
                catch {
                    try {
                        $shareOutput = @(net.exe view ("\\{0}" -f $PeerHost) 2>&1)
                        if ($LASTEXITCODE -ne 0) { throw ("net view failed ({0}): {1}" -f $LASTEXITCODE, ($shareOutput -join " ")) }
                        $Ctx.ShareLines = @($shareOutput | Select-Object -First 20)

                        Add-StepResult 'T1135' @(4) $true 'native_fallback' ([ordered]@{
                            PeerHost   = $PeerHost
                            ShareLines = $Ctx.ShareLines
                        })
                    }
                    catch {
                        Add-StepResult 'T1135' @(4) $false $_.Exception.Message $null
                    }
                }

                # Pull the explicit lab credential for the classroom-only
                # authentication steps below.
                try {
                    $DomainUser = $Cred.UserName
                    $LabPassword = $Cred.GetNetworkCredential().Password
                }
                catch {
                    $DomainUser = $null
                    $LabPassword = $null
                    Write-LabLog ("Unable to unwrap supplied PSCredential: {0}" -f $_.Exception.Message)
                }

                # -------------------------------------------------------------
                # T1021.002#1 - SMB/Windows Admin Share using supplied credential
                # -------------------------------------------------------------
                if ($DomainUser -and $LabPassword) {
                    try {
                        if ($Ctx.AtomicReady) {
                            $SmbArgs = @{
                                computer_name = $PeerHost
                                share_name    = $ShareName
                                user_name     = $DomainUser
                                password      = $LabPassword
                            }

                            Invoke-AtomicToRes `
                                -TechniqueId 'T1021.002' `
                                -TestNumbers @(1) `
                                -InputArgs $SmbArgs


                            $Ctx.MappedRoot = '\\{0}\{1}' -f $PeerHost,$ShareName

                            Add-StepResult 'T1021.002' @(1) $true 'atomic_ok' ([ordered]@{
                                PeerHost   = $PeerHost
                                MappedRoot = $Ctx.MappedRoot
                                User       = $DomainUser
                            })
                        }
                        else {
                            throw 'Atomic unavailable'
                        }
                    }
                    catch {
                        try {
                            $mapOutput = @(net.exe use ("\\{0}\{1}" -f $PeerHost,$ShareName) $LabPassword ("/user:{0}" -f $DomainUser) 2>&1)

                            if ($LASTEXITCODE -ne 0) { throw ("net use failed ({0})" -f $LASTEXITCODE) }
                            $Ctx.MappedRoot = '\\{0}\{1}' -f $PeerHost,$ShareName

                            Add-StepResult 'T1021.002' @(1) $true 'native_fallback' ([ordered]@{
                                PeerHost   = $PeerHost
                                MappedRoot = $Ctx.MappedRoot
                                User       = $DomainUser
                                Output     = @($mapOutput)
                            })
                        }
                        catch {
                            Add-StepResult 'T1021.002' @(1) $false $_.Exception.Message $null
                        }
                    }
                }
                else {
                    Add-StepResult 'T1021.002' @(1) $false 'credential_unavailable' $null
                }

                # -------------------------------------------------------------
                # T1570 - Lateral Tool Transfer class: benign marker file
                # -------------------------------------------------------------
                if ($DomainUser -and $LabPassword) {
                    try {
                        $LocalMarker = Join-Path $env:TEMP ("lab25-marker-{0}.txt" -f $Stamp)

                        @(
                            'SEC598 Lab 2.5 lateral marker'
                            ("from_host={0}" -f $HostName)
                            ("from_user={0}" -f $Ctx.User)
                            ("from_ip={0}" -f $Ctx.PrimaryIPv4)
                            ("peer={0}" -f $PeerHost)
                            ("utc={0}" -f (Get-Date -Format o))
                        ) | Set-Content -LiteralPath $LocalMarker -Encoding ASCII

                        # IPC$ cannot store files, so use C$ for the marker copy.
                        $CopyShare = 'C$'

                        net.exe use ("\\{0}\{1}" -f $PeerHost,$CopyShare) $LabPassword ("/user:{0}" -f $DomainUser) 2>&1 | Out-Null

                        if ($LASTEXITCODE -ne 0) { throw ("Marker share authentication failed ({0})" -f $LASTEXITCODE) }
                        $RemoteFile = '\\{0}\{1}\Users\Public\lab25-marker-{2}.txt' -f `
                            $PeerHost,$CopyShare,$Stamp

                        Copy-Item `
                            -LiteralPath $LocalMarker `
                            -Destination $RemoteFile `
                            -Force `
                            -ErrorAction Stop

                        $Ctx.MarkerRemote = $RemoteFile

                        Add-StepResult 'T1570' @() $true 'smb_marker_ok' ([ordered]@{
                            MarkerRemote = $RemoteFile
                        })
                    }
                    catch {
                        Add-StepResult 'T1570' @() $false $_.Exception.Message $null
                    }
                }
                else {
                    Add-StepResult 'T1570' @() $false 'credential_unavailable' $null
                }

                # -------------------------------------------------------------
                # T1021.006 - WinRM to peer using supplied credential
                # -------------------------------------------------------------
                try {
                    $remote = Invoke-Command `
                        -ComputerName $PeerHost `
                        -Credential $Cred `
                        -ConfigurationName $ConfigurationName `
                        -ScriptBlock {
                            [pscustomobject]@{
                                Hostname = $env:COMPUTERNAME
                                User     = (whoami)
                            }
                        } `
                        -ErrorAction Stop

                    $Ctx.WinRmOk = $true

                    Add-StepResult 'T1021.006' @() $true 'winrm_ok' ([ordered]@{
                        PeerHost = $PeerHost
                        Remote   = $remote
                    })
                }
                catch {
                    Add-StepResult 'T1021.006' @() $false $_.Exception.Message $null
                }

                # -------------------------------------------------------------
                # T1047 - CIM remote process on peer, then terminate it
                # -------------------------------------------------------------
                try {
                    $CimSession = $null
                    $CimOption = New-CimSessionOption -Protocol Dcom

                    $CimSession = New-CimSession `
                        -ComputerName $PeerHost `
                        -Credential $Cred `
                        -SessionOption $CimOption `
                        -ErrorAction Stop

                    $Created = Invoke-CimMethod `
                        -CimSession $CimSession `
                        -ClassName Win32_Process `
                        -MethodName Create `
                        -Arguments @{ CommandLine = 'notepad.exe' } `
                        -ErrorAction Stop

                    if ($Created.ReturnValue -ne 0 -or -not $Created.ProcessId) {
                        throw ("Remote process creation failed ({0})" -f $Created.ReturnValue)
                    }
                    Start-Sleep -Seconds 2

                    if ($Created.ProcessId) {
                        $Terminated = Invoke-CimMethod `
                            -CimSession $CimSession `
                            -Query ("SELECT * FROM Win32_Process WHERE ProcessId={0}" -f $Created.ProcessId) `
                            -MethodName Terminate `
                            -ErrorAction Stop
                        if ($Terminated.ReturnValue -ne 0) { throw ("Remote process termination failed ({0})" -f $Terminated.ReturnValue) }
                    }

                    Remove-CimSession $CimSession
                    $CimSession = $null

                    $Ctx.CimRemoteOk = $true

                    Add-StepResult 'T1047' @() $true 'cim_ok' ([ordered]@{
                        PeerHost    = $PeerHost
                        ReturnValue = $Created.ReturnValue
                        ProcessId   = $Created.ProcessId
                    })
                }
                catch {
                    Add-StepResult 'T1047' @() $false $_.Exception.Message $null
                }
                finally {
                    if ($CimSession) { Remove-CimSession $CimSession -ErrorAction SilentlyContinue }
                }
            }
            else {
                Write-LabLog 'SkipPivot was supplied. Pivot/lateral stages were skipped.'
            }

            $Ctx.Ended = (Get-Date).ToString('o')

            # IMPORTANT: flat JSON array to match workbook comparison functions.
            ConvertTo-Json -InputObject @($StepResults.ToArray()) -Depth 8 |
                Set-Content -LiteralPath $JsonPath -Encoding UTF8

            $Ctx |
                ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath $CtxPath -Encoding UTF8

            Write-LabLog ("Evidence JSON: {0}" -f $JsonPath)
            Write-LabLog ("Context JSON : {0}" -f $CtxPath)
            Write-LabLog ("Evidence TXT : {0}" -f $LogPath)
            Write-LabLog '=== SEC598 Lab 2.5 parallel chain COMPLETE ==='

            # Return only a concise summary to the caller. Full evidence
            # remains on the endpoint in the workbook-compatible path.
            [pscustomobject]@{
                Target       = $Target
                Hostname     = $HostName
                PeerHost     = $PeerHost
                AtomicReady  = $Ctx.AtomicReady
                EvidenceJson = $JsonPath
                EvidenceText = $LogPath
                ContextJson  = $CtxPath
                TechniqueCount = $StepResults.Count
            }

        }
        }
        catch {
            Write-Error -Message ("Target {0}: {1}" -f $Computer, $_.Exception.Message) -ErrorAction Continue
        }
    } -ThrottleLimit $ThrottleLimit
}


