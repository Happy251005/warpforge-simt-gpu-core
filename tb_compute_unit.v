`timescale 1ns/1ps
`include "cu_defs.vh"
`include "compute_unit.v"

module tb_compute_unit;

    reg clk;
    reg rst;

    // Instruction memory interface
    wire [`PC_WIDTH-1:0]   imem_addr;
    reg  [`INST_WIDTH-1:0] imem_rdata;

    // Data memory interface
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_addr;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_wdata;
    wire [`MASK_W-1:0]                dmem_write_mask;
    wire                              dmem_write_en;
    wire                              dmem_read_en;
    reg  [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_rdata;

    // Simple instruction memory
    reg [`INST_WIDTH-1:0] imem [0:255];

    // Simple data memory (word-addressed)
    reg [31:0] data_mem [0:255];

    integer i;

    // Clock
    always #5 clk = ~clk;

    // DUT
    compute_unit dut (
        .clk(clk),
        .rst(rst),

        .imem_addr_o(imem_addr),
        .imem_rdata_i(imem_rdata),

        .dmem_addr_flat_o(dmem_addr),
        .dmem_wdata_flat_o(dmem_wdata),
        .dmem_write_mask_o(dmem_write_mask),
        .dmem_write_en_o(dmem_write_en),
        .dmem_read_en_o(dmem_read_en),

        .dmem_rdata_flat_i(dmem_rdata)
    );

    // Instruction memory read
    always @(*) begin
        imem_rdata = imem[imem_addr >> 2];
    end

    // Data memory model
    always @(*) begin
        dmem_rdata = 0;
        if (dmem_read_en) begin
            for (i = 0; i < `WARP_SIZE; i = i + 1) begin
                dmem_rdata[(i+1)*32-1 -: 32] =
                    data_mem[dmem_addr[(i+1)*32-1 -: 32] >> 2];
            end
        end
    end

    // Data memory write
    always @(posedge clk) begin
        if (dmem_write_en) begin
            for (i = 0; i < `WARP_SIZE; i = i + 1) begin
                if (dmem_write_mask[i]) begin
                    data_mem[dmem_addr[(i+1)*32-1 -: 32] >> 2] <= dmem_wdata[(i+1)*32-1 -: 32];

                    $display("MEM WRITE | lane=%0d addr=%h data=%h",
                        i,
                        dmem_addr[(i+1)*32-1 -: 32],
                        dmem_wdata[(i+1)*32-1 -: 32]);
                end
            end
        end
    end

    // Test sequence
    initial begin

        clk = 0;
        rst = 1;

        // Initialize memories
        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 0;
            data_mem[i] = 0;
        end

        // Load program
        $readmemh("program.mem", imem);

        #20 rst = 0;

        // Run simulation
        #3000;

        $display("Simulation finished.");
        $finish;

    end
    always @(posedge clk) begin
    $display("T=%0t | PC=%h | INST=%h | WRITE_EN=%b | WRITE_ADDR=%h",
        $time,
        imem_addr,
        imem_rdata,
        dmem_write_en,
        dmem_addr);
    $display("  ALU=%h | StoreData=%h", dut.ex_mem_alu_result, dut.ex_mem_store_data);
    end

endmodule
