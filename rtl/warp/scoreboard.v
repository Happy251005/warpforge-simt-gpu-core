// ============================================================
// Module: scoreboard
// Description:
//   Per-warp register busy table for hazard detection
//   - Tracks in-flight destination registers per warp
//   - Set at decode when reg_write instruction is issued
//   - Cleared at writeback when result is committed to VRF
//   - Combinational stall output gates ID/EX pipeline register
//   - Handles RAW hazards
//   - REG_ZERO never marked busy
// ============================================================

`include "cu_defs.vh"

module scoreboard (
    input wire clk, rst,

    // Set port (from decode, 1 cycle after issue)
    input wire                    set_en,
    input wire [`WARP_ID_W-1:0]   set_wid,
    input wire [`REG_ID_W-1:0]    set_rd,

    // Clear port (from writeback)
    input  wire clear_en,
    input  wire [`WARP_ID_W-1:0]  clear_wid,
    input  wire [`REG_ID_W-1:0]   clear_rd,

    // Check port (combinational, from decode stall logic)
    input  wire [`WARP_ID_W-1:0]  check_wid,
    input  wire [`REG_ID_W-1:0]   check_rs,
    input  wire [`REG_ID_W-1:0]   check_rt,
    input wire                    check_alu_src_imm,
    input wire                    check_valid,

    // Output
    output wire                   stall,
    output wire [`WARP_ID_W-1:0]  stall_wid
);

    reg [`NUM_VREGS-1:0] busy_table [`NUM_WARPS-1:0]; // 2D array: [warp][reg]
    integer i;

    always @(posedge clk) begin
    if (rst) begin
        // clear all busy bits
        for (i = 0; i < `NUM_WARPS; i = i + 1) begin
            busy_table[i] <= 0;
        end
    end
    else begin
        // clear takes lower priority, set wins on same cycle conflict
        if (clear_en && !(set_en && clear_wid == set_wid && clear_rd == set_rd))
            busy_table[clear_wid][clear_rd] <= 1'b0;

        if (set_en && set_rd != `REG_ZERO)
            busy_table[set_wid][set_rd] <= 1'b1;
    end
end

    // Stall logic (combinational)
    wire rs_busy = (check_rs == `REG_ZERO) ? 1'b0 : busy_table[check_wid][check_rs];
    wire rt_busy = (check_rt == `REG_ZERO) ? 1'b0 : busy_table[check_wid][check_rt];
    wire hazard  = check_valid && (rs_busy || (rt_busy && !check_alu_src_imm));

    assign stall     = hazard;
    assign stall_wid = check_wid;

endmodule