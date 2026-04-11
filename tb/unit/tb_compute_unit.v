`timescale 1ns/1ps
`include "cu_defs.vh"
// ============================================================
// Testbench: tb_compute_unit
// Signal names match tb_compute_unit_behav.wcfg exactly so
// the saved waveform configuration loads without remapping.
//
// Signals (17 total, matching wcfg):
//   clk, rst
//   sched_pc[15:0]
//   if_pc[15:0]
//   id_pc[15:0]
//   ex_pc[15:0]
//   mem_pc[15:0]
//   wb_pc[15:0]
//   ex_alu_lane0[31:0]
//   ex_alu_lane1[31:0]
//   ex_alu_lane2[31:0]
//   ex_alu_lane3[31:0]
//   dmem_write_en
//   dmem_addr_lane0[31:0]
//   dmem_wdata_lane0[31:0]
//   warp_commit_en
//   warp_commit_state[1:0]
// ============================================================

module tb_compute_unit;

    // =========================================================
    // Clock and reset
    // =========================================================
    reg clk;
    reg rst;

    initial clk = 0;
    always  #5 clk = ~clk;

    // =========================================================
    // DUT — top module contains compute_unit + imem + dmem
    // =========================================================
    top u_top (
        .clk(clk),
        .rst(rst)
    );

    // =========================================================
    // Waveform signals — named to match wcfg exactly
    // All are aliases into the design hierarchy
    // =========================================================

    // Pipeline PC march
    wire [`PC_WIDTH-1:0] sched_pc;
    wire [`PC_WIDTH-1:0] if_pc;
    wire [`PC_WIDTH-1:0] id_pc;
    wire [`PC_WIDTH-1:0] ex_pc;
    wire [`PC_WIDTH-1:0] mem_pc;
    wire [`PC_WIDTH-1:0] wb_pc;

    assign sched_pc = u_top.u_compute_unit.wm_pc;
    assign if_pc    = u_top.u_compute_unit.if_id_pc;
    assign id_pc    = u_top.u_compute_unit.id_ex_pc;
    assign ex_pc    = u_top.u_compute_unit.ex_mem_pc;
    assign mem_pc   = u_top.u_compute_unit.mem_wb_pc;
    assign wb_pc    = u_top.u_compute_unit.mem_wb_pc;

    // ALU results per lane (from EX/MEM register)
    wire [31:0] ex_alu_lane0;
    wire [31:0] ex_alu_lane1;
    wire [31:0] ex_alu_lane2;
    wire [31:0] ex_alu_lane3;

    assign ex_alu_lane0 = u_top.u_compute_unit.ex_mem_alu_result[1*32-1 -: 32];
    assign ex_alu_lane1 = u_top.u_compute_unit.ex_mem_alu_result[2*32-1 -: 32];
    assign ex_alu_lane2 = u_top.u_compute_unit.ex_mem_alu_result[3*32-1 -: 32];
    assign ex_alu_lane3 = u_top.u_compute_unit.ex_mem_alu_result[4*32-1 -: 32];

    // Data memory interface
    wire                  dmem_write_en;
    wire [31:0]           dmem_addr_lane0;
    wire [31:0]           dmem_wdata_lane0;

    assign dmem_write_en   = u_top.u_compute_unit.dmem_write_en_o;
    assign dmem_addr_lane0 = u_top.u_compute_unit.dmem_addr_flat_o[1*32-1 -: 32];
    assign dmem_wdata_lane0= u_top.u_compute_unit.dmem_wdata_flat_o[1*32-1 -: 32];

    // Warp commit interface
    wire                  warp_commit_en;
    wire [1:0]            warp_commit_state;

    assign warp_commit_en    = u_top.u_compute_unit.warp_update_en;
    assign warp_commit_state = u_top.u_compute_unit.warp_update_state;

    // =========================================================
    // Console monitors
    // =========================================================

    // Warp commit
    always @(posedge clk) begin
        if (u_top.u_compute_unit.warp_update_en) begin
            if (u_top.u_compute_unit.warp_update_state == `WARP_DONE)
                $display("[COMMIT] T=%0t | Warp %0d | PC=%04h | --> DONE",
                    $time,
                    u_top.u_compute_unit.warp_update_wid,
                    u_top.u_compute_unit.mem_wb_pc);
            else
                $display("[COMMIT] T=%0t | Warp %0d | PC=%04h | --> READY  next_pc=%04h",
                    $time,
                    u_top.u_compute_unit.warp_update_wid,
                    u_top.u_compute_unit.mem_wb_pc,
                    u_top.u_compute_unit.warp_update_pc);
        end
    end

    // Store monitor
    integer i;
    always @(posedge clk) begin
        if (u_top.u_compute_unit.dmem_write_en_o) begin
            for (i = 0; i < `WARP_SIZE; i = i + 1) begin
                if (u_top.u_compute_unit.dmem_write_mask_o[i])
                    $display("[STORE]  T=%0t | lane%0d | addr=%0d | data=%0d",
                        $time,
                        i,
                        u_top.u_compute_unit.dmem_addr_flat_o [(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH],
                        u_top.u_compute_unit.dmem_wdata_flat_o[(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH]);
            end
        end
    end

    // Branch taken monitor (gated with valid)
    always @(posedge clk) begin
        if (u_top.u_compute_unit.ex_mem_branch_taken
         && u_top.u_compute_unit.ex_mem_valid)
            $display("[BRANCH] T=%0t | Warp %0d | PC=%04h | TAKEN → target=%04h",
                $time,
                u_top.u_compute_unit.ex_mem_wid,
                u_top.u_compute_unit.ex_mem_pc,
                u_top.u_compute_unit.ex_mem_branch_target);
    end

    // =========================================================
    // Simulation control
    // =========================================================
    integer j;
    initial begin
        rst = 1;
        #20 rst = 0;
        #2500;

        $display("");
        $display("--------------------------------------------------");
        $display("Simulation complete. Final memory contents:");
        $display("--------------------------------------------------");
        for (j = 0; j < 16; j = j + 1)
            $display("  mem[%02d] = %0d", j, u_top.u_data_memory.mem[j]);
        $display("--------------------------------------------------");
        $finish;
    end

endmodule