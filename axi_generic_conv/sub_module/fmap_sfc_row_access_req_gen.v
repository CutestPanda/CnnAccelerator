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
本模块: 特征图表面行访问请求生成单元

描述:
根据计算参数、组卷积参数、特征图参数、卷积核参数,
按照"卷积核x方向 -> 卷积核y方向 -> 通道组 -> 特征图y方向 -> 核组"的顺序生成特征图表面行读请求

使用1个(共享)u16*u16乘法器和1个(共享)u16*u24乘法器

使用"通道组号+(部分)物理y坐标"作为实际表面行号, 每当移动到下一个输出行时, 可能会重新生成物理y坐标的编码偏移

支持扩展特征图(内填充、外填充), 支持扩展卷积核(核膨胀)

注意：
扩展后特征图的垂直边界 = 原始特征图高度 + 上部外填充数 + (原始特征图高度 - 1) * 上下内填充数 - 1
输入特征图大小 = 输入特征图宽度 * 输入特征图高度

目前仅支持16位特征图数据
特征图数据在内存中必须是连续存储的

协议:
BLK CTRL
AXIS MASTER
REQ/GRANT

作者: 陈家耀
日期: 2025/11/27
********************************************************************/


module fmap_sfc_row_access_req_gen #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter EN_REG_SLICE_IN_RD_REQ = "true", // 是否在"特征图表面行读请求"处插入寄存器片
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	// [计算参数]
	input wire[2:0] conv_vertical_stride, // 卷积垂直步长 - 1
	// [组卷积模式]
	input wire is_grp_conv_mode, // 是否处于组卷积模式
	input wire[15:0] n_foreach_group, // 每组的通道数 - 1
	input wire[31:0] data_size_foreach_group, // 每组的数据量
	// [特征图参数]
	input wire[31:0] fmap_baseaddr, // 特征图数据基地址
	input wire is_16bit_data, // 是否16位特征图数据
	input wire[15:0] ifmap_w, // 输入特征图宽度 - 1
	input wire[23:0] ifmap_size, // 输入特征图大小 - 1
	input wire[15:0] ofmap_h, // 输出特征图高度 - 1
	input wire[15:0] fmap_chn_n, // 通道数 - 1
	input wire[15:0] ext_i_bottom, // 扩展后特征图的垂直边界
	input wire[2:0] external_padding_top, // 上部外填充数
	input wire[2:0] inner_padding_top_bottom, // 上下内填充数
	// [卷积核参数]
	input wire[15:0] kernal_set_n, // 核组个数 - 1
	input wire[3:0] kernal_dilation_vtc_n, // 垂直膨胀量
	input wire[3:0] kernal_w, // (膨胀前)卷积核宽度 - 1
	input wire[4:0] kernal_h_dilated, // (膨胀后)卷积核高度 - 1
	
	// 块级控制
	input wire blk_start,
	output wire blk_idle,
	output wire blk_done,
	
	// 后级计算单元控制
	// [物理特征图表面行适配器控制]
	output wire rst_adapter, // 重置适配器(标志)
	output wire on_incr_phy_row_traffic, // 增加1个物理特征图表面行流量(指示)
	// [卷积中间结果表面行信息打包单元控制]
	output wire[15:0] cgrp_n_of_fmap_region_that_kernal_set_sel, // 核组所选定特征图域的通道组数 - 1
	
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
	
	// (共享)无符号乘法器#0
	// [计算输入]
	output wire[15:0] mul0_op_a, // 操作数A
	output wire[15:0] mul0_op_b, // 操作数B
	output wire[3:0] mul0_tid, // 操作ID
	output wire mul0_req,
	input wire mul0_grant,
	// [计算结果]
	input wire[31:0] mul0_res,
	input wire[3:0] mul0_oid,
	input wire mul0_ovld,
	
	// (共享)无符号乘法器#1
	// [计算输入]
	output wire[15:0] mul1_op_a, // 操作数A
	output wire[23:0] mul1_op_b, // 操作数B
	output wire[3:0] mul1_tid, // 操作ID
	output wire mul1_req,
	input wire mul1_grant,
	// [计算结果]
	input wire[39:0] mul1_res,
	input wire[3:0] mul1_oid,
	input wire mul1_ovld
);
	
	/** 函数 **/
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
	// 访问请求生成(状态编码)
	localparam REQ_GEN_STS_IDLE = 3'b000; // 状态: 空闲
	localparam REQ_GEN_STS_FMBUF_RST = 3'b001; // 状态: 重置特征图缓存
	localparam REQ_GEN_STS_CRDNT_CVT = 3'b010; // 状态: 启动坐标转换
	localparam REQ_GEN_STS_SEND_INFO = 3'b011; // 状态: 发送特征图切块信息
	localparam REQ_GEN_STS_CAL_ADDR = 3'b100; // 状态: 地址计算
	localparam REQ_GEN_STS_SEND_REQ = 3'b101; // 状态: 发送请求
	localparam REQ_GEN_STS_UPD_CNT = 3'b110; // 状态: 更新计数器
	localparam REQ_GEN_STS_DONE = 3'b111; // 状态: 完成
	// 地址计算子阶段(状态编码)
	localparam integer CAL_ADDR_SUB_STS_ONEHOT_GET_CRDNT = 0; // 从坐标缓存取得当前表面行的坐标信息
	localparam integer CAL_ADDR_SUB_STS_ONEHOT_START_CAL = 1; // 开始计算地址
	localparam integer CAL_ADDR_SUB_STS_ONEHOT_WAIT_CAL = 2; // 等待地址计算完成
	
	/** 内部配置 **/
	localparam MUL0_TID_CONST = 4'd1; // (共享)无符号乘法器#0操作ID
	localparam MUL1_TID_CONST = 4'd2; // (共享)无符号乘法器#1操作ID
	
	/** AXIS寄存器片 **/
	wire[103:0] s_fm_rd_req_reg_axis_data;
	wire s_fm_rd_req_reg_axis_valid;
	wire s_fm_rd_req_reg_axis_ready;
	wire[103:0] m_fm_rd_req_reg_axis_data;
	wire m_fm_rd_req_reg_axis_valid;
	wire m_fm_rd_req_reg_axis_ready;
	
	assign m_fm_rd_req_axis_data = m_fm_rd_req_reg_axis_data;
	assign m_fm_rd_req_axis_valid = m_fm_rd_req_reg_axis_valid;
	assign m_fm_rd_req_reg_axis_ready = m_fm_rd_req_axis_ready;
	
	axis_reg_slice #(
		.data_width(104),
		.user_width(1),
		.forward_registered(EN_REG_SLICE_IN_RD_REQ),
		.back_registered("false"),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)fm_rd_req_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s_fm_rd_req_reg_axis_data),
		.s_axis_keep(13'bx_xxxx_xxxx_xxxx),
		.s_axis_user(1'bx),
		.s_axis_last(1'bx),
		.s_axis_valid(s_fm_rd_req_reg_axis_valid),
		.s_axis_ready(s_fm_rd_req_reg_axis_ready),
		
		.m_axis_data(m_fm_rd_req_reg_axis_data),
		.m_axis_keep(),
		.m_axis_user(),
		.m_axis_last(),
		.m_axis_valid(m_fm_rd_req_reg_axis_valid),
		.m_axis_ready(m_fm_rd_req_reg_axis_ready)
	);
	
	/** 补充运行时参数 **/
	reg[2:0] extra_params_init_stage; // 补充运行时参数(初始化阶段码)
	reg[15:0] actual_ifmap_w; // 输入特征图宽度
	reg[23:0] actual_ifmap_size; // 输入特征图大小
	wire[15:0] chn_n_of_fmap_region_that_kernal_set_sel; // 核组所选定特征图域的通道数
	reg[5:0] sfc_depth_of_last_fmap_cake_cgrp; // 特征图切块最后1个通道组的表面深度
	reg[15:0] cgrp_n_of_fmap_region_that_kernal_set_sel_r; // 核组所选定特征图域的通道组数 - 1
	reg[11:0] mask_for_cgrpid_at_actual_rid; // 实际表面行号中的通道组号(占用掩码)
	wire[11:0] mask_for_phy_y_at_actual_rid; // 实际表面行号中的物理y坐标(占用掩码)
	wire[11:0] mask_for_phy_y_at_actual_rid_rvs; // 实际表面行号中的物理y坐标(倒转占用掩码)
	/****
	参数: 特征图切块最后1个通道组的行数据量
	使用(共享)无符号乘法器#0计算
	****/
	reg req_for_cal_row_data_size_of_last_fmap_cake_cgrp; // 请求计算特征图切块最后1个通道组的行数据量(标志)
	reg[23:0] row_data_size_of_last_fmap_cake_cgrp; // 特征图切块最后1个通道组的行数据量
	reg row_data_size_of_last_fmap_cake_cgrp_available; // 特征图切块最后1个通道组的行数据量(参数可用标志)
	
	assign cgrp_n_of_fmap_region_that_kernal_set_sel = cgrp_n_of_fmap_region_that_kernal_set_sel_r;
	
	// 计算: 特征图切块最后1个通道组的行数据量 = 特征图切块最后1个通道组的表面深度(u6) * 输入特征图宽度(u16) * 每个数据的字节数(1或2)
	assign mul0_op_a = 
		is_16bit_data ? 
			{9'd0, sfc_depth_of_last_fmap_cake_cgrp, 1'b0}:
			{10'd0, sfc_depth_of_last_fmap_cake_cgrp};
	assign mul0_op_b = actual_ifmap_w;
	assign mul0_tid = MUL0_TID_CONST;
	assign mul0_req = req_for_cal_row_data_size_of_last_fmap_cake_cgrp;
	
	assign chn_n_of_fmap_region_that_kernal_set_sel = (is_grp_conv_mode ? n_foreach_group:fmap_chn_n) + 1'b1;
	assign mask_for_phy_y_at_actual_rid = ~mask_for_cgrpid_at_actual_rid;
	assign mask_for_phy_y_at_actual_rid_rvs = {
		mask_for_phy_y_at_actual_rid[0], mask_for_phy_y_at_actual_rid[1], mask_for_phy_y_at_actual_rid[2],
		mask_for_phy_y_at_actual_rid[3], mask_for_phy_y_at_actual_rid[4], mask_for_phy_y_at_actual_rid[5],
		mask_for_phy_y_at_actual_rid[6], mask_for_phy_y_at_actual_rid[7], mask_for_phy_y_at_actual_rid[8],
		mask_for_phy_y_at_actual_rid[9], mask_for_phy_y_at_actual_rid[10], mask_for_phy_y_at_actual_rid[11]
	};
	
	// 补充运行时参数(初始化阶段码)
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | (~extra_params_init_stage[2])))
			extra_params_init_stage <= # SIM_DELAY 
				blk_idle ? 
					3'b001:
					{extra_params_init_stage[1:0], 1'b0};
	end
	
	// 输入特征图宽度
	always @(posedge aclk)
	begin
		if(aclken & blk_start & blk_idle)
			actual_ifmap_w <= # SIM_DELAY ifmap_w + 1'b1;
	end
	
	// 输入特征图大小
	always @(posedge aclk)
	begin
		if(aclken & blk_start & blk_idle)
			actual_ifmap_size <= # SIM_DELAY ifmap_size + 1'b1;
	end
	
	// 特征图切块最后1个通道组的表面深度
	always @(posedge aclk)
	begin
		if(aclken & blk_start & blk_idle)
			sfc_depth_of_last_fmap_cake_cgrp <= # SIM_DELAY 
				((ATOMIC_C != 1) & (|chn_n_of_fmap_region_that_kernal_set_sel[clogb2(ATOMIC_C-1):0])) ? 
					chn_n_of_fmap_region_that_kernal_set_sel[clogb2(ATOMIC_C-1):0]:
					ATOMIC_C;
	end
	
	// 核组所选定特征图域的通道组数 - 1
	always @(posedge aclk)
	begin
		if(aclken & blk_start & blk_idle)
			cgrp_n_of_fmap_region_that_kernal_set_sel_r <= # SIM_DELAY 
				chn_n_of_fmap_region_that_kernal_set_sel[15:clogb2(ATOMIC_C)] - 
				(
					((ATOMIC_C != 1) & (|chn_n_of_fmap_region_that_kernal_set_sel[clogb2(ATOMIC_C-1):0])) ? 
						0:
						1
				);
	end
	
	// 实际表面行号中的通道组号(占用掩码)
	always @(posedge aclk)
	begin
		if(aclken & extra_params_init_stage[1])
			mask_for_cgrpid_at_actual_rid <= # SIM_DELAY 
				{
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:11],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:10],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:9],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:8],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:7],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:6],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:5],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:4],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:3],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:2],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:1],
					|cgrp_n_of_fmap_region_that_kernal_set_sel_r[15:0]
				};
	end
	
	// 请求计算特征图切块最后1个通道组的行数据量(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			req_for_cal_row_data_size_of_last_fmap_cake_cgrp <= 1'b0;
		else if(
			req_for_cal_row_data_size_of_last_fmap_cake_cgrp ? 
				mul0_grant:
				(aclken & blk_start & blk_idle)
		)
			req_for_cal_row_data_size_of_last_fmap_cake_cgrp <= # SIM_DELAY ~req_for_cal_row_data_size_of_last_fmap_cake_cgrp;
	end
	
	// 特征图切块最后1个通道组的行数据量
	always @(posedge aclk)
	begin
		if(mul0_ovld & (mul0_oid == MUL0_TID_CONST))
			row_data_size_of_last_fmap_cake_cgrp <= # SIM_DELAY mul0_res[23:0];
	end
	
	// 特征图切块最后1个通道组的行数据量(参数可用标志)
	always @(posedge aclk)
	begin
		if(
			blk_idle | 
			(
				row_data_size_of_last_fmap_cake_cgrp_available ? 
					(aclken & blk_done):
					(mul0_ovld & (mul0_oid == MUL0_TID_CONST))
			)
		)
			row_data_size_of_last_fmap_cake_cgrp_available <= # SIM_DELAY 
				(~blk_idle) & (~row_data_size_of_last_fmap_cake_cgrp_available);
	end
	
	/** 特征图表面行访问计数器 **/
	reg[3:0] row_repeat_cnt; // 行重复(计数器)
	wire last_row_repeat_flag; // 最后1次行重复(标志)
	reg[4:0] ext_fmap_kernal_dy; // 扩展特征图核偏移y坐标
	reg[3:0] kernal_mixed_zone_cnt; // 卷积核混合带计数器
	wire last_kernal_row_flag; // 处于卷积核的最后1行(标志)
	reg[15:0] cgrpn_cnt; // 通道组号(计数器)
	wire last_fmap_cake_cgrp_flag; // 处于特征图切块的最后1个通道组(标志)
	reg[15:0] ext_fmap_anchor_y; // 扩展特征图锚点y坐标
	reg[15:0] ofmap_y; // 输出特征图y坐标
	wire arrive_ext_fmap_bottom_flag; // 抵达扩展特征图底部(标志)
	reg[15:0] kernal_set_cnt; // 核组编号(计数器)
	wire last_kernal_set; // 处于最后1个核组(标志)
	wire on_upd_row_access_cnt; // 更新行访问计数器(指示)
	wire to_skip_row; // 跳过当前行(标志)
	
	assign last_row_repeat_flag = (row_repeat_cnt == kernal_w) | to_skip_row;
	assign last_kernal_row_flag = ext_fmap_kernal_dy == kernal_h_dilated;
	assign last_fmap_cake_cgrp_flag = cgrpn_cnt == cgrp_n_of_fmap_region_that_kernal_set_sel_r;
	assign arrive_ext_fmap_bottom_flag = ofmap_y == ofmap_h;
	assign last_kernal_set = kernal_set_cnt == kernal_set_n;
	
	// 行重复(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | on_upd_row_access_cnt)
		)
			row_repeat_cnt <= # SIM_DELAY 
				(blk_idle | last_row_repeat_flag) ? 
					4'd0:
					(row_repeat_cnt + 1'b1);
	end
	
	// 扩展特征图核偏移y坐标
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | (on_upd_row_access_cnt & last_row_repeat_flag))
		)
			ext_fmap_kernal_dy <= # SIM_DELAY 
				(blk_idle | last_kernal_row_flag) ? 
					5'd0:
					(ext_fmap_kernal_dy + kernal_dilation_vtc_n + 1'b1);
	end
	
	// 卷积核混合带计数器
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | (on_upd_row_access_cnt & last_row_repeat_flag))
		)
			kernal_mixed_zone_cnt <= # SIM_DELAY 
				(blk_idle | last_kernal_row_flag) ? 
					4'd0:
					(kernal_mixed_zone_cnt + 1'b1);
	end
	
	// 通道组号(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | (on_upd_row_access_cnt & last_row_repeat_flag & last_kernal_row_flag))
		)
			cgrpn_cnt <= # SIM_DELAY 
				(blk_idle | last_fmap_cake_cgrp_flag) ? 
					16'd0:
					(cgrpn_cnt + 1'b1);
	end
	
	// 扩展特征图锚点y坐标
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | (on_upd_row_access_cnt & last_row_repeat_flag & last_kernal_row_flag & last_fmap_cake_cgrp_flag))
		)
			ext_fmap_anchor_y <= # SIM_DELAY 
				(blk_idle | arrive_ext_fmap_bottom_flag) ? 
					16'd0:
					(ext_fmap_anchor_y + conv_vertical_stride + 1'b1);
	end
	
	// 输出特征图y坐标
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | (on_upd_row_access_cnt & last_row_repeat_flag & last_kernal_row_flag & last_fmap_cake_cgrp_flag))
		)
			ofmap_y <= # SIM_DELAY 
				(blk_idle | arrive_ext_fmap_bottom_flag) ? 
					16'd0:
					(ofmap_y + 1'b1);
	end
	
	// 核组编号(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				blk_idle | 
				(
					on_upd_row_access_cnt & last_row_repeat_flag & last_kernal_row_flag & last_fmap_cake_cgrp_flag & 
					arrive_ext_fmap_bottom_flag
				)
			)
		)
			kernal_set_cnt <= # SIM_DELAY 
				(blk_idle | last_kernal_set) ? 
					16'd0:
					(kernal_set_cnt + 1'b1);
	end
	
	/** 扩展特征图 **/
	// [坐标转换控制]
	reg on_start_coordinate_cvt_in_cake; // 启动切块内坐标转换(指示)
	reg on_done_coordinate_cvt_in_cake; // 完成切块内坐标转换(指示)
	reg[4:0] coordinate_cvt_dy_in_cake; // 切块内行偏移量
	// [坐标转换单元]
	reg ext_fmap_coordinate_cvt_blk_start;
	wire ext_fmap_coordinate_cvt_blk_idle;
	wire[15:0] ext_fmap_coordinate_cvt_blk_i_logic_y; // 逻辑y坐标
	wire ext_fmap_coordinate_cvt_blk_done;
	wire[15:0] ext_fmap_coordinate_cvt_blk_o_phy_y; // 物理y坐标
	wire ext_fmap_coordinate_cvt_blk_o_is_vld; // 坐标点是否有效
	// [坐标缓存]
	reg coordinate_buf_mask[0:10]; // 坐标缓存行掩码
	reg[15:0] coordinate_buf_phy_y[0:10]; // 坐标缓存物理y坐标
	reg[3:0] coordinate_buf_wptr; // 坐标缓存写指针
	wire on_rst_coordinate_buf; // 复位坐标缓存(指示)
	reg[11:0] max_vld_row_phy_y; // 有效表面行物理y坐标(最大值)
	reg[11:0] min_vld_row_phy_y; // 有效表面行物理y坐标(最小值)
	reg[3:0] vld_phy_row_n; // 有效表面行总数
	
	assign ext_fmap_coordinate_cvt_blk_i_logic_y = ext_fmap_anchor_y + coordinate_cvt_dy_in_cake;
	
	// 完成切块内坐标转换(指示)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				blk_idle | on_done_coordinate_cvt_in_cake | 
				(ext_fmap_coordinate_cvt_blk_start & ext_fmap_coordinate_cvt_blk_done & (coordinate_cvt_dy_in_cake == kernal_h_dilated))
			)
		)
			on_done_coordinate_cvt_in_cake <= # SIM_DELAY ~(blk_idle | on_done_coordinate_cvt_in_cake);
	end
	
	// 切块内行偏移量
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | (ext_fmap_coordinate_cvt_blk_start & ext_fmap_coordinate_cvt_blk_done))
		)
			coordinate_cvt_dy_in_cake <= # SIM_DELAY 
				(blk_idle | (coordinate_cvt_dy_in_cake == kernal_h_dilated)) ? 
					5'd0:
					(coordinate_cvt_dy_in_cake + kernal_dilation_vtc_n + 1'b1);
	end
	
	// 坐标转换单元(start信号)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ext_fmap_coordinate_cvt_blk_start <= 1'b0;
		else if(
			aclken & 
			(
				blk_idle | 
				(
					ext_fmap_coordinate_cvt_blk_start ? 
						(ext_fmap_coordinate_cvt_blk_done & (coordinate_cvt_dy_in_cake == kernal_h_dilated)):
						(on_start_coordinate_cvt_in_cake & ext_fmap_coordinate_cvt_blk_idle)
				)
			)
		)
			ext_fmap_coordinate_cvt_blk_start <= # SIM_DELAY 
				(~blk_idle) & (~ext_fmap_coordinate_cvt_blk_start);
	end
	
	// 坐标缓存写指针
	always @(posedge aclk)
	begin
		if(aclken & (on_rst_coordinate_buf | (ext_fmap_coordinate_cvt_blk_start & ext_fmap_coordinate_cvt_blk_done)))
			coordinate_buf_wptr <= # SIM_DELAY 
				on_rst_coordinate_buf ? 
					4'd0:
					(coordinate_buf_wptr + 1'b1);
	end
	
	// 坐标缓存(行掩码, 物理y坐标)
	genvar crdnt_buf_i;
	generate
		for(crdnt_buf_i = 0;crdnt_buf_i < 11;crdnt_buf_i = crdnt_buf_i + 1)
		begin:crdnt_buf_blk
			always @(posedge aclk)
			begin
				if(
					aclken & (~on_rst_coordinate_buf) & 
					ext_fmap_coordinate_cvt_blk_start & ext_fmap_coordinate_cvt_blk_done & (coordinate_buf_wptr == crdnt_buf_i)
				)
				begin
					coordinate_buf_mask[crdnt_buf_i] <= # SIM_DELAY ~ext_fmap_coordinate_cvt_blk_o_is_vld;
					coordinate_buf_phy_y[crdnt_buf_i] <= # SIM_DELAY ext_fmap_coordinate_cvt_blk_o_phy_y;
				end
			end
		end
	endgenerate
	
	// 有效表面行物理y坐标(最大值)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				ext_fmap_coordinate_cvt_blk_start ? 
					(
						ext_fmap_coordinate_cvt_blk_done & 
						ext_fmap_coordinate_cvt_blk_o_is_vld & 
						(ext_fmap_coordinate_cvt_blk_o_phy_y[11:0] > max_vld_row_phy_y)
					):
					(on_start_coordinate_cvt_in_cake & ext_fmap_coordinate_cvt_blk_idle)
			)
		)
			max_vld_row_phy_y <= # SIM_DELAY 
				ext_fmap_coordinate_cvt_blk_start ? 
					ext_fmap_coordinate_cvt_blk_o_phy_y[11:0]:
					12'd0;
	end
	
	// 有效表面行物理y坐标(最小值)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				ext_fmap_coordinate_cvt_blk_start ? 
					(
						ext_fmap_coordinate_cvt_blk_done & 
						ext_fmap_coordinate_cvt_blk_o_is_vld & 
						(ext_fmap_coordinate_cvt_blk_o_phy_y[11:0] < min_vld_row_phy_y)
					):
					(on_start_coordinate_cvt_in_cake & ext_fmap_coordinate_cvt_blk_idle)
			)
		)
			min_vld_row_phy_y <= # SIM_DELAY 
				ext_fmap_coordinate_cvt_blk_start ? 
					ext_fmap_coordinate_cvt_blk_o_phy_y[11:0]:
					12'hfff;
	end
	
	// 有效表面行总数
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				ext_fmap_coordinate_cvt_blk_start ? 
					(ext_fmap_coordinate_cvt_blk_done & ext_fmap_coordinate_cvt_blk_o_is_vld):
					(on_start_coordinate_cvt_in_cake & ext_fmap_coordinate_cvt_blk_idle)
			)
		)
			vld_phy_row_n <= # SIM_DELAY 
				ext_fmap_coordinate_cvt_blk_start ? 
					(vld_phy_row_n + 1'b1):
					4'd0;
	end
	
	surface_pos_logic_to_phy #(
		.SIM_DELAY(SIM_DELAY)
	)ext_fmap_y_converter(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.ext_j_right(16'hxxxx),
		.ext_i_bottom(ext_i_bottom),
		.external_padding_left(3'bxxx),
		.external_padding_top(external_padding_top),
		.inner_padding_top_bottom(inner_padding_top_bottom),
		.inner_padding_left_right(3'bxxx),
		
		.blk_start(ext_fmap_coordinate_cvt_blk_start),
		.blk_idle(ext_fmap_coordinate_cvt_blk_idle),
		.blk_i_logic_x(16'hxxxx),
		.blk_i_logic_y(ext_fmap_coordinate_cvt_blk_i_logic_y),
		.blk_i_en_x_cvt(1'b0),
		.blk_i_en_y_cvt(1'b1),
		.blk_done(ext_fmap_coordinate_cvt_blk_done),
		.blk_o_phy_x(),
		.blk_o_phy_y(ext_fmap_coordinate_cvt_blk_o_phy_y),
		.blk_o_is_vld(ext_fmap_coordinate_cvt_blk_o_is_vld)
	);
	
	/** 特征图切片属性 **/
	wire[5:0] sfc_depth_of_cur_fmap_slice; // 当前特征图切片的表面深度
	wire[23:0] row_data_size_of_cur_fmap_slice; // 当前特征图切片的行数据量
	wire row_data_size_of_cur_fmap_slice_available; // 当前特征图切片的行数据量(参数可用标志)
	
	assign sfc_depth_of_cur_fmap_slice = 
		last_fmap_cake_cgrp_flag ? 
			sfc_depth_of_last_fmap_cake_cgrp:
			ATOMIC_C;
	assign row_data_size_of_cur_fmap_slice = 
		last_fmap_cake_cgrp_flag ? 
			row_data_size_of_last_fmap_cake_cgrp:
			(
				(
					is_16bit_data ? 
						{actual_ifmap_w, 1'b0}:
						actual_ifmap_w
				) * ATOMIC_C
			);
	
	assign row_data_size_of_cur_fmap_slice_available = 
		(~last_fmap_cake_cgrp_flag) | row_data_size_of_last_fmap_cake_cgrp_available;
	
	/** 特征图表面行访问地址 **/
	reg[31:0] baseaddr_of_fmap_region_that_kernal_set_sel; // 核组所选定特征图域的基地址
	reg[31:0] cgrp_ofs_addr; // 通道组偏移地址
	reg[31:0] sfc_row_abs_addr; // 表面行绝对地址
	reg sfc_row_abs_addr_upd_stage; // 表面行绝对地址(更新阶段)
	
	// 核组所选定特征图域的基地址
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				(blk_start & blk_idle) | 
				(
					is_grp_conv_mode & 
					on_upd_row_access_cnt & last_row_repeat_flag & last_kernal_row_flag & last_fmap_cake_cgrp_flag & 
					arrive_ext_fmap_bottom_flag
				)
			)
		)
			baseaddr_of_fmap_region_that_kernal_set_sel <= # SIM_DELAY 
				(blk_start & blk_idle) ? 
					fmap_baseaddr:
					(baseaddr_of_fmap_region_that_kernal_set_sel + data_size_foreach_group);
	end
	
	// 通道组偏移地址
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				(blk_start & blk_idle) | 
				(on_upd_row_access_cnt & last_row_repeat_flag & last_kernal_row_flag)
			)
		)
			cgrp_ofs_addr <= # SIM_DELAY 
				((blk_start & blk_idle) | last_fmap_cake_cgrp_flag) ? 
					32'h0000_0000:
					(
						cgrp_ofs_addr + 
						(actual_ifmap_size * ATOMIC_C * (is_16bit_data ? 2:1)) // 此时不处于最后1个通道组
					);
	end
	
	// 表面行绝对地址
	// 计算: 表面行绝对地址 = 表面行偏移地址 + 核组所选定特征图域的基地址 + 通道组偏移地址
	always @(posedge aclk)
	begin
		if(
			sfc_row_abs_addr_upd_stage ? 
				aclken:
				(mul1_ovld & (mul1_oid == MUL1_TID_CONST))
		)
			sfc_row_abs_addr <= # SIM_DELAY 
				(
					sfc_row_abs_addr_upd_stage ? 
						sfc_row_abs_addr:
						mul1_res[31:0]
				) + 
				(
					sfc_row_abs_addr_upd_stage ? 
						cgrp_ofs_addr:
						baseaddr_of_fmap_region_that_kernal_set_sel
				);
	end
	
	// 表面行绝对地址(更新阶段)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			sfc_row_abs_addr_upd_stage <= 1'b0;
		else if(
			sfc_row_abs_addr_upd_stage ? 
				aclken:
				(mul1_ovld & (mul1_oid == MUL1_TID_CONST))
		)
			sfc_row_abs_addr_upd_stage <= # SIM_DELAY ~sfc_row_abs_addr_upd_stage;
	end
	
	/** 访问请求生成控制 **/
	wire on_start_cal_sfc_row_ofs_addr; // 开始计算表面行偏移地址(指示)
	reg req_for_cal_sfc_row_ofs_addr_pending; // 请求计算表面行偏移地址(等待标志)
	reg[2:0] req_gen_sts; // 访问请求生成状态
	reg to_fns_req_gen; // 准备结束访问请求生成(标志)
	reg rst_buf_because_phy_y_reofs; // 因物理y坐标重偏移而重置缓存(标志)
	reg[2:0] cal_addr_sub_sts; // 地址计算子状态
	reg cur_sfc_row_mask; // 当前表面行掩码
	reg[15:0] cur_sfc_row_phy_y; // 当前表面行物理y坐标
	reg[11:0] phy_y_encoding_at_actual_rid; // 当前表面行实际表面行号中物理y坐标的编码
	wire[11:0] phy_y_encoding_at_actual_rid_rvs; // 当前表面行实际表面行号中物理y坐标的倒转编码
	reg[11:0] phy_y_encoding_ofs_at_actual_rid; // 实际表面行号中物理y坐标的编码偏移
	wire phy_y_encoding_at_actual_rid_exceeded; // 当前表面行实际表面行号中物理y坐标的编码超过范围(标志)
	reg to_send_fm_cake_info; // 正在发送特征图切块信息(标志)
	reg blk_idle_r; // 块级空闲(标志)
	reg blk_done_r; // 块级完成(指示)
	
	assign blk_idle = blk_idle_r;
	assign blk_done = blk_done_r;
	
	assign s_fm_rd_req_reg_axis_data[4:0] = (sfc_depth_of_cur_fmap_slice - 1) & 6'b011111; // 每个表面的有效数据个数 - 1
	assign s_fm_rd_req_reg_axis_data[28:5] = row_data_size_of_cur_fmap_slice; // 表面行有效字节数
	assign s_fm_rd_req_reg_axis_data[60:29] = sfc_row_abs_addr; // 表面行基地址
	assign s_fm_rd_req_reg_axis_data[72:61] = ifmap_w[11:0]; // 待读取的表面个数 - 1
	assign s_fm_rd_req_reg_axis_data[84:73] = 12'd0; // 起始表面编号
	assign s_fm_rd_req_reg_axis_data[96:85] = 
		phy_y_encoding_at_actual_rid_rvs | cgrpn_cnt[11:0]; // 实际表面行号
	assign s_fm_rd_req_reg_axis_data[97] = req_gen_sts == REQ_GEN_STS_FMBUF_RST; // 是否重置缓存
	assign s_fm_rd_req_reg_axis_data[103:98] = 6'b000000;
	
	assign s_fm_rd_req_reg_axis_valid = 
		aclken & 
		((req_gen_sts == REQ_GEN_STS_FMBUF_RST) | (req_gen_sts == REQ_GEN_STS_SEND_REQ));
	
	assign m_fm_cake_info_axis_data[7:4] = 4'b0000;
	assign m_fm_cake_info_axis_data[3:0] = vld_phy_row_n;
	
	assign m_fm_cake_info_axis_valid = aclken & to_send_fm_cake_info;
	
	// 计算: 表面行偏移地址 = 物理y坐标(u16) * 当前特征图切片的行数据量(u24)
	assign mul1_op_a = cur_sfc_row_phy_y;
	assign mul1_op_b = row_data_size_of_cur_fmap_slice;
	assign mul1_tid = MUL1_TID_CONST;
	assign mul1_req = (aclken & on_start_cal_sfc_row_ofs_addr) | req_for_cal_sfc_row_ofs_addr_pending;
	
	assign on_upd_row_access_cnt = aclken & (req_gen_sts == REQ_GEN_STS_UPD_CNT);
	assign to_skip_row = cur_sfc_row_mask;
	assign on_rst_coordinate_buf = 
		blk_idle | 
		(on_start_coordinate_cvt_in_cake & ext_fmap_coordinate_cvt_blk_idle);
	
	assign on_start_cal_sfc_row_ofs_addr = 
		aclken & 
		(req_gen_sts == REQ_GEN_STS_CAL_ADDR) & cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_START_CAL] & 
		(~cur_sfc_row_mask) & row_data_size_of_cur_fmap_slice_available;
	assign phy_y_encoding_at_actual_rid_rvs = {
		phy_y_encoding_at_actual_rid[0], phy_y_encoding_at_actual_rid[1], phy_y_encoding_at_actual_rid[2],
		phy_y_encoding_at_actual_rid[3], phy_y_encoding_at_actual_rid[4], phy_y_encoding_at_actual_rid[5],
		phy_y_encoding_at_actual_rid[6], phy_y_encoding_at_actual_rid[7], phy_y_encoding_at_actual_rid[8],
		phy_y_encoding_at_actual_rid[9], phy_y_encoding_at_actual_rid[10], phy_y_encoding_at_actual_rid[11]
	};
	assign phy_y_encoding_at_actual_rid_exceeded = 
		|((max_vld_row_phy_y - phy_y_encoding_ofs_at_actual_rid) & (~mask_for_phy_y_at_actual_rid_rvs));
	
	// 启动切块内坐标转换(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_start_coordinate_cvt_in_cake <= 1'b0;
		else if(
			blk_idle | 
			on_start_coordinate_cvt_in_cake | 
			(
				(
					(req_gen_sts == REQ_GEN_STS_FMBUF_RST) & 
					s_fm_rd_req_reg_axis_valid & s_fm_rd_req_reg_axis_ready & (~to_fns_req_gen)
				) | 
				(
					(req_gen_sts == REQ_GEN_STS_UPD_CNT) & 
					last_row_repeat_flag & last_kernal_row_flag & last_fmap_cake_cgrp_flag & (~arrive_ext_fmap_bottom_flag)
				)
			)
		)
			on_start_coordinate_cvt_in_cake <= # SIM_DELAY ~(blk_idle | on_start_coordinate_cvt_in_cake);
	end
	
	// 请求计算表面行偏移地址(等待标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			req_for_cal_sfc_row_ofs_addr_pending <= 1'b0;
		else if(
			req_for_cal_sfc_row_ofs_addr_pending ? 
				mul1_grant:
				(aclken & on_start_cal_sfc_row_ofs_addr & (~mul1_grant))
		)
			req_for_cal_sfc_row_ofs_addr_pending <= # SIM_DELAY ~req_for_cal_sfc_row_ofs_addr_pending;
	end
	
	// 访问请求生成状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			req_gen_sts <= REQ_GEN_STS_IDLE;
		else if(aclken)
		begin
			case(req_gen_sts)
				REQ_GEN_STS_IDLE: // 状态: 空闲
					if(blk_start)
						req_gen_sts <= # SIM_DELAY REQ_GEN_STS_FMBUF_RST;
				REQ_GEN_STS_FMBUF_RST: // 状态: 重置特征图缓存
					if(s_fm_rd_req_reg_axis_valid & s_fm_rd_req_reg_axis_ready)
						req_gen_sts <= # SIM_DELAY 
							({3{to_fns_req_gen}} & REQ_GEN_STS_DONE) | 
							({3{rst_buf_because_phy_y_reofs}} & REQ_GEN_STS_SEND_INFO) | 
							({3{~(to_fns_req_gen | rst_buf_because_phy_y_reofs)}} & REQ_GEN_STS_CRDNT_CVT);
				REQ_GEN_STS_CRDNT_CVT: // 状态: 启动坐标转换
					if(on_done_coordinate_cvt_in_cake)
						req_gen_sts <= # SIM_DELAY 
							phy_y_encoding_at_actual_rid_exceeded ? 
								REQ_GEN_STS_FMBUF_RST:
								REQ_GEN_STS_SEND_INFO;
				REQ_GEN_STS_SEND_INFO: // 状态: 发送特征图切块信息
					if(m_fm_cake_info_axis_valid & m_fm_cake_info_axis_ready)
						req_gen_sts <= # SIM_DELAY REQ_GEN_STS_CAL_ADDR;
				REQ_GEN_STS_CAL_ADDR: // 状态: 地址计算
					if(
						(cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_START_CAL] & cur_sfc_row_mask) | 
						(cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_WAIT_CAL] & sfc_row_abs_addr_upd_stage)
					)
						req_gen_sts <= # SIM_DELAY 
							cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_WAIT_CAL] ? 
								REQ_GEN_STS_SEND_REQ:
								REQ_GEN_STS_UPD_CNT;
				REQ_GEN_STS_SEND_REQ: // 状态: 发送请求
					if(s_fm_rd_req_reg_axis_valid & s_fm_rd_req_reg_axis_ready)
						req_gen_sts <= # SIM_DELAY REQ_GEN_STS_UPD_CNT;
				REQ_GEN_STS_UPD_CNT: // 状态: 更新计数器
					req_gen_sts <= # SIM_DELAY 
						last_row_repeat_flag ? 
							(
								(last_kernal_row_flag & last_fmap_cake_cgrp_flag) ? 
									(
										arrive_ext_fmap_bottom_flag ? 
											REQ_GEN_STS_FMBUF_RST:
											REQ_GEN_STS_CRDNT_CVT
									):
									REQ_GEN_STS_CAL_ADDR
							):
							REQ_GEN_STS_SEND_REQ;
				REQ_GEN_STS_DONE: // 状态: 完成
					req_gen_sts <= # SIM_DELAY REQ_GEN_STS_IDLE;
				default:
					req_gen_sts <= # SIM_DELAY REQ_GEN_STS_IDLE;
			endcase
		end
	end
	
	// 准备结束访问请求生成(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				((req_gen_sts == REQ_GEN_STS_IDLE) & blk_start) | 
				((req_gen_sts == REQ_GEN_STS_CRDNT_CVT) & on_done_coordinate_cvt_in_cake & phy_y_encoding_at_actual_rid_exceeded) | 
				(
					(req_gen_sts == REQ_GEN_STS_UPD_CNT) & 
					last_row_repeat_flag & last_kernal_row_flag & last_fmap_cake_cgrp_flag & arrive_ext_fmap_bottom_flag
				)
			)
		)
			to_fns_req_gen <= # SIM_DELAY (req_gen_sts == REQ_GEN_STS_UPD_CNT) & last_kernal_set;
	end
	
	// 因物理y坐标重偏移而重置缓存(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				((req_gen_sts == REQ_GEN_STS_IDLE) & blk_start) | 
				((req_gen_sts == REQ_GEN_STS_CRDNT_CVT) & on_done_coordinate_cvt_in_cake & phy_y_encoding_at_actual_rid_exceeded) | 
				(
					(req_gen_sts == REQ_GEN_STS_UPD_CNT) & 
					last_row_repeat_flag & last_kernal_row_flag & last_fmap_cake_cgrp_flag & arrive_ext_fmap_bottom_flag
				)
			)
		)
			rst_buf_because_phy_y_reofs <= # SIM_DELAY req_gen_sts == REQ_GEN_STS_CRDNT_CVT;
	end
	
	// 地址计算子状态
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				blk_idle | 
				(
					(req_gen_sts == REQ_GEN_STS_CAL_ADDR) & 
					(
						cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_GET_CRDNT] | 
						(
							cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_START_CAL] & 
							(cur_sfc_row_mask | row_data_size_of_cur_fmap_slice_available)
						) | 
						(cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_WAIT_CAL] & sfc_row_abs_addr_upd_stage)
					)
				)
			)
		)
			cal_addr_sub_sts <= # SIM_DELAY 
				blk_idle ? 
					(1 << CAL_ADDR_SUB_STS_ONEHOT_GET_CRDNT):
					(
						(
							{3{cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_GET_CRDNT]}} & 
							(1 << CAL_ADDR_SUB_STS_ONEHOT_START_CAL)
						) | 
						(
							{3{cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_START_CAL]}} & 
							(
								cur_sfc_row_mask ? 
									(1 << CAL_ADDR_SUB_STS_ONEHOT_GET_CRDNT):
									(1 << CAL_ADDR_SUB_STS_ONEHOT_WAIT_CAL)
							)
						) | 
						(
							{3{cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_WAIT_CAL]}} & 
							(1 << CAL_ADDR_SUB_STS_ONEHOT_GET_CRDNT)
						)
					);
	end
	
	// 当前表面行坐标信息(当前表面行掩码, 当前表面行物理y坐标, 当前表面行实际表面行号中物理y坐标的编码)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(req_gen_sts == REQ_GEN_STS_CAL_ADDR) & 
			cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_GET_CRDNT]
		)
		begin
			cur_sfc_row_mask <= # SIM_DELAY coordinate_buf_mask[(kernal_mixed_zone_cnt > 4'd10) ? 4'd10:kernal_mixed_zone_cnt];
			cur_sfc_row_phy_y <= # SIM_DELAY coordinate_buf_phy_y[(kernal_mixed_zone_cnt > 4'd10) ? 4'd10:kernal_mixed_zone_cnt];
		end
	end
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(req_gen_sts == REQ_GEN_STS_CAL_ADDR) & 
			cal_addr_sub_sts[CAL_ADDR_SUB_STS_ONEHOT_WAIT_CAL] & 
			sfc_row_abs_addr_upd_stage
		)
			phy_y_encoding_at_actual_rid <= # SIM_DELAY cur_sfc_row_phy_y - phy_y_encoding_ofs_at_actual_rid;
	end
	
	// 实际表面行号中物理y坐标的编码偏移
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				((req_gen_sts == REQ_GEN_STS_FMBUF_RST) & (~rst_buf_because_phy_y_reofs)) | 
				(
					(req_gen_sts == REQ_GEN_STS_CRDNT_CVT) & 
					on_done_coordinate_cvt_in_cake & 
					phy_y_encoding_at_actual_rid_exceeded
				)
			)
		)
			phy_y_encoding_ofs_at_actual_rid <= # SIM_DELAY 
				(req_gen_sts == REQ_GEN_STS_FMBUF_RST) ? 
					12'd0:
					min_vld_row_phy_y;
	end
	
	// 正在发送特征图切块信息(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			to_send_fm_cake_info <= 1'b0;
		else if(
			aclken & 
			(
				to_send_fm_cake_info ? 
					m_fm_cake_info_axis_ready:
					(
						(
							(req_gen_sts == REQ_GEN_STS_FMBUF_RST) & 
							s_fm_rd_req_reg_axis_valid & s_fm_rd_req_reg_axis_ready & rst_buf_because_phy_y_reofs
						) | 
						(
							(req_gen_sts == REQ_GEN_STS_CRDNT_CVT) & 
							on_done_coordinate_cvt_in_cake & (~phy_y_encoding_at_actual_rid_exceeded)
						)
					)
			)
		)
			to_send_fm_cake_info <= # SIM_DELAY ~to_send_fm_cake_info;
	end
	
	// 块级空闲(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			blk_idle_r <= 1'b1;
		else if(
			aclken & 
			(blk_idle_r ? blk_start:blk_done)
		)
			blk_idle_r <= # SIM_DELAY ~blk_idle_r;
	end
	
	// 块级完成(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			blk_done_r <= 1'b0;
		else if(
			aclken & 
			(
				blk_done_r | 
				((req_gen_sts == REQ_GEN_STS_FMBUF_RST) & s_fm_rd_req_reg_axis_valid & s_fm_rd_req_reg_axis_ready & to_fns_req_gen)
			)
		)
			blk_done_r <= # SIM_DELAY ~blk_done_r;
	end
	
	/** 后级计算单元控制 **/
	// [物理特征图表面行适配器控制]
	reg on_incr_phy_row_traffic_r; // 增加1个物理特征图表面行流量(指示)
	
	assign rst_adapter = extra_params_init_stage[1];
	assign on_incr_phy_row_traffic = on_incr_phy_row_traffic_r;
	
	// 增加1个物理特征图表面行流量(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_incr_phy_row_traffic_r <= 1'b0;
		else if(
			on_incr_phy_row_traffic_r | 
			(
				aclken & 
				(req_gen_sts == REQ_GEN_STS_SEND_REQ) & s_fm_rd_req_reg_axis_valid & s_fm_rd_req_reg_axis_ready & (row_repeat_cnt == 4'd0)
			)
		)
			on_incr_phy_row_traffic_r <= # SIM_DELAY ~on_incr_phy_row_traffic_r;
	end
	
endmodule
