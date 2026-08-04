/==============================================================================
// i2c_agent.sv
//==============================================================================
`ifndef I2C_AGENT_SV
`define I2C_AGENT_SV

class i2c_agent extends uvm_agent;
  `uvm_component_utils(i2c_agent)

  i2c_config    cfg;
  i2c_driver    drv;
  i2c_sequencer sqr;
  i2c_monitor   mon;

  function new(string name = "i2c_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(i2c_config)::get(this, "", "i2c_config", cfg))
      `uvm_fatal("NOCFG", "i2c_config not found in config_db")

    uvm_config_db#(i2c_config)::set(this, "*", "i2c_config", cfg);

    mon = i2c_monitor::type_id::create("mon", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      drv = i2c_driver::type_id::create("drv", this);
      sqr = i2c_sequencer::type_id::create("sqr", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass

`endif // I2C_AGENT_SV
