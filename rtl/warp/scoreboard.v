// ============================================================
// Module: scoreboard
// Description:
//   Per-warp register busy table for hazard detection
//   - Tracks in-flight destination registers per warp
//   - Set at decode when reg_write instruction is issued
//   - Cleared at writeback when result is committed to VRF
//   - Combinational stall output gates ID/EX pipeline register
//   - Stalls warp on branch instruction until resolution
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

    // In-flight pipeline writer checks (from EX and MEM stages)
    input  wire                   ex_valid_i,
    input  wire                   ex_reg_write_i,
    input  wire [`WARP_ID_W-1:0]  ex_wid_i,
    input  wire [`REG_ID_W-1:0]   ex_rd_i,

    input  wire                   mem_valid_i,
    input  wire                   mem_reg_write_i,
    input  wire [`WARP_ID_W-1:0]  mem_wid_i,
    input  wire [`REG_ID_W-1:0]   mem_rd_i,

    // Check port (combinational, from decode stall logic)
    input  wire [`WARP_ID_W-1:0]  check_wid,
    input  wire [`REG_ID_W-1:0]   check_rs,
    input  wire [`REG_ID_W-1:0]   check_rt,
    input wire                    check_alu_src_imm,
    input wire                    check_valid,
    input wire                    branch_instr, // Indicates if the instruction is a branch (for stalling until resolution)

    // Output
    output wire                   stall,
    output wire [`WARP_ID_W-1:0]  stall_wid,
    output wire                   stall_cause // 0: register conflict, 1: branch
);

    reg [`NUM_VREGS-1:0] busy_table [`NUM_WARPS-1:0]; // 2D array: [warp][reg]
    integer i;

    // In-flight writer checks to prevent WAW premature clear
    wire id_has_writer  = set_en && (set_wid == clear_wid) && (set_rd == clear_rd);
    wire ex_has_writer  = ex_valid_i && ex_reg_write_i && (ex_wid_i == clear_wid) && (ex_rd_i == clear_rd);
    wire mem_has_writer = mem_valid_i && mem_reg_write_i && (mem_wid_i == clear_wid) && (mem_rd_i == clear_rd);
    wire has_newer_writer = id_has_writer || ex_has_writer || mem_has_writer;

    always @(posedge clk) begin
    if (rst) begin
        // clear all busy bits
        for (i = 0; i < `NUM_WARPS; i = i + 1) begin
            busy_table[i] <= 0;
        end
    end
    else begin
        if (clear_en && !has_newer_writer)
            busy_table[clear_wid][clear_rd] <= 1'b0;

        if (set_en && set_rd != `REG_ZERO)
            busy_table[set_wid][set_rd] <= 1'b1;
    end
end

    // Stall logic (combinational)
    wire rs_busy    = (check_rs == `REG_ZERO) ? 1'b0 : busy_table[check_wid][check_rs];
    wire rt_busy    = (check_rt == `REG_ZERO) ? 1'b0 : busy_table[check_wid][check_rt];
    wire raw_hazard = check_valid && (rs_busy || (rt_busy && !check_alu_src_imm));
    wire hazard     = raw_hazard || (check_valid && branch_instr);

    assign stall       = hazard;
    assign stall_wid   = check_wid;
    assign stall_cause = !raw_hazard && branch_instr;

endmodule