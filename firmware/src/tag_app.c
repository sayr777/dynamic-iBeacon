#include "tag_app.h"
#include "tag_platform.h"
#include "beacon_id.h"
#include "jdy23_at.h"
#include "tag_config.h"

/* ---- Контекст приложения ----------------------------------------------- */

static struct {
    uint32_t cycle_count;   /* текущее число циклов с момента последнего обновления */
    uint32_t slot;          /* текущий временной слот */
    uint16_t major;         /* текущий Major */
    uint16_t minor;         /* текущий Minor */
    uint8_t  mac_suffix[3]; /* текущий суффикс MAC */
    uint8_t  params_changed; /* флаг: нужно обновить JDY-23 */
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
            g_ctx.slot         = unix_time / TAG_SLOT_DURATION_SEC;
            g_ctx.cycle_count  = TAG_CYCLES_PER_SLOT; /* принудить обновление при старте */
            g_ctx.params_changed = 0;

            /* Инициализировать JDY-23 */
            tag_platform_jdy23_power(1);
            tag_platform_delay_ms(TAG_JDY23_BOOT_DELAY_MS);
            jdy23_init();
            tag_platform_jdy23_power(0);

            state = TAG_APP_STATE_CHECK_CYCLES;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_CHECK_CYCLES:
        {
            g_ctx.cycle_count++;

            if (g_ctx.cycle_count >= TAG_CYCLES_PER_SLOT) {
                state = TAG_APP_STATE_UPDATE_PARAMS;
            } else {
                state = TAG_APP_STATE_WAKE_JDY23;
            }
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_UPDATE_PARAMS:
        {
            g_ctx.cycle_count = 0;
            g_ctx.slot++;

            beacon_id_compute(
                g_key,
                (uint16_t)TAG_ID,
                g_ctx.slot,
                &g_ctx.major,
                &g_ctx.minor,
                g_ctx.mac_suffix
            );

            g_ctx.params_changed = 1;
            state = TAG_APP_STATE_WAKE_JDY23;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_WAKE_JDY23:
        {
            /* Подать питание на JDY-23 */
            tag_platform_jdy23_power(1);
            /* Ждать загрузки модуля */
            tag_platform_delay_ms(TAG_JDY23_BOOT_DELAY_MS);

            state = TAG_APP_STATE_SEND_BEACON;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_SEND_BEACON:
        {
            if (g_ctx.params_changed) {
                /* Обновить параметры в JDY-23 */
                jdy23_set_major(g_ctx.major);
                jdy23_set_minor(g_ctx.minor);
                /* Опционально: смена MAC (зависит от ревизии JDY-23) */
                /* jdy23_set_mac_suffix(g_ctx.mac_suffix); */

                /* Перезагрузить JDY-23 — он стартует с новыми параметрами */
                jdy23_reset();
                tag_platform_delay_ms(TAG_JDY23_RESET_DELAY_MS);

                g_ctx.params_changed = 0;
            } else {
                /* JDY-23 уже работает с актуальными параметрами.
                 * Ждём одного рекламного цикла (интервал 100 мс настроен при
                 * первичной AT-настройке → первый пакет уходит за <= 100 мс). */
                tag_platform_delay_ms(80);
            }

            /* Снять питание с JDY-23 */
            tag_platform_jdy23_power(0);

            state = TAG_APP_STATE_STOP_MODE;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_STOP_MODE:
        {
            /* Установить RTC будильник через TAG_WAKE_INTERVAL_SEC секунд */
            tag_platform_set_rtc_alarm(TAG_WAKE_INTERVAL_SEC);
            /* Войти в Stop mode — вернётся по пробуждению от RTC */
            tag_platform_enter_stop();

            /* После пробуждения — проверить счётчик */
            state = TAG_APP_STATE_CHECK_CYCLES;
            break;
        }

        default:
            state = TAG_APP_STATE_BOOT;
            break;
        }
    }
}
