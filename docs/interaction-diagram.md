# Диаграммы взаимодействия

## Диаграмма состояний MCU

```mermaid
stateDiagram-v2
    direction TB

    [*] --> BOOT

    state BOOT {
        direction TB
        [*] --> init_platform : GPIO, UART, RTC (LSE)
        init_platform --> load_config : TAG_ID, KEY, unix_time из Flash
        load_config --> init_jdy23 : AT+VER (проверка связи)
        init_jdy23 --> [*]
    }

    BOOT --> UPDATE_PARAMS : slot = unix_time / SLOT_DURATION

    state UPDATE_PARAMS {
        direction TB
        [*] --> aes_compute : block = tag_id ∥ slot ∥ 0x00×10
        aes_compute --> extract : out = AES128(KEY, block)
        extract --> send_major : major = out[0:2]
        send_major --> send_minor : AT+MAJOR{XXXX}
        send_minor --> send_rst : AT+MINOR{XXXX}
        send_rst --> wait_restart : AT+RST
        wait_restart --> [*] : ожидание 600 мс
    }

    UPDATE_PARAMS --> STOP_MODE : MCU останавливается на 5 мин

    state STOP_MODE {
        direction TB
        [*] --> set_alarm : RTC alarm +300 с
        set_alarm --> enter_stop : HAL_PWR_EnterSTOPMode (0.29 µА)
        enter_stop --> [*] : пробуждение по RTC
    }

    STOP_MODE --> UPDATE_PARAMS : slot++

    note right of STOP_MODE
        JDY-23 работает АВТОНОМНО
        пока MCU спит:
        • реклама каждые 2 с
        • ~150 пакетов за слот
        • ~17 µА непрерывно
    end note
```

---

## Диаграмма последовательности (один слот = 5 мин)

```mermaid
sequenceDiagram
    participant RTC as RTC (LSE 32 кГц)
    participant MCU as STM32L010 (хост)
    participant JDY as JDY-23 (BLE метка)

    Note over JDY: Работает автономно,<br/>реклама каждые 2 с,<br/>~17 µА

    RTC-->>MCU: Пробуждение (RTC alarm, каждые 300 с)
    activate MCU

    MCU->>MCU: slot++
    MCU->>MCU: AES128(KEY, tag_id ∥ slot) → major, minor, mac_suffix

    MCU->>JDY: AT+MAJOR{XXXX}\r\n
    JDY-->>MCU: +OK
    MCU->>JDY: AT+MINOR{XXXX}\r\n
    JDY-->>MCU: +OK
    MCU->>JDY: AT+RST\r\n

    Note over JDY: Перезагрузка ~500 мс,<br/>затем реклама с новыми<br/>Major/Minor

    MCU->>RTC: alarm +300 с
    MCU->>MCU: HAL_PWR_EnterSTOPMode
    deactivate MCU

    Note over MCU: Stop mode 299 с (0.29 µА)
    Note over JDY: Реклама каждые 2 с,<br/>~150 пакетов за слот

    RTC-->>MCU: Следующее пробуждение
```

---

## Временная диаграмма потребления

```
Время (с):
   0      0.6                               300
   │       │                                 │
   ┌───────┐                                 ┌───────┐
   │ MCU   │                                 │ MCU   │
   │ акт.  │                                 │ акт.  │
   └───────┘─────────────────────────────────┘
   2 мА    └──────── MCU Stop 0.29 µА ────────┘

   ═══════════════════════════════════════════
   JDY-23 ≈17 µА  (непрерывно, внутренний сон/реклама 2 с)

   ┌──┐  ┌──┐  ┌──┐     ┌──┐  ┌──┐  ┌──┐
   │  │  │  │  │  │ ... │  │  │  │  │  │   ← ADV пакеты JDY-23
   └──┘  └──┘  └──┘     └──┘  └──┘  └──┘
   0с   2с    4с         296с  298с  300с

   Средний ток:
   MCU:  (2мА × 0.6с + 0.29µА × 299.4с) / 300с = 4.3 µА
   JDY:  17 µА (постоянно)
   Итого: ~22 µА
```

---

## Диаграмма идентификации на сервере

```mermaid
sequenceDiagram
    participant TAG as BLE-метка (JDY-23)
    participant SCAN as BLE-сканер
    participant SRV as Сервер

    loop каждые 2 с (автономно)
        TAG->>SCAN: iBeacon [Major=0x3A7F, Minor=0xC1B2, MAC=E5:xx:xx:xx:xx:xx]
    end

    SCAN->>SRV: {major: 0x3A7F, minor: 0xC1B2, rssi: -72, ts: 1735000000}

    Note over SRV: slot = ts / 300 = 5783333
    loop для s in [slot-1, slot, slot+1]
        loop для tag_id in 0..9999
            SRV->>SRV: AES128(KEY, tag_id ∥ s) → проверить out[0:4]
        end
    end

    Note over SRV: Совпадение: tag_id = 42
    SRV->>SRV: Зафиксировать: метка №42, сканер X, время T
```
