// =============================================================================
// ber_uart_tx.sv
// Periodic UART transmitter — every ~1 second sends:
//   "ERR=XXXXXXXX TOT=YYYYYYYY\r\n"  (8-digit hex, uppercase)
// Connect uart_tx to UART-USB bridge (Nexys 4 DDR: pin C4).
// Open terminal at 115200 8N1 to read BER counts.
// =============================================================================
`timescale 1ns / 1ps

module ber_uart_tx #(
    parameter int CLK_HZ = 100_000_000,
    parameter int BAUD   = 115_200
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] err_count,
    input  logic [31:0] total_bits,
    output logic        uart_tx
);

    // -----------------------------------------------------------------------
    // UART bit period
    // -----------------------------------------------------------------------
    localparam int BIT_CLKS = CLK_HZ / BAUD;  // clocks per UART bit

    // -----------------------------------------------------------------------
    // Build the output string at trigger time
    // "ERR=XXXXXXXX TOT=YYYYYYYY\r\n" = 28 bytes
    // -----------------------------------------------------------------------
    localparam int MSG_LEN = 28;
    logic [7:0] msg [0:MSG_LEN-1];

    function automatic logic [7:0] nibble_to_hex(input logic [3:0] n);
        return (n < 4'd10) ? (8'h30 + {4'h0, n}) : (8'h41 + {4'h0, n} - 8'd10);
    endfunction

    logic [31:0] snap_err;
    logic [31:0] snap_tot;

    // -----------------------------------------------------------------------
    // 1-second trigger counter
    // -----------------------------------------------------------------------
    logic [26:0] sec_cnt;
    logic        send_trigger;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sec_cnt      <= '0;
            send_trigger <= 1'b0;
        end else begin
            send_trigger <= 1'b0;
            if (sec_cnt == CLK_HZ - 1) begin
                sec_cnt      <= '0;
                send_trigger <= 1'b1;
                snap_err     <= err_count;
                snap_tot     <= total_bits;
            end else begin
                sec_cnt <= sec_cnt + 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // UART byte transmitter state machine
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] {IDLE, LOAD, XMIT, WAIT} state_t;
    state_t state;

    logic [$clog2(MSG_LEN)-1:0] byte_idx;
    logic [9:0]  shift_reg;     // {stop, data[7:0], start}
    logic [3:0]  bit_cnt;
    logic [15:0] clk_cnt;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state    <= IDLE;
            uart_tx  <= 1'b1;
            byte_idx <= '0;
            bit_cnt  <= '0;
            clk_cnt  <= '0;
        end else begin
            case (state)
                IDLE: begin
                    uart_tx <= 1'b1;
                    if (send_trigger) begin
                        // Build message from snapped counters
                        msg[0]  <= "E";
                        msg[1]  <= "R";
                        msg[2]  <= "R";
                        msg[3]  <= "=";
                        msg[4]  <= nibble_to_hex(snap_err[31:28]);
                        msg[5]  <= nibble_to_hex(snap_err[27:24]);
                        msg[6]  <= nibble_to_hex(snap_err[23:20]);
                        msg[7]  <= nibble_to_hex(snap_err[19:16]);
                        msg[8]  <= nibble_to_hex(snap_err[15:12]);
                        msg[9]  <= nibble_to_hex(snap_err[11:8]);
                        msg[10] <= nibble_to_hex(snap_err[7:4]);
                        msg[11] <= nibble_to_hex(snap_err[3:0]);
                        msg[12] <= " ";
                        msg[13] <= "T";
                        msg[14] <= "O";
                        msg[15] <= "T";
                        msg[16] <= "=";
                        msg[17] <= nibble_to_hex(snap_tot[31:28]);
                        msg[18] <= nibble_to_hex(snap_tot[27:24]);
                        msg[19] <= nibble_to_hex(snap_tot[23:20]);
                        msg[20] <= nibble_to_hex(snap_tot[19:16]);
                        msg[21] <= nibble_to_hex(snap_tot[15:12]);
                        msg[22] <= nibble_to_hex(snap_tot[11:8]);
                        msg[23] <= nibble_to_hex(snap_tot[7:4]);
                        msg[24] <= nibble_to_hex(snap_tot[3:0]);
                        msg[25] <= "\r";
                        msg[26] <= "\n";
                        msg[27] <= 8'h00;  // padding
                        byte_idx <= '0;
                        state    <= LOAD;
                    end
                end

                LOAD: begin
                    // Load next byte into shift register: {1'stop, data, 0'start}
                    shift_reg <= {1'b1, msg[byte_idx], 1'b0};
                    bit_cnt   <= 4'd0;
                    clk_cnt   <= 16'd0;
                    state     <= XMIT;
                end

                XMIT: begin
                    uart_tx <= shift_reg[0];
                    if (clk_cnt == BIT_CLKS - 1) begin
                        clk_cnt   <= 16'd0;
                        shift_reg <= {1'b1, shift_reg[9:1]};
                        bit_cnt   <= bit_cnt + 1'b1;
                        if (bit_cnt == 4'd9) begin
                            // byte done
                            if (byte_idx == MSG_LEN - 1)
                                state <= IDLE;
                            else begin
                                byte_idx <= byte_idx + 1'b1;
                                state    <= LOAD;
                            end
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
