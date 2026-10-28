# Конфигурация виртуальной машины devops-vm

Документ позволяет восстановить машину с нуля до состояния снимка `03-ssh-hardened`.
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
| `03-ssh-hardened` | 28.10.2026 19:11 | усиление защиты SSH, порт 2222, UFW, имя `devops.local` |

Имя узла: `hostnamectl set-hostname devops-vm`, в `/etc/hosts` строка `127.0.1.1 devops-vm.devops.local devops-vm`; на хостовой системе в `hosts` добавлено `192.168.56.101    devops.local`.
