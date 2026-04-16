#include "beacon_id.h"
#include "aes128.h"
#include <string.h>

void beacon_id_compute(const uint8_t key[16],
                       uint16_t      tag_id,
                       uint32_t      slot,
                       uint16_t     *major,
                       uint16_t     *minor,
                       uint8_t       mac_suffix[3])
{
    uint8_t block[AES128_BLOCK_SIZE];
    uint8_t out[AES128_BLOCK_SIZE];

    /* Сформировать блок: tag_id[2] || slot[4] || 0x00[10] */
    memset(block, 0, sizeof(block));
    block[0] = (uint8_t)(tag_id >> 8);
    block[1] = (uint8_t)(tag_id & 0xFF);
    block[2] = (uint8_t)(slot >> 24);
    block[3] = (uint8_t)(slot >> 16);
    block[4] = (uint8_t)(slot >> 8);
    block[5] = (uint8_t)(slot & 0xFF);

    /* Зашифровать */
    aes128_ecb_encrypt(key, block, out);

    /* Извлечь параметры */
    *major = ((uint16_t)out[0] << 8) | out[1];
    *minor = ((uint16_t)out[2] << 8) | out[3];

    /* MAC-суффикс: установить locally administered bit (bit7 of byte0) */
    mac_suffix[0] = out[4] | 0xC0U;
    mac_suffix[1] = out[5];
    mac_suffix[2] = out[6];
}
