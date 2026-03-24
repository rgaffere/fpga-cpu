`timescale 1ns / 1ps
`include "defines.vh"

module tb_cpu_top;

    reg clk;
    reg rst;

    // Clock generation: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
    cpu_top #(
        .MEM_BYTES(65536),
        .INIT_FILE("test_mem.hex")
    ) u_dut (
        .clk(clk),
        .rst(rst)
    );

    // Convenience accessors into the DUT hierarchy
    wire [`FSM_STATE_W-1:0] state  = u_dut.u_control_unit.state;
    wire [`XLEN-1:0]        pc     = u_dut.u_datapath.pc_curr;
    wire [`XLEN-1:0]        ir     = u_dut.u_control_unit.ir_reg;
    wire                     halted = u_dut.u_control_unit.halt;

    // Register file peek
    wire [`XLEN-1:0] r4 = u_dut.u_datapath.u_regfile.regs[4];
    wire [`XLEN-1:0] r5 = u_dut.u_datapath.u_regfile.regs[5];
    wire [`XLEN-1:0] r6 = u_dut.u_datapath.u_regfile.regs[6];
    wire [`XLEN-1:0] r7 = u_dut.u_datapath.u_regfile.regs[7];
    wire [`XLEN-1:0] r8 = u_dut.u_datapath.u_regfile.regs[8];

    wire flag_z = u_dut.u_datapath.flag_z;
    wire flag_n = u_dut.u_datapath.flag_n;

    integer cycle_count;
    integer pass;

    initial begin
        $dumpfile("tb_cpu_top.vcd");
        $dumpvars(0, tb_cpu_top);

        // Reset
        rst = 1;
        #30;
        rst = 0;

        cycle_count = 0;
        pass = 1;

        // Run until HALT or timeout
        while (!halted && cycle_count < 500) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            // Debug trace
            if (state == `S_FETCH)
                $display("  [cyc %0d] FETCH  PC=%08h", cycle_count, pc);
            if (state == `S_WRITEBACK)
                $display("  [cyc %0d] WB     IR=%08h  r4=%0d r5=%0d r6=%0d r7=%0d r8=%0d",
                         cycle_count, ir, r4, r5, r6, r7, r8);
            if (state == `S_BRANCH)
                $display("  [cyc %0d] BRANCH Z=%b N=%b", cycle_count, flag_z, flag_n);
        end

        $display("");
        $display("=== Simulation complete: %0d cycles ===", cycle_count);
        $display("  r4  = %0d (expected 10)", r4);
        $display("  r5  = %0d (expected 20)", r5);
        $display("  r6  = %0d (expected 30)", r6);
        $display("  r7  = %0d (expected 256)", r7);
        $display("  r8  = %0d (expected 30)", r8);
        $display("  halt = %0b", halted);

        // Check results
        if (r4 !== 32'd10) begin
            $display("FAIL: r4 != 10");
            pass = 0;
        end
        if (r5 !== 32'd20) begin
            $display("FAIL: r5 != 20");
            pass = 0;
        end
        if (r6 !== 32'd30) begin
            $display("FAIL: r6 != 30");
            pass = 0;
        end
        if (r7 !== 32'd256) begin
            $display("FAIL: r7 != 256");
            pass = 0;
        end
        if (r8 !== 32'd30) begin
            $display("FAIL: r8 != 30 (store/load round-trip failed)");
            pass = 0;
        end
        if (!halted) begin
            $display("FAIL: CPU did not halt (timeout)");
            pass = 0;
        end

        if (pass)
            $display("\n*** ALL CHECKS PASSED ***\n");
        else
            $display("\n*** SOME CHECKS FAILED ***\n");

        $finish;
    end

endmodule
