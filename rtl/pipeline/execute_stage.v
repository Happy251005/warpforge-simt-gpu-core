// ============================================================
// Module: execute_stage
// Description:
//   EX stage of 5-stage SIMT pipeline
//   - ALU computation
//   - Address generation for memory ops
//   - Registers EX/MEM boundary
//   - Exposes combinational EX outputs for EX-stage branch
//     resolution (used by warp_manager)
// ============================================================

`include "cu_defs.vh"

module execute_stage (

    input  wire                         clk,
    input  wire                         rst,

    // From ID/EX
    input  wire [`WARP_ID_W-1:0]        wid_i,
    input  wire                         valid_i,
    input  wire [`MASK_W-1:0]           active_mask_i,
    input  wire [`PC_WIDTH-1:0]         pc_i,

    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] rs_flat_i,
    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] rt_flat_i,

    input  wire [`IMM_W-1:0]            imm_i,
    input  wire [`REG_ID_W-1:0]         rd_i,

    input  wire [`FUNC_W-1:0]           alu_func_i,
    input  wire                         alu_src_imm_i,

    input  wire                         reg_write_i,
    input  wire                         mem_read_i,
    input  wire                         mem_write_i,
    input  wire                         branch_i,
    input  wire                         branch_inv_i,
    input  wire                         exit_i,

    // =========================================================
    // Combinational EX outputs  (BEFORE the EX/MEM register)
    // Used by warp_manager for EX-stage branch resolution.
    // Valid during the cycle the branch is in the EX stage.
    // =========================================================
    output wire                         ex_valid_comb,
    output wire [`WARP_ID_W-1:0]        ex_wid_comb,
    output wire                         ex_branch_comb,
    output wire [`MASK_W-1:0]           ex_take_mask_comb,
    output wire [`MASK_W-1:0]           ex_else_mask_comb,
    output wire [`PC_WIDTH-1:0]         ex_branch_target_comb,

    // =========================================================
    // To EX/MEM (registered)
    // =========================================================
    output reg  [`WARP_ID_W-1:0]        wid_o,
    output reg                          valid_o,
    output reg  [`MASK_W-1:0]           active_mask_o,

    output reg  [`WARP_SIZE*`LANE_WIDTH-1:0] alu_result_o,
    output reg  [`WARP_SIZE*`LANE_WIDTH-1:0] mem_addr_o,
    output reg  [`WARP_SIZE*`LANE_WIDTH-1:0] store_data_o,

    output reg  [`REG_ID_W-1:0]         rd_o,

    output reg                          reg_write_o,
    output reg                          mem_read_o,
    output reg                          mem_write_o,
    output reg                          branch_o,
    output reg                          branch_taken_o,
    output reg [`PC_WIDTH-1:0]          branch_target_o,
    output reg [`MASK_W-1:0]            take_mask_o,
    output reg [`MASK_W-1:0]            else_mask_o,
    output reg                          exit_o
);

    // ALU
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] alu_result_w;
    wire                              branch_taken_w;
    wire [`MASK_W-1:0]                take_mask_w;
    wire [`MASK_W-1:0]                else_mask_w;

    vector_ALU u_vector_ALU (
        .rs_flat_i(rs_flat_i),
        .rt_flat_i(rt_flat_i),
        .imm_i(imm_i),
        .active_mask_i(active_mask_i),
        .alu_func_i(alu_func_i),
        .alu_src_imm_i(alu_src_imm_i),
        .branch_i(branch_i),
        .branch_inv_i(branch_inv_i),
        .instr_class_i(3'b000),
        .result_flat_o(alu_result_w),
        .branch_taken_o(branch_taken_w),
        .take_mask_o(take_mask_w),
        .else_mask_o(else_mask_w)
    );

    // Address Generation (per lane): addr = rs + sign_ext(imm)
    wire [`LANE_WIDTH-1:0] imm_ext;
    assign imm_ext = {{(`LANE_WIDTH-`IMM_W){imm_i[`IMM_W-1]}}, imm_i};

    genvar lane;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] mem_addr_w;

    generate
        for (lane = 0; lane < `WARP_SIZE; lane = lane + 1) begin : ADDR_GEN
            wire [`LANE_WIDTH-1:0] rs_lane;
            assign rs_lane = rs_flat_i[(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH];
            assign mem_addr_w[(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH] = rs_lane + imm_ext;
        end
    endgenerate

    // Branch target: PC_branch + sign_ext(imm)
    wire [`PC_WIDTH-1:0] branch_target_w;
    assign branch_target_w = pc_i + {{(`PC_WIDTH-`IMM_W){imm_i[`IMM_W-1]}}, imm_i};

    // =========================================================
    // Combinational EX pass-throughs (for warp_manager resolution)
    // =========================================================
    assign ex_valid_comb         = valid_i;
    assign ex_wid_comb           = wid_i;
    assign ex_branch_comb        = branch_i;
    assign ex_take_mask_comb     = take_mask_w;
    assign ex_else_mask_comb     = else_mask_w;
    assign ex_branch_target_comb = branch_target_w;

    // EX/MEM Pipeline Register
    always @(posedge clk) begin
        if (rst) begin
            wid_o           <= 0;
            valid_o         <= 0;
            active_mask_o   <= 0;
            alu_result_o    <= 0;
            mem_addr_o      <= 0;
            store_data_o    <= 0;
            rd_o            <= 0;
            reg_write_o     <= 0;
            mem_read_o      <= 0;
            mem_write_o     <= 0;
            branch_o        <= 0;
            branch_taken_o  <= 0;
            branch_target_o <= 0;
            take_mask_o     <= 0;
            else_mask_o     <= 0;
            exit_o          <= 0;
        end
        else begin
            wid_o           <= wid_i;
            valid_o         <= valid_i;
            active_mask_o   <= active_mask_i;
            alu_result_o    <= alu_result_w;
            mem_addr_o      <= mem_addr_w;
            store_data_o    <= rt_flat_i;
            rd_o            <= rd_i;
            reg_write_o     <= reg_write_i;
            mem_read_o      <= mem_read_i;
            mem_write_o     <= mem_write_i;
            branch_o        <= branch_i;
            branch_taken_o  <= branch_taken_w;
            branch_target_o <= branch_target_w;
            take_mask_o     <= take_mask_w;
            else_mask_o     <= else_mask_w;
            exit_o          <= exit_i;
        end
    end

endmodule