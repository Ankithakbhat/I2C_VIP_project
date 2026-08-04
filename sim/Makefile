###############################################################################
#                         I2C UVM MAKEFILE
###############################################################################

.SILENT:
compile
simulate
gui
regression
clean
usage

###############################################################################
# Variables
###############################################################################

TOP      = tb_top
WORK     = work
FLIST    = i2c_compile.f

TESTS = \
	test_sanity_reset \
	test_manual_mode_matrix \
	test_auto_mode_matrix \
	test_reactive_exceptions \
	test_interrupt_standalone \
	test_error_recovery_stress

ifndef test
override test = test_sanity_reset
endif

ifndef seed
override seed = random
endif

ifndef verbosity
override verbosity = UVM_MEDIUM
endif

LOGDIR = logs/$(test)

###############################################################################
# Usage
###############################################################################

usage:
	echo ""
	echo "=============== I2C UVM REGRESSION FLOW ==============="
	echo ""
	echo "Compile"
	echo "  make compile"
	echo ""
	echo "Run Single Test"
	echo "  make simulate test=test_sanity_reset"
	echo ""
	echo "Run GUI"
	echo "  make gui test=test_manual_mode_matrix"
	echo ""
	echo "Run With Seed"
	echo "  make simulate test=test_auto_mode_matrix seed=100"
	echo ""
	echo "Run Full Regression"
	echo "  make regression"
	echo ""
	echo "Clean"
	echo "  make clean"
	echo ""

###############################################################################
# Compile
###############################################################################

compile:

	make clean_compile

	mkdir -p logs

	vlib $(WORK)

	vlog \
	-sv \
	+acc \
	-mfcu \
	-timescale 1ns/1ps \
	+cover=bcesft \
	+fcover \
	-f $(FLIST) \
	-l compile.log

	make compile_report

###############################################################################
# Single Test Run
###############################################################################

simulate:

	mkdir -p $(LOGDIR)

	vsim \
	work.$(TOP) \
	-c \
	-sva \
	-coverage \
	-voptargs=+acc \
	+UVM_TESTNAME=$(test) \
	+UVM_VERBOSITY=$(verbosity) \
	-sv_seed $(seed) \
	-l $(LOGDIR)/run.log \
	-wlf $(LOGDIR)/waveform.wlf \
	-do "run -all; \
	     coverage save $(LOGDIR)/coverage.ucdb; \
	     quit -f"

	make sim_report

	vcover report \
	-html \
	$(LOGDIR)/coverage.ucdb \
	-htmldir $(LOGDIR)/coverage_html

###############################################################################
# GUI
###############################################################################

gui:

	vsim \
	work.$(TOP) \
	-coverage \
	+UVM_TESTNAME=$(test) \
	+UVM_VERBOSITY=$(verbosity)

###############################################################################
# Regression
###############################################################################

regression:

	make compile

	for t in $(TESTS); do \
		echo ""; \
		echo "===================================="; \
		echo "Running $$t"; \
		echo "===================================="; \
		$(MAKE) simulate test=$$t; \
	done

	make merge_cov

###############################################################################
# Coverage Merge
###############################################################################

merge_cov:

	rm -rf merged_cov.ucdb
	rm -rf merged_cov_html

	vcover merge \
	merged_cov.ucdb \
	logs/*/coverage.ucdb

	vcover report \
	-html \
	merged_cov.ucdb \
	-htmldir merged_cov_html

	echo ""
	echo "Merged Coverage Generated"
	echo "merged_cov_html/index.html"
	echo ""

###############################################################################
# Compile Report
###############################################################################

compile_report:

	echo ""
	echo "========== COMPILE REPORT =========="
	echo ""

	grep -i error compile.log

	echo ""

	grep -i warning compile.log

	echo ""

###############################################################################
# Simulation Report
###############################################################################

sim_report:

	echo ""
	echo "========== SIMULATION REPORT =========="
	echo ""

	echo "UVM_FATAL"
	grep UVM_FATAL $(LOGDIR)/run.log

	echo ""

	echo "UVM_ERROR"
	grep UVM_ERROR $(LOGDIR)/run.log

	echo ""

	echo "UVM_WARNING"
	grep UVM_WARNING $(LOGDIR)/run.log

	echo ""

	echo "Log File:"
	echo "$(LOGDIR)/run.log"

	echo ""

	echo "Waveform:"
	echo "vsim -view $(LOGDIR)/waveform.wlf"

	echo ""

###############################################################################
# Cleaning
###############################################################################

clean_compile:

	rm -rf work
	rm -rf transcript
	rm -rf compile.log

clean:

	make clean_compile

	rm -rf logs
	rm -rf merged_cov.ucdb
	rm -rf merged_cov_html

	echo "Cleanup Complete"

###############################################################################
# Test Mapping
###############################################################################
#
# test_sanity_reset
#   TC1  Reset Verification
#   TC2  Register Read/Write
#
# test_manual_mode_matrix
#   TC3  START
#   TC4  STOP
#   TC5  Address
#   TC6  Single Byte Write
#   TC7  Single Byte Read
#   TC10 ACK
#   TC18 BUSY
#   TC19 TIP
#   TC20 RXACK
#   TC23 Command Auto Clear
#   TC24 FSM Verification
#   TC25 Manual Mode Delay Stress
#
# test_auto_mode_matrix
#   TC8  Multi-byte Write
#   TC9  Multi-byte Read
#   TC12 Repeated START
#   TC13 Clock Divider
#   TC21 Automatic Mode
#
# test_reactive_exceptions
#   TC11 NACK
#   TC14 Clock Stretching
#   TC15 Timeout
#
# test_interrupt_standalone
#   TC17 Interrupt Verification
#
# test_error_recovery_stress
#   TC16 SDA Error
#   TC22 Error Recovery
#
###############################################################################
