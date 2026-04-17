# Динамическая радиометка на nRF52810 (E73-2G4M04S1A)

Этот проект описывает автономную динамическую BLE-метку, которая меняет `Major`, `Minor` и `MAC`-адрес каждые `5 мин`. При знании секретного ключа сервер **однозначно восстанавливает статичный идентификатор метки** по паре `(Major, Minor)` без хранения истории.

## Выбранная платформа: nRF52810 (E73-2G4M04S1A)

| Параметр | Значение |
|---|---|
| Чип | `nRF52810` (Nordic Semiconductor) |
| Модуль | `EBYTE E73-2G4M04S1A` |
| Средний ток | **~4 µА** |
| Ресурс батареи | **~15–20 лет** (ограничен саморазрядом) |
| Запас по цели 3 года | **×5** |
| Смена MAC | ✅ гарантированно каждый слот |
| Этапов прошивки | 1 (SWD) |

Сравнение с альтернативой (JDY-23 + CW32L010): [`docs/platform-comparison.md`](docs/platform-comparison.md)

## Базовая идея

- `nRF52810` просыпается раз в `2 с`, передаёт один `iBeacon`-пакет и засыпает;
- раз в `5 мин` вычисляет новые `Major`, `Minor`, `MAC` через `AES-128`;
- потребление в глубоком сне с `RTC`: `1.5 µА`;
- сервер идентифицирует метку по `(Major, Minor)` за `< 1 мс`.

## Алгоритм

```
slot  = unix_time / SLOT_DURATION          # 5-минутный слот
block = tag_id[2] || slot[4] || 0x00[10]  # 16 байт
out   = AES-128-ECB(KEY, block)
major = out[0:2]   minor = out[2:4]   mac[3:6] = out[4:7]
```

Полная спецификация: [`docs/algorithm.md`](docs/algorithm.md)

## Структура проекта

- [`docs/platform-comparison.md`](docs/platform-comparison.md) — сравнение nRF52810 vs JDY-23 + CW32L010
- [`docs/architecture.md`](docs/architecture.md) — архитектура изделия и режим работы
- [`docs/algorithm.md`](docs/algorithm.md) — спецификация алгоритма смены параметров
- [`docs/interaction-diagram.md`](docs/interaction-diagram.md) — диаграммы состояний и взаимодействия
- [`docs/bom.md`](docs/bom.md) — состав изделия и ориентир по стоимости
- [`docs/battery-life-estimate.md`](docs/battery-life-estimate.md) — оценка срока жизни батареи
- [`docs/enclosure.md`](docs/enclosure.md) — корпус и правила заливки
- [`docs/production.md`](docs/production.md) — маршрут сборки и запуска
- [`docs/limitations-and-risks.md`](docs/limitations-and-risks.md) — ключевые ограничения и риски
- [`hardware/README.md`](hardware/README.md) — состав аппаратной части
- [`hardware/schematic.md`](hardware/schematic.md) — электрическая схема
- [`hardware/wiring.md`](hardware/wiring.md) — подключение компонентов
- [`hardware/mounting.md`](hardware/mounting.md) — механическая укладка в корпус
- [`firmware/README.md`](firmware/README.md) — требования к прошивке и структура
- [`firmware/tag_config.example.h`](firmware/tag_config.example.h) — пример конфигурации
- [`manufacturing/checklist.md`](manufacturing/checklist.md) — чеклист сборки и приемки
- [`server/README.md`](server/README.md) — идентификация метки на сервере
- [`server/keygen.py`](server/keygen.py) — генерация ключа для новой метки
- [`server/lookup.py`](server/lookup.py) — поиск метки по `(Major, Minor)`
- [`specs/README.md`](specs/README.md) — источники по компонентам

## Связанные проекты

| Проект | Платформа | Назначение |
|---|---|---|
| [`ble-tag-jdy23`](../ble-tag-jdy23) | JDY-23 | Статичная метка, минимальная сложность |
| [`ble-tag-e73`](../ble-tag-e73) | E73 / nRF52810 | Двунаправленная метка, протокол БНСО |
| **ble-tag-jdy23-dynamic** | **E73 / nRF52810** | **Динамическая метка с AES-ротацией** |

Прошивка данного проекта строится на платформе `ble-tag-e73`. Ключевое отличие: вместо приёма команд — периодическая смена параметров рекламы по `AES-128`.
