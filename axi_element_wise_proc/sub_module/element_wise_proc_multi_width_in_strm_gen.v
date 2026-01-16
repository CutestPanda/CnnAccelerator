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
本模块: (逐元素操作处理)可变位宽输入流生成单元

描述:
从总线数据流(位宽 = BUS_WIDTH)转换到逐元素操作处理输入流(项位宽 = 8/16/32, 项数 = ELEMENT_WISE_PROC_PIPELINE_N)

带有全局时钟使能

注意:
必须满足总线位宽(BUS_WIDTH)能被输入流的最大位宽(ELEMENT_WISE_PROC_PIPELINE_N * 最大的项位宽)所整除

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2026/01/14
********************************************************************/


module element_wise_proc_multi_width_in_strm_gen #(
	parameter integer BUS_WIDTH = 64, // 总线位宽(32 | 64 | 128 | 256)
	parameter integer ELEMENT_WISE_PROC_PIPELINE_N = 4, // 逐元素操作处理流水线条数(1 | 2 | 4 | 8 | 16 | 32)
	parameter IN_STRM_WIDTH_1_BYTE_SUPPORTED = 1'b1, // 是否支持输入流项位宽为1字节
	parameter IN_STRM_WIDTH_2_BYTE_SUPPORTED = 1'b1, // 是否支持输入流项位宽为2字节
	parameter IN_STRM_WIDTH_4_BYTE_SUPPORTED = 1'b1, // 是否支持输入流项位宽为4字节
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟
	input wire aclk,
	input wire aclken,
	
	// 使能信号
	input wire en_in_strm_gen, // 使能输入流生成
	
	// 运行时参数
	input wire[2:0] in_data_fmt, // 输入数据格式
	
	// 总线数据流(AXIS从机)
	input wire[BUS_WIDTH-1:0] s_axis_data,
	input wire[BUS_WIDTH/8-1:0] s_axis_keep,
	input wire s_axis_last,
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// (逐元素操作处理)输入流(AXIS主机)
	output wire[ELEMENT_WISE_PROC_PIPELINE_N*32-1:0] m_axis_data,
	output wire[ELEMENT_WISE_PROC_PIPELINE_N*4-1:0] m_axis_keep,
	output wire m_axis_last,
	output wire m_axis_valid,
	input wire m_axis_ready
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
	// 输入数据格式的编码
	localparam IN_DATA_FMT_U8 = 3'b000;
	localparam IN_DATA_FMT_S8 = 3'b001;
	localparam IN_DATA_FMT_U16 = 3'b010;
	localparam IN_DATA_FMT_S16 = 3'b011;
	localparam IN_DATA_FMT_U32 = 3'b100;
	localparam IN_DATA_FMT_S32 = 3'b101;
	localparam IN_DATA_FMT_FP16 = 3'b110;
	localparam IN_DATA_FMT_NONE = 3'b111;
	// 输入流项位宽类型的编码
	localparam IN_STRM_WIDTH_TYPE_1_BYTE = 2'b00;
	localparam IN_STRM_WIDTH_TYPE_2_BYTE = 2'b01;
	localparam IN_STRM_WIDTH_TYPE_4_BYTE = 2'b10;
	
	/** 输入流项位宽类型 **/
	wire[1:0] in_strm_width_type;
	
	assign in_strm_width_type = 
		(
			IN_STRM_WIDTH_1_BYTE_SUPPORTED & 
			((in_data_fmt == IN_DATA_FMT_U8) | (in_data_fmt == IN_DATA_FMT_S8))
		) ? 
			IN_STRM_WIDTH_TYPE_1_BYTE:
			(
				(
					IN_STRM_WIDTH_2_BYTE_SUPPORTED & 
					((in_data_fmt == IN_DATA_FMT_U16) | (in_data_fmt == IN_DATA_FMT_S16) | (in_data_fmt == IN_DATA_FMT_FP16))
				) ? 
					IN_STRM_WIDTH_TYPE_2_BYTE:
					IN_STRM_WIDTH_TYPE_4_BYTE
			);
	
	/**
	总线数据缓存区
	
	存储实体为寄存器组, 位宽 = BUS_WIDTH + BUS_WIDTH/8 + 1, 深度 = 2
	
	写指针[0]是缓存条目索引, 写指针[1]是翻转位
	读指针[1+clogb2(BUS_WIDTH/8-1)]是缓存条目索引, 读指针[2+clogb2(BUS_WIDTH/8-1)]是翻转位, 读指针[clogb2(BUS_WIDTH/8-1):0]是起始字节位置
	**/
	// [存储实体]
	reg[BUS_WIDTH-1:0] bus_data_buf[0:1];
	reg[BUS_WIDTH/8-1:0] bus_keep_flag_buf[0:1];
	reg bus_last_flag_buf[0:1];
	// [写端口]
	reg[1:0] buf_wptr; // 写指针
	wire buf_full; // 满标志
	// [读端口]
	reg[2+clogb2(BUS_WIDTH/8-1):0] buf_rptr; // 读指针
	wire buf_empty; // 空标志
	wire[1+clogb2(BUS_WIDTH/8-1):0] start_byte_id_to_rd_nxt; // 下一待读取的起始字节位置
	wire is_last_in_strm_tsf_flag; // 是否输入流数据包里的最后1次传输(标志)
	
	assign s_axis_ready = aclken & en_in_strm_gen & (~buf_full);
	
	genvar in_strm_item_i;
	generate
		for(in_strm_item_i = 0;in_strm_item_i < ELEMENT_WISE_PROC_PIPELINE_N;in_strm_item_i = in_strm_item_i + 1)
		begin:in_strm_item_blk
			assign m_axis_data[(in_strm_item_i+1)*32-1:in_strm_item_i*32] = 
				(
					bus_data_buf[buf_rptr[1+clogb2(BUS_WIDTH/8-1)]] >> 
					(
						(
							(
								/*
								总线位宽(BUS_WIDTH)能被输入流位宽(ELEMENT_WISE_PROC_PIPELINE_N * 1或2或4)所整除,
								因此起始字节位置必定对齐到输入流位宽
								*/
								buf_rptr[clogb2(BUS_WIDTH/8-1):0] | 
								(
									in_strm_item_i << 
									(
										(in_strm_width_type == IN_STRM_WIDTH_TYPE_1_BYTE) ? 0:
										(in_strm_width_type == IN_STRM_WIDTH_TYPE_2_BYTE) ? 1:
																							2
									)
								)
							) & 
							// 根据输入流项位宽的支持情况, 舍弃总线数据缓存区条目(data)右移字节数的低0~2位
							(
								IN_STRM_WIDTH_1_BYTE_SUPPORTED ? 
									32'hffff_ffff:
									(
										IN_STRM_WIDTH_2_BYTE_SUPPORTED ? 
											32'hffff_fffe:
											32'hffff_fffc
									)
							)
						) * 8
					)
				) & 
				// 取低32位
				(32'hffff_ffff | {BUS_WIDTH{1'b0}});
			
			assign m_axis_keep[(in_strm_item_i+1)*4-1:in_strm_item_i*4] = 
				{4{
					|(
						bus_keep_flag_buf[buf_rptr[1+clogb2(BUS_WIDTH/8-1)]] & 
						(
							1 << (
								(
									/*
									总线位宽(BUS_WIDTH)能被输入流位宽(ELEMENT_WISE_PROC_PIPELINE_N * 1或2或4)所整除,
									因此起始字节位置必定对齐到输入流位宽
									*/
									buf_rptr[clogb2(BUS_WIDTH/8-1):0] | 
									(
										in_strm_item_i << 
										(
											(in_strm_width_type == IN_STRM_WIDTH_TYPE_1_BYTE) ? 0:
											(in_strm_width_type == IN_STRM_WIDTH_TYPE_2_BYTE) ? 1:
																								2
										)
									)
								) & 
								// 根据输入流项位宽的支持情况, 舍弃总线数据缓存区条目(keep掩码)选择位数的低0~2位
								(
									IN_STRM_WIDTH_1_BYTE_SUPPORTED ? 
										32'hffff_ffff:
										(
											IN_STRM_WIDTH_2_BYTE_SUPPORTED ? 
												32'hffff_fffe:
												32'hffff_fffc
										)
								)
							)
						)
					)
				}};
		end
	endgenerate
	
	assign m_axis_last = is_last_in_strm_tsf_flag;
	assign m_axis_valid = aclken & en_in_strm_gen & (~buf_empty);
	
	assign buf_full = 
		(buf_rptr[2+clogb2(BUS_WIDTH/8-1)] ^ buf_wptr[1]) & 
		(~(buf_rptr[1+clogb2(BUS_WIDTH/8-1)] ^ buf_wptr[0]));
	assign buf_empty = 
		(~(buf_rptr[2+clogb2(BUS_WIDTH/8-1)] ^ buf_wptr[1])) & 
		(~(buf_rptr[1+clogb2(BUS_WIDTH/8-1)] ^ buf_wptr[0]));
	
	assign start_byte_id_to_rd_nxt = 
		buf_rptr[clogb2(BUS_WIDTH/8-1):0] + 
		(
			ELEMENT_WISE_PROC_PIPELINE_N << 
			(
				(in_strm_width_type == IN_STRM_WIDTH_TYPE_1_BYTE) ? 0:
				(in_strm_width_type == IN_STRM_WIDTH_TYPE_2_BYTE) ? 1:
				                                                    2
			)
		);
	assign is_last_in_strm_tsf_flag = 
		bus_last_flag_buf[buf_rptr[1+clogb2(BUS_WIDTH/8-1)]] & 
		(~(
			|(
				{{(BUS_WIDTH/8){1'b0}}, bus_keep_flag_buf[buf_rptr[1+clogb2(BUS_WIDTH/8-1)]]} & 
				((1 | {(BUS_WIDTH/8*2){1'b0}}) << start_byte_id_to_rd_nxt)
			)
		));
	
	genvar buf_i;
	generate
		for(buf_i = 0;buf_i < 2;buf_i = buf_i + 1)
		begin:buf_blk
			always @(posedge aclk)
			begin
				if(aclken & s_axis_valid & s_axis_ready & (buf_wptr[0] == buf_i))
				begin
					bus_data_buf[buf_i] <= # SIM_DELAY s_axis_data;
					bus_keep_flag_buf[buf_i] <= # SIM_DELAY s_axis_keep;
					bus_last_flag_buf[buf_i] <= # SIM_DELAY s_axis_last;
				end
			end
		end
	endgenerate
	
	// 写指针
	always @(posedge aclk)
	begin
		if(~en_in_strm_gen)
			buf_wptr <= # SIM_DELAY 2'b00;
		else if(aclken & s_axis_valid & s_axis_ready)
			buf_wptr <= # SIM_DELAY buf_wptr + 1'b1;
	end
	
	// 读指针
	always @(posedge aclk)
	begin
		if(~en_in_strm_gen)
			buf_rptr[2+clogb2(BUS_WIDTH/8-1):1+clogb2(BUS_WIDTH/8-1)] <= # SIM_DELAY 2'b00;
		else if(
			aclken & m_axis_valid & m_axis_ready & 
			(is_last_in_strm_tsf_flag | start_byte_id_to_rd_nxt[1+clogb2(BUS_WIDTH/8-1)])
		)
			buf_rptr[2+clogb2(BUS_WIDTH/8-1):1+clogb2(BUS_WIDTH/8-1)] <= # SIM_DELAY 
				buf_rptr[2+clogb2(BUS_WIDTH/8-1):1+clogb2(BUS_WIDTH/8-1)] + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_in_strm_gen)
			buf_rptr[clogb2(BUS_WIDTH/8-1):0] <= # SIM_DELAY 0;
		else if(aclken & m_axis_valid & m_axis_ready)
			buf_rptr[clogb2(BUS_WIDTH/8-1):0] <= # SIM_DELAY 
				is_last_in_strm_tsf_flag ? 
					0:
					start_byte_id_to_rd_nxt[clogb2(BUS_WIDTH/8-1):0];
	end
	
endmodule
