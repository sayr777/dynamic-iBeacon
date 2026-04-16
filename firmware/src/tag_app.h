#ifndef TAG_APP_H
#define TAG_APP_H

#include <stdint.h>

/* -----------------------------------------------------------------------
 * tag_app — основная логика приложения.
 *
 * Состояния машины состояний:
 *
 *  BOOT → CHECK_CYCLES → UPDATE_PARAMS → WAKE_JDY23 → SEND_BEACON → STOP_MODE
 *                     ↗                              ↗
 *                 (cycle < LIMIT)         (params up to date)
 * ----------------------------------------------------------------------- */

typedef enum
{
    TAG_APP_STATE_BOOT = 0,
    TAG_APP_STATE_CHECK_CYCLES,
    TAG_APP_STATE_UPDATE_PARAMS,
    TAG_APP_STATE_WAKE_JDY23,
    TAG_APP_STATE_SEND_BEACON,
    TAG_APP_STATE_STOP_MODE
} tag_app_state_t;

/* Запустить бесконечный цикл приложения (не возвращается) */
void tag_app_run_forever(void);

#endif /* TAG_APP_H */
