// Web Worker: перебор TagID × Slot через AES-128 ECB
// Схема v2 (динамический UUID):
//   variant=0: ecb(KEY, [tagID(2)|slot(4)|0x00|0(9)]) → UUID (16 байт)
//   variant=1: ecb(KEY, [tagID(2)|slot(4)|0x01|0(9)]) → Major(2)+Minor(2)+MAC(6)
//
// AES-ECB реализован через AES-CBC с нулевым IV:
//   CBC(key, iv=0, block) == ECB(key, block) для одного блока

let cryptoKey = null;

async function importKey(keyBytes) {
  cryptoKey = await crypto.subtle.importKey(
    'raw', keyBytes,
    { name: 'AES-CBC' },
    false,
    ['encrypt']
  );
}

// Формирует 16-байтный входной блок: [tagID(2) | slot(4) | variant(1) | 0x00(9)]
function buildBlock(tagID, slot, variant) {
  const b = new Uint8Array(16);
  b[0] = (tagID >> 8) & 0xFF;
  b[1] =  tagID       & 0xFF;
  b[2] = (slot >> 24) & 0xFF;
  b[3] = (slot >> 16) & 0xFF;
  b[4] = (slot >>  8) & 0xFF;
  b[5] =  slot        & 0xFF;
  b[6] =  variant & 0xFF;
  return b;
}

// AES-128 ECB через CBC с нулевым IV
async function aesECB(block) {
  const iv = new Uint8Array(16); // нули
  const ct = await crypto.subtle.encrypt(
    { name: 'AES-CBC', iv },
    cryptoKey,
    block
  );
  return new Uint8Array(ct, 0, 16); // берём только первый блок
}

// Поиск TagID по тройке (UUID, Major, Minor)
// uuid — строка hex 32 символа без дефисов (опционально)
// При наличии UUID: сначала проверяем UUID (variant=0), затем Major/Minor (variant=1)
// Без UUID: только Major/Minor — менее точно, но работает
async function search({ keyHex, uuid, major, minor, tagMin, tagMax, slotMin, slotMax }) {
  const keyBytes = new Uint8Array(keyHex.match(/.{2}/g).map(b => parseInt(b, 16)));
  await importKey(keyBytes);

  // UUID как байты для побайтового сравнения
  const uuidBytes = uuid
    ? new Uint8Array(uuid.replace(/-/g, '').match(/.{2}/g).map(b => parseInt(b, 16)))
    : null;

  const total = (tagMax - tagMin + 1) * (slotMax - slotMin + 1);
  let checked = 0;
  let lastReport = Date.now();

  for (let tagID = tagMin; tagID <= tagMax; tagID++) {
    for (let slot = slotMin; slot <= slotMax; slot++) {

      // variant=0 → UUID-кандидат
      const uuidOut = await aesECB(buildBlock(tagID, slot, 0));

      if (uuidBytes) {
        // Проверяем UUID (16 байт) — если не совпадает, пропускаем
        let uuidMatch = true;
        for (let i = 0; i < 16; i++) {
          if (uuidOut[i] !== uuidBytes[i]) { uuidMatch = false; break; }
        }
        if (!uuidMatch) {
          checked++;
          const now = Date.now();
          if (now - lastReport > 200) {
            self.postMessage({ type: 'progress', checked, total });
            lastReport = now;
          }
          continue;
        }
      }

      // variant=1 → Major + Minor + MAC
      const advOut = await aesECB(buildBlock(tagID, slot, 1));
      const m = (advOut[0] << 8) | advOut[1];
      const n = (advOut[2] << 8) | advOut[3];

      if (m === major && n === minor) {
        const mac = [
          advOut[4] | 0xC0, advOut[5], advOut[6], advOut[7], advOut[8], advOut[9]
        ].map(b => b.toString(16).padStart(2, '0').toUpperCase()).join(':');

        self.postMessage({ type: 'found', tagID, slot, mac, checked });
        return;
      }

      checked++;
      const now = Date.now();
      if (now - lastReport > 200) {
        self.postMessage({ type: 'progress', checked, total });
        lastReport = now;
      }
    }
  }

  self.postMessage({ type: 'notfound', checked });
}

self.onmessage = async (e) => {
  try {
    await search(e.data);
  } catch (err) {
    self.postMessage({ type: 'error', message: err.message });
  }
};
