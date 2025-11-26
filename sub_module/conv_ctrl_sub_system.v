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
本模块: 通用卷积单元控制子系统

描述:
包括卷积核权重访问请求生成单元、特征图表面行访问请求生成单元、最终结果传输请求生成单元

使用1个u16*u16乘法器、2个u16*u24乘法器, 时延 = 1clk

注意：
目前不支持INT8运算数据格式

输入特征图大小 = 输入特征图宽度 * 输入特征图高度
扩展后特征图的垂直边界 = 原始特征图高度 + 上部外填充数 + (原始特征图高度 - 1) * 上下内填充数 - 1

当处于组卷积模式时, 每组的通道数/核数必须<=权重块最大宽度(max_wgtblk_w)
权重块最大宽度(max_wgtblk_w)必须<=32

卷积核权重块和特征图数据在内存中必须是连续存储的

协议:
BLK CTRL
AXIS MASTER

作者: 陈家耀
日期: 2025/11/26
********************************************************************/


module conv_ctrl_sub_system #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	// [计算参数]
	input wire[1:0] calfmt, // 运算数据格式
	input wire[2:0] conv_vertical_stride, // 卷积垂直步长 - 1
	// [组卷积模式]
	input wire is_grp_conv_mode, // 是否处于组卷积模式
	input wire[15:0] group_n, // 分组数 - 1
	input wire[15:0] n_foreach_group, // 每组的通道数/核数 - 1
	input wire[31:0] data_size_foreach_group, // 每组的数据量
	// [特征图参数]
	input wire[31:0] ifmap_baseaddr, // 输入特征图基地址
	input wire[31:0] ofmap_baseaddr, // 输出特征图基地址
	input wire[15:0] ifmap_w, // 输入特征图宽度 - 1
	input wire[23:0] ifmap_size, // 输入特征图大小 - 1
	input wire[15:0] fmap_chn_n, // 特征图通道数 - 1
	input wire[15:0] fmap_ext_i_bottom, // 扩展后特征图的垂直边界
	input wire[2:0] external_padding_top, // 上部外填充数
	input wire[2:0] inner_padding_top_bottom, // 上下内填充数
	input wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	input wire[15:0] ofmap_h, // 输出特征图高度 - 1
	input wire[1:0] ofmap_data_type, // 输出特征图数据大小类型
	// [卷积核参数]
	input wire[31:0] kernal_wgt_baseaddr, // 卷积核权重基地址
	input wire[2:0] kernal_shape, // 卷积核形状
	input wire[3:0] kernal_dilation_vtc_n, // 垂直膨胀量
	input wire[4:0] kernal_h_dilated, // (膨胀后)卷积核高度 - 1
	input wire[15:0] kernal_chn_n, // 通道数 - 1
	input wire[15:0] cgrpn_foreach_kernal_set, // 每个核组的通道组数 - 1
	input wire[15:0] kernal_num_n, // 核数 - 1
	input wire[15:0] kernal_set_n, // 核组个数 - 1
	input wire[5:0] max_wgtblk_w, // 权重块最大宽度
	
	// 块级控制
	// [卷积核权重访问请求生成单元]
	input wire kernal_access_blk_start,
	output wire kernal_access_blk_idle,
	output wire kernal_access_blk_done,
	// [特征图表面行访问请求生成单元]
	input wire fmap_access_blk_start,
	output wire fmap_access_blk_idle,
	output wire fmap_access_blk_done,
	// [最终结果传输请求生成单元]
	input wire fnl_res_trans_blk_start,
	output wire fnl_res_trans_blk_idle,
	output wire fnl_res_trans_blk_done,
	
	// 后级计算单元控制
	// [物理特征图表面行适配器控制]
	output wire rst_adapter, // 重置适配器(标志)
	output wire on_incr_phy_row_traffic, // 增加1个物理特征图表面行流量(指示)
	// [卷积乘加阵列]
	output wire en_mac_array, // 使能乘加阵列
	// [卷积中间结果表面行信息打包单元控制]
	output wire en_packer, // 使能打包器
	output wire[15:0] cgrp_n_of_fmap_region_that_kernal_set_sel, // 核组所选定特征图域的通道组数 - 1
	
	// 卷积核权重块读请求(AXIS主机)
	/*
	请求格式 -> 
		正常模式:
		{
			保留(6bit),
			是否重置缓存(1'b0)(1bit),
			实际通道组号(10bit),
			权重块编号(7bit),
			起始表面编号(7bit),
			待读取的表面个数 - 1(5bit),
			卷积核通道组基地址(32bit),
			卷积核通道组有效字节数(24bit),
			每个权重块的表面个数 - 1(7bit),
			每个表面的有效数据个数 - 1(5bit)
		}
		
		重置缓存:
		{
			保留(6bit),
			是否重置缓存(1'b1)(1bit),
			卷积核核组实际通道组数 - 1(10bit),
			通道组号偏移(10bit),
			保留(77bit)
		}
	*/
	output wire[103:0] m_kwgtblk_rd_req_axis_data,
	output wire m_kwgtblk_rd_req_axis_valid,
	input wire m_kwgtblk_rd_req_axis_ready,
	
	// 特征图表面行读请求(AXIS主机)
	/*
	请求格式 -> 
		{
			保留(6bit),
			是否重置缓存(1bit),
			实际表面行号(12bit),
			起始表面编号(12bit),
			待读取的表面个数 - 1(12bit),
			表面行基地址(32bit),
			表面行有效字节数(24bit),
			每个表面的有效数据个数 - 1(5bit)
		}
	*/
	output wire[103:0] m_fm_rd_req_axis_data,
	output wire m_fm_rd_req_axis_valid,
	input wire m_fm_rd_req_axis_ready,
	
	// 特征图切块信息(AXIS主机)
	output wire[7:0] m_fm_cake_info_axis_data, // {保留(4bit), 每个切片里的有效表面行数(4bit)}
	output wire m_fm_cake_info_axis_valid,
	input wire m_fm_cake_info_axis_ready,
	
	// S2MM方向DMA命令(AXIS主机)
	output wire[55:0] m_dma_s2mm_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_dma_s2mm_cmd_axis_user, // 固定(1'b1)/递增(1'b0)传输(1bit)
	output wire m_dma_s2mm_cmd_axis_valid,
	input wire m_dma_s2mm_cmd_axis_ready,
	
	// 外部无符号乘法器
	// [乘法器#0(u16*u16)]
	output wire[15:0] mul0_op_a, // 操作数A
	output wire[15:0] mul0_op_b, // 操作数B
	output wire mul0_ce, // 计算使能
	input wire[31:0] mul0_res, // 计算结果
	// [乘法器#1(u16*u24)]
	output wire[15:0] mul1_op_a, // 操作数A
	output wire[23:0] mul1_op_b, // 操作数B
	output wire mul1_ce, // 计算使能
	input wire[39:0] mul1_res, // 计算结果
	// [乘法器#2(u16*u24)]
	output wire[15:0] mul2_op_a, // 操作数A
	output wire[23:0] mul2_op_b, // 操作数B
	output wire mul2_ce, // 计算使能
	input wire[39:0] mul2_res // 计算结果
);
	
	/** 常量 **/
	// 运算数据格式
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	// 卷积核形状的类型编码
	localparam KBUFGRPSZ_1 = 3'b000; // 1x1
	localparam KBUFGRPSZ_9 = 3'b001; // 3x3
	localparam KBUFGRPSZ_25 = 3'b010; // 5x5
	localparam KBUFGRPSZ_49 = 3'b011; // 7x7
	localparam KBUFGRPSZ_81 = 3'b100; // 9x9
	localparam KBUFGRPSZ_121 = 3'b101; // 11x11
	
	/** 补充运行时参数 **/
	wire is_16bit_wgt; // 是否16位权重数据
	wire is_16bit_fmap_data; // 是否16位特征图数据
	wire[3:0] kernal_w; // (膨胀前)卷积核宽度 - 1
	
	assign is_16bit_wgt = calfmt != CAL_FMT_INT8;
	assign is_16bit_fmap_data = calfmt != CAL_FMT_INT8;
	assign kernal_w = 
		(
			(kernal_shape == KBUFGRPSZ_1)  ? 4'd1:
			(kernal_shape == KBUFGRPSZ_9)  ? 4'd3:
			(kernal_shape == KBUFGRPSZ_25) ? 4'd5:
			(kernal_shape == KBUFGRPSZ_49) ? 4'd7:
			(kernal_shape == KBUFGRPSZ_81) ? 4'd9:
											 4'd11
	    ) - 1;
	
	/** 后级计算单元控制 **/
	assign en_mac_array = 1'b1;
	assign en_packer = 1'b1;
	
	/** 卷积核权重访问请求生成单元 **/
	// 共享无符号乘法器
	// [通道#0]
	wire[15:0] kernal_access_mul_c0_op_a; // 操作数A
	wire[15:0] kernal_access_mul_c0_op_b; // 操作数B
	wire[3:0] kernal_access_mul_c0_tid; // 操作ID
	wire kernal_access_mul_c0_req;
	wire kernal_access_mul_c0_grant;
	// [延迟1clk的通道#0输入]
	reg[15:0] kernal_access_mul_c0_op_a_d1; // 延迟1clk的操作数A
	reg[15:0] kernal_access_mul_c0_op_b_d1; // 延迟1clk的操作数B
	reg[3:0] kernal_access_mul_c0_tid_d1; // 延迟1clk的操作ID
	reg kernal_access_mul_c0_req_d1;
	// [计算结果]
	wire[31:0] kernal_access_mul_res;
	reg[3:0] kernal_access_mul_oid;
	reg kernal_access_mul_ovld;
	
	assign mul0_op_a = kernal_access_mul_c0_op_a_d1;
	assign mul0_op_b = kernal_access_mul_c0_op_b_d1;
	assign mul0_ce = aclken & kernal_access_mul_c0_req_d1;
	
	assign kernal_access_mul_c0_grant = kernal_access_mul_c0_req;
	assign kernal_access_mul_res = mul0_res;
	
	always @(posedge aclk)
	begin
		if(aclken & kernal_access_mul_c0_req)
			{
				kernal_access_mul_c0_op_a_d1,
				kernal_access_mul_c0_op_b_d1,
				kernal_access_mul_c0_tid_d1
			} <= # SIM_DELAY {
				kernal_access_mul_c0_op_a,
				kernal_access_mul_c0_op_b,
				kernal_access_mul_c0_tid
			};
	end
	
	always @(posedge aclk)
	begin
		if(aclken & kernal_access_mul_c0_req_d1)
			kernal_access_mul_oid <= # SIM_DELAY kernal_access_mul_c0_tid_d1;
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{kernal_access_mul_ovld, kernal_access_mul_c0_req_d1} <= 2'b00;
		else if(aclken)
			{kernal_access_mul_ovld, kernal_access_mul_c0_req_d1} <= # SIM_DELAY 
				{kernal_access_mul_c0_req_d1, kernal_access_mul_c0_req};
	end
	
	kernal_access_req_gen #(
		.ATOMIC_C(ATOMIC_C),
		.EN_REG_SLICE_IN_RD_REQ("true"),
		.SIM_DELAY(SIM_DELAY)
	)kernal_access_req_gen_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.is_16bit_wgt(is_16bit_wgt),
		.kernal_wgt_baseaddr(kernal_wgt_baseaddr),
		.kernal_chn_n(kernal_chn_n),
		.kernal_num_n(kernal_num_n),
		.kernal_shape(kernal_shape),
		.ofmap_h(ofmap_h),
		.is_grp_conv_mode(is_grp_conv_mode),
		.n_foreach_group(n_foreach_group),
		.group_n(group_n),
		.cgrpn_foreach_kernal_set(cgrpn_foreach_kernal_set),
		.max_wgtblk_w(max_wgtblk_w),
		.conv_vertical_stride(conv_vertical_stride),
		.ext_i_bottom(fmap_ext_i_bottom),
		.external_padding_top(external_padding_top),
		.inner_padding_top_bottom(inner_padding_top_bottom),
		.kernal_dilation_vtc_n(kernal_dilation_vtc_n),
		
		.blk_start(kernal_access_blk_start),
		.blk_idle(kernal_access_blk_idle),
		.blk_done(kernal_access_blk_done),
		
		.m_kwgtblk_rd_req_axis_data(m_kwgtblk_rd_req_axis_data),
		.m_kwgtblk_rd_req_axis_valid(m_kwgtblk_rd_req_axis_valid),
		.m_kwgtblk_rd_req_axis_ready(m_kwgtblk_rd_req_axis_ready),
		
		.shared_mul_c0_op_a(kernal_access_mul_c0_op_a),
		.shared_mul_c0_op_b(kernal_access_mul_c0_op_b),
		.shared_mul_c0_tid(kernal_access_mul_c0_tid),
		.shared_mul_c0_req(kernal_access_mul_c0_req),
		.shared_mul_c0_grant(kernal_access_mul_c0_grant),
		.shared_mul_res(kernal_access_mul_res),
		.shared_mul_oid(kernal_access_mul_oid),
		.shared_mul_ovld(kernal_access_mul_ovld)
	);
	
	/** 特征图表面行访问请求生成单元 **/
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] fmap_access_mul0_op_a; // 操作数A
	wire[15:0] fmap_access_mul0_op_b; // 操作数B
	wire[3:0] fmap_access_mul0_tid; // 操作ID
	wire fmap_access_mul0_req;
	wire fmap_access_mul0_grant;
	// [计算结果]
	wire[31:0] fmap_access_mul0_res;
	wire[3:0] fmap_access_mul0_oid;
	wire fmap_access_mul0_ovld;
	// (共享)无符号乘法器#1
	// [计算输入]
	wire[15:0] fmap_access_mul1_op_a; // 操作数A
	wire[23:0] fmap_access_mul1_op_b; // 操作数B
	wire[3:0] fmap_access_mul1_tid; // 操作ID
	wire fmap_access_mul1_req;
	wire fmap_access_mul1_grant;
	// [计算结果]
	wire[39:0] fmap_access_mul1_res;
	wire[3:0] fmap_access_mul1_oid;
	wire fmap_access_mul1_ovld;
	// 延迟1clk的乘法器输入
	reg[15:0] fmap_access_shared_mul_op_a_d1;
	reg[23:0] fmap_access_shared_mul_op_b_d1;
	reg[3:0] fmap_access_shared_mul_tid_d1;
	reg fmap_access_shared_mul_req_d1;
	// 延迟2clk的乘法器输入
	reg[3:0] fmap_access_shared_mul_tid_d2;
	reg fmap_access_shared_mul_req_d2;
	
	assign mul1_op_a = fmap_access_shared_mul_op_a_d1;
	assign mul1_op_b = fmap_access_shared_mul_op_b_d1;
	assign mul1_ce = aclken & fmap_access_shared_mul_req_d1;
	
	assign fmap_access_mul0_grant = fmap_access_mul0_req;
	assign fmap_access_mul0_res = mul1_res[31:0];
	assign fmap_access_mul0_oid = fmap_access_shared_mul_tid_d2;
	assign fmap_access_mul0_ovld = fmap_access_shared_mul_req_d2;
	
	assign fmap_access_mul1_grant = (~fmap_access_mul0_req) & fmap_access_mul1_req;
	assign fmap_access_mul1_res = mul1_res;
	assign fmap_access_mul1_oid = fmap_access_shared_mul_tid_d2;
	assign fmap_access_mul1_ovld = fmap_access_shared_mul_req_d2;
	
	always @(posedge aclk)
	begin
		if(aclken & (fmap_access_mul0_req | fmap_access_mul1_req))
			{
				fmap_access_shared_mul_op_a_d1,
				fmap_access_shared_mul_op_b_d1,
				fmap_access_shared_mul_tid_d1
			} <= # SIM_DELAY 
				fmap_access_mul0_req ? 
					{
						fmap_access_mul0_op_a,
						{8'h00, fmap_access_mul0_op_b},
						fmap_access_mul0_tid
					}:
					{
						fmap_access_mul1_op_a,
						fmap_access_mul1_op_b,
						fmap_access_mul1_tid
					};
	end
	
	always @(posedge aclk)
	begin
		if(aclken & fmap_access_shared_mul_req_d1)
			fmap_access_shared_mul_tid_d2 <= # SIM_DELAY fmap_access_shared_mul_tid_d1;
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{fmap_access_shared_mul_req_d2, fmap_access_shared_mul_req_d1} <= 2'b00;
		else if(aclken)
			{fmap_access_shared_mul_req_d2, fmap_access_shared_mul_req_d1} <= # SIM_DELAY 
				{fmap_access_shared_mul_req_d1, fmap_access_mul0_req | fmap_access_mul1_req};
	end
	
	fmap_sfc_row_access_req_gen #(
		.ATOMIC_C(ATOMIC_C),
		.EN_REG_SLICE_IN_RD_REQ("true"),
		.SIM_DELAY(SIM_DELAY)
	)fmap_sfc_row_access_req_gen_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.conv_vertical_stride(conv_vertical_stride),
		.is_grp_conv_mode(is_grp_conv_mode),
		.n_foreach_group(n_foreach_group),
		.data_size_foreach_group(data_size_foreach_group),
		.fmap_baseaddr(ifmap_baseaddr),
		.is_16bit_data(is_16bit_fmap_data),
		.ifmap_w(ifmap_w),
		.ifmap_size(ifmap_size),
		.ofmap_h(ofmap_h),
		.fmap_chn_n(fmap_chn_n),
		.ext_i_bottom(fmap_ext_i_bottom),
		.external_padding_top(external_padding_top),
		.inner_padding_top_bottom(inner_padding_top_bottom),
		.kernal_set_n(kernal_set_n),
		.kernal_dilation_vtc_n(kernal_dilation_vtc_n),
		.kernal_w(kernal_w),
		.kernal_h_dilated(kernal_h_dilated),
		
		.blk_start(fmap_access_blk_start),
		.blk_idle(fmap_access_blk_idle),
		.blk_done(fmap_access_blk_done),
		
		.rst_adapter(rst_adapter),
		.on_incr_phy_row_traffic(on_incr_phy_row_traffic),
		.cgrp_n_of_fmap_region_that_kernal_set_sel(cgrp_n_of_fmap_region_that_kernal_set_sel),
		
		.m_fm_rd_req_axis_data(m_fm_rd_req_axis_data),
		.m_fm_rd_req_axis_valid(m_fm_rd_req_axis_valid),
		.m_fm_rd_req_axis_ready(m_fm_rd_req_axis_ready),
		
		.m_fm_cake_info_axis_data(m_fm_cake_info_axis_data),
		.m_fm_cake_info_axis_valid(m_fm_cake_info_axis_valid),
		.m_fm_cake_info_axis_ready(m_fm_cake_info_axis_ready),
		
		.mul0_op_a(fmap_access_mul0_op_a),
		.mul0_op_b(fmap_access_mul0_op_b),
		.mul0_tid(fmap_access_mul0_tid),
		.mul0_req(fmap_access_mul0_req),
		.mul0_grant(fmap_access_mul0_grant),
		.mul0_res(fmap_access_mul0_res),
		.mul0_oid(fmap_access_mul0_oid),
		.mul0_ovld(fmap_access_mul0_ovld),
		
		.mul1_op_a(fmap_access_mul1_op_a),
		.mul1_op_b(fmap_access_mul1_op_b),
		.mul1_tid(fmap_access_mul1_tid),
		.mul1_req(fmap_access_mul1_req),
		.mul1_grant(fmap_access_mul1_grant),
		.mul1_res(fmap_access_mul1_res),
		.mul1_oid(fmap_access_mul1_oid),
		.mul1_ovld(fmap_access_mul1_ovld)
	);
	
	/** 最终结果传输请求生成单元 **/
	// DMA命令(AXIS主机)
	wire[55:0] m_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire[24:0] m_dma_cmd_axis_user; // {命令ID(24bit), 固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_dma_cmd_axis_valid;
	wire m_dma_cmd_axis_ready;
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] fnl_res_trans_mul0_op_a; // 操作数A
	wire[23:0] fnl_res_trans_mul0_op_b; // 操作数B
	wire[3:0] fnl_res_trans_mul0_tid; // 操作ID
	wire fnl_res_trans_mul0_req;
	wire fnl_res_trans_mul0_grant;
	// [计算结果]
	wire[39:0] fnl_res_trans_mul0_res;
	wire[3:0] fnl_res_trans_mul0_oid;
	wire fnl_res_trans_mul0_ovld;
	// (共享)无符号乘法器#1
	// [计算输入]
	wire[15:0] fnl_res_trans_mul1_op_a; // 操作数A
	wire[23:0] fnl_res_trans_mul1_op_b; // 操作数B
	wire[3:0] fnl_res_trans_mul1_tid; // 操作ID
	wire fnl_res_trans_mul1_req;
	wire fnl_res_trans_mul1_grant;
	// [计算结果]
	wire[39:0] fnl_res_trans_mul1_res;
	wire[3:0] fnl_res_trans_mul1_oid;
	wire fnl_res_trans_mul1_ovld;
	// 延迟1clk的乘法器输入
	reg[15:0] fnl_res_trans_shared_mul_op_a_d1;
	reg[23:0] fnl_res_trans_shared_mul_op_b_d1;
	reg[3:0] fnl_res_trans_shared_mul_tid_d1;
	reg fnl_res_trans_shared_mul_req_d1;
	// 延迟2clk的乘法器输入
	reg[3:0] fnl_res_trans_shared_mul_tid_d2;
	reg fnl_res_trans_shared_mul_req_d2;
	
	assign m_dma_s2mm_cmd_axis_data = m_dma_cmd_axis_data;
	assign m_dma_s2mm_cmd_axis_user = m_dma_cmd_axis_user[0];
	assign m_dma_s2mm_cmd_axis_valid = m_dma_cmd_axis_valid;
	assign m_dma_cmd_axis_ready = m_dma_s2mm_cmd_axis_ready;
	
	assign mul2_op_a = fnl_res_trans_shared_mul_op_a_d1;
	assign mul2_op_b = fnl_res_trans_shared_mul_op_b_d1;
	assign mul2_ce = aclken & fnl_res_trans_shared_mul_req_d1;
	
	assign fnl_res_trans_mul0_grant = fnl_res_trans_mul0_req;
	assign fnl_res_trans_mul0_res = mul2_res;
	assign fnl_res_trans_mul0_oid = fnl_res_trans_shared_mul_tid_d2;
	assign fnl_res_trans_mul0_ovld = fnl_res_trans_shared_mul_req_d2;
	
	assign fnl_res_trans_mul1_grant = (~fnl_res_trans_mul0_req) & fnl_res_trans_mul1_req;
	assign fnl_res_trans_mul1_res = mul2_res;
	assign fnl_res_trans_mul1_oid = fnl_res_trans_shared_mul_tid_d2;
	assign fnl_res_trans_mul1_ovld = fnl_res_trans_shared_mul_req_d2;
	
	always @(posedge aclk)
	begin
		if(aclken & (fnl_res_trans_mul0_req | fnl_res_trans_mul1_req))
			{
				fnl_res_trans_shared_mul_op_a_d1,
				fnl_res_trans_shared_mul_op_b_d1,
				fnl_res_trans_shared_mul_tid_d1
			} <= # SIM_DELAY 
				fnl_res_trans_mul0_req ? 
					{
						fnl_res_trans_mul0_op_a,
						fnl_res_trans_mul0_op_b,
						fnl_res_trans_mul0_tid
					}:
					{
						fnl_res_trans_mul1_op_a,
						fnl_res_trans_mul1_op_b,
						fnl_res_trans_mul1_tid
					};
	end
	
	always @(posedge aclk)
	begin
		if(aclken & fnl_res_trans_shared_mul_req_d1)
			fnl_res_trans_shared_mul_tid_d2 <= # SIM_DELAY fnl_res_trans_shared_mul_tid_d1;
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{fnl_res_trans_shared_mul_req_d2, fnl_res_trans_shared_mul_req_d1} <= 2'b00;
		else if(aclken)
			{fnl_res_trans_shared_mul_req_d2, fnl_res_trans_shared_mul_req_d1} <= # SIM_DELAY 
				{fnl_res_trans_shared_mul_req_d1, fnl_res_trans_mul0_req | fnl_res_trans_mul1_req};
	end
	
	fnl_res_trans_req_gen #(
		.ATOMIC_K(ATOMIC_K),
		.SIM_DELAY(SIM_DELAY)
	)fnl_res_trans_req_gen_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.ofmap_baseaddr(ofmap_baseaddr),
		.ofmap_w(ofmap_w),
		.ofmap_h(ofmap_h),
		.ofmap_data_type(ofmap_data_type),
		.kernal_num_n(kernal_num_n),
		.max_wgtblk_w(max_wgtblk_w),
		.is_grp_conv_mode(is_grp_conv_mode),
		.group_n(group_n),
		.n_foreach_group(n_foreach_group),
		
		.blk_start(fnl_res_trans_blk_start),
		.blk_idle(fnl_res_trans_blk_idle),
		.blk_done(fnl_res_trans_blk_done),
		
		.m_dma_cmd_axis_data(m_dma_cmd_axis_data),
		.m_dma_cmd_axis_user(m_dma_cmd_axis_user),
		.m_dma_cmd_axis_valid(m_dma_cmd_axis_valid),
		.m_dma_cmd_axis_ready(m_dma_cmd_axis_ready),
		
		.mul0_op_a(fnl_res_trans_mul0_op_a),
		.mul0_op_b(fnl_res_trans_mul0_op_b),
		.mul0_tid(fnl_res_trans_mul0_tid),
		.mul0_req(fnl_res_trans_mul0_req),
		.mul0_grant(fnl_res_trans_mul0_grant),
		.mul0_res(fnl_res_trans_mul0_res),
		.mul0_oid(fnl_res_trans_mul0_oid),
		.mul0_ovld(fnl_res_trans_mul0_ovld),
		
		.mul1_op_a(fnl_res_trans_mul1_op_a),
		.mul1_op_b(fnl_res_trans_mul1_op_b),
		.mul1_tid(fnl_res_trans_mul1_tid),
		.mul1_req(fnl_res_trans_mul1_req),
		.mul1_grant(fnl_res_trans_mul1_grant),
		.mul1_res(fnl_res_trans_mul1_res),
		.mul1_oid(fnl_res_trans_mul1_oid),
		.mul1_ovld(fnl_res_trans_mul1_ovld)
	);
	
endmodule
