// ============================================================
// Instruction Memory
// Synchronous 1-cycle read memory (byte-addressed PC input)
// - External to Compute Unit
// - Initialized from program.mem file
// ============================================================

`include "cu_defs.vh"

module instruction_memory (
    input  wire                     clk,

    // Byte address from IFU
    input  wire [`PC_WIDTH-1:0]     addr,

    // 32-bit instruction output
    output reg  [`INST_WIDTH-1:0]   rdata
);

    reg [`INST_WIDTH-1:0] mem [0:`IMEM_DEPTH-1];

    // Memory Initialization
    initial begin
        $readmemh("program.mem", mem);
    end

    // Read logic
    always @(posedge clk) begin
        rdata <= mem[addr[`PC_WIDTH-1:2]]; // Using BYTE addressing
    end

endmodule
