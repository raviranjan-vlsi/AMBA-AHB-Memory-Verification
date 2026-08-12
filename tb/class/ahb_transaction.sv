//=============================================================
// ahb_transaction.sv
// Transaction class representing a single AHB burst request
// (the driver will expand this into individual beats).
//=============================================================

// NOTE: included inside ahb_pkg.sv (see that file's `include list).
// Do not compile this file directly with vlog.

class ahb_transaction;

  // Randomized fields -------------------------------------------------
  rand logic [ADDR_WIDTH-1:0] addr;        // starting address of the burst
  rand bit                    write;       // 1 = write, 0 = read
  rand hsize_e                hsize;       // transfer size
  rand hburst_e                hburst;      // burst type
  rand int unsigned           incr_len;    // number of beats, only used for HBURST_INCR
  rand logic [3:0]            hprot;       // protection control (not deeply checked by DUT)

  // Data storage (filled in / consumed by driver, monitor, scoreboard)
  logic [DATA_WIDTH-1:0] write_data [$];   // one entry per beat (writes)
  logic [DATA_WIDTH-1:0] read_data  [$];   // one entry per beat (reads, filled by driver/monitor)

  // Response information captured after the transfer completes
  hresp_e hresp;
  bit     hready;

  //-------------------------------------------------------------------
  // Constraints
  //-------------------------------------------------------------------

  // Keep addresses within the memory's word range, leaving headroom so
  // that bursts (up to 16 beats x 4 bytes = 64 bytes) do not need to
  // consider wrap-around past the memory array itself. Memory is 256
  // words = 1024 bytes (0x000 - 0x3FF).
  constraint c_addr_range {
    addr inside {[32'h0000_0000 : 32'h0000_03C0]};
  }

  // Legal alignment: address must be aligned to the chosen transfer size
  constraint c_alignment {
    (hsize == HSIZE_HALFWORD) -> (addr[0]   == 1'b0);
    (hsize == HSIZE_WORD)     -> (addr[1:0] == 2'b00);
  }

  // Valid transfer size (only byte/halfword/word are supported by the DUT)
  constraint c_valid_size {
    hsize inside {HSIZE_BYTE, HSIZE_HALFWORD, HSIZE_WORD};
  }

  // Valid burst selection: all 8 legal AHB burst types
  constraint c_valid_burst {
    hburst inside {
      HBURST_SINGLE, HBURST_INCR,  HBURST_WRAP4,  HBURST_INCR4,
      HBURST_WRAP8,  HBURST_INCR8, HBURST_WRAP16, HBURST_INCR16
    };
  }

  // For undefined-length INCR bursts, keep the length small and reasonable
  constraint c_incr_len {
    incr_len inside {[1:8]};
  }

  // Read/write is randomized with a roughly even split
  constraint c_rw_dist {
    write dist {1'b0 := 50, 1'b1 := 50};
  }

  //-------------------------------------------------------------------
  // Constructor
  //-------------------------------------------------------------------
  function new();
    hresp  = HRESP_OKAY;
    hready = 1'b1;
  endfunction

  //-------------------------------------------------------------------
  // Returns the number of beats this transaction represents
  //-------------------------------------------------------------------
  function int unsigned num_beats();
    if (hburst == HBURST_INCR) return incr_len;
    else                       return get_burst_length(hburst);
  endfunction

  //-------------------------------------------------------------------
  // copy() - deep copy of randomized + data fields
  //-------------------------------------------------------------------
  function ahb_transaction copy();
    ahb_transaction t = new();
    t.addr     = this.addr;
    t.write    = this.write;
    t.hsize    = this.hsize;
    t.hburst   = this.hburst;
    t.incr_len = this.incr_len;
    t.hprot    = this.hprot;
    t.write_data = this.write_data;
    t.read_data  = this.read_data;
    t.hresp    = this.hresp;
    t.hready   = this.hready;
    return t;
  endfunction

  //-------------------------------------------------------------------
  // compare() - compares two transactions field by field
  // (address/size/burst/write flag and data contents)
  //-------------------------------------------------------------------
  function bit compare(ahb_transaction t);
    if (t == null) return 0;
    if (this.addr   !== t.addr)   return 0;
    if (this.write  !== t.write)  return 0;
    if (this.hsize  !== t.hsize)  return 0;
    if (this.hburst !== t.hburst) return 0;
    if (this.write_data.size() != t.write_data.size()) return 0;
    foreach (this.write_data[i])
      if (this.write_data[i] !== t.write_data[i]) return 0;
    if (this.read_data.size() != t.read_data.size()) return 0;
    foreach (this.read_data[i])
      if (this.read_data[i] !== t.read_data[i]) return 0;
    return 1;
  endfunction

  //-------------------------------------------------------------------
  // display() - print a human readable summary of the transaction
  //-------------------------------------------------------------------
  function void display(string tag = "TXN");
    $display("[%0s] addr=0x%0h write=%0b size=%s burst=%s beats=%0d hresp=%s",
              tag, addr, write, hsize.name(), hburst.name(), num_beats(), hresp.name());
  endfunction

endclass : ahb_transaction
