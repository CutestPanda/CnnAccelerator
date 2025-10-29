`timescale 1ns / 1ps

`include "uvm_macros.svh"

import uvm_pkg::*;

`include "test_cases.sv"
`include "envs.sv"
`include "agents.sv"
`include "sequencers.sv"
`include "drivers.sv"
`include "monitors.sv"
`include "transactions.sv"

module tb_conv_middle_res_acmlt_buf();
	
	/** 常量 **/
	// 运算数据格式
	localparam bit[1:0] CAL_FMT_INT8 = 2'b00;
	localparam bit[1:0] CAL_FMT_INT16 = 2'b01;
	localparam bit[1:0] CAL_FMT_FP16 = 2'b10;
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer ATOMIC_K = 4; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	localparam integer RBUF_BANK_N = 4; // 缓存MEM个数(2~32)
	localparam integer RBUF_DEPTH = 1024; // 缓存MEM深度(512 | 1024 | 2048 | 4096 | 8192)
	localparam EN_SMALL_FP32 = "false"; // 是否处理极小FP32
	// 运行时参数
	localparam bit[1:0] calfmt = CAL_FMT_FP16; // 运算数据格式
	localparam bit[12:0] ofmw_sub1 = 13'd16 - 1; // 输出特征图宽度 - 1
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 接口 **/
	AXIS #(.out_drive_t(simulation_delay), .data_width(ATOMIC_K*48), .user_width(2)) m_axis_mid_res_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(ATOMIC_K*32), .user_width(0)) s_axis_fnl_res_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_K*48), .user_width(2)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_mid_res_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_K*48), .user_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_mid_res_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_K*32), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_fnl_res_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_K*32), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_fnl_res_if.monitor);
		
		uvm_config_db #(bit[1:0])::set(null, "uvm_test_top.env", "calfmt", calfmt);
		
		// 启动testcase
		run_test("ConvMidResAcmltCase0Test");
	end
	
	/** 待测模块 **/
	// 中间结果输入(AXIS从机)
	/*
	对于ATOMIC_K个中间结果 -> 
		{指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)}
	*/
	wire[ATOMIC_K*48-1:0] s_axis_mid_res_data;
	wire[ATOMIC_K*6-1:0] s_axis_mid_res_keep;
	wire[1:0] s_axis_mid_res_user; // {初始化中间结果(标志), 最后1组中间结果(标志)}
	wire s_axis_mid_res_valid;
	wire s_axis_mid_res_ready;
	// 最终结果输出(AXIS主机)
	/*
	对于ATOMIC_K个最终结果 -> 
		{单精度浮点数或定点数(32位)}
	*/
	wire[ATOMIC_K*32-1:0] m_axis_fnl_res_data;
	wire[ATOMIC_K*4-1:0] m_axis_fnl_res_keep;
	wire m_axis_fnl_res_last; // 本行最后1个最终结果(标志)
	wire m_axis_fnl_res_valid;
	wire m_axis_fnl_res_ready;
	// 缓存MEM主接口
	wire mem_clk_a;
	wire[RBUF_BANK_N-1:0] mem_wen_a;
	wire[RBUF_BANK_N*16-1:0] mem_addr_a;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mem_din_a;
	wire mem_clk_b;
	wire[RBUF_BANK_N-1:0] mem_ren_b;
	wire[RBUF_BANK_N*16-1:0] mem_addr_b;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mem_dout_b;
	
	assign s_axis_mid_res_data = m_axis_mid_res_if.data;
	assign s_axis_mid_res_keep = m_axis_mid_res_if.keep;
	assign s_axis_mid_res_user = m_axis_mid_res_if.user;
	assign s_axis_mid_res_valid = m_axis_mid_res_if.valid;
	assign m_axis_mid_res_if.ready = s_axis_mid_res_ready;
	
	assign s_axis_fnl_res_if.data = m_axis_fnl_res_data;
	assign s_axis_fnl_res_if.keep = m_axis_fnl_res_keep;
	assign s_axis_fnl_res_if.last = m_axis_fnl_res_last;
	assign s_axis_fnl_res_if.valid = m_axis_fnl_res_valid;
	assign m_axis_fnl_res_ready = s_axis_fnl_res_if.ready;
	
	genvar mem_i;
	generate
		for(mem_i = 0;mem_i < RBUF_BANK_N;mem_i = mem_i + 1)
		begin:mem_blk
			bram_simple_dual_port #(
				.style("LOW_LATENCY"),
				.mem_width(ATOMIC_K*4*8+ATOMIC_K),
				.mem_depth(RBUF_DEPTH),
				.INIT_FILE("default"),
				.simulation_delay(simulation_delay)
			)bram_u(
				.clk(mem_clk_a),
				
				.wen_a(mem_wen_a[mem_i]),
				.addr_a(mem_addr_a[mem_i*16+15:mem_i*16]),
				.din_a(mem_din_a[(mem_i+1)*(ATOMIC_K*4*8+ATOMIC_K)-1:mem_i*(ATOMIC_K*4*8+ATOMIC_K)]),
				
				.ren_b(mem_ren_b[mem_i]),
				.addr_b(mem_addr_b[mem_i*16+15:mem_i*16]),
				.dout_b(mem_dout_b[(mem_i+1)*(ATOMIC_K*4*8+ATOMIC_K)-1:mem_i*(ATOMIC_K*4*8+ATOMIC_K)])
			);
		end
	endgenerate
	
	conv_middle_res_acmlt_buf #(
		.ATOMIC_K(ATOMIC_K),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.EN_SMALL_FP32(EN_SMALL_FP32),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.calfmt(calfmt),
		.ofmw_sub1(ofmw_sub1),
		
		.s_axis_mid_res_data(s_axis_mid_res_data),
		.s_axis_mid_res_keep(s_axis_mid_res_keep),
		.s_axis_mid_res_user(s_axis_mid_res_user),
		.s_axis_mid_res_valid(s_axis_mid_res_valid),
		.s_axis_mid_res_ready(s_axis_mid_res_ready),
		
		.m_axis_fnl_res_data(m_axis_fnl_res_data),
		.m_axis_fnl_res_keep(m_axis_fnl_res_keep),
		.m_axis_fnl_res_last(m_axis_fnl_res_last),
		.m_axis_fnl_res_valid(m_axis_fnl_res_valid),
		.m_axis_fnl_res_ready(m_axis_fnl_res_ready),
		
		.mem_clk_a(mem_clk_a),
		.mem_wen_a(mem_wen_a),
		.mem_addr_a(mem_addr_a),
		.mem_din_a(mem_din_a),
		.mem_clk_b(mem_clk_b),
		.mem_ren_b(mem_ren_b),
		.mem_addr_b(mem_addr_b),
		.mem_dout_b(mem_dout_b)
	);
	
endmodule
