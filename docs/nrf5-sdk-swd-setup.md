# Настройка nRF5 SDK 17.1.x + SoftDevice S112 и прошивка [YJ-16013](../specs/YJ-16013-datasheet.pdf) (nRF52832) через SWD

## Назначение

Этот документ описывает практическую схему работы с прошивкой для [YJ-16013](../specs/YJ-16013-datasheet.pdf) на базе `nRF52832`:

- установка окружения для `nRF5 SDK 17.1.x`;
- подготовка `SoftDevice S112`;
- подключение SWD-программатора к плате;
- заливка `SoftDevice` и приложения на модуль [YJ-16013](../specs/YJ-16013-datasheet.pdf);
- базовая диагностика типовых проблем.

Документ ориентирован в первую очередь на `Windows`, потому что это самый типичный сценарий для `nRF5 SDK + nrfjprog`.

## Что важно заранее

- `nRF5 SDK` находится в maintenance mode, но для этой BLE-метки он всё ещё подходит;
- для прошивки через `nrfjprog` нужен именно `SEGGER J-Link` или отладочная плата Nordic с J-Link OB, например `nRF52 DK`;
- `ST-LINK` и другие SWD-отладчики можно использовать только через другие инструменты, но **не через `nrfjprog`**;
- `SoftDevice S112` нужно прошивать отдельно от приложения, если вы не используете объединённый `.hex`.

## Рекомендуемая аппаратная схема

### Поддерживаемый и рекомендуемый программатор

Рекомендуется один из вариантов:

- `SEGGER J-Link`;
- `nRF52 DK`, используемая как внешний J-Link-программатор через `Debug Out`;
- другой Nordic DK с J-Link OB.

### SWD-сигналы для [YJ-16013](../specs/YJ-16013-datasheet.pdf)

Для прошивки и отладки на плате должны быть доступны как минимум:

- `SWDIO`
- `SWDCLK`
- `RESET`
- `GND`
- `VDD` или `VTref`

### Подключение программатора

| Программатор | Плата [YJ-16013](../specs/YJ-16013-datasheet.pdf) |
|---|---|
| `SWDIO` | `SWDIO` |
| `SWDCLK` | `SWDCLK` |
| `RESET` | `RESET` |
| `GND` | `GND` |
| `VTref` / `3.0V..3.3V` | `VDD` |

### Правила питания при прошивке

- Самый простой вариант: питать целевую плату от программатора на `3.0-3.3 В`.
- Если плата питается от своего LDO или лабораторного источника, у программатора и платы **обязательно** должна быть общая земля.
- Не подавайте одновременно батарею и внешние `3.3 В`, если схема не рассчитана на это явно.
- Для стабильной прошивки удобно использовать чистое питание `3.0 В` или `3.3 В` без батареи.

## Что установить на ПК

### 1. nRF5 SDK 17.1.0

Нужен архив `nRF5 SDK 17.1.0`.

Практически удобно распаковать его, например, сюда:

```text
C:\nRF5\nRF5_SDK_17.1.0\
```

### 2. SoftDevice S112

Нужен `SoftDevice S112` версии, совместимой с проектом. Для текущей кодовой базы ориентир:

- `S112 v7.3.0`

Удобно держать `.hex` рядом с SDK, например:

```text
C:\nRF5\softdevices\s112_nrf52_7.3.0_softdevice.hex
```

### 3. Arm GNU Toolchain (`arm-none-eabi`)

Нужен компилятор `arm-none-eabi-gcc`.

Пример каталога установки:

```text
C:\GNU Arm Embedded Toolchain\arm-gnu-toolchain-13.3.rel1-mingw-w64-i686-arm-none-eabi\
```

Или любой другой путь без кириллицы и пробелов в критичных переменных Makefile.

### 4. GNU Make

Нужен `make.exe`. Его можно взять:

- из `MSYS2`;
- из `Git for Windows` вместе с Unix toolset;
- из отдельной установки `GNU Make`.

Важно, чтобы команда `make --version` работала из PowerShell или `cmd`.

### 5. SEGGER J-Link Software and Documentation Pack

Нужна установленная утилита `JLink.exe` и драйверы J-Link.

### 6. nRF Command Line Tools

Нужен пакет с `nrfjprog.exe` и `mergehex.exe`.

Важный нюанс:

- Nordic помечает `nRF Command Line Tools` как архивный продукт;
- для `nRF5 SDK` он всё ещё остаётся самым практичным вариантом.

## Рекомендуемая структура каталогов

Один из удобных вариантов:

```text
C:\nRF5\
  nRF5_SDK_17.1.0\
  softdevices\
    s112_nrf52_7.3.0_softdevice.hex
  work\
    dynamic-iBeacon\
```

Ваш репозиторий при этом может лежать отдельно, например:

```text
C:\T1_GIT\dynamic-iBeacon\
```

## Проверка окружения

После установки полезно проверить команды:

```powershell
arm-none-eabi-gcc --version
make --version
nrfjprog --version
mergehex --help
```

Если хотя бы одна команда не находится, нужно исправить `PATH`.

## Как организовать проект внутри nRF5 SDK

### Важный нюанс по текущему репозиторию

В этом репозитории есть исходники платформы и логики в:

```text
firmware\src\
```

Но в репозитории **нет готового build-каталога** вида:

```text
firmware\pca10040e\s112\armgcc\
```

Поэтому для сборки на `nRF5 SDK` нужен отдельный каркас проекта.

### Практический путь

Самый удобный и предсказуемый вариант:

1. Взять близкий пример из `nRF5 SDK` под `nRF52832 + S112`.
2. Скопировать его в новый каталог приложения.
3. Подменить `main.c`, список исходников и include paths на файлы из этого репозитория.

Например:

```text
C:\nRF5\nRF5_SDK_17.1.0\examples\ble_peripheral\ble_app_beacon_yj16013\
```

Внутри него оставить типичную структуру SDK:

```text
ble_app_beacon_yj16013\
  main.c
  pca10040\s112\armgcc\Makefile
```

А исходники из текущего проекта подключить как:

- `firmware/src/main.c`
- `firmware/src/tag_app.c`
- `firmware/src/tag_platform_nrf52832.c`
- `firmware/src/beacon_id.c`
- `firmware/src/aes128.c`

и заголовки:

- `firmware/src/*.h`
- `firmware/tag_config.h`

## Настройка `tag_config.h`

Перед сборкой нужно создать рабочий конфиг:

```text
firmware/tag_config.h
```

Проще всего сделать так:

1. Скопировать `firmware/tag_config.example.h` в `firmware/tag_config.h`.
2. Заполнить:
   - `TAG_ID`
   - `TAG_KEY`
   - `TAG_INITIAL_UNIX_TIME`
   - при необходимости `TAG_IBEACON_UUID`, `TAG_MAC_PREFIX`, `TAG_TX_POWER_DBM`

Если `tag_config.h` лежит вне SDK-примера, его каталог должен быть добавлен в include path вашего `Makefile`.

## Что должно быть в Makefile

Для `nRF52832` и `S112` ориентиры такие:

- target: `nrf52832_xxaa`
- board: `PCA10040`
- softdevice: `S112`

В Makefile должны быть:

- путь к `GNU_INSTALL_ROOT`;
- пути к исходникам проекта;
- include paths до `firmware/src` и `firmware`;
- линкерный скрипт под `nRF52832`;
- startup/system-файлы из SDK;
- CMSIS и nrfx include paths из SDK.

Если хотите, это можно затем оформить как отдельный `armgcc` шаблон прямо в репозитории.

## Подключение платы к программатору

Перед прошивкой:

1. Отключить батарею, если это возможно.
2. Подключить SWD-линии:
   - `SWDIO`
   - `SWDCLK`
   - `RESET`
   - `GND`
   - `VDD/VTref`
3. Подать питание на цель.
4. Проверить, что программатор видит чип.

Проверка:

```powershell
nrfjprog -f nrf52 --ids
```

Если всё нормально, команда покажет serial number J-Link.

Дальше полезно проверить доступ к самому MCU:

```powershell
nrfjprog -f nrf52 --memrd 0x10000100 --w 4
```

Если чтение проходит, SWD-связь установлена.

## Если чип был защищён `APPROTECT`

Если ранее на модуле уже включали защиту чтения, обычная прошивка может не пройти.

Тогда нужен `recover`, который **полностью стирает чип**:

```powershell
nrfjprog -f nrf52 --recover
```

После этого нужно заново прошить:

- `SoftDevice`
- приложение
- все пользовательские данные, если они были

## Порядок прошивки на [YJ-16013](../specs/YJ-16013-datasheet.pdf)

### Вариант 1. Прошивать SoftDevice и приложение отдельно

Это самый понятный путь при отладке.

#### Шаг 1. Стереть кристалл

```powershell
nrfjprog -f nrf52 --eraseall
```

#### Шаг 2. Прошить SoftDevice S112

```powershell
nrfjprog -f nrf52 --program C:\nRF5\softdevices\s112_nrf52_7.3.0_softdevice.hex --sectorerase --verify
nrfjprog -f nrf52 --reset
```

#### Шаг 3. Собрать приложение

Из каталога `armgcc`:

```powershell
make
```

Обычно на выходе получится `.hex` файл приложения.

#### Шаг 4. Прошить приложение

```powershell
nrfjprog -f nrf52 --program _build\nrf52832_xxaa.hex --sectorerase --verify
nrfjprog -f nrf52 --reset
```

Если имя итогового `.hex` у вас другое, подставьте реальный путь из `_build`.

### Вариант 2. Прошивать объединённый HEX

Этот путь удобен для производства.

#### Шаг 1. Объединить SoftDevice и приложение

```powershell
mergehex -m C:\nRF5\softdevices\s112_nrf52_7.3.0_softdevice.hex _build\nrf52832_xxaa.hex -o _build\combined_s112_app.hex
```

#### Шаг 2. Залить объединённый HEX

```powershell
nrfjprog -f nrf52 --eraseall
nrfjprog -f nrf52 --program _build\combined_s112_app.hex --verify
nrfjprog -f nrf52 --reset
```

## Рекомендуемая последовательность для первой заливки

Для новой или восстановленной платы:

1. Подключить SWD.
2. Проверить видимость программатора: `nrfjprog --ids`.
3. Выполнить `--eraseall` или `--recover`, если нужно.
4. Прошить `SoftDevice S112`.
5. Прошить приложение.
6. Выполнить `--reset`.
7. Проверить ток и BLE-рекламу.

## Как понять, что прошивка стартовала

Минимальные признаки:

- `nrfjprog` завершился без ошибок;
- ток платы после старта ушёл в режим сна, а не остался на миллиамперах;
- метка видна как `iBeacon`;
- при смене слота обновляются `Major/Minor/MAC`, если это ожидается по конфигу.

## Типовые проблемы

### `ERROR: Unable to connect to a debugger`

Причины:

- нет питания цели;
- не подключён `VTref`;
- перепутаны `SWDIO` и `SWDCLK`;
- плохой контакт pogo-pin;
- неисправен или не установлен J-Link driver.

### `ERROR: The operation attempted is unavailable due to readback protection`

Причина:

- включён `APPROTECT`.

Решение:

```powershell
nrfjprog -f nrf52 --recover
```

Помните, что это сотрёт содержимое кристалла.

### `make` не находит `arm-none-eabi-gcc`

Причина:

- не настроен `GNU_INSTALL_ROOT`;
- toolchain не добавлен в `PATH`.

### Приложение шьётся, но не стартует

Проверить:

- прошит ли `SoftDevice S112`;
- совпадает ли версия `SoftDevice` с тем, на что рассчитывает проект;
- корректен ли linker script под `nRF52832`;
- не пересекаются ли области памяти `SoftDevice` и приложения;
- не включили ли `APPROTECT` слишком рано во время отладки.

## Что удобно автоматизировать

Когда базовая сборка заработает, удобно сделать:

- `flash_softdevice.bat`
- `flash_app.bat`
- `flash_full.bat`

Например, для полного цикла:

```powershell
nrfjprog -f nrf52 --eraseall
nrfjprog -f nrf52 --program C:\nRF5\softdevices\s112_nrf52_7.3.0_softdevice.hex --sectorerase --verify
nrfjprog -f nrf52 --program _build\nrf52832_xxaa.hex --sectorerase --verify
nrfjprog -f nrf52 --reset
```

## Рекомендация для этого проекта

Для [YJ-16013](../specs/YJ-16013-datasheet.pdf) на `nRF52832` в рамках этого проекта наиболее практичный путь такой:

- `nRF5 SDK 17.1.0`
- `SoftDevice S112 v7.3.0`
- `Arm GNU Toolchain`
- `make`
- `J-Link + nrfjprog`

Это даёт самый простой и воспроизводимый сценарий для BLE-маяка с `System OFF` и прошивкой через SWD.

## Официальные страницы

- `nRF5 SDK`: https://www.nordicsemi.com/Products/Development-software/nrf5-sdk/download
- `nRF Command Line Tools`: https://www.nordicsemi.com/Products/Development-tools/nrf-command-line-tools
- `nRF Command Line Tools Download`: https://www.nordicsemi.com/Products/Development-tools/nrf-command-line-tools/download
- `SEGGER J-Link Downloads`: https://www.segger.com/downloads/jlink
- `Arm GNU Toolchain`: https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads


