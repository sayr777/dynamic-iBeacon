#ifndef JDY23_AT_H
#define JDY23_AT_H

#include <stdint.h>
#include <stdbool.h>

/* -----------------------------------------------------------------------
 * jdy23_at — минимальный драйвер AT-команд для JDY-23.
 * Использует платформенные функции uart_send_str() / uart_wait_ms().
 * ----------------------------------------------------------------------- */

/* Инициализация: проверить связь с модулем (AT+VER) */
bool jdy23_init(void);

/* Установить Major (16-битное значение) */
bool jdy23_set_major(uint16_t major);

/* Установить Minor (16-битное значение) */
bool jdy23_set_minor(uint16_t minor);

/* Установить суффикс MAC-адреса (3 байта).
 * Поддерживается не всеми ревизиями JDY-23 — см. limitations-and-risks.md */
bool jdy23_set_mac_suffix(const uint8_t mac_suffix[3]);

/* Перезагрузить модуль (AT+RST).
 * После перезагрузки модуль начинает рекламу с новыми параметрами. */
void jdy23_reset(void);

/* Перевести модуль в режим сна (AT+SLEEP).
 * Альтернатива: отключение питания через GPIO. */
void jdy23_sleep(void);

#endif /* JDY23_AT_H */
