# Прошивка [YJ-16013](../specs/YJ-16013-datasheet.pdf) через RP2040 (Raspberry Pi Pico) без J-Link

## Назначение

Этот документ описывает, как использовать **Raspberry Pi Pico (RP2040)** в роли SWD-программатора вместо SEGGER J-Link для прошивки модуля [YJ-16013](../specs/YJ-16013-datasheet.pdf) на базе `nRF52832`.

Подход актуален, когда J-Link недоступен, но нужно прошить или восстановить модуль.

## Как это работает

На Pico прошивается firmware **debugprobe** (официальный проект Raspberry Pi Foundation). После этого Pico становится **CMSIS-DAP** совместимым отладчиком. Вместо `nrfjprog` (который работает только с J-Link) используется **OpenOCD**, умеющий работать с CMSIS-DAP и поддерживающий `nRF52832`.

## Шаг 1. Прошить Pico firmware debugprobe

1. Скачайте готовый `.uf2` из релизов репозитория `raspberrypi/debugprobe`:
   ```
   https://github.com/raspberrypi/debugprobe/releases
   ```
   Нужен файл `debugprobe_on_pico.uf2`.

2. Держите кнопку **BOOTSEL** на Pico, подключите USB к ПК — Pico появится как диск `RPI-RP2`.

3. Скопируйте `.uf2` на этот диск. Pico перезагрузится и станет CMSIS-DAP программатором.

## Шаг 2. Подключить Pico к YJ-16013 по SWD

| Raspberry Pi Pico | YJ-16013 (nRF52832) |
|---|---|
| `GP2` (SWDCLK) | `SWDCLK` |
| `GP3` (SWDIO) | `SWDIO` |
| `GND` | `GND` |
| `3.3V (pin 36)` | `VDD` |

> Точные пины SWDCLK/SWDIO зависят от версии debugprobe — всегда сверяйтесь с [README репозитория](https://github.com/raspberrypi/debugprobe).

Правила питания при прошивке те же, что и для J-Link — см. [nrf5-sdk-swd-setup.md](nrf5-sdk-swd-setup.md#правила-питания-при-прошивке).

## Шаг 3. Установить OpenOCD

`nrfjprog` работает **только** с J-Link и с CMSIS-DAP несовместим. Вместо него используется **OpenOCD**.

OpenOCD уже установлен через [scoop](https://scoop.sh/) и доступен в `PATH`:

```powershell
openocd --version   # Open On-Chip Debugger 0.12.0
```

Если нужно установить с нуля:

```powershell
scoop install openocd
```

Проверить подключение к YJ-16013 (после физического подключения Pico по SWD):

```powershell
openocd -f interface/cmsis-dap.cfg -f target/nrf52.cfg -c "init; exit"
```

Если в выводе появляется строка вида `Info : nRF52832-QFAA ...` — SWD-связь установлена.

## Шаг 4. Прошивка

### Стереть чип

```powershell
openocd -f interface/cmsis-dap.cfg -f target/nrf52.cfg `
  -c "init; halt; nrf5 mass_erase; exit"
```

### Прошить SoftDevice S112

```powershell
openocd -f interface/cmsis-dap.cfg -f target/nrf52.cfg `
  -c "init; halt; program C:/nRF5/softdevices/s112_nrf52_7.2.0_softdevice.hex verify; reset; exit"
```

### Прошить приложение

```powershell
openocd -f interface/cmsis-dap.cfg -f target/nrf52.cfg `
  -c "init; halt; program _build/nrf52832_xxaa.hex verify; reset; exit"
```

### Восстановление при включённом APPROTECT

Аналог `nrfjprog --recover` — полностью стирает чип:

```powershell
openocd -f interface/cmsis-dap.cfg -f target/nrf52.cfg `
  -c "init; halt; nrf5 mass_erase; exit"
```

После этого необходимо заново прошить SoftDevice и приложение.

## Сравнение с J-Link + nrfjprog

| Возможность | J-Link + nrfjprog | Pico (debugprobe) + OpenOCD |
|---|---|---|
| Прошивка `.hex` | ✅ | ✅ |
| Восстановление (APPROTECT) | ✅ | ✅ |
| RTT-логи | ✅ | ✅ (через OpenOCD) |
| Использование `nrfjprog` | ✅ | ❌ |
| Скорость прошивки | выше | немного ниже |
| Стоимость | высокая | низкая |

Для штучного и мелкосерийного производства разница в скорости некритична.

## Ссылки

- [debugprobe (raspberrypi/debugprobe)](https://github.com/raspberrypi/debugprobe)
- [OpenOCD в scoop](https://scoop.sh/) (`scoop install openocd`)
- [Основной гайд по прошивке и установке окружения](nrf5-sdk-swd-setup.md)
