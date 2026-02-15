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
`define NUM_VREGS   32

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
`define IMEM_DEPTH   256  
`define FUNC_W       6


// ------------------------------------------------------------
// 4. WARP STATE ENCODINGS
// ------------------------------------------------------------

`define WARP_READY  2'b00
`define WARP_STALL  2'b01
`define WARP_DONE   2'b10


// ------------------------------------------------------------
// 5. INTERNAL INSTRUCTION CLASS (Decode Output)
// ------------------------------------------------------------

`define INST_ALU    2'b00
`define INST_LSU    2'b01
`define INST_BR     2'b10
`define INST_SPECIAL 2'b11


// ------------------------------------------------------------
// 6. OPCODE CLASS FIELD (opcode[5:3])
// ------------------------------------------------------------

`define OPC_CLASS_ALU      3'b000
`define OPC_CLASS_MEM      3'b001
`define OPC_CLASS_BRANCH   3'b010
`define OPC_CLASS_SPECIAL  3'b011

// ------------------------------------------------------------
// 7. ALU OPCODES
// ------------------------------------------------------------

`define OPCODE_ALU_R   6'b000000
`define OPCODE_ALU_I   6'b000001

// ------------------------------------------------------------
// 8. MEMORY OPCODES
// ------------------------------------------------------------

`define OPCODE_LOAD    6'b001000
`define OPCODE_STORE   6'b001001


// ------------------------------------------------------------
// 9. BRANCH OPCODES
// ------------------------------------------------------------

`define OPCODE_BEQ     6'b010000
`define OPCODE_BNE     6'b010001


// ------------------------------------------------------------
// 10. SPECIAL OPCODES
// ------------------------------------------------------------

`define OPCODE_EXIT    6'b011000


// ------------------------------------------------------------
// 11. ALU FUNCTION CODES (R-Type)
// ------------------------------------------------------------

`define FUNC_ADD       6'b000000
`define FUNC_SUB       6'b000001
`define FUNC_AND       6'b000010
`define FUNC_OR        6'b000011
`define FUNC_XOR       6'b000100
`define FUNC_SLT       6'b000101



// ------------------------------------------------------------
// 12. COMMON MASK CONSTANTS
// ------------------------------------------------------------

`define FULL_MASK   {`MASK_W{1'b1}}
`define ZERO_MASK   {`MASK_W{1'b0}}

`endif // CU_DEFS_VH
