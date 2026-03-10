// ============================================================
// Module: compute_unit
// Description:
//   Top-level SIMT Compute Unit
//   - 5-stage pipeline (IF → ID → EX → MEM → WB)
//   - External instruction memory interface
//   - External data memory interface
//   - Internal warp manager + VRF
//   - No stalls / no divergence (v1)
// ============================================================

`include "cu_defs.vh"
`include "warp_manager.v"
`include "IFU.v"
`include "decode_unit.v"
`include "execute_stage.v"
`include "mem_stage.v"
`include "writeback_stage.v"
`include "vector_register_file.v"

module compute_unit (

    input  wire                         clk,
    input  wire                         rst,

    // Instruction Memory Interface

    output wire [`PC_WIDTH-1:0]         imem_addr_o,
    input  wire [`INST_WIDTH-1:0]       imem_rdata_i,


    // Data Memory Interface (External, Per-Lane Flat)

    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_addr_flat_o,
    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_wdata_flat_o,
    output wire [`MASK_W-1:0]                dmem_write_mask_o,
    output wire                              dmem_write_en_o,
    output wire                              dmem_read_en_o,

    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_rdata_flat_i

);

    // Warp Manager
    wire [`WARP_ID_W-1:0]    wm_wid;
    wire                     wm_issue_valid;
    wire [`PC_WIDTH-1:0]     wm_pc;
    wire [`MASK_W-1:0]       wm_active_mask;

    // IF/ID
    wire [`INST_WIDTH-1:0]   if_id_inst;
    wire [`WARP_ID_W-1:0]    if_id_wid;
    wire                     if_id_valid;
    wire [`MASK_W-1:0]       if_id_mask;
    wire [`PC_WIDTH-1:0]     if_id_pc;

    // ID/EX
    wire [`WARP_ID_W-1:0]    id_ex_wid;
    wire                     id_ex_valid;
    wire [`MASK_W-1:0]       id_ex_mask;
    wire [`PC_WIDTH-1:0]     id_ex_pc;

    wire [`REG_ID_W-1:0]     id_ex_rs;
    wire [`REG_ID_W-1:0]     id_ex_rt;
    wire [`REG_ID_W-1:0]     id_ex_rd;
    wire [`IMM_W-1:0]        id_ex_imm;

    wire [`FUNC_W-1:0]       id_ex_alu_func;
    wire                     id_ex_alu_src_imm;
    wire                     id_ex_reg_write;
    wire                     id_ex_mem_read;
    wire                     id_ex_mem_write;
    wire                     id_ex_branch;
    wire                     id_ex_branch_inv;
    wire                     id_ex_exit;

    // VRF read
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] vrf_rs_flat;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] vrf_rt_flat;

    // EX/MEM
    wire [`WARP_ID_W-1:0]    ex_mem_wid;
    wire                     ex_mem_valid;
    wire [`MASK_W-1:0]       ex_mem_mask;
    wire [`PC_WIDTH-1:0]     ex_mem_pc;
    wire [`PC_WIDTH-1:0]     ex_mem_branch_target;
    wire                     ex_mem_branch_taken;

    wire [`WARP_SIZE*`LANE_WIDTH-1:0] ex_mem_alu_result;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] ex_mem_store_data;

    wire [`WARP_SIZE*`LANE_WIDTH-1:0]   ex_mem_mem_addr;
    wire [`REG_ID_W-1:0]     ex_mem_rd;
    wire                     ex_mem_reg_write;
    wire                     ex_mem_mem_read;
    wire                     ex_mem_mem_write;
    wire                     ex_mem_exit;

    // MEM/WB
    wire [`WARP_ID_W-1:0]    mem_wb_wid;
    wire                     mem_wb_valid;
    wire [`MASK_W-1:0]       mem_wb_mask;
    wire [`PC_WIDTH-1:0]     mem_wb_pc;

    wire [`WARP_SIZE*`LANE_WIDTH-1:0] mem_wb_result;
    wire [`REG_ID_W-1:0]     mem_wb_rd;
    wire                     mem_wb_reg_write;
    wire                     mem_wb_branch_taken;
    wire [`PC_WIDTH-1:0]     mem_wb_branch_target;
    wire                     mem_wb_exit;

    // WB → VRF
    wire                     vrf_write_en;
    wire [`WARP_ID_W-1:0]    vrf_write_wid;
    wire [`REG_ID_W-1:0]     vrf_write_rd;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] vrf_write_data;
    wire [`MASK_W-1:0]       vrf_write_mask;

    // WB → Warp Manager
    wire                     warp_update_en;
    wire [`WARP_ID_W-1:0]    warp_update_wid;
    wire [`WARP_STATE_W-1:0] warp_update_state;
    wire [`PC_WIDTH-1:0]     warp_update_pc;
    wire [`MASK_W-1:0]       warp_update_mask;
        
    // Warp Manager
    warp_manager u_warp_manager (
    .clk(clk),
    .rst(rst),

    .write_en(warp_update_en),
    .write_wid(warp_update_wid),
    .write_pc(warp_update_pc), 
    .write_active_mask(warp_update_mask),
    .write_warp_state(warp_update_state),

    .current_wid(wm_wid),
    .issue_valid(wm_issue_valid),
    .current_pc(wm_pc),
    .current_active_mask(wm_active_mask)
    );

    instruction_fetch u_ifu (
    .clk(clk),
    .rst(rst),

    // From warp manager
    .issue_valid(wm_issue_valid),
    .current_wid(wm_wid),
    .current_pc(wm_pc),
    .current_active_mask(wm_active_mask),

    // Instruction memory
    .imem_addr(imem_addr_o),
    .imem_rdata(imem_rdata_i),

    // To decode
    .if_instruction(if_id_inst),
    .if_wid(if_id_wid),
    .if_valid(if_id_valid),
    .if_active_mask(if_id_mask),
    .if_pc(if_id_pc)
    );

    // Decode Unit
    decode_unit u_decode (
    .clk(clk),
    .rst(rst),

    .instr_i(if_id_inst),
    .if_wid_i(if_id_wid),
    .if_valid_i(if_id_valid),
    .if_active_mask_i(if_id_mask),
    .if_pc_i(if_id_pc),

    .wid_o(id_ex_wid),
    .valid_o(id_ex_valid),
    .active_mask_o(id_ex_mask),
    .pc_o(id_ex_pc),

    .rs_o(id_ex_rs),
    .rt_o(id_ex_rt),
    .rd_o(id_ex_rd),
    .imm_o(id_ex_imm),

    .alu_func_o(id_ex_alu_func),
    .alu_src_imm_o(id_ex_alu_src_imm),

    .reg_write_o(id_ex_reg_write),
    .mem_read_o(id_ex_mem_read),
    .mem_write_o(id_ex_mem_write),
    .branch_o(id_ex_branch),
    .branch_inv_o(id_ex_branch_inv),
    .exit_o(id_ex_exit)
    );

    // Vector Register File
    vector_register_file u_vrf (
    .clk(clk),
    .rst(rst),

    .read_wid_i(id_ex_wid),
    .write_wid_i(vrf_write_wid),
    .rs_i(id_ex_rs),
    .rt_i(id_ex_rt),

    .reg_write_i(vrf_write_en),
    .rd_i(vrf_write_rd),
    .write_data_i(vrf_write_data),
    .write_mask_i(vrf_write_mask),

    .rs_data_o(vrf_rs_flat),
    .rt_data_o(vrf_rt_flat)
    );

    // Execute Stage
    execute_stage u_execute (
    .clk(clk),
    .rst(rst),

    // From ID/EX
    .wid_i(id_ex_wid),
    .valid_i(id_ex_valid),
    .active_mask_i(id_ex_mask),
    .pc_i(id_ex_pc),

    .rs_flat_i(vrf_rs_flat),
    .rt_flat_i(vrf_rt_flat),

    .imm_i(id_ex_imm),
    .rd_i(id_ex_rd),

    .alu_func_i(id_ex_alu_func),
    .alu_src_imm_i(id_ex_alu_src_imm),

    .reg_write_i(id_ex_reg_write),
    .mem_read_i(id_ex_mem_read),
    .mem_write_i(id_ex_mem_write),
    .branch_i(id_ex_branch),
    .branch_inv_i(id_ex_branch_inv),
    .exit_i(id_ex_exit),

    // To EX/MEM
    .wid_o(ex_mem_wid),
    .valid_o(ex_mem_valid),
    .active_mask_o(ex_mem_mask),
    .pc_o(ex_mem_pc),

    .alu_result_o(ex_mem_alu_result),
    .mem_addr_o(ex_mem_mem_addr),
    .store_data_o(ex_mem_store_data),

    .rd_o(ex_mem_rd),

    .reg_write_o(ex_mem_reg_write),
    .mem_read_o(ex_mem_mem_read),
    .mem_write_o(ex_mem_mem_write),
    .branch_taken_o(ex_mem_branch_taken),
    .branch_target_o(ex_mem_branch_target),
    .exit_o(ex_mem_exit)
    );

    // Memory Stage
    mem_stage u_mem (
    .clk(clk),
    .rst(rst),

    // From EX/MEM
    .wid_i(ex_mem_wid),
    .valid_i(ex_mem_valid),
    .active_mask_i(ex_mem_mask),
    .pc_i(ex_mem_pc),

    .alu_result_i(ex_mem_alu_result),
    .mem_addr_i(ex_mem_mem_addr),
    .store_data_i(ex_mem_store_data),

    .rd_i(ex_mem_rd),

    .reg_write_i(ex_mem_reg_write),
    .mem_read_i(ex_mem_mem_read),
    .mem_write_i(ex_mem_mem_write),
    .branch_taken_i(ex_mem_branch_taken),
    .branch_target_i(ex_mem_branch_target),
    .exit_i(ex_mem_exit),

    // Data memory interface
    .dmem_addr_o(dmem_addr_flat_o),
    .dmem_write_data_o(dmem_wdata_flat_o),
    .dmem_write_mask_o(dmem_write_mask_o),
    .dmem_write_en_o(dmem_write_en_o),
    .dmem_read_en_o(dmem_read_en_o),
    .dmem_read_data_i(dmem_rdata_flat_i),
    

    // To MEM/WB
    .wid_o(mem_wb_wid),
    .valid_o(mem_wb_valid),
    .active_mask_o(mem_wb_mask),
    .pc_o(mem_wb_pc),        

    .result_o(mem_wb_result),
    .rd_o(mem_wb_rd),

    .reg_write_o(mem_wb_reg_write),
    .branch_taken_o(mem_wb_branch_taken),
    .branch_target_o(mem_wb_branch_target),
    .exit_o(mem_wb_exit)
    );

    // Writeback Stage
    writeback_stage u_wb (
    .clk(clk),
    .rst(rst),

    .wid_i(mem_wb_wid),
    .valid_i(mem_wb_valid),
    .active_mask_i(mem_wb_mask),
    .pc_i(mem_wb_pc),

    .result_i(mem_wb_result),
    .rd_i(mem_wb_rd),
    .reg_write_i(mem_wb_reg_write),
    .branch_taken_i(mem_wb_branch_taken),
    .branch_target_i(mem_wb_branch_target),
    .exit_i(mem_wb_exit),

    .vrf_reg_write_o(vrf_write_en),
    .vrf_wid_o(vrf_write_wid),
    .vrf_rd_o(vrf_write_rd),
    .vrf_write_data_o(vrf_write_data),
    .vrf_write_mask_o(vrf_write_mask),

    .warp_update_en_o(warp_update_en),
    .warp_update_wid_o(warp_update_wid),
    .warp_update_state_o(warp_update_state),
    .warp_update_pc_o(warp_update_pc),
    .warp_update_mask_o(warp_update_mask)
    );

endmodule