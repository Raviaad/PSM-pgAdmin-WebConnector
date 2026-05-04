# PSM pgAdmin 4 Web Connector

CyberArk PSM AutoIT Web Connector for **pgAdmin 4** using **local authentication** (form-based login) against a PostgreSQL database.

Based on the [AutoIT Universal Web](https://github.com/Raviaad/Raviaad) template.

---

## Files

| File | Description |
|------|-------------|
| `pgAdmin4-web_PSM.au3` | AutoIT source script - edit `CHANGE_ME` values, then compile to `.exe` |
| `CC-pgAdmin4-web.xml` | PSM Connection Component XML - import via psPAS |

---

## Prerequisites

- CyberArk PSM server with AutoIT 3 installed
- Google Chrome installed on the PSM server
- pgAdmin 4 (v4.x) accessible from the PSM server (default: `http://<host>:5050`)
- pgAdmin running in **Server Mode** with local authentication enabled

---

## Build & Deploy Steps

### 1. Edit the AutoIT script

Open `pgAdmin4-web_PSM.au3` and review all `CHANGE_ME` comments:

| Variable | Default | Notes |
|---|---|---|
| `$WebPrefix` | `http://` | Change to `https://` if TLS is enabled |
| `$WebSuffix` | `:5050/login` | Change port if pgAdmin uses a non-default port |
| `$AppTimeout` | `45` | Seconds to wait for pgAdmin to load |
| `$KioskMode` | `yes` | Set to `no` for visible browser chrome |
| `$PAGE_LOADED_TITLE` | `pgAdmin 4` | Partial window title of login page |
| `$LOGIN_SUCCESS_TITLE` | `pgAdmin 4` | Partial window title after login |
| `$Tabs_Before_Username` | `0` | Tabs needed to reach email field |
| `$Tabs_From_Username_To_Password` | `1` | Tabs from email to password field |

### 2. Compile the exe

```shell
cd "C:\Program Files (x86)\AutoIt3\Aut2Exe"
.\Aut2Exe.exe /in "C:\Program Files (x86)\CyberArk\PSM\Components\pgAdmin4-web_PSM.au3" /out "C:\Program Files (x86)\CyberArk\PSM\Components\pgAdmin4-web_PSM.exe" /x86
```

### 3. Add to AppLocker

```xml
<Application Name="pgAdmin4-web_PSM" Type="Exe"
  Path="C:\Program Files (x86)\CyberArk\PSM\Components\pgAdmin4-web_PSM.exe"
  Method="Hash" />
```

Run the AppLocker script after adding the entry.

### 4. Import the Connection Component

```powershell
# Compress the XML first - zip name MUST start with CC-
Compress-Archive -Path .\CC-pgAdmin4-web.xml -DestinationPath .\CC-pgAdmin4-web.zip

# Import using psPAS
Import-PASConnectionComponent .\CC-pgAdmin4-web.zip
```

### 5. CyberArk Account Setup

When creating the CyberArk account for PostgreSQL/pgAdmin:

| CyberArk Field | Value |
|---|---|
| **Username** | pgAdmin login email (e.g. `admin@admin.com`) or postgres username |
| **Password** | pgAdmin login password |
| **Address** | Host only, e.g. `localhost` or `10.0.0.5` (no port, no path) |

### 6. Assign and Test

1. Assign `pgAdmin4-web` connection component to your PostgreSQL platform
2. Connect via PSM and verify the session records correctly

---

## pgAdmin Local Auth Notes

- pgAdmin 4 uses an **email address** as the login username in Server Mode
- The default admin email set during pgAdmin setup (e.g. `admin@admin.com`) should match what is stored in CyberArk
- pgAdmin does **not** support HTTP Basic authentication in the URL; the `form` auth mode in this script is mandatory
- If pgAdmin prompts for a **master password** after login, this connector does not handle that additional dialog - disable master password in pgAdmin preferences for PSM use

---

## License

MIT License - Copyright (c) 2024 Michal Masek / Raviaad
