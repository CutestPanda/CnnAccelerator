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
包括物理特征图表面行适配器、卷积乘加阵列、卷积中间结果表面行信息打包单元、卷积中间结果累加与缓存

使用ATOMIC_K*ATOMIC_C个s16*s16乘法器

使用RBUF_BANK_N个简单双口SRAM(位宽 = ATOMIC_K*32+ATOMIC_K, 深度 = RBUF_DEPTH)

注意：
当参数calfmt(运算数据格式)或cal_round(计算轮次 - 1)无效时, 需要除能乘加阵列(en_mac_array拉低)

卷积乘加阵列仅提供简单反压(阵列输出ready拉低时暂停整个计算流水线), 当参数ofmap_w(输出特征图宽度 - 1)或kernal_w((膨胀前)卷积核宽度 - 1)
无效时, 需要除能打包器(en_packer拉低)

计算1层多通道卷积前, 必须先重置适配器(拉高rst_adapter)
增加物理特征图表面行流量(给出on_incr_phy_row_traffic脉冲)以许可(kernal_w+1)个表面行的计算

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/11/12
********************************************************************/


module conv_cal_sub_system #(
	// [子系统配置参数]
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	// [计算配置参数]
	parameter integer MAX_CAL_ROUND = 1, // 最大的计算轮次(1~16)
	parameter EN_SMALL_FP16 = "true", // 是否处理极小FP16
	parameter EN_SMALL_FP32 = "false", // 是否处理极小FP32
	// [中间结果缓存配置参数]
	parameter integer RBUF_BANK_N = 8, // 缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512, // 缓存MEM深度(16 | ...)
	// [仿真配置参数]
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 计算子系统控制/状态
	// [物理特征图表面行适配器]
	input wire rst_adapter, // 重置适配器
	input wire on_incr_phy_row_traffic, // 增加1个物理特征图表面行流量(指示)
	output wire[27:0] row_n_submitted_to_mac_array, // 已向乘加阵列提交的行数
	// [卷积乘加阵列]
	input wire en_mac_array, // 使能乘加阵列
	// [卷积中间结果表面行信息打包单元]
	input wire en_packer, // 使能打包器
	
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
	input wire[3:0] kernal_dilation_hzt_n, // 水平膨胀量
	input wire[3:0] kernal_w, // (膨胀前)卷积核宽度 - 1
	input wire[4:0] kernal_w_dilated, // (膨胀后)卷积核宽度 - 1
	// [中间结果缓存参数]
	input wire[15:0] mid_res_item_n_foreach_row, // 每个输出特征图表面行的中间结果项数 - 1
	input wire[3:0] mid_res_buf_row_n_bufferable, // 可缓存行数 - 1
	
	// 特征图切块信息(AXIS从机)
	input wire[7:0] s_fm_cake_info_axis_data, // {保留(4bit), 每个切片里的有效表面行数(4bit)}
	input wire s_fm_cake_info_axis_valid,
	output wire s_fm_cake_info_axis_ready,
	
	// 物理特征图表面行数据(AXIS从机)
	input wire[ATOMIC_C*2*8-1:0] s_fmap_row_axis_data,
	input wire s_fmap_row_axis_last, // 标志物理特征图行的最后1个表面
	input wire s_fmap_row_axis_valid,
	output wire s_fmap_row_axis_ready,
	
	// 卷积核权重块数据(AXIS从机)
	input wire[ATOMIC_C*2*8-1:0] s_kwgtblk_axis_data,
	input wire s_kwgtblk_axis_last, // 标志卷积核权重块的最后1个表面
	input wire s_kwgtblk_axis_valid,
	output wire s_kwgtblk_axis_ready,
	
	// 最终结果输出(AXIS主机)
	/*
	对于ATOMIC_K个最终结果 -> 
		{单精度浮点数或定点数(32位)}
	*/
	output wire[ATOMIC_K*32-1:0] m_axis_fnl_res_data,
	output wire[ATOMIC_K*4-1:0] m_axis_fnl_res_keep,
	output wire m_axis_fnl_res_last, // 本行最后1个最终结果(标志)
	output wire m_axis_fnl_res_valid,
	input wire m_axis_fnl_res_ready,
	
	// 外部有符号乘法器
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_a, // 操作数A
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_b, // 操作数B
	output wire[ATOMIC_K-1:0] mul_ce, // 计算使能
	input wire[ATOMIC_K*ATOMIC_C*32-1:0] mul_res, // 计算结果
	
	// 中间结果缓存MEM主接口
	output wire mem_clk_a,
	output wire[RBUF_BANK_N-1:0] mem_wen_a,
	output wire[RBUF_BANK_N*16-1:0] mem_addr_a,
	output wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mem_din_a,
	output wire mem_clk_b,
	output wire[RBUF_BANK_N-1:0] mem_ren_b,
	output wire[RBUF_BANK_N*16-1:0] mem_addr_b,
	input wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mem_dout_b
);
	
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
	wire array_i_ftm_sfc_vld; // 有效标志
	wire array_i_ftm_sfc_rdy; // 就绪标志
	// [卷积核]
	wire[ATOMIC_C*16-1:0] array_i_kernal_sfc; // 卷积核表面(数据)
	wire array_i_kernal_sfc_last; // 卷积核权重块对应的最后1个表面(标志)
	wire array_i_kernal_sfc_vld; // 有效指示
	wire array_i_kernal_buf_full_n; // 卷积核权重缓存满(标志)
	// 乘加阵列输出
	wire[ATOMIC_K*48-1:0] array_o_res; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[3:0] array_o_cal_round_id; // 计算轮次编号
	wire array_o_is_last_cal_round; // 是否最后1轮计算
	wire[ATOMIC_K-1:0] array_o_res_mask; // 计算结果输出项掩码
	wire array_o_res_vld; // 有效标志
	wire array_o_res_rdy; // 就绪标志
	
	assign array_i_ftm_sfc = m_adapter_axis_data;
	assign array_i_ftm_sfc_last = m_adapter_axis_last;
	assign array_i_ftm_sfc_vld = m_adapter_axis_valid;
	assign m_adapter_axis_ready = array_i_ftm_sfc_rdy;
	
	assign array_i_kernal_sfc = s_kwgtblk_axis_data;
	assign array_i_kernal_sfc_last = s_kwgtblk_axis_last;
	assign array_i_kernal_sfc_vld = s_kwgtblk_axis_valid;
	assign s_kwgtblk_axis_ready = array_i_kernal_buf_full_n;
	
	conv_mac_array #(
		.MAX_CAL_ROUND(MAX_CAL_ROUND),
		.ATOMIC_K(ATOMIC_K),
		.ATOMIC_C(ATOMIC_C),
		.EN_SMALL_FP16(EN_SMALL_FP16),
		.INFO_ALONG_WIDTH(1),
		.USE_INNER_SFC_CNT("true"),
		.SIM_DELAY(SIM_DELAY)
	)conv_mac_array_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.en_mac_array(en_mac_array),
		
		.calfmt(calfmt),
		.cal_round(cal_round),
		
		.array_i_ftm_sfc(array_i_ftm_sfc),
		.array_i_ftm_info_along(1'bx),
		.array_i_ftm_sfc_last(array_i_ftm_sfc_last),
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
		
		.mul_op_a(mul_op_a),
		.mul_op_b(mul_op_b),
		.mul_ce(mul_ce),
		.mul_res(mul_res)
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
	wire[1:0] m_axis_pkt_out_user; // {初始化中间结果(标志), 最后1组中间结果(标志)}
	wire m_axis_pkt_out_valid;
	wire m_axis_pkt_out_ready;
	
	assign mac_array_res = array_o_res;
	assign mac_array_is_last_cal_round = array_o_is_last_cal_round;
	assign mac_array_res_mask = array_o_res_mask;
	assign mac_array_res_vld = array_o_res_vld;
	assign array_o_res_rdy = mac_array_res_rdy;
	
	conv_middle_res_info_packer #(
		.ATOMIC_K(ATOMIC_K),
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
	wire[1:0] s_axis_mid_res_buf_user; // {初始化中间结果(标志), 最后1组中间结果(标志)}
	wire s_axis_mid_res_buf_valid;
	wire s_axis_mid_res_buf_ready;
	// 最终结果输出(AXIS主机)
	/*
	对于ATOMIC_K个最终结果 -> 
		{单精度浮点数或定点数(32位)}
	*/
	wire[ATOMIC_K*32-1:0] m_axis_mid_res_buf_data;
	wire[ATOMIC_K*4-1:0] m_axis_mid_res_buf_keep;
	wire m_axis_mid_res_buf_last; // 本行最后1个最终结果(标志)
	wire m_axis_mid_res_buf_valid;
	wire m_axis_mid_res_buf_ready;
	
	assign s_axis_mid_res_buf_data = m_axis_pkt_out_data;
	assign s_axis_mid_res_buf_keep = m_axis_pkt_out_keep;
	assign s_axis_mid_res_buf_user = m_axis_pkt_out_user;
	assign s_axis_mid_res_buf_valid = m_axis_pkt_out_valid;
	assign m_axis_pkt_out_ready = s_axis_mid_res_buf_ready;
	
	assign m_axis_fnl_res_data = m_axis_mid_res_buf_data;
	assign m_axis_fnl_res_keep = m_axis_mid_res_buf_keep;
	assign m_axis_fnl_res_last = m_axis_mid_res_buf_last;
	assign m_axis_fnl_res_valid = m_axis_mid_res_buf_valid;
	assign m_axis_mid_res_buf_ready = m_axis_fnl_res_ready;
	
	conv_middle_res_acmlt_buf #(
		.ATOMIC_K(ATOMIC_K),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.EN_SMALL_FP32(EN_SMALL_FP32),
		.SIM_DELAY(SIM_DELAY)
	)conv_middle_res_acmlt_buf_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.calfmt(calfmt),
		.ofmap_w(mid_res_item_n_foreach_row),
		.row_n_bufferable(mid_res_buf_row_n_bufferable),
		
		.s_axis_mid_res_data(s_axis_mid_res_buf_data),
		.s_axis_mid_res_keep(s_axis_mid_res_buf_keep),
		.s_axis_mid_res_user(s_axis_mid_res_buf_user),
		.s_axis_mid_res_valid(s_axis_mid_res_buf_valid),
		.s_axis_mid_res_ready(s_axis_mid_res_buf_ready),
		
		.m_axis_fnl_res_data(m_axis_mid_res_buf_data),
		.m_axis_fnl_res_keep(m_axis_mid_res_buf_keep),
		.m_axis_fnl_res_last(m_axis_mid_res_buf_last),
		.m_axis_fnl_res_valid(m_axis_mid_res_buf_valid),
		.m_axis_fnl_res_ready(m_axis_mid_res_buf_ready),
		
		.mem_clk_a(mem_clk_a),
		.mem_wen_a(mem_wen_a),
		.mem_addr_a(mem_addr_a),
		.mem_din_a(mem_din_a),
		.mem_clk_b(mem_clk_b),
		.mem_ren_b(mem_ren_b),
		.mem_addr_b(mem_addr_b),
		.mem_dout_b(mem_dout_b)
	);
	
endmodule
