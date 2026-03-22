<p align="center">
  <img src="assets/logo.jpg" alt="DFC Manager" width="100%">
</p>

<p align="center">
  <a href="README.md">Русский</a> | <a href="README.en.md">English</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.2.0-blue?style=flat-square" alt="version"/>
  <img src="https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange?style=flat-square" alt="platform"/>
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="license"/>
</p>

<h1 align="center">🛡️ DFC Manager</h1>
<p align="center">Interactive installer and manager for <a href="https://github.com/remnawave/panel">Remnawave VPN Panel</a><br>with NGINX, SSL, cookie-protection and a full suite of management tools</p>

---

## 🚀 Quick Start

```bash
cd /opt && bash <(curl -Ls https://raw.githubusercontent.com/DanteFuaran/dfc-manager/refs/heads/main/dfc-manager.sh)
```

<sub>After installation, manage everything with <b><code>dfc-manager</code></b> or <b><code>dfc</code></b></sub>

---

<h2> $${\color{blue}📦 Installation\ Options}$$ </h2>

<details>
<summary>$${\color{gray}Show\ details:}$$<br></summary>

| Option | Description |
|---|---|
| **Panel + Node (single server)** | Full setup — panel, node, subscription page, NGINX, SSL on one VPS |
| **Panel only** | Install panel without a node |
| **Node only** | Install a node to connect to a remote panel |
| **Add node to panel** | Add a new node to a server with an already installed panel |

</details>

---

<h2> $${\color{blue}✨ Features}$$ </h2>

<details>
<summary>$${\color{gray}Show\ details:}$$<br></summary>

### 🔐 Security
> **Cookie-protected access** — unique cookie-link to the panel instead of a direct URL<br>
> **Instant cookie rotation** — invalidate all old access links in one click<br>
> **Panel port switching** — run on port 443 or 8443 as needed<br>
> **Superadmin reset** — generate new credentials without reinstalling<br>
> **SSL certificates** — Let's Encrypt HTTP-01 or Cloudflare DNS-01 wildcard

### 🌐 Domain Management
> **Panel domain change** — with automatic SSL renewal<br>
> **Subscription page domain change** — with automatic SSL renewal<br>
> **Node / selfsteal domain change** — updates node configuration<br>
> **DNS validation before install** — script verifies the domain points to this server

### 💾 Database & Backups
> **Manual backup** — PostgreSQL dump + `/opt/remnawave` directory packed into one `.tar.gz`<br>
> **Restore from backup** — load any saved archive<br>
> **Automatic backups** — scheduled via cron with Telegram delivery<br>
> **Schedule settings** — every 6 h / 12 h / 24 h / 48 h<br>
> **Telegram notifications** — archive sent directly to a chat or channel

### 🎨 Decoy Website (Masking)
> Installs an HTML template on the node's root domain — the server looks like an ordinary website.<br>
> **20 templates** available, or pick a random one:

| | | |
|---|---|---|
| 🏢 NexCore — Corporate Portal | 💻 DevForge — Tech Hub | ☁️ Nimbus — Cloud Services |
| 💳 PayVault — Fintech Platform | 📚 LearnHub — Education | 🎬 StreamBox — Media Portal |
| 🛒 ShopWave — E-commerce | 🎮 NeonArena — Gaming Portal | 👥 ConnectMe — Social Network |
| 📊 DataPulse — Analytics | ₿ CryptoNex — Crypto Exchange | ✈️ WanderWorld — Travel Agency |
| 💪 IronPulse — Fitness | 📰 VestnikPRO — News Portal | 🎵 SoundWave — Music Service |
| 🏠 HomeNest — Real Estate | 🍕 FastBite — Food Delivery | 🚗 AutoElite — Automotive |
| 🎨 Prisma Studio — Design | 💼 Vertex Advisory — Consulting | 🎲 Random template |

### 🧩 Extra Tools
> **🔥 Firewall (UFW)** — configure and manage firewall rules<br>
> **🌐 WARP** — install and manage Cloudflare WARP<br>
> **💾 SWAP** — create and manage swap space<br>
> **🚀 BBR** — enable TCP BBR for network optimization<br>
> **🛡️ Fail2ban** — brute-force protection<br>
> **📝 Logrotate** — Docker container log rotation<br>
> **📊 Beszel** — server monitoring (agent + hub)

### ⚙️ Service Management
> **Start / Stop** all services with one command<br>
> **Update panel and node** — pull new Docker images<br>
> **Reinstall** — full reinstall while preserving data<br>
> **View logs** — panel, node, NGINX, PostgreSQL in real time<br>
> **Remove node from panel server** — with automatic NGINX reconfiguration to port 443<br>
> **Full removal** — all components, data and configurations

</details>

---

<h2> $${\color{blue}📋 Requirements}$$ </h2>

<details>
<summary>$${\color{gray}Show\ details:}$$<br></summary>

### 🖥️ System
> **Ubuntu** 22.04 / 24.04<br>
> **Debian** 11 / 12<br>
> **root** access or `sudo`

### 🌐 Domains & DNS
> 2–3 subdomains with **A-records** pointing to the server IP

### 🔐 SSL
> Email for **Let's Encrypt**<br>
> or API Token for **Cloudflare DNS-01** (for wildcard)

<sub>⚠️ $${\color{orange}All\ dependencies\ (Docker,\ Docker\ Compose,\ Certbot)\ are\ installed\ automatically.}$$</sub>

</details>

---

<h2> $${\color{green}💰 Support\ the\ Project}$$ </h2>

<details>
<summary>$${\color{gray}Show\ details:}$$<br></summary>

<br>

### 💵 Crypto
> **USDT (TRC-20):** `THqJQsgbWY7Tw1BxdLA6SQAkBGVmMhzeLZ`<br>
> **BTC (BEP-20):** `0x657685922d7a9c50e3e90cae3ba9905985349fbb`

### YooMoney
> **Card:** `4100118836481809`

<br>

<sub>❤️ Thank you for your support — it helps keep the project alive!</sub>

</details>

---

<h2> $${\color{red}🔧 Troubleshooting}$$ </h2>

<details>
<summary>$${\color{gray}Show\ details:}$$<br></summary>

### Make sure:
> ✅ All domains have correct **A-records** pointing to the server IP<br>
> ✅ Ports **80** and **443** are free<br>
> ✅ Firewall allows inbound connections on **80**, **443**, **8443**<br>
> ✅ Email for Let's Encrypt is correct<br>
> ✅ Cloudflare **API Token** is valid (if using DNS-01)

### Solutions:
> 📜 Check component logs via `dfc` → View logs<br>
> 🔄 Try restarting services via `dfc` → Start services<br>
> 🆘 If the issue persists — open an [Issue on GitHub](https://github.com/DanteFuaran/dfc-manager/issues) with the error output

</details>

---

## 📜 License

[MIT](LICENSE)

---

<p align="center">
  <b>⭐ Leave a star if the project was helpful!</b>
</p>
