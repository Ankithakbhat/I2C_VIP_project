//==============================================================================
// i2c_apb_base_test.sv
//
// Base test: builds the environment and reg model, wires config_db entries.
// No scenario test classes are defined here yet - add
// `class my_scenario_test extends i2c_apb_base_test ... endclass` per your
// test list, overriding run_phase (or starting a specific virtual sequence)
// as needed.
//==============================================================================
`ifndef I2C_APB_BASE_TEST_SV
`define I2C_APB_BASE_TEST_SV

class i2c_apb_base_test extends uvm_test;
  `uvm_component_utils(i2c_apb_base_test)

  i2c_apb_env        env;
  i2c_apb_env_config env_cfg;

  function new(string name = "i2c_apb_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    env_cfg = i2c_apb_env_config::type_id::create("env_cfg");

    env_cfg.i2c_cfg = i2c_config::type_id::create("i2c_cfg");
    if (!uvm_config_db#(virtual i2c_if)::get(this, "", "i2c_vif", env_cfg.i2c_cfg.vif))
      `uvm_fatal("NOVIF", "i2c_vif not found in config_db - check tb_top.sv")
    env_cfg.i2c_cfg.is_active = UVM_ACTIVE;

    env_cfg.reg_model = i2c_apb_reg_block::type_id::create("reg_model");
    env_cfg.reg_model.build();

    uvm_config_db#(i2c_apb_env_config)::set(this, "env", "env_cfg", env_cfg);

    env = i2c_apb_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

endclass

`endif // I2C_APB_BASE_TEST_SV
