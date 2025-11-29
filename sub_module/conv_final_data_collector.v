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
本模块: 最终结果数据收集器

描述:
对最终结果数据流实施以项为单元的流整理, 形成带规范KEEP信号(当last无效时, KEEP信号全1;当last信号有效时, 
	KEEP信号可以不全1但必须对齐到LSB且无空洞)的输出AXIS流

输入/输出流的项数可以不同

注意：
要求KEEP信号不能有空洞且对齐到LSB, 如1111、0111、0011、0001、0000是符合要求的, 而0101不符合要求
要求USER信号在AXIS数据包里的每次传输都是相同的, 因此USER信号的存储仅相对于每个数据包而言

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/11/21
********************************************************************/


module conv_final_data_collector #(
	parameter integer IN_ITEM_WIDTH = 4, // 输入流的项位宽(必须<=32)
	parameter integer OUT_ITEM_WIDTH = 2, // 输出流的项位宽(必须<=32)
	parameter integer DATA_WIDTH_FOREACH_ITEM = 16, // 每个项的数据位宽(8 | 16 | 32 | ...)
	parameter HAS_USER = "true", // 是否有USER信号
	parameter integer USER_WIDTH = 1, // USER信号位宽(必须>=1, 不用时悬空即可)
	parameter EN_COLLECTOR_OUT_REG_SLICE = "true", // 是否在"收集器输出"处插入寄存器片
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 收集器输入(AXIS从机)
	input wire[IN_ITEM_WIDTH*DATA_WIDTH_FOREACH_ITEM-1:0] s_axis_collector_data,
	input wire[IN_ITEM_WIDTH*DATA_WIDTH_FOREACH_ITEM/8-1:0] s_axis_collector_keep,
	input wire[USER_WIDTH-1:0] s_axis_collector_user,
	input wire s_axis_collector_last,
	input wire s_axis_collector_valid,
	output wire s_axis_collector_ready,
	
	// 收集器输出(AXIS主机)
	output wire[OUT_ITEM_WIDTH*DATA_WIDTH_FOREACH_ITEM-1:0] m_axis_collector_data,
	output wire[OUT_ITEM_WIDTH*DATA_WIDTH_FOREACH_ITEM/8-1:0] m_axis_collector_keep,
	output wire[USER_WIDTH-1:0] m_axis_collector_user,
	output wire m_axis_collector_last,
	output wire m_axis_collector_valid,
	input wire m_axis_collector_ready
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
	localparam integer BUF_ITEM_N = 2 * ((IN_ITEM_WIDTH > OUT_ITEM_WIDTH) ? IN_ITEM_WIDTH:OUT_ITEM_WIDTH); // 缓存区项数
	localparam IS_BUF_ITEM_N_POW2 = (BUF_ITEM_N == (1 << clogb2(BUF_ITEM_N))) ? 1'b1:1'b0; // 缓存区项数是否2^n
	
	/** USER信号fifo **/
	// [写端口]
	wire user_sgn_fifo_wen;
	wire[USER_WIDTH-1:0] user_sgn_fifo_din;
	wire user_sgn_fifo_full_n;
	// [读端口]
	wire user_sgn_fifo_ren;
	wire[USER_WIDTH-1:0] user_sgn_fifo_dout;
	wire user_sgn_fifo_empty_n;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(USER_WIDTH),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)user_sgn_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(user_sgn_fifo_wen),
		.fifo_din(user_sgn_fifo_din),
		.fifo_full(),
		.fifo_full_n(user_sgn_fifo_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(),
		
		.fifo_ren(user_sgn_fifo_ren),
		.fifo_dout(user_sgn_fifo_dout),
		.fifo_empty(),
		.fifo_empty_n(user_sgn_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	/** 收集器输入 **/
	wire[DATA_WIDTH_FOREACH_ITEM-1:0] collector_in_data_arr[0:BUF_ITEM_N-1];
	wire[IN_ITEM_WIDTH-1:0] collector_in_mask;
	wire[BUF_ITEM_N-1:0] collector_in_mask_ext;
	wire[BUF_ITEM_N-1:0] collector_in_mask_ext_highest;
	
	genvar in_item_i;
	generate
		for(in_item_i = 0;in_item_i < BUF_ITEM_N;in_item_i = in_item_i + 1)
		begin:in_item_blk
			if(in_item_i < IN_ITEM_WIDTH)
				assign collector_in_data_arr[in_item_i] = s_axis_collector_data[
					(in_item_i+1)*DATA_WIDTH_FOREACH_ITEM-1:
					in_item_i*DATA_WIDTH_FOREACH_ITEM
				];
			else
				assign collector_in_data_arr[in_item_i] = {DATA_WIDTH_FOREACH_ITEM{1'bx}};
			
			if(in_item_i < IN_ITEM_WIDTH)
				assign collector_in_mask[in_item_i] = s_axis_collector_keep[in_item_i*DATA_WIDTH_FOREACH_ITEM/8];
		end
	endgenerate
	
	assign collector_in_mask_ext = collector_in_mask | {BUF_ITEM_N{1'b0}};
	assign collector_in_mask_ext_highest = 
		(collector_in_mask & {1'b1, ~collector_in_mask[IN_ITEM_WIDTH-1:1]}) | {BUF_ITEM_N{1'b0}};
	
	/** 数据缓存 **/
	// [存储实体]
	reg[DATA_WIDTH_FOREACH_ITEM-1:0] data_buf[0:BUF_ITEM_N-1];
	reg[BUF_ITEM_N-1:0] last_buf;
	reg[BUF_ITEM_N-1:0] vld_flag_buf;
	// [写端口]
	wire wen;
	wire[BUF_ITEM_N-1:0] wt_item_mask;
	wire[BUF_ITEM_N-1:0] wt_last_flag_mask;
	reg first_tr_in_pkt;
	reg[clogb2(BUF_ITEM_N-1):0] wptr;
	wire[clogb2(IN_ITEM_WIDTH):0] item_n_to_wt;
	// [读端口]
	wire[DATA_WIDTH_FOREACH_ITEM-1:0] data_rd_region[0:OUT_ITEM_WIDTH-1];
	wire[OUT_ITEM_WIDTH-1:0] last_rd_region;
	wire[OUT_ITEM_WIDTH-1:0] vld_flag_rd_region;
	wire ren;
	reg[clogb2(BUF_ITEM_N-1):0] rptr;
	wire[clogb2(OUT_ITEM_WIDTH):0] item_n_to_rd;
	wire is_last_rd_region;
	wire[OUT_ITEM_WIDTH-1:0] rd_last_item_onehot;
	wire[OUT_ITEM_WIDTH-1:0] rd_item_mask;
	wire[BUF_ITEM_N-1:0] rd_item_mask_ext;
	// [存储量计数]
	reg[clogb2(BUF_ITEM_N):0] stored_item_n;
	reg[clogb2(BUF_ITEM_N):0] empty_item_n;
	
	assign s_axis_collector_ready = 
		aclken & 
		(empty_item_n >= item_n_to_wt) & 
		((HAS_USER == "false") | (~first_tr_in_pkt) | user_sgn_fifo_full_n);
	
	assign user_sgn_fifo_wen = wen & first_tr_in_pkt;
	assign user_sgn_fifo_din = s_axis_collector_user;
	
	assign wen = s_axis_collector_valid & s_axis_collector_ready;
	assign wt_item_mask = (collector_in_mask_ext << wptr) | (collector_in_mask_ext >> (BUF_ITEM_N-wptr));
	assign wt_last_flag_mask = (collector_in_mask_ext_highest << wptr) | (collector_in_mask_ext_highest >> (BUF_ITEM_N-wptr));
	assign item_n_to_wt = 
		({6{(BUF_ITEM_N >= 1)  & collector_in_mask_ext_highest[(BUF_ITEM_N >= 1)  ?  0:0]}} & 6'd1)  | 
		({6{(BUF_ITEM_N >= 2)  & collector_in_mask_ext_highest[(BUF_ITEM_N >= 2)  ?  1:0]}} & 6'd2)  | 
		({6{(BUF_ITEM_N >= 3)  & collector_in_mask_ext_highest[(BUF_ITEM_N >= 3)  ?  2:0]}} & 6'd3)  | 
		({6{(BUF_ITEM_N >= 4)  & collector_in_mask_ext_highest[(BUF_ITEM_N >= 4)  ?  3:0]}} & 6'd4)  | 
		({6{(BUF_ITEM_N >= 5)  & collector_in_mask_ext_highest[(BUF_ITEM_N >= 5)  ?  4:0]}} & 6'd5)  | 
		({6{(BUF_ITEM_N >= 6)  & collector_in_mask_ext_highest[(BUF_ITEM_N >= 6)  ?  5:0]}} & 6'd6)  | 
		({6{(BUF_ITEM_N >= 7)  & collector_in_mask_ext_highest[(BUF_ITEM_N >= 7)  ?  6:0]}} & 6'd7)  | 
		({6{(BUF_ITEM_N >= 8)  & collector_in_mask_ext_highest[(BUF_ITEM_N >= 8)  ?  7:0]}} & 6'd8)  | 
		({6{(BUF_ITEM_N >= 9)  & collector_in_mask_ext_highest[(BUF_ITEM_N >= 9)  ?  8:0]}} & 6'd9)  | 
		({6{(BUF_ITEM_N >= 10) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 10) ?  9:0]}} & 6'd10) | 
		({6{(BUF_ITEM_N >= 11) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 11) ? 10:0]}} & 6'd11) | 
		({6{(BUF_ITEM_N >= 12) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 12) ? 11:0]}} & 6'd12) | 
		({6{(BUF_ITEM_N >= 13) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 13) ? 12:0]}} & 6'd13) | 
		({6{(BUF_ITEM_N >= 14) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 14) ? 13:0]}} & 6'd14) | 
		({6{(BUF_ITEM_N >= 15) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 15) ? 14:0]}} & 6'd15) | 
		({6{(BUF_ITEM_N >= 16) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 16) ? 15:0]}} & 6'd16) | 
		({6{(BUF_ITEM_N >= 17) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 17) ? 16:0]}} & 6'd17) | 
		({6{(BUF_ITEM_N >= 18) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 18) ? 17:0]}} & 6'd18) | 
		({6{(BUF_ITEM_N >= 19) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 19) ? 18:0]}} & 6'd19) | 
		({6{(BUF_ITEM_N >= 20) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 20) ? 19:0]}} & 6'd20) | 
		({6{(BUF_ITEM_N >= 21) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 21) ? 20:0]}} & 6'd21) | 
		({6{(BUF_ITEM_N >= 22) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 22) ? 21:0]}} & 6'd22) | 
		({6{(BUF_ITEM_N >= 23) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 23) ? 22:0]}} & 6'd23) | 
		({6{(BUF_ITEM_N >= 24) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 24) ? 23:0]}} & 6'd24) | 
		({6{(BUF_ITEM_N >= 25) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 25) ? 24:0]}} & 6'd25) | 
		({6{(BUF_ITEM_N >= 26) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 26) ? 25:0]}} & 6'd26) | 
		({6{(BUF_ITEM_N >= 27) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 27) ? 26:0]}} & 6'd27) | 
		({6{(BUF_ITEM_N >= 28) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 28) ? 27:0]}} & 6'd28) | 
		({6{(BUF_ITEM_N >= 29) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 29) ? 28:0]}} & 6'd29) | 
		({6{(BUF_ITEM_N >= 30) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 30) ? 29:0]}} & 6'd30) | 
		({6{(BUF_ITEM_N >= 31) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 31) ? 30:0]}} & 6'd31) | 
		({6{(BUF_ITEM_N >= 32) & collector_in_mask_ext_highest[(BUF_ITEM_N >= 32) ? 31:0]}} & 6'd32);
	
	assign item_n_to_rd = 
		is_last_rd_region ? 
		(
			({6{(OUT_ITEM_WIDTH >= 1)  & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 1)  ?  0:0]}} & 6'd1)  | 
			({6{(OUT_ITEM_WIDTH >= 2)  & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 2)  ?  1:0]}} & 6'd2)  | 
			({6{(OUT_ITEM_WIDTH >= 3)  & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 3)  ?  2:0]}} & 6'd3)  | 
			({6{(OUT_ITEM_WIDTH >= 4)  & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 4)  ?  3:0]}} & 6'd4)  | 
			({6{(OUT_ITEM_WIDTH >= 5)  & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 5)  ?  4:0]}} & 6'd5)  | 
			({6{(OUT_ITEM_WIDTH >= 6)  & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 6)  ?  5:0]}} & 6'd6)  | 
			({6{(OUT_ITEM_WIDTH >= 7)  & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 7)  ?  6:0]}} & 6'd7)  | 
			({6{(OUT_ITEM_WIDTH >= 8)  & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 8)  ?  7:0]}} & 6'd8)  | 
			({6{(OUT_ITEM_WIDTH >= 9)  & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 9)  ?  8:0]}} & 6'd9)  | 
			({6{(OUT_ITEM_WIDTH >= 10) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 10) ?  9:0]}} & 6'd10) | 
			({6{(OUT_ITEM_WIDTH >= 11) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 11) ? 10:0]}} & 6'd11) | 
			({6{(OUT_ITEM_WIDTH >= 12) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 12) ? 11:0]}} & 6'd12) | 
			({6{(OUT_ITEM_WIDTH >= 13) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 13) ? 12:0]}} & 6'd13) | 
			({6{(OUT_ITEM_WIDTH >= 14) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 14) ? 13:0]}} & 6'd14) | 
			({6{(OUT_ITEM_WIDTH >= 15) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 15) ? 14:0]}} & 6'd15) | 
			({6{(OUT_ITEM_WIDTH >= 16) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 16) ? 15:0]}} & 6'd16) | 
			({6{(OUT_ITEM_WIDTH >= 17) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 17) ? 16:0]}} & 6'd17) | 
			({6{(OUT_ITEM_WIDTH >= 18) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 18) ? 17:0]}} & 6'd18) | 
			({6{(OUT_ITEM_WIDTH >= 19) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 19) ? 18:0]}} & 6'd19) | 
			({6{(OUT_ITEM_WIDTH >= 20) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 20) ? 19:0]}} & 6'd20) | 
			({6{(OUT_ITEM_WIDTH >= 21) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 21) ? 20:0]}} & 6'd21) | 
			({6{(OUT_ITEM_WIDTH >= 22) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 22) ? 21:0]}} & 6'd22) | 
			({6{(OUT_ITEM_WIDTH >= 23) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 23) ? 22:0]}} & 6'd23) | 
			({6{(OUT_ITEM_WIDTH >= 24) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 24) ? 23:0]}} & 6'd24) | 
			({6{(OUT_ITEM_WIDTH >= 25) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 25) ? 24:0]}} & 6'd25) | 
			({6{(OUT_ITEM_WIDTH >= 26) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 26) ? 25:0]}} & 6'd26) | 
			({6{(OUT_ITEM_WIDTH >= 27) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 27) ? 26:0]}} & 6'd27) | 
			({6{(OUT_ITEM_WIDTH >= 28) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 28) ? 27:0]}} & 6'd28) | 
			({6{(OUT_ITEM_WIDTH >= 29) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 29) ? 28:0]}} & 6'd29) | 
			({6{(OUT_ITEM_WIDTH >= 30) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 30) ? 29:0]}} & 6'd30) | 
			({6{(OUT_ITEM_WIDTH >= 31) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 31) ? 30:0]}} & 6'd31) | 
			({6{(OUT_ITEM_WIDTH >= 32) & rd_last_item_onehot[(OUT_ITEM_WIDTH >= 32) ? 31:0]}} & 6'd32)
		):
		OUT_ITEM_WIDTH;
	assign is_last_rd_region = |(vld_flag_rd_region & last_rd_region);
	
	genvar rd_i;
	generate
		for(rd_i = 0;rd_i < OUT_ITEM_WIDTH;rd_i = rd_i + 1)
		begin:rd_blk
			assign data_rd_region[rd_i] = 
				data_buf[(rptr >= (BUF_ITEM_N - rd_i)) ? (rptr + rd_i - BUF_ITEM_N):(rptr + rd_i)];
			assign last_rd_region[rd_i] = 
				last_buf[(rptr >= (BUF_ITEM_N - rd_i)) ? (rptr + rd_i - BUF_ITEM_N):(rptr + rd_i)];
			assign vld_flag_rd_region[rd_i] = 
				vld_flag_buf[(rptr >= (BUF_ITEM_N - rd_i)) ? (rptr + rd_i - BUF_ITEM_N):(rptr + rd_i)];
			
			if(rd_i == 0)
				assign rd_last_item_onehot[rd_i] = 
					(vld_flag_rd_region[rd_i] & last_rd_region[rd_i]);
			else
				assign rd_last_item_onehot[rd_i] = 
					(vld_flag_rd_region[rd_i] & last_rd_region[rd_i]) & 
					(~(|(vld_flag_rd_region[rd_i-1:0] & last_rd_region[rd_i-1:0])));
		end
	endgenerate
	
	/*
	  vld & last,1'b0       掩码计算过程
	--------------------------------------------
		 0000,0       1111,1 & 1111,1 = 1111,1
		 0001,0       0000,1 & 1110,1 = 0000,1
		 0010,0       0001,1 & 1101,1 = 0001,1
		 0011,0       0010,1 & 1100,1 = 0000,1
		 1000,0       0111,1 & 0111,1 = 0111,1
		 1010,0       1001,1 & 0101,1 = 0001,1
	*/
	assign rd_item_mask = 
		({vld_flag_rd_region & last_rd_region, 1'b0} - 1) & 
		(~{vld_flag_rd_region & last_rd_region, 1'b0});
	assign rd_item_mask_ext = (rd_item_mask << rptr) | (rd_item_mask >> (BUF_ITEM_N-rptr));
	
	genvar buf_i;
	generate
		for(buf_i = 0;buf_i < BUF_ITEM_N;buf_i = buf_i + 1)
		begin:buf_blk
			always @(posedge aclk)
			begin
				if(
					aclken & 
					wen & wt_item_mask[buf_i]
				)
					data_buf[buf_i] <= # SIM_DELAY 
						collector_in_data_arr[
							(buf_i >= wptr) ? 
								(buf_i - wptr):
								(BUF_ITEM_N + buf_i - wptr)
						];
			end
			
			always @(posedge aclk)
			begin
				if(
					aclken & 
					wen & wt_item_mask[buf_i]
				)
					last_buf[buf_i] <= # SIM_DELAY 
						wt_last_flag_mask[buf_i] & s_axis_collector_last;
			end
			
			always @(posedge aclk)
			begin
				if(~aresetn)
					vld_flag_buf[buf_i] <= 1'b0;
				else if(
					aclken & 
					(
						(wen & wt_item_mask[buf_i]) | 
						(ren & rd_item_mask_ext[buf_i])
					)
				)
					vld_flag_buf[buf_i] <= # SIM_DELAY 
						wen & wt_item_mask[buf_i];
			end
		end
	endgenerate
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			first_tr_in_pkt <= 1'b1;
		else if(aclken & wen)
			first_tr_in_pkt <= # SIM_DELAY s_axis_collector_last;
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wptr <= 0;
		else if(aclken & wen)
			wptr <= # SIM_DELAY 
				(((wptr + item_n_to_wt) >= BUF_ITEM_N) & (~IS_BUF_ITEM_N_POW2)) ? 
					(wptr + item_n_to_wt - BUF_ITEM_N):
					(wptr + item_n_to_wt);
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rptr <= 0;
		else if(aclken & ren)
			rptr <= # SIM_DELAY 
				(((rptr + item_n_to_rd) >= BUF_ITEM_N) & (~IS_BUF_ITEM_N_POW2)) ? 
					(rptr + item_n_to_rd - BUF_ITEM_N):
					(rptr + item_n_to_rd);
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			stored_item_n <= 0;
		else if(wen | ren)
			stored_item_n <= # SIM_DELAY 
				stored_item_n + (wen ? item_n_to_wt:0) - (ren ? item_n_to_rd:0);
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			empty_item_n <= BUF_ITEM_N;
		else if(wen | ren)
			empty_item_n <= # SIM_DELAY 
				empty_item_n - (wen ? item_n_to_wt:0) + (ren ? item_n_to_rd:0);
	end
	
	/** 收集器输出 **/
	wire[OUT_ITEM_WIDTH*DATA_WIDTH_FOREACH_ITEM-1:0] s_axis_collector_oreg_data;
	wire[OUT_ITEM_WIDTH*DATA_WIDTH_FOREACH_ITEM/8-1:0] s_axis_collector_oreg_keep;
	wire[USER_WIDTH-1:0] s_axis_collector_oreg_user;
	wire s_axis_collector_oreg_last;
	wire s_axis_collector_oreg_valid;
	wire s_axis_collector_oreg_ready;
	wire[OUT_ITEM_WIDTH*DATA_WIDTH_FOREACH_ITEM-1:0] m_axis_collector_oreg_data;
	wire[OUT_ITEM_WIDTH*DATA_WIDTH_FOREACH_ITEM/8-1:0] m_axis_collector_oreg_keep;
	wire[USER_WIDTH-1:0] m_axis_collector_oreg_user;
	wire m_axis_collector_oreg_last;
	wire m_axis_collector_oreg_valid;
	wire m_axis_collector_oreg_ready;
	
	assign m_axis_collector_data = m_axis_collector_oreg_data;
	assign m_axis_collector_keep = m_axis_collector_oreg_keep;
	assign m_axis_collector_user = m_axis_collector_oreg_user;
	assign m_axis_collector_last = m_axis_collector_oreg_last;
	assign m_axis_collector_valid = m_axis_collector_oreg_valid;
	assign m_axis_collector_oreg_ready = m_axis_collector_ready;
	
	genvar out_item_i;
	generate
		for(out_item_i = 0;out_item_i < OUT_ITEM_WIDTH;out_item_i = out_item_i + 1)
		begin:out_blk
			assign s_axis_collector_oreg_data[(out_item_i+1)*DATA_WIDTH_FOREACH_ITEM-1:out_item_i*DATA_WIDTH_FOREACH_ITEM] = 
				data_rd_region[out_item_i];
			assign s_axis_collector_oreg_keep[(out_item_i+1)*(DATA_WIDTH_FOREACH_ITEM/8)-1:out_item_i*(DATA_WIDTH_FOREACH_ITEM/8)] = 
				{(DATA_WIDTH_FOREACH_ITEM/8){rd_item_mask[out_item_i]}};
		end
	endgenerate
	
	assign s_axis_collector_oreg_user = user_sgn_fifo_dout;
	assign s_axis_collector_oreg_last = is_last_rd_region;
	assign s_axis_collector_oreg_valid = 
		aclken & 
		(is_last_rd_region | (stored_item_n >= OUT_ITEM_WIDTH)) & 
		((HAS_USER == "false") | user_sgn_fifo_empty_n);
	
	assign user_sgn_fifo_ren = ren & is_last_rd_region;
	assign ren = s_axis_collector_oreg_valid & s_axis_collector_oreg_ready;
	
	axis_reg_slice #(
		.data_width(OUT_ITEM_WIDTH*DATA_WIDTH_FOREACH_ITEM),
		.user_width(USER_WIDTH),
		.forward_registered(EN_COLLECTOR_OUT_REG_SLICE),
		.back_registered("false"),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)collector_o_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(aclken),
		
		.s_axis_data(s_axis_collector_oreg_data),
		.s_axis_keep(s_axis_collector_oreg_keep),
		.s_axis_user(s_axis_collector_oreg_user),
		.s_axis_last(s_axis_collector_oreg_last),
		.s_axis_valid(s_axis_collector_oreg_valid),
		.s_axis_ready(s_axis_collector_oreg_ready),
		
		.m_axis_data(m_axis_collector_oreg_data),
		.m_axis_keep(m_axis_collector_oreg_keep),
		.m_axis_user(m_axis_collector_oreg_user),
		.m_axis_last(m_axis_collector_oreg_last),
		.m_axis_valid(m_axis_collector_oreg_valid),
		.m_axis_ready(m_axis_collector_oreg_ready)
	);
	
endmodule
