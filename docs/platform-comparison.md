# Сравнение платформ

## JDY-23 + CW32L010F8P6 vs nRF52810 vs nRF52832 (YJ-16013)

| Критерий | JDY-23 + CW32L010F8P6 | nRF52810 (E73-2G4M04S1A) | nRF52832 (YJ-16013) |
|---|---|---|---|
| **Цена модуля** | ~$1.70 (2 чипа) | ~$3.12 | ~$3.50–4.50 |
| **Количество чипов** | 2 (MCU + BLE-модуль) | 1 | 1 |
| **CPU** | CortexM0+ 32 МГц | CortexM4 64 МГц | CortexM4**F** 64 МГц (FPU) |
| **Flash / RAM** | 64KB / 8KB + 256KB / 32KB | 192KB / 24KB | 512KB / 64KB |
| **Средний ток** | ~22 µА | ~5 µА | ~5 µА (идентично) |
| **Ресурс батареи (расчётный)** | ~10 лет | ~30 лет | ~30 лет |
| **Ресурс батареи (практический)** | ~12 лет | ~15–20 лет | ~15–20 лет |
| **Запас по цели 3 года** | ×4 | ×10 | ×10 |
| **Смена Major/Minor** | ✅ AT+MAJOR/AT+MINOR | ✅ напрямую в payload | ✅ напрямую в payload |
| **Смена MAC** | ❓ зависит от ревизии JDY-23 | ✅ гарантировано | ✅ гарантировано |
| **SDK** | ARM GCC | nRF5 SDK или **Zephyr** | nRF5 SDK или **Zephyr** |
| **Zephyr iBeacon sample** | ❌ | ✅ `samples/bluetooth/ibeacon` | ✅ `samples/bluetooth/ibeacon` |
| **SWD прошивка (west flash)** | ST-LINK | J-Link / nrfjprog / OpenOCD | J-Link / nrfjprog / OpenOCD |
| **Этапов прошивки на производстве** | 2 | 1 | 1 |
| **APPROTECT (защита KEY)** | нет | ✅ UICR | ✅ UICR (тот же регистр) |
| **Сертификация BLE** | JDY-23: FCC/CE | E73: FCC/CE | YJ-16013: FCC/CE |
| **Температурный диапазон** | −20…+75 °C | −40…+85 °C | −40…+85 °C |
| **Для нашей задачи Flash/RAM** | достаточно | достаточно | **избыточно** (×2.7 Flash) |
| **Рекомендация** | пилот/макет | ✅ **промышленный образец** | альтернатива если E73 недоступен |

## nRF52832 (YJ-16013) — детальный анализ

### Что это такое

`YJ-16013` — BLE-модуль на базе `nRF52832` (Nordic Semiconductor).  
Доступен на AliExpress (~$3.50–4.50/шт) и JLCPCB SMT-сборка (вариант YJ-16002).

### nRF52832 vs nRF52810 для нашей задачи

| Аспект | nRF52810 | nRF52832 |
|---|---|---|
| Потребление в deep sleep (System OFF + LFXO) | ~1.5 µА | ~1.5 µА |
| TX ток при 0 dBm | 5.3 мА | 5.3 мА |
| Итоговый средний ток | ~5.2 µА | ~5.2 µА |
| Flash для нашей прошивки (~50 KB) | 192 KB — достаточно | 512 KB — 10× избыток |
| RAM для нашей прошивки (~6 KB) | 24 KB — достаточно | 64 KB — 10× избыток |
| FPU | нет (нам не нужен) | есть (нам не нужен) |
| NFC интерфейс | нет | есть (возможна NFC-провизия) |
| Прошивка (изменения) | текущая | только таргет в Makefile + линкер-скрипт |

**Вывод**: потребление идентично. `nRF52810` оптимальнее по стоимости и размеру.  
`nRF52832` (YJ-16013) — полноценная альтернатива если `E73-2G4M04S1A` недоступен;  
прошивка меняется только в настройках компилятора.

### Что нужно установить для сборки (оба чипа)

#### Вариант A: nRF5 SDK (классический)

```bash
# 1. ARM GCC toolchain
#    https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads
#    (Windows: arm-gnu-toolchain-13.x-mingw-arm-none-eabi.exe)

# 2. nRF5 SDK 17.1.0
#    https://www.nordicsemi.com/Software-and-tools/Software/nRF5-SDK

# 3. nrfjprog (Nordic command-line tools)
#    https://www.nordicsemi.com/Software-and-tools/Development-Tools/nRF-Command-Line-Tools

# 4. Программатор: J-LINK / ST-LINK V2 / nRF52 DK через SWD
```

#### Вариант B: Zephyr SDK (современный, рекомендуется)

```bash
# 1. Установить west (менеджер проектов Zephyr)
pip install west

# 2. Инициализировать Zephyr workspace
west init zephyrproject
cd zephyrproject
west update

# 3. Установить Zephyr SDK (toolchain + OpenOCD + J-Link runner)
#    https://docs.zephyrproject.org/latest/develop/getting_started/

# 4. Сборка iBeacon sample
west build -b nrf52840dk_nrf52840 samples/bluetooth/ibeacon
# или для кастомной платы:
west build -b custom_nrf52810 samples/bluetooth/ibeacon

# 5. Прошивка через SWD
west flash --runner nrfjprog    # через nrfjprog + J-Link
west flash --runner jlink       # прямо через J-Link
west flash --runner openocd     # через OpenOCD (CMSIS-DAP, ST-LINK)
west flash --runner pyocd       # через pyOCD
```

Доступные Zephyr samples для BLE: https://docs.zephyrproject.org/latest/samples/index.html  
Готовый iBeacon sample: `samples/bluetooth/ibeacon`  
System OFF sample: `samples/boards/nordic/system_off`

#### Минимальный `prj.conf` для Broadcaster-only (экономия Flash/RAM)

```kconfig
CONFIG_BT=y
CONFIG_BT_BROADCASTER=y
CONFIG_BT_OBSERVER=n       # отключить сканирование — экономия ~20 KB Flash
CONFIG_BT_PERIPHERAL=n     # отключить GATT peripheral
CONFIG_BT_CENTRAL=n        # отключить central/initiator
CONFIG_BT_MAX_CONN=0       # нет соединений
```

## Расчёт потребления nRF52810

```
Событие рекламы (3 канала × 330 мкс × 5.3 мА):  5.3 мА × 1 мс = 5.3 µАс
Событий в час (2 с интервал):                    1800
Ток от TX:                    5.3 µАс × 1800 / 3600 с = 2.65 µА
Deep sleep с RTC:                                1.5 µА
AES + обновление params (раз в 5 мин):           2 мА × 5 мс / 300 с ≈ 0.03 µА
─────────────────────────────────────────────────────
Итого:                                          ~4.2 µА
```

## Расчёт потребления JDY-23 + CW32L010

```
JDY-23 непрерывная реклама 2 с:     ~17 µА
CW32L010 Stop mode с RTC:           0.5 µА × 299.4/300 = 0.5 µА
CW32L010 активный (раз в 5 мин):    2 мА × 0.6 с / 300 с = 4.0 µА
Утечки схемы:                       0.4 µА
─────────────────────────────────────────────────────
Итого:                              ~22 µА
```

## Итоговый выбор

| | JDY-23 + CW32L010 | nRF52810 (E73) | nRF52832 (YJ-16013) |
|---|:---:|:---:|:---:|
| Прототип / макет | ✅ | ✅ | ✅ |
| **Промышленный образец** | — | ✅ **основной выбор** | ✅ резерв |

### Обоснование выбора nRF52810 для промышленного образца

1. **Ток в 5 раз меньше** (5 µА vs 22 µА) — реальный запас на деградацию батареи и температуру.
2. **Один чип** — меньше точек отказа, проще производство, один этап прошивки.
3. **Гарантированная смена MAC** — полный контроль BLE-пакета без зависимости от AT-команд.
4. **Стабильность партий** — Nordic SoC внутри E73 не меняется от партии к партии.
5. **Промышленный диапазон** — −40…+85 °C без ограничений JDY-23.
6. **Zephyr + nRF5 SDK** — два полноценных SDK, iBeacon sample готов из коробки.
7. **Разница в цене** — vs CW32+JDY23: $1.42 окупается упрощением производства; vs nRF52832: $0.50–1.50 экономии при нашем объёме Flash/RAM.
