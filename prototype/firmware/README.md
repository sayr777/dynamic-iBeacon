# Прошивка прототипа (ProMicro NRF52840)

## Назначение

TinyGo-прошивка используется как быстрый прототип production-логики:
- статичный `UUID` оператора;
- динамические `Major` и `Minor`;
- BLE Privacy для `RadioMAC`;
- совместимость с [server/lookup.py](../../server/lookup.py).

## Платформа

| Параметр | Значение |
|---|---|
| SoC | `nRF52840` |
| Плата | `ProMicro NRF52840 v1940` |
| TinyGo board | `nicenano` |
| Прошивка | USB UF2 |

## Сборка

```bash
cd prototype/firmware/tinygo
go mod tidy
tinygo build -o firmware.uf2 -target=nicenano .
```

## Прошивка

1. Подключить плату по USB.
2. Дважды быстро замкнуть `RESET` на `GND`.
3. Дождаться появления диска `NICENANO` или `NRF52BOOT`.
4. Скопировать `firmware.uf2`.

## Логи

Ожидаемый вывод:

```text
[privacy] OK — Radio MAC меняется каждый слот
========================================
BLE Tag  TagID=42     SlotDuration=10s
Operator UUID=FDA50693-A4E2-4FB1-AFCF-C6EB07647825
UUID статичен для оператора; Major + Minor + MAC + RadioMAC динамические
========================================
[slot    1] TagID=42  Major=0xE4B9  Minor=0xE7CA  MAC=E9:B6:FB:6E:2F:50
           UUID=FDA50693-A4E2-4FB1-AFCF-C6EB07647825
```

## Параметры по умолчанию

| Параметр | Значение |
|---|---|
| `SlotDuration` | 10 секунд |
| `TagID` | 42 |
| `OperatorUUID` | `FDA50693-A4E2-4FB1-AFCF-C6EB07647825` |

## Проверка

1. Считать `UUID`, `Major`, `Minor` из логов или сканера.
2. Запустить локальную идентификацию:

```bash
python server/lookup.py \
  --uuid FDA50693-A4E2-4FB1-AFCF-C6EB07647825 \
  --major E4B9 \
  --minor E7CA \
  --key 2B7E151628AED2A6ABF7158809CF4F3C
```

## Исходники

- [tinygo/main.go](tinygo/main.go)
- [tinygo/privacy.go](tinygo/privacy.go)
- [../../docs/algorithm.md](../../docs/algorithm.md)
