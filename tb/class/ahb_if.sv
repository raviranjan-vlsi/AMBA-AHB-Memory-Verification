//=============================================================
// ahb_if.sv
// AHB-Lite interface: carries all AHB signals between the
// testbench (acting as AHB master) and the DUT (AHB slave).
//
// NOTE: This interface is intentionally standalone (it does NOT
// import ahb_pkg). ahb_pkg's testbench classes need to reference
// "virtual ahb_if.DRIVER" / "virtual ahb_if.MONITOR" types, so
// ahb_if must be compiled BEFORE ahb_pkg. Keeping ahb_if free of
// any dependency on ahb_pkg avoids a circular compile-order
// dependency. Widths are passed in as interface parameters
// instead, and tb_top.sv binds them to ahb_pkg::ADDR_WIDTH /
// ahb_pkg::DATA_WIDTH explicitly so the two stay in sync.
//=============================================================
`timescale 1ns/1ps
interface ahb_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (input logic HCLK, input logic HRESETn);

  // Address / control phase signals
  logic [ADDR_WIDTH-1:0] HADDR;
  logic [1:0]            HTRANS;
  logic                  HWRITE;
  logic [2:0]            HSIZE;
  logic [2:0]            HBURST;
  logic [3:0]            HPROT;
  logic                  HSEL;

  // Data phase signals
  logic [DATA_WIDTH-1:0] HWDATA;
  logic [DATA_WIDTH-1:0] HRDATA;

  // Handshake / response
  logic                  HREADY;     // input to master  (from slave, feeds back)
  logic                  HREADYOUT;  // output of slave
  logic                  HRESP;

  //-----------------------------------------------------------
  // Driver clocking block (acts as AHB master)
  // Drives control/address/write-data, samples HRDATA/HREADY/HRESP
  //-----------------------------------------------------------
  clocking drv_cb @(posedge HCLK);
    default input #1step output #2;
    output HADDR;
    output HTRANS;
    output HWRITE;
    output HSIZE;
    output HBURST;
    output HPROT;
    output HSEL;
    output HWDATA;
    input  HRDATA;
    input  HREADYOUT;
    input  HRESP;
  endclocking

  //-----------------------------------------------------------
  // Monitor clocking block - purely passive sampling
  //-----------------------------------------------------------
  clocking mon_cb @(posedge HCLK);
    default input #1step;
    input HADDR;
    input HTRANS;
    input HWRITE;
    input HSIZE;
    input HBURST;
    input HPROT;
    input HSEL;
    input HWDATA;
    input HRDATA;
    input HREADYOUT;
    input HRESP;
  endclocking

  // HREADY seen by the whole system is simply the slave's HREADYOUT
  // (single-slave system, no address decoder/mux needed)
  assign HREADY = HREADYOUT;

  modport DRIVER (clocking drv_cb, input HCLK, input HRESETn);
  modport MONITOR (clocking mon_cb, input HCLK, input HRESETn);

  // Direct (non-clocking-block) modport for the DUT connection
  modport DUT (
    input  HCLK, HRESETn, HSEL, HADDR, HTRANS, HWRITE, HSIZE, HBURST, HPROT, HWDATA, HREADY,
    output HRDATA, HREADYOUT, HRESP
  );

endinterface : ahb_if
