# Серверная часть

## Назначение

Скрипты для управления ключами и идентификации динамических `iBeacon`-меток. Поддерживает два пути получения данных:

- **Прямо из эфира** — пара `(Major, Minor)` из iBeacon-пакета (BLE-сканер, PWA);
- **Через БНСО** — единственное число `ID` из телематики (Умка / Скаут).

## Файлы

| Файл | Назначение |
|---|---|
| [`keygen.py`](keygen.py) | Генерация регионального `AES-128` ключа |
| [`lookup.py`](lookup.py) | Идентификация метки по `(Major, Minor)` или по ID от БНСО |
| [`lookup-pwa/`](lookup-pwa/) | PWA «Локатор динамических меток» (офлайн, Web Bluetooth) |

## Требования

```
Python 3.8+
pip install pycryptodome   # или: pip install pycryptodomex
```

## Быстрый старт

### 1. Сгенерировать ключ для региона

```bash
python server/keygen.py --region "moscow-north" --num-tags 500
```

### 2. Симулировать вывод метки (для отладки)

```bash
python server/lookup.py --simulate --tag-id 42 --key 2B7E151628AED2A6ABF7158809CF4F3C
```

Вывод:
```
  Tag ID:    42
  Slot:      5922532
  Time:      2026-04-21 08:15:00 UTC
  Major:     0x20CD (8397)
  Minor:     0xF4A0 (62624)
  MAC sfx:   C5:3A:E4
```

### 3. Идентифицировать пакет из эфира (Major / Minor)

```bash
python server/lookup.py --major 20CD --minor F4A0 \
    --key 2B7E151628AED2A6ABF7158809CF4F3C \
    --num-tags 500
```

Вывод:
```
  Tag ID:    42
  Slot:      5922532 (2026-04-21 08:15:00 UTC)
```

### 4. Идентифицировать по ID из БНСО

#### Умка (Wialon IPS) — `ID = Major × 65536 + Minor`

```bash
python server/lookup.py --bnso-serial 87654321 --bnso-id 550368416 \
    --key 2B7E151628AED2A6ABF7158809CF4F3C --num-tags 500
```

Вывод:
```
  БНСО:      87654321 (Умка, Wialon IPS)
  Decoded:   Major=0x20CD (8397), Minor=0xF4A0 (62624)
  Tag ID:    42
  Slot:      5922532 (2026-04-21 08:15:00 UTC)
```

#### Скаут (EGTS) — `ID = Major + Minor`

```bash
python server/lookup.py --bnso-serial 12345678 --bnso-id 71021 \
    --key 2B7E151628AED2A6ABF7158809CF4F3C --num-tags 500
```

Вывод:
```
  БНСО:      12345678 (Скаут, EGTS)
  Decoded:   Major+Minor sum = 71021
  Tag ID:    42
  Slot:      5922532 (2026-04-21 08:15:00 UTC)
```

## Реестр БНСО

Перед развёртыванием заполните `BNSO_REGISTRY` в [`lookup.py`](lookup.py):

```python
BNSO_REGISTRY: dict[str, str] = {
    '12345678': 'скаут',   # Скаут ЕГТС
    '87654321': 'умка',    # Умка Wialon IPS
}
```

Серийный номер — строка, как он приходит в логах БНСО (поле `IMEI` или номер устройства).

## Интеграция в бэкенд

```python
from server.lookup import identify_tag, identify_tag_from_bnso

# Из эфира (Major/Minor)
result = identify_tag(
    major=0x20CD, minor=0xF4A0,
    key=bytes.fromhex("2B7E151628AED2A6ABF7158809CF4F3C"),
    num_tags=500
)

# Из БНСО (автоматически определяет модель и алгоритм)
result = identify_tag_from_bnso(
    serial='87654321',
    raw_id=550368416,
    key=bytes.fromhex("2B7E151628AED2A6ABF7158809CF4F3C"),
    num_tags=500
)

# result = {"tag_id": 42, "slot": 5922532} или None
```

## PWA — веб-приложение

Офлайн-приложение для идентификации меток в браузере:

- **URL**: https://sayr777.github.io/dynamic-iBeacon/server/lookup-pwa/
- Работает офлайн (Service Worker, кэш);
- Ввод Major/Minor вручную **или** ID из БНСО (Умка/Скаут);
- BLE-сканирование через Web Bluetooth (Chrome + экспериментальный флаг);
- Отображение времени формирования слота (UTC для production, аптайм для прототипа).

## Хранение ключа

- ключ хранится в защищённом хранилище (`HashiCorp Vault`, `AWS Secrets Manager`);
- ключ **никогда** не логируется и не передаётся по незащищённым каналам;
- ключ прошивается в метку при производстве через зашифрованный канал.
