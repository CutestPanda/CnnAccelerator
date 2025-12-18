`timescale 1ns / 1ps

`ifndef __VSQR_H

`define __VSQR_H

`include "transactions.sv"
`include "sequencers.sv"

class ConvBufferVsqr #(
	integer ATOMIC_C = 4 // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
)extends uvm_sequencer;
	
	ICBSequencer #(.addr_width(32), .data_width(ATOMIC_C*2*8)) m0_fmbuf_icb_sqr; // 特征图缓存ICB主机#0
	ICBSequencer #(.addr_width(32), .data_width(ATOMIC_C*2*8)) m1_fmbuf_icb_sqr; // 特征图缓存ICB主机#1
	ICBSequencer #(.addr_width(32), .data_width(ATOMIC_C*2*8)) m0_kbuf_icb_sqr; // 卷积核缓存ICB主机#0
	ICBSequencer #(.addr_width(32), .data_width(ATOMIC_C*2*8)) m1_kbuf_icb_sqr; // 卷积核缓存ICB主机#1
	
	`uvm_component_param_utils(ConvBufferVsqr #(.ATOMIC_C(ATOMIC_C)))
	
	function new(string name = "ConvBufferVsqr", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
	
`endif
