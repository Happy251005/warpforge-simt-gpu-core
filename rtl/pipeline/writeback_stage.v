// ============================================================
// Module: writeback_stage
// Description:
//   WB stage of 5-stage SIMT pipeline
//   - Writes ALU or LOAD result to VRF
//   - Fires branch commit to warp manager on taken branch
//   - Fires scoreboard clear on reg-writing instruction commit
//   - Fires exit signal to warp manager on EXIT instruction
// ============================================================

`include "cu_defs.vh"

module writeback_stage (

    // From MEM/WB
    input  wire [`WARP_ID_W-1:0]        wid_i,
    input  wire                         valid_i,
    input  wire [`MASK_W-1:0]           active_mask_i,

    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] result_i,
    input  wire [`REG_ID_W-1:0]         rd_i,

    input  wire                         reg_write_i,
    input  wire                         branch_i,       
    input  wire                         branch_taken_i,
    input  wire [`PC_WIDTH-1:0]         branch_target_i,
    input  wire                         exit_i,


    // To VRF

    output wire                         vrf_reg_write_o,
    output wire [`WARP_ID_W-1:0]        vrf_wid_o,
    output wire [`REG_ID_W-1:0]         vrf_rd_o,
    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] vrf_write_data_o,
    output wire [`MASK_W-1:0]           vrf_write_mask_o,

    // Branch commit interface (to warp manager)
    output wire                         branch_commit_o,
    output wire [`WARP_ID_W-1:0]        branch_wid_o,
    output wire [`PC_WIDTH-1:0]         branch_target_o,
    output wire [`MASK_W-1:0]           branch_mask_o,

    // Scoreboard clear interface
    output wire                         clear_en_o,
    output wire [`WARP_ID_W-1:0]        clear_wid_o,
    output wire [`REG_ID_W-1:0]         clear_rd_o,

    // Exit interface (to warp manager)
    output wire                         exit_en_o,
    output wire [`WARP_ID_W-1:0]        exit_wid_o,

    // Branch resolve interface (to warp manager) — fires on any valid branch (taken OR not-taken)
    output wire                         branch_resolve_o

);

    // VRF Write

    assign vrf_reg_write_o  = reg_write_i & valid_i;
    assign vrf_wid_o        = wid_i;
    assign vrf_rd_o         = rd_i;
    assign vrf_write_data_o = result_i;
    assign vrf_write_mask_o = active_mask_i;


    // Branch commit — fires when valid branch is taken
    assign branch_commit_o  = valid_i & branch_taken_i;
    assign branch_wid_o     = wid_i;
    assign branch_target_o  = branch_target_i;
    assign branch_mask_o    = active_mask_i;

    // Scoreboard clear — fires when valid reg-writing instruction commits
    assign clear_en_o       = valid_i & reg_write_i & (rd_i != `REG_ZERO);
    assign clear_wid_o      = wid_i;
    assign clear_rd_o       = rd_i;

    // Exit — fires when valid EXIT instruction commits
    assign exit_en_o        = valid_i & exit_i;
    assign exit_wid_o       = wid_i;

    // Branch resolve — fires on ANY valid branch commit (taken or not-taken)
    assign branch_resolve_o         = valid_i & branch_i;



endmodule