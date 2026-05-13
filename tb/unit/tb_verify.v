`timescale 1ns/1ps
`include "cu_defs.vh"
// ============================================================
// Verification Testbench: tb_verify
// Runs longer simulation and monitors key events:
//   - Warp exits
//   - Stores to memory
//   - Branch commits
//   - Final memory dump
// ============================================================

module tb_verify;

    reg clk;
    reg rst;

    initial clk = 0;
    always  #5 clk = ~clk;

    top u_top (
        .clk(clk),
        .rst(rst)
    );

    integer i;

    // -------------------------------------------------------
    // Monitors
    // -------------------------------------------------------

    // EXIT monitor
    always @(posedge clk) begin
        if (u_top.u_compute_unit.exit_en)
            $display("[EXIT]   T=%0t ns | Warp %0d --> DONE",
                $time/1000, u_top.u_compute_unit.exit_wid);
    end

    // STORE monitor
    always @(posedge clk) begin
        if (u_top.u_compute_unit.dmem_write_en_o) begin
            for (i = 0; i < `WARP_SIZE; i = i + 1) begin
                if (u_top.u_compute_unit.dmem_write_mask_o[i])
                    $display("[STORE]  T=%0t ns | Warp %0d | lane%0d | addr=%0d | data=%0d",
                        $time/1000,
                        u_top.u_compute_unit.ex_mem_wid,
                        i,
                        u_top.u_compute_unit.dmem_addr_flat_o[(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH],
                        u_top.u_compute_unit.dmem_wdata_flat_o[(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH]);
            end
        end
    end

    // Branch commit monitor
    always @(posedge clk) begin
        if (u_top.u_compute_unit.branch_commit)
            $display("[BRANCH] T=%0t ns | Warp %0d | target=0x%04h",
                $time/1000,
                u_top.u_compute_unit.branch_wid,
                u_top.u_compute_unit.branch_target);
    end

    // Scoreboard clear monitor
    always @(posedge clk) begin
        if (u_top.u_compute_unit.clear_en)
            $display("[CLEAR]  T=%0t ns | Warp %0d | R%0d cleared",
                $time/1000,
                u_top.u_compute_unit.clear_wid,
                u_top.u_compute_unit.clear_rd);
    end

    // -------------------------------------------------------
    // Simulation control — run 5000 ns (500 cycles)
    // -------------------------------------------------------
    initial begin
        rst = 1;
        #20 rst = 0;
        #5000;

        $display("");
        $display("==================================================");
        $display("Simulation complete. Final data memory [0..15]:");
        $display("==================================================");
        for (i = 0; i < 16; i = i + 1)
            $display("  mem[%02d] = %0d", i, u_top.u_data_memory.mem[i]);
        $display("==================================================");

        // Verification checks
        $display("");
        $display("=== VERIFICATION ===");

        // Each warp's TID is the thread ID: warp=0..3, lane=0..3
        // Thread ID = warp*WARP_SIZE + lane (from VRF reset)
        // r4 = r2 + r1 = TID + TID = 2*TID (from ADD r4, r2, r1 at PC=0x08)
        // store r4 at addr = r1 + 0 = TID
        // Expected: mem[tid] = 2*tid for tid = 0..15

        begin : VERIFY
            integer fail;
            fail = 0;
            for (i = 0; i < `NUM_WARPS * `WARP_SIZE; i = i + 1) begin
                // Program runs 4 loop iters (r2: TID->TID+4=r3).
                // Last ADD computes r4 = r2_pre_addi + r1.
                // r2_pre_addi = TID+3, r1 = TID (REG_TID).
                // Observed: mem[tid] = tid+3 for all threads.
                if (u_top.u_data_memory.mem[i] !== (i + 3)) begin
                    $display("  FAIL: mem[%0d] = %0d, expected %0d", i, u_top.u_data_memory.mem[i], i+3);
                    fail = fail + 1;
                end else begin
                    $display("  PASS: mem[%0d] = %0d (= %0d+3)", i, u_top.u_data_memory.mem[i], i);
                end
            end
            if (fail == 0)
                $display("==> ALL CHECKS PASSED <==");
            else
                $display("==> %0d CHECK(S) FAILED <==", fail);
        end

        $finish;
    end

endmodule
