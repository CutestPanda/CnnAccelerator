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
本模块: 最终结果传输请求生成单元

描述:
根据输出特征图参数、卷积核核数、权重块最大宽度、组卷积参数, 生成每个"输出特征图子表面行"的基地址和字节数

可使能的"输出子表面行信息"

当不处于组卷积模式时, 输出通道域的最大深度 = 权重块最大宽度(max_wgtblk_w), 按核并行数(ATOMIC_K)划分子表面行
当处于组卷积模式时, 输出通道域的深度 = 每组的核数(n_foreach_group + 1), 按核并行数(ATOMIC_K)划分子表面行

使用2个共享u16*u24乘法器

注意：
无

协议:
BLK CTRL
AXIS MASTER

作者: 陈家耀
日期: 2025/12/14
********************************************************************/


module fnl_res_trans_req_gen #(
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[31:0] ofmap_baseaddr, // 输出特征图基地址
	input wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	input wire[15:0] ofmap_h, // 输出特征图高度 - 1
	input wire[1:0] ofmap_data_type, // 输出特征图数据大小类型
	input wire[15:0] kernal_num_n, // 卷积核核数 - 1
	input wire[5:0] max_wgtblk_w, // 权重块最大宽度
	input wire is_grp_conv_mode, // 是否处于组卷积模式
	input wire[15:0] n_foreach_group, // 每组的通道数/核数 - 1
	input wire en_send_sub_row_msg, // 是否输出子表面行信息
	
	// 块级控制
	input wire blk_start,
	output wire blk_idle,
	output wire blk_done,
	
	// 子表面行信息(AXIS主机)
	output wire[15:0] m_sub_row_msg_axis_data, // {输出通道号(16bit)}
	output wire m_sub_row_msg_axis_last, // 整个输出特征图的最后1个子表面行(标志)
	output wire m_sub_row_msg_axis_valid,
	input wire m_sub_row_msg_axis_ready,
	
	// DMA命令(AXIS主机)
	output wire[55:0] m_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire[24:0] m_dma_cmd_axis_user, // {命令ID(24bit), 固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m_dma_cmd_axis_valid,
	input wire m_dma_cmd_axis_ready,
	
	// (共享)无符号乘法器#0
	// [计算输入]
	output wire[15:0] mul0_op_a, // 操作数A
	output wire[23:0] mul0_op_b, // 操作数B
	output wire[3:0] mul0_tid, // 操作ID
	output wire mul0_req,
	input wire mul0_grant,
	// [计算结果]
	input wire[39:0] mul0_res,
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
	
	/** 常量 **/
	// 输出特征图数据大小类型编码
	localparam OFMAP_DATA_1_BYTE = 2'b00; // 1字节
	localparam OFMAP_DATA_2_BYTE = 2'b01; // 2字节
	localparam OFMAP_DATA_4_BYTE = 2'b10; // 4字节
	// 输出特征图额外参数计算状态编码
	localparam integer OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_W = 0; // 状态: 计算"输出特征图宽度"
	localparam integer OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_H = 1; // 状态: 计算"输出特征图高度"
	localparam integer OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ = 2; // 状态: 计算"输出组通道数", 计算"输出特征图大小", 请求乘法器#0
	localparam integer OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES = 3; // 状态: 计算"输出特征图大小", 等待乘法器#0返回结果
	localparam integer OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ_2 = 4; // 状态: 计算"输出组大小", 请求乘法器#0
	localparam integer OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES_2 = 5; // 状态: 计算"输出组大小", 等待乘法器#0返回结果
	localparam integer OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_FNS = 6; // 状态: 完成
	// 更新组内子表面行偏移地址状态编码
	localparam integer SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_UTD = 0; // 状态: 最新
	localparam integer SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ = 1; // 状态: 计算"表面行字节数", 请求乘法器#1
	localparam integer SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES = 2; // 状态: 计算"表面行字节数", 等待乘法器#1返回结果
	localparam integer SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ_2 = 3; // 状态: 计算"组内子表面行偏移地址", 请求乘法器#1
	localparam integer SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES_2 = 4; // 状态: 计算"组内子表面行偏移地址", 等待乘法器#1返回结果
	// DMA命令生成状态编码
	localparam integer DMA_CMD_GEN_STS_ONEHOT_IDLE = 0; // 状态: 空闲
	localparam integer DMA_CMD_GEN_STS_ONEHOT_CAL_OFMAP_EXTRA_PARS = 1; // 状态: 计算输出特征图额外参数
	localparam integer DMA_CMD_GEN_STS_ONEHOT_UPD_OFMAP_POS_FLAG = 2; // 状态: 更新输出特征图行位置标志组
	localparam integer DMA_CMD_GEN_STS_ONEHOT_UPD_SFC_DEPTH = 3; // 状态: 更新表面深度
	localparam integer DMA_CMD_GEN_STS_ONEHOT_CAL_SUB_SFC_ROW_OFSADDR = 4; // 状态: 计算组内子表面行偏移地址
	localparam integer DMA_CMD_GEN_STS_ONEHOT_CAL_SFC_ROW_ADDR = 5; // 状态: 计算表面行地址
	localparam integer DMA_CMD_GEN_STS_ONEHOT_SEND_MSG = 6; // 状态: 发送子表面行信息
	localparam integer DMA_CMD_GEN_STS_ONEHOT_SEND_CMD = 7; // 状态: 发送DMA命令
	localparam integer DMA_CMD_GEN_STS_ONEHOT_MOV_TO_NXT_SUB_SFC_ROW = 8; // 状态: 移动到下一个子表面行
	localparam integer DMA_CMD_GEN_STS_ONEHOT_DONE = 9; // 状态: 完成
	
	/** 内部配置 **/
	localparam EN_FAST_CAL_SFC_ROW_LEN = "false"; // 是否使能尽快计算"表面行字节数"
	localparam MUL0_TID_CONST = 4'd3; // (共享)无符号乘法器#0操作ID
	localparam MUL1_TID_CONST = 4'd4; // (共享)无符号乘法器#1操作ID
	
	/**
	共享的u16递增加法器#0:
		"输出特征图宽度 - 1" + 1
		"输出特征图高度 - 1" + 1
		"每组的通道数/核数 - 1" + 1
	**/
	wire[15:0] shared_incr0_op;
	wire[15:0] shared_incr0_res;
	
	assign shared_incr0_res = shared_incr0_op + 1'b1;
	
	/**
	共享的u16大于比较器#0:
		"输出通道号偏移(下一计数值)" > "每组的核数 - 1"
		"输出通道号(下一计数值)" > "卷积核核数 - 1"
	**/
	wire[15:0] shared_gth_cmp0_op1;
	wire[15:0] shared_gth_cmp0_op2;
	wire shared_gth_cmp0_res;
	
	assign shared_gth_cmp0_res = shared_gth_cmp0_op1 > shared_gth_cmp0_op2;
	
	/**
	共享的u32加法器#0:
		"输出组基地址" + "组内子表面行基地址"
		"表面行地址" + "组内子表面行偏移地址"
		"输出组基地址" + "输出组字节数"
	**/
	wire[31:0] shared_add0_op1;
	wire[31:0] shared_add0_op2;
	wire[31:0] shared_add0_res;
	
	assign shared_add0_res = shared_add0_op1 + shared_add0_op2;
	
	/** 输出特征图额外参数 **/
	wire[1:0] ofmap_data_size_lshn; // 输出特征图数据大小导致的左移量
	reg[15:0] ofmap_w_actual; // 输出特征图宽度
	reg[15:0] ofmap_h_actual; // 输出特征图高度
	reg[15:0] ogrp_chn_n; // 输出组通道数
	reg[23:0] ofmap_size; // 输出特征图大小
	reg[31:0] ogrp_byte_n; // 输出组字节数
	reg[6:0] ofmap_extra_params_cal_sts; // 输出特征图额外参数(计算状态)
	wire ofmap_extra_params_available; // 输出特征图额外参数(可用标志)
	
	/*
	计算:
		输出特征图大小[23:0] = 输出特征图宽度[15:0] * 输出特征图高度[15:0]
		输出组大小[31:0] = 输出组通道数[15:0] * 每个特征图数据的字节数[1:0] * 输出特征图大小[23:0]
	*/
	assign mul0_op_a = 
		ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ] ? 
			ofmap_w_actual:
			(ogrp_chn_n << ofmap_data_size_lshn);
	assign mul0_op_b = 
		ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ] ? 
			(ofmap_h_actual | 24'h000000):
			ofmap_size;
	assign mul0_tid = 
		MUL0_TID_CONST;
	assign mul0_req = 
		aclken & (~blk_idle) & 
		(
			ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ] | 
			ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ_2]
		);
	
	assign shared_incr0_op = 
		({16{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_W]}} & ofmap_w) | 
		({16{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_H]}} & ofmap_h) | 
		({16{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ] & is_grp_conv_mode}} & n_foreach_group);
	
	assign ofmap_data_size_lshn = 
		(ofmap_data_type == OFMAP_DATA_1_BYTE) ? 2'b00:
		(ofmap_data_type == OFMAP_DATA_2_BYTE) ? 2'b01:
		                                         2'b10;
	
	assign ofmap_extra_params_available = (~blk_idle) & ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_FNS];
	
	// 输出特征图宽度
	always @(posedge aclk)
	begin
		if(
			aclken & 
			ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_W] & blk_idle & blk_start
		)
			ofmap_w_actual <= # SIM_DELAY shared_incr0_res;
	end
	
	// 输出特征图高度
	always @(posedge aclk)
	begin
		if(
			aclken & 
			ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_H]
		)
			ofmap_h_actual <= # SIM_DELAY shared_incr0_res;
	end
	
	// 输出组通道数
	always @(posedge aclk)
	begin
		if(
			aclken & 
			ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ] & mul0_grant
		)
			ogrp_chn_n <= # SIM_DELAY 
				is_grp_conv_mode ? 
					shared_incr0_res:
					(max_wgtblk_w | 16'h0000);
	end
	
	// 输出特征图大小
	always @(posedge aclk)
	begin
		if((ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES] & mul0_ovld & (mul0_oid == MUL0_TID_CONST)))
			ofmap_size <= # SIM_DELAY mul0_res[23:0];
	end
	
	// 输出组字节数
	always @(posedge aclk)
	begin
		if((ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES_2] & mul0_ovld & (mul0_oid == MUL0_TID_CONST)))
			ogrp_byte_n <= # SIM_DELAY mul0_res[31:0];
	end
	
	// 输出特征图额外参数(计算状态)
	always @(posedge aclk)
	begin
		if(
			(
				aclken & 
				(
					blk_idle | 
					(ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_W] & blk_start) | 
					ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_H] | 
					(
						(
							ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ] | 
							ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ_2]
						) & mul0_grant
					) | 
					(ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_FNS] & blk_done)
				)
			) | 
			(
				(
					ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES] | 
					ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES_2]
				) & mul0_ovld & (mul0_oid == MUL0_TID_CONST)
			)
		)
			ofmap_extra_params_cal_sts <= # SIM_DELAY 
				blk_idle ? 
					(
						(ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_W] & blk_start) ? 
							(1 << OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_H):
							(1 << OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_W)
					):
					(
						(
							{7{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_W]}} & 
							(1 << OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_H)
						) | 
						(
							{7{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_H]}} & 
							(1 << OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ)
						) | 
						(
							{7{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ]}} & 
							(1 << OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES)
						) | 
						(
							{7{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES]}} & 
							(1 << OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ_2)
						) | 
						(
							{7{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_REQ_2]}} & 
							(1 << OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES_2)
						) | 
						(
							{7{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_MUL0_RES_2]}} & 
							(1 << OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_FNS)
						) | 
						(
							{7{ofmap_extra_params_cal_sts[OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_FNS]}} & 
							(1 << OFMAP_EXTRA_PARS_CAL_STS_ONEHOT_W)
						)
					);
	end
	
	/** 输出通道范围计数器组 **/
	reg[15:0] ochn_id_base; // 输出通道号基准(计数器)
	reg[5:0] ochn_id_ofs; // 输出通道号偏移(计数器)
	reg[15:0] ochn_id; // 输出通道号(计数器)
	reg[15:0] sfc_row_y; // 表面行y坐标(计数器)
	reg[31:0] ogrp_baseaddr; // 输出组基地址
	reg[31:0] sub_sfc_row_baseaddr_in_grp; // 组内子表面行基地址
	wire[15:0] ochn_id_base_nxt; // 输出通道号基准(下一计数值)
	wire[5:0] ochn_id_ofs_nxt; // 输出通道号偏移(下一计数值)
	wire[15:0] ochn_id_nxt; // 输出通道号(下一计数值)
	reg is_last_ochn_rgn; // 最后1个输出通道域(标志)
	reg is_last_sub_sfc_row; // 最后1个子表面行(标志)
	reg is_arrive_oh_end; // 抵达输出特征图高度方向末尾(标志)
	reg last_sub_sfc_row_in_entire_fmap; // 整个输出特征图的最后1个子表面行(标志)
	reg is_touch_ochn_end; // 触及输出特征图组内通道方向末尾(标志)
	wire on_upd_ofmap_pos_last_flag; // 更新输出特征图行位置标志组(指示)
	wire on_move_to_nxt_ochn_rgn; // 移动到下一个输出通道域(指示)
	wire on_move_to_nxt_sub_sfc_row; // 移动到下一个子表面行(指示)
	wire on_move_in_oh; // 在输出特征图高度方向移动1行(指示)
	
	assign shared_gth_cmp0_op1 = 
		is_grp_conv_mode ? 
			(ochn_id_ofs_nxt | 16'h0000):
			ochn_id_nxt;
	assign shared_gth_cmp0_op2 = 
		is_grp_conv_mode ? 
			n_foreach_group:
			kernal_num_n;
	
	assign ochn_id_base_nxt = ochn_id_base + ogrp_chn_n;
	assign ochn_id_ofs_nxt = ochn_id_ofs + ATOMIC_K;
	assign ochn_id_nxt = ochn_id + ATOMIC_K;
	
	assign on_move_to_nxt_ochn_rgn = on_move_to_nxt_sub_sfc_row & is_last_sub_sfc_row & is_arrive_oh_end;
	assign on_move_in_oh = on_move_to_nxt_sub_sfc_row & is_last_sub_sfc_row;
	
	// 输出通道号基准(计数器)
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | on_move_to_nxt_ochn_rgn))
			ochn_id_base <= # SIM_DELAY 
				blk_idle ? 
					16'h0000:
					ochn_id_base_nxt;
	end
	
	// 输出通道号偏移(计数器)
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | on_move_to_nxt_sub_sfc_row))
			ochn_id_ofs <= # SIM_DELAY 
				(blk_idle | is_last_sub_sfc_row) ? 
					6'd0:
					ochn_id_ofs_nxt;
	end
	
	// 输出通道号(计数器)
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(blk_idle | on_move_to_nxt_sub_sfc_row)
		)
			ochn_id <= # SIM_DELAY 
				blk_idle ? 
					16'h0000:
					(
						is_last_sub_sfc_row ? 
							(
								is_arrive_oh_end ? 
									ochn_id_base_nxt:
									ochn_id_base
							):
							ochn_id_nxt
					);
	end
	
	// 表面行y坐标(计数器)
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | on_move_in_oh))
			sfc_row_y <= # SIM_DELAY 
				(blk_idle | is_arrive_oh_end) ? 
					16'h0000:
					(sfc_row_y + 1'b1);
	end
	
	// 输出组基地址
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | on_move_to_nxt_ochn_rgn))
			ogrp_baseaddr <= # SIM_DELAY 
				blk_idle ? 
					ofmap_baseaddr:
					shared_add0_res;
	end
	
	// 组内子表面行基地址
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | on_move_to_nxt_sub_sfc_row))
			sub_sfc_row_baseaddr_in_grp <= # SIM_DELAY 
				(blk_idle | is_last_sub_sfc_row) ? 
					32'h0000_0000:
					(sub_sfc_row_baseaddr_in_grp + (({2'b00, ofmap_size} << ofmap_data_size_lshn) * ATOMIC_K));
	end
	
	// 最后1个输出通道域(标志), 最后1个子表面行(标志), 抵达输出特征图高度方向末尾(标志), 整个输出特征图的最后1个子表面行(标志)
	always @(posedge aclk)
	begin
		if(aclken & on_upd_ofmap_pos_last_flag)
		begin
			is_last_ochn_rgn <= # SIM_DELAY 
				ochn_id_base_nxt > kernal_num_n;
			
			/*
			is_grp_conv_mode ? 
				(ochn_id_ofs_nxt > n_foreach_group):
				(
					(ochn_id_ofs_nxt >= max_wgtblk_w) | 
					(ochn_id_nxt > kernal_num_n)
				)
			*/
			is_last_sub_sfc_row <= # SIM_DELAY 
				((~is_grp_conv_mode) & (ochn_id_ofs_nxt >= max_wgtblk_w)) | 
				shared_gth_cmp0_res;
			
			is_arrive_oh_end <= # SIM_DELAY 
				sfc_row_y == ofmap_h;
			
			last_sub_sfc_row_in_entire_fmap <= # SIM_DELAY 
				(ochn_id_base_nxt > kernal_num_n) & 
				(sfc_row_y == ofmap_h) & 
				(
					((~is_grp_conv_mode) & (ochn_id_ofs_nxt >= max_wgtblk_w)) | 
					shared_gth_cmp0_res
				);
		end
	end
	
	// 触及输出特征图组内通道方向末尾(标志)
	always @(posedge aclk)
	begin
		if(aclken & on_upd_ofmap_pos_last_flag)
		begin
			/*
			is_grp_conv_mode ? 
				(ochn_id_ofs_nxt > n_foreach_group):
				(ochn_id_nxt > kernal_num_n)
			*/
			is_touch_ochn_end <= # SIM_DELAY shared_gth_cmp0_res;
		end
	end
	
	/** 当前输出表面行参数 **/
	// [表面深度]
	reg[5:0] cur_sfc_depth; // 表面深度
	wire on_upd_sfc_depth; // 更新表面深度(指示)
	// [表面行字节数]
	reg[23:0] sfc_row_len; // 表面行字节数
	reg[31:0] sub_sfc_row_ofsaddr_in_grp; // 组内子表面行偏移地址
	reg[4:0] sub_sfc_row_ofsaddr_upd_sts; // 更新组内子表面行偏移地址(状态)
	wire on_upd_sub_sfc_row_ofsaddr; // 更新组内子表面行偏移地址(指示)
	wire sub_sfc_row_ofsaddr_available; // 组内子表面行偏移地址(可用标志)
	// [表面行地址]
	reg[31:0] sfc_row_addr; // 表面行地址
	wire on_upd_sfc_row_addr; // 更新表面行地址(指示)
	reg sfc_row_addr_upd_stage; // 更新表面行地址(阶段)
	wire sfc_row_addr_available; // 表面行地址(可用标志)
	
	/*
	计算:
		表面行字节数[23:0] = 输出特征图宽度[15:0] * 表面深度[5:0] * 每个特征图数据的字节数[1:0]
		组内子表面行偏移地址[31:0] = 表面行y坐标[15:0] * 表面行字节数[23:0]
	*/
	assign mul1_op_a = 
		sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ_2] ? 
			sfc_row_y:
			ofmap_w_actual;
	assign mul1_op_b = 
		sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ_2] ? 
			sfc_row_len:
			({2'b00, cur_sfc_depth} << ofmap_data_size_lshn) | 24'h000000;
	assign mul1_tid = 
		MUL1_TID_CONST;
	assign mul1_req = 
		aclken & (~blk_idle) & 
		(
			(
				(EN_FAST_CAL_SFC_ROW_LEN == "true") & 
				sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_UTD] & on_upd_sub_sfc_row_ofsaddr
			) | 
			sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ] | 
			sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ_2]
		);
	
	assign shared_add0_op1 = 
		sfc_row_addr_upd_stage ? 
			sfc_row_addr:
			ogrp_baseaddr;
	assign shared_add0_op2 = 
		(sfc_row_addr_upd_stage | on_upd_sfc_row_addr) ? 
			(
				sfc_row_addr_upd_stage ? 
					sub_sfc_row_ofsaddr_in_grp:
					sub_sfc_row_baseaddr_in_grp
			):
			ogrp_byte_n;
	
	assign sub_sfc_row_ofsaddr_available = 
		(~blk_idle) & sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_UTD] & (~on_upd_sub_sfc_row_ofsaddr);
	assign sfc_row_addr_available = 
		(~blk_idle) & (~sfc_row_addr_upd_stage) & (~on_upd_sfc_row_addr);
	
	// 表面深度
	always @(posedge aclk)
	begin
		if(aclken & on_upd_sfc_depth)
			cur_sfc_depth <= # SIM_DELAY 
				/*
				is_grp_conv_mode ? 
					(
						is_touch_ochn_end ? 
							(n_foreach_group - (ochn_id_ofs | 16'h0000) + 1'b1):
							ATOMIC_K
					):
					(
						is_last_sub_sfc_row ? 
							(
								is_touch_ochn_end ? 
									(kernal_num_n - ochn_id + 1'b1):
									((max_wgtblk_w | 16'h0000) - (ochn_id_ofs | 16'h0000))
							):
							ATOMIC_K
					)
				*/
				(is_grp_conv_mode ? is_touch_ochn_end:is_last_sub_sfc_row) ? 
					(
						(
							is_grp_conv_mode ? 
								n_foreach_group:
								(
									is_touch_ochn_end ? 
										kernal_num_n:
										(max_wgtblk_w | 16'h0000)
								)
						) - 
						(
							((~is_grp_conv_mode) & is_touch_ochn_end) ? 
								ochn_id:
								(ochn_id_ofs | 16'h0000)
						) + 
						(
							(is_grp_conv_mode | is_touch_ochn_end) ? 
								1'b1:
								1'b0
						)
					):
					ATOMIC_K;
	end
	
	// 表面行字节数
	always @(posedge aclk)
	begin
		if(sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES] & mul1_ovld & (mul1_oid == MUL1_TID_CONST))
			sfc_row_len <= # SIM_DELAY mul1_res[23:0];
	end
	
	// 组内子表面行偏移地址
	always @(posedge aclk)
	begin
		if(sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES_2] & mul1_ovld & (mul1_oid == MUL1_TID_CONST))
			sub_sfc_row_ofsaddr_in_grp <= # SIM_DELAY mul1_res[31:0];
	end
	
	// 更新组内子表面行偏移地址(状态)
	always @(posedge aclk)
	begin
		if(
			(
				aclken & 
				(
					blk_idle | 
					(sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_UTD] & on_upd_sub_sfc_row_ofsaddr) | 
					(
						(
							sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ] | 
							sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ_2]
						) & mul1_grant
					)
				)
			) | 
			(
				(
					sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES] | 
					sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES_2]
				) & mul1_ovld & (mul1_oid == MUL1_TID_CONST)
			)
		)
			sub_sfc_row_ofsaddr_upd_sts <= # SIM_DELAY 
				blk_idle ? 
					(1 << SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_UTD):
					(
						(
							{5{sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_UTD]}} & 
							(
								((EN_FAST_CAL_SFC_ROW_LEN == "true") & mul1_grant) ? 
									(1 << SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES):
									(1 << SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ)
							)
						) | 
						(
							{5{sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ]}} & 
							(1 << SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES)
						) | 
						(
							{5{sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES]}} & 
							(1 << SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ_2)
						) | 
						(
							{5{sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_REQ_2]}} & 
							(1 << SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES_2)
						) | 
						(
							{5{sub_sfc_row_ofsaddr_upd_sts[SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_MUL1_RES_2]}} & 
							(1 << SUB_SFC_ROW_OFSADDR_UPD_STS_ONEHOT_UTD)
						)
					);
	end
	
	// 表面行地址
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(sfc_row_addr_upd_stage | on_upd_sfc_row_addr)
		)
			sfc_row_addr <= # SIM_DELAY shared_add0_res;
	end
	
	// 更新表面行地址(阶段)
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | sfc_row_addr_upd_stage | on_upd_sfc_row_addr))
			sfc_row_addr_upd_stage <= # SIM_DELAY ~(blk_idle | sfc_row_addr_upd_stage);
	end
	
	/** DMA命令生成 **/
	reg[23:0] dma_cmd_id; // DMA命令ID
	reg[9:0] dma_cmd_gen_sts; // DMA命令生成(状态)
	
	assign blk_idle = dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_IDLE];
	assign blk_done = dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_DONE];
	
	assign m_sub_row_msg_axis_data = {
		ochn_id // 输出通道号(16bit)
	};
	assign m_sub_row_msg_axis_last = last_sub_sfc_row_in_entire_fmap;
	assign m_sub_row_msg_axis_valid = aclken & dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_SEND_MSG];
	
	assign m_dma_cmd_axis_data = 
		{
			sfc_row_len, // 待传输字节数(24bit)
			sfc_row_addr // 传输首地址(32bit)
		};
	assign m_dma_cmd_axis_user = {
		dma_cmd_id, // DMA命令ID(24bit)
		1'b0 // 递增传输(1bit)
	};
	assign m_dma_cmd_axis_valid = aclken & dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_SEND_CMD];
	
	assign on_upd_ofmap_pos_last_flag = dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_UPD_OFMAP_POS_FLAG];
	assign on_move_to_nxt_sub_sfc_row = dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_MOV_TO_NXT_SUB_SFC_ROW];
	
	assign on_upd_sfc_depth = dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_UPD_SFC_DEPTH];
	
	assign on_upd_sub_sfc_row_ofsaddr = dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_UPD_SFC_DEPTH];
	assign on_upd_sfc_row_addr = dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_CAL_SUB_SFC_ROW_OFSADDR] & sub_sfc_row_ofsaddr_available;
	
	// DMA命令ID
	always @(posedge aclk)
	begin
		if(aclken & (blk_idle | on_move_to_nxt_sub_sfc_row))
			dma_cmd_id <= # SIM_DELAY 
				blk_idle ? 
					24'h000000:
					(dma_cmd_id + 1'b1);
	end
	
	// DMA命令生成(状态)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dma_cmd_gen_sts <= 1 << DMA_CMD_GEN_STS_ONEHOT_IDLE;
		else if(
			aclken & 
			(
				(dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_IDLE] & blk_start) | 
				(dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_CAL_OFMAP_EXTRA_PARS] & ofmap_extra_params_available) | 
				dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_UPD_OFMAP_POS_FLAG] | 
				dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_UPD_SFC_DEPTH] | 
				(dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_CAL_SUB_SFC_ROW_OFSADDR] & sub_sfc_row_ofsaddr_available) | 
				(dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_CAL_SFC_ROW_ADDR] & sfc_row_addr_available) | 
				(dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_SEND_MSG] & m_sub_row_msg_axis_ready) | 
				(dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_SEND_CMD] & m_dma_cmd_axis_ready) | 
				dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_MOV_TO_NXT_SUB_SFC_ROW] | 
				dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_DONE]
			)
		)
			dma_cmd_gen_sts <= # SIM_DELAY 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_IDLE]}} & 
					(1 << DMA_CMD_GEN_STS_ONEHOT_CAL_OFMAP_EXTRA_PARS)
				) | 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_CAL_OFMAP_EXTRA_PARS]}} & 
					(1 << DMA_CMD_GEN_STS_ONEHOT_UPD_OFMAP_POS_FLAG)
				) | 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_UPD_OFMAP_POS_FLAG]}} & 
					(1 << DMA_CMD_GEN_STS_ONEHOT_UPD_SFC_DEPTH)
				) | 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_UPD_SFC_DEPTH]}} & 
					(1 << DMA_CMD_GEN_STS_ONEHOT_CAL_SUB_SFC_ROW_OFSADDR)
				) | 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_CAL_SUB_SFC_ROW_OFSADDR]}} & 
					(1 << DMA_CMD_GEN_STS_ONEHOT_CAL_SFC_ROW_ADDR)
				) | 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_CAL_SFC_ROW_ADDR]}} & 
					(
						en_send_sub_row_msg ? 
							(1 << DMA_CMD_GEN_STS_ONEHOT_SEND_MSG):
							(1 << DMA_CMD_GEN_STS_ONEHOT_SEND_CMD)
					)
				) | 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_SEND_MSG]}} & 
					(1 << DMA_CMD_GEN_STS_ONEHOT_SEND_CMD)
				) | 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_SEND_CMD]}} & 
					(1 << DMA_CMD_GEN_STS_ONEHOT_MOV_TO_NXT_SUB_SFC_ROW)
				) | 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_MOV_TO_NXT_SUB_SFC_ROW]}} & 
					(
						(is_last_sub_sfc_row & is_arrive_oh_end & is_last_ochn_rgn) ? 
							(1 << DMA_CMD_GEN_STS_ONEHOT_DONE):
							(1 << DMA_CMD_GEN_STS_ONEHOT_UPD_OFMAP_POS_FLAG)
					)
				) | 
				(
					{10{dma_cmd_gen_sts[DMA_CMD_GEN_STS_ONEHOT_DONE]}} & 
					(1 << DMA_CMD_GEN_STS_ONEHOT_IDLE)
				);
	end
	
endmodule
