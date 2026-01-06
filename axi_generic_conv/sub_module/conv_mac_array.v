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
本模块: 卷积乘加阵列

描述:
ATOMIC_K个卷积乘加单元

带有全局时钟使能

支持计算轮次拓展, 以适应更宽(>ATOMIC_K)的卷积核权重块
支持跳过空的(未加载权重的)计算轮次

带有卷积核权重乒乓缓存, 可存储2个权重块

使用ATOMIC_K*ATOMIC_C个s16*s16乘法器实现特征图数据和卷积核权重相乘
使用ATOMIC_K个ATOMIC_C输入、32位加法器实现通道累加

 运算数据格式  |     计算时延
--------------------------------
     INT16     | 2 + log2(ATOMIC_C)
     FP16      | 4 + log2(ATOMIC_C)
     INT8      |      暂不支持

FP16模式时, 尾数偏移为-50

注意：
外部有符号乘法器的计算时延 = 1clk

协议:
无

作者: 陈家耀
日期: 2025/12/30
********************************************************************/


module conv_mac_array #(
	parameter integer MAC_ARRAY_CLK_RATE = 1, // 计算核心时钟倍率(>=1)
	parameter integer MAX_CAL_ROUND = 1, // 最大的计算轮次(1~16)
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter EN_SMALL_FP16 = "true", // 是否处理极小FP16
	parameter integer INFO_ALONG_WIDTH = 1, // 随路数据的位宽(必须>=1)
	parameter USE_INNER_SFC_CNT = "true", // 是否使用内部表面计数器
	parameter TO_SKIP_EMPTY_CAL_ROUND = "true", // 是否跳过空的计算轮次
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	// 计算核心时钟和复位
	input wire mac_array_aclk,
	input wire mac_array_aresetn,
	input wire mac_array_aclken,
	
	// 使能信号
	input wire en_mac_array, // 使能乘加阵列
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	input wire[3:0] cal_round, // 计算轮次 - 1
	
	// 乘加阵列输入
	// [特征图]
	input wire[ATOMIC_C*16-1:0] array_i_ftm_sfc, // 特征图表面(数据)
	input wire[INFO_ALONG_WIDTH-1:0] array_i_ftm_info_along, // 随路数据
	input wire array_i_ftm_sfc_last, // 卷积核参数对应的最后1个特征图表面(标志)
	input wire array_i_ftm_sfc_masked, // 特征图表面(无效标志)
	input wire array_i_ftm_sfc_vld, // 有效标志
	output wire array_i_ftm_sfc_rdy, // 就绪标志
	// [卷积核]
	input wire[ATOMIC_C*16-1:0] array_i_kernal_sfc, // 卷积核表面(数据)
	input wire array_i_kernal_sfc_last, // 卷积核权重块对应的最后1个表面(标志)
	// 说明: 仅当不使用内部表面计数器(USE_INNER_SFC_CNT == "false")时可用
	input wire[MAX_CAL_ROUND*ATOMIC_K-1:0] array_i_kernal_sfc_id, // 卷积核表面在权重块中的独热码编号
	input wire array_i_kernal_sfc_vld, // 有效指示
	output wire array_i_kernal_buf_full_n, // 卷积核权重缓存满(标志)
	
	// 乘加阵列输出
	output wire[ATOMIC_K*48-1:0] array_o_res, // 计算结果(数据, {指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)})
	output wire[3:0] array_o_cal_round_id, // 计算轮次编号
	output wire array_o_is_last_cal_round, // 是否最后1轮计算
	output wire[INFO_ALONG_WIDTH-1:0] array_o_res_info_along, // 随路数据
	output wire[ATOMIC_K-1:0] array_o_res_mask, // 计算结果输出项掩码
	output wire array_o_res_vld, // 有效标志
	input wire array_o_res_rdy, // 就绪标志
	
	// 外部有符号乘法器
	output wire mul_clk,
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_a, // 操作数A
	output wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_op_b, // 操作数B
	output wire[ATOMIC_K-1:0] mul_ce, // 计算使能
	input wire[ATOMIC_K*ATOMIC_C*32-1:0] mul_res // 计算结果
);
	
	/** 乘加阵列控制 **/
	wire rst_mac_array; // 复位乘加阵列
	wire async_array_i_vld; // 异步乘加阵列输入有效(标志)
	wire async_array_i_rdy; // 异步乘加阵列输入就绪(标志)
	
	assign rst_mac_array = ~en_mac_array;
	
	/** 卷积核权重乒乓缓存 **/
	reg kernal_buf_wsel; // 写选择
	reg kernal_buf_rsel; // 读选择
	reg[1:0] kernal_buf_stored; // 存储有效标志
	wire kernal_buf_empty_n; // 卷积核权重缓存空(标志)
	wire kernal_buf_full_n; // 卷积核权重缓存满(标志)
	reg[MAX_CAL_ROUND*ATOMIC_K-1:0] kernal_buf_loaded_sfc_vec; // 已加载表面(标志向量)
	wire[MAX_CAL_ROUND*ATOMIC_K-1:0] kernal_buf_loaded_sfc_vec_new; // 最新的已加载表面(标志向量)
	reg[ATOMIC_K*ATOMIC_C*16-1:0] kernal_buf_data[0:MAX_CAL_ROUND*2-1]; // 缓存的卷积核权重(数据)
	reg[MAX_CAL_ROUND-1:0] kernal_region_vld[0:1]; // 缓存的权重域(有效标志)
	reg[MAX_CAL_ROUND*ATOMIC_K-1:0] kernal_buf_mask[0:1]; // 缓存的卷积核权重(掩码)
	reg[MAX_CAL_ROUND*ATOMIC_K-1:0] kernal_sfc_cnt; // 卷积核表面计数器
	
	assign array_i_kernal_buf_full_n = kernal_buf_full_n;
	
	assign kernal_buf_empty_n = (~rst_mac_array) & (kernal_buf_stored[0] | kernal_buf_stored[1]);
	assign kernal_buf_full_n = (~rst_mac_array) & (~(kernal_buf_stored[0] & kernal_buf_stored[1]));
	
	assign kernal_buf_loaded_sfc_vec_new = 
		kernal_buf_loaded_sfc_vec | 
		(
			(USE_INNER_SFC_CNT == "true") ? 
				kernal_sfc_cnt:
				array_i_kernal_sfc_id
		);
	
	// 写选择
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_buf_wsel <= 1'b0;
		else if(
			aclken & 
			(
				rst_mac_array | 
				(array_i_kernal_sfc_vld & array_i_kernal_sfc_last & kernal_buf_full_n)
			)
		)
			kernal_buf_wsel <= # SIM_DELAY (~rst_mac_array) & (~kernal_buf_wsel);
	end
	
	// 读选择
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_buf_rsel <= 1'b0;
		else if(
			aclken & 
			(
				rst_mac_array | 
				(array_i_ftm_sfc_vld & array_i_ftm_sfc_rdy & array_i_ftm_sfc_last)
			)
		)
			kernal_buf_rsel <= # SIM_DELAY (~rst_mac_array) & (~kernal_buf_rsel);
	end
	
	// 存储有效标志
	genvar kernal_buf_stored_i;
	generate
		for(kernal_buf_stored_i = 0;kernal_buf_stored_i < 2;kernal_buf_stored_i = kernal_buf_stored_i + 1)
		begin:kernal_buf_stored_blk
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					kernal_buf_stored[kernal_buf_stored_i] <= 1'b0;
				else if(
					aclken & 
					// 断言: 写和读某个卷积核权重缓存不会同时发生
					(
						rst_mac_array | 
						(
							array_i_kernal_sfc_vld & array_i_kernal_sfc_last & kernal_buf_full_n & 
							(kernal_buf_wsel == kernal_buf_stored_i)
						) | 
						(
							array_i_ftm_sfc_vld & array_i_ftm_sfc_rdy & array_i_ftm_sfc_last & 
							(kernal_buf_rsel == kernal_buf_stored_i)
						)
					)
				)
					kernal_buf_stored[kernal_buf_stored_i] <= # SIM_DELAY 
						(~rst_mac_array) & 
						array_i_kernal_sfc_vld & array_i_kernal_sfc_last & kernal_buf_full_n & 
						(kernal_buf_wsel == kernal_buf_stored_i);
			end
		end
	endgenerate
	
	genvar kernal_buf_sfc_i;
	generate
		for(kernal_buf_sfc_i = 0;kernal_buf_sfc_i < ATOMIC_K * MAX_CAL_ROUND * 2;kernal_buf_sfc_i = kernal_buf_sfc_i + 1)
		begin:kernal_buf_sfc_blk
			if(kernal_buf_sfc_i < ATOMIC_K * MAX_CAL_ROUND)
			begin
				// 已加载表面(标志)
				always @(posedge aclk or negedge aresetn)
				begin
					if(~aresetn)
						kernal_buf_loaded_sfc_vec[kernal_buf_sfc_i] <= 1'b0;
					else if(
						aclken & 
						(
							rst_mac_array | 
							(
								array_i_kernal_sfc_vld & kernal_buf_full_n & 
								(array_i_kernal_sfc_last | (~kernal_buf_loaded_sfc_vec[kernal_buf_sfc_i]))
							)
						)
					)
						kernal_buf_loaded_sfc_vec[kernal_buf_sfc_i] <= # SIM_DELAY 
							(~rst_mac_array) & 
							(~array_i_kernal_sfc_last) & 
							(
								(USE_INNER_SFC_CNT == "true") ? 
									kernal_sfc_cnt[kernal_buf_sfc_i]:
									array_i_kernal_sfc_id[kernal_buf_sfc_i]
							);
				end
			end
			
			// 缓存的卷积核权重(数据)
			always @(posedge aclk)
			begin
				if(
					aclken & 
					array_i_kernal_sfc_vld & kernal_buf_full_n & 
					(kernal_buf_wsel == (kernal_buf_sfc_i / (ATOMIC_K * MAX_CAL_ROUND))) & 
					(
						(USE_INNER_SFC_CNT == "true") ? 
							kernal_sfc_cnt[kernal_buf_sfc_i%(ATOMIC_K*MAX_CAL_ROUND)]:
							array_i_kernal_sfc_id[kernal_buf_sfc_i%(ATOMIC_K*MAX_CAL_ROUND)]
					)
				)
					kernal_buf_data[kernal_buf_sfc_i/ATOMIC_K][
						((kernal_buf_sfc_i%ATOMIC_K)+1)*(ATOMIC_C*16)-1:
						(kernal_buf_sfc_i%ATOMIC_K)*(ATOMIC_C*16)] <= # SIM_DELAY 
							array_i_kernal_sfc;
			end
		end
	endgenerate
	
	// 缓存的权重域(有效标志)
	genvar kernal_region_vld_i;
	generate
		for(kernal_region_vld_i = 0;kernal_region_vld_i < MAX_CAL_ROUND*2;kernal_region_vld_i = kernal_region_vld_i + 1)
		begin
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					kernal_region_vld[kernal_region_vld_i/MAX_CAL_ROUND][kernal_region_vld_i%MAX_CAL_ROUND] <= 1'b0;
				else if(
					aclken & 
					(
						rst_mac_array | 
						(
							array_i_kernal_sfc_vld & array_i_kernal_sfc_last & kernal_buf_full_n & 
							(kernal_buf_wsel == (kernal_region_vld_i/MAX_CAL_ROUND))
						)
					)
				)
					kernal_region_vld[kernal_region_vld_i/MAX_CAL_ROUND][kernal_region_vld_i%MAX_CAL_ROUND] <= # SIM_DELAY 
						(~rst_mac_array) & 
						(
							|kernal_buf_loaded_sfc_vec_new[
								((kernal_region_vld_i%MAX_CAL_ROUND)+1)*ATOMIC_K-1:
								(kernal_region_vld_i%MAX_CAL_ROUND)*ATOMIC_K
							]
						);
			end
		end
	endgenerate
	
	genvar kernal_buf_mask_i;
	generate
		for(kernal_buf_mask_i = 0;kernal_buf_mask_i < 2;kernal_buf_mask_i = kernal_buf_mask_i + 1)
		begin:kernal_buf_mask_blk
			// 缓存的卷积核权重(掩码)
			always @(posedge aclk)
			begin
				if(
					aclken & 
					array_i_kernal_sfc_vld & array_i_kernal_sfc_last & kernal_buf_full_n & 
					(kernal_buf_wsel == kernal_buf_mask_i)
				)
					kernal_buf_mask[kernal_buf_mask_i] <= # SIM_DELAY 
						kernal_buf_loaded_sfc_vec_new;
			end
		end
	endgenerate
	
	// 卷积核表面计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_sfc_cnt <= 1;
		else if(
			aclken & 
			(
				rst_mac_array | 
				(array_i_kernal_sfc_vld & kernal_buf_full_n)
			)
		)
			kernal_sfc_cnt <= # SIM_DELAY 
				(rst_mac_array | array_i_kernal_sfc_last) ? 
					1:
					((kernal_sfc_cnt << 1) | (kernal_sfc_cnt >> (MAX_CAL_ROUND * ATOMIC_K - 1)));
	end
	
	/** 计算轮次拓展 **/
	reg[3:0] cal_round_cnt; // 计算轮次计数器
	reg[MAX_CAL_ROUND-1:0] cal_round_onehot; // 计算轮次独热码
	wire nxt_kernal_rgn_to_cal_invld; // 下一待计算权重域无效(标志)
	
	assign array_i_ftm_sfc_rdy = 
		aclken & (~rst_mac_array) & kernal_buf_empty_n & 
		((MAC_ARRAY_CLK_RATE == 1) ? array_o_res_rdy:async_array_i_rdy) & 
		((cal_round_cnt == cal_round) | nxt_kernal_rgn_to_cal_invld);
	
	assign nxt_kernal_rgn_to_cal_invld = 
		(TO_SKIP_EMPTY_CAL_ROUND == "true") & 
		(
			(
				kernal_region_vld[kernal_buf_rsel] & 
				((cal_round_onehot << 1) | (cal_round_onehot >> (MAX_CAL_ROUND-1)))
			) == 16'h0000
		);
	
	// 计算轮次计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cal_round_cnt <= 4'd0;
		else if(
			aclken & 
			(
				rst_mac_array | 
				(array_i_ftm_sfc_vld & kernal_buf_empty_n & ((MAC_ARRAY_CLK_RATE == 1) ? array_o_res_rdy:async_array_i_rdy))
			)
		)
			cal_round_cnt <= # SIM_DELAY 
				(rst_mac_array | (cal_round_cnt == cal_round) | nxt_kernal_rgn_to_cal_invld) ? 
					4'd0:
					(cal_round_cnt + 1'b1);
	end
	
	// 计算轮次独热码
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cal_round_onehot <= 1;
		else if(
			aclken & 
			(
				rst_mac_array | 
				(array_i_ftm_sfc_vld & kernal_buf_empty_n & ((MAC_ARRAY_CLK_RATE == 1) ? array_o_res_rdy:async_array_i_rdy))
			)
		)
			cal_round_onehot <= # SIM_DELAY 
				(rst_mac_array | (cal_round_cnt == cal_round) | nxt_kernal_rgn_to_cal_invld) ? 
					1:
					((cal_round_onehot << 1) | (cal_round_onehot >> (MAX_CAL_ROUND-1)));
	end
	
	/** 乘加阵列 **/
	wire[4:0] kernal_wgt_sel; // 卷积核权重选择
	wire[ATOMIC_K*ATOMIC_C*16-1:0] kernal_buf_data_cur; // 当前选择的卷积核权重(数据)
	wire[ATOMIC_K-1:0] kernal_buf_mask_cur; // 当前选择的卷积核权重(掩码)
	wire[ATOMIC_K+INFO_ALONG_WIDTH+4+1-1:0] mac_in_info_along; // 输入随路数据
	wire[ATOMIC_K-1:0] mac_in_valid; // 输入有效指示
	wire[ATOMIC_K+INFO_ALONG_WIDTH+4+1-1:0] mac_out_info_along_arr[0:ATOMIC_K-1]; // 随路数据(数组)
	wire[ATOMIC_K-1:0] array_o_res_vld_vec; // 计算结果输出有效(指示向量)
	
	assign {array_o_res_mask, array_o_res_info_along, array_o_cal_round_id, array_o_is_last_cal_round} = mac_out_info_along_arr[0];
	// 断言: array_o_res_vld_vec只能是{ATOMIC_K{1'b1}}或{ATOMIC_K{1'b0}}
	assign array_o_res_vld = aclken & array_o_res_vld_vec[0];
	
	assign kernal_wgt_sel = 
		(
			kernal_buf_rsel ? 
				MAX_CAL_ROUND:
				0
		) + 
		(
			(cal_round_cnt >= (MAX_CAL_ROUND - 1)) ? 
				(MAX_CAL_ROUND - 1):
				cal_round_cnt
		);
	assign kernal_buf_data_cur = kernal_buf_data[kernal_wgt_sel];
	assign kernal_buf_mask_cur = kernal_buf_mask[kernal_buf_rsel] >> (cal_round_cnt * ATOMIC_K);
	
	assign mac_in_info_along[0] = (cal_round_cnt == cal_round) | nxt_kernal_rgn_to_cal_invld;
	assign mac_in_info_along[INFO_ALONG_WIDTH+4+1-1:1] = {array_i_ftm_info_along, cal_round_cnt};
	assign mac_in_info_along[ATOMIC_K+INFO_ALONG_WIDTH+4+1-1:INFO_ALONG_WIDTH+4+1] = kernal_buf_mask_cur;
	
	genvar mac_cell_i;
	generate
		if(MAC_ARRAY_CLK_RATE == 1)
		begin
			for(mac_cell_i = 0;mac_cell_i < ATOMIC_K;mac_cell_i = mac_cell_i + 1)
			begin:mac_array_blk
				assign mul_clk = aclk;
				
				assign mac_in_valid[mac_cell_i] = 
					aclken & (~rst_mac_array) & 
					array_i_ftm_sfc_vld & kernal_buf_empty_n & array_o_res_rdy & 
					kernal_buf_mask_cur[mac_cell_i]; // 若当前权重表面未加载, 则对应CELL无需作这个表面的乘加计算
				
				conv_mac_cell #(
					.ATOMIC_C(ATOMIC_C),
					.EN_SMALL_FP16(EN_SMALL_FP16),
					.INFO_ALONG_WIDTH(ATOMIC_K + INFO_ALONG_WIDTH + 4 + 1),
					.SIM_DELAY(SIM_DELAY)
				)mac_cell_u(
					.aclk(aclk),
					.aresetn(aresetn),
					.aclken(aclken & array_o_res_rdy),
					
					.calfmt(calfmt),
					
					.mac_in_ftm(array_i_ftm_sfc),
					.mac_in_wgt(kernal_buf_data_cur[(mac_cell_i+1)*(ATOMIC_C*16)-1:mac_cell_i*(ATOMIC_C*16)]),
					.mac_in_ftm_masked(array_i_ftm_sfc_masked),
					.mac_in_info_along(mac_in_info_along),
					.mac_in_valid(mac_in_valid[mac_cell_i]),
					
					.mac_out_exp(array_o_res[mac_cell_i*48+47:mac_cell_i*48+40]),
					.mac_out_frac(array_o_res[mac_cell_i*48+39:mac_cell_i*48+0]),
					.mac_out_info_along(mac_out_info_along_arr[mac_cell_i]),
					.mac_out_valid(array_o_res_vld_vec[mac_cell_i]),
					
					.mul_op_a(mul_op_a[(mac_cell_i+1)*(ATOMIC_C*16)-1:mac_cell_i*(ATOMIC_C*16)]),
					.mul_op_b(mul_op_b[(mac_cell_i+1)*(ATOMIC_C*16)-1:mac_cell_i*(ATOMIC_C*16)]),
					.mul_ce(mul_ce[mac_cell_i]),
					.mul_res(mul_res[(mac_cell_i+1)*(ATOMIC_C*32)-1:mac_cell_i*(ATOMIC_C*32)])
				);
			end
		end
		else
		begin
			assign mul_clk = mac_array_aclk;
			
			assign async_array_i_vld = 
				aclken & (~rst_mac_array) & 
				array_i_ftm_sfc_vld & kernal_buf_empty_n;
			
			conv_async_mac_array_core #(
				.MAC_ARRAY_CLK_RATE(MAC_ARRAY_CLK_RATE),
				.ATOMIC_K(ATOMIC_K),
				.ATOMIC_C(ATOMIC_C),
				.INFO_ALONG_WIDTH(ATOMIC_K + INFO_ALONG_WIDTH + 4 + 1),
				.EN_SMALL_FP16(EN_SMALL_FP16),
				.SIM_DELAY(SIM_DELAY)
			)async_mac_array_core_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				.mac_array_aclk(mac_array_aclk),
				.mac_array_aresetn(mac_array_aresetn),
				.mac_array_aclken(mac_array_aclken),
				
				.en_mac_array(en_mac_array),
				
				.calfmt(calfmt),
				
				.array_i_ftm_sfc_data(array_i_ftm_sfc),
				.array_i_kernal_wgtblk_data(kernal_buf_data_cur),
				.array_i_ftm_sfc_masked(array_i_ftm_sfc_masked),
				.array_i_kernal_mask(kernal_buf_mask_cur),
				.array_i_info_along(mac_in_info_along),
				.array_i_vld(async_array_i_vld),
				.array_i_rdy(async_array_i_rdy),
				
				.array_o_res(array_o_res),
				.array_o_info_along(mac_out_info_along_arr[0]),
				.array_o_vld(array_o_res_vld_vec[0]),
				.array_o_rdy(aclken & array_o_res_rdy),
				
				.mul_op_a(mul_op_a),
				.mul_op_b(mul_op_b),
				.mul_ce(mul_ce),
				.mul_res(mul_res)
			);
		end
	endgenerate
	
endmodule
