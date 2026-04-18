# Прошивка прототипа (ProMicro NRF52840)

## Целевая платформа

| Параметр | Значение |
|---|---|
| SoC | `nRF52840` |
| Плата | `ProMicro NRF52840 v1940` (клон nice!nano v2.0) |
| TinyGo board | `nicenano` |
| Zephyr board | `promicro_nrf52840` |
| Прошивка | USB UF2 (без программатора) или SWD (J-LINK) |

## Структура исходного кода

```
prototype/firmware/
├── README.md                          — этот файл
└── tinygo/
    ├── go.mod                         — Go module (tinygo.org/x/bluetooth)
    ├── main.go                        — полное приложение (AES-128 v2 + iBeacon + LED)
    ├── privacy.go                     — BLE Privacy через CGo (sd_ble_gap_privacy_set)
    └── softdevice_include/            — заголовки SoftDevice s140v7 для CGo
        ├── ble_gap.h
        ├── ble.h
        ├── nrf_svc.h
        └── ...
```

---

## Способ A: TinyGo ✅ (рекомендуется — быстрый старт)

Не нужен nRF5 SDK, не нужен Zephyr. Только TinyGo + Go.

### Установка TinyGo (один раз)

```bash
# Windows: скачать installer с https://tinygo.org/getting-started/install/windows/
# или через scoop:
scoop install tinygo

# Проверить:
tinygo version
# → tinygo version 0.34.0 ...
```

### Сборка

```bash
cd prototype/firmware/tinygo

# Загрузить зависимости
go mod tidy

# Собрать UF2 для nice!nano (ProMicro NRF52840 v1940)
tinygo build -o firmware.uf2 -target=nicenano .
```

### Прошивка через USB UF2

```
1. Подключить плату к USB (COM8 в Диспетчере устройств)
2. Дважды быстро нажать RESET — плата войдёт в режим загрузчика
   (в Проводнике появится диск NICENANO или NRF52BOOT)
3. Скопировать firmware.uf2 на этот диск
4. Диск исчезнет — плата перезагрузится и запустит прошивку
```

### Мониторинг через Serial

```bash
tinygo monitor -port COM8
# или любой terminal: 115200 baud, COM8
```

### LED индикация

| Событие | Мигания |
|---|---|
| Старт (BLE готов) | 3 раза |
| Каждые 2 секунды | 1 раз (heartbeat) |

### Ожидаемый вывод (алгоритм v2, подтверждено 18 апреля 2026)

```
[privacy] OK — Radio MAC меняется каждый слот
========================================
BLE Tag v2  TagID=42     SlotDuration=10s
UUID + Major + Minor + MAC + RadioMAC — все динамические
========================================
[slot    0] TagID=42  Major=0xD30B  Minor=0x576E  MAC=D0:27:FA:BD:AC:F3
           UUID=FF352EFE-AF47-1F28-CA03-C13FC3235B8F
[slot    1] TagID=42  Major=0xE4B9  Minor=0xE7CA  MAC=E9:B6:FB:6E:2F:50
           UUID=DEEAEB01-216B-BAE2-51D1-335F754CCB9F
[slot    2] TagID=42  Major=0xC2CB  Minor=0x2A0D  MAC=C6:7E:54:D9:C7:96
           UUID=4B10545F-EBF9-8025-0E94-A221791C0CBF
[slot    3] TagID=42  Major=0x7E33  Minor=0x588D  MAC=E3:81:D9:1C:C4:AB
           UUID=256A7E30-81CC-71D1-7F82-953428525AF2
```

Если `[privacy]` показывает ошибку — RadioMAC фиксирован, остальные параметры всё равно динамические.

### Параметры по умолчанию (для отладки)

| Параметр | Значение | Production |
|---|---|---|
| `SlotDuration` | 10 секунд | 5 минут |
| `AdvertisingInterval` | 100 мс | 100 мс |
| `TagID` | 42 | уникальный |

Поменять `SlotDuration` в `main.go`:
```go
SlotDuration: 5 * time.Minute,  // production
```

### Проверка в nRF Connect

1. Открыть nRF Connect на смартфоне
2. UUID меняется каждые 10 секунд — устройство каждый раз появляется с новым UUID
3. Major, Minor и MAC — тоже меняются каждый слот
4. Manufacturer: Apple (0x004C) — стандартный iBeacon
5. RadioMAC (адрес устройства в сканере) — тоже меняется благодаря BLE Privacy

---

## Исходный код

Общий код приложения (`tag_app.c`, `beacon_id.c`, `aes128.c`) берётся из родительского проекта:
```
../firmware/src/tag_app.c
../firmware/src/tag_app.h
../firmware/src/tag_platform.h
../firmware/src/beacon_id.c/.h
../firmware/src/aes128.c/.h
../firmware/tag_config.example.h  → скопировать как src/tag_config.h
```

---

## Способ A: Zephyr SDK + прошивка через USB (рекомендуется для прототипа)

Не требует программатора. Работает под Windows / Linux / macOS.

### Установка (один раз)

```bash
pip install west
west init -m https://github.com/zephyrproject-rtos/zephyr zephyrproject
cd zephyrproject && west update
pip install -r zephyr/scripts/requirements.txt

# Установить Zephyr SDK (toolchain):
# https://docs.zephyrproject.org/latest/develop/getting_started/
```

### Сборка

```bash
# Базовый iBeacon sample — отправная точка для нашей прошивки
west build -b promicro_nrf52840 samples/bluetooth/ibeacon

# Все доступные Zephyr samples:
# https://docs.zephyrproject.org/latest/samples/index.html
```

Минимальный `prj.conf` для Broadcaster-only:
```kconfig
CONFIG_BT=y
CONFIG_BT_BROADCASTER=y
CONFIG_BT_OBSERVER=n
CONFIG_BT_PERIPHERAL=n
CONFIG_BT_CENTRAL=n
CONFIG_BT_MAX_CONN=0
CONFIG_BT_DEVICE_NAME="BLE-TAG-PROTO"
```

### Прошивка через USB UF2

```bash
# 1. Войти в режим загрузчика:
#    Замкнуть RST на GND ДВАЖДЫ БЫСТРО (двойной клик)
#    Плата появится как диск NRF52BOOT

# 2. Скопировать прошивку (Linux/macOS):
cp build/zephyr/zephyr.uf2 /media/$USER/NRF52BOOT/

# Windows: скопировать zephyr.uf2 через Проводник на диск NRF52BOOT

# 3. Через west:
west flash --runner adafruit-nrfutil
```

### Прошивка через SWD (J-LINK)

```bash
west flash --runner jlink
west flash --runner nrfjprog
west flash --runner openocd
```

---

## Способ B: nRF5 SDK + прошивка через SWD

Ближе к производственной прошивке, использует тот же API.

```bash
# 1. Скачать nRF5 SDK 17.1.0 + S140 SoftDevice
# 2. В Makefile: TARGETS = nrf52840_xxaa, BOARD = PCA10056
# 3. Прошить S140:
nrfjprog --program s140_nrf52_7.3.0_softdevice.hex --chiperase --reset

# 4. Прошить приложение:
make flash
```

---

## Отладка через USB Serial (только Zephyr)

Прототип поддерживает вывод `printk()` / `LOG_INF()` через USB CDC:

```bash
# Подключить USB-C, открыть serial порт:
# Linux:   /dev/ttyACM0
# Windows: COM-порт в Диспетчере устройств
# macOS:   /dev/cu.usbmodem...

# Настроить в prj.conf:
CONFIG_USB_CDC_ACM=y
CONFIG_LOG=y
CONFIG_LOG_BACKEND_USB_CDC=y
```

Пример вывода:
```
[00:00:00.100] BOOT: unix_time=1735000000 slot=5783333
[00:00:00.150] UPDATE_PARAMS: major=0x3A7F minor=0xC1B2 mac=E5:C3:7F:A2
[00:05:00.150] UPDATE_PARAMS: major=0x92B1 minor=0xD4F3 mac=E5:C3:91:B2
```

---

## Важно: APPROTECT

В прототипе **НЕ включать** `TAG_ENABLE_APPROTECT=1` — иначе нельзя будет перепрошить.  
В производственной версии (`YJ-16013`) APPROTECT включается перед финальной прошивкой.

---

## Проверка результата

После прошивки открыть [nRF Connect](https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-mobile) на смартфоне:

1. Найти устройство с UUID из `TAG_IBEACON_UUID`
2. Проверить что `Major` и `Minor` меняются каждые 5 мин
3. Проверить что `MAC`-адрес меняется вместе с ними
4. LED на `P0.09` мигает при каждом обновлении параметров (раз в 5 мин)

Проверка через сервер:

```bash
cd server/
python lookup.py --simulate --tag-id 1
# Вывод: tag_id=1, slot=XXXXXX — метка идентифицирована
```
