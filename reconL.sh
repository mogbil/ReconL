#!/usr/bin/env bash
# =============================================================================
# ReconL v1.0 : Local Privilege Escalation Reconnaissance Tool (Bash Version)
# =============================================================================

export LC_ALL=C
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VERSION="1.0"
DATE=$(date +%F_%H-%M-%S)
HOST=$(hostname 2>/dev/null)

# Determine writable directory
if [ -w "/tmp" ]; then
    LOG_DIR="/tmp"
else
    LOG_DIR="."
fi

REPORT="stealth_enum_${HOST}_${DATE}.log"
JSON="stealth_enum_${HOST}_${DATE}.json"

exec > >(tee -a "$LOG_DIR/$REPORT" 2>/dev/null)

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# Counters for summary
VULN_COUNT=0
GTFO_COUNT=0
SUID_COUNT=0
CVE_CRITICAL=0

# Check if running as root
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

progress() {
    echo -ne "${CYAN}[*] $1... ${RESET}"
    sleep 0.3
    echo -e "${GREEN}✓${RESET}"
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

# =============================================================================
# START
# =============================================================================

banner "Advanced Stealth Enumeration Framework v$VERSION"

if [ "$RUN_AS_ROOT" -eq 0 ]; then
    echo -e "\n${YELLOW}[!] WARNING: Running without root privileges${RESET}"
    echo -e "${YELLOW}[!] Some features will be limited (SUID, capabilities, etc.)${RESET}"
    echo -e "${YELLOW}[!] For full enumeration, run with: sudo $0${RESET}\n"
fi

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

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

if [ $MISSING_DEPS -eq 1 ]; then
    echo -e "\n${YELLOW}[!] Some dependencies missing. Some features may not work.${RESET}"
fi

# =============================================================================
# BASIC INFO
# =============================================================================

section "Basic System Info"

USER_NAME=$(whoami)
KERNEL=$(uname -r)
OS=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2)

safe_cmd "date"
safe_cmd "hostname"
safe_cmd "id"
safe_cmd "uname -a"

# =============================================================================
# KERNEL / PRIVESC ENUMERATION
# =============================================================================

section "Kernel Enumeration"

safe_cmd "uname -r"
safe_cmd "cat /proc/version"
safe_cmd "sysctl kernel.randomize_va_space"
safe_cmd "sysctl kernel.kptr_restrict"
safe_cmd "sysctl kernel.dmesg_restrict"

echo -e "\n[+] Possible Kernel Exploit Indicators"

grep -E "overlay|fuse|bpf|userns|io_uring" /proc/filesystems 2>/dev/null

if [ -f "/boot/config-$(uname -r)" ]; then
    grep CONFIG_USER_NS /boot/config-$(uname -r)
    grep CONFIG_BPF /boot/config-$(uname -r)
    grep CONFIG_IO_URING /boot/config-$(uname -r)
fi

# =============================================================================
# USER ENUMERATION
# =============================================================================

section "Users & Privileges"

safe_cmd "id"
safe_cmd "groups"
safe_cmd "sudo -l"

echo -e "\n[+] Home Directories"
ls -lah /home 2>/dev/null

# =============================================================================
# SUDO / GTFOBins
# =============================================================================

section "GTFOBins & Sudo Abuse"

sudo -l 2>/dev/null | tee /tmp/.sudo_enum.$$ >/dev/null

for bin in vim vi nano less more awk find perl python python3 ruby python2 python3.11 python3.10 python3.9 tar zip bash sh env tee; do
    if grep -qi "$bin" /tmp/.sudo_enum.$$ 2>/dev/null; then
        echo -e "${RED}[!] GTFOBIN: $bin${RESET}"
        ((GTFO_COUNT++))
    fi
done

rm -f /tmp/.sudo_enum.$$

# =============================================================================
# SUID / SGID - Enhanced parsing
# =============================================================================

section "SUID / SGID"

# Known vulnerable SUID binaries
declare -a VULN_SUIDS=(
    "nmap" "vim" "find" "bash" "sh" "dash" "zsh" "tcsh" "csh"
    "perl" "python" "python2" "python3" "ruby" "php" "node" "npm"
    "lua" "irb" "cat" "more" "less" "head" "tail" "cp" "mv"
    "nano" "pico" "vi" "gedit" "kate" "nano" "tar" "zip" "gzip"
    "awk" "gawk" "sed" "cut" "sort" "uniq" "wget" "curl" "fetch"
    "mount" "umount" "su" "sudo" "chmod" "chown" "chgrp"
    "nmap" "masscan" "netcat" "nc" "socat" "telnet" "ssh"
)

# Get all SUID binaries
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

# =============================================================================
# CAPABILITIES
# =============================================================================

section "Linux Capabilities"

exists getcap && getcap -r / 2>/dev/null

# =============================================================================
# NETWORK ENUMERATION
# =============================================================================

section "Network"

safe_cmd "ip a"
safe_cmd "ip route"
safe_cmd "ss -tulpn"
safe_cmd "arp -a"

echo -e "\n[+] Established Connections"
ss -antp 2>/dev/null | grep ESTAB

# =============================================================================
# SERVICES / PROCESSES
# =============================================================================

section "Processes"

ps aux --forest 2>/dev/null | head -200

echo -e "\n[+] Interesting Processes"
ps aux | egrep -i \
"mysql|mariadb|postgres|redis|docker|nginx|apache|httpd|php-fpm|node|java"

# =============================================================================
# CRON ENUMERATION
# =============================================================================

section "Cron Jobs"

crontab -l 2>/dev/null

ls -lah /etc/cron* 2>/dev/null

# =============================================================================
# DOCKER / CONTAINERS
# =============================================================================

section "Containers"

if [ -f /.dockerenv ]; then
    echo -e "${RED}[!] Docker detected (.dockerenv exists)${RESET}"
fi

grep docker /proc/1/cgroup 2>/dev/null

exists docker && docker ps -a 2>/dev/null

# =============================================================================
# CLOUD / VIRTUALIZATION
# =============================================================================

section "Cloud / VM Detection"

grep -i hypervisor /proc/cpuinfo

dmesg 2>/dev/null | grep -i virtual

# =============================================================================
# CLOUDLINUX / CPANEL
# =============================================================================

section "CloudLinux / cPanel"

[ -f /usr/sbin/lvectl ] && echo "[+] CloudLinux detected"

[ -d /usr/local/cpanel ] && \
cat /usr/local/cpanel/version 2>/dev/null

# =============================================================================
# WEB ENUMERATION
# =============================================================================

section "Web Enumeration"

find /var/www/ -type f 2>/dev/null | \
egrep "\.env|config|wp-config|database|settings|\.bak"

echo -e "\n[+] Writable Web Files"
find /var/www/ -writable -type f 2>/dev/null | head -50

# =============================================================================
# PASSWORD / SECRET ENUMERATION
# =============================================================================

section "Secrets Discovery"

grep -Ri "password" /var/www/ 2>/dev/null | head -50

find / -name ".env" 2>/dev/null | head -50

find / -name "id_rsa*" 2>/dev/null

find / -name "*.pem" 2>/dev/null | head -50

# =============================================================================
# PATH HIJACK
# =============================================================================

section "PATH Hijacking"

echo "PATH: $PATH"

find . -writable -type d 2>/dev/null

# =============================================================================
# NFS / MOUNTS
# =============================================================================

section "Mounts"

mount

df -h

cat /etc/fstab 2>/dev/null

# =============================================================================
# SECURITY PRODUCTS
# =============================================================================

section "Security Products"

ps aux | egrep -i \
"clamav|crowdstrike|falcon|wazuh|ossec|auditd|defender|sentinel"

# =============================================================================
# LDAP / AD
# =============================================================================

section "LDAP / Active Directory"

cat /etc/krb5.conf 2>/dev/null

grep -Ri ldap /etc 2>/dev/null | head -50

# =============================================================================
# PERSISTENCE
# =============================================================================

section "Persistence Checks"

ls -lah ~/.ssh 2>/dev/null

cat ~/.bashrc 2>/dev/null | tail -20

cat ~/.profile 2>/dev/null | tail -20

# =============================================================================
# QUICK VULN CHECKS
# =============================================================================

section "Quick Vulnerability Checks"

echo -e "\n[+] Writable passwd?"
if [ -w /etc/passwd ]; then
    echo -e "${RED}[!] VULNERABLE: Writable /etc/passwd${RESET}"
    ((VULN_COUNT++))
fi

echo -e "\n[+] Writable shadow?"
if [ -w /etc/shadow ]; then
    echo -e "${RED}[!] CRITICAL: Writable /etc/shadow${RESET}"
    ((VULN_COUNT++))
fi

echo -e "\n[+] Dangerous Sudo"
NOPASSWD=$(sudo -l 2>/dev/null | grep NOPASSWD)
if [ -n "$NOPASSWD" ]; then
    echo -e "${RED}[!] NOPASSWD Sudo found:${RESET}"
    echo "$NOPASSWD"
    ((VULN_COUNT++))
fi

# =============================================================================
# AUTO CVE MAPPER
# =============================================================================

section "CVE Mapping (NVD NIST)"

CVE_KERNEL=$(uname -r)
CVE_SEARCH="linux kernel ${CVE_KERNEL}"
CVE_API="https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=${CVE_SEARCH}&resultsPerPage=20"

echo -e "\n${CYAN}[*] Querying NVD NIST API for kernel CVEs...${RESET}"

CVE_RESP=$(curl -s --max-time 30 -H "Accept: application/json" "${CVE_API}" 2>/dev/null)

# Check if jq is available for JSON parsing
if exists jq; then
    CVE_TOTAL=$(echo "$CVE_RESP" | jq -r '.totalResults // 0' 2>/dev/null)

    if [ "$CVE_TOTAL" -eq 0 ] || [ "$CVE_TOTAL" = "null" ]; then
        CVE_MAJOR_MINOR=$(echo "$CVE_KERNEL" | cut -d'-' -f1 | sed 's/\.[0-9]*$//')
        CVE_SEARCH="linux kernel ${CVE_MAJOR_MINOR}"
        CVE_API="https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=${CVE_SEARCH}&resultsPerPage=20"
        CVE_RESP=$(curl -s --max-time 30 -H "Accept: application/json" "${CVE_API}" 2>/dev/null)
        CVE_TOTAL=$(echo "$CVE_RESP" | jq -r '.totalResults // 0' 2>/dev/null)
    fi

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
    # Fallback: grep/awk parsing (no jq)
    echo -e "${YELLOW}[!] jq not found, using basic CVE parsing${RESET}"

    CVE_TOTAL=$(echo "$CVE_RESP" | grep -o '"totalResults":[0-9]*' | head -1 | grep -o '[0-9]*')
    [ -z "$CVE_TOTAL" ] && CVE_TOTAL=0

    if [ "$CVE_TOTAL" -eq 0 ]; then
        CVE_MAJOR_MINOR=$(echo "$CVE_KERNEL" | cut -d'-' -f1 | sed 's/\.[0-9]*$//')
        CVE_SEARCH="linux kernel ${CVE_MAJOR_MINOR}"
        CVE_API="https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=${CVE_SEARCH}&resultsPerPage=20"
        CVE_RESP=$(curl -s --max-time 30 -H "Accept: application/json" "${CVE_API}" 2>/dev/null)
        CVE_TOTAL=$(echo "$CVE_RESP" | grep -o '"totalResults":[0-9]*' | head -1 | grep -o '[0-9]*')
        [ -z "$CVE_TOTAL" ] && CVE_TOTAL=0
    fi

    echo -e "${GREEN}[+] Found ${CVE_TOTAL} potential CVEs${RESET}"
    echo -e "${CYAN}[*] Install jq for better CVE parsing: apt install jq${RESET}"
fi

echo -e "\n${CYAN}[*] CVE Lookup Complete: https://nvd.nist.gov/vuln/search/results?query=${CVE_KERNEL}${RESET}"

# =============================================================================
# PRIVILEGE ESCALATION SUMMARY
# =============================================================================

section "PRIVILEGE ESCALATION SUMMARY"

echo "============================================"
echo -e "${CYAN}Findings Summary:${RESET}"
echo "============================================"
echo -e "  GTFOBin candidates: ${YELLOW}${GTFO_COUNT}${RESET}"
echo -e "  Vulnerable SUID:   ${RED}${SUID_COUNT}${RESET}"
echo -e "  Critical CVEs:      ${RED}${CVE_CRITICAL}${RESET}"
echo -e "  Total vulns:       ${RED}${VULN_COUNT}${RESET}"
echo "============================================"

if [ $VULN_COUNT -gt 0 ] || [ $GTFO_COUNT -gt 0 ] || [ $SUID_COUNT -gt 0 ]; then
    echo -e "\n${RED}[!] Privilege Escalation vectors found!${RESET}"
    echo -e "${CYAN}[*] Review highlighted findings above${RESET}"
fi

# =============================================================================
# JSON EXPORT
# =============================================================================

section "JSON Export"

cat > "$JSON" <<EOF
{
  "host":"$(json_escape "$HOST")",
  "user":"$(json_escape "$USER_NAME")",
  "kernel":"$(json_escape "$KERNEL")",
  "os":"$(json_escape "$OS")",
  "report":"$(json_escape "$REPORT")",
  "date":"$(date)",
  "findings":{
    "gtfobins":${GTFO_COUNT},
    "vulnerable_suid":${SUID_COUNT},
    "critical_cves":${CVE_CRITICAL},
    "total_vulns":${VULN_COUNT}
  }
}
EOF

# =============================================================================
# FINISHED
# =============================================================================

banner "ENUMERATION COMPLETE"

echo -e "\n${GREEN}[+] Report:${RESET} $REPORT"
echo -e "${GREEN}[+] JSON:${RESET} $JSON"