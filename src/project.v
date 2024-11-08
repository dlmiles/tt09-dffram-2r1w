/*
 * SPDX-FileCopyrightText: Copyright (c) 2024 Darryl Miles
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_dlmiles_dffram64x4_2r1w (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);


  localparam AHIWIDTH = 2;  // used to fill out tile area
  localparam AWIDTH = 4;  // external address width
  localparam DWIDTH = 4;  // external data width

  localparam WORDWIDTH = DWIDTH;
  localparam ADDRWIDTH = AHIWIDTH + AWIDTH;
  localparam ADDRCOUNT = 2 ** ADDRWIDTH;

  // alias external signals

  wire [AWIDTH-1:0] addr_a;
  wire [AWIDTH-1:0] addr_b;
  wire [DWIDTH-1:0] wdata_a;
  wire [DWIDTH-1:0] rdata_a;
  wire [DWIDTH-1:0] rdata_b;
  wire              w_en;


  // Configuration mode

  reg  [AHIWIDTH-1:0] addrhi;
  reg  read_buffer_a;
  reg  read_buffer_b;
  reg  write_through;

  wire [AHIWIDTH-1:0] i_addrhi; // cocotb workaround
  wire                i_read_buffer_a;
  wire                i_read_buffer_b;
  wire                i_write_through;
  assign i_addrhi        = uio_in[AHIWIDTH-1:0];
  assign i_read_buffer_a = uio_in[4];
  assign i_read_buffer_b = uio_in[5];
  assign i_write_through = uio_in[6];

  always_latch begin
    if (!rst_n) begin
      //addrhi[AHIWIDTH-1:0] = uio_in[3:0]; // cocotb workaround
      //read_buffer_a        = uio_in[4];
      //read_buffer_b        = uio_in[5];
      //write_through        = uio_in[6];
      addrhi[AHIWIDTH-1:0] = i_addrhi[AHIWIDTH-1:0];
      read_buffer_a        = i_read_buffer_a;
      read_buffer_b        = i_read_buffer_b;
      write_through        = i_write_through;
      // not using uio_in[7] so it does not trigger W_EN during RST_N rise
    end
  end


  // The storage

  reg mem[ADDRCOUNT-1:0][WORDWIDTH-1:0];


  // Port A

  reg  [WORDWIDTH-1:0] rdata_buff_a;  // Read Port A buffer register
  wire [WORDWIDTH-1:0] rdata_curr_a;
  wire [ADDRWIDTH-1:0] raddr_curr_a;
  assign raddr_curr_a = {addrhi, addr_a};  // Port A current address

  // ITEM01 cocotb doesn't support this
  //assign rdata_curr_a = mem[raddr_curr_a][WORDWIDTH-1:0];
  generate // ITEM01 generate workaround below
    genvar rab; // read_a bit
    for(rab = 0; rab < WORDWIDTH; rab = rab + 1) begin
      assign rdata_curr_a[rab] = mem[raddr_curr_a][rab]; // assign 1-bit a time
    end
  endgenerate

  always @(posedge clk) begin
    //rdata_curr_a <= mem[raddr_curr_a][WORDWIDTH-1:0];
    rdata_buff_a <= rdata_curr_a;
    if (w_en) begin
      // ITEM02 cocotb doesn't support this, see generate workaround below
      //mem[raddr_curr_a][WORDWIDTH-1:0] <= wdata_a[WORDWIDTH-1:0];
    end
  end

  generate // ITEM02 generate workaround below
    genvar wab; // write_a bit
    for(wab = 0; wab < WORDWIDTH; wab = wab + 1) begin
      always @(posedge clk) begin
        if (w_en) begin
          mem[raddr_curr_a][wab] <= wdata_a[wab];
        end
      end
    end
  endgenerate

  // MUX bypass (for write-through), or buffered or unbuffered read output.
  assign rdata_a = (write_through & w_en) ? wdata_a :
                   ((      read_buffer_a) ? rdata_buff_a : rdata_curr_a);


  // Port B

  reg  [WORDWIDTH-1:0] rdata_buff_b;  // Read Port B buffer register
  wire [WORDWIDTH-1:0] rdata_curr_b;
  wire [ADDRWIDTH-1:0] raddr_curr_b;
  assign raddr_curr_b = {addrhi, addr_b};  // Port B current address

  // ITEM03 cocotb doesn't support this
  //assign rdata_curr_b = mem[raddr_curr_b][WORDWIDTH-1:0];
  generate // ITEM03 generate workaround below
    genvar rbb; // read_b bit
    for(rbb = 0; rbb < WORDWIDTH; rbb = rbb + 1) begin
      assign rdata_curr_b[rbb] = mem[raddr_curr_b][rbb]; // assign 1-bit a time
    end
  endgenerate

  always @(posedge clk) begin
    rdata_buff_b <= rdata_curr_b;
  end

  // buffered or unbuffered read output.
  assign rdata_b = (read_buffer_b) ? rdata_buff_b : rdata_curr_b;


  // Module ports assignments

  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out [3:0] = rdata_a;
  assign uo_out [7:4] = rdata_b;
  assign uio_out[7:0] = 8'h0;  // tie-lo
  assign uio_oe [7:0] = 8'h0;  // all inputs

  assign wdata_a[3:0] = ui_in[3:0];
  assign addr_a [3:0] = ui_in[7:4];
  assign addr_b [3:0] = uio_in[3:0];
  assign w_en         = uio_in[7];

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, 1'b0};

endmodule
