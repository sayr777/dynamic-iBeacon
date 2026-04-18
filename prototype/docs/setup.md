# Руководство по установке и прошивке прототипа

**Плата:** ProMicro NRF52840 v1940 (клон nice!nano v2.0)  
**Прошивка:** TinyGo 0.40.x + `tinygo.org/x/bluetooth`  
**Язык:** Go  

---

## Содержание

1. [Что нужно](#1-что-нужно)
2. [Установка ПО — Windows](#2-установка-по--windows)
3. [Установка ПО — macOS](#3-установка-по--macos)
4. [Получение исходников](#4-получение-исходников)
5. [Сборка прошивки](#5-сборка-прошивки)
6. [Прошивка платы](#6-прошивка-платы)
7. [Мониторинг Serial-лога](#7-мониторинг-serial-лога)
8. [Описание лога](#8-описание-лога)
9. [Алгоритм работы](#9-алгоритм-работы)
10. [Критерии проверки](#10-критерии-проверки)
11. [Проверка через nRF Connect](#11-проверка-через-nrf-connect)
12. [Типичные проблемы](#12-типичные-проблемы)

---

## 1. Что нужно

### Оборудование

| Компонент | Примечание |
|---|---|
| ProMicro NRF52840 v1940 | AliExpress: «SuperMini nRF52840» или «Pro Micro NRF52840» |
| USB-C кабель | Только для данных — зарядные кабели без данных не подойдут |
| Смартфон (Android/iOS) | Для проверки BLE через nRF Connect |

### ПО на ПК

| Программа | Версия | Назначение |
|---|---|---|
| Go | **1.22–1.24** (не 1.25+) | компилятор языка |
| TinyGo | **0.40.x** | компилятор для микроконтроллеров |
| nRF Connect (смартфон) | любая актуальная | BLE-сканер для проверки |

> ⚠️ **Важно про версии Go и TinyGo:**  
> TinyGo 0.40.x поддерживает Go **1.19–1.24** включительно.  
> Go 1.25 и 1.26 вызовут ошибку: `requires go version 1.19 through 1.24, got go1.26`.  
> Установите Go **1.24** параллельно существующему — инструкции ниже.

---

## 2. Установка ПО — Windows

### 2.1 Установить scoop (менеджер пакетов)

Если scoop ещё не установлен, в PowerShell (обычный пользователь):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

Закрыть и открыть PowerShell заново.

### 2.2 Установить Go 1.24

TinyGo 0.40.x **не работает** с Go 1.25+. Устанавливаем версию 1.24 из bucket `versions`:

```powershell
scoop bucket add versions
scoop install versions/go124
```

Проверить:

```powershell
go version
# → go version go1.24.x windows/amd64 (или arm64)
```

> Если уже установлен другой Go (например 1.26) — Go 1.24 установится рядом  
> и станет активным через shim scoop. Старая версия не удаляется.

### 2.3 Установить TinyGo

```powershell
scoop install tinygo
```

Проверить:

```powershell
tinygo version
# → tinygo version 0.40.x windows/amd64 (using go version go1.24.x ...)
```

> Если `tinygo` выдаёт `could not find 'go' command` — убедитесь что `C:\Users\<user>\scoop\shims`  
> есть в `PATH`. Scoop должен добавить его автоматически при установке.

### 2.4 Установить nRF Connect на смартфон

- Android: [Google Play — nRF Connect](https://play.google.com/store/apps/details?id=no.nordicsemi.android.mcp)  
- iOS: [App Store — nRF Connect](https://apps.apple.com/app/nrf-connect-for-mobile/id1054362403)

### 2.5 (Опционально) Serial-терминал

`tinygo monitor` встроен и работает без дополнительных программ.  
Альтернатива — **PuTTY**: [putty.org](https://www.putty.org), параметры: `COM<N>`, 115200 baud.

---

## 3. Установка ПО — macOS

### 3.1 Установить Homebrew (если не установлен)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3.2 Установить Go 1.24

```bash
# Через homebrew-core (актуальная версия может быть новее):
brew install go

# Если установилась версия > 1.24, поставить точную версию через goenv:
brew install goenv
goenv install 1.24.2
goenv global 1.24.2
echo 'export PATH="$HOME/.goenv/shims:$HOME/.goenv/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Или скачать pkg-установщик напрямую:  
`https://go.dev/dl/go1.24.2.darwin-arm64.pkg` (Apple Silicon)  
`https://go.dev/dl/go1.24.2.darwin-amd64.pkg` (Intel)

Проверить:

```bash
go version
# → go version go1.24.x darwin/arm64
```

### 3.3 Установить TinyGo

```bash
brew tap tinygo-org/tools
brew install tinygo
```

Или скачать .tar.gz с [github.com/tinygo-org/tinygo/releases](https://github.com/tinygo-org/tinygo/releases):

```bash
# Apple Silicon (M1/M2/M3):
curl -L https://github.com/tinygo-org/tinygo/releases/download/v0.40.0/tinygo0.40.0.darwin-arm64.tar.gz | tar xz
sudo mv tinygo /usr/local/

# Добавить в PATH:
echo 'export PATH=$PATH:/usr/local/tinygo/bin' >> ~/.zshrc
source ~/.zshrc
```

Проверить:

```bash
tinygo version
# → tinygo version 0.40.x darwin/arm64 (using go version go1.24.x ...)
```

### 3.4 Права на USB (macOS не требует драйверов)

Плата определяется автоматически как USB CDC устройство.  
В режиме загрузчика — как USB Mass Storage диск.

### 3.5 Установить nRF Connect на смартфон

Ссылки те же что в п. 2.4.

---

## 4. Получение исходников

```bash
git clone <url-репозитория>
cd ble-tag-jdy23-dynamic/prototype/firmware/tinygo
```

Загрузить Go-зависимости:

```bash
go mod tidy
```

Ожидаемый вывод — скачивает пакеты (только первый раз):

```
go: downloading tinygo.org/x/bluetooth v0.10.0
go: downloading github.com/saltosystems/winrt-go ...
...
```

После `go mod tidy` должны появиться/обновиться файлы:
- `go.mod` — список зависимостей
- `go.sum` — контрольные суммы (добавить в git)

---

## 5. Сборка прошивки

```bash
# Из директории prototype/firmware/tinygo:
tinygo build -o firmware.uf2 -target=nicenano .
```

**Успешный результат** — никакого вывода + файл `firmware.uf2` (~130–150 KB):

```
ls -lh firmware.uf2
# → -rw-r--r--  1 user  staff   137K  18 Apr 14:21 firmware.uf2
```

На Windows:

```powershell
Get-Item firmware.uf2 | Select-Object Name, Length
# → firmware.uf2   139776
```

### Типичные ошибки сборки

| Ошибка | Причина | Решение |
|---|---|---|
| `requires go version 1.19 through 1.24, got go1.26` | Установлен Go 1.25+ | Установить Go 1.24 (п. 2.2 / 3.2) |
| `could not find 'go' command` | TinyGo не видит Go в PATH | Убедиться что `go version` работает в той же сессии |
| `unknown field AdvertisementType` | Старая версия кода с несовместимым API | Поле `AdvertisementType` убрано — убедиться что используется актуальный `main.go` |
| `no such file or directory: main.go` | Запуск не из папки `tinygo/` | `cd prototype/firmware/tinygo` |

---

## 6. Прошивка платы

### 6.1 Как войти в режим загрузчика (bootloader)

Плата имеет встроенный **Adafruit UF2 bootloader**. Для входа:

**Способ A — двойной RESET (физический):**

```
Найти пины RST и GND на плате (подписаны на шелкографии)
Коротко замкнуть RST → GND ... подождать ~300ms ... снова RST → GND
Суммарно за ~600ms (два касания)
```

> ⏱ **Тайминг критичен:** слишком быстро (<100ms) — не сработает,  
> слишком медленно (>800ms) — плата перезагрузится в обычный режим.  
> Оптимально: касание ~200ms, пауза ~300ms, повтор.

**Способ B — через `tinygo flash` (автоматически):**

```bash
tinygo flash -target=nicenano -port <PORT> .
```

TinyGo открывает порт на скорости **1200 baud**, что является сигналом  
загрузчику («1200-baud touch»). Плата сама войдёт в UF2-режим,  
TinyGo дождётся диска и скопирует прошивку.

### 6.2 Определение COM-порта

**Windows** — Диспетчер устройств → Порты (COM и LPT):

```powershell
Get-WMIObject Win32_SerialPort | Select-Object Name, DeviceID
# → Устройство с последовательным интерфейсом USB (COM6)   COM6
```

> ⚠️ **Порт меняет номер** после каждой перезагрузки платы.  
> Например: COM8 (обычный режим) → диск NICENANO (bootloader) → COM6 (после прошивки).  
> Всегда проверяйте актуальный номер перед подключением.

**macOS:**

```bash
ls /dev/cu.*
# → /dev/cu.usbmodem14101  (обычный режим)
# → /dev/cu.usbmodem1101   (или другой номер — после прошивки)
```

В режиме загрузчика на macOS появится диск `/Volumes/NICENANO`.

### 6.3 Индикатор режима загрузчика

| Состояние | Признак |
|---|---|
| Обычный режим (прошивка работает) | COM-порт в системе, диска нет |
| Режим загрузчика | Диск **NICENANO** (Windows/macOS) или `/Volumes/NICENANO` (macOS) |
| Загрузчик без прошивки (первый раз) | Диск **NRF52BOOT** |

### 6.4 Прошивка — Способ A: `tinygo flash` (рекомендуется)

```bash
# Windows:
tinygo flash -target=nicenano -port COM6 .

# macOS:
tinygo flash -target=nicenano -port /dev/cu.usbmodem14101 .
```

TinyGo автоматически:
1. Отправляет «1200-baud touch» на указанный порт
2. Ждёт появления UF2-диска
3. Копирует прошивку
4. Плата перезагружается с новой прошивкой

**Успешный результат** — команда завершается без вывода (exit code 0).

> Если ошибка `Serial port busy`: закройте все программы использующие порт  
> (tinygo monitor, PuTTY, Arduino IDE и т.д.)

### 6.5 Прошивка — Способ B: копирование UF2 вручную

1. Войти в режим загрузчика (п. 6.1, Способ A)
2. Дождаться появления диска **NICENANO** в проводнике

```bash
# macOS:
cp firmware.uf2 /Volumes/NICENANO/

# Windows (PowerShell):
Copy-Item firmware.uf2 D:\   # D: — буква диска NICENANO
```

3. Диск автоматически исчезнет — плата перезагружается с новой прошивкой.

> ❌ **Не используйте** `cp` с флагами `-p`, `--preserve` или rsync —  
> загрузчик ожидает стандартную запись, иначе прошивка не применится.

---

## 7. Мониторинг Serial-лога

После прошивки плата создаёт USB CDC Serial порт. Подключиться:

```bash
# Windows:
tinygo monitor -port COM6

# macOS:
tinygo monitor -port /dev/cu.usbmodem14101

# Или любой terminal (115200 baud, 8N1):
# Windows: PuTTY → Serial → COM6 → 115200
# macOS:   screen /dev/cu.usbmodem14101 115200
```

> ⚠️ **Первые строки могут пропасть:** USB CDC поднимается ~1–2 секунды после старта.  
> Строки `BLE Tag starting...` и шапка `===` печатаются до готовности USB —  
> вы увидите лог начиная с первого слота. Это нормально.

---

## 8. Описание лога

### Шапка (печатается один раз при старте)

```
========================================
BLE Tag  TagID=42   SlotDuration=10s
UUID     E2C56DB5-DFFB-48D2-B060-D0F5A71096E0
========================================
```

| Поле | Значение |
|---|---|
| `TagID=42` | Уникальный ID метки. **Не передаётся в эфир** — только внутренний идентификатор |
| `SlotDuration=10s` | Длительность одного слота. В тестовом режиме — 10 сек, в production — 5 мин |
| `UUID` | Константный UUID iBeacon. Одинаковый для всех меток в системе. Нужен сканеру чтобы отличить наши метки от чужих |

### Строки слотов (печатаются при каждой смене слота)

```
[slot    2] TagID=42  Major=0x4B10  Minor=0x545F  MAC=EB:F9:80:25:0E:94
[slot    3] TagID=42  Major=0x256A  Minor=0x7E30  MAC=C1:CC:71:D1:7F:82
[slot    4] TagID=42  Major=0xA410  Minor=0xA150  MAC=F0:EB:09:70:D9:86
[slot    5] TagID=42  Major=0x2C5C  Minor=0x8F92  MAC=DE:27:9D:15:76:C6
[slot    6] TagID=42  Major=0x305E  Minor=0xC636  MAC=D6:F4:13:DF:AC:28
[slot    7] TagID=42  Major=0xE896  Minor=0xFC0C  MAC=F0:F4:DE:0D:68:E3
```

| Поле | Описание |
|---|---|
| `[slot N]` | Номер слота, считается от старта прошивки: `uptime / SlotDuration`. В production заменяется на `unix_time / 300` |
| `TagID=42` | Повтор TagID (для удобства при нескольких метках в сети) |
| `Major=0xXXXX` | 2-байтное значение из AES-вывода `[0:2]`. Передаётся в iBeacon-пакете. Меняется каждый слот |
| `Minor=0xXXXX` | 2-байтное значение из AES-вывода `[2:4]`. Передаётся в iBeacon-пакете. Меняется каждый слот |
| `MAC=XX:XX:XX:XX:XX:XX` | BLE MAC-адрес метки в эфире. Первый байт всегда `≥ 0xC0` (Random Static). Меняется каждый слот |

### Что значит «детерминированность»

Значения Major, Minor, MAC для одного и того же TagID и номера слота **всегда одинаковые** — при любом количестве перезагрузок, на любом устройстве с тем же ключом. Это основа серверной идентификации.

Пример: `Slot 4` с `TagID=42` и данным KEY **всегда** даёт:
```
Major=0xA410  Minor=0xA150  MAC=F0:EB:09:70:D9:86
```

---

## 9. Алгоритм работы

### Общая схема

```
TagID (скрыт) + Slot + KEY
          ↓
    AES-128-ECB
          ↓
    16 байт вывода
    ┌──────────┬──────────┬──────────────────────┐
    │ [0:2]    │ [2:4]    │ [4:10]               │
    │ Major    │ Minor    │ MAC (6 байт)          │
    └──────────┴──────────┴──────────────────────┘
          ↓              ↓                ↓
    iBeacon payload               BLE address
```

### Входной блок AES (16 байт)

```
[0]      TagID >> 8          (старший байт TagID)
[1]      TagID & 0xFF        (младший байт TagID)
[2]      slot >> 24
[3]      slot >> 16
[4]      slot >> 8
[5]      slot & 0xFF
[6..15]  0x00 (нули, padding)
```

Пример для TagID=42, Slot=4:
```
2A 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00
│    │  └─────────────────────────────── slot=4 (0x00000004)
│    └──────────────────────────────────── TagID low = 0x2A
└───────────────────────────────────────── TagID high = 0x00
```

### Производные значения

```go
out := AES128_ECB(KEY, input_block)

Major = out[0]<<8 | out[1]          // не может быть 0
Minor = out[2]<<8 | out[3]          // не может быть 0
MAC   = [out[4]|0xC0, out[5], out[6], out[7], out[8], out[9]]
//        ↑ биты 46-47 = '11' → Random Static BLE address (требование BLE spec)
```

### Расчёт номера слота

**Прототип (тестовый режим):**
```go
slot = uptime / SlotDuration   // 10 секунд
```

**Production:**
```go
slot = unix_time / 300         // 300 секунд = 5 минут
```

> Использование `unix_time` (а не счётчика циклов) критично для правильной работы  
> ночного режима: при увеличенном интервале сна слот всё равно считается по времени.

### Цикл работы прошивки (прототип)

```
Старт → Enable BLE → LED ×3 → цикл:
  ┌──────────────────────────────────────────┐
  │  slot = uptime / 10s                     │
  │  if slot != last_slot:                   │
  │      AES(KEY, tagID || slot)             │
  │      → Major, Minor, MAC                 │
  │      Обновить BLE advertising payload    │
  │      LED ×2                              │
  │      last_slot = slot                    │
  │  sleep 100ms                             │
  └──────────────────────────────────────────┘
```

В production для `nRF52832` на [YJ-16013](https://device.report/shenzhen-holyiot-technology/nrf52832) вместо `sleep 100ms` используется  
`sd_power_system_off()` + пробуждение по RTC каждые 2 секунды.

### iBeacon-пакет в эфире

```
AD Type 0xFF (Manufacturer Specific):
  Company ID: 0x004C 0x00  (Apple Inc.)
  Type:       0x02         (iBeacon)
  Length:     0x15         (21 байт)
  UUID:       E2C56DB5-DFFB-48D2-B060-D0F5A71096E0  (16 байт, константа)
  Major:      0xXXXX       (2 байта, меняется каждый слот)
  Minor:      0xXXXX       (2 байта, меняется каждый слот)
  TX Power:   0xC5         (-59 дБм @ 1м)
```

**TagID нигде не передаётся.** Сканер видит только UUID + Major + Minor.  
Сервер, зная KEY, перебирает все TagID и слоты, находит совпадение с парой Major+Minor.

---

## 10. Критерии проверки

### ✅ Прошивка запустилась

| Признак | Ожидаемое поведение |
|---|---|
| LED после прошивки | 3 быстрых вспышки (~150ms суммарно) |
| COM-порт | Появляется в системе как USB CDC устройство |
| Serial-лог | Строки `[slot N]` появляются каждые 10 секунд |
| Диск NICENANO | Исчез после копирования прошивки |

### ✅ Алгоритм работает корректно

| Проверка | Метод | Ожидаемый результат |
|---|---|---|
| Major/Minor меняются | Смотреть лог 30 сек | 3+ разные строки с разными значениями |
| MAC меняется | Смотреть лог 30 сек | MAC-адрес отличается в каждой строке |
| Старший байт MAC ≥ 0xC0 | Смотреть первый байт MAC в логе | `0xC0..0xFF` (биты 46-47 = 11) |
| Детерминированность | Перезагрузить плату, сравнить Slot 2 | `Major=0x4B10 Minor=0x545F MAC=EB:F9:80:...` совпадают с предыдущим запуском |
| UUID константный | nRF Connect → UUID | `E2C56DB5-DFFB-48D2-B060-D0F5A71096E0` при каждом сканировании |

### ✅ BLE-пакет виден в эфире

Проверить в **nRF Connect** на смартфоне (подробнее в п. 11).

### ❌ Что не проверяет прототип

| Функция | Почему не применимо |
|---|---|
| Ток потребления | LTH7R зарядник (~20 µА) делает измерение бессмысленным |
| System OFF deep sleep | TinyGo не поддерживает `sd_power_system_off()`, используется `time.Sleep` |
| Ночной режим | Нет RTC с unix-time (только uptime) |
| APPROTECT | Намеренно отключён для перепрошивки |

---

## 11. Проверка через nRF Connect

### Шаги

1. Открыть nRF Connect → вкладка **Scanner**
2. Нажать **START SCAN**
3. Найти устройство с именем `nice!nano` или без имени, фильтр по Manufacturer: **Apple**

### Что смотреть в деталях пакета

Нажать на устройство → **Raw** или **Advertising Data**:

```
Complete List of 128-bit UUIDs
  UUID: E2C56DB5-DFFB-48D2-B060-D0F5A71096E0  ← должен совпадать

Manufacturer Specific Data
  Company: Apple Inc. (0x004C)
  Type: iBeacon (0x02)
  UUID: E2C56DB5-DFFB-48D2-B060-D0F5A71096E0
  Major: 0x4B10    ← меняется каждые 10 сек
  Minor: 0x545F    ← меняется каждые 10 сек
  TX Power: -59
```

### MAC-адрес в nRF Connect

В списке устройств отображается MAC-адрес (`EB:F9:80:25:0E:94`).  
При каждой смене слота MAC должен меняться — устройство на время пропадёт из списка  
и появится снова с новым адресом.

### Ожидаемые изменения во времени

| Время | Что меняется |
|---|---|
| каждые 10 сек | Major, Minor, MAC — новые значения |
| постоянно | UUID — не меняется никогда |
| постоянно | TagID — не виден в эфире |

---

## 12. Типичные проблемы

### Плата не определяется как COM-порт

- Попробуйте другой USB-C кабель (зарядные кабели без данных не работают)
- Попробуйте другой USB-порт на ПК (иногда хабы не работают)
- Windows: проверьте «Диспетчер устройств» на предмет «Неизвестное устройство»
- Переустановить драйвер: правая кнопка → «Обновить драйвер» → «Автоматический поиск»

### Не получается войти в режим загрузчика (диск не появляется)

- Попробуйте тайминг: 200ms → пауза 300ms → 200ms (медленнее чем кажется нужным)
- Убедитесь что замыкаете именно **RST** на **GND** (не другие пины)
- Используйте `tinygo flash -port COMx .` — автоматический 1200-baud touch надёжнее
- Попробуйте несколько раз подряд — иногда требуется 3–4 попытки

### `tinygo flash` — ошибка `Serial port busy`

```bash
# Найти и завершить процессы, удерживающие порт:

# Windows (PowerShell):
Get-Process | Where-Object { $_.Name -match 'tinygo|putty|arduino' } | Stop-Process -Force

# macOS:
lsof /dev/cu.usbmodem* | awk 'NR>1 {print $2}' | xargs kill -9
```

### Serial-лог пустой после подключения

- Первые строки (~шапка) теряются из-за задержки USB CDC — это нормально
- Строки слотов начнут появляться каждые 10 секунд
- Если ничего нет дольше 30 сек — перепроверьте COM-порт: он мог измениться

### Значения Major/Minor не совпадают с ожидаемыми при перезагрузке

В прототипе слот считается от **uptime** (не unix-time), поэтому после перезагрузки  
нумерация начнётся с 0. Слот 4 после перезагрузки — это `40 секунд uptime`, а не то же  
абсолютное время. Для проверки детерминированности сравнивайте одинаковые номера слотов  
в двух разных запусках.

### Прошивка мигает LED, но в nRF Connect ничего нет

- Убедитесь что Bluetooth на смартфоне включён
- nRF Connect: убедитесь что сканирование запущено (кнопка SCAN активна)
- Попробуйте фильтр по UUID: `E2C56DB5-DFFB-48D2-B060-D0F5A71096E0`
- Интервал рекламы — 100 мс, устройство должно появиться в течение 2–3 секунд
- Если плата в режиме загрузчика — BLE не работает, нужно завершить прошивку

### macOS: `cp firmware.uf2 /Volumes/NICENANO/` — ошибка Input/Output error

Это ложная ошибка — загрузчик намеренно «обрывает» соединение после получения файла.  
Убедитесь что диск исчез и плата перезагрузилась. Прошивка записана корректно.
