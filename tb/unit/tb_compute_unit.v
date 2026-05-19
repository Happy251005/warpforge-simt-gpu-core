`timescale 1ns/1ps
`include "cu_defs.vh"

// ============================================================
// Testbench: tb_compute_unit
// - Instantiates top module (compute_unit + imem + dmem)
// - Monitors key events: branch commits, stores, exits
// - Prints final memory state
// ============================================================

module tb_compute_unit;

    reg clk;
    reg rst;

    initial clk = 0;
    always  #5 clk = ~clk;

    // DUT
    top u_top (
        .clk(clk),
        .rst(rst)
    );

    // =========================================================
    // Event Monitors
    // =========================================================

    // EXIT Monitor — warp completion
    always @(posedge clk) begin
        if (u_top.u_compute_unit.exit_en) begin
            $display("[EXIT]   T=%0t | Warp %0d | --> DONE",
                $time/1000,
                u_top.u_compute_unit.exit_wid);
        end
    end

    // STORE Monitor — memory writes
    integer i;
    always @(posedge clk) begin
        if (u_top.u_compute_unit.dmem_write_en_o) begin
            for (i = 0; i < `WARP_SIZE; i = i + 1) begin
                if (u_top.u_compute_unit.dmem_write_mask_o[i])
                    $display("[STORE]  T=%0t | Warp %0d | lane%0d | addr=%04h | data=%0d",
                        $time/1000,
                        u_top.u_compute_unit.ex_mem_wid,
                        i,
                        u_top.u_compute_unit.dmem_addr_flat_o[(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH],
                        u_top.u_compute_unit.dmem_wdata_flat_o[(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH]);
            end
        end
    end

    // BRANCH Monitor — taken branches
    always @(posedge clk) begin
        if (u_top.u_compute_unit.ex_mem_branch_taken && u_top.u_compute_unit.ex_mem_valid) begin
            $display("[BRANCH] T=%0t | Warp %0d | TAKEN → target=%04h",
                $time/1000,
                u_top.u_compute_unit.ex_mem_wid,
                u_top.u_compute_unit.ex_mem_branch_target);
        end
    end

    // Scoreboard CLEAR Monitor — register writebacks completing
    always @(posedge clk) begin
        if (u_top.u_compute_unit.clear_en) begin
            $display("[CLEAR]  T=%0t | Warp %0d | R%0d cleared",
                $time/1000,
                u_top.u_compute_unit.clear_wid,
                u_top.u_compute_unit.clear_rd);
        end
    end

    // =========================================================
    // Pipeline Trace (every 10 cycles, for visibility)
    // =========================================================
    integer cycle_count = 0;
    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (cycle_count % 10 == 0) begin
            $display("[IF/ID]  T=%0t | Warp %0d | PC=%04h | valid=%0d | instr=%08h",
                $time/1000,
                u_top.u_compute_unit.if_id_wid,
                u_top.u_compute_unit.if_id_pc,
                u_top.u_compute_unit.if_id_valid,
                u_top.u_compute_unit.if_id_inst);
        end
    end

    // =========================================================
    // Simulation Control — 520 µs (52000 cycles)
    // =========================================================
    initial begin
        rst = 1;
        #20 rst = 0;
        #1000;

        $display("");
        $display("--------------------------------------------------");
        $display("Simulation complete. Final memory contents:");
        $display("--------------------------------------------------");
        for (i = 0; i < 16; i = i + 1)
            $display("  mem[%02d] = %0d", i, u_top.u_data_memory.mem[i]);
        $display("--------------------------------------------------");
        $finish;
    end

endmodule
