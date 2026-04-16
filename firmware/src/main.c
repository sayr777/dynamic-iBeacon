/*
 * main.c — точка входа прошивки динамической BLE-метки.
 *
 * Целевая платформа: STM32L031F6P6 (TSSOP-20)
 * Инструментарий:    STM32CubeIDE или PlatformIO + STM32duino
 *
 * Логика приложения вынесена в tag_app.c.
 * Платформенные функции реализованы в tag_platform_stm32l0.c.
 */

#include "tag_app.h"

int main(void)
{
    /* tag_app_run_forever выполняет всю инициализацию и не возвращается */
    tag_app_run_forever();

    /* Никогда не достигается */
    while (1) {}
    return 0;
}
