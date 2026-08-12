//=============================================================
// ahb_test.sv
// Top-level test module. Builds the environment, runs directed
// scenarios (TEST 1-15) followed by randomized/stress testing
// (TEST 16-17), then prints the final summary.
//
// This is a module (not a class) so it can be instantiated
// directly from tb_top.sv. The interface is passed in as a plain
// (non-modport) port; the DRIVER/MONITOR modport views are taken
// from it when constructing the environment.
//=============================================================
`timescale 1ns/1ps
import ahb_pkg::*;

module ahb_test (
    input  logic HCLK,
    input  logic HRESETn,
    ahb_if.DRIVER  bus_drv,
    ahb_if.MONITOR bus_mon
);

  ahb_env env;

  initial begin
    env = new(bus_drv, bus_mon);

    $display("========================================");
    $display("AHB-LITE MEMORY VERIFICATION STARTING");
    $display("========================================");

    // ---------------------------------------------------------------
    // TEST 1: Reset behaviour
    // Reset is generated in tb_top.sv; the driver's wait_for_reset()
    // (called inside env.drv.run()) confirms the bus starts in IDLE
    // and waits for HRESETn to deassert before driving anything.
    // ---------------------------------------------------------------
    $display("[TEST] TEST 1: Reset - handled automatically by driver.wait_for_reset()");

    // Start the continuously-running components (driver/monitor/
    // scoreboard/coverage) now so the directed tests below can be
    // driven through the normal generator->driver mailbox path.
    env.start_components();

    // Give the driver a moment to clear reset before sending stimulus
    wait (HRESETn === 1'b1);
    repeat (3) @(posedge HCLK);

    //------------------------------------------------------------
    // TEST 2: Single Write
    //------------------------------------------------------------
    $display("[TEST] TEST 2: Single Write");
    env.gen.send_directed(32'h0000_0000, 1'b1, HSIZE_WORD, HBURST_SINGLE);

    //------------------------------------------------------------
    // TEST 3: Single Read
    //------------------------------------------------------------
    $display("[TEST] TEST 3: Single Read");
    env.gen.send_directed(32'h0000_0000, 1'b0, HSIZE_WORD, HBURST_SINGLE);

    //------------------------------------------------------------
    // TEST 4: Byte Access (write then read back)
    //------------------------------------------------------------
    $display("[TEST] TEST 4: Byte Access");
    env.gen.send_directed(32'h0000_0004, 1'b1, HSIZE_BYTE, HBURST_SINGLE);
    env.gen.send_directed(32'h0000_0004, 1'b0, HSIZE_BYTE, HBURST_SINGLE);

    //------------------------------------------------------------
    // TEST 5: Halfword Access (write then read back)
    //------------------------------------------------------------
    $display("[TEST] TEST 5: Halfword Access");
    env.gen.send_directed(32'h0000_0008, 1'b1, HSIZE_HALFWORD, HBURST_SINGLE);
    env.gen.send_directed(32'h0000_0008, 1'b0, HSIZE_HALFWORD, HBURST_SINGLE);

    //------------------------------------------------------------
    // TEST 6: Word Access (write then read back)
    //------------------------------------------------------------
    $display("[TEST] TEST 6: Word Access");
    env.gen.send_directed(32'h0000_000C, 1'b1, HSIZE_WORD, HBURST_SINGLE);
    env.gen.send_directed(32'h0000_000C, 1'b0, HSIZE_WORD, HBURST_SINGLE);

    //------------------------------------------------------------
    // TEST 7: SINGLE burst
    //------------------------------------------------------------
    $display("[TEST] TEST 7: SINGLE burst");
    env.gen.send_directed(32'h0000_0010, 1'b1, HSIZE_WORD, HBURST_SINGLE);

    //------------------------------------------------------------
    // TEST 8: INCR burst (undefined length, use 5 beats)
    //------------------------------------------------------------
    $display("[TEST] TEST 8: INCR burst");
    env.gen.send_directed(32'h0000_0020, 1'b1, HSIZE_WORD, HBURST_INCR, 5);
    env.gen.send_directed(32'h0000_0020, 1'b0, HSIZE_WORD, HBURST_INCR, 5);

    //------------------------------------------------------------
    // TEST 9: INCR4
    //------------------------------------------------------------
    $display("[TEST] TEST 9: INCR4 burst");
    env.gen.send_directed(32'h0000_0040, 1'b1, HSIZE_WORD, HBURST_INCR4);
    env.gen.send_directed(32'h0000_0040, 1'b0, HSIZE_WORD, HBURST_INCR4);

    //------------------------------------------------------------
    // TEST 10: WRAP4 (start mid-boundary, per spec example: 0x1008-style)
    //------------------------------------------------------------
    $display("[TEST] TEST 10: WRAP4 burst");
    env.gen.send_directed(32'h0000_0058, 1'b1, HSIZE_WORD, HBURST_WRAP4);
    env.gen.send_directed(32'h0000_0058, 1'b0, HSIZE_WORD, HBURST_WRAP4);

    //------------------------------------------------------------
    // TEST 11: INCR8
    //------------------------------------------------------------
    $display("[TEST] TEST 11: INCR8 burst");
    env.gen.send_directed(32'h0000_0080, 1'b1, HSIZE_WORD, HBURST_INCR8);
    env.gen.send_directed(32'h0000_0080, 1'b0, HSIZE_WORD, HBURST_INCR8);

    //------------------------------------------------------------
    // TEST 12: WRAP8
    //------------------------------------------------------------
    $display("[TEST] TEST 12: WRAP8 burst");
    env.gen.send_directed(32'h0000_00B0, 1'b1, HSIZE_WORD, HBURST_WRAP8);
    env.gen.send_directed(32'h0000_00B0, 1'b0, HSIZE_WORD, HBURST_WRAP8);

    //------------------------------------------------------------
    // TEST 13: INCR16
    //------------------------------------------------------------
    $display("[TEST] TEST 13: INCR16 burst");
    env.gen.send_directed(32'h0000_0100, 1'b1, HSIZE_WORD, HBURST_INCR16);
    env.gen.send_directed(32'h0000_0100, 1'b0, HSIZE_WORD, HBURST_INCR16);

    //------------------------------------------------------------
    // TEST 14: WRAP16
    //------------------------------------------------------------
    $display("[TEST] TEST 14: WRAP16 burst");
    env.gen.send_directed(32'h0000_0180, 1'b1, HSIZE_WORD, HBURST_WRAP16);
    env.gen.send_directed(32'h0000_0180, 1'b0, HSIZE_WORD, HBURST_WRAP16);

    //------------------------------------------------------------
    // TEST 15: Mixed Read/Write (interleaved directed transactions)
    //------------------------------------------------------------
    $display("[TEST] TEST 15: Mixed Read/Write");
    env.gen.send_directed(32'h0000_0200, 1'b1, HSIZE_WORD, HBURST_INCR4);
    env.gen.send_directed(32'h0000_0200, 1'b0, HSIZE_WORD, HBURST_SINGLE);
    env.gen.send_directed(32'h0000_0204, 1'b1, HSIZE_HALFWORD, HBURST_SINGLE);
    env.gen.send_directed(32'h0000_0204, 1'b0, HSIZE_HALFWORD, HBURST_SINGLE);

    //------------------------------------------------------------
    // Directed error-injection: exercise HRESP=ERROR paths
    // (out-of-range address, and a misaligned word access) so that
    // coverage's response_cp.error_resp bin and the error-handling
    // logic in the DUT/scoreboard are both actually exercised.
    //------------------------------------------------------------
    $display("[TEST] Directed error cases: out-of-range and misaligned access");
    env.gen.send_directed(32'h0000_0FFC, 1'b1, HSIZE_WORD, HBURST_SINGLE); // out of range (mem is 0x000-0x3FF)
    env.gen.send_directed(32'h0000_0FFC, 1'b0, HSIZE_WORD, HBURST_SINGLE); // out of range read
    begin
      // Misaligned word access: build directly since the transaction
      // class constraints normally forbid misalignment.
      ahb_transaction bad_txn = new();
      bad_txn.addr     = 32'h0000_0001; // misaligned for WORD
      bad_txn.write    = 1'b0;
      bad_txn.hsize    = HSIZE_WORD;
      bad_txn.hburst   = HBURST_SINGLE;
      bad_txn.incr_len = 1;
      bad_txn.hprot    = 4'b0011;
      env.gen.gen2drv_mbx.put(bad_txn);
    end

    // Wait for all directed transactions (TEST 2-15 + error cases)
    // above to actually be driven before starting the random phase.
    env.wait_for_drain();

    //------------------------------------------------------------
    // TEST 16 & TEST 17: Random Burst Test + Stress Test
    // env.run_random() sweeps all 8 burst types directed (guaranteed
    // coverage) then runs many fully constrained-random transactions
    // (the "stress" portion), and blocks until the driver has
    // finished driving everything.
    //------------------------------------------------------------
    $display("[TEST] TEST 16/17: Random Burst Test + Stress Test");
    env.run_random(500);

    $display("========================================");
    $display("AHB-LITE MEMORY VERIFICATION SUMMARY");
    $display("========================================");
    $display("Total Transactions : %0d", env.sb.total_transactions);
    $display("Passed             : %0d", env.sb.passed_transactions);
    $display("Failed             : %0d", env.sb.failed_transactions);
    $display("Functional Coverage: %0.2f %%", env.cov.cg_ahb.get_coverage());
    $display("========================================");

    if (env.sb.failed_transactions == 0) begin
      $display("TEST PASSED");
    end else begin
      $display("TEST FAILED");
    end
    $display("========================================");

    env.print_results();

    $finish;
  end

endmodule : ahb_test
