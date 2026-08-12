//=============================================================
// ahb_driver.sv
// Drives the AHB bus as the AHB MASTER.
//
// Responsible for:
//  - Expanding a transaction into individual beats
//  - Generating the correct address for every beat (INCR/WRAP math)
//  - Correctly pipelining address phase (beat N) with data phase (beat N-1)
//  - Respecting HREADYOUT (wait states)
//  - Capturing read data / HRESP
//  - Returning the bus to IDLE between transactions
//=============================================================

// NOTE: included inside ahb_pkg.sv (see that file's `include list).
// Do not compile this file directly with vlog.

class ahb_driver;

  virtual ahb_if.DRIVER vif;
  mailbox #(ahb_transaction) gen2drv_mbx;   // generator -> driver

  function new(virtual ahb_if.DRIVER vif, mailbox #(ahb_transaction) gen2drv_mbx);
    this.vif         = vif;
    this.gen2drv_mbx = gen2drv_mbx;
  endfunction

  //-------------------------------------------------------------------
  // Drive the bus to IDLE (used at reset and between transactions)
  //-------------------------------------------------------------------
  task automatic drive_idle();
    vif.drv_cb.HSEL    <= 1'b0;
    vif.drv_cb.HTRANS  <= HTRANS_IDLE;
    vif.drv_cb.HADDR   <= '0;
    vif.drv_cb.HWRITE  <= 1'b0;
    vif.drv_cb.HSIZE   <= '0;
    vif.drv_cb.HBURST  <= '0;
    vif.drv_cb.HPROT   <= '0;
    vif.drv_cb.HWDATA  <= '0;
  endtask

  //-------------------------------------------------------------------
  // Wait for reset deassertion
  //-------------------------------------------------------------------
  task automatic wait_for_reset();
    drive_idle();
    @(negedge vif.HRESETn);
    drive_idle();
    @(posedge vif.HRESETn);
    @(vif.drv_cb);
  endtask

  //-------------------------------------------------------------------
  // Compute the address for beat number 'beat_idx' (0-based) of a burst
  //-------------------------------------------------------------------
  function automatic logic [ADDR_WIDTH-1:0] compute_beat_address(
      ahb_transaction txn,
      int unsigned beat_idx,
      logic [ADDR_WIDTH-1:0] prev_addr
  );
    if (beat_idx == 0) begin
      return txn.addr;
    end else if (is_wrapping_burst(txn.hburst)) begin
      return get_wrap_address(txn.addr, prev_addr, txn.hsize, txn.hburst);
    end else begin
      return get_incr_address(prev_addr, txn.hsize);
    end
  endfunction

  //-------------------------------------------------------------------
  // Drive one full burst transaction (all beats), respecting the
  // AHB pipeline: address phase of beat N overlaps data phase of
  // beat N-1.
  //-------------------------------------------------------------------
  task automatic drive_transaction(ahb_transaction txn);
    int unsigned num_beats;
    logic [ADDR_WIDTH-1:0] beat_addr [16];  // up to 16 beats (WRAP16/INCR16)
    logic [1:0]            beat_trans[16];
    hresp_e                last_hresp;
    bit                    last_hready;

    num_beats = txn.num_beats();
    last_hresp  = HRESP_OKAY;
    last_hready = 1'b1;
    txn.read_data.delete();

    // Pre-compute every beat's address up front (mirrors how a real
    // AHB master would know its whole burst ahead of time)
    beat_addr[0]  = txn.addr;
    beat_trans[0] = HTRANS_NONSEQ;
    for (int i = 1; i < num_beats; i++) begin
      beat_addr[i]  = compute_beat_address(txn, i, beat_addr[i-1]);
      beat_trans[i] = HTRANS_SEQ;
    end

    // ---------------- Address phase of beat 0 ----------------
    vif.drv_cb.HSEL    <= 1'b1;
    vif.drv_cb.HADDR   <= beat_addr[0];
    vif.drv_cb.HTRANS  <= beat_trans[0];
    vif.drv_cb.HWRITE  <= txn.write;
    vif.drv_cb.HSIZE   <= txn.hsize;
    vif.drv_cb.HBURST  <= txn.hburst;
    vif.drv_cb.HPROT   <= txn.hprot;
    @(vif.drv_cb);

    // Wait until the slave accepts the address phase (HREADYOUT=1)
    while (vif.drv_cb.HREADYOUT !== 1'b1) @(vif.drv_cb);

    for (int beat = 1; beat <= num_beats; beat++) begin
      // ---------------- Data phase of beat (beat-1) ----------------
      // Present write data for the beat whose address phase just completed.
      if (txn.write) begin
        vif.drv_cb.HWDATA <= txn.write_data[beat-1];
      end

      // ---------------- Address phase of 'beat' (if it exists) ------
      if (beat < num_beats) begin
        vif.drv_cb.HADDR  <= beat_addr[beat];
        vif.drv_cb.HTRANS <= beat_trans[beat];
      end else begin
        // Last beat: no further address phase for this burst.
        // Drop HTRANS to IDLE so we do not imply another SEQ beat.
        vif.drv_cb.HTRANS <= HTRANS_IDLE;
      end

      @(vif.drv_cb);

      // Wait for the slave to complete this data phase (HREADYOUT=1),
      // holding control signals stable during any wait states.
      while (vif.drv_cb.HREADYOUT !== 1'b1) @(vif.drv_cb);

      // Capture the response / read data for beat (beat-1)
      last_hresp  = hresp_e'(vif.drv_cb.HRESP);
      last_hready = vif.drv_cb.HREADYOUT;
      if (!txn.write) begin
        txn.read_data.push_back(vif.drv_cb.HRDATA);
      end
    end

    txn.hresp  = last_hresp;
    txn.hready = last_hready;

    // Return bus to IDLE between transactions
    drive_idle();
    @(vif.drv_cb);
  endtask

  //-------------------------------------------------------------------
  // Main run loop: pull transactions from the generator and drive them
  //-------------------------------------------------------------------
  task automatic run();
    ahb_transaction txn;

    wait_for_reset();

    forever begin
      gen2drv_mbx.get(txn);
      drive_transaction(txn);
    end
  endtask

endclass : ahb_driver
