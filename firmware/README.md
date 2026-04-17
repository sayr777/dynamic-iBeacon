# Прошивка nRF52810 (E73-2G4M04S1A)

## Назначение

Прошивка реализует динамическую BLE-метку:

- пробуждение каждые `2 с` по `RTC` (`LFXO 32768 Гц`);
- счётчик циклов: каждые `150` циклов (`5 мин`) — смена параметров;
- вычисление `Major/Minor/MAC` через `AES-128 ECB`;
- обновление `advertising data` и `random MAC`;
- отправка одного `advertising event` (3 канала, ~1 мс);
- переход в `System OFF / deep sleep` (~1.5 µА).

## Целевая платформа

| Параметр | Значение |
|---|---|
| SoC | `nRF52810` (Nordic Semiconductor) |
| Модуль | `EBYTE E73-2G4M04S1A` |
| Альтернативный модуль | `YJ-16013` (`nRF52832`) — прошивка идентична, меняется только таргет |
| SDK | **Zephyr** (рекомендуется) или `nRF5 SDK 17.1.x` |
| BLE стек | `SoftDevice S112` / Zephyr BT Broadcaster-only |
| Программатор | `J-LINK` / `nRF52 DK` / `ST-LINK V2` / CMSIS-DAP через `SWD` |
| Прошивка | `west flash` (Zephyr) или `nrfjprog` / `make flash` (nRF5 SDK) |

`S112` выбран вместо `S132` потому что метка только передаёт (`Broadcaster`) — приёмник не нужен. `S112` занимает меньше Flash и RAM.

## Основа из ble-tag-e73

Прошивка строится на платформе [`ble-tag-e73`](../../ble-tag-e73/firmware):

- инициализация `nRF52810`, тактирование, `RTC`, `SoftDevice S112` — из `ble-tag-e73`;
- `advertising` механика — из `ble-tag-e73`;
- добавляется: `AES-128`, счётчик слотов, смена `Major/Minor/MAC` каждый слот.

## Структура исходного кода

```
firmware/
├── README.md
├── tag_config.example.h          — шаблон конфигурации (TAG_ID, KEY, unix_time)
└── src/
    ├── main.c                    — точка входа, инициализация SD, бесконечный цикл
    ├── tag_app.h / tag_app.c     — FSM: BOOT → UPDATE_PARAMS → ADVERTISE → SLEEP
    ├── tag_platform.h            — платформенные абстракции (RTC, BLE adv, sleep)
    ├── tag_platform_nrf52810.c   — реализация для nRF52810 + S112
    ├── tag_config.h              — конфигурация изделия (не в репо, из .example.h)
    ├── aes128.h / aes128.c       — компактный AES-128 ECB (только шифрование)
    └── beacon_id.h / beacon_id.c — вычисление major/minor/mac из tag_id + slot
```

## Отличие от ble-tag-e73

| | `ble-tag-e73` | **ble-tag-jdy23-dynamic** |
|---|---|---|
| `SoftDevice` | `S132` (Observer + Broadcaster) | `S112` (только Broadcaster) |
| Режим BLE | scan window 30 мс + advertising | advertising only |
| Параметры рекламы | фиксированные | AES-ротация каждые 5 мин |
| MAC | фиксированный | меняется каждые 5 мин |
| Цикл | 2 с (scan + optional TX) | 2 с (TX ~1 мс + deep sleep) |
| Средний ток | ~8–15 µА | ~5 µА |

## Минимальный набор тестов

- запуск от внешнего питания `3.0 В`;
- запуск от батареи через `MCP1700`;
- ток deep sleep (цель: `< 3 µА` без TX);
- средний ток в цикле `2 с` (цель: `< 10 µА`);
- `Major/Minor` меняются каждые `CYCLES_PER_SLOT` циклов;
- `MAC` меняется вместе с `Major/Minor`;
- сервер идентифицирует метку через `server/lookup.py`.

## Сборка и прошивка

### Вариант A: Zephyr SDK (рекомендуется)

Zephyr содержит готовый `iBeacon` sample и поддерживает все Nordic SoC через `west`.  
Все доступные samples: https://docs.zephyrproject.org/latest/samples/index.html

```bash
# 1. Установить west
pip install west

# 2. Инициализировать workspace
west init zephyrproject && cd zephyrproject && west update

# 3. Установить Zephyr SDK toolchain
# https://docs.zephyrproject.org/latest/develop/getting_started/

# 4. Сборка iBeacon sample как основа (доработать — добавить AES-ротацию)
west build -b nrf52810pca10040 samples/bluetooth/ibeacon

# 5. Прошивка через SWD (выбрать доступный runner)
west flash --runner nrfjprog   # J-Link + nrfjprog (рекомендуется)
west flash --runner jlink      # прямо через J-Link
west flash --runner openocd    # OpenOCD + CMSIS-DAP / ST-LINK

# 6. Проверить доступные runners
west flash -H
```

Минимальный `prj.conf` (Broadcaster-only, экономия Flash/RAM):
```kconfig
CONFIG_BT=y
CONFIG_BT_BROADCASTER=y
CONFIG_BT_OBSERVER=n
CONFIG_BT_PERIPHERAL=n
CONFIG_BT_CENTRAL=n
CONFIG_BT_MAX_CONN=0
```

System OFF sample (deep sleep с пробуждением по GPIO/RTC):
`samples/boards/nordic/system_off`

### Вариант B: nRF5 SDK + GCC (классический)

```bash
# Установить nRF5 SDK 17.1.x в ../nrf5_sdk/
# Установить ARM GCC toolchain

cd firmware/pca10040e/s112/armgcc
make
make flash_softdevice   # прошить S112 один раз
make flash              # прошить приложение
```

## Важно: Read-out Protection

Перед финальной сборкой изделия включить `APPROTECT`:

```c
// В tag_config.h установить:
#define TAG_ENABLE_APPROTECT  1
// Прошивка активирует защиту при первом старте.
// После этого KEY нельзя прочитать через SWD.
```
