// ============================================================
// Module: vector_alu
// Description:
//   Per-lane SIMD ALU
//   Pure combinational
//   Sign-extended immediate
//   Per-lane branch condition exposed for SIMT divergence (v2)
// ============================================================

`include "cu_defs.vh"

module vector_ALU (

    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] rs_flat_i,
    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] rt_flat_i,
    input  wire [`IMM_W-1:0]                 imm_i,

    input  wire [`MASK_W-1:0]                active_mask_i,
    input  wire [`FUNC_W-1:0]                alu_func_i,
    input  wire                              alu_src_imm_i,
    input  wire                              branch_i,
    input  wire                              branch_inv_i,
    input  wire [2:0]                        instr_class_i,

    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] result_flat_o,
    output wire                              branch_taken_o,

    // SIMT divergence: per-lane branch outcome
    //   take_mask_o[l] = 1 iff lane l is active AND would take the branch
    //   else_mask_o[l] = 1 iff lane l is active AND would NOT take the branch
    //   Inactive lanes contribute 0 to both.
    //   branch_taken_o remains the warp-wide UNIFORM decision (backward compat).
    output wire [`MASK_W-1:0]                take_mask_o,
    output wire [`MASK_W-1:0]                else_mask_o
);

    wire [`LANE_WIDTH-1:0] imm_ext;
    assign imm_ext = {{(`LANE_WIDTH-`IMM_W){imm_i[`IMM_W-1]}}, imm_i};

    genvar lane;

    wire [`WARP_SIZE-1:0] branch_lane_eq;
    // per-lane: 1 if this active lane would take the branch
    wire [`WARP_SIZE-1:0] lane_takes;

    generate
        for (lane = 0; lane < `WARP_SIZE; lane = lane + 1) begin : ALU_LANES

            wire [`LANE_WIDTH-1:0] rs_lane;
            wire [`LANE_WIDTH-1:0] rt_lane;
            reg  [`LANE_WIDTH-1:0] result_lane;

            assign rs_lane = rs_flat_i[(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH];
            assign rt_lane = rt_flat_i[(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH];

            always @(*) begin
                if(!active_mask_i[lane]) begin
                    result_lane = 0;
                end
                else begin
                    case (alu_func_i)

                        `FUNC_ADD: result_lane = rs_lane + (alu_src_imm_i ? imm_ext : rt_lane);
                        `FUNC_SUB: result_lane = rs_lane - rt_lane;
                        `FUNC_AND: result_lane = rs_lane & rt_lane;
                        `FUNC_OR:  result_lane = rs_lane | rt_lane;
                        `FUNC_XOR: result_lane = rs_lane ^ rt_lane;
                        `FUNC_SLT: result_lane = ($signed(rs_lane) < $signed(rt_lane)) ? 1 : 0;
                        default:   result_lane = 0;

                    endcase
                end
            end

            assign result_flat_o[(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH] = result_lane;

            // inactive lanes treated as "agree" so they don't veto uniform decision
            assign branch_lane_eq[lane] = (!active_mask_i[lane]) | (rs_lane == rt_lane);

            // lane_takes: active AND condition holds (eq for BEQ, ne for BNE)
            assign lane_takes[lane] = active_mask_i[lane] &
                                      (branch_inv_i ? (rs_lane != rt_lane)
                                                    : (rs_lane == rt_lane));

        end
    endgenerate

    // Warp-wide uniform branch decision (unchanged)
    assign branch_taken_o = branch_i ? (&branch_lane_eq ^ branch_inv_i) : 1'b0;

    // Per-lane divergence masks (zero when not a branch instruction)
    assign take_mask_o = branch_i ? lane_takes                    : {`MASK_W{1'b0}};
    assign else_mask_o = branch_i ? (active_mask_i & ~lane_takes) : {`MASK_W{1'b0}};

endmodule
