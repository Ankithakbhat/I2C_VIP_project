//==============================================================================
// i2c_if.sv
//
// Physical I2C bus interface. Models SDA/SCL as real tri-state (wired-AND)
// nets with pull-ups, matching genuine open-drain bus behavior.
//
// MODELING ASSUMPTION (confirm against RTL): the DUT's *_oe/*_out pair is
// interpreted as true open-drain pad behavior:
//   oe=1, out=0  -> actively pulled low
//   oe=1, out=1  -> released (attempting to float high)
//   oe=0         -> released
// This is consistent with the confirmed clock-stretch condition
// (scl_oe && scl_out && !scl_in): DUT wants SCL released/high but reads
// back low because an external device (modeled by the I2C agent) is still
// holding it low.
//==============================================================================
interface i2c_if;

  wire sda;
  wire scl;

  // Pull-ups model the idle-high open-drain bus.
  pullup(sda);
  pullup(scl);

  //--------------------------------------------------------------------------
  // DUT-side connections - wire these to the DUT's sda_in/sda_out/sda_oe and
  // scl_in/scl_out/scl_oe ports in tb_top.sv
  //--------------------------------------------------------------------------
  logic dut_sda_out, dut_sda_oe;
  logic dut_scl_out, dut_scl_oe;
  logic dut_sda_in;   // drive this into the DUT's sda_in port
  logic dut_scl_in;   // drive this into the DUT's scl_in port

  assign sda        = dut_sda_oe ? (dut_sda_out ? 1'bz : 1'b0) : 1'bz;
  assign scl        = dut_scl_oe ? (dut_scl_out ? 1'bz : 1'b0) : 1'bz;
  assign dut_sda_in = sda;
  assign dut_scl_in = scl;

  //--------------------------------------------------------------------------
  // I2C agent (slave-emulation) side connections - driven by i2c_driver.sv
  //--------------------------------------------------------------------------
  logic agt_sda_out, agt_sda_oe;
  logic agt_scl_out, agt_scl_oe;  // scl drive only used for clock stretching

  assign sda = agt_sda_oe ? (agt_sda_out ? 1'bz : 1'b0) : 1'bz;
  assign scl = agt_scl_oe ? (agt_scl_out ? 1'bz : 1'b0) : 1'bz;

  //--------------------------------------------------------------------------
  // Convenience tasks used by driver/monitor - centralizes bit-level bus
  // primitives so timing fixes only need to happen in one place.
  //--------------------------------------------------------------------------

  // Release (tri-state) the agent's drive of both lines.
  task automatic agt_release_all();
    agt_sda_oe <= 1'b0;
    agt_scl_oe <= 1'b0;
  endtask

  // Drive SDA low (agent) - used for ACK / data-bit-0 / START/STOP shaping
  task automatic agt_drive_sda(bit val);
    agt_sda_oe  <= 1'b1;
    agt_sda_out <= val;
  endtask

  task automatic agt_release_sda();
    agt_sda_oe <= 1'b0;
  endtask

  // Hold SCL low - used for clock-stretching injection
  task automatic agt_stretch_scl();
    agt_scl_oe  <= 1'b1;
    agt_scl_out <= 1'b0;
  endtask

  task automatic agt_release_scl();
    agt_scl_oe <= 1'b0;
  endtask

  initial begin
    agt_sda_oe = 1'b0;
    agt_scl_oe = 1'b0;
  end

endinterface : i2c_if
