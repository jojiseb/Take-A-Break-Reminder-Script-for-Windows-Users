# ============================================================
#  TakeABreakReminder.ps1  v6.0
#  - Fully offline, no internet needed
#  - Tracks ACTIVE screen time only
#  - Timer resets when screen is locked
#  - Auto-registers itself to run on every login (first run)
#  - Writes logs to: C:\Logs\TakeABreakReminder\reminder.log
#  - Uses system tray balloon notification (works on all Windows)
# ============================================================

# -----------------------------------------------
# CONFIG
# -----------------------------------------------
$INTERVAL_MINS = 30
$POLL_SECONDS  = 15
$LOG_FILE      = "C:\Logs\TakeABreakReminder\reminder.log"
$MAX_LOG_LINES = 500

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
# LOGGING
# -----------------------------------------------
function Write-Log($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line      = "[$timestamp] $message"

    $dir = Split-Path $LOG_FILE
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Add-Content -Path $LOG_FILE -Value $line
    Write-Host "  $line"

    if ((Get-Content $LOG_FILE | Measure-Object -Line).Lines -gt $MAX_LOG_LINES) {
        $trimmed = Get-Content $LOG_FILE | Select-Object -Last $MAX_LOG_LINES
        $trimmed | Set-Content $LOG_FILE
    }
}

# -----------------------------------------------
# AUTO-REGISTER WITH TASK SCHEDULER
# -----------------------------------------------
function Register-StartupTask {
    $taskName = "TakeABreakReminder"
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Log "Task Scheduler entry already exists. Skipping registration."
        return
    }

    $scriptPath = $MyInvocation.ScriptName
    if (-not $scriptPath) {
        Write-Log "Auto-start skipped: could not detect script path. Run from a saved .ps1 file."
        return
    }

    try {
        $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                      -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        $trigger  = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 23)
        Register-ScheduledTask -TaskName $taskName -Action $action `
                               -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
        Write-Log "Auto-start registered. Script will run on every login."
    } catch {
        Write-Log "Auto-start failed. Run as Administrator to enable it."
    }
}

# -----------------------------------------------
# LOCK SCREEN DETECTION
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
# NOTIFICATION — system tray balloon (works on all Windows)
# -----------------------------------------------
Add-Type -AssemblyName System.Windows.Forms

$script:balloon = New-Object System.Windows.Forms.NotifyIcon
$script:balloon.Icon    = [System.Drawing.SystemIcons]::Information
$script:balloon.Visible = $true

function Show-Notification($body) {
    $script:balloon.BalloonTipTitle = "Take a Break"
    $script:balloon.BalloonTipText  = $body
    $script:balloon.ShowBalloonTip(10000)
}

function Fire-Reminder {
    $msg = $prompts | Get-Random
    Show-Notification $msg
    Write-Log "REMINDER FIRED >> $msg"
}

# -----------------------------------------------
# MAIN
# -----------------------------------------------
Enable-LockAudit
Register-StartupTask

$intervalSeconds = $INTERVAL_MINS * 60
$activeSeconds   = 0
$wasLocked       = $false

Write-Log "Script started. Interval: $INTERVAL_MINS minutes."

while ($true) {
    Start-Sleep -Seconds $POLL_SECONDS

    $locked = Is-ScreenLocked

    if ($locked) {
        if (-not $wasLocked) {
            $mins = [math]::Floor($activeSeconds / 60)
            Write-Log "Screen locked. Timer reset. (Was at $mins min active)"
            $activeSeconds = 0
        }
        $wasLocked = $true
    } else {
        if ($wasLocked) {
            Write-Log "Screen unlocked. Active timer started."
        }
        $wasLocked      = $false
        $activeSeconds += $POLL_SECONDS

        if ($activeSeconds % 300 -eq 0) {
            $mins = [math]::Floor($activeSeconds / 60)
            Write-Log "Active for $mins min..."
        }

        if ($activeSeconds -ge $intervalSeconds) {
            Fire-Reminder
            $activeSeconds = 0
        }
    }
}
