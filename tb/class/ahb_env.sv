//=============================================================
// ahb_env.sv
// Environment: instantiates and connects generator, driver,
// monitor, scoreboard, and coverage via mailboxes.
//=============================================================

// NOTE: included inside ahb_pkg.sv (see that file's `include list).
// Do not compile this file directly with vlog.

class ahb_env;

  virtual ahb_if.DRIVER  drv_vif;
  virtual ahb_if.MONITOR mon_vif;

  ahb_generator  gen;
  ahb_driver     drv;
  ahb_monitor    mon;
  ahb_scoreboard sb;
  ahb_coverage   cov;

  // Mailboxes connecting the components
  mailbox #(ahb_transaction) gen2drv_mbx;
  mailbox #(ahb_mon_txn)     mon2sb_mbx;
  mailbox #(ahb_mon_txn)     mon2cov_mbx;

  function new(virtual ahb_if.DRIVER drv_vif, virtual ahb_if.MONITOR mon_vif);
    this.drv_vif = drv_vif;
    this.mon_vif = mon_vif;

    gen2drv_mbx = new();
    mon2sb_mbx  = new();
    mon2cov_mbx = new();

    gen = new(gen2drv_mbx);
    drv = new(drv_vif, gen2drv_mbx);
    mon = new(mon_vif, mon2sb_mbx, mon2cov_mbx);
    sb  = new(mon2sb_mbx);
    cov = new(mon2cov_mbx);
  endfunction

  //-------------------------------------------------------------------
  // Start the continuously-running components: driver, monitor,
  // scoreboard, coverage. These run for the lifetime of the test,
  // consuming whatever the generator (driven directly by the test)
  // sends into gen2drv_mbx.
  //-------------------------------------------------------------------
  task start_components();
    fork
      drv.run();
      mon.run();
      sb.run();
      cov.run();
    join_none
  endtask

  //-------------------------------------------------------------------
  // Run the generator's full directed-burst-sweep + random-transaction
  // sequence, then block until the driver has actually drained the
  // mailbox (not just until the generator finished producing items).
  //-------------------------------------------------------------------
  task run_random(int unsigned num_random_txns);
    gen.num_random_txns = num_random_txns;
    gen.run();
    wait_for_drain();
  endtask

  //-------------------------------------------------------------------
  // Blocks until the generator->driver mailbox is empty, meaning the
  // driver has picked up (started driving) every generated transaction.
  //-------------------------------------------------------------------
  task wait_for_drain();
    while (gen2drv_mbx.num() > 0) @(posedge drv_vif.HCLK);
    // The driver may still be in the middle of driving the very last
    // transaction it just pulled out of the mailbox; give it generous
    // time to finish (longest possible burst is 16 beats, plus wait
    // states), then a little extra for the monitor/scoreboard to
    // process the final beats.
    repeat (64) @(posedge drv_vif.HCLK);
  endtask

  function void print_results();
    sb.print_summary();
    cov.print_coverage();
  endfunction

endclass : ahb_env
