/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
本模块: 卷积私有缓存

描述:
对ICB从机添加了AXIS寄存器片后的卷积私有缓存

注意：
ICB从机不支持非对齐传输(地址必须对齐到ATOMIC_C*2字节)

协议:
ICB SLAVE
MEM MASTER

作者: 陈家耀
日期: 2025/03/28
********************************************************************/


module conv_buffer #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer CBUF_BANK_N = 32, // 缓存MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 512, // 每片缓存MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter EN_EXCEED_BD_PROTECT = "true", // 是否启用逻辑地址越界保护
	parameter EN_HP_ICB = "true", // 是否启用高性能ICB从机
	parameter EN_ICB0_FMBUF_REG_SLICE = "true", // 是否在特征图缓存0号ICB插入AXIS寄存器片
	parameter EN_ICB1_FMBUF_REG_SLICE = "true", // 是否在特征图缓存1号ICB插入AXIS寄存器片
	parameter EN_ICB0_KBUF_REG_SLICE = "true", // 是否在卷积核缓存0号ICB插入AXIS寄存器片
	parameter EN_ICB1_KBUF_REG_SLICE = "true", // 是否在卷积核缓存1号ICB插入AXIS寄存器片
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[7:0] fmbufbankn, // 分配给特征图缓存的Bank数
	
	// 特征图缓存ICB从机#0
	// 命令通道
	input wire[31:0] s0_fmbuf_cmd_addr,
	input wire s0_fmbuf_cmd_read,
	input wire[ATOMIC_C*2*8-1:0] s0_fmbuf_cmd_wdata,
	input wire[ATOMIC_C*2-1:0] s0_fmbuf_cmd_wmask,
	input wire s0_fmbuf_cmd_valid,
	output wire s0_fmbuf_cmd_ready,
	// 响应通道
	output wire[ATOMIC_C*2*8-1:0] s0_fmbuf_rsp_rdata,
	output wire s0_fmbuf_rsp_err,
	output wire s0_fmbuf_rsp_valid,
	input wire s0_fmbuf_rsp_ready,
	
	// 特征图缓存ICB从机#1
	// 命令通道
	input wire[31:0] s1_fmbuf_cmd_addr,
	input wire s1_fmbuf_cmd_read,
	input wire[ATOMIC_C*2*8-1:0] s1_fmbuf_cmd_wdata,
	input wire[ATOMIC_C*2-1:0] s1_fmbuf_cmd_wmask,
	input wire s1_fmbuf_cmd_valid,
	output wire s1_fmbuf_cmd_ready,
	// 响应通道
	output wire[ATOMIC_C*2*8-1:0] s1_fmbuf_rsp_rdata,
	output wire s1_fmbuf_rsp_err,
	output wire s1_fmbuf_rsp_valid,
	input wire s1_fmbuf_rsp_ready,
	
	// 卷积核缓存ICB从机#0
	// 命令通道
	input wire[31:0] s0_kbuf_cmd_addr,
	input wire s0_kbuf_cmd_read,
	input wire[ATOMIC_C*2*8-1:0] s0_kbuf_cmd_wdata,
	input wire[ATOMIC_C*2-1:0] s0_kbuf_cmd_wmask,
	input wire s0_kbuf_cmd_valid,
	output wire s0_kbuf_cmd_ready,
	// 响应通道
	output wire[ATOMIC_C*2*8-1:0] s0_kbuf_rsp_rdata,
	output wire s0_kbuf_rsp_err,
	output wire s0_kbuf_rsp_valid,
	input wire s0_kbuf_rsp_ready,
	
	// 卷积核缓存ICB从机#1
	// 命令通道
	input wire[31:0] s1_kbuf_cmd_addr,
	input wire s1_kbuf_cmd_read,
	input wire[ATOMIC_C*2*8-1:0] s1_kbuf_cmd_wdata,
	input wire[ATOMIC_C*2-1:0] s1_kbuf_cmd_wmask,
	input wire s1_kbuf_cmd_valid,
	output wire s1_kbuf_cmd_ready,
	// 响应通道
	output wire[ATOMIC_C*2*8-1:0] s1_kbuf_rsp_rdata,
	output wire s1_kbuf_rsp_err,
	output wire s1_kbuf_rsp_valid,
	input wire s1_kbuf_rsp_ready,
	
	// 缓存MEM主接口
	output wire mem_clk_a,
	output wire[CBUF_BANK_N-1:0] mem_en_a,
	output wire[CBUF_BANK_N*ATOMIC_C*2-1:0] mem_wen_a,
	output wire[CBUF_BANK_N*16-1:0] mem_addr_a,
	output wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] mem_din_a,
	input wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] mem_dout_a
);
	
	/** 卷积私有缓存(核心) **/
	// 特征图缓存ICB从机#0
	// 命令通道
	wire[31:0] m0_fmbuf_cmd_addr;
	wire m0_fmbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] m0_fmbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] m0_fmbuf_cmd_wmask;
	wire m0_fmbuf_cmd_valid;
	wire m0_fmbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] m0_fmbuf_rsp_rdata;
	wire m0_fmbuf_rsp_err;
	wire m0_fmbuf_rsp_valid;
	wire m0_fmbuf_rsp_ready;
	// 特征图缓存ICB从机#1
	// 命令通道
	wire[31:0] m1_fmbuf_cmd_addr;
	wire m1_fmbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] m1_fmbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] m1_fmbuf_cmd_wmask;
	wire m1_fmbuf_cmd_valid;
	wire m1_fmbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] m1_fmbuf_rsp_rdata;
	wire m1_fmbuf_rsp_err;
	wire m1_fmbuf_rsp_valid;
	wire m1_fmbuf_rsp_ready;
	// 卷积核缓存ICB从机#0
	// 命令通道
	wire[31:0] m0_kbuf_cmd_addr;
	wire m0_kbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] m0_kbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] m0_kbuf_cmd_wmask;
	wire m0_kbuf_cmd_valid;
	wire m0_kbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] m0_kbuf_rsp_rdata;
	wire m0_kbuf_rsp_err;
	wire m0_kbuf_rsp_valid;
	wire m0_kbuf_rsp_ready;
	// 卷积核缓存ICB从机#1
	// 命令通道
	wire[31:0] m1_kbuf_cmd_addr;
	wire m1_kbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] m1_kbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] m1_kbuf_cmd_wmask;
	wire m1_kbuf_cmd_valid;
	wire m1_kbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] m1_kbuf_rsp_rdata;
	wire m1_kbuf_rsp_err;
	wire m1_kbuf_rsp_valid;
	wire m1_kbuf_rsp_ready;
	
	conv_buffer_core #(
		.ATOMIC_C(ATOMIC_C),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.EN_EXCEED_BD_PROTECT(EN_EXCEED_BD_PROTECT),
		.EN_HP_ICB(EN_HP_ICB),
		.SIM_DELAY(SIM_DELAY)
	)conv_buffer_core_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.fmbufbankn(fmbufbankn),
		
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
	
	/** 特征图缓存ICB从机#0 **/
	// 命令通道AXIS寄存器片
	wire[ATOMIC_C*2*8-1:0] s0_reg_slice_axis_data;
	wire[ATOMIC_C*2-1:0] s0_reg_slice_axis_keep;
	wire[32:0] s0_reg_slice_axis_user; // {read(1bit), addr(32bit)}
	wire s0_reg_slice_axis_valid;
	wire s0_reg_slice_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m0_reg_slice_axis_data;
	wire[ATOMIC_C*2-1:0] m0_reg_slice_axis_keep;
	wire[32:0] m0_reg_slice_axis_user; // {read(1bit), addr(32bit)}
	wire m0_reg_slice_axis_valid;
	wire m0_reg_slice_axis_ready;
	// 响应通道AXIS寄存器片
	wire[ATOMIC_C*2*8-1:0] s1_reg_slice_axis_data;
	wire s1_reg_slice_axis_user; // {err(1bit)}
	wire s1_reg_slice_axis_valid;
	wire s1_reg_slice_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m1_reg_slice_axis_data;
	wire m1_reg_slice_axis_user; // {err(1bit)}
	wire m1_reg_slice_axis_valid;
	wire m1_reg_slice_axis_ready;
	
	assign s0_reg_slice_axis_data = s0_fmbuf_cmd_wdata;
	assign s0_reg_slice_axis_keep = s0_fmbuf_cmd_wmask;
	assign s0_reg_slice_axis_user = {s0_fmbuf_cmd_read, s0_fmbuf_cmd_addr};
	assign s0_reg_slice_axis_valid = s0_fmbuf_cmd_valid;
	assign s0_fmbuf_cmd_ready = s0_reg_slice_axis_ready;
	
	assign m0_fmbuf_cmd_wdata = m0_reg_slice_axis_data;
	assign m0_fmbuf_cmd_wmask = m0_reg_slice_axis_keep;
	assign {m0_fmbuf_cmd_read, m0_fmbuf_cmd_addr} = m0_reg_slice_axis_user;
	assign m0_fmbuf_cmd_valid = m0_reg_slice_axis_valid;
	assign m0_reg_slice_axis_ready = m0_fmbuf_cmd_ready;
	
	assign s1_reg_slice_axis_data = m0_fmbuf_rsp_rdata;
	assign s1_reg_slice_axis_user = m0_fmbuf_rsp_err;
	assign s1_reg_slice_axis_valid = m0_fmbuf_rsp_valid;
	assign m0_fmbuf_rsp_ready = s1_reg_slice_axis_ready;
	
	assign s0_fmbuf_rsp_rdata = m1_reg_slice_axis_data;
	assign s0_fmbuf_rsp_err = m1_reg_slice_axis_user;
	assign s0_fmbuf_rsp_valid = m1_reg_slice_axis_valid;
	assign m1_reg_slice_axis_ready = s0_fmbuf_rsp_ready;
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(33),
		.forward_registered(EN_ICB0_FMBUF_REG_SLICE),
		.back_registered(EN_ICB0_FMBUF_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u0(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s0_reg_slice_axis_data),
		.s_axis_keep(s0_reg_slice_axis_keep),
		.s_axis_user(s0_reg_slice_axis_user),
		.s_axis_valid(s0_reg_slice_axis_valid),
		.s_axis_ready(s0_reg_slice_axis_ready),
		
		.m_axis_data(m0_reg_slice_axis_data),
		.m_axis_keep(m0_reg_slice_axis_keep),
		.m_axis_user(m0_reg_slice_axis_user),
		.m_axis_valid(m0_reg_slice_axis_valid),
		.m_axis_ready(m0_reg_slice_axis_ready)
	);
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(1),
		.forward_registered(EN_ICB0_FMBUF_REG_SLICE),
		.back_registered(EN_ICB0_FMBUF_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u1(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s1_reg_slice_axis_data),
		.s_axis_user(s1_reg_slice_axis_user),
		.s_axis_valid(s1_reg_slice_axis_valid),
		.s_axis_ready(s1_reg_slice_axis_ready),
		
		.m_axis_data(m1_reg_slice_axis_data),
		.m_axis_user(m1_reg_slice_axis_user),
		.m_axis_valid(m1_reg_slice_axis_valid),
		.m_axis_ready(m1_reg_slice_axis_ready)
	);
	
	/** 特征图缓存ICB从机#1 **/
	// 命令通道AXIS寄存器片
	wire[ATOMIC_C*2*8-1:0] s2_reg_slice_axis_data;
	wire[ATOMIC_C*2-1:0] s2_reg_slice_axis_keep;
	wire[32:0] s2_reg_slice_axis_user; // {read(1bit), addr(32bit)}
	wire s2_reg_slice_axis_valid;
	wire s2_reg_slice_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m2_reg_slice_axis_data;
	wire[ATOMIC_C*2-1:0] m2_reg_slice_axis_keep;
	wire[32:0] m2_reg_slice_axis_user; // {read(1bit), addr(32bit)}
	wire m2_reg_slice_axis_valid;
	wire m2_reg_slice_axis_ready;
	// 响应通道AXIS寄存器片
	wire[ATOMIC_C*2*8-1:0] s3_reg_slice_axis_data;
	wire s3_reg_slice_axis_user; // {err(1bit)}
	wire s3_reg_slice_axis_valid;
	wire s3_reg_slice_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m3_reg_slice_axis_data;
	wire m3_reg_slice_axis_user; // {err(1bit)}
	wire m3_reg_slice_axis_valid;
	wire m3_reg_slice_axis_ready;
	
	assign s2_reg_slice_axis_data = s1_fmbuf_cmd_wdata;
	assign s2_reg_slice_axis_keep = s1_fmbuf_cmd_wmask;
	assign s2_reg_slice_axis_user = {s1_fmbuf_cmd_read, s1_fmbuf_cmd_addr};
	assign s2_reg_slice_axis_valid = s1_fmbuf_cmd_valid;
	assign s1_fmbuf_cmd_ready = s2_reg_slice_axis_ready;
	
	assign m1_fmbuf_cmd_wdata = m2_reg_slice_axis_data;
	assign m1_fmbuf_cmd_wmask = m2_reg_slice_axis_keep;
	assign {m1_fmbuf_cmd_read, m1_fmbuf_cmd_addr} = m2_reg_slice_axis_user;
	assign m1_fmbuf_cmd_valid = m2_reg_slice_axis_valid;
	assign m2_reg_slice_axis_ready = m1_fmbuf_cmd_ready;
	
	assign s3_reg_slice_axis_data = m1_fmbuf_rsp_rdata;
	assign s3_reg_slice_axis_user = m1_fmbuf_rsp_err;
	assign s3_reg_slice_axis_valid = m1_fmbuf_rsp_valid;
	assign m1_fmbuf_rsp_ready = s3_reg_slice_axis_ready;
	
	assign s1_fmbuf_rsp_rdata = m3_reg_slice_axis_data;
	assign s1_fmbuf_rsp_err = m3_reg_slice_axis_user;
	assign s1_fmbuf_rsp_valid = m3_reg_slice_axis_valid;
	assign m3_reg_slice_axis_ready = s1_fmbuf_rsp_ready;
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(33),
		.forward_registered(EN_ICB1_FMBUF_REG_SLICE),
		.back_registered(EN_ICB1_FMBUF_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u2(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s2_reg_slice_axis_data),
		.s_axis_keep(s2_reg_slice_axis_keep),
		.s_axis_user(s2_reg_slice_axis_user),
		.s_axis_valid(s2_reg_slice_axis_valid),
		.s_axis_ready(s2_reg_slice_axis_ready),
		
		.m_axis_data(m2_reg_slice_axis_data),
		.m_axis_keep(m2_reg_slice_axis_keep),
		.m_axis_user(m2_reg_slice_axis_user),
		.m_axis_valid(m2_reg_slice_axis_valid),
		.m_axis_ready(m2_reg_slice_axis_ready)
	);
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(1),
		.forward_registered(EN_ICB1_FMBUF_REG_SLICE),
		.back_registered(EN_ICB1_FMBUF_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u3(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s3_reg_slice_axis_data),
		.s_axis_user(s3_reg_slice_axis_user),
		.s_axis_valid(s3_reg_slice_axis_valid),
		.s_axis_ready(s3_reg_slice_axis_ready),
		
		.m_axis_data(m3_reg_slice_axis_data),
		.m_axis_user(m3_reg_slice_axis_user),
		.m_axis_valid(m3_reg_slice_axis_valid),
		.m_axis_ready(m3_reg_slice_axis_ready)
	);
	
	/** 卷积核缓存ICB从机#0 **/
	// 命令通道AXIS寄存器片
	wire[ATOMIC_C*2*8-1:0] s4_reg_slice_axis_data;
	wire[ATOMIC_C*2-1:0] s4_reg_slice_axis_keep;
	wire[32:0] s4_reg_slice_axis_user; // {read(1bit), addr(32bit)}
	wire s4_reg_slice_axis_valid;
	wire s4_reg_slice_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m4_reg_slice_axis_data;
	wire[ATOMIC_C*2-1:0] m4_reg_slice_axis_keep;
	wire[32:0] m4_reg_slice_axis_user; // {read(1bit), addr(32bit)}
	wire m4_reg_slice_axis_valid;
	wire m4_reg_slice_axis_ready;
	// 响应通道AXIS寄存器片
	wire[ATOMIC_C*2*8-1:0] s5_reg_slice_axis_data;
	wire s5_reg_slice_axis_user; // {err(1bit)}
	wire s5_reg_slice_axis_valid;
	wire s5_reg_slice_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m5_reg_slice_axis_data;
	wire m5_reg_slice_axis_user; // {err(1bit)}
	wire m5_reg_slice_axis_valid;
	wire m5_reg_slice_axis_ready;
	
	assign s4_reg_slice_axis_data = s0_kbuf_cmd_wdata;
	assign s4_reg_slice_axis_keep = s0_kbuf_cmd_wmask;
	assign s4_reg_slice_axis_user = {s0_kbuf_cmd_read, s0_kbuf_cmd_addr};
	assign s4_reg_slice_axis_valid = s0_kbuf_cmd_valid;
	assign s0_kbuf_cmd_ready = s4_reg_slice_axis_ready;
	
	assign m0_kbuf_cmd_wdata = m4_reg_slice_axis_data;
	assign m0_kbuf_cmd_wmask = m4_reg_slice_axis_keep;
	assign {m0_kbuf_cmd_read, m0_kbuf_cmd_addr} = m4_reg_slice_axis_user;
	assign m0_kbuf_cmd_valid = m4_reg_slice_axis_valid;
	assign m4_reg_slice_axis_ready = m0_kbuf_cmd_ready;
	
	assign s5_reg_slice_axis_data = m0_kbuf_rsp_rdata;
	assign s5_reg_slice_axis_user = m0_kbuf_rsp_err;
	assign s5_reg_slice_axis_valid = m0_kbuf_rsp_valid;
	assign m0_kbuf_rsp_ready = s5_reg_slice_axis_ready;
	
	assign s0_kbuf_rsp_rdata = m5_reg_slice_axis_data;
	assign s0_kbuf_rsp_err = m5_reg_slice_axis_user;
	assign s0_kbuf_rsp_valid = m5_reg_slice_axis_valid;
	assign m5_reg_slice_axis_ready = s0_kbuf_rsp_ready;
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(33),
		.forward_registered(EN_ICB0_KBUF_REG_SLICE),
		.back_registered(EN_ICB0_KBUF_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u4(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s4_reg_slice_axis_data),
		.s_axis_keep(s4_reg_slice_axis_keep),
		.s_axis_user(s4_reg_slice_axis_user),
		.s_axis_valid(s4_reg_slice_axis_valid),
		.s_axis_ready(s4_reg_slice_axis_ready),
		
		.m_axis_data(m4_reg_slice_axis_data),
		.m_axis_keep(m4_reg_slice_axis_keep),
		.m_axis_user(m4_reg_slice_axis_user),
		.m_axis_valid(m4_reg_slice_axis_valid),
		.m_axis_ready(m4_reg_slice_axis_ready)
	);
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(1),
		.forward_registered(EN_ICB0_KBUF_REG_SLICE),
		.back_registered(EN_ICB0_KBUF_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u5(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s5_reg_slice_axis_data),
		.s_axis_user(s5_reg_slice_axis_user),
		.s_axis_valid(s5_reg_slice_axis_valid),
		.s_axis_ready(s5_reg_slice_axis_ready),
		
		.m_axis_data(m5_reg_slice_axis_data),
		.m_axis_user(m5_reg_slice_axis_user),
		.m_axis_valid(m5_reg_slice_axis_valid),
		.m_axis_ready(m5_reg_slice_axis_ready)
	);
	
	/** 卷积核缓存ICB从机#1 **/
	// 命令通道AXIS寄存器片
	wire[ATOMIC_C*2*8-1:0] s6_reg_slice_axis_data;
	wire[ATOMIC_C*2-1:0] s6_reg_slice_axis_keep;
	wire[32:0] s6_reg_slice_axis_user; // {read(1bit), addr(32bit)}
	wire s6_reg_slice_axis_valid;
	wire s6_reg_slice_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m6_reg_slice_axis_data;
	wire[ATOMIC_C*2-1:0] m6_reg_slice_axis_keep;
	wire[32:0] m6_reg_slice_axis_user; // {read(1bit), addr(32bit)}
	wire m6_reg_slice_axis_valid;
	wire m6_reg_slice_axis_ready;
	// 响应通道AXIS寄存器片
	wire[ATOMIC_C*2*8-1:0] s7_reg_slice_axis_data;
	wire s7_reg_slice_axis_user; // {err(1bit)}
	wire s7_reg_slice_axis_valid;
	wire s7_reg_slice_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m7_reg_slice_axis_data;
	wire m7_reg_slice_axis_user; // {err(1bit)}
	wire m7_reg_slice_axis_valid;
	wire m7_reg_slice_axis_ready;
	
	assign s6_reg_slice_axis_data = s1_kbuf_cmd_wdata;
	assign s6_reg_slice_axis_keep = s1_kbuf_cmd_wmask;
	assign s6_reg_slice_axis_user = {s1_kbuf_cmd_read, s1_kbuf_cmd_addr};
	assign s6_reg_slice_axis_valid = s1_kbuf_cmd_valid;
	assign s1_kbuf_cmd_ready = s6_reg_slice_axis_ready;
	
	assign m1_kbuf_cmd_wdata = m6_reg_slice_axis_data;
	assign m1_kbuf_cmd_wmask = m6_reg_slice_axis_keep;
	assign {m1_kbuf_cmd_read, m1_kbuf_cmd_addr} = m6_reg_slice_axis_user;
	assign m1_kbuf_cmd_valid = m6_reg_slice_axis_valid;
	assign m6_reg_slice_axis_ready = m1_kbuf_cmd_ready;
	
	assign s7_reg_slice_axis_data = m1_kbuf_rsp_rdata;
	assign s7_reg_slice_axis_user = m1_kbuf_rsp_err;
	assign s7_reg_slice_axis_valid = m1_kbuf_rsp_valid;
	assign m1_kbuf_rsp_ready = s7_reg_slice_axis_ready;
	
	assign s1_kbuf_rsp_rdata = m7_reg_slice_axis_data;
	assign s1_kbuf_rsp_err = m7_reg_slice_axis_user;
	assign s1_kbuf_rsp_valid = m7_reg_slice_axis_valid;
	assign m7_reg_slice_axis_ready = s1_kbuf_rsp_ready;
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(33),
		.forward_registered(EN_ICB1_KBUF_REG_SLICE),
		.back_registered(EN_ICB1_KBUF_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u6(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s6_reg_slice_axis_data),
		.s_axis_keep(s6_reg_slice_axis_keep),
		.s_axis_user(s6_reg_slice_axis_user),
		.s_axis_valid(s6_reg_slice_axis_valid),
		.s_axis_ready(s6_reg_slice_axis_ready),
		
		.m_axis_data(m6_reg_slice_axis_data),
		.m_axis_keep(m6_reg_slice_axis_keep),
		.m_axis_user(m6_reg_slice_axis_user),
		.m_axis_valid(m6_reg_slice_axis_valid),
		.m_axis_ready(m6_reg_slice_axis_ready)
	);
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(1),
		.forward_registered(EN_ICB1_KBUF_REG_SLICE),
		.back_registered(EN_ICB1_KBUF_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u7(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s7_reg_slice_axis_data),
		.s_axis_user(s7_reg_slice_axis_user),
		.s_axis_valid(s7_reg_slice_axis_valid),
		.s_axis_ready(s7_reg_slice_axis_ready),
		
		.m_axis_data(m7_reg_slice_axis_data),
		.m_axis_user(m7_reg_slice_axis_user),
		.m_axis_valid(m7_reg_slice_axis_valid),
		.m_axis_ready(m7_reg_slice_axis_ready)
	);
	
endmodule
