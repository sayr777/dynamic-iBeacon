#!/usr/bin/env python3
"""
keygen.py — генерация AES-128 ключа для региона меток.

Использование:
    python server/keygen.py --region "moscow-north" --num-tags 500
    python server/keygen.py --region "spb-center" --num-tags 200 --output keys.json
"""

import os
import sys
import json
import argparse
import secrets
import datetime


def generate_key() -> bytes:
    """Сгенерировать криптографически стойкий 128-битный ключ."""
    return secrets.token_bytes(16)


def key_to_c_array(key: bytes) -> str:
    """Отформатировать ключ как инициализатор массива C."""
    parts = [f"0x{b:02X}" for b in key]
    return "{ " + ", ".join(parts) + " }"


def key_to_hex(key: bytes) -> str:
    return key.hex().upper()


def main():
    parser = argparse.ArgumentParser(
        description="Генерация AES-128 ключа для региона BLE-меток"
    )
    parser.add_argument("--region", required=True,
                        help="Название региона (информационное)")
    parser.add_argument("--num-tags", type=int, required=True,
                        help="Количество меток в регионе (для документации)")
    parser.add_argument("--output", default=None,
                        help="Файл для сохранения (JSON). По умолчанию — только вывод на экран.")
    args = parser.parse_args()

    key = generate_key()
    created_at = datetime.datetime.utcnow().isoformat() + "Z"

    result = {
        "region":     args.region,
        "num_tags":   args.num_tags,
        "key_hex":    key_to_hex(key),
        "created_at": created_at,
    }

    print("=" * 60)
    print(f"  Region:    {args.region}")
    print(f"  Num tags:  {args.num_tags}")
    print(f"  Key (hex): {key_to_hex(key)}")
    print(f"  Key (C):   {key_to_c_array(key)}")
    print(f"  Created:   {created_at}")
    print("=" * 60)
    print()
    print("  *** Сохранить ключ в защищённое хранилище! ***")
    print("  *** Прошить KEY в каждый STM32L031 при производстве! ***")
    print()

    if args.output:
        with open(args.output, "w") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        print(f"  Saved to: {args.output}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
