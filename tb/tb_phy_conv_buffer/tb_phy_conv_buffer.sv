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

module tb_phy_conv_buffer();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer ATOMIC_C = 1; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	localparam integer CBUF_BANK_N = 8; // 缓存MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	localparam integer CBUF_DEPTH_FOREACH_BANK = 512; // 每片缓存MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	localparam EN_EXCEED_BD_PROTECT = "true"; // 是否启用逻辑地址越界保护
	localparam EN_HP_ICB = "true"; // 是否启用高性能ICB从机
	localparam EN_ICB0_FMBUF_REG_SLICE = "true"; // 是否在特征图缓存0号ICB插入AXIS寄存器片
	localparam EN_ICB1_FMBUF_REG_SLICE = "true"; // 是否在特征图缓存1号ICB插入AXIS寄存器片
	localparam EN_ICB0_KBUF_REG_SLICE = "true"; // 是否在卷积核缓存0号ICB插入AXIS寄存器片
	localparam EN_ICB1_KBUF_REG_SLICE = "true"; // 是否在卷积核缓存1号ICB插入AXIS寄存器片
	// 运行时参数
	localparam bit[7:0] fmbufbankn = 8'd5; // 分配给特征图缓存的Bank数
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
	ICB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8)) m0_fmbuf_icb_if(.clk(clk), .rst_n(rst_n));
	ICB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8)) m1_fmbuf_icb_if(.clk(clk), .rst_n(rst_n));
	ICB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8)) m0_kbuf_icb_if(.clk(clk), .rst_n(rst_n));
	ICB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(ATOMIC_C*2*8)) m1_kbuf_icb_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(ATOMIC_C*2*8)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "icb_if", m0_fmbuf_icb_if.master);
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(ATOMIC_C*2*8)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "icb_if", m0_fmbuf_icb_if.monitor);
		
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(ATOMIC_C*2*8)).master)::set(null, 
			"uvm_test_top.env.agt2.drv", "icb_if", m1_fmbuf_icb_if.master);
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(ATOMIC_C*2*8)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "icb_if", m1_fmbuf_icb_if.monitor);
		
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(ATOMIC_C*2*8)).master)::set(null, 
			"uvm_test_top.env.agt3.drv", "icb_if", m0_kbuf_icb_if.master);
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(ATOMIC_C*2*8)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "icb_if", m0_kbuf_icb_if.monitor);
		
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(ATOMIC_C*2*8)).master)::set(null, 
			"uvm_test_top.env.agt4.drv", "icb_if", m1_kbuf_icb_if.master);
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(ATOMIC_C*2*8)).monitor)::set(null, 
			"uvm_test_top.env.agt4.mon", "icb_if", m1_kbuf_icb_if.monitor);
		
		// 启动testcase
		run_test("ConvBufferCase0Test");
	end
	
	/** 待测模块 **/
	// 特征图缓存ICB从机#0
	// 命令通道
	wire[31:0] s0_fmbuf_cmd_addr;
	wire s0_fmbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] s0_fmbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] s0_fmbuf_cmd_wmask;
	wire s0_fmbuf_cmd_valid;
	wire s0_fmbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] s0_fmbuf_rsp_rdata;
	wire s0_fmbuf_rsp_err;
	wire s0_fmbuf_rsp_valid;
	wire s0_fmbuf_rsp_ready;
	// 特征图缓存ICB从机#1
	// 命令通道
	wire[31:0] s1_fmbuf_cmd_addr;
	wire s1_fmbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] s1_fmbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] s1_fmbuf_cmd_wmask;
	wire s1_fmbuf_cmd_valid;
	wire s1_fmbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] s1_fmbuf_rsp_rdata;
	wire s1_fmbuf_rsp_err;
	wire s1_fmbuf_rsp_valid;
	wire s1_fmbuf_rsp_ready;
	// 卷积核缓存ICB从机#0
	// 命令通道
	wire[31:0] s0_kbuf_cmd_addr;
	wire s0_kbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] s0_kbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] s0_kbuf_cmd_wmask;
	wire s0_kbuf_cmd_valid;
	wire s0_kbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] s0_kbuf_rsp_rdata;
	wire s0_kbuf_rsp_err;
	wire s0_kbuf_rsp_valid;
	wire s0_kbuf_rsp_ready;
	// 卷积核缓存ICB从机#1
	// 命令通道
	wire[31:0] s1_kbuf_cmd_addr;
	wire s1_kbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] s1_kbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] s1_kbuf_cmd_wmask;
	wire s1_kbuf_cmd_valid;
	wire s1_kbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] s1_kbuf_rsp_rdata;
	wire s1_kbuf_rsp_err;
	wire s1_kbuf_rsp_valid;
	wire s1_kbuf_rsp_ready;
	// 缓存MEM主接口
	wire mem_clk_a;
	wire[CBUF_BANK_N-1:0] mem_en_a;
	wire[CBUF_BANK_N*ATOMIC_C*2-1:0] mem_wen_a;
	wire[CBUF_BANK_N*16-1:0] mem_addr_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] mem_din_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] mem_dout_a;
	
	assign s0_fmbuf_cmd_addr = m0_fmbuf_icb_if.cmd_addr;
	assign s0_fmbuf_cmd_read = m0_fmbuf_icb_if.cmd_read;
	assign s0_fmbuf_cmd_wdata = m0_fmbuf_icb_if.cmd_wdata;
	assign s0_fmbuf_cmd_wmask = m0_fmbuf_icb_if.cmd_wmask;
	assign s0_fmbuf_cmd_valid = m0_fmbuf_icb_if.cmd_valid;
	assign m0_fmbuf_icb_if.cmd_ready = s0_fmbuf_cmd_ready;
	assign m0_fmbuf_icb_if.rsp_rdata = s0_fmbuf_rsp_rdata;
	assign m0_fmbuf_icb_if.rsp_err = s0_fmbuf_rsp_err;
	assign m0_fmbuf_icb_if.rsp_valid = s0_fmbuf_rsp_valid;
	assign s0_fmbuf_rsp_ready = m0_fmbuf_icb_if.rsp_ready;
	
	assign s1_fmbuf_cmd_addr = m1_fmbuf_icb_if.cmd_addr;
	assign s1_fmbuf_cmd_read = m1_fmbuf_icb_if.cmd_read;
	assign s1_fmbuf_cmd_wdata = m1_fmbuf_icb_if.cmd_wdata;
	assign s1_fmbuf_cmd_wmask = m1_fmbuf_icb_if.cmd_wmask;
	assign s1_fmbuf_cmd_valid = m1_fmbuf_icb_if.cmd_valid;
	assign m1_fmbuf_icb_if.cmd_ready = s1_fmbuf_cmd_ready;
	assign m1_fmbuf_icb_if.rsp_rdata = s1_fmbuf_rsp_rdata;
	assign m1_fmbuf_icb_if.rsp_err = s1_fmbuf_rsp_err;
	assign m1_fmbuf_icb_if.rsp_valid = s1_fmbuf_rsp_valid;
	assign s1_fmbuf_rsp_ready = m1_fmbuf_icb_if.rsp_ready;
	
	assign s0_kbuf_cmd_addr = m0_kbuf_icb_if.cmd_addr;
	assign s0_kbuf_cmd_read = m0_kbuf_icb_if.cmd_read;
	assign s0_kbuf_cmd_wdata = m0_kbuf_icb_if.cmd_wdata;
	assign s0_kbuf_cmd_wmask = m0_kbuf_icb_if.cmd_wmask;
	assign s0_kbuf_cmd_valid = m0_kbuf_icb_if.cmd_valid;
	assign m0_kbuf_icb_if.cmd_ready = s0_kbuf_cmd_ready;
	assign m0_kbuf_icb_if.rsp_rdata = s0_kbuf_rsp_rdata;
	assign m0_kbuf_icb_if.rsp_err = s0_kbuf_rsp_err;
	assign m0_kbuf_icb_if.rsp_valid = s0_kbuf_rsp_valid;
	assign s0_kbuf_rsp_ready = m0_kbuf_icb_if.rsp_ready;
	
	assign s1_kbuf_cmd_addr = m1_kbuf_icb_if.cmd_addr;
	assign s1_kbuf_cmd_read = m1_kbuf_icb_if.cmd_read;
	assign s1_kbuf_cmd_wdata = m1_kbuf_icb_if.cmd_wdata;
	assign s1_kbuf_cmd_wmask = m1_kbuf_icb_if.cmd_wmask;
	assign s1_kbuf_cmd_valid = m1_kbuf_icb_if.cmd_valid;
	assign m1_kbuf_icb_if.cmd_ready = s1_kbuf_cmd_ready;
	assign m1_kbuf_icb_if.rsp_rdata = s1_kbuf_rsp_rdata;
	assign m1_kbuf_icb_if.rsp_err = s1_kbuf_rsp_err;
	assign m1_kbuf_icb_if.rsp_valid = s1_kbuf_rsp_valid;
	assign s1_kbuf_rsp_ready = m1_kbuf_icb_if.rsp_ready;
	
	genvar mem_i;
	generate
		for(mem_i = 0;mem_i < CBUF_BANK_N;mem_i = mem_i + 1)
		begin:mem_blk
			bram_single_port #(
				.style("LOW_LATENCY"),
				.rw_mode("read_first"),
				.mem_width(ATOMIC_C*2*8),
				.mem_depth(CBUF_DEPTH_FOREACH_BANK),
				.INIT_FILE("default"),
				.byte_write_mode("true"),
				.simulation_delay(simulation_delay)
			)bram_u(
				.clk(mem_clk_a),
				
				.en(mem_en_a[mem_i]),
				.wen(mem_wen_a[ATOMIC_C*2*(mem_i+1)-1:ATOMIC_C*2*mem_i]),
				.addr(mem_addr_a[16*(mem_i+1)-1:16*mem_i]),
				.din(mem_din_a[ATOMIC_C*2*8*(mem_i+1)-1:ATOMIC_C*2*8*mem_i]),
				.dout(mem_dout_a[ATOMIC_C*2*8*(mem_i+1)-1:ATOMIC_C*2*8*mem_i])
			);
		end
	endgenerate
	
	conv_buffer #(
		.ATOMIC_C(ATOMIC_C),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.EN_EXCEED_BD_PROTECT(EN_EXCEED_BD_PROTECT),
		.EN_HP_ICB(EN_HP_ICB),
		.EN_ICB0_FMBUF_REG_SLICE(EN_ICB0_FMBUF_REG_SLICE),
		.EN_ICB1_FMBUF_REG_SLICE(EN_ICB1_FMBUF_REG_SLICE),
		.EN_ICB0_KBUF_REG_SLICE(EN_ICB0_KBUF_REG_SLICE),
		.EN_ICB1_KBUF_REG_SLICE(EN_ICB1_KBUF_REG_SLICE),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.fmbufbankn(fmbufbankn),
		
		.s0_fmbuf_cmd_addr(s0_fmbuf_cmd_addr),
		.s0_fmbuf_cmd_read(s0_fmbuf_cmd_read),
		.s0_fmbuf_cmd_wdata(s0_fmbuf_cmd_wdata),
		.s0_fmbuf_cmd_wmask(s0_fmbuf_cmd_wmask),
		.s0_fmbuf_cmd_valid(s0_fmbuf_cmd_valid),
		.s0_fmbuf_cmd_ready(s0_fmbuf_cmd_ready),
		.s0_fmbuf_rsp_rdata(s0_fmbuf_rsp_rdata),
		.s0_fmbuf_rsp_err(s0_fmbuf_rsp_err),
		.s0_fmbuf_rsp_valid(s0_fmbuf_rsp_valid),
		.s0_fmbuf_rsp_ready(s0_fmbuf_rsp_ready),
		
		.s1_fmbuf_cmd_addr(s1_fmbuf_cmd_addr),
		.s1_fmbuf_cmd_read(s1_fmbuf_cmd_read),
		.s1_fmbuf_cmd_wdata(s1_fmbuf_cmd_wdata),
		.s1_fmbuf_cmd_wmask(s1_fmbuf_cmd_wmask),
		.s1_fmbuf_cmd_valid(s1_fmbuf_cmd_valid),
		.s1_fmbuf_cmd_ready(s1_fmbuf_cmd_ready),
		.s1_fmbuf_rsp_rdata(s1_fmbuf_rsp_rdata),
		.s1_fmbuf_rsp_err(s1_fmbuf_rsp_err),
		.s1_fmbuf_rsp_valid(s1_fmbuf_rsp_valid),
		.s1_fmbuf_rsp_ready(s1_fmbuf_rsp_ready),
		
		.s0_kbuf_cmd_addr(s0_kbuf_cmd_addr),
		.s0_kbuf_cmd_read(s0_kbuf_cmd_read),
		.s0_kbuf_cmd_wdata(s0_kbuf_cmd_wdata),
		.s0_kbuf_cmd_wmask(s0_kbuf_cmd_wmask),
		.s0_kbuf_cmd_valid(s0_kbuf_cmd_valid),
		.s0_kbuf_cmd_ready(s0_kbuf_cmd_ready),
		.s0_kbuf_rsp_rdata(s0_kbuf_rsp_rdata),
		.s0_kbuf_rsp_err(s0_kbuf_rsp_err),
		.s0_kbuf_rsp_valid(s0_kbuf_rsp_valid),
		.s0_kbuf_rsp_ready(s0_kbuf_rsp_ready),
		
		.s1_kbuf_cmd_addr(s1_kbuf_cmd_addr),
		.s1_kbuf_cmd_read(s1_kbuf_cmd_read),
		.s1_kbuf_cmd_wdata(s1_kbuf_cmd_wdata),
		.s1_kbuf_cmd_wmask(s1_kbuf_cmd_wmask),
		.s1_kbuf_cmd_valid(s1_kbuf_cmd_valid),
		.s1_kbuf_cmd_ready(s1_kbuf_cmd_ready),
		.s1_kbuf_rsp_rdata(s1_kbuf_rsp_rdata),
		.s1_kbuf_rsp_err(s1_kbuf_rsp_err),
		.s1_kbuf_rsp_valid(s1_kbuf_rsp_valid),
		.s1_kbuf_rsp_ready(s1_kbuf_rsp_ready),
		
		.mem_clk_a(mem_clk_a),
		.mem_en_a(mem_en_a),
		.mem_wen_a(mem_wen_a),
		.mem_addr_a(mem_addr_a),
		.mem_din_a(mem_din_a),
		.mem_dout_a(mem_dout_a)
	);
	
endmodule
