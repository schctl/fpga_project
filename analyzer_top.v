module analyzer_top(
    input  wire       clk,
    input  wire       rst,            // active-high reset
    input  wire [1:0] sw_mode,        // EDGE switches: 00=CAN, 01=UART passthrough, 10/11=I2C (no UART stream yet)
    input  wire       scl,
    input  wire       sda,
    input  wire       can_rx,
    input  wire       uart_out_rx,
    output wire       can_tx,
    output wire       uart_laptop_tx
);

    // ------------------------------------------------------------------------
    // Internal UART outputs from each path
    // ------------------------------------------------------------------------
    wire can_uart_tx;
    wire uart_passthrough_tx;
    wire can_tx_int;
    wire unused_rx_led;

    // ------------------------------------------------------------------------
    // CAN path
    // ------------------------------------------------------------------------
    can_top u_can_top (
        .rstn          (~rst),
        .clk           (clk),
        .can_rx        (can_rx),
        .can_tx        (can_tx_int),
        .uart_tx       (can_uart_tx),
        .rx_led        (unused_rx_led)
    );

    // ------------------------------------------------------------------------
    // I2C decoder path (currently decode-only, no UART output port)
    // ------------------------------------------------------------------------
    i2c_decoder u_i2c_decoder (
        .clk           (clk),
        .rst           (rst),
        .scl           (scl),
        .sda           (sda)
    );

    // ------------------------------------------------------------------------
    // UART passthrough path
    // ------------------------------------------------------------------------
    uart_decoder u_uart_decoder (
        .clk           (clk),
        .rst           (rst),
        .uart_out_rx   (uart_out_rx),
        .uart_laptop_tx(uart_passthrough_tx)
    );

    // ------------------------------------------------------------------------
    // Mode mux
    // 00: CAN decoder UART stream
    // 01: UART passthrough
    // 10/11: I2C selected (UART idle high for now)
    // ------------------------------------------------------------------------
    assign uart_laptop_tx =
        (sw_mode == 2'b00) ? can_uart_tx :
        (sw_mode == 2'b01) ? uart_passthrough_tx :
                             1'b1;   // UART idle high

    // CAN TX only driven out when CAN mode selected, else recessive '1'
    assign can_tx = (sw_mode == 2'b00) ? can_tx_int : 1'b1;

endmodule
