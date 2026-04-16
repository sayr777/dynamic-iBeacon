# Спецификации компонентов

Этот раздел содержит ссылки на документацию по компонентам изделия.

## Хост-контроллер

| Компонент | Документ |
|---|---|
| `STM32L031F6P6` | [Datasheet ST](https://www.st.com/resource/en/datasheet/stm32l031f6.pdf) |
| `STM32L010F4P6` (бюджетный вариант) | [Datasheet ST](https://www.st.com/resource/en/datasheet/stm32l010f4.pdf) |
| `STM32L0 Reference Manual` | RM0377 на сайте ST |

## BLE-модуль

| Компонент | Документ |
|---|---|
| `JDY-23` | FCC-мануал: `../ble-tag-jdy23/specs/jdy-23-user-manual-fcc.pdf` |
| `JDY-23` | LCSC datasheet: `../ble-tag-jdy23/specs/jdy-23-datasheet-lcsc.pdf` |

Документация по `JDY-23` взята из сестринского проекта `ble-tag-jdy23`. Хранить копии здесь не требуется — использовать оригиналы.

## Батарея

| Компонент | Документ |
|---|---|
| `FANSO ER14505H-LD` | страница производителя: `../ble-tag-jdy23/specs/fanso-er14505h-official-page.html` |

## Корпус

| Компонент | Документ |
|---|---|
| `AK-W-70-4` | страница производителя: `../ble-tag-jdy23/specs/chinaenclosure-ak-w-series-product-page.html` |

## MOSFET

| Компонент | Параметр | Значение |
|---|---|---|
| `AO3407` (рекомендован) | Тип | P-channel, SOT-23 |
| | `Vgs(th)` | `-0.4...-1.8 В` |
| | `Id` | `4 А` |
| | Цена | `~$0.05` |
| `Si2301CDS` (альтернатива) | Тип | P-channel, SOT-23 |

## Алгоритм

| Стандарт | Описание |
|---|---|
| NIST FIPS 197 | AES-128 (Advanced Encryption Standard) |
| NIST SP 800-38A | ECB mode of operation |

Спецификация алгоритма применительно к проекту: [`../docs/algorithm.md`](../docs/algorithm.md)
