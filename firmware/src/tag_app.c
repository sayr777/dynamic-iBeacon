/*
 * tag_app.c — основная логика динамической BLE-метки на nRF52810.
 *
 * Цикл: каждые 2 с RTC будит nRF52810.
 * Если накопилось CYCLES_PER_SLOT циклов — вычислить новые Major/Minor/MAC.
 * Отправить один advertising event (~1 мс).
 * Уйти в deep sleep до следующего RTC-будильника.
 *
 * Средний ток: ~5 µА → ресурс батареи ER14505H-LD ~20 лет.
 */

#include "tag_app.h"
#include "tag_platform.h"
#include "beacon_id.h"
#include "tag_config.h"

/* ---- Контекст приложения ----------------------------------------------- */

static struct {
    uint32_t cycle_count;    /* циклов с момента последнего обновления */
    uint32_t slot;           /* текущий временной слот */
    uint16_t major;
    uint16_t minor;
    uint8_t  mac_suffix[3];  /* последние 3 байта MAC */
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

            /* Установить начальный слот из сохранённого unix_time */
            uint32_t unix_time  = tag_platform_get_unix_time();
            g_ctx.slot          = unix_time / TAG_SLOT_DURATION_SEC;
            g_ctx.cycle_count   = TAG_CYCLES_PER_SLOT; /* принудить обновление при старте */

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
                state = TAG_APP_STATE_ADVERTISE;
            }
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_UPDATE_PARAMS:
        {
            g_ctx.cycle_count = 0;
            g_ctx.slot++;

            /* Вычислить Major/Minor/MAC для нового слота */
            beacon_id_compute(
                g_key,
                (uint16_t)TAG_ID,
                g_ctx.slot,
                &g_ctx.major,
                &g_ctx.minor,
                g_ctx.mac_suffix
            );

            /* Обновить advertising payload и random MAC в BLE-стеке */
            tag_platform_ble_set_adv_params(
                g_ctx.major,
                g_ctx.minor,
                g_ctx.mac_suffix
            );

            state = TAG_APP_STATE_ADVERTISE;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_ADVERTISE:
        {
            /* Запустить один advertising event.
             * Функция блокирует до завершения события (~1 мс на 3 каналах).
             * nRF52810 потребляет ~5.3 мА в течение этого времени. */
            tag_platform_ble_advertise_once();

            state = TAG_APP_STATE_SLEEP;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_SLEEP:
        {
            /* Установить RTC будильник и уйти в deep sleep.
             * nRF52810 потребляет ~1.5 µА в System OFF с RTC. */
            tag_platform_set_rtc_wakeup(TAG_WAKE_INTERVAL_SEC);
            tag_platform_enter_deep_sleep();

            /* Управление вернётся сюда после пробуждения */
            state = TAG_APP_STATE_CHECK_CYCLES;
            break;
        }

        default:
            state = TAG_APP_STATE_BOOT;
            break;
        }
    }
}
