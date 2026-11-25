[CmdletBinding(DefaultParameterSetName='Request')]
param(
    [Parameter(Mandatory)][string]$Session,
    [Parameter(ParameterSetName='Start',Mandatory)][switch]$Start,
    [Parameter(ParameterSetName='Start')][string]$Game = '',
    [Parameter(ParameterSetName='Start')][switch]$Watch,
    [Parameter(ParameterSetName='Request',Mandatory)][string]$Action,
    [Parameter(ParameterSetName='Request')][string]$Json = '{}',
    [ValidateRange(1,120)][int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'
$Session = [System.IO.Path]::GetFullPath($Session)
$ready = Join-Path $Session 'ready.json'
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

if ($Start) {
    if (-not $Game) {
        $Game = Join-Path $PSScriptRoot 'StarrailLegacy.exe'
        if (-not (Test-Path -LiteralPath $Game)) { $Game = Join-Path $PSScriptRoot 'dist/StarrailLegacy.exe' }
    }
    $Game = (Resolve-Path -LiteralPath $Game).Path
    if (-not (Test-Path -LiteralPath $Session)) {
        New-Item -ItemType Directory -Path $Session | Out-Null
    }
    if (@(Get-ChildItem -Force -LiteralPath $Session).Count) {
        throw "Choose a new empty session directory: $Session"
    }
    $arguments = '-- "' + '--agent-dir=' + $Session.TrimEnd([IO.Path]::DirectorySeparatorChar) + '"'
    if ($Watch) { $arguments += ' --agent-watch' } else { $arguments = '--headless ' + $arguments }
    $visibility = if ($Watch) { 'Normal' } else { 'Hidden' }
    $process = Start-Process -FilePath $Game -ArgumentList $arguments -WindowStyle $visibility -PassThru
    while (-not (Test-Path -LiteralPath $ready -PathType Leaf)) {
        if ($process.HasExited) { throw "Game exited before the bridge became ready ($($process.ExitCode))." }
        if ([DateTime]::UtcNow -ge $deadline) {
            $process.Kill()
            throw "Game did not become ready before the timeout (PID $($process.Id))."
        }
        Start-Sleep -Milliseconds 30
    }
    Get-Content -Encoding utf8 -LiteralPath $ready -Raw
    return
}

$metadata = Get-Content -Encoding utf8 -LiteralPath $ready -Raw | ConvertFrom-Json
if ($metadata.protocol -notin @(1, 2)) { throw 'Unsupported agent bridge protocol.' }
$requestFile = Join-Path $Session 'request.json'
$replyFile = Join-Path $Session 'response.json'
$lockPath = Join-Path $Session 'client.lock'
$lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
$temp = $null
try {
    if ((Test-Path -LiteralPath $requestFile) -or (Test-Path -LiteralPath $replyFile)) {
        throw 'Session has an unfinished request or unread reply. Inspect response.json before retrying; do not blindly replay an action.'
    }
    $process = Get-Process -Id $metadata.pid -ErrorAction SilentlyContinue
    if (-not $process -or $process.HasExited) {
        '{"ok":false,"error":"game_exited","message":"游戏进程已退出"}'
        return
    }
    if ($Json -notmatch '^\s*\{') { throw 'Json must be an object.' }
    $parameters = $Json | ConvertFrom-Json
    if ($metadata.watch -and $Action -eq 'step' -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')) {
        # A watched 1800-tick order takes at least 30 seconds at normal display cadence.
        $deadline = [DateTime]::UtcNow.AddSeconds(90)
    }
    $id = [Guid]::NewGuid().ToString('N')
    $request = @{ id = $id; action = $Action; args = $parameters } | ConvertTo-Json -Depth 12 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($request) -gt 16384) { throw 'Request exceeds 16 KiB.' }
    $temp = Join-Path $Session ("client-" + $id + ".tmp")
    [System.IO.File]::WriteAllText($temp, $request, [Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temp, $requestFile)
    while (-not (Test-Path -LiteralPath $replyFile -PathType Leaf) -or (Test-Path -LiteralPath $requestFile -PathType Leaf)) {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Timed out. Outcome may be unknown; inspect the session instead of replaying the action.' }
        if ($process.HasExited -and -not (Test-Path -LiteralPath $replyFile)) {
            '{"ok":false,"error":"game_exited","message":"游戏进程已退出"}'
            return
        }
        Start-Sleep -Milliseconds 25
    }
    $reply = Get-Content -Encoding utf8 -LiteralPath $replyFile -Raw
    if (($reply | ConvertFrom-Json).id -ne $id) { throw 'Unexpected reply ID; left response.json intact.' }
    Remove-Item -LiteralPath $replyFile
    $reply
} finally {
    if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp }
    $lock.Dispose()
}
