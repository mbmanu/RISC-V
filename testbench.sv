`define hdl_path_regf c.regs
module testbench;

  reg clk;
  reg resetn;
  wire trap;
  reg [7:0] cnt;

  twitchcore c (
    .clk (clk),
    .resetn (resetn),
    .trap (trap)
  );

  initial begin
    string firmware;
    clk = 0;
    cnt = 0;
    // put core to reset while initializing ram
    resetn = 0;

    $display("programming the mem");
    if ($value$plusargs("firmware=%s", firmware)) begin
        $display($sformatf("Using %s as firmware", firmware));
    end else begin
        $display($sformatf("Expecting a command line argument %s", firmware), "ERROR");
        $finish;
    end
    $readmemh(firmware, c.r.mem);

    $display("doing work", cnt);
    @(posedge clk);
    resetn = 1;
  end

  always
    #5 clk = !clk;

  always @(posedge clk) begin
    cnt <= cnt + 1;
    resetn <= 0;
  end



  always @(posedge clk) begin
    if (c.step[6] == 1'b1) begin
      $display("%b: %h %d pc:%h -- opcode:%b -- func:%h alt:%d left:%h imm:%h pend:%h d_addr:%h d_data:%h c.rs1:%h c.rs2:%h c.rd:%h",
        c.step, c.i_data, c.resetn, c.pc, c.opcode, c.alu_func, c.alu_alt, c.alu_left, c.alu_imm, c.pend, c.d_addr, c.d_data, c.rs1, c.rs2, c.rd);
      // foreach (c.regs[i]) $display("regs[%d]:%d", i, c.regs[i]);
      for (int i = 10; i < 18; i = i + 1) $display("regs[%1d]:%2d", i, c.regs[i]);
    end
  end

  always @(posedge trap) begin
    $display("TRAP", c.regs[3]);
    $finish;
  end

  initial begin
    int char_0, char_1, char_2, char_3;
    $dumpfile("waves.vcd");
    $dumpvars(0,testbench);
    #400
    $display("no more work ", cnt);
    $finish;
  end
endmodule

