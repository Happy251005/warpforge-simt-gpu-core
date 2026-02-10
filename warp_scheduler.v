// ============================================================
// Warp Scheduler
// Selects one READY warp per cycle using round-robin policy
// ============================================================

`include "cu_defs.vh"

module warp_scheduler (
    input  wire                    clk,
    input  wire                    rst,

    // Warp states from Warp Context File
    input  wire [`WARP_STATE_W-1:0] warp_state,

    // Scheduling decision
    output reg [`WARP_ID_W-1:0]    current_wid,
    output reg                     issue_valid
);

    reg [`WARP_ID_W-1:0] rr_ptr; // Round-robin pointer
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            rr_ptr <= 0;
        end
        else begin
            // Find the next READY warp starting from rr_ptr
            issue_valid <= 0; // Default to no issue
            for (i = 0; (i < `NUM_WARPS)&&(!issue_valid); i = i + 1) begin
                current_wid <= (rr_ptr + i) % `NUM_WARPS; // Wrap around
                if (warp_state[current_wid] == `WARP_READY) begin
                    issue_valid <= 1; // Found a READY warp
                    rr_ptr <= (current_wid + 1) % `NUM_WARPS; // Update rr_ptr for next cycle
                end
            end
        end
    end
endmodule
