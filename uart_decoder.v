module uart_decoder #(
    parameter integer MEM_DEPTH = 16,
    parameter integer CLK_HZ    = 50000000,
    parameter integer UART_BAUD = 115200
)(
    input  wire clk,
    input  wire rst,
    input  wire uart_out_rx,
    output wire uart_laptop_tx
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            clog2 = i;
        end
    endfunction

    function [7:0] to_ascii;
        input [3:0] nibble;
        begin
            to_ascii = (nibble < 10) ? (nibble + 8'h30) : (nibble + 8'h37);
        end
    endfunction

    localparam integer ADDR_W = clog2(MEM_DEPTH);

    // Synchronize RX and detect start-bit like falling edge as trigger.
    reg rx_ff1 = 1'b1;
    reg rx_ff2 = 1'b1;
    reg rx_prev = 1'b1;
    wire rx_sync = rx_ff2;
    wire trigger_fall = rx_prev & ~rx_sync;

    always @(posedge clk) begin
        if (rst) begin
            rx_ff1 <= 1'b1;
            rx_ff2 <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_ff1 <= uart_out_rx;
            rx_ff2 <= rx_ff1;
            rx_prev <= rx_sync;
        end
    end

    // Circular sample memory of 8-bit probe ({7'b0, rx_sync}).
    reg [7:0] sample_mem [0:MEM_DEPTH-1];
    reg [ADDR_W-1:0] addr_ptr = {ADDR_W{1'b0}};
    reg [ADDR_W-1:0] read_ptr = {ADDR_W{1'b0}};
    reg [ADDR_W:0] capture_count = {(ADDR_W+1){1'b0}};
    reg [ADDR_W:0] transmit_count = {(ADDR_W+1){1'b0}};

    localparam [1:0] S_IDLE = 2'b00,
                     S_POST = 2'b01,
                     S_TX   = 2'b10;
    reg [1:0] state = S_IDLE;

    // Per-sample transmit phase: high nibble, low nibble, CR, LF.
    reg [1:0] tx_phase = 2'd0;

    // UART byte sender handshake
    reg       tx_start = 1'b0;
    reg [7:0] tx_data  = 8'h00;
    wire      tx_busy;

    uart_tx8n1 #(
        .CLK_HZ   ( CLK_HZ        ),
        .UART_BAUD( UART_BAUD     )
    ) u_uart_tx8n1 (
        .clk      ( clk           ),
        .rst      ( rst           ),
        .tx_start ( tx_start      ),
        .tx_data  ( tx_data       ),
        .uart_txd ( uart_laptop_tx),
        .busy     ( tx_busy       )
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            addr_ptr <= {ADDR_W{1'b0}};
            read_ptr <= {ADDR_W{1'b0}};
            capture_count <= {(ADDR_W+1){1'b0}};
            transmit_count <= {(ADDR_W+1){1'b0}};
            tx_phase <= 2'd0;
            tx_start <= 1'b0;
            tx_data <= 8'h00;
        end else begin
            tx_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    sample_mem[addr_ptr] <= {7'd0, rx_sync};
                    addr_ptr <= addr_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};

                    if (trigger_fall) begin
                        state <= S_POST;
                        capture_count <= {(ADDR_W+1){1'b0}};
                    end
                end

                S_POST: begin
                    sample_mem[addr_ptr] <= {7'd0, rx_sync};
                    addr_ptr <= addr_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};
                    capture_count <= capture_count + {{ADDR_W{1'b0}}, 1'b1};

                    if (capture_count == MEM_DEPTH-1) begin
                        state <= S_TX;
                        read_ptr <= addr_ptr - (MEM_DEPTH-1);
                        transmit_count <= {(ADDR_W+1){1'b0}};
                        tx_phase <= 2'd0;
                    end
                end

                S_TX: begin
                    if (~tx_busy) begin
                        tx_start <= 1'b1;
                        case (tx_phase)
                            2'd0: begin
                                tx_data <= to_ascii(sample_mem[read_ptr][7:4]);
                                tx_phase <= 2'd1;
                            end
                            2'd1: begin
                                tx_data <= to_ascii(sample_mem[read_ptr][3:0]);
                                tx_phase <= 2'd2;
                            end
                            2'd2: begin
                                tx_data <= 8'h0D;
                                tx_phase <= 2'd3;
                            end
                            2'd3: begin
                                tx_data <= 8'h0A;
                                tx_phase <= 2'd0;
                                read_ptr <= read_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};
                                transmit_count <= transmit_count + {{ADDR_W{1'b0}}, 1'b1};

                                if (transmit_count == MEM_DEPTH-1)
                                    state <= S_IDLE;
                            end
                        endcase
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule


module uart_tx8n1 #(
    parameter integer CLK_HZ    = 50000000,
    parameter integer UART_BAUD = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        uart_txd,
    output reg        busy
);

    localparam integer UART_DIV = (CLK_HZ + (UART_BAUD/2)) / UART_BAUD;

    reg [31:0] div_cnt = 32'd0;
    reg [ 3:0] bit_cnt = 4'd0;
    reg [ 9:0] shifter = 10'h3ff;

    always @(posedge clk) begin
        if (rst) begin
            uart_txd <= 1'b1;
            busy <= 1'b0;
            div_cnt <= 32'd0;
            bit_cnt <= 4'd0;
            shifter <= 10'h3ff;
        end else begin
            if (~busy) begin
                uart_txd <= 1'b1;
                div_cnt <= 32'd0;
                bit_cnt <= 4'd0;

                if (tx_start) begin
                    shifter <= {1'b1, tx_data, 1'b0};
                    busy <= 1'b1;
                    uart_txd <= 1'b0;
                end
            end else begin
                if (div_cnt >= (UART_DIV-1)) begin
                    div_cnt <= 32'd0;
                    bit_cnt <= bit_cnt + 4'd1;
                    shifter <= {1'b1, shifter[9:1]};
                    uart_txd <= shifter[1];
                    if (bit_cnt == 4'd9)
                        busy <= 1'b0;
                end else begin
                    div_cnt <= div_cnt + 32'd1;
                end
            end
        end
    end

endmodule
