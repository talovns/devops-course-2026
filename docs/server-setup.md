# Конфигурация виртуальной машины devops-vm

Документ позволяет восстановить машину с нуля до итогового состояния ПР №5 (снимок `03-ssh-hardened` плюс межсетевой экран и имя узла).
Хост: Windows, VirtualBox 7.x. Гостевая ОС: Ubuntu Server 26.04.1 LTS (установочный образ `ubuntu-26.04.1-live-server-amd64.iso`).

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Имя в VirtualBox | `devops-vm` |
| Тип и версия | Linux / Ubuntu (64-bit) |
| Оперативная память | 2048 МБ |
| Процессоры | 2 ядра |
| Диск | 25 ГБ, динамически расширяемый (VDI), SATA |
| Оптический привод | образ Ubuntu Server (только на время установки) |

Установка: язык English, раскладка English (US), тип Ubuntu Server (не minimized), разметка Use an entire disk (LVM по умолчанию, без шифрования), имя сервера `devops-vm`, пользователь `student`, Ubuntu Pro пропущен, пакеты Featured snaps не выбираются.
При установке не отмечался компонент OpenSSH server, поэтому его установили после первого входа: `sudo apt install -y openssh-server`.
После установки: `sudo apt update && sudo apt upgrade -y`.

## 2. Сетевые интерфейсы

| Адаптер | Тип | Интерфейс в ОС | Адрес | Назначение |
|---|---|---|---|---|
| 1 | NAT | `enp0s3` | `10.0.2.15/24` (DHCP) | доступ в Интернет (репозитории пакетов) |
| 2 | Host-only (`VirtualBox Host-Only Ethernet Adapter #2`) | `enp0s8` | `192.168.56.101/24` (DHCP) | связь с хостовой системой, обращение из браузера |

Сеть Host-only создаётся в менеджере сетей VirtualBox (Ctrl+H): адрес хоста `192.168.56.1`, маска `255.255.255.0`, DHCP-сервер включён (`192.168.56.100`, диапазон `192.168.56.101` – `192.168.56.254`).

## 3. Правило проброса портов

Адаптер 1 (NAT), правило `ssh`:

| Параметр | Значение |
|---|---|
| Протокол | TCP |
| Адрес хоста | `127.0.0.1` |
| Порт хоста | `2222` |
| Адрес гостя | не задаётся |
| Порт гостя | `2222` (до задания 2 был `22`) |

## 4. Учётные записи

| Имя | Группы | Способ аутентификации |
|---|---|---|
| `student` | `student`, `sudo`, `users` и др. (создан установщиком) | пароль; по SSH вход закрыт директивой `AllowUsers devops`, используется только в консоли ВМ |
| `devops` | `devops`, `sudo`, `users` | по SSH только по ключу ed25519; пароль нужен для `sudo` |

Создание `devops`:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
```

Ключ на хостовой системе: `ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm` (без парольной фразы).
Открытый ключ на сервере: `/home/devops/.ssh/authorized_keys` (права `600`, каталог `~/.ssh` — `700`, владелец `devops`).
На хостовой системе в `~/.ssh/config`:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

Резервная копия основного файла: `/etc/ssh/sshd_config.backup`. Основной файл не изменяется, настройки лежат в дополняющем файле `/etc/ssh/sshd_config.d/99-hardening.conf`:

| Директива | Значение |
|---|---|
| `Port` | `2222` |
| `PermitRootLogin` | `no` |
| `PasswordAuthentication` | `no` |
| `PubkeyAuthentication` | `yes` |
| `PermitEmptyPasswords` | `no` |
| `MaxAuthTries` | `3` |
| `LoginGraceTime` | `30` |
| `AllowUsers` | `devops` |
| `X11Forwarding` | `no` |
| `ClientAliveInterval` | `300` |
| `ClientAliveCountMax` | `2` |

Особенности:
- Конфликтующие значения `PasswordAuthentication yes` в других файлах каталога `sshd_config.d` (например `50-cloud-init.conf`) закомментированы, потому что действует первое встреченное значение.
- Активация по сокету отключена, иначе порт остаётся 22: `sudo systemctl disable --now ssh.socket`, `sudo systemctl enable --now ssh.service`, `sudo systemctl restart ssh`.
- Проверка до перезапуска: `sudo sshd -t`; действующие значения: `sudo sshd -T`.
- Проверку нового соединения выполняют в отдельном терминале, не закрывая рабочую сессию.

## 6. Правила межсетевого экрана

Политики по умолчанию: входящий трафик `deny`, исходящий `allow`.

| Правило | Действие | Комментарий |
|---|---|---|
| `2222/tcp` | LIMIT (не более 5 соединений за 30 с с одного адреса) | SSH rate-limited |
| `80/tcp` | ALLOW | HTTP (для ПР №6) |
| `443/tcp` | ALLOW | HTTPS |

Порядок: сначала разрешающие правила, затем `ufw enable` (иначе сессия оборвётся).

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
```

Команда `ufw allow ssh` не используется: она открывает порт 22 по `/etc/services`.

## 7. Снимки состояния

| Наименование | Момент создания | Состояние |
|---|---|---|
| `01-clean-install` | 28.10.2026 18:39 | чистая установка, SSH-сервер установлен, обновления применены |
| `02-keys-configured` | 28.10.2026 19:05 | пользователь `devops`, ключ, `ssh devops` без пароля |
| `03-ssh-hardened` | 28.10.2026 19:11 | усиление защиты SSH, порт 2222, вход по ключу, root и пароли запрещены |
| `04-nginx-https` | 28.10.2026 19:41 | nginx, ресурс `devops-site` по HTTPS, перенаправление HTTP -> HTTPS |
| `05-docker-compose` | 28.10.2026 21:58 | Docker Engine, проект `~/app` (приложение + PostgreSQL) запущен |

Имя узла: `hostnamectl set-hostname devops-vm`, в `/etc/hosts` строка `127.0.1.1 devops-vm.devops.local devops-vm`; на хостовой системе в `hosts` добавлено `192.168.56.101    devops.local`.

## 8. Веб-сервер

Пакет: `nginx` (из репозитория Ubuntu, `sudo apt install -y nginx`). Служба `nginx.service`: главный процесс от `root`, рабочие от `www-data`.

| Параметр | Значение |
|---|---|
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, активирована ссылкой `/etc/nginx/sites-enabled/devops-site` |
| Стандартный ресурс | ссылка `/etc/nginx/sites-enabled/default` удалена (конфигурация сохранена) |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталоги `755`, файлы `644` |
| Журналы ресурса | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |
| Сертификат | `/etc/ssl/certs/devops.crt`, права `644`, владелец `root` |
| Закрытый ключ | `/etc/ssl/private/devops.key`, права `600`, владелец `root` |
| Срок действия сертификата | 365 дней (выпущен 28.10.2026) |

Команда формирования сертификата (самоподписанный, с полем SAN):

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

Конфигурация состоит из двух блоков `server`: порт 80 возвращает `301 https://$host$request_uri`; порт 443 (`ssl`, протоколы TLSv1.2 и TLSv1.3) отдаёт содержимое `root /var/www/devops-site`, страницу ошибки `404.html`. Заголовок HSTS не используется. Любое изменение применяется командой `sudo nginx -t && sudo systemctl reload nginx` (не `restart`).
Сертификат передаётся на хостовую систему по SSH: `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`; проверка клиентом: `curl --cacert ~/devops.crt https://devops.local`.
Порты 80 и 443 уже разрешены правилами UFW из раздела 6, профили `Nginx HTTP/HTTPS/Full` не применяются.

## 9. Контейнеризация

Docker Engine установлен из официального репозитория Docker (`https://download.docker.com/linux/ubuntu`, набор `resolute`, ключ `/etc/apt/keyrings/docker.asc`, источник `/etc/apt/sources.list.d/docker.sources`) по инструкции docs.docker.com. Пакет `docker.io` из репозитория Ubuntu не используется (перед установкой проверено, что его нет).

```bash
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops     # применяется в новой SSH-сессии
```

| Параметр | Значение |
|---|---|
| Версии | Docker Engine 29.9.2 (клиент и сервер), Docker Compose v5.6.1, containerd.io 2.4.2 |
| Служба | `docker.service`, включена и активна |
| Группа `docker` | только `devops` (участник группы фактически получает права root, поэтому в группу включаются только учётные записи с правом sudo) |
| Каталог проекта | `/home/devops/app` (владелец `devops`, каталоги `755`, файлы `644`); имя проекта Compose `app` |
| Исходный код | каталог `app/` репозитория; доставка `rsync -avz --delete --exclude=.env --chmod=D755,F644 app/ devops:app/`, сначала с `--dry-run` |
| Файл секретов | `/home/devops/app/.env`, права `600`, владелец `devops`; создаётся только на сервере из `.env.example`, пароль `openssl rand -hex 16`; в репозиторий не попадает (`.gitignore`, `.dockerignore`) |
| Образы | `devops-app:1.0` (собирается из `app/Dockerfile`, процесс от пользователя `app`), `postgres:16-alpine` |
| Контейнеры | `app-app-1`, `app-db-1`; `restart: unless-stopped` (поднимаются после перезагрузки) |
| Сеть | `app_backend` (bridge), имя СУБД внутри сети: `db` |
| Публикуемые порты | приложение: только `127.0.0.1:5000`; порт СУБД `5432` не публикуется |
| Именованный том | `app_db_data` -> `/var/lib/postgresql/data`; удаляется только `docker compose down -v` (на рабочем сервере не применять) |
| Проверка готовности СУБД | `pg_isready` каждые 5 с; приложение запускается после состояния `healthy` |

Запуск и обновление: `cd ~/app && docker compose up -d --build`; состояние: `docker compose ps`; журнал: `docker compose logs app`.

Публикация через обратный прокси-сервер: в блок HTTPS `/etc/nginx/sites-available/devops-site` добавлено расположение (статический ресурс `location /` сохранён):

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Завершающий `/` в `proxy_pass` заменяет префикс: запрос `https://devops.local/app/health` передаётся приложению как `/health`. Применение: `sudo nginx -t && sudo systemctl reload nginx`. Если контейнер приложения остановлен, nginx отвечает `502 Bad Gateway`, в `/var/log/nginx/devops-site.error.log` запись `connect() failed (111: Connection refused) while connecting to upstream`.

Публикация `-p 5001:5000` (на всех адресах) обходит UFW: Docker добавляет собственные правила в iptables до цепочек UFW. Поэтому порт приложения публикуется только на `127.0.0.1`, а наружу ресурс доступен через nginx по HTTPS (порт 443).
