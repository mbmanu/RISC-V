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