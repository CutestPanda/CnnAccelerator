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
本模块: 逻辑与物理特征图坐标转换单元

描述:
将逻辑特征图坐标点(位于拓展特征图上)转换到物理特征图坐标点(位于原始特征图上), 以支持外填充和内填充, 并间接支持转置卷积

                         O O O O O O O
                         O * O * O * O
* * *                    O O O O O O O
* * * --[内/外填充 = 1]--> O * O * O * O
* * *                    O O O O O O O
                         O * O * O * O
						 O O O O O O O

注意：
扩展后特征图的水平边界 = 原始特征图宽度 + 左部外填充数 + (原始特征图宽度 - 1) * 左右内填充数 - 1
扩展后特征图的垂直边界 = 原始特征图高度 + 上部外填充数 + (原始特征图高度 - 1) * 上下内填充数 - 1

协议:
BLK CTRL

作者: 陈家耀
日期: 2025/06/26
********************************************************************/


module surface_pos_logic_to_phy #(
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[15:0] ext_j_right, // 扩展后特征图的水平边界
	input wire[15:0] ext_i_bottom, // 扩展后特征图的垂直边界
	input wire[2:0] external_padding_left, // 左部外填充数
	input wire[2:0] external_padding_top, // 上部外填充数
	input wire[2:0] inner_padding_top_bottom, // 上下内填充数
	input wire[2:0] inner_padding_left_right, // 左右内填充数
	
	// 块级控制
	input wire blk_start,
	output wire blk_idle,
	input wire[15:0] blk_i_logic_x, // 逻辑x坐标
	input wire[15:0] blk_i_logic_y, // 逻辑y坐标
	output wire blk_done,
	output wire[15:0] blk_o_phy_x, // 物理x坐标
	output wire[15:0] blk_o_phy_y, // 物理y坐标
	output wire blk_o_is_vld // 坐标点是否有效
);
	
	/** 常量 **/
	// 转换流程状态常量
	localparam CVT_STS_IDLE = 3'b000;
	localparam CVT_STS_JDG_VLD = 3'b001;
	localparam CVT_STS_CAL_PHY_X = 3'b010;
	localparam CVT_STS_CAL_PHY_Y = 3'b011;
	localparam CVT_STS_DONE = 3'b100;
	
	/** 多周期简单除法器(u16/u3) **/
	// 除法器输入
	wire[23:0] s_div_axis_data; // {保留(5bit), 除数(3bit), 被除数(16bit)}
	reg s_div_axis_valid;
	wire s_div_axis_ready;
	// 除法器输出
	wire[23:0] m_div_axis_data; // {保留(5bit), 余数(3bit), 商(16bit)}
	wire m_div_axis_valid;
	wire m_div_axis_ready;
	
	div_u16_u3 #(
		.SIM_DELAY(SIM_DELAY)
	)div_u16_u3_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.s_axis_data(s_div_axis_data),
		.s_axis_valid(s_div_axis_valid),
		.s_axis_ready(s_div_axis_ready),
		
		.m_axis_data(m_div_axis_data),
		.m_axis_valid(m_div_axis_valid),
		.m_axis_ready(m_div_axis_ready)
	);
	
	/** 坐标转换 **/
	reg[2:0] cvt_sts; // 转换状态
	reg[15:0] logic_x_latched; // 锁存的逻辑x坐标
	reg[15:0] logic_y_latched; // 锁存的逻辑y坐标
	wire is_pt_at_ext_padding_rgn_n; // 坐标点位于外填充区域(标志, 低有效)
	reg[15:0] phy_x; // 物理x坐标
	reg[15:0] phy_y; // 物理y坐标
	reg pt_vld; // 坐标点有效(标志)
	
	assign blk_idle = cvt_sts == CVT_STS_IDLE;
	assign blk_done = cvt_sts == CVT_STS_DONE;
	assign blk_o_phy_x = phy_x;
	assign blk_o_phy_y = phy_y;
	assign blk_o_is_vld = pt_vld;
	
	assign s_div_axis_data[23:19] = 5'bxxxxx; // 保留
	assign s_div_axis_data[18:16] = 
		(
			(cvt_sts == CVT_STS_CAL_PHY_X) ? 
				inner_padding_left_right:
				inner_padding_top_bottom
		) + 1'b1; // 除数
	assign s_div_axis_data[15:0] = 
		(
			(cvt_sts == CVT_STS_CAL_PHY_X) ? 
				logic_x_latched:
				logic_y_latched
		) - (
			(cvt_sts == CVT_STS_CAL_PHY_X) ? 
				{13'd0, external_padding_left}:
				{13'd0, external_padding_top}
		);
	
	assign m_div_axis_ready = aclken;
	
	assign is_pt_at_ext_padding_rgn_n = 
		(logic_x_latched >= {13'd0, external_padding_left}) & (logic_x_latched <= ext_j_right) & 
		(logic_y_latched >= {13'd0, external_padding_top}) & (logic_y_latched <= ext_i_bottom);
	
	// 除法器输入有效
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			s_div_axis_valid <= 1'b0;
		else if(aclken)
			s_div_axis_valid <= # SIM_DELAY 
				s_div_axis_valid ? 
					(~s_div_axis_ready):(
						((cvt_sts == CVT_STS_JDG_VLD) & is_pt_at_ext_padding_rgn_n) | 
						((cvt_sts == CVT_STS_CAL_PHY_X) & m_div_axis_valid & (m_div_axis_data[18:16] == 3'b000))
					);
	end
	
	// 转换状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cvt_sts <= CVT_STS_IDLE;
		else if(aclken)
		begin
			case(cvt_sts)
				CVT_STS_IDLE: 
					if(blk_start)
						cvt_sts <= # SIM_DELAY CVT_STS_JDG_VLD;
				CVT_STS_JDG_VLD:
					cvt_sts <= # SIM_DELAY 
						is_pt_at_ext_padding_rgn_n ? 
							CVT_STS_CAL_PHY_X:
							CVT_STS_DONE;
				CVT_STS_CAL_PHY_X:
					if(m_div_axis_valid)
						cvt_sts <= # SIM_DELAY 
							(m_div_axis_data[18:16] == 3'b000) ? 
								CVT_STS_CAL_PHY_Y:
								CVT_STS_DONE;
				CVT_STS_CAL_PHY_Y:
					if(m_div_axis_valid)
						cvt_sts <= # SIM_DELAY CVT_STS_DONE;
				CVT_STS_DONE:
					cvt_sts <= # SIM_DELAY CVT_STS_IDLE;
				default:
					cvt_sts <= # SIM_DELAY CVT_STS_IDLE;
			endcase
		end
	end
	
	// 锁存的逻辑x坐标, 锁存的逻辑y坐标
	always @(posedge aclk)
	begin
		if(aclken & blk_start & blk_idle)
		begin
			logic_x_latched <= # SIM_DELAY blk_i_logic_x;
			logic_y_latched <= # SIM_DELAY blk_i_logic_y;
		end
	end
	
	// 物理x坐标
	always @(posedge aclk)
	begin
		if(aclken & m_div_axis_valid & (cvt_sts == CVT_STS_CAL_PHY_X))
			phy_x <= # SIM_DELAY m_div_axis_data[15:0];
	end
	// 物理y坐标
	always @(posedge aclk)
	begin
		if(aclken & m_div_axis_valid & (cvt_sts == CVT_STS_CAL_PHY_Y))
			phy_y <= # SIM_DELAY m_div_axis_data[15:0];
	end
	
	// 坐标点有效(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & (
				(cvt_sts == CVT_STS_JDG_VLD) | (
					((cvt_sts == CVT_STS_CAL_PHY_X) | (cvt_sts == CVT_STS_CAL_PHY_Y)) & 
					m_div_axis_valid
				)
			)
		)
			pt_vld <= # SIM_DELAY 
				((cvt_sts == CVT_STS_JDG_VLD) & is_pt_at_ext_padding_rgn_n) | 
				(
					((cvt_sts == CVT_STS_CAL_PHY_X) | (cvt_sts == CVT_STS_CAL_PHY_Y)) & 
					(m_div_axis_data[18:16] == 3'b000)
				);
	end
	
endmodule
