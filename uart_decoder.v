module uart_decoder(
    input  wire clk,
    input  wire rst,
    input  wire uart_out_rx,
    output wire uart_laptop_tx
);

    // 2-FF synchronizer for safe clock-domain sampling
    reg rx_ff1, rx_ff2;

    always @(posedge clk) begin
        if (rst) begin
            rx_ff1 <= 1'b1;
            rx_ff2 <= 1'b1;
        end else begin
            rx_ff1 <= uart_out_rx;
            rx_ff2 <= rx_ff1;
        end
    end

    // Direct forward to laptop TX line
    assign uart_laptop_tx = rx_ff2;

endmodule
