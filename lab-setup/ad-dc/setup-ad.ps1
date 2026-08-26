# AD 域控自动化配置脚本
# 适用：Windows Server 2019/2022
# 运行方式：以管理员身份打开 PowerShell，执行 .\setup-ad.ps1

# ========== 配置区 ==========
$DomainName = "corp.local"
$NetBIOSName = "CORP"
$DomainMode = "WinThreshold"  # Windows Server 2016 功能级别
$ForestMode = "WinThreshold"
$SafeModePassword = ConvertTo-SecureString "P@ssw0rd!2024" -AsPlainText -Force
$AdminPassword = "P@ssw0rd!2024"

# 测试用户配置
$TestUsers = @(
    @{ Name = "jdoe"; Password = "Winter2024!"; OU = "Employees"; Description = "普通用户-初始立足点" },
    @{ Name = "svc_sql"; Password = "SQL@2024pass"; OU = "Service Accounts"; Description = "SQL服务账号-弱口令" },
    @{ Name = "backup_admin"; Password = "Backup@2024"; OU = "Service Accounts"; Description = "备份操作员" }
)

# ========== 1. 设置静态 IP ==========
Write-Host "[1/6] 配置静态 IP 地址..." -ForegroundColor Cyan
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress "192.168.56.20" -PrefixLength 24 -DefaultGateway "192.168.56.1" | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ("127.0.0.1", "8.8.8.8")

# ========== 2. 重命名计算机 ==========
Write-Host "[2/6] 重命名计算机为 DC01..." -ForegroundColor Cyan
Rename-Computer -NewName "DC01" -Force

# ========== 3. 安装 AD DS 角色 ==========
Write-Host "[3/6] 安装 Active Directory 域服务..." -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

# ========== 4. 提升为域控 ==========
Write-Host "[4/6] 提升为域控制器，创建新林..." -ForegroundColor Cyan
Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBIOSName `
    -DomainMode $DomainMode `
    -ForestMode $ForestMode `
    -SafeModeAdministratorPassword $SafeModePassword `
    -InstallDns:$true `
    -NoRebootOnCompletion:$true `
    -Force:$true

# ========== 5. 创建 OU 结构 ==========
Write-Host "[5/6] 创建 OU 结构..." -ForegroundColor Cyan
$domainDN = "DC=corp,DC=local"
$OUs = @("Servers", "Workstations", "Users", "Users/Employees", "Users/Service Accounts")
foreach ($ou in $OUs) {
    $ouPath = "OU=$ou,$domainDN" -replace "/", ",OU="
    # 处理嵌套 OU
    if ($ou -match "/") {
        $parts = $ou -split "/"
        $parent = "OU=$($parts[0]),$domainDN"
        for ($i = 1; $i -lt $parts.Count; $i++) {
            $ouPath = "OU=$($parts[$i]),$parent"
            try { New-ADOrganizationalUnit -Name $parts[$i] -Path $parent -ErrorAction Stop } catch {}
            $parent = $ouPath
        }
    } else {
        try { New-ADOrganizationalUnit -Name $ou -Path $domainDN -ErrorAction Stop } catch {}
    }
}

# ========== 6. 创建测试用户 ==========
Write-Host "[6/6] 创建测试用户..." -ForegroundColor Cyan
foreach ($user in $TestUsers) {
    $userPassword = ConvertTo-SecureString $user.Password -AsPlainText -Force
    $ouPath = "OU=$($user.OU),OU=Users,$domainDN"
    New-ADUser `
        -Name $user.Name `
        -SamAccountName $user.Name `
        -UserPrincipalName "$($user.Name)@$DomainName" `
        -Path $ouPath `
        -AccountPassword $userPassword `
        -ChangePasswordAtLogon $false `
        -PasswordNeverExpires $true `
        -Enabled $true `
        -Description $user.Description
    Write-Host "  创建用户: $($user.Name)"
}

# 将 backup_admin 加入 Backup Operators 组
Add-ADGroupMember -Identity "Backup Operators" -Members "backup_admin"

Write-Host "`n========== AD 域控配置完成 ==========" -ForegroundColor Green
Write-Host "域名: $DomainName"
Write-Host "域控: DC01.$DomainName"
Write-Host "请重启计算机使配置生效" -ForegroundColor Yellow
