#!/usr/bin/env perl
use strict;
use warnings;
use POSIX;
use URI::Escape;
use LWP::Simple;
use JSON;

my $RED = "\e[31m";
my $GREEN = "\e[32m";
my $YELLOW = "\e[33m";
my $BLUE = "\e[34m";
my $CYAN = "\e[36m";
my $RESET = "\e[0m";

my $VERSION = "1.0";
my $DATE = strftime("%F_%H-%M-%S", localtime);
my $HOST = $ENV{HOSTNAME} // `hostname` // "unknown";
chomp($HOST);

my $LOG_DIR = ".";
if (-d "/tmp" && -w "/tmp") {
    $LOG_DIR = "/tmp";
} elsif (-d "." && -w ".") {
    $LOG_DIR = ".";
} else {
    foreach my $dir ("/var/tmp", "/tmp", "/usr/tmp") {
        if (-d $dir && -w $dir) {
            $LOG_DIR = $dir;
            last;
        }
    }
}

my $REPORT = "stealth_enum_${HOST}_${DATE}.log";
my $JSON_FILE = "stealth_enum_${HOST}_${DATE}.json";
my $KERNEL = `uname -r`;
chomp($KERNEL);

my $VULN_COUNT = 0;
my $GTFO_COUNT = 0;
my $SUID_COUNT = 0;
my $CVE_CRITICAL = 0;

my $RUN_AS_ROOT = ($> == 0);
if (!$RUN_AS_ROOT) {
    $YELLOW = "\e[33m";
    $CYAN = "\e[36m";
}

my $LOG_PATH = "$LOG_DIR/$REPORT";

open(my $LOG, '>>', $LOG_PATH) or die "Cannot open $LOG_PATH: $!\n";

sub tee_print {
    my ($msg) = @_;
    print $msg;
    print $LOG $msg;
}

sub banner {
    my ($msg) = @_;
    my $out = "\n${BLUE}================================================================${RESET}\n${CYAN}$msg${RESET}\n${BLUE}================================================================${RESET}\n";
    tee_print($out);
}

sub section {
    my ($msg) = @_;
    tee_print("\n${YELLOW}[+] $msg${RESET}\n");
}

sub progress {
    my ($msg) = @_;
    tee_print("${CYAN}[*] $msg... ${RESET}");
    sleep 0.3;
    tee_print("${GREEN}✓${RESET}\n");
}

sub safe_cmd {
    my ($cmd) = @_;
    tee_print("\n${GREEN}\$ $cmd${RESET}\n");
    my $out = `$cmd 2>/dev/null`;
    tee_print($out) if $out;
    return $out;
}

sub exists_cmd {
    my ($cmd) = @_;
    return !!`command -v $cmd 2>/dev/null`;
}

if (! -f "/proc/cpuinfo") {
    print "\n${RED}[!] ERROR: This script requires Linux!${RESET}\n";
    my $sys = `uname -s`;
    print "${RED}[!] Detected: $sys${RESET}";
    print "${YELLOW}[!] /proc/cpuinfo not found. This tool is for Linux only.${RESET}\n";
    exit(1);
}

banner("Advanced Stealth Enumeration Framework v$VERSION (Perl)");

if (!$RUN_AS_ROOT) {
    print "\n${YELLOW}[!] WARNING: Running without root privileges${RESET}\n";
    print "${YELLOW}[!] Some features will be limited (SUID, capabilities, etc.)${RESET}\n";
    print "${YELLOW}[!] For full enumeration, run with: sudo perl $0${RESET}\n";
}

section("Dependencies Check");

my @missing_deps;
foreach my $cmd (qw(curl find)) {
    if (exists_cmd($cmd)) {
        print "${GREEN}[+] $cmd: OK${RESET}\n";
    } else {
        print "${RED}[!] $cmd: MISSING${RESET}\n";
        push @missing_deps, $cmd;
    }
}

if (@missing_deps) {
    print "\n${YELLOW}[!] Some dependencies missing. Some features may not work.${RESET}\n";
}

section("Basic System Info");

my $USER_NAME = `whoami`;
chomp($USER_NAME);
my $OS = `cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2`;
chomp($OS);

safe_cmd("date");
safe_cmd("hostname");
safe_cmd("id");
safe_cmd("uname -a");

section("Kernel Enumeration");

safe_cmd("uname -r");
safe_cmd("cat /proc/version");
safe_cmd("sysctl kernel.randomize_va_space");
safe_cmd("sysctl kernel.kptr_restrict");
safe_cmd("sysctl kernel.dmesg_restrict");

print "\n[+] Possible Kernel Exploit Indicators\n";
my $fs = `cat /proc/filesystems 2>/dev/null`;
print grep(/overlay|fuse|bpf|userns|io_uring/, split(/\n/, $fs));

if (-f "/boot/config-$KERNEL") {
    my $config = `grep CONFIG_USER_NS /boot/config-$KERNEL 2>/dev/null`;
    print "$config\n";
    $config = `grep CONFIG_BPF /boot/config-$KERNEL 2>/dev/null`;
    print "$config\n";
    $config = `grep CONFIG_IO_URING /boot/config-$KERNEL 2>/dev/null`;
    print "$config\n";
}

section("Users & Privileges");

safe_cmd("id");
safe_cmd("groups");
safe_cmd("sudo -l");

print "\n[+] Home Directories\n";
print `ls -lah /home 2>/dev/null`;

section("GTFOBins & Sudo Abuse");

my $sudo_l = `sudo -l 2>/dev/null`;
print $sudo_l;

my @gtfobins = qw(vim vi nano less more awk find perl python python2 python3 ruby php tar zip bash sh env tee node npm lua irb);
foreach my $bin (@gtfobins) {
    if ($sudo_l =~ /$bin/i) {
        print "${RED}[!] GTFOBIN: $bin${RESET}\n";
        $GTFO_COUNT++;
    }
}

section("SUID / SGID");

my @VULN_SUIDS = qw(
    nmap vim find bash sh dash zsh tcsh csh
    perl python python2 python3 ruby php node npm
    lua irb cat more less head tail cp mv
    nano pico vi gedit kate tar zip gzip
    awk gawk sed cut sort uniq wget curl fetch
    mount umount su sudo chmod chown chgrp
    nmap masscan netcat nc socat telnet ssh
);

my $suid_list = `find / -perm -4000 -type f 2>/dev/null | head -200`;
print $suid_list;

print "\n[+] Interesting SUID (Potential Exploits)\n";
foreach my $suid (split(/\n/, $suid_list)) {
    next unless $suid;
    my $name = $suid;
    $name =~ s/.*\///;
    foreach my $vuln (@VULN_SUIDS) {
        if ($name eq $vuln) {
            print "${RED}[!] VULNERABLE SUID: $suid ($name)${RESET}\n";
            $SUID_COUNT++;
            $VULN_COUNT++;
            last;
        }
    }
}

section("Linux Capabilities");

if (exists_cmd("getcap")) {
    print `getcap -r / 2>/dev/null`;
}

section("Network");

safe_cmd("ip a");
safe_cmd("ip route");
safe_cmd("ss -tulpn");
safe_cmd("arp -a");

print "\n[+] Established Connections\n";
print `ss -antp 2>/dev/null | grep ESTAB`;

section("Processes");

print `ps aux --forest 2>/dev/null | head -200`;

print "\n[+] Interesting Processes\n";
print `ps aux | egrep -i "mysql|mariadb|postgres|redis|docker|nginx|apache|httpd|php-fpm|node|java"`;

section("Cron Jobs");

print `crontab -l 2>/dev/null`;
print `ls -lah /etc/cron* 2>/dev/null`;

section("Containers");

if (-f "/.dockerenv") {
    print "${RED}[!] Docker detected (.dockerenv exists)${RESET}\n";
}

print `grep docker /proc/1/cgroup 2>/dev/null`;

if (exists_cmd("docker")) {
    print `docker ps -a 2>/dev/null`;
}

section("Cloud / VM Detection");

print `grep -i hypervisor /proc/cpuinfo`;
print `dmesg 2>/dev/null | grep -i virtual`;

section("CloudLinux / cPanel");

if (-f "/usr/sbin/lvectl") {
    print "[+] CloudLinux detected\n";
}

if (-d "/usr/local/cpanel") {
    print `cat /usr/local/cpanel/version 2>/dev/null`;
}

section("Web Enumeration");

print `find /var/www/ -type f 2>/dev/null | egrep "\\.env|config|wp-config|database|settings|\\.bak"`;
print `find /home/ -type f 2>/dev/null | egrep "\\.env|config|wp-config|database|settings|\\.bak"`;

print "\n[+] Writable Web Files\n";
print `find /var/www/ -writable -type f 2>/dev/null | head -50`;
print `find /home/ -writable -type f 2>/dev/null | head -50`;

section("Secrets Discovery");

print `grep -Ri "password" /var/www/ 2>/dev/null | head -50`;
print `grep -Ri "password" /home/ 2>/dev/null | head -50`;
print `find /var/www/ /home/ -name ".env" 2>/dev/null | head -50`;
print `find / -name "id_rsa*" 2>/dev/null`;
print `find / -name "*.pem" 2>/dev/null | head -50`;

section("PATH Hijacking");

print "PATH: $ENV{PATH}\n";
print `find . -writable -type d 2>/dev/null`;

section("Mounts");

print `mount`;
print `df -h`;
print `cat /etc/fstab 2>/dev/null`;

section("Security Products");

print `ps aux | egrep -i "clamav|crowdstrike|falcon|wazuh|ossec|auditd|defender|sentinel"`;

section("LDAP / Active Directory");

print `cat /etc/krb5.conf 2>/dev/null`;
print `grep -Ri ldap /etc 2>/dev/null | head -50`;

section("Persistence Checks");

print `ls -lah ~/.ssh 2>/dev/null`;
print `cat ~/.bashrc 2>/dev/null | tail -20`;
print `cat ~/.profile 2>/dev/null | tail -20`;

section("Quick Vulnerability Checks");

print "\n[+] Writable passwd?\n";
if (-w "/etc/passwd") {
    print "${RED}[!] VULNERABLE: Writable /etc/passwd${RESET}\n";
    $VULN_COUNT++;
}

print "\n[+] Writable shadow?\n";
if (-w "/etc/shadow") {
    print "${RED}[!] CRITICAL: Writable /etc/shadow${RESET}\n";
    $VULN_COUNT++;
}

print "\n[+] Dangerous Sudo\n";
my $nopasswd = `sudo -l 2>/dev/null | grep NOPASSWD`;
if ($nopasswd) {
    print "${RED}[!] NOPASSWD Sudo found:${RESET}\n";
    print "$nopasswd";
    $VULN_COUNT++;
}

section("CVE Mapping (NVD NIST)");

my $search_term = "linux kernel $KERNEL";
my $encoded = uri_escape($search_term);
my $api_url = "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=$encoded&resultsPerPage=20";

print "\n${CYAN}[*] Querying NVD NIST API for kernel CVEs...${RESET}\n";

my $response = get($api_url);
my $cve_data = $response ? JSON->new->utf8->decode($response) : {};

my $total = $cve_data->{'totalResults'} // 0;

if (!$total) {
    my ($major_minor) = $KERNEL =~ /^(\d+\.\d+)/;
    if ($major_minor) {
        $search_term = "linux kernel $major_minor";
        $encoded = uri_escape($search_term);
        $api_url = "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=$encoded&resultsPerPage=20";
        $response = get($api_url);
        $cve_data = $response ? JSON->new->utf8->decode($response) : {};
        $total = $cve_data->{'totalResults'} // 0;
    }
}

print "${GREEN}[+] Found ${total} potential CVEs${RESET}\n\n";

if ($total > 0) {
    my @vulns = @{ $cve_data->{'vulnerabilities'} // [] };
    foreach my $vuln (@vulns) {
        my $cve = $vuln->{'cve'};
        next unless $cve;

        my $cve_id = $cve->{'id'} // 'N/A';
        my $desc = $cve->{'descriptions'}[0]{'value'} // 'N/A';
        $desc = substr($desc, 0, 150);

        my $severity = 'N/A';
        my $score = 'N/A';

        if ($cve->{'metrics'}{'cvssMetricV31'}[0]) {
            $severity = $cve->{'metrics'}{'cvssMetricV31'}[0]{'cvssData'}{'baseSeverity'} // 'N/A';
            $score = $cve->{'metrics'}{'cvssMetricV31'}[0]{'cvssData'}{'baseScore'} // 'N/A';
        }
        elsif ($cve->{'metrics'}{'cvssMetricV30'}[0]) {
            $severity = $cve->{'metrics'}{'cvssMetricV30'}[0]{'cvssData'}{'baseSeverity'} // 'N/A';
            $score = $cve->{'metrics'}{'cvssMetricV30'}[0]{'cvssData'}{'baseScore'} // 'N/A';
        }
        elsif ($cve->{'metrics'}{'cvssMetricV2'}[0]) {
            $severity = $cve->{'metrics'}{'cvssMetricV2'}[0]{'cvssData'}{'baseSeverity'} // 'N/A';
            $score = $cve->{'metrics'}{'cvssMetricV2'}[0]{'cvssData'}{'baseScore'} // 'N/A';
        }

        my $color = $CYAN;
        if ($severity eq 'CRITICAL' || $severity eq 'HIGH') {
            $color = $RED;
            $CVE_CRITICAL++;
        }
        elsif ($severity eq 'MEDIUM' || $severity eq 'MODERATE') {
            $color = $YELLOW;
        }
        elsif ($severity eq 'LOW') {
            $color = $GREEN;
        }

        print "${color}[${severity}] ${cve_id} (CVSS: ${score})${RESET}\n";
        print "    $desc\n";
    }
}

print "\n${CYAN}[*] CVE Lookup Complete${RESET}\n";
print "${CYAN}[*] Reference: https://nvd.nist.gov/vuln/search/results?query=", uri_escape($KERNEL), "${RESET}\n\n";

section("PRIVILEGE ESCALATION SUMMARY");

print "============================================\n";
print "${CYAN}Findings Summary:${RESET}\n";
print "============================================\n";
print "  GTFOBin candidates: ${YELLOW}${GTFO_COUNT}${RESET}\n";
print "  Vulnerable SUID:     ${RED}${SUID_COUNT}${RESET}\n";
print "  Critical CVEs:       ${RED}${CVE_CRITICAL}${RESET}\n";
print "  Total vulns:        ${RED}${VULN_COUNT}${RESET}\n";
print "============================================\n";

if ($VULN_COUNT > 0 || $GTFO_COUNT > 0 || $SUID_COUNT > 0) {
    print "\n${RED}[!] Privilege Escalation vectors found!${RESET}\n";
    print "${CYAN}[*] Review highlighted findings above${RESET}\n";
}

banner("ENUMERATION COMPLETE");

print "\n${GREEN}[+] Report:${RESET} $LOG_DIR/$REPORT\n";
print "${GREEN}[+] JSON:${RESET} $LOG_DIR/$JSON_FILE\n";

select(STDOUT);
open(my $JSON_OUT, '>', "$LOG_DIR/$JSON_FILE") or die "Cannot open $LOG_DIR/$JSON_FILE: $!";
print $JSON_OUT JSON->new->utf8->encode({
    host => $HOST,
    user => $USER_NAME,
    kernel => $KERNEL,
    os => $OS,
    report => "$LOG_DIR/$REPORT",
    date => scalar(localtime),
    findings => {
        gtfobins => $GTFO_COUNT,
        vulnerable_suid => $SUID_COUNT,
        critical_cves => $CVE_CRITICAL,
        total_vulns => $VULN_COUNT
    }
});
close($JSON_OUT);

close($LOG);
