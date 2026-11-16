# Check-Syntax.ps1
# Запуск:  .\Check-Syntax.ps1
#
# !!! Скрипт ИЗМЕНЯЕТ кодировку файлов (только BOM/кодировку, не содержимое).
#     Перед запуском сделайте резервную копию папки на всякий случай.
#
# Шаги:
#   1) Рекурсивно находит все .ps1/.psm1 под корнем.
#   2) Приводит кодировку каждого файла к UTF-8 with BOM.
#   3) Парсит файлы парсером PowerShell и пишет отчёт в SyntaxReport.txt.

$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).ProviderPath }
$reportPath = Join-Path $root 'SyntaxReport.txt'

function Repair-FileEncoding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)

    # Уже UTF-8 с BOM — ничего не делаем
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [pscustomobject]@{ Before = 'UTF-8 with BOM'; After = 'UTF-8 with BOM'; Changed = $false }
    }
    # UTF-16 LE с BOM
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $content = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($true))
        return [pscustomobject]@{ Before = 'UTF-16 LE BOM'; After = 'UTF-8 with BOM'; Changed = $true }
    }
    # UTF-16 BE с BOM
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $content = [Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
        [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($true))
        return [pscustomobject]@{ Before = 'UTF-16 BE BOM'; After = 'UTF-8 with BOM'; Changed = $true }
    }
    # Без BOM — пробуем строгий UTF-8, при неудаче fallback на Windows-1251
    $content   = $null
    $sourceKind = $null
    try {
        $content    = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $sourceKind = 'UTF-8 no BOM'
    } catch {
        try {
            $content    = [Text.Encoding]::GetEncoding(1251).GetString($bytes)
            $sourceKind = 'Windows-1251'
        } catch {
            return [pscustomobject]@{ Before = 'unknown (no BOM, decode failed)'; After = 'unchanged'; Changed = $false }
        }
    }
    [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($true))
    return [pscustomobject]@{ Before = $sourceKind; After = 'UTF-8 with BOM'; Changed = $true }
}

# --- 1. собрать файлы ---
$targets = Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.ps1', '.psm1' } |
    Sort-Object -Property FullName -Unique

if ($targets.Count -eq 0) {
    Write-Host 'No .ps1/.psm1 files found under' $root -ForegroundColor Red
    return
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add(('Syntax + encoding report - {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$report.Add(('Host PowerShell: {0}' -f $PSVersionTable.PSVersion))
$report.Add(('Root: {0}' -f $root))
$report.Add(('Files to scan: {0}' -f $targets.Count))
$report.Add(('=' * 78))
$report.Add('')

# --- 2. починить кодировку ---
$report.Add('=== ENCODING FIX (все файлы -> UTF-8 with BOM) ===')
$report.Add('')

$fixedCount = 0
$fixedList  = New-Object System.Collections.Generic.List[string]

foreach ($file in $targets) {
    $r = Repair-FileEncoding -Path $file.FullName
    if ($r.Changed) {
        $fixedCount++
        $line = '[FIXED] {0}: {1} -> {2}' -f $file.FullName, $r.Before, $r.After
        $fixedList.Add($line)
        $report.Add($line)
    } else {
        $report.Add(('[OK]    {0}: {1}' -f $file.FullName, $r.After))
    }
}

$report.Add('')
$report.Add(('Files re-encoded: {0}' -f $fixedCount))
$report.Add('')
$report.Add('=== SYNTAX CHECK (после нормализации кодировок) ===')
$report.Add('')

# --- 3. проверить синтаксис ---
$totalErrors = 0
$errorFiles  = 0

foreach ($file in $targets) {
    $tokens = $null
    $errs   = $null
    try {
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName, [ref]$tokens, [ref]$errs)
    } catch {
        $errorFiles++
        $totalErrors++
        $report.Add(('FILE: {0}' -f $file.FullName))
        $report.Add(('  PARSE EXCEPTION: {0}' -f $_.Exception.Message))
        $report.Add('')
        continue
    }

    $errCount = 0
    if ($null -ne $errs) { $errCount = $errs.Count }

    if ($errCount -gt 0) {
        $errorFiles++
        $totalErrors += $errCount
        $report.Add(('FILE: {0}  ({1} parse errors)' -f $file.FullName, $errCount))
        $report.Add(('  {0}' -f ('-' * 74)))
        $i = 0
        foreach ($e in $errs) {
            $i++
            $text = [string]$e.Extent.Text
            if ($text.Length -gt 120) { $text = $text.Substring(0, 120) + '...' }
            $text = $text -replace "`r", '\r' -replace "`n", '\n' -replace "`t", '\t'

            $report.Add(('  [{0}] Line {1}, Col {2}: {3}' -f $i, $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message))
            $report.Add(('       ErrorId: {0}' -f $e.ErrorId))
            $report.Add(('       Text: {0}' -f $text))

            # Не-ASCII в тексте ошибки (кириллица ожидаема — ищем именно «мусор»)
            $bad = foreach ($c in $text.ToCharArray()) {
                $n = [int]$c
                if ($n -ge 0x80 -and $n -le 0xFFFF -and -not ($n -ge 0x0400 -and $n -le 0x04FF)) {
                    'U+{0:X4} ({1})' -f $n, $c
                }
            }
            if ($bad) {
                $report.Add(('       Non-ASCII: {0}' -f (($bad | Select-Object -Unique) -join ', ')))
            }
            $report.Add('')
        }
        $report.Add('')
    } else {
        $report.Add(('OK   {0}' -f $file.FullName))
    }
}

# --- 4. итог ---
$report.Add(('=' * 78))
$report.Add('SUMMARY')
$report.Add(('  Files scanned:       {0}' -f $targets.Count))
$report.Add(('  Files re-encoded:    {0}' -f $fixedCount))
$report.Add(('  Files with errors:   {0}' -f $errorFiles))
$report.Add(('  Total parse errors:  {0}' -f $totalErrors))

# Явно UTF-8 with BOM для отчёта (не зависит от версии PS)
[IO.File]::WriteAllLines($reportPath, $report, [Text.UTF8Encoding]::new($true))

$color = if ($totalErrors -gt 0) { 'Yellow' } else { 'Green' }
Write-Host ('Report: {0}' -f $reportPath) -ForegroundColor Cyan
Write-Host ('Files: {0}  |  Re-encoded: {1}  |  Files with errors: {2}  |  Total errors: {3}' -f `
    $targets.Count, $fixedCount, $errorFiles, $totalErrors) -ForegroundColor $color

if ($fixedList.Count -gt 0) {
    Write-Host ''
    Write-Host 'Re-encoded files:' -ForegroundColor Cyan
    $fixedList | ForEach-Object { Write-Host "  $_" }
}
if ($errorFiles -gt 0) {
    Write-Host ''
    Write-Host 'Files with parse errors — see SyntaxReport.txt' -ForegroundColor Yellow
}