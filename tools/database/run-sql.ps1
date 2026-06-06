# run-sql.ps1 — Execute SQL scripts via System.Data.SqlClient (Windows Auth / Shared Memory)
# Usage: .\run-sql.ps1 [-Files file1.sql,file2.sql] [-Server 'localhost\SQLSERVER2022'] [-Database master]
param(
    [string[]]$Files = @(),
    [string]$Server   = 'localhost\SQLSERVER2022',
    [string]$Database = 'master'
)

$connStr = "Server=$Server;Database=$Database;Integrated Security=SSPI;TrustServerCertificate=True;"
$scriptDir = $PSScriptRoot

function Invoke-SqlBatches {
    param([System.Data.SqlClient.SqlConnection]$Conn, [string]$Sql, [string]$FileName)
    # Split on lines that are exactly GO (case-insensitive)
    $batches = $Sql -split '(?m)^\s*GO\s*$' | Where-Object { $_.Trim() -ne '' }
    $i = 0
    foreach ($batch in $batches) {
        $i++
        $preview = ($batch.Trim() -replace '\s+', ' ').Substring(0, [Math]::Min(80, ($batch.Trim() -replace '\s+', ' ').Length))
        try {
            $cmd = $Conn.CreateCommand()
            $cmd.CommandText = $batch
            $cmd.CommandTimeout = 120
            $cmd.ExecuteNonQuery() | Out-Null
            Write-Host "  [OK]   batch $i : $preview..." -ForegroundColor Green
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match 'already exists|There is already an object|already an index') {
                Write-Host "  [SKIP] batch $i (already exists): $preview..." -ForegroundColor Yellow
            } else {
                Write-Host "  [FAIL] batch $i : $preview..." -ForegroundColor Red
                Write-Host "         $msg" -ForegroundColor Red
                throw
            }
        }
    }
}

# Open connection
Write-Host "Connecting to $Server..." -ForegroundColor Cyan
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()
Write-Host "Connected as: $($conn.ConnectionString.Split(';') | % { $_ })" -ForegroundColor Cyan
# Show current user
$whoCmd = $conn.CreateCommand(); $whoCmd.CommandText = "SELECT SYSTEM_USER AS u"
Write-Host "Windows identity: $($whoCmd.ExecuteScalar())`n" -ForegroundColor Cyan

foreach ($file in $Files) {
    $path = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $scriptDir $file }
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "Running: $(Split-Path $path -Leaf)" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    $sql = Get-Content $path -Raw -Encoding UTF8
    Invoke-SqlBatches -Conn $conn -Sql $sql -FileName $path
    Write-Host ""
}

$conn.Close()
Write-Host "All scripts completed successfully." -ForegroundColor Green
