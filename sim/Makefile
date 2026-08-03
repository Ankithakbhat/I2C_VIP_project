###############################################################################
#                         I2C VIP MAKEFILE
###############################################################################

###############################################################################
# Silent Mode
###############################################################################

.SILENT:
compile
simulate
regression
usage
clean

###############################################################################
# Ignore Errors
###############################################################################

.IGNORE:
compile
simulate

###############################################################################
# Default Variables
###############################################################################

TOP              = tb_top
WORK             = work
FLIST            = i2c_compile.f

ifndef test
override test = test_sanity_reset
endif

ifndef seed
override seed = random
endif

ifndef uvm_verbosity
override uvm_verbosity = UVM_MEDIUM
endif

ifndef test_folder
override test_folder = logs/$(test)
endif

ifndef regression_list
override regression_list = full.list
endif

###############################################################################
# Usage
###############################################################################

usage:

	echo ""
	echo "============================================================"
	echo "                    I2C VIP MAKEFILE"
	echo "============================================================"
	echo ""
	echo "Compile"
	echo "    make compile"
	echo ""
	echo "Run Single Test"
	echo "    make simulate test=test_sanity_reset"
	echo ""
	echo "Run GUI"
	echo "    make gui test=test_sanity_reset"
	echo ""
	echo "Run Regression"
	echo "    make regression"
	echo ""
	echo "Run Smoke Regression"
	echo "    make regression regression_list=smoke.list"
	echo ""
	echo "Run with Seed"
	echo "    make simulate test=test_sanity_reset seed=10"
	echo ""
	echo "Clean"
	echo "    make clean"
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
	+cover=bcesft \
	+fcover \
	-mfcu \
	-timescale 1ns/1ps \
	-f $(FLIST) \
	-l compile.log

	make compile_report

###############################################################################
# Simulation
###############################################################################

simulate:

	mkdir -p $(test_folder)

	vsim \
	work.$(TOP) \
	-voptargs=+acc=npr \
	-sva \
	-coverage \
	+UVM_TESTNAME=$(test) \
	+UVM_VERBOSITY=$(uvm_verbosity) \
	-sv_seed $(seed) \
	-l $(test_folder)/run.log \
	-wlf $(test_folder)/waveform.wlf \
	-c \
	-do "run -all; \
	     coverage save $(test_folder)/coverage.ucdb; \
	     quit -f"

	make sim_report

	vcover report \
	-html \
	$(test_folder)/coverage.ucdb \
	-htmldir $(test_folder)/coverage_html

###############################################################################
# GUI
###############################################################################

gui:

	vsim \
	work.$(TOP) \
	+UVM_TESTNAME=$(test) \
	+UVM_VERBOSITY=$(uvm_verbosity)

###############################################################################
# Regression
###############################################################################

regression:

	make compile

	python3 regression.py $(regression_list)

	make merge_cov

###############################################################################
# Merge Coverage
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
	echo "Merged Coverage Report"
	echo "firefox merged_cov_html/index.html &"

###############################################################################
# Cleaning
###############################################################################

clean_compile:

	rm -rf work
	rm -rf compile.log
	rm -rf transcript

clean:

	make clean_compile
	rm -rf logs
	rm -rf merged_cov.ucdb
	rm -rf merged_cov_html

###############################################################################
# Compile Report
###############################################################################

compile_report:

	echo ""
	echo "================ Compilation Report ================="

	grep "Error" compile.log

	echo ""

	grep "Warning" compile.log

	echo ""

###############################################################################
# Simulation Report
###############################################################################

sim_report:

	echo ""
	echo "================ Simulation Report ================="

	echo ""

	echo "UVM_FATAL"
	grep UVM_FATAL $(test_folder)/run.log

	echo ""

	echo "UVM_ERROR"
	grep UVM_ERROR $(test_folder)/run.log

	echo ""

	echo "UVM_WARNING"
	grep UVM_WARNING $(test_folder)/run.log

	echo ""

	echo "Log File"
	echo "$(test_folder)/run.log"

	echo ""

	echo "Waveform"
	echo "vsim -view $(test_folder)/waveform.wlf &"

	echo ""

	echo "Coverage"
	echo "firefox $(test_folder)/coverage_html/index.html &"
