#!/bin/bash
# Wazuh Server 一键安装脚本
# 适用：Ubuntu Server 22.04 LTS
# 运行方式：sudo bash install-wazuh.sh

set -e

WAZUH_VERSION="4.7.5"
WAZUH_API_USER="wazuh"
WAZUH_API_PASS="Wazuh@2024"

echo "=========================================="
echo "  Wazuh Server 安装脚本 v${WAZUH_VERSION}"
echo "=========================================="

# ========== 1. 系统更新与依赖 ==========
echo "[1/7] 更新系统并安装依赖..."
apt-get update -qq
apt-get install -y -qq curl apt-transport-https lsb-release gnupg2 unzip

# ========== 2. 设置静态 IP ==========
echo "[2/7] 配置静态 IP (192.168.56.10)..."
cat > /etc/netplan/01-static.yaml << 'EOF'
network:
  version: 2
  ethernets:
    enp0s3:
      addresses:
        - 192.168.56.10/24
      gateway4: 192.168.56.1
      nameservers:
        addresses: [8.8.8.8, 192.168.56.20]
EOF
chmod 600 /etc/netplan/01-static.yaml
netplan apply || echo "Netplan 应用可能需要重启"

# ========== 3. 添加 Wazuh GPG 密钥与仓库 ==========
echo "[3/7] 添加 Wazuh 仓库..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list

# ========== 4. 安装 Wazuh Manager ==========
echo "[4/7] 安装 Wazuh Manager..."
apt-get update -qq
apt-get install -y wazuh-manager=${WAZUH_VERSION}-1

# ========== 5. 安装 Filebeat ==========
echo "[5/7] 安装 Filebeat..."
curl -s https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/elasticsearch.gpg --import
chmod 644 /usr/share/keyrings/elasticsearch.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic.list
apt-get update -qq
apt-get install -y filebeat=7.17.13

# 配置 Filebeat
curl -so /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.7/tpl/wazuh/filebeat/filebeat.yml
systemctl daemon-reload
systemctl enable filebeat
systemctl start filebeat

# ========== 6. 安装 Wazuh Indexer (OpenSearch) ==========
echo "[6/7] 安装 Wazuh Indexer..."
apt-get install -y wazuh-indexer=${WAZUH_VERSION}-1

# 配置 Wazuh Indexer
cat > /etc/wazuh-indexer/opensearch.yml << 'EOF'
network.host: "0.0.0.0"
node.name: "wazuh-indexer"
cluster.initial_master_nodes:
  - "wazuh-indexer"
cluster.name: "wazuh"
discovery.seed_hosts:
  - "127.0.0.1"
path.data: /var/lib/wazuh-indexer
path.logs: /var/log/wazuh-indexer
plugins.security.ssl.http.enabled: false
plugins.security.ssl.transport.enforce_hostname_verification: false
EOF

systemctl daemon-reload
systemctl enable wazuh-indexer
systemctl start wazuh-indexer

# 等待 Indexer 启动
echo "等待 Wazuh Indexer 启动..."
sleep 15

# 初始化索引
curl -X PUT "http://localhost:9200/wazuh-alerts-4.x-000001" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "index": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    }
  }
}' || echo "索引创建可能已存在"

# ========== 7. 安装 Wazuh Dashboard ==========
echo "[7/7] 安装 Wazuh Dashboard..."
apt-get install -y wazuh-dashboard=${WAZUH_VERSION}-1

# 配置 Dashboard
cat > /etc/wazuh-dashboard/opensearch_dashboards.yml << 'EOF'
server.host: "0.0.0.0"
server.port: 443
opensearch.hosts: http://127.0.0.1:9200
opensearch.ssl.verificationMode: none
EOF

systemctl daemon-reload
systemctl enable wazuh-dashboard
systemctl start wazuh-dashboard

# ========== 配置 Wazuh API ==========
echo "配置 Wazuh API..."
cat > /var/ossec/api/configuration/api.yaml << EOF
host: 0.0.0.0
port: 55000
intervals:
  request_timeout: 10000
https:
  enabled: yes
  key: "server.key"
  cert: "server.crt"
  use_ca: False
  ca: "ca.crt"
  ssl_protocol: "TLSv1.2"
  ssl_ciphers: ""
EOF

# 重启 Wazuh Manager
systemctl restart wazuh-manager

# ========== 完成 ==========
echo ""
echo "=========================================="
echo "  Wazuh Server 安装完成！"
echo "=========================================="
echo "Dashboard: https://192.168.56.10"
echo "默认账号: admin / admin (首次登录请修改)"
echo "Wazuh API: https://192.168.56.10:55000"
echo ""
echo "下一步：在 Windows 主机上安装 Wazuh Agent"
echo "Agent 下载: https://packages.wazuh.com/4.x/windows/wazuh-agent-${WAZUH_VERSION}-1.msi"
