// Прототип iBeacon-метки на ProMicro NRF52840 v1940 (nice!nano clone)
//
// Статус: РАБОЧИЙ КОД — протестирован 18 апреля 2026
//
// Тест на реальной плате (ProMicro NRF52840 v1940, COM6):
//   ========================================
//   BLE Tag  TagID=42   SlotDuration=10s
//   UUID     E2C56DB5-DFFB-48D2-B060-D0F5A71096E0
//   ========================================
//   [slot    2] TagID=42  Major=0x4B10  Minor=0x545F  MAC=EB:F9:80:25:0E:94
//   [slot    3] TagID=42  Major=0x256A  Minor=0x7E30  MAC=C1:CC:71:D1:7F:82
//   [slot    4] TagID=42  Major=0xA410  Minor=0xA150  MAC=F0:EB:09:70:D9:86
//   [slot    5] TagID=42  Major=0x2C5C  Minor=0x8F92  MAC=DE:27:9D:15:76:C6
//   [slot    6] TagID=42  Major=0x305E  Minor=0xC636  MAC=D6:F4:13:DF:AC:28
//   [slot    7] TagID=42  Major=0xE896  Minor=0xFC0C  MAC=F0:F4:DE:0D:68:E3
//
// Сборка:
//   cd prototype/firmware/tinygo
//   go mod tidy
//   tinygo build -o firmware.uf2 -target=nicenano .
//
// Прошивка (автоматически через tinygo):
//   tinygo flash -target=nicenano -port COM6 .    # Windows
//   tinygo flash -target=nicenano -port /dev/cu.usbmodemXXXX .  # macOS
//
// Прошивка (вручную UF2):
//   Дважды нажать RST→GND → диск NICENANO → скопировать firmware.uf2
//
// Мониторинг:
//   tinygo monitor -port COM6      # Windows
//   tinygo monitor -port /dev/cu.usbmodemXXXX  # macOS
//
// Требования:
//   Go 1.22–1.24  (TinyGo 0.40.x не поддерживает Go 1.25+)
//   TinyGo 0.40.x
//   tinygo.org/x/bluetooth v0.10.0
//
// Алгоритм:
//   - слот считается от uptime (прототип) / unix_time (production)
//   - SlotDuration = 10s для отладки, production = 5 * time.Minute
//   - AES-128 ECB: crypto/aes (стандартная библиотека Go)
//   - Major = AES_out[0:2], Minor = AES_out[2:4], MAC = AES_out[4:10]
//   - MAC[0] | 0xC0 → Random Static BLE address (BLE spec bits 46-47)
//   - LED P0.15 active HIGH: 3 мигания при старте, 2 при смене слота

package main

import (
	"crypto/aes"
	"fmt"
	"machine"
	"time"

	"tinygo.org/x/bluetooth"
)

var adapter = bluetooth.DefaultAdapter

// LED встроенный на ProMicro NRF52840 v1940 — P0.15, active HIGH
// (led.High() = ON, led.Low() = OFF)
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
deriveParams — вычисляет Major, Minor и MAC из AES(KEY, input).

AES-вывод (16 байт):
  out[0:2]   → Major
  out[2:4]   → Minor
  out[4:10]  → MAC (6 байт); out[4] | 0xC0 → Random Static (bits 46-47 = 11)

Major и Minor не могут быть 0 (iBeacon convention).
*/
func deriveParams(config TagConfig, slot uint32) (major, minor uint16, mac [6]byte) {
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

	// MAC: 6 байт из out[4..9]
	// Старший байт (mac[0]) | 0xC0 — Random Static BLE address (bits 46-47 = 11)
	mac[0] = out[4] | 0xC0
	mac[1] = out[5]
	mac[2] = out[6]
	mac[3] = out[7]
	mac[4] = out[8]
	mac[5] = out[9]
	return
}

// macString форматирует MAC как "XX:XX:XX:XX:XX:XX" (MSB первым — как в nRF Connect)
func macString(mac [6]byte) string {
	return fmt.Sprintf("%02X:%02X:%02X:%02X:%02X:%02X",
		mac[0], mac[1], mac[2], mac[3], mac[4], mac[5])
}

// uuidString форматирует UUID как стандартную строку xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
func uuidString(uuid [16]byte) string {
	return fmt.Sprintf("%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
		uuid[0], uuid[1], uuid[2], uuid[3],
		uuid[4], uuid[5],
		uuid[6], uuid[7],
		uuid[8], uuid[9],
		uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15])
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
		Interval: bluetooth.NewDuration(config.AdvertisingInterval),
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
		led.High() // active HIGH на nice!nano / ProMicro NRF52840
		time.Sleep(50 * time.Millisecond)
		led.Low()
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
	led.Low() // выключен (active HIGH — LOW = off)

	// Старт BLE стека
	must("enable BLE", adapter.Enable())

	adv := adapter.DefaultAdvertisement()
	defer adv.Stop()

	fmt.Println("========================================")
	fmt.Printf("BLE Tag  TagID=%-5d  SlotDuration=%s\n", cfg.TagID, cfg.SlotDuration)
	fmt.Printf("UUID     %s\n", uuidString(cfg.UUID))
	fmt.Println("========================================")

	// Сигнал готовности: 3 быстрых мигания
	blinkLED(3)

	var lastSlot uint32 = ^uint32(0) // невалидный → первое обновление немедленно

	for {
		slot := currentSlot(cfg)

		if slot != lastSlot {
			major, minor, mac := deriveParams(cfg, slot)
			fmt.Printf("[slot %4d] TagID=%d  Major=0x%04X  Minor=0x%04X  MAC=%s\n",
				slot, cfg.TagID, major, minor, macString(mac))
			updateAdvertisement(adv, cfg, slot)
			lastSlot = slot
		}

		// Ждём смены слота — проверяем каждые 100ms
		// В production здесь будет System OFF / WFE
		time.Sleep(100 * time.Millisecond)
	}
}
