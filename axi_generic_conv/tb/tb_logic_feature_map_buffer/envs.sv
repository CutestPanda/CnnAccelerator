`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"
`include "vsqr.sv"

/** 环境:(逻辑)特征图缓存 **/
class LogicFmapBufferEnv #(
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	real SIM_DELAY = 1 // 仿真延时
)extends uvm_env;
	
	// 虚拟Sequencer
	LogicFmapBufferVsqr #(.ATOMIC_C(ATOMIC_C)) vsqr;
	
	// 组件
	local AXISMasterAgent #(.out_drive_t(SIM_DELAY), 
		.data_width(ATOMIC_C*2*8), .user_width(22)) m_fin_axis_agt; // 特征图表面行数据输入AXIS主机代理
	local AXISMasterAgent #(.out_drive_t(SIM_DELAY), 
		.data_width(40), .user_width(0)) m_rd_req_axis_agt; // 特征图表面行读请求AXIS主机代理
	local AXISSlaveAgent #(.out_drive_t(SIM_DELAY), 
		.data_width(ATOMIC_C*2*8), .user_width(1)) s_fout_axis_agt; // 特征图表面行数据输出AXIS从机代理
	local ReqAckMasterAgent #(.out_drive_t(SIM_DELAY), 
		.req_payload_width(0), .resp_payload_width(0)) rst_buf_agt; // 重置缓存REQ-ACK主机代理
	local ReqAckMasterAgent #(.out_drive_t(SIM_DELAY), 
		.req_payload_width(10), .resp_payload_width(0)) sfc_row_rplc_agt; // 表面行置换REQ-ACK主机代理
	local ReqAckMasterAgent #(.out_drive_t(SIM_DELAY), 
		.req_payload_width(12), .resp_payload_width(0)) sfc_row_search_agt; // 表面行检索REQ-ACK主机代理
	
	// 注册component
	`uvm_component_param_utils(LogicFmapBufferEnv #(.ATOMIC_C(ATOMIC_C), .SIM_DELAY(SIM_DELAY)))
	
	function new(string name = "LogicFmapBufferEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_fin_axis_agt = AXISMasterAgent #(.out_drive_t(SIM_DELAY), .data_width(ATOMIC_C*2*8), .user_width(22))::
			type_id::create("agt1", this);
		this.m_fin_axis_agt.is_active = UVM_ACTIVE;
		this.m_rd_req_axis_agt = AXISMasterAgent #(.out_drive_t(SIM_DELAY), .data_width(40), .user_width(0))::
			type_id::create("agt2", this);
		this.m_rd_req_axis_agt.is_active = UVM_ACTIVE;
		this.s_fout_axis_agt = AXISSlaveAgent #(.out_drive_t(SIM_DELAY), .data_width(ATOMIC_C*2*8), .user_width(1))::
			type_id::create("agt3", this);
		this.s_fout_axis_agt.is_active = UVM_ACTIVE;
		this.s_fout_axis_agt.use_sqr = 1'b0;
		this.rst_buf_agt = ReqAckMasterAgent #(.out_drive_t(SIM_DELAY), .req_payload_width(0), .resp_payload_width(0))::
			type_id::create("agt4", this);
		this.rst_buf_agt.is_active = UVM_ACTIVE;
		this.sfc_row_rplc_agt = ReqAckMasterAgent #(.out_drive_t(SIM_DELAY), .req_payload_width(10), .resp_payload_width(0))::
			type_id::create("agt5", this);
		this.sfc_row_rplc_agt.is_active = UVM_ACTIVE;
		this.sfc_row_search_agt = ReqAckMasterAgent #(.out_drive_t(SIM_DELAY), .req_payload_width(12), .resp_payload_width(0))::
			type_id::create("agt6", this);
		this.sfc_row_search_agt.is_active = UVM_ACTIVE;
		
		// 创建虚拟Sequencer
		this.vsqr = LogicFmapBufferVsqr #(.ATOMIC_C(ATOMIC_C))::type_id::create("v_sqr", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.vsqr.m_fin_axis_sqr = this.m_fin_axis_agt.sequencer;
		this.vsqr.m_rd_req_axis_sqr = this.m_rd_req_axis_agt.sequencer;
		this.vsqr.rst_buf_sqr = this.rst_buf_agt.sequencer;
		this.vsqr.sfc_row_rplc_sqr = this.sfc_row_rplc_agt.sequencer;
		this.vsqr.sfc_row_search_sqr = this.sfc_row_search_agt.sequencer;
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
	endtask
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
	endfunction
	
endclass
	
`endif
