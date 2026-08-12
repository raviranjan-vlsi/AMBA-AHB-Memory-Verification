//=============================================================
// ahb_coverage.sv
// Functional coverage collector. Consumes beat-level transactions
// from the monitor and samples covergroups.
//=============================================================

// NOTE: included inside ahb_pkg.sv (see that file's `include list).
// Do not compile this file directly with vlog.

class ahb_coverage;

  mailbox #(ahb_mon_txn) mon2cov_mbx;

  // Local copies sampled into the covergroup
  logic [ADDR_WIDTH-1:0] cov_addr;
  hsize_e                cov_size;
  hburst_e               cov_burst;
  bit                    cov_write;
  hresp_e                cov_resp;

  //-------------------------------------------------------------------
  // Covergroup: samples one beat at a time
  //-------------------------------------------------------------------
  covergroup cg_ahb;
    option.per_instance = 1;

    burst_cp : coverpoint cov_burst {
      bins single = {HBURST_SINGLE};
      bins incr   = {HBURST_INCR};
      bins wrap4  = {HBURST_WRAP4};
      bins incr4  = {HBURST_INCR4};
      bins wrap8  = {HBURST_WRAP8};
      bins incr8  = {HBURST_INCR8};
      bins wrap16 = {HBURST_WRAP16};
      bins incr16 = {HBURST_INCR16};
    }

    size_cp : coverpoint cov_size {
      bins byte_size = {HSIZE_BYTE};
      bins half_size = {HSIZE_HALFWORD};
      bins word_size = {HSIZE_WORD};
    }

    rw_cp : coverpoint cov_write {
      bins read_txn  = {1'b0};
      bins write_txn = {1'b1};
    }

    response_cp : coverpoint cov_resp {
      bins okay_resp  = {HRESP_OKAY};
      bins error_resp = {HRESP_ERROR};
    }

    address_cp : coverpoint cov_addr {
      bins low_range  = {[32'h0000_0000 : 32'h0000_00FF]};
      bins mid_range  = {[32'h0000_0100 : 32'h0000_02FF]};
      bins high_range = {[32'h0000_0300 : 32'h0000_03FF]};
      bins other      = default;
    }

    burst_x_size : cross burst_cp, size_cp;
    burst_x_rw   : cross burst_cp, rw_cp;
    size_x_rw    : cross size_cp, rw_cp;

  endgroup : cg_ahb

  function new(mailbox #(ahb_mon_txn) mon2cov_mbx);
    this.mon2cov_mbx = mon2cov_mbx;
    cg_ahb = new();
  endfunction

  //-------------------------------------------------------------------
  // Main run loop: sample coverage for every beat reported by the monitor
  //-------------------------------------------------------------------
  task automatic run();
    ahb_mon_txn m;
    forever begin
      mon2cov_mbx.get(m);
      cov_addr  = m.addr;
      cov_size  = m.hsize;
      cov_burst = m.hburst;
      cov_write = m.write;
      cov_resp  = m.hresp;
      cg_ahb.sample();
    end
  endtask

  //-------------------------------------------------------------------
  // Print final coverage percentage
  //-------------------------------------------------------------------
  function void print_coverage();
    $display("====================================");
    $display("AHB FUNCTIONAL COVERAGE REPORT");
    $display("====================================");
    $display("Overall Coverage : %0.2f %%", cg_ahb.get_coverage());
    $display("====================================");
  endfunction

endclass : ahb_coverage
