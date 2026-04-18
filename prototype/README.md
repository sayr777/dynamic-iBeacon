# Прототип на ProMicro NRF52840 (v1940)

Быстрый стенд для проверки алгоритма `AES-128 iBeacon-ротации`  
без изготовления кастомной PCB и без J-Link программатора.

## Что это за плата

`ProMicro NRF52840 v1940` — китайский клон [nice!nano v2.0](https://nicekeyboards.com/nice-nano/).  
Продаётся на AliExpress как «SuperMini nRF52840» или «Pro Micro NRF52840».

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
| Проверить алгоритм `AES-128` → `Major/Minor/MAC` | ✅ реализовано |
| Убедиться что сервер (`lookup.py`) идентифицирует метку | ✅ |
| Проверить интервал смены параметров (каждые 5 мин) | ✅ LED-индикация |
| Проверить ночной режим | ✅ |
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

Для базового теста достаточно платы + USB-C кабель + смартфон с приложением [nRF Connect](https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-mobile).

## Быстрый старт (Zephyr, прошивка через USB)

```bash
# 1. Инициализировать Zephyr workspace (один раз)
pip install west
west init -m https://github.com/zephyrproject-rtos/zephyr zephyrproject
cd zephyrproject && west update
pip install -r zephyr/scripts/requirements.txt

# 2. Установить Zephyr SDK toolchain
# https://docs.zephyrproject.org/latest/develop/getting_started/

# 3. Собрать iBeacon sample (основа прототипа)
west build -b promicro_nrf52840 samples/bluetooth/ibeacon

# 4. Войти в режим UF2 (двойной клик RESET → GND на плате)
#    Плата появится как USB-диск "NRF52BOOT"

# 5. Скопировать прошивку
cp build/zephyr/zephyr.uf2 /media/NRF52BOOT/
#    Плата перезагрузится и запустит прошивку

# Альтернатива — west flash через DFU:
west flash --runner adafruit-nrfutil
```

## Структура папки

```
prototype/
├── README.md                          — этот файл
├── docs/
│   ├── hardware.md                    — распиновка, схема подключения батареи
│   └── differences.md                 — отличия от производственной метки
└── firmware/
    ├── README.md                      — SDK, сборка, прошивка
    └── src/
        └── tag_platform_nrf52840_promicro.c  — платформенный слой
```

## Ожидаемое потребление прототипа

Плата имеет дополнительные цепи, которых нет в производственной версии:

| Потребитель | Ток |
|---|---:|
| `nRF52840` deep sleep + RTC | ~1.5 µА |
| `LTH7R` LiPo зарядник (standby, без USB) | **~20 µА** |
| LED (отключён в прошивке ночью) | 0 µА |
| Утечки платы | ~1–2 µА |
| **Итого прототип** | **~23–25 µА** |
| **Итого производство (YJ-16013)** | **~5 µА** |

Ток прототипа в ~5 раз выше из-за `LTH7R`. Для проверки алгоритма это не критично.  
Реальный ресурс с LiPo 500 мАч: ~300 дней без зарядки.

## Ссылки

- Zephyr board: https://docs.zephyrproject.org/latest/boards/others/promicro_nrf52840/doc/index.html
- Все Zephyr samples: https://docs.zephyrproject.org/latest/samples/index.html
- nice!nano документация: https://nicekeyboards.com/docs/nice-nano/
- Производственная версия: [`../README.md`](../README.md)
