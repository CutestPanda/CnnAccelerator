`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"
`include "vsqr.sv"

class ConvBufferCase0VSqc #(
	integer ATOMIC_C = 4 // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
)extends uvm_sequence;
	
	localparam integer CBUF_DEPTH_FOREACH_BANK = 512; // 每片缓存MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	
	local ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8)) s0_fmbuf_icb_trans; // 特征图缓存ICB从机#0事务
	local ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8)) s1_fmbuf_icb_trans; // 特征图缓存ICB从机#1事务
	local ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8)) s0_kbuf_icb_trans; // 卷积核缓存ICB从机#0事务
	local ICBTrans #(.addr_width(32), .data_width(ATOMIC_C*2*8)) s1_kbuf_icb_trans; // 卷积核缓存ICB从机#1事务
	
	// 注册object
	`uvm_object_param_utils(ConvBufferCase0VSqc #(.ATOMIC_C(ATOMIC_C)))
	
	// 声明p_sequencer
	`uvm_declare_p_sequencer(ConvBufferVsqr #(.ATOMIC_C(ATOMIC_C)))
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		`uvm_do_on_with(this.s0_fmbuf_icb_trans, p_sequencer.m0_fmbuf_icb_sqr, {
			cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 18 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2187;
			cmd_wmask == 2'b11;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s0_fmbuf_icb_trans, p_sequencer.m0_fmbuf_icb_sqr, {
			cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 19 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2187;
			cmd_wmask == 2'b11;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s0_fmbuf_icb_trans, p_sequencer.m0_fmbuf_icb_sqr, {
			cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 20 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2187;
			cmd_wmask == 2'b11;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s0_fmbuf_icb_trans, p_sequencer.m0_fmbuf_icb_sqr, {
			cmd_addr == 2 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 59 * (ATOMIC_C * 2);
			cmd_read == 1'b0;
			cmd_wdata == 9894;
			cmd_wmask == 2'b10;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s0_fmbuf_icb_trans, p_sequencer.m0_fmbuf_icb_sqr, {
			cmd_addr == 9 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 0 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2086;
			cmd_wmask == 2'b11;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s1_fmbuf_icb_trans, p_sequencer.m1_fmbuf_icb_sqr, {
			cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 18 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2187;
			cmd_wmask == 2'b10;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s1_fmbuf_icb_trans, p_sequencer.m1_fmbuf_icb_sqr, {
			cmd_addr == 2 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 59 * (ATOMIC_C * 2);
			cmd_read == 1'b0;
			cmd_wdata == 9894;
			cmd_wmask == 2'b10;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s1_fmbuf_icb_trans, p_sequencer.m1_fmbuf_icb_sqr, {
			cmd_addr == 9 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 0 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2086;
			cmd_wmask == 2'b11;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s0_kbuf_icb_trans, p_sequencer.m0_kbuf_icb_sqr, {
			cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 18 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2187;
			cmd_wmask == 2'b10;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s0_kbuf_icb_trans, p_sequencer.m0_kbuf_icb_sqr, {
			cmd_addr == 2 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 59 * (ATOMIC_C * 2);
			cmd_read == 1'b0;
			cmd_wdata == 9894;
			cmd_wmask == 2'b10;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s0_kbuf_icb_trans, p_sequencer.m0_kbuf_icb_sqr, {
			cmd_addr == 3 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 0 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2086;
			cmd_wmask == 2'b11;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s1_kbuf_icb_trans, p_sequencer.m1_kbuf_icb_sqr, {
			cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 18 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2187;
			cmd_wmask == 2'b11;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s1_kbuf_icb_trans, p_sequencer.m1_kbuf_icb_sqr, {
			cmd_addr == 2 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 59 * (ATOMIC_C * 2);
			cmd_read == 1'b0;
			cmd_wdata == 9894;
			cmd_wmask == 2'b10;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		`uvm_do_on_with(this.s1_kbuf_icb_trans, p_sequencer.m1_kbuf_icb_sqr, {
			cmd_addr == 3 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 0 * (ATOMIC_C * 2);
			cmd_read == 1'b1;
			cmd_wdata == 2086;
			cmd_wmask == 2'b11;
			cmd_wait_period_n == 0;
			
			rsp_wait_period_n == 0;
		})
		
		fork
			`uvm_do_on_with(this.s0_fmbuf_icb_trans, p_sequencer.m0_fmbuf_icb_sqr, {
				cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 18 * (ATOMIC_C * 2);
				cmd_read == 1'b1;
				cmd_wdata == 2187;
				cmd_wmask == 2'b10;
				cmd_wait_period_n == 0;
				
				rsp_wait_period_n == 2;
			})
			
			`uvm_do_on_with(this.s1_fmbuf_icb_trans, p_sequencer.m1_fmbuf_icb_sqr, {
				cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 49 * (ATOMIC_C * 2);
				cmd_read == 1'b1;
				cmd_wdata == 2187;
				cmd_wmask == 2'b10;
				cmd_wait_period_n == 0;
				
				rsp_wait_period_n == 3;
			})
		join
		
		fork
			`uvm_do_on_with(this.s0_kbuf_icb_trans, p_sequencer.m0_kbuf_icb_sqr, {
				cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 18 * (ATOMIC_C * 2);
				cmd_read == 1'b1;
				cmd_wdata == 2187;
				cmd_wmask == 2'b10;
				cmd_wait_period_n == 0;
				
				rsp_wait_period_n == 2;
			})
			
			`uvm_do_on_with(this.s1_kbuf_icb_trans, p_sequencer.m1_kbuf_icb_sqr, {
				cmd_addr == 0 * (CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2) + 49 * (ATOMIC_C * 2);
				cmd_read == 1'b1;
				cmd_wdata == 2187;
				cmd_wmask == 2'b10;
				cmd_wait_period_n == 0;
				
				rsp_wait_period_n == 3;
			})
		join
		
		// 继续运行10us
		# (10 ** 4);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class ConvBufferBaseTest #(
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	real simulation_delay = 1 // 仿真延时
)extends uvm_test;
	
	// 卷积私有缓存测试环境
	local ConvBufferEnv #(.ATOMIC_C(ATOMIC_C), .simulation_delay(simulation_delay)) env;
	
	// 注册component
	`uvm_component_param_utils(ConvBufferBaseTest #(.ATOMIC_C(ATOMIC_C), .simulation_delay(simulation_delay)))
	
	function new(string name = "ConvBufferBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = ConvBufferEnv #(.ATOMIC_C(ATOMIC_C), .simulation_delay(simulation_delay))::type_id::create("env", this); // 创建env
	endfunction
	
endclass

class ConvBufferCase0Test extends ConvBufferBaseTest #(.ATOMIC_C(1), .simulation_delay(1));
	
	localparam integer ATOMIC_C = 1; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	
	// 注册component
	`uvm_component_utils(ConvBufferCase0Test)
	
	function new(string name = "ConvBufferCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.v_sqr.main_phase", 
			"default_sequence", 
			ConvBufferCase0VSqc #(.ATOMIC_C(ATOMIC_C))::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("ConvBufferCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
