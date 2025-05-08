`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"
`include "vsqr.sv"

/** 环境:(逻辑)卷积核缓存 **/
class LogicKernalBufferEnv #(
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	real simulation_delay = 1 // 仿真延时
)extends uvm_env;
	
	// 虚拟Sequencer
	LogicKernalBufferVsqr #(.ATOMIC_C(ATOMIC_C)) vsqr;
	
	// 组件
	local AXISMasterAgent #(.out_drive_t(simulation_delay), 
		.data_width(ATOMIC_C*2*8), .user_width(11)) m_in_cgrp_axis_agt; // 输入通道组数据流AXIS主机代理
	local AXISMasterAgent #(.out_drive_t(simulation_delay), 
		.data_width(24), .user_width(0)) m_rd_req_axis_agt; // 权重块读请求AXIS主机代理
	local AXISSlaveAgent #(.out_drive_t(simulation_delay), 
		.data_width(ATOMIC_C*2*8), .user_width(1)) s_out_wgtblk_axis_agt; // 输出权重块数据流AXIS从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(ATOMIC_C*2*8), .user_width(11))) m_in_cgrp_axis_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(24), .user_width(0))) m_rd_req_axis_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(ATOMIC_C*2*8), .user_width(1))) s_out_wgtblk_axis_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(ATOMIC_C*2*8), .user_width(11))) m_in_cgrp_axis_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(24), .user_width(0))) m_rd_req_axis_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(ATOMIC_C*2*8), .user_width(1))) s_out_wgtblk_axis_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(ATOMIC_C*2*8), .user_width(11)) m_in_cgrp_axis_trans;
	local AXISTrans #(.data_width(24), .user_width(0)) m_rd_req_axis_trans;
	local AXISTrans #(.data_width(ATOMIC_C*2*8), .user_width(1)) s_out_wgtblk_axis_trans;
	
	// 注册component
	`uvm_component_param_utils(LogicKernalBufferEnv #(.ATOMIC_C(ATOMIC_C), .simulation_delay(simulation_delay)))
	
	function new(string name = "LogicKernalBufferEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_in_cgrp_axis_agt = AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(ATOMIC_C*2*8), .user_width(11))::
			type_id::create("agt1", this);
		this.m_in_cgrp_axis_agt.is_active = UVM_ACTIVE;
		this.m_rd_req_axis_agt = AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(24), .user_width(0))::
			type_id::create("agt2", this);
		this.m_rd_req_axis_agt.is_active = UVM_ACTIVE;
		this.s_out_wgtblk_axis_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(ATOMIC_C*2*8), .user_width(1))::
			type_id::create("agt3", this);
		this.s_out_wgtblk_axis_agt.is_active = UVM_ACTIVE;
		this.s_out_wgtblk_axis_agt.use_sqr = 1'b0;
		
		// 创建通信端口
		this.m_in_cgrp_axis_trans_port = new("m_in_cgrp_axis_trans_port", this);
		this.m_rd_req_axis_trans_port = new("m_rd_req_axis_trans_port", this);
		this.s_out_wgtblk_axis_trans_port = new("s_out_wgtblk_axis_trans_port", this);
		
		// 创建通信fifo
		this.m_in_cgrp_axis_agt_fifo = new("m_in_cgrp_axis_agt_fifo", this);
		this.m_rd_req_axis_agt_fifo = new("m_rd_req_axis_agt_fifo", this);
		this.s_out_wgtblk_axis_agt_fifo = new("s_out_wgtblk_axis_agt_fifo", this);
		
		// 创建虚拟Sequencer
		this.vsqr = LogicKernalBufferVsqr #(.ATOMIC_C(ATOMIC_C))::type_id::create("v_sqr", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_in_cgrp_axis_agt.axis_analysis_port.connect(this.m_in_cgrp_axis_agt_fifo.analysis_export);
		this.m_in_cgrp_axis_trans_port.connect(this.m_in_cgrp_axis_agt_fifo.blocking_get_export);
		this.m_rd_req_axis_agt.axis_analysis_port.connect(this.m_rd_req_axis_agt_fifo.analysis_export);
		this.m_rd_req_axis_trans_port.connect(this.m_rd_req_axis_agt_fifo.blocking_get_export);
		this.s_out_wgtblk_axis_agt.axis_analysis_port.connect(this.s_out_wgtblk_axis_agt_fifo.analysis_export);
		this.s_out_wgtblk_axis_trans_port.connect(this.s_out_wgtblk_axis_agt_fifo.blocking_get_export);
		
		this.vsqr.m_in_cgrp_axis_sqr = this.m_in_cgrp_axis_agt.sequencer;
		this.vsqr.m_rd_req_axis_sqr = this.m_rd_req_axis_agt.sequencer;
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_in_cgrp_axis_trans_port.get(this.m_in_cgrp_axis_trans);
				// this.m_in_cgrp_axis_trans.print();
			end
			forever
			begin
				this.m_rd_req_axis_trans_port.get(this.m_rd_req_axis_trans);
				// this.m_rd_req_axis_trans.print();
			end
			forever
			begin
				this.s_out_wgtblk_axis_trans_port.get(this.s_out_wgtblk_axis_trans);
				// this.s_out_wgtblk_axis_trans.print();
			end
		join
	endtask
	
endclass
	
`endif
