# Прототип на ProMicro NRF52840 (v1940)

Быстрый стенд для проверки production-алгоритма без изготовления кастомной PCB и без SWD-прошивки.

## Что проверяет прототип

Прототип работает по той же модели, что и production:
- статичный `iBeacon UUID` оператора;
- динамические `Major` и `Minor`;
- локальная идентификация на сервере по `Major/Minor`;
- BLE Privacy для `RadioMAC`.

## Статус

| Задача | Статус |
|---|---|
| Проверить статичный UUID оператора | ✅ |
| Проверить смену `Major/Minor` по слотам | ✅ |
| Проверить BLE Privacy | ✅ |
| Сверить с `server/lookup.py` | ✅ |
| Использовать как production-плату | ❌ |

## Плата

`ProMicro NRF52840 v1940` — китайский клон `nice!nano`.

| Параметр | Значение |
|---|---|
| SoC | `nRF52840` |
| Загрузчик | UF2 |
| Прошивка | TinyGo |
| Назначение | лабораторный прототип |

## Быстрый старт

```bash
cd prototype/firmware/tinygo
go mod tidy
tinygo build -o firmware.uf2 -target=nicenano .
```

Дальше:
1. Дважды замкнуть `RESET` на `GND`.
2. Дождаться USB-диска `NICENANO` или `NRF52BOOT`.
3. Скопировать `firmware.uf2`.

## Что видно в логах

Прототип печатает:
- статичный `Operator UUID`;
- текущий `slot`;
- `Major`;
- `Minor`.

Именно эти значения затем сверяются через [server/lookup.py](../server/lookup.py).

## Ограничения прототипа

- выше ток покоя, чем у production;
- другая элементная база питания;
- нужен только для проверки алгоритма и интеграции.

## Ссылки

- [firmware/tinygo/main.go](firmware/tinygo/main.go)
- [server/lookup.py](../server/lookup.py)
- [docs/algorithm.md](../docs/algorithm.md)
- [../README.md](../README.md)
