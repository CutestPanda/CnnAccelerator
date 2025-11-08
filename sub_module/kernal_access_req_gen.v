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
本模块: 卷积核权重访问请求生成单元

描述:
根据卷积核参数和输出特征图高度, 按照"权重块 -> 通道组 -> 核组重复 -> 核组"的顺序生成卷积核权重块读请求

使用1个共享u16*u16乘法器

支持扩展卷积核(核膨胀)

注意：
当处于组卷积模式时, 每组的通道数/核数必须<=权重块最大宽度(MAX_WGTBLK_W)
目前仅支持16位权重数据
卷积核权重块在内存中必须是连续存储的

协议:
BLK CTRL
AXIS MASTER
REQ/GRANT

作者: 陈家耀
日期: 2025/10/29
********************************************************************/


module kernal_access_req_gen #(
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_WGTBLK_W = 8, // 权重块最大宽度(1 | 2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire is_16bit_wgt, // 是否16位权重数据
	input wire[31:0] kernal_wgt_baseaddr, // 卷积核权重基地址
	input wire[15:0] kernal_chn_n, // 通道数 - 1
	input wire[15:0] kernal_num_n, // 核数 - 1
	input wire[2:0] kernal_shape, // 卷积核形状
	input wire[15:0] ofmap_h, // 输出特征图高度 - 1
	input wire is_grp_conv_mode, // 是否处于组卷积模式
	input wire[15:0] n_foreach_group, // 每组的通道数/核数 - 1
	input wire[15:0] group_n, // 分组数 - 1
	input wire[15:0] cgrpn_foreach_kernal_set, // 每个核组的通道组数 - 1
	
	// 块级控制
	input wire blk_start,
	output wire blk_idle,
	output wire blk_done,
	
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
	
	// 共享无符号乘法器
	// [通道#0]
	output wire[15:0] shared_mul_c0_op_a, // 操作数A
	output wire[15:0] shared_mul_c0_op_b, // 操作数B
	output wire[3:0] shared_mul_c0_tid, // 操作ID
	output wire shared_mul_c0_req,
	input wire shared_mul_c0_grant,
	// [计算结果]
	input wire[31:0] shared_mul_res,
	input wire[3:0] shared_mul_oid,
	input wire shared_mul_ovld
);
	
	/** 常量 **/
	// 卷积核形状的类型编码
	localparam KBUFGRPSZ_1 = 3'b000; // 1x1
	localparam KBUFGRPSZ_9 = 3'b001; // 3x3
	localparam KBUFGRPSZ_25 = 3'b010; // 5x5
	localparam KBUFGRPSZ_49 = 3'b011; // 7x7
	localparam KBUFGRPSZ_81 = 3'b100; // 9x9
	localparam KBUFGRPSZ_121 = 3'b101; // 11x11
	// 权重块访问状态编码
	localparam KWGTBLK_ACCESS_STS_IDLE = 3'b000; // 状态: 空闲
	localparam KWGTBLK_ACCESS_STS_BUF_PRE_RST = 3'b001; // 状态: 缓存前复位
	localparam KWGTBLK_ACCESS_STS_GEN_REQ = 3'b010; // 状态: 生成请求
	localparam KWGTBLK_ACCESS_STS_WAIT_REQ_ACPT = 3'b011; // 状态: 等待请求被接受
	localparam KWGTBLK_ACCESS_STS_BUF_POST_RST = 3'b100; // 状态: 缓存后复位
	// 通道组长度更新状态编码
	localparam integer CGRP_BTT_UPD_STS_ONEHOT_UPTODT = 0; // 状态: 无需更新
	localparam integer CGRP_BTT_UPD_STS_ONEHOT_MUL_REQ0 = 1; // 状态: 乘法器请求#0
	localparam integer CGRP_BTT_UPD_STS_ONEHOT_MUL_OUT0 = 2; // 状态: 等待乘法器结果#0
	localparam integer CGRP_BTT_UPD_STS_ONEHOT_MUL_REQ1 = 3; // 状态: 乘法器请求#1
	localparam integer CGRP_BTT_UPD_STS_ONEHOT_MUL_OUT1 = 4; // 状态: 等待乘法器结果#1
	// 共享无符号乘法器操作ID
	localparam SHARED_MUL_C0_TID_CONST = 4'd0; // 通道#0操作ID
	
	/** 内部参数 **/
	wire[6:0] wgtblk_n_foreach_cgrp; // 每个通道组的权重块个数
	
	assign wgtblk_n_foreach_cgrp = 
		(kernal_shape == KBUFGRPSZ_1)  ? 7'd1:
		(kernal_shape == KBUFGRPSZ_9)  ? 7'd9:
		(kernal_shape == KBUFGRPSZ_25) ? 7'd25:
		(kernal_shape == KBUFGRPSZ_49) ? 7'd49:
		(kernal_shape == KBUFGRPSZ_81) ? 7'd81:
		                                 7'd121;
	
	/** 权重块位置计数器 **/
	wire on_upd_wgtblk_pos_cnt; // 更新权重块位置计数器(指示)
	reg[15:0] visited_kernal_num_or_group_cnt; // 已访问的核数或组数(计数器)
	wire is_last_kernal_set; // 最后1个核组(标志)
	reg[15:0] kernal_set_traverse_cnt; // 核组遍历次数(计数器)
	wire is_last_traverse_now_kernal_set; // 最后1次遍历当前核组(标志)
	reg[15:0] visited_kernal_chn_cnt; // 已访问的通道数(计数器)
	wire is_last_kernal_cgrp; // 最后1个通道组(标志)
	reg[6:0] kernal_wgtblk_id_cnt; // 当前访问权重块的编号(计数器)
	wire is_last_kernal_wgtblk; // 最后1个权重块(标志)
	
	assign is_last_kernal_set = 
		is_grp_conv_mode ? 
			(visited_kernal_num_or_group_cnt == group_n):
			((visited_kernal_num_or_group_cnt + MAX_WGTBLK_W) > kernal_num_n);
	assign is_last_traverse_now_kernal_set = 
		kernal_set_traverse_cnt == ofmap_h;
	assign is_last_kernal_cgrp = 
		is_grp_conv_mode ? 
			((visited_kernal_chn_cnt + ATOMIC_C) > n_foreach_group):
			((visited_kernal_chn_cnt + ATOMIC_C) > kernal_chn_n);
	assign is_last_kernal_wgtblk = 
		kernal_wgtblk_id_cnt == (wgtblk_n_foreach_cgrp - 1);
	
	// 已访问的核数或组数(计数器)
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | (on_upd_wgtblk_pos_cnt & is_last_kernal_wgtblk & is_last_kernal_cgrp & is_last_traverse_now_kernal_set)))
			visited_kernal_num_or_group_cnt <= # SIM_DELAY 
				blk_idle ? 
					16'd0:
					(
						is_grp_conv_mode ? 
							(visited_kernal_num_or_group_cnt + 1'b1):
							(visited_kernal_num_or_group_cnt + MAX_WGTBLK_W)
					);
	end
	
	// 核组遍历次数(计数器)
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | (on_upd_wgtblk_pos_cnt & is_last_kernal_wgtblk & is_last_kernal_cgrp)))
			kernal_set_traverse_cnt <= # SIM_DELAY 
				(blk_idle | is_last_traverse_now_kernal_set) ? 
					16'd0:
					(kernal_set_traverse_cnt + 1'b1);
	end
	
	// 已访问的通道数(计数器)
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | (on_upd_wgtblk_pos_cnt & is_last_kernal_wgtblk)))
			visited_kernal_chn_cnt <= # SIM_DELAY 
				(blk_idle | is_last_kernal_cgrp) ? 
					16'd0:
					(visited_kernal_chn_cnt + ATOMIC_C);
	end
	
	// 当前访问权重块的编号(计数器)
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | on_upd_wgtblk_pos_cnt))
			kernal_wgtblk_id_cnt <= # SIM_DELAY 
				(blk_idle | is_last_kernal_wgtblk) ? 
					7'd0:
					(kernal_wgtblk_id_cnt + 1'b1);
	end
	
	/** 权重块访问请求 **/
	// [访问状态]
	reg[2:0] req_gen_sts; // 访问请求生成(当前状态)
	// [核组参数]
	reg on_upd_kernal_set_params; // 更新核组参数(指示)
	reg on_init_kernal_set_params; // 初始化核组参数(指示)
	reg[15:0] wgtblk_w_of_now_kernal_set; // 当前核组的权重块宽度 - 1
	wire[9:0] cgrpn_of_now_kernal_set; // 当前核组的通道组数 - 1
	reg[9:0] cgrp_id_ofs; // 通道组号偏移
	reg[31:0] baseaddr_of_now_kernal_set; // 当前核组的基地址
	// [通道组参数]
	reg on_upd_kernal_cgrp_params; // 更新通道组参数(指示)
	reg upd_kernal_cgrp_params_for_first_cgrp_flag; // 为核组内的首通道组更新参数(标志)
	reg[4:0] sfc_depth_of_now_kernal_cgrp; // 当前通道组的表面深度 - 1
	reg[31:0] baseaddr_of_now_kernal_cgrp; // 当前通道组的基地址
	wire[31:0] incr_addr_of_now_kernal_cgrp; // 通道组递增地址
	reg[23:0] btt_of_now_kernal_cgrp; // 当前通道组的有效字节数
	reg[4:0] kernal_cgrp_len_upd_sts; // 通道组长度更新状态
	// [访问请求]
	reg[9:0] actual_cgrp_id; // 实际通道组号
	wire[6:0] wgtblk_id; // 权重块编号
	wire[6:0] start_sfc_id; // 起始表面编号
	wire[4:0] sfc_n_to_rd; // 待读取的表面个数 - 1
	wire[6:0] sfc_n_foreach_wgtblk; // 每个权重块的表面个数 - 1
	wire[4:0] sfc_depth; // 表面深度 - 1
	
	assign blk_idle = req_gen_sts == KWGTBLK_ACCESS_STS_IDLE;
	assign blk_done = (req_gen_sts == KWGTBLK_ACCESS_STS_BUF_POST_RST) & m_kwgtblk_rd_req_axis_valid & m_kwgtblk_rd_req_axis_ready;
	
	assign m_kwgtblk_rd_req_axis_data = 
		(req_gen_sts == KWGTBLK_ACCESS_STS_WAIT_REQ_ACPT) ? 
			{
				6'd0,
				1'b0, // 是否重置缓存(1bit)
				actual_cgrp_id, // 实际通道组号(10bit)
				wgtblk_id, // 权重块编号(7bit)
				start_sfc_id, // 起始表面编号(7bit)
				sfc_n_to_rd, // 待读取的表面个数 - 1(5bit)
				baseaddr_of_now_kernal_cgrp, // 卷积核通道组基地址(32bit)
				btt_of_now_kernal_cgrp, // 卷积核通道组有效字节数(24bit)
				sfc_n_foreach_wgtblk, // 每个权重块的表面个数 - 1(7bit)
				sfc_depth // 每个表面的有效数据个数 - 1(5bit)
			}:
			{
				6'd0,
				1'b1, // 是否重置缓存(1bit)
				cgrpn_of_now_kernal_set, // 卷积核核组实际通道组数 - 1(10bit)
				cgrp_id_ofs, // 通道组号偏移(10bit)
				77'd0
			};
	assign m_kwgtblk_rd_req_axis_valid = 
		((req_gen_sts == KWGTBLK_ACCESS_STS_BUF_PRE_RST) & (~on_upd_kernal_set_params)) | 
		(req_gen_sts == KWGTBLK_ACCESS_STS_WAIT_REQ_ACPT) | 
		(req_gen_sts == KWGTBLK_ACCESS_STS_BUF_POST_RST);
	
	/*
	第1次计算: 当前核组的权重块宽度 * 当前通道组的表面深度
	第2次计算: (前置结果 * 每个权重数据的字节数(1或2)) * 每个通道组的权重块个数
	*/
	assign shared_mul_c0_op_a = 
		kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_REQ0] ? 
			// 警告: 在组卷积模式下, 核组的权重块宽度可能>1024!
			((wgtblk_w_of_now_kernal_set[9:0] | 16'h0000) + 1'b1):
			(btt_of_now_kernal_cgrp[15:0] << is_16bit_wgt);
	assign shared_mul_c0_op_b = 
		kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_REQ0] ? 
			((sfc_depth_of_now_kernal_cgrp[4:0] | 16'h0000) + 1'b1):
			(wgtblk_n_foreach_cgrp[6:0] | 16'h0000);
	assign shared_mul_c0_tid = SHARED_MUL_C0_TID_CONST;
	assign shared_mul_c0_req = 
		kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_REQ0] | kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_REQ1];
	
	assign on_upd_wgtblk_pos_cnt = 
		(req_gen_sts == KWGTBLK_ACCESS_STS_WAIT_REQ_ACPT) & 
		m_kwgtblk_rd_req_axis_valid & m_kwgtblk_rd_req_axis_ready;
	
	assign cgrpn_of_now_kernal_set = cgrpn_foreach_kernal_set;
	
	assign incr_addr_of_now_kernal_cgrp = baseaddr_of_now_kernal_cgrp + btt_of_now_kernal_cgrp;
	
	assign wgtblk_id = kernal_wgtblk_id_cnt;
	assign start_sfc_id = 7'd0;
	// 警告: 在组卷积模式下, 核组的权重块宽度可能>32!
	assign sfc_n_to_rd = wgtblk_w_of_now_kernal_set[4:0];
	// 警告: 在组卷积模式下, 核组的权重块宽度可能>128!
	assign sfc_n_foreach_wgtblk = wgtblk_w_of_now_kernal_set[6:0];
	assign sfc_depth = sfc_depth_of_now_kernal_cgrp;
	
	// 访问请求生成(当前状态)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			req_gen_sts <= KWGTBLK_ACCESS_STS_IDLE;
		else if(aclken)
		begin
			case(req_gen_sts)
				KWGTBLK_ACCESS_STS_IDLE: // 状态: 空闲
					if(blk_start)
						req_gen_sts <= # SIM_DELAY KWGTBLK_ACCESS_STS_BUF_PRE_RST;
				KWGTBLK_ACCESS_STS_BUF_PRE_RST: // 状态: 缓存前复位
					if(m_kwgtblk_rd_req_axis_valid & m_kwgtblk_rd_req_axis_ready)
						req_gen_sts <= # SIM_DELAY KWGTBLK_ACCESS_STS_GEN_REQ;
				KWGTBLK_ACCESS_STS_GEN_REQ: // 状态: 生成请求
					if(~(on_upd_kernal_set_params | on_upd_kernal_cgrp_params | (~kernal_cgrp_len_upd_sts[KWGTBLK_ACCESS_STS_IDLE])))
						req_gen_sts <= # SIM_DELAY KWGTBLK_ACCESS_STS_WAIT_REQ_ACPT;
				KWGTBLK_ACCESS_STS_WAIT_REQ_ACPT: // 状态: 等待请求被接受
					if(m_kwgtblk_rd_req_axis_valid & m_kwgtblk_rd_req_axis_ready)
						req_gen_sts <= # SIM_DELAY 
							(is_last_kernal_wgtblk & is_last_kernal_cgrp & is_last_traverse_now_kernal_set) ? 
								(
									is_last_kernal_set ? 
										KWGTBLK_ACCESS_STS_BUF_POST_RST:
										KWGTBLK_ACCESS_STS_BUF_PRE_RST
								):
								KWGTBLK_ACCESS_STS_GEN_REQ;
				KWGTBLK_ACCESS_STS_BUF_POST_RST: // 状态: 缓存后复位
					if(m_kwgtblk_rd_req_axis_valid & m_kwgtblk_rd_req_axis_ready)
						req_gen_sts <= # SIM_DELAY KWGTBLK_ACCESS_STS_IDLE;
				default:
					req_gen_sts <= # SIM_DELAY KWGTBLK_ACCESS_STS_IDLE;
			endcase
		end
	end
	
	// 更新核组参数(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_upd_kernal_set_params <= 1'b0;
		else if(aclken)
			on_upd_kernal_set_params <= # SIM_DELAY 
				((req_gen_sts == KWGTBLK_ACCESS_STS_IDLE) & blk_start) | 
				(
					(req_gen_sts == KWGTBLK_ACCESS_STS_WAIT_REQ_ACPT) & 
					m_kwgtblk_rd_req_axis_valid & m_kwgtblk_rd_req_axis_ready & 
					is_last_kernal_wgtblk & is_last_kernal_cgrp & is_last_traverse_now_kernal_set & (~is_last_kernal_set)
				);
	end
	
	// 初始化核组参数(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_init_kernal_set_params <= 1'b0;
		else if(aclken)
			on_init_kernal_set_params <= # SIM_DELAY (req_gen_sts == KWGTBLK_ACCESS_STS_IDLE) & blk_start;
	end
	
	// 当前核组的权重块宽度 - 1
	always @(posedge aclk)
	begin
		if(aclken & on_upd_kernal_set_params)
			wgtblk_w_of_now_kernal_set <= # SIM_DELAY 
				is_grp_conv_mode ? 
					n_foreach_group:
					(
						is_last_kernal_set ? 
							(kernal_num_n - visited_kernal_num_or_group_cnt):
							(MAX_WGTBLK_W - 1)
					);
	end
	
	// 通道组号偏移
	always @(posedge aclk)
	begin
		if(aclken & on_upd_kernal_set_params)
			cgrp_id_ofs <= # SIM_DELAY 
				on_init_kernal_set_params ? 
					10'd0:
					(cgrp_id_ofs + cgrpn_foreach_kernal_set + 1'b1);
	end
	
	// 当前核组的基地址
	always @(posedge aclk)
	begin
		if(aclken & on_upd_kernal_set_params)
			baseaddr_of_now_kernal_set <= # SIM_DELAY 
				on_init_kernal_set_params ? 
					kernal_wgt_baseaddr:
					incr_addr_of_now_kernal_cgrp;
	end
	
	// 更新通道组参数(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_upd_kernal_cgrp_params <= 1'b0;
		else if(aclken)
			on_upd_kernal_cgrp_params <= # SIM_DELAY 
				((req_gen_sts == KWGTBLK_ACCESS_STS_IDLE) & blk_start) | 
				(
					(req_gen_sts == KWGTBLK_ACCESS_STS_WAIT_REQ_ACPT) & 
					m_kwgtblk_rd_req_axis_valid & m_kwgtblk_rd_req_axis_ready & 
					is_last_kernal_wgtblk & (~(is_last_kernal_cgrp & is_last_traverse_now_kernal_set & is_last_kernal_set))
				);
	end
	
	// 为核组内的首通道组更新参数(标志)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(req_gen_sts == KWGTBLK_ACCESS_STS_WAIT_REQ_ACPT) & 
			m_kwgtblk_rd_req_axis_valid & m_kwgtblk_rd_req_axis_ready & 
			is_last_kernal_wgtblk & (~(is_last_kernal_cgrp & is_last_traverse_now_kernal_set & is_last_kernal_set))
		)
			upd_kernal_cgrp_params_for_first_cgrp_flag <= # SIM_DELAY is_last_kernal_cgrp;
	end
	
	// 当前通道组的表面深度 - 1
	always @(posedge aclk)
	begin
		if(aclken & on_upd_kernal_cgrp_params)
			sfc_depth_of_now_kernal_cgrp <= # SIM_DELAY 
				is_last_kernal_cgrp ? 
					(
						is_grp_conv_mode ? 
							(n_foreach_group - visited_kernal_chn_cnt):
							(kernal_chn_n - visited_kernal_chn_cnt)
					):
					(ATOMIC_C - 1);
	end
	
	// 当前通道组的基地址
	always @(posedge aclk)
	begin
		if(aclken & on_upd_kernal_cgrp_params)
			baseaddr_of_now_kernal_cgrp <= # SIM_DELAY 
				on_init_kernal_set_params ? 
					kernal_wgt_baseaddr:
					(
						((~on_upd_kernal_set_params) & upd_kernal_cgrp_params_for_first_cgrp_flag) ? 
							baseaddr_of_now_kernal_set:
							incr_addr_of_now_kernal_cgrp
					);
	end
	
	// 当前通道组的有效字节数
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				(
					kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_OUT0] | 
					kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_OUT1]
				) & shared_mul_ovld & (shared_mul_oid == SHARED_MUL_C0_TID_CONST)
			)
		)
			// 警告: 应保证通道组长度 < 2^24字节!
			btt_of_now_kernal_cgrp <= # SIM_DELAY shared_mul_res[23:0];
	end
	
	// 通道组长度更新状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_cgrp_len_upd_sts <= (1 << CGRP_BTT_UPD_STS_ONEHOT_UPTODT);
		else if(
			aclken & 
			(
				(kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_UPTODT] & on_upd_kernal_cgrp_params) | 
				(
					(
						kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_REQ0] | 
						kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_REQ1]
					) & shared_mul_c0_grant
				) | 
				(
					(
						kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_OUT0] | 
						kernal_cgrp_len_upd_sts[CGRP_BTT_UPD_STS_ONEHOT_MUL_OUT1]
					) & shared_mul_ovld & (shared_mul_oid == SHARED_MUL_C0_TID_CONST)
				)
			)
		)
			kernal_cgrp_len_upd_sts <= # SIM_DELAY {kernal_cgrp_len_upd_sts[3:0], kernal_cgrp_len_upd_sts[4]};
	end
	
	// 实际通道组号
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | (on_upd_wgtblk_pos_cnt & is_last_kernal_wgtblk)))
			actual_cgrp_id <= # SIM_DELAY 
				(blk_idle | is_last_kernal_cgrp) ? 
					10'd0:
					(actual_cgrp_id + 1'b1);
	end
	
endmodule
