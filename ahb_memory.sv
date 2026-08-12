//=============================================================
// ahb_memory.sv
// Simple synthesizable AHB-Lite memory slave.
//
// - Does NOT generate burst addresses. The AHB master (driver)
//   is responsible for presenting the correct HADDR for every
//   beat of a burst. This slave simply accepts what is given.
// - Supports byte / halfword / word accesses.
// - Supports configurable wait states (WAIT_STATES parameter).
// - Returns HRESP = ERROR for out-of-range or misaligned access.
//=============================================================

`timescale 1ns/1ps
module ahb_memory #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int MEM_DEPTH   = 256,   // number of 32-bit words
    parameter int WAIT_STATES = 0      // extra wait cycles per transfer (0 = zero-wait-state)
) (
    input  logic                    HCLK,
    input  logic                    HRESETn,

    input  logic                    HSEL,
    input  logic [ADDR_WIDTH-1:0]   HADDR,
    input  logic [1:0]              HTRANS,
    input  logic                    HWRITE,
    input  logic [2:0]              HSIZE,
    input  logic [2:0]              HBURST,
    input  logic [3:0]              HPROT,
    input  logic [DATA_WIDTH-1:0]   HWDATA,
    input  logic                    HREADY,

    output logic [DATA_WIDTH-1:0]   HRDATA,
    output logic                    HREADYOUT,
    output logic                    HRESP
);

  // Local HTRANS/HSIZE encodings (kept local to stay a standalone,
  // dependency-free RTL module as required)
  localparam logic [1:0] TR_IDLE   = 2'b00;
  localparam logic [1:0] TR_BUSY   = 2'b01;
  localparam logic [1:0] TR_NONSEQ = 2'b10;
  localparam logic [1:0] TR_SEQ    = 2'b11;

  localparam logic [2:0] SZ_BYTE     = 3'b000;
  localparam logic [2:0] SZ_HALFWORD = 3'b001;
  localparam logic [2:0] SZ_WORD     = 3'b010;

  localparam int ADDR_LSB = $clog2(DATA_WIDTH/8); // =2 for 32-bit word
  localparam int WORD_INDEX_BITS = $clog2(MEM_DEPTH);

  // Memory array: MEM_DEPTH words of DATA_WIDTH bits
  logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

  //-----------------------------------------------------------
  // Address phase capture (registered into the data phase)
  //-----------------------------------------------------------
  logic                    addr_phase_valid;   // this transfer requires a data-phase response
  logic [ADDR_WIDTH-1:0]   addr_phase_addr;
  logic                    addr_phase_write;
  logic [2:0]              addr_phase_size;
  logic                    addr_phase_error;   // captured error condition for this transfer

  // A transfer is "valid" for the AHB slave when selected, HREADY high
  // (so the address phase is actually accepted), and HTRANS is NONSEQ or SEQ.
  wire transfer_requested = HSEL & HREADY & ((HTRANS == TR_NONSEQ) || (HTRANS == TR_SEQ));

  // Check alignment: address must be aligned to the transfer size
  function automatic bit is_aligned(input logic [ADDR_WIDTH-1:0] addr, input logic [2:0] size);
    case (size)
      SZ_BYTE:     is_aligned = 1'b1;                 // any alignment ok
      SZ_HALFWORD: is_aligned = (addr[0]   == 1'b0);
      SZ_WORD:     is_aligned = (addr[1:0] == 2'b00);
      default:     is_aligned = 1'b0;                 // unsupported size
    endcase
  endfunction

  // Check that the size is one we support (byte/halfword/word only)
  function automatic bit is_supported_size(input logic [2:0] size);
    is_supported_size = (size == SZ_BYTE) || (size == SZ_HALFWORD) || (size == SZ_WORD);
  endfunction

  // Check address range: word index must be within MEM_DEPTH
  function automatic bit is_in_range(input logic [ADDR_WIDTH-1:0] addr);
    logic [ADDR_WIDTH-1:0] word_index;
    word_index = addr >> ADDR_LSB;
    is_in_range = (word_index < MEM_DEPTH);
  endfunction

  wire req_supported_size = is_supported_size(HSIZE);
  wire req_aligned        = req_supported_size ? is_aligned(HADDR, HSIZE) : 1'b0;
  wire req_in_range       = is_in_range(HADDR);
  wire req_error          = ~(req_supported_size & req_aligned & req_in_range);

  //-----------------------------------------------------------
  // Wait-state handling
  //-----------------------------------------------------------
  // Counts remaining wait cycles for the transfer currently in
  // its data phase. When 0, HREADYOUT is asserted.
  logic [7:0] wait_cnt;
  logic       in_wait;

  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      wait_cnt <= '0;
      in_wait  <= 1'b0;
    end else begin
      if (transfer_requested && !in_wait && (WAIT_STATES > 0)) begin
        // Start wait period for the newly accepted transfer
        wait_cnt <= WAIT_STATES[7:0];
        in_wait  <= 1'b1;
      end else if (in_wait) begin
        if (wait_cnt <= 8'd1) begin
          in_wait  <= 1'b0;
          wait_cnt <= '0;
        end else begin
          wait_cnt <= wait_cnt - 8'd1;
        end
      end
    end
  end

  assign HREADYOUT = ~in_wait;

  //-----------------------------------------------------------
  // Address phase -> data phase pipeline register
  // Captured only when a new transfer is accepted (HREADY high),
  // i.e. we are not currently stalling the pipeline with wait states.
  //-----------------------------------------------------------
  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      addr_phase_valid <= 1'b0;
      addr_phase_addr  <= '0;
      addr_phase_write <= 1'b0;
      addr_phase_size  <= '0;
      addr_phase_error <= 1'b0;
    end else if (HREADYOUT) begin
      // Only latch a new address phase when the current data phase
      // is completing (HREADYOUT=1), matching the AHB pipeline.
      addr_phase_valid <= transfer_requested;
      addr_phase_addr  <= HADDR;
      addr_phase_write <= HWRITE;
      addr_phase_size  <= HSIZE;
      addr_phase_error <= req_error;
    end
  end

  //-----------------------------------------------------------
  // Data phase: perform the actual memory read/write
  //-----------------------------------------------------------
  logic [WORD_INDEX_BITS-1:0] word_idx;
  logic [1:0]                 byte_off;

  assign word_idx = addr_phase_addr[ADDR_LSB +: WORD_INDEX_BITS];
  assign byte_off = addr_phase_addr[1:0];

  // Combinational read data mux (byte/halfword/word extraction)
  always_comb begin
    logic [DATA_WIDTH-1:0] word_data;
    word_data = mem[word_idx];
    unique case (addr_phase_size)
      SZ_BYTE: begin
        unique case (byte_off)
          2'b00: HRDATA = {24'd0, word_data[7:0]};
          2'b01: HRDATA = {24'd0, word_data[15:8]};
          2'b10: HRDATA = {24'd0, word_data[23:16]};
          2'b11: HRDATA = {24'd0, word_data[31:24]};
        endcase
      end
      SZ_HALFWORD: begin
        unique case (byte_off[1])
          1'b0: HRDATA = {16'd0, word_data[15:0]};
          1'b1: HRDATA = {16'd0, word_data[31:16]};
        endcase
      end
      default: HRDATA = word_data; // WORD
    endcase
  end

  // Write handling (data phase). HWDATA corresponds to the
  // transfer whose address phase is currently completing.
  always @(posedge HCLK) begin
    if (HRESETn && addr_phase_valid && addr_phase_write && !addr_phase_error && HREADYOUT) begin
      unique case (addr_phase_size)
        SZ_BYTE: begin
          unique case (byte_off)
            2'b00: mem[word_idx][7:0]   <= HWDATA[7:0];
            2'b01: mem[word_idx][15:8]  <= HWDATA[7:0];
            2'b10: mem[word_idx][23:16] <= HWDATA[7:0];
            2'b11: mem[word_idx][31:24] <= HWDATA[7:0];
          endcase
        end
        SZ_HALFWORD: begin
          unique case (byte_off[1])
            1'b0: mem[word_idx][15:0]  <= HWDATA[15:0];
            1'b1: mem[word_idx][31:16] <= HWDATA[15:0];
          endcase
        end
        default: mem[word_idx] <= HWDATA; // WORD
      endcase
    end
  end

  //-----------------------------------------------------------
  // Response: HRESP is valid during the data phase alongside HREADYOUT
  //-----------------------------------------------------------
  assign HRESP = addr_phase_valid ? addr_phase_error : 1'b0;

  //-----------------------------------------------------------
  // Memory initialization (simulation convenience, harmless for
  // synthesis - most tools will simply drop this for a real memory)
  //-----------------------------------------------------------
  // synthesis translate_off
  initial begin
    for (int i = 0; i < MEM_DEPTH; i++) mem[i] = '0;
  end
  // synthesis translate_on

endmodule : ahb_memory
