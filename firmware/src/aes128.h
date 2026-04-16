#ifndef AES128_H
#define AES128_H

#include <stdint.h>

/* -----------------------------------------------------------------------
 * Компактный AES-128 ECB (только шифрование).
 * Реализация без внешних таблиц S-box — вычисление на лету.
 * Flash: ~1.8 KB.  RAM: ~240 bytes (стек, нет динамической памяти).
 * ----------------------------------------------------------------------- */

#define AES128_BLOCK_SIZE  16U
#define AES128_KEY_SIZE    16U

/*
 * aes128_ecb_encrypt — зашифровать один 16-байтовый блок.
 *
 * @param key    указатель на 16-байтовый ключ
 * @param in     указатель на 16-байтовый входной блок (открытый текст)
 * @param out    указатель на 16-байтовый выходной буфер (шифртекст)
 */
void aes128_ecb_encrypt(const uint8_t key[AES128_KEY_SIZE],
                        const uint8_t in[AES128_BLOCK_SIZE],
                        uint8_t       out[AES128_BLOCK_SIZE]);

#endif /* AES128_H */
