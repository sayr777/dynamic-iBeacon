# Прошивка nRF52832 ([YJ-16013](../specs/YJ-16013-datasheet.pdf))

## Назначение

Production-прошивка реализует BLE-метку со схемой:
- статичный `iBeacon UUID` оператора;
- динамические `Major` и `Minor`;
- локальное восстановление `TagID` на сервере по `Major/Minor`.

## Платформа

| Параметр | Значение |
|---|---|
| SoC | `nRF52832` |
| Модуль | [YJ-16013](../specs/YJ-16013-datasheet.pdf) |
| SDK | `nRF5 SDK 17.1.x` |
| BLE стек | `SoftDevice S112` |
| Режим | `Broadcaster only` |

## Алгоритм

На каждый слот:

```text
block = tag_id[2] || slot[4] || 0x00[10]
out   = AES-128-ECB(KEY, block)

major = out[0:2]
minor = out[2:4]
mac   = out[4:7]
```

`UUID` не вычисляется, а берётся из конфигурации `TAG_IBEACON_UUID`.

## Структура

```text
firmware/
├── tag_config.example.h
└── src/
    ├── main.c
    ├── tag_app.c
    ├── tag_platform_nrf52832.c
    ├── beacon_id.c
    └── aes128.c
```

## Сборка

```bash
cd firmware/pca10040e/s112/armgcc
make
make flash_softdevice
make flash
```

## Что зашивается в устройство

- `TAG_ID`
- `KEY`
- `TAG_IBEACON_UUID`
- начальный `unix_time`

Пример конфигурации: [tag_config.example.h](tag_config.example.h)

## Серверная совместимость

Прошивка совместима с:
- [server/lookup.py](../server/lookup.py)
- [docs/algorithm.md](../docs/algorithm.md)

