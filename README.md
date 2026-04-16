# Динамическая радиометка на STM32L031 + JDY-23

Этот проект описывает автономную динамическую BLE-метку, в которой хост-контроллер `STM32L031` каждые `2 с` управляет передачей `iBeacon`-посылки через модуль `JDY-23`, а раз в `5 мин` сменяет параметры метки: `Major`, `Minor` и суффикс `MAC`-адреса.

Метка остаётся неидентифицируемой для стороннего наблюдателя. Сервер, знающий секретный ключ, **однозначно восстанавливает статичный идентификатор метки** по паре `(Major, Minor)` без хранения истории.

## Базовая идея

- хост `STM32L031` просыпается каждые `2 с` от `RTC`;
- считает циклы и при необходимости вычисляет новые параметры через `AES-128`;
- подаёт питание на `JDY-23`, ждёт `50 мс` (пакет уходит в эфир);
- снимает питание с `JDY-23`, сам уходит в `Stop mode`;
- раз в `5 мин` (настраиваемо) пересылает `AT+MAJOR`, `AT+MINOR`, перезагружает `JDY-23`;
- потребление `STM32L031` в `Stop mode` — `≈ 0.4 µA`.

## Алгоритм

```
slot  = unix_time / SLOT_DURATION          # 5-минутный слот
block = tag_id[2] || slot[4] || 0x00[10]  # 16 байт
out   = AES-128-ECB(KEY, block)
major = out[0:2]   minor = out[2:4]   mac_suffix = out[4:7]
```

Полная спецификация: [`docs/algorithm.md`](docs/algorithm.md)

## Структура проекта

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
- [`configuration/README.md`](configuration/README.md) — первичная настройка `JDY-23`
- [`configuration/jdy23-ibeacon-profile.txt`](configuration/jdy23-ibeacon-profile.txt) — шаблон `AT`-команд
- [`server/README.md`](server/README.md) — идентификация метки на сервере
- [`server/keygen.py`](server/keygen.py) — генерация ключа для новой метки
- [`server/lookup.py`](server/lookup.py) — поиск метки по `(Major, Minor)`
- [`specs/README.md`](specs/README.md) — источники по компонентам

## Совместимость

Проект является продолжением [`ble-tag-jdy23`](../ble-tag-jdy23). Используются те же батарея `FANSO ER14505H-LD` и корпус `AK-W-70-4`. Добавляется хост-контроллер `STM32L031F6P6`.

## Ключевой компромисс

| Параметр | ble-tag-jdy23 | ble-tag-jdy23-dynamic |
|---|---|---|
| Прошивка | нет (только AT) | `STM32L031` + AT |
| Идентификатор | статичный `Major/Minor` | меняется каждые 5 мин |
| Приватность | низкая | высокая |
| Дополнительный компонент | нет | `STM32L031` ~$0.65 |
| Потребление хоста | нет | `≈ 0.4 µA` в `Stop mode` |
