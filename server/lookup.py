#!/usr/bin/env python3
"""
lookup.py — идентификация BLE-метки по паре (Major, Minor).

Алгоритм:
    slot  = unix_time // SLOT_DURATION
    block = tag_id[2] || slot[4] || 0x00[10]
    out   = AES-128-ECB(KEY, block)
    major = out[0:2],  minor = out[2:4]

Использование:
    # Идентификация принятого пакета напрямую
    python server/lookup.py --major 3A7F --minor C1B2 \
        --key 2B7E151628AED2A6ABF7158809CF4F3C --num-tags 500

    # Идентификация по ID из БНСО (Умка: ID=Major*65536+Minor)
    python server/lookup.py --bnso-serial 87654321 --bnso-id 1145128914 \
        --key 2B7E151628AED2A6ABF7158809CF4F3C --num-tags 500

    # Идентификация по ID из БНСО (Скаут: ID=Major+Minor)
    python server/lookup.py --bnso-serial 12345678 --bnso-id 19531 \
        --key 2B7E151628AED2A6ABF7158809CF4F3C --num-tags 500

    # Симуляция вывода конкретной метки
    python server/lookup.py --simulate --tag-id 42 \
        --key 2B7E151628AED2A6ABF7158809CF4F3C

    # Симуляция с заданным unix_time
    python server/lookup.py --simulate --tag-id 42 \
        --key 2B7E151628AED2A6ABF7158809CF4F3C --unix-time 1735000000
"""

import sys
import time
import argparse
import struct
import datetime

try:
    from Crypto.Cipher import AES
except ImportError:
    try:
        from Cryptodome.Cipher import AES
    except ImportError:
        # Fallback: pure Python AES для случаев без pycryptodome
        AES = None


# ---- Pure Python AES-128 (fallback, без зависимостей) -------------------

def _aes128_sbox(x):
    """AES S-box lookup."""
    SBOX = [
        0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
        0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
        0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
        0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
        0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
        0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
        0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
        0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
        0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
        0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
        0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
        0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
        0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
        0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
        0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
        0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
    ]
    return SBOX[x]


def _xtime(x):
    return ((x << 1) ^ (0x1B if x & 0x80 else 0)) & 0xFF


def _gf_mul(a, b):
    p = 0
    for _ in range(8):
        if b & 1:
            p ^= a
        a = _xtime(a)
        b >>= 1
    return p


def aes128_ecb_encrypt_pure(key: bytes, block: bytes) -> bytes:
    """AES-128 ECB encrypt — pure Python, без зависимостей."""
    assert len(key) == 16
    assert len(block) == 16

    # Key expansion
    w = list(key)
    RCON = [0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]
    for i in range(4, 44):
        t = w[(i-1)*4:(i-1)*4+4]
        if i % 4 == 0:
            t = [_aes128_sbox(t[1]) ^ RCON[i//4-1],
                 _aes128_sbox(t[2]),
                 _aes128_sbox(t[3]),
                 _aes128_sbox(t[0])]
        w += [w[(i-4)*4+j] ^ t[j] for j in range(4)]

    # Initial round
    s = list(block)
    s = [s[i] ^ w[i] for i in range(16)]

    for rnd in range(1, 11):
        # SubBytes
        s = [_aes128_sbox(x) for x in s]
        # ShiftRows
        s[1],s[5],s[9],s[13] = s[5],s[9],s[13],s[1]
        s[2],s[6],s[10],s[14] = s[10],s[14],s[2],s[6]
        s[3],s[7],s[11],s[15] = s[15],s[3],s[7],s[11]
        # MixColumns (skip last round)
        if rnd < 10:
            for c in range(4):
                a = s[c*4:c*4+4]
                s[c*4+0] = _gf_mul(2,a[0])^_gf_mul(3,a[1])^a[2]^a[3]
                s[c*4+1] = a[0]^_gf_mul(2,a[1])^_gf_mul(3,a[2])^a[3]
                s[c*4+2] = a[0]^a[1]^_gf_mul(2,a[2])^_gf_mul(3,a[3])
                s[c*4+3] = _gf_mul(3,a[0])^a[1]^a[2]^_gf_mul(2,a[3])
        # AddRoundKey
        rk = w[rnd*16:(rnd+1)*16]
        s = [s[i] ^ rk[i] for i in range(16)]

    return bytes(s)


def aes128_ecb_encrypt(key: bytes, block: bytes) -> bytes:
    """AES-128 ECB encrypt — использует pycryptodome если доступна."""
    if AES is not None:
        cipher = AES.new(key, AES.MODE_ECB)
        return cipher.encrypt(block)
    else:
        return aes128_ecb_encrypt_pure(key, block)


# ---- Реестр БНСО ---------------------------------------------------------
#
# Формат: { 'серийный_номер': 'умка' | 'скаут' }
#
# Умка  (Wialon IPS):  ID = Major * 65536 + Minor  → Major и Minor восстанавливаются точно
# Скаут (EGTS):        ID = Major + Minor           → восстановить точные значения нельзя,
#                                                     но идентификация по сумме работает
#
# Заполните перед развёртыванием. Серийный номер — строка (как в логах БНСО).
BNSO_REGISTRY: dict[str, str] = {
    # '12345678': 'скаут',
    # '87654321': 'умка',
}


def bnso_decode(serial: str, raw_id: int) -> tuple[str, int | None, int | None, int | None]:
    """
    Декодировать raw_id от БНСО в (model, major, minor, id_sum).

    Умка:  возвращает (model, major, minor, None)
    Скаут: возвращает (model, None,  None,  id_sum)

    Raises ValueError если серийный номер не в реестре.
    """
    model = BNSO_REGISTRY.get(serial)
    if model is None:
        raise ValueError(
            f"БНСО с серийным номером '{serial}' не найден в реестре. "
            f"Добавьте запись в BNSO_REGISTRY в server/lookup.py"
        )
    if model == 'умка':
        major = (raw_id >> 16) & 0xFFFF
        minor = raw_id & 0xFFFF
        return model, major, minor, None
    elif model == 'скаут':
        return model, None, None, raw_id
    else:
        raise ValueError(f"Неизвестная модель БНСО: '{model}'")


# ---- Основной алгоритм ---------------------------------------------------

SLOT_DURATION = 300  # секунд (5 минут)


def compute_beacon_params(key: bytes, tag_id: int, slot: int):
    """Вычислить (major, minor, mac_suffix) для заданного тега и слота."""
    block = struct.pack(">HI", tag_id, slot) + b"\x00" * 10
    out = aes128_ecb_encrypt(key, block)
    major = (out[0] << 8) | out[1]
    minor = (out[2] << 8) | out[3]
    mac_suffix = bytes([out[4] | 0xC0, out[5], out[6]])
    return major, minor, mac_suffix


def identify_tag(major: int, minor: int, key: bytes,
                 num_tags: int, unix_time: float = None):
    """
    Найти метку по паре (major, minor).

    Возвращает dict {"tag_id": int, "slot": int} или None.
    Проверяет текущий слот и ±1 (допуск на дрейф часов).
    """
    if unix_time is None:
        unix_time = time.time()

    slot_now = int(unix_time) // SLOT_DURATION

    for slot in [slot_now - 1, slot_now, slot_now + 1]:
        for tag_id in range(0, num_tags + 1):
            m, n, _ = compute_beacon_params(key, tag_id, slot)
            if m == major and n == minor:
                return {"tag_id": tag_id, "slot": slot}

    return None


def identify_tag_by_sum(id_sum: int, key: bytes,
                        num_tags: int, unix_time: float = None) -> dict | None:
    """
    Найти метку по сумме Major+Minor (протокол Скаут: ID = Major + Minor).

    Точные значения Major и Minor восстановить нельзя, но пара (tag_id, slot)
    идентифицируется однозначно — сумма двух AES-выходов уникальна на практике.
    """
    if unix_time is None:
        unix_time = time.time()

    slot_now = int(unix_time) // SLOT_DURATION

    for slot in [slot_now - 1, slot_now, slot_now + 1]:
        for tag_id in range(0, num_tags + 1):
            m, n, _ = compute_beacon_params(key, tag_id, slot)
            if m + n == id_sum:
                return {"tag_id": tag_id, "slot": slot}

    return None


def identify_tag_from_bnso(serial: str, raw_id: int, key: bytes,
                           num_tags: int, unix_time: float = None) -> dict | None:
    """
    Идентификация метки по данным от БНСО.

    По серийному номеру БНСО определяет модель устройства, применяет
    соответствующий алгоритм декодирования и возвращает результат как
    identify_tag() — dict {"tag_id", "slot"} или None.
    """
    model, major, minor, id_sum = bnso_decode(serial, raw_id)

    if model == 'умка':
        return identify_tag(major, minor, key, num_tags, unix_time)
    else:  # скаут
        return identify_tag_by_sum(id_sum, key, num_tags, unix_time)


# ---- CLI -----------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Идентификация BLE-метки по (Major, Minor)"
    )
    parser.add_argument("--key", required=True,
                        help="AES-128 ключ (32 hex символа)")
    parser.add_argument("--num-tags", type=int, default=10000,
                        help="Количество меток в регионе (default: 10000)")
    parser.add_argument("--unix-time", type=float, default=None,
                        help="unix_time для вычисления (default: сейчас)")

    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--simulate", action="store_true",
                      help="Симулировать вывод конкретной метки")
    mode.add_argument("--major", type=str,
                      help="Major из принятого пакета (hex, например: 3A7F)")
    mode.add_argument("--bnso-serial", type=str, metavar="SERIAL",
                      help="Серийный номер БНСО (из реестра BNSO_REGISTRY)")

    parser.add_argument("--minor", type=str,
                        help="Minor из принятого пакета (hex, например: C1B2)")
    parser.add_argument("--bnso-id", type=int, metavar="ID",
                        help="ID метки из телематики БНСО (десятичное целое)")
    parser.add_argument("--tag-id", type=int,
                        help="TAG_ID для симуляции")

    args = parser.parse_args()

    key = bytes.fromhex(args.key)
    if len(key) != 16:
        print("Ошибка: KEY должен быть 32 hex символа (16 байт)", file=sys.stderr)
        return 1

    unix_time = args.unix_time or time.time()
    slot = int(unix_time) // SLOT_DURATION
    ts_str = datetime.datetime.utcfromtimestamp(unix_time).strftime("%Y-%m-%d %H:%M:%S UTC")

    if args.simulate:
        if args.tag_id is None:
            print("Ошибка: --tag-id обязателен для --simulate", file=sys.stderr)
            return 1

        major, minor, mac_suffix = compute_beacon_params(key, args.tag_id, slot)
        print(f"  Tag ID:    {args.tag_id}")
        print(f"  Slot:      {slot}")
        print(f"  Time:      {ts_str}")
        print(f"  Major:     0x{major:04X} ({major})")
        print(f"  Minor:     0x{minor:04X} ({minor})")
        print(f"  MAC sfx:   {mac_suffix[0]:02X}:{mac_suffix[1]:02X}:{mac_suffix[2]:02X}")

    elif args.major:
        if args.minor is None:
            print("Ошибка: --minor обязателен вместе с --major", file=sys.stderr)
            return 1

        major = int(args.major, 16)
        minor = int(args.minor, 16)
        result = identify_tag(major, minor, key, args.num_tags, unix_time)
        _print_result(result, SLOT_DURATION)

    else:  # --bnso-serial
        if args.bnso_id is None:
            print("Ошибка: --bnso-id обязателен вместе с --bnso-serial", file=sys.stderr)
            return 1

        try:
            model, major, minor, id_sum = bnso_decode(args.bnso_serial, args.bnso_id)
        except ValueError as e:
            print(f"Ошибка: {e}", file=sys.stderr)
            return 1

        if model == 'умка':
            print(f"  БНСО:      {args.bnso_serial} (Умка, Wialon IPS)")
            print(f"  Decoded:   Major=0x{major:04X} ({major}), Minor=0x{minor:04X} ({minor})")
            result = identify_tag(major, minor, key, args.num_tags, unix_time)
        else:
            print(f"  БНСО:      {args.bnso_serial} (Скаут, EGTS)")
            print(f"  Decoded:   Major+Minor sum = {id_sum}")
            result = identify_tag_by_sum(id_sum, key, args.num_tags, unix_time)

        _print_result(result, SLOT_DURATION)

    return 0


def _print_result(result: dict | None, slot_duration: int):
    if result:
        slot_ts = result["slot"] * slot_duration
        slot_str = datetime.datetime.utcfromtimestamp(slot_ts).strftime("%Y-%m-%d %H:%M:%S UTC")
        print(f"  Tag ID:    {result['tag_id']}")
        print(f"  Slot:      {result['slot']} ({slot_str})")
    else:
        print("  Метка не найдена")
        return 2


if __name__ == "__main__":
    sys.exit(main())
