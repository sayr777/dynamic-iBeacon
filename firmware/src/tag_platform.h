#ifndef TAG_PLATFORM_H
#define TAG_PLATFORM_H

#include <stdint.h>

/* -----------------------------------------------------------------------
 * tag_platform — платформенные абстракции для nRF52810.
 * Реализация: tag_platform_nrf52810.c
 * ----------------------------------------------------------------------- */

/* Инициализация: тактирование, RTC, SoftDevice S112, BLE advertising */
void tag_platform_init(void);

/* Получить текущий unix_time из backup-регистра (сохранён при прошивке) */
uint32_t tag_platform_get_unix_time(void);

/* Установить unix_time (вызывается при производственной калибровке) */
void tag_platform_set_unix_time(uint32_t unix_time);

/* Обновить advertising payload (iBeacon Major/Minor) и random MAC.
 * mac_suffix[3] — последние 3 байта MAC-адреса. */
void tag_platform_ble_set_adv_params(uint16_t      major,
                                     uint16_t      minor,
                                     const uint8_t mac_suffix[3]);

/* Выполнить один advertising event (3 BLE-канала, ~1 мс).
 * Блокирует до завершения события. */
void tag_platform_ble_advertise_once(void);

/* Установить RTC wakeup через N секунд */
void tag_platform_set_rtc_wakeup(uint32_t seconds);

/* Войти в deep sleep (System OFF с RTC ~1.5 µА).
 * Возвращается после пробуждения по RTC. */
void tag_platform_enter_deep_sleep(void);

#endif /* TAG_PLATFORM_H */
