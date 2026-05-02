# Серверная часть

## Назначение

Серверная часть:
- определяет оператора по статичному `iBeacon UUID`;
- локально идентифицирует наши метки по `Major/Minor`;
- маршрутизирует чужие метки на внешний REST оператора;
- поддерживает легаси-режим работы через БНСО.

## Файлы

| Файл | Назначение |
|---|---|
| [keygen.py](keygen.py) | генерация `AES-128` ключа региона |
| [lookup.py](lookup.py) | локальный lookup и маршрутизация по операторам |
| [operators.example.json](operators.example.json) | пример реестра операторов |
| [lookup-pwa/](lookup-pwa/) | браузерный локатор для наших меток |

## Реестр операторов

Пример: [operators.example.json](operators.example.json)

```json
{
  "local": {
    "name": "ours",
    "uuid": "FDA50693-A4E2-4FB1-AFCF-C6EB07647825"
  },
  "external": [
    {
      "name": "yandex",
      "uuid": "11111111-2222-3333-4444-555555555555",
      "lookup_url": "https://example/api/v1/ibeacon/resolve"
    }
  ]
}
```

## Быстрый старт

### 1. Сгенерировать ключ региона

```bash
python server/keygen.py --region "moscow-north" --num-tags 500
```

### 2. Смоделировать пакет нашей метки

```bash
python server/lookup.py --simulate --tag-id 42 \
  --key 2B7E151628AED2A6ABF7158809CF4F3C
```

### 3. Локально идентифицировать нашу метку

```bash
python server/lookup.py \
  --uuid FDA50693-A4E2-4FB1-AFCF-C6EB07647825 \
  --major 20CD \
  --minor F4A0 \
  --key 2B7E151628AED2A6ABF7158809CF4F3C \
  --num-tags 500
```

### 4. Маршрутизировать чужую метку по UUID

```bash
python server/lookup.py \
  --uuid 11111111-2222-3333-4444-555555555555 \
  --major 20CD \
  --minor F4A0 \
  --key 2B7E151628AED2A6ABF7158809CF4F3C \
  --operators server/operators.json
```

Если `UUID` принадлежит внешнему оператору, `lookup.py` делает REST-вызов по его `lookup_url`.

## Локальный алгоритм

Для нашего оператора сервер проверяет кандидатов:

```text
tag_id x [slot-1, slot, slot+1]
```

и ищет совпадение по `Major/Minor`.

## Легаси-совместимость с БНСО

Пока БНСО не передают `UUID + Major + Minor + RSSI`, поддержаны:
- `Умка`: `ID = Major * 65536 + Minor`
- `Скаут`: `ID = Major + Minor`

Примеры:

```bash
python server/lookup.py --bnso-serial 87654321 --bnso-id 550368416 \
  --key 2B7E151628AED2A6ABF7158809CF4F3C
```

## Хранение ключа

- `KEY` хранится в защищённом хранилище секретов;
- в приложение и логи не выводится;
- в устройство прошивается на производстве.

