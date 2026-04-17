#ifndef TAG_APP_H
#define TAG_APP_H

#include <stdint.h>

/* -----------------------------------------------------------------------
 * tag_app — основная логика динамической BLE-метки на nRF52810.
 *
 * Цикл работы (каждые TAG_WAKE_INTERVAL_SEC = 2 с):
 *
 *  BOOT
 *   │
 *   ▼
 *  CHECK_CYCLES ──► (cycle < CYCLES_PER_SLOT) ──► ADVERTISE ──► SLEEP
 *   │                                                               │
 *   ▼ (cycle >= CYCLES_PER_SLOT)                          RTC будит│
 *  UPDATE_PARAMS ──────────────────────────────► ADVERTISE ──► SLEEP
 *
 *  UPDATE_PARAMS: AES128(KEY, tag_id || slot) → major, minor, mac
 *  ADVERTISE:     один advertising event (~1 мс), затем deep sleep
 * ----------------------------------------------------------------------- */

typedef enum
{
    TAG_APP_STATE_BOOT = 0,
    TAG_APP_STATE_CHECK_CYCLES,
    TAG_APP_STATE_UPDATE_PARAMS,
    TAG_APP_STATE_ADVERTISE,
    TAG_APP_STATE_SLEEP
} tag_app_state_t;

/* Запустить бесконечный цикл приложения (не возвращается) */
void tag_app_run_forever(void);

#endif /* TAG_APP_H */
