module i2c_decoder(
    input wire clk,
    input wire rst,
    input wire scl,
    input wire sda,
    output wire uart_rx
);

    reg  [6:0] addr;
    reg        rw;
    reg  [7:0] data_byte;
    reg        addr_valid;
    reg        data_valid;
    reg        ack;
    reg        busy;
    reg        error;

    reg scl_r1, scl_r2, scl_r3;
    reg sda_r1, sda_r2, sda_r3;

    always @(posedge clk) begin
        if (rst) begin
            scl_r1 <= 1'b1; scl_r2 <= 1'b1; scl_r3 <= 1'b1;
            sda_r1 <= 1'b1; sda_r2 <= 1'b1; sda_r3 <= 1'b1;
        end else begin
            scl_r1 <= scl;  scl_r2 <= scl_r1;  scl_r3 <= scl_r2;
            sda_r1 <= sda;  sda_r2 <= sda_r1;  sda_r3 <= sda_r2;
        end
    end

    wire scl_stable = scl_r2;
    wire sda_stable = sda_r2;

    wire scl_rising  = ( scl_r2 & ~scl_r3);
    wire sda_rising  = ( sda_r2 & ~sda_r3);
    wire sda_falling = (~sda_r2 &  sda_r3);

    wire start_det = sda_falling & scl_stable;
    wire stop_det  = sda_rising  & scl_stable;

    localparam [2:0]
        S_IDLE      = 3'd0,
        S_ADDR      = 3'd1,
        S_RW        = 3'd2,
        S_ACK_ADDR  = 3'd3,
        S_DATA      = 3'd4,
        S_ACK_DATA  = 3'd5;

    reg [2:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;

    // --------------------------------------------------------------------
    // UART output (named uart_rx to match requested external interface)
    // 50MHz / 115200 ~= 434 clocks per bit.
    // --------------------------------------------------------------------
    localparam integer UART_DIV = 434;

    reg        uart_txd = 1'b1;
    reg        uart_busy = 1'b0;
    reg [15:0] uart_divcnt = 16'd0;
    reg [ 3:0] uart_bitcnt = 4'd0;
    reg [ 9:0] uart_shift = 10'h3ff;
    reg        uart_send = 1'b0;
    reg [ 7:0] uart_send_byte = 8'h00;

    assign uart_rx = uart_txd;

    // Pending decoded events
    reg        pend_addr = 1'b0;
    reg [ 6:0] pend_addr_val = 7'd0;
    reg        pend_rw = 1'b0;
    reg        pend_addr_ack = 1'b0;

    reg        pend_data = 1'b0;
    reg [ 7:0] pend_data_val = 8'd0;
    reg        pend_data_ack = 1'b0;

    // Event serializer states
    reg        ser_active = 1'b0;
    reg        ser_is_addr = 1'b0;
    reg [ 2:0] ser_state = 3'd0;
    reg        consume_addr = 1'b0;
    reg        consume_data = 1'b0;

    // UART TX shifter
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
                    // {stop, data[7:0], start}
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

    // Serialize pending decode events into UART bytes
    // Address frame: 0xA1, {addr[6:0],rw}, {7'b0,ack}, 0x1A
    // Data frame   : 0xD1, data_byte,      {7'b0,ack}, 0x1D
    always @(posedge clk) begin
        if (rst) begin
            uart_send      <= 1'b0;
            uart_send_byte <= 8'h00;
            ser_active     <= 1'b0;
            ser_is_addr    <= 1'b0;
            ser_state      <= 3'd0;
            consume_addr   <= 1'b0;
            consume_data   <= 1'b0;
        end else begin
            uart_send <= 1'b0;
            consume_addr <= 1'b0;
            consume_data <= 1'b0;

            if (!ser_active) begin
                if (pend_addr) begin
                    ser_active  <= 1'b1;
                    ser_is_addr <= 1'b1;
                    ser_state   <= 3'd0;
                    consume_addr <= 1'b1;
                end else if (pend_data) begin
                    ser_active  <= 1'b1;
                    ser_is_addr <= 1'b0;
                    ser_state   <= 3'd0;
                    consume_data <= 1'b1;
                end
            end else if (!uart_busy) begin
                uart_send <= 1'b1;
                if (ser_is_addr) begin
                    case (ser_state)
                        3'd0: begin uart_send_byte <= 8'hA1;                   ser_state <= 3'd1; end
                        3'd1: begin uart_send_byte <= {pend_addr_val, pend_rw}; ser_state <= 3'd2; end
                        3'd2: begin uart_send_byte <= {7'd0, pend_addr_ack};    ser_state <= 3'd3; end
                        3'd3: begin uart_send_byte <= 8'h1A;                     ser_active <= 1'b0; end
                        default: begin uart_send_byte <= 8'h1A;                  ser_active <= 1'b0; end
                    endcase
                end else begin
                    case (ser_state)
                        3'd0: begin uart_send_byte <= 8'hD1;                  ser_state <= 3'd1; end
                        3'd1: begin uart_send_byte <= pend_data_val;          ser_state <= 3'd2; end
                        3'd2: begin uart_send_byte <= {7'd0, pend_data_ack};  ser_state <= 3'd3; end
                        3'd3: begin uart_send_byte <= 8'h1D;                   ser_active <= 1'b0; end
                        default: begin uart_send_byte <= 8'h1D;                ser_active <= 1'b0; end
                    endcase
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            bit_cnt    <= 4'd0;
            shift_reg  <= 8'd0;
            addr       <= 7'd0;
            rw         <= 1'b0;
            data_byte  <= 8'd0;
            addr_valid <= 1'b0;
            data_valid <= 1'b0;
            ack        <= 1'b0;
            busy       <= 1'b0;
            error      <= 1'b0;
        end else begin
            addr_valid <= 1'b0;
            data_valid <= 1'b0;
            error      <= 1'b0;

            if (consume_addr)
                pend_addr <= 1'b0;
            if (consume_data)
                pend_data <= 1'b0;

            if (stop_det) begin
                state <= S_IDLE;
                busy  <= 1'b0;
            end else if (start_det) begin
                state     <= S_ADDR;
                bit_cnt   <= 4'd0;
                shift_reg <= 8'd0;
                busy      <= 1'b1;
            end else begin
                case (state)
                    S_IDLE: busy <= 1'b0;

                    S_ADDR: if (scl_rising) begin
                        shift_reg <= {shift_reg[6:0], sda_stable};
                        if (bit_cnt == 4'd6) begin
                            addr    <= {shift_reg[5:0], sda_stable};
                            bit_cnt <= 4'd0;
                            state   <= S_RW;
                        end else bit_cnt <= bit_cnt + 1'b1;
                    end

                    S_RW: if (scl_rising) begin
                        rw         <= sda_stable;
                        addr_valid <= 1'b1;
                        bit_cnt    <= 4'd0;
                        state      <= S_ACK_ADDR;
                    end

                    S_ACK_ADDR: if (scl_rising) begin
                        ack <= ~sda_stable;
                        pend_addr <= 1'b1;
                        pend_addr_val <= addr;
                        pend_rw <= rw;
                        pend_addr_ack <= ~sda_stable;
                        if (!sda_stable) begin
                            shift_reg <= 8'd0;
                            bit_cnt   <= 4'd0;
                            state     <= S_DATA;
                        end else begin
                            error <= 1'b1;
                            state <= S_IDLE;
                        end
                    end

                    S_DATA: if (scl_rising) begin
                        shift_reg <= {shift_reg[6:0], sda_stable};
                        if (bit_cnt == 4'd7) begin
                            data_byte  <= {shift_reg[6:0], sda_stable};
                            data_valid <= 1'b1;
                            bit_cnt    <= 4'd0;
                            state      <= S_ACK_DATA;
                        end else bit_cnt <= bit_cnt + 1'b1;
                            pend_addr      <= 1'b0;
                            pend_addr_val  <= 7'd0;
                            pend_rw        <= 1'b0;
                            pend_addr_ack  <= 1'b0;
                            pend_data      <= 1'b0;
                            pend_data_val  <= 8'd0;
                            pend_data_ack  <= 1'b0;
                    end

                    S_ACK_DATA: if (scl_rising) begin
                        ack      <= ~sda_stable;
                        pend_data <= 1'b1;
                        pend_data_val <= data_byte;
                        pend_data_ack <= ~sda_stable;
                        shift_reg <= 8'd0;
                        bit_cnt   <= 4'd0;
                        state     <= S_DATA;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
