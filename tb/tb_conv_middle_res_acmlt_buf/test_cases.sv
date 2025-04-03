`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class MAxisMidResCase0Sqc #(
	integer ATOMIC_K = 8 // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
)extends uvm_sequence;
	
	/** 常量 **/
	// 运算数据格式
	localparam bit[1:0] CAL_FMT_INT8 = 2'b00;
	localparam bit[1:0] CAL_FMT_INT16 = 2'b01;
	localparam bit[1:0] CAL_FMT_FP16 = 2'b10;
	
	/** 配置参数 **/
	localparam int unsigned test_pkt_n = 8; // 测试最终结果数据包个数
	localparam bit[1:0] calfmt = CAL_FMT_FP16; // 运算数据格式
	localparam bit[12:0] ofmw = 13'd16; // 输出特征图宽度
	localparam int unsigned max_wait_period_n = 1; // 最大的AXIS有效等待周期数
	
	/*
	data {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)}
	user {初始化中间结果(标志), 最后1组中间结果(标志)}
	*/
	local AXISTrans #(.data_width(ATOMIC_K*48), .user_width(2)) m_axis_mid_res_trans;
	
	// 注册object
	`uvm_object_param_utils(MAxisMidResCase0Sqc #(.ATOMIC_K(ATOMIC_K)))
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		if(this.calfmt == CAL_FMT_FP16)
		begin
			// 测试数据格式: FP16
			repeat(this.test_pkt_n)
			begin
				for(int k = 0;k < 2;k++)
				begin
					`uvm_do_with(this.m_axis_mid_res_trans, {
						data_n == ofmw;
						
						wait_period_n.size() == data_n;
						user.size() == data_n;
						last.size() == data_n;
						data.size() == data_n;
						
						foreach(wait_period_n[i]){
							wait_period_n[i] <= max_wait_period_n;
						}
						
						foreach(user[i]){
							user[i][0] == (k == 1);
							user[i][1] == (k == 0);
						}
						
						foreach(last[i]){
							last[i] == (i == (data_n - 1));
						}
						
						foreach(data[i]){
							data[i][48*0+47:48*0+40] inside {24, 26, 28};
							
							(($signed(data[i][48*0+39:48*0]) >= 4194304) && ($signed(data[i][48*0+39:48*0]) <= 67108864)) || 
							(($signed(data[i][48*0+39:48*0]) <= -4194304) && ($signed(data[i][48*0+39:48*0]) >= -67108864));
							
							data[i][48*1+47:48*1+40] inside {24, 26, 28};
							
							(($signed(data[i][48*1+39:48*1]) >= 4194304) && ($signed(data[i][48*1+39:48*1]) <= 67108864)) || 
							(($signed(data[i][48*1+39:48*1]) <= -4194304) && ($signed(data[i][48*1+39:48*1]) >= -67108864));
							
							data[i][48*2+47:48*2+40] inside {24, 26, 28};
							
							(($signed(data[i][48*2+39:48*2]) >= 4194304) && ($signed(data[i][48*2+39:48*2]) <= 67108864)) || 
							(($signed(data[i][48*2+39:48*2]) <= -4194304) && ($signed(data[i][48*2+39:48*2]) >= -67108864));
							
							data[i][48*3+47:48*3+40] inside {24, 26, 28};
							
							(($signed(data[i][48*3+39:48*3]) >= 4194304) && ($signed(data[i][48*3+39:48*3]) <= 67108864)) || 
							(($signed(data[i][48*3+39:48*3]) <= -4194304) && ($signed(data[i][48*3+39:48*3]) >= -67108864));
						}
					})
				end
			end
		end
		else if(this.calfmt == CAL_FMT_INT16)
		begin
			// 测试数据格式: INT16
			repeat(this.test_pkt_n)
			begin
				for(int k = 0;k < 2;k++)
				begin
					`uvm_do_with(this.m_axis_mid_res_trans, {
						data_n == ofmw;
						
						wait_period_n.size() == data_n;
						user.size() == data_n;
						last.size() == data_n;
						data.size() == data_n;
						
						foreach(wait_period_n[i]){
							wait_period_n[i] <= max_wait_period_n;
						}
						
						foreach(user[i]){
							user[i][0] == (k == 1);
							user[i][1] == (k == 0);
						}
						
						foreach(last[i]){
							last[i] == (i == (data_n - 1));
						}
						
						foreach(data[i]){
							(($signed(data[i][48*0+39:48*0]) >= 16) && ($signed(data[i][48*0+39:48*0]) <= 1024)) || 
							(($signed(data[i][48*0+39:48*0]) <= -16) && ($signed(data[i][48*0+39:48*0]) >= -1024));
							
							(($signed(data[i][48*1+39:48*1]) >= 16) && ($signed(data[i][48*1+39:48*1]) <= 1024)) || 
							(($signed(data[i][48*1+39:48*1]) <= -16) && ($signed(data[i][48*1+39:48*1]) >= -1024));
							
							(($signed(data[i][48*2+39:48*2]) >= 16) && ($signed(data[i][48*2+39:48*2]) <= 1024)) || 
							(($signed(data[i][48*2+39:48*2]) <= -16) && ($signed(data[i][48*2+39:48*2]) >= -1024));
							
							(($signed(data[i][48*3+39:48*3]) >= 16) && ($signed(data[i][48*3+39:48*3]) <= 1024)) || 
							(($signed(data[i][48*3+39:48*3]) <= -16) && ($signed(data[i][48*3+39:48*3]) >= -1024));
						}
					})
				end
			end
		end
		
		// 继续运行10us
		# (10 ** 4);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class ConvMidResAcmltBaseTest #(
	integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	real simulation_delay = 1 // 仿真延时
)extends uvm_test;
	
	// 卷积中间结果累加与缓存测试环境
	local ConvMidResAcmltEnv #(.ATOMIC_K(ATOMIC_K), .simulation_delay(simulation_delay)) env;
	
	// 注册component
	`uvm_component_param_utils(ConvMidResAcmltBaseTest #(.ATOMIC_K(ATOMIC_K), .simulation_delay(simulation_delay)))
	
	function new(string name = "ConvMidResAcmltBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = ConvMidResAcmltEnv #(.ATOMIC_K(ATOMIC_K), .simulation_delay(simulation_delay))::type_id::create("env", this); // 创建env
	endfunction
	
endclass

class ConvMidResAcmltCase0Test extends ConvMidResAcmltBaseTest #(.ATOMIC_K(4), .simulation_delay(1));
	
	localparam integer ATOMIC_K = 4; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	
	// 注册component
	`uvm_component_utils(ConvMidResAcmltCase0Test)
	
	function new(string name = "ConvMidResAcmltCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			MAxisMidResCase0Sqc #(.ATOMIC_K(ATOMIC_K))::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("ConvMidResAcmltCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
