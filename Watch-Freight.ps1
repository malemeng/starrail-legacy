[CmdletBinding()]
param(
    [string]$Seed = 'agent-flight-acceptance',
    [string]$Game = '',
    [string]$EvidenceDirectory = '',
    [switch]$ExitAfterDemo
)

$ErrorActionPreference = 'Stop'
$client = Join-Path $PSScriptRoot 'agent_client.ps1'
$session = Join-Path ([IO.Path]::GetTempPath()) ('starrail-watch-' + [Guid]::NewGuid().ToString('N'))
$records = [Collections.Generic.List[object]]::new()
$ready = $null
$completed = $false

function Send-Order([string]$Action, [hashtable]$Parameters = @{}) {
    $reply = & $client -Session $session -Action $Action -Json (ConvertTo-Json $Parameters -Depth 6 -Compress) | ConvertFrom-Json
    if (-not $reply.ok) { throw "游戏拒绝 ${Action}：$($reply.error) $($reply.detail)" }
    $records.Add([ordered]@{
        time = [DateTime]::UtcNow.ToString('o')
        action = $Action
        arguments = $Parameters
        result = $reply.result
        screen = $reply.state.screen
        system = $reply.state.system.id
        dock = $reply.state.ship.dock
        position = $reply.state.ship.pos
        fuel = $reply.state.ship.fuel
        ore = $reply.state.ship.cargo | Select-Object -First 1
        credits = $reply.state.actor.credits
    })
    return $reply
}

function Show-Intent([string]$Message, [string]$Target) {
    $null = Send-Order 'set_intent' @{ text = $Message; target = $Target }
    Write-Host $Message
}

function Save-Frame([string]$Name) {
    if (-not $EvidenceDirectory) { return }
    $capture = Send-Order 'watch_frame'
    if ($capture.result.file -ne 'watch.png') { throw '游戏未返回观战截图。' }
    Copy-Item -LiteralPath (Join-Path $session 'watch.png') -Destination (Join-Path $EvidenceDirectory "$Name.png")
}

function Fly-To([string]$Kind, [int]$Target = 0, [switch]$CaptureCruise) {
    $null = Send-Order 'waypoint' @{ kind = $Kind; target = $Target }
    # A short first order exposes a real in-flight frame on the interstellar leg.
    $ticks = if ($CaptureCruise -and $EvidenceDirectory) { 60 } else { 1800 }
    for ($leg = 0; $leg -lt 12; $leg++) {
        $flight = Send-Order 'step' @{ ticks = $ticks; speed = 3; stop = 'arrival' }
        if ($CaptureCruise -and $leg -eq 0) { Save-Frame 'cruise' }
        if ($flight.result.stopped -eq 'arrival') { return }
        if ($flight.result.stopped -ne 'tick_limit' -or $flight.state.ship.fuel -le 0) {
            throw "飞行中止（$($flight.result.stopped)）。请查看窗口中的航行状态。"
        }
        $ticks = 1800
    }
    throw '超过预期航程，航点仍未到达。'
}

try {
    if ($EvidenceDirectory) {
        $EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
        [IO.Directory]::CreateDirectory($EvidenceDirectory) | Out-Null
        foreach ($name in @('departure.png','cruise.png','purchase.png','sale.png','voyage.json')) {
            if (Test-Path -LiteralPath (Join-Path $EvidenceDirectory $name)) { throw "证据目录已包含 $name，请选择新目录。" }
        }
    }
    $ready = & $client -Start -Watch -Game $Game -Session $session | ConvertFrom-Json
    if (-not $ready.watch) { throw '请使用随发行包提供的观战版游戏和客户端。' }
    $start = (Send-Order 'new_game' @{ seed = $Seed; name = '林舟' }).state
    $contract = (Send-Order 'accept_first_job').state.contract
    $origin = $start.ports | Where-Object id -eq $start.ship.dock | Select-Object -First 1
    Show-Intent '接下首航单，去矿港买 16 份原矿。8 份交货，8 份出售。' $origin.name
    Save-Frame 'departure'
    Start-Sleep -Milliseconds 1600
    $null = Send-Order 'depart'
    Fly-To 'gravity'
    $hyper = (Send-Order 'jump').state
    # The authored first-delivery mine is the first port of core system 1.
    $beacon = $hyper.beacons | Where-Object id -eq 1 | Select-Object -First 1
    if (-not $beacon) { throw '首航委托的星系未出现在航标列表。' }
    Show-Intent '已进入跃迁空间。跟随航标，去邻近星系的矿港采购。' $beacon.name
    Fly-To 'system' $beacon.id -CaptureCruise
    $local = (Send-Order 'jump').state
    if ($local.system.id -ne $beacon.id) { throw '进入的星系与所选航标不同。' }
    $mine = @($local.ports)[0]
    $foundry = $local.ports | Where-Object id -eq $contract.target | Select-Object -First 1
    if (-not $foundry) { throw '目的星系缺少委托指定的交货港。' }
    Fly-To 'port' $mine.id
    $docked = (Send-Order 'dock').state
    if ($docked.ship.dock -ne $mine.id) { throw '未在选定矿港靠泊。' }
    $purchase = Send-Order 'trade' @{ ware = 0; amount = 16 }
    if ($purchase.result.moved -ne 16 -or $purchase.state.ship.cargo[0] - $docked.ship.cargo[0] -ne 16) { throw '未购足首航所需的原矿。' }
    $cost = $docked.actor.credits - $purchase.state.actor.credits
    Show-Intent "已花 $cost 信用点装好 16 份原矿，飞往铸造站交货。" $foundry.name
    Save-Frame 'purchase'
    Start-Sleep -Milliseconds 1600
    $null = Send-Order 'depart'
    Fly-To 'port' $foundry.id
    $arrived = (Send-Order 'dock').state
    if ($arrived.ship.dock -ne $foundry.id) { throw '当前靠泊点与交货港不符。' }
    $delivered = (Send-Order 'deliver_first_job').state
    $fee = $delivered.actor.credits - $arrived.actor.credits
    if ($delivered.ship.cargo[0] -ne $arrived.ship.cargo[0] - 8 -or $fee -le 0) { throw '首航委托未完成结算。' }
    $sale = Send-Order 'trade' @{ ware = 0; amount = -8 }
    $proceeds = $sale.state.actor.credits - $delivered.actor.credits
    if ($sale.result.moved -ne -8 -or $proceeds -le 0 -or $sale.state.ship.cargo[0] -ne $start.ship.cargo[0]) { throw '余货未完成销售。' }
    Show-Intent "首航完成。交货获 $fee，卖矿得 $proceeds，现有 $($sale.state.actor.credits) 信用点。" $foundry.name
    Save-Frame 'sale'
    $completed = $true
    if (-not $ExitAfterDemo) { Write-Host "可在游戏窗口查看成交结果。会话目录 $session" }
} finally {
    if ($EvidenceDirectory -and $ready) {
        $report = [ordered]@{ seed = $Seed; completed = $completed; watch = $ready.watch; protocol = $ready.protocol; orders = $records }
        $path = Join-Path $EvidenceDirectory 'voyage.json'
        [IO.File]::WriteAllText($path, (ConvertTo-Json $report -Depth 8), [Text.UTF8Encoding]::new($false))
    }
    if ($ExitAfterDemo -and $ready -and -not (Test-Path -LiteralPath (Join-Path $session 'request.json')) -and -not (Test-Path -LiteralPath (Join-Path $session 'response.json'))) {
        & $client -Session $session -Action quit | Out-Null
    }
}
