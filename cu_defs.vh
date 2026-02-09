// ============================================================
// cu_defs.vh
// Global architectural definitions for SIMT Compute Unit
// ============================================================

`ifndef CU_DEFS_VH
`define CU_DEFS_VH

// ------------------------------------------------------------
// 1. CORE ARCHITECTURAL CONSTANTS
// ------------------------------------------------------------

// Number of lanes per warp
`define WARP_SIZE   4

// Maximum number of resident warps
`define NUM_WARPS   4

// Number of vector registers per warp
`define NUM_VREGS   8

// Lane data width
`define LANE_WIDTH  32

// Program counter width
`define PC_WIDTH    16


// ------------------------------------------------------------
// 2. DERIVED WIDTHS
// ------------------------------------------------------------

// Warp ID width
`define WARP_ID_W   $clog2(`NUM_WARPS)

// Vector register index width
`define REG_ID_W    $clog2(`NUM_VREGS)

// Active mask width
`define MASK_W      `WARP_SIZE

// Warp state encoding width
`define WARP_STATE_W 2


// ------------------------------------------------------------
// 3. INSTRUCTION FORMAT
// ------------------------------------------------------------

`define INST_WIDTH  32
`define OPCODE_W    6
`define IMM_W       16


// ------------------------------------------------------------
// 4. WARP STATE ENCODINGS
// ------------------------------------------------------------

`define WARP_READY  2'b00
`define WARP_STALL  2'b01
`define WARP_DONE   2'b10


// ------------------------------------------------------------
// 5. INSTRUCTION CLASS ENCODINGS
// ------------------------------------------------------------

`define INST_ALU    2'b00
`define INST_LSU    2'b01
`define INST_BR     2'b10
`define INST_EXIT   2'b11


// ------------------------------------------------------------
// 6. ALU OPERATION ENCODINGS
// ------------------------------------------------------------

`define ALU_ADD     4'b0000
`define ALU_SUB     4'b0001
`define ALU_AND     4'b0010
`define ALU_OR      4'b0011
`define ALU_XOR     4'b0100
`define ALU_SLT     4'b0101


// ------------------------------------------------------------
// 7. MEMORY OPERATION TYPES
// ------------------------------------------------------------

`define MEM_LOAD    1'b0
`define MEM_STORE   1'b1


// ------------------------------------------------------------
// 8. COMMON MASK CONSTANTS
// ------------------------------------------------------------

`define FULL_MASK   {`MASK_W{1'b1}}
`define ZERO_MASK   {`MASK_W{1'b0}}

`endif // CU_DEFS_VH
