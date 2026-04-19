# protocol_transmitter

Embassy + probe-rs firmware for **STM32F103CBT6 (WeAct/Bluepill)** that transmits:

- UART stream
- I2C master writes (with pull-ups enabled in config)
- CAN frames

All are emitted continuously so you can feed your FPGA analyzer input paths.

## Pin usage (STM32 side)

- **UART1 TX**: `PA9`
- **UART1 RX**: `PA10` (unused, required by constructor)
- **I2C1 SCL**: `PB6`
- **I2C1 SDA**: `PB7`
- **CAN1 RX**: `PB8` (CAN remap enabled)
- **CAN1 TX**: `PB9` (CAN remap enabled)

## Protocol settings

- UART: `115200 8N1`
- I2C: `100 kHz`, target address `0x4A`
- CAN: `1 Mbps`, standard ID `0x123`

## Important hardware notes

1. **CAN requires a transceiver** (e.g. SN65HVD230, TJA1050, MCP2551 + level care).
2. **I2C pull-ups**: firmware enables internal pull-ups, but external 4.7k pull-ups to 3.3V are recommended.
3. Connect grounds between STM32 board and FPGA board.

## Build

```bash
cd protocol_transmitter
cargo build --release
```

## Flash + run (probe-rs)

```bash
cd protocol_transmitter
cargo run --release
```

`cargo run` uses `.cargo/config.toml` runner:
`probe-rs run --chip STM32F103CBTx`

## Suggested FPGA analyzer wiring

- STM32 `PA9` -> FPGA `uart_out_rx`
- STM32 `PB6/PB7` -> FPGA `scl/sda`
- CAN transceiver TX/RX bus -> FPGA CAN input path (`can_rx` side through your PHY arrangement)

