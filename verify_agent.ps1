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
    Test-Condition ($reply.ok -eq $ExpectSuccess) "$Action expected ok=$ExpectSuccess and returned ok=$($reply.ok) $($reply.error)"
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
        Test-Condition ($start.protocol -eq 2 -and $start.ship.hull_id -eq 'beacon_ff' -and $start.wares.Count -eq 16) 'protocol 2 reports stable hull and industrial cargo identities'
        Test-Condition ($start.ship.owner -eq 0 -and $start.ship.charter.price -gt $start.actor.credits) 'commoner operates a workboat and cannot afford to buy it out on day one'
        $null = Send-Command buyout_charter @{ ship = $start.ship.id } $false
        $hullQuote = (Send-Command ship_quote @{ hull_id = $start.ship.hull_id }).result
        Test-Condition ($hullQuote.materials.Count -gt 0 -and $hullQuote.material_cost -gt 0 -and $hullQuote.labor_cost -gt 0 -and $hullQuote.price -gt $start.actor.credits) 'actual port quote itemizes construction materials and paid work'
        Test-Condition ($start.organizations.Count -eq 2 -and $start.system.starfield -and $start.system.planets.Count -gt 0) 'two real outlaw bases and a generated system are charted'
        Test-Condition ($start.ship.ship_system.id -eq 'maneuveringjets' -and $start.ship.ship_system.description) 'export exposes the active hull system and its behavior'
        $catalog = @($start.ports | Where-Object id -eq $start.ship.dock)[0].wing_catalog
        Test-Condition ($catalog.Count -eq 31 -and 'shrouded_ejecta_wing' -in $catalog.id) 'export loads all 31 wing production programs at the port'
        $null = Send-Command refit_wing @{ bay = 0; wing_id = 'cobra_wing' } $false
        $offers = (Send-Command refit_offers @{ slot = 0 }).result
        Test-Condition ($offers.slot_id -and $offers.current -eq $start.ship.weapons[0] -and $offers.weapons.Count -gt 0) 'docked agent can discover compatible offers'
        $quote = Send-Command refit_quote @{ slot = 0; weapon = '' }
        Test-Condition ($quote.result.ok -and $quote.result.free_op -gt 0 -and $quote.result.net -lt 0 -and $quote.state.actor.credits -eq $start.actor.credits) 'refit preview reports a refund without changing the wallet'
        $focused = (Send-Command set_focus @{ focus = 'industry' }).state
        Test-Condition ($focused.actor.focus -eq 'industry') 'lifestyle action changes live character'
        $fit = (Send-Command refit_tuning @{ caps_delta = 1; vents_delta = 0 }).state
        Test-Condition ($fit.ship.fit.caps -eq 1 -and $fit.actor.credits -lt $start.actor.credits) 'purchased capacitor persists on the real ship'
        $null = Send-Command refit_tuning @{ caps_delta = -1; vents_delta = 0 }
        $null = Send-Command refit_preset @{ preset = 'unknown_preset' } $false
        $null = Send-Command event_choice @{ event_id = 'invalid_event'; option_index = 0 } $false
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
        $null = Follow-Waypoint mine
        $arrival = (Send-Command sensor_ping).state
        $target = @($arrival.targets | Where-Object hostile | Select-Object -First 1)[0]
        Test-Condition ($null -ne $target) 'a real local hostile ship is visible'
        $null = Send-Command group @{ group = 2 }
        $null = Send-Command system @{ target = $target.id; aim = $target.pos; move = @(0,1) }
        # The launcher's six-degree arc requires the pilot to turn the bow first.
        $launched = $false
        for ($turn = 0; $turn -lt 20; $turn++) {
            $initial = Send-Command step @{ target = $target.id; fire = $true; ticks = 9; stop = 'never' }
            $launched = $initial.state.ship.cooldowns[1] -gt 0 -and $initial.state.ship.soft_flux -gt 0
            if ($launched) { break }
        }
        Test-Condition $launched 'combat control aligns the fixed launcher, fires and produces flux'
        $vent = Send-Command vent
        Test-Condition ($vent.state.ship.vent -eq $true) 'combat can enter venting'
        $null = Send-Command step @{ ticks = 150; stop = 'never' }
        $null = Send-Command group @{ group = 1 }
        $state = (Send-Command sensor_ping).state
        for ($run = 0; $run -lt 12 -and !$state.ship.locked; $run++) {
            $contact = @($state.targets | Where-Object id -eq $target.id)[0]
            $direction = @(($contact.pos[0] - $state.ship.pos[0]), ($contact.pos[1] - $state.ship.pos[1]))
            $state = (Send-Command step @{ target = $target.id; move = $direction; ticks = 30; stop = 'encounter' }).state
        }
        Test-Condition $state.ship.locked 'closing on a real hostile enters an encounter'
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
