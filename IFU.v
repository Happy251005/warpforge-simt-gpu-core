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

    // To Instruction Memory
    output wire [`PC_WIDTH-1:0]      imem_addr,
    input  wire [`INST_WIDTH-1:0]    imem_rdata,

    // To Decode Stage (IF/ID pipeline outputs)
    output reg  [`INST_WIDTH-1:0]    if_instruction,
    output reg  [`WARP_ID_W-1:0]     if_wid,
    output reg                       if_valid
);
    reg [`WARP_ID_W-1:0] wid_d;
    reg valid_d;

    assign imem_addr = current_pc;

    // Fetch logic
    always @(posedge clk) begin
        if(rst) begin
            wid_d <= 0;
            valid_d <= 0;
            if_instruction <= 0;
            if_wid <= 0;

        end
        else begin
            wid_d <= current_wid;
            valid_d <= issue_valid;
            if_instruction <= imem_rdata;
            if_wid <= wid_d;
            if_valid <= valid_d;
        end
    end
endmodule
