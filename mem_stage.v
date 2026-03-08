// ============================================================
// Module: mem_stage
// Description:
//   MEM stage (LSU) of 5-stage SIMT pipeline
//   - Interfaces with shared data_memory
//   - Registers MEM/WB boundary
//   - No stalls (v1)
// ============================================================

`include "cu_defs.vh"

module mem_stage (

    input  wire                         clk,
    input  wire                         rst,

    // From EX/MEM
    input  wire [`WARP_ID_W-1:0]        wid_i,
    input  wire                         valid_i,
    input  wire [`MASK_W-1:0]           active_mask_i,
    input  wire [`PC_WIDTH-1:0]         pc_i,

    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] alu_result_i,
    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] mem_addr_i,
    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] store_data_i,

    input  wire [`REG_ID_W-1:0]         rd_i,

    input  wire                         reg_write_i,
    input  wire                         mem_read_i,
    input  wire                         mem_write_i,
    input  wire                         branch_taken_i,
    input  wire                         exit_i,

    // Interface to data_memory
    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_addr_o,
    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_write_data_o,
    output wire [`MASK_W-1:0]                dmem_write_mask_o,
    output wire                              dmem_write_en_o,
    output wire                              dmem_read_en_o,

    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_read_data_i,

    // To MEM/WB
    output reg  [`WARP_ID_W-1:0]        wid_o,
    output reg                          valid_o,
    output reg  [`MASK_W-1:0]           active_mask_o,
    output reg  [`PC_WIDTH-1:0]         pc_o,

    output reg  [`WARP_SIZE*`LANE_WIDTH-1:0] result_o,
    output reg  [`REG_ID_W-1:0]         rd_o,

    output reg                          reg_write_o,
    output reg                          branch_taken_o,
    output reg                          exit_o
);

    // Drive data memory interface

    assign dmem_addr_o       = mem_addr_i;
    assign dmem_write_data_o = store_data_i;
    assign dmem_write_mask_o = active_mask_i;
    assign dmem_write_en_o   = mem_write_i & valid_i;
    assign dmem_read_en_o    = mem_read_i & valid_i;

    // MEM/WB Pipeline Register

    always @(posedge clk) begin
        if (rst) begin
            wid_o           <= 0;
            valid_o         <= 0;
            active_mask_o   <= 0;
            pc_o            <= 0;
            
            result_o        <= 0;
            rd_o            <= 0;
            reg_write_o     <= 0;
            branch_taken_o  <= 0;
            exit_o          <= 0;
        end
        else begin
            wid_o         <= wid_i;
            valid_o       <= valid_i;
            active_mask_o <= active_mask_i;
            pc_o          <= pc_i;
            
            rd_o          <= rd_i;

            branch_taken_o <= branch_taken_i;
            exit_o         <= exit_i;

            // Select ALU result or memory result
            if (mem_read_i)
                result_o <= dmem_read_data_i;
            else
                result_o <= alu_result_i;

            reg_write_o <= reg_write_i;
        end
    end

endmodule