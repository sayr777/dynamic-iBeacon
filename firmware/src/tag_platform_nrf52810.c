/*
 * tag_platform_nrf52810.c — реализация платформенных функций для nRF52810.
 *
 * SDK:    nRF5 SDK 17.1.x
 * Stack:  SoftDevice S112 (только Broadcaster — приёмник не нужен)
 * Модуль: EBYTE E73-2G4M04S1A
 *
 * Ключевые особенности:
 *  - RTC1 на LFXO 32768 Гц — пробуждение раз в 2 с из deep sleep
 *  - advertising_once(): sd_ble_gap_adv_start() + APP_TIMER + sd_ble_gap_adv_stop()
 *  - random MAC обновляется через sd_ble_gap_address_set() перед каждым слотом
 *  - unix_time хранится в GPREGRET2 (не теряется при System OFF с RTC)
 */

#include "tag_platform.h"
#include "tag_config.h"

/* nRF5 SDK headers */
#include "nrf.h"
#include "nrf_sdh.h"
#include "nrf_sdh_ble.h"
#include "nrf_ble_qwr.h"
#include "ble_advdata.h"
#include "ble_gap.h"
#include "nrf_drv_rtc.h"
#include "nrf_drv_clock.h"
#include "app_error.h"
#include "app_timer.h"

/* ---- Константы --------------------------------------------------------- */

/* iBeacon Company ID */
#define IBEACON_COMPANY_ID      0x004CU
/* iBeacon тип и длина */
#define IBEACON_BEACON_TYPE     0x02U
#define IBEACON_BEACON_LEN      0x15U
/* Расстояние калибровки RSSI (на 1 м, 0 dBm TX) */
#define IBEACON_MEASURED_RSSI   (-65)

/* RTC prescaler для ~1 с (32768 / 32 = 1024 тиков/с) */
#define RTC_PRESCALER           31U

/* ---- Состояние --------------------------------------------------------- */

static const nrf_drv_rtc_t m_rtc = NRF_DRV_RTC_INSTANCE(1);

static volatile bool m_adv_done       = false;
static volatile bool m_rtc_wakeup     = false;
static uint32_t      m_wakeup_ticks   = 0;

/* Текущие параметры рекламы */
static uint16_t m_major      = 0x0001;
static uint16_t m_minor      = 0x0001;
static uint8_t  m_mac_sfx[3] = {0xE5, 0x00, 0x00};

/* ---- UUID -------------------------------------------------------------- */

static const uint8_t m_ibeacon_uuid[16] = TAG_IBEACON_UUID;

/* ---- BLE advertising data ---------------------------------------------- */

static void adv_data_build(uint8_t *buf, uint8_t *len)
{
    /*
     * iBeacon Manufacturer Specific Data:
     *   Company ID (2) + Beacon type (1) + Beacon len (1) +
     *   UUID (16) + Major (2) + Minor (2) + RSSI (1) = 25 bytes
     */
    buf[0] = 0x1A;                              /* длина AD-поля (26 - 1) */
    buf[1] = BLE_GAP_AD_TYPE_MANUFACTURER_SPECIFIC_DATA;
    buf[2] = (uint8_t)(IBEACON_COMPANY_ID & 0xFF);
    buf[3] = (uint8_t)(IBEACON_COMPANY_ID >> 8);
    buf[4] = IBEACON_BEACON_TYPE;
    buf[5] = IBEACON_BEACON_LEN;
    for (int i = 0; i < 16; i++) buf[6 + i] = m_ibeacon_uuid[i];
    buf[22] = (uint8_t)(m_major >> 8);
    buf[23] = (uint8_t)(m_major & 0xFF);
    buf[24] = (uint8_t)(m_minor >> 8);
    buf[25] = (uint8_t)(m_minor & 0xFF);
    buf[26] = (uint8_t)IBEACON_MEASURED_RSSI;
    *len = 27;
}

/* ---- Обработчики событий ----------------------------------------------- */

static void ble_evt_handler(ble_evt_t const *p_ble_evt, void *p_context)
{
    if (p_ble_evt->header.evt_id == BLE_GAP_EVT_ADV_SET_TERMINATED) {
        m_adv_done = true;
    }
}

NRF_SDH_BLE_OBSERVER(m_ble_observer, 3, ble_evt_handler, NULL);

static void rtc_handler(nrf_drv_rtc_int_type_t int_type)
{
    if (int_type == NRF_DRV_RTC_INT_COMPARE0) {
        m_rtc_wakeup = true;
        /* Обновить unix_time в GPREGRET2 */
        uint32_t t = tag_platform_get_unix_time() + TAG_WAKE_INTERVAL_SEC;
        tag_platform_set_unix_time(t);
    }
}

/* ---- Инициализация ----------------------------------------------------- */

static void clock_init(void)
{
    ret_code_t err;
    err = nrf_drv_clock_init();
    APP_ERROR_CHECK(err);
    nrf_drv_clock_lfclk_request(NULL);
    while (!nrf_drv_clock_lfclk_is_running()) {}
}

static void rtc_init(void)
{
    ret_code_t err;
    nrf_drv_rtc_config_t cfg = NRF_DRV_RTC_DEFAULT_CONFIG;
    cfg.prescaler = RTC_PRESCALER;          /* 1024 тиков/с */
    err = nrf_drv_rtc_init(&m_rtc, &cfg, rtc_handler);
    APP_ERROR_CHECK(err);
    nrf_drv_rtc_enable(&m_rtc);
}

static void softdevice_init(void)
{
    ret_code_t err;
    err = nrf_sdh_enable_request();
    APP_ERROR_CHECK(err);

    uint32_t ram_start = 0;
    err = nrf_sdh_ble_default_cfg_set(1, &ram_start);
    APP_ERROR_CHECK(err);

    err = nrf_sdh_ble_enable(&ram_start);
    APP_ERROR_CHECK(err);

    /* TX мощность */
    err = sd_ble_gap_tx_power_set(BLE_GAP_TX_POWER_ROLE_ADV, 0, TAG_TX_POWER_DBM);
    APP_ERROR_CHECK(err);
}

/* ---- Public API -------------------------------------------------------- */

void tag_platform_init(void)
{
    clock_init();
    rtc_init();
    softdevice_init();

    /* Установить начальное unix_time если GPREGRET2 = 0 (первый запуск) */
    if (tag_platform_get_unix_time() == 0) {
        tag_platform_set_unix_time(TAG_INITIAL_UNIX_TIME);
    }

    /* Включить APPROTECT если задано в конфиге */
#if TAG_ENABLE_APPROTECT
    if (NRF_UICR->APPROTECT != 0xFFFFFF00UL) {
        NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Wen;
        NRF_UICR->APPROTECT = 0xFFFFFF00UL;
        NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Ren;
        NVIC_SystemReset();
    }
#endif
}

uint32_t tag_platform_get_unix_time(void)
{
    /* GPREGRET2 (32-бит) сохраняется при System OFF */
    return NRF_POWER->GPREGRET2;
}

void tag_platform_set_unix_time(uint32_t unix_time)
{
    NRF_POWER->GPREGRET2 = unix_time;
}

void tag_platform_ble_set_adv_params(uint16_t      major,
                                     uint16_t      minor,
                                     const uint8_t mac_suffix[3])
{
    m_major     = major;
    m_minor     = minor;
    m_mac_sfx[0] = mac_suffix[0];
    m_mac_sfx[1] = mac_suffix[1];
    m_mac_sfx[2] = mac_suffix[2];

    /* Обновить random MAC: prefix E5:00:00 + suffix из AES */
    ble_gap_addr_t addr;
    addr.addr_type = BLE_GAP_ADDR_TYPE_RANDOM_STATIC;
    addr.addr[5] = TAG_MAC_PREFIX[0];
    addr.addr[4] = TAG_MAC_PREFIX[1];
    addr.addr[3] = TAG_MAC_PREFIX[2];
    addr.addr[2] = mac_suffix[0];
    addr.addr[1] = mac_suffix[1];
    addr.addr[0] = mac_suffix[2];
    /* Установить два старших бита для RANDOM_STATIC (требование BLE spec) */
    addr.addr[5] |= 0xC0;

    ret_code_t err = sd_ble_gap_address_set(&addr);
    APP_ERROR_CHECK(err);
}

void tag_platform_ble_advertise_once(void)
{
    uint8_t adv_buf[31];
    uint8_t adv_len = 0;
    adv_data_build(adv_buf, &adv_len);

    ble_gap_adv_data_t adv_data = {
        .adv_data.p_data = adv_buf,
        .adv_data.len    = adv_len,
    };

    /* Один advertising event, все три канала (37, 38, 39) */
    ble_gap_adv_params_t adv_params = {
        .properties.type = BLE_GAP_ADV_TYPE_NONCONNECTABLE_NONSCANNABLE_UNDIRECTED,
        .p_peer_addr     = NULL,
        .filter_policy   = BLE_GAP_ADV_FP_ANY,
        .interval        = MSEC_TO_UNITS(TAG_WAKE_INTERVAL_SEC * 1000, UNIT_0_625_MS),
        .duration        = BLE_GAP_ADV_TIMEOUT_GENERAL_UNLIMITED,
        .max_adv_evts    = 1,   /* ровно один advertising event */
        .primary_phy     = BLE_GAP_PHY_1MBPS,
        .channel_mask    = {0, 0, 0, 0, 0}, /* все каналы */
    };

    uint8_t adv_handle = BLE_GAP_ADV_SET_HANDLE_NOT_SET;
    m_adv_done = false;

    ret_code_t err = sd_ble_gap_adv_set_configure(&adv_handle, &adv_data, &adv_params);
    APP_ERROR_CHECK(err);

    err = sd_ble_gap_adv_start(adv_handle, 1);
    APP_ERROR_CHECK(err);

    /* Ждать завершения события (BLE_GAP_EVT_ADV_SET_TERMINATED) */
    while (!m_adv_done) {
        sd_app_evt_wait();
    }
}

void tag_platform_set_rtc_wakeup(uint32_t seconds)
{
    /* Тиков = seconds × 1024 (при PRESCALER=31, 32768/(31+1) = 1024 Гц) */
    m_wakeup_ticks = nrf_drv_rtc_counter_get(&m_rtc) + seconds * 1024;
    ret_code_t err = nrf_drv_rtc_cc_set(&m_rtc, 0, m_wakeup_ticks, true);
    APP_ERROR_CHECK(err);
}

void tag_platform_enter_deep_sleep(void)
{
    m_rtc_wakeup = false;

    /* Отключить SoftDevice для минимального тока в System OFF */
    ret_code_t err = sd_power_system_off();
    APP_ERROR_CHECK(err);

    /* sd_power_system_off() не возвращается — при пробуждении по RTC
     * nRF52810 делает полный холодный старт.
     * tag_platform_enter_deep_sleep() фактически никогда не возвращается. */
    while (1) { __WFE(); }
}
