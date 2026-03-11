`timescale 1ns/1ps
`include "cu_defs.vh"
`include "top.v"

// ============================================================
// Testbench: tb_top
// Description:
//   Instantiates the top module (compute_unit + imem + dmem).
//   Monitors warp commit events and store operations.
//   Dumps final data memory contents after simulation.
// ============================================================

module tb_top;

    reg clk;
    reg rst;

    // =========================================================
    // DUT — top module contains compute_unit, imem, dmem
    // =========================================================
    top u_top (
        .clk(clk),
        .rst(rst)
    );

    // =========================================================
    // Clock — 10ns period
    // =========================================================
    initial clk = 0;
    always  #5 clk = ~clk;

    // =========================================================
    // Warp commit monitor
    // Watches the warp manager write interface inside top
    // =========================================================
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

    // =========================================================
    // Store monitor
    // Watches data memory write interface
    // =========================================================
    integer i;
    always @(posedge clk) begin
        if (u_top.u_compute_unit.dmem_write_en_o) begin
            for (i = 0; i < `WARP_SIZE; i = i + 1) begin
                if (u_top.u_compute_unit.dmem_write_mask_o[i]) begin
                    $display("[STORE]  T=%0t | lane%0d | addr=%0d | data=%0d",
                        $time,
                        i,
                        u_top.u_compute_unit.dmem_addr_flat_o[(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH],
                        u_top.u_compute_unit.dmem_wdata_flat_o[(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH]);
                end
            end
        end
    end

    // =========================================================
    // Branch monitor
    // Watches for taken branches to show redirect in console
    // =========================================================
    always @(posedge clk) begin
        if (u_top.u_compute_unit.ex_mem_branch_taken) begin
            $display("[BRANCH] T=%0t | Warp %0d | PC=%04h | TAKEN → target=%04h",
                $time,
                u_top.u_compute_unit.ex_mem_wid,
                u_top.u_compute_unit.ex_mem_pc,
                u_top.u_compute_unit.ex_mem_branch_target);
        end
    end

    // =========================================================
    // Simulation control
    // =========================================================
    initial begin
        rst = 1;
        #20 rst = 0;

        // Run long enough for loop program to complete
        // 7 instructions x 4 iterations x 4 warps x ~10 cycles + margin
        #2500;

        $display("");
        $display("--------------------------------------------------");
        $display("Simulation complete. Final memory contents:");
        $display("--------------------------------------------------");

        for (i = 0; i < 16; i = i + 1) begin
            $display("  mem[%02d] = %0d", i, u_top.u_data_memory.mem[i]);
        end

        $display("--------------------------------------------------");
        $finish;
    end

endmodule