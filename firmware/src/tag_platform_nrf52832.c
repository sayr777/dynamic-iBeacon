/*
 * tag_platform_nrf52832.c — реализация платформенных функций для nRF52832.
 *
 * SDK:    nRF5 SDK 17.1.x
 * Stack:  SoftDevice S112 v7.3.0 (только Broadcaster — приёмник не нужен)
 * Модуль: YJ-16013 (nRF52832, 512KB Flash / 64KB RAM)
 *
 * Ключевые особенности:
 *  - RTC1 на LFXO 32768 Гц — пробуждение раз в 2 с из deep sleep (System OFF)
 *  - advertise_once(): sd_ble_gap_adv_start(max_adv_evts=1), ждёт BLE_GAP_EVT_ADV_SET_TERMINATED
 *  - random MAC обновляется через sd_ble_gap_address_set() перед каждым слотом
 *  - unix_time хранится в NRF_POWER->GPREGRET2 (32-бит, сохраняется при System OFF + RTC)
 *
 * Отличия от nRF52810 на уровне кода:
 *  - Нет отличий — S112 API идентичен на обоих чипах.
 *  - Board target в Makefile: PCA10040 (нRF52832), не PCA10040E (nRF52810).
 *  - Линкер-скрипт: nrf52832_xxaa.ld (512KB Flash / 64KB RAM).
 *  - nRF52832 имеет пин RESET (P0.21 по умолчанию) — используется при SWD отладке.
 *
 * Makefile target (nRF5 SDK):
 *   TARGETS   = nrf52832_xxaa
 *   BOARD     = PCA10040
 *   SOFTDEVICE = S112
 */

#include "tag_platform.h"
#include "tag_config.h"

/* nRF5 SDK headers */
#include "nrf.h"
#include "nrf_sdh.h"
#include "nrf_sdh_ble.h"
#include "ble_advdata.h"
#include "ble_gap.h"
#include "nrf_drv_rtc.h"
#include "nrf_drv_clock.h"
#include "app_error.h"

/* ---- Константы --------------------------------------------------------- */

/* iBeacon Company ID (Apple) */
#define IBEACON_COMPANY_ID      0x004CU
/* iBeacon subtype и длина payload */
#define IBEACON_BEACON_TYPE     0x02U
#define IBEACON_BEACON_LEN      0x15U
/* Откалиброванный RSSI на расстоянии 1 м при 0 dBm TX */
#define IBEACON_MEASURED_RSSI   (-65)

/*
 * RTC prescaler.
 * f_RTC = 32768 / (PRESCALER + 1) = 32768 / 32 = 1024 Гц.
 * Один тик = ~977 мкс. Для 2 с wakeup: 2048 тиков.
 */
#define RTC_PRESCALER           31U
#define RTC_TICKS_PER_SEC       1024U

/* ---- Состояние --------------------------------------------------------- */

static const nrf_drv_rtc_t m_rtc = NRF_DRV_RTC_INSTANCE(1);

static volatile bool m_adv_done   = false;
static volatile bool m_rtc_wakeup = false;

/* Текущие параметры iBeacon-пакета */
static uint16_t m_major      = 0x0001;
static uint16_t m_minor      = 0x0001;
static uint8_t  m_mac_sfx[3] = {0xE5, 0x00, 0x01};

/* UUID из tag_config.h */
static const uint8_t m_ibeacon_uuid[16] = TAG_IBEACON_UUID;

/* ---- Формирование iBeacon-пакета --------------------------------------- */

/*
 * Формат iBeacon Manufacturer Specific Data (25 байт payload):
 *   [0]    0x1A  — длина AD-элемента (26 - 1)
 *   [1]    0xFF  — тип: Manufacturer Specific Data
 *   [2..3] 0x4C 0x00 — Apple Company ID (little-endian)
 *   [4]    0x02  — Beacon Type
 *   [5]    0x15  — Beacon Length (21 байт)
 *   [6..21] UUID (16 байт, big-endian)
 *   [22..23] Major (big-endian)
 *   [24..25] Minor (big-endian)
 *   [26]   RSSI @ 1m
 */
static void adv_data_build(uint8_t *buf, uint8_t *len)
{
    buf[0]  = 0x1A;
    buf[1]  = BLE_GAP_AD_TYPE_MANUFACTURER_SPECIFIC_DATA;
    buf[2]  = (uint8_t)(IBEACON_COMPANY_ID & 0xFFU);
    buf[3]  = (uint8_t)(IBEACON_COMPANY_ID >> 8U);
    buf[4]  = IBEACON_BEACON_TYPE;
    buf[5]  = IBEACON_BEACON_LEN;
    for (int i = 0; i < 16; i++) {
        buf[6 + i] = m_ibeacon_uuid[i];
    }
    buf[22] = (uint8_t)(m_major >> 8U);
    buf[23] = (uint8_t)(m_major & 0xFFU);
    buf[24] = (uint8_t)(m_minor >> 8U);
    buf[25] = (uint8_t)(m_minor & 0xFFU);
    buf[26] = (uint8_t)IBEACON_MEASURED_RSSI;
    *len = 27;
}

/* ---- Обработчики событий ----------------------------------------------- */

static void ble_evt_handler(ble_evt_t const *p_ble_evt, void *p_context)
{
    (void)p_context;
    if (p_ble_evt->header.evt_id == BLE_GAP_EVT_ADV_SET_TERMINATED) {
        m_adv_done = true;
    }
}

NRF_SDH_BLE_OBSERVER(m_ble_observer, 3, ble_evt_handler, NULL);

static void rtc_handler(nrf_drv_rtc_int_type_t int_type)
{
    if (int_type == NRF_DRV_RTC_INT_COMPARE0) {
        m_rtc_wakeup = true;
        /* Инкрементировать unix_time на величину одного wake-интервала */
        uint32_t t = tag_platform_get_unix_time() + TAG_WAKE_INTERVAL_SEC;
        tag_platform_set_unix_time(t);
    }
}

/* ---- Инициализация ----------------------------------------------------- */

static void clock_init(void)
{
    ret_code_t err = nrf_drv_clock_init();
    APP_ERROR_CHECK(err);
    nrf_drv_clock_lfclk_request(NULL);
    while (!nrf_drv_clock_lfclk_is_running()) { /* ждать LFXO */ }
}

static void rtc_init(void)
{
    nrf_drv_rtc_config_t cfg = NRF_DRV_RTC_DEFAULT_CONFIG;
    cfg.prescaler = RTC_PRESCALER;
    ret_code_t err = nrf_drv_rtc_init(&m_rtc, &cfg, rtc_handler);
    APP_ERROR_CHECK(err);
    nrf_drv_rtc_enable(&m_rtc);
}

static void softdevice_init(void)
{
    ret_code_t err;

    err = nrf_sdh_enable_request();
    APP_ERROR_CHECK(err);

    /*
     * Использовать конфигурацию по умолчанию для S112.
     * ram_start — адрес начала доступной RAM приложению после SoftDevice.
     * nRF52832: SD занимает ~6.5 KB RAM начиная с 0x20000000.
     */
    uint32_t ram_start = 0;
    err = nrf_sdh_ble_default_cfg_set(1, &ram_start);
    APP_ERROR_CHECK(err);

    err = nrf_sdh_ble_enable(&ram_start);
    APP_ERROR_CHECK(err);

    /* Установить TX-мощность */
    err = sd_ble_gap_tx_power_set(BLE_GAP_TX_POWER_ROLE_ADV, 0,
                                   (int8_t)TAG_TX_POWER_DBM);
    APP_ERROR_CHECK(err);
}

/* ---- Public API -------------------------------------------------------- */

void tag_platform_init(void)
{
    clock_init();
    rtc_init();
    softdevice_init();

    /*
     * Первый запуск: GPREGRET2 = 0 (сброс питанием).
     * Устанавливаем начальное unix_time из конфига, записанного при прошивке.
     */
    if (tag_platform_get_unix_time() == 0) {
        tag_platform_set_unix_time(TAG_INITIAL_UNIX_TIME);
    }

    /*
     * Защита от считывания через SWD (APPROTECT).
     * Активировать только перед производственной прошивкой (TAG_ENABLE_APPROTECT=1).
     * После активации ключ TAG_KEY недоступен через отладчик.
     * ВНИМАНИЕ: необратимая операция — ключ нельзя будет прочитать через SWD.
     */
#if TAG_ENABLE_APPROTECT
    if (NRF_UICR->APPROTECT != 0xFFFFFF00UL) {
        NRF_NVMC->CONFIG  = NVMC_CONFIG_WEN_Wen << NVMC_CONFIG_WEN_Pos;
        while (NRF_NVMC->READY == NVMC_READY_READY_Busy) {}
        NRF_UICR->APPROTECT = 0xFFFFFF00UL;
        while (NRF_NVMC->READY == NVMC_READY_READY_Busy) {}
        NRF_NVMC->CONFIG  = NVMC_CONFIG_WEN_Ren << NVMC_CONFIG_WEN_Pos;
        NVIC_SystemReset(); /* перезагрузка для применения защиты */
    }
#endif
}

uint32_t tag_platform_get_unix_time(void)
{
    /*
     * NRF_POWER->GPREGRET2 — 32-битный регистр, сохраняется при System OFF
     * если питание не снималось. При полном сбросе питания = 0.
     */
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
    m_major      = major;
    m_minor      = minor;
    m_mac_sfx[0] = mac_suffix[0];
    m_mac_sfx[1] = mac_suffix[1];
    m_mac_sfx[2] = mac_suffix[2];

    /*
     * Обновить Random Static MAC-адрес.
     * Формат (6 байт, передаётся в SoftDevice от addr[5] до addr[0]):
     *   addr[5] = TAG_MAC_PREFIX[0] | 0xC0  — два старших бита = 11 (RANDOM STATIC)
     *   addr[4] = TAG_MAC_PREFIX[1]
     *   addr[3] = TAG_MAC_PREFIX[2]
     *   addr[2] = mac_suffix[0]             — из AES-вывода, меняется каждый слот
     *   addr[1] = mac_suffix[1]
     *   addr[0] = mac_suffix[2]
     *
     * Биты 46..47 (addr[5] биты 6..7) должны быть '11' для Random Static (BLE spec).
     */
    ble_gap_addr_t addr;
    addr.addr_type = BLE_GAP_ADDR_TYPE_RANDOM_STATIC;
    addr.addr[5]   = TAG_MAC_PREFIX[0] | 0xC0U;
    addr.addr[4]   = TAG_MAC_PREFIX[1];
    addr.addr[3]   = TAG_MAC_PREFIX[2];
    addr.addr[2]   = mac_suffix[0];
    addr.addr[1]   = mac_suffix[1];
    addr.addr[0]   = mac_suffix[2];

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
        .scan_rsp_data   = {0},
    };

    /*
     * Nonconnectable, nonscannable undirected — минимальный пакет без scan response.
     * max_adv_evts = 1: ровно одно advertising event (все 3 канала: 37, 38, 39),
     * после чего SoftDevice генерирует BLE_GAP_EVT_ADV_SET_TERMINATED.
     */
    ble_gap_adv_params_t adv_params;
    memset(&adv_params, 0, sizeof(adv_params));
    adv_params.properties.type = BLE_GAP_ADV_TYPE_NONCONNECTABLE_NONSCANNABLE_UNDIRECTED;
    adv_params.p_peer_addr     = NULL;
    adv_params.filter_policy   = BLE_GAP_ADV_FP_ANY;
    adv_params.interval        = MSEC_TO_UNITS(TAG_WAKE_INTERVAL_SEC * 1000U,
                                               UNIT_0_625_MS);
    adv_params.duration        = BLE_GAP_ADV_TIMEOUT_GENERAL_UNLIMITED;
    adv_params.max_adv_evts    = 1;
    adv_params.primary_phy     = BLE_GAP_PHY_1MBPS;

    uint8_t    adv_handle = BLE_GAP_ADV_SET_HANDLE_NOT_SET;
    m_adv_done = false;

    ret_code_t err;
    err = sd_ble_gap_adv_set_configure(&adv_handle, &adv_data, &adv_params);
    APP_ERROR_CHECK(err);

    err = sd_ble_gap_adv_start(adv_handle, 1 /* conn_cfg_tag */);
    APP_ERROR_CHECK(err);

    /* Ждать BLE_GAP_EVT_ADV_SET_TERMINATED (~1 мс на 3 канала) */
    while (!m_adv_done) {
        sd_app_evt_wait();
    }
}

void tag_platform_set_rtc_wakeup(uint32_t seconds)
{
    /*
     * Установить compare-регистр CC[0] на текущий счётчик + нужное кол-во тиков.
     * При срабатывании вызовется rtc_handler(NRF_DRV_RTC_INT_COMPARE0).
     * System OFF будет разбужен этим событием, nRF52832 сделает холодный старт.
     */
    uint32_t ticks = nrf_drv_rtc_counter_get(&m_rtc) + seconds * RTC_TICKS_PER_SEC;
    ret_code_t err = nrf_drv_rtc_cc_set(&m_rtc, 0, ticks, true);
    APP_ERROR_CHECK(err);
}

void tag_platform_enter_deep_sleep(void)
{
    m_rtc_wakeup = false;

    /*
     * sd_power_system_off() переводит nRF52832 в System OFF:
     *  - потребление: ~0.4–1.5 µА (RTC + LFXO работают)
     *  - GPREGRET2 сохраняется
     *  - при срабатывании RTC CC[0] — холодный старт (Reset из System OFF)
     *
     * Функция не возвращается. При пробуждении исполнение начинается
     * с точки входа main() как после обычного сброса питания.
     */
    ret_code_t err = sd_power_system_off();
    APP_ERROR_CHECK(err);

    /* Недостижимо, но компилятор требует завершения функции */
    for (;;) { __WFE(); }
}
