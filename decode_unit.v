// ============================================================
// Module: decode_unit
// Description:
//   Decodes 32-bit instruction from IFU.
//   Extracts operand fields and generates control signals.
//   Pure combinational logic (no internal state).
// ============================================================

`include "cu_defs.vh"

module decode_unit (
    input  wire                         clk,
    input  wire                         rst,

    // From IF/ID pipeline register
    input  wire [`INST_WIDTH-1:0]       instr_i,

    // Register fields
    output reg [`REG_ID_W-1:0]        rs_o,
    output reg [`REG_ID_W-1:0]        rt_o,
    output reg [`REG_ID_W-1:0]        rd_o,
    output reg [15:0]                  imm_o,

    // Instruction classification
    output reg [2:0]                   instr_class_o,
    // 3'b000 : ALU
    // 3'b001 : MEM
    // 3'b010 : BRANCH
    // 3'b011 : SPECIAL

    // ALU function (R-type func field)
    output reg  [`FUNC_W-1:0]            alu_func_o,

    // Control signals
    output reg                          reg_write_o,
    output reg                          mem_read_o,
    output reg                          mem_write_o,
    output reg                          branch_o,
    output reg                          exit_o

);
    wire [`OPCODE_W-1:0] opcode = instr_i[31:31-`OPCODE_W+1];
    wire [`REG_ID_W-1:0] rs_d, rt_d, rd_d;
    wire [`IMM_W-1:0] imm_d;
    wire [2:0] instr_class_d;

    reg reg_write_d;
    reg mem_read_d;
    reg mem_write_d;
    reg branch_d;
    reg [`FUNC_W-1:0] alu_func_d;
    reg exit_d;

    // Extract fields from instruction
    assign rs_d  = instr_i[25:21];
    assign rt_d  = instr_i[20:16];
    assign rd_d  = instr_i[15:11];
    assign imm_d = instr_i[15:0];
    assign instr_class_d = opcode[5:3];

    always @(*) begin
        // Default control signal values
        reg_write_d = 0;
        mem_read_d  = 0;
        mem_write_d = 0;
        branch_d    = 0;
        alu_func_d  = 0;
        exit_d      = 0;

        case (opcode)
            `OPCODE_ALU_R: begin
                reg_write_d = 1; // R-type ALU instructions write to register
                alu_func_d  = instr_i[5:0]; // func field determines ALU operation
            end
            `OPCODE_ALU_I: begin
                reg_write_d = 1; // I-type ALU instructions write to register
                alu_func_d  = `FUNC_ADD; // func field determines ALU operation
            end
            `OPCODE_LOAD: begin
                reg_write_d = 1; // Load instructions write to register
                mem_read_d  = 1; // Read from memory
            end
            `OPCODE_STORE: begin
                mem_write_d = 1; // Write to memory
            end
            `OPCODE_BEQ: begin
                branch_d    = 1; // Branch instruction
            end
            `OPCODE_EXIT: begin
                exit_d      = 1; // Exit instruction
            end
            default: begin
                // For unrecognized opcodes, keep control signals at default (inactive)
            end
        endcase
    end

    always @(posedge clk) begin
            if (rst) begin
            rs_o <= 0;
            rt_o <= 0;
            rd_o <= 0;
            imm_o <= 0;
            instr_class_o <= 0;
            reg_write_o <= 0;
            mem_read_o  <= 0;
            mem_write_o <= 0;
            branch_o    <= 0;
            alu_func_o  <= 0;
            exit_o      <= 0;
        end else begin
            rs_o <= rs_d;
            rt_o <= rt_d;
            rd_o <= rd_d;
            imm_o <= imm_d;
            instr_class_o <= instr_class_d;
            reg_write_o <= reg_write_d;
            mem_read_o  <= mem_read_d;
            mem_write_o <= mem_write_d;
            branch_o    <= branch_d;
            alu_func_o  <= alu_func_d;
            exit_o      <= exit_d;
        end
    end

    

endmodule
