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
本模块: 卷积中间结果累加与缓存

描述:
带有全局时钟使能

支持为输出特征图行动态分配BANK数量, 从而提高MEM利用率

当BANK未被填充时,
缓存MEM读端口 --> (更新写端口看到的写指针) --> 读出原中间结果(2clk) --> 累加计算(2clk或9clk) --> 
	(写入新结果) --> (更新读端口看到的写指针, 更新写列计数器, [设置BANK为填充状态]) --> 缓存MEM写端口

当BANK已被填充时,
缓存MEM读端口 --> (更新读端口看到的读指针, 更新读列计数器) --> 读数据流水线(2clk) --> 
	(更新写端口看到的读指针, [设置BANK为未填充状态])

判满使用"写端口看到的写指针"和"写端口看到的读指针"
判空使用"读端口看到的读指针"和"读端口看到的写指针"

注意：
启用计算轮次拓展功能时, 无需给出"输出特征图宽度 - 1", 实际的最终结果表面行长度 = 输出特征图宽度 * 计算轮次

协议:
AXIS MASTER/SLAVE
MEM MASTER

作者: 陈家耀
日期: 2025/12/18
********************************************************************/


module conv_middle_res_acmlt_buf #(
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer RBUF_BANK_N = 8, // 缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512, // 缓存MEM深度(16 | ...)
	parameter integer INFO_ALONG_WIDTH = 2, // 随路数据的位宽(必须>=1)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	input wire[3:0] row_n_bufferable, // 可缓存行数 - 1
	input wire[3:0] bank_n_foreach_ofmap_row, // 每个输出特征图行所占用的缓存MEM个数
	input wire[3:0] max_upd_latency, // 最大的更新时延
	input wire en_cal_round_ext, // 是否启用计算轮次拓展功能
	input wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	
	// 中间结果输入(AXIS从机)
	input wire[ATOMIC_K*48-1:0] s_axis_mid_res_data,
	input wire[ATOMIC_K*6-1:0] s_axis_mid_res_keep,
	input wire[2+INFO_ALONG_WIDTH:0] s_axis_mid_res_user, // {随路数据, 是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	input wire s_axis_mid_res_last, // 本行最后1个中间结果(标志)
	input wire s_axis_mid_res_valid,
	output wire s_axis_mid_res_ready,
	
	// 最终结果输出(AXIS主机)
	output wire[ATOMIC_K*32-1:0] m_axis_fnl_res_data, // ATOMIC_K个最终结果(单精度浮点数或定点数)
	output wire[ATOMIC_K*4-1:0] m_axis_fnl_res_keep,
	output wire[4:0] m_axis_fnl_res_user, // {是否最后1个子行(1bit), 子行号(4bit)}
	output wire m_axis_fnl_res_last, // 本行最后1个最终结果(标志)
	output wire m_axis_fnl_res_valid,
	input wire m_axis_fnl_res_ready,
	
	// 缓存MEM主接口
	output wire mem_clk_a,
	output wire[RBUF_BANK_N-1:0] mem_wen_a,
	output wire[RBUF_BANK_N*16-1:0] mem_addr_a,
	output wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mem_din_a,
	output wire mem_clk_b,
	output wire[RBUF_BANK_N-1:0] mem_ren_b,
	output wire[RBUF_BANK_N*16-1:0] mem_addr_b,
	input wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mem_dout_b,
	
	// 中间结果更新单元组
	// [更新单元组输入]
	output wire[ATOMIC_K*48-1:0] acmlt_in_new_res, // 新结果
	output wire[ATOMIC_K*32-1:0] acmlt_in_org_mid_res, // 原中间结果
	output wire[ATOMIC_K-1:0] acmlt_in_mask, // 项掩码
	output wire acmlt_in_first_item, // 是否第1项(标志)
	output wire acmlt_in_last_grp, // 是否最后1组(标志)
	output wire acmlt_in_last_res, // 本行最后1个中间结果(标志)
	output wire[INFO_ALONG_WIDTH-1:0] acmlt_in_info_along, // 随路数据
	output wire[ATOMIC_K-1:0] acmlt_in_valid, // 输入有效指示
	// [更新单元组输出]
	input wire[ATOMIC_K*32-1:0] acmlt_out_data, // 单精度浮点数或定点数
	input wire[ATOMIC_K-1:0] acmlt_out_mask, // 输出项掩码
	input wire acmlt_out_last_grp, // 是否最后1组(标志)
	input wire acmlt_out_last_res, // 本行最后1个中间结果(标志)
	input wire acmlt_out_to_upd_mem, // 更新缓存MEM(标志)
	input wire acmlt_out_valid // 输出有效指示
);
	
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
	// 运算数据格式
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	// 中间结果输入(user信号各字段的索引)
	localparam integer S_AXIS_MID_RES_USER_LAST_ROUND = 0;
	localparam integer S_AXIS_MID_RES_USER_FIRST_ROUND = 1;
	localparam integer S_AXIS_MID_RES_USER_IS_LAST_CAL_ROUND = 2;
	localparam integer S_AXIS_MID_RES_USER_INFO_ALONG = 3;
	
	/** 输出特征图表面行附加信息fifo **/
	// [fifo写端口]
	wire ofm_row_extra_msg_fifo_wen;
	wire[19:0] ofm_row_extra_msg_fifo_din; // {计算轮次 - 1(4bit), 输出表面行长度 - 1(16bit)}
	wire ofm_row_extra_msg_fifo_full_n;
	// [fifo读端口]
	wire ofm_row_extra_msg_fifo_ren;
	wire[19:0] ofm_row_extra_msg_fifo_dout; // {计算轮次 - 1(4bit), 输出表面行长度 - 1(16bit)}
	wire ofm_row_extra_msg_fifo_empty_n;
	wire[15:0] ofm_row_final_res_len; // 输出表面行(最终结果)长度 - 1
	wire[3:0] ofm_row_final_res_cal_round_n; // 输出表面行(最终结果)计算轮次 - 1
	reg ofm_row_final_res_extra_msg_vld; // 输出特征图表面行附加信息(有效标志)
	
	assign ofm_row_final_res_len = 
		en_cal_round_ext ? 
			ofm_row_extra_msg_fifo_dout[15:0]:
			ofmap_w;
	assign ofm_row_final_res_cal_round_n = 
		en_cal_round_ext ? 
			ofm_row_extra_msg_fifo_dout[19:16]:
			4'd0;
	
	fifo_based_on_regs #(
		.fwft_mode("false"),
		.low_latency_mode("false"),
		.fifo_depth(RBUF_BANK_N),
		.fifo_data_width(20),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)ofm_row_extra_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(ofm_row_extra_msg_fifo_wen),
		.fifo_din(ofm_row_extra_msg_fifo_din),
		.fifo_full(),
		.fifo_full_n(ofm_row_extra_msg_fifo_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(),
		
		.fifo_ren(ofm_row_extra_msg_fifo_ren),
		.fifo_dout(ofm_row_extra_msg_fifo_dout),
		.fifo_empty(),
		.fifo_empty_n(ofm_row_extra_msg_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	/** 中间结果累加读数据流水线 **/
	// 第0级流水线
	reg[clogb2(RBUF_BANK_N-1):0] mid_res_sel_s0; // 缓存MEM读数据选择
	wire mid_res_first_item_s0; // 是否第1项(标志)
	wire mid_res_last_grp_s0; // 是否最后1组(标志)
	wire[INFO_ALONG_WIDTH-1:0] mid_res_info_along_s0; // 随路数据
	wire[ATOMIC_K*48-1:0] mid_res_new_item_s0; // 新的待累加项
	wire[ATOMIC_K-1:0] mid_res_mask_s0; // 项掩码
	wire mid_res_last_s0; // 本行最后1个中间结果(标志)
	wire mid_res_valid_s0;
	// 第1级流水线
	wire[ATOMIC_K*32+ATOMIC_K-1:0] mem_dout_b_arr[0:RBUF_BANK_N-1]; // 缓存MEM读数据(数组)
	reg[clogb2(RBUF_BANK_N-1):0] mid_res_sel_s1; // 缓存MEM读数据选择
	reg mid_res_first_item_s1; // 是否第1项(标志)
	reg mid_res_last_grp_s1; // 是否最后1组(标志)
	reg[INFO_ALONG_WIDTH-1:0] mid_res_info_along_s1; // 随路数据
	wire[ATOMIC_K*32-1:0] mid_res_data_s1; // 原中间结果
	reg[ATOMIC_K*48-1:0] mid_res_new_item_s1; // 新的待累加项
	reg[ATOMIC_K-1:0] mid_res_mask_s1; // 项掩码
	reg mid_res_last_s1; // 本行最后1个中间结果(标志)
	reg mid_res_valid_s1;
	// 第2级流水线
	reg mid_res_first_item_s2; // 是否第1项(标志)
	reg mid_res_last_grp_s2; // 是否最后1组(标志)
	reg[INFO_ALONG_WIDTH-1:0] mid_res_info_along_s2; // 随路数据
	reg[ATOMIC_K*32-1:0] mid_res_data_s2; // 原中间结果
	reg[ATOMIC_K*48-1:0] mid_res_new_item_s2; // 新的待累加项
	reg[ATOMIC_K-1:0] mid_res_mask_s2; // 项掩码
	reg mid_res_last_s2; // 本行最后1个中间结果(标志)
	reg mid_res_valid_s2;
	
	genvar mem_dout_b_i;
	generate
		for(mem_dout_b_i = 0;mem_dout_b_i < RBUF_BANK_N;mem_dout_b_i = mem_dout_b_i + 1)
		begin:mem_dout_b_blk
			assign mem_dout_b_arr[mem_dout_b_i] = 
				mem_dout_b[(mem_dout_b_i+1)*(32*ATOMIC_K+ATOMIC_K)-1:mem_dout_b_i*(32*ATOMIC_K+ATOMIC_K)];
		end
	endgenerate
	
	assign mid_res_data_s1 = mem_dout_b_arr[mid_res_sel_s1][ATOMIC_K*32-1:0];
	
	always @(posedge aclk)
	begin
		if(aclken & mid_res_valid_s0)
		begin
			mid_res_sel_s1 <= # SIM_DELAY mid_res_sel_s0;
			mid_res_first_item_s1 <= # SIM_DELAY mid_res_first_item_s0;
			mid_res_last_grp_s1 <= # SIM_DELAY mid_res_last_grp_s0;
			mid_res_info_along_s1 <= # SIM_DELAY mid_res_info_along_s0;
			mid_res_new_item_s1 <= # SIM_DELAY mid_res_new_item_s0;
			mid_res_mask_s1 <= # SIM_DELAY mid_res_mask_s0;
			mid_res_last_s1 <= # SIM_DELAY mid_res_last_s0;
		end
	end
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_valid_s1 <= 1'b0;
		else if(aclken)
			mid_res_valid_s1 <= # SIM_DELAY mid_res_valid_s0;
	end
	
	always @(posedge aclk)
	begin
		if(aclken & mid_res_valid_s1)
		begin
			mid_res_first_item_s2 <= # SIM_DELAY mid_res_first_item_s1;
			mid_res_last_grp_s2 <= # SIM_DELAY mid_res_last_grp_s1;
			mid_res_info_along_s2 <= # SIM_DELAY mid_res_info_along_s1;
			mid_res_data_s2 <= # SIM_DELAY mid_res_data_s1;
			mid_res_new_item_s2 <= # SIM_DELAY mid_res_new_item_s1;
			mid_res_mask_s2 <= # SIM_DELAY mid_res_mask_s1;
			mid_res_last_s2 <= # SIM_DELAY mid_res_last_s1;
		end
	end
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_valid_s2 <= 1'b0;
		else if(aclken)
			mid_res_valid_s2 <= # SIM_DELAY mid_res_valid_s1;
	end
	
	/** 最终结果输出读数据流水线 **/
	// 第0级流水线
	reg[clogb2(RBUF_BANK_N-1):0] fnl_res_sel_s0; // 缓存MEM读数据选择
	wire fnl_res_is_last_sub_row_s0; // 是否最后1个子行(标志)
	wire[3:0] fnl_res_sub_rid_s0; // 子行号
	wire fnl_res_last_s0; // 本行最后1个最终结果(标志)
	wire fnl_res_valid_s0;
	wire fnl_res_ready_s0;
	// 第1级流水线
	reg[clogb2(RBUF_BANK_N-1):0] fnl_res_sel_s1; // 缓存MEM读数据选择
	wire[ATOMIC_K*32-1:0] fnl_res_data_s1;
	reg fnl_res_is_last_sub_row_s1; // 是否最后1个子行(标志)
	reg[3:0] fnl_res_sub_rid_s1; // 子行号
	reg fnl_res_last_s1; // 本行最后1个最终结果(标志)
	wire[ATOMIC_K-1:0] fnl_res_mask_s1; // 项掩码
	reg fnl_res_valid_s1;
	wire fnl_res_ready_s1;
	// 第2级流水线
	reg[ATOMIC_K*32-1:0] fnl_res_data_s2;
	reg fnl_res_is_last_sub_row_s2; // 是否最后1个子行(标志)
	reg[3:0] fnl_res_sub_rid_s2; // 子行号
	reg fnl_res_last_s2; // 本行最后1个最终结果(标志)
	reg[ATOMIC_K-1:0] fnl_res_mask_s2; // 项掩码
	reg fnl_res_valid_s2;
	wire fnl_res_ready_s2;
	
	assign m_axis_fnl_res_data = fnl_res_data_s2;
	assign m_axis_fnl_res_last = fnl_res_last_s2;
	assign m_axis_fnl_res_valid = aclken & fnl_res_valid_s2;
	assign fnl_res_ready_s2 = m_axis_fnl_res_ready;
	
	genvar m_axis_fnl_res_keep_i;
	generate
		for(m_axis_fnl_res_keep_i = 0;m_axis_fnl_res_keep_i < ATOMIC_K;m_axis_fnl_res_keep_i = m_axis_fnl_res_keep_i + 1)
		begin:m_axis_fnl_res_keep_blk
			assign m_axis_fnl_res_keep[m_axis_fnl_res_keep_i*4+3:m_axis_fnl_res_keep_i*4] = 
				{4{fnl_res_mask_s2[m_axis_fnl_res_keep_i]}};
		end
	endgenerate
	
	assign m_axis_fnl_res_user = {fnl_res_is_last_sub_row_s2, fnl_res_sub_rid_s2};
	
	assign fnl_res_ready_s0 = (~fnl_res_valid_s1) | fnl_res_ready_s1;
	assign fnl_res_ready_s1 = (~fnl_res_valid_s2) | fnl_res_ready_s2;
	
	assign {fnl_res_mask_s1, fnl_res_data_s1} = mem_dout_b_arr[fnl_res_sel_s1];
	
	always @(posedge aclk)
	begin
		if(aclken & fnl_res_valid_s0 & fnl_res_ready_s0)
		begin
			fnl_res_sel_s1 <= # SIM_DELAY fnl_res_sel_s0;
			fnl_res_is_last_sub_row_s1 <= # SIM_DELAY fnl_res_is_last_sub_row_s0;
			fnl_res_sub_rid_s1 <= # SIM_DELAY fnl_res_sub_rid_s0;
			fnl_res_last_s1 <= # SIM_DELAY fnl_res_last_s0;
		end
	end
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			fnl_res_valid_s1 <= 1'b0;
		else if(aclken & fnl_res_ready_s0)
			fnl_res_valid_s1 <= # SIM_DELAY fnl_res_valid_s0;
	end
	
	always @(posedge aclk)
	begin
		if(aclken & fnl_res_valid_s1 & fnl_res_ready_s1)
		begin
			fnl_res_data_s2 <= # SIM_DELAY fnl_res_data_s1;
			fnl_res_is_last_sub_row_s2 <= # SIM_DELAY fnl_res_is_last_sub_row_s1;
			fnl_res_sub_rid_s2 <= # SIM_DELAY fnl_res_sub_rid_s1;
			fnl_res_last_s2 <= # SIM_DELAY fnl_res_last_s1;
			fnl_res_mask_s2 <= # SIM_DELAY fnl_res_mask_s1;
		end
	end
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			fnl_res_valid_s2 <= 1'b0;
		else if(aclken & fnl_res_ready_s1)
			fnl_res_valid_s2 <= # SIM_DELAY fnl_res_valid_s1;
	end
	
	/** 中间结果行缓存控制 **/
	// 中间结果输入读后写相关性等待
	reg[15:0] mid_res_upd_pipl_sts; // 中间结果更新流水线状态
	reg[3:0] mid_res_upd_pipl_rid; // 正在执行更新流水线的存储行号
	reg[15:0] mid_res_upd_pipl_cid; // 正在执行更新流水线的列号
	// 虚拟行缓存填充向量
	reg[RBUF_BANK_N-1:0] mid_res_line_buf_filled;
	// 虚拟行缓存写端口
	reg[15:0] col_cnt_at_wr; // 列计数器
	wire[15:0] col_cnt_at_wr_nxt; // 新的列计数器
	reg[3:0] cal_round_n_cnt_at_wr; // 计算轮次计数器
	reg cal_round_n_cnt_at_wr_locked; // 计算轮次计数器(锁定标志)
	wire mid_res_line_buf_wen_at_wr; // 写使能
	wire mid_res_line_buf_ren_at_wr; // 读使能
	wire mid_res_line_buf_full_n; // 满标志
	reg[4:0] mid_res_line_buf_wptr_at_wr; // 写指针
	reg[4:0] mid_res_line_buf_rptr_at_wr; // 读指针
	// 虚拟行缓存读端口
	reg[3:0] sub_row_cnt; // 子行计数器
	wire[3:0] sub_row_cnt_nxt; // 下一子行计数器
	reg[15:0] col_cnt_at_rd; // 列计数器
	wire[15:0] col_cnt_at_rd_nxt; // 新的列计数器
	wire mid_res_line_buf_wen_at_rd; // 写使能
	wire mid_res_line_buf_ren_at_rd; // 读使能
	wire mid_res_line_buf_empty_n; // 空标志
	reg[4:0] mid_res_line_buf_wptr_at_rd; // 写指针
	reg[4:0] mid_res_line_buf_rptr_at_rd; // 读指针
	
	assign s_axis_mid_res_ready = 
		aclken & 
		mid_res_line_buf_full_n & 
		((~en_cal_round_ext) | ofm_row_extra_msg_fifo_full_n) & 
		(~(
			(~mid_res_upd_pipl_sts[0]) & 
			(col_cnt_at_wr == 0) & // 仅在写第1列时作读后写相关性检查
			(mid_res_upd_pipl_rid == mid_res_line_buf_wptr_at_wr[3:0]) & 
			(mid_res_upd_pipl_cid <= (max_upd_latency | 16'h0000))
		));
	
	assign ofm_row_extra_msg_fifo_wen = 
		aclken & en_cal_round_ext & 
		s_axis_mid_res_valid & s_axis_mid_res_ready & 
		s_axis_mid_res_user[S_AXIS_MID_RES_USER_LAST_ROUND] & 
		s_axis_mid_res_last;
	assign ofm_row_extra_msg_fifo_din[15:0] = 
		col_cnt_at_wr; // 输出表面行长度 - 1
	assign ofm_row_extra_msg_fifo_din[19:16] = 
		cal_round_n_cnt_at_wr; // 计算轮次 - 1
	
	assign ofm_row_extra_msg_fifo_ren = 
		aclken & 
		(
			(~en_cal_round_ext) | 
			(~ofm_row_final_res_extra_msg_vld) | 
			(
				fnl_res_valid_s0 & fnl_res_ready_s0 & 
				fnl_res_last_s0 & fnl_res_is_last_sub_row_s0
			)
		);
	
	assign mid_res_first_item_s0 = s_axis_mid_res_user[S_AXIS_MID_RES_USER_FIRST_ROUND];
	assign mid_res_last_grp_s0 = s_axis_mid_res_user[S_AXIS_MID_RES_USER_LAST_ROUND];
	assign mid_res_info_along_s0 = s_axis_mid_res_user[INFO_ALONG_WIDTH-1+S_AXIS_MID_RES_USER_INFO_ALONG:S_AXIS_MID_RES_USER_INFO_ALONG];
	assign mid_res_new_item_s0 = s_axis_mid_res_data;
	assign mid_res_last_s0 = s_axis_mid_res_last;
	assign mid_res_valid_s0 = aclken & s_axis_mid_res_valid & s_axis_mid_res_ready;
	
	genvar mid_res_mask_s0_i;
	generate
		for(mid_res_mask_s0_i = 0;mid_res_mask_s0_i < ATOMIC_K;mid_res_mask_s0_i = mid_res_mask_s0_i + 1)
		begin:mid_res_mask_s0_blk
			assign mid_res_mask_s0[mid_res_mask_s0_i] = s_axis_mid_res_keep[6*mid_res_mask_s0_i];
		end
	endgenerate
	
	assign fnl_res_is_last_sub_row_s0 = sub_row_cnt == ofm_row_final_res_cal_round_n;
	assign fnl_res_sub_rid_s0 = sub_row_cnt;
	assign fnl_res_last_s0 = (col_cnt_at_rd + ofm_row_final_res_cal_round_n) >= ofm_row_final_res_len;
	assign fnl_res_valid_s0 = 
		aclken & 
		mid_res_line_buf_empty_n & 
		((~en_cal_round_ext) | ofm_row_final_res_extra_msg_vld);
	
	assign col_cnt_at_wr_nxt = 
		(s_axis_mid_res_valid & s_axis_mid_res_ready) ? 
			(
				s_axis_mid_res_last ? 
					16'd0:
					(col_cnt_at_wr + 1'b1)
			):
			col_cnt_at_wr;
	
	assign mid_res_line_buf_wen_at_wr = 
		aclken & s_axis_mid_res_valid & s_axis_mid_res_ready & 
		s_axis_mid_res_user[S_AXIS_MID_RES_USER_LAST_ROUND] & 
		s_axis_mid_res_last;
	assign mid_res_line_buf_ren_at_wr = 
		aclken & fnl_res_valid_s2 & fnl_res_ready_s2 & fnl_res_last_s2 & fnl_res_is_last_sub_row_s2;
	assign mid_res_line_buf_full_n = ~(
		(mid_res_line_buf_wptr_at_wr[4] ^ mid_res_line_buf_rptr_at_wr[4]) & 
		(mid_res_line_buf_wptr_at_wr[3:0] == mid_res_line_buf_rptr_at_wr[3:0])
	);
	
	assign sub_row_cnt_nxt = 
		(sub_row_cnt == ofm_row_final_res_cal_round_n) ? 
			4'd0:
			(sub_row_cnt + 1'b1);
	assign col_cnt_at_rd_nxt = 
		(fnl_res_valid_s0 & fnl_res_ready_s0) ? 
			(
				fnl_res_last_s0 ? 
					(sub_row_cnt_nxt | 16'd0):
					(col_cnt_at_rd + ofm_row_final_res_cal_round_n + 1'b1)
			):
			col_cnt_at_rd;
	
	assign mid_res_line_buf_ren_at_rd = 
		aclken & fnl_res_valid_s0 & fnl_res_ready_s0 & fnl_res_last_s0 & fnl_res_is_last_sub_row_s0;
	assign mid_res_line_buf_empty_n = ~(mid_res_line_buf_wptr_at_rd == mid_res_line_buf_rptr_at_rd);
	
	// 输出特征图表面行附加信息(有效标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ofm_row_final_res_extra_msg_vld <= 1'b0;
		else if(
			aclken & 
			(
				(~en_cal_round_ext) | 
				(
					ofm_row_final_res_extra_msg_vld ? 
						(
							fnl_res_valid_s0 & fnl_res_ready_s0 & 
							fnl_res_last_s0 & fnl_res_is_last_sub_row_s0 & 
							(~ofm_row_extra_msg_fifo_empty_n)
						):
						ofm_row_extra_msg_fifo_empty_n
				)
			)
		)
			ofm_row_final_res_extra_msg_vld <= # SIM_DELAY 
				en_cal_round_ext & (~ofm_row_final_res_extra_msg_vld);
	end
	
	// 中间结果更新流水线状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_upd_pipl_sts <= 16'h0001;
		else if(
			aclken & 
			((~mid_res_upd_pipl_sts[0]) | (s_axis_mid_res_valid & s_axis_mid_res_ready))
		)
			mid_res_upd_pipl_sts <= # SIM_DELAY 
				(s_axis_mid_res_valid & s_axis_mid_res_ready) ? 
					16'h0002:
					(
						(
							((calfmt == CAL_FMT_INT8) & mid_res_upd_pipl_sts[7]) | 
							((calfmt == CAL_FMT_INT16) & mid_res_upd_pipl_sts[7]) | 
							((calfmt == CAL_FMT_FP16) & mid_res_upd_pipl_sts[15])
						) ? 
							16'h0001:
							{mid_res_upd_pipl_sts[14:0], mid_res_upd_pipl_sts[15]}
					);
	end
	// 正在执行更新流水线的存储行号
	always @(posedge aclk)
	begin
		if(s_axis_mid_res_valid & s_axis_mid_res_ready)
			mid_res_upd_pipl_rid <= # SIM_DELAY mid_res_line_buf_wptr_at_wr[3:0];
	end
	// 正在执行更新流水线的列号
	always @(posedge aclk)
	begin
		if(s_axis_mid_res_valid & s_axis_mid_res_ready)
			mid_res_upd_pipl_cid <= # SIM_DELAY col_cnt_at_wr;
	end
	
	// 位于写端口的列计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			col_cnt_at_wr <= 16'd0;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready)
			col_cnt_at_wr <= # SIM_DELAY col_cnt_at_wr_nxt;
	end
	
	// 位于写端口的计算轮次计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cal_round_n_cnt_at_wr <= 4'd0;
		else if(
			(~en_cal_round_ext) | 
			(
				s_axis_mid_res_valid & s_axis_mid_res_ready & s_axis_mid_res_user[S_AXIS_MID_RES_USER_LAST_ROUND] & 
				(
					((~cal_round_n_cnt_at_wr_locked) & (~s_axis_mid_res_user[S_AXIS_MID_RES_USER_IS_LAST_CAL_ROUND])) | 
					s_axis_mid_res_last
				)
			)
		)
			cal_round_n_cnt_at_wr <= # SIM_DELAY 
				((~en_cal_round_ext) | s_axis_mid_res_last) ? 
					4'd0:
					(cal_round_n_cnt_at_wr + 1'b1);
	end
	
	// 计算轮次计数器(锁定标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cal_round_n_cnt_at_wr_locked <= 1'b0;
		else if(
			(~en_cal_round_ext) | 
			(
				s_axis_mid_res_valid & s_axis_mid_res_ready & s_axis_mid_res_user[S_AXIS_MID_RES_USER_LAST_ROUND] & 
				(
					(~cal_round_n_cnt_at_wr_locked) | 
					s_axis_mid_res_last
				)
			)
		)
			cal_round_n_cnt_at_wr_locked <= # SIM_DELAY 
				en_cal_round_ext & (~s_axis_mid_res_last) & s_axis_mid_res_user[S_AXIS_MID_RES_USER_IS_LAST_CAL_ROUND];
	end
	
	// 位于写端口的写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_line_buf_wptr_at_wr <= 5'b00000;
		else if(mid_res_line_buf_wen_at_wr)
		begin
			mid_res_line_buf_wptr_at_wr[4] <= # SIM_DELAY 
				(mid_res_line_buf_wptr_at_wr[3:0] == row_n_bufferable) ? 
					(~mid_res_line_buf_wptr_at_wr[4]):
					mid_res_line_buf_wptr_at_wr[4];
			
			mid_res_line_buf_wptr_at_wr[3:0] <= # SIM_DELAY 
				(mid_res_line_buf_wptr_at_wr[3:0] == row_n_bufferable) ? 
					4'b0000:
					(mid_res_line_buf_wptr_at_wr[3:0] + 1);
		end
	end
	
	// 位于写端口的读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_line_buf_rptr_at_wr <= 5'b00000;
		else if(mid_res_line_buf_ren_at_wr)
		begin
			mid_res_line_buf_rptr_at_wr[4] <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_wr[3:0] == row_n_bufferable) ? 
					(~mid_res_line_buf_rptr_at_wr[4]):
					mid_res_line_buf_rptr_at_wr[4];
			
			mid_res_line_buf_rptr_at_wr[3:0] <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_wr[3:0] == row_n_bufferable) ? 
					4'b0000:
					(mid_res_line_buf_rptr_at_wr[3:0] + 1);
		end
	end
	
	// 位于读端口的子行计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			sub_row_cnt <= 4'd0;
		else if(fnl_res_valid_s0 & fnl_res_ready_s0 & fnl_res_last_s0)
			sub_row_cnt <= # SIM_DELAY sub_row_cnt_nxt;
	end
	
	// 位于读端口的列计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			col_cnt_at_rd <= 16'd0;
		else if(fnl_res_valid_s0 & fnl_res_ready_s0)
			col_cnt_at_rd <= # SIM_DELAY col_cnt_at_rd_nxt;
	end
	
	// 位于读端口的写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_line_buf_wptr_at_rd <= 5'b00000;
		else if(mid_res_line_buf_wen_at_rd)
		begin
			mid_res_line_buf_wptr_at_rd[4] <= # SIM_DELAY 
				(mid_res_line_buf_wptr_at_rd[3:0] == row_n_bufferable) ? 
					(~mid_res_line_buf_wptr_at_rd[4]):
					mid_res_line_buf_wptr_at_rd[4];
			
			mid_res_line_buf_wptr_at_rd[3:0] <= # SIM_DELAY 
				(mid_res_line_buf_wptr_at_rd[3:0] == row_n_bufferable) ? 
					4'b0000:
					(mid_res_line_buf_wptr_at_rd[3:0] + 1'b1);
		end
	end
	
	// 位于读端口的读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_line_buf_rptr_at_rd <= 5'b00000;
		else if(mid_res_line_buf_ren_at_rd)
		begin
			mid_res_line_buf_rptr_at_rd[4] <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_rd[3:0] == row_n_bufferable) ? 
					(~mid_res_line_buf_rptr_at_rd[4]):
					mid_res_line_buf_rptr_at_rd[4];
			
			mid_res_line_buf_rptr_at_rd[3:0] <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_rd[3:0] == row_n_bufferable) ? 
					4'b0000:
					(mid_res_line_buf_rptr_at_rd[3:0] + 1'b1);
		end
	end
	
	/** 卷积中间结果累加单元 **/
	assign acmlt_in_new_res = mid_res_new_item_s2;
	assign acmlt_in_org_mid_res = mid_res_data_s2;
	assign acmlt_in_mask = mid_res_mask_s2;
	assign acmlt_in_first_item = mid_res_first_item_s2;
	assign acmlt_in_last_grp = mid_res_last_grp_s2;
	assign acmlt_in_last_res = mid_res_last_s2;
	assign acmlt_in_info_along = mid_res_info_along_s2;
	assign acmlt_in_valid = {ATOMIC_K{mid_res_valid_s2}} & mid_res_mask_s2;
	
	assign mid_res_line_buf_wen_at_rd = 
		aclken & acmlt_out_valid & acmlt_out_last_res & acmlt_out_last_grp;
	
	/** 缓存MEM接口 **/
	wire mem_wlast; // 缓存MEM更新当前行最后1个表面(标志)
	reg[15:0] mem_waddr; // 缓存MEM写地址
	wire[15:0] mem_waddr_nxt; // 新的缓存MEM写地址
	// [更新行缓存时写选择]
	reg[7:0] upd_row_buffer_wsel_bid_base; // 更新行缓存时写选择(BANK编号基准)
	wire[7:0] upd_row_buffer_wsel_bid_base_nxt; // 下一更新行缓存时写选择(BANK编号基准)
	wire[3:0] row_buffer_wsel_bid_ofs; // 更新行缓存时写选择(BANK编号偏移)
	wire[3:0] row_buffer_wsel_bid_ofs_nxt; // 下一更新行缓存时写选择(BANK编号偏移)
	reg[clogb2(RBUF_BANK_N-1):0] upd_row_buffer_wsel; // 更新行缓存时写选择
	// [更新行缓存时读选择]
	reg[7:0] upd_row_buffer_rsel_bid_base; // 更新行缓存时读选择(BANK编号基准)
	wire[7:0] upd_row_buffer_rsel_bid_base_nxt; // 下一更新行缓存时读选择(BANK编号基准)
	wire[3:0] upd_row_buffer_rsel_bid_ofs; // 更新行缓存时读选择(BANK编号偏移)
	wire[3:0] upd_row_buffer_rsel_bid_ofs_nxt; // 下一更新行缓存时读选择(BANK编号偏移)
	// [提取行缓存时读选择]
	reg[7:0] extract_row_buffer_rsel_bid_base; // 提取行缓存时读选择(BANK编号基准)
	wire[7:0] extract_row_buffer_rsel_bid_base_nxt; // 下一提取行缓存时读选择(BANK编号基准)
	wire[3:0] extract_row_buffer_rsel_bid_ofs; // 提取行缓存时读选择(BANK编号偏移)
	wire[3:0] extract_row_buffer_rsel_bid_ofs_nxt; // 下一提取行缓存时读选择(BANK编号偏移)
	// [提取行缓存时写选择]
	reg[7:0] extract_row_buffer_wsel_bid_base; // 提取行缓存时写选择(BANK编号基准)
	
	assign mem_clk_a = aclk;
	assign mem_clk_b = aclk;
	
	genvar mem_i;
	generate
		for(mem_i = 0;mem_i < RBUF_BANK_N;mem_i = mem_i + 1)
		begin:mem_blk
			assign mem_wen_a[mem_i] = 
				aclken & 
				(~mid_res_line_buf_filled[mem_i]) & 
				acmlt_out_valid & acmlt_out_to_upd_mem & (upd_row_buffer_wsel == mem_i);
			assign mem_addr_a[(mem_i+1)*16-1:mem_i*16] = 
				mem_waddr | 16'h0000;
			assign mem_din_a[(mem_i+1)*(32*ATOMIC_K+ATOMIC_K)-1:mem_i*(32*ATOMIC_K+ATOMIC_K)] = 
				{acmlt_out_mask, acmlt_out_data};
			
			assign mem_ren_b[mem_i] = 
				aclken & 
				(
					mid_res_line_buf_filled[mem_i] ? 
						(fnl_res_valid_s0 & fnl_res_ready_s0 & (fnl_res_sel_s0 == mem_i)):
						(s_axis_mid_res_valid & s_axis_mid_res_ready & (mid_res_sel_s0 == mem_i))
				);
			assign mem_addr_b[(mem_i+1)*16-1:mem_i*16] = 
				(
					mid_res_line_buf_filled[mem_i] ? 
						col_cnt_at_rd:
						col_cnt_at_wr
				) | 16'h0000;
		end
	endgenerate
	
	assign mem_wlast = acmlt_out_last_res;
	assign mem_waddr_nxt = 
		acmlt_out_valid ? 
			(
				mem_wlast ? 
					16'd0:
					(mem_waddr + 1'b1)
			):
			mem_waddr;
	
	assign upd_row_buffer_wsel_bid_base_nxt = 
		mid_res_line_buf_wen_at_rd ? 
			(
				(mid_res_line_buf_wptr_at_rd[3:0] == row_n_bufferable) ? 
					8'd0:
					(upd_row_buffer_wsel_bid_base + bank_n_foreach_ofmap_row)
			):
			upd_row_buffer_wsel_bid_base;
	assign row_buffer_wsel_bid_ofs = mem_waddr[15:clogb2(RBUF_DEPTH)] | 4'd0;
	assign row_buffer_wsel_bid_ofs_nxt = mem_waddr_nxt[15:clogb2(RBUF_DEPTH)] | 4'd0;
	
	assign upd_row_buffer_rsel_bid_base_nxt = 
		mid_res_line_buf_wen_at_wr ? 
			(
				(mid_res_line_buf_wptr_at_wr[3:0] == row_n_bufferable) ? 
					8'd0:
					(upd_row_buffer_rsel_bid_base + bank_n_foreach_ofmap_row)
			):
			upd_row_buffer_rsel_bid_base;
	assign upd_row_buffer_rsel_bid_ofs = col_cnt_at_wr[15:clogb2(RBUF_DEPTH)] | 4'd0;
	assign upd_row_buffer_rsel_bid_ofs_nxt = col_cnt_at_wr_nxt[15:clogb2(RBUF_DEPTH)] | 4'd0;
	
	assign extract_row_buffer_rsel_bid_base_nxt = 
		mid_res_line_buf_ren_at_rd ? 
			(
				(mid_res_line_buf_rptr_at_rd[3:0] == row_n_bufferable) ? 
					8'd0:
					(extract_row_buffer_rsel_bid_base + bank_n_foreach_ofmap_row)
			):
			extract_row_buffer_rsel_bid_base;
	assign extract_row_buffer_rsel_bid_ofs = col_cnt_at_rd[15:clogb2(RBUF_DEPTH)] | 4'd0;
	assign extract_row_buffer_rsel_bid_ofs_nxt = col_cnt_at_rd_nxt[15:clogb2(RBUF_DEPTH)] | 4'd0;
	
	// 缓存MEM读数据选择
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_sel_s0 <= 0;
		else if(mid_res_line_buf_wen_at_wr | (s_axis_mid_res_valid & s_axis_mid_res_ready))
			mid_res_sel_s0 <= # SIM_DELAY upd_row_buffer_rsel_bid_base_nxt + upd_row_buffer_rsel_bid_ofs_nxt;
	end
	
	// 缓存MEM读数据选择
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			fnl_res_sel_s0 <= 0;
		else if(mid_res_line_buf_ren_at_rd | (fnl_res_valid_s0 & fnl_res_ready_s0))
			fnl_res_sel_s0 <= # SIM_DELAY extract_row_buffer_rsel_bid_base_nxt + extract_row_buffer_rsel_bid_ofs_nxt;
	end
	
	// 虚拟行缓存填充向量
	genvar mid_res_line_buf_filled_i;
	generate
		for(mid_res_line_buf_filled_i = 0;mid_res_line_buf_filled_i < RBUF_BANK_N;
			mid_res_line_buf_filled_i = mid_res_line_buf_filled_i + 1)
		begin:mid_res_line_buf_filled_blk
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					mid_res_line_buf_filled[mid_res_line_buf_filled_i] <= 1'b0;
				else if(
					(
						mid_res_line_buf_wen_at_rd & 
						(mid_res_line_buf_filled_i >= upd_row_buffer_wsel_bid_base) & 
						(mid_res_line_buf_filled_i < (upd_row_buffer_wsel_bid_base + bank_n_foreach_ofmap_row))
					) | 
					(
						mid_res_line_buf_ren_at_wr & 
						(mid_res_line_buf_filled_i >= extract_row_buffer_wsel_bid_base) & 
						(mid_res_line_buf_filled_i < (extract_row_buffer_wsel_bid_base + bank_n_foreach_ofmap_row))
					)
				)
					mid_res_line_buf_filled[mid_res_line_buf_filled_i] <= # SIM_DELAY 
						mid_res_line_buf_wen_at_rd & 
						(mid_res_line_buf_filled_i >= upd_row_buffer_wsel_bid_base) & 
						(mid_res_line_buf_filled_i < (upd_row_buffer_wsel_bid_base + bank_n_foreach_ofmap_row));
			end
		end
	endgenerate
	
	// 缓存MEM写地址
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mem_waddr <= 16'd0;
		else if(acmlt_out_valid)
			mem_waddr <= # SIM_DELAY mem_waddr_nxt;
	end
	
	// 更新行缓存时写选择(BANK编号基准)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			upd_row_buffer_wsel_bid_base <= 8'd0;
		else if(mid_res_line_buf_wen_at_rd)
		begin
			upd_row_buffer_wsel_bid_base <= # SIM_DELAY upd_row_buffer_wsel_bid_base_nxt;
		end
	end
	
	// 更新行缓存时写选择
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			upd_row_buffer_wsel <= 0;
		else if(mid_res_line_buf_wen_at_rd | acmlt_out_valid)
			upd_row_buffer_wsel <= # SIM_DELAY upd_row_buffer_wsel_bid_base_nxt + row_buffer_wsel_bid_ofs_nxt;
	end
	
	// 更新行缓存时读选择(BANK编号基准)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			upd_row_buffer_rsel_bid_base <= 8'd0;
		else if(mid_res_line_buf_wen_at_wr)
			upd_row_buffer_rsel_bid_base <= # SIM_DELAY upd_row_buffer_rsel_bid_base_nxt;
	end
	
	// 提取行缓存时读选择(BANK编号基准)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			extract_row_buffer_rsel_bid_base <= 8'd0;
		else if(mid_res_line_buf_ren_at_rd)
		begin
			extract_row_buffer_rsel_bid_base <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_rd[3:0] == row_n_bufferable) ? 
					8'd0:
					(extract_row_buffer_rsel_bid_base + bank_n_foreach_ofmap_row);
		end
	end
	
	// 提取行缓存时写选择(BANK编号基准)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			extract_row_buffer_wsel_bid_base <= 8'd0;
		else if(mid_res_line_buf_ren_at_wr)
		begin
			extract_row_buffer_wsel_bid_base <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_wr[3:0] == row_n_bufferable) ? 
					8'd0:
					(extract_row_buffer_wsel_bid_base + bank_n_foreach_ofmap_row);
		end
	end
	
endmodule
