# ============================================================
#  TakeABreakReminder.ps1  v4.0
#  - No emojis, no internet needed, fully offline
#  - Tracks ACTIVE screen time only
#  - Timer resets when screen is locked
#  - Auto-registers itself to run on every login (first run)
# ============================================================

# -----------------------------------------------
# CONFIG
# -----------------------------------------------
$INTERVAL_MINS = 30
$POLL_SECONDS  = 15

# -----------------------------------------------
# ACTIVITY PROMPTS
# -----------------------------------------------
$prompts = @(
    "You have been sitting for 30 minutes. Stand up and stretch your legs."
    "Step away from the screen. Walk around for 2 to 3 minutes."
    "Roll your shoulders, stretch your neck, loosen your wrists."
    "Look at something far away for 20 seconds. Your eyes need a break."
    "Take 4 deep breaths. Inhale slowly, hold, exhale. Do it now."
    "When did you last drink water? Go grab a glass right now."
    "Check your posture. Sit straight, shoulders back, screen at eye level."
    "Walk to the kitchen, balcony, or just around the room. Move."
    "Put your hands down. Shake them out. Flex and extend your fingers."
    "Do 10 jumping jacks or any movement for 15 seconds. Get up."
)

# -----------------------------------------------
# AUTO-REGISTER WITH TASK SCHEDULER
# Runs once — skips if task already exists
# -----------------------------------------------
function Register-StartupTask {
    $taskName = "TakeABreakReminder"
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) { return }

    $scriptPath = $MyInvocation.ScriptName
    if (-not $scriptPath) {
        Write-Host "  [Auto-start skipped: could not detect script path. Run from a saved .ps1 file.]"
        return
    }

    try {
        $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                      -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        $trigger  = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 23)
        Register-ScheduledTask -TaskName $taskName -Action $action `
                               -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
        Write-Host "  [Auto-start registered. Script will run on every login from now on.]"
    } catch {
        Write-Host "  [Auto-start failed. Run as Administrator to enable it.]"
    }
}

# -----------------------------------------------
# LOCK SCREEN DETECTION
# Event ID 4800 = screen locked
# Event ID 4801 = screen unlocked
# -----------------------------------------------
function Enable-LockAudit {
    try {
        auditpol /set /subcategory:"Other Logon/Logoff Events" /success:enable /failure:enable 2>$null
    } catch {}
}

function Is-ScreenLocked {
    try {
        $lastLock   = (Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4800 } -MaxEvents 1 -ErrorAction SilentlyContinue).TimeCreated
        $lastUnlock = (Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4801 } -MaxEvents 1 -ErrorAction SilentlyContinue).TimeCreated
        if ($null -eq $lastLock)   { return $false }
        if ($null -eq $lastUnlock) { return $true  }
        return $lastLock -gt $lastUnlock
    } catch {
        return $false
    }
}

# -----------------------------------------------
# NOTIFICATIONS
# -----------------------------------------------
function Show-Toast($body) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]
        $xml  = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>Take a Break</text><text>$body</text></binding></visual></toast>")
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("TakeABreakReminder").Show($toast)
    } catch {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($body, "Take a Break") | Out-Null
    }
}

function Show-Terminal($body) {
    $line = "-" * 60
    Write-Host ""
    Write-Host $line
    Write-Host "  TAKE A BREAK"
    Write-Host "  $body"
    Write-Host "  Time: $(Get-Date -Format 'hh:mm tt')"
    Write-Host $line
    Write-Host ""
}

function Fire-Reminder {
    $msg = $prompts | Get-Random
    Show-Terminal $msg
    Show-Toast $msg
}

# -----------------------------------------------
# MAIN
# -----------------------------------------------
Enable-LockAudit
Register-StartupTask

$intervalSeconds = $INTERVAL_MINS * 60
$activeSeconds   = 0
$wasLocked       = $false

Write-Host ""
Write-Host "  TakeABreakReminder is running."
Write-Host "  Reminds after $INTERVAL_MINS minutes of active screen time."
Write-Host "  Locking your screen resets the timer."
Write-Host "  Press Ctrl+C to stop."
Write-Host ""

while ($true) {
    Start-Sleep -Seconds $POLL_SECONDS

    $locked = Is-ScreenLocked

    if ($locked) {
        if (-not $wasLocked) {
            $mins = [math]::Floor($activeSeconds / 60)
            Write-Host "  Screen locked. Timer reset. (Was at $mins min active)"
            $activeSeconds = 0
        }
        $wasLocked = $true
    } else {
        if ($wasLocked) {
            Write-Host "  Screen unlocked. Active timer started."
        }
        $wasLocked      = $false
        $activeSeconds += $POLL_SECONDS

        if ($activeSeconds % 300 -eq 0) {
            $mins = [math]::Floor($activeSeconds / 60)
            Write-Host "  Active for $mins min..."
        }

        if ($activeSeconds -ge $intervalSeconds) {
            Fire-Reminder
            $activeSeconds = 0
        }
    }
}
