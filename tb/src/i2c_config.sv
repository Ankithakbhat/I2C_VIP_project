//==============================================================================
// i2c_config.sv
// Configuration object for the I2C agent
//==============================================================================
`ifndef I2C_CONFIG_SV
`define I2C_CONFIG_SV

class i2c_config extends uvm_object;
  `uvm_object_utils(i2c_config)

  virtual i2c_if vif;

  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // The DUT is confirmed to be the only I2C master on the bus (no multi-
  // controller/arbitration), so the agent always operates as a slave-
  // emulation device. Kept as a bit for forward-compatibility only.
  bit slave_emulation_mode = 1;

  bit checks_enable    = 1;
  bit coverage_enable   = 1;

  i2c_speed_e speed = I2C_SPEED_STANDARD;

  function new(string name = "i2c_config");
    super.new(name);
  endfunction

endclass
