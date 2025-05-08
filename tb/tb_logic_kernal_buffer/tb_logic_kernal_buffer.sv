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

module tb_logic_kernal_buffer();
	
	/** 常量 **/
	// 每个通道组的权重块个数的类型编码
	localparam KBUFGRPSZ_4 = 3'b000;
	localparam KBUFGRPSZ_16 = 3'b001;
	localparam KBUFGRPSZ_32 = 3'b010;
	localparam KBUFGRPSZ_64 = 3'b011;
	localparam KBUFGRPSZ_128 = 3'b100;
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer ATOMIC_C = 1; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	localparam integer ATOMIC_K = 8; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	localparam integer CBUF_BANK_N = 4; // 缓存MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	localparam integer CBUF_DEPTH_FOREACH_BANK = 512; // 每片缓存MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	// 运行时参数
	localparam bit[7:0] kbufgrpn = 4 - 1; // 卷积核缓存的通道组数 - 1
	localparam bit[2:0] kbufgrpsz = KBUFGRPSZ_16; // 每个通道组的权重块个数的类型
	localparam bit[9:0] rsv_rgn_grpsid = 5; // 驻留区起始通道组号
	localparam bit[9:0] cgrpn = 10 - 1; // 实际通道组数 - 1
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(ATOMIC_C*2*8), .user_width(11)) m_in_cgrp_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(24), .user_width(0)) m_rd_req_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(ATOMIC_C*2*8), .user_width(1)) s_out_wgtblk_axis_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(11)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_in_cgrp_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(11)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_in_cgrp_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(24), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", m_rd_req_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(24), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", m_rd_req_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(1)).slave)::set(null, 
			"uvm_test_top.env.agt3.drv", "axis_if", s_out_wgtblk_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(1)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "axis_if", s_out_wgtblk_axis_if.monitor);
		
		// 启动testcase
		run_test("LogicKernalBufferCase0Test");
	end
	
	/** 待测模块 **/
	// 控制信号
	reg rst_logic_kbuf; // 重置逻辑卷积核缓存
	reg sw_rgn0_rplc; // 置换交换区通道组#0
	reg sw_rgn1_rplc; // 置换交换区通道组#1
	// 输入通道组数据流(AXIS从机)
	wire[ATOMIC_C*2*8-1:0] s_in_cgrp_axis_data;
	wire[ATOMIC_C*2-1:0] s_in_cgrp_axis_keep;
	wire[10:0] s_in_cgrp_axis_user; // {实际通道组号(10bit), 标志通道组的最后1个权重块(1bit)}
	wire s_in_cgrp_axis_last; // 标志权重块的最后1个表面
	wire s_in_cgrp_axis_valid;
	wire s_in_cgrp_axis_ready;
	// 权重块读请求(AXIS从机)
	wire[23:0] s_rd_req_axis_data;
	wire s_rd_req_axis_valid;
	wire s_rd_req_axis_ready;
	// 输出权重块数据流(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_out_wgtblk_axis_data;
	wire m_out_wgtblk_axis_user; // 标志权重块未找到
	wire m_out_wgtblk_axis_last; // 标志权重块的最后1个表面
	wire m_out_wgtblk_axis_valid;
	wire m_out_wgtblk_axis_ready;
	// 卷积核缓存ICB主机#0
	// 命令通道
	wire[31:0] m0_kbuf_cmd_addr;
	wire m0_kbuf_cmd_read; // const -> 1'b0
	wire[ATOMIC_C*2*8-1:0] m0_kbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] m0_kbuf_cmd_wmask; // const -> {(ATOMIC_C*2){1'b1}}
	wire m0_kbuf_cmd_valid;
	wire m0_kbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] m0_kbuf_rsp_rdata; // ignored
	wire m0_kbuf_rsp_err; // ignored
	wire m0_kbuf_rsp_valid;
	wire m0_kbuf_rsp_ready; // const -> 1'b1
	// 卷积核缓存ICB主机#1
	// 命令通道
	wire[31:0] m1_kbuf_cmd_addr;
	wire m1_kbuf_cmd_read; // const -> 1'b1
	wire[ATOMIC_C*2*8-1:0] m1_kbuf_cmd_wdata; // not care
	wire[ATOMIC_C*2-1:0] m1_kbuf_cmd_wmask; // not care
	wire m1_kbuf_cmd_valid;
	wire m1_kbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] m1_kbuf_rsp_rdata;
	wire m1_kbuf_rsp_err; // ignored
	wire m1_kbuf_rsp_valid;
	wire m1_kbuf_rsp_ready;
	// 缓存MEM主接口
	wire mem_clk_a;
	wire[CBUF_BANK_N-1:0] mem_en_a;
	wire[CBUF_BANK_N*ATOMIC_C*2-1:0] mem_wen_a;
	wire[CBUF_BANK_N*16-1:0] mem_addr_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] mem_din_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] mem_dout_a;
	
	assign s_in_cgrp_axis_data = m_in_cgrp_axis_if.data;
	assign s_in_cgrp_axis_keep = m_in_cgrp_axis_if.keep;
	assign s_in_cgrp_axis_user = m_in_cgrp_axis_if.user;
	assign s_in_cgrp_axis_last = m_in_cgrp_axis_if.last;
	assign s_in_cgrp_axis_valid = m_in_cgrp_axis_if.valid;
	assign m_in_cgrp_axis_if.ready = s_in_cgrp_axis_ready;
	
	assign s_rd_req_axis_data = m_rd_req_axis_if.data;
	assign s_rd_req_axis_valid = m_rd_req_axis_if.valid;
	assign m_rd_req_axis_if.ready = s_rd_req_axis_ready;
	
	assign s_out_wgtblk_axis_if.data = m_out_wgtblk_axis_data;
	assign s_out_wgtblk_axis_if.user = m_out_wgtblk_axis_user;
	assign s_out_wgtblk_axis_if.last = m_out_wgtblk_axis_last;
	assign s_out_wgtblk_axis_if.valid = m_out_wgtblk_axis_valid;
	assign m_out_wgtblk_axis_ready = s_out_wgtblk_axis_if.ready;
	
	initial
	begin
		rst_logic_kbuf <= 1'b1;
		sw_rgn0_rplc <= 1'b0;
		sw_rgn1_rplc <= 1'b0;
		
		repeat(10)
			@(posedge clk iff rst_n);
		
		rst_logic_kbuf <= # simulation_delay 1'b0;
		
		repeat(200)
			@(posedge clk iff rst_n);
		
		sw_rgn1_rplc <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		sw_rgn1_rplc <= # simulation_delay 1'b0;
		
		repeat(400)
			@(posedge clk iff rst_n);
		
		sw_rgn0_rplc <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		sw_rgn0_rplc <= # simulation_delay 1'b0;
	end
	
	logic_kernal_buffer #(
		.ATOMIC_C(ATOMIC_C),
		.ATOMIC_K(ATOMIC_K),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.kbufgrpn(kbufgrpn),
		.kbufgrpsz(kbufgrpsz),
		
		.rsv_rgn_grpsid(rsv_rgn_grpsid),
		.cgrpn(cgrpn),
		
		.rst_logic_kbuf(rst_logic_kbuf),
		.sw_rgn0_rplc(sw_rgn0_rplc),
		.sw_rgn1_rplc(sw_rgn1_rplc),
		
		.rsv_rgn_vld_grpn(),
		.sw_rgn0_vld(),
		.sw_rgn1_vld(),
		.sw_rgn0_grpid(),
		.sw_rgn1_grpid(),
		.has_sw_rgn(),
		
		.s_in_cgrp_axis_data(s_in_cgrp_axis_data),
		.s_in_cgrp_axis_keep(s_in_cgrp_axis_keep),
		.s_in_cgrp_axis_user(s_in_cgrp_axis_user),
		.s_in_cgrp_axis_last(s_in_cgrp_axis_last),
		.s_in_cgrp_axis_valid(s_in_cgrp_axis_valid),
		.s_in_cgrp_axis_ready(s_in_cgrp_axis_ready),
		
		.s_rd_req_axis_data(s_rd_req_axis_data),
		.s_rd_req_axis_valid(s_rd_req_axis_valid),
		.s_rd_req_axis_ready(s_rd_req_axis_ready),
		
		.m_out_wgtblk_axis_data(m_out_wgtblk_axis_data),
		.m_out_wgtblk_axis_user(m_out_wgtblk_axis_user),
		.m_out_wgtblk_axis_last(m_out_wgtblk_axis_last),
		.m_out_wgtblk_axis_valid(m_out_wgtblk_axis_valid),
		.m_out_wgtblk_axis_ready(m_out_wgtblk_axis_ready),
		
		.m0_kbuf_cmd_addr(m0_kbuf_cmd_addr),
		.m0_kbuf_cmd_read(m0_kbuf_cmd_read),
		.m0_kbuf_cmd_wdata(m0_kbuf_cmd_wdata),
		.m0_kbuf_cmd_wmask(m0_kbuf_cmd_wmask),
		.m0_kbuf_cmd_valid(m0_kbuf_cmd_valid),
		.m0_kbuf_cmd_ready(m0_kbuf_cmd_ready),
		.m0_kbuf_rsp_rdata(m0_kbuf_rsp_rdata),
		.m0_kbuf_rsp_err(m0_kbuf_rsp_err),
		.m0_kbuf_rsp_valid(m0_kbuf_rsp_valid),
		.m0_kbuf_rsp_ready(m0_kbuf_rsp_ready),
		
		.m1_kbuf_cmd_addr(m1_kbuf_cmd_addr),
		.m1_kbuf_cmd_read(m1_kbuf_cmd_read),
		.m1_kbuf_cmd_wdata(m1_kbuf_cmd_wdata),
		.m1_kbuf_cmd_wmask(m1_kbuf_cmd_wmask),
		.m1_kbuf_cmd_valid(m1_kbuf_cmd_valid),
		.m1_kbuf_cmd_ready(m1_kbuf_cmd_ready),
		.m1_kbuf_rsp_rdata(m1_kbuf_rsp_rdata),
		.m1_kbuf_rsp_err(m1_kbuf_rsp_err),
		.m1_kbuf_rsp_valid(m1_kbuf_rsp_valid),
		.m1_kbuf_rsp_ready(m1_kbuf_rsp_ready),
		
		.wt_rsv_rgn_actual_gid_mismatch()
	);
	
	conv_buffer #(
		.ATOMIC_C(ATOMIC_C),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.EN_EXCEED_BD_PROTECT("true"),
		.EN_HP_ICB("true"),
		.EN_ICB0_FMBUF_REG_SLICE("false"),
		.EN_ICB1_FMBUF_REG_SLICE("false"),
		.EN_ICB0_KBUF_REG_SLICE("false"),
		.EN_ICB1_KBUF_REG_SLICE("false"),
		.SIM_DELAY(simulation_delay)
	)conv_buffer_u(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.fmbufbankn(CBUF_BANK_N/2),
		
		.s0_fmbuf_cmd_addr(),
		.s0_fmbuf_cmd_read(),
		.s0_fmbuf_cmd_wdata(),
		.s0_fmbuf_cmd_wmask(),
		.s0_fmbuf_cmd_valid(1'b0),
		.s0_fmbuf_cmd_ready(),
		.s0_fmbuf_rsp_rdata(),
		.s0_fmbuf_rsp_err(),
		.s0_fmbuf_rsp_valid(),
		.s0_fmbuf_rsp_ready(1'b1),
		
		.s1_fmbuf_cmd_addr(),
		.s1_fmbuf_cmd_read(),
		.s1_fmbuf_cmd_wdata(),
		.s1_fmbuf_cmd_wmask(),
		.s1_fmbuf_cmd_valid(1'b0),
		.s1_fmbuf_cmd_ready(),
		.s1_fmbuf_rsp_rdata(),
		.s1_fmbuf_rsp_err(),
		.s1_fmbuf_rsp_valid(),
		.s1_fmbuf_rsp_ready(1'b1),
		
		.s0_kbuf_cmd_addr(m0_kbuf_cmd_addr),
		.s0_kbuf_cmd_read(m0_kbuf_cmd_read),
		.s0_kbuf_cmd_wdata(m0_kbuf_cmd_wdata),
		.s0_kbuf_cmd_wmask(m0_kbuf_cmd_wmask),
		.s0_kbuf_cmd_valid(m0_kbuf_cmd_valid),
		.s0_kbuf_cmd_ready(m0_kbuf_cmd_ready),
		.s0_kbuf_rsp_rdata(m0_kbuf_rsp_rdata),
		.s0_kbuf_rsp_err(m0_kbuf_rsp_err),
		.s0_kbuf_rsp_valid(m0_kbuf_rsp_valid),
		.s0_kbuf_rsp_ready(m0_kbuf_rsp_ready),
		
		.s1_kbuf_cmd_addr(m1_kbuf_cmd_addr),
		.s1_kbuf_cmd_read(m1_kbuf_cmd_read),
		.s1_kbuf_cmd_wdata(m1_kbuf_cmd_wdata),
		.s1_kbuf_cmd_wmask(m1_kbuf_cmd_wmask),
		.s1_kbuf_cmd_valid(m1_kbuf_cmd_valid),
		.s1_kbuf_cmd_ready(m1_kbuf_cmd_ready),
		.s1_kbuf_rsp_rdata(m1_kbuf_rsp_rdata),
		.s1_kbuf_rsp_err(m1_kbuf_rsp_err),
		.s1_kbuf_rsp_valid(m1_kbuf_rsp_valid),
		.s1_kbuf_rsp_ready(m1_kbuf_rsp_ready),
		
		.mem_clk_a(mem_clk_a),
		.mem_en_a(mem_en_a),
		.mem_wen_a(mem_wen_a),
		.mem_addr_a(mem_addr_a),
		.mem_din_a(mem_din_a),
		.mem_dout_a(mem_dout_a)
	);
	
	genvar mem_i;
	generate
		for(mem_i = 0;mem_i < CBUF_BANK_N;mem_i = mem_i + 1)
		begin:mem_blk
			bram_single_port #(
				.style("LOW_LATENCY"),
				.rw_mode("read_first"),
				.mem_width(ATOMIC_C*2*8),
				.mem_depth(CBUF_DEPTH_FOREACH_BANK),
				.INIT_FILE("no_init"),
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
	
endmodule
