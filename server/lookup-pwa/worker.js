// Web Worker: перебор TagID × Slot через AES-128 ECB
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

// Формирует 16-байтный входной блок: [tagID(2) | slot(4) | 0x00(10)]
function buildBlock(tagID, slot) {
  const b = new Uint8Array(16);
  b[0] = (tagID >> 8) & 0xFF;
  b[1] =  tagID       & 0xFF;
  b[2] = (slot >> 24) & 0xFF;
  b[3] = (slot >> 16) & 0xFF;
  b[4] = (slot >>  8) & 0xFF;
  b[5] =  slot        & 0xFF;
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

// Поиск TagID по паре (Major, Minor) в диапазоне слотов
async function search({ keyHex, major, minor, tagMin, tagMax, slotMin, slotMax }) {
  // Импортировать ключ
  const keyBytes = new Uint8Array(keyHex.match(/.{2}/g).map(b => parseInt(b, 16)));
  await importKey(keyBytes);

  const total = (tagMax - tagMin + 1) * (slotMax - slotMin + 1);
  let checked = 0;
  let lastReport = Date.now();

  for (let tagID = tagMin; tagID <= tagMax; tagID++) {
    for (let slot = slotMin; slot <= slotMax; slot++) {
      const block = buildBlock(tagID, slot);
      const out   = await aesECB(block);

      const m = (out[0] << 8) | out[1];
      const n = (out[2] << 8) | out[3];

      if (m === major && n === minor) {
        // Вычислить MAC из того же out
        const mac = [
          out[4] | 0xC0, out[5], out[6], out[7], out[8], out[9]
        ].map(b => b.toString(16).padStart(2, '0').toUpperCase()).join(':');

        self.postMessage({ type: 'found', tagID, slot, mac, checked });
        return;
      }

      checked++;

      // Прогресс раз в 200ms
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
