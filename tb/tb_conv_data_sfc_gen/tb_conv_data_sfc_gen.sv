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

module tb_conv_data_sfc_gen();
	
	/** 配置参数 **/
	localparam integer STREAM_DATA_WIDTH = 32; // 特征图/卷积核数据流的数据位宽(32 | 64 | 128 | 256)
	localparam integer ATOMIC_C = 4; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	localparam integer EXTRA_DATA_WIDTH = 4; // 随路传输附加数据的位宽(必须>=1)
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(STREAM_DATA_WIDTH), .user_width(5+EXTRA_DATA_WIDTH)) m_stream_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(ATOMIC_C*2*8), .user_width(EXTRA_DATA_WIDTH)) s_sfc_axis_if(.clk(clk), .rst_n(rst_n));
	ConvDataSfcGenCvgSmpIf #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .ATOMIC_C(ATOMIC_C), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH)) cvg_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(STREAM_DATA_WIDTH), .user_width(5+EXTRA_DATA_WIDTH)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_stream_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(STREAM_DATA_WIDTH), .user_width(5+EXTRA_DATA_WIDTH)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_stream_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(EXTRA_DATA_WIDTH)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_sfc_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(ATOMIC_C*2*8), .user_width(EXTRA_DATA_WIDTH)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_sfc_axis_if.monitor);
		
		// 启动testcase
		run_test("ConvDataSfcGenCase0Test");
	end
	
	/** 待测模块 **/
	// 特征图/卷积核数据流(AXIS从机)
	wire[STREAM_DATA_WIDTH-1:0] s_stream_axis_data;
	wire[STREAM_DATA_WIDTH/8-1:0] s_stream_axis_keep;
	wire[5+EXTRA_DATA_WIDTH-1:0] s_stream_axis_user; // {随路传输附加数据(EXTRA_DATA_WIDTH bit), 每个表面的有效数据个数 - 1(5bit)}
	wire s_stream_axis_last;
	wire s_stream_axis_valid;
	wire s_stream_axis_ready;
	// 特征图/卷积核表面流(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_sfc_axis_data;
	wire[ATOMIC_C*2-1:0] m_sfc_axis_keep;
	wire[EXTRA_DATA_WIDTH-1:0] m_sfc_axis_user; // {随路传输附加数据(EXTRA_DATA_WIDTH bit)}
	wire m_sfc_axis_last;
	wire m_sfc_axis_valid;
	wire m_sfc_axis_ready;
	
	assign s_stream_axis_data = m_stream_axis_if.data;
	assign s_stream_axis_keep = m_stream_axis_if.keep;
	assign s_stream_axis_user = m_stream_axis_if.user;
	assign s_stream_axis_last = m_stream_axis_if.last;
	assign s_stream_axis_valid = m_stream_axis_if.valid;
	assign m_stream_axis_if.ready = s_stream_axis_ready;
	
	assign s_sfc_axis_if.data = m_sfc_axis_data;
	assign s_sfc_axis_if.keep = m_sfc_axis_keep;
	assign s_sfc_axis_if.user = m_sfc_axis_user;
	assign s_sfc_axis_if.last = m_sfc_axis_last;
	assign s_sfc_axis_if.valid = m_sfc_axis_valid;
	assign m_sfc_axis_ready = s_sfc_axis_if.ready;
	
	assign cvg_if.strm_pkt_msg_fifo_wen = dut.strm_pkt_msg_fifo_wen;
	assign cvg_if.strm_pkt_msg_fifo_din = dut.strm_pkt_msg_fifo_din;
	assign cvg_if.strm_pkt_msg_fifo_full_n = dut.strm_pkt_msg_fifo_full_n;
	assign cvg_if.strm_pkt_msg_fifo_ren = dut.strm_pkt_msg_fifo_ren;
	assign cvg_if.strm_pkt_msg_fifo_dout = dut.strm_pkt_msg_fifo_dout;
	assign cvg_if.strm_pkt_msg_fifo_empty_n = dut.strm_pkt_msg_fifo_empty_n;
	assign cvg_if.s_stream_axis_hs = s_stream_axis_valid & s_stream_axis_ready;
	assign cvg_if.m_sfc_axis_hs = m_sfc_axis_valid & m_sfc_axis_ready;
	assign cvg_if.hw_stored_cnt = dut.hw_stored_cnt;
	assign cvg_if.hw_buf_wptr = dut.hw_buf_wptr;
	assign cvg_if.hw_buf_rptr = dut.hw_buf_rptr;
	assign cvg_if.vld_hw_n_sub1_of_cur_strm_trans = dut.vld_hw_n_sub1_of_cur_strm_trans;
	
	conv_data_sfc_gen #(
		.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH),
		.ATOMIC_C(ATOMIC_C),
		.EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		.aclken(1'b1),
		
		.s_stream_axis_data(s_stream_axis_data),
		.s_stream_axis_keep(s_stream_axis_keep),
		.s_stream_axis_user(s_stream_axis_user),
		.s_stream_axis_last(s_stream_axis_last),
		.s_stream_axis_valid(s_stream_axis_valid),
		.s_stream_axis_ready(s_stream_axis_ready),
		
		.m_sfc_axis_data(m_sfc_axis_data),
		.m_sfc_axis_keep(m_sfc_axis_keep),
		.m_sfc_axis_user(m_sfc_axis_user),
		.m_sfc_axis_last(m_sfc_axis_last),
		.m_sfc_axis_valid(m_sfc_axis_valid),
		.m_sfc_axis_ready(m_sfc_axis_ready)
	);
	
endmodule
