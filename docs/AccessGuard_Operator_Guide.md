# AccessGuard — Operator Guide

> **Version 2.0** · Enterprise Biometric Access Reconciler & Terminal Controller

---

## Table of Contents

1. [System Overview & Core Logic](#1-system-overview--core-logic)
2. [Prerequisites & Installation](#2-prerequisites--installation)
3. [First-Time Configuration (Web Dashboard)](#3-first-time-configuration-web-dashboard)
4. [Oracle Database Integration & Schema](#4-oracle-database-integration--schema)
5. [Hardware Terminal Management](#5-hardware-terminal-management)
6. [Daily Operations & Monitoring](#6-daily-operations--monitoring)
7. [Manual Overrides & The Pardon Guard](#7-manual-overrides--the-pardon-guard)
8. [Auditing & Reports Module](#8-auditing--reports-module)
9. [Windows Service Management](#9-windows-service-management)
10. [Database Backup & Disaster Recovery](#10-database-backup--disaster-recovery)
11. [Troubleshooting & Diagnostics](#11-troubleshooting--diagnostics)

---

## 1. System Overview & Core Logic

**AccessGuard** is an autonomous Windows Service and middleware platform that bridges corporate Human Resources Oracle attendance records with physical ZKTeco biometric turnstiles.

### How the Reconciler Engine Operates

```
Every night at scheduled time (default 01:00 AM):
  ① Syncs employee shift mappings from Oracle (MDPL_EMP_SHIFT_V)
  ② Fetches yesterday's arrival check-in punches from Oracle (PP_EMP_ATT_MST_DW)
  ③ Evaluates tardiness against the Configurable Rolling Penalty Window
  ④ Enforces physical turnstile access groups via network (TCP 4370):
     • Strikes < Quota  → Group 1 (Clear Tier: Full 24h entry)
     • Strikes == Quota → Group 1 (Warning Tier: Normal entry, flagged yellow)
     • Strikes > Quota  → Group 3 (Locked Out: Zero-access Time Zone, turnstile denied)
  ⑤ Synchronizes hardware clocks on terminals if drift exceeds 60 seconds
```

### Configurable Rolling Penalty Window

Unlike simple consecutive-day counters, AccessGuard enforces a **Rolling Penalty Window** (e.g. 30 days):
- When an employee arrives late beyond their allowed grace period, a **Strike** is recorded.
- Each strike has a strictly tracked expiration timestamp. Once the window period elapses (e.g., 30 days from the infraction), that strike **automatically expires and falls off their record**.
- A counter on the dashboard (`Lates in Window`, e.g. `2 / 3`) displays their active strike status with a dynamic countdown (`Window Expires: in 14 days`).

### The Three Penalty Tiers

| Status | Rule Condition | Hardware Group | Turnstile Physical State |
|---|---|---|---|
| 🟢 **Clear** | `Strikes < Quota` | **Group 1** | Normal 24-hour physical access granted |
| 🟡 **Warning** | `Strikes == Quota` | **Group 1** | Normal access granted; flagged yellow on dashboard (1 strike from lockout) |
| 🔴 **Locked Out** | `Strikes > Quota` | **Group 3** | Access withheld ("Invalid Time Zone" displayed on terminal) |

> **Non-Destructive Enforcement**: Employee profiles are **never disabled** on hardware. Biometrics continue scanning and logging so arrival attempts are permanently recorded in Oracle, while unauthorized turnstile entry is physically blocked.

### Sequential Catch-up Mechanism

If the host server is powered down or disconnected over weekends or holidays:
- The Reconciler **never skips dates**.
- Upon startup, a sequential catch-up loop identifies the last successfully evaluated date.
- It iterates through every missing calendar day in chronological order, calculating attendance and strike states day-by-day until fully synchronized with the present day.

### Hardware Signature (HWID) Licensing

AccessGuard generates an internal hardware fingerprint based on the host server's **Motherboard** and **CPU** serial numbers to prevent unauthorized virtual machine cloning. Operating system disk upgrades and RAM expansions do not invalidate the license; moving to a different motherboard requires license re-issuance.

---

## 2. Prerequisites & Installation

### Prerequisites

- **Operating System**: Windows 10, Windows 11, or Windows Server 2016/2019/2022 (64-bit).
- **Administrative Privileges**: Required for service registration and firewall configuration.
- **ZKTeco 64-bit COM Object**: Registered automatically by the installer (`zkemkeeper.dll`).
- **Network Ports**:
  - `TCP 4370`: Bidirectional communication to ZKTeco terminal IP addresses.
  - `TCP 1521`: Outbound to corporate Oracle Database Listener.
  - `TCP 5000`: Inbound HTTP for the local management dashboard (opened automatically by installer).

### Installation Steps

1. Right-click [`AccessGuard-Setup-v2.0.exe`](../installer/AccessGuard-Setup-v2.0.exe) and select **Run as administrator**.
2. Follow the setup wizard prompts (default installation directory: `C:\Program Files\AccessGuard\` or `C:\Program Files\ZtkHardwareService\`).
3. The installer automatically:
   - Deploys application binaries and embedded runtime assets.
   - Registers required 64-bit ZKTeco SDK COM components.
   - Configures and starts `ZtkHardwareService` as an automatic Windows Service.
   - Adds an inbound rule to Windows Firewall for TCP port 5000.
4. When installation finishes, the browser opens the management dashboard at:
   ```
   http://localhost:5000
   ```
5. Log in using the initial default administrator credentials provided during onboarding.

---

## 3. First-Time Configuration (Web Dashboard)

All system settings are managed directly within the web dashboard at `http://localhost:5000`. **No manual JSON file editing or service restarts are required.**

### Step 1 — Admin Users & Role-Based Access Control (RBAC)

Navigate to **Admin Users**:
1. Update default administrator credentials immediately (minimum 8-character password policy enforced).
2. Create dedicated accounts for HR and security personnel with granular permissions:
   - `Administrator`: Full unrestricted access to all modules and configurations.
   - `Can Override Penalties`: Allows granting Pardons without permission to change system rules.
   - `Can Edit Config`: Allows tuning grace periods, penalty windows, and late quotas.
   - `Can Manage Terminals`: Allows enrolling or removing ZKTeco hardware devices.
   - `Can Manage Database`: Restricts Oracle credentials to IT staff.
   - `Can View Reports`: Read-only access for payroll auditors and CSV exports.

### Step 2 — Configure Oracle Database

Navigate to **Database Settings**:
1. Enter your Oracle connection details:
   - **Host / IP**: IP address or hostname of the Oracle server.
   - **Port**: Listener port (default `1521`).
   - **Service Name / SID**: Oracle service identifier (e.g. `ORCL`, `FREEPDB1`, `XE`).
   - **Username & Password**: Oracle user credentials with `SELECT` grant on the required entities.
2. Click **Test Connection**:
   - Performs an active TCP handshake and authentication check against Oracle.
   - Confirms listener responsiveness and credential validity.
3. Click **Save Settings**:
   - Connection strings are encrypted and saved into local SQLite storage (`reconciler.db`).
   - Takes effect **immediately** for all future queries without restarting the Windows Service.

### Step 3 — Configure Global Policies

Navigate to **Configuration Settings**:
- **Default Grace Period**: Universal buffer added to shift start (default: `5` minutes).
- **Penalty Window**: Number of rolling days strikes remain active (default: `30` days).
- **Late Quota**: Number of allowed lates before lockout occurs (default: `1` or `2`).
- **Reconciler Run Time**: Scheduled 24-hour time for the nightly audit (default: `01:00 AM`).

---

## 4. Oracle Database Integration & Schema

AccessGuard reads from two strictly named entities in Oracle. Refer to [Oracle_Required_Objects.sql](../database/Oracle_Required_Objects.sql) for reference DDL.

### 1. Shift Schedule Entity: `MDPL_EMP_SHIFT_V`
A view or table defining work hours and mapping biometric device IDs to payroll numbers:

| Column Name | Data Type | Required Format | Description |
|---|---|---|---|
| `MACHINE_ID` | `VARCHAR2` | String (e.g. `'1042'`) | Terminal biometric enrollment ID |
| `EMPLOYEE_NUMBER` | `VARCHAR2` | String (e.g. `'EMP-1042'`) | Corporate employee code |
| `SHIFT_START` | `VARCHAR2` | `HH24:MI` (e.g. `'08:00'`) | Scheduled work start time |
| `SHIFT_END` | `VARCHAR2` | `HH24:MI` (e.g. `'17:00'`) | Scheduled work end time |

### 2. Biometric Attendance Entity: `PP_EMP_ATT_MST_DW`
A view or table containing raw arrival scan events:

| Column Name | Data Type | Required Format | Description |
|---|---|---|---|
| `AM_EMPNO` | `VARCHAR2` | String (e.g. `'1042'`) | Matches `MACHINE_ID` |
| `AM_TIME` | `VARCHAR2` | `YYYY/MM/DD HH24:MI` | Punch timestamp (e.g. `'2026/10/11 08:04'`) |
| `AM_SHIFT` | `VARCHAR2` | String (`'1'` or `'3'`) | `'1'` = Morning Check-In, `'3'` = Break-In |

> **Note on Event Types**: If an employee clocks in via Morning Check-In (`'1'`), that timestamp is evaluated. If an employee missed morning check-in and their first scan of the day is a Lunch Break-In (`'3'`), the engine marks them late by default.

---

## 5. Hardware Terminal Management

Navigate to **Terminals Module** to oversee physical turnstiles:

### Device Enrollment & Live Status
- Add terminals by entering their static IP address and communication port (default: `4370`).
- The dashboard performs automated heartbeat polling displaying live **Online** or **Offline** indicators.

### Access Group Enforcement
- **Group 1**: Assigned to Clear and Warning employees (unrestricted physical access).
- **Group 3**: Assigned to Locked Out employees (hardware time zone zeroed out; terminal beeps and denies entry).

### Automated Clock Drift Synchronization
Biometric devices experience internal RTC drift over time:
- Before each reconciliation run or upon device reconnection, the service queries the terminal clock.
- If variance exceeds **60 seconds** relative to the authoritative server clock, AccessGuard automatically pushes the correct time to the terminal RTC.
- Guarantees grace-period evaluation accuracy.

---

## 6. Daily Operations & Monitoring

### The Operational Dashboard
The main dashboard displays an interactive, searchable **Employee Table**:
- **Employee ID**: Biometric enrollment ID synced from Oracle.
- **Penalty Tier**: Visual badge (🟢 Clear, 🟡 Warning, 🔴 Locked Out).
- **Lates in Window**: Current active strike ratio (e.g. `2 / 2`).
- **Window Expires**: Real-time countdown until the oldest strike naturally falls off (e.g. `in 12 days`).
- **Last Late**: Timestamp of most recent late arrival.
- **Last Pardoned**: Date of the most recent manual HR exception.

### Running Reconciliation On-Demand
To calculate strikes immediately without waiting for the nightly timer:
1. Click **Run Reconciler Now** at the top right of the Dashboard.
2. The engine immediately synchronizes Oracle tables, recomputes rolling strike totals, pushes access groups to hardware, and refreshes dashboard statistics.

---

## 7. Manual Overrides & The Pardon Guard

When an employee is locked out due to an approved manager exception or legitimate delay, HR staff with `Can Override Penalties` permission can grant a **Pardon**.

### Granting a Pardon
1. Navigate to **Override Module**.
2. Search for the employee ID.
3. Click **Pardon (Override)**.
4. Enter mandatory fields:
   - **Approver Name**: Supervisor or HR manager granting approval.
   - **Justification Reason**: Explanation (e.g. *"Approved emergency family leave"*).
5. Click **Confirm Pardon**:
   - The employee's latest active strike is tagged as `Pardoned`.
   - Active strike count decreases by 1, returning the employee to Warning Tier.
   - Hardware **Group 1** is pushed instantly over TCP 4370, opening the turnstile immediately.

### The "Pardon Guard" (Double-Penalty Shield)
Because the automated reconciler runs every night, an employee who was pardoned in the morning could otherwise have yesterday's punch re-evaluated that night and get locked out again.

To prevent this, AccessGuard engages the **Pardon Guard**:
- When a pardon is granted, the current calendar date is stamped into the employee's shield record.
- During the nightly reconciliation run, the engine checks for an active Pardon Guard for that date.
- If present, late strike generation is bypassed for that employee on that day, ensuring they remain unlocked for the following morning.

---

## 8. Auditing & Reports Module

The Reports Module provides exportable records for compliance, management reviews, and payroll deduction calculations:

1. **Override Audit Log**: Complete history of every granted pardon, including timestamp, employee ID, active strikes at time of pardon, approver name, and reason.
2. **System Audit Log**: Administrative event trail logging user logins, permission changes, terminal additions, and configuration modifications.
3. **Raw Punch Logs**: Live direct window into Oracle attendance punches (`PP_EMP_ATT_MST_DW`), showing timestamps, device IDs, and check-in vs break-in event types.
4. **Historical Lates**: Permanent cumulative ledger of every tardiness event ever recorded, preserving counted vs pardoned states even after rolling windows expire.
5. **CSV Export**: Any report can be filtered by date range and exported to `.csv` with one click.

---

## 9. Windows Service Management

The engine runs as a native background service named `ZtkHardwareService`.

### PowerShell Management Commands

```powershell
# Check whether the service is running
Get-Service ZtkHardwareService

# Start service
Start-Service ZtkHardwareService

# Stop service
Stop-Service ZtkHardwareService

# Restart service (e.g. after manual file updates)
Restart-Service ZtkHardwareService

# Inspect the 25 most recent service event logs
Get-EventLog -LogName Application -Source ZtkHardwareService -Newest 25
```

---

## 10. Database Backup & Disaster Recovery

### The SQLite Database File
AccessGuard stores all configuration, user credentials, strike histories, and audit records in an embedded SQLite database:
```
C:\Program Files\AccessGuard\reconciler.db
(or C:\Program Files\ZtkHardwareService\reconciler.db)
```

### Automated Backup Recommendation
Schedule a daily backup script using Windows Task Scheduler:

```powershell
# Daily backup PowerShell snippet
$dbPath = "C:\Program Files\AccessGuard\reconciler.db"
$backupDir = "\\BackupServer\AccessGuardBackups"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Copy-Item -Path $dbPath -Destination "$backupDir\reconciler_$timestamp.db" -Force
```

### Full Disaster Recovery
1. Run [`AccessGuard-Setup-v2.0.exe`](../installer/AccessGuard-Setup-v2.0.exe) on the target host.
2. Stop the service: `Stop-Service ZtkHardwareService`.
3. Restore your backup `reconciler.db` into the application directory.
4. Start the service: `Start-Service ZtkHardwareService`.
5. Open `http://localhost:5000` to confirm all historical logs, users, and terminal configurations are restored.

---

## 11. Troubleshooting & Diagnostics

| Symptom | Probable Cause | Corrective Action |
|---|---|---|
| **Terminal Offline** | Incorrect IP, unplugged network cable, or port 4370 blocked | Verify terminal IP; test network connectivity using `ping <Terminal-IP>`; verify port 4370 is open on intermediate switches. |
| **Terminal Busy / Retries Failing** | Legacy attendance software holding port 4370 open | AccessGuard retries with exponential backoff. Ensure legacy sync tools release the device or schedule their runs outside the 01:00 AM window. |
| **Oracle Test Connection Failed** | Listener offline, incorrect port, or bad credentials | Confirm Oracle Listener is running (`lsnrctl status`); check port 1521; verify service name (`ORCL` vs `XE`); test credentials via Oracle SQL Developer. |
| **Reconciler Returns 0 Records** | Missing Oracle views or mismatched schema names | Verify `MDPL_EMP_SHIFT_V` and `PP_EMP_ATT_MST_DW` exist in the configured schema. Ensure `AM_TIME` is stored as `YYYY/MM/DD HH24:MI`. |
| **Dashboard Inaccessible (:5000)** | Service stopped or port 5000 conflict | Run `Get-Service ZtkHardwareService` to verify running state. Check if another web application is bound to port 5000. |
| **Hardware Access Not Updating** | Device offline during pardon or cache delay | Check terminal connection; trigger **Run Reconciler Now** to push pending access groups. Wait 15–30 seconds for device buffer sync. |

---

*For detailed UI walkthroughs, refer to the [Live AccessGuard User Manual](https://release-iwbr0fq6o-junaiddbzs-projects.vercel.app/).*
