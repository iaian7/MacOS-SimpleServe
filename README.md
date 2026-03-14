# MacOS-SimpleServe

Simple menu bar server management for local hosting of test websites in macOS. Host sites at `.test` domains with HTTPS support, powered by Homebrew services (Apache or Nginx, dnsmasq, mkcert).

## Prerequisites

- macOS
- [Homebrew](https://brew.sh) (required)
- Xcode (for building from source)

## Installation

1. Open `SimpleServe.xcodeproj` in Xcode.
2. Build and run (⌘R), or archive and export the app.

## Setup

Follow these steps before using SimpleServe:

| Step | Action | Notes |
|------|--------|-------|
| 1 | Install Homebrew | See [brew.sh](https://brew.sh) |
| 2 | Install required components | `brew install httpd dnsmasq mkcert` |
| 3 | Install optional (PHP, Nginx) | `brew install php` and/or `brew install nginx` if needed |
| 4 | Create DNS resolver | `sudo mkdir -p /etc/resolver && echo 'nameserver 127.0.0.1' | sudo tee /etc/resolver/test` |
| 5 | Install mkcert CA | `mkcert -install` (approve Keychain when prompted) |
| 6 | Optional: Port forwarding | Run setup from Settings > Commands for port-free URLs (80/443) |

The app shows component status and copy-paste commands in **Settings > Setup** and **Settings > Commands**.

## Usage

- **Launch** — Icon appears in the menu bar.
- **Click icon** — Popover shows your site list.
- **Add site** — Click +, choose project folder, enter hostname (e.g. `mysite` → `mysite.test`).
- **Toggle** — Switch sites on or off.
- **Actions** — Open in browser, open in Finder, edit (gear), delete (right-click).
- **Restart** — Button to restart all servers.
- **Settings** — Component Status, Commands (DNS, mkcert CA, port forwarding), Preferences (browser, menu icon, start at login).

## Notes & Conflict Warnings

### System Apache conflict

macOS includes built-in Apache. If it is running, it will conflict with SimpleServe’s Homebrew httpd. SimpleServe uses ports **8080** (HTTP) and **8443** (HTTPS).

- **Check if system Apache is running:** `apachectl status` or `ps aux | grep httpd` (look for `/usr/sbin/httpd`).
- **Stop it temporarily:** `sudo /usr/sbin/apachectl stop`
- **Disable it permanently:** `sudo launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist`

Stop or disable system Apache before starting SimpleServe.

### Port conflicts

Ports 8080 and 8443 must be free. To see what is using them:

```
lsof -i :8080 -i :8443
```

### Port forwarding

Port forwarding modifies `/etc/pf.conf`. It can affect networking. If problems occur, run the **revert** command shown in Settings > Commands.

### DNS / .test domains

Until the resolver is set up (step 4), use full URLs with the port (e.g. `http://mysite.test:8080`) or type the URL explicitly in Safari. Chrome and Firefox usually work better with `.test` domains and local HTTPS than Safari.

### mkcert

If Safari shows “connection is not private” after installing the CA, restart Safari or use Chrome.
