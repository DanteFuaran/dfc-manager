<p align="center">
  <img src="assets/logo.jpg" alt="DFC Remna Install" width="100%">
</p>

<h1 align="center">🛡️ DFC Remna Install</h1>
<p align="center">Interactive installer and manager for <a href="https://github.com/remnawave/panel">Remnawave VPN Panel</a><br>with NGINX, SSL, cookie-protection and a full suite of management tools</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.1.0-blue?style=flat-square" alt="version"/>
  <img src="https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange?style=flat-square" alt="platform"/>
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="license"/>
  <a href="README.md"><img src="https://img.shields.io/badge/lang-RU-blue?style=flat-square" alt="RU"></a>
  <a href="README.en.md"><img src="https://img.shields.io/badge/lang-EN-lightgrey?style=flat-square" alt="EN"></a>
</p>

---

## 🚀 Quick Start

```bash
cd /opt && bash <(curl -Ls https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/dfc-remna-install.sh)
```

<sub>After installation, manage everything with <b><code>remnawave</code></b> or <b><code>rw</code></b></sub>

---

<details>
<summary><b>📦 Installation Options</b></summary>
<br>

| Option | Description |
|---|---|
| **Panel + Node (single server)** | Full setup — panel, node, subscription page, NGINX, SSL on one VPS |
| **Panel only** | Install panel without a node |
| **Node only** | Install a node to connect to a remote panel |
| **Add node to panel** | Add a new node to a server with an already installed panel |

</details>

---

<details>
<summary><b>✨ Features</b></summary>
<br>

<details>
<summary><b>🔐 Security</b></summary>
<br>

- **Cookie-protected access** — unique cookie-link to the panel instead of a direct URL
- **Instant cookie rotation** — invalidate all old access links in one click
- **Panel port switching** — run on port 443 or 8443 as needed
- **Superadmin reset** — generate new credentials without reinstalling
- **SSL certificates** — Let's Encrypt HTTP-01 or Cloudflare DNS-01 wildcard

</details>

<details>
<summary><b>🌐 Domain Management</b></summary>
<br>

- **Panel domain change** — with automatic SSL renewal
- **Subscription page domain change** — with automatic SSL renewal
- **Node / selfsteal domain change** — updates node configuration
- **DNS validation before install** — script verifies the domain points to this server

</details>

<details>
<summary><b>💾 Database & Backups</b></summary>
<br>

- **Manual backup** — PostgreSQL dump + `/opt/remnawave` directory packed into one `.tar.gz`
- **Restore from backup** — load any saved archive
- **Automatic backups** — scheduled via cron with Telegram delivery
- **Schedule settings** — every 6 h / 12 h / 24 h / 48 h
- **Telegram notifications** — archive sent directly to a chat or channel

</details>

<details>
<summary><b>🎨 Decoy Website (Masking)</b></summary>
<br>

Installs an HTML template on the node's root domain — the server looks like an ordinary website. **20 templates** available or pick a random one:

| | | |
|---|---|---|
| 🏢 NexCore — Corporate Portal | 💻 DevForge — Tech Hub | ☁️ Nimbus — Cloud Services |
| 💳 PayVault — Fintech Platform | 📚 LearnHub — Education | 🎬 StreamBox — Media Portal |
| 🛒 ShopWave — E-commerce | 🎮 NeonArena — Gaming Portal | 👥 ConnectMe — Social Network |
| 📊 DataPulse — Analytics | ₿ CryptoNex — Crypto Exchange | ✈️ WanderWorld — Travel Agency |
| 💪 IronPulse — Fitness | 📰 VestnikPRO — News Portal | 🎵 SoundWave — Music Service |
| 🏠 HomeNest — Real Estate | 🍕 FastBite — Food Delivery | 🚗 AutoElite — Automotive |
| 🎨 Prisma Studio — Design | 💼 Vertex Advisory — Consulting | 🎲 Random template |

</details>

<details>
<summary><b>🧩 Extra Tools</b></summary>
<br>

- **🔥 Firewall (UFW)** — configure and manage firewall rules
- **🌐 WARP** — install and manage Cloudflare WARP
- **💾 SWAP** — create and manage swap space
- **🚀 BBR** — enable TCP BBR for network optimization
- **🛡️ Fail2ban** — brute-force protection
- **📝 Logrotate** — Docker container log rotation
- **📊 Beszel** — server monitoring (agent + hub)

</details>

<details>
<summary><b>⚙️ Service Management</b></summary>
<br>

- **Start / Stop** all services with one command
- **Update panel and node** — pull new Docker images
- **Reinstall** — full reinstall while preserving data
- **View logs** — panel, node, NGINX, PostgreSQL in real time
- **Remove node from panel server** — with automatic NGINX reconfiguration to port 443
- **Full removal** — all components, data and configurations

</details>

</details>

---

<details>
<summary><b>📋 Requirements</b></summary>
<br>

| | |
|---|---|
| **OS** | Ubuntu 22.04 / 24.04, Debian 11 / 12 |
| **Access** | root or sudo |
| **Domains** | 2–3 subdomains with A-records pointing to the server IP |
| **SSL** | Email for Let's Encrypt **or** Cloudflare API Token |
| **Remnawave** | version **2.5.24** or higher |

> ⚠️ Docker, Docker Compose and Certbot are installed **automatically**.

</details>

---

<details>
<summary><b>💰 Support the Project</b></summary>
<br>

| Method | Details |
|---|---|
| **USDT (TRC-20)** | `THqJQsgbWY7Tw1BxdLA6SQAkBGVmMhzeLZ` |
| **BTC (BEP-20)** | `0x657685922d7a9c50e3e90cae3ba9905985349fbb` |
| **YooMoney** | `4100118836481809` |

❤️ Thank you for your support — it helps keep the project alive!

</details>

---

<details>
<summary><b>🔧 Troubleshooting</b></summary>
<br>

**Before installation, make sure:**
- All domains have A-records pointing to the server IP
- Ports **80** and **443** are free
- Firewall allows inbound connections on 80, 443, 8443

**Diagnostic tools:**
- View logs: `remnawave` → View logs
- Restart services: `remnawave` → Start services
- If the issue persists — open an [Issue on GitHub](https://github.com/DanteFuaran/dfc-remna-install/issues) with the error output

</details>

---

## 📜 License

[MIT](LICENSE)

---

<p align="center">
  <b>⭐ Leave a star if the project was helpful!</b>
</p>
