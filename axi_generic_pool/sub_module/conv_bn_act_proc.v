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
本模块: 批归一化与激活处理单元

描述:
根据子表面行的输出通道号, 从BN参数MEM取出参数组(ATOMIC_K个参数)
进行批归一化处理(aX + b)

进行激活处理(目前仅支持Leaky Relu)

批归一化所使用的乘法器 -> 
------------------------------------------------------------------------------------------------------
| 是否支持INT16运算数据格式 | 是否支持INT32运算数据格式 |      乘法器使用情况       |   乘法器时延   |
------------------------------------------------------------------------------------------------------
|              是           |             ---           | BN_ACT_PRL_N*4个s18乘法器 |       1        |
------------------------------------------------------------------------------------------------------
|              否           |              是           | BN_ACT_PRL_N个s32乘法器   |       3        |
|                           |---------------------------|---------------------------|                |
|                           |              否           | BN_ACT_PRL_N个s25乘法器   |                |
------------------------------------------------------------------------------------------------------

Leaky Relu所使用的乘法器 -> 
-----------------------------------------------------------------------------
| 是否需要支持INT32运算数据格式 |      乘法器使用情况      |   乘法器时延   |
-----------------------------------------------------------------------------
|              是               | BN_ACT_PRL_N个s32乘法器  |       2        |
|-------------------------------|--------------------------|                |
|              否               | BN_ACT_PRL_N个s25乘法器  |                |
-----------------------------------------------------------------------------

使用1个真双口SRAM(位宽 = 64, 深度 = 最大的卷积核个数), 读时延 = 1clk
使用1个简单双口SRAM(位宽 = BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5, 深度 = 512), 读时延 = 1clk

注意：
BN与激活并行数(BN_ACT_PRL_N)必须<=核并行数(ATOMIC_K)

协议:
AXIS MASTER/SLAVE
MEM MASTER

作者: 陈家耀
日期: 2025/12/20
********************************************************************/


module conv_bn_act_proc #(
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1, // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter INT16_SUPPORTED = 1'b0, // 是否支持INT16运算数据格式
	parameter INT32_SUPPORTED = 1'b1, // 是否支持INT32运算数据格式
	parameter FP32_SUPPORTED = 1'b1, // 是否支持FP32运算数据格式
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 使能信号
	input wire en_bn_act_proc, // 使能BN与激活处理单元
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	input wire use_bn_unit, // 启用BN单元
	input wire use_act_unit, // 启用激活单元
	// [批归一化参数]
	input wire[4:0] bn_fixed_point_quat_accrc, // (操作数A)定点数量化精度
	input wire bn_is_a_eq_1, // 参数A的实际值为1(标志)
	input wire bn_is_b_eq_0, // 参数B的实际值为0(标志)
	input wire is_in_const_mac_mode, // 是否处于常量乘加模式
	input wire[31:0] param_a_in_const_mac_mode, // 常量乘加模式下的参数A
	input wire[31:0] param_b_in_const_mac_mode, // 常量乘加模式下的参数B
	// [泄露Relu激活参数]
	input wire[4:0] leaky_relu_fixed_point_quat_accrc, // (激活参数)定点数量化精度
	input wire[31:0] leaky_relu_param_alpha, // 激活参数
	
	// 子表面行信息(AXIS从机)
	input wire[15:0] s_sub_row_msg_axis_data, // {输出通道号(16bit)}
	input wire s_sub_row_msg_axis_last, // 整个输出特征图的最后1个子表面行(标志)
	input wire s_sub_row_msg_axis_valid,
	output wire s_sub_row_msg_axis_ready,
	
	// 卷积最终结果(AXIS从机)
	input wire[ATOMIC_K*32-1:0] s_axis_fnl_res_data, // 对于ATOMIC_K个最终结果 -> {单精度浮点数或定点数(32位)}
	input wire[ATOMIC_K*4-1:0] s_axis_fnl_res_keep,
	input wire[4:0] s_axis_fnl_res_user, // {是否最后1个子行(1bit), 子行号(4bit)}
	input wire s_axis_fnl_res_last, // 本行最后1个最终结果(标志)
	input wire s_axis_fnl_res_valid,
	output wire s_axis_fnl_res_ready,
	
	// 经过BN与激活处理的结果(AXIS主机)
	output wire[BN_ACT_PRL_N*32-1:0] m_axis_bn_act_res_data, // 对于BN_ACT_PRL_N个最终结果 -> {单精度浮点数或定点数(32位)}
	output wire[BN_ACT_PRL_N*4-1:0] m_axis_bn_act_res_keep,
	output wire[4:0] m_axis_bn_act_res_user,
	output wire m_axis_bn_act_res_last, // 本行最后1个处理结果(标志)
	output wire m_axis_bn_act_res_valid,
	input wire m_axis_bn_act_res_ready,
	
	// BN参数MEM主接口
	output wire bn_mem_clk_b,
	output wire bn_mem_ren_b,
	output wire[15:0] bn_mem_addr_b,
	input wire[63:0] bn_mem_dout_b, // {参数B(32bit), 参数A(32bit)}
	
	// 处理结果fifo(MEM主接口)
	output wire proc_res_fifo_mem_clk,
	output wire proc_res_fifo_mem_wen_a,
	output wire[8:0] proc_res_fifo_mem_addr_a,
	output wire[(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_mem_din_a,
	output wire proc_res_fifo_mem_ren_b,
	output wire[8:0] proc_res_fifo_mem_addr_b,
	input wire[(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_mem_dout_b,
	
	// 外部有符号乘法器#0
	output wire[(INT16_SUPPORTED ? 4*18:(INT32_SUPPORTED ? 32:25))*BN_ACT_PRL_N-1:0] mul0_op_a, // 操作数A
	output wire[(INT16_SUPPORTED ? 4*18:(INT32_SUPPORTED ? 32:25))*BN_ACT_PRL_N-1:0] mul0_op_b, // 操作数B
	output wire[(INT16_SUPPORTED ? 4:3)*BN_ACT_PRL_N-1:0] mul0_ce, // 计算使能
	input wire[(INT16_SUPPORTED ? 4*36:(INT32_SUPPORTED ? 64:50))*BN_ACT_PRL_N-1:0] mul0_res, // 计算结果
	
	// 外部有符号乘法器#1
	output wire[(INT32_SUPPORTED ? 32:25)*BN_ACT_PRL_N-1:0] mul1_op_a, // 操作数A
	output wire[(INT32_SUPPORTED ? 32:25)*BN_ACT_PRL_N-1:0] mul1_op_b, // 操作数B
	output wire[2*BN_ACT_PRL_N-1:0] mul1_ce, // 计算使能
	input wire[(INT32_SUPPORTED ? 64:50)*BN_ACT_PRL_N-1:0] mul1_res // 计算结果
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
	
	/** 常量 **/
	// 每个表面的最大处理轮次
	localparam integer MAX_PROC_ROUND_N = ATOMIC_K / BN_ACT_PRL_N;
	// 获取BN参数的状态编码
	localparam integer BN_FTC_STS_READY_ONEHOT = 0; // 状态: 准备好获取下1组BN参数
	localparam integer BN_FTC_STS_RD_MEM_ONEHOT = 1; // 状态: 读BN参数MEM
	localparam integer BN_FTC_STS_WAIT_ONEHOT = 2; // 状态: 组内等待
	// 外部有符号乘法器#0的位宽
	localparam integer MUL0_OP_WIDTH = INT16_SUPPORTED ? 4*18:(INT32_SUPPORTED ? 32:25);
	localparam integer MUL0_CE_WIDTH = INT16_SUPPORTED ? 4:3;
	localparam integer MUL0_RES_WIDTH = INT16_SUPPORTED ? 4*36:(INT32_SUPPORTED ? 64:50);
	// 外部有符号乘法器#1的位宽
	localparam integer MUL1_OP_WIDTH = INT32_SUPPORTED ? 32:25;
	localparam integer MUL1_CE_WIDTH = 2;
	localparam integer MUL1_RES_WIDTH = INT32_SUPPORTED ? 64:50;
	
	/** 子表面行信息fifo **/
	wire sub_row_msg_fifo_wen;
	wire[15:0] sub_row_msg_fifo_din; // {输出通道号(16bit)}
	wire sub_row_msg_fifo_full_n;
	wire sub_row_msg_fifo_ren;
	wire[15:0] sub_row_msg_fifo_dout; // {输出通道号(16bit)}
	wire sub_row_msg_fifo_empty_n;
	
	assign s_sub_row_msg_axis_ready = aclken & en_bn_act_proc & (is_in_const_mac_mode | sub_row_msg_fifo_full_n);
	
	assign sub_row_msg_fifo_wen = aclken & en_bn_act_proc & (~is_in_const_mac_mode) & s_sub_row_msg_axis_valid;
	assign sub_row_msg_fifo_din = s_sub_row_msg_axis_data;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(8),
		.fifo_data_width(16),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)sub_row_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(sub_row_msg_fifo_wen),
		.fifo_din(sub_row_msg_fifo_din),
		.fifo_full(),
		.fifo_full_n(sub_row_msg_fifo_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(),
		
		.fifo_ren(sub_row_msg_fifo_ren),
		.fifo_dout(sub_row_msg_fifo_dout),
		.fifo_empty(),
		.fifo_empty_n(sub_row_msg_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	/** BN参数乒乓缓存 **/
	reg[ATOMIC_K*32-1:0] bn_param_buf_a[0:1]; // 参数A缓存区
	reg[ATOMIC_K*32-1:0] bn_param_buf_b[0:1]; // 参数B缓存区
	wire bn_param_buf_wen;
	reg[1:0] bn_param_buf_wptr;
	wire bn_param_buf_full;
	wire bn_param_buf_ren;
	reg[1:0] bn_param_buf_rptr;
	wire bn_param_buf_empty;
	reg[2:0] bn_param_fetch_sts; // 获取BN参数(状态)
	reg[15:0] bn_param_fetch_cid; // 待取BN参数的输出通道号(计数器)
	reg[clogb2(ATOMIC_K-1):0] bn_param_fetch_data_id; // 待取BN参数的数据号(计数器)
	reg to_upd_bn_param_buf; // 更新BN参数缓存区(标志)
	reg[clogb2(ATOMIC_K-1):0] upd_bn_param_data_id; // 待更新的数据号
	
	assign sub_row_msg_fifo_ren = 
		aclken & en_bn_act_proc & 
		(
			is_in_const_mac_mode | 
			(
				bn_param_fetch_sts[BN_FTC_STS_READY_ONEHOT] & 
				(~bn_param_buf_full)
			)
		);
	
	assign bn_mem_clk_b = aclk;
	assign bn_mem_ren_b = aclken & bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT];
	assign bn_mem_addr_b = bn_param_fetch_cid;
	
	assign bn_param_buf_wen = bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT];
	assign bn_param_buf_full = (bn_param_buf_wptr[1] ^ bn_param_buf_rptr[1]) & (~(bn_param_buf_wptr[0] ^ bn_param_buf_rptr[0]));
	assign bn_param_buf_empty = bn_param_buf_wptr == bn_param_buf_rptr;
	
	// BN参数缓存(参数A, 参数B)
	genvar bn_param_buf_i;
	genvar bn_param_buf_j;
	generate
		for(bn_param_buf_i = 0;bn_param_buf_i < 2;bn_param_buf_i = bn_param_buf_i + 1)
		begin:bn_param_buf_item_blk
			for(bn_param_buf_j = 0;bn_param_buf_j < ATOMIC_K;bn_param_buf_j = bn_param_buf_j + 1)
			begin:bn_param_buf_data_blk
				always @(posedge aclk)
				begin
					if(
						aclken & en_bn_act_proc & 
						to_upd_bn_param_buf & 
						(bn_param_buf_wptr[0] == bn_param_buf_i) & (upd_bn_param_data_id == bn_param_buf_j)
					)
					begin
						bn_param_buf_a[bn_param_buf_i][bn_param_buf_j*32+31:bn_param_buf_j*32] <= # SIM_DELAY bn_mem_dout_b[31:0];
						bn_param_buf_b[bn_param_buf_i][bn_param_buf_j*32+31:bn_param_buf_j*32] <= # SIM_DELAY bn_mem_dout_b[63:32];
					end
				end
			end
		end
	endgenerate
	
	// BN参数缓存区写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			bn_param_buf_wptr <= 2'b00;
		else if(
			aclken & 
			((~en_bn_act_proc) | (bn_param_buf_wen & (~bn_param_buf_full)))
		)
			bn_param_buf_wptr <= # SIM_DELAY 
				en_bn_act_proc ? 
					(bn_param_buf_wptr + 1'b1):
					2'b00;
	end
	
	// BN参数缓存区读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			bn_param_buf_rptr <= 2'b00;
		else if(
			aclken & 
			((~en_bn_act_proc) | (bn_param_buf_ren & (~bn_param_buf_empty)))
		)
			bn_param_buf_rptr <= # SIM_DELAY 
				en_bn_act_proc ? 
					(bn_param_buf_rptr + 1'b1):
					2'b00;
	end
	
	// 获取BN参数(状态)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			bn_param_fetch_sts <= 1 << BN_FTC_STS_READY_ONEHOT;
		else if(
			aclken & 
			(
				(~en_bn_act_proc) | 
				(
					bn_param_fetch_sts[BN_FTC_STS_READY_ONEHOT] & 
					(~is_in_const_mac_mode) & sub_row_msg_fifo_empty_n & sub_row_msg_fifo_ren
				) | 
				(bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT] & (bn_param_fetch_data_id == (ATOMIC_K-1))) | 
				bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT]
			)
		)
			bn_param_fetch_sts <= # SIM_DELAY 
				en_bn_act_proc ? 
				(
					(
						{3{bn_param_fetch_sts[BN_FTC_STS_READY_ONEHOT]}} & 
						(
							(bn_is_a_eq_1 & bn_is_b_eq_0) ? 
								(1 << BN_FTC_STS_WAIT_ONEHOT):
								(1 << BN_FTC_STS_RD_MEM_ONEHOT)
						)
					) | 
					(
						{3{bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT]}} & 
						(1 << BN_FTC_STS_WAIT_ONEHOT)
					) | 
					(
						{3{bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT]}} & 
						(1 << BN_FTC_STS_READY_ONEHOT)
					)
				):
				(1 << BN_FTC_STS_READY_ONEHOT);
	end
	
	// 待取BN参数的输出通道号(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			en_bn_act_proc & 
			(
				(
					bn_param_fetch_sts[BN_FTC_STS_READY_ONEHOT] & 
					(~is_in_const_mac_mode) & sub_row_msg_fifo_empty_n & sub_row_msg_fifo_ren & 
					(~(bn_is_a_eq_1 & bn_is_b_eq_0))
				) | 
				bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT]
			)
		)
			bn_param_fetch_cid <= # SIM_DELAY 
				bn_param_fetch_sts[BN_FTC_STS_READY_ONEHOT] ? 
					sub_row_msg_fifo_dout[15:0]:
					(bn_param_fetch_cid + 1'b1);
	end
	
	// 待取BN参数的数据号(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				(~en_bn_act_proc) | 
				bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT] | 
				bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT]
			)
		)
			bn_param_fetch_data_id <= # SIM_DELAY 
				((ATOMIC_K == 1) | (~en_bn_act_proc) | bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT]) ? 
					0:
					(bn_param_fetch_data_id + 1'b1);
	end
	
	// 更新BN参数缓存区(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			to_upd_bn_param_buf <= 1'b0;
		else if(
			aclken & 
			(
				(~en_bn_act_proc) | 
				(
					to_upd_bn_param_buf ? 
						bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT]:
						bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT]
				)
			)
		)
			to_upd_bn_param_buf <= # SIM_DELAY 
				en_bn_act_proc & (~to_upd_bn_param_buf);
	end
	
	// 待更新的数据号
	always @(posedge aclk)
	begin
		if(aclken & bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT])
			upd_bn_param_data_id <= # SIM_DELAY bn_param_fetch_data_id;
	end
	
	/** 批归一化处理 **/
	// [卷积最终结果表面选取]
	wire to_pass_fnl_sfc; // 放行最终结果表面(标志)
	wire fnl_sfc_in_vld; // 最终结果表面输入有效(指示)
	wire[ATOMIC_K-1:0] fnl_sfc_mask; // 最终结果表面有效掩码
	wire last_fnl_data_blk_in_tsf; // 本次传输里的最后1个最终结果数据块(标志)
	wire last_data_blk_in_row; // 本行的最后1个最终结果数据块(标志)
	reg[ATOMIC_K-1:0] optional_fnl_data_blk_mask; // 可选的最终结果数据块(掩码)
	reg[clogb2(MAX_PROC_ROUND_N-1):0] bn_proc_round_id; // BN处理轮次(计数器)
	wire[BN_ACT_PRL_N*32-1:0] cur_sfc_data; // 当前的最终结果表面数据
	wire[BN_ACT_PRL_N-1:0] cur_sfc_mask; // 当前的最终结果表面有效掩码
	wire[BN_ACT_PRL_N*32-1:0] cur_bn_param_a; // 当前的BN参数A
	wire[BN_ACT_PRL_N*32-1:0] cur_bn_param_b; // 当前的BN参数B
	// [BN单元]
	wire[BN_ACT_PRL_N-1:0] bn_mac_i_vld;
	wire[BN_ACT_PRL_N+1+5-1:0] bn_mac_i_info_along[0:BN_ACT_PRL_N-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N*32-1:0] bn_mac_o_res; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] bn_mac_o_info_along[0:BN_ACT_PRL_N-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N-1:0] bn_mac_o_vld;
	wire[BN_ACT_PRL_N*32-1:0] bn_mac_o_res_actual; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] bn_mac_o_info_along_actual[0:BN_ACT_PRL_N-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N-1:0] bn_mac_o_vld_actual;
	
	assign s_axis_fnl_res_ready = 
		aclken & 
		en_bn_act_proc & 
		to_pass_fnl_sfc & 
		(is_in_const_mac_mode | (~bn_param_buf_empty)) & 
		last_fnl_data_blk_in_tsf;
	
	assign bn_param_buf_ren = is_in_const_mac_mode | (s_axis_fnl_res_valid & s_axis_fnl_res_ready & s_axis_fnl_res_last);
	
	assign fnl_sfc_in_vld = 
		en_bn_act_proc & 
		to_pass_fnl_sfc & 
		(is_in_const_mac_mode | (~bn_param_buf_empty)) & 
		s_axis_fnl_res_valid;
	assign last_fnl_data_blk_in_tsf = 
		optional_fnl_data_blk_mask[ATOMIC_K-1] | 
		(~(|((optional_fnl_data_blk_mask << BN_ACT_PRL_N) & fnl_sfc_mask)));
	assign last_data_blk_in_row = 
		last_fnl_data_blk_in_tsf & 
		s_axis_fnl_res_last;
	
	assign cur_sfc_data = s_axis_fnl_res_data >> (BN_ACT_PRL_N*32*bn_proc_round_id);
	assign cur_sfc_mask = fnl_sfc_mask >> (BN_ACT_PRL_N*bn_proc_round_id);
	assign cur_bn_param_a = 
		is_in_const_mac_mode ? 
			{BN_ACT_PRL_N{param_a_in_const_mac_mode}}:
			(bn_param_buf_a[bn_param_buf_rptr[0]] >> (BN_ACT_PRL_N*32*bn_proc_round_id));
	assign cur_bn_param_b = 
		is_in_const_mac_mode ? 
			{BN_ACT_PRL_N{param_b_in_const_mac_mode}}:
			(bn_param_buf_b[bn_param_buf_rptr[0]] >> (BN_ACT_PRL_N*32*bn_proc_round_id));
	
	genvar fnl_sfc_i;
	generate
		for(fnl_sfc_i = 0;fnl_sfc_i < ATOMIC_K;fnl_sfc_i = fnl_sfc_i + 1)
		begin:fnl_sfc_blk
			assign fnl_sfc_mask[fnl_sfc_i] = s_axis_fnl_res_keep[fnl_sfc_i*4];
		end
	endgenerate
	
	assign bn_mac_o_res_actual = 
		use_bn_unit ? 
			bn_mac_o_res:
			cur_sfc_data;
	assign bn_mac_o_vld_actual = 
		use_bn_unit ? 
			bn_mac_o_vld:
			bn_mac_i_vld;
	
	// 可选的最终结果数据块(掩码)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			optional_fnl_data_blk_mask <= (1 << BN_ACT_PRL_N) - 1;
		else if(
			aclken & 
			((~en_bn_act_proc) | fnl_sfc_in_vld)
		)
			optional_fnl_data_blk_mask <= # SIM_DELAY 
				en_bn_act_proc ? 
					(
						last_fnl_data_blk_in_tsf ? 
							((1 << BN_ACT_PRL_N) - 1):
							(optional_fnl_data_blk_mask << BN_ACT_PRL_N)
					):
					((1 << BN_ACT_PRL_N) - 1);
	end
	
	// BN处理轮次(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			bn_proc_round_id <= 0;
		else if(
			(MAX_PROC_ROUND_N > 1) & 
			aclken & 
			((~en_bn_act_proc) | fnl_sfc_in_vld)
		)
			bn_proc_round_id <= # SIM_DELAY 
				en_bn_act_proc ? 
					(
						last_fnl_data_blk_in_tsf ? 
							0:
							(bn_proc_round_id + 1'b1)
					):
					0;
	end
	
	genvar bn_cell_i;
	generate
		for(bn_cell_i = 0;bn_cell_i < BN_ACT_PRL_N;bn_cell_i = bn_cell_i + 1)
		begin:bn_mac_blk
			assign bn_mac_i_vld[bn_cell_i] = 
				fnl_sfc_in_vld & cur_sfc_mask[bn_cell_i];
			assign bn_mac_i_info_along[bn_cell_i] = 
				(bn_cell_i == 0) ? 
					{
						s_axis_fnl_res_user[4], // 是否最后1个子行(1bit)
						s_axis_fnl_res_user[3:0], // 子行号(4bit)
						cur_sfc_mask, // 数据有效掩码(BN_ACT_PRL_N bit)
						last_data_blk_in_row // 行内最后1个数据块标志(1bit)
					}:
					{(BN_ACT_PRL_N+1+5){1'bx}};
			
			assign bn_mac_o_info_along_actual[bn_cell_i] = 
				use_bn_unit ? 
					bn_mac_o_info_along[bn_cell_i]:
					bn_mac_i_info_along[bn_cell_i];
			
			batch_nml_mac_cell #(
				.INT16_SUPPORTED(INT16_SUPPORTED),
				.INT32_SUPPORTED(INT32_SUPPORTED),
				.FP32_SUPPORTED(FP32_SUPPORTED),
				.INFO_ALONG_WIDTH(BN_ACT_PRL_N+1+5),
				.SIM_DELAY(SIM_DELAY)
			)batch_nml_mac_cell_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				
				.bn_calfmt(calfmt),
				.fixed_point_quat_accrc(bn_fixed_point_quat_accrc),
				
				.mac_cell_i_op_a(cur_bn_param_a[bn_cell_i*32+31:bn_cell_i*32]),
				.mac_cell_i_op_x(cur_sfc_data[bn_cell_i*32+31:bn_cell_i*32]),
				.mac_cell_i_op_b(cur_bn_param_b[bn_cell_i*32+31:bn_cell_i*32]),
				.mac_cell_i_is_a_eq_1(bn_is_a_eq_1),
				.mac_cell_i_is_b_eq_0(bn_is_b_eq_0),
				.mac_cell_i_info_along(bn_mac_i_info_along[bn_cell_i]),
				.mac_cell_i_vld(bn_mac_i_vld[bn_cell_i]),
				
				.mac_cell_o_res(bn_mac_o_res[bn_cell_i*32+31:bn_cell_i*32]),
				.mac_cell_o_info_along(bn_mac_o_info_along[bn_cell_i]),
				.mac_cell_o_vld(bn_mac_o_vld[bn_cell_i]),
				
				.mul_op_a(mul0_op_a[MUL0_OP_WIDTH*(bn_cell_i+1)-1:MUL0_OP_WIDTH*bn_cell_i]),
				.mul_op_b(mul0_op_b[MUL0_OP_WIDTH*(bn_cell_i+1)-1:MUL0_OP_WIDTH*bn_cell_i]),
				.mul_ce(mul0_ce[MUL0_CE_WIDTH*(bn_cell_i+1)-1:MUL0_CE_WIDTH*bn_cell_i]),
				.mul_res(mul0_res[MUL0_RES_WIDTH*(bn_cell_i+1)-1:MUL0_RES_WIDTH*bn_cell_i])
			);
		end
	endgenerate
	
	/**
	激活处理
	
	目前仅支持Leaky Relu
	**/
	wire[BN_ACT_PRL_N*32-1:0] act_grp_o_res; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] act_grp_o_info_along[0:BN_ACT_PRL_N-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N-1:0] act_grp_o_vld;
	wire[BN_ACT_PRL_N*32-1:0] act_grp_o_res_actual; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] act_grp_o_info_along_actual[0:BN_ACT_PRL_N-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N-1:0] act_grp_o_vld_actual;
	
	assign act_grp_o_res_actual = 
		use_act_unit ? 
			act_grp_o_res:
			bn_mac_o_res_actual;
	assign act_grp_o_vld_actual = 
		use_act_unit ? 
			act_grp_o_vld:
			bn_mac_o_vld_actual;
	
	genvar act_i;
	generate
		for(act_i = 0;act_i < BN_ACT_PRL_N;act_i = act_i + 1)
		begin:act_blk
			assign act_grp_o_info_along_actual[act_i] = 
				use_act_unit ? 
					act_grp_o_info_along[act_i]:
					bn_mac_o_info_along_actual[act_i];
			
			leaky_relu_cell #(
				.INT16_SUPPORTED(INT16_SUPPORTED),
				.INT32_SUPPORTED(INT32_SUPPORTED),
				.FP32_SUPPORTED(FP32_SUPPORTED),
				.INFO_ALONG_WIDTH(BN_ACT_PRL_N+1+5),
				.SIM_DELAY(SIM_DELAY)
			)leaky_relu_cell_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				
				.act_calfmt(calfmt),
				.fixed_point_quat_accrc(leaky_relu_fixed_point_quat_accrc),
				.act_param_alpha(leaky_relu_param_alpha),
				
				.act_cell_i_op_x(bn_mac_o_res_actual[act_i*32+31:act_i*32]),
				.act_cell_i_pass(1'b0),
				.act_cell_i_info_along(bn_mac_o_info_along_actual[act_i]),
				.act_cell_i_vld(bn_mac_o_vld_actual[act_i]),
				
				.act_cell_o_res(act_grp_o_res[act_i*32+31:act_i*32]),
				.act_cell_o_info_along(act_grp_o_info_along[act_i]),
				.act_cell_o_vld(act_grp_o_vld[act_i]),
				
				.mul_op_a(mul1_op_a[MUL1_OP_WIDTH*(act_i+1)-1:MUL1_OP_WIDTH*act_i]),
				.mul_op_b(mul1_op_b[MUL1_OP_WIDTH*(act_i+1)-1:MUL1_OP_WIDTH*act_i]),
				.mul_ce(mul1_ce[MUL1_CE_WIDTH*(act_i+1)-1:MUL1_CE_WIDTH*act_i]),
				.mul_res(mul1_res[MUL1_RES_WIDTH*(act_i+1)-1:MUL1_RES_WIDTH*act_i])
			);
		end
	endgenerate
	
	/** 处理结果fifo **/
	// [写端口]
	wire proc_res_fifo_wen;
	wire[(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_din; // {是否最后1个子行(1bit), 子行号(4bit), 计算结果(BN_ACT_PRL_N*32 bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)}
	wire proc_res_fifo_full_n;
	wire proc_res_fifo_almost_full_n;
	// [读端口]
	wire proc_res_fifo_ren;
	wire[(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_dout; // {是否最后1个子行(1bit), 子行号(4bit), 计算结果(BN_ACT_PRL_N*32 bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)}
	wire proc_res_fifo_empty_n;
	
	assign m_axis_bn_act_res_data = proc_res_fifo_dout[(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1)-1:BN_ACT_PRL_N+1];
	
	genvar m_axis_bn_act_res_mask_i;
	generate
		for(m_axis_bn_act_res_mask_i = 0;m_axis_bn_act_res_mask_i < BN_ACT_PRL_N;m_axis_bn_act_res_mask_i = m_axis_bn_act_res_mask_i + 1)
		begin:m_axis_bn_act_res_mask_blk
			assign m_axis_bn_act_res_keep[m_axis_bn_act_res_mask_i*4+3:m_axis_bn_act_res_mask_i*4] = 
				{4{proc_res_fifo_dout[m_axis_bn_act_res_mask_i+1]}};
		end
	endgenerate
	
	assign m_axis_bn_act_res_user = proc_res_fifo_dout[(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5)-1:BN_ACT_PRL_N*32+BN_ACT_PRL_N+1];
	
	assign m_axis_bn_act_res_last = proc_res_fifo_dout[0];
	assign m_axis_bn_act_res_valid = aclken & proc_res_fifo_empty_n;
	
	assign proc_res_fifo_mem_clk = aclk;
	
	assign to_pass_fnl_sfc = proc_res_fifo_almost_full_n;
	
	assign proc_res_fifo_wen = act_grp_o_vld_actual[0];
	assign proc_res_fifo_din = {
		act_grp_o_info_along_actual[0][(BN_ACT_PRL_N+1+5)-1], // 是否最后1个子行(1bit)
		act_grp_o_info_along_actual[0][(BN_ACT_PRL_N+1+4)-1:BN_ACT_PRL_N+1], // 子行号(4bit)
		act_grp_o_res_actual[BN_ACT_PRL_N*32-1:0], // 计算结果(BN_ACT_PRL_N*32 bit)
		act_grp_o_info_along_actual[0][(BN_ACT_PRL_N+1)-1:1], // 数据有效掩码(BN_ACT_PRL_N bit)
		act_grp_o_info_along_actual[0][0] // 行内最后1个数据块标志(1bit)
	};
	assign proc_res_fifo_ren = aclken & m_axis_bn_act_res_ready;
	
	fifo_based_on_ram #(
		.fwft_mode("true"),
		.ram_read_la(1),
		.fifo_depth(512),
		.fifo_data_width(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5),
		.almost_full_th(480),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)proc_res_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(proc_res_fifo_wen),
		.fifo_din(proc_res_fifo_din),
		.fifo_full(),
		.fifo_full_n(proc_res_fifo_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(proc_res_fifo_almost_full_n),
		
		.fifo_ren(proc_res_fifo_ren),
		.fifo_dout(proc_res_fifo_dout),
		.fifo_empty(),
		.fifo_empty_n(proc_res_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.ram_wen(proc_res_fifo_mem_wen_a),
		.ram_w_addr(proc_res_fifo_mem_addr_a),
		.ram_din(proc_res_fifo_mem_din_a),
		
		.ram_ren(proc_res_fifo_mem_ren_b),
		.ram_r_addr(proc_res_fifo_mem_addr_b),
		.ram_dout(proc_res_fifo_mem_dout_b),
		
		.data_cnt()
	);
	
endmodule
