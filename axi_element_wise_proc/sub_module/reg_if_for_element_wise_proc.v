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
本模块: 通用逐元素操作单元的寄存器配置接口

描述:
寄存器 -> 
	| 寄存器名 | 偏移量  |             含义              |   读写特性   |              备注                |
    --------------------------------------------------------------------------------------------------------
    | version  | 0x00/0  |31~0: 版本号                   |      RO      | 用日期表示的版本号,              |
	|          |         |                               |              | 每4位取值0~9, 小端格式           |
	--------------------------------------------------------------------------------------------------------
	| acc_name | 0x04/1  |29~0: 加速器类型               |      RO      | 用小写字母表示的加速器类型, 每5位|
	|          |         |                               |              | 取值0~26, 小端格式, 26表示'\0'   |
	|          |         |31~30: 加速器ID                |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info0    | 0x08/2  |15~0: MM2S通道DMA数据流的位宽  |      RO      |                                  |
	|          |         |31~16: S2MM通道DMA数据流的位宽 |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info1    | 0x0C/3  |7~0: 逐元素操作处理流水线条数  |      RO      |                                  |
	|          |         |8: 是否支持输入流项位宽为1字节 |      RO      |                                  |
	|          |         |9: 是否支持输入流项位宽为2字节 |      RO      |                                  |
	|          |         |10: 是否支持输入流项位宽为4字节|      RO      |                                  |
	|          |         |11: 是否支持输出流项位宽为1字节|      RO      |                                  |
	|          |         |12: 是否支持输出流项位宽为2字节|      RO      |                                  |
	|          |         |13: 是否支持输出流项位宽为4字节|      RO      |                                  |
	|          |         |14: 是否支持输入FP16转FP32     |      RO      |                                  |
	|          |         |15: 是否支持输入整型转FP32     |      RO      |                                  |
	|          |         |16: 是否支持S16运算数据格式    |      RO      |                                  |
	|          |         |17: 是否支持S32运算数据格式    |      RO      |                                  |
	|          |         |18: 是否支持FP32运算数据格式   |      RO      |                                  |
	|          |         |19: 是否支持输出FP32转S33      |      RO      |                                  |
	|          |         |20: 是否支持S33数据的舍入      |      RO      |                                  |
	|          |         |21: 是否支持FP32舍入为FP16     |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	| ctrl0    | 0x40/16 |0: 使能加速器                  |      RW      |                                  |
	|          |         |1: 使能数据枢纽                |      RW      |                                  |
	|          |         |2: 使能处理核心                |      RW      |                                  |
	|          |         |3: 使能运行周期数计数器        |      RW      | 仅当支持性能监测时写1生效        |
	--------------------------------------------------------------------------------------------------------
	| ctrl1    | 0x44/17 |0: 发送0号MM2S通道的DMA命令    |      RW      | 写1发送命令, 读该位时得到等待标志|
	|          |         |1: 发送1号MM2S通道的DMA命令    |      RW      | 写1发送命令, 读该位时得到等待标志|
	|          |         |2: 发送S2MM通道的DMA命令       |      RW      | 写1发送命令, 读该位时得到等待标志|
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	| sts0     | 0x60/24 |31~0: 0号MM2S通道完成的命令数  |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts1     | 0x64/25 |31~0: 1号MM2S通道完成的命令数  |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts2     | 0x68/26 |31~0: S2MM通道完成的命令数     |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts3     | 0x6C/27 |31~0: 运行周期数               |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	| buf_cfg0 | 0x80/32 |31~0: 操作数X缓存区基地址      |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg1 | 0x84/33 |31~0: 操作数A或B缓存区基地址   |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg2 | 0x88/34 |31~0: 结果缓存区基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg3 | 0x8C/35 |23~0: 操作数X缓存区大小        |      RW      | 以字节计                         |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg4 | 0x90/36 |23~0: 操作数A或B缓存区大小     |      RW      | 以字节计                         |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg5 | 0x94/37 |23~0: 结果缓存区大小           |      RW      | 以字节计                         |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	| fmt_cfg  | 0xC0/48 |2~0: 输入数据格式              |      RW      |                                  |
	|          |         |9~8: 计算数据格式              |      RW      | 仅当写入支持的运算数据格式时生效 |
	|          |         |18~16: 输出数据格式            |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fixed_    | 0xC4/49 |5~0: 输入定点数量化精度        |      RW      |仅在支持输入整型转FP32时可用      |
	|point_cfg0|         |12~8: 操作数X的定点数量化精度  |      RW      |仅在支持S16或S32运算数据格式时可用|
	|          |         |20~16: 操作数A的定点数量化精度 |      RW      |仅在支持S16或S32运算数据格式时可用|
	|          |         |29~24: 转换为S33输出数据的     |      RW      |仅在支持输出FP32转S33时可用       |
	|          |         |       定点数量化精度          |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|fixed_    | 0xC8/50 |4~0: 舍入单元输入定点数量化精度|      RW      |仅在支持S33数据的舍入时可用       |
	|point_cfg1|         |12~8: 舍入单元输出             |      RW      |仅在支持S33数据的舍入时可用       |
	|          |         |      定点数量化精度           |              |                                  |
	|          |         |20~16: 定点数舍入位数          |      RW      |仅在支持S33数据的舍入时可用       |
	--------------------------------------------------------------------------------------------------------
	| op_a_b_  | 0xCC/51 |0: 操作数A的实际值恒为1        |      RW      |                                  |
	| cfg0     |         |1: 操作数B的实际值恒为0        |      RW      |                                  |
	|          |         |8: 操作数A为常量               |      RW      |                                  |
	|          |         |9: 操作数B为常量               |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	| op_a_b_  | 0xD0/52 |31~0: 操作数A的常量值          |      RW      |                                  |
	| cfg1     |         |                               |              |                                  |
	--------------------------------------------------------------------------------------------------------
	| op_a_b_  | 0xD4/53 |31~0: 操作数B的常量值          |      RW      |                                  |
	| cfg2     |         |                               |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|fu_bypass_| 0xD8/54 |0: 旁路输入数据转换单元        |      RW      |仅在启用输入数据转换单元时写0生效 |
	|cfg       |         |1: 旁路二次幂计算单元          |      RW      |仅在启用二次幂计算单元时写0生效   |
	|          |         |2: 旁路乘加计算单元            |      RW      |仅在启用乘加计算单元时写0生效     |
	|          |         |3: 旁路输出数据转换单元        |      RW      |仅在启用输出数据转换单元时写0生效 |
	|          |         |4: 旁路舍入单元                |      RW      |仅在启用舍入单元时写0生效         |
	--------------------------------------------------------------------------------------------------------

注意：
无

协议:
AXI-Lite SLAVE

作者: 陈家耀
日期: 2026/01/15
********************************************************************/


module reg_if_for_element_wise_proc #(
	// 逐元素操作处理全局配置
	parameter integer ACCELERATOR_ID = 0, // 加速器ID(0~3)
	parameter integer MM2S_STREAM_DATA_WIDTH = 64, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer ELEMENT_WISE_PROC_PIPELINE_N = 4, // 逐元素操作处理流水线条数(1 | 2 | 4 | 8 | 16 | 32)
	// 输入与输出项字节数配置
	parameter IN_STRM_WIDTH_1_BYTE_SUPPORTED = 1'b1, // 是否支持输入流项位宽为1字节
	parameter IN_STRM_WIDTH_2_BYTE_SUPPORTED = 1'b1, // 是否支持输入流项位宽为2字节
	parameter IN_STRM_WIDTH_4_BYTE_SUPPORTED = 1'b1, // 是否支持输入流项位宽为4字节
	parameter OUT_STRM_WIDTH_1_BYTE_SUPPORTED = 1'b1, // 是否支持输出流项位宽为1字节
	parameter OUT_STRM_WIDTH_2_BYTE_SUPPORTED = 1'b1, // 是否支持输出流项位宽为2字节
	parameter OUT_STRM_WIDTH_4_BYTE_SUPPORTED = 1'b1, // 是否支持输出流项位宽为4字节
	// 输入数据转换单元配置
	parameter EN_IN_DATA_CVT = 1'b1, // 启用输入数据转换单元
	parameter IN_DATA_CVT_FP16_IN_DATA_SUPPORTED = 1'b0, // 是否支持FP16输入数据格式
	parameter IN_DATA_CVT_S33_IN_DATA_SUPPORTED = 1'b1, // 是否支持S33输入数据格式
	// 计算单元配置
	parameter EN_POW2_CAL_UNIT = 1'b1, // 启用二次幂计算单元
	parameter EN_MAC_UNIT = 1'b1, // 启用乘加计算单元
	parameter CAL_INT16_SUPPORTED = 1'b0, // 是否支持INT16运算数据格式
	parameter CAL_INT32_SUPPORTED = 1'b0, // 是否支持INT32运算数据格式
	parameter CAL_FP32_SUPPORTED = 1'b1, // 是否支持FP32运算数据格式
	// 输出数据转换单元配置
	parameter EN_OUT_DATA_CVT = 1'b1, // 启用输出数据转换单元
	parameter OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED = 1'b1, // 是否支持S33输出数据格式
	// 舍入单元配置
	parameter EN_ROUND_UNIT = 1'b1, // 启用舍入单元
	parameter ROUND_S33_ROUND_SUPPORTED = 1'b1, // 是否支持S33数据的舍入
	parameter ROUND_FP32_ROUND_SUPPORTED = 1'b1, // 是否支持FP32数据的舍入
	// 性能监测
	parameter EN_PERF_MON = 1'b1, // 是否支持性能监测
	// 仿真配置
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire aclk,
    input wire aresetn,
	
	// 寄存器配置接口(AXI-Lite从机)
    // 读地址通道
    input wire[31:0] s_axi_lite_araddr,
    input wire s_axi_lite_arvalid,
    output wire s_axi_lite_arready,
    // 写地址通道
    input wire[31:0] s_axi_lite_awaddr,
    input wire s_axi_lite_awvalid,
    output wire s_axi_lite_awready,
    // 写响应通道
    output wire[1:0] s_axi_lite_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_bvalid,
    input wire s_axi_lite_bready,
    // 读数据通道
    output wire[31:0] s_axi_lite_rdata,
    output wire[1:0] s_axi_lite_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_rvalid,
    input wire s_axi_lite_rready,
    // 写数据通道
    input wire[31:0] s_axi_lite_wdata,
    input wire s_axi_lite_wvalid,
    output wire s_axi_lite_wready,
	
	// 控制/状态
	output wire en_accelerator, // 使能加速器
	output wire en_data_hub, // 使能数据枢纽
	output wire en_proc_core, // 使能处理核心
	output wire on_send_mm2s_0_cmd, // 发送0号MM2S通道的DMA命令
	output wire on_send_mm2s_1_cmd, // 发送1号MM2S通道的DMA命令
	output wire on_send_s2mm_cmd, // 发送S2MM通道的DMA命令
	input wire mm2s_0_cmd_pending, // 等待0号MM2S通道的DMA命令传输完成(标志)
	input wire mm2s_1_cmd_pending, // 等待1号MM2S通道的DMA命令传输完成(标志)
	input wire s2mm_cmd_pending, // 等待S2MM通道的DMA命令传输完成(标志)
	
	// DMA命令完成指示
	input wire mm2s_0_cmd_done, // 0号MM2S通道命令完成(指示)
	input wire mm2s_1_cmd_done, // 1号MM2S通道命令完成(指示)
	input wire s2mm_cmd_done, // S2MM通道命令完成(指示)
	
	// 运行时参数
	// [执行单元旁路]
	output wire in_data_cvt_unit_bypass, // 旁路输入数据转换单元
	output wire pow2_cell_bypass, // 旁路二次幂计算单元
	output wire mac_cell_bypass, // 旁路乘加计算单元
	output wire out_data_cvt_unit_bypass, // 旁路输出数据转换单元
	output wire round_cell_bypass, // 旁路舍入单元
	// [缓存区基地址与大小]
	output wire[31:0] op_x_buf_baseaddr, // 操作数X缓存区基地址
	output wire[23:0] op_x_buf_len, // 操作数X缓存区大小
	output wire[31:0] op_a_b_buf_baseaddr, // 操作数A或B缓存区基地址
	output wire[23:0] op_a_b_buf_len, // 操作数A或B缓存区大小
	output wire[31:0] res_buf_baseaddr, // 结果缓存区基地址
	output wire[23:0] res_buf_len, // 结果缓存区大小
	// [数据格式]
	output wire[2:0] in_data_fmt, // 输入数据格式
	output wire[1:0] cal_calfmt, // 计算数据格式
	output wire[2:0] out_data_fmt, // 输出数据格式
	// [定点数量化精度]
	output wire[5:0] in_fixed_point_quat_accrc, // 输入定点数量化精度
	output wire[4:0] op_x_fixed_point_quat_accrc, // 操作数X的定点数量化精度
	output wire[4:0] op_a_fixed_point_quat_accrc, // 操作数A的定点数量化精度
	output wire[5:0] s33_cvt_fixed_point_quat_accrc, // 转换为S33输出数据的定点数量化精度
	output wire[4:0] round_in_fixed_point_quat_accrc, // 舍入单元输入定点数量化精度
	output wire[4:0] round_out_fixed_point_quat_accrc, // 舍入单元输出定点数量化精度
	output wire[4:0] fixed_point_rounding_digits, // 定点数舍入位数
	// [操作数A或B]
	output wire is_op_a_eq_1, // 操作数A的实际值恒为1(标志)
	output wire is_op_b_eq_0, // 操作数B的实际值恒为0(标志)
	output wire is_op_a_const, // 操作数A为常量(标志)
	output wire is_op_b_const, // 操作数B为常量(标志)
	output wire[31:0] op_a_const_val, // 操作数A的常量值
	output wire[31:0] op_b_const_val // 操作数B的常量值
);
	
	/** 常量 **/
	// 运算数据格式的编码
	localparam CAL_FMT_INT16 = 2'b00;
	localparam CAL_FMT_INT32 = 2'b01;
	localparam CAL_FMT_FP32 = 2'b10;
	localparam CAL_FMT_NONE = 2'b11;
	
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
	
	/** 内部配置 **/
	localparam integer REGS_N = 128; // 寄存器总数
	
	/** 常量 **/
	// 寄存器配置状态独热码编号
	localparam integer REG_CFG_STS_ADDR = 0; // 状态:地址阶段
	localparam integer REG_CFG_STS_RW_REG = 1; // 状态:读/写寄存器
	localparam integer REG_CFG_STS_RW_RESP = 2; // 状态:读/写响应
	
	/** 寄存器配置控制 **/
	reg[2:0] reg_cfg_sts; // 寄存器配置状态
	wire[1:0] rw_grant; // 读写许可({写许可, 读许可})
	reg[1:0] addr_ready; // 地址通道的ready信号({aw_ready, ar_ready})
	reg is_write; // 是否写寄存器
	reg[clogb2(REGS_N-1):0] ofs_addr; // 读写寄存器的偏移地址
	reg wready; // 写数据通道的ready信号
	reg bvalid; // 写响应通道的valid信号
	reg rvalid; // 读数据通道的valid信号
	wire regs_en; // 寄存器访问使能
	wire regs_wen; // 寄存器写使能
	wire[clogb2(REGS_N-1):0] regs_addr; // 寄存器访问地址
	wire[31:0] regs_din; // 寄存器写数据
	reg[31:0] regs_dout; // 寄存器读数据
	
	assign {s_axi_lite_awready, s_axi_lite_arready} = addr_ready;
	assign s_axi_lite_bresp = 2'b00;
	assign s_axi_lite_bvalid = bvalid;
	assign s_axi_lite_rdata = regs_dout;
	assign s_axi_lite_rresp = 2'b00;
	assign s_axi_lite_rvalid = rvalid;
	assign s_axi_lite_wready = wready;
	
	assign rw_grant = {s_axi_lite_awvalid, (~s_axi_lite_awvalid) & s_axi_lite_arvalid}; // 写优先
	
	assign regs_en = reg_cfg_sts[REG_CFG_STS_RW_REG] & ((~is_write) | s_axi_lite_wvalid);
	assign regs_wen = is_write;
	assign regs_addr = ofs_addr;
	assign regs_din = s_axi_lite_wdata;
	
	// 寄存器配置状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			reg_cfg_sts <= 3'b001;
		else if((reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid)) | 
			(reg_cfg_sts[REG_CFG_STS_RW_REG] & ((~is_write) | s_axi_lite_wvalid)) | 
			(reg_cfg_sts[REG_CFG_STS_RW_RESP] & (is_write ? s_axi_lite_bready:s_axi_lite_rready)))
			reg_cfg_sts <= # SIM_DELAY {reg_cfg_sts[1:0], reg_cfg_sts[2]};
	end
	
	// 地址通道的ready信号
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			addr_ready <= 2'b00;
		else
			addr_ready <= # SIM_DELAY {2{reg_cfg_sts[REG_CFG_STS_ADDR]}} & rw_grant;
	end
	
	// 是否写寄存器
	always @(posedge aclk)
	begin
		if(reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid))
			is_write <= # SIM_DELAY s_axi_lite_awvalid;
	end
	
	// 读写寄存器的偏移地址
	always @(posedge aclk)
	begin
		if(reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid))
			ofs_addr <= # SIM_DELAY s_axi_lite_awvalid ? 
				s_axi_lite_awaddr[2+clogb2(REGS_N-1):2]:s_axi_lite_araddr[2+clogb2(REGS_N-1):2];
	end
	
	// 写数据通道的ready信号
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wready <= 1'b0;
		else
			wready <= # SIM_DELAY wready ? 
				(~s_axi_lite_wvalid):(reg_cfg_sts[REG_CFG_STS_ADDR] & s_axi_lite_awvalid);
	end
	
	// 写响应通道的valid信号
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			bvalid <= 1'b0;
		else
			bvalid <= # SIM_DELAY bvalid ? 
				(~s_axi_lite_bready):(s_axi_lite_wvalid & s_axi_lite_wready);
	end
	
	// 读数据通道的valid信号
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rvalid <= 1'b0;
		else
			rvalid <= # SIM_DELAY rvalid ? 
				(~s_axi_lite_rready):(reg_cfg_sts[REG_CFG_STS_RW_REG] & (~is_write));
	end
	
	/**
	寄存器(version, acc_name, info0, info1)
	
	--------------------------------------------------------------------------------------------------------
    | version  | 0x00/0  |31~0: 版本号                   |      RO      | 用日期表示的版本号,              |
	|          |         |                               |              | 每4位取值0~9, 小端格式           |
	--------------------------------------------------------------------------------------------------------
	| acc_name | 0x04/1  |29~0: 加速器类型               |      RO      | 用小写字母表示的加速器类型, 每5位|
	|          |         |                               |              | 取值0~26, 小端格式, 26表示'\0'   |
	|          |         |31~30: 加速器ID                |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info0    | 0x08/2  |15~0: MM2S通道DMA数据流的位宽  |      RO      |                                  |
	|          |         |31~16: S2MM通道DMA数据流的位宽 |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info1    | 0x0C/3  |7~0: 逐元素操作处理流水线条数  |      RO      |                                  |
	|          |         |8: 是否支持输入流项位宽为1字节 |      RO      |                                  |
	|          |         |9: 是否支持输入流项位宽为2字节 |      RO      |                                  |
	|          |         |10: 是否支持输入流项位宽为4字节|      RO      |                                  |
	|          |         |11: 是否支持输出流项位宽为1字节|      RO      |                                  |
	|          |         |12: 是否支持输出流项位宽为2字节|      RO      |                                  |
	|          |         |13: 是否支持输出流项位宽为4字节|      RO      |                                  |
	|          |         |14: 是否支持输入FP16转FP32     |      RO      |                                  |
	|          |         |15: 是否支持输入整型转FP32     |      RO      |                                  |
	|          |         |16: 是否支持S16运算数据格式    |      RO      |                                  |
	|          |         |17: 是否支持S32运算数据格式    |      RO      |                                  |
	|          |         |18: 是否支持FP32运算数据格式   |      RO      |                                  |
	|          |         |19: 是否支持输出FP32转S33      |      RO      |                                  |
	|          |         |20: 是否支持S33数据的舍入      |      RO      |                                  |
	|          |         |21: 是否支持FP32舍入为FP16     |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	**/
	wire[31:0] version_r; // 版本号
	wire[29:0] acc_type_r; // 加速器类型
	wire[1:0] acc_id_r; // 加速器ID
	wire[15:0] mm2s_stream_data_width_r; // MM2S通道DMA数据流的位宽
	wire[15:0] s2mm_stream_data_width_r; // S2MM通道DMA数据流的位宽
	wire[7:0] element_wise_proc_pipeline_n_r; // 逐元素操作处理流水线条数
	wire in_stream_width_1_byte_supported_r; // 是否支持输入流项位宽为1字节
	wire in_stream_width_2_byte_supported_r; // 是否支持输入流项位宽为2字节
	wire in_stream_width_4_byte_supported_r; // 是否支持输入流项位宽为4字节
	wire out_stream_width_1_byte_supported_r; // 是否支持输出流项位宽为1字节
	wire out_stream_width_2_byte_supported_r; // 是否支持输出流项位宽为2字节
	wire out_stream_width_4_byte_supported_r; // 是否支持输出流项位宽为4字节
	wire in_data_cvt_fp16_to_fp32_supported_r; // 是否支持输入FP16转FP32
	wire in_data_cvt_int_to_fp32_supported_r; // 是否支持输入整型转FP32
	wire cal_s16_supported_r; // 是否支持S16运算数据格式
	wire cal_s32_supported_r; // 是否支持S32运算数据格式
	wire cal_fp32_supported_r; // 是否支持FP32运算数据格式
	wire out_data_cvt_fp32_to_s33_supported_r; // 是否支持输出FP32转S33
	wire s33_round_supported_r; // 是否支持S33数据的舍入
	wire fp32_to_fp16_round_supported_r; // 是否支持FP32舍入为FP16
	
	assign version_r = {4'd5, 4'd1, 4'd1, 4'd0, 4'd6, 4'd2, 4'd0, 4'd2}; // 2026.01.15
	assign acc_type_r = {5'd26, 5'd26, 5'd22, 5'd12, 5'd11, 5'd4}; // "elmw\0\0"
	assign acc_id_r = ACCELERATOR_ID;
	
	assign mm2s_stream_data_width_r = MM2S_STREAM_DATA_WIDTH;
	assign s2mm_stream_data_width_r = S2MM_STREAM_DATA_WIDTH;
	
	assign element_wise_proc_pipeline_n_r = ELEMENT_WISE_PROC_PIPELINE_N;
	assign in_stream_width_1_byte_supported_r = IN_STRM_WIDTH_1_BYTE_SUPPORTED;
	assign in_stream_width_2_byte_supported_r = IN_STRM_WIDTH_2_BYTE_SUPPORTED;
	assign in_stream_width_4_byte_supported_r = IN_STRM_WIDTH_4_BYTE_SUPPORTED;
	assign out_stream_width_1_byte_supported_r = OUT_STRM_WIDTH_1_BYTE_SUPPORTED;
	assign out_stream_width_2_byte_supported_r = OUT_STRM_WIDTH_2_BYTE_SUPPORTED;
	assign out_stream_width_4_byte_supported_r = OUT_STRM_WIDTH_4_BYTE_SUPPORTED;
	assign in_data_cvt_fp16_to_fp32_supported_r = EN_IN_DATA_CVT & IN_DATA_CVT_FP16_IN_DATA_SUPPORTED;
	assign in_data_cvt_int_to_fp32_supported_r = EN_IN_DATA_CVT & IN_DATA_CVT_S33_IN_DATA_SUPPORTED;
	assign cal_s16_supported_r = CAL_INT16_SUPPORTED;
	assign cal_s32_supported_r = CAL_INT32_SUPPORTED;
	assign cal_fp32_supported_r = CAL_FP32_SUPPORTED;
	assign out_data_cvt_fp32_to_s33_supported_r = EN_OUT_DATA_CVT & OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED;
	assign s33_round_supported_r = EN_ROUND_UNIT & ROUND_S33_ROUND_SUPPORTED;
	assign fp32_to_fp16_round_supported_r = EN_ROUND_UNIT & ROUND_FP32_ROUND_SUPPORTED;
	
	/**
	寄存器(ctrl0, ctrl1)
	
	--------------------------------------------------------------------------------------------------------
	| ctrl0    | 0x40/16 |0: 使能加速器                  |      RW      |                                  |
	|          |         |1: 使能数据枢纽                |      RW      |                                  |
	|          |         |2: 使能处理核心                |      RW      |                                  |
	|          |         |3: 使能运行周期数计数器        |      RW      | 仅当支持性能监测时写1生效        |
	--------------------------------------------------------------------------------------------------------
	| ctrl1    | 0x44/17 |0: 发送0号MM2S通道的DMA命令    |      RW      | 写1发送命令, 读该位时得到等待标志|
	|          |         |1: 发送1号MM2S通道的DMA命令    |      RW      | 写1发送命令, 读该位时得到等待标志|
	|          |         |2: 发送S2MM通道的DMA命令       |      RW      | 写1发送命令, 读该位时得到等待标志|
	--------------------------------------------------------------------------------------------------------
	**/
	reg en_accelerator_r; // 使能加速器
	reg en_data_hub_r; // 使能数据枢纽
	reg en_proc_core_r; // 使能处理核心
	reg en_cycle_n_cnt_r; // 使能运行周期数计数器
	reg on_send_mm2s_0_cmd_r; // 发送0号MM2S通道的DMA命令(指示)
	reg on_send_mm2s_1_cmd_r; // 发送1号MM2S通道的DMA命令(指示)
	reg on_send_s2mm_cmd_r; // 发送S2MM通道的DMA命令(指示)
	wire mm2s_0_cmd_pending_r; // 等待0号MM2S通道的DMA命令传输完成(标志)
	wire mm2s_1_cmd_pending_r; // 等待1号MM2S通道的DMA命令传输完成(标志)
	wire s2mm_cmd_pending_r; // 等待S2MM通道的DMA命令传输完成(标志)
	
	assign en_accelerator = en_accelerator_r;
	assign en_data_hub = en_data_hub_r;
	assign en_proc_core = en_proc_core_r;
	assign on_send_mm2s_0_cmd = on_send_mm2s_0_cmd_r;
	assign on_send_mm2s_1_cmd = on_send_mm2s_1_cmd_r;
	assign on_send_s2mm_cmd = on_send_s2mm_cmd_r;
	assign mm2s_0_cmd_pending_r = mm2s_0_cmd_pending;
	assign mm2s_1_cmd_pending_r = mm2s_1_cmd_pending;
	assign s2mm_cmd_pending_r = s2mm_cmd_pending;
	
	// 使能加速器, 使能数据枢纽, 使能处理核心, 使能运行周期数计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{en_cycle_n_cnt_r, en_proc_core_r, en_data_hub_r, en_accelerator_r} <= 4'b0000;
		else if(regs_en & regs_wen & (regs_addr == 16))
			{en_cycle_n_cnt_r, en_proc_core_r, en_data_hub_r, en_accelerator_r} <= # SIM_DELAY 
				{EN_PERF_MON, 3'b111} & regs_din[3:0];
	end
	
	// 发送0号MM2S通道的DMA命令(指示), 发送1号MM2S通道的DMA命令(指示), 发送S2MM通道的DMA命令(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{on_send_s2mm_cmd_r, on_send_mm2s_1_cmd_r, on_send_mm2s_0_cmd_r} <= 3'b000;
		else
			{on_send_s2mm_cmd_r, on_send_mm2s_1_cmd_r, on_send_mm2s_0_cmd_r} <= # SIM_DELAY 
				{3{regs_en & regs_wen & (regs_addr == 17)}} & regs_din[2:0];
	end
	
	/**
	寄存器(sts0, sts1, sts2, sts3)
	
	--------------------------------------------------------------------------------------------------------
	| sts0     | 0x60/24 |31~0: 0号MM2S通道完成的命令数  |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts1     | 0x64/25 |31~0: 1号MM2S通道完成的命令数  |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts2     | 0x68/26 |31~0: S2MM通道完成的命令数     |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts3     | 0x6C/27 |31~0: 运行周期数               |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	**/
	reg[31:0] dma_mm2s_0_fns_cmd_n_r; // 0号MM2S通道完成的命令数
	reg[31:0] dma_mm2s_1_fns_cmd_n_r; // 1号MM2S通道完成的命令数
	reg[31:0] dma_s2mm_fns_cmd_n_r; // S2MM通道完成的命令数
	reg[31:0] cycle_n_cnt_r; // 运行周期数计数器
	
	// 0号MM2S通道完成的命令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dma_mm2s_0_fns_cmd_n_r <= 32'd0;
		else if(
			(en_accelerator_r & mm2s_0_cmd_done) | 
			(regs_en & regs_wen & (regs_addr == 24))
		)
			dma_mm2s_0_fns_cmd_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 24)) ? 
					32'd0:
					(dma_mm2s_0_fns_cmd_n_r + 1'b1);
	end
	
	// 1号MM2S通道完成的命令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dma_mm2s_1_fns_cmd_n_r <= 32'd0;
		else if(
			(en_accelerator_r & mm2s_1_cmd_done) | 
			(regs_en & regs_wen & (regs_addr == 25))
		)
			dma_mm2s_1_fns_cmd_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 25)) ? 
					32'd0:
					(dma_mm2s_1_fns_cmd_n_r + 1'b1);
	end
	
	// S2MM通道完成的命令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dma_s2mm_fns_cmd_n_r <= 32'd0;
		else if(
			(en_accelerator_r & s2mm_cmd_done) | 
			(regs_en & regs_wen & (regs_addr == 26))
		)
			dma_s2mm_fns_cmd_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 26)) ? 
					32'd0:
					(dma_s2mm_fns_cmd_n_r + 1'b1);
	end
	
	// 运行周期数计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cycle_n_cnt_r <= 32'd0;
		else if(
			EN_PERF_MON & 
			(
				(en_accelerator_r & en_cycle_n_cnt_r) | 
				(regs_en & regs_wen & (regs_addr == 27))
			)
		)
			cycle_n_cnt_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 27)) ? 
					32'd0:
					(cycle_n_cnt_r + 1'b1);
	end
	
	/**
	寄存器(buf_cfg0, buf_cfg1, buf_cfg2, buf_cfg3, buf_cfg4, buf_cfg5)
	
	--------------------------------------------------------------------------------------------------------
	| buf_cfg0 | 0x80/32 |31~0: 操作数X缓存区基地址      |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg1 | 0x84/33 |31~0: 操作数A或B缓存区基地址   |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg2 | 0x88/34 |31~0: 结果缓存区基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg3 | 0x8C/35 |23~0: 操作数X缓存区大小        |      RW      | 以字节计                         |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg4 | 0x90/36 |23~0: 操作数A或B缓存区大小     |      RW      | 以字节计                         |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg5 | 0x94/37 |23~0: 结果缓存区大小           |      RW      | 以字节计                         |
	--------------------------------------------------------------------------------------------------------
	**/
	reg[31:0] op_x_buf_baseaddr_r; // 操作数X缓存区基地址
	reg[31:0] op_a_b_buf_baseaddr_r; // 操作数A或B缓存区基地址
	reg[31:0] res_buf_baseaddr_r; // 结果缓存区基地址
	reg[23:0] op_x_buf_len_r; // 操作数X缓存区大小
	reg[23:0] op_a_b_buf_len_r; // 操作数A或B缓存区大小
	reg[23:0] res_buf_len_r; // 结果缓存区大小
	
	assign op_x_buf_baseaddr = op_x_buf_baseaddr_r;
	assign op_x_buf_len = op_x_buf_len_r;
	assign op_a_b_buf_baseaddr = op_a_b_buf_baseaddr_r;
	assign op_a_b_buf_len = op_a_b_buf_len_r;
	assign res_buf_baseaddr = res_buf_baseaddr_r;
	assign res_buf_len = res_buf_len_r;
	
	// 操作数X缓存区基地址
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 32))
			op_x_buf_baseaddr_r <= # SIM_DELAY regs_din[31:0];
	end
	// 操作数A或B缓存区基地址
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 33))
			op_a_b_buf_baseaddr_r <= # SIM_DELAY regs_din[31:0];
	end
	// 结果缓存区基地址
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 34))
			res_buf_baseaddr_r <= # SIM_DELAY regs_din[31:0];
	end
	// 操作数X缓存区大小
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 35))
			op_x_buf_len_r <= # SIM_DELAY regs_din[23:0];
	end
	// 操作数A或B缓存区大小
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 36))
			op_a_b_buf_len_r <= # SIM_DELAY regs_din[23:0];
	end
	// 结果缓存区大小
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 37))
			res_buf_len_r <= # SIM_DELAY regs_din[23:0];
	end
	
	/**
	寄存器(fmt_cfg, fixed_point_cfg0, fixed_point_cfg1, op_a_b_cfg0, op_a_b_cfg1, op_a_b_cfg2, fu_bypass_cfg)
	
	--------------------------------------------------------------------------------------------------------
	| fmt_cfg  | 0xC0/48 |2~0: 输入数据格式              |      RW      |                                  |
	|          |         |9~8: 计算数据格式              |      RW      | 仅当写入支持的运算数据格式时生效 |
	|          |         |18~16: 输出数据格式            |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fixed_    | 0xC4/49 |5~0: 输入定点数量化精度        |      RW      |仅在支持输入整型转FP32时可用      |
	|point_cfg0|         |12~8: 操作数X的定点数量化精度  |      RW      |仅在支持S16或S32运算数据格式时可用|
	|          |         |20~16: 操作数A的定点数量化精度 |      RW      |仅在支持S16或S32运算数据格式时可用|
	|          |         |29~24: 转换为S33输出数据的     |      RW      |仅在支持输出FP32转S33时可用       |
	|          |         |       定点数量化精度          |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|fixed_    | 0xC8/50 |4~0: 舍入单元输入定点数量化精度|      RW      |仅在支持S33数据的舍入时可用       |
	|point_cfg1|         |12~8: 舍入单元输出             |      RW      |仅在支持S33数据的舍入时可用       |
	|          |         |      定点数量化精度           |              |                                  |
	|          |         |20~16: 定点数舍入位数          |      RW      |仅在支持S33数据的舍入时可用       |
	--------------------------------------------------------------------------------------------------------
	| op_a_b_  | 0xCC/51 |0: 操作数A的实际值恒为1        |      RW      |                                  |
	| cfg0     |         |1: 操作数B的实际值恒为0        |      RW      |                                  |
	|          |         |8: 操作数A为常量               |      RW      |                                  |
	|          |         |9: 操作数B为常量               |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	| op_a_b_  | 0xD0/52 |31~0: 操作数A的常量值          |      RW      |                                  |
	| cfg1     |         |                               |              |                                  |
	--------------------------------------------------------------------------------------------------------
	| op_a_b_  | 0xD4/53 |31~0: 操作数B的常量值          |      RW      |                                  |
	| cfg2     |         |                               |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|fu_bypass_| 0xD8/54 |0: 旁路输入数据转换单元        |      RW      |仅在启用输入数据转换单元时写0生效 |
	|cfg       |         |1: 旁路二次幂计算单元          |      RW      |仅在启用二次幂计算单元时写0生效   |
	|          |         |2: 旁路乘加计算单元            |      RW      |仅在启用乘加计算单元时写0生效     |
	|          |         |3: 旁路输出数据转换单元        |      RW      |仅在启用输出数据转换单元时写0生效 |
	|          |         |4: 旁路舍入单元                |      RW      |仅在启用舍入单元时写0生效         |
	--------------------------------------------------------------------------------------------------------
	**/
	// 数据格式
	reg[2:0] in_data_fmt_r; // 输入数据格式
	reg[1:0] cal_calfmt_r; // 计算数据格式
	reg[2:0] out_data_fmt_r; // 输出数据格式
	// 定点数量化精度
	reg[5:0] in_fixed_point_quat_accrc_r; // 输入定点数量化精度
	reg[4:0] op_x_fixed_point_quat_accrc_r; // 操作数X的定点数量化精度
	reg[4:0] op_a_fixed_point_quat_accrc_r; // 操作数A的定点数量化精度
	reg[5:0] s33_cvt_fixed_point_quat_accrc_r; // 转换为S33输出数据的定点数量化精度
	reg[4:0] round_in_fixed_point_quat_accrc_r; // 舍入单元输入定点数量化精度
	reg[4:0] round_out_fixed_point_quat_accrc_r; // 舍入单元输出定点数量化精度
	reg[4:0] fixed_point_rounding_digits_r; // 定点数舍入位数
	// 操作数A或B
	reg is_op_a_eq_1_r; // 操作数A的实际值恒为1(标志)
	reg is_op_b_eq_0_r; // 操作数B的实际值恒为0(标志)
	reg is_op_a_const_r; // 操作数A为常量(标志)
	reg is_op_b_const_r; // 操作数B为常量(标志)
	reg[31:0] op_a_const_val_r; // 操作数A的常量值
	reg[31:0] op_b_const_val_r; // 操作数B的常量值
	// 执行单元旁路
	reg in_data_cvt_unit_bypass_r; // 旁路输入数据转换单元
	reg pow2_cell_bypass_r; // 旁路二次幂计算单元
	reg mac_cell_bypass_r; // 旁路乘加计算单元
	reg out_data_cvt_unit_bypass_r; // 旁路输出数据转换单元
	reg round_cell_bypass_r; // 旁路舍入单元
	
	assign in_data_fmt = in_data_fmt_r;
	assign cal_calfmt = cal_calfmt_r;
	assign out_data_fmt = out_data_fmt_r;
	
	assign in_fixed_point_quat_accrc = in_fixed_point_quat_accrc_r;
	assign op_x_fixed_point_quat_accrc = op_x_fixed_point_quat_accrc_r;
	assign op_a_fixed_point_quat_accrc = op_a_fixed_point_quat_accrc_r;
	assign s33_cvt_fixed_point_quat_accrc = s33_cvt_fixed_point_quat_accrc_r;
	assign round_in_fixed_point_quat_accrc = round_in_fixed_point_quat_accrc_r;
	assign round_out_fixed_point_quat_accrc = round_out_fixed_point_quat_accrc_r;
	assign fixed_point_rounding_digits = fixed_point_rounding_digits_r;
	
	assign is_op_a_eq_1 = is_op_a_eq_1_r;
	assign is_op_b_eq_0 = is_op_b_eq_0_r;
	assign is_op_a_const = is_op_a_const_r;
	assign is_op_b_const = is_op_b_const_r;
	assign op_a_const_val = op_a_const_val_r;
	assign op_b_const_val = op_b_const_val_r;
	
	assign in_data_cvt_unit_bypass = in_data_cvt_unit_bypass_r;
	assign pow2_cell_bypass = pow2_cell_bypass_r;
	assign mac_cell_bypass = mac_cell_bypass_r;
	assign out_data_cvt_unit_bypass = out_data_cvt_unit_bypass_r;
	assign round_cell_bypass = round_cell_bypass_r;
	
	// 输入数据格式
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 48))
			in_data_fmt_r <= # SIM_DELAY regs_din[2:0];
	end
	// 计算数据格式
	always @(posedge aclk)
	begin
		if(
			regs_en & regs_wen & (regs_addr == 48) & 
			(
				(CAL_INT16_SUPPORTED & (regs_din[9:8] == CAL_FMT_INT16)) | 
				(CAL_INT32_SUPPORTED & (regs_din[9:8] == CAL_FMT_INT32)) | 
				(CAL_FP32_SUPPORTED & (regs_din[9:8] == CAL_FMT_FP32))
			)
		)
			cal_calfmt_r <= # SIM_DELAY regs_din[9:8];
	end
	// 输出数据格式
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 48))
			out_data_fmt_r <= # SIM_DELAY regs_din[18:16];
	end
	
	// 转换为S33输出数据的定点数量化精度
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 49) & OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED)
			s33_cvt_fixed_point_quat_accrc_r <= # SIM_DELAY regs_din[29:24];
	end
	// 操作数A的定点数量化精度
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 49) & (CAL_INT16_SUPPORTED | CAL_INT32_SUPPORTED))
			op_a_fixed_point_quat_accrc_r <= # SIM_DELAY regs_din[20:16];
	end
	// 操作数X的定点数量化精度
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 49) & (CAL_INT16_SUPPORTED | CAL_INT32_SUPPORTED))
			op_x_fixed_point_quat_accrc_r <= # SIM_DELAY regs_din[12:8];
	end
	// 输入定点数量化精度
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 49) & IN_DATA_CVT_S33_IN_DATA_SUPPORTED)
			in_fixed_point_quat_accrc_r <= # SIM_DELAY regs_din[5:0];
	end
	
	// 舍入单元输入定点数量化精度, 舍入单元输出定点数量化精度, 定点数舍入位数
	always @(posedge aclk)
	begin
		if(
			regs_en & regs_wen & (regs_addr == 50) & 
			ROUND_S33_ROUND_SUPPORTED
		)
			{
				fixed_point_rounding_digits_r,
				round_out_fixed_point_quat_accrc_r,
				round_in_fixed_point_quat_accrc_r
			} <= # SIM_DELAY {
				regs_din[20:16],
				regs_din[12:8],
				regs_din[4:0]
			};
	end
	
	// 操作数A的实际值恒为1(标志), 操作数B的实际值恒为0(标志), 操作数A为常量(标志), 操作数B为常量(标志)
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 51))
			{is_op_b_const_r, is_op_a_const_r, is_op_b_eq_0_r, is_op_a_eq_1_r} <= # SIM_DELAY {
				regs_din[9],
				regs_din[8],
				regs_din[1],
				regs_din[0]
			};
	end
	
	// 操作数A的常量值
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 52))
			op_a_const_val_r <= # SIM_DELAY regs_din[31:0];
	end
	
	// 操作数B的常量值
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 53))
			op_b_const_val_r <= # SIM_DELAY regs_din[31:0];
	end
	
	// 旁路输入数据转换单元, 旁路二次幂计算单元, 旁路乘加计算单元, 旁路输出数据转换单元, 旁路舍入单元
	always @(posedge aclk)
	begin
		if(~aresetn)
			{
				round_cell_bypass_r,
				out_data_cvt_unit_bypass_r,
				mac_cell_bypass_r,
				pow2_cell_bypass_r,
				in_data_cvt_unit_bypass_r
			} <= 5'b11111;
		else if(regs_en & regs_wen & (regs_addr == 54))
			{
				round_cell_bypass_r,
				out_data_cvt_unit_bypass_r,
				mac_cell_bypass_r,
				pow2_cell_bypass_r,
				in_data_cvt_unit_bypass_r
			} <= # SIM_DELAY 
				regs_din[4:0] | 
				(~{
					EN_ROUND_UNIT,
					EN_OUT_DATA_CVT,
					EN_MAC_UNIT,
					EN_POW2_CAL_UNIT,
					EN_IN_DATA_CVT
				});
	end
	
	/** 寄存器读结果 **/
	always @(posedge aclk)
	begin
		if(regs_en & (~is_write))
		begin
			case(regs_addr)
				0: regs_dout <= # SIM_DELAY {version_r[31:0]};
				1: regs_dout <= # SIM_DELAY {acc_id_r[1:0], acc_type_r[29:0]};
				2: regs_dout <= # SIM_DELAY {s2mm_stream_data_width_r[15:0], mm2s_stream_data_width_r[15:0]};
				3: regs_dout <= # SIM_DELAY {
					10'd0,
					fp32_to_fp16_round_supported_r,
					s33_round_supported_r,
					out_data_cvt_fp32_to_s33_supported_r,
					cal_fp32_supported_r,
					cal_s32_supported_r,
					cal_s16_supported_r,
					in_data_cvt_int_to_fp32_supported_r,
					in_data_cvt_fp16_to_fp32_supported_r,
					out_stream_width_4_byte_supported_r,
					out_stream_width_2_byte_supported_r,
					out_stream_width_1_byte_supported_r,
					in_stream_width_4_byte_supported_r,
					in_stream_width_2_byte_supported_r,
					in_stream_width_1_byte_supported_r,
					element_wise_proc_pipeline_n_r[7:0]
				};
				
				16: regs_dout <= # SIM_DELAY {24'd0, 4'd0, en_cycle_n_cnt_r, en_proc_core_r, en_data_hub_r, en_accelerator_r};
				17: regs_dout <= # SIM_DELAY {24'd0, 5'd0, s2mm_cmd_pending_r, mm2s_1_cmd_pending_r, mm2s_0_cmd_pending_r};
				
				24: regs_dout <= # SIM_DELAY {dma_mm2s_0_fns_cmd_n_r[31:0]};
				25: regs_dout <= # SIM_DELAY {dma_mm2s_1_fns_cmd_n_r[31:0]};
				26: regs_dout <= # SIM_DELAY {dma_s2mm_fns_cmd_n_r[31:0]};
				27: regs_dout <= # SIM_DELAY {cycle_n_cnt_r[31:0]};
				
				32: regs_dout <= # SIM_DELAY {op_x_buf_baseaddr_r[31:0]};
				33: regs_dout <= # SIM_DELAY {op_a_b_buf_baseaddr_r[31:0]};
				34: regs_dout <= # SIM_DELAY {res_buf_baseaddr_r[31:0]};
				35: regs_dout <= # SIM_DELAY {8'd0, op_x_buf_len_r[23:0]};
				36: regs_dout <= # SIM_DELAY {8'd0, op_a_b_buf_len_r[23:0]};
				37: regs_dout <= # SIM_DELAY {8'd0, res_buf_len_r[23:0]};
				
				48: regs_dout <= # SIM_DELAY {8'd0, 5'd0, out_data_fmt_r[2:0], 6'd0, cal_calfmt_r[1:0], 5'd0, in_data_fmt_r[2:0]};
				49: regs_dout <= # SIM_DELAY {
					2'd0, s33_cvt_fixed_point_quat_accrc_r[5:0],
					3'd0, op_a_fixed_point_quat_accrc_r[4:0],
					3'd0, op_x_fixed_point_quat_accrc_r[4:0],
					2'd0, in_fixed_point_quat_accrc_r[5:0]
				};
				50: regs_dout <= # SIM_DELAY {
					8'd0,
					3'd0, fixed_point_rounding_digits_r[4:0],
					3'd0, round_out_fixed_point_quat_accrc_r[4:0],
					3'd0, round_in_fixed_point_quat_accrc_r[4:0]
				};
				51: regs_dout <= # SIM_DELAY {
					8'd0,
					8'd0,
					6'd0, is_op_b_const_r, is_op_a_const_r,
					6'd0, is_op_b_eq_0_r, is_op_a_eq_1_r
				};
				52: regs_dout <= # SIM_DELAY {op_a_const_val_r[31:0]};
				53: regs_dout <= # SIM_DELAY {op_b_const_val_r[31:0]};
				54: regs_dout <= # SIM_DELAY {
					8'd0,
					8'd0,
					8'd0,
					3'd0, round_cell_bypass_r, out_data_cvt_unit_bypass_r, mac_cell_bypass_r, pow2_cell_bypass_r, in_data_cvt_unit_bypass_r
				};
				
				default: regs_dout <= # SIM_DELAY 32'h0000_0000;
			endcase
		end
	end
	
endmodule
