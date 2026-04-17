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

/* Продолжительность одного временного слота в секундах (5 минут).
 * За один слот метка отправляет SLOT_DURATION / WAKE_INTERVAL = 150 пакетов. */
#define TAG_SLOT_DURATION_SEC  300U

/* Интервал пробуждения и рекламы в секундах */
#define TAG_WAKE_INTERVAL_SEC  2U

/* Количество циклов до смены параметров */
#define TAG_CYCLES_PER_SLOT  (TAG_SLOT_DURATION_SEC / TAG_WAKE_INTERVAL_SEC)

/* 128-битный секретный ключ региона (AES-128).
 * ЗАМЕНИТЬ на реальный ключ из server/keygen.py */
#define TAG_KEY  { \
    0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6, \
    0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C  \
}

/* Начальное значение unix_time, записывается при прошивке.
 * Обновлять при каждой прошивке новой единицы.
 * Значение ниже — заглушка (2026-01-01 00:00:00 UTC). */
#define TAG_INITIAL_UNIX_TIME  1767225600UL

/* UUID iBeacon (стандартный шаблон, заменить при необходимости) */
#define TAG_IBEACON_UUID  { \
    0xFD, 0xA5, 0x06, 0x93, 0xA4, 0xE2, 0x4F, 0xB1, \
    0xAF, 0xCF, 0xC6, 0xEB, 0x07, 0x64, 0x78, 0x25  \
}

/* TX мощность (дБм): -20, -16, -12, -8, -4, 0, +4 */
#define TAG_TX_POWER_DBM  0

/* Первые 3 байта MAC (OUI с locally administered bit).
 * Последние 3 байта вычисляются AES и меняются каждый слот. */
#define TAG_MAC_PREFIX  { 0xE5U, 0x00U, 0x00U }

/* Включить защиту от считывания через SWD (APPROTECT).
 * Установить 1 перед финальным производственным прошиванием. */
#define TAG_ENABLE_APPROTECT  0

#endif /* TAG_CONFIG_H */
