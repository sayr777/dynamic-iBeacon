#ifndef TAG_APP_H
#define TAG_APP_H

#include <stdint.h>

/* -----------------------------------------------------------------------
 * tag_app — основная логика приложения.
 *
 * Цикл работы:
 *
 *  BOOT → UPDATE_PARAMS → STOP_MODE → UPDATE_PARAMS → STOP_MODE → ...
 *
 *  STOP_MODE: STM32L010 спит SLOT_DURATION секунд (5 мин).
 *  JDY-23 работает непрерывно и рекламирует автономно каждые 2 с.
 *  UPDATE_PARAMS: AT+MAJOR + AT+MINOR + AT+RST → JDY-23 перезапускается
 *                 с новыми параметрами.
 * ----------------------------------------------------------------------- */

typedef enum
{
    TAG_APP_STATE_BOOT = 0,
    TAG_APP_STATE_UPDATE_PARAMS,
    TAG_APP_STATE_STOP_MODE
} tag_app_state_t;

/* Запустить бесконечный цикл приложения (не возвращается) */
void tag_app_run_forever(void);

#endif /* TAG_APP_H */
