//=============================================================
// ahb_generator.sv
// Generates AHB transactions (directed + constrained-random)
// and sends them to the driver through a mailbox.
//=============================================================

// NOTE: included inside ahb_pkg.sv (see that file's `include list).
// Do not compile this file directly with vlog.

class ahb_generator;

  mailbox #(ahb_transaction) gen2drv_mbx;   // generator -> driver
  int unsigned num_random_txns = 100;       // configurable transaction count

  function new(mailbox #(ahb_transaction) gen2drv_mbx);
    this.gen2drv_mbx = gen2drv_mbx;
  endfunction

  //-------------------------------------------------------------------
  // Send a fully directed transaction (all fields specified by caller)
  //-------------------------------------------------------------------
  task send_directed(
      logic [ADDR_WIDTH-1:0] addr,
      bit                    write,
      hsize_e                hsize,
      hburst_e               hburst,
      int unsigned           incr_len = 1
  );
    ahb_transaction txn = new();
    txn.addr     = addr;
    txn.write    = write;
    txn.hsize    = hsize;
    txn.hburst   = hburst;
    txn.incr_len = incr_len;
    txn.hprot    = 4'b0011; // typical default: privileged, non-bufferable data access

    // Fill write data for each beat with a recognizable pattern
    if (write) begin
      for (int i = 0; i < txn.num_beats(); i++)
        txn.write_data.push_back(($urandom & 32'hFFFF_FFF0) | i[3:0]);
    end

    gen2drv_mbx.put(txn);
  endtask

  //-------------------------------------------------------------------
  // Send one fully constrained-random transaction
  //-------------------------------------------------------------------
  task send_random();
    ahb_transaction txn = new();
    if (!txn.randomize()) begin
      $display("[GENERATOR] ERROR: randomize() failed, using defaults");
    end

    if (txn.write) begin
      for (int i = 0; i < txn.num_beats(); i++)
        txn.write_data.push_back($urandom);
    end

    gen2drv_mbx.put(txn);
  endtask

  //-------------------------------------------------------------------
  // Send a random transaction forced to a specific burst type
  // (used to guarantee coverage of all 8 burst types)
  //-------------------------------------------------------------------
  task send_random_burst(hburst_e burst_type);
    ahb_transaction txn = new();
    if (!txn.randomize() with { hburst == burst_type; }) begin
      $display("[GENERATOR] ERROR: randomize() with burst constraint failed");
    end

    if (txn.write) begin
      for (int i = 0; i < txn.num_beats(); i++)
        txn.write_data.push_back($urandom);
    end

    gen2drv_mbx.put(txn);
  endtask

  //-------------------------------------------------------------------
  // Run: generate directed coverage of all 8 burst types, then
  // a configurable number of fully random transactions.
  //-------------------------------------------------------------------
  task run();
    hburst_e all_bursts[8] = '{
      HBURST_SINGLE, HBURST_INCR,  HBURST_WRAP4,  HBURST_INCR4,
      HBURST_WRAP8,  HBURST_INCR8, HBURST_WRAP16, HBURST_INCR16
    };

    $display("[GENERATOR] Starting directed burst-type sweep (write then read for each)");
    foreach (all_bursts[i]) begin
      send_random_burst(all_bursts[i]);
    end

    $display("[GENERATOR] Starting %0d constrained-random transactions", num_random_txns);
    repeat (num_random_txns) begin
      send_random();
    end

    $display("[GENERATOR] Generation complete");
  endtask

endclass : ahb_generator
