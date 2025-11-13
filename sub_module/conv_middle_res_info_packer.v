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
本模块: 卷积中间结果表面行信息打包单元

描述:
根据特征图每个切片里的有效表面行数, 在乘加阵列得到的中间结果的基础上, 附加上本切块第1组/最后1组中间结果的标志

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/11/12
********************************************************************/


module conv_middle_res_info_packer #(
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 使能信号
	input wire en_packer, // 使能打包器
	
	// 运行时参数
	input wire[11:0] ofmap_w, // 输出特征图宽度 - 1
	input wire[3:0] kernal_w, // (膨胀前)卷积核宽度 - 1
	input wire[15:0] cgrp_n_of_fmap_region_that_kernal_set_sel, // 核组所选定特征图域的通道组数 - 1
	
	// 特征图切块信息(AXIS从机)
	input wire[7:0] s_fm_cake_info_axis_data, // {保留(4bit), 每个切片里的有效表面行数(4bit)}
	input wire s_fm_cake_info_axis_valid,
	output wire s_fm_cake_info_axis_ready,
	
	// 乘加阵列得到的中间结果
	input wire[ATOMIC_K*48-1:0] mac_array_res, // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	input wire mac_array_is_last_cal_round, // 是否最后1轮计算
	input wire[ATOMIC_K-1:0] mac_array_res_mask, // 计算结果输出项掩码
	input wire mac_array_res_vld, // 有效标志
	output wire mac_array_res_rdy, // 就绪标志
	
	// 打包后的中间结果(AXIS主机)
	output wire[ATOMIC_K*48-1:0] m_axis_pkt_out_data, // ATOMIC_K个中间结果
	                                                  // ({指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	output wire[ATOMIC_K*6-1:0] m_axis_pkt_out_keep,
	output wire[1:0] m_axis_pkt_out_user, // {初始化中间结果(标志), 最后1组中间结果(标志)}
	output wire m_axis_pkt_out_valid,
	input wire m_axis_pkt_out_ready
);
	
	/** 特征图切块信息fifo **/
	// [写端口]
	wire fm_cake_info_fifo_wen;
	wire[3:0] fm_cake_info_fifo_din; // {每个切片里的有效表面行数(4bit)}
	wire fm_cake_info_fifo_full_n;
	// [读端口]
	wire fm_cake_info_fifo_ren;
	wire[3:0] fm_cake_info_fifo_dout; // {每个切片里的有效表面行数(4bit)}
	wire fm_cake_info_fifo_empty_n;
	
	assign s_fm_cake_info_axis_ready = aclken & en_packer & fm_cake_info_fifo_full_n;
	
	assign fm_cake_info_fifo_wen = aclken & en_packer & s_fm_cake_info_axis_valid;
	assign fm_cake_info_fifo_din = s_fm_cake_info_axis_data[3:0];
	
	fifo_based_on_regs #(
		.fwft_mode("false"),
		.low_latency_mode("false"),
		.fifo_depth(16),
		.fifo_data_width(4),
		.almost_full_th(8),
		.almost_empty_th(8),
		.simulation_delay(SIM_DELAY)
	)fm_cake_info_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(fm_cake_info_fifo_wen),
		.fifo_din(fm_cake_info_fifo_din),
		.fifo_full_n(fm_cake_info_fifo_full_n),
		
		.fifo_ren(fm_cake_info_fifo_ren),
		.fifo_dout(fm_cake_info_fifo_dout),
		.fifo_empty_n(fm_cake_info_fifo_empty_n)
	);
	
	/** 特征图切块内计数器组 **/
	wire[3:0] cur_fm_cake_h; // 当前特征图切块的高度
	reg cur_fm_cake_h_param_vld; // 当前特征图切块的高度(参数有效标志)
	reg[11:0] ofmap_x_cnt; // 输出特征图x坐标(计数器)
	wire arrive_ofmap_row_end; // 抵达输出特征图行尾(标志)
	reg[3:0] kernal_vld_region_x_cnt; // 卷积核有效区域x坐标(计数器)
	wire arrive_kernal_vld_region_row_end; // 抵达卷积核有效区域行尾(标志)
	reg[3:0] rid_in_fm_cake_cnt; // 特征图切块内行号(计数器)
	wire at_last_row_in_fm_cake; // 位于特征图切块内的最后1行(标志)
	reg[15:0] cgrpid_in_fm_cake_cnt; // 特征图切块内通道组号(计数器)
	wire at_last_cgrp_in_fm_cake; // 位于特征图切块内的最后1个通道组(标志)
	
	assign fm_cake_info_fifo_ren = aclken & en_packer & (~cur_fm_cake_h_param_vld);
	
	assign cur_fm_cake_h = fm_cake_info_fifo_dout;
	
	assign arrive_ofmap_row_end = ofmap_x_cnt == ofmap_w;
	assign arrive_kernal_vld_region_row_end = kernal_vld_region_x_cnt == kernal_w;
	assign at_last_row_in_fm_cake = rid_in_fm_cake_cnt == cur_fm_cake_h;
	assign at_last_cgrp_in_fm_cake = cgrpid_in_fm_cake_cnt == cgrp_n_of_fmap_region_that_kernal_set_sel;
	
	// 当前特征图切块的高度(参数有效标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cur_fm_cake_h_param_vld <= 1'b0;
		else if(
			aclken & 
			(
				(~en_packer) | 
				(
					cur_fm_cake_h_param_vld ? 
						(
							mac_array_res_vld & mac_array_res_rdy & 
							mac_array_is_last_cal_round & 
							arrive_ofmap_row_end & arrive_kernal_vld_region_row_end & at_last_row_in_fm_cake & at_last_cgrp_in_fm_cake
						):
						fm_cake_info_fifo_empty_n
				)
			)
		)
			cur_fm_cake_h_param_vld <= # SIM_DELAY en_packer & (~cur_fm_cake_h_param_vld);
	end
	
	// 输出特征图x坐标(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ofmap_x_cnt <= 12'd0;
		else if(
			aclken & 
			(
				(~en_packer) | 
				(
					mac_array_res_vld & mac_array_res_rdy & 
					mac_array_is_last_cal_round
				)
			)
		)
			ofmap_x_cnt <= # SIM_DELAY 
				((~en_packer) | arrive_ofmap_row_end) ? 
					12'd0:
					(ofmap_x_cnt + 1'b1);
	end
	
	// 卷积核有效区域x坐标(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_vld_region_x_cnt <= 4'd0;
		else if(
			aclken & 
			(
				(~en_packer) | 
				(
					mac_array_res_vld & mac_array_res_rdy & 
					mac_array_is_last_cal_round & arrive_ofmap_row_end
				)
			)
		)
			kernal_vld_region_x_cnt <= # SIM_DELAY 
				((~en_packer) | arrive_kernal_vld_region_row_end) ? 
					4'd0:
					(kernal_vld_region_x_cnt + 1'b1);
	end
	
	// 特征图切块内行号(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rid_in_fm_cake_cnt <= 4'd1;
		else if(
			aclken & 
			(
				(~en_packer) | 
				(
					mac_array_res_vld & mac_array_res_rdy & 
					mac_array_is_last_cal_round & arrive_ofmap_row_end & arrive_kernal_vld_region_row_end
				)
			)
		)
			rid_in_fm_cake_cnt <= # SIM_DELAY 
				((~en_packer) | at_last_row_in_fm_cake) ? 
					4'd1:
					(rid_in_fm_cake_cnt + 1'b1);
	end
	
	// 特征图切块内通道组号(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cgrpid_in_fm_cake_cnt <= 16'd0;
		else if(
			aclken & 
			(
				(~en_packer) | 
				(
					mac_array_res_vld & mac_array_res_rdy & 
					mac_array_is_last_cal_round & arrive_ofmap_row_end & arrive_kernal_vld_region_row_end & at_last_row_in_fm_cake
				)
			)
		)
			cgrpid_in_fm_cake_cnt <= # SIM_DELAY 
				((~en_packer) | at_last_cgrp_in_fm_cake) ? 
					16'd0:
					(cgrpid_in_fm_cake_cnt + 1'b1);
	end
	
	/** 中间结果打包处理 **/
	wire need_cur_fm_cake_h_param; // 当前特征图切块的高度(需要参数标志)
	reg first_mid_res; // 第1组中间结果(标志)
	wire last_mid_res; // 最后1组中间结果(标志)
	
	assign mac_array_res_rdy = 
		aclken & 
		en_packer & 
		m_axis_pkt_out_ready & 
		((~need_cur_fm_cake_h_param) | cur_fm_cake_h_param_vld);
	
	assign m_axis_pkt_out_data = mac_array_res;
	
	genvar res_mask_i;
	generate
		for(res_mask_i = 0;res_mask_i < ATOMIC_K;res_mask_i = res_mask_i + 1)
		begin:res_mask_blk
			assign m_axis_pkt_out_keep[6*res_mask_i+5:6*res_mask_i] = {6{mac_array_res_mask[res_mask_i]}};
		end
	endgenerate
	
	assign m_axis_pkt_out_user[0] = last_mid_res; // 最后1组中间结果(标志)
	assign m_axis_pkt_out_user[1] = first_mid_res; // 初始化中间结果(标志)
	
	assign m_axis_pkt_out_valid = 
		aclken & 
		en_packer & 
		mac_array_res_vld & 
		((~need_cur_fm_cake_h_param) | cur_fm_cake_h_param_vld);
	
	assign need_cur_fm_cake_h_param = arrive_ofmap_row_end & arrive_kernal_vld_region_row_end;
	assign last_mid_res = 
		mac_array_is_last_cal_round & 
		arrive_ofmap_row_end & arrive_kernal_vld_region_row_end & at_last_row_in_fm_cake & at_last_cgrp_in_fm_cake;
	
	// 第1组中间结果(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			first_mid_res <= 1'b1;
		else if(
			aclken & 
			(
				(~en_packer) | 
				(
					mac_array_res_vld & mac_array_res_rdy & 
					mac_array_is_last_cal_round & arrive_ofmap_row_end
				)
			)
		)
			first_mid_res <= # SIM_DELAY (~en_packer) | last_mid_res;
	end
	
endmodule
