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
    // Branch Commit Interface
    // (from writeback stage)
    // ============================
    input  wire                         branch_commit,
    input  wire [`WARP_ID_W-1:0]        branch_wid,
    input  wire [`PC_WIDTH-1:0]         branch_target,
    input  wire [`MASK_W-1:0]           branch_mask,

    // Branch resolve interface — fires on any branch (taken OR not-taken)
    input  wire                         branch_resolve,

    // ============================
    // Scoreboard Unblock Interface
    // (from writeback via scoreboard clear)
    // ============================
    input  wire                         clear_en,
    input  wire [`WARP_ID_W-1:0]        clear_wid,

    // ============================
    // Exit Interface
    // (from writeback stage)
    // ============================
    input  wire                         exit_en,
    input  wire [`WARP_ID_W-1:0]        exit_wid,

    // ============================
    // Scoreboard Stall Interface
    // (from scoreboard)
    // ============================
    input  wire                         scoreboard_stall,
    input  wire [`WARP_ID_W-1:0]        scoreboard_stall_wid,
    input  wire                         scoreboard_stall_cause, // 0: register conflict, 1: branch
    input  wire [`PC_WIDTH-1:0]         stall_pc, // from if_id registers

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

    reg [`PC_WIDTH-1:0]     pc_array        [0:`NUM_WARPS-1];
    reg [`MASK_W-1:0]       active_mask_array [0:`NUM_WARPS-1];
    reg [`WARP_STATE_W-1:0] warp_state_array  [0:`NUM_WARPS-1];

    reg [`WARP_ID_W-1:0]    rr_ptr;
    reg                     found;
    reg [`WARP_ID_W-1:0]    temp_id;
    reg [`WARP_ID_W-1:0]    idx;

    reg [`NUM_WARPS-1:0]    stall_cause; // 0: register conflict, 1: branch

    integer i;

    // ============================
    // Read logic
    // ============================
    assign current_pc          = pc_array[current_wid];
    assign current_active_mask = active_mask_array[current_wid];

    // ============================
    // Round-robin scheduler
    // ============================
    always @(*) begin
        found   = 0;
        temp_id = rr_ptr;

        for (i = 0; i < `NUM_WARPS; i = i + 1) begin
            idx = rr_ptr + i;
            if (idx >= `NUM_WARPS)
                idx = idx - `NUM_WARPS;

            if (!found && warp_state_array[idx] == `WARP_READY) begin
                temp_id = idx;
                found   = 1;
            end
        end
    end

    assign current_wid  = temp_id;
    assign issue_valid  = found;

    // ============================
    // State and PC update
    // ============================
    always @(posedge clk) begin
        if (rst) begin
            rr_ptr <= 0;
            for (i = 0; i < `NUM_WARPS; i = i + 1) begin
                pc_array[i]           <= 0;
                active_mask_array[i]  <= `FULL_MASK;
                warp_state_array[i]   <= `WARP_READY;
            end
        end
        else begin

            // --- Issue: increment PC ---
            //  explicit priority — don't pre-increment if this warp is being stalled this cycle
            if (issue_valid && !(scoreboard_stall && scoreboard_stall_wid == temp_id)) begin
                pc_array[temp_id] <= current_pc + 4;
                if (temp_id == `NUM_WARPS-1)
                    rr_ptr <= 0;
                else
                    rr_ptr <= temp_id + 1;
            end

            // --- Scoreboard stall: mark warp STALL ---
            if (scoreboard_stall) begin
                warp_state_array[scoreboard_stall_wid] <= `WARP_STALL;
                stall_cause[scoreboard_stall_wid] <= scoreboard_stall_cause;
                    if (scoreboard_stall_cause)  // branch stall
                        pc_array[scoreboard_stall_wid] <= stall_pc + 4;
                    else                         // register hazard stall
                        pc_array[scoreboard_stall_wid] <= stall_pc;
            end

            // --- Scoreboard clear: unblock stalled warp ---
            if (clear_en && warp_state_array[clear_wid] == `WARP_STALL
                && stall_cause[clear_wid] == 0
                && !(exit_en && exit_wid == clear_wid)
                && !(scoreboard_stall && scoreboard_stall_wid == clear_wid))
                warp_state_array[clear_wid] <= `WARP_READY;

            // --- Branch commit: update PC and mask (taken branch) ---
            if (branch_commit) begin
                pc_array[branch_wid]          <= branch_target;
                active_mask_array[branch_wid] <= branch_mask;
                warp_state_array[branch_wid]  <= `WARP_READY;
            end

            // --- Branch resolve: unblock on not-taken branch ---
            if (branch_resolve && !branch_commit
                && warp_state_array[branch_wid] == `WARP_STALL
                && stall_cause[branch_wid] == 1)
                warp_state_array[branch_wid] <= `WARP_READY;

            // --- Exit: mark warp DONE ---
            if (exit_en)
                warp_state_array[exit_wid] <= `WARP_DONE;

        end
    end

endmodule