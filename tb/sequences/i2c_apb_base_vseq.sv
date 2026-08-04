/==============================================================================
// i2c_apb_base_vseq.sv
//
// Base virtual sequence - infrastructure only (objection handling + handles
// to both sequencers via p_sequencer). Scenario sequences extend this once
// the test list is provided; none are defined here per current instructions.
//==============================================================================
`ifndef I2C_APB_BASE_VSEQ_SV
`define I2C_APB_BASE_VSEQ_SV

class i2c_apb_base_vseq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(i2c_apb_base_vseq)
  `uvm_declare_p_sequencer(i2c_apb_virtual_sequencer)

  function new(string name = "i2c_apb_base_vseq");
    super.new(name);
  endfunction

  virtual task pre_body();
    if (starting_phase != null)
      starting_phase.raise_objection(this, get_type_name());
  endtask

  virtual task post_body();
    if (starting_phase != null)
      starting_phase.drop_objection(this, get_type_name());
  endtask

endclass
