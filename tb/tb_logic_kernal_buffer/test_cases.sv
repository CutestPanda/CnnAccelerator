`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"
`include "vsqr.sv"

class LogicKernalBufferCase0VSqc #(
	integer ATOMIC_C = 4 // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
)extends uvm_sequence;
	
	local AXISTrans #(.data_width(ATOMIC_C*2*8), .user_width(11)) m_in_cgrp_axis_trans; // 输入通道组数据流AXIS事务
	local AXISTrans #(.data_width(24), .user_width(0)) m_rd_req_axis_trans; // 权重块读请求AXIS事务
	
	// 注册object
	`uvm_object_param_utils(LogicKernalBufferCase0VSqc #(.ATOMIC_C(ATOMIC_C)))
	
	// 声明p_sequencer
	`uvm_declare_p_sequencer(LogicKernalBufferVsqr #(.ATOMIC_C(ATOMIC_C)))
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		for(int i = 0;i < 6;i++)
		begin
			for(int j = 0;j < (i+1);j++)
			begin
				automatic bit is_last_wtblk = j == i;
				
				`uvm_do_on_with(this.m_in_cgrp_axis_trans, p_sequencer.m_in_cgrp_axis_sqr, {
					data_n >= 6 && data_n <= 8;
					
					data.size() == data_n;
					keep.size() == data_n;
					user.size() == data_n;
					last.size() == data_n;
					wait_period_n.size() == data_n;
					
					foreach(data[k]){
						data[k] == (k + 1);
					}
					
					foreach(keep[k]){
						keep[k] == {(ATOMIC_C*2){1'b1}};
					}
					
					foreach(user[k]){
						user[k][10:1] == (5 + i);
						user[k][0] == is_last_wtblk;
					}
					
					foreach(last[k]){
						last[k] == (k == (data_n - 1));
					}
					
					foreach(wait_period_n[k]){
						wait_period_n[k] <= 1;
					}
				})
			end
		end
		
		`uvm_do_on_with(this.m_rd_req_axis_trans, p_sequencer.m_rd_req_axis_sqr, {
			data_n == 1;
			
			data.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0][4:0] == (4 - 1);
			data[0][11:5] <= 1;
			data[0][21:12] == 6;
			data[0][22] == 1'b1;
			last[0] == 1'b1;
			wait_period_n[0] <= 3;
		})
		
		`uvm_do_on_with(this.m_rd_req_axis_trans, p_sequencer.m_rd_req_axis_sqr, {
			data_n == 1;
			
			data.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0][4:0] == (8 - 1);
			data[0][11:5] == 0;
			data[0][21:12] == 10;
			data[0][22] == 1'b1;
			last[0] == 1'b1;
			wait_period_n[0] <= 3;
		})
		
		`uvm_do_on_with(this.m_rd_req_axis_trans, p_sequencer.m_rd_req_axis_sqr, {
			data_n == 1;
			
			data.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0][4:0] == (4 - 1);
			(data[0][11:5] == 0) || (data[0][11:5] == 1);
			data[0][21:12] == 0;
			data[0][22] == 1'b1;
			last[0] == 1'b1;
			wait_period_n[0] <= 3;
		})
		
		// 继续运行10us
		# (10 ** 4);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class LogicKernalBufferBaseTest #(
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	real simulation_delay = 1 // 仿真延时
)extends uvm_test;
	
	// (逻辑)卷积核缓存测试环境
	local LogicKernalBufferEnv #(.ATOMIC_C(ATOMIC_C), .simulation_delay(simulation_delay)) env;
	
	// 注册component
	`uvm_component_param_utils(LogicKernalBufferBaseTest #(.ATOMIC_C(ATOMIC_C), .simulation_delay(simulation_delay)))
	
	function new(string name = "LogicKernalBufferBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = LogicKernalBufferEnv #(.ATOMIC_C(ATOMIC_C), .simulation_delay(simulation_delay))::type_id::create("env", this); // 创建env
	endfunction
	
endclass

class LogicKernalBufferCase0Test extends LogicKernalBufferBaseTest #(.ATOMIC_C(1), .simulation_delay(1));
	
	localparam integer ATOMIC_C = 1; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	
	// 注册component
	`uvm_component_utils(LogicKernalBufferCase0Test)
	
	function new(string name = "LogicKernalBufferCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.v_sqr.main_phase", 
			"default_sequence", 
			LogicKernalBufferCase0VSqc #(.ATOMIC_C(ATOMIC_C))::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("LogicKernalBufferCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
