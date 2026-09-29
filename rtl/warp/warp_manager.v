// ============================================================
// Module: warp_manager  (v2 — SIMT divergence support)
//
// Changes from v1:
//   • Branch resolution moved from WB to EX stage.
//     - branch_commit / branch_resolve (WB) no longer used for
//       state updates; inputs retained but ignored to avoid
//       breaking compute_unit wiring during migration.
//   • branch_pending[] per-warp flag guards exactly-once
//     EX resolution.
//   • SIMT stack push driven from here for divergent branches.
//   • Reconvergence check (current_pc == top.reconv_pc) runs
//     combinationally before fetch; overrides current_pc and
//     current_active_mask transparently.  Also drives pop_en.
//   • active_mask_array updated on divergent branch (take_mask)
//     and on reconvergence (stack top mask).
// ============================================================

`include "cu_defs.vh"

module warp_manager (
    input  wire clk,
    input  wire rst,

    // ============================
    // WB-stage Branch interfaces  (kept for wiring compatibility;
    //                              no longer drive state changes)
    // ============================
    input  wire                         branch_commit,      // legacy – unused for state
    input  wire [`WARP_ID_W-1:0]        branch_wid,
    input  wire [`PC_WIDTH-1:0]         branch_target,
    input  wire [`MASK_W-1:0]           branch_mask,
    input  wire                         branch_resolve,     // legacy – unused for state

    // ============================
    // Scoreboard Unblock (RAW clear from WB)
    // ============================
    input  wire                         clear_en,
    input  wire [`WARP_ID_W-1:0]        clear_wid,

    // ============================
    // Exit (from WB)
    // ============================
    input  wire                         exit_en,
    input  wire [`WARP_ID_W-1:0]        exit_wid,

    // ============================
    // Scoreboard stall (from scoreboard, combinational)
    // ============================
    input  wire                         scoreboard_stall,
    input  wire [`WARP_ID_W-1:0]        scoreboard_stall_wid,
    input  wire                         scoreboard_stall_cause, // 0=RAW, 1=branch
    input  wire [`PC_WIDTH-1:0]         stall_pc,    // if_id_pc

    // ============================
    // EX-stage branch resolution  (combinational from execute_stage)
    // These signals are valid for exactly the one cycle during which
    // a branch instruction occupies the EX stage.
    // ============================
    input  wire                         ex_valid,            // id_ex_valid
    input  wire [`WARP_ID_W-1:0]        ex_wid,              // id_ex_wid
    input  wire                         ex_branch,           // id_ex_branch
    input  wire [`MASK_W-1:0]           ex_take_mask,        // from vector_ALU
    input  wire [`MASK_W-1:0]           ex_else_mask,        // from vector_ALU
    input  wire [`PC_WIDTH-1:0]         ex_branch_target,    // branch target PC

    // ============================
    // SIMT stack interface
    //   Push is driven by warp_manager when a divergent branch
    //   reaches EX.  Pop is driven on reconvergence.
    // ============================
    // Push outputs → simt_stack
    output wire                         simt_push_en,
    output wire [`WARP_ID_W-1:0]        simt_push_wid,
    output wire [`PC_WIDTH-1:0]         simt_push_fallthrough,  // = pc_array[ex_wid] at stall
    output wire [`MASK_W-1:0]           simt_push_else_mask,
    output wire [`MASK_W-1:0]           simt_push_full_mask,

    // Pop outputs → simt_stack
    output wire                         simt_pop_en,
    output wire [`WARP_ID_W-1:0]        simt_pop_wid,

    // Clear pending_rpc output → simt_stack (on any branch resolution in EX)
    output wire                         simt_clear_rpc_en,
    output wire [`WARP_ID_W-1:0]        simt_clear_rpc_wid,

    // Peek inputs ← simt_stack (for the currently scheduled warp)
    input  wire [`PC_WIDTH-1:0]         simt_top_reconv_pc,
    input  wire [`PC_WIDTH-1:0]         simt_top_target_pc,
    input  wire [`MASK_W-1:0]           simt_top_mask,
    input  wire [`NUM_WARPS-1:0]        simt_stack_empty,

    // ============================
    // Scheduling outputs
    // ============================
    output wire [`WARP_ID_W-1:0]        current_wid,
    output wire                         issue_valid,

    // Read access for selected warp (→ IFU)
    // current_pc and current_active_mask are overridden during
    // reconvergence so the IFU fetches the else-path entry.
    output wire [`PC_WIDTH-1:0]         current_pc,
    output wire [`MASK_W-1:0]           current_active_mask
);

    reg [`PC_WIDTH-1:0]     pc_array         [0:`NUM_WARPS-1];
    reg [`MASK_W-1:0]       active_mask_array[0:`NUM_WARPS-1];
    reg [`WARP_STATE_W-1:0] warp_state_array [0:`NUM_WARPS-1];

    reg [`WARP_ID_W-1:0]    rr_ptr;
    reg                     found;
    reg [`WARP_ID_W-1:0]    temp_id;
    reg [`WARP_ID_W-1:0]    idx;

    // stall_cause[w]: 0 = RAW, 1 = branch
    reg [`NUM_WARPS-1:0]    stall_cause;

    // branch_pending[w]: set when a branch stall fires for warp w;
    // cleared when EX resolution fires.  Prevents duplicate resolutions.
    reg [`NUM_WARPS-1:0]    branch_pending;

    integer i;

    // ============================
    // Round-robin scheduler (combinational)
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
    // EX-stage branch resolution (combinational decode)
    // ============================
    wire ex_resolves   = ex_valid && ex_branch && branch_pending[ex_wid];
    wire ex_divergent  = ex_resolves && (ex_take_mask != {`MASK_W{1'b0}})
                                     && (ex_else_mask != {`MASK_W{1'b0}});
    wire ex_uni_taken  = ex_resolves && (ex_else_mask == {`MASK_W{1'b0}})
                                     && (ex_take_mask != {`MASK_W{1'b0}});
    // ex_uni_not_taken: take_mask==0; PC already stored as fall-through at stall time

    // ============================
    // SIMT stack push signals (combinational, driven on divergent EX)
    // ============================
    assign simt_push_en          = ex_divergent;
    assign simt_push_wid         = ex_wid;
    assign simt_push_fallthrough = pc_array[ex_wid];  // fall-through saved at stall time
    assign simt_push_else_mask   = ex_else_mask;
    assign simt_push_full_mask   = active_mask_array[ex_wid]; // pre-divergence mask

    // Clear pending_rpc on ANY branch resolution in EX (uniform taken, uniform not-taken, divergent)
    assign simt_clear_rpc_en     = ex_resolves;
    assign simt_clear_rpc_wid    = ex_wid;

    // ============================
    // Reconvergence detection (combinational, for current/scheduled warp)
    // Fires when current warp's PC matches the reconv_pc at top of stack.
    // ============================
    wire reconv_hit;
    assign reconv_hit = issue_valid
                     && !simt_stack_empty[temp_id]
                     && (pc_array[temp_id] == simt_top_reconv_pc);

    // Override fetch PC and mask during reconvergence
    assign current_pc          = reconv_hit ? simt_top_target_pc : pc_array[temp_id];
    assign current_active_mask = reconv_hit ? simt_top_mask      : active_mask_array[temp_id];

    // Pop the stack when reconvergence fires (and we actually issue this cycle)
    assign simt_pop_en  = reconv_hit && issue_valid
                       && !(scoreboard_stall && scoreboard_stall_wid == temp_id);
    assign simt_pop_wid = temp_id;

    // ============================
    // Clocked state and PC updates
    // ============================
    always @(posedge clk) begin
        if (rst) begin
            rr_ptr <= 0;
            for (i = 0; i < `NUM_WARPS; i = i + 1) begin
                pc_array[i]          <= 0;
                active_mask_array[i] <= `FULL_MASK;
                warp_state_array[i]  <= `WARP_READY;
                stall_cause[i]       <= 0;
                branch_pending[i]    <= 0;
            end
        end
        else begin

            // --------------------------------------------------
            // Priority 1: EX-stage branch resolution
            // Fires when a branch is in EX and branch_pending is set.
            // This takes priority over scoreboard_stall for the same warp
            // (which cannot happen simultaneously as argued in the design doc,
            //  but the priority guard is retained for clarity).
            // --------------------------------------------------
            if (ex_resolves) begin
                branch_pending[ex_wid]   <= 1'b0;
                warp_state_array[ex_wid] <= `WARP_READY;

                if (ex_divergent) begin
                    // Taken path executes first; else path is on the stack
                    pc_array[ex_wid]          <= ex_branch_target;
                    active_mask_array[ex_wid] <= ex_take_mask;
                end
                else if (ex_uni_taken) begin
                    // Uniform taken: jump to target, mask unchanged
                    pc_array[ex_wid] <= ex_branch_target;
                    // active_mask_array unchanged
                end
                // Uniform not-taken: pc_array already set to fall-through at stall time;
                // active_mask_array unchanged.
            end

            // --------------------------------------------------
            // Priority 2: Scoreboard stall
            // Only apply to a warp not simultaneously being resolved by EX.
            // --------------------------------------------------
            if (scoreboard_stall
                && !(ex_resolves && scoreboard_stall_wid == ex_wid))
            begin
                warp_state_array[scoreboard_stall_wid] <= `WARP_STALL;
                stall_cause[scoreboard_stall_wid]      <= scoreboard_stall_cause;

                if (scoreboard_stall_cause) begin  // branch stall
                    pc_array[scoreboard_stall_wid] <= stall_pc + 4; // save fall-through
                    branch_pending[scoreboard_stall_wid] <= 1'b1;
                end
                else begin                          // RAW stall
                    pc_array[scoreboard_stall_wid] <= stall_pc; // re-issue same instr
                end
            end

            // --------------------------------------------------
            // RAW unblock: clear_en from WB releases a RAW-stalled warp
            // --------------------------------------------------
            if (clear_en
                && warp_state_array[clear_wid] == `WARP_STALL
                && stall_cause[clear_wid] == 0
                && !(exit_en && exit_wid == clear_wid)
                && !(scoreboard_stall && scoreboard_stall_wid == clear_wid))
            begin
                warp_state_array[clear_wid] <= `WARP_READY;
            end

            // --------------------------------------------------
            // Exit: mark warp DONE
            // --------------------------------------------------
            if (exit_en)
                warp_state_array[exit_wid] <= `WARP_DONE;

            // --------------------------------------------------
            // Issue: increment PC and advance round-robin pointer.
            // current_pc is overridden by reconv_hit when applicable,
            // so pc_array[temp_id] receives the correct post-reconv value.
            // Also update active_mask_array on reconvergence.
            // --------------------------------------------------
            if (issue_valid
                && !(scoreboard_stall && scoreboard_stall_wid == temp_id))
            begin
                pc_array[temp_id] <= current_pc + 4; // current_pc may be overridden

                if (reconv_hit)
                    active_mask_array[temp_id] <= simt_top_mask;

                if (temp_id == `NUM_WARPS-1)
                    rr_ptr <= 0;
                else
                    rr_ptr <= temp_id + 1;
            end

        end // else (not rst)
    end // always

endmodule