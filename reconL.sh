#!/usr/bin/env bash
export LC_ALL=C
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VERSION="1.0"
DATE=$(date +%F_%H-%M-%S)
HOST=$(hostname 2>/dev/null)

if [ -w "/tmp" ]; then
    LOG_DIR="/tmp"
else
    LOG_DIR="."
fi

REPORT="stealth_enum_${HOST}_${DATE}.log"
JSON="stealth_enum_${HOST}_${DATE}.json"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

VULN_COUNT=0
GTFO_COUNT=0
SUID_COUNT=0
CVE_CRITICAL=0

if [ "$(id -u)" -ne 0 ]; then
    RUN_AS_ROOT=0
    YELLOW="\e[33m"
    CYAN="\e[36m"
else
    RUN_AS_ROOT=1
fi

banner() {
    echo -e "\n${BLUE}================================================================${RESET}"
    echo -e "${CYAN}$1${RESET}"
    echo -e "${BLUE}================================================================${RESET}"
}

section() {
    echo -e "\n${YELLOW}[+] $1${RESET}"
}

exists() {
    command -v "$1" >/dev/null 2>&1
}

safe_cmd() {
    echo -e "\n${GREEN}\$ $*${RESET}"
    timeout 10 bash -c "$*" 2>/dev/null
}

json_escape() {
    echo "$1" | sed 's/"/\\"/g'
}

if [ ! -f "/proc/cpuinfo" ]; then
    echo -e "\n${RED}[!] ERROR: This script requires Linux!${RESET}"
    echo -e "${RED}[!] Detected: $(uname -s)${RESET}"
    echo -e "${YELLOW}[!] /proc/cpuinfo not found. This tool is for Linux only.${RESET}\n"
    exit 1
fi

banner "Advanced Stealth Enumeration Framework v$VERSION"

if [ "$RUN_AS_ROOT" -eq 0 ]; then
    echo -e "\n${YELLOW}[!] WARNING: Running without root privileges${RESET}"
    echo -e "${YELLOW}[!] Some features will be limited (SUID, capabilities, etc.)${RESET}"
    echo -e "${YELLOW}[!] For full enumeration, run with: sudo $0${RESET}\n"
fi

section "Dependencies Check"

MISSING_DEPS=0
for cmd in curl find jq; do
    if exists "$cmd"; then
        echo -e "${GREEN}[+] $cmd: OK${RESET}"
    else
        echo -e "${RED}[!] $cmd: MISSING${RESET}"
        MISSING_DEPS=1
    fi
done

[ $MISSING_DEPS -eq 1 ] && echo -e "\n${YELLOW}[!] Some dependencies missing. Some features may not work.${RESET}"

section "Basic System Info"

USER_NAME=$(whoami)
KERNEL=$(uname -r)
OS=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2)

safe_cmd "date"
safe_cmd "hostname"
safe_cmd "id"
safe_cmd "uname -a"

section "Kernel Enumeration"

safe_cmd "uname -r"
safe_cmd "cat /proc/version"
safe_cmd "sysctl kernel.randomize_va_space"
safe_cmd "sysctl kernel.kptr_restrict"
safe_cmd "sysctl kernel.dmesg_restrict"

echo -e "\n[+] Possible Kernel Exploit Indicators"
grep -E "overlay|fuse|bpf|userns|io_uring" /proc/filesystems 2>/dev/null

[ -f "/boot/config-$(uname -r)" ] && {
    grep CONFIG_USER_NS /boot/config-$(uname -r)
    grep CONFIG_BPF /boot/config-$(uname -r)
    grep CONFIG_IO_URING /boot/config-$(uname -r)
}

section "Users & Privileges"

safe_cmd "id"
safe_cmd "groups"
safe_cmd "sudo -l"
echo -e "\n[+] Home Directories"
ls -lah /home 2>/dev/null

section "GTFOBins & Sudo Abuse"

sudo -l 2>/dev/null | tee /tmp/.sudo_enum.$$ >/dev/null

for bin in vim vi nano less more awk find perl python python3 ruby python2 python3.11 python3.10 python3.9 tar zip bash sh env tee; do
    grep -qi "$bin" /tmp/.sudo_enum.$$ 2>/dev/null && echo -e "${RED}[!] GTFOBIN: $bin${RESET}" && ((GTFO_COUNT++))
done

rm -f /tmp/.sudo_enum.$$

section "SUID / SGID"

declare -a VULN_SUIDS=(
    "nmap" "vim" "find" "bash" "sh" "dash" "zsh" "tcsh" "csh"
    "perl" "python" "python2" "python3" "ruby" "php" "node" "npm"
    "lua" "irb" "cat" "more" "less" "head" "tail" "cp" "mv"
    "nano" "pico" "vi" "gedit" "kate" "tar" "zip" "gzip"
    "awk" "gawk" "sed" "cut" "sort" "uniq" "wget" "curl" "fetch"
    "mount" "umount" "su" "sudo" "chmod" "chown" "chgrp"
    "nmap" "masscan" "netcat" "nc" "socat" "telnet" "ssh"
)

SUID_LIST=$(find / -perm -4000 -type f 2>/dev/null | head -200)
echo "$SUID_LIST"

echo -e "\n[+] Interesting SUID (Potential Exploits)"
while IFS= read -r suid; do
    [ -z "$suid" ] && continue
    name=$(basename "$suid")
    for vuln in "${VULN_SUIDS[@]}"; do
        if [ "$name" = "$vuln" ]; then
            echo -e "${RED}[!] VULNERABLE SUID: $suid ($name)${RESET}"
            ((SUID_COUNT++))
            ((VULN_COUNT++))
            break
        fi
    done
done <<< "$SUID_LIST"

section "Linux Capabilities"

exists getcap && getcap -r / 2>/dev/null

section "Network"

safe_cmd "ip a"
safe_cmd "ip route"
safe_cmd "ss -tulpn"
safe_cmd "arp -a"
echo -e "\n[+] Established Connections"
ss -antp 2>/dev/null | grep ESTAB

section "Processes"

ps aux --forest 2>/dev/null | head -200
echo -e "\n[+] Interesting Processes"
ps aux | egrep -i "mysql|mariadb|postgres|redis|docker|nginx|apache|httpd|php-fpm|node|java"

section "Cron Jobs"

crontab -l 2>/dev/null
ls -lah /etc/cron* 2>/dev/null

section "Containers"

[ -f /.dockerenv ] && echo -e "${RED}[!] Docker detected (.dockerenv exists)${RESET}"
grep docker /proc/1/cgroup 2>/dev/null
exists docker && docker ps -a 2>/dev/null

section "Cloud / VM Detection"

grep -i hypervisor /proc/cpuinfo
dmesg 2>/dev/null | grep -i virtual

section "CloudLinux / cPanel"

[ -f /usr/sbin/lvectl ] && echo "[+] CloudLinux detected"
[ -d /usr/local/cpanel ] && cat /usr/local/cpanel/version 2>/dev/null

section "Web Enumeration"

find /var/www/ -type f 2>/dev/null | egrep "\.env|config|wp-config|database|settings|\.bak"
find /home/ -type f 2>/dev/null | egrep "\.env|config|wp-config|database|settings|\.bak"
echo -e "\n[+] Writable Web Files"
find /var/www/ -writable -type f 2>/dev/null | head -50
find /home/ -writable -type f 2>/dev/null | head -50

section "Secrets Discovery"

grep -Ri "password" /var/www/ 2>/dev/null | head -50
grep -Ri "password" /home/ 2>/dev/null | head -50
find /var/www/ /home/ -name ".env" 2>/dev/null | head -50
find / -name "id_rsa*" 2>/dev/null
find / -name "*.pem" 2>/dev/null | head -50

section "PATH Hijacking"

echo "PATH: $PATH"
find . -writable -type d 2>/dev/null

section "Mounts"

mount
df -h
cat /etc/fstab 2>/dev/null

section "Security Products"

ps aux | egrep -i "clamav|crowdstrike|falcon|wazuh|ossec|auditd|defender|sentinel"

section "LDAP / Active Directory"

cat /etc/krb5.conf 2>/dev/null
grep -Ri ldap /etc 2>/dev/null | head -50

section "Persistence Checks"

ls -lah ~/.ssh 2>/dev/null
cat ~/.bashrc 2>/dev/null | tail -20
cat ~/.profile 2>/dev/null | tail -20

section "Quick Vulnerability Checks"

echo -e "\n[+] Writable passwd?"
[ -w /etc/passwd ] && echo -e "${RED}[!] VULNERABLE: Writable /etc/passwd${RESET}" && ((VULN_COUNT++))

echo -e "\n[+] Writable shadow?"
[ -w /etc/shadow ] && echo -e "${RED}[!] CRITICAL: Writable /etc/shadow${RESET}" && ((VULN_COUNT++))

echo -e "\n[+] Dangerous Sudo"
NOPASSWD=$(sudo -l 2>/dev/null | grep NOPASSWD)
[ -n "$NOPASSWD" ] && echo -e "${RED}[!] NOPASSWD Sudo found:${RESET}" && echo "$NOPASSWD" && ((VULN_COUNT++))

section "CVE Mapping (NVD NIST)"

CVE_KERNEL=$(uname -r)
CVE_API="https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=linux%20kernel%20${CVE_KERNEL}&resultsPerPage=20"

echo -e "\n${CYAN}[*] Querying NVD NIST API for kernel CVEs...${RESET}"

CVE_RESP=$(curl -s --max-time 30 -H "Accept: application/json" "${CVE_API}" 2>/dev/null)

if exists jq; then
    CVE_TOTAL=$(echo "$CVE_RESP" | jq -r '.totalResults // 0' 2>/dev/null)
    [ "$CVE_TOTAL" -eq 0 ] || [ "$CVE_TOTAL" = "null" ] && {
        CVE_MAJOR_MINOR=$(echo "$CVE_KERNEL" | cut -d'-' -f1 | sed 's/\.[0-9]*$//')
        CVE_API="https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=linux%20kernel%20${CVE_MAJOR_MINOR}&resultsPerPage=20"
        CVE_RESP=$(curl -s --max-time 30 -H "Accept: application/json" "${CVE_API}" 2>/dev/null)
        CVE_TOTAL=$(echo "$CVE_RESP" | jq -r '.totalResults // 0' 2>/dev/null)
    }

    echo -e "${GREEN}[+] Found ${CVE_TOTAL} potential CVEs${RESET}\n"

    echo "$CVE_RESP" | jq -r '.vulnerabilities[] | .cve' 2>/dev/null | while read -r cve; do
        CVE_ID=$(echo "$cve" | jq -r '.id // "N/A"')
        DESC=$(echo "$cve" | jq -r '.descriptions[0].value // "N/A"' | head -c 150)
        SEV=$(echo "$cve" | jq -r '.metrics.cvssMetricV31[0].cvssData.baseSeverity // .metrics.cvssMetricV30[0].cvssData.baseSeverity // .metrics.cvssMetricV2[0].cvssData.baseSeverity // "N/A"' 2>/dev/null)
        SCORE=$(echo "$cve" | jq -r '.metrics.cvssMetricV31[0].cvssData.baseScore // .metrics.cvssMetricV30[0].cvssData.baseScore // .metrics.cvssMetricV2[0].cvssData.baseScore // "N/A"' 2>/dev/null)

        if [ "$SEV" = "CRITICAL" ] || [ "$SEV" = "HIGH" ]; then
            echo -e "${RED}[${SEV}] ${CVE_ID} (CVSS: ${SCORE})${RESET}"
            ((CVE_CRITICAL++))
        elif [ "$SEV" = "MEDIUM" ] || [ "$SEV" = "MODERATE" ]; then
            echo -e "${YELLOW}[${SEV}] ${CVE_ID} (CVSS: ${SCORE})${RESET}"
        else
            echo -e "${CYAN}[${SEV}] ${CVE_ID} (CVSS: ${SCORE})${RESET}"
        fi
        echo "    $DESC"
    done
else
    echo -e "${YELLOW}[!] jq not found, using basic CVE parsing${RESET}"
    CVE_TOTAL=$(echo "$CVE_RESP" | grep -o '"totalResults":[0-9]*' | head -1 | grep -o '[0-9]*')
    [ -z "$CVE_TOTAL" ] && CVE_TOTAL=0
    echo -e "${GREEN}[+] Found ${CVE_TOTAL} potential CVEs${RESET}"
    echo -e "${CYAN}[*] Install jq for better CVE parsing: apt install jq${RESET}"
fi

echo -e "\n${CYAN}[*] CVE Lookup Complete: https://nvd.nist.gov/vuln/search/results?query=${CVE_KERNEL}${RESET}"

section "PRIVILEGE ESCALATION SUMMARY"

echo "============================================"
echo -e "${CYAN}Findings Summary:${RESET}"
echo "============================================"
echo -e "  GTFOBin candidates: ${YELLOW}${GTFO_COUNT}${RESET}"
echo -e "  Vulnerable SUID:   ${RED}${SUID_COUNT}${RESET}"
echo -e "  Critical CVEs:      ${RED}${CVE_CRITICAL}${RESET}"
echo -e "  Total vulns:        ${RED}${VULN_COUNT}${RESET}"
echo "============================================"

[ $VULN_COUNT -gt 0 ] || [ $GTFO_COUNT -gt 0 ] || [ $SUID_COUNT -gt 0 ] && {
    echo -e "\n${RED}[!] Privilege Escalation vectors found!${RESET}"
    echo -e "${CYAN}[*] Review highlighted findings above${RESET}"
}

section "JSON Export"

cat > "$LOG_DIR/$JSON" <<EOF
{
  "host":"$(json_escape "$HOST")",
  "user":"$(json_escape "$USER_NAME")",
  "kernel":"$(json_escape "$KERNEL")",
  "os":"$(json_escape "$OS")",
  "report":"$(json_escape "$LOG_DIR/$REPORT")",
  "date":"$(date)",
  "findings":{
    "gtfobins":${GTFO_COUNT},
    "vulnerable_suid":${SUID_COUNT},
    "critical_cves":${CVE_CRITICAL},
    "total_vulns":${VULN_COUNT}
  }
}
EOF

banner "ENUMERATION COMPLETE"

echo -e "\n${GREEN}[+] Report:${RESET} $LOG_DIR/$REPORT"
echo -e "${GREEN}[+] JSON:${RESET} $LOG_DIR/$JSON"