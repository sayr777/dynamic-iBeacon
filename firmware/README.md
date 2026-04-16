# Прошивка STM32L031

## Назначение

Прошивка реализует управляющую логику динамической BLE-метки:

- пробуждение каждые `2 с` по `RTC`;
- счётчик циклов для определения момента смены параметров;
- вычисление `Major/Minor/MAC` через `AES-128`;
- управление питанием `JDY-23` через `GPIO`;
- отправка `AT`-команд в `JDY-23` при смене параметров;
- глубокий сон `Stop mode` между циклами.

## Целевая платформа

| Параметр | Значение |
|---|---|
| MCU | `STM32L031F6P6` (рекомендован) или `STM32L010F4P6` |
| Package | `TSSOP-20` |
| Flash | `32 KB` / `16 KB` |
| RAM | `8 KB` / `2 KB` |
| Stop mode с RTC | `≈ 0.4 µА` |
| Инструментарий | `STM32CubeIDE` или `PlatformIO + STM32duino` |
| Программатор | `ST-LINK V2` или `J-LINK` через `SWD` |

## Структура исходного кода

```
firmware/
├── README.md
├── tag_config.example.h        — пример конфигурации (шаблон)
└── src/
    ├── main.c                  — точка входа, инициализация, бесконечный цикл
    ├── tag_app.h / tag_app.c   — основная логика приложения (FSM)
    ├── tag_platform.h          — платформенные абстракции (RTC, GPIO, UART, Stop)
    ├── tag_platform_stm32l0.c  — реализация для STM32L0 (LL-драйверы)
    ├── tag_config.h            — конфигурация конкретного изделия (не в репо)
    ├── aes128.h / aes128.c     — компактный AES-128 ECB (только шифрование)
    ├── beacon_id.h / beacon_id.c — вычисление major/minor/mac из tag_id + slot
    └── jdy23_at.h / jdy23_at.c — AT-команды для JDY-23
```

## Минимальный набор тестов

- запуск от внешнего `3.3 В`;
- запуск от батареи;
- ток `Stop mode` (цель: `< 1 µА` с учётом всей схемы);
- `JDY-23` включается и выключается по `GPIO` в ожидаемые интервалы;
- `Major/Minor` меняются каждые `CYCLES_PER_SLOT` циклов;
- сервер идентифицирует метку по принятым `Major/Minor`.

## Сборка

### STM32CubeIDE

1. Создать проект для `STM32L031F6P6`.
2. Добавить файлы из `firmware/src/` в проект.
3. Скопировать `tag_config.example.h` → `tag_config.h`, задать `TAG_ID`, `KEY`, `unix_time`.
4. Собрать и прошить через `ST-LINK`.

### PlatformIO

```ini
[env:stm32l031]
platform = ststm32
board = genericSTM32L031F6P
framework = arduino
build_flags = -DUSE_LL_DRIVERS
```

## Важно: Read-out Protection

Перед финальной сборкой изделия включить `RDP Level 1` на `STM32L031`:

```
ST-LINK Utility → Target → Option Bytes → Read Out Protection → Level 1
```

Без `RDP` злоумышленник может считать `KEY` из Flash через `SWD`.
