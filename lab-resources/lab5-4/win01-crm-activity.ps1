<#
.SYNOPSIS
Runs a bounded CRM request burst from Windows01 for observation by LimaCharlie.
.DESCRIPTION
The child command line carries the first CRM request ID. Function keys are read
privately and passed only through the child environment, never command arguments.
Control starts the same observed process without contacting the CRM application.
#>
[CmdletBinding()]
param([string]$CrmUrl, [switch]$Control, [switch]$Cleanup)
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath('C:\GlobexLab\lab54-marker')
foreach ($PathToCheck in @('C:\GlobexLab', $Root)) {
    if ((Test-Path -LiteralPath $PathToCheck) -and ((Get-Item -LiteralPath $PathToCheck).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The lab directory must not be a link.'
    }
}
$Worker = Join-Path $Root 'lab54-crm-worker.ps1'
$Manifest = Join-Path $Root 'lab54-crm-owned.json'
function Assert-OwnedFile([string]$Path) {
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)) -ne $Root) { throw 'File escaped lab directory.' }
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Expected a regular lab file.' }
    }
}
Assert-OwnedFile $Worker
Assert-OwnedFile $Manifest
if ($Cleanup) {
    if (-not (Test-Path -LiteralPath $Manifest)) { Write-Host 'No owned CRM activity files recorded.'; return }
    $owned = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    if ($owned.ProcessId) {
        $running = Get-Process -Id ([int]$owned.ProcessId) -ErrorAction SilentlyContinue
        if ($running -and $running.StartTime.ToUniversalTime().ToString('o') -eq $owned.StartTimeUtc) {
            throw 'Wait for the recorded CRM worker to finish before cleanup.'
        }
    }
    foreach ($requestId in $owned.RequestIds) {
        $canonical = ([Guid]$requestId).ToString()
        if ($canonical -ne $requestId) { throw 'Invalid owned request identifier.' }
        $receipt = Join-Path $Root ('lab54-crm-' + $canonical + '.json')
        Assert-OwnedFile $receipt
        if (Test-Path -LiteralPath $receipt) { Remove-Item -LiteralPath $receipt }
    }
    Remove-Item -LiteralPath $Worker -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Manifest
    if (@(Get-ChildItem -LiteralPath $Root -Force).Count -eq 0) { Remove-Item -LiteralPath $Root }
    Write-Host 'Owned CRM worker and receipts removed; other files were preserved.'
    return
}
if (-not (Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -eq '192.168.10.10')) { throw 'Run only on assigned Windows01 at 192.168.10.10.' }
if ($Control -and $CrmUrl) { throw 'Control does not take a CRM URL.' }
if (-not $Control) {
    $uri = [Uri]$CrmUrl
    if ($uri.Scheme -ne 'https' -or -not $uri.DnsSafeHost.EndsWith('.azurewebsites.net') -or $uri.AbsolutePath -ne '/api/crm/admin' -or $uri.Query -or $uri.Fragment -or $uri.UserInfo -or $uri.Port -ne 443) {
        throw 'Use your deployed HTTPS CRM URL ending in /api/crm/admin.'
    }
}
New-Item -ItemType Directory -Path $Root -Force | Out-Null
$owned = @{ RequestIds = @(); ProcessId = $null; StartTimeUtc = $null }
if (Test-Path -LiteralPath $Manifest) {
    $previous = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    if ($previous.ProcessId) {
        $running = Get-Process -Id ([int]$previous.ProcessId) -ErrorAction SilentlyContinue
        if ($running -and $running.StartTime.ToUniversalTime().ToString('o') -eq $previous.StartTimeUtc) { throw 'Previous worker is still running.' }
    }
    $owned.RequestIds = @($previous.RequestIds)
} elseif (Test-Path -LiteralPath $Worker) { throw 'Unowned worker exists. Preserve it and use a clean lab directory.' }
$RequestId = [Guid]::NewGuid().ToString()
$owned.RequestIds += $RequestId
$owned | ConvertTo-Json | Set-Content -LiteralPath $Manifest -Encoding UTF8
@'
param([Parameter(Mandatory=$true)][Guid]$CrmRequestId)
$ErrorActionPreference = 'Stop'
$Url = $env:LAB54_CRM_URL
$Key = $env:LAB54_CRM_KEY
$IsControl = $env:LAB54_CONTROL -eq '1'
Remove-Item Env:LAB54_CRM_KEY -ErrorAction SilentlyContinue
$Receipt = Join-Path 'C:\GlobexLab\lab54-marker' ('lab54-crm-' + $CrmRequestId.ToString() + '.json')
$Result = @{ status='running'; request_id=$CrmRequestId.ToString(); hostname=$env:COMPUTERNAME; user=[Security.Principal.WindowsIdentity]::GetCurrent().Name; control=$IsControl; events=@() }
try {
    if ($IsControl) {
        Start-Sleep -Seconds 3
        $Result.status = 'control_complete'
    } else {
        if (-not $Key -or -not $Url) { throw 'Missing private CRM configuration.' }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $started = Get-Date
        for ($attempt=0; $attempt -lt 5; $attempt++) {
            if ($attempt -gt 0) { Start-Sleep -Milliseconds 1100 }
            $EventId = if ($attempt -eq 0) { $CrmRequestId.ToString() } else { [Guid]::NewGuid().ToString() }
            $Body = @{event_id=$EventId} | ConvertTo-Json -Compress
            try {
                $response = Invoke-WebRequest -Uri $Url -Method Post -Headers @{'x-functions-key'=$Key} -ContentType 'application/json' -Body $Body -UseBasicParsing -TimeoutSec 10
                throw 'Expected denied CRM access, but received a successful HTTP response.'
            } catch [System.Net.WebException] {
                $response = $_.Exception.Response
                if (-not $response -or [int]$response.StatusCode -ne 403) { throw 'CRM did not return expected HTTP 403; inspect access and the endpoint.' }
                $reader = New-Object IO.StreamReader($response.GetResponseStream())
                try { $data = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose(); $response.Close() }
            }
            $raw = $data.row.RawMessage | ConvertFrom-Json
            if (-not $data.telemetry_accepted -or $raw.event_id -ne $EventId -or $data.row.Operation -ne 'AdminAccessDenied' -or $raw.source_ip_emulated -ne $true) { throw 'CRM telemetry did not match the actual request.' }
            $Result.events += @{event_id=$EventId; http_status=403; row=$data.row}
            Write-Host ('CRM request {0}/5: HTTP 403; telemetry accepted; request {1}' -f ($attempt+1),$EventId)
            if (((Get-Date)-$started).TotalSeconds -gt 60) { throw 'Burst exceeded 60 seconds. Preserve partial evidence.' }
        }
        $times = @($Result.events | ForEach-Object { [DateTimeOffset]::Parse($_.row.TimeGenerated) } | Sort-Object)
        if (($times[-1]-$times[0]).TotalSeconds -gt 60) { throw 'Accepted event timestamps exceed the detection window.' }
        $Result.status='complete'
        $Result.source_ip_emulated=$true
    }
} catch {
    $Result.status='failed'
    Write-Error 'CRM worker failed. Inspect the saved partial receipt; no success is implied.' -ErrorAction Continue
} finally {
    $Key=$null
    $Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Receipt -Encoding UTF8
}
if ($Result.status -eq 'failed') { exit 1 }
'@ | Set-Content -LiteralPath $Worker -Encoding UTF8
try {
    $env:LAB54_CONTROL = if ($Control) {'1'} else {'0'}
    $env:LAB54_CRM_URL = $CrmUrl
    if (-not $Control) {
        $secure = Read-Host 'Paste the assigned CRM Function key (hidden)' -AsSecureString
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $env:LAB54_CRM_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
    }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Worker,'-CrmRequestId',$RequestId) -WindowStyle Hidden -PassThru
    $owned.ProcessId=$process.Id
    $owned.StartTimeUtc=$process.StartTime.ToUniversalTime().ToString('o')
    $owned | ConvertTo-Json | Set-Content -LiteralPath $Manifest -Encoding UTF8
} finally {
    Remove-Item Env:LAB54_CRM_KEY,Env:LAB54_CRM_URL,Env:LAB54_CONTROL -ErrorAction SilentlyContinue
}
Write-Host ('Observed worker request ID: '+$RequestId)
if (-not $process.WaitForExit(70000)) { $process.Kill(); throw 'Owned worker exceeded its 70-second runtime limit. Inspect partial evidence.' }
$Receipt = Join-Path $Root ('lab54-crm-'+$RequestId+'.json')
Assert-OwnedFile $Receipt
$result = Get-Content -LiteralPath $Receipt -Raw | ConvertFrom-Json
if ($result.status -notin @('complete','control_complete')) { throw ('CRM worker failed. Receipt: '+$Receipt) }
Write-Host ('Result: '+$result.status+'; receipt: '+$Receipt)
Write-Host 'Compare this request ID with the LimaCharlie detection and CRM Sentinel alert. CRM source IP remains an emulated Lab 3.1 indicator.'
