<p align="center">
  <img src="assets/logo.jpg" alt="DFC Manager" width="100%">
</p>
 
<p align="center">
  <img src="https://img.shields.io/badge/version-0.2.0-blue?style=flat-square" alt="version"/>
  <img src="https://img.shields.io/badge/platform-Ubuntu%2022%2F24%20%7C%20Debian%2011%2F12-orange?style=flat-square" alt="platform"/>
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="license"/>
  <img src="https://img.shields.io/badge/shell-bash-success?style=flat-square" alt="bash"/>
</p>
 
<h1 align="center">🛡️ DFC Manager</h1>
<p align="center">Интерактивный менеджер <a href="https://github.com/remnawave/panel">Remnawave Panel</a><br>с полным набором инструментов управления, тестирования и мониторинга.</p>
 
---
 
## 🚀 Установка
 
```bash
cd /opt && bash <(curl -s https://raw.githubusercontent.com/DanteFuaran/dfc-manager/main/dfc-manager.sh)
```
 
<p align="center">
  <big>
    ${\color{yellow}\text{После установки для открытия меню используйте команды: }}{\color{blue}\textbf{dfc}}{\color{yellow}\text{ или }}{\color{blue}\textbf{rw}}$
  </big>
</p>
 
---
 
<h2>$${\color{blue}\text{📦 Remnawave — Панель}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
Установка возможна в нескольких вариантах:
 
> **🟢 Панель + Страница подписки + Нода** — всё на одном сервере<br>
> **🟡 Панель + Страница подписки** — нода на отдельном сервере<br>
> **🟡 Панель + Нода** — страница подписки на отдельном сервере<br>
> **🟠 Только панель** — минимальная установка<br>
> **➕ Подключить ноду** — к уже установленной панели<br>
> **📄 Только страница подписки** — для существующей панели<br>
> **🌐 Только нода** — для подключения к удалённой панели
 
После установки доступны:
 
> **▶️ / ⏹️ Запуск и остановка** всех сервисов одной командой<br>
> **📋 Просмотр логов** по каждому контейнеру отдельно<br>
> **🔄 Обновление** панели и ноды без потери данных<br>
> **💾 Управление БД** — ручные и автоматические бэкапы в Telegram<br>
> **🔓 Настройки** — суперадмин, домены, cookie, шаблон-заглушка, порт панели
 
</details>
 
---
 
<h2>$${\color{blue}\text{📊 Beszel — Мониторинг}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
[Beszel](https://beszel.dev) — лёгкая система мониторинга серверов с веб-интерфейсом и SSL.
 
> **📊 Установка панели Beszel** — хаб с веб-интерфейсом через NGINX<br>
> **🖥️ Подключение агента** — установка сборщика метрик на сервер<br>
> **🌐 Смена домена** хаба с автоматическим перевыпуском SSL<br>
> **🔗 Смена адреса хаба** у установленного агента
 
</details>
 
---
 
<h2>$${\color{blue}\text{📡 MTProto — TG Прокси}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
Прокси-сервер для Telegram с **fake-TLS** маскировкой.
 
> **📦 Установка / переустановка** с автогенерацией порта и секрета<br>
> **⬆️ Обновление** Docker-образа<br>
> **📊 Статистика** подключений с геолокацией по IP<br>
> **🚫 Управление доступом** — whitelist / blacklist (IP и CIDR-подсети)<br>
> **📄 Готовая `tg://`-ссылка** для подключения<br>
> **🔑 Смена конфигурации** — порт и секрет<br>
> **▶️ / ⏹️ / 🔄 Запуск, остановка, перезапуск**
 
</details>
 
---
 
<h2>$${\color{blue}\text{🧩 Дополнительные программы}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
| Инструмент | Назначение |
|---|---|
| **🔥 UFW** | Управление firewall: правила, открытые порты, включение/выключение |
| **🌐 WARP** | Cloudflare WARP для исходящих соединений ноды |
| **🛡️ Fail2ban** | Защита от брутфорса SSH с настройкой параметров и статистикой блокировок |
 
</details>
 
---
 
<h2>$${\color{blue}\text{🧪 Тестирование сервера}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
> **⚡ Скорость сети** — Speedtest CLI (загрузка, отдача, latency, packet loss)<br>
> **🌍 Доступность сервисов** — Google, YouTube, Telegram и других<br>
> **🔒 Региональные ограничения** — проверка гео-блокировок текущего IP<br>
> **📍 Геолокация IP** — страна, провайдер, AS-номер
 
</details>
 
---
 
<h2>$${\color{blue}\text{⚙️ Оптимизация сервера}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
> **💾 SWAP** — создание, пересоздание и удаление swap-раздела с автоподбором размера под объём RAM<br>
> **🚀 BBR** — включение TCP BBR с комплексной сетевой оптимизацией (`fq`, `tcp_fastopen`, увеличенные буферы)
 
</details>
 
---
 
<h2>$${\color{blue}\text{🗑️ Удаление компонентов}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
Меню динамически показывает только установленные компоненты — каждый можно удалить отдельно или все сразу. NGINX-конфигурация автоматически пересобирается под оставшиеся сервисы.
 
</details>
 
---
 
<h2>$${\color{blue}\text{✨ Возможности}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
### 🔐 Безопасность
> Cookie-защита панели • мгновенная смена cookie • переключение порта 443 / 8443 • сброс суперадмина • Let's Encrypt и Cloudflare DNS-01 (wildcard) • whitelist/blacklist для MTProto
 
### 🌐 Управление доменами
> Смена домена панели, страницы подписки, ноды и Telegram-бота — с автоматическим перевыпуском SSL и проверкой DNS до установки
 
### 💾 Резервные копии
> Ручные и автоматические бэкапы (час / день / неделя / месяц) с отправкой архива в Telegram. Восстановление из любого сохранённого архива
 
### 🎨 Сайт-заглушка
> 20 готовых HTML-шаблонов + случайный выбор для маскировки сервера под обычный сайт
 
### ⚙️ Управление
> Запуск, остановка, обновление, просмотр логов и удаление — всё через единое меню `dfc`
 
</details>
 
---
 
<h2>$${\color{blue}\text{📋 Требования}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
> **🖥️ Система:** Ubuntu 22.04 / 24.04 или Debian 11 / 12, доступ `root` или `sudo`<br>
> **🌐 DNS:** 2–3 поддомена с A-записями на IP сервера<br>
> **🔐 SSL:** email для Let's Encrypt **или** Cloudflare API Token (для wildcard)
 
<sub>⚠️ ${\color{orange}\text{Все зависимости (Docker, Docker Compose, Certbot, git) устанавливаются автоматически.}}$</sub>
 
</details>
 
---
 
<h2>$${\color{red}\text{🔧 Решение проблем}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
### Перед установкой убедитесь, что:
> ✅ Все домены указывают на IP сервера через A-записи<br>
> ✅ Порты **80** и **443** свободны<br>
> ✅ Firewall разрешает входящие на **80**, **443**, **8443**<br>
> ✅ Email для Let's Encrypt введён корректно<br>
> ✅ Cloudflare API Token имеет права `Zone.DNS:Edit`
 
### Если что-то пошло не так:
> 📜 Логи: `dfc` → Просмотр логов<br>
> 🔄 Перезапуск: `dfc` → Запустить сервисы<br>
> 🆘 [Issue на GitHub](https://github.com/DanteFuaran/dfc-manager/issues) с текстом ошибки
 
</details>
 
---
 
<h2>$${\color{green}\text{💰 Поддержать проект}}$$</h2>
 
<details>
<summary>$${\color{gray}\text{Показать подробности:}}$$<br></summary>
 
<br>
 
### 💵 Криптовалюта
> **USDT (TRC-20):** `THqJQsgbWY7Tw1BxdLA6SQAkBGVmMhzeLZ`<br>
> **BTC (BEP-20):** `0x657685922d7a9c50e3e90cae3ba9905985349fbb`
 
### 🇷🇺 ЮMoney
> **Номер карты:** `4100118836481809`
 
<br>
 
<sub>❤️ Спасибо за вашу поддержку! Она помогает развивать проект.</sub>
 
</details>
 
---
 
## 📜 Лицензия
 
Проект распространяется под лицензией [MIT](LICENSE)
 
---
 
<p align="center">
  <b>⭐ Поставьте звезду, если проект оказался полезным!</b>
</p>
