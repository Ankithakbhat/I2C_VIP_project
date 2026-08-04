//==============================================================================
// i2c_agent_pkg.sv
//==============================================================================
`ifndef I2C_AGENT_PKG_SV
`define I2C_AGENT_PKG_SV

package i2c_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "i2c_apb_defines.svh"

  `include "i2c_transaction.sv"
  `include "i2c_config.sv"
  `include "i2c_sequencer.sv"
  `include "i2c_driver.sv"
  `include "i2c_monitor.sv"
  `include "i2c_agent.sv"

endpackage

`endif // I2C_AGENT_PKG_SV
