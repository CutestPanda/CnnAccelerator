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

进行激活处理(支持Leaky Relu和Sigmoid)

支持独立的BN与激活计算核心时钟, 实际的BN与激活单元数 = BN_ACT_PRL_N/BN_ACT_CLK_RATE

可选的舍入 -> 
---------------------------------------
|  待舍入数据格式  |  舍入后数据格式  |
---------------------------------------
|      INT16       |       INT8       |
---------------------------------------
|      INT32       |      INT16       |
---------------------------------------
|       FP32       |       FP16       |
---------------------------------------

批归一化所使用的乘法器 -> 
----------------------------------------------------------------------------------------------------------------------
| 是否支持INT16运算数据格式 | 是否支持INT32运算数据格式 |               乘法器使用情况              |   乘法器时延   |
----------------------------------------------------------------------------------------------------------------------
|              是           |             ---           | BN_ACT_PRL_N/BN_ACT_CLK_RATE*4个s18乘法器 |       1        |
----------------------------------------------------------------------------------------------------------------------
|              否           |              是           | BN_ACT_PRL_N/BN_ACT_CLK_RATE个s32乘法器   |       3        |
|                           |---------------------------|-------------------------------------------|                |
|                           |              否           | BN_ACT_PRL_N/BN_ACT_CLK_RATE个s25乘法器   |                |
----------------------------------------------------------------------------------------------------------------------

Leaky Relu所使用的乘法器 -> 
---------------------------------------------------------------------------------------------
| 是否需要支持INT32运算数据格式 |              乘法器使用情况              |   乘法器时延   |
---------------------------------------------------------------------------------------------
|              是               | BN_ACT_PRL_N/BN_ACT_CLK_RATE个s32乘法器  |       2        |
|-------------------------------|------------------------------------------|                |
|              否               | BN_ACT_PRL_N/BN_ACT_CLK_RATE个s25乘法器  |                |
---------------------------------------------------------------------------------------------

使用1个真双口SRAM(位宽 = 64, 深度 = 最大的卷积核个数), 读时延 = 1clk
使用1个简单双口SRAM(位宽 = BN_ACT_PRL_N*(16或32)+BN_ACT_PRL_N+1+5, 深度 = 512), 读时延 = 1clk
使用BN_ACT_PRL_N/BN_ACT_CLK_RATE个单口SRAM(位宽 = 16, 深度 = 4096), 读时延 = 1clk

注意：
BN与激活并行数(BN_ACT_PRL_N)必须<=核并行数(ATOMIC_K)
BN与激活并行数(BN_ACT_PRL_N)必须能被BN与激活单元的时钟倍率(BN_ACT_CLK_RATE)整除

协议:
AXIS MASTER/SLAVE
MEM MASTER

作者: 陈家耀
日期: 2026/01/02
********************************************************************/


module conv_bn_act_proc #(
	parameter integer BN_ACT_CLK_RATE = 1, // BN与激活单元的时钟倍率(>=1)
	parameter FP32_KEEP = 1'b1, // 是否保持FP32输出
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1, // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter INT16_SUPPORTED = 1'b0, // 是否支持INT16运算数据格式
	parameter INT32_SUPPORTED = 1'b1, // 是否支持INT32运算数据格式
	parameter FP32_SUPPORTED = 1'b1, // 是否支持FP32运算数据格式
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	// BN与激活单元时钟和复位
	input wire bn_act_aclk,
	input wire bn_act_aresetn,
	input wire bn_act_aclken,
	
	// 使能信号
	input wire en_bn_act_proc, // 使能BN与激活处理单元
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	input wire use_bn_unit, // 启用BN单元
	input wire[2:0] act_func_type, // 激活函数类型
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
	// [Sigmoid激活参数]
	input wire[4:0] sigmoid_fixed_point_quat_accrc, // 输入定点数量化精度
	
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
	output wire[BN_ACT_PRL_N*(FP32_KEEP ? 32:16)-1:0] m_axis_bn_act_res_data, // 对于BN_ACT_PRL_N个最终结果 -> {浮点数或定点数}
	output wire[BN_ACT_PRL_N*(FP32_KEEP ? 4:2)-1:0] m_axis_bn_act_res_keep,
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
	output wire proc_res_fifo_mem_clk_a,
	output wire proc_res_fifo_mem_wen_a,
	output wire[8:0] proc_res_fifo_mem_addr_a,
	output wire[(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_mem_din_a,
	output wire proc_res_fifo_mem_clk_b,
	output wire proc_res_fifo_mem_ren_b,
	output wire[8:0] proc_res_fifo_mem_addr_b,
	input wire[(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_mem_dout_b,
	
	// Sigmoid函数值查找表(MEM主接口)
	output wire sigmoid_lut_mem_clk_a,
	output wire[BN_ACT_PRL_N-1:0] sigmoid_lut_mem_ren_a,
	output wire[12*BN_ACT_PRL_N-1:0] sigmoid_lut_mem_addr_a,
	input wire[16*BN_ACT_PRL_N-1:0] sigmoid_lut_mem_dout_a,
	
	// 外部有符号乘法器#0
	output wire mul0_clk,
	output wire[(INT16_SUPPORTED ? 4*18:(INT32_SUPPORTED ? 32:25))*BN_ACT_PRL_N-1:0] mul0_op_a, // 操作数A
	output wire[(INT16_SUPPORTED ? 4*18:(INT32_SUPPORTED ? 32:25))*BN_ACT_PRL_N-1:0] mul0_op_b, // 操作数B
	output wire[(INT16_SUPPORTED ? 4:3)*BN_ACT_PRL_N-1:0] mul0_ce, // 计算使能
	input wire[(INT16_SUPPORTED ? 4*36:(INT32_SUPPORTED ? 64:50))*BN_ACT_PRL_N-1:0] mul0_res, // 计算结果
	
	// 外部有符号乘法器#1
	output wire mul1_clk,
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
	// 激活函数类型的编码
	localparam ACT_FUNC_TYPE_LEAKY_RELU = 3'b000; // 泄露Relu
	localparam ACT_FUNC_TYPE_SIGMOID = 3'b001; // sigmoid
	localparam ACT_FUNC_TYPE_NONE = 3'b111;
	// 每个表面的最大处理轮次
	localparam integer MAX_PROC_ROUND_N = ATOMIC_K / (BN_ACT_PRL_N / BN_ACT_CLK_RATE);
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
	
	/** 使能信号跨时钟域处理 **/
	reg en_bn_act_proc_d1;
	reg en_bn_act_proc_d2;
	reg en_bn_act_proc_d3;
	wire en_bn_act_proc_sync;
	
	assign en_bn_act_proc_sync = 
		(BN_ACT_CLK_RATE == 1) ? 
			en_bn_act_proc:
			en_bn_act_proc_d3;
	
	// 跨时钟域: ... -> en_bn_act_proc_d1
	always @(posedge bn_act_aclk or negedge bn_act_aresetn)
	begin
		if(~bn_act_aresetn)
			{en_bn_act_proc_d3, en_bn_act_proc_d2, en_bn_act_proc_d1} <= 3'b000;
		else
			{en_bn_act_proc_d3, en_bn_act_proc_d2, en_bn_act_proc_d1} <= # SIM_DELAY 
				{en_bn_act_proc_d2, en_bn_act_proc_d1, en_bn_act_proc};
	end
	
	/** BN与激活输入异步fifo **/
	// [fifo写端口]
	wire bn_act_in_async_fifo_wen;
	wire bn_act_in_async_fifo_full_n;
	wire[BN_ACT_PRL_N*32-1:0] bn_act_in_async_fifo_din_data; // 数据块
	wire[BN_ACT_PRL_N-1:0] bn_act_in_async_fifo_din_mask; // 项掩码
	wire bn_act_in_async_fifo_din_last_sub_row_flag; // 最后1个子行(标志)
	wire[3:0] bn_act_in_async_fifo_din_sub_row_id; // 子行号
	wire bn_act_in_async_fifo_din_last_data_blk_in_sfc; // 本表面最后1个数据块(标志)
	wire bn_act_in_async_fifo_din_last_data_blk; // 本行最后1个数据块(标志)
	// [fifo读端口]
	wire bn_act_in_async_fifo_ren;
	wire bn_act_in_async_fifo_empty_n;
	wire[BN_ACT_PRL_N*32-1:0] bn_act_in_async_fifo_dout_data; // 数据块
	wire[BN_ACT_PRL_N-1:0] bn_act_in_async_fifo_dout_mask; // 项掩码
	wire bn_act_in_async_fifo_dout_last_sub_row_flag; // 最后1个子行(标志)
	wire[3:0] bn_act_in_async_fifo_dout_sub_row_id; // 子行号
	wire bn_act_in_async_fifo_dout_last_data_blk_in_sfc; // 本表面最后1个数据块(标志)
	wire bn_act_in_async_fifo_dout_last_data_blk_in_row; // 本行最后1个数据块(标志)
	// [从最终结果表面生成数据块]
	wire[ATOMIC_K-1:0] fnl_sfc_mask; // 最终结果表面有效掩码
	reg[clogb2(ATOMIC_K/BN_ACT_PRL_N-1):0] async_blk_gen_sel_bin_cnt; // 块选择(二进制码)计数器
	reg[ATOMIC_K/BN_ACT_PRL_N-1:0] async_blk_gen_sel_onehot_cnt; // 块选择(独热码)计数器
	wire[ATOMIC_K/BN_ACT_PRL_N-1:0] async_blk_gen_sel_onehot_cnt_nxt; // 块选择(独热码)下一计数值
	wire[ATOMIC_K-1:0] async_blk_gen_nxt_mask_test_vec; // 下一数据块(包含有效项)测试掩码
	wire async_blk_gen_last_flag; // 本表面最后1个数据块(标志)
	// [BN与激活输入并串转换]
	reg[clogb2(BN_ACT_CLK_RATE-1):0] bn_act_in_round_cnt; // BN与激活输入轮次(计数器)
	
	assign bn_act_in_async_fifo_wen = 
		(BN_ACT_CLK_RATE > 1) & 
		aclken & en_bn_act_proc & 
		s_axis_fnl_res_valid;
	
	assign bn_act_in_async_fifo_din_data = s_axis_fnl_res_data >> (BN_ACT_PRL_N*32*async_blk_gen_sel_bin_cnt);
	assign bn_act_in_async_fifo_din_mask = fnl_sfc_mask >> (BN_ACT_PRL_N*async_blk_gen_sel_bin_cnt);
	assign bn_act_in_async_fifo_din_last_sub_row_flag = s_axis_fnl_res_user[4];
	assign bn_act_in_async_fifo_din_sub_row_id = s_axis_fnl_res_user[3:0];
	assign bn_act_in_async_fifo_din_last_data_blk_in_sfc = async_blk_gen_last_flag;
	assign bn_act_in_async_fifo_din_last_data_blk = async_blk_gen_last_flag & s_axis_fnl_res_last;
	
	genvar fnl_sfc_i;
	generate
		for(fnl_sfc_i = 0;fnl_sfc_i < ATOMIC_K;fnl_sfc_i = fnl_sfc_i + 1)
		begin:fnl_sfc_blk
			assign fnl_sfc_mask[fnl_sfc_i] = s_axis_fnl_res_keep[fnl_sfc_i*4];
		end
	endgenerate
	
	genvar test_vec_i;
	generate
		for(test_vec_i = 0;test_vec_i < ATOMIC_K/BN_ACT_PRL_N;test_vec_i = test_vec_i + 1)
		begin:test_vec_blk
			assign async_blk_gen_nxt_mask_test_vec[(test_vec_i+1)*BN_ACT_PRL_N-1:test_vec_i*BN_ACT_PRL_N] = 
				{BN_ACT_PRL_N{async_blk_gen_sel_onehot_cnt_nxt[test_vec_i]}};
		end
	endgenerate
	
	assign async_blk_gen_sel_onehot_cnt_nxt = 
		(async_blk_gen_sel_onehot_cnt << 1) | (async_blk_gen_sel_onehot_cnt >> (ATOMIC_K/BN_ACT_PRL_N-1));
	assign async_blk_gen_last_flag = 
		async_blk_gen_sel_onehot_cnt[ATOMIC_K/BN_ACT_PRL_N-1] | 
		(~(|(async_blk_gen_nxt_mask_test_vec & fnl_sfc_mask)));
	
	// 块选择计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
		begin
			async_blk_gen_sel_bin_cnt <= 0;
			async_blk_gen_sel_onehot_cnt <= 1;
		end
		else if(aclken & ((~en_bn_act_proc) | (s_axis_fnl_res_valid & bn_act_in_async_fifo_full_n)))
		begin
			async_blk_gen_sel_bin_cnt <= # SIM_DELAY 
				((~en_bn_act_proc) | async_blk_gen_last_flag) ? 
					0:
					(async_blk_gen_sel_bin_cnt + 1);
			async_blk_gen_sel_onehot_cnt <= # SIM_DELAY 
				((~en_bn_act_proc) | async_blk_gen_last_flag) ? 
					1:
					async_blk_gen_sel_onehot_cnt_nxt;
		end
	end
	
	/*
	跨时钟域:
		bn_act_in_async_fifo_u/async_fifo_u/rptr_gray_at_r[*] -> bn_act_in_async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]
		bn_act_in_async_fifo_u/async_fifo_u/wptr_gray_at_w[*] -> bn_act_in_async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]
		... -> bn_act_in_async_fifo_u/axis_reg_slice_u/axis_reg_slice_core_u/fwd_payload[*]
	*/
	async_fifo_with_ram #(
		.fwft_mode("true"),
		.ram_type("lutram"),
		.depth(32),
		.data_width(BN_ACT_PRL_N*32 + BN_ACT_PRL_N + 1 + 4 + 1 + 1),
		.simulation_delay(SIM_DELAY)
	)bn_act_in_async_fifo_u(
		.clk_wt(aclk),
		.rst_n_wt(aresetn),
		.clk_rd(bn_act_aclk),
		.rst_n_rd(bn_act_aresetn),
		
		.fifo_wen(bn_act_in_async_fifo_wen),
		.fifo_full(),
		.fifo_full_n(bn_act_in_async_fifo_full_n),
		.fifo_din({
			bn_act_in_async_fifo_din_data,
			bn_act_in_async_fifo_din_mask,
			bn_act_in_async_fifo_din_last_sub_row_flag,
			bn_act_in_async_fifo_din_sub_row_id,
			bn_act_in_async_fifo_din_last_data_blk_in_sfc,
			bn_act_in_async_fifo_din_last_data_blk
		}),
		.data_cnt_wt(),
		.fifo_ren(bn_act_in_async_fifo_ren),
		.fifo_empty(),
		.fifo_empty_n(bn_act_in_async_fifo_empty_n),
		.fifo_dout({
			bn_act_in_async_fifo_dout_data,
			bn_act_in_async_fifo_dout_mask,
			bn_act_in_async_fifo_dout_last_sub_row_flag,
			bn_act_in_async_fifo_dout_sub_row_id,
			bn_act_in_async_fifo_dout_last_data_blk_in_sfc,
			bn_act_in_async_fifo_dout_last_data_blk_in_row
		}),
		.data_cnt_rd()
	);
	
	/** 子表面行信息fifo **/
	wire sub_row_msg_fifo_wen;
	wire[15:0] sub_row_msg_fifo_din; // {输出通道号(16bit)}
	wire sub_row_msg_fifo_full_n;
	wire sub_row_msg_fifo_ren;
	wire[15:0] sub_row_msg_fifo_dout; // {输出通道号(16bit)}
	wire sub_row_msg_fifo_empty_n;
	
	assign s_sub_row_msg_axis_ready = 
		aclken & en_bn_act_proc & 
		((~use_bn_unit) | is_in_const_mac_mode | sub_row_msg_fifo_full_n);
	
	assign sub_row_msg_fifo_wen = 
		aclken & en_bn_act_proc & 
		use_bn_unit & (~is_in_const_mac_mode) & s_sub_row_msg_axis_valid;
	assign sub_row_msg_fifo_din = s_sub_row_msg_axis_data;
	
	generate
		if(BN_ACT_CLK_RATE == 1)
		begin
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
		end
		else
		begin
			/*
			跨时钟域:
				sub_row_msg_fifo_u/async_fifo_u/rptr_gray_at_r[*] -> sub_row_msg_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]
				sub_row_msg_fifo_u/async_fifo_u/wptr_gray_at_w[*] -> sub_row_msg_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]
				... -> sub_row_msg_fifo_u/axis_reg_slice_u/axis_reg_slice_core_u/fwd_payload[*]
			*/
			async_fifo_with_ram #(
				.fwft_mode("true"),
				.ram_type("lutram"),
				.depth(32),
				.data_width(16),
				.simulation_delay(SIM_DELAY)
			)sub_row_msg_fifo_u(
				.clk_wt(aclk),
				.rst_n_wt(aresetn),
				.clk_rd(bn_act_aclk),
				.rst_n_rd(bn_act_aresetn),
				
				.fifo_wen(sub_row_msg_fifo_wen),
				.fifo_full(),
				.fifo_full_n(sub_row_msg_fifo_full_n),
				.fifo_din(sub_row_msg_fifo_din),
				.data_cnt_wt(),
				.fifo_ren(sub_row_msg_fifo_ren),
				.fifo_empty(),
				.fifo_empty_n(sub_row_msg_fifo_empty_n),
				.fifo_dout(sub_row_msg_fifo_dout),
				.data_cnt_rd()
			);
		end
	endgenerate
	
	/** BN参数乒乓缓存 **/
	wire bn_param_buf_aclk;
	wire bn_param_buf_aresetn;
	wire bn_param_buf_aclken;
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
		bn_param_buf_aclken & en_bn_act_proc_sync & 
		(
			(~use_bn_unit) | is_in_const_mac_mode | 
			(bn_param_fetch_sts[BN_FTC_STS_READY_ONEHOT] & (~bn_param_buf_full))
		);
	
	assign bn_mem_clk_b = bn_param_buf_aclk;
	assign bn_mem_ren_b = bn_param_buf_aclken & bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT];
	assign bn_mem_addr_b = bn_param_fetch_cid;
	
	assign bn_param_buf_aclk = (BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk;
	assign bn_param_buf_aresetn = (BN_ACT_CLK_RATE == 1) ? aresetn:bn_act_aresetn;
	assign bn_param_buf_aclken = (BN_ACT_CLK_RATE == 1) ? aclken:bn_act_aclken;
	
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
				always @(posedge bn_param_buf_aclk)
				begin
					if(
						bn_param_buf_aclken & en_bn_act_proc_sync & 
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
	always @(posedge bn_param_buf_aclk or negedge bn_param_buf_aresetn)
	begin
		if(~bn_param_buf_aresetn)
			bn_param_buf_wptr <= 2'b00;
		else if(
			bn_param_buf_aclken & 
			((~en_bn_act_proc_sync) | (bn_param_buf_wen & (~bn_param_buf_full)))
		)
			bn_param_buf_wptr <= # SIM_DELAY 
				en_bn_act_proc_sync ? 
					(bn_param_buf_wptr + 1'b1):
					2'b00;
	end
	
	// BN参数缓存区读指针
	always @(posedge bn_param_buf_aclk or negedge bn_param_buf_aresetn)
	begin
		if(~bn_param_buf_aresetn)
			bn_param_buf_rptr <= 2'b00;
		else if(
			bn_param_buf_aclken & 
			((~en_bn_act_proc_sync) | (bn_param_buf_ren & (~bn_param_buf_empty)))
		)
			bn_param_buf_rptr <= # SIM_DELAY 
				en_bn_act_proc_sync ? 
					(bn_param_buf_rptr + 1'b1):
					2'b00;
	end
	
	// 获取BN参数(状态)
	always @(posedge bn_param_buf_aclk or negedge bn_param_buf_aresetn)
	begin
		if(~bn_param_buf_aresetn)
			bn_param_fetch_sts <= 1 << BN_FTC_STS_READY_ONEHOT;
		else if(
			bn_param_buf_aclken & 
			(
				(~en_bn_act_proc_sync) | 
				(
					bn_param_fetch_sts[BN_FTC_STS_READY_ONEHOT] & 
					use_bn_unit & (~is_in_const_mac_mode) & 
					sub_row_msg_fifo_empty_n & sub_row_msg_fifo_ren
				) | 
				(bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT] & (bn_param_fetch_data_id == (ATOMIC_K-1))) | 
				bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT]
			)
		)
			bn_param_fetch_sts <= # SIM_DELAY 
				en_bn_act_proc_sync ? 
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
	always @(posedge bn_param_buf_aclk)
	begin
		if(
			bn_param_buf_aclken & 
			en_bn_act_proc_sync & 
			(
				(
					bn_param_fetch_sts[BN_FTC_STS_READY_ONEHOT] & 
					use_bn_unit & (~is_in_const_mac_mode) & 
					sub_row_msg_fifo_empty_n & sub_row_msg_fifo_ren & 
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
	always @(posedge bn_param_buf_aclk)
	begin
		if(
			bn_param_buf_aclken & 
			(
				(~en_bn_act_proc_sync) | 
				bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT] | 
				bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT]
			)
		)
			bn_param_fetch_data_id <= # SIM_DELAY 
				((ATOMIC_K == 1) | (~en_bn_act_proc_sync) | bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT]) ? 
					0:
					(bn_param_fetch_data_id + 1'b1);
	end
	
	// 更新BN参数缓存区(标志)
	always @(posedge bn_param_buf_aclk or negedge bn_param_buf_aresetn)
	begin
		if(~bn_param_buf_aresetn)
			to_upd_bn_param_buf <= 1'b0;
		else if(
			bn_param_buf_aclken & 
			(
				(~en_bn_act_proc_sync) | 
				(
					to_upd_bn_param_buf ? 
						bn_param_fetch_sts[BN_FTC_STS_WAIT_ONEHOT]:
						bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT]
				)
			)
		)
			to_upd_bn_param_buf <= # SIM_DELAY 
				en_bn_act_proc_sync & (~to_upd_bn_param_buf);
	end
	
	// 待更新的数据号
	always @(posedge bn_param_buf_aclk)
	begin
		if(bn_param_buf_aclken & bn_param_fetch_sts[BN_FTC_STS_RD_MEM_ONEHOT])
			upd_bn_param_data_id <= # SIM_DELAY bn_param_fetch_data_id;
	end
	
	/** 批归一化处理 **/
	// [卷积最终结果表面选取]
	wire bn_act_data_blk_gen_aclk;
	wire bn_act_data_blk_gen_aresetn;
	wire bn_act_data_blk_gen_aclken;
	wire to_pass_fnl_sfc; // 放行最终结果表面(标志)
	wire fnl_sfc_in_vld; // 最终结果表面输入有效(指示)
	wire last_fnl_data_blk_in_tsf; // 本次传输里的最后1个最终结果数据块(标志)
	wire last_data_blk_in_row; // 本行的最后1个最终结果数据块(标志)
	reg[ATOMIC_K-1:0] optional_fnl_data_blk_mask; // 可选的最终结果数据块(掩码)
	reg[clogb2(MAX_PROC_ROUND_N-1):0] bn_proc_round_id; // BN处理轮次(计数器)
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] cur_sfc_data; // 当前的最终结果表面数据
	wire[BN_ACT_PRL_N-1:0] cur_sfc_mask; // 当前的最终结果表面有效掩码
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] cur_bn_param_a; // 当前的BN参数A
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] cur_bn_param_b; // 当前的BN参数B
	// [BN单元]
	wire bn_mac_aclk;
	wire bn_mac_aresetn;
	wire bn_mac_aclken;
	reg[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] cur_bn_param_a_d1;
	reg[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] cur_bn_param_b_d1;
	reg[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] cur_sfc_data_d1;
	reg[BN_ACT_PRL_N+1+5-1:0] cur_info_along_d1;
	reg[BN_ACT_PRL_N/BN_ACT_CLK_RATE-1:0] cur_bn_vld_d1;
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE-1:0] bn_mac_i_vld;
	wire[BN_ACT_PRL_N+1+5-1:0] bn_mac_i_info_along[0:BN_ACT_PRL_N/BN_ACT_CLK_RATE-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] bn_mac_o_res; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] bn_mac_o_info_along[0:BN_ACT_PRL_N/BN_ACT_CLK_RATE-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE-1:0] bn_mac_o_vld;
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] bn_mac_o_res_actual; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] bn_mac_o_info_along_actual[0:BN_ACT_PRL_N/BN_ACT_CLK_RATE-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE-1:0] bn_mac_o_vld_actual;
	
	assign s_axis_fnl_res_ready = 
		aclken & en_bn_act_proc & 
		(
			(BN_ACT_CLK_RATE == 1) ? 
				(
					to_pass_fnl_sfc & 
					((~use_bn_unit) | is_in_const_mac_mode | (~bn_param_buf_empty)) & 
					last_fnl_data_blk_in_tsf
				):
				(
					bn_act_in_async_fifo_full_n & 
					async_blk_gen_last_flag
				)
		);
	
	assign mul0_clk = (BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk;
	
	assign bn_act_in_async_fifo_ren = 
		(BN_ACT_CLK_RATE == 1) | 
		(
			bn_act_data_blk_gen_aclken & en_bn_act_proc_sync & 
			to_pass_fnl_sfc & 
			((~use_bn_unit) | is_in_const_mac_mode | (~bn_param_buf_empty)) & 
			(bn_act_in_round_cnt == (BN_ACT_CLK_RATE-1))
		);
	
	assign bn_param_buf_ren = 
		(~use_bn_unit) | is_in_const_mac_mode | 
		(
			(BN_ACT_CLK_RATE == 1) ? 
				(s_axis_fnl_res_valid & s_axis_fnl_res_ready & s_axis_fnl_res_last):
				(bn_act_in_async_fifo_empty_n & bn_act_in_async_fifo_ren & bn_act_in_async_fifo_dout_last_data_blk_in_row)
		);
	
	assign bn_act_data_blk_gen_aclk = (BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk;
	assign bn_act_data_blk_gen_aresetn = (BN_ACT_CLK_RATE == 1) ? aresetn:bn_act_aresetn;
	assign bn_act_data_blk_gen_aclken = (BN_ACT_CLK_RATE == 1) ? aclken:bn_act_aclken;
	
	assign bn_mac_aclk = (BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk;
	assign bn_mac_aresetn = (BN_ACT_CLK_RATE == 1) ? aresetn:bn_act_aresetn;
	assign bn_mac_aclken = (BN_ACT_CLK_RATE == 1) ? aclken:bn_act_aclken;
	
	assign fnl_sfc_in_vld = 
		en_bn_act_proc_sync & 
		to_pass_fnl_sfc & 
		((~use_bn_unit) | is_in_const_mac_mode | (~bn_param_buf_empty)) & 
		(
			(BN_ACT_CLK_RATE == 1) ? 
				s_axis_fnl_res_valid:
				bn_act_in_async_fifo_empty_n
		);
	assign last_fnl_data_blk_in_tsf = 
		(BN_ACT_CLK_RATE == 1) ? 
			(
				optional_fnl_data_blk_mask[ATOMIC_K-1] | 
				(~(|((optional_fnl_data_blk_mask << BN_ACT_PRL_N) & fnl_sfc_mask)))
			):
			(bn_act_in_async_fifo_dout_last_data_blk_in_sfc & (bn_act_in_round_cnt == (BN_ACT_CLK_RATE-1)));
	assign last_data_blk_in_row = 
		(BN_ACT_CLK_RATE == 1) ? 
			(last_fnl_data_blk_in_tsf & s_axis_fnl_res_last):
			bn_act_in_async_fifo_dout_last_data_blk_in_row;
	
	assign cur_sfc_data = 
		(BN_ACT_CLK_RATE == 1) ? 
			(s_axis_fnl_res_data >> (BN_ACT_PRL_N*32*bn_proc_round_id)):
			(bn_act_in_async_fifo_dout_data >> (BN_ACT_PRL_N/BN_ACT_CLK_RATE*32*bn_act_in_round_cnt));
	assign cur_sfc_mask = 
		(BN_ACT_CLK_RATE == 1) ? 
			(fnl_sfc_mask >> (BN_ACT_PRL_N*bn_proc_round_id)):
			bn_act_in_async_fifo_dout_mask;
	assign cur_bn_param_a = 
		is_in_const_mac_mode ? 
			{(BN_ACT_PRL_N/BN_ACT_CLK_RATE){param_a_in_const_mac_mode}}:
			(bn_param_buf_a[bn_param_buf_rptr[0]] >> (BN_ACT_PRL_N/BN_ACT_CLK_RATE*32*bn_proc_round_id));
	assign cur_bn_param_b = 
		is_in_const_mac_mode ? 
			{(BN_ACT_PRL_N/BN_ACT_CLK_RATE){param_b_in_const_mac_mode}}:
			(bn_param_buf_b[bn_param_buf_rptr[0]] >> (BN_ACT_PRL_N/BN_ACT_CLK_RATE*32*bn_proc_round_id));
	
	assign bn_mac_o_res_actual = 
		use_bn_unit ? 
			bn_mac_o_res:
			cur_sfc_data_d1;
	assign bn_mac_o_vld_actual = 
		use_bn_unit ? 
			bn_mac_o_vld:
			bn_mac_i_vld;
	
	// BN与激活输入轮次(计数器)
	always @(posedge bn_act_aclk or negedge bn_act_aresetn)
	begin
		if(~bn_act_aresetn)
			bn_act_in_round_cnt <= 0;
		else if(bn_act_aclken & ((~en_bn_act_proc_sync) | fnl_sfc_in_vld))
			bn_act_in_round_cnt <= # SIM_DELAY 
				((~en_bn_act_proc_sync) | (bn_act_in_round_cnt == (BN_ACT_CLK_RATE-1))) ? 
					0:
					(bn_act_in_round_cnt + 1);
	end
	
	// 可选的最终结果数据块(掩码)
	always @(posedge bn_act_data_blk_gen_aclk or negedge bn_act_data_blk_gen_aresetn)
	begin
		if(~bn_act_data_blk_gen_aresetn)
			optional_fnl_data_blk_mask <= (1 << BN_ACT_PRL_N) - 1;
		else if(
			bn_act_data_blk_gen_aclken & 
			((~en_bn_act_proc_sync) | fnl_sfc_in_vld)
		)
			optional_fnl_data_blk_mask <= # SIM_DELAY 
				en_bn_act_proc_sync ? 
					(
						last_fnl_data_blk_in_tsf ? 
							((1 << BN_ACT_PRL_N) - 1):
							(optional_fnl_data_blk_mask << BN_ACT_PRL_N)
					):
					((1 << BN_ACT_PRL_N) - 1);
	end
	
	// BN处理轮次(计数器)
	always @(posedge bn_act_data_blk_gen_aclk or negedge bn_act_data_blk_gen_aresetn)
	begin
		if(~bn_act_data_blk_gen_aresetn)
			bn_proc_round_id <= 0;
		else if(
			(MAX_PROC_ROUND_N > 1) & 
			bn_act_data_blk_gen_aclken & 
			((~en_bn_act_proc_sync) | fnl_sfc_in_vld)
		)
			bn_proc_round_id <= # SIM_DELAY 
				en_bn_act_proc_sync ? 
					(
						last_fnl_data_blk_in_tsf ? 
							0:
							(bn_proc_round_id + 1'b1)
					):
					0;
	end
	
	// 延迟1clk的BN输入
	always @(posedge bn_mac_aclk)
	begin
		if(bn_mac_aclken & fnl_sfc_in_vld)
		begin
			cur_bn_param_a_d1 <= # SIM_DELAY cur_bn_param_a;
			cur_bn_param_b_d1 <= # SIM_DELAY cur_bn_param_b;
			cur_sfc_data_d1 <= # SIM_DELAY cur_sfc_data;
			cur_info_along_d1 <= # SIM_DELAY 
				{
					// 是否最后1个子行(1bit)
					(BN_ACT_CLK_RATE == 1) ? 
						s_axis_fnl_res_user[4]:
						bn_act_in_async_fifo_dout_last_sub_row_flag,
					// 子行号(4bit)
					(BN_ACT_CLK_RATE == 1) ? 
						s_axis_fnl_res_user[3:0]:
						bn_act_in_async_fifo_dout_sub_row_id,
					cur_sfc_mask, // 数据有效掩码(BN_ACT_PRL_N bit)
					last_data_blk_in_row // 行内最后1个数据块标志(1bit)
				};
		end
	end
	
	genvar bn_cell_i;
	generate
		for(bn_cell_i = 0;bn_cell_i < BN_ACT_PRL_N;bn_cell_i = bn_cell_i + 1)
		begin:bn_mac_blk
			if(bn_cell_i < BN_ACT_PRL_N/BN_ACT_CLK_RATE)
			begin
				assign bn_mac_i_vld[bn_cell_i] = 
					cur_bn_vld_d1[bn_cell_i];
				assign bn_mac_i_info_along[bn_cell_i] = 
					(bn_cell_i == 0) ? 
						cur_info_along_d1:
						{(BN_ACT_PRL_N+1+5){1'bx}};
				
				assign bn_mac_o_info_along_actual[bn_cell_i] = 
					use_bn_unit ? 
						bn_mac_o_info_along[bn_cell_i]:
						bn_mac_i_info_along[bn_cell_i];
				
				always @(posedge bn_mac_aclk or negedge bn_mac_aresetn)
				begin
					if(~bn_mac_aresetn)
						cur_bn_vld_d1[bn_cell_i] <= 1'b0;
					else if(bn_mac_aclken)
						cur_bn_vld_d1[bn_cell_i] <= # SIM_DELAY 
							fnl_sfc_in_vld & 
							(
								((BN_ACT_CLK_RATE > 1) & (bn_cell_i == 0)) | 
								(|(
									cur_sfc_mask & 
									(1 << (BN_ACT_PRL_N/BN_ACT_CLK_RATE*bn_act_in_round_cnt*((BN_ACT_CLK_RATE == 1) ? 0:1) + bn_cell_i))
								))
							);
				end
				
				batch_nml_mac_cell #(
					.INT16_SUPPORTED(INT16_SUPPORTED),
					.INT32_SUPPORTED(INT32_SUPPORTED),
					.FP32_SUPPORTED(FP32_SUPPORTED),
					.INFO_ALONG_WIDTH(BN_ACT_PRL_N+1+5),
					.SIM_DELAY(SIM_DELAY)
				)batch_nml_mac_cell_u(
					.aclk(bn_mac_aclk),
					.aresetn(bn_mac_aresetn),
					.aclken(bn_mac_aclken),
					
					.bn_calfmt(calfmt),
					.fixed_point_quat_accrc(bn_fixed_point_quat_accrc),
					
					.mac_cell_i_op_a(cur_bn_param_a_d1[bn_cell_i*32+31:bn_cell_i*32]),
					.mac_cell_i_op_x(cur_sfc_data_d1[bn_cell_i*32+31:bn_cell_i*32]),
					.mac_cell_i_op_b(cur_bn_param_b_d1[bn_cell_i*32+31:bn_cell_i*32]),
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
			else
			begin
				assign mul0_op_a[MUL0_OP_WIDTH*(bn_cell_i+1)-1:MUL0_OP_WIDTH*bn_cell_i] = {MUL0_OP_WIDTH{1'bx}};
				assign mul0_op_b[MUL0_OP_WIDTH*(bn_cell_i+1)-1:MUL0_OP_WIDTH*bn_cell_i] = {MUL0_OP_WIDTH{1'bx}};
				assign mul0_ce[MUL0_CE_WIDTH*(bn_cell_i+1)-1:MUL0_CE_WIDTH*bn_cell_i] = {MUL0_CE_WIDTH{1'b0}};
			end
		end
	endgenerate
	
	/**
	激活处理
	
	支持Leaky Relu和Sigmoid
	**/
	// [Leaky Relu给出的结果]
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] act_leaky_relu_o_res; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] act_leaky_relu_o_info_along[0:BN_ACT_PRL_N/BN_ACT_CLK_RATE-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE-1:0] act_leaky_relu_o_vld;
	// [Sigmoid给出的结果]
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] act_sigmoid_o_res; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] act_sigmoid_o_info_along[0:BN_ACT_PRL_N/BN_ACT_CLK_RATE-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE-1:0] act_sigmoid_o_vld;
	// [实际选择的结果]
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0] act_grp_o_res_actual; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] act_grp_o_info_along_actual[0:BN_ACT_PRL_N/BN_ACT_CLK_RATE-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE-1:0] act_grp_o_vld_actual;
	
	assign sigmoid_lut_mem_clk_a = (BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk;
	assign mul1_clk = (BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk;
	
	assign act_grp_o_res_actual = 
		({(BN_ACT_PRL_N/BN_ACT_CLK_RATE*32){act_func_type == ACT_FUNC_TYPE_LEAKY_RELU}} & act_leaky_relu_o_res) | 
		({(BN_ACT_PRL_N/BN_ACT_CLK_RATE*32){act_func_type == ACT_FUNC_TYPE_SIGMOID}} & act_sigmoid_o_res) | 
		({(BN_ACT_PRL_N/BN_ACT_CLK_RATE*32){act_func_type == ACT_FUNC_TYPE_NONE}} & bn_mac_o_res_actual);
	assign act_grp_o_vld_actual = 
		({(BN_ACT_PRL_N/BN_ACT_CLK_RATE){act_func_type == ACT_FUNC_TYPE_LEAKY_RELU}} & act_leaky_relu_o_vld) | 
		({(BN_ACT_PRL_N/BN_ACT_CLK_RATE){act_func_type == ACT_FUNC_TYPE_SIGMOID}} & act_sigmoid_o_vld) | 
		({(BN_ACT_PRL_N/BN_ACT_CLK_RATE){act_func_type == ACT_FUNC_TYPE_NONE}} & bn_mac_o_vld_actual);
	
	genvar act_i;
	generate
		for(act_i = 0;act_i < BN_ACT_PRL_N;act_i = act_i + 1)
		begin:act_blk
			if(act_i < BN_ACT_PRL_N/BN_ACT_CLK_RATE)
			begin
				assign act_grp_o_info_along_actual[act_i] = 
					({(BN_ACT_PRL_N+1+5){act_func_type == ACT_FUNC_TYPE_LEAKY_RELU}} & act_leaky_relu_o_info_along[act_i]) | 
					({(BN_ACT_PRL_N+1+5){act_func_type == ACT_FUNC_TYPE_SIGMOID}} & act_sigmoid_o_info_along[act_i]) | 
					({(BN_ACT_PRL_N+1+5){act_func_type == ACT_FUNC_TYPE_NONE}} & bn_mac_o_info_along_actual[act_i]);
				
				leaky_relu_cell #(
					.INT16_SUPPORTED(INT16_SUPPORTED),
					.INT32_SUPPORTED(INT32_SUPPORTED),
					.FP32_SUPPORTED(FP32_SUPPORTED),
					.INFO_ALONG_WIDTH(BN_ACT_PRL_N+1+5),
					.SIM_DELAY(SIM_DELAY)
				)leaky_relu_cell_u(
					.aclk((BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk),
					.aresetn((BN_ACT_CLK_RATE == 1) ? aresetn:bn_act_aresetn),
					.aclken((BN_ACT_CLK_RATE == 1) ? aclken:bn_act_aclken),
					
					.act_calfmt(calfmt),
					.fixed_point_quat_accrc(leaky_relu_fixed_point_quat_accrc),
					.act_param_alpha(leaky_relu_param_alpha),
					
					.act_cell_i_op_x(bn_mac_o_res_actual[act_i*32+31:act_i*32]),
					.act_cell_i_pass(1'b0),
					.act_cell_i_info_along(bn_mac_o_info_along_actual[act_i]),
					.act_cell_i_vld(bn_mac_o_vld_actual[act_i] & (act_func_type == ACT_FUNC_TYPE_LEAKY_RELU)),
					
					.act_cell_o_res(act_leaky_relu_o_res[act_i*32+31:act_i*32]),
					.act_cell_o_info_along(act_leaky_relu_o_info_along[act_i]),
					.act_cell_o_vld(act_leaky_relu_o_vld[act_i]),
					
					.mul_op_a(mul1_op_a[MUL1_OP_WIDTH*(act_i+1)-1:MUL1_OP_WIDTH*act_i]),
					.mul_op_b(mul1_op_b[MUL1_OP_WIDTH*(act_i+1)-1:MUL1_OP_WIDTH*act_i]),
					.mul_ce(mul1_ce[MUL1_CE_WIDTH*(act_i+1)-1:MUL1_CE_WIDTH*act_i]),
					.mul_res(mul1_res[MUL1_RES_WIDTH*(act_i+1)-1:MUL1_RES_WIDTH*act_i])
				);
				
				sigmoid_cell #(
					.INT16_SUPPORTED(INT16_SUPPORTED),
					.INT32_SUPPORTED(INT32_SUPPORTED),
					.FP32_SUPPORTED(FP32_SUPPORTED),
					.INFO_ALONG_WIDTH(BN_ACT_PRL_N+1+5),
					.SIM_DELAY(SIM_DELAY)
				)sigmoid_cell_u(
					.aclk((BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk),
					.aresetn((BN_ACT_CLK_RATE == 1) ? aresetn:bn_act_aresetn),
					.aclken((BN_ACT_CLK_RATE == 1) ? aclken:bn_act_aclken),
					
					.act_calfmt(calfmt),
					.in_fixed_point_quat_accrc(sigmoid_fixed_point_quat_accrc),
					
					.act_cell_i_op_x(bn_mac_o_res_actual[act_i*32+31:act_i*32]),
					.act_cell_i_pass(1'b0),
					.act_cell_i_info_along(bn_mac_o_info_along_actual[act_i]),
					.act_cell_i_vld(bn_mac_o_vld_actual[act_i] & (act_func_type == ACT_FUNC_TYPE_SIGMOID)),
					
					.act_cell_o_res(act_sigmoid_o_res[act_i*32+31:act_i*32]),
					.act_cell_o_info_along(act_sigmoid_o_info_along[act_i]),
					.act_cell_o_vld(act_sigmoid_o_vld[act_i]),
					
					.lut_mem_clk_a(),
					.lut_mem_ren_a(sigmoid_lut_mem_ren_a[act_i]),
					.lut_mem_addr_a(sigmoid_lut_mem_addr_a[(act_i+1)*12-1:act_i*12]),
					.lut_mem_dout_a(sigmoid_lut_mem_dout_a[(act_i+1)*16-1:act_i*16])
				);
			end
			else
			begin
				assign mul1_op_a[MUL1_OP_WIDTH*(act_i+1)-1:MUL1_OP_WIDTH*act_i] = {MUL1_OP_WIDTH{1'bx}};
				assign mul1_op_b[MUL1_OP_WIDTH*(act_i+1)-1:MUL1_OP_WIDTH*act_i] = {MUL1_OP_WIDTH{1'bx}};
				assign mul1_ce[MUL1_CE_WIDTH*(act_i+1)-1:MUL1_CE_WIDTH*act_i] = {MUL1_CE_WIDTH{1'b0}};
				
				assign sigmoid_lut_mem_ren_a[act_i] = 1'b0;
				assign sigmoid_lut_mem_addr_a[(act_i+1)*12-1:act_i*12] = 12'dx;
			end
		end
	endgenerate
	
	/** 舍入处理 **/
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE*16-1:0] round_o_res; // 计算结果
	wire[BN_ACT_PRL_N+1+5-1:0] round_o_info_along[0:BN_ACT_PRL_N/BN_ACT_CLK_RATE-1]; // 随路数据({是否最后1个子行(1bit), 子行号(4bit), 数据有效掩码(BN_ACT_PRL_N bit), 行内最后1个数据块标志(1bit)})
	wire[BN_ACT_PRL_N/BN_ACT_CLK_RATE-1:0] round_o_vld;
	
	genvar round_i;
	generate
		for(round_i = 0;round_i < BN_ACT_PRL_N/BN_ACT_CLK_RATE;round_i = round_i + 1)
		begin:round_blk
			out_round_cell #(
				.USE_EXT_CE(1'b0),
				.INT8_SUPPORTED(INT16_SUPPORTED),
				.INT16_SUPPORTED(INT32_SUPPORTED),
				.FP16_SUPPORTED(FP32_SUPPORTED),
				.INFO_ALONG_WIDTH(BN_ACT_PRL_N+1+5),
				.SIM_DELAY(SIM_DELAY)
			)out_round_cell_u(
				.aclk((BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk),
				.aresetn((BN_ACT_CLK_RATE == 1) ? aresetn:bn_act_aresetn),
				.aclken((BN_ACT_CLK_RATE == 1) ? aclken:bn_act_aclken),
				
				.calfmt(calfmt),
				.fixed_point_quat_accrc(4'bxxxx), // 需要给出运行时参数!!!
				
				.s0_ce(1'b0),
				.s1_ce(1'b0),
				
				.round_i_op_x(act_grp_o_res_actual[round_i*32+31:round_i*32]),
				.round_i_info_along(act_grp_o_info_along_actual[round_i]),
				.round_i_vld(act_grp_o_vld_actual[round_i]),
				
				.round_o_res(round_o_res[round_i*16+15:round_i*16]),
				.round_o_info_along(round_o_info_along[round_i]),
				.round_o_vld(round_o_vld[round_i])
			);
		end
	endgenerate
	
	/**
	处理结果fifo
	
	负载数据 -> 
		{
			是否最后1个子行(1bit),
			子行号(4bit),
			计算结果(BN_ACT_PRL_N*(16或32) bit),
			数据有效掩码(BN_ACT_PRL_N bit),
			行内最后1个数据块标志(1bit)
		}
	**/
	// [BN与激活结果串并转换]
	reg[BN_ACT_CLK_RATE-1:0] bn_act_res_out_round_cnt; // BN与激活结果输出轮次(计数器)
	reg[(BN_ACT_PRL_N*(FP32_KEEP ? 32:16))-1:0] bn_act_res_saved; // 保存的BN与激活结果
	// [fifo写端口]
	wire proc_res_fifo_wen;
	wire[BN_ACT_PRL_N*(FP32_KEEP ? 32:16)-1:0] proc_res_fifo_din_res;
	wire[(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_din;
	wire proc_res_fifo_full_n;
	wire proc_res_fifo_almost_full_n;
	wire[9:0] proc_res_fifo_data_cnt_wt;
	// [fifo读端口]
	wire proc_res_async_fifo_ren;
	wire[(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5)-1:0] proc_res_async_fifo_dout;
	wire proc_res_async_fifo_empty;
	wire proc_res_fifo_ren;
	wire[(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_dout;
	wire proc_res_fifo_empty_n;
	
	assign m_axis_bn_act_res_data = 
		proc_res_fifo_dout[(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1)-1:BN_ACT_PRL_N+1];
	
	genvar m_axis_bn_act_res_mask_i;
	generate
		for(m_axis_bn_act_res_mask_i = 0;m_axis_bn_act_res_mask_i < BN_ACT_PRL_N;m_axis_bn_act_res_mask_i = m_axis_bn_act_res_mask_i + 1)
		begin:m_axis_bn_act_res_mask_blk
			assign m_axis_bn_act_res_keep[(m_axis_bn_act_res_mask_i+1)*(FP32_KEEP ? 4:2)-1:m_axis_bn_act_res_mask_i*(FP32_KEEP ? 4:2)] = 
				{(FP32_KEEP ? 4:2){proc_res_fifo_dout[m_axis_bn_act_res_mask_i+1]}};
		end
	endgenerate
	
	assign m_axis_bn_act_res_user = 
		proc_res_fifo_dout[(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5)-1:BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1];
	assign m_axis_bn_act_res_last = 
		proc_res_fifo_dout[0];
	assign m_axis_bn_act_res_valid = 
		aclken & proc_res_fifo_empty_n;
	
	assign proc_res_fifo_mem_clk_a = (BN_ACT_CLK_RATE == 1) ? aclk:bn_act_aclk;
	assign proc_res_fifo_mem_clk_b = aclk;
	
	assign to_pass_fnl_sfc = proc_res_fifo_almost_full_n;
	
	assign proc_res_fifo_wen = 
		((BN_ACT_CLK_RATE == 1) ? aclken:bn_act_aclken) & 
		(FP32_KEEP ? act_grp_o_vld_actual[0]:round_o_vld[0]) & 
		((BN_ACT_CLK_RATE == 1) | bn_act_res_out_round_cnt[BN_ACT_CLK_RATE-1]);
	assign proc_res_fifo_din_res = 
		FP32_KEEP ? 
			(
				(BN_ACT_CLK_RATE == 1) ? 
					act_grp_o_res_actual[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0]:
					{
						act_grp_o_res_actual[BN_ACT_PRL_N/BN_ACT_CLK_RATE*32-1:0],
						bn_act_res_saved[(BN_ACT_PRL_N/BN_ACT_CLK_RATE*((BN_ACT_CLK_RATE == 1) ? 1:(BN_ACT_CLK_RATE-1))*(FP32_KEEP ? 32:16))-1:0]
					}
			):
			(
				(BN_ACT_CLK_RATE == 1) ? 
					round_o_res[BN_ACT_PRL_N/BN_ACT_CLK_RATE*16-1:0]:
					{
						round_o_res[BN_ACT_PRL_N/BN_ACT_CLK_RATE*16-1:0],
						bn_act_res_saved[(BN_ACT_PRL_N/BN_ACT_CLK_RATE*((BN_ACT_CLK_RATE == 1) ? 1:(BN_ACT_CLK_RATE-1))*(FP32_KEEP ? 32:16))-1:0]
					}
			);
	assign proc_res_fifo_din = 
		FP32_KEEP ? 
			{
				act_grp_o_info_along_actual[0][(BN_ACT_PRL_N+1+5)-1], // 是否最后1个子行(1bit)
				act_grp_o_info_along_actual[0][(BN_ACT_PRL_N+1+4)-1:BN_ACT_PRL_N+1], // 子行号(4bit)
				proc_res_fifo_din_res[BN_ACT_PRL_N*32-1:0], // 计算结果(BN_ACT_PRL_N*32 bit)
				act_grp_o_info_along_actual[0][(BN_ACT_PRL_N+1)-1:1], // 数据有效掩码(BN_ACT_PRL_N bit)
				act_grp_o_info_along_actual[0][0] // 行内最后1个数据块标志(1bit)
			}:
			{
				round_o_info_along[0][(BN_ACT_PRL_N+1+5)-1], // 是否最后1个子行(1bit)
				round_o_info_along[0][(BN_ACT_PRL_N+1+4)-1:BN_ACT_PRL_N+1], // 子行号(4bit)
				proc_res_fifo_din_res[BN_ACT_PRL_N*16-1:0], // 计算结果(BN_ACT_PRL_N*16 bit)
				round_o_info_along[0][(BN_ACT_PRL_N+1)-1:1], // 数据有效掩码(BN_ACT_PRL_N bit)
				round_o_info_along[0][0] // 行内最后1个数据块标志(1bit)
			};
	
	assign proc_res_fifo_ren = aclken & m_axis_bn_act_res_ready;
	
	// BN与激活结果输出轮次(计数器)
	always @(posedge bn_act_aclk or negedge bn_act_aresetn)
	begin
		if(~bn_act_aresetn)
			bn_act_res_out_round_cnt <= 1;
		else if(bn_act_aclken & (FP32_KEEP ? act_grp_o_vld_actual[0]:round_o_vld[0]))
			bn_act_res_out_round_cnt <= # SIM_DELAY (bn_act_res_out_round_cnt << 1) | (bn_act_res_out_round_cnt >> (BN_ACT_PRL_N - 1));
	end
	
	// 保存的BN与激活结果
	genvar bn_act_res_saved_i;
	generate
		for(bn_act_res_saved_i = 0;bn_act_res_saved_i < BN_ACT_CLK_RATE;bn_act_res_saved_i = bn_act_res_saved_i + 1)
		begin:bn_act_res_saved_blk
			always @(posedge bn_act_aclk)
			begin
				if(bn_act_aclken & bn_act_res_out_round_cnt[bn_act_res_saved_i])
					bn_act_res_saved[
						BN_ACT_PRL_N/BN_ACT_CLK_RATE*(FP32_KEEP ? 32:16)*(bn_act_res_saved_i+1)-1:
						BN_ACT_PRL_N/BN_ACT_CLK_RATE*(FP32_KEEP ? 32:16)*bn_act_res_saved_i
					] <= # SIM_DELAY 
						FP32_KEEP ? 
							act_grp_o_res_actual:
							round_o_res;
			end
		end
	endgenerate
	
	generate
		if(BN_ACT_CLK_RATE == 1)
		begin
			fifo_based_on_ram #(
				.fwft_mode("true"),
				.ram_read_la(1),
				.fifo_depth(512),
				.fifo_data_width(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5),
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
		end
		else
		begin
			assign proc_res_fifo_almost_full_n = proc_res_fifo_data_cnt_wt < 10'd480;
			
			/*
			跨时钟域:
				proc_res_fifo_ctrler_u/rptr_gray_at_r[*] -> proc_res_fifo_ctrler_u/rptr_gray_at_w_p2[*]
				proc_res_fifo_ctrler_u/wptr_gray_at_w[*] -> proc_res_fifo_ctrler_u/wptr_gray_at_r_p2[*]
			*/
			async_fifo #(
				.depth(512),
				.data_width(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5),
				.simulation_delay(SIM_DELAY)
			)proc_res_fifo_ctrler_u(
				.clk_wt(bn_act_aclk),
				.rst_n_wt(bn_act_aresetn),
				.clk_rd(aclk),
				.rst_n_rd(aresetn),
				
				.ram_clk_w(),
				.ram_waddr(proc_res_fifo_mem_addr_a),
				.ram_wen(proc_res_fifo_mem_wen_a),
				.ram_din(proc_res_fifo_mem_din_a),
				.ram_clk_r(),
				.ram_ren(proc_res_fifo_mem_ren_b),
				.ram_raddr(proc_res_fifo_mem_addr_b),
				.ram_dout(proc_res_fifo_mem_dout_b),
				
				.fifo_wen(proc_res_fifo_wen),
				.fifo_full(),
				.fifo_full_n(proc_res_fifo_full_n),
				.fifo_din(proc_res_fifo_din),
				.data_cnt_wt(proc_res_fifo_data_cnt_wt),
				.fifo_ren(proc_res_async_fifo_ren),
				.fifo_empty(proc_res_async_fifo_empty),
				.fifo_empty_n(),
				.fifo_dout(proc_res_async_fifo_dout),
				.data_cnt_rd()
			);
			
			fifo_show_ahead_buffer #(
				.fifo_data_width(BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5),
				.simulation_delay(SIM_DELAY)
			)proc_res_fifo_show_ahead_buffer_u(
				.clk(aclk),
				.rst_n(aresetn),
				
				.std_fifo_ren(proc_res_async_fifo_ren),
				.std_fifo_dout(proc_res_async_fifo_dout),
				.std_fifo_empty(proc_res_async_fifo_empty),
				
				.fwft_fifo_ren(proc_res_fifo_ren),
				.fwft_fifo_dout(proc_res_fifo_dout),
				.fwft_fifo_empty(),
				.fwft_fifo_empty_n(proc_res_fifo_empty_n)
			);
		end
	endgenerate
	
endmodule
