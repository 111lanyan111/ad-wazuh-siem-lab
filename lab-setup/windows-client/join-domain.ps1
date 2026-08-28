# Windows 客户端加入域与基础配置脚本
# 适用：Windows 10 22H2 / Windows 11 22H2
# 运行方式：以管理员身份打开 PowerShell，执行 .\join-domain.ps1

# ========== 配置区 ==========
$DomainName = "corp.local"
$DCIP = "192.168.56.20"
$DomainAdmin = "CORP\administrator"
$DomainPassword = ConvertTo-SecureString "P@ssw0rd!2024" -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($DomainAdmin, $DomainPassword)

# 根据主机名设置静态 IP
$IPMap = @{
    "WIN10-01" = "192.168.56.30"
    "WIN10-02" = "192.168.56.31"
    "WIN11-01" = "192.168.56.31"
}

# ========== 1. 配置静态 IP 与 DNS ==========
Write-Host "[1/5] 配置静态 IP 与 DNS..." -ForegroundColor Cyan
$hostname = $env:COMPUTERNAME
$staticIP = $IPMap[$hostname]
if (-not $staticIP) {
    $staticIP = "192.168.56.30"
    Write-Host "  未识别主机名，使用默认 IP: $staticIP" -ForegroundColor Yellow
}

$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
# 移除现有 DHCP IP
Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $staticIP -PrefixLength 24 -DefaultGateway "192.168.56.1" | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ($DCIP, "8.8.8.8")
Write-Host "  IP: $staticIP, DNS: $DCIP"

# ========== 2. 禁用 Windows Defender 实时保护（实验室环境） ==========
Write-Host "[2/5] 禁用 Defender 实时保护（实验室环境）..." -ForegroundColor Cyan
Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
Set-MpPreference -DisableBehaviorMonitoring $true -ErrorAction SilentlyContinue
Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue
Write-Host "  Defender 已禁用（仅用于攻击复现，生产环境勿用）"

# ========== 3. 启用 SMB1（部分攻击场景需要） ==========
Write-Host "[3/5] 启用 SMB1 与相关服务..." -ForegroundColor Cyan
Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue
Set-Service -Name LanmanServer -StartupType Automatic
Set-Service -Name LanmanWorkstation -StartupType Automatic
Write-Host "  SMB1 已启用"

# ========== 4. 加入域 ==========
Write-Host "[4/5] 加入域 $DomainName..." -ForegroundColor Cyan
Add-Computer -DomainName $DomainName -Credential $Credential -Force -Restart:$false
Write-Host "  已加入域，需要重启生效"

# ========== 5. 将域用户加入本地管理员组（模拟配置错误） ==========
Write-Host "[5/5] 配置本地管理员组（模拟脆弱配置）..." -ForegroundColor Cyan
Add-LocalGroupMember -Group "Administrators" -Member "CORP\jdoe" -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "CORP\Domain Users" -ErrorAction SilentlyContinue
Write-Host "  jdoe 已加入本地管理员组（模拟配置错误）"
Write-Host "  Domain Users 已加入远程桌面用户组"

Write-Host "`n========== 客户端配置完成 ==========" -ForegroundColor Green
Write-Host "请重启计算机使加域生效" -ForegroundColor Yellow
Write-Host "重启后以域用户 jdoe 登录"
