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

    // ===============================
    // ID/EX Pipeline Outputs
    // ===============================

    output reg  [`WARP_ID_W-1:0]        wid_o,
    output reg                          valid_o,
    output reg  [`MASK_W-1:0]           active_mask_o,

    // Register fields
    output reg  [`REG_ID_W-1:0]         rs_o,
    output reg  [`REG_ID_W-1:0]         rt_o,
    output reg  [`REG_ID_W-1:0]         rd_o,
    output reg  [`IMM_W-1:0]            imm_o,

    // Instruction class (opcode[5:3])
    output reg  [2:0]                   instr_class_o,

    // ALU function
    output reg  [`FUNC_W-1:0]           alu_func_o,

    // Control signals
    output reg                          alu_src_imm_o,
    output reg                          reg_write_o,
    output reg                          mem_read_o,
    output reg                          mem_write_o,
    output reg                          branch_o,
    output reg                          exit_o
);

    // Combinational Decode
    wire [`OPCODE_W-1:0] opcode = instr_i[31:26];

    wire [`REG_ID_W-1:0] rs_d  = instr_i[25:21];
    wire [`REG_ID_W-1:0] rt_d  = instr_i[20:16];
    wire [`REG_ID_W-1:0] rd_d  = instr_i[15:11];
    wire [`IMM_W-1:0]    imm_d = instr_i[15:0];

    wire [2:0] instr_class_d = opcode[5:3];


    reg reg_write_d;
    reg mem_read_d;
    reg mem_write_d;
    reg branch_d;
    reg [`FUNC_W-1:0] alu_func_d;
    reg alu_src_imm_d;
    reg exit_d;
    reg rd_use_rt_d;  // For I-type: dest is rt, not rd

    always @(*) begin
        // Default safe values
        reg_write_d   = 0;
        mem_read_d    = 0;
        mem_write_d   = 0;
        branch_d      = 0;
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
                rd_use_rt_d = 1;
            end

            `OPCODE_STORE: begin
                mem_write_d = 1;
            end

            `OPCODE_BEQ,
            `OPCODE_BNE: begin
                branch_d = 1;
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

            rs_o          <= 0;
            rt_o          <= 0;
            rd_o          <= 0;
            imm_o         <= 0;

            instr_class_o <= 0;
            alu_func_o    <= 0;

            alu_src_imm_o <= 0;
            reg_write_o   <= 0;
            mem_read_o    <= 0;
            mem_write_o   <= 0;
            branch_o      <= 0;
            exit_o        <= 0;
        end
        else begin
            // SIMT identity propagation
            wid_o         <= if_wid_i;
            valid_o       <= if_valid_i;

            // Decoded fields
            rs_o          <= rs_d;
            rt_o          <= rt_d;
            rd_o          <= rd_use_rt_d ? rt_d : rd_d;
            imm_o         <= imm_d;

            instr_class_o <= instr_class_d;
            alu_func_o    <= alu_func_d;

            alu_src_imm_o <= alu_src_imm_d;
            active_mask_o <= if_active_mask_i;
            reg_write_o   <= reg_write_d;
            mem_read_o    <= mem_read_d;
            mem_write_o   <= mem_write_d;
            branch_o      <= branch_d;
            exit_o        <= exit_d;
        end
    end

    

endmodule
