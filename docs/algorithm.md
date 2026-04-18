# Алгоритм динамической идентификации (v2)

## Задача

Каждые `5 мин` метка публикует новые `UUID`, `Major`, `Minor`, `MAC` (iBeacon payload) и `RadioMAC` (BLE Privacy). Наблюдатель не может отследить метку по этим значениям. Сервер, знающий ключ, однозначно определяет метку по тройке `(UUID, Major, Minor)` за время `O(N)`, где `N` — количество меток в регионе (до `10 000`).

## Параметры

| Параметр | Размер | Описание |
|---|---|---|
| `TAG_ID` | `16 бит` | статичный уникальный номер метки, `0...65535` |
| `KEY` | `16 байт` | общий секретный ключ региона (одинаков на всех метках и на сервере) |
| `SLOT_DURATION` | `300 с` | длительность одного временного слота (настраиваемо) |
| `slot` | `32 бита` | номер текущего слота: `unix_time / SLOT_DURATION` |

## Вычисление параметров метки

Два вызова AES-128 ECB на каждый слот — отличаются байтом `variant` в позиции `[6]`:

```
# Входной блок (16 байт)
block[0]    = TAG_ID >> 8
block[1]    = TAG_ID & 0xFF
block[2]    = slot >> 24
block[3]    = slot >> 16
block[4]    = slot >> 8
block[5]    = slot & 0xFF
block[6]    = variant    # 0x00 или 0x01
block[7..15] = 0x00      # padding

# variant=0 → UUID (все 16 байт вывода)
uuid[0..15] = AES-128-ECB-Encrypt(KEY, block с variant=0)

# variant=1 → Major + Minor + MAC
out[0..15]  = AES-128-ECB-Encrypt(KEY, block с variant=1)
major       = (out[0] << 8) | out[1]    # 16 бит
minor       = (out[2] << 8) | out[3]    # 16 бит
mac[0]      = out[4] | 0xC0             # Random Static (биты 46-47 = 11, BLE spec)
mac[1]      = out[5]
mac[2]      = out[6]
mac[3]      = out[7]
mac[4]      = out[8]
mac[5]      = out[9]
```

### Что меняется каждый слот

| Поле iBeacon | Источник | Меняется |
|---|---|---|
| UUID (16 байт) | AES variant=0, все 16 байт | ✅ каждый слот |
| Major (2 байта) | AES variant=1, out[0:2] | ✅ каждый слот |
| Minor (2 байта) | AES variant=1, out[2:4] | ✅ каждый слот |
| MAC payload (6 байт) | AES variant=1, out[4:10] | ✅ каждый слот |
| RadioMAC (BLE Privacy) | SoftDevice `sd_ble_gap_privacy_set()` | ✅ каждый слот |
| TAG_ID | — | ❌ недоступен из эфира |

## Идентификация на сервере

Для каждого принятого пакета `(uuid_rx, major_rx, minor_rx)`:

```python
slot_now = int(unix_time()) // SLOT_DURATION

for s in [slot_now - 1, slot_now, slot_now + 1]:   # окно ±5 мин
    for tag_id in range(0, NUM_TAGS):               # перебор всех меток
        # variant=0: проверяем UUID
        block0 = tag_id.to_bytes(2,'big') + s.to_bytes(4,'big') + b'\x00' + bytes(9)
        uuid_c = AES128_encrypt(KEY, block0)
        if uuid_c != uuid_rx:
            continue                                 # быстрое отсечение по UUID

        # variant=1: проверяем Major+Minor
        block1 = tag_id.to_bytes(2,'big') + s.to_bytes(4,'big') + b'\x01' + bytes(9)
        out = AES128_encrypt(KEY, block1)
        major_c = (out[0] << 8) | out[1]
        minor_c = (out[2] << 8) | out[3]
        if major_c == major_rx and minor_c == minor_rx:
            return tag_id                            # метка найдена
return None  # не найдена
```

С `10 000` метками и `3` слотами — `60 000` AES-128 операций (2 на кандидата) ≈ `< 1 мс` на современном сервере.

### Оптимизированный вариант (precompute)

Для сканера реального времени: перед началом сканирования построить словарь
`Map(uuid_hex → {tag_id, slot, major, minor, mac})` для всех `(tag_id, slot)` комбинаций.
Приём пакета → O(1) lookup по UUID.

## Вероятность коллизии

Вероятность коллизии UUID (128 бит) практически нулевая:

```
P_collision(UUID) ≈ N² / 2¹²⁸ ≈ 10000² / 3.4×10³⁸ ≈ 0
```

Коллизия Major+Minor (32 бита):
```
P_collision(Major+Minor) ≈ N² / 2³² ≈ 10000² / 4294967296 ≈ 0.0023%
```

UUID служит первичным ключом — коллизии на уровне (UUID, Major, Minor) исключены.

## Свойства безопасности

- **Неотслеживаемость**: без знания `KEY` наблюдатель не может связать пакеты одной метки между слотами. UUID, Major, Minor, MAC и RadioMAC — все меняются.
- **BLE Privacy**: `sd_ble_gap_privacy_set(DEVICE_PRIVACY, NON_RESOLVABLE_PRIVATE_ADDRESS)` — SoftDevice сам меняет RadioMAC каждый `cycle_s` секунд.
- **Аутентичность**: подобрать `(tag_id, slot)` под произвольный UUID без `KEY` — задача инверсии AES-128.
- **Общий ключ**: один ключ на весь регион. Компрометация одного устройства раскрывает все метки региона. Для повышения безопасности — иерархия ключей: `device_key = AES(master_key, tag_id)`.

## Управление ключами

- `KEY` генерируется один раз для региона: [`server/keygen.py`](../server/keygen.py).
- `KEY` прошивается в каждое устройство при производстве.
- `KEY` хранится на сервере в защищённом хранилище.
- `KEY` **никогда не передаётся** по воздуху.

## Иерархия ключей (расширенный вариант)

```
master_key   — хранится только на сервере (16 байт)
device_key_i = AES128(master_key, tag_id_i || 0x00[14])  — для каждой метки
```

Компрометация одного `device_key_i` не раскрывает другие метки.

## Пример вычисления

```
TAG_ID = 42      → 0x002A
slot   = 17520   → 0x00004470  (unix_time = 5256000 / 300 = 17520)
KEY    = 2B7E151628AED2A6ABF7158809CF4F3C

# variant=0 (UUID)
block0 = 002A 00004470 00 000000000000000000
AES128(KEY, block0) → UUID = DEEAEB01-216B-BAE2-51D1-335F754CCB9F

# variant=1 (Major+Minor+MAC)
block1 = 002A 00004470 01 000000000000000000
AES128(KEY, block1) → out = [E4 B9 E7 CA 29 B6 FB 6E 2F 50 ...]
major = 0xE4B9  minor = 0xE7CA
mac   = E9:B6:FB:6E:2F:50  (out[4] | 0xC0 = 0xE9)
```

Реальный вывод прошивки (18 апреля 2026, slot=1, TagID=42):
```
[slot    1] TagID=42  Major=0xE4B9  Minor=0xE7CA  MAC=E9:B6:FB:6E:2F:50
           UUID=DEEAEB01-216B-BAE2-51D1-335F754CCB9F
```

## История версий

| Версия | Дата | Изменения |
|---|---|---|
| v1 | до 18.04.2026 | 1 вызов AES: UUID статичный, only Major+Minor+3 bytes MAC suffix |
| **v2** | **18.04.2026** | **2 вызова AES (variant=0/1): UUID динамический, full 6-byte MAC, BLE Privacy** |

## Тестирование алгоритма

```bash
# Симуляция одного цикла метки
python server/lookup.py --simulate --tag-id 42 --slot 17520

# Идентификация принятого пакета
python server/lookup.py --uuid DEEAEB01216BBAE251D1335F754CCB9F --major E4B9 --minor E7CA
```
