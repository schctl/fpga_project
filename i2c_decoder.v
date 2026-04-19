module i2c_decoder(
    input wire clk,
    input wire rst,
    input wire scl,
    input wire sda
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
                    end

                    S_ACK_DATA: if (scl_rising) begin
                        ack      <= ~sda_stable;
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
