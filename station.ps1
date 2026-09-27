# ==============================================================================
# Colab LLM Station - Local Workstation Launcher (Windows PowerShell)
# Zero-Browser Headless CLI Interface
# ==============================================================================
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArgs
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonBin = Get-Command python -ErrorAction SilentlyContinue

if (-not $PythonBin) {
    Write-Error "[ERROR] Python 3 was not found on your system PATH."
    exit 1
}

& python "$ScriptDir\tools\station_ctl.py" @ScriptArgs
