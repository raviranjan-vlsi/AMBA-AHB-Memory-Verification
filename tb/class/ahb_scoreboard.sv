//=============================================================
// ahb_scoreboard.sv
// Self-checking scoreboard with an independent reference memory
// model. Consumes beat-level transactions from the monitor.
//=============================================================

// NOTE: included inside ahb_pkg.sv (see that file's `include list).
// Do not compile this file directly with vlog.

class ahb_scoreboard;

  mailbox #(ahb_mon_txn) mon2sb_mbx;

  // Independent reference memory (mirrors ahb_memory.sv contents)
  logic [DATA_WIDTH-1:0] ref_mem [0:MEM_DEPTH-1];

  // Statistics
  int unsigned total_transactions  = 0;
  int unsigned passed_transactions = 0;
  int unsigned failed_transactions = 0;

  function new(mailbox #(ahb_mon_txn) mon2sb_mbx);
    this.mon2sb_mbx = mon2sb_mbx;
    foreach (ref_mem[i]) ref_mem[i] = '0;
  endfunction

  //-------------------------------------------------------------------
  // Extract the expected byte/halfword/word value from the reference
  // memory, given an address and size (mirrors DUT read-data muxing).
  //-------------------------------------------------------------------
  function automatic logic [DATA_WIDTH-1:0] get_expected_read(
      logic [ADDR_WIDTH-1:0] addr,
      hsize_e size
  );
    int unsigned word_idx;
    logic [1:0]  byte_off;
    logic [DATA_WIDTH-1:0] word_data;

    word_idx  = addr >> 2;
    byte_off  = addr[1:0];
    word_data = ref_mem[word_idx];

    case (size)
      HSIZE_BYTE: begin
        case (byte_off)
          2'b00: return {24'd0, word_data[7:0]};
          2'b01: return {24'd0, word_data[15:8]};
          2'b10: return {24'd0, word_data[23:16]};
          default: return {24'd0, word_data[31:24]};
        endcase
      end
      HSIZE_HALFWORD: begin
        if (byte_off[1] == 1'b0) return {16'd0, word_data[15:0]};
        else                     return {16'd0, word_data[31:16]};
      end
      default: return word_data; // WORD
    endcase
  endfunction

  //-------------------------------------------------------------------
  // Apply a write beat to the reference memory
  //-------------------------------------------------------------------
  function automatic void apply_write(
      logic [ADDR_WIDTH-1:0] addr,
      hsize_e size,
      logic [DATA_WIDTH-1:0] data
  );
    int unsigned word_idx;
    logic [1:0]  byte_off;

    word_idx = addr >> 2;
    byte_off = addr[1:0];

    case (size)
      HSIZE_BYTE: begin
        case (byte_off)
          2'b00: ref_mem[word_idx][7:0]   = data[7:0];
          2'b01: ref_mem[word_idx][15:8]  = data[7:0];
          2'b10: ref_mem[word_idx][23:16] = data[7:0];
          default: ref_mem[word_idx][31:24] = data[7:0];
        endcase
      end
      HSIZE_HALFWORD: begin
        if (byte_off[1] == 1'b0) ref_mem[word_idx][15:0]  = data[15:0];
        else                     ref_mem[word_idx][31:16] = data[15:0];
      end
      default: ref_mem[word_idx] = data; // WORD
    endcase
  endfunction

  //-------------------------------------------------------------------
  // Returns 1 if the address/size combination is a legal in-range,
  // aligned access (mirrors the DUT's own error checking).
  //-------------------------------------------------------------------
  function automatic bit is_legal_access(logic [ADDR_WIDTH-1:0] addr, hsize_e size);
    bit aligned;
    bit in_range;
    case (size)
      HSIZE_BYTE:     aligned = 1'b1;
      HSIZE_HALFWORD: aligned = (addr[0]   == 1'b0);
      HSIZE_WORD:     aligned = (addr[1:0] == 2'b00);
      default:        aligned = 1'b0;
    endcase
    in_range = ((addr >> 2) < MEM_DEPTH);
    return aligned & in_range;
  endfunction

  //-------------------------------------------------------------------
  // Main run loop: check every beat reported by the monitor
  //-------------------------------------------------------------------
  task automatic run();
    ahb_mon_txn m;
    bit legal;
    hresp_e expected_resp;

    forever begin
      mon2sb_mbx.get(m);
      total_transactions++;

      legal = is_legal_access(m.addr, m.hsize);
      expected_resp = legal ? HRESP_OKAY : HRESP_ERROR;

      if (m.hresp !== expected_resp) begin
        failed_transactions++;
        $display("[SCOREBOARD] FAIL (HRESP mismatch) addr=0x%0h size=%s burst=%s expected_resp=%s actual_resp=%s",
                  m.addr, m.hsize.name(), m.hburst.name(), expected_resp.name(), m.hresp.name());
        continue;
      end

      if (!legal) begin
        // DUT correctly reported an error; nothing further to check
        // (no memory update, no data comparison for an errored access)
        passed_transactions++;
        continue;
      end

      if (m.write) begin
        apply_write(m.addr, m.hsize, m.data);
        passed_transactions++;
        // Uncomment for verbose write logging:
        // $display("[SCOREBOARD] WRITE addr=0x%0h size=%s data=0x%0h", m.addr, m.hsize.name(), m.data);
      end else begin
        logic [DATA_WIDTH-1:0] expected_data = get_expected_read(m.addr, m.hsize);
        if (expected_data === m.data) begin
          passed_transactions++;
        end else begin
          failed_transactions++;
          $display("[SCOREBOARD] FAIL (READ mismatch) addr=0x%0h size=%s burst=%s expected=0x%0h actual=0x%0h",
                    m.addr, m.hsize.name(), m.hburst.name(), expected_data, m.data);
        end
      end
    end
  endtask

  //-------------------------------------------------------------------
  // Print final summary
  //-------------------------------------------------------------------
  function void print_summary();
    $display("====================================");
    $display("AHB SCOREBOARD SUMMARY");
    $display("====================================");
    $display("Total     : %0d", total_transactions);
    $display("Passed    : %0d", passed_transactions);
    $display("Failed    : %0d", failed_transactions);
    $display("====================================");
  endfunction

endclass : ahb_scoreboard
