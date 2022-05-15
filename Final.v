
module risk_single_mem #(parameter LINE=18) (
  input clk,
  input [9:0] addr,
  output reg [LINE-1:0] data_r,
  input [LINE-1:0] data_w,
  input we
);
  reg [LINE-1:0] mem [0:1023];
  always @(posedge clk) begin
    if (we) begin
      mem[addr] <= data_w;
    end else begin
      data_r <= mem[addr];
    end
  end
endmodule


// this is hard to synthesize
module risk_mem #(parameter SZ=4, LOGCNT=5, BITS=18) (
  input clk,
  input [10+LOGCNT-1:0] addr,
  input [10+LOGCNT-2:0] stride_x,
  input [10+LOGCNT-2:0] stride_y,
  input [BITS*SZ*SZ-1:0] dat_w,
  input we,
  output reg [BITS*SZ*SZ-1:0] dat_r
);
  parameter CNT=(1<<LOGCNT);


  parameter SZ_X=1;
  parameter LINE=BITS*SZ;

  // 1 cycle to get all the addresses
  reg [(10+LOGCNT)*SZ*SZ_X-1:0] addrs;

  generate
    genvar x,y;
    for (y=0; y<SZ; y=y+1) begin
      for (x=0; x<SZ_X; x=x+1) begin
        always @(posedge clk) begin
          addrs[(y*SZ_X+x)*(10+LOGCNT) +: (10+LOGCNT)] <= addr + stride_x*x + stride_y*y;
        end
      end
    end
  endgenerate
  
  reg [CNT*SZ_X*SZ-1:0] mask;
  wire [LINE*CNT-1:0] outs;

  generate
    genvar i,k;

    // CNT number of priority encoders of SZ*SZ
    for (i=0; i<CNT; i=i+1) begin
      reg [9:0] taddr;
      reg [LINE-1:0] in;
      wire [LINE-1:0] out;
      risk_single_mem #(LINE) rsm(
        .clk(clk),
        .addr(taddr),
        .data_r(out),
        .data_w(in),
        .we(we)
      );

      integer l;
      always @(posedge clk) begin
        //ens[i] <= 'b0;
        mask[i*SZ_X*SZ +: SZ_X*SZ] <= 'b0;
        for (l=SZ_X*SZ-1; l>=0; l=l-1) begin
          if (addrs[(10+LOGCNT)*l +: LOGCNT] == i) begin
            mask[i*SZ_X*SZ +: SZ_X*SZ] <= (1 << l);
            taddr <= addrs[(10+LOGCNT)*l+LOGCNT +: 10];
            in <= dat_w[LINE*l +: LINE];
          end
        end
      end
      assign outs[i*LINE +: LINE] = out;
    end

    // this is SZ*SZ number of CNT to 1 muxes. these don't have to be priority encoders, really just a big or gate
    for (k=0; k<SZ_X*SZ; k=k+1) begin
      wire [CNT-1:0] lmask;
      for (i=0; i < CNT; i=i+1) assign lmask[i] = mask[i*SZ_X*SZ + k];

      integer l;
      always @(posedge clk) begin
        if (lmask != 'b0) begin
          dat_r[LINE*k +: LINE] = 'b0;
          for (l=0; l<CNT; l=l+1)
            dat_r[LINE*k +: LINE] = dat_r[LINE*k +: LINE] | (outs[LINE*l +: LINE] & {LINE{lmask[l]}});
        end
      end
    end

  endgenerate

endmodule


module risk_alu (
  input clk
);

endmodule

module alu (
  input clk,
  input [2:0] funct3,
  input [31:0] x,
  input [31:0] y,
  output reg [31:0] out
);
  always @(posedge clk) begin
    case (funct3) 
      3'b000: begin  // ADD
        out <= x + y;
      end

      3'b001: begin  // SUB
        out <= x - y;
      end

      3'b010: begin  // NOT
        out <= !x;
      end

      3'b011: begin  // SL
        out <= x << y;
      end

      3'b100: begin  // SR
        out <= x >> y;
      end

      3'b101: begin  // XOR
        out <= x ^ y;
      end

      3'b110: begin  // OR
        out <= x | y;
      end

      3'b111: begin  // AND
        out <= x & y;
      end
      default: begin
        out <= 0;
      end
    endcase
  end
endmodule

module cond (
  input clk, 
  input [2:0] funct3,
  input [31:0] x,
  input [31:0] y,
  output reg out
);
  always @(posedge clk) begin
    case (funct3) 
      3'b000: begin  // BEQ
        out <= x == y;
      end
      3'b001: begin  // BNE
        out <= x != y;
      end
      3'b100: begin  // BLT
        out <= $signed(x) < $signed(y);
      end
      3'b101: begin  // BGE
        out <= $signed(x) >= $signed(y);
      end
      3'b110: begin  // BLTU
        out <= x < y;
      end
      3'b111: begin  // BGEU
        out <= x >= y;
      end
    endcase
  end
endmodule

module ram (
  input clk,
  input [13:0] i_addr,
  output reg [31:0] i_data,
  input [13:0] d_addr,
  output reg [31:0] d_data,
  input [31:0] dw_data,
  input [1:0] dw_size);

  // 16 KB
  reg [31:0] mem [0:4095];
  wire [31:0] dt_data = mem[d_addr[13:2]];

  always @(posedge clk) begin
    // always aligned for instruction fetch
    i_data <= mem[i_addr[13:2]];
    // misaligned data, but it's filled with 0s
    // support some unaligned loads, but can't break word boundary
    d_data <=
      d_addr[1] ? (d_addr[0] ? (dt_data >> 24) : (dt_data >> 16))
                : (d_addr[0] ? (dt_data >> 8) : dt_data);
    // 2'b01 = 8-bit
    // 2'b10 = 16-bit
    // 2'b11 = 32-bit
    // again, can't break word boundary
    case (dw_size)
      2'b11: mem[d_addr[13:2]] <= dw_data;
      2'b10: mem[d_addr[13:2]] <= 
        d_addr[1] ? {dw_data[15:0], dt_data[15:0]} : 
                    {dt_data[31:16], dw_data[15:0]};
      2'b01: mem[d_addr[13:2]] <= 
        d_addr[1] ?
          (d_addr[0] ? {dw_data[7:0], dt_data[23:0]} : {dt_data[31:24], dw_data[7:0], dt_data[15:0]}) :
          (d_addr[0] ? {dt_data[31:16], dw_data[7:0], dt_data[7:0]} : {dt_data[31:8], dw_data[7:0]});
    endcase
  end
endmodule

// twitchcore is a low performance RISC-V processor
module twitchcore (
  input clk, resetn,
  output reg trap,
  output reg [31:0] pc
);

  //wire [13:0] i_addr = pc[13:0];
  reg [13:0] i_addr;
  wire [31:0] i_data;
  reg [13:0] d_addr;
  wire [31:0] d_data;
  reg [31:0] dw_data;
  reg [1:0] dw_size;
  ram r (
    .clk (clk),
    .i_data (i_data),
    .i_addr (i_addr),
    .d_data (d_data),
    .d_addr (d_addr),
    .dw_data (dw_data),
    .dw_size (dw_size)
  );

  reg [31:0] regs [0:31];
  reg [4:0] rd;

  reg [31:0] vs1;
  reg [31:0] vs2;
  reg [31:0] vpc;

  // Instruction decode and register fetch
  wire [6:0] opcode = i_data[6:0];
  wire [2:0] funct3 = i_data[14:12];
  wire [6:0] funct7 = i_data[31:25];
  wire [4:0] rs1 = i_data[19:15];
  wire [4:0] rs2 = i_data[24:20];
  wire [31:0] imm_i = {{20{i_data[31]}}, i_data[31:20]};
  wire [31:0] imm_s = {{20{i_data[31]}}, i_data[31:25], i_data[11:7]};
  wire [31:0] imm_b = {{19{i_data[31]}}, i_data[31], i_data[7], i_data[30:25], i_data[11:8], 1'b0};
  wire [31:0] imm_u = {i_data[31:12], 12'b0};
  wire [31:0] imm_j = {{11{i_data[31]}}, i_data[31], i_data[19:12], i_data[20], i_data[30:21], 1'b0};

  reg [31:0] alu_left;
  reg [31:0] alu_imm;
  reg [2:0] alu_func;

  wire [31:0] pend;
  reg [2:0] funct3_saved;
  wire cond_out;
  reg [1:0] update_pc;  // 2'b00: don't update, 2'b01: update always, 2'b10: update cond
  reg reg_writeback;

  wire pend_is_new_pc = update_pc[0] || (update_pc[1] && cond_out);
  reg do_load;
  reg do_store;

  reg [6:0] step;

  alu a (
    .clk (clk),
    .funct3 (alu_func),
    .x (alu_left),
    .y (alu_imm),
    .out (pend)
  );

  cond c (
    .clk (clk),
    .funct3 (funct3_saved),
    .x (vs1),
    .y (vs2),
    .out (cond_out)
  );



  integer i;
  always @(posedge clk) begin
    step <= step << 1;
    if (resetn) begin
      pc <= 32'h80000000;
      for (i=0; i<32; i=i+1) regs[i] <= 0;
      step <= 'b1;
      trap <= 1'b0;
    end

    // *** Instruction Fetch ***
    i_addr <= pc[13:0];
    // it sets i_data here from pc

    // *** Instruction decode and register fetch ***
    vs1 <= regs[rs1];
    vs2 <= regs[rs2];
    vpc <= pc;
    rd <= i_data[11:7];
    funct3_saved <= funct3;

    alu_func <= 3'b000;
    alu_left <= vs1;
    update_pc <= 2'b00;
    reg_writeback <= 1'b0;
    do_load <= 1'b0;
    do_store <= 1'b0;
    case (opcode)
      7'b0110111: begin // LUI
        alu_imm <= imm_u;
        alu_left <= 32'b0;
        reg_writeback <= 1'b1;
      end
      7'b0000011: begin // LOAD
        alu_imm <= imm_i;
        reg_writeback <= 1'b1;
        do_load <= 1'b1;
      end
      7'b0100011: begin // STORE
        alu_imm <= imm_s;
        do_store <= 1'b1;
      end

      7'b0010111: begin // AUIPC
        alu_imm <= imm_u;
        alu_left <= pc;
        reg_writeback <= 1'b1;
      end
      7'b1100011: begin // BRANCH
        alu_imm <= imm_b;
        alu_left <= pc;
        update_pc <= 2'b10;
      end
      7'b1101111: begin // JAL
        alu_imm <= imm_j;
        alu_left <= pc;
        update_pc <= 2'b01;
        reg_writeback <= 1'b1;
      end
      7'b1100111: begin // JALR
        alu_imm <= imm_i;
        update_pc <= 2'b01;
        reg_writeback <= 1'b1;
      end

      7'b0010011: begin // IMM
        alu_imm <= imm_i;
        alu_func <= funct3;
        reg_writeback <= 1'b1;
      end
      7'b0110011: begin // OP
        alu_imm <= regs[rs2];
        alu_func <= funct3;
        reg_writeback <= 1'b1;
      end

      7'b1110011: begin // SYSTEM
        trap <= regs[3] > 0;
      end
    endcase

    // *** Execute (happens above in arith and cond) ***
    // it sets pend and cond_out here

    // *** Memory access ***
    // this sets d_data based on pend
    if (step[5] == 1'b1) begin
      d_addr <= pend[13:0];
      if (do_store) begin
        dw_data <= vs2;
        dw_size <= (funct3_saved[1:0] + 1);
      end
    end
    
    // *** Register Writeback ***
    if (step[6] == 1'b1) begin
      pc <= pend_is_new_pc ? pend : (vpc + 4);
      if (reg_writeback && rd != 5'b00000) begin
        if (do_load) begin
          case (funct3_saved)
            3'b000: regs[rd] <= {{24{d_data[7]}}, d_data[7:0]};
            3'b001: regs[rd] <= {{16{d_data[15]}}, d_data[15:0]};
            3'b010: regs[rd] <= d_data;
            3'b100: regs[rd] <= {24'b0, d_data[7:0]};
            3'b101: regs[rd] <= {16'b0, d_data[15:0]};
          endcase
        end else begin
          regs[rd] <= (pend_is_new_pc ? (vpc + 4) : pend);
        end
      end
      step <= 'b1;
      dw_size <= 2'b00;
    end
  end

endmodule


