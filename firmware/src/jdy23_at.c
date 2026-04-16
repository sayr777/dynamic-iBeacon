#include "jdy23_at.h"
#include "tag_platform.h"
#include <stdio.h>
#include <string.h>

/* ---- Вспомогательные функции ------------------------------------------ */

static void send_cmd(const char *cmd)
{
    tag_platform_uart_send(cmd, (uint16_t)strlen(cmd));
    /* CRLF окончание — обязательно для JDY-23 */
    tag_platform_uart_send("\r\n", 2);
    /* Минимальная задержка между командами */
    tag_platform_delay_ms(20);
}

/* ---- Public API -------------------------------------------------------- */

bool jdy23_init(void)
{
    char buf[32];
    /* Запросить версию прошивки */
    send_cmd("AT+VER");
    /* Ожидать ответ — упрощённо: задержка без разбора ответа.
     * Для production добавить чтение UART и проверку "+VER:" */
    tag_platform_delay_ms(100);
    (void)buf;
    return true;
}

bool jdy23_set_major(uint16_t major)
{
    char buf[20];
    /* Формат: AT+MAJOR{XXXX} где XXXX — 4 hex символа */
    snprintf(buf, sizeof(buf), "AT+MAJOR%04X", (unsigned)major);
    send_cmd(buf);
    return true;
}

bool jdy23_set_minor(uint16_t minor)
{
    char buf[20];
    snprintf(buf, sizeof(buf), "AT+MINOR%04X", (unsigned)minor);
    send_cmd(buf);
    return true;
}

bool jdy23_set_mac_suffix(const uint8_t mac_suffix[3])
{
    char buf[32];
    /* Формат команды зависит от ревизии JDY-23.
     * Проверить наличие AT+MAC на конкретном модуле перед использованием.
     * Полный MAC: TAG_MAC_BYTE0:TAG_MAC_BYTE1:TAG_MAC_BYTE2:suffix[0]:suffix[1]:suffix[2] */
    snprintf(buf, sizeof(buf), "AT+LADDR%02X%02X%02X%02X%02X%02X",
             (unsigned)0xE5, (unsigned)0x00, (unsigned)0x00,
             (unsigned)mac_suffix[0],
             (unsigned)mac_suffix[1],
             (unsigned)mac_suffix[2]);
    send_cmd(buf);
    return true;
}

void jdy23_reset(void)
{
    send_cmd("AT+RST");
    /* Время перезагрузки JDY-23: ~500 мс — ожидать в tag_app.c */
}

void jdy23_sleep(void)
{
    /* Если JDY-23 поддерживает команду сна */
    send_cmd("AT+SLEEP");
    /* Альтернатива: GPIO LOW (отключение питания) в tag_app.c */
}
