//==============================================================================
// tb_top.sv
//
// TODO before this compiles/runs against your real DUT:
//   1. Replace `i2c_apb_ctrl` below with your actual DUT module name.
//   2. Confirm the APB VIP's BFM interface name/params (ADDRESS_WIDTH,
//      DATA_WIDTH, NO_OF_SLAVES) - placeholders below use 12, 32, 1 to
//      match the confirmed paddr[11:0]/pwdata[31:0] and a single-slave
//      system; adjust NO_OF_SLAVES if this DUT shares an APB bus with
//      other peripherals at SoC level.
//==============================================================================
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import i2c_agent_pkg::*;
  import i2c_apb_env_pkg::*;

  //--------------------------------------------------------------------------
  // Clock / Reset generation
  //--------------------------------------------------------------------------
  bit pclk;
  bit rst_n;

  // 100MHz per confirmed system clock frequency
  initial pclk = 0;
  always #5 pclk = ~pclk; // 10ns period -> 100MHz

  initial begin
    rst_n = 0;
    repeat (10) @(posedge pclk);
    rst_n = 1;
  end

  //--------------------------------------------------------------------------
  // APB VIP BFM interface instance
  // TODO: confirm exact parameter names/defaults against your VIP.
  //--------------------------------------------------------------------------
  apb_master_driver_bfm #(
    .ADDRESS_WIDTH(12),
    .DATA_WIDTH(32),
    .NO_OF_SLAVES(1)
  ) apb_master_driver_bfm_h (
    .pclk     (pclk),
    .preset_n (rst_n),
    .pready   (pready_w),
    .pslverr  (pslverr_w),
    .prdata   (prdata_w),
    .pprot    (pprot_w),
    .penable  (penable_w),
    .pwrite   (pwrite_w),
    .paddr    (paddr_w),
    .pselx    (pselx_w),
    .pwdata   (pwdata_w),
    .pstrb    (pstrb_w)
  );

  wire        pready_w;
  wire        pslverr_w;
  wire [31:0] prdata_w;
  wire [2:0]  pprot_w;
  wire        penable_w;
  wire        pwrite_w;
  wire [11:0] paddr_w;
  wire [0:0]  pselx_w;
  wire [31:0] pwdata_w;
  wire [3:0]  pstrb_w;

  //--------------------------------------------------------------------------
  // I2C bus interface instance
  //--------------------------------------------------------------------------
  i2c_if i2c_vif();

  //--------------------------------------------------------------------------
  // DUT instantiation
  // TODO: replace module name/port list with the actual DUT.
  //--------------------------------------------------------------------------
  i2c_apb_ctrl dut (
    .pclk    (pclk),
    .rst_n   (rst_n),
    .paddr   (paddr_w),
    .psel    (pselx_w[0]),
    .penable (penable_w),
    .pwrite  (pwrite_w),
    .pwdata  (pwdata_w),
    .prdata  (prdata_w),
    .pready  (pready_w),
    .pslverr (pslverr_w),

    .sda_in  (i2c_vif.dut_sda_in),
    .sda_out (i2c_vif.dut_sda_out),
    .sda_oe  (i2c_vif.dut_sda_oe),
    .scl_in  (i2c_vif.dut_scl_in),
    .scl_out (i2c_vif.dut_scl_out),
    .scl_oe  (i2c_vif.dut_scl_oe),

    .irq     (irq_w)
  );

  wire irq_w;

  //--------------------------------------------------------------------------
  // config_db handoff + run_test
  //--------------------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual apb_master_driver_bfm)::set(
      null, "*", "apb_master_driver_bfm", apb_master_driver_bfm_h);

    uvm_config_db#(virtual i2c_if)::set(
      null, "*", "i2c_vif", i2c_vif);

    run_test();
  end

endmodule
