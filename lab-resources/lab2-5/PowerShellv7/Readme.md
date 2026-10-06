# SEC598 Lab 2.5 — PowerShell 7

The original filename and function name are retained. Run these commands in **PowerShell 7 on Windows01** from the folder containing the supplied scripts:

```powershell
. .\Invoke-ParallelAtomicWorkflow-Full.ps1
$cred = Get-Credential -UserName 'sec598admin'
$runs = Invoke-Lab25ParallelChain `
    -ComputerNames @('192.168.10.10','192.168.10.12') `
    -Credential $cred
$runs | Format-Table Hostname,TechniqueCount,EvidenceJson -AutoSize
```

The orchestrator uses `ForEach-Object -Parallel` with a default throttle of 2 and `Invoke-Command` for each target. Exactly two distinct target strings are required; supply one address per machine.

The default remote configuration remains `Microsoft.PowerShell` to work with the existing Windows PowerShell 5.1 lab endpoints. To execute on registered PowerShell 7 endpoints, add `-ConfigurationName PowerShell.7` to the chain and collection commands. The same configuration is used for the peer WinRM stage. The scripts do not install endpoints or change WinRM, TrustedHosts, firewall, or authentication settings.

## Evidence and compatibility

Each endpoint retains the existing root:

`C:\Users\sec598admin\Desktop\lab25-results\parallel\<HOSTNAME>\`

The existing timestamp format and filenames remain: `parallel-chain_<timestamp>.json`, `parallel-chain_<timestamp>.txt`, `parallel-context_<timestamp>.json`, and `atomic-res_<timestamp>.txt`. The last file is created when an Atomic test produces output and retains the most recent test output, as in the original script. Avoid overlapping runs on the same endpoint within the same second.

Chain JSON remains a flat array with the original fields: `TechniqueId`, `TestNumbers`, `Hostname`, `Target`, `PeerHost`, `Detail`, `Ok`, `Captured`, and `Ended`. All context and technique-specific Captured fields are retained. `TestNumbers` remains a string; the three native pivot stages retain an empty string. `-SkipPivot` retains the original six discovery rows, and `-SkipAtomic` uses the native fallbacks.

Existing workbook loading and comparison functions remain compatible. The two supplied companion scripts implement the collection and comparison logic shown in the referenced chat, with explicit errors for missing evidence:

Both companion scripts support Windows PowerShell 5.1 and PowerShell 7. Only the parallel chain requires PowerShell 7 on the orchestrator.

```powershell
.\Get-Lab25Evidence.ps1 -ComputerName '192.168.10.12' -Credential $cred
.\Compare-Lab25Evidence.ps1 | Format-Table -AutoSize
```

Collection copies the newest completed evidence bundle with `Copy-Item -FromSession` to `$env:USERPROFILE\Desktop\lab25-results\parallel\WINDOWS02-from-remote` when the remote hostname is WINDOWS02. It closes the session even on failure. It does not rerun techniques. Use the path parameters if your account, hostnames, or results locations differ. The comparison selects the newest JSON in each directory; ensure those files correspond to the runs you intend to compare.

## Fixes and verification

Logging uses the information stream so readiness checks remain Boolean and function output contains only endpoint summaries. Atomic module imports remain available to subsequent steps. Terminating PowerShell errors trigger existing fallbacks. Native share commands check their exit codes and pass arguments directly; CIM creation/termination checks return values and always releases the session.

Local PowerShell 7 verification covers syntax, all 12 technique rows, unchanged field names, fallback and skip behavior, missing Atomic modules, CIM failure status, empty test-number comparisons, missing evidence, real parallel runspace argument transport with simulated remoting, and collection of byte-identical JSON with simulated remoting.

Live WinRM, SMB, DCOM, installed Atomic test versions, and Windows01/Windows02 were **not executed or validated** here. `atomic_ok` retains the original meaning that the Atomic invocation returned without a terminating PowerShell error; it is not an independent assertion that every underlying test command achieved its goal. `native_fallback` records a successful fallback rather than a successful Atomic test. Evidence is not a checkpoint/resume mechanism.

References: [ForEach-Object](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object) and [Invoke-Command](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/invoke-command).
