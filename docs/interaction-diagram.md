# Диаграммы взаимодействия

## Диаграмма состояний основного цикла

```mermaid
stateDiagram-v2
    direction TB

    [*] --> BOOT

    state BOOT {
        direction TB
        [*] --> init_platform : GPIO, UART, RTC
        init_platform --> load_config : TAG_ID, KEY, unix_time из Flash
        load_config --> init_jdy23 : первичный AT-профиль
        init_jdy23 --> [*]
    }

    BOOT --> CHECK_CYCLES : cycle_count = 0, slot = RTC / SLOT_DURATION

    state CHECK_CYCLES <<choice>>
    CHECK_CYCLES --> UPDATE_PARAMS : cycle_count ≥ CYCLES_PER_SLOT
    CHECK_CYCLES --> WAKE_JDY23 : cycle_count < CYCLES_PER_SLOT

    state UPDATE_PARAMS {
        direction TB
        [*] --> reset_counter : cycle_count = 0
        reset_counter --> inc_slot : slot++
        inc_slot --> aes_compute : block = tag_id ∥ slot ∥ 0x00×10
        aes_compute --> extract : out = AES128(KEY, block)
        extract --> [*] : major=out[0:2]  minor=out[2:4]  mac=out[4:7]
    }

    UPDATE_PARAMS --> WAKE_JDY23

    state WAKE_JDY23 {
        direction TB
        [*] --> gpio_high : GPIO_JDY_PWR = 1
        gpio_high --> wait_boot : ожидание 50 мс
        wait_boot --> [*]
    }

    WAKE_JDY23 --> SEND_BEACON

    state SEND_BEACON <<choice>>
    SEND_BEACON --> AT_UPDATE : params_changed == 1
    SEND_BEACON --> TX_WAIT : params_changed == 0

    state AT_UPDATE {
        direction TB
        [*] --> send_major : AT+MAJOR{XXXX}\r\n
        send_major --> send_minor : AT+MINOR{XXXX}\r\n
        send_minor --> send_rst : AT+RST\r\n
        send_rst --> wait_restart : ожидание 500 мс
        wait_restart --> [*] : params_changed = 0
    }

    AT_UPDATE --> SLEEP_JDY23
    TX_WAIT --> SLEEP_JDY23 : JDY-23 передаёт пакет (50–80 мс)

    state SLEEP_JDY23 {
        direction TB
        [*] --> gpio_low : GPIO_JDY_PWR = 0
        gpio_low --> [*]
    }

    SLEEP_JDY23 --> STOP_MODE

    state STOP_MODE {
        direction TB
        [*] --> set_rtc_alarm : RTC alarm +2с
        set_rtc_alarm --> enter_stop : HAL_PWR_EnterSTOPMode
        enter_stop --> [*] : пробуждение по RTC
    }

    STOP_MODE --> cycle_inc
    cycle_inc --> CHECK_CYCLES : cycle_count++
```

---

## Диаграмма последовательности (один полный цикл)

```mermaid
sequenceDiagram
    participant RTC as RTC (будильник)
    participant MCU as STM32L031 (хост)
    participant JDY as JDY-23 (метка)

    Note over MCU: Stop mode (~1960 мс)
    RTC-->>MCU: Пробуждение (RTC alarm)

    MCU->>MCU: cycle_count++

    alt cycle_count >= CYCLES_PER_SLOT (параметры устарели)
        MCU->>MCU: cycle_count = 0, slot++
        MCU->>MCU: AES128(KEY, tag_id ∥ slot) → major, minor, mac_suffix
        MCU->>JDY: GPIO HIGH (питание на JDY-23)
        MCU->>MCU: ожидание 50 мс (JDY-23 стартует)
        MCU->>JDY: AT+MAJOR{XXXX}\r\n
        JDY-->>MCU: +OK
        MCU->>JDY: AT+MINOR{XXXX}\r\n
        JDY-->>MCU: +OK
        MCU->>JDY: AT+RST\r\n
        MCU->>MCU: ожидание 500 мс (JDY-23 перезагружается)
        Note over JDY: iBeacon с новыми Major/Minor
    else cycle_count < CYCLES_PER_SLOT (параметры актуальны)
        MCU->>JDY: GPIO HIGH (питание на JDY-23)
        MCU->>MCU: ожидание 80 мс
        Note over JDY: iBeacon с текущими Major/Minor
    end

    MCU->>JDY: GPIO LOW (питание снято с JDY-23)
    MCU->>RTC: установить alarm +2с
    MCU->>MCU: HAL_PWR_EnterSTOPMode
```

---

## Временная диаграмма потребления

```
Время (мс):
   0          50          130        2000
   |          |           |          |
   |__________| __________|          |
   GPIO_JDY   |  JDY-23   |          |
              |  active   |          |
              |           |__________|
                          MCU Stop
   
   Нормальный цикл:
   ├─ MCU active: 0..10 мс    (GPIO, логика, Stop-entry)
   ├─ JDY-23 active: 10..90 мс (boot + 1 ADV packet at 100 мс interval)
   └─ Stop mode: 90..2000 мс  (MCU + JDY off)

   Цикл обновления параметров (каждые 150 циклов = 5 мин):
   ├─ MCU active: 0..10 мс    (AES вычисление)
   ├─ JDY-23 + AT: 10..600 мс (boot + AT+MAJOR + AT+MINOR + AT+RST + restart)
   └─ Stop mode: 600..2000 мс
```

---

## Диаграмма идентификации на сервере

```mermaid
sequenceDiagram
    participant TAG as BLE-метка
    participant SCAN as BLE-сканер
    participant SRV as Сервер

    TAG->>SCAN: iBeacon [Major=0x3A7F, Minor=0xC1B2, MAC=E5:3A:E4:9D:A1:XX]
    SCAN->>SRV: {major: 0x3A7F, minor: 0xC1B2, rssi: -72, ts: 1735000000}

    Note over SRV: slot = ts / 300 = 5783333
    loop для s in [slot-1, slot, slot+1]
        loop для tag_id in 0..9999
            SRV->>SRV: block = tag_id ∥ s ∥ 0x00×10
            SRV->>SRV: out = AES128(KEY, block)
            SRV->>SRV: проверить out[0:4] == 0x3A7FC1B2
        end
    end

    Note over SRV: совпадение найдено: tag_id = 42
    SRV->>SRV: зафиксировать событие: метка #42 у сканера X
```
