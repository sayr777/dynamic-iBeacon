#ifndef TAG_APP_H
#define TAG_APP_H

#include <stdint.h>
#include <stdbool.h>

/* -----------------------------------------------------------------------
 * tag_app — основная логика динамической BLE-метки на nRF52832.
 *
 * Дневной цикл (TAG_WAKE_INTERVAL_SEC = 2 с):
 *
 *  BOOT
 *   │  инициализация платформы, вычислить начальный слот
 *   ▼
 *  CHECK_SLOT ──► (слот не изменился) ──────────────────► ADVERTISE ──► SLEEP
 *   │                                                                      │
 *   ▼ (current_slot() != last_slot)                         RTC будит ◄───┘
 *  UPDATE_PARAMS ──► AES128(KEY, tag_id||slot) → major/minor/mac
 *   │
 *   ▼
 *  ADVERTISE ──► один iBeacon-пакет (~1 мс, 5.3 мА)
 *   │
 *   ▼
 *  SLEEP ──► RTC будильник: 2 с (день) или 60 с (ночь) → System OFF
 *
 * Ночной режим (TAG_NIGHT_MODE_ENABLE = 1):
 *   В часы TAG_NIGHT_START_SEC..TAG_NIGHT_END_SEC (местное время UTC+TZ)
 *   интервал пробуждения увеличивается до TAG_NIGHT_WAKE_INTERVAL_SEC (60 с).
 *   Детекция смены слота основана на unix_time/300, поэтому параметры
 *   iBeacon обновляются точно каждые 5 мин независимо от интервала сна.
 *
 * Средний ток:
 *   День (17 ч):  ~5.2 µА  (2 с интервал)
 *   Ночь  (7 ч):  ~2.5 µА  (60 с интервал, TX-вклад ~0.09 µА)
 *   Сутки:        ~4.5 µА  (-15% экономия)
 * ----------------------------------------------------------------------- */

typedef enum
{
    TAG_APP_STATE_BOOT = 0,
    TAG_APP_STATE_CHECK_SLOT,       /* проверить изменение слота по unix_time */
    TAG_APP_STATE_UPDATE_PARAMS,    /* AES-вычисление major/minor/mac         */
    TAG_APP_STATE_ADVERTISE,        /* один iBeacon advertising event         */
    TAG_APP_STATE_SLEEP             /* System OFF, интервал зависит от времени */
} tag_app_state_t;

/* Запустить бесконечный цикл приложения (не возвращается) */
void tag_app_run_forever(void);

#endif /* TAG_APP_H */
