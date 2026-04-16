#ifndef TAG_PLATFORM_H
#define TAG_PLATFORM_H

#include <stdint.h>

/* -----------------------------------------------------------------------
 * tag_platform — платформенные абстракции.
 * Реализация для STM32L0: tag_platform_stm32l0.c
 * ----------------------------------------------------------------------- */

/* Инициализация всех периферийных устройств */
void tag_platform_init(void);

/* Задержка в миллисекундах (активное ожидание или таймер) */
void tag_platform_delay_ms(uint32_t ms);

/* Отправить байты через UART (к JDY-23) */
void tag_platform_uart_send(const char *data, uint16_t len);

/* Управление питанием JDY-23 через GPIO:
 * state = 1 → включить (GPIO_JDY_PWR = HIGH → P-MOS открыт → JDY-23 VCC)
 * state = 0 → выключить */
void tag_platform_jdy23_power(uint8_t state);

/* Установить RTC будильник через N секунд от текущего момента */
void tag_platform_set_rtc_alarm(uint32_t seconds);

/* Получить текущее unix_time из RTC */
uint32_t tag_platform_get_unix_time(void);

/* Установить unix_time в RTC (вызывается при производственной калибровке) */
void tag_platform_set_unix_time(uint32_t unix_time);

/* Войти в Stop mode (просыпается по RTC alarm или EXTI).
 * Функция возвращает управление после пробуждения. */
void tag_platform_enter_stop(void);

#endif /* TAG_PLATFORM_H */
