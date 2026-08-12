//=============================================================
// ahb_assertions.sv
// AHB-Lite protocol checker. Bound (via `bind`) onto the ahb_if
// interface instance in tb_top.sv so it observes the live bus.
//
// This is a plain module using SVA (SystemVerilog Assertions),
// not a class - it runs concurrently with the rest of the testbench.
//=============================================================
`timescale 1ns/1ps
module ahb_assertions (
    input logic       HCLK,
    input logic       HRESETn,
    input logic       HSEL,
    input logic [31:0] HADDR,
    input logic [1:0]  HTRANS,
    input logic        HWRITE,
    input logic [2:0]  HSIZE,
    input logic [2:0]  HBURST,
    input logic        HREADY,
    input logic        HREADYOUT,
    input logic        HRESP
);

  localparam logic [1:0] TR_IDLE   = 2'b00;
  localparam logic [1:0] TR_BUSY   = 2'b01;
  localparam logic [1:0] TR_NONSEQ = 2'b10;
  localparam logic [1:0] TR_SEQ    = 2'b11;

  // Tracks whether a burst is currently "open" (a NONSEQ has been
  // accepted and we have not yet returned to IDLE).
  logic burst_active;

  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      burst_active <= 1'b0;
    end else if (HREADY) begin
      if (HSEL && (HTRANS == TR_NONSEQ)) burst_active <= 1'b1;
      else if (HTRANS == TR_IDLE)        burst_active <= 1'b0;
    end
  end

  //-------------------------------------------------------------------
  // a_no_transfer_during_reset
  // While HRESETn is low, HTRANS must be IDLE (no active transfer).
  //-------------------------------------------------------------------
  property p_no_transfer_during_reset;
    @(posedge HCLK) (!HRESETn) |-> (HTRANS == TR_IDLE);
  endproperty
  a_no_transfer_during_reset: assert property (p_no_transfer_during_reset)
    else $error("ASSERTION FAILED: a_no_transfer_during_reset - HTRANS not IDLE during reset");

  //-------------------------------------------------------------------
  // a_valid_htrans
  // HTRANS must always be a legal 2-bit encoding (guaranteed by type,
  // but checked here to document the requirement and to catch X/Z).
  //-------------------------------------------------------------------
  property p_valid_htrans;
    @(posedge HCLK) disable iff (!HRESETn)
      !$isunknown(HTRANS);
  endproperty
  a_valid_htrans: assert property (p_valid_htrans)
    else $error("ASSERTION FAILED: a_valid_htrans - HTRANS is X/Z");

  //-------------------------------------------------------------------
  // a_aligned_word_access
  // A WORD (HSIZE=010) transfer must have its two LSBs of HADDR = 00.
  //-------------------------------------------------------------------
  property p_aligned_word_access;
    @(posedge HCLK) disable iff (!HRESETn)
      (HSEL && HREADY && (HTRANS inside {TR_NONSEQ, TR_SEQ}) && (HSIZE == 3'b010))
        |-> (HADDR[1:0] == 2'b00);
  endproperty
  a_aligned_word_access: assert property (p_aligned_word_access)
    else $error("ASSERTION FAILED: a_aligned_word_access - unaligned word access, HADDR=%0h", HADDR);

  //-------------------------------------------------------------------
  // a_aligned_halfword_access
  // A HALFWORD (HSIZE=001) transfer must have HADDR[0] = 0.
  //-------------------------------------------------------------------
  property p_aligned_halfword_access;
    @(posedge HCLK) disable iff (!HRESETn)
      (HSEL && HREADY && (HTRANS inside {TR_NONSEQ, TR_SEQ}) && (HSIZE == 3'b001))
        |-> (HADDR[0] == 1'b0);
  endproperty
  a_aligned_halfword_access: assert property (p_aligned_halfword_access)
    else $error("ASSERTION FAILED: a_aligned_halfword_access - unaligned halfword access, HADDR=%0h", HADDR);

  //-------------------------------------------------------------------
  // a_seq_follows_active_burst
  // A SEQ transfer must only occur while a burst is already active
  // (i.e. a NONSEQ has previously opened it).
  //-------------------------------------------------------------------
  property p_seq_follows_active_burst;
    @(posedge HCLK) disable iff (!HRESETn)
      (HSEL && HREADY && (HTRANS == TR_SEQ)) |-> burst_active;
  endproperty
  a_seq_follows_active_burst: assert property (p_seq_follows_active_burst)
    else $error("ASSERTION FAILED: a_seq_follows_active_burst - SEQ seen without an active burst");

  //-------------------------------------------------------------------
  // a_address_stable_when_waiting
  // While the slave holds HREADYOUT low (wait state), the master must
  // keep HADDR/HTRANS/HWRITE/HSIZE/HBURST stable.
  //-------------------------------------------------------------------
  property p_address_stable_when_waiting;
    @(posedge HCLK) disable iff (!HRESETn)
      (!HREADYOUT) |=> ($stable(HADDR) && $stable(HTRANS) && $stable(HWRITE) &&
                         $stable(HSIZE) && $stable(HBURST));
  endproperty
  a_address_stable_when_waiting: assert property (p_address_stable_when_waiting)
    else $error("ASSERTION FAILED: a_address_stable_when_waiting - control signals changed during wait state");

  //-------------------------------------------------------------------
  // a_valid_hresp
  // HRESP must never be unknown.
  //-------------------------------------------------------------------
  property p_valid_hresp;
    @(posedge HCLK) disable iff (!HRESETn)
      !$isunknown(HRESP);
  endproperty
  a_valid_hresp: assert property (p_valid_hresp)
    else $error("ASSERTION FAILED: a_valid_hresp - HRESP is X/Z");

  //-------------------------------------------------------------------
  // a_hsel_gates_transfer
  // A NONSEQ/SEQ transfer is only meaningful while HSEL is asserted;
  // this documents that the slave should not act on transfers not
  // addressed to it (checked here as: when HSEL is low, HREADYOUT of
  // this slave should not be artificially held low by a stale request).
  // Simplified to: HTRANS should be IDLE or BUSY whenever HSEL is low.
  //-------------------------------------------------------------------
  property p_hsel_gates_transfer;
    @(posedge HCLK) disable iff (!HRESETn)
      (!HSEL) |-> (HTRANS inside {TR_IDLE, TR_BUSY});
  endproperty
  a_hsel_gates_transfer: assert property (p_hsel_gates_transfer)
    else $error("ASSERTION FAILED: a_hsel_gates_transfer - active transfer type seen while HSEL is low");

  //-------------------------------------------------------------------
  // a_readyout_known
  // HREADYOUT must never be unknown after reset (needed for the
  // pipeline to make forward progress).
  //-------------------------------------------------------------------
  property p_readyout_known;
    @(posedge HCLK) disable iff (!HRESETn)
      !$isunknown(HREADYOUT);
  endproperty
  a_readyout_known: assert property (p_readyout_known)
    else $error("ASSERTION FAILED: a_readyout_known - HREADYOUT is X/Z");

endmodule : ahb_assertions
