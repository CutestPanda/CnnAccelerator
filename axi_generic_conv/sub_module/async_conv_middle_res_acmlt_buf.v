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
本模块: (异步)卷积中间结果累加与缓存

描述:
输入异步fifo -> (并串转换) -> 中间结果更新与缓存(计算核心) -> (串并转换) -> 输出异步fifo

注意：
核并行数(ATOMIC_K)必须能被缓存时钟倍率(BUF_CLK_RATE)整除

协议:
AXIS MASTER/SLAVE
MEM MASTER

作者: 陈家耀
日期: 2026/01/04
********************************************************************/


module async_conv_middle_res_acmlt_buf #(
	parameter integer BUF_CLK_RATE = 1, // 缓存时钟倍率(1 | 2 | 4 | 8)
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer RBUF_BANK_N = 8, // 缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512, // 缓存MEM深度(16 | ...)
	parameter integer INFO_ALONG_WIDTH = 2, // 随路数据的位宽(必须>=1)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	// 中间结果缓存时钟和复位
	input wire mid_res_buf_aclk,
	input wire mid_res_buf_aresetn,
	input wire mid_res_buf_aclken,
	
	// 控制信号
	input wire runtime_params_vld, // 运行时参数有效标志
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	input wire[3:0] row_n_bufferable, // 可缓存行数 - 1
	input wire[3:0] bank_n_foreach_ofmap_row, // 每个输出特征图行所占用的缓存MEM个数
	input wire[3:0] max_upd_latency, // 最大的更新时延
	input wire en_cal_round_ext, // 是否启用计算轮次拓展功能
	input wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	
	// 中间结果输入(AXIS从机)
	input wire[ATOMIC_K*48-1:0] s_axis_mid_res_data,
	input wire[ATOMIC_K*6-1:0] s_axis_mid_res_keep,
	input wire[2+INFO_ALONG_WIDTH:0] s_axis_mid_res_user, // {随路数据, 是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	input wire s_axis_mid_res_last, // 本行最后1个中间结果(标志)
	input wire s_axis_mid_res_valid,
	output wire s_axis_mid_res_ready,
	
	// 最终结果输出(AXIS主机)
	output wire[ATOMIC_K*32-1:0] m_axis_fnl_res_data, // ATOMIC_K个最终结果(单精度浮点数或定点数)
	output wire[ATOMIC_K*4-1:0] m_axis_fnl_res_keep,
	output wire[4:0] m_axis_fnl_res_user, // {是否最后1个子行(1bit), 子行号(4bit)}
	output wire m_axis_fnl_res_last, // 本行最后1个最终结果(标志)
	output wire m_axis_fnl_res_valid,
	input wire m_axis_fnl_res_ready,
	
	// 缓存MEM主接口
	output wire mem_clk_a,
	output wire[RBUF_BANK_N-1:0] mem_wen_a,
	output wire[RBUF_BANK_N*16-1:0] mem_addr_a,
	output wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mem_din_a,
	output wire mem_clk_b,
	output wire[RBUF_BANK_N-1:0] mem_ren_b,
	output wire[RBUF_BANK_N*16-1:0] mem_addr_b,
	input wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mem_dout_b,
	
	// 中间结果更新单元组
	output wire acmlt_aclk,
	output wire acmlt_aresetn,
	output wire acmlt_aclken,
	// [更新单元组输入]
	output wire[ATOMIC_K/BUF_CLK_RATE*48-1:0] acmlt_in_new_res, // 新结果
	output wire[ATOMIC_K/BUF_CLK_RATE*32-1:0] acmlt_in_org_mid_res, // 原中间结果
	output wire[ATOMIC_K/BUF_CLK_RATE-1:0] acmlt_in_mask, // 项掩码
	output wire acmlt_in_first_item, // 是否第1项(标志)
	output wire acmlt_in_last_grp, // 是否最后1组(标志)
	output wire acmlt_in_last_res, // 本行最后1个中间结果(标志)
	output wire[INFO_ALONG_WIDTH-1:0] acmlt_in_info_along, // 随路数据
	output wire[ATOMIC_K/BUF_CLK_RATE-1:0] acmlt_in_valid, // 输入有效指示
	// [更新单元组输出]
	input wire[ATOMIC_K/BUF_CLK_RATE*32-1:0] acmlt_out_data, // 单精度浮点数或定点数
	input wire[ATOMIC_K/BUF_CLK_RATE-1:0] acmlt_out_mask, // 输出项掩码
	input wire acmlt_out_last_grp, // 是否最后1组(标志)
	input wire acmlt_out_last_res, // 本行最后1个中间结果(标志)
	input wire acmlt_out_to_upd_mem, // 更新缓存MEM(标志)
	input wire acmlt_out_valid // 输出有效指示
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
	
	/**
	保存的运行时参数
	
	跨时钟域:
		... -> runtime_params_vld_delayed[1]
		
		... -> calfmt_saved[*]
		... -> row_n_bufferable_saved[*]
		... -> bank_n_foreach_ofmap_row_saved[*]
		... -> max_upd_latency_saved[*]
		... -> en_cal_round_ext_saved
		... -> ofmap_w_saved[*]
	**/
	reg[4:1] runtime_params_vld_delayed; // 延迟的运行时参数有效标志
	reg[1:0] calfmt_saved; // 运算数据格式
	reg[3:0] row_n_bufferable_saved; // 可缓存行数 - 1
	reg[3:0] bank_n_foreach_ofmap_row_saved; // 每个输出特征图行所占用的缓存MEM个数
	reg[3:0] max_upd_latency_saved; // 最大的更新时延
	reg en_cal_round_ext_saved; // 是否启用计算轮次拓展功能
	reg[15:0] ofmap_w_saved; // 输出特征图宽度 - 1
	
	// 延迟的运行时参数有效标志
	always @(posedge mid_res_buf_aclk or negedge mid_res_buf_aresetn)
	begin
		if(~mid_res_buf_aresetn)
			runtime_params_vld_delayed <= 4'b0000;
		else if(mid_res_buf_aclken)
			runtime_params_vld_delayed <= # SIM_DELAY {runtime_params_vld_delayed[3:1], runtime_params_vld};
	end
	
	// 保存的运行时参数
	always @(posedge mid_res_buf_aclk)
	begin
		if(runtime_params_vld_delayed[3] & (~runtime_params_vld_delayed[4]))
		begin
			calfmt_saved <= # SIM_DELAY calfmt;
			row_n_bufferable_saved <= # SIM_DELAY row_n_bufferable;
			bank_n_foreach_ofmap_row_saved <= # SIM_DELAY bank_n_foreach_ofmap_row;
			max_upd_latency_saved <= # SIM_DELAY max_upd_latency;
			en_cal_round_ext_saved <= # SIM_DELAY en_cal_round_ext;
			ofmap_w_saved <= # SIM_DELAY ofmap_w;
		end
	end
	
	/** 输入异步fifo **/
	// fifo写端口
	wire in_async_fifo_wen;
	wire in_async_fifo_full_n;
	wire[ATOMIC_K*48-1:0] in_async_fifo_din_data;
	wire[ATOMIC_K*6-1:0] in_async_fifo_din_keep;
	wire in_async_fifo_din_last;
	wire[INFO_ALONG_WIDTH-1:0] in_async_fifo_din_info_along;
	wire in_async_fifo_din_is_last_cal_round;
	wire in_async_fifo_din_is_first_grp;
	wire in_async_fifo_din_is_last_grp;
	// fifo读端口
	wire in_async_fifo_ren;
	wire in_async_fifo_empty_n;
	wire[ATOMIC_K*48-1:0] in_async_fifo_dout_data;
	wire[ATOMIC_K*6-1:0] in_async_fifo_dout_keep;
	wire in_async_fifo_dout_last;
	wire[INFO_ALONG_WIDTH-1:0] in_async_fifo_dout_info_along;
	wire in_async_fifo_dout_is_last_cal_round;
	wire in_async_fifo_dout_is_first_grp;
	wire in_async_fifo_dout_is_last_grp;
	// 并串转换
	reg[clogb2(BUF_CLK_RATE-1):0] inner_mid_res_sel;
	
	assign s_axis_mid_res_ready = aclken & in_async_fifo_full_n;
	
	assign in_async_fifo_din_data = s_axis_mid_res_data;
	assign in_async_fifo_din_keep = s_axis_mid_res_keep;
	assign in_async_fifo_din_last = s_axis_mid_res_last;
	assign {
		in_async_fifo_din_info_along,
		in_async_fifo_din_is_last_cal_round,
		in_async_fifo_din_is_first_grp,
		in_async_fifo_din_is_last_grp
	} = s_axis_mid_res_user;
	assign in_async_fifo_wen = aclken & s_axis_mid_res_valid;
	
	async_fifo_with_ram #(
		.fwft_mode("true"),
		.ram_type("lutram"),
		.depth(32),
		.data_width(ATOMIC_K*48 + ATOMIC_K*6 + 1 + INFO_ALONG_WIDTH + 3),
		.simulation_delay(SIM_DELAY)
	)in_async_fifo_u(
		.clk_wt(aclk),
		.rst_n_wt(aresetn),
		.clk_rd(mid_res_buf_aclk),
		.rst_n_rd(mid_res_buf_aresetn),
		
		.fifo_wen(in_async_fifo_wen),
		.fifo_full(),
		.fifo_full_n(in_async_fifo_full_n),
		.fifo_din({
			in_async_fifo_din_data,
			in_async_fifo_din_keep,
			in_async_fifo_din_last,
			in_async_fifo_din_info_along,
			in_async_fifo_din_is_last_cal_round,
			in_async_fifo_din_is_first_grp,
			in_async_fifo_din_is_last_grp
		}),
		.data_cnt_wt(),
		.fifo_ren(in_async_fifo_ren),
		.fifo_empty(),
		.fifo_empty_n(in_async_fifo_empty_n),
		.fifo_dout({
			in_async_fifo_dout_data,
			in_async_fifo_dout_keep,
			in_async_fifo_dout_last,
			in_async_fifo_dout_info_along,
			in_async_fifo_dout_is_last_cal_round,
			in_async_fifo_dout_is_first_grp,
			in_async_fifo_dout_is_last_grp
		}),
		.data_cnt_rd()
	);
	
	/** 中间结果更新与缓存(计算核心) **/
	// 中间结果输入(AXIS从机)
	wire[ATOMIC_K/BUF_CLK_RATE*48-1:0] s_axis_inner_mid_res_data;
	wire[ATOMIC_K/BUF_CLK_RATE*6-1:0] s_axis_inner_mid_res_keep;
	wire[2+INFO_ALONG_WIDTH:0] s_axis_inner_mid_res_user; // {随路数据, 是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire s_axis_inner_mid_res_last; // 本行最后1个中间结果(标志)
	wire s_axis_inner_mid_res_valid;
	wire s_axis_inner_mid_res_ready;
	// 最终结果输出(AXIS主机)
	wire[ATOMIC_K/BUF_CLK_RATE*32-1:0] m_axis_inner_fnl_res_data; // ATOMIC_K个最终结果(单精度浮点数或定点数)
	wire[ATOMIC_K/BUF_CLK_RATE*4-1:0] m_axis_inner_fnl_res_keep;
	wire[4:0] m_axis_inner_fnl_res_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_inner_fnl_res_last; // 本行最后1个最终结果(标志)
	wire m_axis_inner_fnl_res_valid;
	wire m_axis_inner_fnl_res_ready;
	// 缓存MEM主接口
	wire mem_clk_a_inner;
	wire[RBUF_BANK_N-1:0] mem_wen_a_inner;
	wire[RBUF_BANK_N*16-1:0] mem_addr_a_inner;
	wire[RBUF_BANK_N*(ATOMIC_K/BUF_CLK_RATE*4*8+ATOMIC_K/BUF_CLK_RATE)-1:0] mem_din_a_inner;
	wire mem_clk_b_inner;
	wire[RBUF_BANK_N-1:0] mem_ren_b_inner;
	wire[RBUF_BANK_N*16-1:0] mem_addr_b_inner;
	wire[RBUF_BANK_N*(ATOMIC_K/BUF_CLK_RATE*4*8+ATOMIC_K/BUF_CLK_RATE)-1:0] mem_dout_b_inner;
	
	assign mem_clk_a = mem_clk_a_inner;
	assign mem_wen_a = mem_wen_a_inner;
	assign mem_addr_a = mem_addr_a_inner;
	assign mem_clk_b = mem_clk_b_inner;
	assign mem_ren_b = mem_ren_b_inner;
	assign mem_addr_b = mem_addr_b_inner;
	
	genvar mid_res_mem_i;
	generate
		for(mid_res_mem_i = 0;mid_res_mem_i < RBUF_BANK_N;mid_res_mem_i = mid_res_mem_i + 1)
		begin:mid_res_mem_blk
			assign mem_din_a[(mid_res_mem_i+1)*(ATOMIC_K*4*8+ATOMIC_K)-1:mid_res_mem_i*(ATOMIC_K*4*8+ATOMIC_K)] = 
				mem_din_a_inner[
					(mid_res_mem_i+1)*(ATOMIC_K/BUF_CLK_RATE*4*8+ATOMIC_K/BUF_CLK_RATE)-1:
					mid_res_mem_i*(ATOMIC_K/BUF_CLK_RATE*4*8+ATOMIC_K/BUF_CLK_RATE)
				] | {(ATOMIC_K*4*8+ATOMIC_K){1'b0}};
			
			assign mem_dout_b_inner[
				(mid_res_mem_i+1)*(ATOMIC_K/BUF_CLK_RATE*4*8+ATOMIC_K/BUF_CLK_RATE)-1:
				mid_res_mem_i*(ATOMIC_K/BUF_CLK_RATE*4*8+ATOMIC_K/BUF_CLK_RATE)
			] = mem_dout_b[
				mid_res_mem_i*(ATOMIC_K*4*8+ATOMIC_K)+(ATOMIC_K/BUF_CLK_RATE*4*8+ATOMIC_K/BUF_CLK_RATE)-1:
				mid_res_mem_i*(ATOMIC_K*4*8+ATOMIC_K)
			];
		end
	endgenerate
	
	assign in_async_fifo_ren = mid_res_buf_aclken & s_axis_inner_mid_res_ready & (inner_mid_res_sel == (BUF_CLK_RATE-1));
	
	assign s_axis_inner_mid_res_data = in_async_fifo_dout_data >> (ATOMIC_K/BUF_CLK_RATE*48*inner_mid_res_sel);
	assign s_axis_inner_mid_res_keep = in_async_fifo_dout_keep >> (ATOMIC_K/BUF_CLK_RATE*6*inner_mid_res_sel);
	assign s_axis_inner_mid_res_user = {
		in_async_fifo_dout_info_along,
		in_async_fifo_dout_is_last_cal_round,
		in_async_fifo_dout_is_first_grp,
		in_async_fifo_dout_is_last_grp
	};
	assign s_axis_inner_mid_res_last = 
		(inner_mid_res_sel == (BUF_CLK_RATE-1)) & in_async_fifo_dout_is_last_cal_round & in_async_fifo_dout_last;
	assign s_axis_inner_mid_res_valid = mid_res_buf_aclken & in_async_fifo_empty_n;
	
	always @(posedge mid_res_buf_aclk or negedge mid_res_buf_aresetn)
	begin
		if(~mid_res_buf_aresetn)
			inner_mid_res_sel <= 0;
		else if(
			mid_res_buf_aclken & 
			s_axis_inner_mid_res_valid & s_axis_inner_mid_res_ready
		)
			inner_mid_res_sel <= # SIM_DELAY 
				(inner_mid_res_sel == (BUF_CLK_RATE-1)) ? 
					0:
					(inner_mid_res_sel + 1);
	end
	
	conv_middle_res_acmlt_buf #(
		.TSF_N_FOREACH_SFC(BUF_CLK_RATE),
		.ATOMIC_K(ATOMIC_K/BUF_CLK_RATE),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.INFO_ALONG_WIDTH(INFO_ALONG_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)middle_res_acmlt_buf_u(
		.aclk(mid_res_buf_aclk),
		.aresetn(mid_res_buf_aresetn),
		.aclken(mid_res_buf_aclken),
		
		.calfmt(calfmt_saved),
		.row_n_bufferable(row_n_bufferable_saved),
		.bank_n_foreach_ofmap_row(bank_n_foreach_ofmap_row_saved),
		.max_upd_latency(max_upd_latency_saved),
		.en_cal_round_ext(en_cal_round_ext_saved),
		.ofmap_w(ofmap_w_saved),
		
		.s_axis_mid_res_data(s_axis_inner_mid_res_data),
		.s_axis_mid_res_keep(s_axis_inner_mid_res_keep),
		.s_axis_mid_res_user(s_axis_inner_mid_res_user),
		.s_axis_mid_res_last(s_axis_inner_mid_res_last),
		.s_axis_mid_res_valid(s_axis_inner_mid_res_valid),
		.s_axis_mid_res_ready(s_axis_inner_mid_res_ready),
		
		.m_axis_fnl_res_data(m_axis_inner_fnl_res_data),
		.m_axis_fnl_res_keep(m_axis_inner_fnl_res_keep),
		.m_axis_fnl_res_user(m_axis_inner_fnl_res_user),
		.m_axis_fnl_res_last(m_axis_inner_fnl_res_last),
		.m_axis_fnl_res_valid(m_axis_inner_fnl_res_valid),
		.m_axis_fnl_res_ready(m_axis_inner_fnl_res_ready),
		
		.mem_clk_a(mem_clk_a_inner),
		.mem_wen_a(mem_wen_a_inner),
		.mem_addr_a(mem_addr_a_inner),
		.mem_din_a(mem_din_a_inner),
		.mem_clk_b(mem_clk_b_inner),
		.mem_ren_b(mem_ren_b_inner),
		.mem_addr_b(mem_addr_b_inner),
		.mem_dout_b(mem_dout_b_inner),
		
		.acmlt_aclk(acmlt_aclk),
		.acmlt_aresetn(acmlt_aresetn),
		.acmlt_aclken(acmlt_aclken),
		.acmlt_in_new_res(acmlt_in_new_res),
		.acmlt_in_org_mid_res(acmlt_in_org_mid_res),
		.acmlt_in_mask(acmlt_in_mask),
		.acmlt_in_first_item(acmlt_in_first_item),
		.acmlt_in_last_grp(acmlt_in_last_grp),
		.acmlt_in_last_res(acmlt_in_last_res),
		.acmlt_in_info_along(acmlt_in_info_along),
		.acmlt_in_valid(acmlt_in_valid),
		.acmlt_out_data(acmlt_out_data),
		.acmlt_out_mask(acmlt_out_mask),
		.acmlt_out_last_grp(acmlt_out_last_grp),
		.acmlt_out_last_res(acmlt_out_last_res),
		.acmlt_out_to_upd_mem(acmlt_out_to_upd_mem),
		.acmlt_out_valid(acmlt_out_valid)
	);
	
	/** 输出异步fifo **/
	// fifo写端口
	wire out_async_fifo_wen;
	wire out_async_fifo_full_n;
	wire[ATOMIC_K*32-1:0] out_async_fifo_din_data;
	wire[ATOMIC_K*4-1:0] out_async_fifo_din_keep;
	wire out_async_fifo_din_is_last_sub_row;
	wire[3:0] out_async_fifo_din_sub_row_id;
	wire out_async_fifo_din_last;
	// fifo读端口
	wire out_async_fifo_ren;
	wire out_async_fifo_empty_n;
	wire[ATOMIC_K*32-1:0] out_async_fifo_dout_data;
	wire[ATOMIC_K*4-1:0] out_async_fifo_dout_keep;
	wire out_async_fifo_dout_is_last_sub_row;
	wire[3:0] out_async_fifo_dout_sub_row_id;
	wire out_async_fifo_dout_last;
	// 串并转换
	reg[ATOMIC_K*32-1:0] fnl_res_data_saved;
	reg[ATOMIC_K*4-1:0] fnl_res_keep_saved;
	reg[BUF_CLK_RATE-1:0] fnl_res_sel;
	
	assign m_axis_fnl_res_data = out_async_fifo_dout_data;
	assign m_axis_fnl_res_keep = out_async_fifo_dout_keep;
	assign m_axis_fnl_res_user = {out_async_fifo_dout_is_last_sub_row, out_async_fifo_dout_sub_row_id};
	assign m_axis_fnl_res_last = out_async_fifo_dout_last;
	assign m_axis_fnl_res_valid = aclken & out_async_fifo_empty_n;
	
	assign m_axis_inner_fnl_res_ready = 
		mid_res_buf_aclken & 
		((~fnl_res_sel[BUF_CLK_RATE-1]) | out_async_fifo_full_n);
	
	assign out_async_fifo_wen = mid_res_buf_aclken & m_axis_inner_fnl_res_valid & fnl_res_sel[BUF_CLK_RATE-1];
	
	assign out_async_fifo_din_data = 
		(BUF_CLK_RATE == 1) ? 
			m_axis_inner_fnl_res_data:
			{m_axis_inner_fnl_res_data, fnl_res_data_saved[ATOMIC_K/BUF_CLK_RATE*(BUF_CLK_RATE-1)*32-1:0]};
	assign out_async_fifo_din_keep = 
		(BUF_CLK_RATE == 1) ? 
			m_axis_inner_fnl_res_keep:
			{m_axis_inner_fnl_res_keep, fnl_res_keep_saved[ATOMIC_K/BUF_CLK_RATE*(BUF_CLK_RATE-1)*4-1:0]};
	assign {out_async_fifo_din_is_last_sub_row, out_async_fifo_din_sub_row_id} = 
		m_axis_inner_fnl_res_user;
	assign out_async_fifo_din_last = m_axis_inner_fnl_res_last & fnl_res_sel[BUF_CLK_RATE-1];
	
	assign out_async_fifo_ren = aclken & m_axis_fnl_res_ready;
	
	genvar fnl_res_saved_i;
	generate
		for(fnl_res_saved_i = 0;fnl_res_saved_i < BUF_CLK_RATE;fnl_res_saved_i = fnl_res_saved_i + 1)
		begin:fnl_res_saved_blk
			always @(posedge mid_res_buf_aclk)
			begin
				if(
					mid_res_buf_aclken & 
					m_axis_inner_fnl_res_valid & m_axis_inner_fnl_res_ready & fnl_res_sel[fnl_res_saved_i]
				)
				begin
					fnl_res_data_saved[ATOMIC_K/BUF_CLK_RATE*32*(fnl_res_saved_i+1)-1:ATOMIC_K/BUF_CLK_RATE*32*fnl_res_saved_i] <= 
						# SIM_DELAY m_axis_inner_fnl_res_data;
					fnl_res_keep_saved[ATOMIC_K/BUF_CLK_RATE*4*(fnl_res_saved_i+1)-1:ATOMIC_K/BUF_CLK_RATE*4*fnl_res_saved_i] <= 
						# SIM_DELAY m_axis_inner_fnl_res_keep;
				end
			end
		end
	endgenerate
	
	always @(posedge mid_res_buf_aclk or negedge mid_res_buf_aresetn)
	begin
		if(~mid_res_buf_aresetn)
			fnl_res_sel <= 1;
		else if(
			mid_res_buf_aclken & 
			m_axis_inner_fnl_res_valid & m_axis_inner_fnl_res_ready
		)
			fnl_res_sel <= # SIM_DELAY (fnl_res_sel << 1) | (fnl_res_sel >> (BUF_CLK_RATE-1));
	end
	
	async_fifo_with_ram #(
		.fwft_mode("true"),
		.ram_type("lutram"),
		.depth(32),
		.data_width(ATOMIC_K*32 + ATOMIC_K*4 + 1 + 1 + 4),
		.simulation_delay(SIM_DELAY)
	)out_async_fifo_u(
		.clk_wt(mid_res_buf_aclk),
		.rst_n_wt(mid_res_buf_aresetn),
		.clk_rd(aclk),
		.rst_n_rd(aresetn),
		
		.fifo_wen(out_async_fifo_wen),
		.fifo_full(),
		.fifo_full_n(out_async_fifo_full_n),
		.fifo_din({
			out_async_fifo_din_data,
			out_async_fifo_din_keep,
			out_async_fifo_din_last,
			out_async_fifo_din_is_last_sub_row,
			out_async_fifo_din_sub_row_id
		}),
		.data_cnt_wt(),
		.fifo_ren(out_async_fifo_ren),
		.fifo_empty(),
		.fifo_empty_n(out_async_fifo_empty_n),
		.fifo_dout({
			out_async_fifo_dout_data,
			out_async_fifo_dout_keep,
			out_async_fifo_dout_last,
			out_async_fifo_dout_is_last_sub_row,
			out_async_fifo_dout_sub_row_id
		}),
		.data_cnt_rd()
	);
	
endmodule
