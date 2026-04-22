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
日期: 2026/03/29
********************************************************************/


module conv_middle_res_info_packer #(
	parameter IS_MID_RES_COMMON_CLK = "true", // 中间结果时钟是否与主时钟一致
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter EN_MAC_ARRAY_REG_SLICE = "true", // 是否在"乘加阵列得到的中间结果"处插入寄存器片
	parameter EN_PKT_OUT_REG_SLICE = "true", // 是否在"打包后的中间结果"处插入寄存器片
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	// 中间结果时钟和复位
	input wire mid_res_aclk,
	input wire mid_res_aresetn,
	input wire mid_res_aclken,
	
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
	output wire[2:0] m_axis_pkt_out_user, // {是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	output wire m_axis_pkt_out_last, // 本行最后1个中间结果(标志)
	output wire m_axis_pkt_out_valid,
	input wire m_axis_pkt_out_ready
);
	
	/** 内部配置 **/
	localparam EN_FM_CAKE_INFO_FIFO_FAST_RD = "false"; // 是否使能"特征图切块信息fifo尽快读取"
	
	/** 时钟和复位 **/
	// 实际的中间结果时钟和复位
	wire actual_mid_res_aclk;
	wire actual_mid_res_aresetn;
	wire actual_mid_res_aclken;
	
	assign actual_mid_res_aclk = (IS_MID_RES_COMMON_CLK == "true") ? aclk:mid_res_aclk;
	assign actual_mid_res_aresetn = (IS_MID_RES_COMMON_CLK == "true") ? aresetn:mid_res_aresetn;
	assign actual_mid_res_aclken = (IS_MID_RES_COMMON_CLK == "true") ? aclken:mid_res_aclken;
	
	/** 同步到中间结果时钟域的使能信号和运行时参数 **/
	reg[4:1] en_packer_delayed_by_mid_res_aclk;
	reg[11:0] ofmap_w_latched_by_mid_res_aclk;
	reg[3:0] kernal_w_latched_by_mid_res_aclk;
	reg[15:0] cgrp_n_of_fmap_region_that_kernal_set_sel_d1;
	reg[15:0] cgrp_n_of_fmap_region_that_kernal_set_sel_latched_by_mid_res_aclk;
	wire en_packer_sync_in_mid_res_aclk;
	wire[11:0] ofmap_w_sync_in_mid_res_aclk;
	wire[3:0] kernal_w_sync_in_mid_res_aclk;
	wire[15:0] cgrp_n_of_fmap_region_that_kernal_set_sel_sync_in_mid_res_aclk;
	
	assign en_packer_sync_in_mid_res_aclk = en_packer_delayed_by_mid_res_aclk[4];
	assign ofmap_w_sync_in_mid_res_aclk = ofmap_w;
	assign kernal_w_sync_in_mid_res_aclk = kernal_w;
	assign cgrp_n_of_fmap_region_that_kernal_set_sel_sync_in_mid_res_aclk = cgrp_n_of_fmap_region_that_kernal_set_sel_d1;
	
	// 跨时钟域: ... -> en_packer_delayed_by_mid_res_aclk[1]
	always @(posedge actual_mid_res_aclk or negedge actual_mid_res_aresetn)
	begin
		if(~actual_mid_res_aresetn)
			en_packer_delayed_by_mid_res_aclk <= 4'b0000;
		else
			en_packer_delayed_by_mid_res_aclk <= # SIM_DELAY 
				{en_packer_delayed_by_mid_res_aclk[3:1], en_packer};
	end
	
	always @(posedge aclk)
	begin
		cgrp_n_of_fmap_region_that_kernal_set_sel_d1 <= # SIM_DELAY 
			cgrp_n_of_fmap_region_that_kernal_set_sel;
	end
	
	/*
	跨时钟域:
		... -> ofmap_w_latched_by_mid_res_aclk[*]
		... -> kernal_w_latched_by_mid_res_aclk[*]
		cgrp_n_of_fmap_region_that_kernal_set_sel_d1[*] -> cgrp_n_of_fmap_region_that_kernal_set_sel_latched_by_mid_res_aclk[*]
	*/
	always @(posedge actual_mid_res_aclk)
	begin
		if(en_packer_delayed_by_mid_res_aclk[3] & (~en_packer_delayed_by_mid_res_aclk[4])) // 检测到使能信号的上升沿
		begin
			ofmap_w_latched_by_mid_res_aclk <= # SIM_DELAY ofmap_w;
			kernal_w_latched_by_mid_res_aclk <= # SIM_DELAY kernal_w;
			cgrp_n_of_fmap_region_that_kernal_set_sel_latched_by_mid_res_aclk <= # SIM_DELAY 
				cgrp_n_of_fmap_region_that_kernal_set_sel_d1;
		end
	end
	
	/** AXIS寄存器片 **/
	// [寄存器片#0]
	wire[ATOMIC_K*48-1:0] s_axis_mac_array_reg_data; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[1+ATOMIC_K-1:0] s_axis_mac_array_reg_user; // {是否最后1轮计算(1bit), 计算结果输出项掩码(ATOMIC_K bit)}
	wire s_axis_mac_array_reg_valid;
	wire s_axis_mac_array_reg_ready;
	wire[ATOMIC_K*48-1:0] m_axis_mac_array_reg_data; // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[1+ATOMIC_K-1:0] m_axis_mac_array_reg_user; // {是否最后1轮计算(1bit), 计算结果输出项掩码(ATOMIC_K bit)}
	wire m_axis_mac_array_reg_valid;
	wire m_axis_mac_array_reg_ready;
	// [寄存器片#1]
	wire[ATOMIC_K*48-1:0] s_axis_pkt_out_reg_data; // ATOMIC_K个中间结果
	                                               // ({指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[ATOMIC_K*6-1:0] s_axis_pkt_out_reg_keep;
	wire[2:0] s_axis_pkt_out_reg_user; // {是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire s_axis_pkt_out_reg_last; // 本行最后1个中间结果(标志)
	wire s_axis_pkt_out_reg_valid;
	wire s_axis_pkt_out_reg_ready;
	wire[ATOMIC_K*48-1:0] m_axis_pkt_out_reg_data; // ATOMIC_K个中间结果
	                                               // ({指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	wire[ATOMIC_K*6-1:0] m_axis_pkt_out_reg_keep;
	wire[2:0] m_axis_pkt_out_reg_user; // {是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire m_axis_pkt_out_reg_last; // 本行最后1个中间结果(标志)
	wire m_axis_pkt_out_reg_valid;
	wire m_axis_pkt_out_reg_ready;
	
	assign s_axis_mac_array_reg_data = mac_array_res;
	assign s_axis_mac_array_reg_user = {mac_array_is_last_cal_round, mac_array_res_mask};
	assign s_axis_mac_array_reg_valid = mac_array_res_vld;
	assign mac_array_res_rdy = s_axis_mac_array_reg_ready;
	
	assign m_axis_pkt_out_data = m_axis_pkt_out_reg_data;
	assign m_axis_pkt_out_keep = m_axis_pkt_out_reg_keep;
	assign m_axis_pkt_out_user = m_axis_pkt_out_reg_user;
	assign m_axis_pkt_out_last = m_axis_pkt_out_reg_last;
	assign m_axis_pkt_out_valid = m_axis_pkt_out_reg_valid;
	assign m_axis_pkt_out_reg_ready = m_axis_pkt_out_ready;
	
	axis_reg_slice #(
		.data_width(ATOMIC_K*48),
		.user_width(1+ATOMIC_K),
		.forward_registered("false"),
		.back_registered(EN_MAC_ARRAY_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)mac_array_reg_slice(
		.clk(actual_mid_res_aclk),
		.rst_n(actual_mid_res_aresetn),
		.clken(actual_mid_res_aclken),
		
		.s_axis_data(s_axis_mac_array_reg_data),
		.s_axis_keep({(ATOMIC_K*6){1'bx}}),
		.s_axis_user(s_axis_mac_array_reg_user),
		.s_axis_last(1'bx),
		.s_axis_valid(s_axis_mac_array_reg_valid),
		.s_axis_ready(s_axis_mac_array_reg_ready),
		
		.m_axis_data(m_axis_mac_array_reg_data),
		.m_axis_keep(),
		.m_axis_user(m_axis_mac_array_reg_user),
		.m_axis_last(),
		.m_axis_valid(m_axis_mac_array_reg_valid),
		.m_axis_ready(m_axis_mac_array_reg_ready)
	);
	
	axis_reg_slice #(
		.data_width(ATOMIC_K*48),
		.user_width(3),
		.forward_registered(EN_PKT_OUT_REG_SLICE),
		.back_registered("false"),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)pkt_out_reg_slice(
		.clk(actual_mid_res_aclk),
		.rst_n(actual_mid_res_aresetn),
		.clken(actual_mid_res_aclken),
		
		.s_axis_data(s_axis_pkt_out_reg_data),
		.s_axis_keep(s_axis_pkt_out_reg_keep),
		.s_axis_user(s_axis_pkt_out_reg_user),
		.s_axis_last(s_axis_pkt_out_reg_last),
		.s_axis_valid(s_axis_pkt_out_reg_valid),
		.s_axis_ready(s_axis_pkt_out_reg_ready),
		
		.m_axis_data(m_axis_pkt_out_reg_data),
		.m_axis_keep(m_axis_pkt_out_reg_keep),
		.m_axis_user(m_axis_pkt_out_reg_user),
		.m_axis_last(m_axis_pkt_out_reg_last),
		.m_axis_valid(m_axis_pkt_out_reg_valid),
		.m_axis_ready(m_axis_pkt_out_reg_ready)
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
	
	generate
		if(IS_MID_RES_COMMON_CLK == "true")
		begin
			fifo_based_on_regs #(
				.fwft_mode("false"),
				.low_latency_mode("false"),
				.fifo_depth(16),
				.fifo_data_width(4),
				.almost_full_th(8),
				.almost_empty_th(8),
				.simulation_delay(SIM_DELAY)
			)fm_cake_info_fifo_u(
				.clk(actual_mid_res_aclk),
				.rst_n(actual_mid_res_aresetn),
				
				.fifo_wen(fm_cake_info_fifo_wen),
				.fifo_din(fm_cake_info_fifo_din),
				.fifo_full(),
				.fifo_full_n(fm_cake_info_fifo_full_n),
				.fifo_almost_full(),
				.fifo_almost_full_n(),
				
				.fifo_ren(fm_cake_info_fifo_ren),
				.fifo_dout(fm_cake_info_fifo_dout),
				.fifo_empty(),
				.fifo_empty_n(fm_cake_info_fifo_empty_n),
				.fifo_almost_empty(),
				.fifo_almost_empty_n(),
				
				.data_cnt()
			);
		end
		else
		begin
			/*
			跨时钟域:
				fm_cake_info_fifo_u/async_fifo_u/rptr_gray_at_r[*] -> fm_cake_info_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]
				fm_cake_info_fifo_u/async_fifo_u/wptr_gray_at_w[*] -> fm_cake_info_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]
				... -> fm_cake_info_fifo_u/ram_u/dout_b_regs[*]
			*/
			async_fifo_with_ram #(
				.fwft_mode("false"),
				.ram_type("lutram"),
				.depth(32),
				.data_width(4),
				.simulation_delay(SIM_DELAY)
			)fm_cake_info_fifo_u(
				.clk_wt(aclk),
				.rst_n_wt(aresetn),
				.clk_rd(actual_mid_res_aclk),
				.rst_n_rd(actual_mid_res_aresetn),
				
				.fifo_wen(fm_cake_info_fifo_wen),
				.fifo_full(),
				.fifo_full_n(fm_cake_info_fifo_full_n),
				.fifo_din(fm_cake_info_fifo_din),
				.data_cnt_wt(),
				
				.fifo_ren(fm_cake_info_fifo_ren),
				.fifo_empty(),
				.fifo_empty_n(fm_cake_info_fifo_empty_n),
				.fifo_dout(fm_cake_info_fifo_dout),
				.data_cnt_rd()
			);
		end
	endgenerate
	
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
	
	assign fm_cake_info_fifo_ren = 
		actual_mid_res_aclken & en_packer_sync_in_mid_res_aclk & 
		(
			(~cur_fm_cake_h_param_vld) | 
			(
				(EN_FM_CAKE_INFO_FIFO_FAST_RD == "true") & 
				m_axis_mac_array_reg_valid & m_axis_mac_array_reg_ready & 
				m_axis_mac_array_reg_user[ATOMIC_K] & 
				arrive_ofmap_row_end & arrive_kernal_vld_region_row_end & at_last_row_in_fm_cake & at_last_cgrp_in_fm_cake
			)
		);
	
	assign cur_fm_cake_h = fm_cake_info_fifo_dout;
	
	assign arrive_ofmap_row_end = ofmap_x_cnt == ofmap_w_sync_in_mid_res_aclk;
	assign arrive_kernal_vld_region_row_end = kernal_vld_region_x_cnt == kernal_w_sync_in_mid_res_aclk;
	assign at_last_row_in_fm_cake = rid_in_fm_cake_cnt == cur_fm_cake_h;
	assign at_last_cgrp_in_fm_cake = cgrpid_in_fm_cake_cnt == cgrp_n_of_fmap_region_that_kernal_set_sel_sync_in_mid_res_aclk;
	
	// 当前特征图切块的高度(参数有效标志)
	always @(posedge actual_mid_res_aclk or negedge actual_mid_res_aresetn)
	begin
		if(~actual_mid_res_aresetn)
			cur_fm_cake_h_param_vld <= 1'b0;
		else if(
			actual_mid_res_aclken & 
			(
				(~en_packer_sync_in_mid_res_aclk) | 
				(
					cur_fm_cake_h_param_vld ? 
						(
							m_axis_mac_array_reg_valid & m_axis_mac_array_reg_ready & 
							m_axis_mac_array_reg_user[ATOMIC_K] & 
							arrive_ofmap_row_end & arrive_kernal_vld_region_row_end & at_last_row_in_fm_cake & at_last_cgrp_in_fm_cake & 
							((EN_FM_CAKE_INFO_FIFO_FAST_RD == "false") | (~fm_cake_info_fifo_empty_n))
						):
						fm_cake_info_fifo_empty_n
				)
			)
		)
			cur_fm_cake_h_param_vld <= # SIM_DELAY en_packer_sync_in_mid_res_aclk & (~cur_fm_cake_h_param_vld);
	end
	
	// 输出特征图x坐标(计数器)
	always @(posedge actual_mid_res_aclk or negedge actual_mid_res_aresetn)
	begin
		if(~actual_mid_res_aresetn)
			ofmap_x_cnt <= 12'd0;
		else if(
			actual_mid_res_aclken & 
			(
				(~en_packer_sync_in_mid_res_aclk) | 
				(
					m_axis_mac_array_reg_valid & m_axis_mac_array_reg_ready & 
					m_axis_mac_array_reg_user[ATOMIC_K]
				)
			)
		)
			ofmap_x_cnt <= # SIM_DELAY 
				((~en_packer_sync_in_mid_res_aclk) | arrive_ofmap_row_end) ? 
					12'd0:
					(ofmap_x_cnt + 1'b1);
	end
	
	// 卷积核有效区域x坐标(计数器)
	always @(posedge actual_mid_res_aclk or negedge actual_mid_res_aresetn)
	begin
		if(~actual_mid_res_aresetn)
			kernal_vld_region_x_cnt <= 4'd0;
		else if(
			actual_mid_res_aclken & 
			(
				(~en_packer_sync_in_mid_res_aclk) | 
				(
					m_axis_mac_array_reg_valid & m_axis_mac_array_reg_ready & 
					m_axis_mac_array_reg_user[ATOMIC_K] & arrive_ofmap_row_end
				)
			)
		)
			kernal_vld_region_x_cnt <= # SIM_DELAY 
				((~en_packer_sync_in_mid_res_aclk) | arrive_kernal_vld_region_row_end) ? 
					4'd0:
					(kernal_vld_region_x_cnt + 1'b1);
	end
	
	// 特征图切块内行号(计数器)
	always @(posedge actual_mid_res_aclk or negedge actual_mid_res_aresetn)
	begin
		if(~actual_mid_res_aresetn)
			rid_in_fm_cake_cnt <= 4'd1;
		else if(
			actual_mid_res_aclken & 
			(
				(~en_packer_sync_in_mid_res_aclk) | 
				(
					m_axis_mac_array_reg_valid & m_axis_mac_array_reg_ready & 
					m_axis_mac_array_reg_user[ATOMIC_K] & arrive_ofmap_row_end & arrive_kernal_vld_region_row_end
				)
			)
		)
			rid_in_fm_cake_cnt <= # SIM_DELAY 
				((~en_packer_sync_in_mid_res_aclk) | at_last_row_in_fm_cake) ? 
					4'd1:
					(rid_in_fm_cake_cnt + 1'b1);
	end
	
	// 特征图切块内通道组号(计数器)
	always @(posedge actual_mid_res_aclk or negedge actual_mid_res_aresetn)
	begin
		if(~actual_mid_res_aresetn)
			cgrpid_in_fm_cake_cnt <= 16'd0;
		else if(
			actual_mid_res_aclken & 
			(
				(~en_packer_sync_in_mid_res_aclk) | 
				(
					m_axis_mac_array_reg_valid & m_axis_mac_array_reg_ready & 
					m_axis_mac_array_reg_user[ATOMIC_K] & arrive_ofmap_row_end & arrive_kernal_vld_region_row_end & at_last_row_in_fm_cake
				)
			)
		)
			cgrpid_in_fm_cake_cnt <= # SIM_DELAY 
				((~en_packer_sync_in_mid_res_aclk) | at_last_cgrp_in_fm_cake) ? 
					16'd0:
					(cgrpid_in_fm_cake_cnt + 1'b1);
	end
	
	/** 中间结果打包处理 **/
	wire need_cur_fm_cake_h_param; // 当前特征图切块的高度(需要参数标志)
	reg first_mid_res; // 第1组中间结果(标志)
	wire last_mid_res; // 最后1组中间结果(标志)
	
	assign m_axis_mac_array_reg_ready = 
		actual_mid_res_aclken & 
		en_packer_sync_in_mid_res_aclk & 
		s_axis_pkt_out_reg_ready & 
		((~need_cur_fm_cake_h_param) | cur_fm_cake_h_param_vld);
	
	assign s_axis_pkt_out_reg_data = m_axis_mac_array_reg_data;
	
	genvar res_mask_i;
	generate
		for(res_mask_i = 0;res_mask_i < ATOMIC_K;res_mask_i = res_mask_i + 1)
		begin:res_mask_blk
			assign s_axis_pkt_out_reg_keep[6*res_mask_i+5:6*res_mask_i] = {6{m_axis_mac_array_reg_user[res_mask_i]}};
		end
	endgenerate
	
	assign s_axis_pkt_out_reg_user[0] = last_mid_res; // 最后1组中间结果(标志)
	assign s_axis_pkt_out_reg_user[1] = first_mid_res; // 初始化中间结果(标志)
	assign s_axis_pkt_out_reg_user[2] = m_axis_mac_array_reg_user[ATOMIC_K]; // 是否最后1轮计算
	
	assign s_axis_pkt_out_reg_last = m_axis_mac_array_reg_user[ATOMIC_K] & arrive_ofmap_row_end;
	
	assign s_axis_pkt_out_reg_valid = 
		actual_mid_res_aclken & 
		en_packer_sync_in_mid_res_aclk & 
		m_axis_mac_array_reg_valid & 
		((~need_cur_fm_cake_h_param) | cur_fm_cake_h_param_vld);
	
	assign need_cur_fm_cake_h_param = arrive_ofmap_row_end & arrive_kernal_vld_region_row_end;
	assign last_mid_res = arrive_kernal_vld_region_row_end & at_last_row_in_fm_cake & at_last_cgrp_in_fm_cake;
	
	// 第1组中间结果(标志)
	always @(posedge actual_mid_res_aclk or negedge actual_mid_res_aresetn)
	begin
		if(~actual_mid_res_aresetn)
			first_mid_res <= 1'b1;
		else if(
			actual_mid_res_aclken & 
			(
				(~en_packer_sync_in_mid_res_aclk) | 
				(
					m_axis_mac_array_reg_valid & m_axis_mac_array_reg_ready & 
					m_axis_mac_array_reg_user[ATOMIC_K] & arrive_ofmap_row_end
				)
			)
		)
			first_mid_res <= # SIM_DELAY (~en_packer_sync_in_mid_res_aclk) | last_mid_res;
	end
	
endmodule
