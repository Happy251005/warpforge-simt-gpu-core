// ============================================================
// Module: simt_stack
// Description:
//   Per-warp SIMT divergence/reconvergence stack.
//
//   Each warp has an independent LIFO stack of entries:
//       { target_pc, reconv_pc, active_mask }
//
//   Divergent branch pushes TWO entries atomically:
//     [sp  ] BARRIER : { RPC,  RPC,  full_mask  }
//     [sp+1] INNER   : { FT,   RPC,  else_mask  }   (sp+1 = top)
//
//   Reconvergence pop fires when warp_manager detects:
//       current_pc == top.reconv_pc
//   It pops INNER first (switching to else path), then later
//   pops BARRIER (restoring the pre-divergence mask at RPC).
//
//   SETRPC instruction writes pending_rpc[warp_id] which is
//   consumed at divergent push time.
//
//   Synthesisable: reg arrays (flip-flops), no BRAM.
// ============================================================

`include "cu_defs.vh"

module simt_stack (
    input  wire clk,
    input  wire rst,

    // SETRPC interface (from decode stage)
    input  wire                          setrpc_en,
    input  wire [`WARP_ID_W-1:0]         setrpc_wid,
    input  wire [`PC_WIDTH-1:0]          setrpc_val,

    // Divergent-push interface (from warp_manager, EX-stage)
    // Pushes BARRIER then INNER in a single clock edge.
    input  wire                          push_en,
    input  wire [`WARP_ID_W-1:0]         push_wid,
    input  wire [`PC_WIDTH-1:0]          push_fallthrough_pc,  // INNER.target_pc = FT
    input  wire [`MASK_W-1:0]            push_else_mask,       // INNER.active_mask
    input  wire [`MASK_W-1:0]            push_full_mask,       // BARRIER.active_mask

    // Pop interface (from warp_manager reconvergence logic)
    input  wire                          pop_en,
    input  wire [`WARP_ID_W-1:0]         pop_wid,

    // Clear pending_rpc interface (from warp_manager on branch resolution in EX)
    input  wire                          clear_rpc_en,
    input  wire [`WARP_ID_W-1:0]         clear_rpc_wid,

    // Peek interface (combinational, for the currently scheduled warp)
    input  wire [`WARP_ID_W-1:0]         peek_wid,
    output wire [`PC_WIDTH-1:0]          top_target_pc,
    output wire [`PC_WIDTH-1:0]          top_reconv_pc,
    output wire [`MASK_W-1:0]            top_active_mask,

    // Per-warp status
    output wire [`NUM_WARPS-1:0]         stack_empty,
    output wire [`NUM_WARPS-1:0]         stack_full
);

    // Stack storage (flip-flop arrays)
    reg [`PC_WIDTH-1:0]    s_target_pc   [`NUM_WARPS-1:0][`STACK_DEPTH-1:0];
    reg [`PC_WIDTH-1:0]    s_reconv_pc   [`NUM_WARPS-1:0][`STACK_DEPTH-1:0];
    reg [`MASK_W-1:0]      s_active_mask [`NUM_WARPS-1:0][`STACK_DEPTH-1:0];

    // Stack pointers (0 = empty)
    reg [`STACK_PTR_W-1:0] sp            [`NUM_WARPS-1:0];

    // Pending reconvergence PC staging register (set by SETRPC)
    reg [`PC_WIDTH-1:0]    pending_rpc   [`NUM_WARPS-1:0];

    integer i, j;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < `NUM_WARPS; i = i + 1) begin
                sp[i]          <= 0;
                pending_rpc[i] <= 0;
                for (j = 0; j < `STACK_DEPTH; j = j + 1) begin
                    s_target_pc  [i][j] <= 0;
                    s_reconv_pc  [i][j] <= 0;
                    s_active_mask[i][j] <= 0;
                end
            end
        end
        else begin
            // Clear pending_rpc on branch resolution in EX (all branch outcomes)
            if (clear_rpc_en)
                pending_rpc[clear_rpc_wid] <= {`PC_WIDTH{1'b0}};

            // SETRPC: update pending reconvergence PC for a warp
            if (setrpc_en)
                pending_rpc[setrpc_wid] <= setrpc_val;

            // Divergent push: write two entries in one clock edge
            // BARRIER at sp, INNER at sp+1 (becomes new top).
            // Silent no-op if fewer than 2 free slots.
            if (push_en && (sp[push_wid] <= `STACK_DEPTH - 2)) begin
                // BARRIER (lower)
                s_target_pc  [push_wid][sp[push_wid]]     <= pending_rpc[push_wid];
                s_reconv_pc  [push_wid][sp[push_wid]]     <= pending_rpc[push_wid];
                s_active_mask[push_wid][sp[push_wid]]     <= push_full_mask;
                // INNER / ELSE (upper = new top)
                s_target_pc  [push_wid][sp[push_wid] + 1] <= push_fallthrough_pc;
                s_reconv_pc  [push_wid][sp[push_wid] + 1] <= pending_rpc[push_wid];
                s_active_mask[push_wid][sp[push_wid] + 1] <= push_else_mask;

                sp[push_wid] <= sp[push_wid] + 2;
            end

            // Pop: decrement stack pointer
            if (pop_en && sp[pop_wid] > 0)
                sp[pop_wid] <= sp[pop_wid] - 1;
        end
    end

    // Combinational peek: top entry for peek_wid
    wire [`STACK_PTR_W-1:0] top_idx;
    assign top_idx = (sp[peek_wid] > 0) ? (sp[peek_wid] - 1) : 0;

    assign top_target_pc   = (sp[peek_wid] > 0) ? s_target_pc  [peek_wid][top_idx] : {`PC_WIDTH{1'b0}};
    assign top_reconv_pc   = (sp[peek_wid] > 0) ? s_reconv_pc  [peek_wid][top_idx] : {`PC_WIDTH{1'b0}};
    assign top_active_mask = (sp[peek_wid] > 0) ? s_active_mask[peek_wid][top_idx] : {`MASK_W{1'b0}};

    // Per-warp status
    genvar w;
    generate
        for (w = 0; w < `NUM_WARPS; w = w + 1) begin : GEN_STATUS
            assign stack_empty[w] = (sp[w] == 0);
            assign stack_full[w]  = (sp[w] >= `STACK_DEPTH - 1);
        end
    endgenerate

endmodule
