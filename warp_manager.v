// ============================================================
// Warp Manager
// Merged Warp Context File + Warp Scheduler
// Stores warp state and selects next READY warp
// ============================================================

`include "cu_defs.vh"

module warp_manager (
    input  wire clk,
    input  wire rst,

    // ============================
    // Commit / Update Interface
    // (from execute/commit stage)
    // ============================

    input  wire                         write_en,
    input  wire [`WARP_ID_W-1:0]        write_wid,
    input  wire [`PC_WIDTH-1:0]         write_pc,
    input  wire [`MASK_W-1:0]           write_active_mask,
    input  wire [`WARP_STATE_W-1:0]     write_warp_state,

    // ============================
    // Scheduling Output
    // ============================

    output wire [`WARP_ID_W-1:0]        current_wid,
    output wire                         issue_valid,

    // ============================
    // Read Access for Selected Warp
    // (used by fetch stage)
    // ============================

    output wire [`PC_WIDTH-1:0]         current_pc,
    output wire [`MASK_W-1:0]           current_active_mask
);
    
    reg [`PC_WIDTH-1:0]      pc_array [0:`NUM_WARPS-1];
    reg [`MASK_W-1:0]        active_mask_array [0:`NUM_WARPS-1];
    reg [`WARP_STATE_W-1:0]  warp_state_array [0:`NUM_WARPS-1];
    reg [`WARP_ID_W-1:0] rr_ptr; // Round-robin pointer
    reg found; // Flag to indicate if a READY warp was found
    reg [`WARP_ID_W-1:0] temp_id; // Temporary variable to hold warp ID during scheduling
    reg [`WARP_ID_W-1:0] idx; // Index variable for loop iteration

    integer i;

    // Read logic
    assign current_pc = pc_array[current_wid];
    assign current_active_mask = active_mask_array[current_wid];

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

        else if(found) begin
            pc_array[temp_id] <= pc_array[temp_id] + 4; // Increment PC by 4 for next instruction
        end
    end

    always @(*) begin
        found = 0;
        temp_id = rr_ptr;

        for (i = 0; i < `NUM_WARPS; i++) begin
            idx = rr_ptr + i;
            if (idx >= `NUM_WARPS)
                idx = idx - `NUM_WARPS;

            if (!found && warp_state_array[idx] == `WARP_READY) begin
                temp_id = idx;
                found = 1;
            end
        end

    end

    assign current_wid = temp_id;
    assign issue_valid = found;

    always @(posedge clk) begin

        if(rst) begin
            rr_ptr <= 0;
        end

        else if(found) begin
            if (temp_id == `NUM_WARPS-1)
                rr_ptr <= 0;
            else
                rr_ptr <= temp_id + 1;
        end

    end
endmodule
