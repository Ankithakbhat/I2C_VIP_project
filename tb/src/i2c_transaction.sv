//==============================================================================
// i2c_transaction.sv
// Sequence item for the I2C agent (slave-emulation mode).
//
// Used two ways:
//   1) As a *stimulus* item from a sequence to the driver: tells the driver
//      how to behave as the target slave device (ACK/NACK, data to return
//      on a read, whether to stretch the clock, etc.)
//   2) As the *observed* item published by the monitor after decoding an
//      actual bus transaction (for scoreboard/coverage use).
//==============================================================================
`ifndef I2C_TRANSACTION_SV
`define I2C_TRANSACTION_SV

class i2c_transaction extends uvm_sequence_item;

  // ---- Address / direction (as driven by the DUT master, or expected) ----
  rand bit [6:0] slave_addr;
  rand i2c_dir_e dir;
  rand bit       repeat_start;      // repeated START expected after this phase
  rand int       num_bytes;         // 1-4, per confirmed max multibyte size

  // ---- Data payload ----
  rand bit [7:0] wr_data[4];        // data the driver sends back on I2C_READ
  bit      [7:0] rd_data[4];        // data captured on I2C_WRITE (monitor/driver)

  // ---- Driver-side stimulus controls (slave-emulation behavior) ----
  rand bit inject_addr_nack;        // NACK the address byte
  rand bit inject_data_nack_on;     // byte index (0-3) to NACK, if any
  rand int data_nack_byte_idx;
  rand bit inject_clock_stretch;
  rand int stretch_cycles;          // approximate hold duration (in SCL "ticks")
  rand bit inject_sda_stuck_after_stop; // hold SDA low through STOP to trigger sda_err

  // ---- Observed/result fields (populated by driver after completion, or
  //      by monitor after decode) ----
  bit addr_ack_rcvd;                // 1 = ACK, 0 = NACK observed on addr byte
  bit data_ack_rcvd[4];             // per-byte ACK/NACK observed
  i2c_error_e observed_error;

  `uvm_object_utils_begin(i2c_transaction)
    `uvm_field_int(slave_addr, UVM_ALL_ON)
    `uvm_field_enum(i2c_dir_e, dir, UVM_ALL_ON)
    `uvm_field_int(repeat_start, UVM_ALL_ON)
    `uvm_field_int(num_bytes, UVM_ALL_ON)
    `uvm_field_sarray_int(wr_data, UVM_ALL_ON)
    `uvm_field_sarray_int(rd_data, UVM_ALL_ON)
    `uvm_field_int(inject_addr_nack, UVM_ALL_ON)
    `uvm_field_int(data_nack_byte_idx, UVM_ALL_ON)
    `uvm_field_int(inject_clock_stretch, UVM_ALL_ON)
    `uvm_field_int(stretch_cycles, UVM_ALL_ON)
    `uvm_field_int(inject_sda_stuck_after_stop, UVM_ALL_ON)
    `uvm_field_int(addr_ack_rcvd, UVM_ALL_ON)
    `uvm_field_enum(i2c_error_e, observed_error, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i2c_transaction");
    super.new(name);
  endfunction

  constraint c_num_bytes { num_bytes inside {[1:4]}; }
  constraint c_data_nack_idx { data_nack_byte_idx inside {[0:3]}; }

endclass

`endif // I2C_TRANSACTION_SV
