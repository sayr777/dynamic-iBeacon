#ifndef TAG_CONFIG_H
#define TAG_CONFIG_H

/* -----------------------------------------------------------------------
 * tag_config.example.h — шаблон конфигурации изделия.
 *
 * Скопировать как firmware/src/tag_config.h и заполнить.
 * НИКОГДА не коммитить tag_config.h с реальным ключом в репозиторий.
 * ----------------------------------------------------------------------- */

/* Статичный уникальный номер метки (0..65535, уникален в регионе) */
#define TAG_ID  1U

/* Продолжительность одного временного слота в секундах (5 минут) */
#define TAG_SLOT_DURATION_SEC  300U

/* Интервал пробуждения MCU в секундах (цикл передачи) */
#define TAG_WAKE_INTERVAL_SEC  2U

/* Количество циклов до смены параметров:
 * CYCLES_PER_SLOT = SLOT_DURATION_SEC / WAKE_INTERVAL_SEC = 150 */
#define TAG_CYCLES_PER_SLOT  (TAG_SLOT_DURATION_SEC / TAG_WAKE_INTERVAL_SEC)

/* 128-битный секретный ключ региона (AES-128).
 * ЗАМЕНИТЬ на реальный ключ из server/keygen.py */
#define TAG_KEY  { \
    0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6, \
    0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C  \
}

/* Начальное значение unix_time, которое записывается при прошивке.
 * После записи RTC ведёт отсчёт автономно.
 * Обновлять при каждой прошивке новой единицы или обслуживании.
 * Значение ниже — заглушка (2024-01-01 00:00:00 UTC). */
#define TAG_INITIAL_UNIX_TIME  1704067200UL

/* Задержка включения JDY-23 (мс): время от подачи питания до готовности */
#define TAG_JDY23_BOOT_DELAY_MS  50U

/* Задержка после AT+RST (мс): время перезагрузки JDY-23 */
#define TAG_JDY23_RESET_DELAY_MS  500U

/* UART baudrate для JDY-23 */
#define TAG_JDY23_BAUDRATE  9600U

/* Первые 3 байта MAC (OUI, locally administered bit установлен) */
#define TAG_MAC_BYTE0  0xE5U
#define TAG_MAC_BYTE1  0x00U
#define TAG_MAC_BYTE2  0x00U

#endif /* TAG_CONFIG_H */
