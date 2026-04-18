// Прототип iBeacon-метки на ProMicro NRF52840 v1940 (nice!nano clone)
//
// Сборка:
//   tinygo build -o firmware.uf2 -target=nicenano .
//
// Прошивка:
//   Дважды нажать RESET → диск NICENANO появится в проводнике
//   Скопировать firmware.uf2 на диск
//
// Мониторинг:
//   tinygo monitor -port COM8
//
// Зависимости:
//   go get tinygo.org/x/bluetooth
//
// Алгоритм (упрощённый, для тестирования):
//   - слот считается от uptime (не от unix-time)
//   - SlotDuration = 10s (не 5 мин) — удобно для отладки
//   - AES-128 ECB настоящий (не заглушка)
//   - Major/Minor/MAC берутся из AES-вывода
//   - LED мигает при каждом обновлении слота

package main

import (
	"crypto/aes"
	"machine"
	"time"

	"tinygo.org/x/bluetooth"
)

var adapter = bluetooth.DefaultAdapter

// LED встроенный на ProMicro NRF52840 v1940 — P0.15 (active low)
// Если у вашей платы другой пин — поменяйте здесь
var led = machine.LED

// ──────────────────────────────────────────────
// Конфигурация метки
// ──────────────────────────────────────────────

/*
TagID — уникальный ID метки (0..65535).

Именно этот ID скрыт от эфира.
В эфире только UUID + Major + Minor.
Сервер, зная KEY и алгоритм, восстанавливает TagID через lookup.
*/
const TagID uint16 = 42

/*
TagConfig — все параметры одной метки.
*/
type TagConfig struct {
	TagID               uint16
	Key                 [16]byte
	UUID                [16]byte
	SlotDuration        time.Duration
	AdvertisingInterval time.Duration
	TxPower             int8
}

var cfg = TagConfig{
	TagID: TagID,

	/*
	   Секретный 128-битный ключ.

	   В реальном устройстве:
	   - генерировать отдельно для каждой метки
	   - подставлять на этапе прошивки (linker define или UICR)
	   - не хранить в публичном репозитории
	*/
	Key: [16]byte{
		0x2B, 0x7E, 0x15, 0x16,
		0x28, 0xAE, 0xD2, 0xA6,
		0xAB, 0xF7, 0x15, 0x88,
		0x09, 0xCF, 0x4F, 0x3C,
	},

	UUID: [16]byte{
		0xE2, 0xC5, 0x6D, 0xB5,
		0xDF, 0xFB,
		0x48, 0xD2,
		0xB0, 0x60,
		0xD0, 0xF5, 0xA7, 0x10, 0x96, 0xE0,
	},

	// Для отладки — короткий слот 10 секунд.
	// В production: 5 * time.Minute
	SlotDuration: 10 * time.Second,

	// Интервал рекламы 100ms — виден в nRF Connect
	AdvertisingInterval: 100 * time.Millisecond,

	// Calibrated TX power @ 1m (iBeacon spec field)
	TxPower: -59,
}

// ──────────────────────────────────────────────
// Криптография
// ──────────────────────────────────────────────

/*
aes128Encrypt — AES-128 ECB шифрование одного блока (16 байт).

Используется стандартная библиотека crypto/aes TinyGo.
Идентично серверному Python:
    from Crypto.Cipher import AES
    AES.new(key, AES.MODE_ECB).encrypt(block)
*/
func aes128Encrypt(key [16]byte, block [16]byte) [16]byte {
	c, err := aes.NewCipher(key[:])
	if err != nil {
		panic("aes: " + err.Error())
	}
	var out [16]byte
	c.Encrypt(out[:], block[:])
	return out
}

/*
buildCryptoInput — формирует 16-байтный входной блок для AES.

Формат (совместим с серверным lookup.py):
  [0]      TagID >> 8
  [1]      TagID & 0xFF
  [2]      slot >> 24
  [3]      slot >> 16
  [4]      slot >> 8
  [5]      slot & 0xFF
  [6..15]  нули (padding)
*/
func buildCryptoInput(tagID uint16, slot uint32) [16]byte {
	var block [16]byte
	block[0] = byte(tagID >> 8)
	block[1] = byte(tagID)
	block[2] = byte(slot >> 24)
	block[3] = byte(slot >> 16)
	block[4] = byte(slot >> 8)
	block[5] = byte(slot)
	return block
}

/*
deriveParams — вычисляет Major, Minor и MAC-суффикс из AES(KEY, input).

AES-вывод (16 байт):
  out[0:2]  → Major
  out[2:4]  → Minor
  out[4:9]  → MAC suffix (5 байт, 6-й байт задаётся префиксом)

Major и Minor не могут быть 0 (iBeacon convention).
*/
func deriveParams(config TagConfig, slot uint32) (major, minor uint16, macSuffix [5]byte) {
	block := buildCryptoInput(config.TagID, slot)
	out := aes128Encrypt(config.Key, block)

	major = uint16(out[0])<<8 | uint16(out[1])
	minor = uint16(out[2])<<8 | uint16(out[3])

	if major == 0 {
		major = 1
	}
	if minor == 0 {
		minor = 1
	}

	copy(macSuffix[:], out[4:9])
	return
}

// ──────────────────────────────────────────────
// Слоты
// ──────────────────────────────────────────────

var startTime = time.Now()

/*
currentSlot — номер текущего слота.

Прототип: считается от uptime.
Production: заменить на unix_time / 300
*/
func currentSlot(config TagConfig) uint32 {
	elapsed := time.Since(startTime)
	return uint32(elapsed / config.SlotDuration)
}

// ──────────────────────────────────────────────
// BLE
// ──────────────────────────────────────────────

/*
buildIBeaconPayload — стандартный iBeacon payload (23 байта).

  0x02 0x15 | UUID[16] | Major[2] | Minor[2] | TxPower[1]
*/
func buildIBeaconPayload(config TagConfig, major, minor uint16) []byte {
	data := make([]byte, 0, 23)
	data = append(data, 0x02, 0x15)
	data = append(data, config.UUID[:]...)
	data = append(data, byte(major>>8), byte(major))
	data = append(data, byte(minor>>8), byte(minor))
	data = append(data, byte(config.TxPower))
	return data
}

/*
updateAdvertisement — пересобирает рекламный пакет для нового слота.

Вызывается только когда slot изменился → не тратит энергию на лишние операции.
*/
func updateAdvertisement(adv *bluetooth.Advertisement, config TagConfig, slot uint32) {
	major, minor, _ := deriveParams(config, slot)
	payload := buildIBeaconPayload(config, major, minor)

	_ = adv.Stop()

	must("configure", adv.Configure(bluetooth.AdvertisementOptions{
		AdvertisementType: bluetooth.AdvertisingTypeNonConnInd,
		Interval:          bluetooth.NewDuration(config.AdvertisingInterval),
		ManufacturerData: []bluetooth.ManufacturerDataElement{
			{
				CompanyID: 0x004C, // Apple — iBeacon
				Data:      payload,
			},
		},
	}))

	must("start adv", adv.Start())

	// Мигнуть LED — слот обновился
	blinkLED(2)
}

// ──────────────────────────────────────────────
// LED утилиты
// ──────────────────────────────────────────────

func blinkLED(times int) {
	for i := 0; i < times; i++ {
		led.Low() // active low
		time.Sleep(50 * time.Millisecond)
		led.High()
		time.Sleep(50 * time.Millisecond)
	}
}

// ──────────────────────────────────────────────
// Вспомогательные
// ──────────────────────────────────────────────

func must(action string, err error) {
	if err != nil {
		panic(action + ": " + err.Error())
	}
}

// ──────────────────────────────────────────────
// main
// ──────────────────────────────────────────────

func main() {
	// Инициализация LED
	led.Configure(machine.PinConfig{Mode: machine.PinOutput})
	led.High() // выключен (active low)

	// Старт BLE стека
	must("enable BLE", adapter.Enable())

	adv := adapter.DefaultAdvertisement()
	defer adv.Stop()

	// Сигнал готовности: 3 быстрых мигания
	blinkLED(3)

	var lastSlot uint32 = ^uint32(0) // невалидный → первое обновление немедленно

	for {
		slot := currentSlot(cfg)

		if slot != lastSlot {
			updateAdvertisement(adv, cfg, slot)
			lastSlot = slot
		}

		// Ждём смены слота — проверяем каждые 100ms
		// В production здесь будет System OFF / WFE
		time.Sleep(100 * time.Millisecond)
	}
}
