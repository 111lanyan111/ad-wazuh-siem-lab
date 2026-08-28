# Wazuh Agent 安装与配置脚本
# 适用：Windows 10/11 / Windows Server 2019/2022
# 运行方式：以管理员身份打开 PowerShell，执行 .\install-wazuh-agent.ps1

# ========== 配置区 ==========
$WazuhServerIP = "192.168.56.10"
$WazuhVersion = "4.7.5"
$AgentName = $env:COMPUTERNAME
$InstallDir = "C:\Program Files (x86)\ossec-agent"

# ========== 1. 下载 Wazuh Agent ==========
Write-Host "[1/4] 下载 Wazuh Agent ${WazuhVersion}..." -ForegroundColor Cyan
$msiUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-${WazuhVersion}-1.msi"
$msiPath = "$env:TEMP\wazuh-agent.msi"
Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

# ========== 2. 静默安装 ==========
Write-Host "[2/4] 静默安装 Wazuh Agent..." -ForegroundColor Cyan
$args = "/i `"$msiPath`" /q WAZUH_MANAGER=`"$WazuhServerIP`" WAZUH_AGENT_NAME=`"$AgentName`" WAZUH_REGISTRATION_SERVER=`"$WazuhServerIP`""
Start-Process msiexec.exe -ArgumentList $args -Wait -NoNewWindow

# ========== 3. 配置 ossec.conf（启用 Sysmon 日志采集） ==========
Write-Host "[3/4] 配置 ossec.conf..." -ForegroundColor Cyan
$configPath = Join-Path $InstallDir "ossec.conf"
[xml]$config = Get-Content $configPath

# 添加 Sysmon 日志采集
$localfile = $config.CreateElement("localfile")
$location = $config.CreateElement("location")
$location.InnerText = "Microsoft-Windows-Sysmon/Operational"
$logFormat = $config.CreateElement("log_format")
$logFormat.InnerText = "eventchannel"
$localfile.AppendChild($location)
$localfile.AppendChild($logFormat)
$config.ossec_config.AppendChild($localfile)

# 添加 Windows 安全日志采集（如果不存在）
$existing = $config.SelectNodes("//localfile/location[text()='Security']")
if (-not $existing) {
    $localfile2 = $config.CreateElement("localfile")
    $location2 = $config.CreateElement("location")
    $location2.InnerText = "Security"
    $logFormat2 = $config.CreateElement("log_format")
    $logFormat2.InnerText = "eventlog"
    $localfile2.AppendChild($location2)
    $localfile2.AppendChild($logFormat2)
    $config.ossec_config.AppendChild($localfile2)
}

# 添加 System 日志
$existing2 = $config.SelectNodes("//localfile/location[text()='System']")
if (-not $existing2) {
    $localfile3 = $config.CreateElement("localfile")
    $location3 = $config.CreateElement("location")
    $location3.InnerText = "System"
    $logFormat3 = $config.CreateElement("log_format")
    $logFormat3.InnerText = "eventlog"
    $localfile3.AppendChild($location3)
    $localfile3.AppendChild($logFormat3)
    $config.ossec_config.AppendChild($localfile3)
}

$config.Save($configPath)
Write-Host "  已添加 Sysmon/Security/System 日志采集"

# ========== 4. 启动服务并验证 ==========
Write-Host "[4/4] 启动 Wazuh Agent 服务..." -ForegroundColor Cyan
Restart-Service -Name "WazuhSvc" -Force
Start-Sleep -Seconds 5

$service = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq "Running") {
    Write-Host "  Wazuh Agent 服务运行正常" -ForegroundColor Green
} else {
    Write-Host "  警告：Wazuh Agent 服务未运行" -ForegroundColor Yellow
}

# 验证连接
$logFile = Join-Path $InstallDir "ossec.log"
if (Test-Path $logFile) {
    $connectLog = Get-Content $logFile -Tail 20 | Select-String -Pattern "Connected to server"
    if ($connectLog) {
        Write-Host "  已连接到 Wazuh Server: $WazuhServerIP" -ForegroundColor Green
    } else {
        Write-Host "  等待连接到 Wazuh Server..." -ForegroundColor Yellow
    }
}

Write-Host "`n========== Wazuh Agent 安装完成 ==========" -ForegroundColor Green
Write-Host "Agent 名称: $AgentName"
Write-Host "Wazuh Server: $WazuhServerIP"
Write-Host "安装目录: $InstallDir"
Write-Host "`n请在 Wazuh Dashboard 中确认 Agent 状态为 Active"
Write-Host "Dashboard: https://$WazuhServerIP"
