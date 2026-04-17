# Диаграммы взаимодействия

Платформа: **`YJ-16013` (nRF52832)**.  
Подробный протокол: [`protocol.md`](protocol.md)

---

## Диаграмма состояний FSM

```mermaid
stateDiagram-v2
    direction TB

    [*] --> BOOT

    state BOOT {
        direction LR
        [*] --> init : tag_platform_init()\nRTC, SoftDevice S112, LFXO
        init --> slot0 : unix_time ← GPREGRET2
        slot0 --> [*] : last_slot = unix_time/300 − 1
    }

    BOOT --> CHECK_SLOT

    CHECK_SLOT --> UPDATE_PARAMS : unix_time/300 ≠ last_slot
    CHECK_SLOT --> ADVERTISE    : unix_time/300 = last_slot

    state UPDATE_PARAMS {
        direction LR
        [*] --> aes    : block = tag_id[2] ∥ slot[4] ∥ 0x00[10]
        aes    --> ext : out = AES128(KEY, block)
        ext    --> set : Major=out[0:2] · Minor=out[2:4] · MAC=out[4:7]
        set    --> [*] : sd_ble_gap_address_set + adv_set_configure
    }

    UPDATE_PARAMS --> ADVERTISE

    state ADVERTISE {
        direction LR
        [*] --> tx   : sd_ble_gap_adv_start(max_adv_evts=1)
        tx   --> [*] : ch37+38+39 (~1 мс, 5.3 мА)\nBLE_GAP_EVT_ADV_SET_TERMINATED
    }

    ADVERTISE --> SLEEP

    state SLEEP {
        direction LR
        [*] --> night : is_night()?
        night --> r60 : да → RTC +60 с
        night --> r2  : нет → RTC +2 с
        r60   --> off : sd_power_system_off() → ~1.5 µА
        r2    --> off
        off   --> [*]
    }

    SLEEP --> CHECK_SLOT : RTC пробуждение (холодный старт)
```

---

## Диаграмма последовательности (один слот = 5 мин, 150 циклов)

```mermaid
sequenceDiagram
    participant RTC  as RTC (LFXO)
    participant MCU  as nRF52832
    participant AIR  as Эфир (BLE)
    participant SRV  as Сервер

    Note over MCU: System OFF ~1.5 µА

    RTC -->> MCU : пробуждение #1 (t=0 с)
    activate MCU
    MCU ->>  MCU : slot=unix_time/300 → граница слота!
    MCU ->>  MCU : AES128(KEY, tag_id∥slot) → Major, Minor, MAC
    MCU ->>  AIR : iBeacon ch37+38+39 (~1 мс)
    MCU ->>  MCU : sd_power_system_off()
    deactivate MCU
    Note over MCU: Sleep 1999 мс

    RTC -->> MCU : пробуждение #2 (t=2 с)
    activate MCU
    MCU ->>  MCU : slot не изменился
    MCU ->>  AIR : iBeacon ch37+38+39 (те же Major/Minor/MAC)
    MCU ->>  MCU : sd_power_system_off()
    deactivate MCU
    Note over MCU: ...

    Note over MCU,AIR: 148 пробуждений с теми же параметрами...

    RTC -->> MCU : пробуждение #150 (t=298 с)
    activate MCU
    MCU ->>  AIR : iBeacon ch37+38+39
    MCU ->>  MCU : sd_power_system_off()
    deactivate MCU

    Note over AIR,SRV: Сканер передаёт (Major, Minor, RSSI, ts) на сервер

    SRV ->>  SRV  : slot=ts/300; AES×30000 → tag_id=42 (<1 мс)
```

---

## Диаграмма идентификации на сервере

```mermaid
sequenceDiagram
    participant TAG  as BLE-метка (nRF52832)
    participant SCAN as BLE-сканер
    participant SRV  as Сервер

    loop каждые 2 с
        TAG  ->> SCAN : iBeacon\n[UUID=..., Major=0x3A7F, Minor=0xC1B2,\nMAC=E5:C3:7F:A2:11:B4]
    end

    SCAN ->> SRV : {major:0x3A7F, minor:0xC1B2, ts:1735000200}

    Note over SRV : slot = 1735000200 / 300 = 5783333

    loop s ∈ {slot−1, slot, slot+1}
        loop tag_id ∈ 0..9999
            SRV ->> SRV : out = AES128(KEY, tag_id∥s)\nout[0:4] == 0x3A7FC1B2 ?
        end
    end

    Note over SRV : Найдено: tag_id=42, s=5783333\n(30 000 операций, ~0.3 мс)
    SRV ->> SRV  : событие: метка №42, позиция X, время T
```

---

## Временна́я диаграмма потребления

```
Ток:
                    ┌──────┐
  5.3 мА │          │  TX  │
         │          │~1 мс │
  ~0 мА  │──────────┘      └───────────────────────────────────│
         │<──── AES + init ─>│<────── System OFF ~1999 мс ─────>│
         │     ~0.5 мс       │        nRF52832: ~1.5 µА         │
         │                   │        MCP1700:  ~1.0 µА         │
         0                                                   2000 мс

Дневной цикл (интервал 2 с):
  TX:    5.3 мА × 1 мс / 2000 мс   =  2.65 µА
  Sleep: 1.5 µА × 1999 мс / 2000   =  1.50 µА
  LDO:   1.0 µА (постоянно)         =  1.00 µА
  AES:   4.0 мА × 5 мс / 300 000   =  0.07 µА  (раз в 5 мин)
  ────────────────────────────────────────────
  Итого день:                        5.22 µА

Ночной цикл (интервал 60 с):
  TX:    5.3 мА × 1 мс / 60 000    =  0.09 µА  ← исчезает
  Sleep: 1.5 µА + 1.0 µА           =  2.50 µА
  ────────────────────────────────────────────
  Итого ночь:                        2.59 µА

Среднесуточный (17 ч день + 7 ч ночь):
  I = (5.22×17 + 2.59×7) / 24     = 4.40 µА
```
