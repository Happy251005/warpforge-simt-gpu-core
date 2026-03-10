`timescale 1ns/1ps

`include "cu_defs.vh"
`include "compute_unit.v"
`include "instruction_memory.v"
`include "data_memory.v"

// ============================================================
// Testbench: tb_compute_unit
// Program under test (loaded from program.mem):
//
//   ADDI r2, r0, 10       // r2 = 10  (constant for all lanes)
//   ADDI r3, r1, 0        // r3 = tid (r1 = thread ID, unique per lane)
//   ADD  r4, r2, r3       // r4 = 10 + tid
//   STORE r4, r0, 0       // mem[tid] = r4  (each lane writes to unique addr)
//   EXIT
//
// Expected results per lane (per warp):
//   Warp 0: lane0→mem[0]=10, lane1→mem[1]=11, lane2→mem[2]=12, lane3→mem[3]=13
//   Warp 1: lane0→mem[4]=14, lane1→mem[5]=15, lane2→mem[6]=16, lane3→mem[7]=17
//   Warp 2: lane0→mem[8]=18, ...
//   Warp 3: lane0→mem[12]=22, ...
//
// Waveform groups (set up in Vivado):
//   [1] Clock & Reset
//   [2] Warp Scheduler
//   [3] Pipeline Stage Tracking  (wid + pc per stage)
//   [4] Execute Results          (per-lane ALU output)
//   [5] Memory Interface         (per-lane address and data)
//   [6] Writeback & Commit
// ============================================================

module tb_compute_unit;

    reg clk;
    reg rst;

    always #5 clk = ~clk;


    // Memory interface wires (connect DUT ↔ memory modules)
    wire [`PC_WIDTH-1:0]              imem_addr;
    wire [`INST_WIDTH-1:0]            imem_rdata;

    wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_addr_flat;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_wdata_flat;
    wire [`MASK_W-1:0]                dmem_write_mask;
    wire                              dmem_write_en;
    wire                              dmem_read_en;
    wire [`WARP_SIZE*`LANE_WIDTH-1:0] dmem_rdata_flat;


    // DUT
    compute_unit dut (
        .clk              (clk),
        .rst              (rst),

        .imem_addr_o      (imem_addr),
        .imem_rdata_i     (imem_rdata),

        .dmem_addr_flat_o (dmem_addr_flat),
        .dmem_wdata_flat_o(dmem_wdata_flat),
        .dmem_write_mask_o(dmem_write_mask),
        .dmem_write_en_o  (dmem_write_en),
        .dmem_read_en_o   (dmem_read_en),
        .dmem_rdata_flat_i(dmem_rdata_flat)
    );


    // Instruction Memory
    instruction_memory u_imem (
        .clk  (clk),
        .addr (imem_addr),
        .rdata(imem_rdata)
    );



    // Data Memory
    data_memory u_dmem (
        .clk         (clk),
        .addr_i      (dmem_addr_flat),
        .write_data_i(dmem_wdata_flat),
        .write_mask_i(dmem_write_mask),
        .mem_write_i (dmem_write_en),
        .read_data_o (dmem_rdata_flat)
    );


    wire [`WARP_ID_W-1:0] sched_warp_id;      // warp selected this cycle
    wire                  sched_issue_valid;   // a valid warp was found
    wire [`PC_WIDTH-1:0]  sched_pc;           // PC of selected warp

    assign sched_warp_id    = dut.wm_wid;
    assign sched_issue_valid= dut.wm_issue_valid;
    assign sched_pc         = dut.wm_pc;

    // Pipeline Stage Tracking
    
    // IF/ID boundary
    wire [`WARP_ID_W-1:0] if_warp_id;
    wire [`PC_WIDTH-1:0]  if_pc;
    wire [`INST_WIDTH-1:0]if_instruction;
    wire                  if_valid;

    assign if_warp_id    = dut.if_id_wid;
    assign if_pc         = dut.if_id_pc;
    assign if_instruction= dut.if_id_inst;
    assign if_valid      = dut.if_id_valid;

    // ID/EX boundary
    wire [`WARP_ID_W-1:0] id_warp_id;
    wire [`PC_WIDTH-1:0]  id_pc;
    wire                  id_valid;
    wire                  id_reg_write;
    wire                  id_mem_read;
    wire                  id_mem_write;
    wire                  id_branch;
    wire                  id_exit;

    assign id_warp_id  = dut.id_ex_wid;
    assign id_pc       = dut.id_ex_pc;
    assign id_valid    = dut.id_ex_valid;
    assign id_reg_write= dut.id_ex_reg_write;
    assign id_mem_read = dut.id_ex_mem_read;
    assign id_mem_write= dut.id_ex_mem_write;
    assign id_branch   = dut.id_ex_branch;
    assign id_exit     = dut.id_ex_exit;

    // EX/MEM boundary
    wire [`WARP_ID_W-1:0] ex_warp_id;
    wire [`PC_WIDTH-1:0]  ex_pc;
    wire                  ex_valid;
    wire                  ex_reg_write;
    wire                  ex_mem_read;
    wire                  ex_mem_write;

    assign ex_warp_id  = dut.ex_mem_wid;
    assign ex_pc       = dut.ex_mem_pc;
    assign ex_valid    = dut.ex_mem_valid;
    assign ex_reg_write= dut.ex_mem_reg_write;
    assign ex_mem_read = dut.ex_mem_mem_read;
    assign ex_mem_write= dut.ex_mem_mem_write;

    // MEM/WB boundary
    wire [`WARP_ID_W-1:0] mem_warp_id;
    wire [`PC_WIDTH-1:0]  mem_pc;
    wire                  mem_valid;
    wire                  mem_reg_write;

    assign mem_warp_id  = dut.mem_wb_wid;
    assign mem_pc       = dut.mem_wb_pc;
    assign mem_valid    = dut.mem_wb_valid;
    assign mem_reg_write= dut.mem_wb_reg_write;

    // ========================================================
    // [4] Execute Results - per-lane ALU output
    // ========================================================
    wire [31:0] ex_alu_lane0;
    wire [31:0] ex_alu_lane1;
    wire [31:0] ex_alu_lane2;
    wire [31:0] ex_alu_lane3;

    assign ex_alu_lane0 = dut.ex_mem_alu_result[1*32-1 -: 32];
    assign ex_alu_lane1 = dut.ex_mem_alu_result[2*32-1 -: 32];
    assign ex_alu_lane2 = dut.ex_mem_alu_result[3*32-1 -: 32];
    assign ex_alu_lane3 = dut.ex_mem_alu_result[4*32-1 -: 32];

    // ========================================================
    // [5] Memory Interface - per-lane unpacked
    // ========================================================
    wire [31:0] dmem_addr_lane0;
    wire [31:0] dmem_addr_lane1;
    wire [31:0] dmem_addr_lane2;
    wire [31:0] dmem_addr_lane3;

    wire [31:0] dmem_wdata_lane0;
    wire [31:0] dmem_wdata_lane1;
    wire [31:0] dmem_wdata_lane2;
    wire [31:0] dmem_wdata_lane3;

    wire [31:0] dmem_rdata_lane0;
    wire [31:0] dmem_rdata_lane1;
    wire [31:0] dmem_rdata_lane2;
    wire [31:0] dmem_rdata_lane3;

    assign dmem_addr_lane0  = dmem_addr_flat [1*32-1 -: 32];
    assign dmem_addr_lane1  = dmem_addr_flat [2*32-1 -: 32];
    assign dmem_addr_lane2  = dmem_addr_flat [3*32-1 -: 32];
    assign dmem_addr_lane3  = dmem_addr_flat [4*32-1 -: 32];

    assign dmem_wdata_lane0 = dmem_wdata_flat[1*32-1 -: 32];
    assign dmem_wdata_lane1 = dmem_wdata_flat[2*32-1 -: 32];
    assign dmem_wdata_lane2 = dmem_wdata_flat[3*32-1 -: 32];
    assign dmem_wdata_lane3 = dmem_wdata_flat[4*32-1 -: 32];

    assign dmem_rdata_lane0 = dmem_rdata_flat[1*32-1 -: 32];
    assign dmem_rdata_lane1 = dmem_rdata_flat[2*32-1 -: 32];
    assign dmem_rdata_lane2 = dmem_rdata_flat[3*32-1 -: 32];
    assign dmem_rdata_lane3 = dmem_rdata_flat[4*32-1 -: 32];

    // ========================================================
    // [6] Writeback & Commit
    // ========================================================
    wire [`WARP_ID_W-1:0] wb_warp_id;
    wire [`PC_WIDTH-1:0]  wb_pc;
    wire                  wb_valid;
    wire                  wb_reg_write;
    wire                  wb_exit;

    wire                     warp_commit_en;
    wire [`WARP_ID_W-1:0]    warp_commit_wid;
    wire [`PC_WIDTH-1:0]     warp_commit_next_pc;
    wire [`WARP_STATE_W-1:0] warp_commit_state;

    assign wb_warp_id        = dut.mem_wb_wid;
    assign wb_pc             = dut.mem_wb_pc;
    assign wb_valid          = dut.mem_wb_valid;
    assign wb_reg_write      = dut.mem_wb_reg_write;
    assign wb_exit           = dut.mem_wb_exit;

    assign warp_commit_en    = dut.warp_update_en;
    assign warp_commit_wid   = dut.warp_update_wid;
    assign warp_commit_next_pc = dut.warp_update_pc;
    assign warp_commit_state = dut.warp_update_state;

    // ========================================================
    // Simulation control
    // ========================================================
    integer i;

    initial begin
        clk = 0;
        rst = 1;
        #20;
        rst = 0;

        // Run long enough for all 4 warps to complete the 5-instruction program
        // Each warp: 5 instructions × ~8 cycles per instruction (issue-stall) = ~160 cycles
        // 4 warps interleaved: ~200 cycles to be safe
        #2000;

        $display("--------------------------------------------------");
        $display("Simulation complete.");
        $display("--------------------------------------------------");
        $finish;
    end

    // ========================================================
    // Warp state monitor - prints on every commit
    // ========================================================
    always @(posedge clk) begin
        if (warp_commit_en) begin
            if (warp_commit_state == `WARP_DONE)
                $display("[COMMIT] T=%0t | Warp %0d | PC=%h | --> DONE",
                    $time, warp_commit_wid, wb_pc);
            else
                $display("[COMMIT] T=%0t | Warp %0d | PC=%h | --> READY  next_pc=%h",
                    $time, warp_commit_wid, wb_pc, warp_commit_next_pc);
        end
    end

    // ========================================================
    // Memory write monitor - prints on every lane store
    // ========================================================
    always @(posedge clk) begin
        if (dmem_write_en) begin
            if (dmem_write_mask[0])
                $display("[STORE]  T=%0t | lane0 | addr=%0d | data=%0d",
                    $time, dmem_addr_lane0, dmem_wdata_lane0);
            if (dmem_write_mask[1])
                $display("[STORE]  T=%0t | lane1 | addr=%0d | data=%0d",
                    $time, dmem_addr_lane1, dmem_wdata_lane1);
            if (dmem_write_mask[2])
                $display("[STORE]  T=%0t | lane2 | addr=%0d | data=%0d",
                    $time, dmem_addr_lane2, dmem_wdata_lane2);
            if (dmem_write_mask[3])
                $display("[STORE]  T=%0t | lane3 | addr=%0d | data=%0d",
                    $time, dmem_addr_lane3, dmem_wdata_lane3);
        end
    end

endmodule