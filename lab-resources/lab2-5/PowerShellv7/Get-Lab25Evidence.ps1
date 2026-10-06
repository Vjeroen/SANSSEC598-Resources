#requires -Version 7.0
#requires -Version 5.1
<#
.SYNOPSIS
Copies the latest complete evidence bundle from one endpoint without rerunning tests.
.EXAMPLE
 .\Get-Lab25Evidence.ps1 -ComputerName 192.168.10.12 -Credential $cred
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ComputerName,
    [Parameter(Mandatory)][pscredential]$Credential,
    [string]$ResultsRoot = 'C:\Users\sec598admin\Desktop\lab25-results',
    [string]$LocalResultsRoot = (Join-Path $env:USERPROFILE 'Desktop\lab25-results'),
    [string]$ConfigurationName = 'Microsoft.PowerShell'
)
$ErrorActionPreference = 'Stop'
$session = New-PSSession -ComputerName $ComputerName -Credential $Credential -ConfigurationName $ConfigurationName
try {
    $bundle = Invoke-Command -Session $session -ArgumentList $ResultsRoot -ScriptBlock {
        param($Root)
        $folder = Join-Path (Join-Path $Root 'parallel') $env:COMPUTERNAME
        $latest = Get-ChildItem -LiteralPath $folder -Filter 'parallel-chain_*.json' -File -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) { throw "No evidence JSON found in $folder" }
        $stamp = $latest.BaseName.Substring('parallel-chain_'.Length)
        $context = Join-Path $folder "parallel-context_$stamp.json"
        $log = Join-Path $folder "parallel-chain_$stamp.txt"
        foreach ($path in @($context,$log)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Incomplete evidence bundle: $path" }
        }
        $ctx = Get-Content -LiteralPath $context -Raw | ConvertFrom-Json
        if (-not $ctx.Ended) { throw 'The latest run has not completed.' }
        $files = @($latest.FullName,$context,$log)
        $res = Join-Path $folder "atomic-res_$stamp.txt"
        if (Test-Path -LiteralPath $res) { $files += $res }
        [pscustomobject]@{ Hostname = $env:COMPUTERNAME; Files = $files; JsonName = $latest.Name }
    }
    $destination = Join-Path (Join-Path $LocalResultsRoot 'parallel') ($bundle.Hostname + '-from-remote')
    $null = New-Item -ItemType Directory -Path $destination -Force
    foreach ($path in $bundle.Files) {
        Copy-Item -FromSession $session -LiteralPath $path -Destination $destination -Force
    }
    $jsonPath = Join-Path $destination $bundle.JsonName
    $data = @(Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json)
    $parsed = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    $data = @($parsed)
    if ($data.Count -eq 0 -or -not $data[0].TechniqueId) { throw "Invalid technique evidence: $jsonPath" }
    Get-Item -LiteralPath $jsonPath
}
finally { Remove-PSSession $session }
