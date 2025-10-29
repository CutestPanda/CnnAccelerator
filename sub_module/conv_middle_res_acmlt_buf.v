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
支持INT16、FP16两种运算数据格式
带有全局时钟使能

缓存MEM读端口 --> (更新写端口看到的写指针) --> [读出原中间结果(2clk)] --> [累加计算(2clk或9clk)] --> 
	写入新结果 --> (更新读端口看到的写指针, 更新写列计数器) --> 缓存MEM写端口

缓存MEM读端口 --> (更新读端口看到的读指针, 更新读列计数器) --> [读数据流水线(2clk)] --> (更新写端口看到的读指针)

注意：
暂不支持INT8运算数据格式

协议:
AXIS MASTER/SLAVE
MEM MASTER

作者: 陈家耀
日期: 2025/04/01
********************************************************************/


module conv_middle_res_acmlt_buf #(
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer RBUF_BANK_N = 4, // 缓存MEM个数(2~32)
	parameter integer RBUF_DEPTH = 1024, // 缓存MEM深度(512 | 1024 | 2048 | 4096 | 8192)
	parameter EN_SMALL_FP32 = "false", // 是否处理极小FP32
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	input wire[1:0] calfmt, // 运算数据格式
	input wire[12:0] ofmw_sub1, // 输出特征图宽度 - 1
	
	// 中间结果输入(AXIS从机)
	/*
	对于ATOMIC_K个中间结果 -> 
		{指数部分(8位, 仅当运算数据格式为FP16时有效), 尾数部分或定点数(40位)}
	*/
	input wire[ATOMIC_K*48-1:0] s_axis_mid_res_data,
	input wire[ATOMIC_K*6-1:0] s_axis_mid_res_keep,
	input wire[1:0] s_axis_mid_res_user, // {初始化中间结果(标志), 最后1组中间结果(标志)}
	input wire s_axis_mid_res_valid,
	output wire s_axis_mid_res_ready,
	
	// 最终结果输出(AXIS主机)
	/*
	对于ATOMIC_K个最终结果 -> 
		{单精度浮点数或定点数(32位)}
	*/
	output wire[ATOMIC_K*32-1:0] m_axis_fnl_res_data,
	output wire[ATOMIC_K*4-1:0] m_axis_fnl_res_keep,
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
	input wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mem_dout_b
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
	
	/** 中间结果累加读数据流水线 **/
	// 第0级流水线
	wire[clogb2(RBUF_BANK_N-1):0] mid_res_sel_s0; // 缓存MEM读数据选择
	wire mid_res_first_item_s0; // 是否第1项(标志)
	wire[ATOMIC_K*48-1:0] mid_res_new_item_s0; // 新的待累加项
	wire[ATOMIC_K-1:0] mid_res_mask_s0; // 项掩码
	wire mid_res_valid_s0;
	// 第1级流水线
	wire[ATOMIC_K*32+ATOMIC_K-1:0] mem_dout_b_arr[0:RBUF_BANK_N-1]; // 缓存MEM读数据(数组)
	reg[clogb2(RBUF_BANK_N-1):0] mid_res_sel_s1; // 缓存MEM读数据选择
	reg mid_res_first_item_s1; // 是否第1项(标志)
	wire[ATOMIC_K*32-1:0] mid_res_data_s1; // 原中间结果
	reg[ATOMIC_K*48-1:0] mid_res_new_item_s1; // 新的待累加项
	reg[ATOMIC_K-1:0] mid_res_mask_s1; // 项掩码
	reg mid_res_valid_s1;
	// 第2级流水线
	reg mid_res_first_item_s2; // 是否第1项(标志)
	reg[ATOMIC_K*32-1:0] mid_res_data_s2; // 原中间结果
	reg[ATOMIC_K*48-1:0] mid_res_new_item_s2; // 新的待累加项
	reg[ATOMIC_K-1:0] mid_res_mask_s2; // 项掩码
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
			mid_res_new_item_s1 <= # SIM_DELAY mid_res_new_item_s0;
			mid_res_mask_s1 <= # SIM_DELAY 
				// 说明: 仅在输入最后1组中间结果时才保存项掩码
				mid_res_mask_s0 & {ATOMIC_K{s_axis_mid_res_user[0]}};
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
			mid_res_data_s2 <= # SIM_DELAY mid_res_data_s1;
			mid_res_new_item_s2 <= # SIM_DELAY mid_res_new_item_s1;
			mid_res_mask_s2 <= # SIM_DELAY mid_res_mask_s1;
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
	wire[clogb2(RBUF_BANK_N-1):0] fnl_res_sel_s0; // 缓存MEM读数据选择
	wire fnl_res_last_s0; // 本行最后1个最终结果(标志)
	wire fnl_res_valid_s0;
	wire fnl_res_ready_s0;
	// 第1级流水线
	reg[clogb2(RBUF_BANK_N-1):0] fnl_res_sel_s1; // 缓存MEM读数据选择
	wire[ATOMIC_K*32-1:0] fnl_res_data_s1;
	reg fnl_res_last_s1; // 本行最后1个最终结果(标志)
	wire[ATOMIC_K-1:0] fnl_res_mask_s1; // 项掩码
	reg fnl_res_valid_s1;
	wire fnl_res_ready_s1;
	// 第2级流水线
	reg[ATOMIC_K*32-1:0] fnl_res_data_s2;
	reg fnl_res_last_s2; // 本行最后1个最终结果(标志)
	reg[ATOMIC_K-1:0] fnl_res_mask_s2; // 项掩码
	reg fnl_res_valid_s2;
	wire fnl_res_ready_s2;
	
	assign m_axis_fnl_res_data = fnl_res_data_s2;
	assign m_axis_fnl_res_last = fnl_res_last_s2;
	assign m_axis_fnl_res_valid = fnl_res_valid_s2;
	assign fnl_res_ready_s2 = m_axis_fnl_res_ready;
	
	genvar m_axis_fnl_res_keep_i;
	generate
		for(m_axis_fnl_res_keep_i = 0;m_axis_fnl_res_keep_i < ATOMIC_K;m_axis_fnl_res_keep_i = m_axis_fnl_res_keep_i + 1)
		begin:m_axis_fnl_res_keep_blk
			assign m_axis_fnl_res_keep[m_axis_fnl_res_keep_i*4+3:m_axis_fnl_res_keep_i*4] = 
				{4{fnl_res_mask_s2[m_axis_fnl_res_keep_i]}};
		end
	endgenerate
	
	assign fnl_res_ready_s0 = (~fnl_res_valid_s1) | fnl_res_ready_s1;
	assign fnl_res_ready_s1 = (~fnl_res_valid_s2) | fnl_res_ready_s2;
	
	assign {fnl_res_mask_s1, fnl_res_data_s1} = mem_dout_b_arr[fnl_res_sel_s1];
	
	always @(posedge aclk)
	begin
		if(aclken & fnl_res_valid_s0 & fnl_res_ready_s0)
		begin
			fnl_res_sel_s1 <= # SIM_DELAY fnl_res_sel_s0;
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
	reg[clogb2(RBUF_BANK_N-1):0] mid_res_upd_pipl_bid; // 正在执行更新流水线的存储器Bank号
	reg[clogb2(RBUF_DEPTH-1):0] mid_res_upd_pipl_cid; // 正在执行更新流水线的列号
	// 虚拟行缓存填充向量
	reg[RBUF_BANK_N-1:0] mid_res_line_buf_filled;
	// 虚拟行缓存写端口
	reg[clogb2(RBUF_DEPTH-1):0] col_cnt_at_wr; // 列计数器
	wire mid_res_line_buf_wen_at_wr; // 写使能
	wire mid_res_line_buf_wen_at_wr_d4; // 延迟4clk的写使能
	wire mid_res_line_buf_wen_at_wr_d11; // 延迟11clk的写使能
	wire mid_res_line_buf_ren_at_wr; // 读使能
	wire mid_res_line_buf_full_n; // 满标志
	reg[clogb2(RBUF_BANK_N-1)+1:0] mid_res_line_buf_wptr_at_wr; // 写指针
	reg[clogb2(RBUF_BANK_N-1)+1:0] mid_res_line_buf_rptr_at_wr; // 读指针
	// 虚拟行缓存读端口
	reg[clogb2(RBUF_DEPTH-1):0] col_cnt_at_rd; // 列计数器
	wire mid_res_line_buf_wen_at_rd; // 写使能
	wire mid_res_line_buf_ren_at_rd; // 读使能
	wire mid_res_line_buf_empty_n; // 空标志
	reg[clogb2(RBUF_BANK_N-1)+1:0] mid_res_line_buf_wptr_at_rd; // 写指针
	reg[clogb2(RBUF_BANK_N-1)+1:0] mid_res_line_buf_rptr_at_rd; // 读指针
	
	assign s_axis_mid_res_ready = 
		aclken & mid_res_line_buf_full_n & (~(
			(~mid_res_upd_pipl_sts[0]) & 
			// 仅在写第1列时作读后写相关性检查
			(col_cnt_at_wr == 0) & 
			(mid_res_upd_pipl_bid == mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1):0]) & 
			(mid_res_upd_pipl_cid <= 11)
		));
	
	assign mid_res_sel_s0 = mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1):0];
	assign mid_res_first_item_s0 = s_axis_mid_res_user[1];
	assign mid_res_new_item_s0 = s_axis_mid_res_data;
	assign mid_res_valid_s0 = aclken & s_axis_mid_res_valid & s_axis_mid_res_ready;
	
	genvar mid_res_mask_s0_i;
	generate
		for(mid_res_mask_s0_i = 0;mid_res_mask_s0_i < ATOMIC_K;mid_res_mask_s0_i = mid_res_mask_s0_i + 1)
		begin:mid_res_mask_s0_blk
			assign mid_res_mask_s0[mid_res_mask_s0_i] = s_axis_mid_res_keep[6*mid_res_mask_s0_i];
		end
	endgenerate
	
	assign fnl_res_sel_s0 = mid_res_line_buf_rptr_at_rd[clogb2(RBUF_BANK_N-1):0];
	assign fnl_res_last_s0 = col_cnt_at_rd == ofmw_sub1[clogb2(RBUF_DEPTH-1):0];
	assign fnl_res_valid_s0 = aclken & mid_res_line_buf_empty_n;
	
	assign mid_res_line_buf_wen_at_wr = 
		aclken & s_axis_mid_res_valid & s_axis_mid_res_ready & 
		s_axis_mid_res_user[0] & (col_cnt_at_wr == ofmw_sub1[clogb2(RBUF_DEPTH-1):0]);
	assign mid_res_line_buf_ren_at_wr = 
		aclken & fnl_res_valid_s2 & fnl_res_ready_s2 & fnl_res_last_s2;
	assign mid_res_line_buf_full_n = ~(
		(mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1)+1] ^ mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1)+1]) & 
		(mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1):0] == mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1):0])
	);
	
	assign mid_res_line_buf_wen_at_rd = 
		aclken & (
			((calfmt == CAL_FMT_INT16) & mid_res_line_buf_wen_at_wr_d4) | 
			((calfmt == CAL_FMT_FP16) & mid_res_line_buf_wen_at_wr_d11)
		);
	assign mid_res_line_buf_ren_at_rd = 
		aclken & fnl_res_valid_s0 & fnl_res_ready_s0 & fnl_res_last_s0;
	assign mid_res_line_buf_empty_n = ~(mid_res_line_buf_wptr_at_rd == mid_res_line_buf_rptr_at_rd);
	
	// 中间结果更新流水线状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_upd_pipl_sts <= 16'h0001;
		else if(aclken & (
			(mid_res_upd_pipl_sts[0] & s_axis_mid_res_valid & s_axis_mid_res_ready) | 
			(~mid_res_upd_pipl_sts[0])
		))
			mid_res_upd_pipl_sts <= # SIM_DELAY 
				(s_axis_mid_res_valid & s_axis_mid_res_ready) ? 
					16'h0002:
					(
						(
							((calfmt == CAL_FMT_INT16) & mid_res_upd_pipl_sts[7]) | 
							((calfmt == CAL_FMT_FP16) & mid_res_upd_pipl_sts[15])
						) ? 
							16'h0001:
							{mid_res_upd_pipl_sts[14:0], mid_res_upd_pipl_sts[15]}
					);
	end
	// 正在执行更新流水线的存储器Bank号
	always @(posedge aclk)
	begin
		if(s_axis_mid_res_valid & s_axis_mid_res_ready)
			mid_res_upd_pipl_bid <= # SIM_DELAY mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1):0];
	end
	// 正在执行更新流水线的列号
	always @(posedge aclk)
	begin
		if(s_axis_mid_res_valid & s_axis_mid_res_ready)
			mid_res_upd_pipl_cid <= # SIM_DELAY col_cnt_at_wr;
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
					(mid_res_line_buf_wen_at_rd & (mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1):0] == mid_res_line_buf_filled_i)) | 
					(mid_res_line_buf_ren_at_wr & (mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1):0] == mid_res_line_buf_filled_i))
				)
					mid_res_line_buf_filled[mid_res_line_buf_filled_i] <= # SIM_DELAY 
						mid_res_line_buf_wen_at_rd & (mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1):0] == mid_res_line_buf_filled_i);
			end
		end
	endgenerate
	
	// 位于写端口的列计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			col_cnt_at_wr <= 0;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready)
			col_cnt_at_wr <= # SIM_DELAY 
				(col_cnt_at_wr == ofmw_sub1[clogb2(RBUF_DEPTH-1):0]) ? 
					0:
					(col_cnt_at_wr + 1);
	end
	
	// 位于写端口的写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_line_buf_wptr_at_wr <= 0;
		else if(mid_res_line_buf_wen_at_wr)
		begin
			mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1)+1] <= # SIM_DELAY 
				(mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1):0] == (RBUF_BANK_N - 1)) ? 
					(~mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1)+1]):
					mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1)+1];
			
			mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1):0] <= # SIM_DELAY 
				(mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1):0] == (RBUF_BANK_N - 1)) ? 
					0:
					(mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1):0] + 1);
		end
	end
	
	// 位于写端口的读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_line_buf_rptr_at_wr <= 0;
		else if(mid_res_line_buf_ren_at_wr)
		begin
			mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1)+1] <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1):0] == (RBUF_BANK_N - 1)) ? 
					(~mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1)+1]):
					mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1)+1];
			
			mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1):0] <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1):0] == (RBUF_BANK_N - 1)) ? 
					0:
					(mid_res_line_buf_rptr_at_wr[clogb2(RBUF_BANK_N-1):0] + 1);
		end
	end
	
	// 位于读端口的列计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			col_cnt_at_rd <= 0;
		else if(fnl_res_valid_s0 & fnl_res_ready_s0)
			col_cnt_at_rd <= # SIM_DELAY 
				(col_cnt_at_rd == ofmw_sub1[clogb2(RBUF_DEPTH-1):0]) ? 
					0:
					(col_cnt_at_rd + 1);
	end
	
	// 位于读端口的写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_line_buf_wptr_at_rd <= 0;
		else if(mid_res_line_buf_wen_at_rd)
		begin
			mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1)+1] <= # SIM_DELAY 
				(mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1):0] == (RBUF_BANK_N - 1)) ? 
					(~mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1)+1]):
					mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1)+1];
			
			mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1):0] <= # SIM_DELAY 
				(mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1):0] == (RBUF_BANK_N - 1)) ? 
					0:
					(mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1):0] + 1);
		end
	end
	
	// 位于读端口的读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mid_res_line_buf_rptr_at_rd <= 0;
		else if(mid_res_line_buf_ren_at_rd)
		begin
			mid_res_line_buf_rptr_at_rd[clogb2(RBUF_BANK_N-1)+1] <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_rd[clogb2(RBUF_BANK_N-1):0] == (RBUF_BANK_N - 1)) ? 
					(~mid_res_line_buf_rptr_at_rd[clogb2(RBUF_BANK_N-1)+1]):
					mid_res_line_buf_rptr_at_rd[clogb2(RBUF_BANK_N-1)+1];
			
			mid_res_line_buf_rptr_at_rd[clogb2(RBUF_BANK_N-1):0] <= # SIM_DELAY 
				(mid_res_line_buf_rptr_at_rd[clogb2(RBUF_BANK_N-1):0] == (RBUF_BANK_N - 1)) ? 
					0:
					(mid_res_line_buf_rptr_at_rd[clogb2(RBUF_BANK_N-1):0] + 1);
		end
	end
	
	ram_based_shift_regs #(
		.data_width(1),
		.delay_n(4),
		.shift_type("ff"),
		.en_output_register_init("false"),
		.simulation_delay(SIM_DELAY)
	)delay_for_mid_res_line_buf_wen_at_wr_u(
		.clk(aclk),
		.resetn(1'b1),
		
		.shift_in(mid_res_line_buf_wen_at_wr),
		.ce(aclken),
		.shift_out(mid_res_line_buf_wen_at_wr_d4)
	);
	ram_based_shift_regs #(
		.data_width(1),
		.delay_n(7),
		.shift_type("ff"),
		.en_output_register_init("false"),
		.simulation_delay(SIM_DELAY)
	)delay_for_mid_res_line_buf_wen_at_wr_d4_u(
		.clk(aclk),
		.resetn(1'b1),
		
		.shift_in(mid_res_line_buf_wen_at_wr_d4),
		.ce(aclken),
		.shift_out(mid_res_line_buf_wen_at_wr_d11)
	);
	
	/** 卷积中间结果累加单元 **/
	// 中间结果累加输入
	wire[7:0] acmlt_in_exp[0:ATOMIC_K-1]; // 指数部分(仅当运算数据格式为FP16时有效)
	wire signed[39:0] acmlt_in_frac[0:ATOMIC_K-1]; // 尾数部分或定点数
	wire[31:0] acmlt_in_org_mid_res[0:ATOMIC_K-1]; // 原中间结果
	wire acmlt_in_first_item[0:ATOMIC_K-1]; // 是否第1项(标志)
	wire[ATOMIC_K-1:0] acmlt_in_info_along[0:ATOMIC_K-1]; // 随路数据
	wire acmlt_in_valid[0:ATOMIC_K-1]; // 输入有效指示
	// 中间结果累加输出
	wire[31:0] acmlt_out_data[0:ATOMIC_K-1]; // 单精度浮点数或定点数
	wire[32*ATOMIC_K-1:0] acmlt_out_data_flattened; // 展平的单精度浮点数或定点数
	wire[ATOMIC_K-1:0] acmlt_out_info_along[0:ATOMIC_K-1]; // 随路数据
	wire acmlt_out_valid[0:ATOMIC_K-1]; // 输出有效指示
	
	genvar acmlt_i;
	generate
		for(acmlt_i = 0;acmlt_i < ATOMIC_K;acmlt_i = acmlt_i + 1)
		begin:acmlt_blk
			assign acmlt_in_exp[acmlt_i] = mid_res_new_item_s2[acmlt_i*48+47:acmlt_i*48+40];
			assign acmlt_in_frac[acmlt_i] = mid_res_new_item_s2[acmlt_i*48+39:acmlt_i*48+0];
			assign acmlt_in_org_mid_res[acmlt_i] = mid_res_data_s2[acmlt_i*32+31:acmlt_i*32];
			assign acmlt_in_first_item[acmlt_i] = mid_res_first_item_s2;
			assign acmlt_in_info_along[acmlt_i] = mid_res_mask_s2;
			assign acmlt_in_valid[acmlt_i] = mid_res_valid_s2;
			
			assign acmlt_out_data_flattened[acmlt_i*32+31:acmlt_i*32] = acmlt_out_data[acmlt_i];
			
			conv_middle_res_accumulate #(
				.EN_SMALL_FP32(EN_SMALL_FP32),
				.INFO_ALONG_WIDTH(ATOMIC_K),
				.SIM_DELAY(SIM_DELAY)
			)conv_middle_res_accumulate_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(aclken),
				
				.calfmt(calfmt),
				
				.acmlt_in_exp(acmlt_in_exp[acmlt_i]),
				.acmlt_in_frac(acmlt_in_frac[acmlt_i]),
				.acmlt_in_org_mid_res(acmlt_in_org_mid_res[acmlt_i]),
				.acmlt_in_first_item(acmlt_in_first_item[acmlt_i]),
				.acmlt_in_info_along(acmlt_in_info_along[acmlt_i]),
				.acmlt_in_valid(acmlt_in_valid[acmlt_i]),
				
				.acmlt_out_data(acmlt_out_data[acmlt_i]),
				.acmlt_out_info_along(acmlt_out_info_along[acmlt_i]),
				.acmlt_out_valid(acmlt_out_valid[acmlt_i])
			);
		end
	endgenerate
	
	/** 存储器接口 **/
	reg[clogb2(RBUF_DEPTH-1):0] mem_waddr; // 缓存MEM写地址
	
	assign mem_clk_a = aclk;
	assign mem_clk_b = aclk;
	
	genvar mem_i;
	generate
		for(mem_i = 0;mem_i < RBUF_BANK_N;mem_i = mem_i + 1)
		begin:mem_blk
			assign mem_wen_a[mem_i] = 
				aclken & 
				(~mid_res_line_buf_filled[mem_i]) & (mid_res_line_buf_wptr_at_rd[clogb2(RBUF_BANK_N-1):0] == mem_i) & 
				acmlt_out_valid[0];
			assign mem_addr_a[(mem_i+1)*16-1:mem_i*16] = mem_waddr | 16'h0000;
			assign mem_din_a[(mem_i+1)*(32*ATOMIC_K+ATOMIC_K)-1:mem_i*(32*ATOMIC_K+ATOMIC_K)] = 
				{acmlt_out_info_along[0], acmlt_out_data_flattened};
			
			assign mem_ren_b[mem_i] = 
				aclken & (
					mid_res_line_buf_filled[mem_i] ? 
						(
							fnl_res_valid_s0 & fnl_res_ready_s0 & 
							(mid_res_line_buf_rptr_at_rd[clogb2(RBUF_BANK_N-1):0] == mem_i)
						):
						(
							s_axis_mid_res_valid & s_axis_mid_res_ready & 
							(mid_res_line_buf_wptr_at_wr[clogb2(RBUF_BANK_N-1):0] == mem_i)
						)
				);
			assign mem_addr_b[(mem_i+1)*16-1:mem_i*16] = 
				(
					mid_res_line_buf_filled[mem_i] ? 
						col_cnt_at_rd:
						col_cnt_at_wr
				) | 16'h0000;
		end
	endgenerate
	
	// 缓存MEM写地址
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mem_waddr <= 0;
		else if(acmlt_out_valid[0])
			mem_waddr <= # SIM_DELAY 
				(mem_waddr == ofmw_sub1[clogb2(RBUF_DEPTH-1):0]) ? 
					0:
					(mem_waddr + 1);
	end
	
endmodule
