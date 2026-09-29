`timescale 1ns/1ps
`include "cu_defs.vh"

// ============================================================
// Testbench: tb_simt_divergence
// Comprehensive verification of SIMT divergence and reconvergence
//
// Tests verified:
//   TEST 1: Uniform branch: all active lanes take branch
//   TEST 2: Uniform not-taken branch
//   TEST 3: 2/2 divergence
//   TEST 4: 1/3 divergence
//   TEST 5: Nested divergence requiring stack depth > 1
//   TEST 6: Two different warps diverging independently
//   TEST 7: Memory and register writes under divergent masks
// ============================================================

module tb_simt_divergence;

    reg clk;
    reg rst;

    initial clk = 0;
    always #5 clk = ~clk;

    // Instantiate Top
    top u_top (
        .clk(clk),
        .rst(rst)
    );

    // Test tracking
    integer test_num = 0;
    integer tests_passed = 0;
    integer tests_failed = 0;
    reg [255:0] current_test_name;

    integer cycle_count = 0;
    integer raw_stall_detected = 0;
    always @(posedge clk) begin
        if (!rst)
            cycle_count <= cycle_count + 1;
        else
            cycle_count <= 0;
    end

    // =========================================================
    // Instruction Encoders (helper functions)
    // =========================================================
    function [31:0] enc_alu_r;
        input [5:0] func;
        input [4:0] rs;
        input [4:0] rt;
        input [4:0] rd;
        begin
            enc_alu_r = {`OPCODE_ALU_R, rs, rt, rd, 5'b0, func};
        end
    endfunction

    function [31:0] enc_alu_i;
        input [4:0] rs;
        input [4:0] rt;
        input [15:0] imm;
        begin
            enc_alu_i = {`OPCODE_ALU_I, rs, rt, imm};
        end
    endfunction

    function [31:0] enc_load;
        input [4:0] rs;
        input [4:0] rt;
        input [15:0] imm;
        begin
            enc_load = {`OPCODE_LOAD, rs, rt, imm};
        end
    endfunction

    function [31:0] enc_store;
        input [4:0] rs;
        input [4:0] rt;
        input [15:0] imm;
        begin
            enc_store = {`OPCODE_STORE, rs, rt, imm};
        end
    endfunction

    function [31:0] enc_beq;
        input [4:0] rs;
        input [4:0] rt;
        input [15:0] imm;
        begin
            enc_beq = {`OPCODE_BEQ, rs, rt, imm};
        end
    endfunction

    function [31:0] enc_bne;
        input [4:0] rs;
        input [4:0] rt;
        input [15:0] imm;
        begin
            enc_bne = {`OPCODE_BNE, rs, rt, imm};
        end
    endfunction

    function [31:0] enc_setrpc;
        input [15:0] rpc;
        begin
            enc_setrpc = {`OPCODE_SETRPC, 10'b0, rpc};
        end
    endfunction

    function [31:0] enc_exit;
        input dummy;
        begin
            enc_exit = {`OPCODE_EXIT, 26'b0};
        end
    endfunction

    // =========================================================
    // Debug & Monitoring Logic
    // =========================================================
    always @(posedge clk) begin
        if (!rst) begin
            // 1. Branch in EX monitor
            if (u_top.u_compute_unit.ex_valid_comb && u_top.u_compute_unit.ex_branch_comb &&
                u_top.u_compute_unit.u_warp_manager.branch_pending[u_top.u_compute_unit.ex_wid_comb]) begin
                $display("  [EX-BRANCH] Cycle=%4d | Warp %0d | PC=%04h | TakeMask=%b | ElseMask=%b | Divergent=%0d | Target=%04h",
                    cycle_count,
                    u_top.u_compute_unit.ex_wid_comb,
                    u_top.u_compute_unit.id_ex_pc,
                    u_top.u_compute_unit.ex_take_mask_comb,
                    u_top.u_compute_unit.ex_else_mask_comb,
                    u_top.u_compute_unit.u_warp_manager.ex_divergent,
                    u_top.u_compute_unit.ex_branch_target_comb);
            end

            // 2. SIMT Stack Push monitor
            if (u_top.u_compute_unit.simt_push_en) begin
                $display("  [STACK-PUSH] Cycle=%4d | Warp %0d | FT_PC=%04h | ElseMask=%b | FullMask=%b | NewDepth=%0d",
                    cycle_count,
                    u_top.u_compute_unit.simt_push_wid,
                    u_top.u_compute_unit.simt_push_fallthrough,
                    u_top.u_compute_unit.simt_push_else_mask,
                    u_top.u_compute_unit.simt_push_full_mask,
                    u_top.u_compute_unit.u_simt_stack.sp[u_top.u_compute_unit.simt_push_wid] + 2);
            end

            // 3. Reconvergence / Pop monitor
            if (u_top.u_compute_unit.simt_pop_en) begin
                $display("  [RECONV-POP] Cycle=%4d | Warp %0d | ReconvPC=%04h | NextTargetPC=%04h | NewMask=%b | NewDepth=%0d",
                    cycle_count,
                    u_top.u_compute_unit.simt_pop_wid,
                    u_top.u_compute_unit.simt_top_reconv_pc,
                    u_top.u_compute_unit.simt_top_target_pc,
                    u_top.u_compute_unit.simt_top_mask,
                    u_top.u_compute_unit.u_simt_stack.sp[u_top.u_compute_unit.simt_pop_wid] - 1);
            end

            // 4. Memory write monitor
            if (u_top.u_compute_unit.dmem_write_en_o) begin
                $display("  [STORE]      Cycle=%4d | Warp %0d | Mask=%b | Addr0=%04h Data0=%0d | Addr2=%04h Data2=%0d",
                    cycle_count,
                    u_top.u_compute_unit.ex_mem_wid,
                    u_top.u_compute_unit.dmem_write_mask_o,
                    u_top.u_compute_unit.dmem_addr_flat_o[31:0],
                    u_top.u_compute_unit.dmem_wdata_flat_o[31:0],
                    u_top.u_compute_unit.dmem_addr_flat_o[95:64],
                    u_top.u_compute_unit.dmem_wdata_flat_o[95:64]);
            end

            // 5. Scoreboard RAW stall monitor
            if (u_top.u_compute_unit.u_scoreboard.stall && (u_top.u_compute_unit.u_scoreboard.stall_cause == 1'b0)) begin
                raw_stall_detected = raw_stall_detected + 1;
                $display("  [RAW-STALL]  Cycle=%4d | Warp %0d | Scoreboard RAW stall detected",
                    cycle_count,
                    u_top.u_compute_unit.u_scoreboard.stall_wid);
            end
        end
    end

    // Memory clear helper
    integer m;
    task clear_memories;
        begin
            for (m = 0; m < `IMEM_DEPTH; m = m + 1)
                u_top.u_instruction_memory.mem[m] = 32'h00000000;
            for (m = 0; m < 1024; m = m + 1)
                u_top.u_data_memory.mem[m] = 32'h00000000;
        end
    endtask

    // Reset sequence helper
    task do_reset;
        begin
            rst = 1;
            #30;
            @(posedge clk);
            #1;
            rst = 0;
            @(posedge clk);
        end
    endtask

    // Wait until warp is done or timeout
    task wait_warp_done;
        input [1:0] wid;
        input integer max_cycles;
        integer cnt;
        begin
            cnt = 0;
            while (u_top.u_compute_unit.u_warp_manager.warp_state_array[wid] != `WARP_DONE && cnt < max_cycles) begin
                @(posedge clk);
                cnt = cnt + 1;
            end
            if (cnt >= max_cycles) begin
                $display("  [WARNING] Warp %0d reached timeout of %0d cycles!", wid, max_cycles);
            end
        end
    endtask

    // =========================================================
    // Main Test Execution
    // =========================================================
    integer val0, val1, val2, val3;
    integer pass;

    initial begin
        $display("==================================================================");
        $display("   WARPFORGE SIMT DIVERGENCE & RECONVERGENCE REGRESSION SUITE    ");
        $display("==================================================================");

        // --------------------------------------------------------
        // TEST 1: Uniform branch: all active lanes take branch
        // --------------------------------------------------------
        test_num = 1;
        current_test_name = "Uniform branch: all active lanes take branch";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // Program:
        // 0x00: ADDI r2, r0, 10
        // 0x04: SETRPC 0x0018
        // 0x08: BEQ r0, r0, +8   -> target = 0x08 + 8 = 0x10 (uniform taken)
        // 0x0C: ADDI r2, r0, 99  -> dead code (must never execute)
        // 0x10: ADDI r3, r2, 5   -> target: r3 = 10 + 5 = 15
        // 0x14: EXIT
        u_top.u_instruction_memory.mem[0] = enc_alu_i(5'd0, 5'd2, 16'd10);
        u_top.u_instruction_memory.mem[1] = enc_setrpc(16'h0018);
        u_top.u_instruction_memory.mem[2] = enc_beq(5'd0, 5'd0, 16'd8);
        u_top.u_instruction_memory.mem[3] = enc_alu_i(5'd0, 5'd2, 16'd99);
        u_top.u_instruction_memory.mem[4] = enc_alu_i(5'd2, 5'd3, 16'd5);
        u_top.u_instruction_memory.mem[5] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 100);

        // Check registers for Warp 0
        val0 = u_top.u_compute_unit.u_vrf.regfile[0][0][3];
        val1 = u_top.u_compute_unit.u_vrf.regfile[0][1][3];
        val2 = u_top.u_compute_unit.u_vrf.regfile[0][2][3];
        val3 = u_top.u_compute_unit.u_vrf.regfile[0][3][3];
        pass = (val0 == 15 && val1 == 15 && val2 == 15 && val3 == 15) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][2] == 10) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 1 PASSED: R3=[%0d,%0d,%0d,%0d] (exp: 15), Dead code not reached (R2=10), Stack depth=0",
                val0, val1, val2, val3);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 1 FAILED: R3=[%0d,%0d,%0d,%0d], R2_lane0=%0d, SP=%0d",
                val0, val1, val2, val3, u_top.u_compute_unit.u_vrf.regfile[0][0][2], u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 2: Uniform not-taken branch
        // --------------------------------------------------------
        test_num = 2;
        current_test_name = "Uniform not-taken branch";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // Program:
        // 0x00: ADDI r2, r0, 10
        // 0x04: SETRPC 0x0018
        // 0x08: BNE r0, r0, +8   -> target = 0x10 (condition r0!=r0 is false for all)
        // 0x0C: ADDI r2, r2, 1   -> fall-through executes: r2 = 11
        // 0x10: ADDI r3, r2, 5   -> r3 = 11 + 5 = 16
        // 0x14: EXIT
        u_top.u_instruction_memory.mem[0] = enc_alu_i(5'd0, 5'd2, 16'd10);
        u_top.u_instruction_memory.mem[1] = enc_setrpc(16'h0018);
        u_top.u_instruction_memory.mem[2] = enc_bne(5'd0, 5'd0, 16'd8);
        u_top.u_instruction_memory.mem[3] = enc_alu_i(5'd2, 5'd2, 16'd1);
        u_top.u_instruction_memory.mem[4] = enc_alu_i(5'd2, 5'd3, 16'd5);
        u_top.u_instruction_memory.mem[5] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 100);

        val0 = u_top.u_compute_unit.u_vrf.regfile[0][0][3];
        val1 = u_top.u_compute_unit.u_vrf.regfile[0][1][3];
        val2 = u_top.u_compute_unit.u_vrf.regfile[0][2][3];
        val3 = u_top.u_compute_unit.u_vrf.regfile[0][3][3];
        pass = (val0 == 16 && val1 == 16 && val2 == 16 && val3 == 16) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][2] == 11) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 2 PASSED: R3=[%0d,%0d,%0d,%0d] (exp: 16), Fall-through executed (R2=11), Stack depth=0",
                val0, val1, val2, val3);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 2 FAILED: R3=[%0d,%0d,%0d,%0d], R2=%0d, SP=%0d",
                val0, val1, val2, val3, u_top.u_compute_unit.u_vrf.regfile[0][0][2], u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 3: 2/2 Divergence
        // --------------------------------------------------------
        test_num = 3;
        current_test_name = "2/2 divergence";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // R1 holds TID: [0, 1, 2, 3]
        // 0x00: ADDI r2, r0, 2
        // 0x04: SLT r3, r1, r2      -> r3 = (tid < 2) ? 1 : 0
        // 0x08: SETRPC 0x0020       -> RPC = 0x20
        // 0x0C: BEQ r3, r0, +12     -> branch if r3==0 (lanes 2,3 take to 0x18; lanes 0,1 FT to 0x10)
        // // ELSE / Fall-through path (lanes 0, 1):
        // 0x10: ADDI r4, r0, 100
        // 0x14: BEQ r0, r0, +12     -> jump to RPC 0x20
        // // TAKEN path (lanes 2, 3):
        // 0x18: ADDI r4, r0, 200
        // 0x1C: BEQ r0, r0, +4      -> jump to RPC 0x20
        // // RECONVERGENCE (all lanes):
        // 0x20: ADDI r5, r4, 1      -> r5 = r4 + 1
        // 0x24: EXIT
        u_top.u_instruction_memory.mem[0] = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[1] = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[2] = enc_setrpc(16'h0020);
        u_top.u_instruction_memory.mem[3] = enc_beq(5'd3, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[4] = enc_alu_i(5'd0, 5'd4, 16'd100);
        u_top.u_instruction_memory.mem[5] = enc_beq(5'd0, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[6] = enc_alu_i(5'd0, 5'd4, 16'd200);
        u_top.u_instruction_memory.mem[7] = enc_beq(5'd0, 5'd0, 16'd4);
        u_top.u_instruction_memory.mem[8] = enc_alu_i(5'd4, 5'd5, 16'd1);
        u_top.u_instruction_memory.mem[9] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 150);

        val0 = u_top.u_compute_unit.u_vrf.regfile[0][0][4];
        val1 = u_top.u_compute_unit.u_vrf.regfile[0][1][4];
        val2 = u_top.u_compute_unit.u_vrf.regfile[0][2][4];
        val3 = u_top.u_compute_unit.u_vrf.regfile[0][3][4];

        pass = (val0 == 100 && val1 == 100 && val2 == 200 && val3 == 200) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][5] == 101) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][5] == 101) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][5] == 201) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][5] == 201) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 3 PASSED: 2/2 Divergence: R4=[%0d,%0d,%0d,%0d] (exp: [100,100,200,200]), R5=[%0d,%0d,%0d,%0d] (exp: [101,101,201,201]), Reconv SP=0",
                val0, val1, val2, val3,
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 3 FAILED: R4=[%0d,%0d,%0d,%0d], R5=[%0d,%0d,%0d,%0d], SP=%0d",
                val0, val1, val2, val3,
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5],
                u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 4: 1/3 Divergence
        // --------------------------------------------------------
        test_num = 4;
        current_test_name = "1/3 divergence";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // 0x00: ADDI r2, r0, 1
        // 0x04: SLT r3, r1, r2      -> r3 = (tid < 1) ? 1 : 0 (Lane 0=1, Lanes 1,2,3=0)
        // 0x08: SETRPC 0x0020       -> RPC = 0x20
        // 0x0C: BNE r3, r0, +12     -> branch if r3!=0 (Lane 0 takes to 0x18; Lanes 1,2,3 FT to 0x10)
        // // ELSE path (lanes 1, 2, 3):
        // 0x10: ADDI r4, r0, 30
        // 0x14: BEQ r0, r0, +12     -> jump to RPC 0x20
        // // TAKEN path (lane 0):
        // 0x18: ADDI r4, r0, 10
        // 0x1C: BEQ r0, r0, +4      -> jump to RPC 0x20
        // // RECONVERGENCE:
        // 0x20: ADDI r5, r4, 2      -> r5 = r4 + 2
        // 0x24: EXIT
        u_top.u_instruction_memory.mem[0] = enc_alu_i(5'd0, 5'd2, 16'd1);
        u_top.u_instruction_memory.mem[1] = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[2] = enc_setrpc(16'h0020);
        u_top.u_instruction_memory.mem[3] = enc_bne(5'd3, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[4] = enc_alu_i(5'd0, 5'd4, 16'd30);
        u_top.u_instruction_memory.mem[5] = enc_beq(5'd0, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[6] = enc_alu_i(5'd0, 5'd4, 16'd10);
        u_top.u_instruction_memory.mem[7] = enc_beq(5'd0, 5'd0, 16'd4);
        u_top.u_instruction_memory.mem[8] = enc_alu_i(5'd4, 5'd5, 16'd2);
        u_top.u_instruction_memory.mem[9] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 150);

        val0 = u_top.u_compute_unit.u_vrf.regfile[0][0][4];
        val1 = u_top.u_compute_unit.u_vrf.regfile[0][1][4];
        val2 = u_top.u_compute_unit.u_vrf.regfile[0][2][4];
        val3 = u_top.u_compute_unit.u_vrf.regfile[0][3][4];

        pass = (val0 == 10 && val1 == 30 && val2 == 30 && val3 == 30) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][5] == 12) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][5] == 32) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][5] == 32) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][5] == 32) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 4 PASSED: 1/3 Divergence: R4=[%0d,%0d,%0d,%0d] (exp: [10,30,30,30]), R5=[%0d,%0d,%0d,%0d] (exp: [12,32,32,32]), Reconv SP=0",
                val0, val1, val2, val3,
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 4 FAILED: R4=[%0d,%0d,%0d,%0d], R5=[%0d,%0d,%0d,%0d], SP=%0d",
                val0, val1, val2, val3,
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5],
                u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 5: Nested divergence requiring stack depth > 1
        // --------------------------------------------------------
        test_num = 5;
        current_test_name = "Nested divergence (stack depth > 1)";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // Program:
        // Outer divergence: split lanes 0,1 (FT1=0x10) and lanes 2,3 (target=0x1C). RPC1=0x44.
        // 0x00: ADDI r2, r0, 2
        // 0x04: SLT r3, r1, r2
        // 0x08: SETRPC 0x0044
        // 0x0C: BEQ r3, r0, +16     -> target = 0x1C (lanes 2,3); FT1 = 0x10 (lanes 0,1)
        // // Outer Else Path (lanes 0, 1):
        // 0x10: ADDI r4, r0, 50
        // 0x14: BEQ r0, r0, +48     -> jump to RPC1 0x44 (0x14 + 48 = 0x44)
        // 0x18: NOP
        // // Outer Taken Path (lanes 2, 3 active):
        // 0x1C: ADDI r2, r0, 3
        // 0x20: SLT r3, r1, r2      -> lane 2 gets 1, lane 3 gets 0
        // 0x24: SETRPC 0x003C       -> RPC2 = 0x3C
        // 0x28: BEQ r3, r0, +12     -> target = 0x34 (lane 3); FT2 = 0x2C (lane 2)
        // // Inner Else Path (lane 2):
        // 0x2C: ADDI r4, r0, 70
        // 0x30: BEQ r0, r0, +12     -> jump to RPC2 0x3C (0x30 + 12 = 0x3C)
        // // Inner Taken Path (lane 3):
        // 0x34: ADDI r4, r0, 80
        // 0x38: BEQ r0, r0, +4      -> jump to RPC2 0x3C (0x38 + 4 = 0x3C)
        // // Inner Reconvergence (lanes 2, 3 active, depth returns to 2):
        // 0x3C: ADDI r4, r4, 1      -> lane 2 gets 71, lane 3 gets 81
        // 0x40: BEQ r0, r0, +4      -> jump to RPC1 0x44 (0x40 + 4 = 0x44)
        // // Outer Reconvergence (all lanes active, depth returns to 0):
        // 0x44: ADDI r5, r4, 10     -> lane 0: 60, lane 1: 60, lane 2: 81, lane 3: 91
        // 0x48: EXIT
        u_top.u_instruction_memory.mem[0]  = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[1]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[2]  = enc_setrpc(16'h0044);
        u_top.u_instruction_memory.mem[3]  = enc_beq(5'd3, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[4]  = enc_alu_i(5'd0, 5'd4, 16'd50);
        u_top.u_instruction_memory.mem[5]  = enc_beq(5'd0, 5'd0, 16'd48);
        u_top.u_instruction_memory.mem[6]  = 32'h00000000;
        u_top.u_instruction_memory.mem[7]  = enc_alu_i(5'd0, 5'd2, 16'd3);
        u_top.u_instruction_memory.mem[8]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[9]  = enc_setrpc(16'h003C);
        u_top.u_instruction_memory.mem[10] = enc_beq(5'd3, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[11] = enc_alu_i(5'd0, 5'd4, 16'd70);
        u_top.u_instruction_memory.mem[12] = enc_beq(5'd0, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[13] = enc_alu_i(5'd0, 5'd4, 16'd80);
        u_top.u_instruction_memory.mem[14] = enc_beq(5'd0, 5'd0, 16'd4);
        u_top.u_instruction_memory.mem[15] = enc_alu_i(5'd4, 5'd4, 16'd1);
        u_top.u_instruction_memory.mem[16] = enc_beq(5'd0, 5'd0, 16'd4);
        u_top.u_instruction_memory.mem[17] = enc_alu_i(5'd4, 5'd5, 16'd10);
        u_top.u_instruction_memory.mem[18] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 250);

        val0 = u_top.u_compute_unit.u_vrf.regfile[0][0][4];
        val1 = u_top.u_compute_unit.u_vrf.regfile[0][1][4];
        val2 = u_top.u_compute_unit.u_vrf.regfile[0][2][4];
        val3 = u_top.u_compute_unit.u_vrf.regfile[0][3][4];

        pass = (val0 == 50 && val1 == 50 && val2 == 71 && val3 == 81) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][5] == 60) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][5] == 60) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][5] == 81) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][5] == 91) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 5 PASSED: Nested Divergence: R4=[%0d,%0d,%0d,%0d] (exp: [50,50,71,81]), R5=[%0d,%0d,%0d,%0d] (exp: [60,60,81,91]), Final SP=0",
                val0, val1, val2, val3,
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 5 FAILED: R4=[%0d,%0d,%0d,%0d], R5=[%0d,%0d,%0d,%0d], SP=%0d",
                val0, val1, val2, val3,
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5],
                u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 6: Two different warps diverging independently
        // --------------------------------------------------------
        test_num = 6;
        current_test_name = "Two different warps diverging independently";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // Warp 0 has TID: [0, 1, 2, 3] -> (TID % 4)
        // Warp 1 has TID: [4, 5, 6, 7] -> (TID % 4)
        // Let's test with SLT on (TID & 3) using an immediate or bitwise:
        // Or directly:
        // For Warp 0: compare r1 with 2 -> lanes 0,1 take else, 2,3 take branch.
        // For Warp 1: compare r1 with 6 -> lanes 4,5 take else, 6,7 take branch.
        // We can do this cleanly:
        // 0x00: ADDI r2, r0, 2      // threshold for Warp 0
        // 0x04: ADDI r6, r0, 6      // threshold for Warp 1
        // Check if warp 0 vs warp 1 by checking if r1 < 4:
        // 0x08: ADDI r7, r0, 4
        // 0x0C: SLT r8, r1, r7      // r8 = 1 for warp 0, r8 = 0 for warp 1
        // 0x10: BEQ r8, r0, +8      // if warp 1: jump to 0x18
        // 0x14: BEQ r0, r0, +8      // if warp 0: jump to 0x1C
        // // Warp 1 setup:
        // 0x18: ADDI r2, r6, 0      // r2 = 6
        // // Both warps continue at 0x1C:
        // 0x1C: SLT r3, r1, r2      // r3 = 1 for lower 2 lanes of each warp, 0 for upper 2 lanes!
        // 0x20: SETRPC 0x0034
        // 0x24: BEQ r3, r0, +12     -> upper 2 lanes take branch to 0x30; lower 2 FT to 0x28
        // // ELSE path (lower 2 lanes: lanes 0,1 for W0, lanes 4,5 for W1):
        // 0x28: ADDI r4, r0, 11
        // 0x2C: BEQ r0, r0, +8      -> jump to RPC 0x34
        // // TAKEN path (upper 2 lanes: lanes 2,3 for W0, lanes 6,7 for W1):
        // 0x30: ADDI r4, r0, 22
        // 0x34: ADDI r5, r4, 100    -> RECONV: lower gets 111, upper gets 122!
        // 0x38: EXIT
        u_top.u_instruction_memory.mem[0]  = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[1]  = enc_alu_i(5'd0, 5'd6, 16'd6);
        u_top.u_instruction_memory.mem[2]  = enc_alu_i(5'd0, 5'd7, 16'd4);
        u_top.u_instruction_memory.mem[3]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd7, 5'd8);
        u_top.u_instruction_memory.mem[4]  = enc_beq(5'd8, 5'd0, 16'd8);
        u_top.u_instruction_memory.mem[5]  = enc_beq(5'd0, 5'd0, 16'd8);
        u_top.u_instruction_memory.mem[6]  = enc_alu_i(5'd6, 5'd2, 16'd0);
        u_top.u_instruction_memory.mem[7]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[8]  = enc_setrpc(16'h0034);
        u_top.u_instruction_memory.mem[9]  = enc_beq(5'd3, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[10] = enc_alu_i(5'd0, 5'd4, 16'd11);
        u_top.u_instruction_memory.mem[11] = enc_beq(5'd0, 5'd0, 16'd8);
        u_top.u_instruction_memory.mem[12] = enc_alu_i(5'd0, 5'd4, 16'd22);
        u_top.u_instruction_memory.mem[13] = enc_alu_i(5'd4, 5'd5, 16'd100);
        u_top.u_instruction_memory.mem[14] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 200);
        wait_warp_done(2'd1, 200);

        // Check Warp 0:
        val0 = u_top.u_compute_unit.u_vrf.regfile[0][0][5];
        val1 = u_top.u_compute_unit.u_vrf.regfile[0][1][5];
        val2 = u_top.u_compute_unit.u_vrf.regfile[0][2][5];
        val3 = u_top.u_compute_unit.u_vrf.regfile[0][3][5];

        // Check Warp 1:
        pass = (val0 == 111 && val1 == 111 && val2 == 122 && val3 == 122) &&
               (u_top.u_compute_unit.u_vrf.regfile[1][0][5] == 111) &&
               (u_top.u_compute_unit.u_vrf.regfile[1][1][5] == 111) &&
               (u_top.u_compute_unit.u_vrf.regfile[1][2][5] == 122) &&
               (u_top.u_compute_unit.u_vrf.regfile[1][3][5] == 122) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0) &&
               (u_top.u_compute_unit.u_simt_stack.sp[1] == 0);

        if (pass) begin
            $display("TEST 6 PASSED: Independent Divergence:");
            $display("         Warp 0: R5=[%0d,%0d,%0d,%0d] (exp: [111,111,122,122]), SP=0",
                val0, val1, val2, val3);
            $display("         Warp 1: R5=[%0d,%0d,%0d,%0d] (exp: [111,111,122,122]), SP=0",
                u_top.u_compute_unit.u_vrf.regfile[1][0][5], u_top.u_compute_unit.u_vrf.regfile[1][1][5],
                u_top.u_compute_unit.u_vrf.regfile[1][2][5], u_top.u_compute_unit.u_vrf.regfile[1][3][5]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 6 FAILED: Warp 0 R5=[%0d,%0d,%0d,%0d], Warp 1 R5=[%0d,%0d,%0d,%0d], SP0=%0d, SP1=%0d",
                val0, val1, val2, val3,
                u_top.u_compute_unit.u_vrf.regfile[1][0][5], u_top.u_compute_unit.u_vrf.regfile[1][1][5],
                u_top.u_compute_unit.u_vrf.regfile[1][2][5], u_top.u_compute_unit.u_vrf.regfile[1][3][5],
                u_top.u_compute_unit.u_simt_stack.sp[0], u_top.u_compute_unit.u_simt_stack.sp[1]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 7: Memory/register writes under divergent masks
        // --------------------------------------------------------
        test_num = 7;
        current_test_name = "Memory/register writes under divergent masks";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // 0x00: ADDI r2, r0, 2
        // 0x04: SLT r3, r1, r2      -> lanes 0,1: r3=1; lanes 2,3: r3=0
        // 0x08: SETRPC 0x0028       -> RPC = 0x28
        // 0x0C: BEQ r3, r0, +16     -> target 0x1C (lanes 2,3); FT 0x10 (lanes 0,1)
        // // ELSE path (lanes 0, 1):
        // 0x10: ADDI r4, r0, 1234
        // 0x14: STORE r1, r4, 100   -> mem[r1 + 100] = 1234 (mem[100]=1234, mem[101]=1234)
        // 0x18: BEQ r0, r0, +16     -> jump to RPC 0x28
        // // TAKEN path (lanes 2, 3):
        // 0x1C: ADDI r4, r0, 5678
        // 0x20: STORE r1, r4, 100   -> mem[r1 + 100] = 5678 (mem[102]=5678, mem[103]=5678)
        // 0x24: BEQ r0, r0, +4      -> jump to RPC 0x28
        // // RECONVERGENCE:
        // 0x28: ADDI r4, r5, 1      -> r5 = r4 + 1 (lane 0,1: 1235, lane 2,3: 5679)
        // 0x2C: EXIT
        u_top.u_instruction_memory.mem[0]  = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[1]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[2]  = enc_setrpc(16'h0028);
        u_top.u_instruction_memory.mem[3]  = enc_beq(5'd3, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[4]  = enc_alu_i(5'd0, 5'd4, 16'd1234);
        u_top.u_instruction_memory.mem[5]  = enc_store(5'd1, 5'd4, 16'd100);
        u_top.u_instruction_memory.mem[6]  = enc_beq(5'd0, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[7]  = enc_alu_i(5'd0, 5'd4, 16'd5678);
        u_top.u_instruction_memory.mem[8]  = enc_store(5'd1, 5'd4, 16'd100);
        u_top.u_instruction_memory.mem[9]  = enc_beq(5'd0, 5'd0, 16'd4);
        u_top.u_instruction_memory.mem[10] = enc_alu_i(5'd4, 5'd5, 16'd1);
        u_top.u_instruction_memory.mem[11] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 200);

        // Check memory contents:
        val0 = u_top.u_data_memory.mem[100];
        val1 = u_top.u_data_memory.mem[101];
        val2 = u_top.u_data_memory.mem[102];
        val3 = u_top.u_data_memory.mem[103];

        pass = (val0 == 1234 && val1 == 1234 && val2 == 5678 && val3 == 5678) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][4] == 1234) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][4] == 1234) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][4] == 5678) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][4] == 5678) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][5] == 1235) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][5] == 1235) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][5] == 5679) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][5] == 5679) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 7 PASSED: Memory and register writes gated by active_mask:");
            $display("         mem[100..103] = [%0d, %0d, %0d, %0d] (exp: [1234, 1234, 5678, 5678])",
                val0, val1, val2, val3);
            $display("         VRF R4 (divergent) = [%0d, %0d, %0d, %0d] (exp: [1234, 1234, 5678, 5678])",
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4]);
            $display("         VRF R5 (reconverged) = [%0d, %0d, %0d, %0d] (exp: [1235, 1235, 5679, 5679])",
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 7 FAILED: mem[100..103] = [%0d, %0d, %0d, %0d], R4=[%0d,%0d,%0d,%0d], R5=[%0d,%0d,%0d,%0d], SP=%0d",
                val0, val1, val2, val3,
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4],
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5],
                u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 8: Stale SETRPC Invalidation / Clear on Branch Resolution
        // --------------------------------------------------------
        test_num = 8;
        current_test_name = "Stale SETRPC Invalidation (Uniform branch -> later divergent branch without SETRPC)";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // Sequence:
        // 0x00: SETRPC 0x0088       -> pending_rpc[0] = 0x0088 (RPC_A)
        // 0x04: BEQ r0, r0, +8      -> Uniform taken branch to 0x0C
        //                            When this resolves in EX, pending_rpc[0] must be CLEARED!
        // 0x08: ADDI r2, r0, 99     -> dead code
        // 0x0C: ADDI r2, r0, 2
        // 0x10: SLT r3, r1, r2      -> r3 = (tid < 2) ? 1 : 0 -> [1, 1, 0, 0]
        // 0x14: BEQ r3, r0, +12     -> Divergent branch WITHOUT SETRPC! (Lanes 2,3 take to 0x20; lanes 0,1 FT to 0x18)
        // 0x18: EXIT
        // 0x1C: EXIT
        // 0x20: EXIT
        u_top.u_instruction_memory.mem[0] = enc_setrpc(16'h0088);
        u_top.u_instruction_memory.mem[1] = enc_beq(5'd0, 5'd0, 16'd8);
        u_top.u_instruction_memory.mem[2] = enc_alu_i(5'd0, 5'd2, 16'd99);
        u_top.u_instruction_memory.mem[3] = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[4] = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[5] = enc_beq(5'd3, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[6] = enc_exit(1'b0);
        u_top.u_instruction_memory.mem[7] = enc_exit(1'b0);
        u_top.u_instruction_memory.mem[8] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 150);

        pass = (u_top.u_compute_unit.u_simt_stack.s_reconv_pc[0][0] != 16'h0088) &&
               (u_top.u_compute_unit.u_simt_stack.s_reconv_pc[0][0] == 16'h0000) &&
               (u_top.u_compute_unit.u_simt_stack.pending_rpc[0] != 16'h0088);

        if (pass) begin
            $display("TEST 8 PASSED: Stale SETRPC Invalidation verified:");
            $display("         Pushed Reconv PC = %04h (exp: 0000, NOT stale RPC_A 0088)",
                u_top.u_compute_unit.u_simt_stack.s_reconv_pc[0][0]);
            $display("         Pending RPC      = %04h (exp: 0000)",
                u_top.u_compute_unit.u_simt_stack.pending_rpc[0]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 8 FAILED: Pushed Reconv PC = %04h (stale RPC_A 0088 was mistakenly used!), Pending RPC = %04h",
                u_top.u_compute_unit.u_simt_stack.s_reconv_pc[0][0],
                u_top.u_compute_unit.u_simt_stack.pending_rpc[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 9: Case 1: Divergent Producer -> Same-Path Consumer
        // --------------------------------------------------------
        test_num = 9;
        current_test_name = "Case 1: Divergent Producer -> Same-Path Consumer";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // 0x00: ADDI r4, r0, 5       -> All lanes initialize R4 = 5
        // 0x04: ADDI r2, r0, 2
        // 0x08: SLT  r3, r1, r2      -> R3 = (tid < 2) ? 1 : 0 -> [1, 1, 0, 0]
        // 0x0C: SETRPC 0x0028        -> RPC = 0x28
        // 0x10: BEQ  r3, r0, +16     -> Taken to 0x20 (lanes 2, 3); FT to 0x14 (lanes 0, 1)
        // // Else path (lanes 0, 1, FT = 0x14, mask = 0011):
        // 0x14: ADDI r5, r4, 1       -> Reads R4=5 (untouched by taken path!) -> R5=6
        // 0x18: BEQ  r0, r0, +16     -> Jump to RPC 0x28
        // 0x1C: NOP
        // // Taken path (lanes 2, 3, Target = 0x20, mask = 1100):
        // 0x20: ADDI r4, r0, 20      -> PRODUCER: writes R4=20 (lanes 2, 3 only!)
        // 0x24: ADDI r5, r4, 10      -> CONSUMER: reads R4=20 -> R5=30 (lanes 2, 3)
        // // Reconvergence (RPC = 0x28, all lanes active, mask = 1111):
        // 0x28: ADDI r6, r5, 0       -> Copy R5 to R6
        // 0x2C: EXIT
        u_top.u_instruction_memory.mem[0]  = enc_alu_i(5'd0, 5'd4, 16'd5);
        u_top.u_instruction_memory.mem[1]  = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[2]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[3]  = enc_setrpc(16'h0028);
        u_top.u_instruction_memory.mem[4]  = enc_beq(5'd3, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[5]  = enc_alu_i(5'd4, 5'd5, 16'd1);
        u_top.u_instruction_memory.mem[6]  = enc_beq(5'd0, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[7]  = 32'h00000000;
        u_top.u_instruction_memory.mem[8]  = enc_alu_i(5'd0, 5'd4, 16'd20);
        u_top.u_instruction_memory.mem[9]  = enc_alu_i(5'd4, 5'd5, 16'd10);
        u_top.u_instruction_memory.mem[10] = enc_alu_i(5'd5, 5'd6, 16'd0);
        u_top.u_instruction_memory.mem[11] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 200);

        pass = (u_top.u_compute_unit.u_vrf.regfile[0][0][4] == 5) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][4] == 5) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][4] == 20) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][4] == 20) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][5] == 6) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][5] == 6) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][5] == 30) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][5] == 30) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][6] == 6) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][6] == 6) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][6] == 30) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][6] == 30) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 9 PASSED: Divergent Producer -> Same-Path Consumer verified:");
            $display("         R4 (lanes 0,1 preserved at 5, lanes 2,3 written 20) = [%0d,%0d,%0d,%0d]",
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4]);
            $display("         R5 (else read 5->6, taken read 20->30)               = [%0d,%0d,%0d,%0d]",
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 9 FAILED: R4=[%0d,%0d,%0d,%0d], R5=[%0d,%0d,%0d,%0d], SP=%0d",
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4],
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5],
                u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 10: Case 2: Different Values From Each Path -> Reconverged Consumer
        // --------------------------------------------------------
        test_num = 10;
        current_test_name = "Case 2: Different Values From Each Path -> Reconverged Consumer";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // 0x00: ADDI r2, r0, 2
        // 0x04: SLT  r3, r1, r2      -> r3 = [1, 1, 0, 0]
        // 0x08: SETRPC 0x0024        -> RPC = 0x24
        // 0x0C: BEQ  r3, r0, +16     -> Taken to 0x1C (lanes 2, 3); FT to 0x10 (lanes 0, 1)
        // // Else path (lanes 0, 1, mask 0011):
        // 0x10: ADDI r4, r0, 100     -> Writes R4 = 100 for lanes 0, 1
        // 0x14: BEQ  r0, r0, +16     -> Jump to RPC 0x24
        // 0x18: NOP
        // // Taken path (lanes 2, 3, mask 1100):
        // 0x1C: ADDI r4, r0, 200     -> Writes R4 = 200 for lanes 2, 3
        // 0x20: BEQ  r0, r0, +4      -> Jump to RPC 0x24
        // // Reconvergence (all lanes active, mask 1111):
        // 0x24: ADDI r5, r4, 1       -> Reconverged consumer: R5 = R4 + 1
        // 0x28: EXIT
        u_top.u_instruction_memory.mem[0]  = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[1]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[2]  = enc_setrpc(16'h0024);
        u_top.u_instruction_memory.mem[3]  = enc_beq(5'd3, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[4]  = enc_alu_i(5'd0, 5'd4, 16'd100);
        u_top.u_instruction_memory.mem[5]  = enc_beq(5'd0, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[6]  = 32'h00000000;
        u_top.u_instruction_memory.mem[7]  = enc_alu_i(5'd0, 5'd4, 16'd200);
        u_top.u_instruction_memory.mem[8]  = enc_beq(5'd0, 5'd0, 16'd4);
        u_top.u_instruction_memory.mem[9]  = enc_alu_i(5'd4, 5'd5, 16'd1);
        u_top.u_instruction_memory.mem[10] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 200);

        pass = (u_top.u_compute_unit.u_vrf.regfile[0][0][4] == 100) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][4] == 100) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][4] == 200) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][4] == 200) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][5] == 101) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][5] == 101) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][5] == 201) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][5] == 201) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 10 PASSED: Different Values From Each Path -> Reconverged Consumer verified:");
            $display("         R4 (else=100, taken=200)       = [%0d,%0d,%0d,%0d]",
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4]);
            $display("         R5 (reconverged R4+1)          = [%0d,%0d,%0d,%0d] (exp: [101,101,201,201])",
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 10 FAILED: R4=[%0d,%0d,%0d,%0d], R5=[%0d,%0d,%0d,%0d], SP=%0d",
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4],
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5],
                u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 11: Case 3: RAW Hazard Across Divergence
        // --------------------------------------------------------
        test_num = 11;
        current_test_name = "Case 3: RAW Hazard Across Divergence";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();
        raw_stall_detected = 0;

        // Sequence with back-to-back RAW dependencies:
        // 0x00: ADDI r2, r0, 2       -> Producer of R2
        // 0x04: SLT  r3, r1, r2      -> RAW consumer of R2 (stalls on R2 busy!)
        // 0x08: SETRPC 0x0024        -> Staging RPC = 0x24
        // 0x0C: BEQ  r3, r0, +16     -> RAW consumer of R3 (stalls on R3 busy!)
        // // Else path (lanes 0, 1, FT = 0x10):
        // 0x10: ADDI r4, r0, 11
        // 0x14: BEQ  r0, r0, +16     -> Jump to RPC 0x24
        // 0x18: NOP
        // // Taken path (lanes 2, 3, Target = 0x1C):
        // 0x1C: ADDI r4, r0, 22
        // 0x20: BEQ  r0, r0, +4      -> Jump to RPC 0x24
        // // Reconvergence (0x24):
        // 0x24: ADDI r5, r4, 0
        // 0x28: EXIT
        u_top.u_instruction_memory.mem[0]  = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[1]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[2]  = enc_setrpc(16'h0024);
        u_top.u_instruction_memory.mem[3]  = enc_beq(5'd3, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[4]  = enc_alu_i(5'd0, 5'd4, 16'd11);
        u_top.u_instruction_memory.mem[5]  = enc_beq(5'd0, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[6]  = 32'h00000000;
        u_top.u_instruction_memory.mem[7]  = enc_alu_i(5'd0, 5'd4, 16'd22);
        u_top.u_instruction_memory.mem[8]  = enc_beq(5'd0, 5'd0, 16'd4);
        u_top.u_instruction_memory.mem[9]  = enc_alu_i(5'd4, 5'd5, 16'd0);
        u_top.u_instruction_memory.mem[10] = enc_exit(1'b0);

        do_reset();
        // Inactivate Warps 1..3 so Warp 0 issues back-to-back instructions to test single-warp RAW hazard stalls
        u_top.u_compute_unit.u_warp_manager.warp_state_array[1] = `WARP_DONE;
        u_top.u_compute_unit.u_warp_manager.warp_state_array[2] = `WARP_DONE;
        u_top.u_compute_unit.u_warp_manager.warp_state_array[3] = `WARP_DONE;
        wait_warp_done(2'd0, 200);

        pass = (raw_stall_detected > 0) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][4] == 11) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][4] == 11) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][4] == 22) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][4] == 22) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][5] == 11) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][5] == 11) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][5] == 22) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][5] == 22) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 11 PASSED: RAW Hazard Across Divergence verified:");
            $display("         Scoreboard RAW Stalls Detected = %0d (> 0)", raw_stall_detected);
            $display("         R4 = [%0d,%0d,%0d,%0d] (exp: [11,11,22,22])",
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4]);
            $display("         R5 = [%0d,%0d,%0d,%0d] (exp: [11,11,22,22])",
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 11 FAILED: raw_stalls=%0d, R4=[%0d,%0d,%0d,%0d], R5=[%0d,%0d,%0d,%0d], SP=%0d",
                raw_stall_detected,
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4],
                u_top.u_compute_unit.u_vrf.regfile[0][0][5], u_top.u_compute_unit.u_vrf.regfile[0][1][5],
                u_top.u_compute_unit.u_vrf.regfile[0][2][5], u_top.u_compute_unit.u_vrf.regfile[0][3][5],
                u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 12: Case 4: Older In-Flight Instruction + Divergence
        // --------------------------------------------------------
        test_num = 12;
        current_test_name = "Case 4: Older In-Flight Instruction + Divergence";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // 0x00: ADDI r2, r0, 2
        // 0x04: SLT  r3, r1, r2      -> r3 = [1, 1, 0, 0] (commits to VRF)
        // 0x08: ADDI r6, r0, 77      -> OLDER IN-FLIGHT INSTRUCTION (writes R6=77 under full mask 1111)
        // 0x0C: SETRPC 0x0028        -> Staged in decode, transparent
        // 0x10: BEQ  r3, r0, +16     -> In EX at cycle T4 while ADDI R6 is in WB!
        // // Else path (lanes 0, 1, FT = 0x14, mask = 0011):
        // 0x14: ADDI r7, r6, 2       -> Reads R6 (= 77)! R7 = 77 + 2 = 79
        // 0x18: BEQ  r0, r0, +16     -> Jump to RPC 0x28
        // 0x1C: NOP
        // // Taken path (lanes 2, 3, Target = 0x20, mask = 1100):
        // 0x20: ADDI r7, r6, 1       -> Reads R6 (= 77)! R7 = 77 + 1 = 78
        // 0x24: BEQ  r0, r0, +4      -> Jump to RPC 0x28
        // // Reconvergence (all lanes active, mask 1111):
        // 0x28: ADDI r8, r7, 0       -> Copy R7 to R8
        // 0x2C: EXIT
        u_top.u_instruction_memory.mem[0]  = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[1]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[2]  = enc_alu_i(5'd0, 5'd6, 16'd77);
        u_top.u_instruction_memory.mem[3]  = enc_setrpc(16'h0028);
        u_top.u_instruction_memory.mem[4]  = enc_beq(5'd3, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[5]  = enc_alu_i(5'd6, 5'd7, 16'd2);
        u_top.u_instruction_memory.mem[6]  = enc_beq(5'd0, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[7]  = 32'h00000000;
        u_top.u_instruction_memory.mem[8]  = enc_alu_i(5'd6, 5'd7, 16'd1);
        u_top.u_instruction_memory.mem[9]  = enc_beq(5'd0, 5'd0, 16'd4);
        u_top.u_instruction_memory.mem[10] = enc_alu_i(5'd7, 5'd8, 16'd0);
        u_top.u_instruction_memory.mem[11] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 200);

        pass = (u_top.u_compute_unit.u_vrf.regfile[0][0][6] == 77) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][6] == 77) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][6] == 77) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][6] == 77) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][7] == 79) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][7] == 79) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][7] == 78) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][7] == 78) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][8] == 79) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][8] == 79) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][8] == 78) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][8] == 78) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 12 PASSED: Older In-Flight Instruction + Divergence verified:");
            $display("         R6 (written under full mask 1111)    = [%0d,%0d,%0d,%0d] (exp: [77,77,77,77])",
                u_top.u_compute_unit.u_vrf.regfile[0][0][6], u_top.u_compute_unit.u_vrf.regfile[0][1][6],
                u_top.u_compute_unit.u_vrf.regfile[0][2][6], u_top.u_compute_unit.u_vrf.regfile[0][3][6]);
            $display("         R7 (else read 77+2=79, taken 77+1=78)= [%0d,%0d,%0d,%0d] (exp: [79,79,78,78])",
                u_top.u_compute_unit.u_vrf.regfile[0][0][7], u_top.u_compute_unit.u_vrf.regfile[0][1][7],
                u_top.u_compute_unit.u_vrf.regfile[0][2][7], u_top.u_compute_unit.u_vrf.regfile[0][3][7]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 12 FAILED: R6=[%0d,%0d,%0d,%0d], R7=[%0d,%0d,%0d,%0d], SP=%0d",
                u_top.u_compute_unit.u_vrf.regfile[0][0][6], u_top.u_compute_unit.u_vrf.regfile[0][1][6],
                u_top.u_compute_unit.u_vrf.regfile[0][2][6], u_top.u_compute_unit.u_vrf.regfile[0][3][6],
                u_top.u_compute_unit.u_vrf.regfile[0][0][7], u_top.u_compute_unit.u_vrf.regfile[0][1][7],
                u_top.u_compute_unit.u_vrf.regfile[0][2][7], u_top.u_compute_unit.u_vrf.regfile[0][3][7],
                u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // TEST 13: Case 5: Nested Divergence + Register Dependency
        // --------------------------------------------------------
        test_num = 13;
        current_test_name = "Case 5: Nested Divergence + Register Dependency";
        $display("\n------------------------------------------------------------------");
        $display("TEST %0d: %s", test_num, current_test_name);
        $display("------------------------------------------------------------------");
        clear_memories();

        // 0x00: ADDI r2, r0, 2
        // 0x04: SLT  r3, r1, r2      -> r3 = [1, 1, 0, 0]
        // 0x08: SETRPC 0x0048        -> Outer RPC = 0x48
        // 0x0C: BEQ  r3, r0, +16     -> Outer branch: taken to 0x1C (lanes 2, 3); FT to 0x10 (lanes 0, 1)
        // // Outer Else Path (lanes 0, 1, mask 0011):
        // 0x10: ADDI r4, r0, 50      -> Lanes 0, 1 write R4 = 50
        // 0x14: ADDI r4, r4, 5       -> Consumer: R4 = 50 + 5 = 55
        // 0x18: BEQ  r0, r0, +48     -> Jump to Outer RPC 0x48 (0x18 + 48 = 0x48)
        // // Outer Taken Path (lanes 2, 3 active, mask 1100):
        // 0x1C: ADDI r2, r0, 3
        // 0x20: SLT  r3, r1, r2      -> lane 2 gets 1, lane 3 gets 0
        // 0x24: SETRPC 0x003C        -> Inner RPC = 0x3C
        // 0x28: BEQ  r3, r0, +12     -> Inner branch: taken to 0x34 (lane 3); FT to 0x2C (lane 2)
        // // Inner Else Path (lane 2 active, mask 0100):
        // 0x2C: ADDI r4, r0, 70      -> Lane 2 writes R4 = 70
        // 0x30: BEQ  r0, r0, +12     -> Jump to Inner RPC 0x3C (0x30 + 12 = 0x3C)
        // // Inner Taken Path (lane 3 active, mask 1000):
        // 0x34: ADDI r4, r0, 80      -> Lane 3 writes R4 = 80
        // 0x38: BEQ  r0, r0, +4      -> Jump to Inner RPC 0x3C (0x38 + 4 = 0x3C)
        // // Inner Reconvergence (lanes 2, 3 active, mask 1100, SP=2):
        // 0x3C: ADDI r4, r4, 5       -> Consumer: Lane 2 gets 70+5=75; Lane 3 gets 80+5=85
        // 0x40: BEQ  r0, r0, +8      -> Jump to Outer RPC 0x48 (0x40 + 8 = 0x48)
        // 0x44: NOP
        // // Outer Reconvergence (all lanes active, mask 1111, SP=0):
        // 0x48: ADDI r6, r4, 1       -> Reconverged consumer: R6 = R4 + 1
        // 0x4C: EXIT
        u_top.u_instruction_memory.mem[0]  = enc_alu_i(5'd0, 5'd2, 16'd2);
        u_top.u_instruction_memory.mem[1]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[2]  = enc_setrpc(16'h0048);
        u_top.u_instruction_memory.mem[3]  = enc_beq(5'd3, 5'd0, 16'd16);
        u_top.u_instruction_memory.mem[4]  = enc_alu_i(5'd0, 5'd4, 16'd50);
        u_top.u_instruction_memory.mem[5]  = enc_alu_i(5'd4, 5'd4, 16'd5);
        u_top.u_instruction_memory.mem[6]  = enc_beq(5'd0, 5'd0, 16'd48);
        u_top.u_instruction_memory.mem[7]  = enc_alu_i(5'd0, 5'd2, 16'd3);
        u_top.u_instruction_memory.mem[8]  = enc_alu_r(`FUNC_SLT, 5'd1, 5'd2, 5'd3);
        u_top.u_instruction_memory.mem[9]  = enc_setrpc(16'h003C);
        u_top.u_instruction_memory.mem[10] = enc_beq(5'd3, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[11] = enc_alu_i(5'd0, 5'd4, 16'd70);
        u_top.u_instruction_memory.mem[12] = enc_beq(5'd0, 5'd0, 16'd12);
        u_top.u_instruction_memory.mem[13] = enc_alu_i(5'd0, 5'd4, 16'd80);
        u_top.u_instruction_memory.mem[14] = enc_beq(5'd0, 5'd0, 16'd4);
        u_top.u_instruction_memory.mem[15] = enc_alu_i(5'd4, 5'd4, 16'd5);
        u_top.u_instruction_memory.mem[16] = enc_beq(5'd0, 5'd0, 16'd8);
        u_top.u_instruction_memory.mem[17] = 32'h00000000;
        u_top.u_instruction_memory.mem[18] = enc_alu_i(5'd4, 5'd6, 16'd1);
        u_top.u_instruction_memory.mem[19] = enc_exit(1'b0);

        do_reset();
        wait_warp_done(2'd0, 250);

        pass = (u_top.u_compute_unit.u_vrf.regfile[0][0][4] == 55) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][4] == 55) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][4] == 75) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][4] == 85) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][0][6] == 56) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][1][6] == 56) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][2][6] == 76) &&
               (u_top.u_compute_unit.u_vrf.regfile[0][3][6] == 86) &&
               (u_top.u_compute_unit.u_simt_stack.sp[0] == 0);

        if (pass) begin
            $display("TEST 13 PASSED: Nested Divergence + Register Dependency verified:");
            $display("         R4 (lane0,1=55, lane2=75, lane3=85) = [%0d,%0d,%0d,%0d]",
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4]);
            $display("         R6 (reconverged R4+1)                 = [%0d,%0d,%0d,%0d] (exp: [56,56,76,86])",
                u_top.u_compute_unit.u_vrf.regfile[0][0][6], u_top.u_compute_unit.u_vrf.regfile[0][1][6],
                u_top.u_compute_unit.u_vrf.regfile[0][2][6], u_top.u_compute_unit.u_vrf.regfile[0][3][6]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("TEST 13 FAILED: R4=[%0d,%0d,%0d,%0d], R6=[%0d,%0d,%0d,%0d], SP=%0d",
                u_top.u_compute_unit.u_vrf.regfile[0][0][4], u_top.u_compute_unit.u_vrf.regfile[0][1][4],
                u_top.u_compute_unit.u_vrf.regfile[0][2][4], u_top.u_compute_unit.u_vrf.regfile[0][3][4],
                u_top.u_compute_unit.u_vrf.regfile[0][0][6], u_top.u_compute_unit.u_vrf.regfile[0][1][6],
                u_top.u_compute_unit.u_vrf.regfile[0][2][6], u_top.u_compute_unit.u_vrf.regfile[0][3][6],
                u_top.u_compute_unit.u_simt_stack.sp[0]);
            tests_failed = tests_failed + 1;
        end

        // --------------------------------------------------------
        // Summary Report
        // --------------------------------------------------------
        $display("\n==================================================================");
        $display("                   REGRESSION SUMMARY                             ");
        $display("==================================================================");
        $display("  Total Tests Run : %0d", tests_passed + tests_failed);
        $display("  Tests Passed    : %0d", tests_passed);
        $display("  Tests Failed    : %0d", tests_failed);
        $display("==================================================================");
        if (tests_failed == 0)
            $display("  >>> ALL 13 SIMT DIVERGENCE & DEPENDENCY TESTS PASSED! <<<");
        else
            $display("  >>> SOME TESTS FAILED! <<<");
        $display("==================================================================\n");

        $finish;
    end

endmodule
