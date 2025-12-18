`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"
`include "scoreboard.sv"
`include "utils.sv"

/** 环境:特征图/卷积核表面生成单元 **/
class ConvDataSfcGenEnv #(
	integer STREAM_DATA_WIDTH = 32, // 特征图/卷积核数据流的数据位宽(32 | 64 | 128 | 256)
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	integer EXTRA_DATA_WIDTH = 4, // 随路传输附加数据的位宽(必须>=1)
	real SIM_DELAY = 1 // 仿真延时
)extends uvm_env;
	
	// 组件
	local AXISMasterAgent #(.out_drive_t(SIM_DELAY), .data_width(STREAM_DATA_WIDTH), .user_width(5+EXTRA_DATA_WIDTH)) stream_axis_agt;
	local AXISSlaveAgent #(.out_drive_t(SIM_DELAY), .data_width(ATOMIC_C*2*8), .user_width(EXTRA_DATA_WIDTH)) sfc_axis_agt;
	local ConvDataSfcGenScb #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .ATOMIC_C(ATOMIC_C), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH)) scb;
	
	// 注册component
	`uvm_component_param_utils(ConvDataSfcGenEnv #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .ATOMIC_C(ATOMIC_C), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH), .SIM_DELAY(SIM_DELAY)))
	
	function new(string name = "ConvDataSfcGenEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.stream_axis_agt = 
			AXISMasterAgent #(.out_drive_t(SIM_DELAY), .data_width(STREAM_DATA_WIDTH), .user_width(5+EXTRA_DATA_WIDTH))::
				type_id::create("agt1", this);
		this.stream_axis_agt.is_active = UVM_ACTIVE;
		
		this.sfc_axis_agt = 
			AXISSlaveAgent #(.out_drive_t(SIM_DELAY), .data_width(ATOMIC_C*2*8), .user_width(EXTRA_DATA_WIDTH))::
				type_id::create("agt2", this);
		this.sfc_axis_agt.is_active = UVM_ACTIVE;
		this.sfc_axis_agt.use_sqr = 1'b0;
		
		// 创建scoreboard
		this.scb = 
			ConvDataSfcGenScb #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .ATOMIC_C(ATOMIC_C), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH))::
				type_id::create("scb", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.stream_axis_agt.axis_analysis_port.connect(this.scb.strm_imp);
		this.sfc_axis_agt.axis_analysis_port.connect(this.scb.sfc_imp);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
	endtask
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
	endfunction
	
endclass
	
`endif
