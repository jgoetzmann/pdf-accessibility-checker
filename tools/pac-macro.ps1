<#
Drive PAC 2026 through Windows UI Automation and save its WCAG report for each PDF.

    pac-macro.ps1 -Mode check -InputDir <folder> [-Files a.pdf,b.pdf] -OutDir <folder>
    pac-macro.ps1 -Mode probe -InputDir <folder> -OutDir <folder>

check  For every PDF: Open document, wait for the check, select the WCAG tab, PDF report,
       save under PAC's own default name, <file>_PAC_WCAG_Report.pdf, in -OutDir.
probe  Launch PAC, open the first PDF, and write PAC's UI Automation tree and screenshots to
       -OutDir. Run this when PAC's interface changes and the check mode stops finding things.

Every step has a timeout, so a dialog nobody expected fails that file instead of hanging the
run. A failing file is logged with a screenshot and the run carries on to the next one; the
exit code is the number of files that failed.
#>
param(
    [ValidateSet('check', 'probe')] [string]$Mode = 'check',
    [Parameter(Mandatory)] [string]$InputDir,
    [string[]]$Files,
    [Parameter(Mandatory)] [string]$OutDir,
    [int]$CheckTimeoutSec = 900
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PacMouse {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        mouse_event(0x02, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x04, 0, 0, 0, UIntPtr.Zero);
    }
    // Windows refuses SetForegroundWindow from a process that is not in front; borrowing
    // the foreground thread's input state for the call is the documented way round it.
    public static void Front(IntPtr h) {
        uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
        uint me = GetCurrentThreadId();
        if (fg != me) AttachThreadInput(me, fg, true);
        BringWindowToTop(h); ShowWindow(h, 5); SetForegroundWindow(h);
        if (fg != me) AttachThreadInput(me, fg, false);
    }
}
"@
$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$CT = [System.Windows.Automation.ControlType]
$PacExe = Join-Path $env:LOCALAPPDATA 'PAC\PAC.exe'
$InputDir = (Resolve-Path $InputDir).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$Log = Join-Path $OutDir 'macro.log'
$Status = Join-Path $OutDir 'status.csv'
if ($Mode -eq 'check') { Set-Content -Path $Status -Value 'file,status,seconds,pac_check_errors,detail' }

function Record([string]$file, [string]$state, [double]$sec, [int]$pacErr, [string]$detail) {
    $q = { param($v) '"' + ($v -replace '"', '""') + '"' }
    Add-Content -Path $Status -Value ('{0},{1},{2:N0},{3},{4}' -f (& $q $file), $state, $sec, $pacErr, (& $q $detail))
}

function Log([string]$m) {
    $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $m
    Write-Host $line
    Add-Content -Path $Log -Value $line
}

function Shot([string]$name) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save((Join-Path $OutDir "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function Wait-Until([scriptblock]$probe, [int]$timeoutSec, [string]$what) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        $r = & $probe
        if ($r) { return $r }
        Start-Sleep -Milliseconds 500
    }
    throw "timed out after ${timeoutSec}s waiting for $what"
}

# --- finding things ----------------------------------------------------------------
function Top-Windows([int]$procId) {
    $c = New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty, $procId)
    @($AE::RootElement.FindAll($TS::Children, $c))
}

function Find-Window([int]$procId, [string]$like) {
    # Dialogs PAC opens can be top-level windows or children of its main window.
    foreach ($w in Top-Windows $procId) {
        if ($w.Current.Name -like $like) { return $w }
        $c = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Window)
        foreach ($d in $w.FindAll($TS::Descendants, $c)) { if ($d.Current.Name -like $like) { return $d } }
    }
    $null
}

function Find-ByName($root, [string]$like, $type) {
    $c = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $type)
    foreach ($e in $root.FindAll($TS::Descendants, $c)) { if ($e.Current.Name -like $like) { return $e } }
    $null
}

function Find-Named($root, [string]$name) {
    $c = New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, $name)
    $root.FindFirst($TS::Descendants, $c)
}

function Find-ById($root, [string]$id) {
    $c = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, $id)
    $root.FindFirst($TS::Descendants, $c)
}

function Invoke-El($el) {
    # Standard Win32 buttons (the file dialogs) take Invoke; PAC's own controls are
    # DevExpress panes without it, so those are clicked at the centre of their rectangle.
    $p = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return }
    Click-El $el
}

function Click-El($el, [int]$dx = 0, [int]$dy = 0) {
    $r = $el.Current.BoundingRectangle
    if ($r.IsEmpty) { throw "element '$($el.Current.Name)' has no position on screen" }
    $x = [int]($r.X + $r.Width / 2) + $dx; $y = [int]($r.Y + $r.Height / 2) + $dy
    Click-At $x $y
}

function Click-At([int]$x, [int]$y) {
    if ($script:MainHwnd) { [PacMouse]::Front($script:MainHwnd) }
    [PacMouse]::Click($x, $y)
    Start-Sleep -Milliseconds 400
}

function Find-Like($root, [string]$like) {
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    while ($stack.Count) {
        $e = $stack.Pop()
        if ($e.Current.Name -like $like) { return $e }
        $c = $walker.GetFirstChild($e)
        while ($c) { $stack.Push($c); $c = $walker.GetNextSibling($c) }
    }
    $null
}

# The WCAG tab header is drawn by PAC, not exposed to UI Automation. It sits at a fixed
# offset from the Open document button: measured from PAC 26.0.0.0's own layout, the
# header row is 252 px below the button's top edge and the WCAG tab spans 73-123 px right
# of its left edge (73-163 once a result icon is drawn in it), so +100 is inside both.
function Click-WcagTab($pac) {
    $open = Find-Like $pac.Main 'Open document'
    if (-not $open) { throw 'cannot find the Open document button to locate the WCAG tab' }
    $r = $open.Current.BoundingRectangle
    Click-At ([int]$r.X + 100) ([int]$r.Y + 252)
}

function Dump($el, [System.IO.StreamWriter]$w, [int]$depth = 0) {
    if ($depth -gt 14) { return }
    $c = $el.Current
    $r = $c.BoundingRectangle
    # elements with no place on screen report an empty, infinite rectangle
    $rect = if ($r.IsEmpty) { 'none' } else { '{0},{1},{2}x{3}' -f [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height }
    $w.WriteLine(('{0}{1} | name="{2}" | id="{3}" | enabled={4} | rect={5}' -f
        ('  ' * $depth), $c.ControlType.ProgrammaticName, $c.Name, $c.AutomationId, $c.IsEnabled, $rect))
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($el)
    while ($child) { Dump $child $w ($depth + 1); $child = $walker.GetNextSibling($child) }
}

function Dump-To([int]$procId, [string]$name) {
    # diagnostics only: never let a dump failure stop the run
    $w = New-Object System.IO.StreamWriter (Join-Path $OutDir "$name.txt")
    try { foreach ($top in Top-Windows $procId) { Dump $top $w } }
    catch { $w.WriteLine("dump stopped: $($_.Exception.Message)") }
    finally { $w.Close() }
}

# --- PAC steps -----------------------------------------------------------------------
function Hide-Consoles {
    # The runner's own console windows sit on the desktop and can end up in front of PAC.
    foreach ($w in @($AE::RootElement.FindAll($TS::Children, [System.Windows.Automation.Condition]::TrueCondition))) {
        if ($w.Current.ClassName -in 'CASCADIA_HOSTING_WINDOW_CLASS', 'ConsoleWindowClass') {
            [PacMouse]::ShowWindow([IntPtr]$w.Current.NativeWindowHandle, 6) | Out-Null
        }
    }
}

function Start-Pac {
    Hide-Consoles
    $p = Start-Process -FilePath $PacExe -PassThru
    $main = Wait-Until { Find-Window $p.Id 'PAC*' } 180 'the PAC window'
    Start-Sleep -Seconds 3
    $script:MainHwnd = [IntPtr]$main.Current.NativeWindowHandle
    [PacMouse]::Front($script:MainHwnd)
    Log "PAC started (pid $($p.Id)): $($main.Current.Name)"
    @{ Proc = $p; Main = $main }
}

function Close-Strays {
    # After saving, PAC asks Windows to open the report; close whatever answers.
    foreach ($n in 'OpenWith', 'msedge', 'AcroRd32', 'Acrobat') {
        Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Dismiss-Errors($pac, [ref]$count) {
    $err = Find-Window $pac.Proc.Id 'Error*'
    if ($err) {
        $count.Value++
        Shot ('pac-error-{0:D2}' -f $count.Value)
        $ok = Find-Like $err 'OK'
        if ($ok) { Invoke-El $ok } else { [System.Windows.Forms.SendKeys]::SendWait('{ENTER}') }
        Log "  PAC reported that a check could not be completed; acknowledged"
        Start-Sleep -Seconds 1
        return $true
    }
    $false
}

function Set-DialogFile($pac, $dlg, [string]$path) {
    # On these runners the Windows file dialogs expose their controls only as plain panes,
    # and an element id such as "1" can be a file in the list rather than the OK button.
    # So use the keyboard: Alt+N is the dialogs' own shortcut for the file-name box, the
    # path is pasted (names like report+v2 (final).pdf hold characters SendKeys reads as
    # modifiers), and Enter is OK.
    Set-Clipboard -Value $path
    [PacMouse]::Front([IntPtr]$dlg.Current.NativeWindowHandle)
    Start-Sleep -Milliseconds 300
    foreach ($k in '%n', '^a', '^v') {
        [System.Windows.Forms.SendKeys]::SendWait($k)
        Start-Sleep -Milliseconds 250
    }
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Seconds 1
    $confirm = Find-Window $pac.Proc.Id 'Confirm*'
    if ($confirm) {
        # never overwrite anything: say No and fail this file
        [PacMouse]::Front([IntPtr]$confirm.Current.NativeWindowHandle)
        [System.Windows.Forms.SendKeys]::SendWait('n')
        throw "the dialog wanted to overwrite an existing file instead of saving $path"
    }
}

function Open-Pdf($pac, [string]$path) {
    Invoke-El (Wait-Until { Find-Like $pac.Main 'Open document' } 30 'the Open document button')
    $dlg = Wait-Until { Find-Window $pac.Proc.Id 'Select PDF file*' } 30 'the open dialog'
    Set-DialogFile $pac $dlg $path
    Start-Sleep -Seconds 1
    if (Find-Window $pac.Proc.Id 'Select PDF file*') { throw "the open dialog did not accept $path" }
}

function Check-One($pac, [string]$pdf, [ref]$errors) {
    $name = Split-Path $pdf -Leaf
    $report = Join-Path $OutDir (([IO.Path]::GetFileNameWithoutExtension($name)) + '_PAC_WCAG_Report.pdf')
    if (Test-Path $report) { Remove-Item $report -Force }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Open-Pdf $pac $pdf
    # Done when the WCAG report can be made for this file. The report button stays disabled
    # while PAC is checking, so clicking the WCAG tab and testing the button is the signal.
    Start-Sleep -Seconds 3
    Wait-Until {
        Dismiss-Errors $pac $errors | Out-Null
        Click-WcagTab $pac
        $btn = Find-Like $pac.Main 'PDF report'
        if ($btn -and $btn.Current.IsEnabled) { return $btn }
        Start-Sleep -Seconds 2
        $false
    } $CheckTimeoutSec "PAC to finish checking $name" | ForEach-Object { Invoke-El $_ }
    $dlg = Wait-Until { Find-Window $pac.Proc.Id 'Export PDF report*' } 60 'the save dialog'
    Set-DialogFile $pac $dlg $report
    Wait-Until { (Test-Path $report) -and (Get-Item $report).Length -gt 0 } 120 "the report file for $name" | Out-Null
    Start-Sleep -Seconds 2
    Close-Strays
    Log ("  ok {0} ({1:N0}s)" -f $name, $sw.Elapsed.TotalSeconds)
    $sw.Elapsed.TotalSeconds
}

# --- main ------------------------------------------------------------------------------
$pdfs = if ($Files) { $Files | ForEach-Object { Join-Path $InputDir $_ } }
        else { Get-ChildItem -Path $InputDir -Filter *.pdf | Sort-Object Name | ForEach-Object FullName }
$pdfs = @($pdfs)
if (-not $pdfs) { throw "no PDFs found in $InputDir" }
foreach ($p in $pdfs) { if (-not (Test-Path $p)) { throw "missing input: $p" } }
Log "$Mode mode, $($pdfs.Count) PDF(s) from $InputDir"
$pac = Start-Pac

if ($Mode -eq 'probe') {
    try {
        Shot 'probe-01-start'; Dump-To $pac.Proc.Id 'probe-01-start'
        Invoke-El (Wait-Until { Find-Like $pac.Main 'Open document' } 30 'the Open document button')
        $dlg = Wait-Until { Find-Window $pac.Proc.Id 'Select PDF file*' } 30 'the open dialog'
        Shot 'probe-02-open-dialog'; Dump-To $pac.Proc.Id 'probe-02-open-dialog'
        Set-DialogFile $pac $dlg $pdfs[0]
        Start-Sleep -Seconds 60
        Shot 'probe-03-checked'; Dump-To $pac.Proc.Id 'probe-03-checked'
        Click-WcagTab $pac
        Start-Sleep -Seconds 2
        Shot 'probe-04-wcag-tab'; Dump-To $pac.Proc.Id 'probe-04-wcag-tab'
        Log 'probe written'
    } catch {
        Log "probe failed: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
        Shot 'probe-error'; Dump-To $pac.Proc.Id 'probe-error'
        exit 1
    }
    exit 0
}

$failed = 0; $pacErrors = 0
$i = 0
foreach ($pdf in $pdfs) {
    $i++
    Log ("[{0}/{1}] {2}" -f $i, $pdfs.Count, (Split-Path $pdf -Leaf))
    $before = $pacErrors
    $t0 = Get-Date
    try {
        # last value only: PowerShell returns everything a function writes, not just its result
        $sec = @(Check-One $pac $pdf ([ref]$pacErrors))[-1]
        Record (Split-Path $pdf -Leaf) 'ok' $sec ($pacErrors - $before) ''
    } catch {
        $failed++
        Log "  FAILED: $($_.Exception.Message)"
        Record (Split-Path $pdf -Leaf) 'failed' ((Get-Date) - $t0).TotalSeconds ($pacErrors - $before) $_.Exception.Message
        Shot ('failed-{0:D2}' -f $i)
        try { Dump-To $pac.Proc.Id ('failed-{0:D2}-tree' -f $i) } catch {}
        # start clean for the next file
        Close-Strays
        Stop-Process -Id $pac.Proc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $pac = Start-Pac
    }
}
Log "done: $($pdfs.Count - $failed) of $($pdfs.Count) reports saved, $failed failed, $pacErrors PAC check error(s)"
exit $failed
