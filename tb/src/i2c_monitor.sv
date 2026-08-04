//==============================================================================
// i2c_monitor.sv
// Passive monitor - decodes START/ADDR/ACK/DATA/STOP off the physical bus
// and publishes the observed transaction via analysis port.
//==============================================================================
`ifndef I2C_MONITOR_SV
`define I2C_MONITOR_SV

class i2c_monitor extends uvm_monitor;
  `uvm_component_utils(i2c_monitor)

  virtual i2c_if vif;
  i2c_config     cfg;

  uvm_analysis_port #(i2c_transaction) item_collected_port;

  function new(string name = "i2c_monitor", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(i2c_config)::get(this, "", "i2c_config", cfg))
      `uvm_fatal("NOCFG", "i2c_config not found in config_db")
    vif = cfg.vif;
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      collect_one_transaction();
    end
  endtask

  task automatic wait_for_start();
    forever begin
      @(negedge vif.sda);
      if (vif.scl === 1'b1) break;
    end
  endtask

  task automatic sample_byte(output bit [7:0] byte_val);
    for (int i = 7; i >= 0; i--) begin
      @(posedge vif.scl);
      byte_val[i] = vif.sda;
    end
  endtask

  task automatic sample_ack(output bit is_ack);
    @(posedge vif.scl);
    is_ack = (vif.sda === 1'b0);
  endtask

  // Returns 1 if a STOP condition is seen, 0 if a repeated START is seen instead
  task automatic wait_for_stop_or_rstart(output bit stop_seen);
    fork
      begin : stop_watch
        forever begin
          @(posedge vif.sda);
          if (vif.scl === 1'b1) begin
            stop_seen = 1;
            disable rstart_watch;
            break;
          end
        end
      end
      begin : rstart_watch
        forever begin
          @(negedge vif.sda);
          if (vif.scl === 1'b1) begin
            stop_seen = 0;
            disable stop_watch;
            break;
          end
        end
      end
    join
  endtask

  task automatic collect_one_transaction();
    i2c_transaction tr;
    bit [7:0] addr_byte;
    bit       ack;
    bit       stop_seen;

    tr = i2c_transaction::type_id::create("tr");

    wait_for_start();
    sample_byte(addr_byte);
    tr.slave_addr = addr_byte[7:1];
    tr.dir        = i2c_dir_e'(addr_byte[0]);

    sample_ack(ack);
    tr.addr_ack_rcvd = ack;

    if (!ack) begin
      // Address NACK'd - transaction ends here (master should STOP)
      tr.observed_error = I2C_ERR_ADDR_NACK;
      item_collected_port.write(tr);
      return;
    end

    tr.num_bytes = 0;
    for (int b = 0; b < 4; b++) begin
      bit [7:0] data_byte;
      bit       data_ack;
      bit       more_expected;

      sample_byte(data_byte);
      if (tr.dir == I2C_WRITE) tr.rd_data[b] = data_byte;
      else                     tr.wr_data[b] = data_byte;

      sample_ack(data_ack);
      tr.data_ack_rcvd[b] = data_ack;
      tr.num_bytes = b + 1;

      if (!data_ack) begin
        if (tr.dir == I2C_WRITE) tr.observed_error = I2C_ERR_DATA_NACK;
        break;
      end

      // Peek ahead: does another data byte follow, or STOP/repeated-START?
      // A simple heuristic: check bus state at next SCL low-to-high edge -
      // if a START/STOP condition occurs before the next bit's SCL edge, stop.
      // (Left intentionally simple; refine once byte-count framing is
      // cross-checked against the TXN_CTL register value in the scoreboard.)
      more_expected = (b < 3);
      if (!more_expected) break;
    end

    wait_for_stop_or_rstart(stop_seen);
    tr.repeat_start = !stop_seen;

    item_collected_port.write(tr);
  endtask

endclass

`endif // I2C_MONITOR_SV
