# Серверная часть

## Назначение

Скрипты для управления ключами и идентификации динамических `iBeacon`-меток по принятым пакетам.

## Файлы

| Файл | Назначение |
|---|---|
| [`keygen.py`](keygen.py) | Генерация регионального `AES-128` ключа |
| [`lookup.py`](lookup.py) | Идентификация метки по паре `(Major, Minor)` |

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

Вывод:
```
Region: moscow-north
Key:    2B7E151628AED2A6ABF7158809CF4F3C
Tags:   1..500
Save key to server config and firmware tag_config.h!
```

### 2. Симулировать вывод метки (для отладки)

```bash
python server/lookup.py --simulate --tag-id 42 --key 2B7E151628AED2A6ABF7158809CF4F3C
```

Вывод:
```
Slot: 5783333
Major: 0x3A7F (15999)
Minor: 0xC1B2 (49586)
MAC suffix: E5:3A:E4
```

### 3. Идентифицировать принятый пакет

```bash
python server/lookup.py --major 3A7F --minor C1B2 \
    --key 2B7E151628AED2A6ABF7158809CF4F3C \
    --num-tags 500
```

Вывод:
```
Tag ID: 42
Slot:   5783333 (2024-01-01 12:22:30 UTC)
```

## Интеграция в бэкенд

```python
from server.lookup import identify_tag

result = identify_tag(
    major=0x3A7F,
    minor=0xC1B2,
    key=bytes.fromhex("2B7E151628AED2A6ABF7158809CF4F3C"),
    num_tags=500,
    unix_time=int(time.time())
)
# result = {"tag_id": 42, "slot": 5783333} или None
```

## Хранение ключа

- ключ хранится в защищённом хранилище (например, `HashiCorp Vault`, `AWS Secrets Manager`);
- ключ **никогда** не логируется и не передаётся по незащищённым каналам;
- ключ прошивается в каждую метку при производстве через зашифрованный канал или в защищённом помещении.
