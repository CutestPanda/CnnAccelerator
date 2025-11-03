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
本模块: 逻辑与物理卷积核坐标转换单元

描述:
将逻辑卷积核坐标点(位于拓展卷积核上)转换到物理卷积核坐标点(位于原始卷积核上), 以支持膨胀卷积

                                 * O * O *
* * *                            O O O O O
* * * --[水平/垂直膨胀量 = 1]--> * O * O *
* * *                            O O O O O
                                 * O * O *

注意：
转换单元只能通过"移动到下1个逻辑卷积核点位"顺序产生每1个逻辑/物理卷积核点位, 不支持随机转换

协议:
无

作者: 陈家耀
日期: 2025/06/24
********************************************************************/


module kernal_pos_logic_to_phy #(
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[3:0] kernal_dilation_hzt_n, // 水平膨胀量
	input wire[3:0] kernal_dilation_vtc_n, // 垂直膨胀量
	input wire[3:0] kernal_w, // (膨胀前)卷积核宽度 - 1
	input wire[3:0] kernal_h, // (膨胀前)卷积核高度 - 1
	
	// 控制/状态
	input wire rst_cvt, // 复位转换单元
	input wire mv_to_nxt_logic_pt, // 移动到下1个逻辑卷积核点位
	output wire[7:0] kernal_logic_x, // 当前的逻辑卷积核x坐标
	output wire[7:0] kernal_logic_y, // 当前的逻辑卷积核y坐标
	output wire[7:0] kernal_phy_x, // 当前的物理卷积核x坐标
	output wire[7:0] kernal_phy_y, // 当前的物理卷积核y坐标
	output wire kernal_pt_valid // 逻辑卷积核点有效标志
);
	
	reg[7:0] kernal_logic_x_r; // 当前的逻辑卷积核x坐标
	reg[7:0] kernal_logic_y_r; // 当前的逻辑卷积核y坐标
	reg[7:0] kernal_phy_x_r; // 当前的物理卷积核x坐标
	reg[7:0] kernal_phy_y_r; // 当前的物理卷积核y坐标
	reg kernal_pt_valid_r; // 逻辑卷积核点有效标志
	reg is_at_hzt_dilation_rgn; // 是否处于水平膨胀区(标志)
	reg is_at_vtc_dilation_rgn; // 是否处于垂直膨胀区(标志)
	reg[3:0] hzt_dilation_cnt; // 水平膨胀计数器
	reg[3:0] vtc_dilation_cnt; // 垂直膨胀计数器
	
	assign kernal_logic_x = kernal_logic_x_r;
	assign kernal_logic_y = kernal_logic_y_r;
	assign kernal_phy_x = kernal_phy_x_r;
	assign kernal_phy_y = kernal_phy_y_r;
	assign kernal_pt_valid = kernal_pt_valid_r;
	
	// 当前的逻辑卷积核x坐标
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_logic_x_r <= 8'd0;
		else if(aclken & (rst_cvt | mv_to_nxt_logic_pt))
			kernal_logic_x_r <= # SIM_DELAY 
				(rst_cvt | (kernal_phy_x_r == {4'd0, kernal_w})) ? 
					8'd0:
					(kernal_logic_x_r + 1'b1);
	end
	// 当前的逻辑卷积核y坐标
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_logic_y_r <= 8'd0;
		else if(aclken & (rst_cvt | (mv_to_nxt_logic_pt & (kernal_phy_x_r == {4'd0, kernal_w}))))
			kernal_logic_y_r <= # SIM_DELAY 
				(rst_cvt | (kernal_phy_y_r == {4'd0, kernal_h})) ? 
					8'd0:
					(kernal_logic_y_r + 1'b1);
	end
	
	// 当前的物理卷积核x坐标
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_phy_x_r <= 8'd0;
		else if(
			aclken & (
				rst_cvt | (
					mv_to_nxt_logic_pt & (
						(kernal_phy_x_r == {4'd0, kernal_w}) | 
						(kernal_dilation_hzt_n == 4'd0) | 
						(is_at_hzt_dilation_rgn & (hzt_dilation_cnt == kernal_dilation_hzt_n))
					)
				)
			)
		)
			kernal_phy_x_r <= # SIM_DELAY 
				(rst_cvt | (kernal_phy_x_r == {4'd0, kernal_w})) ? 
					8'd0:
					(kernal_phy_x_r + 1'b1);
	end
	// 当前的物理卷积核y坐标
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_phy_y_r <= 8'd0;
		else if(
			aclken & (
				rst_cvt | (
					mv_to_nxt_logic_pt & (kernal_phy_x_r == {4'd0, kernal_w}) & (
						(kernal_phy_y_r == {4'd0, kernal_h}) | 
						(kernal_dilation_vtc_n == 4'd0) | 
						(is_at_vtc_dilation_rgn & (vtc_dilation_cnt == kernal_dilation_vtc_n))
					)
				)
			)
		)
			kernal_phy_y_r <= # SIM_DELAY 
				(rst_cvt | (kernal_phy_y_r == {4'd0, kernal_h})) ? 
					8'd0:
					(kernal_phy_y_r + 1'b1);
	end
	
	// 逻辑卷积核点有效标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_pt_valid_r <= 1'b1;
		else if(
			aclken & (
				rst_cvt | mv_to_nxt_logic_pt
			)
		)
			kernal_pt_valid_r <= # SIM_DELAY 
				rst_cvt | (
					(
						is_at_hzt_dilation_rgn ? 
							(hzt_dilation_cnt == kernal_dilation_hzt_n):
							((kernal_dilation_hzt_n == 4'd0) | (kernal_phy_x_r == {4'd0, kernal_w}))
					) & (
						(kernal_phy_x_r == {4'd0, kernal_w}) ? 
							(
								is_at_vtc_dilation_rgn ? 
									(vtc_dilation_cnt == kernal_dilation_vtc_n):
									((kernal_dilation_vtc_n == 4'd0) | (kernal_phy_y_r == {4'd0, kernal_h}))
							):
							(~is_at_vtc_dilation_rgn)
					)
				);
	end
	
	// 是否处于水平膨胀区(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			is_at_hzt_dilation_rgn <= 1'b0;
		else if(
			aclken & (
				rst_cvt | (
					mv_to_nxt_logic_pt & (
						is_at_hzt_dilation_rgn ? 
							(hzt_dilation_cnt == kernal_dilation_hzt_n):
							((kernal_dilation_hzt_n != 4'd0) & (kernal_phy_x_r != {4'd0, kernal_w}))
					)
				)
			)
		)
			is_at_hzt_dilation_rgn <= # SIM_DELAY (~rst_cvt) & (~is_at_hzt_dilation_rgn);
	end
	// 是否处于垂直膨胀区(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			is_at_vtc_dilation_rgn <= 1'b0;
		else if(
			aclken & (
				rst_cvt | (
					mv_to_nxt_logic_pt & (kernal_phy_x_r == {4'd0, kernal_w}) & (
						is_at_vtc_dilation_rgn ? 
							(vtc_dilation_cnt == kernal_dilation_vtc_n):
							((kernal_dilation_vtc_n != 4'd0) & (kernal_phy_y_r != {4'd0, kernal_h}))
					)
				)
			)
		)
			is_at_vtc_dilation_rgn <= # SIM_DELAY (~rst_cvt) & (~is_at_vtc_dilation_rgn);
	end
	
	// 水平膨胀计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			hzt_dilation_cnt <= 4'd1;
		else if(
			aclken & (
				rst_cvt | (
					mv_to_nxt_logic_pt & is_at_hzt_dilation_rgn
				)
			)
		)
			hzt_dilation_cnt <= # SIM_DELAY 
				(rst_cvt | (hzt_dilation_cnt == kernal_dilation_hzt_n)) ? 
					4'd1:
					(hzt_dilation_cnt + 4'd1);
	end
	// 垂直膨胀计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			vtc_dilation_cnt <= 4'd1;
		else if(
			aclken & (
				rst_cvt | (
					mv_to_nxt_logic_pt & (kernal_phy_x_r == {4'd0, kernal_w}) & is_at_vtc_dilation_rgn
				)
			)
		)
			vtc_dilation_cnt <= # SIM_DELAY 
				(rst_cvt | (vtc_dilation_cnt == kernal_dilation_vtc_n)) ? 
					4'd1:
					(vtc_dilation_cnt + 4'd1);
	end
	
endmodule
