`timescale 1ns/1ps

module tb_mm;

  // Clock
  reg clk;

  // Write port
  reg  [3:0] waddr;
  reg  [7:0] wdata;
  reg        we;

  // Read ports
  reg  [3:0] raddr0, raddr1;
  wire [7:0] rdata0, rdata1;

  // DUT
  mm dut (
    .waddr(waddr),
    .wdata(wdata),
    .we(we),
    .clk(clk),
    .raddr0(raddr0),
    .rdata0(rdata0),
    .raddr1(raddr1),
    .rdata1(rdata1)
  );

  // 100 MHz clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Write helper (sync write on posedge)
  task write_mem(input [3:0] a, input [7:0] v);
    begin
      @(negedge clk);
      waddr <= a;
      wdata <= v;
      we    <= 1'b1;
      @(posedge clk);       // write occurs here
      @(negedge clk);
      we    <= 1'b0;
      wdata <= 8'h00;
    end
  endtask

  // Async read check helper: set addresses, wait, compare both outputs
  task read2_check_async(input [3:0] a0, input [7:0] e0,
                         input [3:0] a1, input [7:0] e1);
    begin
      @(negedge clk);
      raddr0 <= a0;
      raddr1 <= a1;
      #1;
      if (rdata0 !== e0 || rdata1 !== e1) begin
        $display("FAIL @%0t: r0[addr=%0d]=%h exp=%h | r1[addr=%0d]=%h exp=%h",
                 $time, a0, rdata0, e0, a1, rdata1, e1);
        $stop;
      end else begin
        $display("PASS @%0t: r0[%0d]=%h | r1[%0d]=%h",
                 $time, a0, rdata0, a1, rdata1);
      end
    end
  endtask

  integer i;

  initial begin
    // Init
    we     = 1'b0;
    waddr  = 4'h0;
    wdata  = 8'h00;
    raddr0 = 4'h0;
    raddr1 = 4'h0;

    repeat (2) @(posedge clk);

    $display("---- TEST: basic writes then dual reads ----");

    write_mem(4'h0, 8'hA5);
    write_mem(4'h1, 8'h3C);
    write_mem(4'hF, 8'hFF);

    // Read two addresses at once
    read2_check_async(4'h0, 8'hA5, 4'h1, 8'h3C);
    read2_check_async(4'hF, 8'hFF, 4'h0, 8'hA5);

    $display("---- TEST: bulk fill ----");

    for (i = 0; i < 16; i = i + 1) begin
      write_mem(i[3:0], (i*3));
    end

    // Spot dual reads
    read2_check_async(4'h5, (5*3), 4'hA, (10*3));
    read2_check_async(4'h0, (0*3), 4'hF, (15*3));

    $display("---- TEST: write-first collision behavior ----");
    // Prepare a known old value at address 2
    write_mem(4'h2, 8'h11);

    // Set reads to collide with upcoming write
    @(negedge clk);
    raddr0 <= 4'h2;   // collide with write
    raddr1 <= 4'h3;   // non-colliding
    waddr  <= 4'h2;
    wdata  <= 8'h22;
    we     <= 1'b1;

    // Before posedge, async read sees old mem[2]=0x11
    #1;
    $display("INFO pre-edge @%0t: r0=%h (expected old=22), r1=%h", $time, rdata0, rdata1);

    // At posedge, write happens. If your DUT has explicit write-first mux,
    // rdata0 should become 0x22 right after the edge.
    @(posedge clk);
    #1;
    if (rdata0 !== 8'h22) begin
      $display("FAIL write-first @%0t: r0=%h expected 22", $time, rdata0);
      $stop;
    end else begin
      $display("PASS write-first @%0t: r0=%h", $time, rdata0);
    end

    // Cleanup
    @(negedge clk);
    we <= 1'b0;

    $display("ALL TESTS PASSED");
    $finish;
  end

endmodule
