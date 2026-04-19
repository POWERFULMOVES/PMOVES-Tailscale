#!/usr/bin/env pwsh
<#
.SYNOPSIS
    PMOVES Tailscale Deploy — Windows PowerShell provisioning.
.DESCRIPTION
    Provisions a Windows host onto the PMOVES tailnet.
    Ported from: PMOVES-PROVISIONS/tailscale/tailscale_up.ps1
    Enhanced with role profiles, Headscale support, and sentinel tracking.
.PARAMETER Role
    Node role: workstation, vps, edge (default: workstation)
.PARAMETER Headscale
    Use Headscale login server (requires HEADSCALE_URL env var)
.PARAMETER Force
    Force re-authentication even if sentinel exists
.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Role workstation -Force
    .\deploy.ps1 -Headscale
#>

[CmdletBinding()]
param(
    [ValidateSet('workstation', 'vps', 'edge')]
    [string]$Role = $env:TAILSCALE_DEPLOY_ROLE ?? 'workstation',

    [switch]$Headscale,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$profilesDir = Join-Path $scriptDir 'profiles'

function Log($msg) { Write-Host "[pmoves-tailscale] $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Warning "[pmoves-tailscale] $msg" }
function Fatal($msg) { Write-Error "[pmoves-tailscale] $msg"; exit 1 }

function Mask-Key([string]$key, [int]$visible = 4) {
    if ([string]::IsNullOrEmpty($key)) { return '' }
    if ($key.Length -le $visible) { return '*' * $key.Length }
    return $key.Substring(0, $visible) + ('*' * ($key.Length - $visible))
}

# ── Load Profile ────────────────────────────────────────────────────────────

$profileFile = Join-Path $profilesDir "$Role.env"
$profileVars = @{}
if (Test-Path $profileFile) {
    Log "Loading profile: $Role ($profileFile)"
    Get-Content $profileFile | ForEach-Object {
        $_ = $_.Trim()
        if ($_ -and -not $_.StartsWith('#')) {
            $parts = $_ -split '=', 2
            if ($parts.Count -eq 2) {
                $profileVars[$parts[0].Trim()] = $parts[1].Trim()
            }
        }
    }
}

# Helper: get value with fallback chain (env var → profile → default)
function Get-Config([string]$name, [string]$default = '') {
    $envVal = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrWhiteSpace($envVal)) { return $envVal }
    if ($profileVars.ContainsKey($name)) { return $profileVars[$name] }
    return $default
}

# ── Sentinel Check ──────────────────────────────────────────────────────────

$sentinelDir = Join-Path $env:USERPROFILE '.config\pmoves'
$sentinelPath = Join-Path $sentinelDir 'tailnet-initialized'
$forceReauth = $Force -or ((Get-Config 'TAILSCALE_FORCE_REAUTH') -eq 'true')

if ((Test-Path $sentinelPath) -and -not $forceReauth) {
    Log "Sentinel found at $sentinelPath — already initialized."
    Log "Use -Force to re-join."
    exit 0
}

# ── Verify tailscale.exe ───────────────────────────────────────────────────

try {
    $tailscaleCli = Get-Command 'tailscale.exe' -ErrorAction Stop
    $tailscalePath = $tailscaleCli.Source
    Log "Found: $tailscalePath"
} catch {
    Fatal "tailscale.exe not in PATH. Install from https://tailscale.com/download/windows"
}

# ── Auth Key Resolution ─────────────────────────────────────────────────────

$authKey = Get-Config 'TAILSCALE_AUTHKEY'

if ([string]::IsNullOrWhiteSpace($authKey)) {
    $authKeyFile = Get-Config 'TAILSCALE_AUTHKEY_FILE'
    if (-not [string]::IsNullOrWhiteSpace($authKeyFile)) {
        # Resolve relative paths from script directory
        if (-not [System.IO.Path]::IsPathRooted($authKeyFile)) {
            $authKeyFile = Join-Path (Split-Path $scriptDir -Parent) $authKeyFile
        }
        if (Test-Path $authKeyFile) {
            $authKey = (Get-Content $authKeyFile -First 1).Trim()
            Log "Loaded auth key from $authKeyFile"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($authKey)) {
    # Try default location
    $defaultKeyFile = Join-Path $scriptDir 'tailscale_authkey.txt'
    if (Test-Path $defaultKeyFile) {
        $authKey = (Get-Content $defaultKeyFile -First 1).Trim()
        Log "Loaded auth key from $defaultKeyFile"
    }
}

# ── Build Arguments ─────────────────────────────────────────────────────────

$hostname   = Get-Config 'TAILSCALE_HOSTNAME' "pmoves-$($env:COMPUTERNAME.ToLower())"
$tags       = Get-Config 'TAILSCALE_TAGS' 'tag:pmoves'
$routes     = Get-Config 'TAILSCALE_ADVERTISE_ROUTES'
$loginServer = Get-Config 'TAILSCALE_LOGIN_SERVER'
$acceptRoutes = Get-Config 'TAILSCALE_ACCEPT_ROUTES' 'true'
$ssh        = Get-Config 'TAILSCALE_SSH' 'true'

# Headscale override
if ($Headscale) {
    $headscaleUrl = Get-Config 'HEADSCALE_URL'
    if ([string]::IsNullOrWhiteSpace($headscaleUrl)) {
        Fatal "HEADSCALE_URL required when using -Headscale"
    }
    $loginServer = $headscaleUrl
}

$tsArgs = @('up')
if ($ssh -eq 'true')          { $tsArgs += '--ssh' }
if ($acceptRoutes -eq 'true') { $tsArgs += '--accept-routes' }
if (-not [string]::IsNullOrWhiteSpace($tags))        { $tsArgs += "--advertise-tags=$tags" }
if (-not [string]::IsNullOrWhiteSpace($routes))      { $tsArgs += "--advertise-routes=$routes" }
if (-not [string]::IsNullOrWhiteSpace($hostname))     { $tsArgs += "--hostname=$hostname" }
if (-not [string]::IsNullOrWhiteSpace($loginServer))  { $tsArgs += "--login-server=$loginServer" }
if ($forceReauth)                                      { $tsArgs += '--force-reauth' }
if (-not [string]::IsNullOrWhiteSpace($authKey))      { $tsArgs += "--authkey=$authKey" }

# Extra args
$extraArgs = Get-Config 'TAILSCALE_EXTRA_ARGS'
if (-not [string]::IsNullOrWhiteSpace($extraArgs)) {
    $tsArgs += $extraArgs -split '\s+'
}

# ── Execute ─────────────────────────────────────────────────────────────────

$displayArgs = $tsArgs -replace [regex]::Escape($authKey), (Mask-Key $authKey)
Log "Executing: $tailscalePath $($displayArgs -join ' ')"

try {
    & $tailscalePath @tsArgs
    if ($LASTEXITCODE -ne 0) {
        throw "tailscale.exe exited with code $LASTEXITCODE"
    }
    Log "Tailscale up completed."
} catch {
    Fatal "tailscale up failed: $($_.Exception.Message)"
}

# ── Write Sentinel ──────────────────────────────────────────────────────────

if (-not (Test-Path $sentinelDir)) {
    New-Item -ItemType Directory -Path $sentinelDir -Force | Out-Null
}
(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ') | Out-File -FilePath $sentinelPath -Encoding utf8 -Force
Log "Sentinel written to $sentinelPath"

# ── Summary ─────────────────────────────────────────────────────────────────

try {
    $status = & $tailscalePath status 2>&1
    Log "Status:`n$status"
} catch {
    Warn "Could not retrieve tailscale status."
}

Log "Done. Role=$Role, Hostname=$hostname"
