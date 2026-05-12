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
    assign ex_pc  = u_top.u_compute_unit.ex_mem_alu_result[1*32-1 -: 32]; // or remove
    assign mem_pc = u_top.u_compute_unit.mem_wb_result[1*32-1 -: 32];     // or remove
    assign wb_pc  = mem_pc;

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


    wire warp_commit_en    = u_top.u_compute_unit.exit_en;
    wire warp_commit_state = u_top.u_compute_unit.sb_stall; // or remove

/*
    // =========================================================
    // Console monitors
    // =========================================================

    // Warp commit
    always @(posedge clk) begin
        if (u_top.u_compute_unit.exit_en) begin
            $display("[COMMIT] T=%0t | Warp %0d | --> DONE",
                $time,
                u_top.u_compute_unit.exit_wid);
        end

        if (u_top.u_compute_unit.clear_en) begin
            $display("[COMMIT] T=%0t | Warp %0d | --> READY",
                $time,
                u_top.u_compute_unit.clear_wid);
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
                mem_pc,
                u_top.u_compute_unit.ex_mem_branch_target);
    end

    // Branch commit monitor
    always @(posedge clk) begin
        if (u_top.u_compute_unit.branch_commit)
            $display("[BRANCH_COMMIT] T=%0t | Warp %0d | target=%04h",
                $time,
                u_top.u_compute_unit.branch_wid,
                u_top.u_compute_unit.branch_target);
    end

always @(posedge clk) begin
    if (u_top.u_compute_unit.wm_issue_valid)
        $display("[ISSUE] T=%0t | Warp %0d | PC=%04h | rr_ptr=%0d",
            $time,
            u_top.u_compute_unit.wm_wid,
            u_top.u_compute_unit.wm_pc,
            u_top.u_compute_unit.u_warp_manager.rr_ptr);
end

    // Scoreboard stall monitor
always @(posedge clk) begin
    if (u_top.u_compute_unit.sb_stall)
        $display("[SB_STALL] T=%0t | Warp %0d | cause=%0d | rs=%0d | rt=%0d",
            $time,
            u_top.u_compute_unit.sb_stall_wid,
            u_top.u_compute_unit.sb_stall_cause,
            u_top.u_compute_unit.sb_check_rs,
            u_top.u_compute_unit.sb_check_rt);
end


// =========================================================
// Monitor Block
// =========================================================

// Issue monitor
always @(posedge clk) begin
    if (u_top.u_compute_unit.wm_issue_valid)
        $display("[ISSUE]  T=%0t | Warp %0d | PC=%04h",
            $time,
            u_top.u_compute_unit.wm_wid,
            u_top.u_compute_unit.wm_pc);
end

// Scoreboard stall monitor
always @(posedge clk) begin
    if (u_top.u_compute_unit.sb_stall)
        $display("[STALL]  T=%0t | Warp %0d | cause=%0d | rs=R%0d | rt=R%0d",
            $time,
            u_top.u_compute_unit.sb_stall_wid,
            u_top.u_compute_unit.sb_stall_cause,
            u_top.u_compute_unit.sb_check_rs,
            u_top.u_compute_unit.sb_check_rt);
end

// Branch commit monitor
always @(posedge clk) begin
    if (u_top.u_compute_unit.branch_commit)
        $display("[BRANCH] T=%0t | Warp %0d | target=%04h",
            $time,
            u_top.u_compute_unit.branch_wid,
            u_top.u_compute_unit.branch_target);
end

// Scoreboard clear monitor
always @(posedge clk) begin
    if (u_top.u_compute_unit.clear_en)
        $display("[CLEAR]  T=%0t | Warp %0d | R%0d cleared",
            $time,
            u_top.u_compute_unit.clear_wid,
            u_top.u_compute_unit.clear_rd);
end

// Exit monitor
always @(posedge clk) begin
    if (u_top.u_compute_unit.exit_en)
        $display("[EXIT]   T=%0t | Warp %0d | --> DONE",
            $time,
            u_top.u_compute_unit.exit_wid);
end

// Store monitor
integer i;
always @(posedge clk) begin
    if (u_top.u_compute_unit.dmem_write_en_o) begin
        for (i = 0; i < `WARP_SIZE; i = i + 1) begin
            if (u_top.u_compute_unit.dmem_write_mask_o[i])
                $display("[STORE]  T=%0t | Warp %0d | lane%0d | addr=%04h | data=%0d",
                    $time,
                    u_top.u_compute_unit.ex_mem_wid,
                    i,
                    u_top.u_compute_unit.dmem_addr_flat_o[(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH],
                    u_top.u_compute_unit.dmem_wdata_flat_o[(i+1)*`LANE_WIDTH-1 -: `LANE_WIDTH]);
        end
    end
end

// WB instruction monitor — shows every valid WB commit with wid and pc
always @(posedge clk) begin
    if (u_top.u_compute_unit.u_wb.valid_i)
        $display("[WB]     T=%0t | Warp %0d | reg_write=%0d | rd=R%0d | exit=%0d",
            $time,
            u_top.u_compute_unit.u_wb.wid_i,
            u_top.u_compute_unit.u_wb.reg_write_i,
            u_top.u_compute_unit.u_wb.rd_i,
            u_top.u_compute_unit.u_wb.exit_i);
end

*/
// Pipeline stage tracker
always @(posedge clk) begin
    // IF/ID stage
    $display("[IF/ID]  T=%0t | Warp %0d | PC=%04h | valid=%0d | instr=%08h",
        $time,
        u_top.u_compute_unit.if_id_wid,
        u_top.u_compute_unit.if_id_pc,
        u_top.u_compute_unit.if_id_valid,
        u_top.u_compute_unit.if_id_inst);

    // ID/EX stage
    $display("[ID/EX]  T=%0t | Warp %0d | PC=%04h | valid=%0d | exit=%0d | branch=%0d | instr=%08h",
        $time,
        u_top.u_compute_unit.id_ex_wid,
        u_top.u_compute_unit.id_ex_pc,
        u_top.u_compute_unit.id_ex_valid,
        u_top.u_compute_unit.id_ex_exit,
        u_top.u_compute_unit.id_ex_branch,
        u_top.u_compute_unit.if_id_inst);

    // EX/MEM stage
    $display("[EX/MEM] T=%0t | Warp %0d | valid=%0d | exit=%0d | branch_taken=%0d",
        $time,
        u_top.u_compute_unit.ex_mem_wid,
        u_top.u_compute_unit.ex_mem_valid,
        u_top.u_compute_unit.ex_mem_exit,
        u_top.u_compute_unit.ex_mem_branch_taken);

    // MEM/WB stage
    $display("[MEM/WB] T=%0t | Warp %0d | valid=%0d | exit=%0d",
        $time,
        u_top.u_compute_unit.mem_wb_wid,
        u_top.u_compute_unit.mem_wb_valid,
        u_top.u_compute_unit.mem_wb_exit);
end

// =========================================================
// Simulation control
// =========================================================
integer j;
initial begin
    rst = 1;
    #20 rst = 0;
    #1000;

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