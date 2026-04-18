# Компоненты: даташиты и закупка

Платформа: **YJ-16013 (nRF52832)** + **ER14505H-LD**.  
Все ссылки проверены. Альтернативные поставщики указаны где возможно.

---

## BLE-модуль

### YJ-16013 (nRF52832, основной)

| Параметр | Значение |
|---|---|
| SoC | Nordic nRF52832 (ARM Cortex-M4F, BLE 5.0) |
| Flash / RAM | 512 KB / 64 KB |
| Антенна | Встроенная PCB-trace |
| Питание | 1.7–3.6 В |
| Размер | 16 × 13 мм |

**Покупка:**
- AliExpress: поиск [`YJ-16013 nRF52832`](https://www.aliexpress.com/w/wholesale-YJ-16013-nRF52832.html) (~$3–4/шт)
- AliExpress: поиск [`nRF52832 BLE module PCB antenna`](https://www.aliexpress.com/w/wholesale-nrf52832-ble-module.html)

**Документация:**
- [nRF52832 Product Page — Nordic Semiconductor](https://www.nordicsemi.com/Products/nRF52832)
- [nRF52832 Datasheet (PDF)](https://infocenter.nordicsemi.com/pdf/nRF52832_PS_v1.8.pdf)
- [nRF5 SDK 17.1.0](https://www.nordicsemi.com/Products/Development-software/nRF5-SDK/Download)
- [nRF5 SDK документация](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.1.0/index.html)
- [SoftDevice S112 (Broadcaster-only)](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.1.0/group__nrf__sdm.html)

### E73-2G4M04S1A (nRF52810, альтернатива для серийного производства)

| Параметр | Значение |
|---|---|
| SoC | Nordic nRF52810 (ARM Cortex-M4, BLE 5.0) |
| Flash / RAM | 192 KB / 24 KB |
| Пин RESET | ❌ отсутствует |

**Покупка:**
- LCSC: [E73-2G4M04S1A — C2687940](https://www.lcsc.com/product-detail/RF-Modules_Ebyte-E73-2G4M04S1A_C2687940.html) (~$3.12/шт)

---

## Стабилизатор напряжения

### MCP1700T-3002E/TT (LDO 3.0 В)

| Параметр | Значение |
|---|---|
| Вых. напряжение | 3.0 В (суффикс `3002`) |
| Ток покоя Iq | **1 µА** (типовой) |
| Макс. вых. ток | 250 мА |
| Входное напряжение | 2.3–6.0 В |
| Корпус | SOT-23-3 |
| Dropout | 178 мВ @ 100 мА |

> ⚠️ Брать только `3002` (3.0 В), не `3302` (3.3 В) — nRF52832 max 3.6 В, батарея даёт 3.6 В в начале жизни.

**Покупка:**
- LCSC: [MCP1700T-3002E/TT — C79786](https://www.lcsc.com/product-detail/Linear-Voltage-Regulators-LDO_Microchip-Tech-MCP1700T-3002E-TT_C79786.html) (~$0.25/шт)
- Digikey: [MCP1700T-3002E/TT](https://www.digikey.com/en/products/detail/microchip-technology/MCP1700T-3002E-TT/652685)
- Mouser: [MCP1700T-3002E/TT](https://www.mouser.com/ProductDetail/Microchip-Technology/MCP1700T-3002E-TT)

**Документация:**
- [MCP1700 Datasheet (Microchip)](https://ww1.microchip.com/downloads/en/DeviceDoc/MCP1700-Low-Quiescent-Current-LDO-20001826E.pdf)

---

## Диод Шотки (защита от переполюсовки)

### BAT54 SOD-323 (основной)

| Параметр | Значение |
|---|---|
| Vf @ 1 mA | ~0.24–0.32 В |
| Vrrm | 30 В |
| If max | 200 мА |
| Корпус | SOD-323 (SC-76) |
| Ток утечки | ~0.1 µА @ 25°C |

**Покупка:**
- LCSC: [BAT54 SOD-323 — C2480](https://www.lcsc.com/product-detail/Schottky-Diodes_onsemi-BAT54WT1G_C2480.html) (~$0.01/шт)
- LCSC (Vishay): [BAT54WS — C8038](https://www.lcsc.com/product-detail/Schottky-Diodes_Vishay-Intertech-BAT54WS_C8038.html)

**Аналоги (взаимозаменяемы):**
- `BAT60A` — Vf ≤ 0.25 В, чуть меньше падение
- `RB520S-30` — аналог Rohm, SOD-323
- `1N5819` (SOD-123) — если корпус SOD-323 недоступен

**Документация:**
- [BAT54 Datasheet (onsemi)](https://www.onsemi.com/pdf/datasheet/bat54t1-d.pdf)

---

## Буферный конденсатор CBUF (220 µF)

| Параметр | Требование |
|---|---|
| Ёмкость | 220 µF |
| Напряжение | 6.3 В или 10 В |
| Тип | **low-leakage** электролит |
| Ток утечки | **< 0.5 µА** (критично!) |
| Корпус | D5×11 мм (радиальный) |
| Серия | Nichicon **UCC** или Panasonic **FR/FM** |

> ⚠️ Общего назначения (серии CD, GP и т.п.) не подходят — утечка 2–5 µА убьёт весь токовый бюджет.

**Покупка:**
- Mouser: [Nichicon UCC1H221MCL1GS](https://www.mouser.com/ProductDetail/Nichicon/UCC1H221MCL1GS) (~$0.12/шт)
- Digikey: поиск [`Nichicon UCC 220uF 6.3V`](https://www.digikey.com/en/products/filter/aluminum-electrolytic-capacitors/58?s=N4IgjCBcoGwJxVAYygMwIYBsDOBTANCAPZQDaIALGGAMxgC6AvkA)
- LCSC: поиск [`Nichicon UCC 220uF`](https://www.lcsc.com/search?q=nichicon+UCC+220uf)

---

## Керамические конденсаторы

### 1 µF X7R 0402 (C_IN, C_OUT для MCP1700)

**Покупка:**
- LCSC: [Samsung CL05B105KQ5NNNC — C15849](https://www.lcsc.com/product-detail/Multilayer-Ceramic-Capacitors-MLCC-SMD-SMT_Samsung-Electro-Mechanics-CL05B105KQ5NNNC_C15849.html)

### 100 нФ X7R 0402 (байпасные)

**Покупка:**
- LCSC: [Samsung CL05B104KO5NNNC — C1525](https://www.lcsc.com/product-detail/Multilayer-Ceramic-Capacitors-MLCC-SMD-SMT_Samsung-Electro-Mechanics-CL05B104KO5NNNC_C1525.html)

---

## Батарея

### FANSO ER14505H-LD (AA Li-SOCl₂, основная)

| Параметр | Значение |
|---|---|
| Химия | Li-SOCl₂ (литий-тионилхлорид) |
| Напряжение | 3.6 В |
| Ёмкость | 2700 мАч |
| Форм-фактор | AA (14.5 × 50.5 мм) |
| Исполнение | **LD** — с выводами под пайку |
| Саморазряд | < 2%/год |
| Темп. диапазон | −60 до +85°C |
| Ресурс при 5 µА | **~20 лет** |

> ⚠️ Только исполнение `-LD` (with **L**ead **D**uration — выводы). Версия без суффикса — под держатель, не подходит.

**Покупка:**
- Официальный сайт FANSO: [www.fanso.com](http://www.fanso.com/products/er14505.html)
- AliExpress: поиск [`FANSO ER14505H`](https://www.aliexpress.com/w/wholesale-fanso-er14505h.html)
- AliExpress: поиск [`ER14505 3.6V AA lithium`](https://www.aliexpress.com/w/wholesale-er14505-3.6v.html)

**Аналоги (взаимозаменяемы по корпусу и параметрам):**
- `EVE ER14505H` — аналог EVE Energy, широко доступен
- `Tadiran TL-5903` — Tadiran, дороже, но премиальное качество
- `SAFT LS14500` — SAFT, военный сегмент

**Документация:**
- [FANSO ER14505H Datasheet](http://www.fanso.com/uploadfile/2020/0605/20200605111752137.pdf)

---

## Корпус

### AK-W-70-4 (IP67, 70×40×20 мм)

| Параметр | Значение |
|---|---|
| Размер (Д×Ш×В) | 70 × 40 × 20 мм |
| Материал | ABS пластик |
| Степень защиты | IP67 |
| Цвет | чёрный |
| Крепление | 4 винта M2.5 |

**Покупка:**
- AliExpress: поиск [`AK-W-70-4 IP67 enclosure`](https://www.aliexpress.com/w/wholesale-AK-W-70-4.html)
- AliExpress: поиск [`IP67 plastic enclosure 70x40x20`](https://www.aliexpress.com/w/wholesale-ip67-plastic-enclosure-70x40.html)

---

## Прототип

### ProMicro NRF52840 v1940 (клон nice!nano v2.0)

| Параметр | Значение |
|---|---|
| SoC | nRF52840 (1 MB Flash, 256 KB RAM) |
| Форм-фактор | Pro Micro 18×33 мм |
| Загрузчик | Adafruit UF2 (drag-and-drop USB) |
| Зарядник | LTH7R (JST-PH 2-pin LiPo) |
| TinyGo board | `nicenano` |

**Покупка:**
- AliExpress: поиск [`SuperMini nRF52840`](https://www.aliexpress.com/w/wholesale-supermini-nrf52840.html)
- AliExpress: поиск [`Pro Micro NRF52840`](https://www.aliexpress.com/w/wholesale-pro-micro-nrf52840.html)

**Документация:**
- [nice!nano v2.0 (оригинал)](https://nicekeyboards.com/docs/nice-nano/)
- [TinyGo nicenano board](https://tinygo.org/docs/reference/microcontrollers/nicenano/)
- [Руководство по прошивке прототипа](../prototype/docs/setup.md)

---

## Инструменты разработки

| Инструмент | Назначение | Ссылка |
|---|---|---|
| nRF Command Line Tools | nrfjprog, mergehex | [Nordic](https://www.nordicsemi.com/Products/Development-tools/nRF-Command-Line-Tools) |
| nRF Connect Desktop | Flash programmer, BLE sniffer | [Nordic](https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-Desktop) |
| nRF Connect Mobile | BLE scanner для проверки | [Android](https://play.google.com/store/apps/details?id=no.nordicsemi.android.mcp) / [iOS](https://apps.apple.com/app/nrf-connect-for-mobile/id1054362403) |
| J-LINK (SEGGER) | SWD программатор | [segger.com](https://www.segger.com/products/debug-probes/j-link/) |
| nRF52840 DK | Отладочная плата Nordic | [Nordic](https://www.nordicsemi.com/Products/Development-hardware/nRF52840-DK) |
| TinyGo | Компилятор для прототипа | [tinygo.org](https://tinygo.org/getting-started/install/) |

---

## Стандарты и алгоритмы

| Стандарт | Описание | Ссылка |
|---|---|---|
| NIST FIPS 197 | AES-128 (Advanced Encryption Standard) | [NIST](https://csrc.nist.gov/publications/detail/fips/197/final) |
| NIST SP 800-38A | ECB mode of operation | [NIST](https://csrc.nist.gov/publications/detail/sp/800-38a/final) |
| iBeacon Specification | Apple iBeacon формат | [Apple](https://developer.apple.com/ibeacon/) |
| BLE Core Spec 5.0 | Bluetooth Low Energy | [Bluetooth SIG](https://www.bluetooth.com/specifications/specs/core-specification-5-0/) |
| Bluetooth Assigned Numbers | Company ID 0x004C = Apple | [Bluetooth SIG](https://www.bluetooth.com/specifications/assigned-numbers/) |

Спецификация алгоритма применительно к проекту: [`docs/algorithm.md`](../docs/algorithm.md)
