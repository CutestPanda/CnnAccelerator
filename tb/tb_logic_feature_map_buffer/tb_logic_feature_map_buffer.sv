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

module tb_logic_feature_map_buffer();
	
	/** 常量 **/
	// 每个表面行的表面个数类型编码
	localparam FMBUFCOLN_32 = 3'b000;
	localparam FMBUFCOLN_64 = 3'b001;
	localparam FMBUFCOLN_128 = 3'b010;
	localparam FMBUFCOLN_256 = 3'b011;
	localparam FMBUFCOLN_512 = 3'b100;
	localparam FMBUFCOLN_1024 = 3'b101;
	localparam FMBUFCOLN_2048 = 3'b110;
	localparam FMBUFCOLN_4096 = 3'b111;
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer MAX_FMBUF_ROWN = 512; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	localparam integer ATOMIC_C = 2; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	localparam integer CBUF_BANK_N = 4; // 缓存MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	localparam integer CBUF_DEPTH_FOREACH_BANK = 512; // 每片缓存MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	// 运行时参数
	localparam bit[2:0] fmbufcoln = FMBUFCOLN_128; // 每个表面行的表面个数类型
	localparam bit[9:0] fmbufrown = 10'd8 - 1; // 表面行数 - 1
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(ATOMIC_C*2*8), .user_width(10)) m_fin_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(40), .user_width(0)) m_rd_req_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(ATOMIC_C*2*8), .user_width(1)) s_fout_axis_if(.clk(clk), .rst_n(rst_n));
	ReqAck #(.out_drive_t(simulation_delay), .req_payload_width(0), .resp_payload_width(0)) rst_buf_if(.clk(clk), .rst_n(rst_n));
	ReqAck #(.out_drive_t(simulation_delay), .req_payload_width(10), .resp_payload_width(0)) sfc_row_rplc_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(10)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_fin_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(10)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_fin_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(40), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", m_rd_req_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(40), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", m_rd_req_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(1)).slave)::set(null, 
			"uvm_test_top.env.agt3.drv", "axis_if", s_fout_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(1)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "axis_if", s_fout_axis_if.monitor);
		
		uvm_config_db #(virtual ReqAck #(.out_drive_t(simulation_delay), 
			.req_payload_width(0), .resp_payload_width(0)).master)::set(null, 
			"uvm_test_top.env.agt4.drv", "req_ack_if", rst_buf_if.master);
		uvm_config_db #(virtual ReqAck #(.out_drive_t(simulation_delay), 
			.req_payload_width(0), .resp_payload_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt4.mon", "req_ack_if", rst_buf_if.monitor);
		
		uvm_config_db #(virtual ReqAck #(.out_drive_t(simulation_delay), 
			.req_payload_width(10), .resp_payload_width(0)).master)::set(null, 
			"uvm_test_top.env.agt5.drv", "req_ack_if", sfc_row_rplc_if.master);
		uvm_config_db #(virtual ReqAck #(.out_drive_t(simulation_delay), 
			.req_payload_width(10), .resp_payload_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt5.mon", "req_ack_if", sfc_row_rplc_if.monitor);
		
		// 启动testcase
		run_test("LogicFmapBufferCase0Test");
	end
	
	/** 待测模块 **/
	// 控制/状态
	wire rst_logic_fmbuf; // 重置逻辑特征图缓存
	wire sfc_row_rplc_req; // 表面行置换请求
	wire[9:0] sfc_rid_to_rplc; // 待置换的表面行编号
	wire sfc_row_rplc_pending; // 表面行置换等待标志
	wire init_fns; // 初始化完成(标志)
	// 特征图表面行数据输入(AXIS从机)
	wire[ATOMIC_C*2*8-1:0] s_fin_axis_data;
	wire[9:0] s_fin_axis_user; // 表面行的缓存编号
	wire s_fin_axis_last; // 标志当前表面行的最后1个表面
	wire s_fin_axis_valid;
	wire s_fin_axis_ready;
	// 特征图表面行读请求(AXIS从机)
	/*
	{
		保留(5bit), 
		是否需要自动置换表面行(1bit), 
		表面行的缓存编号(10bit), 
		起始表面编号(12bit), 
		待读取的表面个数 - 1(12bit)
	}
	*/
	wire[39:0] s_rd_req_axis_data;
	wire s_rd_req_axis_valid;
	wire s_rd_req_axis_ready;
	// 特征图表面行数据输出(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_fout_axis_data;
	wire m_fout_axis_user; // 标志表面行未缓存
	wire m_fout_axis_last; // 标志本次读请求的最后1个表面
	wire m_fout_axis_valid;
	wire m_fout_axis_ready;
	// 特征图缓存ICB从机#0
	// [命令通道]
	wire[31:0] m0_fmbuf_cmd_addr;
	wire m0_fmbuf_cmd_read; // const -> 1'b0
	wire[ATOMIC_C*2*8-1:0] m0_fmbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] m0_fmbuf_cmd_wmask; // const -> {(ATOMIC_C*2){1'b1}}
	wire m0_fmbuf_cmd_valid;
	wire m0_fmbuf_cmd_ready;
	// [响应通道]
	wire[ATOMIC_C*2*8-1:0] m0_fmbuf_rsp_rdata; // ignored
	wire m0_fmbuf_rsp_err; // ignored
	wire m0_fmbuf_rsp_valid;
	wire m0_fmbuf_rsp_ready; // const -> 1'b1
	// 特征图缓存ICB从机#1
	// [命令通道]
	wire[31:0] m1_fmbuf_cmd_addr;
	wire m1_fmbuf_cmd_read; // const -> 1'b1
	wire[ATOMIC_C*2*8-1:0] m1_fmbuf_cmd_wdata; // not care
	wire[ATOMIC_C*2-1:0] m1_fmbuf_cmd_wmask; // not care
	wire m1_fmbuf_cmd_valid;
	wire m1_fmbuf_cmd_ready;
	// [响应通道]
	wire[ATOMIC_C*2*8-1:0] m1_fmbuf_rsp_rdata;
	wire m1_fmbuf_rsp_err; // ignored
	wire m1_fmbuf_rsp_valid;
	wire m1_fmbuf_rsp_ready;
	// 表面行有效标志MEM
	wire sfc_row_vld_flag_mem_clk;
	wire sfc_row_vld_flag_mem_en;
	wire sfc_row_vld_flag_mem_wen;
	wire[9:0] sfc_row_vld_flag_mem_addr;
	wire sfc_row_vld_flag_mem_din;
	wire sfc_row_vld_flag_mem_dout;
	// 缓存MEM主接口
	wire mem_clk_a;
	wire[CBUF_BANK_N-1:0] mem_en_a;
	wire[CBUF_BANK_N*ATOMIC_C*2-1:0] mem_wen_a;
	wire[CBUF_BANK_N*16-1:0] mem_addr_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] mem_din_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] mem_dout_a;
	
	assign rst_logic_fmbuf = rst_buf_if.req;
	assign rst_buf_if.ack = 1'b1;
	
	assign sfc_row_rplc_req = sfc_row_rplc_if.req;
	assign sfc_rid_to_rplc = sfc_row_rplc_if.req_payload;
	assign sfc_row_rplc_if.ack = 1'b1;
	
	assign s_fin_axis_data = m_fin_axis_if.data;
	assign s_fin_axis_user = m_fin_axis_if.user;
	assign s_fin_axis_last = m_fin_axis_if.last;
	assign s_fin_axis_valid = m_fin_axis_if.valid;
	assign m_fin_axis_if.ready = s_fin_axis_ready;
	
	assign s_rd_req_axis_data = m_rd_req_axis_if.data;
	assign s_rd_req_axis_valid = m_rd_req_axis_if.valid;
	assign m_rd_req_axis_if.ready = s_rd_req_axis_ready;
	
	assign s_fout_axis_if.data = m_fout_axis_data;
	assign s_fout_axis_if.user = m_fout_axis_user;
	assign s_fout_axis_if.last = m_fout_axis_last;
	assign s_fout_axis_if.valid = m_fout_axis_valid;
	assign m_fout_axis_ready = s_fout_axis_if.ready;
	
	logic_feature_map_buffer #(
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.ATOMIC_C(ATOMIC_C),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.fmbufcoln(fmbufcoln),
		.fmbufrown(fmbufrown),
		
		.rst_logic_fmbuf(rst_logic_fmbuf),
		.sfc_row_rplc_req(sfc_row_rplc_req),
		.sfc_rid_to_rplc(sfc_rid_to_rplc),
		.sfc_row_rplc_pending(sfc_row_rplc_pending),
		.init_fns(init_fns),
		
		.s_fin_axis_data(s_fin_axis_data),
		.s_fin_axis_user(s_fin_axis_user),
		.s_fin_axis_last(s_fin_axis_last),
		.s_fin_axis_valid(s_fin_axis_valid),
		.s_fin_axis_ready(s_fin_axis_ready),
		
		.s_rd_req_axis_data(s_rd_req_axis_data),
		.s_rd_req_axis_valid(s_rd_req_axis_valid),
		.s_rd_req_axis_ready(s_rd_req_axis_ready),
		
		.m_fout_axis_data(m_fout_axis_data),
		.m_fout_axis_user(m_fout_axis_user),
		.m_fout_axis_last(m_fout_axis_last),
		.m_fout_axis_valid(m_fout_axis_valid),
		.m_fout_axis_ready(m_fout_axis_ready),
		
		.m0_fmbuf_cmd_addr(m0_fmbuf_cmd_addr),
		.m0_fmbuf_cmd_read(m0_fmbuf_cmd_read),
		.m0_fmbuf_cmd_wdata(m0_fmbuf_cmd_wdata),
		.m0_fmbuf_cmd_wmask(m0_fmbuf_cmd_wmask),
		.m0_fmbuf_cmd_valid(m0_fmbuf_cmd_valid),
		.m0_fmbuf_cmd_ready(m0_fmbuf_cmd_ready),
		.m0_fmbuf_rsp_rdata(m0_fmbuf_rsp_rdata),
		.m0_fmbuf_rsp_err(m0_fmbuf_rsp_err),
		.m0_fmbuf_rsp_valid(m0_fmbuf_rsp_valid),
		.m0_fmbuf_rsp_ready(m0_fmbuf_rsp_ready),
		
		.m1_fmbuf_cmd_addr(m1_fmbuf_cmd_addr),
		.m1_fmbuf_cmd_read(m1_fmbuf_cmd_read),
		.m1_fmbuf_cmd_wdata(m1_fmbuf_cmd_wdata),
		.m1_fmbuf_cmd_wmask(m1_fmbuf_cmd_wmask),
		.m1_fmbuf_cmd_valid(m1_fmbuf_cmd_valid),
		.m1_fmbuf_cmd_ready(m1_fmbuf_cmd_ready),
		.m1_fmbuf_rsp_rdata(m1_fmbuf_rsp_rdata),
		.m1_fmbuf_rsp_err(m1_fmbuf_rsp_err),
		.m1_fmbuf_rsp_valid(m1_fmbuf_rsp_valid),
		.m1_fmbuf_rsp_ready(m1_fmbuf_rsp_ready),
		
		.sfc_row_vld_flag_mem_clk(sfc_row_vld_flag_mem_clk),
		.sfc_row_vld_flag_mem_en(sfc_row_vld_flag_mem_en),
		.sfc_row_vld_flag_mem_wen(sfc_row_vld_flag_mem_wen),
		.sfc_row_vld_flag_mem_addr(sfc_row_vld_flag_mem_addr),
		.sfc_row_vld_flag_mem_din(sfc_row_vld_flag_mem_din),
		.sfc_row_vld_flag_mem_dout(sfc_row_vld_flag_mem_dout)
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
		
		.s0_fmbuf_cmd_addr(m0_fmbuf_cmd_addr),
		.s0_fmbuf_cmd_read(m0_fmbuf_cmd_read),
		.s0_fmbuf_cmd_wdata(m0_fmbuf_cmd_wdata),
		.s0_fmbuf_cmd_wmask(m0_fmbuf_cmd_wmask),
		.s0_fmbuf_cmd_valid(m0_fmbuf_cmd_valid),
		.s0_fmbuf_cmd_ready(m0_fmbuf_cmd_ready),
		.s0_fmbuf_rsp_rdata(m0_fmbuf_rsp_rdata),
		.s0_fmbuf_rsp_err(m0_fmbuf_rsp_err),
		.s0_fmbuf_rsp_valid(m0_fmbuf_rsp_valid),
		.s0_fmbuf_rsp_ready(m0_fmbuf_rsp_ready),
		
		.s1_fmbuf_cmd_addr(m1_fmbuf_cmd_addr),
		.s1_fmbuf_cmd_read(m1_fmbuf_cmd_read),
		.s1_fmbuf_cmd_wdata(m1_fmbuf_cmd_wdata),
		.s1_fmbuf_cmd_wmask(m1_fmbuf_cmd_wmask),
		.s1_fmbuf_cmd_valid(m1_fmbuf_cmd_valid),
		.s1_fmbuf_cmd_ready(m1_fmbuf_cmd_ready),
		.s1_fmbuf_rsp_rdata(m1_fmbuf_rsp_rdata),
		.s1_fmbuf_rsp_err(m1_fmbuf_rsp_err),
		.s1_fmbuf_rsp_valid(m1_fmbuf_rsp_valid),
		.s1_fmbuf_rsp_ready(m1_fmbuf_rsp_ready),
		
		.s0_kbuf_cmd_addr(),
		.s0_kbuf_cmd_read(),
		.s0_kbuf_cmd_wdata(),
		.s0_kbuf_cmd_wmask(),
		.s0_kbuf_cmd_valid(1'b0),
		.s0_kbuf_cmd_ready(),
		.s0_kbuf_rsp_rdata(),
		.s0_kbuf_rsp_err(),
		.s0_kbuf_rsp_valid(),
		.s0_kbuf_rsp_ready(1'b1),
		
		.s1_kbuf_cmd_addr(),
		.s1_kbuf_cmd_read(),
		.s1_kbuf_cmd_wdata(),
		.s1_kbuf_cmd_wmask(),
		.s1_kbuf_cmd_valid(1'b0),
		.s1_kbuf_cmd_ready(),
		.s1_kbuf_rsp_rdata(),
		.s1_kbuf_rsp_err(),
		.s1_kbuf_rsp_valid(),
		.s1_kbuf_rsp_ready(1'b1),
		
		.mem_clk_a(mem_clk_a),
		.mem_en_a(mem_en_a),
		.mem_wen_a(mem_wen_a),
		.mem_addr_a(mem_addr_a),
		.mem_din_a(mem_din_a),
		.mem_dout_a(mem_dout_a)
	);
	
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("read_first"),
		.mem_width(1),
		.mem_depth(1024),
		.INIT_FILE("no_init"),
		.byte_write_mode("false"),
		.simulation_delay(simulation_delay)
	)sfc_row_vld_flag_mem_u(
		.clk(sfc_row_vld_flag_mem_clk),
		
		.en(sfc_row_vld_flag_mem_en),
		.wen(sfc_row_vld_flag_mem_wen),
		.addr(sfc_row_vld_flag_mem_addr),
		.din(sfc_row_vld_flag_mem_din),
		.dout(sfc_row_vld_flag_mem_dout)
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
