// =============================================================================
// clk_div_en.sv — Clock divider with single-cycle enable output
// =============================================================================
// Divides the input clock by DIV_RATIO.  clk_out toggles at half the divided
// rate; clk_en pulses HIGH for exactly one sys-clk cycle every DIV_RATIO
// cycles (used as a clock-enable for all downstream registered logic).
//
// Parameters:
//   DIV_RATIO — integer division factor (must be even for 50% duty clk_out)
//               Default 100 → 100 MHz ÷ 100 = 1 MHz clk_en
// =============================================================================
`timescale 1ns / 1ps

module clk_div_en #(
    parameter int DIV_RATIO = 100
) (
    input  logic clk,
    input  logic rst_n,       // active-low reset
    output logic clk_out,     // divided clock (50% duty, toggles at DIV_RATIO/2)
    output logic clk_en       // single-cycle enable pulse at divided rate
);

    localparam int CNT_MAX = DIV_RATIO - 1;

    logic [$clog2(DIV_RATIO)-1:0] cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= '0;
            clk_out <= 1'b0;
            clk_en  <= 1'b0;
        end else begin
            clk_en <= 1'b0;                         // default: de-asserted
            if (cnt == CNT_MAX[($clog2(DIV_RATIO)-1):0]) begin
                cnt     <= '0;
                clk_out <= ~clk_out;
                clk_en  <= 1'b1;                    // pulse for one sys-clk
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

endmodule
