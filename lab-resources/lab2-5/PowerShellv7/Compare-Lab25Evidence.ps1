#requires -Version 5.1
<#
.SYNOPSIS
Compares flat Lab 2.5 evidence arrays. Missing rows remain visibly missing.
.EXAMPLE
 .\Compare-Lab25Evidence.ps1
#>
[CmdletBinding()]
param(
    [string]$Windows01Dir = (Join-Path $env:USERPROFILE 'Desktop\lab25-results\parallel\WINDOWS01'),
    [string]$Windows02Copy = (Join-Path $env:USERPROFILE 'Desktop\lab25-results\parallel\WINDOWS02-from-remote')
)
$ErrorActionPreference = 'Stop'
function Get-LatestJsonFile {
    param([Parameter(Mandatory)][string]$Path)
    $file = Get-ChildItem -LiteralPath $Path -Filter 'parallel-chain_*.json' -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $file) { throw "No parallel-chain JSON file found in $Path. Collect the remote evidence first." }
    $file
}
function Load-TechniqueResults {
    param([Parameter(Mandatory)][string]$JsonPath)
    $raw = Get-Content -LiteralPath $JsonPath -Raw
    if (-not $raw.TrimStart().StartsWith('[')) { throw "Expected a flat JSON array: $JsonPath" }
    $parsed = $raw | ConvertFrom-Json
    $rows = @($parsed)
    foreach ($row in $rows) {
        foreach ($field in 'TechniqueId','TestNumbers','Hostname','Detail','Ok','Captured') {
            if ($row.PSObject.Properties.Name -notcontains $field) { throw "Missing $field in $JsonPath" }
        }
    }
    $rows
}
function Find-TechniqueResult {
    param([AllowEmptyCollection()][array]$Data,[string]$TechniqueId,[AllowEmptyString()][string]$TestNumbers)
    $Data | Where-Object { $_.TechniqueId -eq $TechniqueId -and [string]$_.TestNumbers -eq $TestNumbers } |
        Select-Object -First 1
}
$file01 = Get-LatestJsonFile $Windows01Dir
$file02 = Get-LatestJsonFile $Windows02Copy
$data01 = @(Load-TechniqueResults $file01.FullName)
$data02 = @(Load-TechniqueResults $file02.FullName)
foreach ($key in 'T1082#1','T1033#1','T1016#1','T1049#1','T1057#1','T1057#6','T1018#16','T1135#4','T1021.002#1','T1570#','T1021.006#','T1047#') {
    $id,$number = $key.Split('#')
    $one = Find-TechniqueResult $data01 $id $number
    $two = Find-TechniqueResult $data02 $id $number
    [pscustomobject]@{
        Technique = $key.TrimEnd('#')
        WINDOWS01_Status = if ($one) { $one.Detail } else { 'Not Found' }
        WINDOWS01_Ok = if ($one) { $one.Ok } else { $false }
        WINDOWS02_Status = if ($two) { $two.Detail } else { 'Not Found' }
        WINDOWS02_Ok = if ($two) { $two.Ok } else { $false }
    }
}
