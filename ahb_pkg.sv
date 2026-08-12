//=============================================================
// ahb_pkg.sv
// Common AHB-Lite definitions used across the testbench.
//=============================================================

`timescale 1ns/1ps
package ahb_pkg;

  //-----------------------------------------------------------
  // Address / Data widths and memory size (must match DUT)
  //-----------------------------------------------------------
  parameter int ADDR_WIDTH = 32;
  parameter int DATA_WIDTH = 32;
  parameter int MEM_DEPTH  = 256;   // number of 32-bit words

  //-----------------------------------------------------------
  // HTRANS values
  //-----------------------------------------------------------
  typedef enum logic [1:0] {
    HTRANS_IDLE   = 2'b00,
    HTRANS_BUSY   = 2'b01,
    HTRANS_NONSEQ = 2'b10,
    HTRANS_SEQ    = 2'b11
  } htrans_e;

  //-----------------------------------------------------------
  // HBURST values
  //-----------------------------------------------------------
  typedef enum logic [2:0] {
    HBURST_SINGLE = 3'b000,
    HBURST_INCR   = 3'b001,
    HBURST_WRAP4  = 3'b010,
    HBURST_INCR4  = 3'b011,
    HBURST_WRAP8  = 3'b100,
    HBURST_INCR8  = 3'b101,
    HBURST_WRAP16 = 3'b110,
    HBURST_INCR16 = 3'b111
  } hburst_e;

  //-----------------------------------------------------------
  // HSIZE values
  //-----------------------------------------------------------
  typedef enum logic [2:0] {
    HSIZE_BYTE     = 3'b000,
    HSIZE_HALFWORD = 3'b001,
    HSIZE_WORD     = 3'b010
  } hsize_e;

  //-----------------------------------------------------------
  // HRESP values
  //-----------------------------------------------------------
  typedef enum logic {
    HRESP_OKAY  = 1'b0,
    HRESP_ERROR = 1'b1
  } hresp_e;

  //-----------------------------------------------------------
  // Helper functions - shared address/size math used by the
  // driver (and reusable by the monitor / scoreboard if needed)
  //-----------------------------------------------------------

  // Number of bytes transferred for a given HSIZE
  function automatic int bytes_per_transfer(hsize_e size);
    case (size)
      HSIZE_BYTE:     return 1;
      HSIZE_HALFWORD: return 2;
      HSIZE_WORD:     return 4;
      default:        return 4;
    endcase
  endfunction

  // Number of beats in a burst (1 for SINGLE and undefined-length INCR)
  function automatic int get_burst_length(hburst_e burst);
    case (burst)
      HBURST_SINGLE: return 1;
      HBURST_INCR:   return 1;  // length chosen by generator/driver for INCR
      HBURST_WRAP4:  return 4;
      HBURST_INCR4:  return 4;
      HBURST_WRAP8:  return 8;
      HBURST_INCR8:  return 8;
      HBURST_WRAP16: return 16;
      HBURST_INCR16: return 16;
      default:       return 1;
    endcase
  endfunction

  // Returns 1 if the burst type is a wrapping burst
  function automatic bit is_wrapping_burst(hburst_e burst);
    return (burst == HBURST_WRAP4) || (burst == HBURST_WRAP8) || (burst == HBURST_WRAP16);
  endfunction

  // Compute the next address for an incrementing burst
  function automatic logic [ADDR_WIDTH-1:0] get_incr_address(
      logic [ADDR_WIDTH-1:0] current_addr,
      hsize_e                size
  );
    return current_addr + bytes_per_transfer(size);
  endfunction

  //-----------------------------------------------------------
  // Shared beat-level observation type.
  // Represents a single AHB beat as reconstructed by the monitor:
  // one address phase paired with its corresponding data phase.
  // Used by the monitor (producer) and the scoreboard/coverage
  // (consumers), so it lives in the package rather than inside
  // ahb_monitor.sv to avoid any compilation-order dependency.
  //-----------------------------------------------------------
  class ahb_mon_txn;
    logic [ADDR_WIDTH-1:0] addr;
    bit                    write;
    hsize_e                hsize;
    hburst_e               hburst;
    logic [1:0]            htrans;
    logic [DATA_WIDTH-1:0] data;      // HWDATA for writes, HRDATA for reads
    hresp_e                hresp;

    function void display(string tag = "MON");
      $display("[%0s] addr=0x%0h write=%0b size=%s burst=%s data=0x%0h hresp=%s",
                tag, addr, write, hsize.name(), hburst.name(), data, hresp.name());
    endfunction
  endclass : ahb_mon_txn

  // Compute the next address for a wrapping burst.
  // wrap_boundary = burst_length * transfer_bytes
  // base_address  = starting_address aligned down to wrap_boundary
  // next_address  = current_address + transfer_bytes
  // if next_address reaches (base_address + wrap_boundary) -> wrap back to base_address
  function automatic logic [ADDR_WIDTH-1:0] get_wrap_address(
      logic [ADDR_WIDTH-1:0] start_addr,
      logic [ADDR_WIDTH-1:0] current_addr,
      hsize_e                size,
      hburst_e                burst
  );
    int unsigned transfer_bytes;
    int unsigned burst_len;
    int unsigned wrap_boundary;
    logic [ADDR_WIDTH-1:0] base_addr;
    logic [ADDR_WIDTH-1:0] next_addr;
    logic [ADDR_WIDTH-1:0] mask;

    transfer_bytes = bytes_per_transfer(size);
    burst_len       = get_burst_length(burst);
    wrap_boundary   = burst_len * transfer_bytes;

    // Align start_addr down to the wrap boundary (boundary is power of 2)
    mask      = ~(wrap_boundary - 1);
    base_addr = start_addr & mask;

    next_addr = current_addr + transfer_bytes;

    if (next_addr >= (base_addr + wrap_boundary)) begin
      next_addr = base_addr;
    end

    return next_addr;
  endfunction

  //-----------------------------------------------------------
  // Testbench classes.
  //
  // These live in their own files for readability (as separate,
  // reviewable units) but are pulled in here with `include so
  // they all share this package's scope. This is required because
  // each file compiled as its own `vlog` invocation gets its own
  // compilation-unit scope in most simulators (including Questa);
  // a bare class in file A is therefore invisible to file B unless
  // both live inside the same package. Do NOT compile these files
  // directly with vlog - they are not standalone compilation units.
  //
  // Include order follows the dependency chain: ahb_transaction
  // has no class dependencies; ahb_generator and ahb_driver depend
  // on ahb_transaction; ahb_monitor depends on ahb_mon_txn (defined
  // above); ahb_scoreboard/ahb_coverage depend on ahb_mon_txn;
  // ahb_env depends on all of the above. ahb_driver and ahb_monitor
  // also reference "virtual ahb_if.DRIVER" / "virtual ahb_if.MONITOR",
  // so ahb_if.sv must be compiled before this package.
  //-----------------------------------------------------------
  `include "ahb_transaction.sv"
  `include "ahb_generator.sv"
  `include "ahb_driver.sv"
  `include "ahb_monitor.sv"
  `include "ahb_scoreboard.sv"
  `include "ahb_coverage.sv"
  `include "ahb_env.sv"

endpackage : ahb_pkg
