// ============================================================
// Module: writeback_stage
// Description:
//   WB stage of 5-stage SIMT pipeline
//   - Writes ALU or LOAD result to VRF
//   - Marks warp DONE on EXIT
//   - No branch PC correction (v1)
// ============================================================

`include "cu_defs.vh"

module writeback_stage (

    input  wire                         clk,
    input  wire                         rst,

    // From MEM/WB
    input  wire [`WARP_ID_W-1:0]        wid_i,
    input  wire                         valid_i,
    input  wire [`MASK_W-1:0]           active_mask_i,
    input  wire [`PC_WIDTH-1:0]         pc_i,

    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] result_i,
    input  wire [`REG_ID_W-1:0]         rd_i,

    input  wire                         reg_write_i,
    input  wire                         exit_i,


    // To VRF

    output wire                         vrf_reg_write_o,
    output wire [`WARP_ID_W-1:0]        vrf_wid_o,
    output wire [`REG_ID_W-1:0]         vrf_rd_o,
    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] vrf_write_data_o,
    output wire [`MASK_W-1:0]           vrf_write_mask_o,


    // To Warp Manager

    output reg                          warp_update_en_o,
    output reg  [`WARP_ID_W-1:0]        warp_update_wid_o,
    output reg  [`WARP_STATE_W-1:0]     warp_update_state_o,
    output reg  [`PC_WIDTH-1:0]         warp_update_pc_o,
    output reg  [`MASK_W-1:0]           warp_update_mask_o

);

    // VRF Write

    assign vrf_reg_write_o  = reg_write_i & valid_i;
    assign vrf_wid_o        = wid_i;
    assign vrf_rd_o         = rd_i;
    assign vrf_write_data_o = result_i;
    assign vrf_write_mask_o = active_mask_i;


    // EXIT Handling

    always @(posedge clk) begin
        if (rst) begin
            warp_update_en_o    <= 0;
            warp_update_wid_o   <= 0;
            warp_update_state_o <= `WARP_READY;
            warp_update_pc_o    <= 0;
            warp_update_mask_o  <= 0;
        end
        else begin
            if (valid_i) begin
                warp_update_en_o    <= 1;
                warp_update_wid_o   <= wid_i;
                warp_update_mask_o  <= active_mask_i;

                if(exit_i) begin
                    warp_update_state_o <= `WARP_DONE;
                    warp_update_pc_o    <= pc_i; // Not used for DONE warps
                end
                else begin
                    warp_update_state_o <= `WARP_READY;
                    warp_update_pc_o    <= pc_i + 4; // No PC update on non-EXIT instructions in v1
                end
            end
            else begin
                warp_update_en_o <= 0;
            end
        end
    end

endmodule