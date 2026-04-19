
//--------------------------------------------------------------------------------------------------------
// Module  : can_top
// Type    : synthesizable, IP's top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: CAN bus controller,
//           CAN-TX: buffer input data and send them to CAN bus,
//           CAN-RX: get CAN bus data and output to user
//--------------------------------------------------------------------------------------------------------

module can_top #(
    // local ID parameter
    parameter [10:0] LOCAL_ID      = 11'h456,

    // recieve ID filter parameters
    parameter [10:0] RX_ID_SHORT_FILTER = 11'h123,
    parameter [10:0] RX_ID_SHORT_MASK   = 11'h7ff,
    parameter [28:0] RX_ID_LONG_FILTER  = 29'h12345678,
    parameter [28:0] RX_ID_LONG_MASK    = 29'h1fffffff,

    // CAN timing parameters
    parameter [15:0] default_c_PTS  = 16'd34,
    parameter [15:0] default_c_PBS1 = 16'd5,
    parameter [15:0] default_c_PBS2 = 16'd10,

    // UART debug stream parameters (for USB-UART on dev board)
    parameter integer CLK_HZ        = 50000000,
    parameter integer UART_BAUD     = 115200
) (
    input  wire        rstn,      // set to 1 while working
    input  wire        clk,       // system clock

    // CAN TX and RX, connect to external CAN phy (e.g., TJA1050)
    input  wire        can_rx,
    output wire        can_tx,

    // UART TX output, connect to board USB-UART RX pin
    output wire        uart_tx,
    // optional status LED output: toggles when an accepted CAN data frame is received
    output reg         rx_led
);



initial rx_led = 1'b0;

reg         pkt_txing = 1'b0;
reg  [31:0] pkt_tx_data = 0;
reg  [31:0] t_auto_data = 32'h0000_0001;
wire        pkt_tx_done;
wire        pkt_tx_acked;
wire        pkt_rx_valid;
wire [28:0] pkt_rx_id;
wire        pkt_rx_ide;
wire        pkt_rx_rtr;
wire [ 3:0] pkt_rx_len;
wire [63:0] pkt_rx_data;
reg         pkt_rx_ack = 1'b0;

reg         t_rtr_req = 1'b0;
reg         r_rtr_req = 1'b0;
reg  [ 1:0] t_retry_cnt = 2'h0;

wire        pkt_accept_data;


// ---------------------------------------------------------------------------------------------------------------------------------------
//  UART debug byte FIFO
// ---------------------------------------------------------------------------------------------------------------------------------------
localparam UDSIZE = 8;
localparam UASIZE = 8;

reg [UDSIZE-1:0] uart_fifo [0:((1<<UASIZE)-1)];
reg [UASIZE:0] uart_wptr = 0;
reg [UASIZE:0] uart_rptr = 0;

wire uart_fifo_full  = uart_wptr == {~uart_rptr[UASIZE], uart_rptr[UASIZE-1:0]};
wire uart_fifo_empty = uart_wptr == uart_rptr;

reg        uart_push = 1'b0;
reg [ 7:0] uart_push_data = 8'h00;
reg        uart_pop = 1'b0;
wire [7:0] uart_pop_data = uart_fifo[uart_rptr[UASIZE-1:0]];

always @ (posedge clk)
    if(uart_push & ~uart_fifo_full)
        uart_fifo[uart_wptr[UASIZE-1:0]] <= uart_push_data;

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        uart_wptr <= 0;
        uart_rptr <= 0;
    end else begin
        if(uart_push & ~uart_fifo_full)
            uart_wptr <= uart_wptr + {{UASIZE{1'b0}}, 1'b1};
        if(uart_pop & ~uart_fifo_empty)
            uart_rptr <= uart_rptr + {{UASIZE{1'b0}}, 1'b1};
    end


// ---------------------------------------------------------------------------------------------------------------------------------------
//  RX packet to UART debug stream (binary frame)
//  Frame format: 0xA5 | ID[31:24] | ID[23:16] | ID[15:8] | ID[7:0] | IDE | LEN | DATA[0..LEN-1] | 0x5A
// ---------------------------------------------------------------------------------------------------------------------------------------
reg         uart_ser_active = 1'b0;
reg  [ 3:0] uart_ser_state  = 4'd0;
reg  [ 3:0] uart_ser_idx    = 4'd0;
reg  [31:0] uart_ser_id32   = 32'd0;
reg         uart_ser_ide    = 1'b0;
reg  [ 3:0] uart_ser_len    = 4'd0;
reg  [63:0] uart_ser_data   = 64'd0;

assign pkt_accept_data = pkt_rx_valid & ~pkt_rx_rtr &
                        ( ((~pkt_rx_ide) && ((pkt_rx_id[10:0] & RX_ID_SHORT_MASK) == (RX_ID_SHORT_FILTER & RX_ID_SHORT_MASK))) |
                          (  pkt_rx_ide  && ((pkt_rx_id       & RX_ID_LONG_MASK ) == (RX_ID_LONG_FILTER  & RX_ID_LONG_MASK ))) );

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        uart_push <= 1'b0;
        uart_push_data <= 8'h00;
        uart_ser_active <= 1'b0;
        uart_ser_state <= 4'd0;
        uart_ser_idx <= 4'd0;
        uart_ser_id32 <= 32'd0;
        uart_ser_ide <= 1'b0;
        uart_ser_len <= 4'd0;
        uart_ser_data <= 64'd0;
    end else begin
        uart_push <= 1'b0;

        if(~uart_ser_active) begin
            if(pkt_accept_data) begin
                uart_ser_active <= 1'b1;
                uart_ser_state <= 4'd0;
                uart_ser_idx <= 4'd0;
                uart_ser_id32 <= {3'b000, pkt_rx_id};
                uart_ser_ide <= pkt_rx_ide;
                uart_ser_len <= pkt_rx_len;
                uart_ser_data <= pkt_rx_data;
            end
        end else if(~uart_fifo_full) begin
            uart_push <= 1'b1;
            case(uart_ser_state)
                4'd0: begin
                    uart_push_data <= 8'hA5;
                    uart_ser_state <= 4'd1;
                end
                4'd1: begin
                    uart_push_data <= uart_ser_id32[31:24];
                    uart_ser_state <= 4'd2;
                end
                4'd2: begin
                    uart_push_data <= uart_ser_id32[23:16];
                    uart_ser_state <= 4'd3;
                end
                4'd3: begin
                    uart_push_data <= uart_ser_id32[15:8];
                    uart_ser_state <= 4'd4;
                end
                4'd4: begin
                    uart_push_data <= uart_ser_id32[7:0];
                    uart_ser_state <= 4'd5;
                end
                4'd5: begin
                    uart_push_data <= {7'd0, uart_ser_ide};
                    uart_ser_state <= 4'd6;
                end
                4'd6: begin
                    uart_push_data <= {4'd0, uart_ser_len};
                    uart_ser_state <= 4'd7;
                end
                4'd7: begin
                    if(uart_ser_idx < uart_ser_len) begin
                        uart_push_data <= uart_ser_data[63:56];
                        uart_ser_data <= {uart_ser_data[55:0], 8'h00};
                        uart_ser_idx <= uart_ser_idx + 4'd1;
                    end else begin
                        uart_push_data <= 8'h5A;
                        uart_ser_active <= 1'b0;
                    end
                end
                default: begin
                    uart_push_data <= 8'h5A;
                    uart_ser_active <= 1'b0;
                end
            endcase
        end
    end


// ---------------------------------------------------------------------------------------------------------------------------------------
//  UART transmitter (8N1)
// ---------------------------------------------------------------------------------------------------------------------------------------
localparam integer UART_DIV = (CLK_HZ + (UART_BAUD/2)) / UART_BAUD;

reg [31:0] uart_div_cnt = 32'd0;
reg [ 3:0] uart_bit_cnt = 4'd0;
reg [ 9:0] uart_shift   = 10'h3ff;
reg        uart_busy    = 1'b0;
reg        uart_txd_reg = 1'b1;

assign uart_tx = uart_txd_reg;

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        uart_pop <= 1'b0;
        uart_div_cnt <= 32'd0;
        uart_bit_cnt <= 4'd0;
        uart_shift <= 10'h3ff;
        uart_busy <= 1'b0;
        uart_txd_reg <= 1'b1;
    end else begin
        uart_pop <= 1'b0;

        if(~uart_busy) begin
            uart_txd_reg <= 1'b1;
            uart_div_cnt <= 32'd0;
            uart_bit_cnt <= 4'd0;
            if(~uart_fifo_empty) begin
                uart_pop <= 1'b1;
                uart_shift <= {1'b1, uart_pop_data, 1'b0};
                uart_busy <= 1'b1;
                uart_txd_reg <= 1'b0;
            end
        end else begin
            if(uart_div_cnt >= (UART_DIV-1)) begin
                uart_div_cnt <= 32'd0;
                uart_bit_cnt <= uart_bit_cnt + 4'd1;
                uart_shift <= {1'b1, uart_shift[9:1]};
                uart_txd_reg <= uart_shift[1];
                if(uart_bit_cnt == 4'd9)
                    uart_busy <= 1'b0;
            end else begin
                uart_div_cnt <= uart_div_cnt + 32'd1;
            end
        end
    end

// ---------------------------------------------------------------------------------------------------------------------------------------
//  CAN packet level controller
// ---------------------------------------------------------------------------------------------------------------------------------------
can_level_packet #(
    .TX_ID           ( LOCAL_ID         ),
    .default_c_PTS   ( default_c_PTS    ),
    .default_c_PBS1  ( default_c_PBS1   ),
    .default_c_PBS2  ( default_c_PBS2   )
) u_can_level_packet (
    .rstn            ( rstn             ),
    .clk             ( clk              ),

    .can_rx          ( can_rx           ),
    .can_tx          ( can_tx           ),

    .tx_start        ( pkt_txing        ),
    .tx_data         ( pkt_tx_data      ),
    .tx_done         ( pkt_tx_done      ),
    .tx_acked        ( pkt_tx_acked     ),

    .rx_valid        ( pkt_rx_valid     ),
    .rx_id           ( pkt_rx_id        ),
    .rx_ide          ( pkt_rx_ide       ),
    .rx_rtr          ( pkt_rx_rtr       ),
    .rx_len          ( pkt_rx_len       ),
    .rx_data         ( pkt_rx_data      ),
    .rx_ack          ( pkt_rx_ack       )
);



// ---------------------------------------------------------------------------------------------------------------------------------------
//  RX action
// ---------------------------------------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        pkt_rx_ack <= 1'b0;
        r_rtr_req <= 1'b0;
        rx_led <= 1'b0;
    end else begin
        pkt_rx_ack <= 1'b0;
        r_rtr_req <= 1'b0;

        if(pkt_rx_valid) begin  // recieve a new packet
            if(pkt_rx_rtr) begin
                if(~pkt_rx_ide && pkt_rx_id[10:0]==LOCAL_ID) begin                                           // is a short-ID remote packet, and the ID matches LOCAL_ID
                    pkt_rx_ack <= 1'b1;
                    r_rtr_req <= 1'b1;
                end
            end else if(~pkt_rx_ide) begin                                                                   // is a short-ID data packet
                if( (pkt_rx_id[10:0] & RX_ID_SHORT_MASK) == (RX_ID_SHORT_FILTER & RX_ID_SHORT_MASK) ) begin  // ID match
                    pkt_rx_ack <= 1'b1;
                    rx_led <= ~rx_led;
                end
            end else begin                                                                                   // is a long-ID data packet
                if( (pkt_rx_id & RX_ID_LONG_MASK) == (RX_ID_LONG_FILTER & RX_ID_LONG_MASK) ) begin           // ID match
                    pkt_rx_ack <= 1'b1;
                    rx_led <= ~rx_led;
                end
            end
        end
    end



// ---------------------------------------------------------------------------------------------------------------------------------------
//  TX action
// ---------------------------------------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        pkt_tx_data <= 0;
        t_auto_data <= 32'h0000_0001;
        t_rtr_req <= 1'b0;
        pkt_txing <= 1'b0;
        t_retry_cnt <= 2'd0;
    end else begin
        if(r_rtr_req)
            t_rtr_req <= 1'b1;                   // set t_rtr_req

        if(~pkt_txing) begin
            t_retry_cnt <= 2'd0;
            if(t_rtr_req) begin                  // if recieved a remote packet
                t_rtr_req <= 1'b0;               // reset t_rtr_req
                pkt_tx_data <= t_auto_data;      // auto response payload for RTR requests
                pkt_txing <= 1'b1;
            end
        end else if(pkt_tx_done) begin
            if(pkt_tx_acked || t_retry_cnt==2'd3) begin
                pkt_txing <= 1'b0;
                if(pkt_tx_acked)
                    t_auto_data <= t_auto_data + 32'd1;
            end else begin
                t_retry_cnt <= t_retry_cnt + 2'd1;
            end
        end
    end


endmodule
