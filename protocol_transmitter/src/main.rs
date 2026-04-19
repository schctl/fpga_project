#![no_std]
#![no_main]

use core::fmt::Write as _;

use defmt::*;
use embassy_stm32::bind_interrupts;
use embassy_stm32::can::{filter, Can, Fifo, Frame, Rx0InterruptHandler, Rx1InterruptHandler, SceInterruptHandler, StandardId, TxInterruptHandler};
use embassy_stm32::i2c::{self, I2c};
use embassy_stm32::peripherals::CAN;
use embassy_stm32::time::Hertz;
use embassy_stm32::usart::{Config as UartConfig, Uart};
use embassy_time::{Duration, Instant, Timer};
use heapless::String;
use {defmt_rtt as _, panic_probe as _};

// CAN interrupt mapping for STM32F103 bxCAN peripheral.
bind_interrupts!(struct Irqs {
    USB_LP_CAN1_RX0 => Rx0InterruptHandler<CAN>;
    CAN1_RX1 => Rx1InterruptHandler<CAN>;
    CAN1_SCE => SceInterruptHandler<CAN>;
    USB_HP_CAN1_TX => TxInterruptHandler<CAN>;
});

const UART_BAUD: u32 = 115_200;
const I2C_ADDR_7BIT: u8 = 0x4A;
const CAN_BITRATE: u32 = 1_000_000;
const CAN_STD_ID: u16 = 0x123; // Matches can_top RX_ID_SHORT_FILTER default.

#[embassy_executor::main]
async fn main(_spawner: embassy_executor::Spawner) -> ! {
    let p = embassy_stm32::init(Default::default());

    // CAN1 remap to PB8 (RX) / PB9 (TX)
    // Helpful on Bluepill so PA11/PA12 are not needed.
    embassy_stm32::pac::AFIO.mapr().modify(|w| w.set_can1_remap(2));

    // UART1 TX on PA9 (PA10 is RX but unused by this app).
    let mut uart_cfg = UartConfig::default();
    uart_cfg.baudrate = UART_BAUD;
    let mut uart = Uart::new_blocking(p.USART1, p.PA10, p.PA9, uart_cfg).unwrap();

    // I2C1 on PB6 (SCL) / PB7 (SDA), with internal pull-ups enabled.
    // External pull-ups (e.g. 4.7k to 3.3V) are still recommended for robust edges.
    let mut i2c_cfg = i2c::Config::default();
    i2c_cfg.frequency = Hertz(100_000);
    // i2c_cfg.scl_pullup = true;
    // i2c_cfg.sda_pullup = true;
    let mut i2c = I2c::new_blocking(p.I2C1, p.PB6, p.PB7, i2c_cfg);

    // CAN1 on PB8/PB9.
    let mut can = Can::new(p.CAN, p.PB8, p.PB9, Irqs);
    can.modify_filters()
        .enable_bank(0, Fifo::Fifo0, filter::Mask32::accept_all());
    can.modify_config()
        .set_loopback(false)
        .set_silent(false)
        .set_bitrate(CAN_BITRATE);
    can.enable().await;

    info!("protocol_transmitter started");

    let mut uart_cnt: u32 = 0;
    let mut i2c_cnt: u8 = 0;
    let mut can_cnt: u8 = 0;

    let mut next_uart = Instant::now();
    let mut next_i2c = Instant::now();
    let mut next_can = Instant::now();

    loop {
        let now = Instant::now();

        if now >= next_uart {
            let mut line: String<64> = String::new();
            let _ = core::write!(&mut line, "UART {:08}\\r\\n", uart_cnt);
            let _ = uart.blocking_write(line.as_bytes());
            uart_cnt = uart_cnt.wrapping_add(1);
            next_uart += Duration::from_millis(25);
        }

        if now >= next_i2c {
            // 3-byte payload so edges are easy to identify on the analyzer.
            let payload = [0xA0 | (i2c_cnt & 0x0F), i2c_cnt, !i2c_cnt];
            let _ = i2c.blocking_write(I2C_ADDR_7BIT, &payload);
            i2c_cnt = i2c_cnt.wrapping_add(1);
            next_i2c += Duration::from_millis(10);
            info!("I2C write: {:02?}", payload);
        }

        if now >= next_can {
            let data = [
                can_cnt,
                can_cnt.wrapping_add(1),
                can_cnt.wrapping_add(2),
                can_cnt.wrapping_add(3),
                0xCA,
                0xFE,
                0xBE,
                0xEF,
            ];

            if let Some(id) = StandardId::new(CAN_STD_ID) {
                if let Ok(frame) = Frame::new_data(id, &data) {
                    let _ = can.write(&frame).await;
                }
            }

            can_cnt = can_cnt.wrapping_add(1);
            next_can += Duration::from_millis(5);
        }

        Timer::after_millis(1).await;
    }
}
