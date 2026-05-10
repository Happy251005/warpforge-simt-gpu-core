// ============================================================
// Instruction Fetch Unit (IFU)
// Fetches instruction for selected warp (1-cycle memory latency)
// ============================================================

`include "cu_defs.vh"

module instruction_fetch (
    input  wire clk,
    input  wire rst,

    // From Warp Manager
    input  wire                      issue_valid,
    input  wire [`WARP_ID_W-1:0]     current_wid,
    input  wire [`PC_WIDTH-1:0]      current_pc,
    input  wire [`MASK_W-1:0]        current_active_mask,

    // Squash signal
    input  wire                      squash,
    input  wire [`WARP_ID_W-1:0]     squash_wid,

    // To Instruction Memory
    output wire [`PC_WIDTH-1:0]      imem_addr,
    input  wire [`INST_WIDTH-1:0]    imem_rdata,

    // To Decode Stage (IF/ID pipeline outputs)
    output reg  [`INST_WIDTH-1:0]    if_instruction,
    output reg  [`WARP_ID_W-1:0]     if_wid,
    output reg                       if_valid,
    output reg  [`MASK_W-1:0]        if_active_mask,
    output reg  [`PC_WIDTH-1:0]      if_pc
);

    assign imem_addr = current_pc;

    // Fetch logic
    always @(posedge clk) begin
        if(rst) begin
            if_instruction <= 0;
            if_wid <= 0;
            if_valid <= 0;
            if_active_mask <= 0;
            if_pc <= 0;
        end
        else begin
            if_instruction <= imem_rdata;
            if_wid <= current_wid;
            if_active_mask <= current_active_mask;
            if_pc <= current_pc;

            if(squash && squash_wid == current_wid)
                if_valid <= 0;
            else
                if_valid <= issue_valid;
        end
    end
endmodule
