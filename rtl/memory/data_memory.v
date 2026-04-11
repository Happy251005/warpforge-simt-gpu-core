// ============================================================
// Module: data_memory
// Description:
//   Shared data memory for SIMT core
//   - Word addressed
//   - 1-cycle synchronous read
//   - Initialized from data.mem
// ============================================================

`include "cu_defs.vh"

module data_memory (

    input  wire                         clk,

    // Per-lane interface
    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] addr_i,
    input  wire [`WARP_SIZE*`LANE_WIDTH-1:0] write_data_i,
    input  wire [`MASK_W-1:0]                write_mask_i,
    input  wire                              mem_write_i,

    output wire [`WARP_SIZE*`LANE_WIDTH-1:0] read_data_o
);

    reg [`LANE_WIDTH-1:0] mem [0:1023];

    initial begin
        $readmemh("programs/data.mem", mem);
    end

    genvar lane;
    generate
        for (lane = 0; lane < `WARP_SIZE; lane = lane + 1) begin : DATA_LANES

            wire [`LANE_WIDTH-1:0] addr_lane;
            wire [`LANE_WIDTH-1:0] write_lane;

            assign addr_lane  = addr_i  [(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH];
            assign write_lane = write_data_i[(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH];

            // WRITE — synchronous
            always @(posedge clk) begin
                if (mem_write_i && write_mask_i[lane])
                    mem[addr_lane] <= write_lane;
            end

            // READ — combinational
            assign read_data_o[(lane+1)*`LANE_WIDTH-1 -: `LANE_WIDTH]
                = mem[addr_lane[`LANE_WIDTH-1:2]];

        end
    endgenerate

endmodule