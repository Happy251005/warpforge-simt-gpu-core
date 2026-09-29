// ============================================================
// Module: compute_unit  (v2 — SIMT divergence support)
//
// Changes from v1:
//   • simt_stack instantiated as a separate hardware unit.
//   • execute_stage combinational EX outputs wired to warp_manager
//     for EX-stage branch resolution.
//   • SETRPC signals from decode_unit wired to simt_stack.
//   • simt_stack peek/push/pop wired through warp_manager.
//   • branch_commit / branch_resolve from writeback_stage are
//     still generated (monitored by testbench) but are no longer
//     used by warp_manager for state updates.
//   • All existing mask propagation paths unchanged.
// ============================================================

`include "cu_defs.vh"

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

    // =========================================================
    // Warp Manager outputs
    // =========================================================
    wire [`WARP_ID_W-1:0]    wm_wid;
    wire                     wm_issue_valid;
    wire [`PC_WIDTH-1:0]     wm_pc;
    wire [`MASK_W-1:0]       wm_active_mask;

    // =========================================================
    // Scoreboard → Warp Manager
    // =========================================================
    wire                     sb_stall;
    wire [`WARP_ID_W-1:0]    sb_stall_wid;
    wire                     sb_stall_cause;

    // Squash signal to IFU (branch stalls only)
    wire                     sb_squash;
    wire [`WARP_ID_W-1:0]    sb_squash_wid;

    // Decode → Scoreboard (set port)
    wire                     sb_set_en;
    wire [`WARP_ID_W-1:0]    sb_set_wid;
    wire [`REG_ID_W-1:0]     sb_set_rd;

    // Decode → Scoreboard (check port)
    wire [`WARP_ID_W-1:0]    sb_check_wid;
    wire [`REG_ID_W-1:0]     sb_check_rs;
    wire [`REG_ID_W-1:0]     sb_check_rt;
    wire                     sb_check_alu_src_imm;
    wire                     sb_check_valid;
    wire                     sb_branch_instr;

    // =========================================================
    // IF/ID pipeline register signals
    // =========================================================
    wire [`INST_WIDTH-1:0]   if_id_inst;
    wire [`WARP_ID_W-1:0]    if_id_wid;
    wire                     if_id_valid;
    wire [`MASK_W-1:0]       if_id_mask;
    wire [`PC_WIDTH-1:0]     if_id_pc;

    // =========================================================
    // ID/EX pipeline register signals
    // =========================================================
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

    // SETRPC signals from decode → simt_stack
    wire                     setrpc_en;
    wire [`WARP_ID_W-1:0]    setrpc_wid;
    wire [`PC_WIDTH-1:0]     setrpc_val;

    // =========================================================
    // VRF read outputs
    // =========================================================
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] vrf_rs_flat;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] vrf_rt_flat;

    // =========================================================
    // EX combinational outputs (before EX/MEM register)
    // =========================================================
    wire                     ex_valid_comb;
    wire [`WARP_ID_W-1:0]    ex_wid_comb;
    wire                     ex_branch_comb;
    wire [`MASK_W-1:0]       ex_take_mask_comb;
    wire [`MASK_W-1:0]       ex_else_mask_comb;
    wire [`PC_WIDTH-1:0]     ex_branch_target_comb;

    // =========================================================
    // EX/MEM pipeline register signals
    // =========================================================
    wire [`WARP_ID_W-1:0]    ex_mem_wid;
    wire                     ex_mem_valid;
    wire [`MASK_W-1:0]       ex_mem_mask;
    wire [`PC_WIDTH-1:0]     ex_mem_branch_target;
    wire                     ex_mem_branch_taken;

    wire [`WARP_SIZE*`LANE_WIDTH-1:0] ex_mem_alu_result;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] ex_mem_store_data;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] ex_mem_mem_addr;
    wire [`REG_ID_W-1:0]     ex_mem_rd;
    wire                     ex_mem_reg_write;
    wire                     ex_mem_mem_read;
    wire                     ex_mem_mem_write;
    wire                     ex_mem_branch;
    wire [`MASK_W-1:0]       ex_mem_take_mask;
    wire [`MASK_W-1:0]       ex_mem_else_mask;
    wire                     ex_mem_exit;

    // =========================================================
    // MEM/WB pipeline register signals
    // =========================================================
    wire [`WARP_ID_W-1:0]    mem_wb_wid;
    wire                     mem_wb_valid;
    wire [`MASK_W-1:0]       mem_wb_mask;

    wire [`WARP_SIZE*`LANE_WIDTH-1:0] mem_wb_result;
    wire [`REG_ID_W-1:0]     mem_wb_rd;
    wire                     mem_wb_reg_write;
    wire                     mem_wb_branch;
    wire                     mem_wb_branch_taken;
    wire [`PC_WIDTH-1:0]     mem_wb_branch_target;
    wire                     mem_wb_exit;

    // =========================================================
    // WB → VRF
    // =========================================================
    wire                     vrf_write_en;
    wire [`WARP_ID_W-1:0]    vrf_write_wid;
    wire [`REG_ID_W-1:0]     vrf_write_rd;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] vrf_write_data;
    wire [`MASK_W-1:0]       vrf_write_mask;

    // =========================================================
    // WB → Warp Manager (legacy paths, kept for monitoring)
    // =========================================================
    wire                     branch_commit;
    wire [`WARP_ID_W-1:0]    branch_wid_wb;
    wire [`PC_WIDTH-1:0]     branch_target_wb;
    wire [`MASK_W-1:0]       branch_mask_wb;
    wire                     branch_resolve;

    // =========================================================
    // WB → Scoreboard
    // =========================================================
    wire                     clear_en;
    wire [`WARP_ID_W-1:0]    clear_wid;
    wire [`REG_ID_W-1:0]     clear_rd;

    wire                     exit_en;
    wire [`WARP_ID_W-1:0]    exit_wid;

    // =========================================================
    // SIMT Stack wires
    // =========================================================
    // warp_manager → simt_stack (push)
    wire                     simt_push_en;
    wire [`WARP_ID_W-1:0]    simt_push_wid;
    wire [`PC_WIDTH-1:0]     simt_push_fallthrough;
    wire [`MASK_W-1:0]       simt_push_else_mask;
    wire [`MASK_W-1:0]       simt_push_full_mask;

    // warp_manager → simt_stack (pop)
    wire                     simt_pop_en;
    wire [`WARP_ID_W-1:0]    simt_pop_wid;

    // warp_manager → simt_stack (clear pending_rpc on branch resolution)
    wire                     simt_clear_rpc_en;
    wire [`WARP_ID_W-1:0]    simt_clear_rpc_wid;

    // simt_stack → warp_manager (peek for current warp)
    wire [`PC_WIDTH-1:0]     simt_top_reconv_pc;
    wire [`PC_WIDTH-1:0]     simt_top_target_pc;
    wire [`MASK_W-1:0]       simt_top_mask;
    wire [`NUM_WARPS-1:0]    simt_stack_empty;
    wire [`NUM_WARPS-1:0]    simt_stack_full;

    // =========================================================
    // Squash logic (IFU squash on branch stalls only)
    // =========================================================
    assign sb_squash     = sb_stall & sb_stall_cause;
    assign sb_squash_wid = sb_stall_wid;

    // =========================================================
    // Warp Manager
    // =========================================================
    warp_manager u_warp_manager (
        .clk(clk),
        .rst(rst),

        // WB branch paths (legacy, inputs only for compat)
        .branch_commit(branch_commit),
        .branch_wid(branch_wid_wb),
        .branch_target(branch_target_wb),
        .branch_mask(branch_mask_wb),
        .branch_resolve(branch_resolve),

        .clear_en(clear_en),
        .clear_wid(clear_wid),

        .exit_en(exit_en),
        .exit_wid(exit_wid),

        .scoreboard_stall(sb_stall),
        .scoreboard_stall_wid(sb_stall_wid),
        .scoreboard_stall_cause(sb_stall_cause),
        .stall_pc(if_id_pc),

        // EX-stage branch resolution
        .ex_valid(ex_valid_comb),
        .ex_wid(ex_wid_comb),
        .ex_branch(ex_branch_comb),
        .ex_take_mask(ex_take_mask_comb),
        .ex_else_mask(ex_else_mask_comb),
        .ex_branch_target(ex_branch_target_comb),

        // SIMT stack push
        .simt_push_en(simt_push_en),
        .simt_push_wid(simt_push_wid),
        .simt_push_fallthrough(simt_push_fallthrough),
        .simt_push_else_mask(simt_push_else_mask),
        .simt_push_full_mask(simt_push_full_mask),

        // SIMT stack pop
        .simt_pop_en(simt_pop_en),
        .simt_pop_wid(simt_pop_wid),

        // SIMT stack clear pending_rpc
        .simt_clear_rpc_en(simt_clear_rpc_en),
        .simt_clear_rpc_wid(simt_clear_rpc_wid),

        // SIMT stack peek (for current warp)
        .simt_top_reconv_pc(simt_top_reconv_pc),
        .simt_top_target_pc(simt_top_target_pc),
        .simt_top_mask(simt_top_mask),
        .simt_stack_empty(simt_stack_empty),

        .current_wid(wm_wid),
        .issue_valid(wm_issue_valid),
        .current_pc(wm_pc),
        .current_active_mask(wm_active_mask)
    );

    // =========================================================
    // SIMT Stack
    // =========================================================
    simt_stack u_simt_stack (
        .clk(clk),
        .rst(rst),

        // SETRPC from decode
        .setrpc_en(setrpc_en),
        .setrpc_wid(setrpc_wid),
        .setrpc_val(setrpc_val),

        // Divergent push from warp_manager
        .push_en(simt_push_en),
        .push_wid(simt_push_wid),
        .push_fallthrough_pc(simt_push_fallthrough),
        .push_else_mask(simt_push_else_mask),
        .push_full_mask(simt_push_full_mask),

        // Pop from warp_manager
        .pop_en(simt_pop_en),
        .pop_wid(simt_pop_wid),

        // Clear pending_rpc from warp_manager on branch resolution in EX
        .clear_rpc_en(simt_clear_rpc_en),
        .clear_rpc_wid(simt_clear_rpc_wid),

        // Peek: always for the currently scheduled warp
        .peek_wid(wm_wid),
        .top_target_pc(simt_top_target_pc),
        .top_reconv_pc(simt_top_reconv_pc),
        .top_active_mask(simt_top_mask),

        .stack_empty(simt_stack_empty),
        .stack_full(simt_stack_full)
    );

    // =========================================================
    // Scoreboard
    // =========================================================
    scoreboard u_scoreboard (
        .clk(clk),
        .rst(rst),

        .set_en(sb_set_en),
        .set_wid(sb_set_wid),
        .set_rd(sb_set_rd),

        .clear_en(clear_en),
        .clear_wid(clear_wid),
        .clear_rd(clear_rd),

        // In-flight pipeline writer checks (from EX and MEM stages)
        .ex_valid_i(id_ex_valid),
        .ex_reg_write_i(id_ex_reg_write),
        .ex_wid_i(id_ex_wid),
        .ex_rd_i(id_ex_rd),

        .mem_valid_i(ex_mem_valid),
        .mem_reg_write_i(ex_mem_reg_write),
        .mem_wid_i(ex_mem_wid),
        .mem_rd_i(ex_mem_rd),

        .check_wid(sb_check_wid),
        .check_rs(sb_check_rs),
        .check_rt(sb_check_rt),
        .check_alu_src_imm(sb_check_alu_src_imm),
        .check_valid(sb_check_valid),
        .branch_instr(sb_branch_instr),

        .stall(sb_stall),
        .stall_wid(sb_stall_wid),
        .stall_cause(sb_stall_cause)
    );

    // =========================================================
    // Instruction Fetch Unit
    // =========================================================
    instruction_fetch u_ifu (
        .clk(clk),
        .rst(rst),

        .issue_valid(wm_issue_valid),
        .current_wid(wm_wid),
        .current_pc(wm_pc),
        .current_active_mask(wm_active_mask),

        .squash(sb_squash),
        .squash_wid(sb_squash_wid),

        .imem_addr(imem_addr_o),
        .imem_rdata(imem_rdata_i),

        .if_instruction(if_id_inst),
        .if_wid(if_id_wid),
        .if_valid(if_id_valid),
        .if_active_mask(if_id_mask),
        .if_pc(if_id_pc)
    );

    // =========================================================
    // Decode Unit
    // =========================================================
    decode_unit u_decode (
        .clk(clk),
        .rst(rst),

        .instr_i(if_id_inst),
        .if_wid_i(if_id_wid),
        .if_valid_i(if_id_valid),
        .if_active_mask_i(if_id_mask),
        .if_pc_i(if_id_pc),
        .stall_i(sb_stall),
        .stall_cause_i(sb_stall_cause),

        .set_en(sb_set_en),
        .set_wid(sb_set_wid),
        .set_rd(sb_set_rd),
        .branch_instr(sb_branch_instr),

        .check_valid(sb_check_valid),
        .check_wid(sb_check_wid),
        .check_rs(sb_check_rs),
        .check_rt(sb_check_rt),
        .check_alu_src_imm(sb_check_alu_src_imm),

        // SETRPC → simt_stack
        .setrpc_en(setrpc_en),
        .setrpc_wid(setrpc_wid),
        .setrpc_val(setrpc_val),

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

    // =========================================================
    // Vector Register File
    // =========================================================
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

    // =========================================================
    // Execute Stage
    // =========================================================
    execute_stage u_execute (
        .clk(clk),
        .rst(rst),

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

        // Combinational EX outputs → warp_manager
        .ex_valid_comb(ex_valid_comb),
        .ex_wid_comb(ex_wid_comb),
        .ex_branch_comb(ex_branch_comb),
        .ex_take_mask_comb(ex_take_mask_comb),
        .ex_else_mask_comb(ex_else_mask_comb),
        .ex_branch_target_comb(ex_branch_target_comb),

        // Registered EX/MEM outputs
        .wid_o(ex_mem_wid),
        .valid_o(ex_mem_valid),
        .active_mask_o(ex_mem_mask),

        .alu_result_o(ex_mem_alu_result),
        .mem_addr_o(ex_mem_mem_addr),
        .store_data_o(ex_mem_store_data),

        .rd_o(ex_mem_rd),

        .reg_write_o(ex_mem_reg_write),
        .mem_read_o(ex_mem_mem_read),
        .mem_write_o(ex_mem_mem_write),
        .branch_o(ex_mem_branch),
        .branch_taken_o(ex_mem_branch_taken),
        .branch_target_o(ex_mem_branch_target),
        .take_mask_o(ex_mem_take_mask),
        .else_mask_o(ex_mem_else_mask),
        .exit_o(ex_mem_exit)
    );

    // =========================================================
    // Memory Stage
    // =========================================================
    mem_stage u_mem (
        .clk(clk),
        .rst(rst),

        .wid_i(ex_mem_wid),
        .valid_i(ex_mem_valid),
        .active_mask_i(ex_mem_mask),

        .alu_result_i(ex_mem_alu_result),
        .mem_addr_i(ex_mem_mem_addr),
        .store_data_i(ex_mem_store_data),

        .rd_i(ex_mem_rd),

        .reg_write_i(ex_mem_reg_write),
        .mem_read_i(ex_mem_mem_read),
        .mem_write_i(ex_mem_mem_write),
        .branch_i(ex_mem_branch),
        .branch_taken_i(ex_mem_branch_taken),
        .branch_target_i(ex_mem_branch_target),
        .exit_i(ex_mem_exit),

        .dmem_addr_o(dmem_addr_flat_o),
        .dmem_write_data_o(dmem_wdata_flat_o),
        .dmem_write_mask_o(dmem_write_mask_o),
        .dmem_write_en_o(dmem_write_en_o),
        .dmem_read_en_o(dmem_read_en_o),
        .dmem_read_data_i(dmem_rdata_flat_i),

        .wid_o(mem_wb_wid),
        .valid_o(mem_wb_valid),
        .active_mask_o(mem_wb_mask),

        .result_o(mem_wb_result),
        .rd_o(mem_wb_rd),

        .reg_write_o(mem_wb_reg_write),
        .branch_o(mem_wb_branch),
        .branch_taken_o(mem_wb_branch_taken),
        .branch_target_o(mem_wb_branch_target),
        .exit_o(mem_wb_exit)
    );

    // =========================================================
    // Writeback Stage
    // =========================================================
    writeback_stage u_wb (

        .wid_i(mem_wb_wid),
        .valid_i(mem_wb_valid),
        .active_mask_i(mem_wb_mask),
        .result_i(mem_wb_result),
        .rd_i(mem_wb_rd),
        .reg_write_i(mem_wb_reg_write),
        .branch_i(mem_wb_branch),
        .branch_taken_i(mem_wb_branch_taken),
        .branch_target_i(mem_wb_branch_target),
        .exit_i(mem_wb_exit),

        .vrf_reg_write_o(vrf_write_en),
        .vrf_wid_o(vrf_write_wid),
        .vrf_rd_o(vrf_write_rd),
        .vrf_write_data_o(vrf_write_data),
        .vrf_write_mask_o(vrf_write_mask),

        // Legacy branch paths (monitored by testbench, no longer
        // drive warp_manager state in v2)
        .branch_commit_o(branch_commit),
        .branch_wid_o(branch_wid_wb),
        .branch_target_o(branch_target_wb),
        .branch_mask_o(branch_mask_wb),

        .clear_en_o(clear_en),
        .clear_wid_o(clear_wid),
        .clear_rd_o(clear_rd),

        .exit_en_o(exit_en),
        .exit_wid_o(exit_wid),

        .branch_resolve_o(branch_resolve)
    );

endmodule