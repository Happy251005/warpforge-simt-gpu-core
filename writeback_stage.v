// ============================================================
// Module: writeback_stage
// Description:
//   WB stage of 4-stage SIMT pipeline
//   - Writes ALU results to VRF
//   - Marks warp DONE on EXIT
//   - No branch handling (v1)
// ============================================================

`include "cu_defs.vh"

module writeback_stage (

    input  wire                         clk,
    input  wire                         rst,

    // From EX/WB
    input  wire [`WARP_ID_W-1:0]        wid_i,
    input  wire                         valid_i,
    input  wire [`MASK_W-1:0]           active_mask_i,

    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] result_flat_i,
    input  wire [`REG_ID_W-1:0]         rd_i,

    input  wire                         reg_write_i,
    input  wire                         exit_i,


    // To VRF
    output wire                         vrf_reg_write_o,
    output wire [`WARP_ID_W-1:0]        vrf_wid_o,
    output wire [`REG_ID_W-1:0]         vrf_rd_o,
    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] vrf_write_data_o,


    // To Warp Manager
    output reg                          warp_update_en_o,
    output reg  [`WARP_ID_W-1:0]        warp_update_wid_o,
    output reg  [`WARP_STATE_W-1:0]     warp_update_state_o

);

    // VRF Write
    assign vrf_reg_write_o  = reg_write_i & valid_i;
    assign vrf_wid_o        = wid_i;
    assign vrf_rd_o         = rd_i;
    assign vrf_write_data_o = result_flat_i;


    // EXIT Handling

    always @(posedge clk) begin
        if (rst) begin
            warp_update_en_o    <= 0;
            warp_update_wid_o   <= 0;
            warp_update_state_o <= 0;
        end
        else begin
            if (valid_i && exit_i) begin
                warp_update_en_o    <= 1;
                warp_update_wid_o   <= wid_i;
                warp_update_state_o <= `WARP_DONE;
            end
            else begin
                warp_update_en_o    <= 0;
            end
        end
    end

endmodule