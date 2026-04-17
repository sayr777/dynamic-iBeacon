/*
 * tag_app.c — основная логика динамической BLE-метки на nRF52832.
 *
 * Дневной цикл (каждые TAG_WAKE_INTERVAL_SEC = 2 с):
 *   CHECK_SLOT → (слот изменился) → UPDATE_PARAMS → ADVERTISE → SLEEP
 *               → (слот не изменился)             → ADVERTISE → SLEEP
 *
 * Ночной цикл (TAG_NIGHT_MODE_ENABLE=1, часы TAG_NIGHT_START..END):
 *   Тот же FSM, но SLEEP использует TAG_NIGHT_WAKE_INTERVAL_SEC (60 с).
 *   Параметры обновляются по-прежнему раз в 5 мин — детекция по unix_time.
 *
 * Средний ток:
 *   День (17 ч):  ~5.2 µА
 *   Ночь  (7 ч):  ~2.5 µА  (TX-вклад исчезает при 60 с интервале)
 *   Сутки:        ~4.5 µА  (-15% vs без ночного режима)
 */

#include "tag_app.h"
#include "tag_platform.h"
#include "beacon_id.h"
#include "tag_config.h"

/* ---- Контекст приложения ----------------------------------------------- */

static struct {
    uint32_t last_slot;     /* последний слот, для которого вычислены параметры */
    uint16_t major;
    uint16_t minor;
    uint8_t  mac_suffix[3];
} g_ctx;

static const uint8_t g_key[16] = TAG_KEY;

/* ---- Вспомогательные функции ------------------------------------------- */

/*
 * Текущий слот на основе unix_time.
 * Слот меняется каждые TAG_SLOT_DURATION_SEC секунд (300 с = 5 мин).
 * Детекция по времени, а не по счётчику циклов — корректно работает
 * при любом интервале пробуждения (2 с днём или 60 с ночью).
 */
static uint32_t current_slot(void)
{
    return tag_platform_get_unix_time() / TAG_SLOT_DURATION_SEC;
}

/*
 * Проверить: сейчас ночное время?
 *
 * Алгоритм:
 *  1. Перевести unix_time в секунды суток по местному времени:
 *       local_sec = (unix_time + TAG_TIMEZONE_OFFSET_SEC) % 86400
 *  2. Если ночной диапазон переходит полночь (START > END, напр. 23:00-06:00):
 *       is_night = (local_sec >= START) || (local_sec < END)
 *  3. Иначе (START < END, напр. 01:00-04:00):
 *       is_night = (local_sec >= START) && (local_sec < END)
 */
static bool is_night(void)
{
#if TAG_NIGHT_MODE_ENABLE
    uint32_t unix_time = tag_platform_get_unix_time();
    uint32_t local_sec = (unix_time + TAG_TIMEZONE_OFFSET_SEC) % 86400U;

    if (TAG_NIGHT_START_SEC > TAG_NIGHT_END_SEC) {
        /* Диапазон переходит полночь: 23:00 → 06:00 */
        return (local_sec >= TAG_NIGHT_START_SEC || local_sec < TAG_NIGHT_END_SEC);
    } else {
        /* Диапазон внутри суток: e.g. 01:00 → 04:00 */
        return (local_sec >= TAG_NIGHT_START_SEC && local_sec < TAG_NIGHT_END_SEC);
    }
#else
    return false;
#endif
}

/* Вернуть интервал сна в секундах в зависимости от времени суток */
static uint32_t sleep_interval_sec(void)
{
    return is_night() ? TAG_NIGHT_WAKE_INTERVAL_SEC : TAG_WAKE_INTERVAL_SEC;
}

/* ---- Основной цикл ------------------------------------------------------ */

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

            /*
             * Вычислить начальный слот из сохранённого unix_time.
             * last_slot = текущий слот − 1: принудит UPDATE_PARAMS
             * при первом же входе в CHECK_SLOT.
             */
            uint32_t slot = current_slot();
            g_ctx.last_slot = (slot > 0) ? (slot - 1) : 0;

            state = TAG_APP_STATE_CHECK_SLOT;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_CHECK_SLOT:
        {
            /*
             * Сравниваем слот по текущему unix_time с последним обработанным.
             * Работает правильно при любом интервале пробуждения:
             *   2 с → слот меняется каждые 150 пробуждений;
             *   60 с → слот меняется каждые 5 пробуждений.
             */
            if (current_slot() != g_ctx.last_slot) {
                state = TAG_APP_STATE_UPDATE_PARAMS;
            } else {
                state = TAG_APP_STATE_ADVERTISE;
            }
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_UPDATE_PARAMS:
        {
            uint32_t slot = current_slot();
            g_ctx.last_slot = slot;

            /* Вычислить Major/Minor/MAC для нового слота */
            beacon_id_compute(
                g_key,
                (uint16_t)TAG_ID,
                slot,
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
            /*
             * Запустить один advertising event (3 канала: 37, 38, 39).
             * Блокирует ~1 мс, потребление ~5.3 мА.
             */
            tag_platform_ble_advertise_once();

            state = TAG_APP_STATE_SLEEP;
            break;
        }

        /* ----------------------------------------------------------------- */
        case TAG_APP_STATE_SLEEP:
        {
            /*
             * Выбрать интервал сна: 2 с (день) или 60 с (ночь).
             * В ночном режиме TX-вклад в средний ток падает с 2.65 µА до ~0.09 µА.
             *
             * Ночные часы: TAG_NIGHT_START_SEC..TAG_NIGHT_END_SEC (местное время).
             * Параметры iBeacon обновляются по unix_time — корректно при любом
             * интервале пробуждения.
             */
            tag_platform_set_rtc_wakeup(sleep_interval_sec());
            tag_platform_enter_deep_sleep();

            /* Управление вернётся сюда после пробуждения из System OFF */
            state = TAG_APP_STATE_CHECK_SLOT;
            break;
        }

        default:
            state = TAG_APP_STATE_BOOT;
            break;
        }
    }
}
