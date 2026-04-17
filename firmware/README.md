# Прошивка nRF52832 (YJ-16013)

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
| SoC | `nRF52832` (Nordic Semiconductor) |
| Модуль | `EBYTE YJ-16013` |
| Альтернативный модуль | `E73-2G4M04S1A` (`nRF52810`) — для серийного производства 1000+ шт |
| SDK | `nRF5 SDK 17.1.x` (рекомендуется) или `nRF Connect SDK` (Zephyr) |
| BLE стек | `SoftDevice S112` (только Broadcaster) |
| Программатор | `J-LINK` / `nRF52 DK` / `ST-LINK V2` / CMSIS-DAP через `SWD` |

`S112` выбран вместо `S132` потому что метка только передаёт (`Broadcaster`) — приёмник не нужен. `S112` занимает меньше Flash и RAM.

## Выбор SDK

| | nRF5 SDK 17.1.x | nRF Connect SDK (Zephyr) |
|---|---|---|
| Основа | простая очередь событий | Zephyr RTOS (ОСРВ) |
| Установка | скачать архив (~500 МБ) + GCC | `west init` + 2–3 ГБ зависимостей |
| System OFF deep sleep | ✅ нативная, отлаженная | ⚠️ через `PM_STATE_SOFT_OFF`, менее стабильна |
| iBeacon sample | ✅ есть | ✅ `samples/bluetooth/ibeacon` |
| RAM overhead | ~8 KB (SoftDevice) | +30–50 KB (RTOS) |
| Для нашей задачи | ✅ **оптимально** | приемлемо, но избыточно |
| Когда оправдан | BLE Broadcaster / простые устройства | nRF91 (LTE/NB-IoT), nRF5340, BLE Mesh |

**Рекомендация**: nRF5 SDK для данного проекта. Наша задача — BLE Broadcaster + deep sleep,
это именно тот класс задач, для которого nRF5 SDK создавался. Накладные расходы Zephyr RTOS
здесь не нужны и усложняют настройку окружения.

Zephyr оправдан при переходе на nRF91 (LTE), nRF5340 (dual-core),
или если нужна переносимость на не-Nordic платформы.

Все доступные Zephyr samples: https://docs.zephyrproject.org/latest/samples/index.html

## Основа из ble-tag-e73

Прошивка строится на платформе [`ble-tag-e73`](../../ble-tag-e73/firmware):

- инициализация `nRF52832`, тактирование, `RTC`, `SoftDevice S112` — из `ble-tag-e73`;
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
    ├── tag_platform_nrf52832.c   — реализация для nRF52832 + S112
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

### nRF5 SDK + GCC (рекомендуется)

```bash
# 1. Скачать nRF5 SDK 17.1.0:
#    https://www.nordicsemi.com/Software-and-tools/Software/nRF5-SDK

# 2. Установить ARM GCC toolchain:
#    https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads

# 3. Установить nRF Command Line Tools (nrfjprog):
#    https://www.nordicsemi.com/Software-and-tools/Development-Tools/nRF-Command-Line-Tools

# 4. Сборка и прошивка
cd firmware/pca10040e/s112/armgcc
make
make flash_softdevice   # прошить SoftDevice S112 один раз
make flash              # прошить приложение
```

### nRF Connect SDK + west (альтернатива)

```bash
# Все доступные samples: https://docs.zephyrproject.org/latest/samples/index.html

pip install west
west init zephyrproject && cd zephyrproject && west update

# Сборка iBeacon sample (основа для доработки)
west build -b nrf52810pca10040 samples/bluetooth/ibeacon

# Прошивка через SWD
west flash --runner nrfjprog    # J-Link + nrfjprog
west flash --runner openocd     # OpenOCD + CMSIS-DAP / ST-LINK
```

Минимальный `prj.conf` для Broadcaster-only (экономия Flash/RAM):
```kconfig
CONFIG_BT=y
CONFIG_BT_BROADCASTER=y
CONFIG_BT_OBSERVER=n
CONFIG_BT_PERIPHERAL=n
CONFIG_BT_CENTRAL=n
CONFIG_BT_MAX_CONN=0
```

## Важно: Read-out Protection

Перед финальной сборкой изделия включить `APPROTECT`:

```c
// В tag_config.h установить:
#define TAG_ENABLE_APPROTECT  1
// Прошивка активирует защиту при первом старте.
// После этого KEY нельзя прочитать через SWD.
```
