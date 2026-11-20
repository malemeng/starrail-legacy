param([string]$Game = (Join-Path $PSScriptRoot 'dist/StarrailLegacy.exe'))

$ErrorActionPreference = 'Stop'
$client = Join-Path $PSScriptRoot 'agent_client.ps1'
$checks = 0

function Test-Condition([bool]$Condition, [string]$Description) {
    if (-not $Condition) { throw "FAIL: $Description" }
    $script:checks++
}

function Send-Command([string]$Action, [hashtable]$Parameters = @{}, [bool]$ExpectSuccess = $true) {
    $reply = & $client -Session $session -Action $Action -Json (ConvertTo-Json -InputObject $Parameters -Depth 8 -Compress) | ConvertFrom-Json
    Test-Condition ($reply.ok -eq $ExpectSuccess) "$Action returned $($reply | ConvertTo-Json -Depth 4 -Compress)"
    return $reply
}

function Follow-Waypoint([string]$Kind, [int]$Target = 0) {
    $null = Send-Command waypoint @{ kind = $Kind; target = $Target }
    return Send-Command step @{ ticks = 1200; stop = 'arrival'; speed = 3 }
}

function Run-Route {
    $session = Join-Path ([IO.Path]::GetTempPath()) ('starrail-agent-' + [Guid]::NewGuid().ToString('N'))
    $started = & $client -Start -Session $session -Game $Game | ConvertFrom-Json
    try {
        Test-Condition ((Send-Command observe).state.screen -eq 'title') 'session starts without loading a player save'
        $null = Send-Command step @{ ticks = 60 } $false
        $start = (Send-Command new_game @{ seed = 'agent-flight-acceptance'; name = '测试航务官' }).state
        Test-Condition ($start.screen -eq 'port' -and $start.actor.credits -eq 460) 'new commander begins at the port with standard credits'
        $null = Send-Command step @{ ticks = -1 } $false
        $null = Send-Command set_position @{ pos = @(0,0) } $false
        $null = Send-Command accept_first_job
        $origin = $start.ship.dock
        $null = Send-Command depart
        $null = Send-Command jump @{} $false
        $near = Follow-Waypoint gravity
        Test-Condition ($near.state.jump_allowed -and $near.result.stopped -eq 'arrival') 'standard autopilot reaches the gravity well'
        $hyperspace = (Send-Command jump).state
        Test-Condition ($hyperspace.screen -eq 'hyperspace') 'gravity well allows hyperspace'
        $null = Follow-Waypoint system 1
        $local = (Send-Command jump).state
        Test-Condition ($local.system.id -eq 1 -and $local.screen -eq 'flight') 'arrival at second system'
        $mining = @($local.ports)[0]
        $foundry = @($local.ports)[1]
        $null = Follow-Waypoint port $mining.id
        $null = Send-Command dock
        $bought = Send-Command trade @{ ware = 0; amount = 8 }
        Test-Condition ($bought.result.moved -eq 8 -and $bought.state.ship.cargo[0] -eq 8) 'real purchase reduces money and fills cargo'
        $null = Send-Command depart
        $null = Follow-Waypoint port $foundry.id
        $null = Send-Command dock
        $delivered = (Send-Command deliver_first_job).state
        Test-Condition ($delivered.ship.cargo[0] -eq 0 -and $delivered.actor.credits -eq ($bought.state.actor.credits + 210)) 'foundry delivery consumes cargo and pays the reward'
        $null = Send-Command deliver_first_job @{} $false
        $still = (Send-Command observe).state
        Test-Condition ($still.day -eq $delivered.day) 'observation does not advance simulated time'
        return $delivered | ConvertTo-Json -Depth 15 -Compress
    } finally {
        try { $null = Send-Command quit } catch { Write-Warning "Bridge shutdown failed: $_" }
        Wait-Process -Id $started.pid -Timeout 5 -ErrorAction SilentlyContinue
    }
}

function Run-Combat {
    $session = Join-Path ([IO.Path]::GetTempPath()) ('starrail-agent-combat-' + [Guid]::NewGuid().ToString('N'))
    $started = & $client -Start -Session $session -Game $Game | ConvertFrom-Json
    try {
        $null = Send-Command new_game @{ seed = 'agent-combat-acceptance' }
        $null = Send-Command depart
        $null = Follow-Waypoint gravity
        $null = Send-Command jump
        $null = Follow-Waypoint system 1
        $null = Send-Command jump
        $null = Send-Command waypoint @{ kind = 'point'; pos = @(-20,100) }
        $arrival = (Send-Command step @{ ticks = 900; stop = 'arrival'; speed = 3 }).state
        $target = @($arrival.targets | Where-Object hostile | Select-Object -First 1)[0]
        Test-Condition ($null -ne $target) 'a real local hostile ship is visible'
        $null = Send-Command group @{ group = 2 }
        $null = Send-Command system
        $initial = Send-Command step @{ target = $target.id; fire = $true; ticks = 36; stop = 'never' }
        Test-Condition ($initial.state.ship.cooldowns[1] -gt 0 -and $initial.state.ship.soft_flux -gt 0) 'combat control launches a real weapon and produces flux'
        $vent = Send-Command vent
        Test-Condition ($vent.state.ship.vent -eq $true) 'combat can enter venting'
        $null = Send-Command step @{ ticks = 150; stop = 'never' }
        $null = Send-Command group @{ group = 1 }
        $approach = Send-Command step @{ target = $target.id; move = @(-1,0); fire = $true; ticks = 60 }
        Test-Condition ($approach.result.stopped -eq 'encounter' -and $approach.state.ship.locked) 'physics halts at a real encounter'
        $null = Send-Command step @{ target = $target.id; fire = $true; shield = $true; ticks = 90; stop = 'never' }
    } finally {
        try { $null = Send-Command quit } catch { Write-Warning "Bridge shutdown failed: $_" }
        Wait-Process -Id $started.pid -Timeout 5 -ErrorAction SilentlyContinue
    }
}

$first = Run-Route
$second = Run-Route
Test-Condition ($first -ceq $second) 'same seed and commands reproduce the same result'
Run-Combat
"Agent bridge: $checks/$checks checks passed (two trade voyages and a live combat scenario through the exported game)"
