/*
 * tag_platform_stm32l0.c — реализация платформенных функций для STM32L031.
 *
 * Использует STM32 LL (Low Layer) драйверы для минимального Flash-overhead.
 * Собирать с STM32CubeIDE: добавить LL-библиотеки в проект (не HAL).
 *
 * Пины:
 *   PA9  — USART1 TX → JDY-23 RX
 *   PA10 — USART1 RX ← JDY-23 TX
 *   PA0  — GPIO выход → затвор P-MOS ключа JDY-23 VCC
 *           (LOW = JDY-23 включён, HIGH = выключён для P-MOS)
 *
 * RTC: LSE 32768 Гц, формат BCD, будильник Alarm A.
 */

#include "tag_platform.h"
#include "tag_config.h"

/* STM32L0 LL headers — подключаются через STM32CubeIDE или вручную */
#include "stm32l0xx_ll_rcc.h"
#include "stm32l0xx_ll_system.h"
#include "stm32l0xx_ll_bus.h"
#include "stm32l0xx_ll_gpio.h"
#include "stm32l0xx_ll_usart.h"
#include "stm32l0xx_ll_rtc.h"
#include "stm32l0xx_ll_pwr.h"
#include "stm32l0xx_ll_utils.h"
#include "stm32l0xx_ll_exti.h"

/* ---- Вспомогательные функции ------------------------------------------ */

static void system_clock_config(void)
{
    /* MSI 2.097 МГц — минимальный активный ток, достаточен для UART 9600 */
    LL_RCC_MSI_Enable();
    while (!LL_RCC_MSI_IsReady()) {}
    LL_RCC_SetSysClkSource(LL_RCC_SYS_CLKSOURCE_MSI);
    LL_RCC_MSI_SetRange(LL_RCC_MSIRANGE_5); /* 2.097 МГц */
    LL_RCC_SetAHBPrescaler(LL_RCC_SYSCLK_DIV_1);
    LL_RCC_SetAPB1Prescaler(LL_RCC_APB1_DIV_1);
    LL_RCC_SetAPB2Prescaler(LL_RCC_APB2_DIV_1);
    /* SysTick для delay_ms */
    LL_Init1msTick(2097000);
    LL_SetSystemCoreClock(2097000);
}

static void gpio_init(void)
{
    LL_IOP_GRP1_EnableClock(LL_IOP_GRP1_PERIPH_GPIOA);

    /* PA0: GPIO output — управление питанием JDY-23 (через P-MOS)
     * Начальное состояние HIGH = JDY-23 выключен (P-MOS закрыт) */
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_0, LL_GPIO_MODE_OUTPUT);
    LL_GPIO_SetPinOutputType(GPIOA, LL_GPIO_PIN_0, LL_GPIO_OUTPUT_PUSHPULL);
    LL_GPIO_SetPinSpeed(GPIOA, LL_GPIO_PIN_0, LL_GPIO_SPEED_FREQ_LOW);
    LL_GPIO_SetOutputPin(GPIOA, LL_GPIO_PIN_0); /* HIGH = выключен */

    /* PA9: USART1 TX */
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_9, LL_GPIO_MODE_ALTERNATE);
    LL_GPIO_SetAFPin_8_15(GPIOA, LL_GPIO_PIN_9, LL_GPIO_AF_4);

    /* PA10: USART1 RX */
    LL_GPIO_SetPinMode(GPIOA, LL_GPIO_PIN_10, LL_GPIO_MODE_ALTERNATE);
    LL_GPIO_SetAFPin_8_15(GPIOA, LL_GPIO_PIN_10, LL_GPIO_AF_4);
}

static void usart_init(void)
{
    LL_APB2_GRP1_EnableClock(LL_APB2_GRP1_PERIPH_USART1);
    LL_USART_SetBaudRate(USART1, 2097000, LL_USART_OVERSAMPLING_16,
                         TAG_JDY23_BAUDRATE);
    LL_USART_SetDataWidth(USART1, LL_USART_DATAWIDTH_8B);
    LL_USART_SetStopBitsLength(USART1, LL_USART_STOPBITS_1);
    LL_USART_SetParity(USART1, LL_USART_PARITY_NONE);
    LL_USART_SetTransferDirection(USART1, LL_USART_DIRECTION_TX_RX);
    LL_USART_Enable(USART1);
}

static void rtc_init(uint32_t initial_unix_time)
{
    /* Включить LSE (внешний кварц 32768 Гц) */
    LL_APB1_GRP1_EnableClock(LL_APB1_GRP1_PERIPH_PWR);
    LL_PWR_EnableBkUpAccess();
    LL_RCC_LSE_Enable();
    while (!LL_RCC_LSE_IsReady()) {}
    LL_RCC_SetRTCClockSource(LL_RCC_RTC_CLKSOURCE_LSE);
    LL_RCC_EnableRTC();

    LL_RTC_DisableWriteProtection(RTC);
    LL_RTC_EnterInitMode(RTC);

    /* Делитель: 32768 / (127+1) / (255+1) = 1 Гц */
    LL_RTC_SetAsynchPrescaler(RTC, 127);
    LL_RTC_SetSynchPrescaler(RTC, 255);

    /* Установить начальное время (BCD конвертация упрощена) */
    /* Для production: записать корректный BCD из initial_unix_time */
    /* Упрощённо: хранить unix_time в backup-регистрах и использовать RTC
     * только для генерации периодических прерываний через Alarm A */
    LL_RTC_BKP_SetRegister(RTC, LL_RTC_BKP_DR0, initial_unix_time & 0xFFFF);
    LL_RTC_BKP_SetRegister(RTC, LL_RTC_BKP_DR1, initial_unix_time >> 16);

    LL_RTC_ExitInitMode(RTC);
    LL_RTC_EnableWriteProtection(RTC);
}

/* ---- Public API -------------------------------------------------------- */

void tag_platform_init(void)
{
    LL_APB2_GRP1_EnableClock(LL_APB2_GRP1_PERIPH_SYSCFG);
    LL_APB1_GRP1_EnableClock(LL_APB1_GRP1_PERIPH_PWR);

    system_clock_config();
    gpio_init();
    usart_init();
    rtc_init(TAG_INITIAL_UNIX_TIME);
}

void tag_platform_delay_ms(uint32_t ms)
{
    LL_mDelay(ms);
}

void tag_platform_uart_send(const char *data, uint16_t len)
{
    uint16_t i;
    for (i = 0; i < len; i++) {
        while (!LL_USART_IsActiveFlag_TXE(USART1)) {}
        LL_USART_TransmitData8(USART1, (uint8_t)data[i]);
    }
    while (!LL_USART_IsActiveFlag_TC(USART1)) {}
}

void tag_platform_jdy23_power(uint8_t state)
{
    if (state) {
        /* P-MOS: LOW на затворе = открыт = JDY-23 включён */
        LL_GPIO_ResetOutputPin(GPIOA, LL_GPIO_PIN_0);
    } else {
        /* HIGH на затворе = закрыт = JDY-23 выключён */
        LL_GPIO_SetOutputPin(GPIOA, LL_GPIO_PIN_0);
    }
}

void tag_platform_set_rtc_alarm(uint32_t seconds)
{
    /* Простая реализация через RTC Wakeup Timer (WUTR).
     * WUTR с ck_spre (1 Гц): просыпаться через 'seconds' секунд. */
    LL_RTC_DisableWriteProtection(RTC);

    /* Выключить Wakeup Timer */
    LL_RTC_WAKEUP_Disable(RTC);
    while (!LL_RTC_IsActiveFlag_WUTW(RTC)) {}

    /* Настроить на seconds секунд */
    LL_RTC_WAKEUP_SetAutoReload(RTC, seconds - 1);
    LL_RTC_WAKEUP_SetClock(RTC, LL_RTC_WAKEUPCLOCK_CKSPRE); /* 1 Гц */

    /* Включить прерывание */
    LL_RTC_EnableIT_WUT(RTC);
    LL_EXTI_EnableIT_0_31(LL_EXTI_LINE_20); /* EXTI20 = RTC Wakeup */
    LL_EXTI_EnableRisingTrig_0_31(LL_EXTI_LINE_20);

    /* Включить Wakeup Timer */
    LL_RTC_WAKEUP_Enable(RTC);
    LL_RTC_ClearFlag_WUT(RTC);

    LL_RTC_EnableWriteProtection(RTC);
}

uint32_t tag_platform_get_unix_time(void)
{
    /* Читать из backup-регистров RTC (обновляются каждую секунду в ISR) */
    uint32_t lo = LL_RTC_BKP_GetRegister(RTC, LL_RTC_BKP_DR0);
    uint32_t hi = LL_RTC_BKP_GetRegister(RTC, LL_RTC_BKP_DR1);
    return (hi << 16) | lo;
}

void tag_platform_set_unix_time(uint32_t unix_time)
{
    LL_APB1_GRP1_EnableClock(LL_APB1_GRP1_PERIPH_PWR);
    LL_PWR_EnableBkUpAccess();
    LL_RTC_BKP_SetRegister(RTC, LL_RTC_BKP_DR0, unix_time & 0xFFFF);
    LL_RTC_BKP_SetRegister(RTC, LL_RTC_BKP_DR1, unix_time >> 16);
}

void tag_platform_enter_stop(void)
{
    /* Выключить HSI и MSI (RTC на LSE продолжает работать) */
    LL_PWR_SetRegulVoltageScaling(LL_PWR_REGU_VOLTAGE_SCALE3);

    /* Войти в Stop mode с Low Power Regulator */
    LL_PWR_EnableLowPowerRunMode();
    LL_LPM_EnableDeepSleep();
    __WFI(); /* Wait For Interrupt — просыпается по EXTI20 (RTC Wakeup) */

    /* После пробуждения: восстановить тактирование */
    LL_LPM_EnableSleep();
    system_clock_config();
    LL_RTC_ClearFlag_WUT(RTC);
    LL_EXTI_ClearFlag_0_31(LL_EXTI_LINE_20);
}

/* ---- Обработчик прерывания RTC Wakeup ---------------------------------- */

void RTC_IRQHandler(void)
{
    /* Инкрементировать unix_time в backup-регистрах */
    uint32_t t = tag_platform_get_unix_time();
    t += TAG_WAKE_INTERVAL_SEC;
    tag_platform_set_unix_time(t);

    LL_RTC_ClearFlag_WUT(RTC);
    LL_EXTI_ClearFlag_0_31(LL_EXTI_LINE_20);
}
