#!/usr/bin/env python3

import os
import sys
import subprocess
import re
import json
import urllib.parse
import urllib.request
from datetime import datetime

RED = r"\e[31m"
GREEN = r"\e[32m"
YELLOW = r"\e[33m"
BLUE = r"\e[34m"
CYAN = r"\e[36m"
RESET = r"\e[0m"

VERSION = "1.0"
DATE = datetime.now().strftime("%F_%H-%M-%S")
HOST = os.environ.get('HOSTNAME') or subprocess.getoutput('hostname').strip() or "unknown"
REPORT = f"stealth_enum_{HOST}_{DATE}.log"
JSON_FILE = f"stealth_enum_{HOST}_{DATE}.json"

VULN_COUNT = 0
GTFO_COUNT = 0
SUID_COUNT = 0
CVE_CRITICAL = 0

RUN_AS_ROOT = os.geteuid() == 0 if hasattr(os, 'geteuid') else subprocess.getoutput('id -u') == '0'
if not RUN_AS_ROOT:
    YELLOW = r"\e[33m"
    CYAN = r"\e[36m"

def banner(msg):
    print(f"\n{BLUE}{'='*64}{RESET}\n{CYAN}{msg}{RESET}\n{BLUE}{'='*64}{RESET}")

def section(msg):
    print(f"\n{YELLOW}[+] {msg}{RESET}")

def progress(msg):
    print(f"{CYAN}[*] {msg}... {RESET}", end='', flush=True)
    import time; time.sleep(0.3)
    print(f"{GREEN}✓{RESET}")

def safe_cmd(cmd):
    print(f"\n{GREEN}$ {cmd}{RESET}")
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, timeout=10)
        if result.stdout:
            print(result.stdout.decode('utf-8', errors='ignore'))
        return result.stdout.decode('utf-8', errors='ignore') if result.stdout else ""
    except:
        return ""

def exists_cmd(cmd):
    return subprocess.getoutput(f'command -v {cmd} 2>/dev/null') != ""

def get_kernel():
    with open('/proc/version', 'r') as f:
        return f.read().strip().split()[2].strip('()')

if not os.path.exists('/proc/cpuinfo'):
    print(f"\n{RED}[!] ERROR: This script requires Linux!{RESET}")
    print(f"{RED}[!] Detected: {os.uname().sysname}{RESET}")
    print(f"{YELLOW}[!] /proc/cpuinfo not found. This tool is for Linux only.{RESET}\n")
    sys.exit(1)

banner(f"Advanced Stealth Enumeration Framework v{VERSION} (Python)")

if not RUN_AS_ROOT:
    print(f"\n{YELLOW}[!] WARNING: Running without root privileges{RESET}")
    print(f"{YELLOW}[!] Some features will be limited (SUID, capabilities, etc.){RESET}")
    print(f"{YELLOW}[!] For full enumeration, run with: sudo python3 {sys.argv[0]}{RESET}\n")

LOG_DIR = "/tmp" if os.path.isdir("/tmp") else "."
LOG_PATH = f"{LOG_DIR}/{REPORT}"

LOG_FILE = None
def tee_print(*args, **kwargs):
    msg = ' '.join(str(a) for a in args)
    print(msg, **kwargs)
    if LOG_FILE:
        LOG_FILE.write(msg + '\n')

LOG_FILE = open(LOG_PATH, 'a')

section("Dependencies Check")

missing_deps = []
for cmd in ['curl', 'find']:
    if exists_cmd(cmd):
        print(f"{GREEN}[+] {cmd}: OK{RESET}")
    else:
        print(f"{RED}[!] {cmd}: MISSING{RESET}")
        missing_deps.append(cmd)

if missing_deps:
    print(f"\n{YELLOW}[!] Some dependencies missing. Some features may not work.{RESET}")

section("Basic System Info")

USER_NAME = subprocess.getoutput('whoami')
KERNEL = get_kernel()
OS = subprocess.getoutput('cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2')

safe_cmd("date")
safe_cmd("hostname")
safe_cmd("id")
safe_cmd("uname -a")

section("Kernel Enumeration")

safe_cmd("uname -r")
safe_cmd("cat /proc/version")
safe_cmd("sysctl kernel.randomize_va_space")
safe_cmd("sysctl kernel.kptr_restrict")
safe_cmd("sysctl kernel.dmesg_restrict")

print("\n[+] Possible Kernel Exploit Indicators")
fs_content = subprocess.getoutput('cat /proc/filesystems 2>/dev/null')
for line in fs_content.split('\n'):
    if any(x in line for x in ['overlay', 'fuse', 'bpf', 'userns', 'io_uring']):
        print(line)

config_file = f"/boot/config-{KERNEL}"
if os.path.exists(config_file):
    for pattern in ['CONFIG_USER_NS', 'CONFIG_BPF', 'CONFIG_IO_URING']:
        print(subprocess.getoutput(f'grep {pattern} {config_file} 2>/dev/null'))

section("Users & Privileges")

safe_cmd("id")
safe_cmd("groups")
safe_cmd("sudo -l")

print("\n[+] Home Directories")
print(subprocess.getoutput('ls -lah /home 2>/dev/null'))

section("GTFOBins & Sudo Abuse")

sudo_l = subprocess.getoutput('sudo -l 2>/dev/null')
print(sudo_l)

gtfobins = ['vim', 'vi', 'nano', 'less', 'more', 'awk', 'find', 'perl', 'python', 'python2', 'python3', 'ruby', 'php', 'tar', 'zip', 'bash', 'sh', 'env', 'tee', 'node', 'npm', 'lua', 'irb']
for bin in gtfobins:
    if bin.lower() in sudo_l.lower():
        print(f"{RED}[!] GTFOBIN: {bin}{RESET}")
        GTFO_COUNT += 1

section("SUID / SGID")

VULN_SUIDS = [
    'nmap', 'vim', 'find', 'bash', 'sh', 'dash', 'zsh', 'tcsh', 'csh',
    'perl', 'python', 'python2', 'python3', 'ruby', 'php', 'node', 'npm',
    'lua', 'irb', 'cat', 'more', 'less', 'head', 'tail', 'cp', 'mv',
    'nano', 'pico', 'vi', 'gedit', 'kate', 'tar', 'zip', 'gzip',
    'awk', 'gawk', 'sed', 'cut', 'sort', 'uniq', 'wget', 'curl', 'fetch',
    'mount', 'umount', 'su', 'sudo', 'chmod', 'chown', 'chgrp',
    'nmap', 'masscan', 'netcat', 'nc', 'socat', 'telnet', 'ssh'
]

suid_list = subprocess.getoutput('find / -perm -4000 -type f 2>/dev/null | head -200')
print(suid_list)

print("\n[+] Interesting SUID (Potential Exploits)")
for suid in suid_list.split('\n'):
    if not suid:
        continue
    name = os.path.basename(suid)
    if name in VULN_SUIDS:
        print(f"{RED}[!] VULNERABLE SUID: {suid} ({name}){RESET}")
        SUID_COUNT += 1
        VULN_COUNT += 1

section("Linux Capabilities")

if exists_cmd("getcap"):
    print(subprocess.getoutput('getcap -r / 2>/dev/null'))

section("Network")

safe_cmd("ip a")
safe_cmd("ip route")
safe_cmd("ss -tulpn")
safe_cmd("arp -a")

print("\n[+] Established Connections")
print(subprocess.getoutput('ss -antp 2>/dev/null | grep ESTAB'))

section("Processes")

print(subprocess.getoutput('ps aux --forest 2>/dev/null | head -200'))

print("\n[+] Interesting Processes")
print(subprocess.getoutput('ps aux | egrep -i "mysql|mariadb|postgres|redis|docker|nginx|apache|httpd|php-fpm|node|java"'))

section("Cron Jobs")

print(subprocess.getoutput('crontab -l 2>/dev/null'))
print(subprocess.getoutput('ls -lah /etc/cron* 2>/dev/null'))

section("Containers")

if os.path.exists('/.dockerenv'):
    print(f"{RED}[!] Docker detected (.dockerenv exists){RESET}")

print(subprocess.getoutput('grep docker /proc/1/cgroup 2>/dev/null'))

if exists_cmd("docker"):
    print(subprocess.getoutput('docker ps -a 2>/dev/null'))

section("Cloud / VM Detection")

print(subprocess.getoutput('grep -i hypervisor /proc/cpuinfo'))
print(subprocess.getoutput('dmesg 2>/dev/null | grep -i virtual'))

section("CloudLinux / cPanel")

if os.path.exists('/usr/sbin/lvectl'):
    print("[+] CloudLinux detected")

if os.path.isdir('/usr/local/cpanel'):
    print(subprocess.getoutput('cat /usr/local/cpanel/version 2>/dev/null'))

section("Web Enumeration")

print(subprocess.getoutput('find /var/www/ -type f 2>/dev/null | egrep "\\.env|config|wp-config|database|settings|\\.bak"'))
print(subprocess.getoutput('find /home/ -type f 2>/dev/null | egrep "\\.env|config|wp-config|database|settings|\\.bak"'))

print("\n[+] Writable Web Files")
print(subprocess.getoutput('find /var/www/ -writable -type f 2>/dev/null | head -50'))
print(subprocess.getoutput('find /home/ -writable -type f 2>/dev/null | head -50'))

section("Secrets Discovery")

print(subprocess.getoutput('grep -Ri "password" /var/www/ 2>/dev/null | head -50'))
print(subprocess.getoutput('grep -Ri "password" /home/ 2>/dev/null | head -50'))
print(subprocess.getoutput('find /var/www/ /home/ -name ".env" 2>/dev/null | head -50'))
print(subprocess.getoutput('find / -name "id_rsa*" 2>/dev/null'))
print(subprocess.getoutput('find / -name "*.pem" 2>/dev/null | head -50'))

section("PATH Hijacking")

print(f"PATH: {os.environ.get('PATH', '')}")
print(subprocess.getoutput('find . -writable -type d 2>/dev/null'))

section("Mounts")

print(subprocess.getoutput('mount'))
print(subprocess.getoutput('df -h'))
print(subprocess.getoutput('cat /etc/fstab 2>/dev/null'))

section("Security Products")

print(subprocess.getoutput('ps aux | egrep -i "clamav|crowdstrike|falcon|wazuh|ossec|auditd|defender|sentinel"'))

section("LDAP / Active Directory")

print(subprocess.getoutput('cat /etc/krb5.conf 2>/dev/null'))
print(subprocess.getoutput('grep -Ri ldap /etc 2>/dev/null | head -50'))

section("Persistence Checks")

print(subprocess.getoutput('ls -lah ~/.ssh 2>/dev/null'))
print(subprocess.getoutput('cat ~/.bashrc 2>/dev/null | tail -20'))
print(subprocess.getoutput('cat ~/.profile 2>/dev/null | tail -20'))

section("Quick Vulnerability Checks")

print("\n[+] Writable passwd?")
if os.access('/etc/passwd', os.W_OK):
    print(f"{RED}[!] VULNERABLE: Writable /etc/passwd{RESET}")
    VULN_COUNT += 1

print("\n[+] Writable shadow?")
if os.access('/etc/shadow', os.W_OK):
    print(f"{RED}[!] CRITICAL: Writable /etc/shadow{RESET}")
    VULN_COUNT += 1

print("\n[+] Dangerous Sudo")
nopasswd = subprocess.getoutput('sudo -l 2>/dev/null | grep NOPASSWD')
if nopasswd:
    print(f"{RED}[!] NOPASSWD Sudo found:{RESET}")
    print(nopasswd)
    VULN_COUNT += 1

section("CVE Mapping (NVD NIST)")

search_term = f"linux kernel {KERNEL}"
encoded = urllib.parse.quote(search_term)
api_url = f"https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch={encoded}&resultsPerPage=20"

print(f"\n{CYAN}[*] Querying NVD NIST API for kernel CVEs...{RESET}\n")

try:
    req = urllib.request.Request(api_url, headers={'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as response:
        cve_data = json.loads(response.read().decode())
except Exception as e:
    cve_data = {}

total = cve_data.get('totalResults', 0)

if not total:
    match = re.match(r'(\d+\.\d+)', KERNEL)
    if match:
        search_term = f"linux kernel {match.group(1)}"
        encoded = urllib.parse.quote(search_term)
        api_url = f"https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch={encoded}&resultsPerPage=20"
        try:
            req = urllib.request.Request(api_url, headers={'Accept': 'application/json'})
            with urllib.request.urlopen(req, timeout=30) as response:
                cve_data = json.loads(response.read().decode())
        except:
            cve_data = {}
        total = cve_data.get('totalResults', 0)

print(f"{GREEN}[+] Found {total} potential CVEs{RESET}\n\n")

if total > 0:
    for vuln in cve_data.get('vulnerabilities', []):
        cve = vuln.get('cve', {})
        cve_id = cve.get('id', 'N/A')
        desc = cve.get('descriptions', [{}])[0].get('value', 'N/A')
        desc = desc[:150]

        severity = 'N/A'
        score = 'N/A'

        metrics = cve.get('metrics', {})
        if metrics.get('cvssMetricV31'):
            cvss = metrics['cvssMetricV31'][0]['cvssData']
            severity = cvss.get('baseSeverity', 'N/A')
            score = cvss.get('baseScore', 'N/A')
        elif metrics.get('cvssMetricV30'):
            cvss = metrics['cvssMetricV30'][0]['cvssData']
            severity = cvss.get('baseSeverity', 'N/A')
            score = cvss.get('baseScore', 'N/A')
        elif metrics.get('cvssMetricV2'):
            cvss = metrics['cvssMetricV2'][0]['cvssData']
            severity = cvss.get('baseSeverity', 'N/A')
            score = cvss.get('baseScore', 'N/A')

        if severity in ('CRITICAL', 'HIGH'):
            print(f"{RED}[{severity}] {cve_id} (CVSS: {score}){RESET}")
            CVE_CRITICAL += 1
        elif severity in ('MEDIUM', 'MODERATE'):
            print(f"{YELLOW}[{severity}] {cve_id} (CVSS: {score}){RESET}")
        else:
            print(f"{CYAN}[{severity}] {cve_id} (CVSS: {score}){RESET}")

        print(f"    {desc}")

print(f"\n{CYAN}[*] CVE Lookup Complete{RESET}")
print(f"{CYAN}[*] Reference: https://nvd.nist.gov/vuln/search/results?query={urllib.parse.quote(KERNEL)}{RESET}\n\n")

section("PRIVILEGE ESCALATION SUMMARY")

print("============================================")
print(f"{CYAN}Findings Summary:{RESET}")
print("============================================")
print(f"  GTFOBin candidates: {YELLOW}{GTFO_COUNT}{RESET}")
print(f"  Vulnerable SUID:     {RED}{SUID_COUNT}{RESET}")
print(f"  Critical CVEs:       {RED}{CVE_CRITICAL}{RESET}")
print(f"  Total vulns:        {RED}{VULN_COUNT}{RESET}")
print("============================================")

if VULN_COUNT > 0 or GTFO_COUNT > 0 or SUID_COUNT > 0:
    print(f"\n{RED}[!] Privilege Escalation vectors found!{RESET}")
    print(f"{CYAN}[*] Review highlighted findings above{RESET}")

banner("ENUMERATION COMPLETE")

print(f"\n{GREEN}[+] Report:{RESET} {LOG_DIR}/{REPORT}")
print(f"{GREEN}[+] JSON:{RESET} {LOG_DIR}/{JSON_FILE}")

LOG_FILE.close()

with open(f"{LOG_DIR}/{JSON_FILE}", 'w') as f:
    json.dump({
        'host': HOST,
        'user': USER_NAME,
        'kernel': KERNEL,
        'os': OS,
        'report': REPORT,
        'date': str(datetime.now()),
        'findings': {
            'gtfobins': GTFO_COUNT,
            'vulnerable_suid': SUID_COUNT,
            'critical_cves': CVE_CRITICAL,
            'total_vulns': VULN_COUNT
        }
    }, f, indent=2)
