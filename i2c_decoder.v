module i2c_decoder(
    input  wire clk,
    input  wire rst,
    input  wire scl,
    input  wire sda,
    output wire uart_rx
);

    // Temporary dummy UART generator (for integration bring-up)
    localparam integer UART_DIV      = 434;      // 50MHz / 115200
    localparam integer SEND_INTERVAL = 500000;   // ~10ms at 50MHz

    reg [31:0] interval_cnt = 32'd0;
    reg [7:0]  next_byte    = 8'h30;

    reg        uart_txd     = 1'b1;
    reg        uart_busy    = 1'b0;
    reg [15:0] uart_divcnt  = 16'd0;
    reg [3:0]  uart_bitcnt  = 4'd0;
    reg [9:0]  uart_shift   = 10'h3ff;
    reg        uart_send    = 1'b0;
    reg [7:0]  uart_send_byte = 8'h00;

    assign uart_rx = uart_txd;

    // Reference inputs so synthesizer keeps ports visible during bring-up.
    wire _unused_i2c = scl ^ sda;

    // Generate periodic dummy bytes.
    always @(posedge clk) begin
        if (rst) begin
            interval_cnt   <= 32'd0;
            next_byte      <= 8'h30;
            uart_send      <= 1'b0;
            uart_send_byte <= 8'h00;
        end else begin
            uart_send <= 1'b0;
            if (!uart_busy) begin
                if (interval_cnt >= (SEND_INTERVAL - 1)) begin
                    interval_cnt   <= 32'd0;
                    uart_send      <= 1'b1;
                    uart_send_byte <= next_byte;
                    next_byte      <= next_byte + 8'd1;
                end else begin
                    interval_cnt <= interval_cnt + 32'd1;
                end
            end
        end
    end

    // UART TX shifter (8N1)
    always @(posedge clk) begin
        if (rst) begin
            uart_txd    <= 1'b1;
            uart_busy   <= 1'b0;
            uart_divcnt <= 16'd0;
            uart_bitcnt <= 4'd0;
            uart_shift  <= 10'h3ff;
        end else begin
            if (!uart_busy) begin
                uart_txd <= 1'b1;
                if (uart_send) begin
                    uart_shift  <= {1'b1, uart_send_byte, 1'b0};
                    uart_busy   <= 1'b1;
                    uart_divcnt <= UART_DIV - 1;
                    uart_bitcnt <= 4'd0;
                    uart_txd    <= 1'b0;
                end
            end else begin
                if (uart_divcnt == 16'd0) begin
                    uart_txd    <= uart_shift[1];
                    uart_shift  <= {1'b1, uart_shift[9:1]};
                    uart_bitcnt <= uart_bitcnt + 4'd1;
                    uart_divcnt <= UART_DIV - 1;
                    if (uart_bitcnt == 4'd9) begin
                        uart_busy <= 1'b0;
                        uart_txd  <= 1'b1;
                    end
                end else begin
                    uart_divcnt <= uart_divcnt - 16'd1;
                end
            end
        end
    end

endmodule
