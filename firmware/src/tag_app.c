/*
 * tag_app.c — основная логика приложения.
 *
 * Архитектура:
 *   JDY-23 работает НЕПРЕРЫВНО на внутреннем цикле рекламы 2 с.
 *   STM32L010 спит в Stop mode и просыпается ТОЛЬКО раз в SLOT_DURATION (5 мин)
 *   чтобы обновить Major/Minor через AT-команды.
 *
 * Средний ток: ~22 µА → ресурс батареи ~10 лет.
 */

#include "tag_app.h"
#include "tag_platform.h"
#include "beacon_id.h"
#include "jdy23_at.h"
#include "tag_config.h"

/* ---- Контекст приложения ----------------------------------------------- */

static struct {
    uint32_t slot;           /* текущий временной слот */
    uint16_t major;          /* текущий Major */
    uint16_t minor;          /* текущий Minor */
    uint8_t  mac_suffix[3];  /* текущий суффикс MAC */
} g_ctx;

static const uint8_t g_key[16] = TAG_KEY;

/* ---- Реализация --------------------------------------------------------- */

void tag_app_run_forever(void)
{
    tag_app_state_t state = TAG_APP_STATE_BOOT;

    while (1)
    {
        switch (state)
        {
        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_BOOT:
        {
            tag_platform_init();

            /* Вычислить начальный слот из RTC */
            uint32_t unix_time = tag_platform_get_unix_time();
            g_ctx.slot = unix_time / TAG_SLOT_DURATION_SEC;

            /* JDY-23 уже включён (питание прямое от VCC_MAIN).
             * Выполнить начальную настройку и установить первые параметры. */
            tag_platform_delay_ms(TAG_JDY23_BOOT_DELAY_MS);
            jdy23_init();

            state = TAG_APP_STATE_UPDATE_PARAMS;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_UPDATE_PARAMS:
        {
            /* Вычислить параметры для текущего слота */
            beacon_id_compute(
                g_key,
                (uint16_t)TAG_ID,
                g_ctx.slot,
                &g_ctx.major,
                &g_ctx.minor,
                g_ctx.mac_suffix
            );

            /* Обновить JDY-23 через AT-команды */
            jdy23_set_major(g_ctx.major);
            jdy23_set_minor(g_ctx.minor);
            /* Опционально: смена MAC (зависит от ревизии JDY-23) */
            /* jdy23_set_mac_suffix(g_ctx.mac_suffix); */

            /* Перезагрузить JDY-23 — он стартует с новыми параметрами
             * и продолжает рекламировать автономно на интервале 2 с */
            jdy23_reset();
            tag_platform_delay_ms(TAG_JDY23_RESET_DELAY_MS);

            state = TAG_APP_STATE_STOP_MODE;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_STOP_MODE:
        {
            /* Спать ровно один слот (SLOT_DURATION = 300 с = 5 мин).
             * За это время JDY-23 отправит ~150 рекламных пакетов автономно. */
            tag_platform_set_rtc_alarm(TAG_SLOT_DURATION_SEC);
            tag_platform_enter_stop();

            /* После пробуждения: следующий слот */
            g_ctx.slot++;
            state = TAG_APP_STATE_UPDATE_PARAMS;
            break;
        }

        default:
            state = TAG_APP_STATE_BOOT;
            break;
        }
    }
}
