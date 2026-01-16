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
本模块: (异步)逐元素操作处理核心

描述:
1.组成
输入异步fifo -> (并串转换) -> 逐元素操作处理流水线 -> (串并转换) -> 输出异步fifo

2.带有全局时钟使能

注意:
处理流水线条数(PROC_PIPELINE_N)必须能被功能单元的时钟倍率(FU_CLK_RATE)所整除

浮点运算未考虑INF和NAN

操作数A与操作数B不能同时为变量

当计算数据格式(cal_calfmt)为S16或S32时, 操作数B的定点数量化精度 = 操作数X的定点数量化精度(op_x_fixed_point_quat_accrc)

必须满足舍入单元输出定点数量化精度(round_out_fixed_point_quat_accrc) <= 舍入单元输入定点数量化精度(round_in_fixed_point_quat_accrc)
定点数舍入位数(fixed_point_rounding_digits) = 
	舍入单元输入定点数量化精度(round_in_fixed_point_quat_accrc) - 舍入单元输出定点数量化精度(round_out_fixed_point_quat_accrc)

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2026/01/14
********************************************************************/


module async_element_wise_proc #(
	// 处理核心全局配置
	parameter integer PROC_PIPELINE_N = 4, // 处理流水线条数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer FU_CLK_RATE = 2, // 功能单元的时钟倍率(1 | 2 | 4 | 8)
	// 输入数据转换单元配置
	parameter IN_DATA_CVT_EN_ROUND = 1'b1, // 是否需要进行四舍五入
	parameter IN_DATA_CVT_FP16_IN_DATA_SUPPORTED = 1'b0, // 是否支持FP16输入数据格式
	parameter IN_DATA_CVT_S33_IN_DATA_SUPPORTED = 1'b1, // 是否支持S33输入数据格式
	// 计算单元配置
	parameter CAL_EN_ROUND = 1'b0, // 是否需要进行四舍五入
	parameter CAL_INT16_SUPPORTED = 1'b0, // 是否支持INT16运算数据格式
	parameter CAL_INT32_SUPPORTED = 1'b0, // 是否支持INT32运算数据格式
	parameter CAL_FP32_SUPPORTED = 1'b1, // 是否支持FP32运算数据格式
	// 输出数据转换单元配置
	parameter OUT_DATA_CVT_EN_ROUND = 1'b1, // 是否需要进行四舍五入
	parameter OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED = 1'b1, // 是否支持S33输出数据格式
	// 舍入单元配置
	parameter ROUND_S33_ROUND_SUPPORTED = 1'b1, // 是否支持S33数据的舍入
	parameter ROUND_FP32_ROUND_SUPPORTED = 1'b1, // 是否支持FP32数据的舍入
	// 仿真配置
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	// 功能单元时钟和复位
	input wire fu_aclk,
	input wire fu_aresetn,
	input wire fu_aclken,
	
	// 使能信号
	input wire en_proc_core, // 使能处理核心
	
	// 执行单元旁路
	input wire in_data_cvt_unit_bypass, // 旁路输入数据转换单元
	input wire pow2_cell_bypass, // 旁路二次幂计算单元
	input wire mac_cell_bypass, // 旁路乘加计算单元
	input wire out_data_cvt_unit_bypass, // 旁路输出数据转换单元
	input wire round_cell_bypass, // 旁路舍入单元
	
	// 运行时参数
	input wire[2:0] in_data_fmt, // 输入数据格式
	input wire[1:0] cal_calfmt, // 计算数据格式
	input wire[2:0] out_data_fmt, // 输出数据格式
	input wire[5:0] in_fixed_point_quat_accrc, // 输入定点数量化精度
	input wire[4:0] op_x_fixed_point_quat_accrc, // 操作数X的定点数量化精度
	input wire[4:0] op_a_fixed_point_quat_accrc, // 操作数A的定点数量化精度
	input wire is_op_a_eq_1, // 操作数A的实际值恒为1(标志)
	input wire is_op_b_eq_0, // 操作数B的实际值恒为0(标志)
	input wire is_op_a_const, // 操作数A为常量(标志)
	input wire is_op_b_const, // 操作数B为常量(标志)
	input wire[31:0] op_a_const_val, // 操作数A的常量值
	input wire[31:0] op_b_const_val, // 操作数B的常量值
	input wire[5:0] s33_cvt_fixed_point_quat_accrc, // 转换为S33输出数据的定点数量化精度
	input wire[4:0] round_in_fixed_point_quat_accrc, // 舍入单元输入定点数量化精度
	input wire[4:0] round_out_fixed_point_quat_accrc, // 舍入单元输出定点数量化精度
	input wire[4:0] fixed_point_rounding_digits, // 定点数舍入位数
	
	// 逐元素操作处理输入流(AXIS从机)
	input wire[64*PROC_PIPELINE_N-1:0] s_axis_data, // 每组数据(64位) -> {操作数A或B(32位), 操作数X(32位)}
	input wire[8*PROC_PIPELINE_N-1:0] s_axis_keep,
	input wire s_axis_last,
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 逐元素操作结果输出流(AXIS主机)
	output wire[32*PROC_PIPELINE_N-1:0] m_axis_data,
	output wire[4*PROC_PIPELINE_N-1:0] m_axis_keep,
	output wire m_axis_last,
	output wire m_axis_valid,
	input wire m_axis_ready,
	
	// 外部有符号乘法器#0
	output wire mul0_clk,
	output wire[(PROC_PIPELINE_N/FU_CLK_RATE*((CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 32:16))-1:0] mul0_op_a, // 操作数A
	output wire[(PROC_PIPELINE_N/FU_CLK_RATE*((CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 32:16))-1:0] mul0_op_b, // 操作数B
	output wire[(PROC_PIPELINE_N/FU_CLK_RATE*3)-1:0] mul0_ce, // 计算使能
	input wire[(PROC_PIPELINE_N/FU_CLK_RATE*((CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 64:32))-1:0] mul0_res, // 计算结果
	
	// 外部有符号乘法器#1
	output wire mul1_clk,
	output wire[(PROC_PIPELINE_N/FU_CLK_RATE*(CAL_INT16_SUPPORTED ? 4*18:(CAL_INT32_SUPPORTED ? 32:25)))-1:0] mul1_op_a, // 操作数A
	output wire[(PROC_PIPELINE_N/FU_CLK_RATE*(CAL_INT16_SUPPORTED ? 4*18:(CAL_INT32_SUPPORTED ? 32:25)))-1:0] mul1_op_b, // 操作数B
	output wire[(PROC_PIPELINE_N/FU_CLK_RATE*(CAL_INT16_SUPPORTED ? 4:3))-1:0] mul1_ce, // 计算使能
	input wire[(PROC_PIPELINE_N/FU_CLK_RATE*(CAL_INT16_SUPPORTED ? 4*36:(CAL_INT32_SUPPORTED ? 64:50)))-1:0] mul1_res // 计算结果
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
	// 外部有符号乘法器的位宽
	localparam integer MUL0_OP_WIDTH = (CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 32:16;
	localparam integer MUL1_OP_WIDTH = CAL_INT16_SUPPORTED ? 4*18:(CAL_INT32_SUPPORTED ? 32:25);
	localparam integer MUL0_CE_WIDTH = 3;
	localparam integer MUL1_CE_WIDTH = CAL_INT16_SUPPORTED ? 4:3;
	localparam integer MUL0_RES_WIDTH = (CAL_INT32_SUPPORTED | CAL_FP32_SUPPORTED) ? 64:32;
	localparam integer MUL1_RES_WIDTH = CAL_INT16_SUPPORTED ? 4*36:(CAL_INT32_SUPPORTED ? 64:50);
	
	/** 使能信号与运行时参数同步 **/
	// 使能处理核心
	reg[4:1] en_proc_core_r;
	wire en_proc_core_sync;
	wire en_proc_core_sync_d1;
	wire on_en_proc_core_posedge;
	// 执行单元旁路
	reg in_data_cvt_unit_bypass_sync; // 旁路输入数据转换单元
	reg pow2_cell_bypass_sync; // 旁路二次幂计算单元
	reg mac_cell_bypass_sync; // 旁路乘加计算单元
	reg out_data_cvt_unit_bypass_sync; // 旁路输出数据转换单元
	reg round_cell_bypass_sync; // 旁路舍入单元
	// 运行时参数
	reg[2:0] in_data_fmt_sync; // 输入数据格式
	reg[1:0] cal_calfmt_sync; // 计算数据格式
	reg[2:0] out_data_fmt_sync; // 输出数据格式
	reg[5:0] in_fixed_point_quat_accrc_sync; // 输入定点数量化精度
	reg[4:0] op_x_fixed_point_quat_accrc_sync; // 操作数X的定点数量化精度
	reg[4:0] op_a_fixed_point_quat_accrc_sync; // 操作数A的定点数量化精度
	reg is_op_a_eq_1_sync; // 操作数A的实际值恒为1(标志)
	reg is_op_b_eq_0_sync; // 操作数B的实际值恒为0(标志)
	reg is_op_a_const_sync; // 操作数A为常量(标志)
	reg is_op_b_const_sync; // 操作数B为常量(标志)
	reg[31:0] op_a_const_val_sync; // 操作数A的常量值
	reg[31:0] op_b_const_val_sync; // 操作数B的常量值
	reg[5:0] s33_cvt_fixed_point_quat_accrc_sync; // 转换为S33输出数据的定点数量化精度
	reg[4:0] round_in_fixed_point_quat_accrc_sync; // 舍入单元输入定点数量化精度
	reg[4:0] round_out_fixed_point_quat_accrc_sync; // 舍入单元输出定点数量化精度
	reg[4:0] fixed_point_rounding_digits_sync; // 定点数舍入位数
	
	assign en_proc_core_sync = en_proc_core_r[3];
	assign en_proc_core_sync_d1 = en_proc_core_r[4];
	assign on_en_proc_core_posedge = en_proc_core_sync & (~en_proc_core_sync_d1);
	
	// 跨时钟域: ... -> en_proc_core_r[1]
	always @(posedge fu_aclk or negedge fu_aresetn)
	begin
		if(~fu_aresetn)
			en_proc_core_r <= 4'b0000;
		else if(fu_aclken)
			en_proc_core_r <= # SIM_DELAY 
				{en_proc_core_r[3:1], en_proc_core};
	end
	
	/*
	跨时钟域:
		... -> in_data_cvt_unit_bypass_sync
		... -> pow2_cell_bypass_sync
		... -> mac_cell_bypass_sync
		... -> out_data_cvt_unit_bypass_sync
		... -> round_cell_bypass_sync
		
		... -> in_data_fmt_sync[*]
		... -> cal_calfmt_sync[*]
		... -> out_data_fmt_sync[*]
		... -> in_fixed_point_quat_accrc_sync[*]
		... -> op_x_fixed_point_quat_accrc_sync[*]
		... -> op_a_fixed_point_quat_accrc_sync[*]
		... -> is_op_a_eq_1_sync
		... -> is_op_b_eq_0_sync
		... -> is_op_a_const_sync
		... -> is_op_b_const_sync
		... -> op_a_const_val_sync[*]
		... -> op_b_const_val_sync[*]
		... -> s33_cvt_fixed_point_quat_accrc_sync[*]
		... -> round_in_fixed_point_quat_accrc_sync[*]
		... -> round_out_fixed_point_quat_accrc_sync[*]
		... -> fixed_point_rounding_digits_sync[*]
	*/
	always @(posedge fu_aclk)
	begin
		if(fu_aclken & on_en_proc_core_posedge)
		begin
			in_data_cvt_unit_bypass_sync <= # SIM_DELAY in_data_cvt_unit_bypass;
			pow2_cell_bypass_sync <= # SIM_DELAY pow2_cell_bypass;
			mac_cell_bypass_sync <= # SIM_DELAY mac_cell_bypass;
			out_data_cvt_unit_bypass_sync <= # SIM_DELAY out_data_cvt_unit_bypass;
			round_cell_bypass_sync <= # SIM_DELAY round_cell_bypass;
			
			in_data_fmt_sync <= # SIM_DELAY in_data_fmt;
			cal_calfmt_sync <= # SIM_DELAY cal_calfmt;
			out_data_fmt_sync <= # SIM_DELAY out_data_fmt;
			in_fixed_point_quat_accrc_sync <= # SIM_DELAY in_fixed_point_quat_accrc;
			op_x_fixed_point_quat_accrc_sync <= # SIM_DELAY op_x_fixed_point_quat_accrc;
			op_a_fixed_point_quat_accrc_sync <= # SIM_DELAY op_a_fixed_point_quat_accrc;
			is_op_a_eq_1_sync <= # SIM_DELAY is_op_a_eq_1;
			is_op_b_eq_0_sync <= # SIM_DELAY is_op_b_eq_0;
			is_op_a_const_sync <= # SIM_DELAY is_op_a_const;
			is_op_b_const_sync <= # SIM_DELAY is_op_b_const;
			op_a_const_val_sync <= # SIM_DELAY op_a_const_val;
			op_b_const_val_sync <= # SIM_DELAY op_b_const_val;
			s33_cvt_fixed_point_quat_accrc_sync <= # SIM_DELAY s33_cvt_fixed_point_quat_accrc;
			round_in_fixed_point_quat_accrc_sync <= # SIM_DELAY round_in_fixed_point_quat_accrc;
			round_out_fixed_point_quat_accrc_sync <= # SIM_DELAY round_out_fixed_point_quat_accrc;
			fixed_point_rounding_digits_sync <= # SIM_DELAY fixed_point_rounding_digits;
		end
	end
	
	/** 输入异步fifo **/
	// fifo写端口
	wire in_async_fifo_wen;
	wire in_async_fifo_full_n;
	wire[64*PROC_PIPELINE_N-1:0] in_async_fifo_din_op; // 每组数据(64位) -> {操作数A或B(32位), 操作数X(32位)}
	wire in_async_fifo_din_last_flag;
	wire[PROC_PIPELINE_N-1:0] in_async_fifo_din_item_mask;
	// fifo读端口
	wire in_async_fifo_ren;
	wire in_async_fifo_empty_n;
	wire[64*PROC_PIPELINE_N-1:0] in_async_fifo_dout_op; // 每组数据(64位) -> {操作数A或B(32位), 操作数X(32位)}
	wire in_async_fifo_dout_last_flag;
	wire[PROC_PIPELINE_N-1:0] in_async_fifo_dout_item_mask;
	
	assign s_axis_ready = aclken & en_proc_core_sync_d1 & in_async_fifo_full_n;
	
	assign in_async_fifo_wen = aclken & en_proc_core_sync_d1 & s_axis_valid;
	assign in_async_fifo_din_op = s_axis_data;
	assign in_async_fifo_din_last_flag = s_axis_last;
	
	/*
	跨时钟域:
		in_async_fifo_u/async_fifo_u/rptr_gray_at_r[*] -> in_async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]
		in_async_fifo_u/async_fifo_u/wptr_gray_at_w[*] -> in_async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]
		... -> in_async_fifo_u/axis_reg_slice_u/axis_reg_slice_core_u/fwd_payload[*]
	*/
	async_fifo_with_ram #(
		.fwft_mode("true"),
		.ram_type("lutram"),
		.depth(32),
		.data_width(64*PROC_PIPELINE_N + 1 + PROC_PIPELINE_N),
		.simulation_delay(SIM_DELAY)
	)in_async_fifo_u(
		.clk_wt(aclk),
		.rst_n_wt(aresetn),
		.clk_rd(fu_aclk),
		.rst_n_rd(fu_aresetn),
		
		.fifo_wen(in_async_fifo_wen),
		.fifo_full(),
		.fifo_full_n(in_async_fifo_full_n),
		.fifo_din({in_async_fifo_din_op, in_async_fifo_din_last_flag, in_async_fifo_din_item_mask}),
		.data_cnt_wt(),
		.fifo_ren(in_async_fifo_ren),
		.fifo_empty(),
		.fifo_empty_n(in_async_fifo_empty_n),
		.fifo_dout({in_async_fifo_dout_op, in_async_fifo_dout_last_flag, in_async_fifo_dout_item_mask}),
		.data_cnt_rd()
	);
	
	/** 输入并串转换 **/
	wire proc_pipeline_in_permitted_flag; // 许可输入(标志)
	reg[clogb2(FU_CLK_RATE-1):0] proc_pipeline_in_sel_cnt; // 输入选择计数器
	reg[64*PROC_PIPELINE_N/FU_CLK_RATE-1:0] proc_pipeline_in_op_cur; // 当前输入到处理流水线的操作数
	reg[PROC_PIPELINE_N/FU_CLK_RATE-1:0] proc_pipeline_in_item_mask_cur; // 当前输入到处理流水线的项掩码
	reg proc_pipeline_in_last_flag_cur; // 当前输入到处理流水线的last标志
	reg proc_pipeline_in_vld; // 处理流水线输入有效(标志)
	
	assign in_async_fifo_ren = 
		fu_aclken & proc_pipeline_in_permitted_flag & (proc_pipeline_in_sel_cnt == (FU_CLK_RATE-1));
	
	// 输入选择计数器
	always @(posedge fu_aclk or negedge fu_aresetn)
	begin
		if(~fu_aresetn)
			proc_pipeline_in_sel_cnt <= 0;
		else if(fu_aclken & in_async_fifo_empty_n & proc_pipeline_in_permitted_flag)
			proc_pipeline_in_sel_cnt <= # SIM_DELAY 
				(proc_pipeline_in_sel_cnt == (FU_CLK_RATE-1)) ? 
					0:
					(proc_pipeline_in_sel_cnt + 1);
	end
	
	// 当前输入到处理流水线的操作数, 当前输入到处理流水线的项掩码, 当前输入到处理流水线的last标志
	always @(posedge fu_aclk)
	begin
		if(fu_aclken & in_async_fifo_empty_n & proc_pipeline_in_permitted_flag)
		begin
			proc_pipeline_in_op_cur <= # SIM_DELAY 
				in_async_fifo_dout_op >> (64*PROC_PIPELINE_N/FU_CLK_RATE * proc_pipeline_in_sel_cnt);
			proc_pipeline_in_item_mask_cur <= # SIM_DELAY 
				in_async_fifo_dout_item_mask >> (PROC_PIPELINE_N/FU_CLK_RATE * proc_pipeline_in_sel_cnt);
			proc_pipeline_in_last_flag_cur <= # SIM_DELAY 
				in_async_fifo_dout_last_flag;
		end
	end
	
	// 处理流水线输入有效(标志)
	always @(posedge fu_aclk or negedge fu_aresetn)
	begin
		if(~fu_aresetn)
			proc_pipeline_in_vld <= 1'b0;
		else if(fu_aclken)
			proc_pipeline_in_vld <= # SIM_DELAY 
				in_async_fifo_empty_n & proc_pipeline_in_permitted_flag;
	end
	
	/** 逐元素操作处理流水线 **/
	// 处理流水线输入
	wire[31:0] proc_pipeline_i_op_x[0:PROC_PIPELINE_N/FU_CLK_RATE-1]; // 操作数X
	wire[31:0] proc_pipeline_i_op_a[0:PROC_PIPELINE_N/FU_CLK_RATE-1]; // 操作数A
	wire[31:0] proc_pipeline_i_op_b[0:PROC_PIPELINE_N/FU_CLK_RATE-1]; // 操作数B
	wire[PROC_PIPELINE_N/FU_CLK_RATE+1-1:0] proc_pipeline_i_info_along[0:PROC_PIPELINE_N/FU_CLK_RATE-1]; // 随路数据
	wire[PROC_PIPELINE_N/FU_CLK_RATE-1:0] proc_pipeline_i_vld;
	// 处理流水线输出
	wire[32*PROC_PIPELINE_N/FU_CLK_RATE-1:0] proc_pipeline_o_res; // 结果
	wire[PROC_PIPELINE_N/FU_CLK_RATE+1-1:0] proc_pipeline_o_info_along[0:PROC_PIPELINE_N/FU_CLK_RATE-1]; // 随路数据
	wire[PROC_PIPELINE_N/FU_CLK_RATE-1:0] proc_pipeline_o_vld;
	
	assign mul0_clk = fu_aclk;
	assign mul1_clk = fu_aclk;
	
	genvar proc_pipeline_id;
	generate
		for(proc_pipeline_id = 0;proc_pipeline_id < PROC_PIPELINE_N/FU_CLK_RATE;proc_pipeline_id = proc_pipeline_id + 1)
		begin:proc_pipeline_blk
			assign proc_pipeline_i_op_x[proc_pipeline_id] = proc_pipeline_in_op_cur[64*proc_pipeline_id+31:64*proc_pipeline_id];
			assign proc_pipeline_i_op_a[proc_pipeline_id] = proc_pipeline_in_op_cur[64*proc_pipeline_id+63:64*proc_pipeline_id+32];
			assign proc_pipeline_i_op_b[proc_pipeline_id] = proc_pipeline_in_op_cur[64*proc_pipeline_id+63:64*proc_pipeline_id+32];
			
			assign proc_pipeline_i_info_along[proc_pipeline_id] = 
				{
					proc_pipeline_in_item_mask_cur,
					proc_pipeline_in_last_flag_cur
				};
			
			assign proc_pipeline_i_vld[proc_pipeline_id] = 
				proc_pipeline_in_vld & proc_pipeline_in_item_mask_cur[proc_pipeline_id];
			
			element_wise_proc_pipeline #(
				.INFO_ALONG_WIDTH(PROC_PIPELINE_N/FU_CLK_RATE+1),
				.IN_DATA_CVT_EN_ROUND(IN_DATA_CVT_EN_ROUND),
				.IN_DATA_CVT_FP16_IN_DATA_SUPPORTED(IN_DATA_CVT_FP16_IN_DATA_SUPPORTED),
				.IN_DATA_CVT_S33_IN_DATA_SUPPORTED(IN_DATA_CVT_S33_IN_DATA_SUPPORTED),
				.CAL_EN_ROUND(CAL_EN_ROUND),
				.CAL_INT16_SUPPORTED(CAL_INT16_SUPPORTED),
				.CAL_INT32_SUPPORTED(CAL_INT32_SUPPORTED),
				.CAL_FP32_SUPPORTED(CAL_FP32_SUPPORTED),
				.OUT_DATA_CVT_EN_ROUND(OUT_DATA_CVT_EN_ROUND),
				.OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED(OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED),
				.ROUND_S33_ROUND_SUPPORTED(ROUND_S33_ROUND_SUPPORTED),
				.ROUND_FP32_ROUND_SUPPORTED(ROUND_FP32_ROUND_SUPPORTED),
				.SIM_DELAY(SIM_DELAY)
			)proc_pipeline_u(
				.aclk(fu_aclk),
				.aresetn(fu_aresetn),
				.aclken(fu_aclken),
				
				.in_data_cvt_unit_bypass(in_data_cvt_unit_bypass_sync),
				.pow2_cell_bypass(pow2_cell_bypass_sync),
				.mac_cell_bypass(mac_cell_bypass_sync),
				.out_data_cvt_unit_bypass(out_data_cvt_unit_bypass_sync),
				.round_cell_bypass(round_cell_bypass_sync),
				
				.in_data_fmt(in_data_fmt_sync),
				.cal_calfmt(cal_calfmt_sync),
				.out_data_fmt(out_data_fmt_sync),
				.in_fixed_point_quat_accrc(in_fixed_point_quat_accrc_sync),
				.op_x_fixed_point_quat_accrc(op_x_fixed_point_quat_accrc_sync),
				.op_a_fixed_point_quat_accrc(op_a_fixed_point_quat_accrc_sync),
				.is_op_a_eq_1(is_op_a_eq_1_sync),
				.is_op_b_eq_0(is_op_b_eq_0_sync),
				.is_op_a_const(is_op_a_const_sync),
				.is_op_b_const(is_op_b_const_sync),
				.op_a_const_val(op_a_const_val_sync),
				.op_b_const_val(op_b_const_val_sync),
				.s33_cvt_fixed_point_quat_accrc(s33_cvt_fixed_point_quat_accrc_sync),
				.round_in_fixed_point_quat_accrc(round_in_fixed_point_quat_accrc_sync),
				.round_out_fixed_point_quat_accrc(round_out_fixed_point_quat_accrc_sync),
				.fixed_point_rounding_digits(fixed_point_rounding_digits_sync),
				
				.proc_i_op_x(proc_pipeline_i_op_x[proc_pipeline_id]),
				.proc_i_op_a(proc_pipeline_i_op_a[proc_pipeline_id]),
				.proc_i_op_b(proc_pipeline_i_op_b[proc_pipeline_id]),
				.proc_i_info_along(proc_pipeline_i_info_along[proc_pipeline_id]),
				.proc_i_vld(proc_pipeline_i_vld[proc_pipeline_id]),
				
				.proc_o_res(proc_pipeline_o_res[(proc_pipeline_id+1)*32-1:proc_pipeline_id*32]),
				.proc_o_info_along(proc_pipeline_o_info_along[proc_pipeline_id]),
				.proc_o_vld(proc_pipeline_o_vld[proc_pipeline_id]),
				
				.mul0_clk(),
				.mul0_op_a(mul0_op_a[MUL0_OP_WIDTH*(proc_pipeline_id+1)-1:MUL0_OP_WIDTH*proc_pipeline_id]),
				.mul0_op_b(mul0_op_b[MUL0_OP_WIDTH*(proc_pipeline_id+1)-1:MUL0_OP_WIDTH*proc_pipeline_id]),
				.mul0_ce(mul0_ce[MUL0_CE_WIDTH*(proc_pipeline_id+1)-1:MUL0_CE_WIDTH*proc_pipeline_id]),
				.mul0_res(mul0_res[MUL0_RES_WIDTH*(proc_pipeline_id+1)-1:MUL0_RES_WIDTH*proc_pipeline_id]),
				
				.mul1_clk(),
				.mul1_op_a(mul1_op_a[MUL1_OP_WIDTH*(proc_pipeline_id+1)-1:MUL1_OP_WIDTH*proc_pipeline_id]),
				.mul1_op_b(mul1_op_b[MUL1_OP_WIDTH*(proc_pipeline_id+1)-1:MUL1_OP_WIDTH*proc_pipeline_id]),
				.mul1_ce(mul1_ce[MUL1_CE_WIDTH*(proc_pipeline_id+1)-1:MUL1_CE_WIDTH*proc_pipeline_id]),
				.mul1_res(mul1_res[MUL1_RES_WIDTH*(proc_pipeline_id+1)-1:MUL1_RES_WIDTH*proc_pipeline_id])
			);
		end
	endgenerate
	
	/** 输出串并转换 **/
	reg[FU_CLK_RATE-1:0] proc_pipeline_out_prl_cnt; // 输出并行化计数器
	reg[32*PROC_PIPELINE_N-1:0] proc_pipeline_out_res_saved; // 保存的结果
	reg[PROC_PIPELINE_N-1:0] proc_pipeline_out_item_mask_saved; // 保存的项掩码
	wire[32*PROC_PIPELINE_N-1:0] proc_pipeline_out_res_cur; // 当前处理流水线输出的结果
	wire[PROC_PIPELINE_N-1:0] proc_pipeline_out_item_mask_cur; // 当前处理流水线输出的项掩码
	wire proc_pipeline_out_last_flag_cur; // 当前处理流水线输出的last标志
	wire proc_pipeline_out_vld; // 流水线输出有效(标志)
	
	assign proc_pipeline_out_res_cur = 
		(proc_pipeline_out_res_saved & ((1 << (32*PROC_PIPELINE_N/FU_CLK_RATE*(FU_CLK_RATE-1))) - 1)) | 
		((proc_pipeline_o_res | {(32*PROC_PIPELINE_N){1'b0}}) << (32*PROC_PIPELINE_N/FU_CLK_RATE*(FU_CLK_RATE-1)));
	assign proc_pipeline_out_item_mask_cur = 
		(proc_pipeline_out_item_mask_saved & ((1 << (PROC_PIPELINE_N/FU_CLK_RATE*(FU_CLK_RATE-1))) - 1)) | 
		(
			(proc_pipeline_o_info_along[0][PROC_PIPELINE_N/FU_CLK_RATE+1-1:1] | {PROC_PIPELINE_N{1'b0}}) << 
			(PROC_PIPELINE_N/FU_CLK_RATE*(FU_CLK_RATE-1))
		);
	assign proc_pipeline_out_last_flag_cur = proc_pipeline_o_info_along[0][0];
	assign proc_pipeline_out_vld = proc_pipeline_o_vld[0] & proc_pipeline_out_prl_cnt[FU_CLK_RATE-1];
	
	// 输出并行化计数器
	always @(posedge fu_aclk or negedge fu_aresetn)
	begin
		if(~fu_aresetn)
			proc_pipeline_out_prl_cnt <= 1;
		else if(fu_aclken & proc_pipeline_o_vld[0])
			proc_pipeline_out_prl_cnt <= # SIM_DELAY 
				// 循环左移1位
				(proc_pipeline_out_prl_cnt << 1) | (proc_pipeline_out_prl_cnt >> (FU_CLK_RATE-1));
	end
	
	genvar out_ser_to_prl_i;
	generate
		for(out_ser_to_prl_i = 0;out_ser_to_prl_i < FU_CLK_RATE;out_ser_to_prl_i = out_ser_to_prl_i + 1)
		begin:out_ser_to_prl_blk
			always @(posedge fu_aclk)
			begin
				if(fu_aclken & proc_pipeline_o_vld[0] & proc_pipeline_out_prl_cnt[out_ser_to_prl_i])
				begin
					proc_pipeline_out_res_saved[
						(32*PROC_PIPELINE_N/FU_CLK_RATE)*(out_ser_to_prl_i+1)-1:
						(32*PROC_PIPELINE_N/FU_CLK_RATE)*out_ser_to_prl_i
					] <= # SIM_DELAY 
						proc_pipeline_o_res;
					
					proc_pipeline_out_item_mask_saved[
						(PROC_PIPELINE_N/FU_CLK_RATE)*(out_ser_to_prl_i+1)-1:
						(PROC_PIPELINE_N/FU_CLK_RATE)*out_ser_to_prl_i
					] <= # SIM_DELAY 
						proc_pipeline_o_info_along[0][PROC_PIPELINE_N/FU_CLK_RATE+1-1:1];
				end
			end
		end
	endgenerate
	
	/** 输出异步fifo **/
	// fifo写端口
	wire out_async_fifo_wen;
	wire[32*PROC_PIPELINE_N-1:0] out_async_fifo_din_res;
	wire[PROC_PIPELINE_N-1:0] out_async_fifo_din_item_mask;
	wire out_async_fifo_din_last_flag;
	wire[6:0] out_async_fifo_data_cnt_wt;
	// fifo读端口
	wire out_async_fifo_ren;
	wire out_async_fifo_empty_n;
	wire[32*PROC_PIPELINE_N-1:0] out_async_fifo_dout_res;
	wire[PROC_PIPELINE_N-1:0] out_async_fifo_dout_item_mask;
	wire out_async_fifo_dout_last_flag;
	
	assign m_axis_data = out_async_fifo_dout_res;
	assign m_axis_last = out_async_fifo_dout_last_flag;
	assign m_axis_valid = aclken & out_async_fifo_empty_n;
	
	genvar item_mask_i;
	generate
		for(item_mask_i = 0;item_mask_i < PROC_PIPELINE_N;item_mask_i = item_mask_i + 1)
		begin:item_mask_blk
			assign m_axis_keep[4*(item_mask_i+1)-1:4*item_mask_i] = {4{out_async_fifo_dout_item_mask[item_mask_i]}};
			
			assign in_async_fifo_din_item_mask[item_mask_i] = s_axis_keep[8*item_mask_i];
		end
	endgenerate
	
	assign proc_pipeline_in_permitted_flag = out_async_fifo_data_cnt_wt < 7'd32;
	
	assign out_async_fifo_wen = fu_aclken & proc_pipeline_out_vld;
	assign out_async_fifo_din_res = proc_pipeline_out_res_cur;
	assign out_async_fifo_din_item_mask = proc_pipeline_out_item_mask_cur;
	assign out_async_fifo_din_last_flag = proc_pipeline_out_last_flag_cur;
	
	assign out_async_fifo_ren = aclken & m_axis_ready;
	
	/*
	跨时钟域:
		out_async_fifo_u/async_fifo_u/rptr_gray_at_r[*] -> out_async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]
		out_async_fifo_u/async_fifo_u/wptr_gray_at_w[*] -> out_async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]
		... -> out_async_fifo_u/axis_reg_slice_u/axis_reg_slice_core_u/fwd_payload[*]
	*/
	async_fifo_with_ram #(
		.fwft_mode("true"),
		.ram_type("lutram"),
		.depth(64),
		.data_width(32*PROC_PIPELINE_N + 1 + PROC_PIPELINE_N),
		.simulation_delay(SIM_DELAY)
	)out_async_fifo_u(
		.clk_wt(fu_aclk),
		.rst_n_wt(fu_aresetn),
		.clk_rd(aclk),
		.rst_n_rd(aresetn),
		
		.fifo_wen(out_async_fifo_wen),
		.fifo_full(),
		.fifo_full_n(),
		.fifo_din({out_async_fifo_din_res, out_async_fifo_din_last_flag, out_async_fifo_din_item_mask}),
		.data_cnt_wt(out_async_fifo_data_cnt_wt),
		.fifo_ren(out_async_fifo_ren),
		.fifo_empty(),
		.fifo_empty_n(out_async_fifo_empty_n),
		.fifo_dout({out_async_fifo_dout_res, out_async_fifo_dout_last_flag, out_async_fifo_dout_item_mask}),
		.data_cnt_rd()
	);
	
endmodule
