/*
 * aes128.c — компактная реализация AES-128 ECB (только шифрование).
 *
 * Основана на публично известной compact AES без предвычисленных таблиц.
 * S-box вычисляется из GF(2^8) операций — нет глобальных таблиц 256 байт.
 * Подходит для MCU с малым Flash и RAM.
 *
 * Совместимость: C99, без стандартной библиотеки (кроме stdint.h).
 */

#include "aes128.h"

/* ---- GF(2^8) умножение (xtime) ---------------------------------------- */

static uint8_t xtime(uint8_t x)
{
    return (uint8_t)(((x << 1) ^ ((x >> 7) * 0x1BU)) & 0xFFU);
}

static uint8_t gf_mul(uint8_t a, uint8_t b)
{
    uint8_t p = 0;
    uint8_t i;
    for (i = 0; i < 8; i++) {
        if (b & 1U) p ^= a;
        a = xtime(a);
        b >>= 1;
    }
    return p;
}

/* ---- S-box вычисление через GF(2^8) инверсию --------------------------- */

static uint8_t gf_inv(uint8_t a)
{
    /* Extended Euclidean algorithm in GF(2^8) */
    uint8_t t0 = 1, t1 = 0;
    uint8_t r0 = a, r1 = 0x1B; /* irreducible poly x^8+x^4+x^3+x+1 */
    uint8_t q;
    int i;
    if (a == 0) return 0;
    /* Use square-and-multiply: a^254 = a^(-1) in GF(2^8) */
    uint8_t res = 1;
    uint8_t base = a;
    uint8_t exp = 254;
    (void)t0; (void)t1; (void)r0; (void)r1; (void)q; (void)i;
    for (i = 0; i < 8; i++) {
        if (exp & 1U) res = gf_mul(res, base);
        base = gf_mul(base, base);
        exp >>= 1;
    }
    return res;
}

static uint8_t sbox(uint8_t a)
{
    uint8_t b = gf_inv(a);
    /* Affine transformation */
    b = b ^ (uint8_t)(((b << 1) | (b >> 7)) & 0xFF)
          ^ (uint8_t)(((b << 2) | (b >> 6)) & 0xFF)
          ^ (uint8_t)(((b << 3) | (b >> 5)) & 0xFF)
          ^ (uint8_t)(((b << 4) | (b >> 4)) & 0xFF)
          ^ 0x63U;
    return b;
}

/* ---- Round constant ------------------------------------------------------- */

static uint8_t rcon(uint8_t round)
{
    uint8_t c = 1;
    uint8_t i;
    for (i = 1; i < round; i++) c = xtime(c);
    return c;
}

/* ---- Key expansion -------------------------------------------------------- */

#define NK 4   /* key words */
#define NB 4   /* block words */
#define NR 10  /* rounds */

static void key_expansion(const uint8_t key[16], uint8_t w[4 * NB * (NR + 1)])
{
    uint8_t i, j;
    uint8_t temp[4];

    for (i = 0; i < 4 * NK; i++) {
        w[i] = key[i];
    }

    for (i = NK; i < NB * (NR + 1); i++) {
        temp[0] = w[(i-1)*4+0];
        temp[1] = w[(i-1)*4+1];
        temp[2] = w[(i-1)*4+2];
        temp[3] = w[(i-1)*4+3];

        if (i % NK == 0) {
            /* RotWord + SubWord + Rcon */
            uint8_t t = temp[0];
            temp[0] = sbox(temp[1]) ^ rcon(i / NK);
            temp[1] = sbox(temp[2]);
            temp[2] = sbox(temp[3]);
            temp[3] = sbox(t);
        }

        for (j = 0; j < 4; j++) {
            w[i*4+j] = w[(i-NK)*4+j] ^ temp[j];
        }
    }
}

/* ---- AES state operations ------------------------------------------------- */

static void sub_bytes(uint8_t s[16])
{
    uint8_t i;
    for (i = 0; i < 16; i++) s[i] = sbox(s[i]);
}

static void shift_rows(uint8_t s[16])
{
    uint8_t t;
    /* Row 1: shift left 1 */
    t = s[1]; s[1] = s[5]; s[5] = s[9]; s[9] = s[13]; s[13] = t;
    /* Row 2: shift left 2 */
    t = s[2]; s[2] = s[10]; s[10] = t;
    t = s[6]; s[6] = s[14]; s[14] = t;
    /* Row 3: shift left 3 (= shift right 1) */
    t = s[15]; s[15] = s[11]; s[11] = s[7]; s[7] = s[3]; s[3] = t;
}

static void mix_columns(uint8_t s[16])
{
    uint8_t col;
    for (col = 0; col < 4; col++) {
        uint8_t *c = &s[col * 4];
        uint8_t a0 = c[0], a1 = c[1], a2 = c[2], a3 = c[3];
        c[0] = gf_mul(0x02, a0) ^ gf_mul(0x03, a1) ^ a2             ^ a3;
        c[1] = a0             ^ gf_mul(0x02, a1) ^ gf_mul(0x03, a2) ^ a3;
        c[2] = a0             ^ a1             ^ gf_mul(0x02, a2) ^ gf_mul(0x03, a3);
        c[3] = gf_mul(0x03, a0) ^ a1           ^ a2             ^ gf_mul(0x02, a3);
    }
}

static void add_round_key(uint8_t s[16], const uint8_t *rk)
{
    uint8_t i;
    for (i = 0; i < 16; i++) s[i] ^= rk[i];
}

/* ---- Public API ----------------------------------------------------------- */

void aes128_ecb_encrypt(const uint8_t key[AES128_KEY_SIZE],
                        const uint8_t in[AES128_BLOCK_SIZE],
                        uint8_t       out[AES128_BLOCK_SIZE])
{
    uint8_t w[4 * NB * (NR + 1)]; /* round keys: 176 bytes on stack */
    uint8_t state[16];
    uint8_t round;

    key_expansion(key, w);

    /* Copy input to state (column-major) */
    uint8_t r, c;
    for (r = 0; r < 4; r++)
        for (c = 0; c < 4; c++)
            state[c*4 + r] = in[r*4 + c];

    add_round_key(state, w);

    for (round = 1; round <= NR; round++) {
        sub_bytes(state);
        shift_rows(state);
        if (round < NR) mix_columns(state);
        add_round_key(state, w + round * 16);
    }

    /* Copy state to output */
    for (r = 0; r < 4; r++)
        for (c = 0; c < 4; c++)
            out[r*4 + c] = state[c*4 + r];
}
