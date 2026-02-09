// ============================================================
// Warp Context File (WCF)
// Stores PC, active mask, and state for each warp
// ============================================================

`include "cu_defs.vh"

module warp_context_file (
    input  wire                    clk,
    input  wire                    rst,

    // Read port
    input  wire [`WARP_ID_W-1:0]     read_wid,
    output wire [`PC_WIDTH-1:0]      read_pc,
    output wire [`MASK_W-1:0]        read_active_mask,
    output wire [`WARP_STATE_W-1:0]  read_warp_state,

    // Write port
    input  wire                     write_en,
    input  wire [`WARP_ID_W-1:0]     write_wid,
    input  wire [`PC_WIDTH-1:0]      write_pc,
    input  wire [`MASK_W-1:0]        write_active_mask,
    input  wire [`WARP_STATE_W-1:0]  write_warp_state
);

    // The context
    reg [`PC_WIDTH-1:0]      pc_array [0:`NUM_WARPS-1];
    reg [`MASK_W-1:0]        active_mask_array [0:`NUM_WARPS-1];
    reg [`WARP_STATE_W-1:0]  warp_state_array [0:`NUM_WARPS-1];
    
    integer i;

    // Read logic
    assign read_pc = pc_array[read_wid];
    assign read_active_mask = active_mask_array[read_wid];
    assign read_warp_state = warp_state_array[read_wid];

    // Write logic
    always @(posedge clk) begin

        if(rst) begin
            // Initialize all warps to PC=0, all lanes active, state=READY
            for (i = 0; i < `NUM_WARPS; i = i + 1) begin
                pc_array[i] <= 0;
                active_mask_array[i] <= `FULL_MASK;
                warp_state_array[i] <= `WARP_READY;
            end
        end 
        
        else if(write_en) begin
            pc_array[write_wid] <= write_pc;
            active_mask_array[write_wid] <= write_active_mask;
            warp_state_array[write_wid] <= write_warp_state;
        end
    end

endmodule
