//=============================================================
// ahb_monitor.sv
// Passive AHB bus monitor.
//
// Observes the interface (never drives it), reconstructs each
// individual AHB beat into a single-beat transaction, and
// forwards it to the scoreboard and coverage collector.
//=============================================================

// NOTE: included inside ahb_pkg.sv (see that file's `include list).
// Do not compile this file directly with vlog.

// ahb_mon_txn (a single observed beat: one address phase + its data
// phase result) is defined earlier in ahb_pkg.sv, since it is shared
// between this monitor (producer) and the scoreboard/coverage
// (consumers).

class ahb_monitor;

  virtual ahb_if.MONITOR vif;
  mailbox #(ahb_mon_txn) mon2sb_mbx;    // monitor -> scoreboard
  mailbox #(ahb_mon_txn) mon2cov_mbx;   // monitor -> coverage

  function new(
      virtual ahb_if.MONITOR vif,
      mailbox #(ahb_mon_txn) mon2sb_mbx,
      mailbox #(ahb_mon_txn) mon2cov_mbx
  );
    this.vif         = vif;
    this.mon2sb_mbx  = mon2sb_mbx;
    this.mon2cov_mbx = mon2cov_mbx;
  endfunction

  //-------------------------------------------------------------------
  // Main run loop.
  //
  // The monitor tracks address-phase info in a small pipeline (depth 1)
  // so it can pair each address phase with its corresponding data phase,
  // exactly mirroring the DUT's own address/data phase pipeline.
  //-------------------------------------------------------------------
  task automatic run();
    bit                    addr_valid_q;
    logic [ADDR_WIDTH-1:0] addr_q;
    bit                    write_q;
    hsize_e                hsize_q;
    hburst_e               hburst_q;

    addr_valid_q = 1'b0;

    forever begin
      @(vif.mon_cb);

      // Wait out reset
      if (!vif.HRESETn) begin
        addr_valid_q = 1'b0;
        continue;
      end

      // ---- Data phase completion for the previously captured address phase ----
      // A data phase is "complete" whenever HREADYOUT is high on this edge,
      // regardless of whether it took extra wait-state cycles to get there.
      if (addr_valid_q && vif.mon_cb.HREADYOUT) begin
        ahb_mon_txn m = new();
        m.addr   = addr_q;
        m.write  = write_q;
        m.hsize  = hsize_q;
        m.hburst = hburst_q;
        m.hresp  = hresp_e'(vif.mon_cb.HRESP);
        m.data   = write_q ? vif.mon_cb.HWDATA : vif.mon_cb.HRDATA;

        mon2sb_mbx.put(m);
        mon2cov_mbx.put(m);

        addr_valid_q = 1'b0;
      end

      // ---- Capture a new address phase, if one is being accepted now ----
      // A new address phase is accepted when HSEL is high, HREADYOUT is
      // high (so the bus is not stalled), and HTRANS indicates a real
      // transfer (NONSEQ or SEQ).
      if (vif.mon_cb.HSEL && vif.mon_cb.HREADYOUT &&
          ((vif.mon_cb.HTRANS == HTRANS_NONSEQ) || (vif.mon_cb.HTRANS == HTRANS_SEQ))) begin
        addr_q       = vif.mon_cb.HADDR;
        write_q      = vif.mon_cb.HWRITE;
        hsize_q      = hsize_e'(vif.mon_cb.HSIZE);
        hburst_q     = hburst_e'(vif.mon_cb.HBURST);
        addr_valid_q = 1'b1;
      end
    end
  endtask

endclass : ahb_monitor
