// Top module

`include "cu_defs.vh"
module top (
    input wire clk,
    input wire rst
);

// compute unit -> instruction memory
wire [`PC_WIDTH-1:0]   instr_addr;
wire [`INST_WIDTH-1:0] instr_data;

// compute unit -> data memory
wire [`WARP_SIZE*`LANE_WIDTH-1:0] data_addr;
wire [`WARP_SIZE*`LANE_WIDTH-1:0] write_data;
wire [`MASK_W-1:0]                write_mask;
wire                              mem_write;

wire [`WARP_SIZE*`LANE_WIDTH-1:0] read_data;

instruction_memory u_instruction_memory (
    .clk(clk),
    .addr(instr_addr),
    .rdata(instr_data)
);

data_memory u_data_memory (
    .clk(clk),
    .addr_i(data_addr),
    .write_data_i(write_data),
    .write_mask_i(write_mask),
    .mem_write_i(mem_write),
    .read_data_o(read_data)
);

compute_unit u_compute_unit (
    .clk(clk),
    .rst(rst),

    .imem_addr_o(instr_addr),
    .imem_rdata_i(instr_data),

    .dmem_addr_flat_o(data_addr),
    .dmem_wdata_flat_o(write_data),
    .dmem_write_mask_o(write_mask),
    .dmem_write_en_o(mem_write),

    .dmem_rdata_flat_i(read_data)
);

endmodule