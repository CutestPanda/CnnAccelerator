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
本模块: (物理)卷积私有缓存(核心)

描述:
使用CBUF_BANK_N个单口SRAM作为特征图和卷积核缓存

提供2个特征图缓存ICB从机, 带有Bank冲突仲裁逻辑
提供2个卷积核缓存ICB从机, 带有Bank冲突仲裁逻辑

特征图缓存的物理地址是向下增长的, 而卷积核缓存的物理地址是向上增长的

可动态分配特征图/卷积核缓存所占Bank数, 提供逻辑地址越界保护

可选的高性能ICB从机, 在响应通道ready时允许接收下一条命令

注意：
ICB从机不支持非对齐传输(地址必须对齐到ATOMIC_C*2字节)

协议:
ICB SLAVE
MEM MASTER

作者: 陈家耀
日期: 2025/03/27
********************************************************************/


module phy_conv_buffer_core #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer CBUF_BANK_N = 32, // 缓存MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 512, // 每片缓存MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter EN_EXCEED_BD_PROTECT = "true", // 是否启用逻辑地址越界保护
	parameter EN_HP_ICB = "true", // 是否启用高性能ICB从机
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
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 缓存MEM主接口 **/
	wire[ATOMIC_C*2-1:0] mem_wen_a_arr[0:CBUF_BANK_N-1];
	wire[15:0] mem_addr_a_arr[0:CBUF_BANK_N-1];
	wire[ATOMIC_C*2*8-1:0] mem_din_a_arr[0:CBUF_BANK_N-1];
	wire[ATOMIC_C*2*8-1:0] mem_dout_a_arr[0:CBUF_BANK_N-1];
	
	assign mem_clk_a = aclk;
	
	genvar mem_i;
	generate
		for(mem_i = 0;mem_i < CBUF_BANK_N;mem_i = mem_i + 1)
		begin:mem_blk
			assign mem_wen_a[(mem_i+1)*ATOMIC_C*2-1:mem_i*ATOMIC_C*2] = mem_wen_a_arr[mem_i];
			assign mem_addr_a[mem_i*16+15:mem_i*16] = mem_addr_a_arr[mem_i];
			assign mem_din_a[(mem_i+1)*ATOMIC_C*2*8-1:mem_i*ATOMIC_C*2*8] = mem_din_a_arr[mem_i];
			assign mem_dout_a_arr[mem_i] = mem_dout_a[(mem_i+1)*ATOMIC_C*2*8-1:mem_i*ATOMIC_C*2*8];
		end
	endgenerate
	
	/**
	特征图缓存ICB从机访问信息fifo
	
	当Bank号为0~(CBUF_BANK_N-1)时, 则访问的是实际的物理Bank
	当Bank号为CBUF_BANK_N时, 则表示访问地址越界
	**/
	// fifo写端口
	wire fmbuf_access_msg_fifo_wen[0:1];
	wire[clogb2(CBUF_BANK_N):0] fmbuf_access_msg_fifo_din[0:1]; // 所访问的Bank号
	wire fmbuf_access_msg_fifo_full_n[0:1];
	// fifo读端口
	wire fmbuf_access_msg_fifo_ren[0:1];
	wire[clogb2(CBUF_BANK_N):0] fmbuf_access_msg_fifo_dout[0:1]; // 所访问的Bank号
	wire fmbuf_access_msg_fifo_empty_n[0:1];
	
	genvar fmbuf_access_msg_fifo_i;
	generate
		for(fmbuf_access_msg_fifo_i = 0;fmbuf_access_msg_fifo_i < 2;fmbuf_access_msg_fifo_i = fmbuf_access_msg_fifo_i + 1)
		begin:fmbuf_access_msg_fifo_blk
			fifo_based_on_regs #(
				.fwft_mode("true"),
				.low_latency_mode("false"),
				.fifo_depth(4),
				.fifo_data_width(clogb2(CBUF_BANK_N)+1),
				.almost_full_th(3),
				.almost_empty_th(1),
				.simulation_delay(SIM_DELAY)
			)fmbuf_access_msg_fifo_u(
				.clk(aclk),
				.rst_n(aresetn),
				
				.fifo_wen(fmbuf_access_msg_fifo_wen[fmbuf_access_msg_fifo_i]),
				.fifo_din(fmbuf_access_msg_fifo_din[fmbuf_access_msg_fifo_i]),
				.fifo_full_n(fmbuf_access_msg_fifo_full_n[fmbuf_access_msg_fifo_i]),
				
				.fifo_ren(fmbuf_access_msg_fifo_ren[fmbuf_access_msg_fifo_i]),
				.fifo_dout(fmbuf_access_msg_fifo_dout[fmbuf_access_msg_fifo_i]),
				.fifo_empty_n(fmbuf_access_msg_fifo_empty_n[fmbuf_access_msg_fifo_i])
			);
		end
	endgenerate
	
	/**
	卷积核缓存ICB从机访问信息fifo
	
	当Bank号为0~(CBUF_BANK_N-1)时, 则访问的是实际的物理Bank
	当Bank号为CBUF_BANK_N时, 则表示访问地址越界
	**/
	// fifo写端口
	wire kbuf_access_msg_fifo_wen[0:1];
	wire[clogb2(CBUF_BANK_N):0] kbuf_access_msg_fifo_din[0:1]; // 所访问的Bank号
	wire kbuf_access_msg_fifo_full_n[0:1];
	// fifo读端口
	wire kbuf_access_msg_fifo_ren[0:1];
	wire[clogb2(CBUF_BANK_N):0] kbuf_access_msg_fifo_dout[0:1]; // 所访问的Bank号
	wire kbuf_access_msg_fifo_empty_n[0:1];
	
	genvar kbuf_access_msg_fifo_i;
	generate
		for(kbuf_access_msg_fifo_i = 0;kbuf_access_msg_fifo_i < 2;kbuf_access_msg_fifo_i = kbuf_access_msg_fifo_i + 1)
		begin:kbuf_access_msg_fifo_blk
			fifo_based_on_regs #(
				.fwft_mode("true"),
				.low_latency_mode("false"),
				.fifo_depth(4),
				.fifo_data_width(clogb2(CBUF_BANK_N)+1),
				.almost_full_th(3),
				.almost_empty_th(1),
				.simulation_delay(SIM_DELAY)
			)kbuf_access_msg_fifo_u(
				.clk(aclk),
				.rst_n(aresetn),
				
				.fifo_wen(kbuf_access_msg_fifo_wen[kbuf_access_msg_fifo_i]),
				.fifo_din(kbuf_access_msg_fifo_din[kbuf_access_msg_fifo_i]),
				.fifo_full_n(kbuf_access_msg_fifo_full_n[kbuf_access_msg_fifo_i]),
				
				.fifo_ren(kbuf_access_msg_fifo_ren[kbuf_access_msg_fifo_i]),
				.fifo_dout(kbuf_access_msg_fifo_dout[kbuf_access_msg_fifo_i]),
				.fifo_empty_n(kbuf_access_msg_fifo_empty_n[kbuf_access_msg_fifo_i])
			);
		end
	endgenerate
	
	/** 缓存访问空间限制 **/
	wire[clogb2(CBUF_BANK_N):0] kbufbankn; // 分配给卷积核缓存的Bank数
	wire[31:0] fmbuf_high_addr; // 特征图缓存最大地址
	wire[31:0] kbuf_high_addr; // 卷积核缓存最大地址
	wire[1:0] fmbuf_addr_exceed_bd; // 特征图缓存访问地址越界
	wire[1:0] kbuf_addr_exceed_bd; // 卷积核缓存访问地址越界
	
	assign kbufbankn = CBUF_BANK_N - fmbufbankn[clogb2(CBUF_BANK_N):0];
	
	assign fmbuf_high_addr = fmbufbankn[clogb2(CBUF_BANK_N):0] * CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2;
	assign kbuf_high_addr = kbufbankn * CBUF_DEPTH_FOREACH_BANK * ATOMIC_C * 2;
	
	assign fmbuf_addr_exceed_bd[0] = (EN_EXCEED_BD_PROTECT == "true") & (s0_fmbuf_cmd_addr >= fmbuf_high_addr);
	assign fmbuf_addr_exceed_bd[1] = (EN_EXCEED_BD_PROTECT == "true") & (s1_fmbuf_cmd_addr >= fmbuf_high_addr);
	
	assign kbuf_addr_exceed_bd[0] = (EN_EXCEED_BD_PROTECT == "true") & (s0_kbuf_cmd_addr >= kbuf_high_addr);
	assign kbuf_addr_exceed_bd[1] = (EN_EXCEED_BD_PROTECT == "true") & (s1_kbuf_cmd_addr >= kbuf_high_addr);
	
	/** 缓存MEM控制 **/
	wire[clogb2(CBUF_BANK_N-1):0] fmbuf_access_bid[0:1]; // 特征图缓存访问Bank号
	wire[clogb2(CBUF_BANK_N-1):0] kbuf_access_bid[0:1]; // 卷积核缓存访问Bank号
	wire[clogb2(CBUF_DEPTH_FOREACH_BANK-1):0] fmbuf_access_pgaddr[0:1]; // 特征图缓存访问Bank内地址
	wire[clogb2(CBUF_DEPTH_FOREACH_BANK-1):0] kbuf_access_pgaddr[0:1]; // 卷积核缓存访问Bank内地址
	reg buf_mem_access_pending[0:CBUF_BANK_N-1]; // 缓存MEM访问等待(标志)
	/*
	4'b0001 -> 特征图缓存ICB从机#0, 4'b0010 -> 特征图缓存ICB从机#1, 
	4'b0100 -> 卷积核缓存ICB从机#0, 4'b1000 -> 卷积核缓存ICB从机#1
	*/
	reg[3:0] buf_mem_rsp_sid[0:CBUF_BANK_N-1]; // 缓存MEM响应选择的从机号
	wire buf_mem_rsp_slave_ready[0:CBUF_BANK_N-1]; // 缓存MEM响应选择的从机是否就绪(标志)
	wire buf_mem_rsp_to_pass[0:CBUF_BANK_N-1]; // 缓存MEM允许传递响应(标志)
	wire[3:0] buf_mem_access_by_slave[0:CBUF_BANK_N-1]; // 缓存MEM被从机访问(指示向量)
	wire buf_mem_rsp_accepted[0:CBUF_BANK_N-1]; // 缓存MEM响应被接受(指示)
	
	/*
	在ICB从机的响应端无需检查缓存MEM响应选择的从机号, 这是因为对于某个Bank来说, 不同ICB从机对它的访问必定是按序进行的, 
		在ICB从机访问信息fifo中可以找到这个从机在命令端给出的Bank号
	*/
	assign s0_fmbuf_rsp_rdata = mem_dout_a_arr[fmbuf_access_msg_fifo_dout[0][clogb2(CBUF_BANK_N-1):0]];
	assign s0_fmbuf_rsp_err = (EN_EXCEED_BD_PROTECT == "true") & fmbuf_access_msg_fifo_dout[0][clogb2(CBUF_BANK_N)];
	assign s0_fmbuf_rsp_valid = 
		aclken & 
		fmbuf_access_msg_fifo_empty_n[0] & (
			((EN_EXCEED_BD_PROTECT == "true") & fmbuf_access_msg_fifo_dout[0][clogb2(CBUF_BANK_N)]) | 
			buf_mem_access_pending[fmbuf_access_msg_fifo_dout[0][clogb2(CBUF_BANK_N-1):0]]
		);
	assign s1_fmbuf_rsp_rdata = mem_dout_a_arr[fmbuf_access_msg_fifo_dout[1][clogb2(CBUF_BANK_N-1):0]];
	assign s1_fmbuf_rsp_err = (EN_EXCEED_BD_PROTECT == "true") & fmbuf_access_msg_fifo_dout[1][clogb2(CBUF_BANK_N)];
	assign s1_fmbuf_rsp_valid = 
		aclken & 
		fmbuf_access_msg_fifo_empty_n[1] & (
			((EN_EXCEED_BD_PROTECT == "true") & fmbuf_access_msg_fifo_dout[1][clogb2(CBUF_BANK_N)]) | 
			buf_mem_access_pending[fmbuf_access_msg_fifo_dout[1][clogb2(CBUF_BANK_N-1):0]]
		);
	assign s0_kbuf_rsp_rdata = mem_dout_a_arr[kbuf_access_msg_fifo_dout[0][clogb2(CBUF_BANK_N-1):0]];
	assign s0_kbuf_rsp_err = (EN_EXCEED_BD_PROTECT == "true") & kbuf_access_msg_fifo_dout[0][clogb2(CBUF_BANK_N)];
	assign s0_kbuf_rsp_valid = 
		aclken & 
		kbuf_access_msg_fifo_empty_n[0] & (
			((EN_EXCEED_BD_PROTECT == "true") & kbuf_access_msg_fifo_dout[0][clogb2(CBUF_BANK_N)]) | 
			buf_mem_access_pending[kbuf_access_msg_fifo_dout[0][clogb2(CBUF_BANK_N-1):0]]
		);
	assign s1_kbuf_rsp_rdata = mem_dout_a_arr[kbuf_access_msg_fifo_dout[1][clogb2(CBUF_BANK_N-1):0]];
	assign s1_kbuf_rsp_err = (EN_EXCEED_BD_PROTECT == "true") & kbuf_access_msg_fifo_dout[1][clogb2(CBUF_BANK_N)];
	assign s1_kbuf_rsp_valid = 
		aclken & 
		kbuf_access_msg_fifo_empty_n[1] & (
			((EN_EXCEED_BD_PROTECT == "true") & kbuf_access_msg_fifo_dout[1][clogb2(CBUF_BANK_N)]) | 
			buf_mem_access_pending[kbuf_access_msg_fifo_dout[1][clogb2(CBUF_BANK_N-1):0]]
		);
	
	assign fmbuf_access_msg_fifo_ren[0] = s0_fmbuf_rsp_valid & s0_fmbuf_rsp_ready;
	assign fmbuf_access_msg_fifo_ren[1] = s1_fmbuf_rsp_valid & s1_fmbuf_rsp_ready;
	assign kbuf_access_msg_fifo_ren[0] = s0_kbuf_rsp_valid & s0_kbuf_rsp_ready;
	assign kbuf_access_msg_fifo_ren[1] = s1_kbuf_rsp_valid & s1_kbuf_rsp_ready;
	
	assign fmbuf_access_bid[0] = 
		s0_fmbuf_cmd_addr[
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK)+clogb2(CBUF_BANK_N-1):
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK)
		];
	assign fmbuf_access_bid[1] = 
		s1_fmbuf_cmd_addr[
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK)+clogb2(CBUF_BANK_N-1):
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK)
		];
	assign kbuf_access_bid[0] = 
		~s0_kbuf_cmd_addr[
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK)+clogb2(CBUF_BANK_N-1):
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK)
		];
	assign kbuf_access_bid[1] = 
		~s1_kbuf_cmd_addr[
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK)+clogb2(CBUF_BANK_N-1):
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK)
		];
	assign fmbuf_access_pgaddr[0] = 
		s0_fmbuf_cmd_addr[
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK-1):
			clogb2(ATOMIC_C*2)
		];
	assign fmbuf_access_pgaddr[1] = 
		s1_fmbuf_cmd_addr[
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK-1):
			clogb2(ATOMIC_C*2)
		];
	assign kbuf_access_pgaddr[0] = 
		~s0_kbuf_cmd_addr[
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK-1):
			clogb2(ATOMIC_C*2)
		];
	assign kbuf_access_pgaddr[1] = 
		~s1_kbuf_cmd_addr[
			clogb2(ATOMIC_C*2)+clogb2(CBUF_DEPTH_FOREACH_BANK-1):
			clogb2(ATOMIC_C*2)
		];
	
	genvar buf_mem_ctrl_i;
	generate
		for(buf_mem_ctrl_i = 0;buf_mem_ctrl_i < CBUF_BANK_N;buf_mem_ctrl_i = buf_mem_ctrl_i + 1)
		begin:buf_mem_ctrl_blk
			assign mem_en_a[buf_mem_ctrl_i] = aclken & (
				(buf_mem_ctrl_i < fmbufbankn[clogb2(CBUF_BANK_N):0]) ? 
					(buf_mem_access_by_slave[buf_mem_ctrl_i][0] | buf_mem_access_by_slave[buf_mem_ctrl_i][1]):
					(buf_mem_access_by_slave[buf_mem_ctrl_i][2] | buf_mem_access_by_slave[buf_mem_ctrl_i][3])
			);
			assign mem_wen_a_arr[buf_mem_ctrl_i] = 
				(buf_mem_ctrl_i < fmbufbankn[clogb2(CBUF_BANK_N):0]) ? (
					buf_mem_access_by_slave[buf_mem_ctrl_i][0] ? 
						({(ATOMIC_C*2){~s0_fmbuf_cmd_read}} & s0_fmbuf_cmd_wmask):
						({(ATOMIC_C*2){~s1_fmbuf_cmd_read}} & s1_fmbuf_cmd_wmask)
				):(
					buf_mem_access_by_slave[buf_mem_ctrl_i][2] ? 
						({(ATOMIC_C*2){~s0_kbuf_cmd_read}} & s0_kbuf_cmd_wmask):
						({(ATOMIC_C*2){~s1_kbuf_cmd_read}} & s1_kbuf_cmd_wmask)
				);
			assign mem_addr_a_arr[buf_mem_ctrl_i] = 
				(buf_mem_ctrl_i < fmbufbankn[clogb2(CBUF_BANK_N):0]) ? (
					buf_mem_access_by_slave[buf_mem_ctrl_i][0] ? 
						(16'h0000 | fmbuf_access_pgaddr[0]):
						(16'h0000 | fmbuf_access_pgaddr[1])
				):(
					buf_mem_access_by_slave[buf_mem_ctrl_i][2] ? 
						(16'h0000 | kbuf_access_pgaddr[0]):
						(16'h0000 | kbuf_access_pgaddr[1])
				);
			assign mem_din_a_arr[buf_mem_ctrl_i] = 
				(buf_mem_ctrl_i < fmbufbankn[clogb2(CBUF_BANK_N):0]) ? (
					buf_mem_access_by_slave[buf_mem_ctrl_i][0] ? 
						s0_fmbuf_cmd_wdata:
						s1_fmbuf_cmd_wdata
				):(
					buf_mem_access_by_slave[buf_mem_ctrl_i][2] ? 
						s0_kbuf_cmd_wdata:
						s1_kbuf_cmd_wdata
				);
			
			assign buf_mem_rsp_slave_ready[buf_mem_ctrl_i] = 
				(EN_HP_ICB == "true") & (
					(buf_mem_ctrl_i < fmbufbankn[clogb2(CBUF_BANK_N):0]) ? (
						(buf_mem_rsp_sid[buf_mem_ctrl_i][0] & s0_fmbuf_rsp_ready) | 
						(buf_mem_rsp_sid[buf_mem_ctrl_i][1] & s1_fmbuf_rsp_ready)
					):(
						(buf_mem_rsp_sid[buf_mem_ctrl_i][2] & s0_kbuf_rsp_ready) | 
						(buf_mem_rsp_sid[buf_mem_ctrl_i][3] & s1_kbuf_rsp_ready)
					)
				);
			assign buf_mem_rsp_to_pass[buf_mem_ctrl_i] = 
				(EN_HP_ICB == "true") & (
					(buf_mem_ctrl_i < fmbufbankn[clogb2(CBUF_BANK_N):0]) ? (
						(buf_mem_rsp_sid[buf_mem_ctrl_i][0] & 
							fmbuf_access_msg_fifo_empty_n[0] & (fmbuf_access_msg_fifo_dout[0] == buf_mem_ctrl_i)) | 
						(buf_mem_rsp_sid[buf_mem_ctrl_i][1] & 
							fmbuf_access_msg_fifo_empty_n[1] & (fmbuf_access_msg_fifo_dout[1] == buf_mem_ctrl_i))
					):(
						(buf_mem_rsp_sid[buf_mem_ctrl_i][2] & 
							kbuf_access_msg_fifo_empty_n[0] & (kbuf_access_msg_fifo_dout[0] == buf_mem_ctrl_i)) | 
						(buf_mem_rsp_sid[buf_mem_ctrl_i][3] & 
							kbuf_access_msg_fifo_empty_n[1] & (kbuf_access_msg_fifo_dout[1] == buf_mem_ctrl_i))
					)
				);
			// 断言: 缓存MEM被从机访问(指示向量)要么是4'b0000, 要么是独热码!
			assign buf_mem_access_by_slave[buf_mem_ctrl_i] = {
				s1_kbuf_cmd_valid & s1_kbuf_cmd_ready & (kbuf_access_bid[1] == buf_mem_ctrl_i) & (~kbuf_addr_exceed_bd[1]), 
				s0_kbuf_cmd_valid & s0_kbuf_cmd_ready & (kbuf_access_bid[0] == buf_mem_ctrl_i) & (~kbuf_addr_exceed_bd[0]), 
				s1_fmbuf_cmd_valid & s1_fmbuf_cmd_ready & (fmbuf_access_bid[1] == buf_mem_ctrl_i) & (~fmbuf_addr_exceed_bd[1]), 
				s0_fmbuf_cmd_valid & s0_fmbuf_cmd_ready & (fmbuf_access_bid[0] == buf_mem_ctrl_i) & (~fmbuf_addr_exceed_bd[0])
			};
			assign buf_mem_rsp_accepted[buf_mem_ctrl_i] = 
				buf_mem_access_pending[buf_mem_ctrl_i] & 
				(|(buf_mem_rsp_sid[buf_mem_ctrl_i] & {
					kbuf_access_msg_fifo_empty_n[1] & (kbuf_access_msg_fifo_dout[1] == buf_mem_ctrl_i) & s1_kbuf_rsp_ready, 
					kbuf_access_msg_fifo_empty_n[0] & (kbuf_access_msg_fifo_dout[0] == buf_mem_ctrl_i) & s0_kbuf_rsp_ready, 
					fmbuf_access_msg_fifo_empty_n[1] & (fmbuf_access_msg_fifo_dout[1] == buf_mem_ctrl_i) & s1_fmbuf_rsp_ready, 
					fmbuf_access_msg_fifo_empty_n[0] & (fmbuf_access_msg_fifo_dout[0] == buf_mem_ctrl_i) & s0_fmbuf_rsp_ready
				}));
			
			// 缓存MEM访问等待(标志)
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					buf_mem_access_pending[buf_mem_ctrl_i] <= 1'b0;
				else if(mem_en_a[buf_mem_ctrl_i] ^ buf_mem_rsp_accepted[buf_mem_ctrl_i])
					buf_mem_access_pending[buf_mem_ctrl_i] <= # SIM_DELAY mem_en_a[buf_mem_ctrl_i];
			end
			
			// 缓存MEM响应选择的从机号
			always @(posedge aclk)
			begin
				if(aclken & mem_en_a[buf_mem_ctrl_i])
					buf_mem_rsp_sid[buf_mem_ctrl_i] <= # SIM_DELAY buf_mem_access_by_slave[buf_mem_ctrl_i];
			end
		end
	endgenerate
	
	/** 特征图缓存冲突访问仲裁 **/
	wire fmbuf_addr_conflict; // 特征图缓存访问冲突(标志)
	reg fmbuf_access_cfl_sel; // 特征图缓存访问冲突时选择的从机
	
	/*
	如果待访问的Bank处于等待状态, 
		那么除了需要检查缓存MEM响应所选择的从机是否就绪外, 还要检查这个从机是否允许本Bank传递响应, 
		这是因为在不同Bank上的滞外传输可能是存在的
	*/
	assign s0_fmbuf_cmd_ready = 
		aclken & 
		fmbuf_access_msg_fifo_full_n[0] & (
			(~buf_mem_access_pending[fmbuf_access_bid[0]]) | 
			(buf_mem_rsp_slave_ready[fmbuf_access_bid[0]] & buf_mem_rsp_to_pass[fmbuf_access_bid[0]])
		) & (
			(~fmbuf_access_cfl_sel) | (~s1_fmbuf_cmd_valid) | (~fmbuf_addr_conflict) | fmbuf_addr_exceed_bd[0] | fmbuf_addr_exceed_bd[1]
		);
	assign s1_fmbuf_cmd_ready = 
		aclken & 
		fmbuf_access_msg_fifo_full_n[1] & (
			(~buf_mem_access_pending[fmbuf_access_bid[1]]) | 
			(buf_mem_rsp_slave_ready[fmbuf_access_bid[1]] & buf_mem_rsp_to_pass[fmbuf_access_bid[1]])
		) & (
			fmbuf_access_cfl_sel | (~s0_fmbuf_cmd_valid) | (~fmbuf_addr_conflict) | fmbuf_addr_exceed_bd[0] | fmbuf_addr_exceed_bd[1]
		);
	
	assign fmbuf_access_msg_fifo_wen[0] = s0_fmbuf_cmd_valid & s0_fmbuf_cmd_ready;
	assign fmbuf_access_msg_fifo_wen[1] = s1_fmbuf_cmd_valid & s1_fmbuf_cmd_ready;
	assign fmbuf_access_msg_fifo_din[0] = {fmbuf_addr_exceed_bd[0], fmbuf_access_bid[0]};
	assign fmbuf_access_msg_fifo_din[1] = {fmbuf_addr_exceed_bd[1], fmbuf_access_bid[1]};
	
	assign fmbuf_addr_conflict = fmbuf_access_bid[0] == fmbuf_access_bid[1];
	
	// 特征图缓存访问冲突时选择的从机
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			fmbuf_access_cfl_sel <= 1'b0;
		else if(aclken & 
			s0_fmbuf_cmd_valid & s1_fmbuf_cmd_valid & 
			(s0_fmbuf_cmd_ready | s1_fmbuf_cmd_ready) & 
			fmbuf_addr_conflict & (~fmbuf_addr_exceed_bd[0]) & (~fmbuf_addr_exceed_bd[1])
		)
			fmbuf_access_cfl_sel <= # SIM_DELAY ~fmbuf_access_cfl_sel;
	end
	
	/** 卷积核缓存冲突访问仲裁 **/
	wire kbuf_addr_conflict; // 卷积核缓存访问冲突(标志)
	reg kbuf_access_cfl_sel; // 卷积核缓存访问冲突时选择的从机
	
	/*
	如果待访问的Bank处于等待状态, 
		那么除了需要检查缓存MEM响应所选择的从机是否就绪外, 还要检查这个从机是否允许本Bank传递响应, 
		这是因为在不同Bank上的滞外传输可能是存在的
	*/
	assign s0_kbuf_cmd_ready = 
		aclken & 
		kbuf_access_msg_fifo_full_n[0] & (
			(~buf_mem_access_pending[kbuf_access_bid[0]]) | 
			(buf_mem_rsp_slave_ready[kbuf_access_bid[0]] & buf_mem_rsp_to_pass[kbuf_access_bid[0]])
		) & (
			(~kbuf_access_cfl_sel) | (~s1_kbuf_cmd_valid) | (~kbuf_addr_conflict) | kbuf_addr_exceed_bd[0] | kbuf_addr_exceed_bd[1]
		);
	assign s1_kbuf_cmd_ready = 
		aclken & 
		kbuf_access_msg_fifo_full_n[1] & (
			(~buf_mem_access_pending[kbuf_access_bid[1]]) | 
			(buf_mem_rsp_slave_ready[kbuf_access_bid[1]] & buf_mem_rsp_to_pass[kbuf_access_bid[1]])
		) & (
			kbuf_access_cfl_sel | (~s0_kbuf_cmd_valid) | (~kbuf_addr_conflict) | kbuf_addr_exceed_bd[0] | kbuf_addr_exceed_bd[1]
		);
	
	assign kbuf_access_msg_fifo_wen[0] = s0_kbuf_cmd_valid & s0_kbuf_cmd_ready;
	assign kbuf_access_msg_fifo_wen[1] = s1_kbuf_cmd_valid & s1_kbuf_cmd_ready;
	assign kbuf_access_msg_fifo_din[0] = {kbuf_addr_exceed_bd[0], kbuf_access_bid[0]};
	assign kbuf_access_msg_fifo_din[1] = {kbuf_addr_exceed_bd[1], kbuf_access_bid[1]};
	
	assign kbuf_addr_conflict = kbuf_access_bid[0] == kbuf_access_bid[1];
	
	// 卷积核缓存访问冲突时选择的从机
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kbuf_access_cfl_sel <= 1'b0;
		else if(aclken & 
			s0_kbuf_cmd_valid & s1_kbuf_cmd_valid & 
			(s0_kbuf_cmd_ready | s1_kbuf_cmd_ready) & 
			kbuf_addr_conflict & (~kbuf_addr_exceed_bd[0]) & (~kbuf_addr_exceed_bd[1])
		)
			kbuf_access_cfl_sel <= # SIM_DELAY ~kbuf_access_cfl_sel;
	end
	
endmodule
