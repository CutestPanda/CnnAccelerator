`ifndef __PANDA_PKG_H
`define __PANDA_PKG_H

package panda_pkg;
	`include "uvm_macros.svh"
	`include "tue_macros.svh"
	
	import uvm_pkg::*;
	import tue_pkg::*;
	
	typedef virtual panda_clock_if panda_clock_vif;
	typedef virtual panda_reset_if panda_reset_vif;
	typedef virtual panda_icb_if panda_icb_vif;
	typedef virtual panda_axis_if panda_axis_vif;
	
	`include "panda_defines.svh"
	`include "panda_macros.svh"
	
	`include "panda_configuration.svh"
	`include "panda_memory.svh"
	`include "panda_status.svh"
	`include "panda_transaction.svh"
	
	`include "panda_sequencer.svh"
	`include "panda_monitor.svh"
	`include "panda_driver.svh"
	`include "panda_agent.svh"
	
	`include "panda_test_base.svh"
	
	`include "panda_default_sequence.svh"
	
endpackage

`endif
