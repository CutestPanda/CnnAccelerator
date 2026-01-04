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
本模块: 通用卷积单元计算子系统

描述:
包括物理特征图表面行适配器、卷积乘加阵列、卷积中间结果表面行信息打包单元、卷积中间结果累加与缓存、
	批归一化与激活处理单元、最终结果数据收集器

乘加阵列使用ATOMIC_K*ATOMIC_C个s16*s16乘法器, 时延 = 1clk
批归一化单元组使用BN_ACT_PRL_N*4个s18*s18乘法器或BN_ACT_PRL_N个s32*s32乘法器或BN_ACT_PRL_N个s25*s25乘法器, 时延 = 1或3clk
泄露Relu激活单元组使用BN_ACT_PRL_N个s32*s32乘法器或BN_ACT_PRL_N个s25*s25乘法器, 时延 = 2clk

使用RBUF_BANK_N个简单双口SRAM(位宽 = ATOMIC_K*32+ATOMIC_K, 深度 = RBUF_DEPTH), 读时延 = 1clk
使用1个真双口SRAM(位宽 = 64, 深度 = 最大的卷积核个数), 读时延 = 1clk
使用1个简单双口SRAM(位宽 = BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5, 深度 = 512), 读时延 = 1clk
使用BN_ACT_PRL_N个单口SRAM(位宽 = 16, 深度 = 4096), 读时延 = 1clk

注意：
当参数calfmt(运算数据格式)或cal_round(计算轮次 - 1)无效时, 需要除能乘加阵列(en_mac_array拉低)
卷积乘加阵列仅提供简单反压(阵列输出ready拉低时暂停整个计算流水线), 当参数ofmap_w(输出特征图宽度 - 1)或kernal_w((膨胀前)卷积核宽度 - 1)
	无效时, 需要除能打包器(en_packer拉低)
当(BN参数MEM里的)BN参数未准备好时, 需要除能BN与激活处理单元(en_bn_act_proc拉低)

计算1层多通道卷积前, 必须先重置适配器(拉高rst_adapter)
增加物理特征图表面行流量(给出on_incr_phy_row_traffic脉冲)以许可(kernal_w+1)个表面行的计算

BN与激活并行数(BN_ACT_PRL_N)必须<=核并行数(ATOMIC_K)

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/12/25
********************************************************************/


module conv_cal_sub_system #(
	// [子系统配置参数]
	parameter integer MAC_ARRAY_CLK_RATE = 1, // 计算核心时钟倍率(>=1)
	parameter integer BN_ACT_CLK_RATE = 1, // BN与激活单元的时钟倍率(>=1)
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1, // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer STREAM_DATA_WIDTH = 32, // 最终结果数据流的位宽(32 | 64 | 128 | 256)
	parameter FP32_KEEP = 1'b1, // 是否保持FP32输出
	parameter USE_EXT_MID_RES_BUF = "false", // 是否使用外部的中间结果缓存
	parameter USE_EXT_BN_ACT_UNIT = "false", // 是否使用外部的BN与激活单元
	parameter USE_EXT_FNL_RES_COLLECTOR = "false", // 是否使用外部的最终结果数据收集器
	parameter USE_EXT_ROUND_GRP = "false", // 是否使用外部的输出数据舍入单元组
	parameter USE_DSP_MACRO_FOR_ADD_TREE_IN_MAC_ARRAY = "false", // 是否使用DSP单元作为乘加阵列里的加法器
	// [计算配置参数]
	parameter integer MAX_CAL_ROUND = 1, // 最大的计算轮次(1~16)
	parameter EN_SMALL_FP16 = "true", // 乘加阵列是否处理极小FP16
	parameter EN_SMALL_FP32 = "true", // 中间结果累加是否处理极小FP32
	parameter BN_ACT_INT16_SUPPORTED = 1'b0, // BN与激活是否支持INT16运算数据格式
	parameter BN_ACT_INT32_SUPPORTED = 1'b1, // BN与激活是否支持INT32运算数据格式
	parameter BN_ACT_FP32_SUPPORTED = 1'b1, // BN与激活是否支持FP32运算数据格式
	// [中间结果缓存配置参数]
	parameter integer RBUF_BANK_N = 8, // 缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512, // 缓存MEM深度(16 | ...)
	// [仿真配置参数]
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	// 计算核心时钟和复位
	input wire mac_array_aclk,
	input wire mac_array_aresetn,
	input wire mac_array_aclken,
	// BN与激活单元时钟和复位
	input wire bn_act_aclk,
	input wire bn_act_aresetn,
	input wire bn_act_aclken,
	
	// 计算子系统控制/状态
	// [物理特征图表面行适配器]
	input wire rst_adapter, // 重置适配器
	input wire on_incr_phy_row_traffic, // 增加1个物理特征图表面行流量(指示)
	output wire[27:0] row_n_submitted_to_mac_array, // 已向乘加阵列提交的行数
	// [卷积乘加阵列]
	input wire en_mac_array, // 使能乘加阵列
	output wire[31:0] ftm_sfc_cal_n, // 已计算的特征图表面数
	// [卷积中间结果表面行信息打包单元]
	input wire en_packer, // 使能打包器
	// [批归一化与激活处理单元]
	input wire en_bn_act_proc, // 使能处理单元
	
	// 运行时参数
	// [计算参数]
	input wire[2:0] conv_horizontal_stride, // 卷积水平步长 - 1
	input wire[1:0] calfmt, // 运算数据格式
	input wire[3:0] cal_round, // 计算轮次 - 1
	// [特征图参数]
	input wire[2:0] external_padding_left, // 左部外填充数
	input wire[2:0] inner_padding_left_right, // 左右内填充数
	input wire[15:0] ifmap_w, // 输入特征图宽度 - 1
	input wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	input wire[15:0] cgrp_n_of_fmap_region_that_kernal_set_sel, // 核组所选定特征图域的通道组数 - 1
	// [卷积核参数]
	input wire[2:0] kernal_shape, // 卷积核形状
	input wire[3:0] kernal_dilation_hzt_n, // 水平膨胀量
	input wire[4:0] kernal_w_dilated, // (膨胀后)卷积核宽度 - 1
	// [中间结果缓存参数]
	input wire[15:0] mid_res_item_n_foreach_row, // 每个输出特征图表面行的中间结果项数 - 1
	input wire[3:0] mid_res_buf_row_n_bufferable, // 可缓存行数 - 1
	// [批归一化与激活参数]
	input wire use_bn_unit, // 启用BN单元
	input wire[2:0] act_func_type, // 激活函数类型
	input wire[4:0] bn_fixed_point_quat_accrc, // (批归一化操作数A)定点数量化精度
	input wire bn_is_a_eq_1, // 批归一化参数A的实际值为1(标志)
	input wire bn_is_b_eq_0, // 批归一化参数B的实际值为0(标志)
	input wire[4:0] leaky_relu_fixed_point_quat_accrc, // (泄露Relu激活参数)定点数量化精度
	input wire[31:0] leaky_relu_param_alpha, // 泄露Relu激活参数
	input wire[4:0] sigmoid_fixed_point_quat_accrc, // Sigmoid输入定点数量化精度
	
	// 特征图切块信息(AXIS从机)
	input wire[7:0] s_fm_cake_info_axis_data, // {保留(4bit), 每个切片里的有效表面行数(4bit)}
	input wire s_fm_cake_info_axis_valid,
	output wire s_fm_cake_info_axis_ready, // combinational logic out
	
	// 子表面行信息(AXIS从机)
	input wire[15:0] s_sub_row_msg_axis_data, // {输出通道号(16bit)}
	input wire s_sub_row_msg_axis_last, // 整个输出特征图的最后1个子表面行(标志)
	input wire s_sub_row_msg_axis_valid,
	output wire s_sub_row_msg_axis_ready, // combinational logic out
	
	// 物理特征图表面行数据(AXIS从机)
	input wire[ATOMIC_C*2*8-1:0] s_fmap_row_axis_data,
	input wire s_fmap_row_axis_last, // 标志物理特征图行的最后1个表面
	input wire s_fmap_row_axis_valid,
	output wire s_fmap_row_axis_ready,
	
	// 卷积核权重块数据(AXIS从机)
	input wire[ATOMIC_C*2*8-1:0] s_kwgtblk_axis_data,
	input wire s_kwgtblk_axis_last, // 标志卷积核权重块的最后1个表面
	input wire s_kwgtblk_axis_valid,
	output wire s_kwgtblk_axis_ready, // combinational logic out
	
	// 最终结果数据流(AXIS主机)
	output wire[STREAM_DATA_WIDTH-1:0] m_axis_fnl_res_data,
	output wire[STREAM_DATA_WIDTH/8-1:0] m_axis_fnl_res_keep,
	output wire m_axis_fnl_res_last, // 本行最后1个最终结果(标志)
	output wire m_axis_fnl_res_valid,
	input wire m_axis_fnl_res_ready,
	
	// 外部的中间结果缓存
	// [中间结果(AXIS主机)]
	output wire[ATOMIC_K*48-1:0] m_axis_ext_mid_res_data,
	output wire[ATOMIC_K*6-1:0] m_axis_ext_mid_res_keep,
	output wire[2:0] m_axis_ext_mid_res_user, // {是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	output wire m_axis_ext_mid_res_last, // 本行最后1个中间结果(标志)
	output wire m_axis_ext_mid_res_valid,
	input wire m_axis_ext_mid_res_ready,
	// [最终结果(AXIS从机)]
	input wire[ATOMIC_K*32-1:0] s_axis_ext_fnl_res_data, // ATOMIC_K个最终结果(单精度浮点数或定点数)
	input wire[ATOMIC_K*4-1:0] s_axis_ext_fnl_res_keep,
	input wire[4:0] s_axis_ext_fnl_res_user, // {是否最后1个子行(1bit), 子行号(4bit)}
	input wire s_axis_ext_fnl_res_last, // 本行最后1个最终结果(标志)
	input wire s_axis_ext_fnl_res_valid,
	output wire s_axis_ext_fnl_res_ready,
	
	// 外部的BN与激活单元
	// [卷积最终结果(AXIS主机)]
	output wire[ATOMIC_K*32-1:0] m_axis_ext_bn_act_i_data, // 对于ATOMIC_K个最终结果 -> {单精度浮点数或定点数(32位)}
	output wire[ATOMIC_K*4-1:0] m_axis_ext_bn_act_i_keep,
	output wire[4:0] m_axis_ext_bn_act_i_user, // {是否最后1个子行(1bit), 子行号(4bit)}
	output wire m_axis_ext_bn_act_i_last, // 本行最后1个最终结果(标志)
	output wire m_axis_ext_bn_act_i_valid,
	input wire m_axis_ext_bn_act_i_ready,
	// [经过BN与激活处理的结果(AXIS从机)]
	input wire[BN_ACT_PRL_N*32-1:0] s_axis_ext_bn_act_o_data, // 对于BN_ACT_PRL_N个最终结果 -> {浮点数或定点数}
	input wire[BN_ACT_PRL_N*4-1:0] s_axis_ext_bn_act_o_keep,
	input wire[4:0] s_axis_ext_bn_act_o_user, // {是否最后1个子行(1bit), 子行号(4bit)}
	input wire s_axis_ext_bn_act_o_last, // 本行最后1个处理结果(标志)
	input wire s_axis_ext_bn_act_o_valid,
	output wire s_axis_ext_bn_act_o_ready,
	
	// 外部的输出数据舍入单元组
	// [待舍入数据(AXIS主机)]
	output wire[ATOMIC_K*32-1:0] m_axis_ext_round_i_data, // ATOMIC_K个定点数或FP32
	output wire[ATOMIC_K*4-1:0] m_axis_ext_round_i_keep,
	output wire[4:0] m_axis_ext_round_i_user,
	output wire m_axis_ext_round_i_last,
	output wire m_axis_ext_round_i_valid,
	input wire m_axis_ext_round_i_ready,
	// [舍入后数据(AXIS从机)]
	input wire[ATOMIC_K*16-1:0] s_axis_ext_round_o_data, // ATOMIC_K个定点数或浮点数
	input wire[ATOMIC_K*2-1:0] s_axis_ext_round_o_keep,
	input wire[4:0] s_axis_ext_round_o_user,
	input wire s_axis_ext_round_o_last,
	input wire s_axis_ext_round_o_valid,
	output wire s_axis_ext_round_o_ready,
	
	// 外部的最终结果数据收集器
	// [待收集的数据流(AXIS主机)]
	output wire[ATOMIC_K*(FP32_KEEP ? 32:16)-1:0] m_axis_ext_collector_data,
	output wire[ATOMIC_K*(FP32_KEEP ? 4:2)-1:0] m_axis_ext_collector_keep,
	output wire m_axis_ext_collector_last,
	output wire m_axis_ext_collector_valid,
	input wire m_axis_ext_collector_ready,
	
	// 外部有符号乘法器#0
	output wire mul0_clk,
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul0_op_a, // 操作数A
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul0_op_b, // 操作数B
	output wire[ATOMIC_K-1:0] mul0_ce, // 计算使能
	input wire[ATOMIC_K*ATOMIC_C*32-1:0] mul0_res, // 计算结果
	// 外部有符号乘法器#1
	output wire mul1_clk,
	output wire[(BN_ACT_INT16_SUPPORTED ? 4*18:(BN_ACT_INT32_SUPPORTED ? 32:25))*BN_ACT_PRL_N-1:0] mul1_op_a, // 操作数A
	output wire[(BN_ACT_INT16_SUPPORTED ? 4*18:(BN_ACT_INT32_SUPPORTED ? 32:25))*BN_ACT_PRL_N-1:0] mul1_op_b, // 操作数B
	output wire[(BN_ACT_INT16_SUPPORTED ? 4:3)*BN_ACT_PRL_N-1:0] mul1_ce, // 计算使能
	                                                                      // combinational logic out
	input wire[(BN_ACT_INT16_SUPPORTED ? 4*36:(BN_ACT_INT32_SUPPORTED ? 64:50))*BN_ACT_PRL_N-1:0] mul1_res, // 计算结果
	// 外部有符号乘法器#2
	output wire mul2_clk,
	output wire[(BN_ACT_INT32_SUPPORTED ? 32:25)*BN_ACT_PRL_N-1:0] mul2_op_a, // 操作数A
	output wire[(BN_ACT_INT32_SUPPORTED ? 32:25)*BN_ACT_PRL_N-1:0] mul2_op_b, // 操作数B
	output wire[2*BN_ACT_PRL_N-1:0] mul2_ce, // 计算使能
	input wire[(BN_ACT_INT32_SUPPORTED ? 64:50)*BN_ACT_PRL_N-1:0] mul2_res, // 计算结果
	
	// 中间结果缓存MEM主接口
	output wire mid_res_mem_clk_a,
	output wire[RBUF_BANK_N-1:0] mid_res_mem_wen_a, // combinational logic out
	output wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_a,
	output wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_din_a,
	output wire mid_res_mem_clk_b,
	output wire[RBUF_BANK_N-1:0] mid_res_mem_ren_b, // combinational logic out
	output wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_b, // combinational logic out
	input wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_dout_b,
	// BN参数MEM主接口
	output wire bn_mem_clk_b,
	output wire bn_mem_ren_b,
	output wire[15:0] bn_mem_addr_b,
	input wire[63:0] bn_mem_dout_b, // {参数B(32bit), 参数A(32bit)}
	// 处理结果fifo(MEM主接口)
	output wire proc_res_fifo_mem_clk_a,
	output wire proc_res_fifo_mem_wen_a, // combinational logic out
	output wire[8:0] proc_res_fifo_mem_addr_a,
	output wire[(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_mem_din_a,
	output wire proc_res_fifo_mem_clk_b,
	output wire proc_res_fifo_mem_ren_b, // combinational logic out
	output wire[8:0] proc_res_fifo_mem_addr_b,
	input wire[(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5)-1:0] proc_res_fifo_mem_dout_b,
	// Sigmoid函数值查找表(MEM主接口)
	output wire sigmoid_lut_mem_clk_a,
	output wire[BN_ACT_PRL_N-1:0] sigmoid_lut_mem_ren_a, // combinational logic out
	output wire[12*BN_ACT_PRL_N-1:0] sigmoid_lut_mem_addr_a, // combinational logic out
	input wire[16*BN_ACT_PRL_N-1:0] sigmoid_lut_mem_dout_a
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
	// 卷积核形状的类型编码
	localparam KBUFGRPSZ_1 = 3'b000; // 1x1
	localparam KBUFGRPSZ_9 = 3'b001; // 3x3
	localparam KBUFGRPSZ_25 = 3'b010; // 5x5
	localparam KBUFGRPSZ_49 = 3'b011; // 7x7
	localparam KBUFGRPSZ_81 = 3'b100; // 9x9
	localparam KBUFGRPSZ_121 = 3'b101; // 11x11
	// BN与激活处理的运算数据格式的编码
	localparam BN_ACT_CAL_FMT_INT16 = 2'b00;
	localparam BN_ACT_CAL_FMT_INT32 = 2'b01;
	localparam BN_ACT_CAL_FMT_FP32 = 2'b10;
	localparam BN_ACT_CAL_FMT_NONE = 2'b11;
	// 乘加阵列和中间结果累加的运算数据格式的编码
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	
	/** 补充运行时参数 **/
	wire[3:0] kernal_w; // (膨胀前)卷积核宽度 - 1
	wire[3:0] bank_n_foreach_ofmap_row; // 每个输出特征图行所占用的缓存MEM个数
	wire[1:0] bn_act_calfmt; // BN与激活处理的数据格式
	
	assign kernal_w = 
		(
			(kernal_shape == KBUFGRPSZ_1)  ? 4'd1:
			(kernal_shape == KBUFGRPSZ_9)  ? 4'd3:
			(kernal_shape == KBUFGRPSZ_25) ? 4'd5:
			(kernal_shape == KBUFGRPSZ_49) ? 4'd7:
			(kernal_shape == KBUFGRPSZ_81) ? 4'd9:
											 4'd11
	    ) - 1;
	assign bank_n_foreach_ofmap_row = 
		(mid_res_item_n_foreach_row[15:clogb2(RBUF_DEPTH)] | 4'd0) + 1'b1;
	assign bn_act_calfmt = 
		(calfmt == CAL_FMT_INT8)  ? BN_ACT_CAL_FMT_INT16:
		(calfmt == CAL_FMT_INT16) ? BN_ACT_CAL_FMT_INT32:
		(calfmt == CAL_FMT_FP16)  ? BN_ACT_CAL_FMT_FP32:
		                            BN_ACT_CAL_FMT_NONE;
	
	/** 物理特征图表面行适配器 **/
	// 物理特征图表面行数据(AXIS从机)
	wire[ATOMIC_C*2*8-1:0] s_adapter_axis_data;
	wire s_adapter_axis_last; // 标志物理特征图行的最后1个表面
	wire s_adapter_axis_valid;
	wire s_adapter_axis_ready;
	// 乘加阵列计算数据(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_adapter_axis_data;
	wire m_adapter_axis_last; // 卷积核参数对应的最后1个特征图表面(标志)
	wire m_adapter_axis_user; // 标志本表面全0
	wire m_adapter_axis_valid;
	wire m_adapter_axis_ready;
	
	assign s_adapter_axis_data = s_fmap_row_axis_data;
	assign s_adapter_axis_last = s_fmap_row_axis_last;
	assign s_adapter_axis_valid = s_fmap_row_axis_valid;
	assign s_fmap_row_axis_ready = s_adapter_axis_ready;
	
	phy_fmap_sfc_row_adapter #(
		.ATOMIC_C(ATOMIC_C),
		.EN_ROW_AXIS_REG_SLICE("true"),
		.EN_MAC_ARRAY_AXIS_REG_SLICE("true"),
		.SIM_DELAY(SIM_DELAY)
	)phy_fmap_sfc_row_adapter_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.rst_adapter(rst_adapter),
		
		.conv_horizontal_stride(conv_horizontal_stride),
		.external_padding_left(external_padding_left),
		.inner_padding_left_right(inner_padding_left_right),
		.ifmap_w(ifmap_w),
		.ofmap_w(ofmap_w),
		.kernal_dilation_hzt_n(kernal_dilation_hzt_n),
		.kernal_w(kernal_w),
		.kernal_w_dilated(kernal_w_dilated),
		
		.on_incr_phy_row_traffic(on_incr_phy_row_traffic),
		.row_n_submitted_to_mac_array(row_n_submitted_to_mac_array),
		
		.s_fmap_row_axis_data(s_adapter_axis_data),
		.s_fmap_row_axis_last(s_adapter_axis_last),
		.s_fmap_row_axis_valid(s_adapter_axis_valid),
		.s_fmap_row_axis_ready(s_adapter_axis_ready),
		
		.m_mac_array_axis_data(m_adapter_axis_data),
		.m_mac_array_axis_last(m_adapter_axis_last),
		.m_mac_array_axis_user(m_adapter_axis_user),
		.m_mac_array_axis_valid(m_adapter_axis_valid),
		.m_mac_array_axis_ready(m_adapter_axis_ready)
	);
	
	/** 卷积乘加阵列 **/
	// 乘加阵列输入
	// [特征图]
	wire[ATOMIC_C*16-1:0] array_i_ftm_sfc; // 特征图表面(数据)
	wire array_i_ftm_sfc_last; // 卷积核参数对应的最后1个特征图表面(标志)
	wire array_i_ftm_sfc_masked; // 特征图表面(无效标志)
	wire array_i_ftm_sfc_vld; // 有效标志
	wire array_i_ftm_sfc_rdy; // 就绪标志
	// [卷积核]
	wire[ATOMIC_C*16-1:0] array_i_kernal_sfc; // 卷积核表面(数据)
	wire array_i_kernal_sfc_last; // 卷积核权重块对应的最后1个表面(标志)
	wire array_i_kernal_sfc_vld; // 有效指示
	wire array_i_kernal_buf_full_n; // 卷积核权重缓存满(标志)
	// [性能监测]
	reg[31:0] ftm_sfc_cal_n_cnt; // 已计算的特征图表面数(计数器)
	// 乘加阵列输出
	wire[ATOMIC_K*48-1:0] array_o_res; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[3:0] array_o_cal_round_id; // 计算轮次编号
	wire array_o_is_last_cal_round; // 是否最后1轮计算
	wire[ATOMIC_K-1:0] array_o_res_mask; // 计算结果输出项掩码
	wire array_o_res_vld; // 有效标志
	wire array_o_res_rdy; // 就绪标志
	
	assign ftm_sfc_cal_n = ftm_sfc_cal_n_cnt;
	
	assign array_i_ftm_sfc = m_adapter_axis_data;
	assign array_i_ftm_sfc_last = m_adapter_axis_last;
	assign array_i_ftm_sfc_masked = m_adapter_axis_user;
	assign array_i_ftm_sfc_vld = m_adapter_axis_valid;
	assign m_adapter_axis_ready = array_i_ftm_sfc_rdy;
	
	assign array_i_kernal_sfc = s_kwgtblk_axis_data;
	assign array_i_kernal_sfc_last = s_kwgtblk_axis_last;
	assign array_i_kernal_sfc_vld = s_kwgtblk_axis_valid;
	assign s_kwgtblk_axis_ready = array_i_kernal_buf_full_n;
	
	// 已计算的特征图表面数(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			((~en_mac_array) | (array_o_res_vld & array_o_res_rdy))
		)
			ftm_sfc_cal_n_cnt <= # SIM_DELAY 
				en_mac_array ? 
					(ftm_sfc_cal_n_cnt + 1'b1):
					32'd0;
	end
	
	conv_mac_array #(
		.MAC_ARRAY_CLK_RATE(MAC_ARRAY_CLK_RATE),
		.MAX_CAL_ROUND(MAX_CAL_ROUND),
		.ATOMIC_K(ATOMIC_K),
		.ATOMIC_C(ATOMIC_C),
		.EN_SMALL_FP16(EN_SMALL_FP16),
		.INFO_ALONG_WIDTH(1),
		.USE_INNER_SFC_CNT("true"),
		.TO_SKIP_EMPTY_CAL_ROUND("true"),
		.USE_DSP_MACRO_FOR_ADD_TREE(USE_DSP_MACRO_FOR_ADD_TREE_IN_MAC_ARRAY),
		.SIM_DELAY(SIM_DELAY)
	)conv_mac_array_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		.mac_array_aclk(mac_array_aclk),
		.mac_array_aresetn(mac_array_aresetn),
		.mac_array_aclken(mac_array_aclken),
		
		.en_mac_array(en_mac_array),
		
		.calfmt(calfmt),
		.cal_round(cal_round),
		
		.array_i_ftm_sfc(array_i_ftm_sfc),
		.array_i_ftm_info_along(1'bx),
		.array_i_ftm_sfc_last(array_i_ftm_sfc_last),
		.array_i_ftm_sfc_masked(array_i_ftm_sfc_masked),
		.array_i_ftm_sfc_vld(array_i_ftm_sfc_vld),
		.array_i_ftm_sfc_rdy(array_i_ftm_sfc_rdy),
		
		.array_i_kernal_sfc(array_i_kernal_sfc),
		.array_i_kernal_sfc_last(array_i_kernal_sfc_last),
		.array_i_kernal_sfc_id({(MAX_CAL_ROUND*ATOMIC_K){1'bx}}),
		.array_i_kernal_sfc_vld(array_i_kernal_sfc_vld),
		.array_i_kernal_buf_full_n(array_i_kernal_buf_full_n),
		
		.array_o_res(array_o_res),
		.array_o_cal_round_id(array_o_cal_round_id),
		.array_o_is_last_cal_round(array_o_is_last_cal_round),
		.array_o_res_info_along(),
		.array_o_res_mask(array_o_res_mask),
		.array_o_res_vld(array_o_res_vld),
		.array_o_res_rdy(array_o_res_rdy),
		
		.mul_clk(mul0_clk),
		.mul_op_a(mul0_op_a),
		.mul_op_b(mul0_op_b),
		.mul_ce(mul0_ce),
		.mul_res(mul0_res)
	);
	
	/** 卷积中间结果表面行信息打包单元 **/
	// 乘加阵列得到的中间结果
	wire[ATOMIC_K*48-1:0] mac_array_res; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire mac_array_is_last_cal_round; // 是否最后1轮计算
	wire[ATOMIC_K-1:0] mac_array_res_mask; // 计算结果输出项掩码
	wire mac_array_res_vld; // 有效标志
	wire mac_array_res_rdy; // 就绪标志
	// 打包后的中间结果(AXIS主机)
	wire[ATOMIC_K*48-1:0] m_axis_pkt_out_data; // ATOMIC_K个中间结果
	                                           // ({指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[ATOMIC_K*6-1:0] m_axis_pkt_out_keep;
	wire[2:0] m_axis_pkt_out_user; // {是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire m_axis_pkt_out_last; // 本行最后1个中间结果(标志)
	wire m_axis_pkt_out_valid;
	wire m_axis_pkt_out_ready;
	
	assign mac_array_res = array_o_res;
	assign mac_array_is_last_cal_round = array_o_is_last_cal_round;
	assign mac_array_res_mask = array_o_res_mask;
	assign mac_array_res_vld = array_o_res_vld;
	assign array_o_res_rdy = mac_array_res_rdy;
	
	conv_middle_res_info_packer #(
		.ATOMIC_K(ATOMIC_K),
		.EN_MAC_ARRAY_REG_SLICE("true"),
		.EN_PKT_OUT_REG_SLICE("true"),
		.SIM_DELAY(SIM_DELAY)
	)conv_middle_res_info_packer_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.en_packer(en_packer),
		
		.ofmap_w(ofmap_w[11:0]),
		.kernal_w(kernal_w),
		.cgrp_n_of_fmap_region_that_kernal_set_sel(cgrp_n_of_fmap_region_that_kernal_set_sel),
		
		.s_fm_cake_info_axis_data(s_fm_cake_info_axis_data),
		.s_fm_cake_info_axis_valid(s_fm_cake_info_axis_valid),
		.s_fm_cake_info_axis_ready(s_fm_cake_info_axis_ready),
		
		.mac_array_res(mac_array_res),
		.mac_array_is_last_cal_round(mac_array_is_last_cal_round),
		.mac_array_res_mask(mac_array_res_mask),
		.mac_array_res_vld(mac_array_res_vld),
		.mac_array_res_rdy(mac_array_res_rdy),
		
		.m_axis_pkt_out_data(m_axis_pkt_out_data),
		.m_axis_pkt_out_keep(m_axis_pkt_out_keep),
		.m_axis_pkt_out_user(m_axis_pkt_out_user),
		.m_axis_pkt_out_last(m_axis_pkt_out_last),
		.m_axis_pkt_out_valid(m_axis_pkt_out_valid),
		.m_axis_pkt_out_ready(m_axis_pkt_out_ready)
	);
	
	/** 卷积中间结果累加与缓存 **/
	// 中间结果输入(AXIS从机)
	/*
	对于ATOMIC_K个中间结果 -> 
		{指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)}
	*/
	wire[ATOMIC_K*48-1:0] s_axis_mid_res_buf_data;
	wire[ATOMIC_K*6-1:0] s_axis_mid_res_buf_keep;
	wire[2:0] s_axis_mid_res_buf_user; // {是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire s_axis_mid_res_buf_last; // 本行最后1个中间结果(标志)
	wire s_axis_mid_res_buf_valid;
	wire s_axis_mid_res_buf_ready;
	// 最终结果输出(AXIS主机)
	/*
	对于ATOMIC_K个最终结果 -> 
		{单精度浮点数或定点数(32位)}
	*/
	wire[ATOMIC_K*32-1:0] m_axis_mid_res_buf_data;
	wire[ATOMIC_K*4-1:0] m_axis_mid_res_buf_keep;
	wire[4:0] m_axis_mid_res_buf_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_mid_res_buf_last; // 本行最后1个最终结果(标志)
	wire m_axis_mid_res_buf_valid;
	wire m_axis_mid_res_buf_ready;
	// 中间结果累加单元组
	// [累加单元组输入]
	wire[ATOMIC_K*48-1:0] acmlt_in_new_res; // 新结果
	wire[ATOMIC_K*32-1:0] acmlt_in_org_mid_res; // 原中间结果
	wire[ATOMIC_K+2-1:0] acmlt_in_info_along[0:ATOMIC_K-1]; // 随路数据
	wire[ATOMIC_K-1:0] acmlt_in_mask; // 项掩码
	wire acmlt_in_first_item; // 是否第1项(标志)
	wire acmlt_in_last_grp; // 是否最后1组(标志)
	wire acmlt_in_last_res; // 本行最后1个中间结果(标志)
	wire[ATOMIC_K-1:0] acmlt_in_valid; // 输入有效指示
	// [累加单元组输出]
	wire[ATOMIC_K*32-1:0] acmlt_out_data; // 单精度浮点数或定点数
	wire[ATOMIC_K+2-1:0] acmlt_out_info_along[0:ATOMIC_K-1]; // 随路数据
	wire[ATOMIC_K-1:0] acmlt_out_mask; // 输出项掩码
	wire acmlt_out_last_grp; // 是否最后1组(标志)
	wire acmlt_out_last_res; // 本行最后1个中间结果(标志)
	wire[ATOMIC_K-1:0] acmlt_out_valid; // 输出有效指示
	
	assign s_axis_mid_res_buf_data = m_axis_pkt_out_data;
	assign s_axis_mid_res_buf_keep = m_axis_pkt_out_keep;
	assign s_axis_mid_res_buf_user = m_axis_pkt_out_user;
	assign s_axis_mid_res_buf_last = m_axis_pkt_out_last;
	assign s_axis_mid_res_buf_valid = m_axis_pkt_out_valid;
	assign m_axis_pkt_out_ready = s_axis_mid_res_buf_ready;
	
	assign {acmlt_out_last_res, acmlt_out_last_grp, acmlt_out_mask} = acmlt_out_info_along[0];
	
	genvar acmlt_i;
	generate
		for(acmlt_i = 0;acmlt_i < ATOMIC_K;acmlt_i = acmlt_i + 1)
		begin:acmlt_blk
			assign acmlt_in_info_along[acmlt_i] = 
				(acmlt_i == 0) ? 
					{acmlt_in_last_res, acmlt_in_last_grp, acmlt_in_mask}:
					{(ATOMIC_K+2){1'bx}};
			
			if(USE_EXT_MID_RES_BUF == "false")
			begin
				conv_middle_res_accumulate #(
					.EN_SMALL_FP32(EN_SMALL_FP32),
					.INFO_ALONG_WIDTH(ATOMIC_K+2),
					.SIM_DELAY(SIM_DELAY)
				)conv_middle_res_accumulate_u(
					.aclk(aclk),
					.aresetn(aresetn),
					.aclken(aclken),
					
					.calfmt(calfmt),
					
					.acmlt_in_exp(acmlt_in_new_res[acmlt_i*48+47:acmlt_i*48+40]),
					.acmlt_in_frac(acmlt_in_new_res[acmlt_i*48+39:acmlt_i*48+0]),
					.acmlt_in_org_mid_res(acmlt_in_org_mid_res[acmlt_i*32+31:acmlt_i*32+0]),
					.acmlt_in_first_item(acmlt_in_first_item),
					.acmlt_in_info_along(acmlt_in_info_along[acmlt_i]),
					.acmlt_in_valid(acmlt_in_valid[acmlt_i]),
					
					.acmlt_out_data(acmlt_out_data[acmlt_i*32+31:acmlt_i*32+0]),
					.acmlt_out_info_along(acmlt_out_info_along[acmlt_i]),
					.acmlt_out_valid(acmlt_out_valid[acmlt_i])
				);
			end
			else
			begin
				assign acmlt_out_data[acmlt_i*32+31:acmlt_i*32+0] = 32'dx;
				assign acmlt_out_info_along[acmlt_i] = {(ATOMIC_K+2){1'bx}};
				assign acmlt_out_valid[acmlt_i] = 1'b0;
			end
		end
	endgenerate
	
	generate
		if(USE_EXT_MID_RES_BUF == "false")
		begin
			/**
			不使用外部的中间结果缓存
			
			无效 -> 外部的中间结果缓存的中间结果(AXIS主机)
			外部的中间结果缓存的最终结果(AXIS从机) -> 忽略
			**/
			assign m_axis_ext_mid_res_data = {(ATOMIC_K*48){1'bx}};
			assign m_axis_ext_mid_res_keep = {(ATOMIC_K*6){1'bx}};
			assign m_axis_ext_mid_res_user = 3'bxxx;
			assign m_axis_ext_mid_res_last = 1'bx;
			assign m_axis_ext_mid_res_valid = 1'b0;
			
			assign s_axis_ext_fnl_res_ready = 1'b1;
			
			conv_middle_res_acmlt_buf #(
				.ATOMIC_K(ATOMIC_K),
				.RBUF_BANK_N(RBUF_BANK_N),
				.RBUF_DEPTH(RBUF_DEPTH),
				.INFO_ALONG_WIDTH(1),
				.SIM_DELAY(SIM_DELAY)
			)conv_middle_res_acmlt_buf_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				
				.calfmt(calfmt),
				.row_n_bufferable(mid_res_buf_row_n_bufferable),
				.bank_n_foreach_ofmap_row(bank_n_foreach_ofmap_row),
				.max_upd_latency(2 + 7),
				.en_cal_round_ext(1'b1),
				.ofmap_w(16'dx),
				
				.s_axis_mid_res_data(s_axis_mid_res_buf_data),
				.s_axis_mid_res_keep(s_axis_mid_res_buf_keep),
				.s_axis_mid_res_user({1'b0, s_axis_mid_res_buf_user}),
				.s_axis_mid_res_last(s_axis_mid_res_buf_last),
				.s_axis_mid_res_valid(s_axis_mid_res_buf_valid),
				.s_axis_mid_res_ready(s_axis_mid_res_buf_ready),
				
				.m_axis_fnl_res_data(m_axis_mid_res_buf_data),
				.m_axis_fnl_res_keep(m_axis_mid_res_buf_keep),
				.m_axis_fnl_res_user(m_axis_mid_res_buf_user),
				.m_axis_fnl_res_last(m_axis_mid_res_buf_last),
				.m_axis_fnl_res_valid(m_axis_mid_res_buf_valid),
				.m_axis_fnl_res_ready(m_axis_mid_res_buf_ready),
				
				.mem_clk_a(mid_res_mem_clk_a),
				.mem_wen_a(mid_res_mem_wen_a),
				.mem_addr_a(mid_res_mem_addr_a),
				.mem_din_a(mid_res_mem_din_a),
				.mem_clk_b(mid_res_mem_clk_b),
				.mem_ren_b(mid_res_mem_ren_b),
				.mem_addr_b(mid_res_mem_addr_b),
				.mem_dout_b(mid_res_mem_dout_b),
				
				.acmlt_in_new_res(acmlt_in_new_res),
				.acmlt_in_org_mid_res(acmlt_in_org_mid_res),
				.acmlt_in_mask(acmlt_in_mask),
				.acmlt_in_first_item(acmlt_in_first_item),
				.acmlt_in_last_grp(acmlt_in_last_grp),
				.acmlt_in_last_res(acmlt_in_last_res),
				.acmlt_in_info_along(),
				.acmlt_in_valid(acmlt_in_valid),
				
				.acmlt_out_data(acmlt_out_data),
				.acmlt_out_mask(acmlt_out_mask),
				.acmlt_out_last_grp(acmlt_out_last_grp),
				.acmlt_out_last_res(acmlt_out_last_res),
				.acmlt_out_to_upd_mem(1'b1),
				.acmlt_out_valid(acmlt_out_valid)
			);
		end
		else
		begin
			/**
			使用外部的中间结果缓存
			
			内部的中间结果缓存的中间结果(名义AXIS主机) -> 外部的中间结果缓存的中间结果(AXIS主机)
			外部的中间结果缓存的最终结果(AXIS从机) -> 内部的中间结果缓存的最终结果(AXIS主机)
			**/
			assign m_axis_ext_mid_res_data = s_axis_mid_res_buf_data;
			assign m_axis_ext_mid_res_keep = s_axis_mid_res_buf_keep;
			assign m_axis_ext_mid_res_user = s_axis_mid_res_buf_user;
			assign m_axis_ext_mid_res_last = s_axis_mid_res_buf_last;
			assign m_axis_ext_mid_res_valid = s_axis_mid_res_buf_valid;
			assign s_axis_mid_res_buf_ready = m_axis_ext_mid_res_ready;
			
			assign m_axis_mid_res_buf_data = s_axis_ext_fnl_res_data;
			assign m_axis_mid_res_buf_keep = s_axis_ext_fnl_res_keep;
			assign m_axis_mid_res_buf_user = s_axis_ext_fnl_res_user;
			assign m_axis_mid_res_buf_last = s_axis_ext_fnl_res_last;
			assign m_axis_mid_res_buf_valid = s_axis_ext_fnl_res_valid;
			assign s_axis_ext_fnl_res_ready = m_axis_mid_res_buf_ready;
			
			assign mid_res_mem_clk_a = 1'b0;
			assign mid_res_mem_wen_a = {RBUF_BANK_N{1'b0}};
			assign mid_res_mem_addr_a = {(RBUF_BANK_N*16){1'bx}};
			assign mid_res_mem_din_a = {(RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)){1'bx}};
			assign mid_res_mem_clk_b = 1'b0;
			assign mid_res_mem_ren_b = {RBUF_BANK_N{1'b0}};
			assign mid_res_mem_addr_b = {(RBUF_BANK_N*16){1'bx}};
			
			assign acmlt_in_new_res = {(ATOMIC_K*48){1'bx}};
			assign acmlt_in_org_mid_res = {(ATOMIC_K*32){1'bx}};
			assign acmlt_in_mask = {ATOMIC_K{1'bx}};
			assign acmlt_in_first_item = 1'bx;
			assign acmlt_in_last_grp = 1'bx;
			assign acmlt_in_last_res = 1'bx;
			assign acmlt_in_valid = 1'b0;
		end
	endgenerate
	
	/** 批归一化与激活处理单元 **/
	// 卷积最终结果(AXIS从机)
	wire[ATOMIC_K*32-1:0] s_axis_bn_act_data; // 对于ATOMIC_K个最终结果 -> {单精度浮点数或定点数(32位)}
	wire[ATOMIC_K*4-1:0] s_axis_bn_act_keep;
	wire[4:0] s_axis_bn_act_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire s_axis_bn_act_last; // 本行最后1个最终结果(标志)
	wire s_axis_bn_act_valid;
	wire s_axis_bn_act_ready;
	// 经过BN与激活处理的结果(AXIS主机)
	wire[BN_ACT_PRL_N*32-1:0] m_axis_bn_act_data; // 对于BN_ACT_PRL_N个最终结果 -> {浮点数或定点数}
	wire[BN_ACT_PRL_N*4-1:0] m_axis_bn_act_keep;
	wire[4:0] m_axis_bn_act_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_bn_act_last; // 本行最后1个处理结果(标志)
	wire m_axis_bn_act_valid;
	wire m_axis_bn_act_ready;
	
	assign s_axis_bn_act_data = m_axis_mid_res_buf_data;
	assign s_axis_bn_act_keep = m_axis_mid_res_buf_keep;
	assign s_axis_bn_act_user = m_axis_mid_res_buf_user;
	assign s_axis_bn_act_last = m_axis_mid_res_buf_last;
	assign s_axis_bn_act_valid = m_axis_mid_res_buf_valid;
	assign m_axis_mid_res_buf_ready = s_axis_bn_act_ready;
	
	generate
		if(USE_EXT_BN_ACT_UNIT == "false")
		begin
			/**
			不使用外部的BN与激活单元
			
			子表面行信息(AXIS从机) -> 内部的BN与激活单元
			无效 -> 外部的BN与激活单元的卷积最终结果(AXIS主机)
			外部的BN与激活单元的处理结果(AXIS从机) -> 忽略
			**/
			assign m_axis_ext_bn_act_i_data = {(ATOMIC_K*32){1'bx}};
			assign m_axis_ext_bn_act_i_keep = {(ATOMIC_K*4){1'bx}};
			assign m_axis_ext_bn_act_i_user = 5'bxxxxx;
			assign m_axis_ext_bn_act_i_last = 1'bx;
			assign m_axis_ext_bn_act_i_valid = 1'b0;
			
			assign s_axis_ext_bn_act_o_ready = 1'b1;
			
			conv_bn_act_proc #(
				.BN_ACT_CLK_RATE(BN_ACT_CLK_RATE),
				.FP32_KEEP(1'b1),
				.ATOMIC_K(ATOMIC_K),
				.BN_ACT_PRL_N(BN_ACT_PRL_N),
				.INT16_SUPPORTED(BN_ACT_INT16_SUPPORTED),
				.INT32_SUPPORTED(BN_ACT_INT32_SUPPORTED),
				.FP32_SUPPORTED(BN_ACT_FP32_SUPPORTED),
				.SIM_DELAY(SIM_DELAY)
			)conv_bn_act_proc_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				.bn_act_aclk(bn_act_aclk),
				.bn_act_aresetn(bn_act_aresetn),
				.bn_act_aclken(bn_act_aclken),
				
				.en_bn_act_proc(en_bn_act_proc),
				
				.calfmt(bn_act_calfmt),
				.use_bn_unit(use_bn_unit),
				.act_func_type(act_func_type),
				.bn_fixed_point_quat_accrc(bn_fixed_point_quat_accrc),
				.bn_is_a_eq_1(bn_is_a_eq_1),
				.bn_is_b_eq_0(bn_is_b_eq_0),
				.is_in_const_mac_mode(1'b0),
				.param_a_in_const_mac_mode(32'hxxxxxxxx),
				.param_b_in_const_mac_mode(32'hxxxxxxxx),
				.leaky_relu_fixed_point_quat_accrc(leaky_relu_fixed_point_quat_accrc),
				.leaky_relu_param_alpha(leaky_relu_param_alpha),
				.sigmoid_fixed_point_quat_accrc(sigmoid_fixed_point_quat_accrc),
				
				.s_sub_row_msg_axis_data(s_sub_row_msg_axis_data),
				.s_sub_row_msg_axis_last(s_sub_row_msg_axis_last),
				.s_sub_row_msg_axis_valid(s_sub_row_msg_axis_valid),
				.s_sub_row_msg_axis_ready(s_sub_row_msg_axis_ready),
				
				.s_axis_fnl_res_data(s_axis_bn_act_data),
				.s_axis_fnl_res_keep(s_axis_bn_act_keep),
				.s_axis_fnl_res_user(s_axis_bn_act_user),
				.s_axis_fnl_res_last(s_axis_bn_act_last),
				.s_axis_fnl_res_valid(s_axis_bn_act_valid),
				.s_axis_fnl_res_ready(s_axis_bn_act_ready),
				
				.m_axis_bn_act_res_data(m_axis_bn_act_data),
				.m_axis_bn_act_res_keep(m_axis_bn_act_keep),
				.m_axis_bn_act_res_user(m_axis_bn_act_user),
				.m_axis_bn_act_res_last(m_axis_bn_act_last),
				.m_axis_bn_act_res_valid(m_axis_bn_act_valid),
				.m_axis_bn_act_res_ready(m_axis_bn_act_ready),
				
				.bn_mem_clk_b(bn_mem_clk_b),
				.bn_mem_ren_b(bn_mem_ren_b),
				.bn_mem_addr_b(bn_mem_addr_b),
				.bn_mem_dout_b(bn_mem_dout_b),
				
				.proc_res_fifo_mem_clk_a(proc_res_fifo_mem_clk_a),
				.proc_res_fifo_mem_wen_a(proc_res_fifo_mem_wen_a),
				.proc_res_fifo_mem_addr_a(proc_res_fifo_mem_addr_a),
				.proc_res_fifo_mem_din_a(proc_res_fifo_mem_din_a),
				.proc_res_fifo_mem_clk_b(proc_res_fifo_mem_clk_b),
				.proc_res_fifo_mem_ren_b(proc_res_fifo_mem_ren_b),
				.proc_res_fifo_mem_addr_b(proc_res_fifo_mem_addr_b),
				.proc_res_fifo_mem_dout_b(proc_res_fifo_mem_dout_b),
				
				.sigmoid_lut_mem_clk_a(sigmoid_lut_mem_clk_a),
				.sigmoid_lut_mem_ren_a(sigmoid_lut_mem_ren_a),
				.sigmoid_lut_mem_addr_a(sigmoid_lut_mem_addr_a),
				.sigmoid_lut_mem_dout_a(sigmoid_lut_mem_dout_a),
				
				.mul0_clk(mul1_clk),
				.mul0_op_a(mul1_op_a),
				.mul0_op_b(mul1_op_b),
				.mul0_ce(mul1_ce),
				.mul0_res(mul1_res),
				
				.mul1_clk(mul2_clk),
				.mul1_op_a(mul2_op_a),
				.mul1_op_b(mul2_op_b),
				.mul1_ce(mul2_ce),
				.mul1_res(mul2_res)
			);
		end
		else
		begin
			/**
			使用外部的BN与激活单元
			
			子表面行信息(AXIS从机) -> 忽略
			内部的BN与激活处理单元的卷积最终结果(名义AXIS主机) -> 外部的BN与激活单元的卷积最终结果(AXIS主机)
			外部的BN与激活单元的处理结果(AXIS从机) -> 内部的BN与激活处理单元的处理结果(AXIS主机)
			**/
			assign s_sub_row_msg_axis_ready = 1'b1;
			
			assign m_axis_ext_bn_act_i_data = s_axis_bn_act_data;
			assign m_axis_ext_bn_act_i_keep = s_axis_bn_act_keep;
			assign m_axis_ext_bn_act_i_user = s_axis_bn_act_user;
			assign m_axis_ext_bn_act_i_last = s_axis_bn_act_last;
			assign m_axis_ext_bn_act_i_valid = s_axis_bn_act_valid;
			assign s_axis_bn_act_ready = m_axis_ext_bn_act_i_ready;
			
			assign m_axis_bn_act_data = s_axis_ext_bn_act_o_data;
			assign m_axis_bn_act_keep = s_axis_ext_bn_act_o_keep;
			assign m_axis_bn_act_user = s_axis_ext_bn_act_o_user;
			assign m_axis_bn_act_last = s_axis_ext_bn_act_o_last;
			assign m_axis_bn_act_valid = s_axis_ext_bn_act_o_valid;
			assign s_axis_ext_bn_act_o_ready = m_axis_bn_act_ready;
			
			assign bn_mem_clk_b = 1'b0;
			assign bn_mem_ren_b = 1'b0;
			assign bn_mem_addr_b = 16'dx;
			
			assign proc_res_fifo_mem_clk_a = 1'b0;
			assign proc_res_fifo_mem_wen_a = 1'b0;
			assign proc_res_fifo_mem_addr_a = 9'dx;
			assign proc_res_fifo_mem_din_a = {(BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5){1'bx}};
			assign proc_res_fifo_mem_clk_b = 1'b0;
			assign proc_res_fifo_mem_ren_b = 1'b0;
			assign proc_res_fifo_mem_addr_b = 9'dx;
			
			assign sigmoid_lut_mem_clk_a = 1'b0;
			assign sigmoid_lut_mem_ren_a = {BN_ACT_PRL_N{1'b0}};
			assign sigmoid_lut_mem_addr_a = {(BN_ACT_PRL_N*12){1'b0}};
			
			assign mul1_clk = 1'b0;
			assign mul1_op_a = {((BN_ACT_INT16_SUPPORTED ? 4*18:(BN_ACT_INT32_SUPPORTED ? 32:25))*BN_ACT_PRL_N){1'bx}};
			assign mul1_op_b = {((BN_ACT_INT16_SUPPORTED ? 4*18:(BN_ACT_INT32_SUPPORTED ? 32:25))*BN_ACT_PRL_N){1'bx}};
			assign mul1_ce = {((BN_ACT_INT16_SUPPORTED ? 4:3)*BN_ACT_PRL_N){1'b0}};
			
			assign mul2_clk = 1'b0;
			assign mul2_op_a = {((BN_ACT_INT32_SUPPORTED ? 32:25)*BN_ACT_PRL_N){1'bx}};
			assign mul2_op_b = {((BN_ACT_INT32_SUPPORTED ? 32:25)*BN_ACT_PRL_N){1'bx}};
			assign mul2_ce = {(2*BN_ACT_PRL_N){1'b0}};
		end
	endgenerate
	
	/** 输出数据舍入单元组 **/
	// [舍入单元组输入]
	wire[ATOMIC_K*32-1:0] s_axis_round_data; // ATOMIC_K个定点数或FP32
	wire[ATOMIC_K*4-1:0] s_axis_round_keep;
	wire[4:0] s_axis_round_user;
	wire s_axis_round_last;
	wire s_axis_round_valid;
	wire s_axis_round_ready;
	// [舍入单元组输出]
	wire[ATOMIC_K*(FP32_KEEP ? 32:16)-1:0] m_axis_round_data; // ATOMIC_K个定点数或浮点数
	wire[ATOMIC_K*(FP32_KEEP ? 4:2)-1:0] m_axis_round_keep;
	wire[4:0] m_axis_round_user;
	wire m_axis_round_last;
	wire m_axis_round_valid;
	wire m_axis_round_ready;
	
	assign s_axis_round_data = m_axis_bn_act_data | {(ATOMIC_K*32){1'b0}};
	assign s_axis_round_keep = m_axis_bn_act_keep | {(ATOMIC_K*4){1'b0}};
	assign s_axis_round_user = m_axis_bn_act_user;
	assign s_axis_round_last = m_axis_bn_act_last;
	assign s_axis_round_valid = m_axis_bn_act_valid;
	assign m_axis_bn_act_ready = s_axis_round_ready;
	
	generate
		if(FP32_KEEP == 1'b0)
		begin
			if(USE_EXT_ROUND_GRP == "false")
			begin
				/**
				不使用外部的输出数据舍入单元组
				
				无效 -> 外部的输出数据舍入单元组的待舍入数据(AXIS主机)
				外部的输出数据舍入单元组的舍入后数据(AXIS从机) -> 忽略
				**/
				assign m_axis_ext_round_i_data = {(ATOMIC_K*32){1'bx}};
				assign m_axis_ext_round_i_keep = {(ATOMIC_K*4){1'bx}};
				assign m_axis_ext_round_i_user = 5'bxxxxx;
				assign m_axis_ext_round_i_last = 1'bx;
				assign m_axis_ext_round_i_valid = 1'b0;
				
				assign s_axis_ext_round_o_ready = 1'b1;
				
				out_round_group #(
					.ATOMIC_K(ATOMIC_K),
					.INT8_SUPPORTED(BN_ACT_INT16_SUPPORTED),
					.INT16_SUPPORTED(BN_ACT_INT32_SUPPORTED),
					.FP16_SUPPORTED(BN_ACT_FP32_SUPPORTED),
					.USER_WIDTH(5),
					.SIM_DELAY(SIM_DELAY)
				)out_round_group_u(
					.aclk(aclk),
					.aresetn(aresetn),
					.aclken(aclken),
					
					.calfmt(calfmt),
					.fixed_point_quat_accrc(4'dx), // 警告: 需要给出运行时参数!!!
					
					.s_axis_round_data(s_axis_round_data),
					.s_axis_round_keep(s_axis_round_keep),
					.s_axis_round_user(s_axis_round_user),
					.s_axis_round_last(s_axis_round_last),
					.s_axis_round_valid(s_axis_round_valid),
					.s_axis_round_ready(s_axis_round_ready),
					
					.m_axis_round_data(m_axis_round_data),
					.m_axis_round_keep(m_axis_round_keep),
					.m_axis_round_user(m_axis_round_user),
					.m_axis_round_last(m_axis_round_last),
					.m_axis_round_valid(m_axis_round_valid),
					.m_axis_round_ready(m_axis_round_ready)
				);
			end
			else
			begin
				/**
				使用外部的输出数据舍入单元组
				
				内部的输出数据舍入单元组的输入(名义AXIS主机) -> 外部的输出数据舍入单元组的待舍入数据(AXIS主机)
				外部的输出数据舍入单元组的舍入后数据(AXIS从机) -> 内部的输出数据舍入单元组的输出(AXIS主机)
				**/
				assign m_axis_ext_round_i_data = s_axis_round_data;
				assign m_axis_ext_round_i_keep = s_axis_round_keep;
				assign m_axis_ext_round_i_user = s_axis_round_user;
				assign m_axis_ext_round_i_last = s_axis_round_last;
				assign m_axis_ext_round_i_valid = s_axis_round_valid;
				assign s_axis_round_ready = m_axis_ext_round_i_ready;
				
				assign m_axis_round_data = s_axis_ext_round_o_data;
				assign m_axis_round_keep = s_axis_ext_round_o_keep;
				assign m_axis_round_user = s_axis_ext_round_o_user;
				assign m_axis_round_last = s_axis_ext_round_o_last;
				assign m_axis_round_valid = s_axis_ext_round_o_valid;
				assign s_axis_ext_round_o_ready = m_axis_round_ready;
			end
		end
		else
		begin
			assign m_axis_ext_round_i_data = {(ATOMIC_K*32){1'bx}};
			assign m_axis_ext_round_i_keep = {(ATOMIC_K*4){1'bx}};
			assign m_axis_ext_round_i_user = 5'bxxxxx;
			assign m_axis_ext_round_i_last = 1'bx;
			assign m_axis_ext_round_i_valid = 1'b0;
			
			assign s_axis_ext_round_o_ready = 1'b1;
			
			assign m_axis_round_data = s_axis_round_data;
			assign m_axis_round_keep = s_axis_round_keep;
			assign m_axis_round_user = s_axis_round_user;
			assign m_axis_round_last = s_axis_round_last;
			assign m_axis_round_valid = s_axis_round_valid;
			assign s_axis_round_ready = m_axis_round_ready;
		end
	endgenerate
	
	/** 最终结果数据收集器 **/
	// 收集器输入(AXIS从机)
	wire[ATOMIC_K*(FP32_KEEP ? 32:16)-1:0] s_axis_collector_data;
	wire[ATOMIC_K*(FP32_KEEP ? 4:2)-1:0] s_axis_collector_keep;
	wire s_axis_collector_last;
	wire s_axis_collector_valid;
	wire s_axis_collector_ready;
	// 收集器输出(AXIS主机)
	wire[STREAM_DATA_WIDTH-1:0] m_axis_collector_data;
	wire[STREAM_DATA_WIDTH/8-1:0] m_axis_collector_keep;
	wire m_axis_collector_last;
	wire m_axis_collector_valid;
	wire m_axis_collector_ready;
	
	assign s_axis_collector_data = m_axis_round_data;
	assign s_axis_collector_keep = m_axis_round_keep;
	assign s_axis_collector_last = m_axis_round_last;
	assign s_axis_collector_valid = m_axis_round_valid;
	assign m_axis_round_ready = s_axis_collector_ready;
	
	assign m_axis_fnl_res_data = m_axis_collector_data;
	assign m_axis_fnl_res_keep = m_axis_collector_keep;
	assign m_axis_fnl_res_last = m_axis_collector_last;
	assign m_axis_fnl_res_valid = m_axis_collector_valid;
	assign m_axis_collector_ready = m_axis_fnl_res_ready;
	
	generate
		if(USE_EXT_FNL_RES_COLLECTOR == "false")
		begin
			/**
			不使用外部的最终结果数据收集器
			
			无效 -> 外部的最终结果数据收集器的待收集的数据流(AXIS主机)
			**/
			assign m_axis_ext_collector_data = {(ATOMIC_K*(FP32_KEEP ? 32:16)){1'bx}};
			assign m_axis_ext_collector_keep = {(ATOMIC_K*(FP32_KEEP ? 4:2)){1'bx}};
			assign m_axis_ext_collector_last = 1'bx;
			assign m_axis_ext_collector_valid = 1'b0;
			
			conv_final_data_collector #(
				.IN_ITEM_WIDTH(ATOMIC_K),
				.OUT_ITEM_WIDTH(STREAM_DATA_WIDTH/(FP32_KEEP ? 32:16)),
				.DATA_WIDTH_FOREACH_ITEM(FP32_KEEP ? 32:16),
				.HAS_USER("false"),
				.USER_WIDTH(1),
				.EN_COLLECTOR_OUT_REG_SLICE("true"),
				.SIM_DELAY(SIM_DELAY)
			)conv_final_data_collector_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				
				.s_axis_collector_data(s_axis_collector_data),
				.s_axis_collector_keep(s_axis_collector_keep),
				.s_axis_collector_user(1'bx),
				.s_axis_collector_last(s_axis_collector_last),
				.s_axis_collector_valid(s_axis_collector_valid),
				.s_axis_collector_ready(s_axis_collector_ready),
				
				.m_axis_collector_data(m_axis_collector_data),
				.m_axis_collector_keep(m_axis_collector_keep),
				.m_axis_collector_user(),
				.m_axis_collector_last(m_axis_collector_last),
				.m_axis_collector_valid(m_axis_collector_valid),
				.m_axis_collector_ready(m_axis_collector_ready)
			);
		end
		else
		begin
			/**
			使用外部的最终结果数据收集器
			
			内部的最终结果数据收集器的收集器输入(名义AXIS主机) -> 外部的最终结果数据收集器的待收集的数据流(AXIS主机)
			无效 -> 内部的最终结果数据收集器的收集器输出(AXIS主机)
			**/
			assign m_axis_ext_collector_data = s_axis_collector_data;
			assign m_axis_ext_collector_keep = s_axis_collector_keep;
			assign m_axis_ext_collector_last = s_axis_collector_last;
			assign m_axis_ext_collector_valid = s_axis_collector_valid;
			assign s_axis_collector_ready = m_axis_ext_collector_ready;
			
			assign m_axis_collector_data = {STREAM_DATA_WIDTH{1'bx}};
			assign m_axis_collector_keep = {(STREAM_DATA_WIDTH/8){1'bx}};
			assign m_axis_collector_last = 1'bx;
			assign m_axis_collector_valid = 1'b0;
		end
	endgenerate
	
endmodule
