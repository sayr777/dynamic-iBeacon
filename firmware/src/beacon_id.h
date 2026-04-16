#ifndef BEACON_ID_H
#define BEACON_ID_H

#include <stdint.h>

/* -----------------------------------------------------------------------
 * beacon_id — вычисление динамических параметров BLE-маяка.
 *
 * Алгоритм: AES-128-ECB(KEY, tag_id[2] || slot[4] || 0x00[10])
 *   major      = out[0..1]
 *   minor      = out[2..3]
 *   mac_suffix = out[4..6]  (3 байта)
 * ----------------------------------------------------------------------- */

/*
 * beacon_id_compute — вычислить major/minor/mac_suffix для заданного слота.
 *
 * @param key        16-байтовый AES-ключ
 * @param tag_id     статичный идентификатор метки (0..65535)
 * @param slot       текущий временной слот (unix_time / SLOT_DURATION)
 * @param major      [out] 16-битный major
 * @param minor      [out] 16-битный minor
 * @param mac_suffix [out] 3 байта суффикса MAC (mac[3], mac[4], mac[5])
 */
void beacon_id_compute(const uint8_t key[16],
                       uint16_t      tag_id,
                       uint32_t      slot,
                       uint16_t     *major,
                       uint16_t     *minor,
                       uint8_t       mac_suffix[3]);

#endif /* BEACON_ID_H */
