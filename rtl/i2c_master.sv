`include "iic_defs.vh"

`timescale 1 ns / 1 ps

module iic_block (
  // APB4 Interface
  input  logic        pclk,
  input  logic        rst_n,          
  input  logic [11:0] paddr,
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,
  
  // IIC PAD Interface (Uni-directional)
  input  logic        sda_in,
  output logic        sda_out,
  output logic        sda_oe,
  input  logic        scl_in,
  output logic        scl_out,
  output logic        scl_oe,
  
  // Interrupt
  output logic        irq
);
    
  // =============================================================================
  // IIC State Machine 
  // =============================================================================
  typedef enum logic [2:0] {
    IDLE       = 3'b000,  // Idle state, waiting for commands
    START      = 3'b001,  // Generate start condition
    TX_ADDR    = 3'b010,  // Transmit address byte
    ACK_ADDR   = 3'b011,  // Wait for address ACK
    TX_DATA    = 3'b100,  // Transmit data byte
    RX_DATA    = 3'b101,  // Receive data byte
    ACK_PHASE  = 3'b110,  // Handle ACK/NACK (both send and receive)
    STOP       = 3'b111   // Generate stop condition
  } iic_state_t;
  
  // ACK phase sub-states for clear differentiation
  typedef enum logic [1:0] {
    ACK_WAIT_DATA,    // Waiting for data ACK from slave
    ACK_SEND_MASTER   // Sending ACK/NACK as master
  } ack_substate_t;
  
  // =============================================================================
  // Internal Registers and Signals
  // =============================================================================
  
  // APB Registers
  logic [31:0] ctrl_reg;
  logic [31:0] status_reg;
  logic [31:0] data_reg;
  logic [7:0]  addr_reg;
  logic [15:0] clkdiv_reg;
  logic [31:0] timeout_reg;      
  
  // Control Register Bit Fields
  logic start_cmd, stop_cmd, read_cmd, write_cmd;
  logic ack_en, auto_mode, iic_en;
  
  // Status Register Bit Fields
  logic busy, tip, nack_err, scl_timeout, sda_err;
  logic rxack;    
  
  // State Machine
  iic_state_t current_state, next_state;
  ack_substate_t ack_substate, next_ack_substate;
  
  // Clock Generation and Timing
  logic [15:0] clk_cnt;
  logic [1:0]  scl_phase;
  logic        scl_clk, scl_tick;
  logic [15:0] timing_cnt;
  logic        timing_met;
  logic        clock_stretched;         
  
  // Synchronizers and Edge Detection
  logic [2:0] sda_sync, scl_sync;
  logic       sda_in_sync, scl_in_sync;
  logic       sda_fall, sda_rise, scl_fall, scl_rise;
  
  // IIC Protocol Signals
  logic [7:0]  tx_data;
  logic [31:0] rx_data;
  logic [2:0]  bit_cnt;
  logic [31:0] timeout_cnt;      
  
  // Command Processing
  logic cmd_start, cmd_stop, cmd_read, cmd_write;
  logic cmd_clear, cmd_valid;
 
  // Byte Count , 2 Bit Write counter
  logic [1:0] counter;
  logic [1:0] byte_count;

  // Repeated Start bit
  logic apb_sr_bit;
  logic sr_bit;
  logic repeat_read;

  // Byte Count , 2 Bit Read counter
  logic [1:0] read_count;
  logic [1:0] read_counter;           
  
  // Automatic Mode Control
  logic auto_active;
  logic auto_read_phase;
  
  // Error Detection and Recovery
  logic error_detected;
  logic current_is_read_op;
  logic bus_stuck_timeout;       
  
  // =============================================================================
  // Input Synchronizers and Edge Detection (Noise Immunity)
  // =============================================================================
  
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      sda_sync <= 3'b111;
      scl_sync <= 3'b111;
    end else begin
      sda_sync <= {sda_sync[1:0], sda_in};
      scl_sync <= {scl_sync[1:0], scl_in};
    end
  end
  
  assign sda_in_sync = sda_sync[2];
  assign scl_in_sync = scl_sync[2];
  
  // Edge detection with debouncing for noise immunity
  assign sda_fall = (sda_sync[2:1] == 2'b10);
  assign sda_rise = (sda_sync[2:1] == 2'b01);
  assign scl_fall = (scl_sync[2:1] == 2'b10);
  assign scl_rise = (scl_sync[2:1] == 2'b01);
  
  // =============================================================================
  // APB4 Interface Logic with  Register Set
  // =============================================================================
  
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_reg     <= 32'h0;
      data_reg     <= 32'b0;
      apb_sr_bit   <= 1'b0;
      addr_reg     <= 8'b0;
      byte_count   <= 2'b0;
      clkdiv_reg   <= 16'd374; // Default for 100kHz
      timeout_reg  <= DEFAULT_TIMEOUT_CYCLES; 
      pslverr      <= 1'b0;
      read_count   <= 2'b00;
    end else begin
      // Clear command bits after execution starts
      if (cmd_clear) begin
        ctrl_reg[CTRL_WRITE_BIT:CTRL_START_BIT] <= 4'h0;
      end
      
      if (psel && penable && pwrite) begin
        case (paddr)
          CTRL_ADDR: begin
            ctrl_reg   <= pwdata;
          end
          DATA_ADDR: begin
            data_reg   <= pwdata[31:0];
          end
          ADDR_ADDR: begin
            addr_reg   <= pwdata[7:0];
  	    byte_count <= pwdata[31:30];          // No. of Bytes for Write : 2'b00- 1_byte,2'b01- 2_bytes,2'b10- 3_bytes and 2'b11- 4_bytes
  	    apb_sr_bit <= pwdata[29];             // Repeated Start Bit
  	    read_count <= pwdata[28:27];          // No. of Bytes for Read : 2'b00- 1_byte,2'b01- 2_bytes,2'b10- 3_bytes and 2'b11- 4_bytes
          end
          CLKDIV_ADDR: begin
            clkdiv_reg <= pwdata[15:0];
          end
          TIMEOUT_ADDR: begin 
            timeout_reg <= pwdata;
          end
          default: begin
            pslverr <= 1'b1;
          end
        endcase
      end
    end
  end
  
  // APB Read Logic 
  always_comb begin
  if (psel && penable && !pwrite) begin
    case (paddr)
      CTRL_ADDR   :  prdata  = ctrl_reg;
      STATUS_ADDR :  prdata  = status_reg;
      DATA_ADDR   :  prdata  = {rx_data};
      ADDR_ADDR   :  prdata  = {byte_count, apb_sr_bit, read_count, 19'h0, addr_reg};
      CLKDIV_ADDR :  prdata  = {16'h0, clkdiv_reg};
      IRQ_ADDR    :  prdata  = {31'h0, irq};
      TIMEOUT_ADDR:  prdata  = timeout_reg; 
      default     :  prdata  = 32'h0;
    endcase
  end
  else begin
  prdata = 32'h0;
  end
  end
  
  assign pready = 1'b1; // Always ready
  
  // =============================================================================
  // Control and Status Bit Extraction
  // =============================================================================
  assign start_cmd = ctrl_reg[CTRL_START_BIT];
  assign stop_cmd  = ctrl_reg[CTRL_STOP_BIT];
  assign read_cmd  = ctrl_reg[CTRL_READ_BIT];
  assign write_cmd = ctrl_reg[CTRL_WRITE_BIT];
  assign ack_en    = ctrl_reg[CTRL_ACK_EN_BIT];
  assign auto_mode = ctrl_reg[CTRL_AUTO_BIT];
  assign iic_en    = ctrl_reg[CTRL_IIC_EN_BIT];
  
  // status register assembly
  assign status_reg = {24'h0, rxack, 1'b0, sda_err, scl_timeout, 
                       nack_err, tip, 1'b0, busy};
  
  // =============================================================================
  // Command Detection and Processing
  // =============================================================================
  assign cmd_start = start_cmd && iic_en;
  assign cmd_stop  = stop_cmd && iic_en;
  assign cmd_read  = read_cmd && iic_en;
  assign cmd_write = write_cmd && iic_en;
  assign cmd_valid = cmd_start || cmd_stop || cmd_read || cmd_write;
  
  // =============================================================================
  // IIC Clock Generation with Clock Stretching Support
  // =============================================================================
  
  // Clock stretching detection: Master wants SCL high but slave holds it low
  assign clock_stretched = scl_oe && scl_out && !scl_in_sync;
  
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      clk_cnt   <= 16'h0;
      scl_phase <= 2'b00;
    end else if (iic_en && busy) begin
      // Clock stretching: FSM is paused while slave stretches clock
      if (clock_stretched) begin
        // Hold current state during stretching - FSM effectively paused
        clk_cnt <= clk_cnt; 
        scl_phase <= scl_phase; 
      end else if (clk_cnt == clkdiv_reg) begin
        clk_cnt   <= 16'h0;
        scl_phase <= scl_phase + 1'b1;
      end else begin
        clk_cnt <= clk_cnt + 1'b1;
      end
    end else begin
      clk_cnt   <= 16'h0;
      scl_phase <= 2'b00;
    end
  end
  
  assign scl_clk = scl_phase[1]; // SCL high during phases 2 and 3
  assign scl_tick = (clk_cnt == clkdiv_reg) && !clock_stretched; // FSM paused during stretch
  
  // =============================================================================
  // Timing Counter for Minimum High/Low Times
  // =============================================================================
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      timing_cnt <= 16'h0;
    end else if (current_state == START || current_state == STOP) begin
      if (scl_tick) begin
        timing_cnt <= timing_cnt + 1'b1;
      end
    end else begin
      timing_cnt <= 16'h0;
    end
  end
  
  assign timing_met = (timing_cnt >= 16'd4); // Minimum 4 clock phases for reliable conditions
  
  // =============================================================================
  //  Error Detection with Configurable Timeout
  // =============================================================================
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      timeout_cnt       <= 32'h0;
      scl_timeout       <= 1'b0;
      nack_err          <= 1'b0;
      sda_err           <= 1'b0;
      bus_stuck_timeout <= 1'b0;
    end else begin
      // Configurable timeout for clock stretching
      if (clock_stretched) begin
        if (timeout_cnt >= timeout_reg) begin
          scl_timeout <= 1'b1;
        end else begin
          timeout_cnt <= timeout_cnt + 1'b1;
        end
      end else begin
        timeout_cnt <= 32'h0;
      end
      
      // Bus stuck detection - if bus is held indefinitely
      if (busy && !clock_stretched && !scl_in_sync && timeout_cnt >= timeout_reg) begin
        bus_stuck_timeout <= 1'b1;
      end
      
      // NACK error detection - only for receiving ACK states
      if (current_state == ACK_ADDR || 
        (current_state == ACK_PHASE && ack_substate == ACK_WAIT_DATA)) begin
        if (scl_tick && scl_phase == 2'b11) begin
          nack_err <= sda_in_sync; // NACK = 1
        end
      end
      
      // SDA stuck error during STOP condition
      if (current_state == STOP && timing_met && scl_phase == 2'b11) begin
        if (!sda_in_sync) begin
          sda_err <= 1'b1; // SDA should be high after STOP
        end
      end
      
      // Clear errors on new transaction start
      if (current_state == IDLE && next_state == START) begin
        scl_timeout       <= 1'b0;
        nack_err          <= 1'b0;
        sda_err           <= 1'b0;
        bus_stuck_timeout <= 1'b0;
      end
    end
  end
  
  assign error_detected = scl_timeout || sda_err || bus_stuck_timeout;
  
  // =============================================================================
  // IIC State Machine 
  // =============================================================================
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= IDLE;
      ack_substate <= ACK_WAIT_DATA;
    end else begin
      current_state <= next_state;
      ack_substate <= next_ack_substate;
    end
  end
  
  always_comb begin
    next_state = current_state;
    next_ack_substate = ack_substate;
    
    unique case (current_state)
      IDLE: begin
              // Wait for start command or automatic mode activation
              if (cmd_start) begin
                next_state = START; // Begin IIC transaction
              end
              // Remain in IDLE until valid command received
            end
      START: begin
               // Generate start condition (SDA high?low while SCL high)
               if (scl_tick && scl_phase == 2'b11) begin
                 next_state = TX_ADDR; 
               end else if (error_detected) begin
                 next_state = IDLE; 
               end
               // Wait for start condition timing to be satisfied
             end
      TX_ADDR: begin
                 // Transmit 8-bit address (7-bit address + R/W bit)
                 if (scl_tick && scl_phase == 2'b11 && bit_cnt == 3'd7) begin
                   next_state = ACK_ADDR; // All address bits sent, wait for ACK
                 end else if (error_detected) begin
                   next_state = STOP;
                 end
                 // Continue transmitting address bits
               end
      ACK_ADDR: begin
                  // Wait for slave to acknowledge address
                  if (scl_tick && scl_phase == 2'b11) begin
                    if (!sda_in_sync) begin // ACK received (SDA pulled low by slave)
                      if (current_is_read_op) begin
                        next_state = RX_DATA; // Address ACK'd for read, start receiving data
                      end else begin
                        next_state = TX_DATA; // Address ACK'd for write, start sending data
                      end
                    end else begin // NACK received (SDA remains high)
                      next_state = STOP; // Slave didn't ACK address, terminate transaction
                    end
                  end else if (error_detected) begin
                    next_state = STOP; // Abort on error (timeout, etc.)
                  end
                  // Wait for ACK/NACK from slave
                end
      TX_DATA: begin
                 // Transmit 8-bit data to slave
                 if (scl_tick && scl_phase == 2'b11 && bit_cnt == 3'd7) begin
                   next_state = ACK_PHASE; // All data bits sent, wait for data ACK
                   next_ack_substate = ACK_WAIT_DATA;
                 end else if (error_detected) begin
                   next_state = STOP; // Abort on error during data transmission
                 end
                 // Continue transmitting data bits
               end
      RX_DATA: begin
                 // Receive 8-bit data from slave
                 if (scl_tick && scl_phase == 2'b11 && bit_cnt == 3'd7) begin
                     next_state = ACK_PHASE; // All data bits received, send ACK/NACK to slave
                     next_ack_substate = ACK_SEND_MASTER;
                 end else if (error_detected) begin
                     next_state = STOP; // Abort on error during data reception
                 end
                 // Continue receiving data bits
               end
      ACK_PHASE: begin
                   if (scl_tick && scl_phase == 2'b11 && (apb_sr_bit) && sr_bit && (~current_is_read_op)) begin
                     if ((counter == 2'b11)) begin
                       next_state = START; // Complete transaction with stop condition
                     end else begin
                       next_state = TX_DATA; 
                     end
                   end
                   // Handle ACK/NACK phase (both send and receive)
                   if (scl_tick && scl_phase == 2'b11 && (~apb_sr_bit) && (~current_is_read_op)) begin
                     if ((auto_active || cmd_stop || error_detected) && (counter == 2'b11)) begin
                       next_state = STOP; // Complete transaction with stop condition
                     end else begin
                       next_state = TX_DATA;
                     end
                   end else if (scl_tick && scl_phase == 2'b11 && sr_bit && counter < 2'b11) begin
                     next_state = TX_DATA;    
                   end else if (scl_tick && scl_phase == 2'b11 && sr_bit) begin
                     next_state = START;    
                   end else if (scl_tick && scl_phase == 2'b11 && (read_counter < 2'b11)) begin
                     next_state = RX_DATA;
                   end else if (scl_tick && scl_phase == 2'b11) begin
                     next_state = STOP;
                   end
                   // Wait for ACK phase to complete
                 end
      STOP: begin
              // Generate stop condition (SDA low?high while SCL high)
              if (scl_tick && scl_phase == 2'b01 && timing_met) begin
                next_state = IDLE; // Stop condition complete, return to idle
              end
              // Wait for stop condition timing to be satisfied
            end
      
      default: next_state = IDLE; // Safe default state
    endcase
  end

  // ============================================================================
  // Write Byte Counter
  // ============================================================================
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      counter <= 2'b0;
    end else if (current_state == IDLE && next_state ==START) begin
      counter <= byte_count;
    end else if (current_state == TX_DATA && next_state == ACK_PHASE) begin 
      counter <= counter - 1'b1;        
    end
  end

  // ============================================================================
  // Read Byte Counter
  // ============================================================================
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      read_counter <= 2'b0;
    end else if (current_state == IDLE && next_state == START) begin
      read_counter <= read_count + 2'b11;
    end else if (current_state == ACK_PHASE && next_state == RX_DATA) begin 
      read_counter <= read_counter - 1'b1;        
    end
  end

  // =============================================================================
  // Bit Counter for Address and Data Transmission/Reception
  // =============================================================================
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      bit_cnt <= 3'h0;
    end else begin
      if (current_state == TX_ADDR || current_state == TX_DATA || 
          current_state == RX_DATA) begin
        if (scl_tick && scl_phase == 2'b11) begin
          bit_cnt <= bit_cnt + 1'b1; // Increment on falling edge
        end
      end else begin
        bit_cnt <= 3'h0; // Reset between bytes
      end
    end
  end
  
  // =============================================================================
  // TX/RX Data Handling 
  // =============================================================================

  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      tx_data            <= 8'h0;
      rx_data            <= 8'h0;
      current_is_read_op <= 1'b0;
      sr_bit             <= 1'b0;
      repeat_read        <= 1'b0;
    end else begin
          
        // Load address/command at start of transaction
      if (current_state == IDLE && next_state == START) begin
          // Load from registers
          tx_data            <= {addr_reg[7:1], read_cmd};
          current_is_read_op <= read_cmd;
      end
       
      // Read operation for Repeated Start : sr_bit == 1'b1
      if (current_state == ACK_PHASE && next_state == START) begin
        current_is_read_op <= 1'b1;
        sr_bit             <= 0;
      end
     
      if (current_state == IDLE && next_state == START && apb_sr_bit) begin
        sr_bit      <= apb_sr_bit;
        repeat_read <= ~apb_sr_bit;
      end

      if (current_state == ACK_PHASE && next_state == START && apb_sr_bit) begin
        tx_data <= addr_reg + 1'b1; 
      end

      // Load 1st Byte for transmission
      if (current_state == ACK_ADDR && next_state == TX_DATA) begin
        tx_data <= data_reg[7:0];              // 1-byte data transfer
      end
       
      // Load 3 more bytes for transmission
      if (current_state == ACK_PHASE && next_state == TX_DATA) begin
       case (byte_count)
         2'b11: begin                          // 4-byte data transfer
           case (counter)
             2'b00: tx_data <= data_reg[31:24];
             2'b01: tx_data <= data_reg[23:16];
             2'b10: tx_data <= data_reg[15:8];
             default: ; // no action
           endcase
         end
         2'b10: begin                          // 3-byte data transfer
           case (counter)
             2'b01: tx_data <= data_reg[15:8];
             2'b00: tx_data <= data_reg[23:16];
             default: ;
           endcase
         end
         2'b01: begin                          // 2-byte data transfer
           case (counter)
             2'b00: tx_data <= data_reg[15:8];
             default: ;
           endcase
         end
         default: ; // no action for other byte_count values
       endcase
      end         

      // Capturing Received Data from SDA in Read operation
      if (current_state == RX_DATA) begin
       if (scl_tick && scl_phase == 2'b11) begin
         case (read_count)
          2'b11: begin                         // 4-byte data capture
            case (read_counter)
              2'b10 : rx_data[7:0]   <= {rx_data[6:0], sda_in_sync};
              2'b01 : rx_data[15:8]  <= {rx_data[14:8], sda_in_sync};
              2'b00 : rx_data[23:16] <= {rx_data[22:16], sda_in_sync};
              2'b11 : rx_data[31:24] <= {rx_data[30:24], sda_in_sync};
              default: ;
             endcase
             end
          2'b10: begin                         // 3-byte data capture
            case (read_counter)
              2'b01 : rx_data[7:0]   <= {rx_data[6:0], sda_in_sync};
              2'b00 : rx_data[15:8]  <= {rx_data[14:8], sda_in_sync};
              2'b11 : rx_data[23:16] <= {rx_data[22:16], sda_in_sync};
              default: ;
            endcase
          end
          2'b01: begin                         // 2-byte data capture
           case (read_counter)
             2'b00 : rx_data[7:0]   <= {rx_data[6:0], sda_in_sync};
             2'b11 : rx_data[15:8]  <= {rx_data[14:8], sda_in_sync};
             default: ;
           endcase
          end
          2'b00: begin                         // 1-byte data capture
           case (read_counter)
             2'b11 : rx_data[7:0]  <= {rx_data[6:0], sda_in_sync};
             default: ;
           endcase
          end
         default: ;
       endcase
       end
      end
    end
  end
  
  // =============================================================================
  // Automatic Mode Control
  // =============================================================================
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n)begin
      auto_active <= 1'b0;
    end else begin
      if (auto_mode && current_state == IDLE) begin
        auto_active <= 1'b1; // Activate automatic mode
      end else if (current_state == STOP && next_state == IDLE) begin
        auto_active <= 1'b0; // Deactivate after transaction complete
      end
    end
  end
    
  // =============================================================================
  // IIC Signal Generation with Proper Tri-State Control
  // =============================================================================
  always_comb begin
    sda_out = 1'b1;
    sda_oe  = 1'b0;
    scl_out = 1'b1;
    scl_oe  = 1'b0;
    
    unique case (current_state)
      START: begin
        // Generate start condition
        scl_oe  = 1'b1;
        scl_out = 1'b1;
        sda_oe  = 1'b1;
        if (scl_phase < 2'b01) begin
          sda_out = 1'b1; // SDA high initially
        end else begin
          sda_out = 1'b0; // Pull SDA low for start condition
        end
      end

      TX_ADDR, TX_DATA: begin
        // Transmit address or data bits
        scl_oe  = 1'b1;
        scl_out = scl_clk;
        sda_oe  = 1'b1;
        sda_out = tx_data[7-bit_cnt]; // Output current bit
      end
      
      ACK_ADDR: begin
        // Release SDA for slave ACK
        scl_oe  = 1'b1;
        scl_out = scl_clk;
        sda_oe  = 1'b0; // Release SDA for slave to pull low (ACK)
      end
      
      RX_DATA: begin
        // Release SDA for slave data transmission
        scl_oe  = 1'b1;
        scl_out = scl_clk;
        sda_oe  = 1'b0; // Release SDA for slave to drive
      end

      ACK_PHASE: begin                                                        
        // Handle ACK/NACK phase
        scl_oe  = 1'b1;
        scl_out = scl_clk;
	    if (ack_substate == ACK_SEND_MASTER) begin
	      if (read_counter < 2'b11 && apb_sr_bit && current_is_read_op) begin
              sda_oe  = 1'b1;
	      sda_out = 1'b0;
              end else if (read_counter < 2'b11 && current_is_read_op) begin
              sda_oe  = 1'b1;
	      sda_out = 1'b0;
	      end else begin
              sda_oe = 1'b0;             // NACK for last byte read operation
  	      end
	     end else begin
              sda_oe = 1'b0; // Release SDA for slave ACK
             end
      end

      STOP: begin
        // Generate stop condition
        scl_oe  = 1'b1;
        scl_out = scl_clk;
        sda_oe  = 1'b1;
        if (timing_cnt < 16'd3) begin
          sda_out = 1'b0; // SDA low initially
        end else begin
          sda_out = 1'b1; 
	  scl_out = 1'b1;
        end
      end
          
      default: begin
        // High-impedance when idle
        sda_oe = 1'b0;
        scl_oe = 1'b0;
      end
    endcase
  end
  
  // =============================================================================
  // Status Signals and Flags
  // =============================================================================
  assign busy = (current_state != IDLE);
  assign tip  = (current_state == TX_ADDR || current_state == TX_DATA || 
                 current_state == RX_DATA);
  
  // Received ACK detection
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      rxack <= 1'b0;
    end else if (current_state == ACK_ADDR || 
                 (current_state == ACK_PHASE && ack_substate == ACK_WAIT_DATA)) begin
      if (scl_tick && scl_phase == 2'b11) begin
        rxack <= sda_in_sync; // Sample ACK/NACK
      end
    end
  end
  
  // Command clear logic
  assign cmd_clear = (current_state == IDLE && next_state == START);
  
  // interrupt generation with error conditions
  always_ff @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      irq <= 1'b0;
    end
    else if ((current_state != IDLE && next_state == IDLE) || error_detected) begin
      irq <= 1'b1;
    end
    else if (paddr[11:0] == IRQ_ADDR && psel && penable && !pwrite) begin
      irq <= 1'b0;
    end
    end


endmodule
