# ReconL - Local Privilege Escalation Reconnaissance Tool

<p align="center">
  <img src="https://img.shields.io/badge/Version-1.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/Language-Bash%20%7C%20Perl%20%7C%20Python-orange.svg" alt="Languages">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License">
</p>

Advanced Stealth Enumeration Framework for Linux privilege escalation reconnaissance.

## Features

- **Multi-Language Support** - Bash, Perl, and Python implementations
- **Auto CVE Mapping** - Queries NVD NIST API for kernel vulnerabilities
- **GTFOBins Detection** - Identifies exploitable sudo binaries
- **Enhanced SUID Analysis** - Matches against 40+ known vulnerable SUID binaries
- **Privilege Escalation Summary** - Quick overview of all findings
- **Dependency Check** - Validates required tools at startup
- **Colored Output** - Visual severity indicators
- **Dual Output** - Terminal + log file + JSON report


## Usage Direct

Run directly without cloning:

```bash
# Bash (with jq)
curl -L https://github.com/mogbil/ReconL/raw/main/reconL.sh | bash

# Perl
curl -L https://github.com/mogbil/ReconL/raw/main/reconL.pl | perl

# Python
curl -L https://github.com/mogbil/ReconL/raw/main/reconL.py | python3
```

## Usage 

```bash
# Bash (requires jq)
chmod +x reconL.sh
sudo ./reconL.sh

# Perl
chmod +x reconL.pl
sudo perl reconL.pl

# Python
chmod +x reconL.py
sudo python3 reconL.py
```

## What It Enumerates

| Category | Description |
|----------|-------------|
| **System Info** | Kernel version, OS, user, hostname |
| **Kernel Enum** | Kernel config, exploit indicators (overlay, bpf, io_uring, userns) |
| **Users & Privs** | Current user, groups, sudo permissions |
| **GTFOBins** | Exploitable binaries (vim, nano, python, find, etc.) |
| **SUID/SGID** | All SUID binaries + vulnerability matching |
| **Capabilities** | Linux capabilities (getcap) |
| **Network** | IP addresses, routes, listening ports, connections |
| **Processes** | Running services (mysql, nginx, apache, docker, etc.) |
| **Cron Jobs** | User and system crontabs |
| **Containers** | Docker, container detection |
| **Cloud/VM** | Hypervisor detection, CloudLinux, cPanel |
| **Web Enum** | Config files, .env, wp-config, writable files |
| **Secrets** | Passwords in web dirs, SSH keys, .pem files |
| **Persistence** | SSH keys, bashrc, profile modifications |
| **Security Prod** | ClamAV, CrowdStrike, Wazuh, Defender, etc. |
| **LDAP/AD** | Kerberos config, LDAP references |
| **Quick Vulns** | Writable /etc/passwd, /etc/shadow, NOPASSWD sudo |
| **CVE Mapping** | NVD NIST API kernel CVE lookup |

## Output Files

```
stealth_enum_<hostname>_<date>.log    # Full scan log
stealth_enum_<hostname>_<date>.json   # JSON report with findings
```

### JSON Output Structure

```json
{
  "host": "target-server",
  "user": "low-privilege-user",
  "kernel": "5.15.0-60-generic",
  "os": "\"Ubuntu 22.04.1 LTS\"",
  "report": "stealth_enum_target-server_2026-05-10_15-30-00.log",
  "date": "Sun May 10 15:30:00 2026",
  "findings": {
    "gtfobins": 3,
    "vulnerable_suid": 2,
    "critical_cves": 5,
    "total_vulns": 10
  }
}
```

## CVE Mapping

Queries the **NVD NIST API** (free, no API key required) for kernel CVEs:

```
[CRITICAL] CVE-2024-26921 (CVSS: 7.8)
    Linux kernel privilege escalation in the BPF subsystem...

[CRITICAL] CVE-2024-26923 (CVSS: 7.8)
    Use-after-free vulnerability in the io_uring subsystem...

[HIGH] CVE-2024-23897 (CVSS: 7.3)
    Linux kernel information disclosure via BPF...
```

## Privilege Escalation Summary

At the end of each scan:

```
============================================
Findings Summary:
============================================
  GTFOBin candidates: 3
  Vulnerable SUID:    2
  Critical CVEs:       5
  Total vulns:        10
============================================

[!] Privilege Escalation vectors found!
[*] Review highlighted findings above
```

## Requirements

| Version | Dependencies |
|---------|-------------|
| **Bash** | `jq`, `curl`, `find` |
| **Perl** | `LWP::Simple`, `JSON`, `URI::Escape` |
| **Python** | Python 3 (stdlib only - no dependencies) |

### Install jq (Bash)

```bash
# Debian/Ubuntu
sudo apt install jq

# RHEL/CentOS
sudo yum install jq

# Arch Linux
sudo pacman -S jq
```

## Quick Start

```bash
# Clone or download
git clone https://github.com/user/ReconL.git
cd ReconL

# Make scripts executable
chmod +x reconL.sh reconL.pl reconL.py

# Run as root for full enumeration
sudo ./reconL.sh

# View results
cat stealth_enum_*.log
cat stealth_enum_*.json | jq
```

## Color Legend

| Color | Severity |
|-------|----------|
| 🔴 Red | CRITICAL / HIGH - Immediate action required |
| 🟡 Yellow | MEDIUM / MODERATE - Review recommended |
| 🔵 Cyan | LOW / N/A - Informational |
| 🟢 Green | OK / Success |

## Legal Notice

**FOR AUTHORIZED SECURITY TESTING ONLY**

This tool is designed for:
- Penetration testers conducting authorized assessments
- Security researchers analyzing systems they own
- System administrators auditing their own infrastructure

**Warning:** Any unauthorized use or scanning systems you do not own or lack explicit permission to test is **illegal** and **unethical**.

**Disclaimer:** The developer assumes no responsibility for misuse of this tool.

## License

**MIT License** - Copyright (c) 2026 ReconL

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software to deal in the Software without restriction.

---

<p align="center">
  <strong>ReconL</strong> - Linux Privilege Escalation Reconnaissance
</p>

