# Sysmon 安装与配置脚本
# 适用：Windows 10/11 / Windows Server 2019/2022
# 运行方式：以管理员身份打开 PowerShell，执行 .\install-sysmon.ps1

# ========== 配置区 ==========
$SysmonVersion = "14.18"
$SysmonURL = "https://download.sysinternals.com/files/Sysmon.zip"
$InstallDir = "C:\Program Files\Sysmon"
$ConfigFile = "$PSScriptRoot\sysmon-config.xml"

# ========== 1. 下载 Sysmon ==========
Write-Host "[1/4] 下载 Sysmon ${SysmonVersion}..." -ForegroundColor Cyan
$tempZip = "$env:TEMP\Sysmon.zip"
Invoke-WebRequest -Uri $SysmonURL -OutFile $tempZip -UseBasicParsing

# ========== 2. 解压到安装目录 ==========
Write-Host "[2/4] 解压到 $InstallDir..." -ForegroundColor Cyan
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
Expand-Archive -Path $tempZip -DestinationPath $InstallDir -Force
Remove-Item $tempZip -Force

# 选择对应架构的可执行文件
$arch = if ([Environment]::Is64BitOperatingSystem) { "Sysmon64.exe" } else { "Sysmon.exe" }
$sysmonExe = Join-Path $InstallDir $arch

# ========== 3. 安装 Sysmon 并加载配置 ==========
Write-Host "[3/4] 安装 Sysmon 并加载配置..." -ForegroundColor Cyan
if (-not (Test-Path $ConfigFile)) {
    Write-Host "  错误：配置文件不存在: $ConfigFile" -ForegroundColor Red
    exit 1
}

# 复制配置文件到安装目录
Copy-Item $ConfigFile -Destination (Join-Path $InstallDir "sysmon-config.xml") -Force

# 检查是否已安装
$service = Get-Service -Name "Sysmon*" -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "  Sysmon 已安装，更新配置..."
    & $sysmonExe -c (Join-Path $InstallDir "sysmon-config.xml") -accepteula
} else {
    Write-Host "  全新安装 Sysmon..."
    & $sysmonExe -i (Join-Path $InstallDir "sysmon-config.xml") -accepteula -n
}

# ========== 4. 验证安装 ==========
Write-Host "[4/4] 验证安装..." -ForegroundColor Cyan
Start-Sleep -Seconds 3
$service = Get-Service -Name "Sysmon*" -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq "Running") {
    Write-Host "  Sysmon 服务运行正常: $($service.Name)" -ForegroundColor Green
} else {
    Write-Host "  警告：Sysmon 服务未运行" -ForegroundColor Yellow
}

# 验证事件日志通道
$eventLog = Get-WinEvent -ListLog "Microsoft-Windows-Sysmon/Operational" -ErrorAction SilentlyContinue
if ($eventLog) {
    Write-Host "  事件日志通道: $($eventLog.LogName)" -ForegroundColor Green
    Write-Host "  最大日志大小: $([math]::Round($eventLog.MaximumSizeInBytes/1MB, 2)) MB"
}

Write-Host "`n========== Sysmon 安装完成 ==========" -ForegroundColor Green
Write-Host "安装目录: $InstallDir"
Write-Host "配置文件: $InstallDir\sysmon-config.xml"
Write-Host "事件查看器路径: 应用程序和服务日志 > Microsoft > Windows > Sysmon > Operational"
Write-Host "`n常用命令："
Write-Host "  查看配置: & $sysmonExe -c"
Write-Host "  更新配置: & $sysmonExe -c <新配置文件>"
Write-Host "  卸载: & $sysmonExe -u force"
