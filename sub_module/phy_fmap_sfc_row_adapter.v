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
本模块: 物理特征图表面行适配器

描述:
根据计算参数、特征图参数和卷积核参数, 使用光标法, 从物理特征图表面行(数据流)生成用于乘加阵列计算的表面行(数据流)

注意：
计算1层多通道卷积前, 必须先重置适配器(拉高rst_adapter)
增加物理特征图表面行流量(给出on_incr_phy_row_traffic脉冲)以许可(kernal_w+1)个表面行的计算

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/11/10
********************************************************************/


module phy_fmap_sfc_row_adapter #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter EN_ROW_AXIS_REG_SLICE = "true", // 是否在物理特征图表面行数据AXIS接口插入寄存器片
	parameter EN_MAC_ARRAY_AXIS_REG_SLICE = "true", // 是否在乘加阵列计算数据AXIS接口插入寄存器片
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 重置适配器
	input wire rst_adapter,
	
	// 运行时参数
	// [计算参数]
	input wire[2:0] conv_horizontal_stride, // 卷积水平步长 - 1
	// [特征图参数]
	input wire[2:0] external_padding_left, // 左部外填充数
	input wire[2:0] inner_padding_left_right, // 左右内填充数
	input wire[15:0] ifmap_w, // 输入特征图宽度 - 1
	input wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	// [卷积核参数]
	input wire[3:0] kernal_dilation_hzt_n, // 水平膨胀量
	input wire[3:0] kernal_w, // (膨胀前)卷积核宽度 - 1
	input wire[4:0] kernal_w_dilated, // (膨胀后)卷积核宽度 - 1
	
	// 特征图表面行流量
	input wire on_incr_phy_row_traffic, // 增加1个物理特征图表面行流量(指示)
	output wire[27:0] row_n_submitted_to_mac_array, // 已向乘加阵列提交的行数
	
	// 物理特征图表面行数据(AXIS从机)
	input wire[ATOMIC_C*2*8-1:0] s_fmap_row_axis_data,
	input wire s_fmap_row_axis_last, // 标志物理特征图行的最后1个表面
	input wire s_fmap_row_axis_valid,
	output wire s_fmap_row_axis_ready,
	
	// 乘加阵列计算数据(AXIS主机)
	output wire[ATOMIC_C*2*8-1:0] m_mac_array_axis_data,
	output wire m_mac_array_axis_last, // 卷积核参数对应的最后1个特征图表面(标志)
	output wire m_mac_array_axis_user, // 标志本表面全0
	output wire m_mac_array_axis_valid,
	input wire m_mac_array_axis_ready
);
	
	/** AXIS寄存器片 **/
	// [寄存器片#0]
	wire[ATOMIC_C*2*8-1:0] s_row_reg_axis_data;
	wire s_row_reg_axis_last;
	wire s_row_reg_axis_valid;
	wire s_row_reg_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m_row_reg_axis_data;
	wire m_row_reg_axis_last;
	wire m_row_reg_axis_valid;
	wire m_row_reg_axis_ready;
	// [寄存器片#1]
	wire[ATOMIC_C*2*8-1:0] s_mac_array_reg_axis_data;
	wire s_mac_array_reg_axis_last;
	wire s_mac_array_reg_axis_user;
	wire s_mac_array_reg_axis_valid;
	wire s_mac_array_reg_axis_ready;
	wire[ATOMIC_C*2*8-1:0] m_mac_array_reg_axis_data;
	wire m_mac_array_reg_axis_last;
	wire m_mac_array_reg_axis_user;
	wire m_mac_array_reg_axis_valid;
	wire m_mac_array_reg_axis_ready;
	
	assign s_row_reg_axis_data = s_fmap_row_axis_data;
	assign s_row_reg_axis_last = s_fmap_row_axis_last;
	assign s_row_reg_axis_valid = s_fmap_row_axis_valid;
	assign s_fmap_row_axis_ready = s_row_reg_axis_ready;
	
	assign m_mac_array_axis_data = m_mac_array_reg_axis_data;
	assign m_mac_array_axis_last = m_mac_array_reg_axis_last;
	assign m_mac_array_axis_user = m_mac_array_reg_axis_user;
	assign m_mac_array_axis_valid = m_mac_array_reg_axis_valid;
	assign m_mac_array_reg_axis_ready = m_mac_array_axis_ready;
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(1),
		.forward_registered("false"),
		.back_registered(EN_ROW_AXIS_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)row_reg_axis_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s_row_reg_axis_data),
		.s_axis_keep({(ATOMIC_C*2){1'bx}}),
		.s_axis_user(1'bx),
		.s_axis_last(s_row_reg_axis_last),
		.s_axis_valid(s_row_reg_axis_valid),
		.s_axis_ready(s_row_reg_axis_ready),
		
		.m_axis_data(m_row_reg_axis_data),
		.m_axis_keep(),
		.m_axis_user(),
		.m_axis_last(m_row_reg_axis_last),
		.m_axis_valid(m_row_reg_axis_valid),
		.m_axis_ready(m_row_reg_axis_ready)
	);
	
	axis_reg_slice #(
		.data_width(ATOMIC_C*2*8),
		.user_width(1),
		.forward_registered(EN_MAC_ARRAY_AXIS_REG_SLICE),
		.back_registered("false"),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)mac_array_axis_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s_mac_array_reg_axis_data),
		.s_axis_keep({(ATOMIC_C*2){1'bx}}),
		.s_axis_user(s_mac_array_reg_axis_user),
		.s_axis_last(s_mac_array_reg_axis_last),
		.s_axis_valid(s_mac_array_reg_axis_valid),
		.s_axis_ready(s_mac_array_reg_axis_ready),
		
		.m_axis_data(m_mac_array_reg_axis_data),
		.m_axis_keep(),
		.m_axis_user(m_mac_array_reg_axis_user),
		.m_axis_last(m_mac_array_reg_axis_last),
		.m_axis_valid(m_mac_array_reg_axis_valid),
		.m_axis_ready(m_mac_array_reg_axis_ready)
	);
	
	/** 基准光标 **/
	reg signed[15:0] logic_x_to_cvt; // 待转换的逻辑x坐标(计数器)
	reg[15:0] cursor_phy_x; // 光标所处的物理x坐标
	reg[2:0] pos_at_padding_region_cnt; // 填充域内坐标(计数器)
	wire is_cursor_at_external_padding_region; // 光标处于外填充域(标志)
	reg is_cursor_at_inner_padding_region; // 光标处于内填充域(标志)
	reg cursor_exceeded_phy_row; // 光标已越过物理表面行(标志)
	reg cursor_exceeded_cal_region; // 光标已越过计算区(标志)
	wire on_moving_cursor_to_nxt_pt; // 移动光标到下一点(指示)
	wire to_rst_cursor; // 复位光标(标志)
	wire cursor_at_last_cal_sfc; // 光标位于最后1个待计算表面(标志)
	
	assign is_cursor_at_external_padding_region = (logic_x_to_cvt < 16'sd0) | cursor_exceeded_phy_row;
	
	// 待转换的逻辑x坐标(计数器)
	always @(posedge aclk)
	begin
		if(aclken & (rst_adapter | on_moving_cursor_to_nxt_pt))
			logic_x_to_cvt <= # SIM_DELAY 
				(rst_adapter | to_rst_cursor) ? 
					({13'b1_1111_1111_1111, ~external_padding_left} + 1'b1):
					(logic_x_to_cvt + 1'b1);
	end
	
	// 光标所处的物理x坐标
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				rst_adapter | 
				(
					on_moving_cursor_to_nxt_pt & 
					(
						to_rst_cursor | 
						(
							(~is_cursor_at_external_padding_region) & 
							(cursor_phy_x != ifmap_w) & 
							(
								is_cursor_at_inner_padding_region ? 
									(pos_at_padding_region_cnt == inner_padding_left_right):
									(inner_padding_left_right == 3'b000)
							)
						)
					)
				)
			)
		)
			cursor_phy_x <= # SIM_DELAY 
				(rst_adapter | to_rst_cursor) ? 
					16'd0:
					(cursor_phy_x + 1'b1);
	end
	
	// 填充域内坐标(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				rst_adapter | 
				(on_moving_cursor_to_nxt_pt & (to_rst_cursor | is_cursor_at_inner_padding_region))
			)
		)
			pos_at_padding_region_cnt <= # SIM_DELAY 
				(rst_adapter | to_rst_cursor | (pos_at_padding_region_cnt == inner_padding_left_right)) ? 
					3'b001:
					(pos_at_padding_region_cnt + 1'b1);
	end
	
	// 光标处于内填充域(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				rst_adapter | 
				(
					on_moving_cursor_to_nxt_pt & 
					(
						to_rst_cursor | 
						(
							(~is_cursor_at_external_padding_region) & 
							(
								is_cursor_at_inner_padding_region ? 
									(pos_at_padding_region_cnt == inner_padding_left_right):
									((inner_padding_left_right != 3'b000) & (cursor_phy_x != ifmap_w))
							)
						)
					)
				)
			)
		)
			is_cursor_at_inner_padding_region <= # SIM_DELAY 
				(~rst_adapter) & (~to_rst_cursor) & (~is_cursor_at_inner_padding_region);
	end
	
	// 光标已越过物理表面行(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				rst_adapter | 
				(on_moving_cursor_to_nxt_pt & (to_rst_cursor | (~is_cursor_at_external_padding_region)))
			)
		)
			cursor_exceeded_phy_row <= # SIM_DELAY 
				(~rst_adapter) & (~to_rst_cursor) & 
				(cursor_phy_x == ifmap_w) & (~is_cursor_at_inner_padding_region);
	end
	
	// 光标已越过计算区(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				rst_adapter | 
				(on_moving_cursor_to_nxt_pt & (to_rst_cursor | (~cursor_exceeded_cal_region)))
			)
		)
			cursor_exceeded_cal_region <= # SIM_DELAY 
				(~rst_adapter) & (~to_rst_cursor) & 
				cursor_at_last_cal_sfc;
	end
	
	/** 待计算表面光标 **/
	reg[4:0] cal_start_logic_x; // 起始逻辑x坐标
	wire[4:0] cal_start_logic_x_nxt; // 下一起始逻辑x坐标
	reg signed[15:0] cur_cal_pos; // 待计算表面的逻辑x坐标
	reg[15:0] pst_cal_sfc_n; // 已提交计算的表面数
	wire on_pst_cal_sfc; // 提交待计算表面(指示)
	
	assign cal_start_logic_x_nxt = 
		(rst_adapter | (cal_start_logic_x == kernal_w_dilated)) ? 
			5'd0:
			(cal_start_logic_x + kernal_dilation_hzt_n + 1'b1);
	
	// 起始逻辑x坐标
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(rst_adapter | (on_pst_cal_sfc & (pst_cal_sfc_n == ofmap_w)))
		)
			cal_start_logic_x <= # SIM_DELAY cal_start_logic_x_nxt;
	end
	
	// 待计算表面的逻辑x坐标
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(rst_adapter | on_pst_cal_sfc)
		)
			cur_cal_pos <= # SIM_DELAY 
				rst_adapter ? 
					({13'b1_1111_1111_1111, ~external_padding_left} + 1'b1):
					(
						(pst_cal_sfc_n == ofmap_w) ? 
							({13'b1_1111_1111_1111, ~external_padding_left} + cal_start_logic_x_nxt + 1'b1):
							(cur_cal_pos + conv_horizontal_stride + 1'b1)
					);
	end
	
	// 已提交计算的表面数
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(rst_adapter | on_pst_cal_sfc)
		)
			pst_cal_sfc_n <= # SIM_DELAY 
				(rst_adapter | (pst_cal_sfc_n == ofmap_w)) ? 
					16'd0:
					(pst_cal_sfc_n + 1'b1);
	end
	
	/** 物理特征图表面光标 **/
	reg[15:0] phy_sfc_x; // 物理表面位置
	wire on_acpt_phy_sfc; // 接受物理表面(指示)
	wire arrive_phy_row_end; // 抵达物理特征图表面行尾(标志)
	
	// 物理表面位置
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(rst_adapter | on_acpt_phy_sfc)
		)
			phy_sfc_x <= # SIM_DELAY 
				(rst_adapter | arrive_phy_row_end) ? 
					16'd0:
					(phy_sfc_x + 1'b1);
	end
	
	/** 特征图表面行流量 **/
	reg has_phy_row_traffic; // 有物理特征图表面行流量(标志)
	reg[27:0] phy_row_traffic_cnt; // 物理特征图表面行流量(计数器)
	wire on_consume_phy_row_traffic; // 消耗1个物理特征图表面行流量(指示)
	reg[27:0] row_n_submitted_to_mac_array_r; // 已向乘加阵列提交的行数
	
	assign row_n_submitted_to_mac_array = row_n_submitted_to_mac_array_r;
	
	// 有物理特征图表面行流量(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			has_phy_row_traffic <= 1'b0;
		else if(
			aclken & 
			(rst_adapter | (on_incr_phy_row_traffic ^ on_consume_phy_row_traffic))
		)
			has_phy_row_traffic <= # SIM_DELAY 
				(~rst_adapter) & (on_incr_phy_row_traffic | (phy_row_traffic_cnt != 32'd1));
	end
	
	// 物理特征图表面行流量(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			phy_row_traffic_cnt <= 28'h000_0000;
		else if(
			aclken & 
			(rst_adapter | (on_incr_phy_row_traffic | on_consume_phy_row_traffic))
		)
			phy_row_traffic_cnt <= # SIM_DELAY 
				rst_adapter ? 
					28'h000_0000:
					(
						phy_row_traffic_cnt + 
						({28{~on_incr_phy_row_traffic}} | {24'h00_0000, kernal_w}) + 
						((on_incr_phy_row_traffic & (~on_consume_phy_row_traffic)) ? 1'b1:1'b0)
					);
	end
	
	// 已向乘加阵列提交的行数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			row_n_submitted_to_mac_array_r <= 28'h000_0000;
		else if(
			aclken & 
			(rst_adapter | (on_pst_cal_sfc & (pst_cal_sfc_n == ofmap_w)))
		)
			row_n_submitted_to_mac_array_r <= # SIM_DELAY 
				rst_adapter ? 
					28'h000_0000:
					(row_n_submitted_to_mac_array_r + 1'b1);
	end
	
	assign m_row_reg_axis_ready = 
		aclken & 
		has_phy_row_traffic & 
		(cursor_phy_x == phy_sfc_x) & 
		(~is_cursor_at_external_padding_region) & (~is_cursor_at_inner_padding_region) & 
		((logic_x_to_cvt != cur_cal_pos) | s_mac_array_reg_axis_ready);
	
	assign s_mac_array_reg_axis_data = 
		(is_cursor_at_external_padding_region | is_cursor_at_inner_padding_region) ? 
			{(ATOMIC_C*2*8){1'b0}}:
			m_row_reg_axis_data;
	assign s_mac_array_reg_axis_last = pst_cal_sfc_n == ofmap_w;
	assign s_mac_array_reg_axis_user = is_cursor_at_external_padding_region | is_cursor_at_inner_padding_region;
	assign s_mac_array_reg_axis_valid = 
		aclken & 
		has_phy_row_traffic & 
		(logic_x_to_cvt == cur_cal_pos) & 
		(is_cursor_at_external_padding_region | is_cursor_at_inner_padding_region | m_row_reg_axis_valid);
	
	assign on_moving_cursor_to_nxt_pt = 
		aclken & 
		has_phy_row_traffic & 
		(
			(~((cursor_phy_x == phy_sfc_x) & (~is_cursor_at_external_padding_region) & (~is_cursor_at_inner_padding_region))) | 
			m_row_reg_axis_valid
		) & 
		((~(logic_x_to_cvt == cur_cal_pos)) | s_mac_array_reg_axis_ready);
	assign to_rst_cursor = 
		(cursor_exceeded_phy_row | ((cursor_phy_x == ifmap_w) & (~is_cursor_at_inner_padding_region))) & 
		(cursor_exceeded_cal_region | (s_mac_array_reg_axis_valid & s_mac_array_reg_axis_ready & s_mac_array_reg_axis_last));
	assign cursor_at_last_cal_sfc = (logic_x_to_cvt == cur_cal_pos) & (pst_cal_sfc_n == ofmap_w);
	
	assign on_pst_cal_sfc = aclken & s_mac_array_reg_axis_valid & s_mac_array_reg_axis_ready;
	
	assign on_acpt_phy_sfc = aclken & m_row_reg_axis_valid & m_row_reg_axis_ready;
	assign arrive_phy_row_end = m_row_reg_axis_last;
	
	assign on_consume_phy_row_traffic = aclken & on_moving_cursor_to_nxt_pt & to_rst_cursor;
	
endmodule
