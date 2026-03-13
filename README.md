<p align="center">
  <img src="assets/logo.jpg" alt="DFC Remna Install" width="320"/>
</p>

<p align="center">
  <a href="README.md">🇷🇺 Русский</a> | <a href="README.en.md">🇬🇧 English</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.1.0-blue?style=flat-square" alt="version"/>
  <img src="https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange?style=flat-square" alt="platform"/>
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="license"/>
  <img src="https://img.shields.io/badge/shell-bash-lightgrey?style=flat-square" alt="shell"/>
</p>

<h1 align="center">🛡️ DFC Remna Install</h1>
<p align="center">Интерактивный установщик и менеджер <a href="https://github.com/remnawave/panel">Remnawave VPN Panel</a><br>с NGINX, SSL, cookie-защитой и полным набором инструментов управления</p>

---

## 🚀 Быстрый старт

```bash
cd /opt && bash <(curl -Ls https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/main/dfc-remna-install.sh)
```

<sub>После установки управление доступно через команду <b><code>remnawave</code></b> или <b><code>rw</code></b></sub>

---

## 📦 Варианты установки

| Вариант | Описание |
|---|---|
| **Панель + Нода (один сервер)** | Полная установка — панель, нода, подписка, NGINX, SSL на одном VPS |
| **Только панель** | Установка панели без ноды |
| **Только нода** | Установка ноды для подключения к удалённой панели |
| **Подключить ноду к панели** | Добавление новой ноды на сервер с уже установленной панелью |

---

## ✨ Возможности

<details>
<summary><b>🔐 Безопасность</b></summary>
<br>

- **Cookie-защита доступа** — уникальная cookie-ссылка на панель вместо прямого URL
- **Мгновенная смена cookie** — инвалидация всех старых ссылок в один клик
- **Переключение порта панели** — работа на 443 или 8443 на выбор
- **Сброс суперадмина** — генерация новых учётных данных без переустановки
- **SSL-сертификаты** — Let's Encrypt HTTP-01 или Cloudflare DNS-01 wildcard

</details>

<details>
<summary><b>🌐 Управление доменами</b></summary>
<br>

- **Смена домена панели** — с автоматическим перевыпуском SSL
- **Смена домена страницы подписки** — с автоматическим перевыпуском SSL
- **Смена домена ноды / selfsteal** — обновление конфигурации
- **Проверка DNS перед установкой** — скрипт убеждается что домен указывает на сервер

</details>

<details>
<summary><b>💾 База данных и резервные копии</b></summary>
<br>

- **Ручной бэкап** — архив БД PostgreSQL + директория `/opt/remnawave` в один `.tar.gz`
- **Восстановление из бэкапа** — загрузка из любого сохранённого архива
- **Автоматические бэкапы** — по расписанию (cron) с отправкой в Telegram
- **Настройка расписания** — каждые 6 ч / 12 ч / 24 ч / 48 ч
- **Telegram-нотификации** — архив отправляется напрямую в чат или канал

</details>

<details>
<summary><b>🎨 Сайт-заглушка (маскировка)</b></summary>
<br>

Скрипт устанавливает HTML-шаблон на корневой домен ноды — сервер выглядит как обычный сайт. Доступно **20 шаблонов** или случайный:

| | | |
|---|---|---|
| 🏢 NexCore — Корпоративный портал | 💻 DevForge — Технологический хаб | ☁️ Nimbus — Облачные сервисы |
| 💳 PayVault — Финтех платформа | 📚 LearnHub — Образовательная платформа | 🎬 StreamBox — Медиа портал |
| 🛒 ShopWave — E-commerce | 🎮 NeonArena — Игровой портал | 👥 ConnectMe — Социальная сеть |
| 📊 DataPulse — Аналитика | ₿ CryptoNex — Крипто биржа | ✈️ WanderWorld — Туризм |
| 💪 IronPulse — Фитнес | 📰 ВестникПРО — Новости | 🎵 SoundWave — Музыка |
| 🏠 HomeNest — Недвижимость | 🍕 FastBite — Доставка еды | 🚗 AutoElite — Автомобили |
| 🎨 Prisma Studio — Дизайн | 💼 Vertex Advisory — Консалтинг | 🎲 Случайный шаблон |

</details>

<details>
<summary><b>🧩 Дополнительные инструменты</b></summary>
<br>

- **🔥 Firewall (UFW)** — настройка и управление правилами
- **🌐 WARP** — установка и управление Cloudflare WARP
- **💾 SWAP** — создание и управление swap-разделом
- **🚀 BBR** — включение TCP BBR для оптимизации сети
- **🛡️ Fail2ban** — защита от брутфорса
- **📝 Logrotate** — ротация логов Docker-контейнеров
- **📊 Beszel** — мониторинг сервера (агент + hub)

</details>

<details>
<summary><b>⚙️ Управление сервисами</b></summary>
<br>

- **Запуск / остановка** всех сервисов одной командой
- **Обновление панели и ноды** — pull новых Docker-образов
- **Переустановка** — полная переустановка с сохранением данных
- **Просмотр логов** — панель, нода, NGINX, PostgreSQL в реальном времени
- **Удаление ноды с сервера панели** — с реконфигурацией NGINX на порт 443
- **Полное удаление** — все компоненты, данные и конфигурации

</details>

---

## 📋 Требования

| | |
|---|---|
| **ОС** | Ubuntu 22.04 / 24.04, Debian 11 / 12 |
| **Права** | root или sudo |
| **Домены** | 2–3 поддомена с A-записями на IP сервера |
| **SSL** | Email для Let's Encrypt **или** Cloudflare API Token |
| **Remnawave** | версия **2.5.24** или выше |

> ⚠️ Docker, Docker Compose и Certbot устанавливаются **автоматически**.

---

## 🔧 Решение проблем

<details>
<summary><b>Показать</b></summary>
<br>

**Перед установкой убедитесь:**
- Все домены имеют корректные A-записи на IP сервера
- Порты **80** и **443** свободны
- Firewall разрешает входящие соединения на 80, 443, 8443

**Инструменты диагностики:**
- Просмотр логов: `remnawave` → Просмотр логов
- Перезапуск: `remnawave` → Запустить сервисы
- При неразрешимой проблеме — откройте [Issue на GitHub](https://github.com/DanteFuaran/dfc-remna-install/issues) с текстом ошибки

</details>

---

## 💰 Поддержать проект

<details>
<summary><b>Показать реквизиты</b></summary>
<br>

| Метод | Реквизиты |
|---|---|
| **USDT (TRC-20)** | `THqJQsgbWY7Tw1BxdLA6SQAkBGVmMhzeLZ` |
| **BTC (BEP-20)** | `0x657685922d7a9c50e3e90cae3ba9905985349fbb` |
| **ЮMoney** | `4100118836481809` |

❤️ Спасибо за поддержку — она помогает развивать проект!

</details>

---

## 📜 Лицензия

[MIT](LICENSE)

---

<p align="center">
  <b>⭐ Поставьте звезду, если проект оказался полезным!</b>
</p>
