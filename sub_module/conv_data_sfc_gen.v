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
本模块: 特征图/卷积核表面生成单元

描述:
从特征图/卷积核数据流根据"每个表面的有效数据个数"生成表面流

注意：
"随路传输附加数据"和"每个表面的有效数据个数"在每个数据包内保持不变
"每个表面的有效数据个数"必须<=ATOMIC_C

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/08/01
********************************************************************/


module conv_data_sfc_gen #(
	parameter integer STREAM_DATA_WIDTH = 32, // 特征图/卷积核数据流的数据位宽(32 | 64 | 128 | 256)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer EXTRA_DATA_WIDTH = 26, // 随路传输附加数据的位宽(必须>=1)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 特征图/卷积核数据流(AXIS从机)
	input wire[STREAM_DATA_WIDTH-1:0] s_stream_axis_data,
	input wire[STREAM_DATA_WIDTH/8-1:0] s_stream_axis_keep,
	input wire[5+EXTRA_DATA_WIDTH-1:0] s_stream_axis_user, // {随路传输附加数据(EXTRA_DATA_WIDTH bit), 每个表面的有效数据个数 - 1(5bit)}
	input wire s_stream_axis_last,
	input wire s_stream_axis_valid,
	output wire s_stream_axis_ready,
	
	// 特征图/卷积核表面流(AXIS主机)
	output wire[ATOMIC_C*2*8-1:0] m_sfc_axis_data,
	output wire[ATOMIC_C*2-1:0] m_sfc_axis_keep,
	output wire[EXTRA_DATA_WIDTH-1:0] m_sfc_axis_user, // {随路传输附加数据(EXTRA_DATA_WIDTH bit)}
	output wire m_sfc_axis_last,
	output wire m_sfc_axis_valid,
	input wire m_sfc_axis_ready
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
	// 半字缓存区的大小
	localparam HW_BUF_LEN = 
		(STREAM_DATA_WIDTH > (ATOMIC_C*2*8)) ? 
			(STREAM_DATA_WIDTH/16*2):
			(ATOMIC_C*2);
	
	/** 特征图/卷积核数据流 **/
	// [传输状态]
	reg first_trans_within_strm; // 数据流内的首次传输(标志)
	wire[STREAM_DATA_WIDTH/16-1:0] cur_strm_trans_hw_vld; // 当前传输的半字有效(标志向量)
	wire[clogb2(STREAM_DATA_WIDTH/16):0] vld_hw_n_of_cur_strm_trans; // 当前传输的有效半字数
	wire[clogb2(STREAM_DATA_WIDTH/16-1):0] vld_hw_n_sub1_of_cur_strm_trans; // 当前传输的有效半字数 - 1
	wire cur_strm_trans_bufferable; // 当前传输可缓存(标志)
	// [数据包信息fifo]
	wire strm_pkt_msg_fifo_wen;
	wire[11+EXTRA_DATA_WIDTH-1:0] strm_pkt_msg_fifo_din; // {每个表面的有效数据个数(6bit), 随路传输附加数据(EXTRA_DATA_WIDTH bit), 
	                                                     //     每个表面的有效数据个数 - 1(5bit)}
	wire strm_pkt_msg_fifo_full_n;
	wire strm_pkt_msg_fifo_ren;
	wire[11+EXTRA_DATA_WIDTH-1:0] strm_pkt_msg_fifo_dout; // {每个表面的有效数据个数(6bit), 随路传输附加数据(EXTRA_DATA_WIDTH bit), 
	                                                      //     每个表面的有效数据个数 - 1(5bit)}
	wire strm_pkt_msg_fifo_empty_n;
	
	assign s_stream_axis_ready = 
		aclken & cur_strm_trans_bufferable & ((~first_trans_within_strm) | strm_pkt_msg_fifo_full_n);
	
	genvar strm_hw_vld_i;
	generate
		for(strm_hw_vld_i = 0;strm_hw_vld_i < STREAM_DATA_WIDTH/16;strm_hw_vld_i = strm_hw_vld_i + 1)
		begin:cur_strm_trans_hw_vld_blk
			assign cur_strm_trans_hw_vld[strm_hw_vld_i] = s_stream_axis_keep[2*strm_hw_vld_i+1];
		end
	endgenerate
	
	assign vld_hw_n_of_cur_strm_trans = 
		((STREAM_DATA_WIDTH >= 256) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 256) ? 15:0]) ? 16:
		((STREAM_DATA_WIDTH >= 256) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 256) ? 14:0]) ? 15:
		((STREAM_DATA_WIDTH >= 256) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 256) ? 13:0]) ? 14:
		((STREAM_DATA_WIDTH >= 256) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 256) ? 12:0]) ? 13:
		((STREAM_DATA_WIDTH >= 256) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 256) ? 11:0]) ? 12:
		((STREAM_DATA_WIDTH >= 256) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 256) ? 10:0]) ? 11:
		((STREAM_DATA_WIDTH >= 256) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 256) ?  9:0]) ? 10:
		((STREAM_DATA_WIDTH >= 256) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 256) ?  8:0]) ?  9:
		((STREAM_DATA_WIDTH >= 128) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 128) ?  7:0]) ?  8:
		((STREAM_DATA_WIDTH >= 128) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 128) ?  6:0]) ?  7:
		((STREAM_DATA_WIDTH >= 128) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 128) ?  5:0]) ?  6:
		((STREAM_DATA_WIDTH >= 128) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >= 128) ?  4:0]) ?  5:
		((STREAM_DATA_WIDTH >=  64) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >=  64) ?  3:0]) ?  4:
		((STREAM_DATA_WIDTH >=  64) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >=  64) ?  2:0]) ?  3:
		((STREAM_DATA_WIDTH >=  32) & cur_strm_trans_hw_vld[(STREAM_DATA_WIDTH >=  32) ?  1:0]) ?  2:
		                                                                                           1;
	assign vld_hw_n_sub1_of_cur_strm_trans = vld_hw_n_of_cur_strm_trans - 1;
	
	assign strm_pkt_msg_fifo_wen = aclken & s_stream_axis_valid & s_stream_axis_ready & first_trans_within_strm;
	assign strm_pkt_msg_fifo_din[5+EXTRA_DATA_WIDTH-1:0] = s_stream_axis_user;
	assign strm_pkt_msg_fifo_din[11+EXTRA_DATA_WIDTH-1:5+EXTRA_DATA_WIDTH] = {1'b0, s_stream_axis_user[4:0]} + 1'b1;
	assign strm_pkt_msg_fifo_ren = aclken & m_sfc_axis_valid & m_sfc_axis_ready & m_sfc_axis_last;
	
	// 数据流内的首次传输(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			first_trans_within_strm <= 1'b1;
		else if(aclken & s_stream_axis_valid & s_stream_axis_ready)
			first_trans_within_strm <= # SIM_DELAY s_stream_axis_last;
	end
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(2),
		.fifo_data_width(EXTRA_DATA_WIDTH+11),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)strm_pkt_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(strm_pkt_msg_fifo_wen),
		.fifo_din(strm_pkt_msg_fifo_din),
		.fifo_full_n(strm_pkt_msg_fifo_full_n),
		
		.fifo_ren(strm_pkt_msg_fifo_ren),
		.fifo_dout(strm_pkt_msg_fifo_dout),
		.fifo_empty_n(strm_pkt_msg_fifo_empty_n)
	);
	
	/** 半字缓存 **/
	reg[15:0] hw_buf_data[0:HW_BUF_LEN-1]; // 半字缓存区(data字段)
	reg hw_buf_last[0:HW_BUF_LEN-1]; // 半字缓存区(last字段)
	reg[clogb2(HW_BUF_LEN):0] hw_stored_cnt; // 已存储的半字(计数器)
	reg[clogb2(HW_BUF_LEN-1):0] hw_buf_wptr; // 半字缓存区写指针
	reg[clogb2(HW_BUF_LEN-1):0] hw_buf_rptr; // 半字缓存区读指针
	wire[HW_BUF_LEN-1:0] hw_buf_wen; // 半字缓存区写使能
	wire[16*HW_BUF_LEN-1:0] hw_buf_wdata; // 半字缓存区写数据(data字段)
	wire[HW_BUF_LEN-1:0] hw_buf_wlast; // 半字缓存区写数据(last字段)
	wire[16*HW_BUF_LEN-1:0] hw_buf_rdata; // 半字缓存区读数据(data字段)
	wire[HW_BUF_LEN-1:0] hw_buf_rlast; // 半字缓存区读数据(last字段)
	
	assign cur_strm_trans_bufferable = 
		// 更严格的条件: hw_stored_cnt <= (HW_BUF_LEN-STREAM_DATA_WIDTH/16)
		hw_stored_cnt <= (HW_BUF_LEN-vld_hw_n_of_cur_strm_trans);
	
	assign hw_buf_wen = 
		{HW_BUF_LEN{aclken & s_stream_axis_valid & s_stream_axis_ready}} & 
		(
			((cur_strm_trans_hw_vld | {HW_BUF_LEN{1'b0}}) << hw_buf_wptr) | 
			((cur_strm_trans_hw_vld | {HW_BUF_LEN{1'b0}}) >> (HW_BUF_LEN-hw_buf_wptr))
		);
	assign hw_buf_wdata = 
		((s_stream_axis_data | {(16*HW_BUF_LEN){1'b0}}) << (hw_buf_wptr*16)) | 
		((s_stream_axis_data | {(16*HW_BUF_LEN){1'b0}}) >> ((HW_BUF_LEN-hw_buf_wptr)*16));
	assign hw_buf_wlast = 
		(((s_stream_axis_last | {HW_BUF_LEN{1'b0}}) << vld_hw_n_sub1_of_cur_strm_trans) << hw_buf_wptr) | 
		(((s_stream_axis_last | {HW_BUF_LEN{1'b0}}) << vld_hw_n_sub1_of_cur_strm_trans) >> (HW_BUF_LEN-hw_buf_wptr));
	
	// 已存储的半字(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			hw_stored_cnt <= 0;
		else if(
			aclken & 
			(
				(s_stream_axis_valid & s_stream_axis_ready) | 
				(m_sfc_axis_valid & m_sfc_axis_ready)
			)
		)
			hw_stored_cnt <= # SIM_DELAY 
				hw_stored_cnt + 
				(
					(s_stream_axis_valid & s_stream_axis_ready) ? 
						vld_hw_n_of_cur_strm_trans:
						0
				) - 
				(
					(m_sfc_axis_valid & m_sfc_axis_ready) ? 
						strm_pkt_msg_fifo_dout[11+EXTRA_DATA_WIDTH-1:5+EXTRA_DATA_WIDTH]:
						0
				);
	end
	
	// 半字缓存区写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			hw_buf_wptr <= 0;
		else if(aclken & s_stream_axis_valid & s_stream_axis_ready)
			hw_buf_wptr <= # SIM_DELAY hw_buf_wptr + vld_hw_n_of_cur_strm_trans;
	end
	
	// 半字缓存区读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			hw_buf_rptr <= 0;
		else if(aclken & m_sfc_axis_valid & m_sfc_axis_ready)
			hw_buf_rptr <= # SIM_DELAY hw_buf_rptr + strm_pkt_msg_fifo_dout[11+EXTRA_DATA_WIDTH-1:5+EXTRA_DATA_WIDTH];
	end
	
	// 半字缓存区(字段:data, last), 半字缓存区读数据(字段:data, last)
	genvar hw_buf_i;
	generate
		for(hw_buf_i = 0;hw_buf_i < HW_BUF_LEN;hw_buf_i = hw_buf_i + 1)
		begin:hw_buf_blk
			assign hw_buf_rdata[16*hw_buf_i+15:16*hw_buf_i] = 
				hw_buf_data[(hw_buf_rptr+hw_buf_i) & {(clogb2(HW_BUF_LEN-1)+1){1'b1}}];
			assign hw_buf_rlast[hw_buf_i] = 
				hw_buf_last[(hw_buf_rptr+hw_buf_i) & {(clogb2(HW_BUF_LEN-1)+1){1'b1}}];
			
			always @(posedge aclk)
			begin
				if(hw_buf_wen[hw_buf_i])
					hw_buf_data[hw_buf_i] <= # SIM_DELAY hw_buf_wdata[16*hw_buf_i+15:16*hw_buf_i];
			end
			
			always @(posedge aclk)
			begin
				if(hw_buf_wen[hw_buf_i])
					hw_buf_last[hw_buf_i] <= # SIM_DELAY hw_buf_wlast[hw_buf_i];
			end
		end
	endgenerate
	
	/** 特征图/卷积核表面流 **/
	assign m_sfc_axis_data = hw_buf_rdata[ATOMIC_C*2*8-1:0];
	
	genvar m_sfc_axis_keep_i;
	generate
		for(m_sfc_axis_keep_i = 0;m_sfc_axis_keep_i < ATOMIC_C;m_sfc_axis_keep_i = m_sfc_axis_keep_i + 1)
		begin:m_sfc_axis_keep_blk
			assign m_sfc_axis_keep[2*m_sfc_axis_keep_i+1:2*m_sfc_axis_keep_i] = 
				{2{strm_pkt_msg_fifo_dout[4:0] >= m_sfc_axis_keep_i}};
		end
	endgenerate
	
	assign m_sfc_axis_user = strm_pkt_msg_fifo_dout[5+EXTRA_DATA_WIDTH-1:5];
	assign m_sfc_axis_last = hw_buf_rlast[strm_pkt_msg_fifo_dout[4:0]];
	assign m_sfc_axis_valid = 
		aclken & 
		strm_pkt_msg_fifo_empty_n & 
		/*
		hw_stored_cnt >= ({1'b0, strm_pkt_msg_fifo_dout[4:0]} + 1'b1) -> hw_stored_cnt > strm_pkt_msg_fifo_dout[4:0]
		
		比如, x >= 3 + 1 -> x > 3
		*/
		(hw_stored_cnt > strm_pkt_msg_fifo_dout[4:0]);
	
endmodule
