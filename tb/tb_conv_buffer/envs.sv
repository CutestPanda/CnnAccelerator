`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"
`include "vsqr.sv"

/** 环境:卷积私有缓存 **/
class ConvBufferEnv #(
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	real simulation_delay = 1 // 仿真延时
)extends uvm_env;
	
	// 虚拟Sequencer
	ConvBufferVsqr #(.ATOMIC_C(ATOMIC_C)) vsqr;
	
	// 组件
	local ICBMasterAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8)) m0_fmbuf_icb_agt; // 特征图缓存ICB主机#0代理
	local ICBMasterAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8)) m1_fmbuf_icb_agt; // 特征图缓存ICB主机#1代理
	local ICBMasterAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8)) m0_kbuf_icb_agt; // 卷积核缓存ICB主机#0代理
	local ICBMasterAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8)) m1_kbuf_icb_agt; // 卷积核缓存ICB主机#1代理
	
	// 通信端口
	local uvm_blocking_get_port #(ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8))) m0_fmbuf_icb_trans_port;
	local uvm_blocking_get_port #(ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8))) m1_fmbuf_icb_trans_port;
	local uvm_blocking_get_port #(ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8))) m0_kbuf_icb_trans_port;
	local uvm_blocking_get_port #(ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8))) m1_kbuf_icb_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8))) m0_fmbuf_icb_agt_fifo;
	local uvm_tlm_analysis_fifo #(ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8))) m1_fmbuf_icb_agt_fifo;
	local uvm_tlm_analysis_fifo #(ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8))) m0_kbuf_icb_agt_fifo;
	local uvm_tlm_analysis_fifo #(ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8))) m1_kbuf_icb_agt_fifo;
	
	// 事务
	local ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8)) m0_fmbuf_icb_trans;
	local ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8)) m1_fmbuf_icb_trans;
	local ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8)) m0_kbuf_icb_trans;
	local ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8)) m1_kbuf_icb_trans;
	
	// 注册component
	`uvm_component_param_utils(ConvBufferEnv #(.ATOMIC_C(ATOMIC_C), .simulation_delay(simulation_delay)))
	
	function new(string name = "ConvBufferEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m0_fmbuf_icb_agt = ICBMasterAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8))::
			type_id::create("agt1", this);
		this.m0_fmbuf_icb_agt.is_active = UVM_ACTIVE;
		this.m1_fmbuf_icb_agt = ICBMasterAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8))::
			type_id::create("agt2", this);
		this.m1_fmbuf_icb_agt.is_active = UVM_ACTIVE;
		this.m0_kbuf_icb_agt = ICBMasterAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8))::
			type_id::create("agt3", this);
		this.m0_kbuf_icb_agt.is_active = UVM_ACTIVE;
		this.m1_kbuf_icb_agt = ICBMasterAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8))::
			type_id::create("agt4", this);
		this.m1_kbuf_icb_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m0_fmbuf_icb_trans_port = new("m0_fmbuf_icb_trans_port", this);
		this.m1_fmbuf_icb_trans_port = new("m1_fmbuf_icb_trans_port", this);
		this.m0_kbuf_icb_trans_port = new("m0_kbuf_icb_trans_port", this);
		this.m1_kbuf_icb_trans_port = new("m1_kbuf_icb_trans_port", this);
		
		// 创建通信fifo
		this.m0_fmbuf_icb_agt_fifo = new("m0_fmbuf_icb_agt_fifo", this);
		this.m1_fmbuf_icb_agt_fifo = new("m1_fmbuf_icb_agt_fifo", this);
		this.m0_kbuf_icb_agt_fifo = new("m0_kbuf_icb_agt_fifo", this);
		this.m1_kbuf_icb_agt_fifo = new("m1_kbuf_icb_agt_fifo", this);
		
		// 创建虚拟Sequencer
		this.vsqr = ConvBufferVsqr #(.ATOMIC_C(ATOMIC_C))::type_id::create("v_sqr", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m0_fmbuf_icb_agt.icb_analysis_port.connect(this.m0_fmbuf_icb_agt_fifo.analysis_export);
		this.m0_fmbuf_icb_trans_port.connect(this.m0_fmbuf_icb_agt_fifo.blocking_get_export);
		this.m1_fmbuf_icb_agt.icb_analysis_port.connect(this.m1_fmbuf_icb_agt_fifo.analysis_export);
		this.m1_fmbuf_icb_trans_port.connect(this.m1_fmbuf_icb_agt_fifo.blocking_get_export);
		this.m0_kbuf_icb_agt.icb_analysis_port.connect(this.m0_kbuf_icb_agt_fifo.analysis_export);
		this.m0_kbuf_icb_trans_port.connect(this.m0_kbuf_icb_agt_fifo.blocking_get_export);
		this.m1_kbuf_icb_agt.icb_analysis_port.connect(this.m1_kbuf_icb_agt_fifo.analysis_export);
		this.m1_kbuf_icb_trans_port.connect(this.m1_kbuf_icb_agt_fifo.blocking_get_export);
		
		this.vsqr.m0_fmbuf_icb_sqr = this.m0_fmbuf_icb_agt.sequencer;
		this.vsqr.m1_fmbuf_icb_sqr = this.m1_fmbuf_icb_agt.sequencer;
		this.vsqr.m0_kbuf_icb_sqr = this.m0_kbuf_icb_agt.sequencer;
		this.vsqr.m1_kbuf_icb_sqr = this.m1_kbuf_icb_agt.sequencer;
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m0_fmbuf_icb_trans_port.get(this.m0_fmbuf_icb_trans);
				// this.m0_fmbuf_icb_trans.print();
			end
			forever
			begin
				this.m1_fmbuf_icb_trans_port.get(this.m1_fmbuf_icb_trans);
				// this.m1_fmbuf_icb_trans.print();
			end
			forever
			begin
				this.m0_kbuf_icb_trans_port.get(this.m0_kbuf_icb_trans);
				// this.m0_kbuf_icb_trans.print();
			end
			forever
			begin
				this.m1_kbuf_icb_trans_port.get(this.m1_kbuf_icb_trans);
				// this.m1_kbuf_icb_trans.print();
			end
		join
	endtask
	
endclass
	
`endif
