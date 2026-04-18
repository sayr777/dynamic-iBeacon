# Динамическая BLE-метка на nRF52832 (YJ-16013)

Автономная динамическая BLE-метка, которая меняет `Major`, `Minor` и `MAC`-адрес каждые `5 мин`. При знании секретного ключа сервер **однозначно восстанавливает статичный идентификатор метки** по паре `(Major, Minor)` без хранения истории.

## Выбранная платформа: nRF52832 (YJ-16013)

| Параметр | Значение |
|---|---|
| Чип | `nRF52832` (Nordic Semiconductor, ARM Cortex-M4F) |
| Модуль | `YJ-16013` (512 KB Flash / 64 KB RAM) |
| SDK | `nRF5 SDK 17.1.x`, SoftDevice `S112` |
| Средний ток | **~5.2 µА** |
| Ресурс батареи `ER14505H` | **~15–20 лет** (ограничен саморазрядом) |
| Запас по цели 3 года | **×5–6** |
| Смена MAC | ✅ гарантированно каждый слот |
| Этапов прошивки | 1 (SWD через J-LINK / nRF52 DK) |
| Полная стоимость изделия | **~$6.95** (батарея + корпус + все компоненты) |

Сравнение с альтернативами: [`docs/platform-comparison.md`](docs/platform-comparison.md)

## Протокол работы

```
Каждые 2 секунды:
  1. nRF52832 просыпается из System OFF по RTC
  2. Передаёт один стандартный iBeacon-пакет (3 канала, ~1 мс)
  3. Засыпает обратно в System OFF (~1.5 µА)

Каждые 5 минут (каждые 150 циклов):
  4. Вычисляет новые Major, Minor, MAC через AES-128
  5. Обновляет параметры рекламы перед следующей передачей
```

Параметры iBeacon (UUID, Major, Minor) и MAC-адрес меняются синхронно каждые 5 мин.  
Статичный `TAG_ID` метки недоступен из эфира — только через серверную идентификацию.

## Алгоритм идентификации

```
slot  = unix_time / 300             # номер 5-минутного слота
block = tag_id[2] || slot[4] || 0x00[10]   # 16 байт
out   = AES-128-ECB(KEY, block)
major = out[0:2]   minor = out[2:4]   mac[3:6] = out[4:7]
```

Сервер перебирает все `tag_id × [slot-1, slot, slot+1]` = 30 000 AES-операций < 1 мс.

Полная спецификация: [`docs/algorithm.md`](docs/algorithm.md)

## Структура проекта

- [`docs/protocol.md`](docs/protocol.md) — **протокол работы**: FSM, sequence diagrams, iBeacon формат, ночной режим
- [`docs/cost.md`](docs/cost.md) — **полная стоимость** изделия: каждый компонент, схема питания, $6.95/шт
- [`docs/platform-comparison.md`](docs/platform-comparison.md) — сравнение nRF52832 vs nRF52810 vs JDY-23+CW32L010
- [`docs/architecture.md`](docs/architecture.md) — архитектура изделия и режим работы
- [`docs/algorithm.md`](docs/algorithm.md) — спецификация алгоритма смены параметров
- [`docs/interaction-diagram.md`](docs/interaction-diagram.md) — диаграммы состояний и взаимодействия (Mermaid)
- [`docs/bom.md`](docs/bom.md) — полный BOM с пассивными компонентами, оба варианта питания
- [`docs/battery-life-estimate.md`](docs/battery-life-estimate.md) — расчёт ресурса батареи: первичная батарея vs LiPo+Solar
- [`docs/enclosure.md`](docs/enclosure.md) — корпус и правила заливки
- [`docs/production.md`](docs/production.md) — маршрут сборки и запуска
- [`docs/limitations-and-risks.md`](docs/limitations-and-risks.md) — ключевые ограничения и риски
- [`hardware/README.md`](hardware/README.md) — состав аппаратной части
- [`hardware/schematic.md`](hardware/schematic.md) — электрическая схема
- [`hardware/wiring.md`](hardware/wiring.md) — подключение компонентов
- [`hardware/mounting.md`](hardware/mounting.md) — механическая укладка в корпус
- [`firmware/README.md`](firmware/README.md) — SDK, сборка, прошивка
- [`firmware/tag_config.example.h`](firmware/tag_config.example.h) — пример конфигурации (TAG_ID, KEY, unix_time)
- [`firmware/src/tag_platform_nrf52832.c`](firmware/src/tag_platform_nrf52832.c) — платформенный слой nRF52832 + S112
- [`manufacturing/checklist.md`](manufacturing/checklist.md) — чеклист сборки и приемки
- [`server/README.md`](server/README.md) — идентификация метки на сервере
- [`server/keygen.py`](server/keygen.py) — генерация ключа для новой метки
- [`server/lookup.py`](server/lookup.py) — поиск метки по `(Major, Minor)`
- [`specs/README.md`](specs/README.md) — **даташиты и ссылки на закупку** всех компонентов
- [`prototype/README.md`](prototype/README.md) — **прототип** на ProMicro NRF52840 v1940 (TinyGo, USB UF2)

## Связанные проекты

| Проект | Платформа | Назначение |
|---|---|---|
| [`ble-tag-jdy23`](../ble-tag-jdy23) | JDY-23 | Статичная метка, минимальная сложность |
| [`ble-tag-e73`](../ble-tag-e73) | E73 / nRF52832 | Двунаправленная метка, протокол БНСО |
| **ble-tag-jdy23-dynamic** | **YJ-16013 / nRF52832** | **Динамическая метка с AES-ротацией** |

Прошивка данного проекта строится на платформе `ble-tag-e73`. Ключевое отличие: вместо приёма команд — периодическая смена `Major/Minor/MAC` по `AES-128`.
