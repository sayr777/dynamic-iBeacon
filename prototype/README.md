# Прототип на ProMicro NRF52840 (v1940)

Быстрый стенд для проверки алгоритма `AES-128 iBeacon-ротации`  
без изготовления кастомной PCB и без J-Link программатора.

## Что это за плата

`ProMicro NRF52840 v1940` — китайский клон [nice!nano v2.0](https://nicekeyboards.com/nice-nano/).  
На AliExpress обычно ищется как [SuperMini nRF52840](https://www.aliexpress.com/w/wholesale-supermini-nrf52840.html) или [Pro Micro NRF52840](https://www.aliexpress.com/w/wholesale-pro-micro-nrf52840.html).

| Параметр | Значение |
|---|---|
| SoC | `nRF52840` (1 MB Flash / 256 KB RAM, BLE 5.0) |
| Форм-фактор | Pro Micro, 18 × 33 мм |
| Питание | USB-C `5 В` или JST-PH 2-pin `3.7 В` LiPo |
| LiPo зарядник | `LTH7R` (~20 µА standby) |
| Антенна | PCB-trace (встроенная) |
| Загрузчик | Adafruit UF2 nRF52840 (drag-and-drop через USB) |
| SWD | тест-пады на обратной стороне платы |
| Zephyr board | `promicro_nrf52840` |
| Цена | ~$4–6 / шт (AliExpress) |

## Цель прототипа

| Задача | Статус |
|---|---|
| Проверить алгоритм: AES-128 variant=0 → UUID, variant=1 → Major/Minor/MAC | ✅ реализовано и подтверждено |
| UUID динамический (меняется каждый слот) | ✅ подтверждено на устройстве |
| MAC payload (все 6 байт) динамический | ✅ подтверждено |
| BLE Privacy — RadioMAC меняется каждый слот | ✅ `[privacy] OK` в логе |
| Убедиться что сервер (`lookup.py`) идентифицирует метку | ✅ |
| Проверить интервал смены параметров | ✅ 10с (отладка) / 5 мин (production) |
| Измерить реальный ток потребления | ⚠️ выше, чем в производстве (см. ниже) |
| Использовать в производстве | ❌ не предназначено (см. `differences.md`) |

## Что нужно купить

| Компонент | Где купить | Цена | Зачем |
|---|---|---:|---|
| `ProMicro NRF52840 v1940` | AliExpress | ~$5 | сама плата |
| LiPo аккумулятор 100–500 мАч 3.7В (JST-PH 2-pin) | AliExpress | ~$2–4 | автономное питание |
| USB-C кабель | — | — | прошивка и питание |
| **Только для SWD отладки:** | | | |
| J-LINK v9 или nRF52840 DK | AliExpress / Nordic | $5–30 | SWD программирование (опционально) |

Для базового теста достаточно платы + USB-C кабель + смартфон с приложением [nRF Connect for Mobile](https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-mobile).

## Быстрый старт (TinyGo, прошивка через USB)

Сейчас прототип работает на **TinyGo**, а не на Zephyr.

```bash
# 1. Установить TinyGo
#    Windows installer:
#    https://tinygo.org/getting-started/install/windows/

# 2. Перейти в каталог прошивки
cd prototype/firmware/tinygo

# 3. Подтянуть зависимости
go mod tidy

# 4. Собрать UF2 для ProMicro NRF52840 v1940
tinygo build -o firmware.uf2 -target=nicenano .
```

Дальше прошивка заливается через UF2 bootloader:

1. Подключить плату по USB.
2. Дважды быстро замкнуть `RESET` на `GND`, чтобы войти в загрузчик.
3. Плата появится как USB-диск `NICENANO` или `NRF52BOOT`.
4. Скопировать `prototype/firmware/tinygo/firmware.uf2` на этот диск.
5. Плата перезагрузится и запустит прошивку.

Для просмотра логов:

```bash
tinygo monitor -port COM8
# или любой serial terminal на 115200 baud
```

## Структура папки

```
prototype/
├── README.md                          — обзор прототипа
├── docs/
│   ├── hardware.md                    — распиновка, батарея, плата
│   ├── differences.md                 — отличия от производственной метки
│   └── setup.md                       — подробная инструкция по прошивке и тестам
└── firmware/
    ├── README.md                      — SDK, сборка, прошивка
    └── tinygo/
        ├── main.go                    — основная TinyGo-прошивка
        ├── privacy.go                 — BLE Privacy через SoftDevice
        ├── go.mod / go.sum            — зависимости TinyGo
        ├── softdevice_include/        — заголовки SoftDevice для CGo
        └── firmware.uf2               — собранный UF2-образ
```

## Ожидаемое потребление прототипа

Плата имеет дополнительные цепи, которых нет в производственной версии:

| Потребитель | Ток |
|---|---:|
| `nRF52840` deep sleep + RTC | ~1.5 µА |
| `LTH7R` LiPo зарядник (standby, без USB) | **~20 µА** |
| Статусный LED | ~0 µА в базовой оценке |
| Утечки платы | ~1–2 µА |
| **Итого прототип** | **~23–25 µА** |
| **Итого производство ([YJ-16013](../specs/YJ-16013-datasheet.pdf))** | **~5 µА** |

Ток прототипа в ~5 раз выше из-за `LTH7R`. Для проверки алгоритма это не критично.  
Реальный ресурс с LiPo 500 мАч: ~300 дней без зарядки.

## Ссылки

- TinyGo install: https://tinygo.org/getting-started/install/
- TinyGo nicenano board: https://tinygo.org/docs/reference/microcontrollers/nicenano/
- AliExpress: [SuperMini nRF52840](https://www.aliexpress.com/w/wholesale-supermini-nrf52840.html)
- AliExpress: [Pro Micro NRF52840](https://www.aliexpress.com/w/wholesale-pro-micro-nrf52840.html)
- nice!nano документация: https://nicekeyboards.com/docs/nice-nano/
- nRF Connect for Mobile: https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-mobile
- Google Play: https://play.google.com/store/apps/details?id=no.nordicsemi.android.mcp
- App Store: https://apps.apple.com/us/app/nrf-connect-for-mobile/id1054362403
- Подробная настройка и тесты: [`docs/setup.md`](docs/setup.md)
- Прошивка прототипа: [`firmware/README.md`](firmware/README.md)
- Производственная версия: [`../README.md`](../README.md)


