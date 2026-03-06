// ============================================================
// Instruction Fetch Unit (IFU)
// Fetches instruction for selected warp (1-cycle memory latency)
// ============================================================

`include "cu_defs.vh"

module instruction_fetch (
    input  wire clk,
    input  wire rst,

    // From Warp Manager
    input  wire                     issue_valid,
    input  wire [`WARP_ID_W-1:0]     current_wid,
    input  wire [`PC_WIDTH-1:0]      current_pc,
    input  wire [`MASK_W-1:0]        current_active_mask,

    // To Instruction Memory
    output wire [`PC_WIDTH-1:0]      imem_addr,
    input  wire [`INST_WIDTH-1:0]    imem_rdata,

    // To Decode Stage (IF/ID pipeline outputs)
    output reg  [`INST_WIDTH-1:0]    if_instruction,
    output reg  [`WARP_ID_W-1:0]     if_wid,
    output reg                       if_valid,
    output reg  [`MASK_W-1:0]        if_active_mask
);
    reg [`WARP_ID_W-1:0] wid_d;
    reg valid_d;
    reg [`MASK_W-1:0] active_mask_d;
    assign imem_addr = current_pc;

    // Fetch logic — single pipeline stage
    // Capture instruction and metadata together so they stay aligned
    always @(posedge clk) begin
        if(rst) begin
            if_instruction <= 0;
            if_wid <= 0;
            if_valid <= 0;
            if_active_mask <= 0;
        end
        else begin
            if_instruction <= imem_rdata;
            if_wid <= current_wid;
            if_valid <= issue_valid;
            if_active_mask <= current_active_mask;
        end
    end
endmodule
