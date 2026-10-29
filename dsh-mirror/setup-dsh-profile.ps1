#requires -Version 5.1
<#
  Recreate this machine's DSH profile on a fresh DSH install.

  NOTE: this file is intentionally pure ASCII so that Windows PowerShell 5.1
  parses it correctly regardless of the file encoding / code page.

  Steps:
    1. back up existing profile config files
    2. write package.json (dependencies + bundle order)
    3. write cordis.patch.yml (default model, UI, theme, agent preset)
    4. write pnpm-workspace.yaml (hoisted linker, same as source machine)
    5. provision vendor/dsh-startup-screen (offline cache, else GitHub)
    6. pnpm install with DSH's bundled node + pnpm
    7. patch dsh-deepseek-web-free: disable the web UI's built-in search
    8. print a summary

  Usage: double-click setup.cmd. Idempotent, safe to re-run.
#>
[CmdletBinding()]
param(
    [string]$ProfileDir  = (Join-Path $env:USERPROFILE '.dsh\profiles\desktop'),
    [string]$RuntimeDeps = '',
    [switch]$SkipVendorDownload,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$script:LogPath = Join-Path $PSScriptRoot 'setup-log.txt'
if (Test-Path -LiteralPath $script:LogPath) { Remove-Item -LiteralPath $script:LogPath -Force }
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    [System.IO.File]::AppendAllText($script:LogPath, $line + "`r`n", $script:Utf8NoBom)
}
function Fail([string]$Message) {
    Log ("ERROR: " + $Message)
    throw $Message
}

Log '==== DSH profile setup start ===='
Log ("profile: " + $ProfileDir)

# ---------- 0. preconditions ----------
if (-not (Test-Path -LiteralPath $ProfileDir)) {
    Fail ("profile directory not found: " + $ProfileDir + " (start DSH once first so it creates profiles)")
}

function Find-RuntimeDeps {
    $candidates = @()
    if ($RuntimeDeps) { $candidates += $RuntimeDeps }
    $candidates += (Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies')
    $candidates += 'E:\deepseek\resources\runtime\primary-runtime\dependencies'
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'node\bin\node.exe'))) { return $c }
    }
    return $null
}

$deps = Find-RuntimeDeps
if (-not $deps) { Fail 'cannot locate the node runtime bundled with DSH; pass -RuntimeDeps <dependencies dir>' }
$nodeExe = Join-Path $deps 'node\bin\node.exe'
$pnpmCjs = Join-Path $deps 'pnpm\bin\pnpm.cjs'
if (-not (Test-Path -LiteralPath $pnpmCjs)) { Fail ("pnpm not found: " + $pnpmCjs) }
Log ("node: " + $nodeExe)
Log ("pnpm: " + $pnpmCjs)

# ---------- 1. backup ----------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $ProfileDir ("backup-" + $stamp)
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($f in 'package.json', 'cordis.patch.yml', 'pnpm-lock.yaml', 'pnpm-workspace.yaml') {
    $p = Join-Path $ProfileDir $f
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $backupDir -Force }
}
Log ("backed up to " + $backupDir)

# ---------- 2. package.json ----------
$packageJson = @'
{
  "name": "dsh-profile-desktop",
  "private": true,
  "dependencies": {
    "@leon___/dsh-client-liang-intensity-skin": "^0.1.12",
    "@liustack/modsearch": "5.10.10",
    "dsh-concurrency-guard": "^1.5.6",
    "dsh-deepseek-web-free": "1.0.10",
    "dsh-endfield-theme": "^1.6.0",
    "dsh-m": "https://registry.npmmirror.com/dsh-m/-/dsh-m-0.10.23.tgz",
    "dsh-pet": "^0.3.8",
    "dsh-startup-screen": "link:./vendor/dsh-startup-screen"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app",
        "dsh-m",
        "dsh-pet",
        "dsh-deepseek-web-free",
        "dsh-concurrency-guard",
        "@liustack/modsearch",
        "dsh-startup-screen",
        "@deepseek-ai/dsh-experimental-agent-team-profile",
        "@leon___/dsh-client-liang-intensity-skin"
      ]
    }
  }
}
'@
Set-Content -LiteralPath (Join-Path $ProfileDir 'package.json') -Value $packageJson -Encoding UTF8
Log 'package.json written'

# ---------- 3. cordis.patch.yml ----------
$patchYml = @'
# Your patch layer for this dsh profile, applied after every bundle layer:
# a top-level YAML array of loader patch entries (id-targeted config
# overrides, disables, and insert lists; `!!js` expressions allowed).
- id: agent-default-model
  name: "@deepseek-ai/dsh-agent-default-model"
  config:
    provider: deepseek-web
    model: default
    reasoningEffort: on
- id: ui-settings-account
  name: "@deepseek-ai/dsh-client-ui-settings-account"
  config:
    version: 1
    step: done
    purpose: development
    process: standard
    completion: completed
    usage: detailed
    developerTools: true
- id: ui-chat
  name: "@deepseek-ai/dsh-client-ui-chat"
  config:
    transcriptView: standard
    performanceUsage: detailed
- id: ui-settings
  name: "@deepseek-ai/dsh-client-ui-settings"
  config:
    enabled: true
- id: ui-theme
  name: "@deepseek-ai/dsh-client-ui-theme"
  config:
    preference: dark
- id: agent-preset-registry
  name: "@deepseek-ai/dsh-agent-preset-registry"
  config:
    default: standard
    selectedDefault: cordis
'@
Set-Content -LiteralPath (Join-Path $ProfileDir 'cordis.patch.yml') -Value $patchYml -Encoding UTF8
Log 'cordis.patch.yml written'

# ---------- 4. pnpm-workspace.yaml ----------
$wsYaml = @'
packages:
  - .

nodeLinker: hoisted
autoInstallPeers: false
minimumReleaseAgeExclude:
  - dsh-m@0.10.23
'@
Set-Content -LiteralPath (Join-Path $ProfileDir 'pnpm-workspace.yaml') -Value $wsYaml -Encoding UTF8
Log 'pnpm-workspace.yaml written'

# ---------- 5. vendor: dsh-startup-screen ----------
$vendorDir = Join-Path $ProfileDir 'vendor'
$bundleDir = Join-Path $vendorDir 'dsh-startup-screen'
$cacheDir  = Join-Path $PSScriptRoot 'vendor-cache\dsh-startup-screen'

if (Test-Path -LiteralPath (Join-Path $bundleDir 'package.json')) {
    Log 'vendor/dsh-startup-screen already present, skipping'
}
elseif (Test-Path -LiteralPath (Join-Path $cacheDir 'package.json')) {
    New-Item -ItemType Directory -Path $vendorDir -Force | Out-Null
    Copy-Item -LiteralPath $cacheDir -Destination $bundleDir -Recurse -Force
    Log 'copied dsh-startup-screen from bundled vendor-cache (offline)'
}
elseif ($SkipVendorDownload) {
    Fail 'vendor/dsh-startup-screen missing and -SkipVendorDownload was given'
}
else {
    New-Item -ItemType Directory -Path $vendorDir -Force | Out-Null
    $tgz = Join-Path $env:TEMP 'dsh-startup-screen.tar.gz'
    $url = 'https://codeload.github.com/6shenhonghong9/dsh-startup-screen/tar.gz/refs/heads/main'
    Log ("downloading " + $url)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tgz -UseBasicParsing
    $tmp = Join-Path $env:TEMP ('dsh-ss-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    & tar.exe -xzf $tgz -C $tmp
    if ($LASTEXITCODE -ne 0) { Fail 'tar extraction failed' }
    $inner = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    if (-not $inner) { Fail 'unexpected archive layout' }
    Move-Item -LiteralPath $inner.FullName -Destination $bundleDir
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Log 'dsh-startup-screen source provisioned'
}

# ---------- 6. pnpm install ----------
if ($SkipInstall) {
    Log 'skipping pnpm install (-SkipInstall)'
}
else {
    Log 'running pnpm install (may take a few minutes)...'
    Push-Location $ProfileDir
    try {
        Remove-Item Env:CI -ErrorAction SilentlyContinue
        $lines = & $nodeExe $pnpmCjs install --no-frozen-lockfile 2>&1
        $rc = $LASTEXITCODE
        foreach ($l in $lines) { Log ('  ' + $l) }
        if ($rc -ne 0) { Fail ("pnpm install failed (exit " + $rc + ")") }
    }
    finally {
        Pop-Location
    }
    Log 'pnpm install finished'
}

# ---------- 7. patch: disable built-in web search ----------
$pluginLib = Join-Path $ProfileDir 'node_modules\dsh-deepseek-web-free\lib'
if (-not (Test-Path -LiteralPath $pluginLib)) {
    Log 'WARN: dsh-deepseek-web-free not installed, skipping search patch'
}
else {
    $pattern = '(?s)(function\s+nativeSearchActive\s*\([^)]*\)\s*\{)\s*return\s+[^;]+;'
    $targets = @(Get-ChildItem -LiteralPath $pluginLib -Filter 'config-*.js' -File)
    if ($targets.Count -eq 0) { Log 'WARN: no config-*.js under lib, plugin layout may have changed' }
    foreach ($t in $targets) {
        $text = [System.IO.File]::ReadAllText($t.FullName, $script:Utf8NoBom)
        if ($text -notmatch $pattern) {
            if ($text -match 'function\s+nativeSearchActive') { Log ('already patched: ' + $t.Name) }
            else { Log ('WARN: nativeSearchActive not found in ' + $t.Name) }
            continue
        }
        $new = [regex]::Replace($text, $pattern, ('$1' + "`r`n`treturn false;"))
        [System.IO.File]::WriteAllText($t.FullName, $new, $script:Utf8NoBom)
        Log ('patched (built-in web search disabled): ' + $t.Name)
    }
}

# ---------- 8. summary ----------
Log '==== summary ===='
$finalPkg = Get-Content -LiteralPath (Join-Path $ProfileDir 'package.json') -Raw | ConvertFrom-Json
Log '-- dependencies --'
foreach ($d in $finalPkg.dependencies.PSObject.Properties) { Log ('   ' + $d.Name.PadRight(46) + ' ' + $d.Value) }
Log '-- install check --'
$checks = @(
    @{ n = 'dsh-m';                 p = 'node_modules\dsh-m\package.json' },
    @{ n = 'dsh-pet';               p = 'node_modules\dsh-pet\package.json' },
    @{ n = 'dsh-deepseek-web-free'; p = 'node_modules\dsh-deepseek-web-free\package.json' },
    @{ n = 'dsh-concurrency-guard'; p = 'node_modules\dsh-concurrency-guard\package.json' },
    @{ n = '@liustack/modsearch';   p = 'node_modules\@liustack\modsearch\package.json' },
    @{ n = 'dsh-endfield-theme';    p = 'node_modules\dsh-endfield-theme\package.json' },
    @{ n = 'dsh-startup-screen';    p = 'node_modules\dsh-startup-screen\package.json' },
    @{ n = 'liang-intensity-skin';  p = 'node_modules\@leon___\dsh-client-liang-intensity-skin\package.json' }
)
foreach ($c in $checks) {
    $ok = Test-Path -LiteralPath (Join-Path $ProfileDir $c.p)
    $state = 'MISSING'
    if ($ok) { $state = 'OK' }
    Log ('   ' + $c.n.PadRight(30) + ' ' + $state)
}
$cfg = Get-ChildItem -LiteralPath $pluginLib -Filter 'config-*.js' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cfg) {
    $hit = Select-String -LiteralPath $cfg.FullName -Pattern 'nativeSearchActive' -Context 0,1 | Select-Object -First 1
    if ($hit) { Log ('-- nativeSearchActive: ' + ((($hit.Line + ' ' + ($hit.Context.PostContext -join ' ')) -replace '\s+', ' '))) }
}
Log 'DONE. Fully quit DSH, start it again, then refresh the page.'
Log ("log: " + $script:LogPath)
