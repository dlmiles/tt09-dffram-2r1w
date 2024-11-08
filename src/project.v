/*
 * SPDX-FileCopyrightText: Copyright (c) 2024 Darryl Miles
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

//`define STORAGE_POWER_OF_TWO
`define STORAGE_MINUS_TWO
`define STORAGE_MINUS_FOUR
`define STORAGE_MINUS_SIX
`define STORAGE_MINUS_EIGHT
//`define STORAGE_MINUS_TEN
//`define STORAGE_MINUS_TWELEVE
//`define STORAGE_MINUS_FOURTEEN
//`define STORAGE_MINUS_SIXTEEN

module tt_um_dlmiles_dffram32x8_2r1w (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);


  localparam AHIWIDTH = 1;  // used to fill out tile area
  localparam AWIDTH = 4;  // external address width
  localparam DWIDTH = 4;  // external data width

  localparam WORDWIDTH     = DWIDTH + DWIDTH;
  localparam HALFWORDWIDTH = DWIDTH;
  localparam ADDRWIDTH     = AHIWIDTH + AWIDTH;
  localparam ADDRCOUNT     = 2 ** ADDRWIDTH;

  localparam ADDRESS_ZERO  = {ADDRWIDTH{1'b0}};

  // alias external signals

  wire [AWIDTH-1:0] addr_a;
  wire [AWIDTH-1:0] addr_b;
  wire [DWIDTH-1:0] wdata_a;
  wire [DWIDTH-1:0] rdata_a;
  wire [DWIDTH-1:0] rdata_b;
  wire              lohi_a;
  wire              lohi_b;
  wire              w_en;

  wire [WORDWIDTH-1:0] wword_a;
  wire [WORDWIDTH-1:0] rword_a;
  wire [WORDWIDTH-1:0] rword_b;


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

  // This purpose of this is to allow removal on byte granulatity of storage area to meet tile 1x1 limits
  reg  [ADDRWIDTH-1:0] raddr_xlat_a;
`ifdef STORAGE_POWER_OF_TWO
  assign raddr_xlat_a = raddr_curr_a; // No translation
`else
  always @(*) begin
    // each byte here is removed from storage and remapped to zero location
    case(raddr_curr_a)
`ifdef STORAGE_MINUS_SIXTEEN
      5'b10000:
        raddr_xlat_a = ADDRESS_ZERO;
      5'b10001:
        raddr_xlat_a = ADDRESS_ZERO;
`endif
`ifdef STORAGE_MINUS_FOURTEEN
      5'b10010:
        raddr_xlat_a = ADDRESS_ZERO;
      5'b10011:
        raddr_xlat_a = ADDRESS_ZERO;
`endif

`ifdef STORAGE_MINUS_TWELEVE
      5'b10100:
        raddr_xlat_a = ADDRESS_ZERO;
      5'b10101:
        raddr_xlat_a = ADDRESS_ZERO;
`endif
`ifdef STORAGE_MINUS_TEN
      5'b10110:
        raddr_xlat_a = ADDRESS_ZERO;
      5'b10111:
        raddr_xlat_a = ADDRESS_ZERO;
`endif

`ifdef STORAGE_MINUS_EIGHT
      5'b11000:
        raddr_xlat_a = ADDRESS_ZERO;
      5'b11001:
        raddr_xlat_a = ADDRESS_ZERO;
`ifdef STORAGE_MINUS_SIX
`endif
      5'b11010:
        raddr_xlat_a = ADDRESS_ZERO;
      5'b11011:
        raddr_xlat_a = ADDRESS_ZERO;
`endif

`ifdef STORAGE_MINUS_FOUR
      5'b11100:
        raddr_xlat_a = ADDRESS_ZERO;
      5'b11101:
        raddr_xlat_a = ADDRESS_ZERO;
`endif
`ifdef STORAGE_MINUS_TWO
      5'b11110:
        raddr_xlat_a = ADDRESS_ZERO;
      5'b11111:
        raddr_xlat_a = ADDRESS_ZERO;
`endif
      default:
        raddr_xlat_a = raddr_curr_a;
    endcase
  end
`endif

  // ITEM01 cocotb doesn't support this
  //assign rdata_curr_a = mem[raddr_xlat_a][WORDWIDTH-1:0];
  generate // ITEM01 generate workaround below
    genvar rab; // read_a bit
    for(rab = 0; rab < WORDWIDTH; rab = rab + 1) begin
      assign rdata_curr_a[rab] = mem[raddr_xlat_a][rab]; // assign 1-bit a time
    end
  endgenerate

  always @(posedge clk) begin
    //rdata_curr_a <= mem[raddr_xlat_a][WORDWIDTH-1:0];
    rdata_buff_a <= rdata_curr_a;
    if (w_en) begin
      // ITEM02 cocotb doesn't support this, see generate workaround below
      //mem[raddr_xlat_a][WORDWIDTH-1:0] <= wword_a[WORDWIDTH-1:0];
    end
  end

  wire w_en_lo;
  assign w_en_lo = w_en &  lohi_a;
  wire w_en_hi;
  assign w_en_hi = w_en & !lohi_a;
  assign wword_a = {wdata_a, wdata_a};  // repeated so connection is correct in generate block
  generate // ITEM02 generate workaround below
    genvar wab; // write_a bit
    for(wab = 0; wab < WORDWIDTH; wab = wab + 1) begin
      always @(posedge clk) begin
        if (wab < HALFWORDWIDTH && w_en_lo) begin
          mem[raddr_xlat_a][wab] <= wword_a[wab];
        end
        if (wab >= HALFWORDWIDTH && w_en_hi) begin
          mem[raddr_xlat_a][wab] <= wword_a[wab];
        end
      end
    end
  endgenerate

  // MUX bypass (for write-through), or buffered or unbuffered read output.
  assign rword_a = (write_through & w_en) ? wword_a :
                   ((      read_buffer_a) ? rdata_buff_a : rdata_curr_a);
  assign rdata_a = (lohi_a) ? rword_a[7:4] : rword_a[3:0];


  // Port B

  reg  [WORDWIDTH-1:0] rdata_buff_b;  // Read Port B buffer register
  wire [WORDWIDTH-1:0] rdata_curr_b;
  wire [ADDRWIDTH-1:0] raddr_curr_b;
  assign raddr_curr_b = {addrhi, addr_b};  // Port B current address

  // This purpose of this is to allow removal on byte granulatity of storage area to meet tile 1x1 limits
  reg  [ADDRWIDTH-1:0] raddr_xlat_b;
`ifdef STORAGE_POWER_OF_TWO
  assign raddr_xlat_b = raddr_curr_b; // No translation
`else
  always @(*) begin
    // each byte here is removed from storage and remapped to zero location
    case(raddr_curr_b)
`ifdef STORAGE_MINUS_SIXTEEN
      5'b10000:
        raddr_xlat_b = ADDRESS_ZERO;
      5'b10001:
        raddr_xlat_b = ADDRESS_ZERO;
`endif
`ifdef STORAGE_MINUS_FOURTEEN
      5'b10010:
        raddr_xlat_b = ADDRESS_ZERO;
      5'b10011:
        raddr_xlat_b = ADDRESS_ZERO;
`endif

`ifdef STORAGE_MINUS_TWELEVE
      5'b10100:
        raddr_xlat_b = ADDRESS_ZERO;
      5'b10101:
        raddr_xlat_b = ADDRESS_ZERO;
`endif
`ifdef STORAGE_MINUS_TEN
      5'b10110:
        raddr_xlat_b = ADDRESS_ZERO;
      5'b10111:
        raddr_xlat_b = ADDRESS_ZERO;
`endif

`ifdef STORAGE_MINUS_EIGHT
      5'b11000:
        raddr_xlat_b = ADDRESS_ZERO;
      5'b11001:
        raddr_xlat_b = ADDRESS_ZERO;
`ifdef STORAGE_MINUS_SIX
`endif
      5'b11010:
        raddr_xlat_b = ADDRESS_ZERO;
      5'b11011:
        raddr_xlat_b = ADDRESS_ZERO;
`endif

`ifdef STORAGE_MINUS_FOUR
      5'b11100:
        raddr_xlat_b = ADDRESS_ZERO;
      5'b11101:
        raddr_xlat_b = ADDRESS_ZERO;
`endif
`ifdef STORAGE_MINUS_TWO
      5'b11110:
        raddr_xlat_b = ADDRESS_ZERO;
      5'b11111:
        raddr_xlat_b = ADDRESS_ZERO;
`endif
      default:
        raddr_xlat_b = raddr_curr_b;
    endcase
  end
`endif

  // ITEM03 cocotb doesn't support this
  //assign rdata_curr_b = mem[raddr_xlat_b][WORDWIDTH-1:0];
  generate // ITEM03 generate workaround below
    genvar rbb; // read_b bit
    for(rbb = 0; rbb < WORDWIDTH; rbb = rbb + 1) begin
      assign rdata_curr_b[rbb] = mem[raddr_xlat_b][rbb]; // assign 1-bit a time
    end
  endgenerate

  always @(posedge clk) begin
    rdata_buff_b <= rdata_curr_b;
  end

  // buffered or unbuffered read output.
  assign rword_b = (read_buffer_b) ? rdata_buff_b : rdata_curr_b;
  assign rdata_b = (lohi_b) ? rword_b[7:4] : rword_b[3:0];


  // Module ports assignments

  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out [3:0] = rdata_a;
  assign uo_out [7:4] = rdata_b;
  assign uio_out[7:0] = 8'h0;  // tie-lo
  assign uio_oe [7:0] = 8'h0;  // all inputs

  assign wdata_a[3:0] = ui_in[3:0];
  assign addr_a [3:0] = ui_in[7:4];
  assign addr_b [3:0] = uio_in[3:0];
  assign lohi_a       = uio_in[4];
  assign lohi_b       = uio_in[5];
  assign w_en         = uio_in[7];

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, 1'b0};

endmodule
