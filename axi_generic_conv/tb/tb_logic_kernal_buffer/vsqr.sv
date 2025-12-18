`timescale 1ns / 1ps

`ifndef __VSQR_H

`define __VSQR_H

`include "transactions.sv"
`include "sequencers.sv"

class LogicKernalBufferVsqr #(
	integer ATOMIC_C = 4 // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
)extends uvm_sequencer;
	
	AXISSequencer #(.data_width(ATOMIC_C*2*8), .user_width(15)) m_in_cgrp_axis_sqr; // 输入通道组数据流AXIS主机
	AXISSequencer #(.data_width(32), .user_width(0)) m_rd_req_axis_sqr; // 权重块读请求AXIS主机
	
	`uvm_component_param_utils(LogicKernalBufferVsqr #(.ATOMIC_C(ATOMIC_C)))
	
	function new(string name = "LogicKernalBufferVsqr", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
	
`endif
