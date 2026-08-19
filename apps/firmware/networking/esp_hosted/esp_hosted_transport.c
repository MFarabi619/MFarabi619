#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/sd/sd.h>
#include <zephyr/sd/sdio.h>
#include <zephyr/sd/sd_spec.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/logging/log.h>
#include "esp_hosted.h"

LOG_MODULE_REGISTER(esp_hosted, LOG_LEVEL_INF);

#define ESP_HOSTED_NODE DT_NODELABEL(esp_hosted)

static const struct device *const sdhc_dev = DEVICE_DT_GET(DT_PHANDLE(ESP_HOSTED_NODE, sdhc));
static const struct gpio_dt_spec reset_gpio = GPIO_DT_SPEC_GET(ESP_HOSTED_NODE, reset_gpios);

/* ESP slave SLCHOST registers, masked to the low 10 bits for SDIO access. */
#define ESP_ADDR_MASK      0x3FF
#define ESP_TOKEN_RDATA    0x044
#define ESP_INT_RAW_REG    0x050
#define ESP_PACKET_LEN_REG 0x060
#define ESP_INT_CLR_REG    0x0D4
#define ESP_HOST_TO_SLAVE  0x08C /* scratch reg 7 */
#define ESP_PKT_LEN_OFFSET (ESP_PACKET_LEN_REG - ESP_INT_RAW_REG)
#define ESP_REG_WINDOW     (ESP_PKT_LEN_OFFSET + 4)

#define ESP_CMD53_END_ADDR 0x1F800
#define ESP_BLOCK_SIZE     512
#define ESP_LEN_MASK       0xFFFFF
#define ESP_RX_BYTE_MAX    0x100000
#define ESP_RX_BUFFER_SIZE 1536
#define ESP_TX_BUFFER_MAX  0x1000
#define ESP_TX_BUFFER_MASK (ESP_TX_BUFFER_MAX - 1)
#define ESP_TX_BUF_RETRY_MAX 50
#define ESP_TX_BUF_RETRY_US  400
#define ESP_OPEN_DATA_PATH 0

#define CCCR_INT_ENABLE 0x04

struct esp_payload_header {
	uint8_t if_type: 4;
	uint8_t if_num: 4;
	uint8_t flags;
	uint16_t len;
	uint16_t offset;
	uint16_t checksum;
	uint16_t seq_num;
	uint8_t reserved;
	uint8_t packet_type;
} __packed;

#define ESP_HEADER_LEN sizeof(struct esp_payload_header)

/* Priv init-event TLV tags. */
#define ESP_PRIV_EVENT_INIT       0x22
#define ESP_PRIV_CAPABILITY       0x11
#define ESP_PRIV_FIRMWARE_CHIP_ID 0x12
#define ESP_PRIV_FIRMWARE_VERSION 0x17

static struct sd_card card;
static struct sdio_func func1;
static uint32_t rx_byte_count;
static uint32_t rx_stream_len;
static uint32_t rx_stream_pos;
static uint16_t tx_buf_used;
static uint8_t rx_buf[ESP_BLOCK_SIZE * 16] __aligned(32);
static uint8_t tx_buf[ESP_BLOCK_SIZE * 4] __aligned(32);

static int reg_read(uint32_t reg, void *buf, uint16_t len)
{
	reg &= ESP_ADDR_MASK;
	if (len == 1) {
		return sdio_read_byte(&func1, reg, buf);
	}
	return sdio_read_addr(&func1, reg, buf, len);
}

static int reg_write(uint32_t reg, const void *buf, uint16_t len)
{
	reg &= ESP_ADDR_MASK;
	if (len == 1) {
		return sdio_write_byte(&func1, reg, *(const uint8_t *)buf);
	}
	return sdio_write_addr(&func1, reg, (uint8_t *)buf, len);
}

static int c6_reset(void)
{
	if (!gpio_is_ready_dt(&reset_gpio)) {
		LOG_ERR("C6 reset GPIO not ready");
		return -ENODEV;
	}

	/* Hold in reset, release, then wait for the co-processor firmware to boot. */
	gpio_pin_configure_dt(&reset_gpio, GPIO_OUTPUT_INACTIVE);
	k_msleep(50);
	gpio_pin_set_dt(&reset_gpio, 1);
	k_msleep(1500);
	return 0;
}

static int send_slave_config(uint8_t chip_id)
{
	/* TLV init event echoed back so the slave opens its data path. */
	uint8_t buf[] = {
		ESP_PRIV_EVENT_INIT, 0, /* event_type, event_len (patched below) */
		0x44, 1, 0,             /* HOST_CAPABILITIES */
		0x45, 1, chip_id,       /* RCVD_ESP_FIRMWARE_CHIP_ID */
		0x46, 1, 0,             /* SLV_CONFIG_TEST_RAW_TP */
		0x47, 1, 80,            /* THROTTLE_HIGH */
		0x48, 1, 60,            /* THROTTLE_LOW */
	};

	buf[1] = sizeof(buf) - 2;
	return esp_hosted_tx(ESP_PRIV_IF, 0, buf, sizeof(buf));
}

static void handle_priv_event(const uint8_t *payload, uint16_t len)
{
	uint8_t chip_id = 0xff;
	const uint8_t *pos = payload;
	uint16_t left;

	/* payload[0] = event_type, payload[1] = event_len, then TLVs. */
	if (len < 2 || payload[0] != ESP_PRIV_EVENT_INIT) {
		return;
	}
	pos += 2;
	left = payload[1];

	while (left >= 2) {
		uint8_t tag = pos[0];
		uint8_t tlen = pos[1];

		switch (tag) {
		case ESP_PRIV_CAPABILITY:
			LOG_INF("slave capabilities: 0x%02x", pos[2]);
			break;
		case ESP_PRIV_FIRMWARE_CHIP_ID:
			chip_id = pos[2];
			LOG_INF("slave chip id: 0x%02x", chip_id);
			break;
		case ESP_PRIV_FIRMWARE_VERSION:
			LOG_INF("slave fw version: %u.%u.%u", pos[2], pos[3], pos[4]);
			break;
		default:
			break;
		}
		pos += tlen + 2;
		left -= tlen + 2;
	}

	if (chip_id != 0xff) {
		send_slave_config(chip_id);
	}
}

int esp_hosted_transport_init(void)
{
	uint8_t ie = 0;
	uint8_t open = BIT(ESP_OPEN_DATA_PATH);
	int ret;

	if (!device_is_ready(sdhc_dev)) {
		LOG_ERR("SDHC not ready");
		return -ENODEV;
	}

	ret = c6_reset();
	if (ret) {
		return ret;
	}

	ret = sd_init(sdhc_dev, &card);
	if (ret) {
		LOG_ERR("sd_init failed: %d", ret);
		return ret;
	}

	ret = sdio_init_func(&card, &func1, SDIO_FUNC_NUM_1);
	if (ret) {
		LOG_ERR("sdio_init_func failed: %d", ret);
		return ret;
	}

	ret = sdio_enable_func(&func1);
	if (ret) {
		LOG_ERR("sdio_enable_func failed: %d", ret);
		return ret;
	}

	ret = sdio_set_block_size(&func1, ESP_BLOCK_SIZE);
	if (ret) {
		LOG_ERR("sdio_set_block_size failed: %d", ret);
		return ret;
	}

	/* Enable the master + function-1 SDIO interrupt (CCCR lives on function 0). */
	sdio_read_byte(&card.func0, CCCR_INT_ENABLE, &ie);
	sdio_write_byte(&card.func0, CCCR_INT_ENABLE, ie | BIT(0) | BIT(1));

	rx_byte_count = 0;
	rx_stream_len = 0;
	rx_stream_pos = 0;
	tx_buf_used = 0;

	/* Signal the slave to open its data path. */
	ret = reg_write(ESP_HOST_TO_SLAVE, &open, 1);
	if (ret) {
		LOG_ERR("open data path failed: %d", ret);
		return ret;
	}

	LOG_INF("esp-hosted SDIO transport up");
	return 0;
}

static K_MUTEX_DEFINE(tx_mutex);
static uint16_t tx_seq_num;

/* The slave silently drops a write when it has no free RX buffer. TOKEN1 (bits 27:16
 * of TOKEN_RDATA) is its running count of loaded buffers; free = TOKEN1 - buffers used. */
static int tx_buffers_available(uint32_t needed)
{
	uint8_t token[4];
	int ret = reg_read(ESP_TOKEN_RDATA, token, sizeof(token));

	if (ret) {
		return ret;
	}

	uint32_t loaded = (sys_get_le32(token) >> 16) & ESP_TX_BUFFER_MASK;
	uint32_t free = (loaded + ESP_TX_BUFFER_MAX - tx_buf_used) % ESP_TX_BUFFER_MAX;

	return free >= needed ? 0 : -EAGAIN;
}

int esp_hosted_tx(uint8_t if_type, uint8_t if_num, const uint8_t *payload, uint16_t len)
{
	struct esp_payload_header *hdr = (struct esp_payload_header *)tx_buf;
	uint32_t total = ESP_HEADER_LEN + len;
	uint32_t block_len = ROUND_UP(total, ESP_BLOCK_SIZE);
	uint32_t needed = DIV_ROUND_UP(total, ESP_RX_BUFFER_SIZE);
	uint16_t checksum = 0;
	int retries = 0;
	int ret;

	if (block_len > sizeof(tx_buf)) {
		return -EMSGSIZE;
	}

	k_mutex_lock(&tx_mutex, K_FOREVER);

	while ((ret = tx_buffers_available(needed)) == -EAGAIN) {
		if (++retries > ESP_TX_BUF_RETRY_MAX) {
			k_mutex_unlock(&tx_mutex);
			return -ENOBUFS;
		}
		k_usleep(ESP_TX_BUF_RETRY_US);
	}
	if (ret) {
		k_mutex_unlock(&tx_mutex);
		return ret;
	}

	memset(tx_buf, 0, block_len);
	hdr->if_type = if_type;
	hdr->if_num = if_num;
	hdr->len = sys_cpu_to_le16(len);
	hdr->offset = sys_cpu_to_le16(ESP_HEADER_LEN);
	hdr->seq_num = sys_cpu_to_le16(tx_seq_num++);
	memcpy(tx_buf + ESP_HEADER_LEN, payload, len);

	/* Slave checks this over header (field zeroed) + payload and drops on mismatch
	 * when its checksum option is on; a correct value is ignored when it's off. */
	for (uint32_t i = 0; i < total; i++) {
		checksum += tx_buf[i];
	}
	hdr->checksum = sys_cpu_to_le16(checksum);

	/* Address encodes the unpadded length; the block-padded byte count is only the
	 * CMD53 transfer size, and the slave discards the padding past `total`. */
	ret = sdio_write_addr(&func1, ESP_CMD53_END_ADDR - total, tx_buf, block_len);
	if (ret == 0) {
		tx_buf_used = (tx_buf_used + needed) % ESP_TX_BUFFER_MAX;
	}
	k_mutex_unlock(&tx_mutex);
	return ret;
}

int esp_hosted_rx(uint8_t *if_type, uint8_t **payload, uint16_t *len)
{
	/* One slave read returns a stream of concatenated packets. Drain them one per
	 * call from rx_buf; only touch the bus once the current stream is exhausted. */
	if (rx_stream_pos >= rx_stream_len) {
		uint8_t reg[ESP_REG_WINDOW];
		int ret = reg_read(ESP_INT_RAW_REG, reg, ESP_REG_WINDOW);

		if (ret) {
			return ret;
		}

		uint32_t interrupts = sys_get_le32(&reg[0]);
		uint32_t cumulative = sys_get_le32(&reg[ESP_PKT_LEN_OFFSET]) & ESP_LEN_MASK;
		uint32_t rx_size = (cumulative + ESP_RX_BYTE_MAX - rx_byte_count) % ESP_RX_BYTE_MAX;

		if (rx_size == 0) {
			return 0;
		}

		reg_write(ESP_INT_CLR_REG, &interrupts, sizeof(interrupts));

		uint32_t block_len = ROUND_UP(rx_size, ESP_BLOCK_SIZE);

		/* Advance the counter even when the stream won't fit, or rx_byte_count never
		 * catches up to the slave's cumulative counter and RX wedges permanently. */
		rx_byte_count = (rx_byte_count + rx_size) % ESP_RX_BYTE_MAX;
		if (block_len > sizeof(rx_buf)) {
			return 0;
		}

		ret = sdio_read_addr(&func1, ESP_CMD53_END_ADDR - rx_size, rx_buf, block_len);
		if (ret) {
			return ret;
		}
		rx_stream_len = rx_size;
		rx_stream_pos = 0;
	}

	while (rx_stream_pos + ESP_HEADER_LEN <= rx_stream_len) {
		struct esp_payload_header *hdr =
			(struct esp_payload_header *)(rx_buf + rx_stream_pos);
		uint16_t plen = sys_le16_to_cpu(hdr->len);
		uint16_t poff = sys_le16_to_cpu(hdr->offset);
		uint8_t itype = hdr->if_type;
		uint32_t packet_len = (uint32_t)poff + plen;

		if (plen == 0 || poff != ESP_HEADER_LEN ||
		    rx_stream_pos + packet_len > rx_stream_len) {
			rx_stream_pos = rx_stream_len; /* framing lost; abandon the rest */
			return 0;
		}

		uint8_t *data = rx_buf + rx_stream_pos + poff;

		rx_stream_pos += packet_len;

		if (itype == ESP_PRIV_IF) {
			handle_priv_event(data, plen);
			continue;
		}

		*if_type = itype;
		*payload = data;
		*len = plen;
		return 1;
	}

	return 0;
}
