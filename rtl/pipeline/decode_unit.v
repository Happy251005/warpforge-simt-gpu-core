// ============================================================
// Module: decode_unit
// Description:
//   Decodes 32-bit instruction from IFU.
//   Extracts operand fields and generates control signals.
//   Contains ID/EX pipeline register.
//   SIMT-safe: propagates warp ID and valid bit.
// ============================================================

`include "cu_defs.vh"

module decode_unit (
    input  wire                         clk,
    input  wire                         rst,

    // From IF/ID stage
    input  wire [`INST_WIDTH-1:0]       instr_i,
    input  wire [`WARP_ID_W-1:0]        if_wid_i,
    input  wire                         if_valid_i,
    input  wire [`MASK_W-1:0]           if_active_mask_i,
    input  wire [`PC_WIDTH-1:0]         if_pc_i,

    // From Scoreboard
    input  wire                         stall_i,

    // To Scoreboard
    output wire                         set_en,
    output wire [`WARP_ID_W-1:0]        set_wid,
    output wire [`REG_ID_W-1:0]         set_rd,
    output wire                         branch_instr,
    output wire                         check_valid,
    output wire [`WARP_ID_W-1:0]        check_wid,
    output wire [`REG_ID_W-1:0]         check_rs,
    output wire [`REG_ID_W-1:0]         check_rt,
    output wire                         check_alu_src_imm,

    // ===============================
    // ID/EX Pipeline Outputs
    // ===============================

    output reg  [`WARP_ID_W-1:0]        wid_o,
    output reg                          valid_o,
    output reg  [`MASK_W-1:0]           active_mask_o,
    output reg  [`PC_WIDTH-1:0]         pc_o,

    // Register fields
    output reg  [`REG_ID_W-1:0]         rs_o,
    output reg  [`REG_ID_W-1:0]         rt_o,
    output reg  [`REG_ID_W-1:0]         rd_o,
    output reg  [`IMM_W-1:0]            imm_o,

    // ALU function
    output reg  [`FUNC_W-1:0]           alu_func_o,

    // Control signals
    output reg                          alu_src_imm_o,
    output reg                          reg_write_o,
    output reg                          mem_read_o,
    output reg                          mem_write_o,
    output reg                          branch_o,
    output reg                          branch_inv_o,
    output reg                          exit_o
);

    // Combinational Decode
    wire [`OPCODE_W-1:0] opcode = instr_i[31:26];

    wire [`REG_ID_W-1:0] rs_d  = instr_i[25:21];
    wire [`REG_ID_W-1:0] rt_d  = instr_i[20:16];
    wire [`REG_ID_W-1:0] rd_d  = instr_i[15:11];
    wire [`IMM_W-1:0]    imm_d = instr_i[15:0];



    reg reg_write_d;
    reg mem_read_d;
    reg mem_write_d;
    reg branch_d;
    reg branch_inv_d;
    reg [`FUNC_W-1:0] alu_func_d;
    reg alu_src_imm_d;
    reg exit_d;
    reg rd_use_rt_d;  // For I-type: dest is rt, not rd


    // Scoreboard set — fires when valid reg-writing instruction passes decode
    assign set_en          = if_valid_i & reg_write_d & ((rd_use_rt_d ? rt_d : rd_d) != `REG_ZERO) & !stall_i;
    assign set_wid         = if_wid_i;
    assign set_rd          = rd_use_rt_d ? rt_d : rd_d;

    // Scoreboard check — combinational from incoming instruction
    assign check_valid     = if_valid_i;
    assign check_wid       = if_wid_i;
    assign check_rs        = rs_d;
    assign check_rt        = rt_d;
    assign check_alu_src_imm = alu_src_imm_d;

    // Branch detection
    assign branch_instr    = if_valid_i & branch_d;


    always @(*) begin
        // Default safe values
        reg_write_d   = 0;
        mem_read_d    = 0;
        mem_write_d   = 0;
        branch_d      = 0;
        branch_inv_d  = 0;
        alu_func_d    = 0;
        exit_d        = 0;
        alu_src_imm_d = 0;
        rd_use_rt_d   = 0;

        case (opcode)

            `OPCODE_ALU_R: begin
                reg_write_d = 1;
                alu_func_d  = instr_i[5:0];
            end

            `OPCODE_ALU_I: begin
                alu_src_imm_d = 1;
                reg_write_d = 1;
                alu_func_d  = `FUNC_ADD;
                rd_use_rt_d = 1;
            end

            `OPCODE_LOAD: begin
                reg_write_d = 1;
                mem_read_d  = 1;
                rd_use_rt_d = 1;   //LOAD dest is rt field
            end

            `OPCODE_STORE: begin
                mem_write_d = 1;
            end

            `OPCODE_BEQ: begin
                branch_d     = 1;
                branch_inv_d = 0;   // taken when rs == rt
            end

            `OPCODE_BNE: begin
                branch_d     = 1;
                branch_inv_d = 1;   // taken when rs != rt
            end

            `OPCODE_EXIT: begin
                exit_d = 1;
            end

            default: begin
                // Remain inactive
            end

        endcase
    end

    // ID/EX Pipeline Register

    always @(posedge clk) begin
        if (rst) begin
            wid_o         <= 0;
            valid_o       <= 0;
            active_mask_o <= 0;
            pc_o          <= 0;

            rs_o          <= 0;
            rt_o          <= 0;
            rd_o          <= 0;
            imm_o         <= 0;

            alu_func_o    <= 0;

            alu_src_imm_o <= 0;
            reg_write_o   <= 0;
            mem_read_o    <= 0;
            mem_write_o   <= 0;
            branch_o      <= 0;
            branch_inv_o  <= 0;
            exit_o        <= 0;
        end
        else begin
            // SIMT identity propagation
            wid_o         <= if_wid_i;
            valid_o       <= if_valid_i & !(stall_i & !branch_instr); // Branch stalls: let branch flow through to commit; RAW stalls: bubble
            active_mask_o <= if_active_mask_i;
            pc_o          <= if_pc_i;
            
            // Decoded fields
            rs_o          <= rs_d;
            rt_o          <= rt_d;
            rd_o          <= rd_use_rt_d ? rt_d : rd_d;
            imm_o         <= imm_d;

            alu_func_o    <= alu_func_d;

            alu_src_imm_o <= alu_src_imm_d;
            reg_write_o   <= reg_write_d;
            mem_read_o    <= mem_read_d;
            mem_write_o   <= mem_write_d;
            branch_o      <= branch_d;
            branch_inv_o  <= branch_inv_d;
            exit_o        <= exit_d;
        end
    end

    

endmodule
