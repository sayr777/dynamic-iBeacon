//go:build (softdevice && s140v7) || (softdevice && s140v6) || (softdevice && s132v6)

package main

// BLE Privacy Mode через SoftDevice sd_ble_gap_privacy_set().
// Заставляет nRF52840 автоматически менять radio MAC (Non-Resolvable Private Address)
// каждые N секунд — без участия прошивки.

/*
#cgo CFLAGS: -I./softdevice_include

#include "ble_gap.h"
#include "nrf_svc.h"

// Вызов SoftDevice через CGo-обёртку.
// Возвращает 0 при успехе, иначе код ошибки SoftDevice.
static uint32_t ble_gap_privacy_set(uint8_t privacy_mode,
                                     uint8_t addr_type,
                                     uint16_t cycle_s) {
    ble_gap_privacy_params_t p;
    p.privacy_mode          = privacy_mode;
    p.private_addr_type     = addr_type;
    p.private_addr_cycle_s  = cycle_s;
    p.p_device_irk          = ((void*)0); // NULL — SoftDevice генерирует IRK сам
    return sd_ble_gap_privacy_set(&p);
}
*/
import "C"

import "fmt"

// enableBLEPrivacy включает BLE Privacy Mode (Non-Resolvable Private Address).
//
// После вызова SoftDevice меняет radio MAC каждые cycleSeconds секунд.
// Адрес анонимный — не требует IRK на стороне сканера.
//
// Вызывать ПОСЛЕ adapter.Enable() и ДО первого adv.Start().
//
// cycleSeconds: рекомендуется совместить с SlotDuration.
//   Например, SlotDuration=10s → cycleSeconds=10.
//   Минимум: 1 секунда. Максимум: 65535 секунд (~18 часов).
func enableBLEPrivacy(cycleSeconds uint16) error {
	errCode := C.ble_gap_privacy_set(
		C.uint8_t(0x01), // BLE_GAP_PRIVACY_MODE_DEVICE_PRIVACY
		C.uint8_t(0x03), // BLE_GAP_ADDR_TYPE_RANDOM_PRIVATE_NON_RESOLVABLE
		C.uint16_t(cycleSeconds),
	)
	if errCode != 0 {
		return fmt.Errorf("sd_ble_gap_privacy_set error: %d", int(errCode))
	}
	return nil
}
