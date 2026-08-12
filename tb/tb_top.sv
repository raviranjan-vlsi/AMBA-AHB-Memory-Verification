//=============================================================
// tb_top.sv
// Top-level testbench: generates clock/reset, instantiates the
// AHB interface, the DUT, binds assertions, and starts the test.
//=============================================================
`timescale 1ns/1ps

import ahb_pkg::*;

module tb_top;

  // Set to a value > 0 to exercise the DUT's wait-state support.
  parameter int WAIT_STATES = 0;

  //-----------------------------------------------------------
  // Clock generation: 10 ns period
  //-----------------------------------------------------------
  logic HCLK;
  initial HCLK = 1'b0;
  always #5 HCLK = ~HCLK;

  //-----------------------------------------------------------
  // Reset generation: active-low, held low for first few cycles
  //-----------------------------------------------------------
  logic HRESETn;
  initial begin
    HRESETn = 1'b0;
    repeat (5) @(posedge HCLK);
    HRESETn = 1'b1;
  end

  //-----------------------------------------------------------
  // AHB interface instance
  // Widths are bound explicitly to ahb_pkg's parameters so the
  // interface and the rest of the testbench/DUT always agree,
  // even though ahb_if.sv itself does not import ahb_pkg.
  //-----------------------------------------------------------
  ahb_if #(
      .ADDR_WIDTH (ahb_pkg::ADDR_WIDTH),
      .DATA_WIDTH (ahb_pkg::DATA_WIDTH)
  ) bus (.HCLK(HCLK), .HRESETn(HRESETn));

  //-----------------------------------------------------------
  // DUT instance
  //-----------------------------------------------------------
  ahb_memory #(
      .ADDR_WIDTH  (ADDR_WIDTH),
      .DATA_WIDTH  (DATA_WIDTH),
      .MEM_DEPTH   (MEM_DEPTH),
      .WAIT_STATES (WAIT_STATES)
  ) dut (
      .HCLK      (HCLK),
      .HRESETn   (HRESETn),
      .HSEL      (bus.HSEL),
      .HADDR     (bus.HADDR),
      .HTRANS    (bus.HTRANS),
      .HWRITE    (bus.HWRITE),
      .HSIZE     (bus.HSIZE),
      .HBURST    (bus.HBURST),
      .HPROT     (bus.HPROT),
      .HWDATA    (bus.HWDATA),
      .HREADY    (bus.HREADY),
      .HRDATA    (bus.HRDATA),
      .HREADYOUT (bus.HREADYOUT),
      .HRESP     (bus.HRESP)
  );

  //-----------------------------------------------------------
  // Protocol assertions (plain instance, not bound into the interface)
  //-----------------------------------------------------------
  ahb_assertions u_ahb_assertions (
      .HCLK      (HCLK),
      .HRESETn   (HRESETn),
      .HSEL      (bus.HSEL),
      .HADDR     (bus.HADDR),
      .HTRANS    (bus.HTRANS),
      .HWRITE    (bus.HWRITE),
      .HSIZE     (bus.HSIZE),
      .HBURST    (bus.HBURST),
      .HREADY    (bus.HREADY),
      .HREADYOUT (bus.HREADYOUT),
      .HRESP     (bus.HRESP)
  );

  //-----------------------------------------------------------
  // Test instance
  // Passes the DRIVER and MONITOR modport views of the same
  // physical interface instance into the test/environment.
  //-----------------------------------------------------------
  ahb_test test (
      .HCLK    (HCLK),
      .HRESETn (HRESETn),
      .bus_drv (bus.DRIVER),
      .bus_mon (bus.MONITOR)
  );

  //-----------------------------------------------------------
  // Waveform dumping (optional, useful for debug in Questa)
  //-----------------------------------------------------------
  initial begin
    $dumpfile("ahb_tb.vcd");
    $dumpvars(0, tb_top);
  end

endmodule : tb_top
