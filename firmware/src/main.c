/*
 * main.c — точка входа прошивки динамической BLE-метки.
 *
 * Целевая платформа: nRF52810 (EBYTE E73-2G4M04S1A)
 * SDK:               nRF5 SDK 17.1.x + SoftDevice S112
 *
 * Логика приложения: tag_app.c
 * Платформа:         tag_platform_nrf52810.c
 * Алгоритм:          beacon_id.c (AES-128)
 */

#include "tag_app.h"

int main(void)
{
    /* tag_app_run_forever() выполняет всю инициализацию и не возвращается */
    tag_app_run_forever();

    /* Никогда не достигается */
    while (1) {}
    return 0;
}
