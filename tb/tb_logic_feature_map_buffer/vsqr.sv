`timescale 1ns / 1ps

`ifndef __VSQR_H

`define __VSQR_H

`include "transactions.sv"
`include "sequencers.sv"

class LogicFmapBufferVsqr #(
	integer ATOMIC_C = 4 // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
)extends uvm_sequencer;
	
	AXISSequencer #(.data_width(ATOMIC_C*2*8), .user_width(22)) m_fin_axis_sqr; // 特征图表面行数据输入AXIS主机
	AXISSequencer #(.data_width(40), .user_width(0)) m_rd_req_axis_sqr; // 特征图表面行读请求AXIS主机
	
	ReqAckSequencer #(.req_payload_width(0), .resp_payload_width(0)) rst_buf_sqr; // 重置缓存REQ-ACK主机
	ReqAckSequencer #(.req_payload_width(10), .resp_payload_width(0)) sfc_row_rplc_sqr; // 表面行置换REQ-ACK主机
	ReqAckSequencer #(.req_payload_width(12), .resp_payload_width(0)) sfc_row_search_sqr; // 表面行检索REQ-ACK主机
	
	`uvm_component_param_utils(LogicFmapBufferVsqr #(.ATOMIC_C(ATOMIC_C)))
	
	function new(string name = "LogicFmapBufferVsqr", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
	
`endif
