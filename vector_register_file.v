// ============================================================
// Module: vector_register_file
// Description:
//   Unified SIMT Vector Register File
//   Structure: regfile[warp][lane][reg]
//   - 2 read ports
//   - 1 write port
//   - Per-lane parallel access
//   - No hazard handling (v1)
// ============================================================

`include "cu_defs.vh"

module vector_register_file (

    input  wire                         clk,
    input  wire                         rst,

    // Warp selection
    input  wire [`WARP_ID_W-1:0]        read_wid_i,
    input  wire [`WARP_ID_W-1:0]        write_wid_i,
    input  wire [`MASK_W-1:0]           write_mask_i,

    // Read ports
    input  wire [`REG_ID_W-1:0]         rs_i,
    input  wire [`REG_ID_W-1:0]         rt_i,

    // Write port
    input  wire                         reg_write_i,
    input  wire [`REG_ID_W-1:0]         rd_i,
    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] write_data_i,

    // Read outputs
    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] rs_data_o,
    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] rt_data_o

);

    reg [`LANE_WIDTH-1:0] regfile
        [0:`NUM_WARPS-1]
        [0:`WARP_SIZE-1]
        [0:`NUM_VREGS-1];

    integer w, l, r;

    // Reset + Write
    always @(posedge clk) begin
        if (rst) begin
            for (w = 0; w < `NUM_WARPS; w = w + 1)
                for (l = 0; l < `WARP_SIZE; l = l + 1) begin
                    for (r = 0; r < `NUM_VREGS; r = r + 1)
                        regfile[w][l][r] <= 0;

                    regfile[w][l][`REG_TID] <= w * `WARP_SIZE + l;
                end
        end
        else if (reg_write_i && (rd_i != `REG_ZERO)) begin
            for (l = 0; l < `WARP_SIZE; l = l + 1)
                if (write_mask_i[l])
                    regfile[write_wid_i][l][rd_i] <= write_data_i[(l+1)*`LANE_WIDTH-1 -: `LANE_WIDTH];
        end
    end

    // Combinational read
    genvar lane;
    generate
        for (lane = 0; lane < `WARP_SIZE; lane = lane + 1) begin : READS
            assign rs_data_o[(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH] =
                regfile[read_wid_i][lane][rs_i];

            assign rt_data_o[(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH] =
                regfile[read_wid_i][lane][rt_i];
        end
    endgenerate

endmodule
