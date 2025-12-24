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
本模块: 通用池化处理单元的寄存器配置接口

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
	| info0    | 0x08/2  |7~0: 通道并行数                |      RO      |                                  |
	|          |         |15~8: 后乘加并行数             |      RO      |                                  |
	|          |         |31~16: 特征图缓存的最大表面行数|      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info1    | 0x0C/3  |15~0: MM2S通道DMA数据流的位宽  |      RO      |                                  |
	|          |         |31~16: S2MM通道DMA数据流的位宽 |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info2    | 0x10/4  |15~0: 物理缓存BANK数           |      RO      |                                  |
	|          |         |31~16: 物理缓存每个BANK的深度  |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info3    | 0x14/5  |15~0: 中间结果缓存BANK数       |      RO      |                                  |
	|          |         |31~16: 中间结果每个BANK的深度  |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	| ctrl0    | 0x40/16 |0: 启动表面行访问请求生成单元  |      WO      | 向该字段写1以启动                |
	|          |         |                               |              | 表面行访问请求生成单元           |
	|          |         |1: 启动最终结果传输请求生成单元|      WO      | 向该字段写1以启动                |
	|          |         |                               |              | 最终结果传输请求生成单元         |
	|          |         |8: 使能计算子系统              |      RW      |                                  |
	|          |         |9: 启用后乘加处理              |      RW      | 仅当支持后乘加处理时可写1        |
	|          |         |10: 使能性能监测计数器         |      RW      | 仅当支持性能监测时可写1          |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	| sts0     | 0x60/24 |0: 表面行访问请求生成单元空闲  |      RO      |                                  |
	|          |         |1: 最终结果传输请求生成单元空闲|      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts1     | 0x64/25 |31~0: MM2S通道完成的命令数     |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts2     | 0x68/26 |31~0: S2MM通道完成的命令数     |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts3     | 0x6C/27 |31~0: 性能监测计数器           |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	| sts4     | 0x70/28 |31~0: MM2S通道传输字节数       |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	| sts5     | 0x74/29 |31~0: S2MM通道传输字节数       |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	| sts6     | 0x78/30 |31~0: 更新单元组运行周期数     |      RO      | 仅当支持性能监测时, 该字段可用   |
	|          |         |                               |              | 除能计算子系统时, 该字段清零     |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	| cal_cfg0 | 0x80/32 |3~0: 处理模式                  |      RW      | 仅当写入支持的处理模式时生效     |
	|          |         |7~4: 运算数据格式              |      RW      | 仅当写入支持的运算数据格式时生效 |
	|          |         |15~8: 池化水平步长 - 1         |      RW      | 仅当支持池化时该字段存在         |
	|          |         |23~16: 池化垂直步长 - 1        |      RW      | 仅当支持池化时该字段存在         |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg1 | 0x84/33 |7~0: 池化窗口宽度或            |      RW      | 含义根据处理模式而定             |
	|          |         |     上采样水平复制量 - 1      |              |                                  |
	|          |         |15~8: 池化窗口高度或           |      RW      | 含义根据处理模式而定             |
	|          |         |      上采样垂直复制量 - 1     |              |                                  |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg2 | 0x88/34 |0: 是否处于非0常量填充模式     |      RW      | 仅当支持非0常量填充模式时可写1   |
	|          |         |31~16: 待填充的常量            |      RW      | 仅当支持非0常量填充模式时        |
	|          |         |                               |              | 该字段存在                       |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg3 | 0x8C/35 |0: 参数A的实际值是否为1        |      RW      | 仅当支持后乘加处理时可写0        |
	|          |         |1: 参数B的实际值是否为0        |      RW      | 仅当支持后乘加处理时可写0        |
	|          |         |12~8: 定点数量化精度           |      RW      | 仅当支持后乘加处理和             |
	|          |         |                               |              | 整型运算数据格式时该字段存在     |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg4 | 0x90/36 |31~0: 后乘加处理的参数A        |      RW      | 仅当支持后乘加处理时该字段存在   |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg5 | 0x94/37 |31~0: 后乘加处理的参数B        |      RW      | 仅当支持后乘加处理时该字段存在   |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg0 | 0xC0/48 |31~0: 输入特征图基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg1 | 0xC4/49 |31~0: 输出特征图基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg2 | 0xC8/50 |15~0: 输入特征图宽度 - 1       |      RW      |                                  |
	|          |         |31~16: 输入特征图高度 - 1      |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg3 | 0xCC/51 |23~0: 输入特征图大小 - 1       |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg4 | 0xD0/52 |15~0: 特征图通道数 - 1         |      RW      |                                  |
	|          |         |23~16: 特征图左部外填充数      |      RW      | 仅当支持外填充时可写非0值        |
	|          |         |31~24: 特征图上部外填充数      |      RW      | 仅当支持外填充时可写非0值        |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg5 | 0xD4/53 |15~0: 扩展输入特征图宽度 - 1   |      RW      | 仅当支持外填充时该字段可写       |
	|          |         |31~16: 扩展输入特征图高度 - 1  |      RW      | 仅当支持外填充时该字段可写       |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg6 | 0xD8/54 |14~0: 输出特征图宽度 - 1       |      RW      |                                  |
	|          |         |29~15: 输出特征图高度 - 1      |      RW      |                                  |
	|          |         |31~30: 输出特征图数据大小类型  |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	| buf_cfg0 |0x100/64 |3~0: 特征图缓存                |      RW      |                                  |
	|          |         |     每个表面行的表面个数类型  |              |                                  |
	|          |         |31~16: 特征图缓存              |      RW      |                                  |
	|          |         |       可缓存的表面行数 - 1    |              |                                  |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg1 |0x104/65 |7~0: 中间结果缓存可缓存行数 - 1|      RW      |                                  |
	--------------------------------------------------------------------------------------------------------

注意：
支持非0常量填充模式的前提是支持外填充

协议:
AXI-Lite SLAVE
BLK CTRL

作者: 陈家耀
日期: 2025/12/24
********************************************************************/


module reg_if_for_generic_pool #(
	parameter integer ACCELERATOR_ID = 0, // 加速器ID(0~3)
	parameter MAX_POOL_SUPPORTED = 1'b1, // 是否支持最大池化
	parameter AVG_POOL_SUPPORTED = 1'b0, // 是否支持平均池化
	parameter UP_SAMPLE_SUPPORTED = 1'b1, // 是否支持上采样
	parameter POST_MAC_SUPPORTED = 1'b1, // 是否支持后乘加处理
	parameter INT8_SUPPORTED = 1'b0, // 是否支持INT8运算数据格式
	parameter INT16_SUPPORTED = 1'b1, // 是否支持INT16运算数据格式
	parameter FP16_SUPPORTED = 1'b1, // 是否支持FP16运算数据格式
	parameter EXT_PADDING_SUPPORTED = 1'b1, // 是否支持外填充
	parameter NON_ZERO_CONST_PADDING_SUPPORTED = 1'b0, // 是否支持非0常量填充模式
	parameter EN_PERF_MON = 1'b1, // 是否支持性能监测
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer POST_MAC_PRL_N = 1, // 后乘加并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MM2S_STREAM_DATA_WIDTH = 64, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16, // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 1024, // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512, // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 8, // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512, // 中间结果缓存MEM深度(16 | ...)
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
	
	// 控制信号
	output wire en_adapter, // 使能适配器
	output wire en_upd_grp_run_cnt, // 使能更新单元组运行周期数计数器
	output wire en_post_mac, // 使能后乘加处理
	
	// 状态信息
	input wire[31:0] upd_grp_run_n, // 更新单元组运行周期数
	
	// 传输字节数监测
	// [MM2S通道]
	input wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s_mm2s_strm_axis_keep,
	input wire s_mm2s_strm_axis_valid,
	input wire s_mm2s_strm_axis_ready,
	// [S2MM通道]
	input wire[S2MM_STREAM_DATA_WIDTH/8-1:0] s_s2mm_strm_axis_keep,
	input wire s_s2mm_strm_axis_valid,
	input wire s_s2mm_strm_axis_ready,
	
	// DMA命令完成指示
	input wire mm2s_cmd_done, // MM2S通道命令完成(指示)
	input wire s2mm_cmd_done, // S2MM通道命令完成(指示)
	
	// 块级控制
	// [池化表面行缓存访问控制]
	output wire sfc_row_access_blk_start,
	input wire sfc_row_access_blk_idle,
	input wire sfc_row_access_blk_done,
	// [最终结果传输请求生成单元]
	output wire fnl_res_tr_req_gen_blk_start,
	input wire fnl_res_tr_req_gen_blk_idle,
	input wire fnl_res_tr_req_gen_blk_done,
	
	// 运行时参数
	// [计算参数]
	output wire[1:0] pool_mode, // 池化模式
	output wire[1:0] calfmt, // 运算数据格式
	output wire[2:0] pool_horizontal_stride, // 池化水平步长 - 1
	output wire[2:0] pool_vertical_stride, // 池化垂直步长 - 1
	output wire[7:0] pool_window_w, // 池化窗口宽度 - 1
	output wire[7:0] pool_window_h, // 池化窗口高度 - 1
	// [后乘加处理参数]
	output wire[4:0] post_mac_fixed_point_quat_accrc, // 定点数量化精度
	output wire post_mac_is_a_eq_1, // 参数A的实际值为1(标志)
	output wire post_mac_is_b_eq_0, // 参数B的实际值为0(标志)
	output wire[31:0] post_mac_param_a, // 参数A
	output wire[31:0] post_mac_param_b, // 参数B
	// [上采样参数]
	output wire[7:0] upsample_horizontal_n, // 上采样水平复制量 - 1
	output wire[7:0] upsample_vertical_n, // 上采样垂直复制量 - 1
	// [非0常量填充]
	output wire non_zero_const_padding_mode, // 是否处于非0常量填充模式
	output wire[15:0] const_to_fill, // 待填充的常量
	// [特征图参数]
	output wire[31:0] ifmap_baseaddr, // 输入特征图基地址
	output wire[31:0] ofmap_baseaddr, // 输出特征图基地址
	output wire is_16bit_data, // 是否16位(输入)特征图数据
	output wire[15:0] ifmap_w, // 输入特征图宽度 - 1
	output wire[15:0] ifmap_h, // 输入特征图高度 - 1
	output wire[23:0] ifmap_size, // 输入特征图大小 - 1
	output wire[15:0] ext_ifmap_w, // 扩展输入特征图宽度 - 1
	output wire[15:0] ext_ifmap_h, // 扩展输入特征图高度 - 1
	output wire[15:0] fmap_chn_n, // 通道数 - 1
	output wire[2:0] external_padding_left, // 左部外填充数
	output wire[2:0] external_padding_top, // 上部外填充数
	output wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	output wire[15:0] ofmap_h, // 输出特征图高度 - 1
	output wire[1:0] ofmap_data_type, // 输出特征图数据大小类型
	// [特征图缓存参数]
	output wire[3:0] fmbufcoln, // 每个表面行的表面个数类型
	output wire[9:0] fmbufrown, // 可缓存的表面行数 - 1
	// [中间结果缓存参数]
	output wire[3:0] mid_res_buf_row_n_bufferable // 可缓存行数 - 1
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
	
	// 计算u32中"1"的个数
    function [5:0] count1_of_u32(input[31:0] data);
        integer i;
    begin
        count1_of_u32 = 6'd0;
        
        for(i = 0;i < 32;i = i + 1)
        begin
            if(data[i])
                count1_of_u32 = count1_of_u32 + 6'd1;
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
	// 处理模式的编码
	localparam PROC_MODE_AVG = 2'b00;
	localparam PROC_MODE_MAX = 2'b01;
	localparam PROC_MODE_UPSP = 2'b10;
	localparam PROC_MODE_NONE = 2'b11;
	// 运算数据格式的编码
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	localparam CAL_FMT_NONE = 2'b11;
	
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
	寄存器(version, acc_name, info0, info1, info2, info3)
	
	--------------------------------------------------------------------------------------------------------
    | version  | 0x00/0  |31~0: 版本号                   |      RO      | 用日期表示的版本号,              |
	|          |         |                               |              | 每4位取值0~9, 小端格式           |
	--------------------------------------------------------------------------------------------------------
	| acc_name | 0x04/1  |29~0: 加速器类型               |      RO      | 用小写字母表示的加速器类型, 每5位|
	|          |         |                               |              | 取值0~26, 小端格式, 26表示'\0'   |
	|          |         |31~30: 加速器ID                |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info0    | 0x08/2  |7~0: 通道并行数                |      RO      |                                  |
	|          |         |15~8: 后乘加并行数             |      RO      |                                  |
	|          |         |31~16: 特征图缓存的最大表面行数|      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info1    | 0x0C/3  |15~0: MM2S通道DMA数据流的位宽  |      RO      |                                  |
	|          |         |31~16: S2MM通道DMA数据流的位宽 |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info2    | 0x10/4  |15~0: 物理缓存BANK数           |      RO      |                                  |
	|          |         |31~16: 物理缓存每个BANK的深度  |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| info3    | 0x14/5  |15~0: 中间结果缓存BANK数       |      RO      |                                  |
	|          |         |31~16: 中间结果每个BANK的深度  |      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	**/
	wire[31:0] version_r; // 版本号
	wire[29:0] acc_type_r; // 加速器类型
	wire[1:0] acc_id_r; // 加速器ID
	wire[7:0] atomic_c_r; // 通道并行数
	wire[7:0] post_mac_prl_n_r; // 后乘加并行数
	wire[15:0] max_fmbuf_rown_r; // 特征图缓存的最大表面行数
	wire[15:0] mm2s_strm_data_width_r; // MM2S通道DMA数据流的位宽
	wire[15:0] s2mm_strm_data_width_r; // S2MM通道DMA数据流的位宽
	wire[15:0] phy_buffer_bank_n_r; // 物理缓存BANK数
	wire[15:0] phy_buffer_bank_depth_r; // 物理缓存每个BANK的深度
	wire[15:0] mid_res_buf_bank_n_r; // 中间结果缓存BANK数
	wire[15:0] mid_res_buf_bank_depth_r; // 中间结果每个BANK的深度
	
	assign version_r = {4'd7, 4'd1, 4'd2, 4'd1, 4'd5, 4'd2, 4'd0, 4'd2}; // 2025.12.17
	assign acc_type_r = {5'd26, 5'd26, 5'd11, 5'd14, 5'd14, 5'd15}; // "pool\0\0"
	assign acc_id_r = ACCELERATOR_ID;
	assign atomic_c_r = ATOMIC_C;
	assign post_mac_prl_n_r = POST_MAC_SUPPORTED ? POST_MAC_PRL_N:0;
	assign max_fmbuf_rown_r = MAX_FMBUF_ROWN;
	assign mm2s_strm_data_width_r = MM2S_STREAM_DATA_WIDTH;
	assign s2mm_strm_data_width_r = S2MM_STREAM_DATA_WIDTH;
	assign phy_buffer_bank_n_r = CBUF_BANK_N;
	assign phy_buffer_bank_depth_r = CBUF_DEPTH_FOREACH_BANK;
	assign mid_res_buf_bank_n_r = RBUF_BANK_N;
	assign mid_res_buf_bank_depth_r = RBUF_DEPTH;
	
	/**
	寄存器(ctrl0)
	
	--------------------------------------------------------------------------------------------------------
	| ctrl0    | 0x40/16 |0: 启动表面行访问请求生成单元  |      WO      | 向该字段写1以启动                |
	|          |         |                               |              | 表面行访问请求生成单元           |
	|          |         |1: 启动最终结果传输请求生成单元|      WO      | 向该字段写1以启动                |
	|          |         |                               |              | 最终结果传输请求生成单元         |
	|          |         |8: 使能计算子系统              |      RW      |                                  |
	|          |         |9: 启用后乘加处理              |      RW      | 仅当支持后乘加处理时可写1        |
	|          |         |10: 使能性能监测计数器         |      RW      | 仅当支持性能监测时可写1          |
	--------------------------------------------------------------------------------------------------------
	**/
	reg sfc_row_access_blk_start_r; // 启动表面行访问请求生成单元(指示)
	reg fnl_res_tr_req_gen_blk_start_r; // 启动最终结果传输请求生成单元(指示)
	reg en_cal_sub_sys_r; // 使能计算子系统
	reg to_use_post_mac_r; // 启用后乘加处理
	reg en_pm_cnt_r; // 使能性能监测计数器
	
	assign en_adapter = en_cal_sub_sys_r;
	assign en_upd_grp_run_cnt = en_cal_sub_sys_r & EN_PERF_MON;
	assign en_post_mac = en_cal_sub_sys_r & to_use_post_mac_r;
	
	assign sfc_row_access_blk_start = sfc_row_access_blk_start_r;
	assign fnl_res_tr_req_gen_blk_start = fnl_res_tr_req_gen_blk_start_r;
	
	// 启动表面行访问请求生成单元(指示), 启动最终结果传输请求生成单元(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{fnl_res_tr_req_gen_blk_start_r, sfc_row_access_blk_start_r} <= 2'b00;
		else
			{fnl_res_tr_req_gen_blk_start_r, sfc_row_access_blk_start_r} <= # SIM_DELAY 
				{2{regs_en & regs_wen & (regs_addr == 16)}} & regs_din[1:0];
	end
	
	// 使能计算子系统, 启用后乘加处理, 使能性能监测计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{en_pm_cnt_r, to_use_post_mac_r, en_cal_sub_sys_r} <= 3'b000;
		else if(regs_en & regs_wen & (regs_addr == 16))
			{en_pm_cnt_r, to_use_post_mac_r, en_cal_sub_sys_r} <= # SIM_DELAY 
				{
					regs_din[10] & EN_PERF_MON,
					regs_din[9] & POST_MAC_SUPPORTED,
					regs_din[8]
				};
	end
	
	/**
	寄存器(sts0, sts1, sts2, sts3, sts4, sts5, sts6)
	
	--------------------------------------------------------------------------------------------------------
	| sts0     | 0x60/24 |0: 表面行访问请求生成单元空闲  |      RO      |                                  |
	|          |         |1: 最终结果传输请求生成单元空闲|      RO      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts1     | 0x64/25 |31~0: MM2S通道完成的命令数     |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts2     | 0x68/26 |31~0: S2MM通道完成的命令数     |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	| sts3     | 0x6C/27 |31~0: 性能监测计数器           |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	| sts4     | 0x70/28 |31~0: MM2S通道传输字节数       |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	| sts5     | 0x74/29 |31~0: S2MM通道传输字节数       |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	| sts6     | 0x78/30 |31~0: 更新单元组运行周期数     |      RO      | 仅当支持性能监测时, 该字段可用   |
	|          |         |                               |              | 除能计算子系统时, 该字段清零     |
	--------------------------------------------------------------------------------------------------------
	**/
	wire sfc_row_access_blk_idle_r; // 表面行访问请求生成单元空闲
	wire fnl_res_tr_req_gen_blk_idle_r; // 最终结果传输请求生成单元空闲
	reg[31:0] dma_mm2s_fns_cmd_n_r; // MM2S通道完成的命令数
	reg[31:0] dma_s2mm_fns_cmd_n_r; // S2MM通道完成的命令数
	reg[31:0] pm_cnt_r; // 性能监测计数器
	reg[31:0] mm2s_tsf_n_r; // MM2S通道传输字节数
	reg[31:0] s2mm_tsf_n_r; // S2MM通道传输字节数
	wire[31:0] upd_grp_run_n_r; // 更新单元组运行周期数
	
	assign sfc_row_access_blk_idle_r = sfc_row_access_blk_idle;
	assign fnl_res_tr_req_gen_blk_idle_r = fnl_res_tr_req_gen_blk_idle;
	assign upd_grp_run_n_r = upd_grp_run_n;
	
	// MM2S通道完成的命令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dma_mm2s_fns_cmd_n_r <= 32'd0;
		else if(
			mm2s_cmd_done | 
			(regs_en & regs_wen & (regs_addr == 25))
		)
			dma_mm2s_fns_cmd_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 25)) ? 
					32'd0:
					(dma_mm2s_fns_cmd_n_r + 1'b1);
	end
	
	// S2MM通道完成的命令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dma_s2mm_fns_cmd_n_r <= 32'd0;
		else if(
			s2mm_cmd_done | 
			(regs_en & regs_wen & (regs_addr == 26))
		)
			dma_s2mm_fns_cmd_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 26)) ? 
					32'd0:
					(dma_s2mm_fns_cmd_n_r + 1'b1);
	end
	
	// 性能监测计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pm_cnt_r <= 32'd0;
		else if(
			EN_PERF_MON & 
			(
				en_pm_cnt_r | 
				(regs_en & regs_wen & (regs_addr == 27))
			)
		)
			pm_cnt_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 27)) ? 
					32'd0:
					(pm_cnt_r + 1'b1);
	end
	
	// MM2S通道传输字节数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mm2s_tsf_n_r <= 32'd0;
		else if(
			EN_PERF_MON & 
			(
				(s_mm2s_strm_axis_valid & s_mm2s_strm_axis_ready) | 
				(regs_en & regs_wen & (regs_addr == 28))
			)
		)
			mm2s_tsf_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 28)) ? 
					32'd0:
					(mm2s_tsf_n_r + count1_of_u32(s_mm2s_strm_axis_keep | 32'd0));
	end
	
	// S2MM通道传输字节数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			s2mm_tsf_n_r <= 32'd0;
		else if(
			EN_PERF_MON & 
			(
				(s_s2mm_strm_axis_valid & s_s2mm_strm_axis_ready) | 
				(regs_en & regs_wen & (regs_addr == 29))
			)
		)
			s2mm_tsf_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 29)) ? 
					32'd0:
					(s2mm_tsf_n_r + count1_of_u32(s_s2mm_strm_axis_keep | 32'd0));
	end
	
	/**
	寄存器(cal_cfg0, cal_cfg1, cal_cfg2, cal_cfg3, cal_cfg4, cal_cfg5)
	
	--------------------------------------------------------------------------------------------------------
	| cal_cfg0 | 0x80/32 |3~0: 处理模式                  |      RW      | 仅当写入支持的处理模式时生效     |
	|          |         |7~4: 运算数据格式              |      RW      | 仅当写入支持的运算数据格式时生效 |
	|          |         |15~8: 池化水平步长 - 1         |      RW      | 仅当支持池化时该字段存在         |
	|          |         |23~16: 池化垂直步长 - 1        |      RW      | 仅当支持池化时该字段存在         |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg1 | 0x84/33 |7~0: 池化窗口宽度或            |      RW      | 含义根据处理模式而定             |
	|          |         |     上采样水平复制量 - 1      |              |                                  |
	|          |         |15~8: 池化窗口高度或           |      RW      | 含义根据处理模式而定             |
	|          |         |      上采样垂直复制量 - 1     |              |                                  |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg2 | 0x88/34 |0: 是否处于非0常量填充模式     |      RW      | 仅当支持非0常量填充模式时可写1   |
	|          |         |31~16: 待填充的常量            |      RW      | 仅当支持非0常量填充模式时        |
	|          |         |                               |              | 该字段存在                       |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg3 | 0x8C/35 |0: 参数A的实际值是否为1        |      RW      | 仅当支持后乘加处理时可写0        |
	|          |         |1: 参数B的实际值是否为0        |      RW      | 仅当支持后乘加处理时可写0        |
	|          |         |12~8: 定点数量化精度           |      RW      | 仅当支持后乘加处理和             |
	|          |         |                               |              | 整型运算数据格式时该字段存在     |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg4 | 0x90/36 |31~0: 后乘加处理的参数A        |      RW      | 仅当支持后乘加处理时该字段存在   |
	--------------------------------------------------------------------------------------------------------
	| cal_cfg5 | 0x94/37 |31~0: 后乘加处理的参数B        |      RW      | 仅当支持后乘加处理时该字段存在   |
	--------------------------------------------------------------------------------------------------------
	**/
	reg[3:0] proc_mode_r; // 处理模式
	reg[3:0] calfmt_r; // 运算数据格式
	reg[7:0] pool_horizontal_stride_r; // 池化水平步长 - 1
	reg[7:0] pool_vertical_stride_r; // 池化垂直步长 - 1
	reg[7:0] pool_window_w_or_upsample_horizontal_n_r; // 池化窗口宽度或上采样水平复制量 - 1
	reg[7:0] pool_window_h_or_upsample_vertical_n_r; // 池化窗口高度或上采样垂直复制量 - 1
	reg is_non_zero_const_padding_mode_r; // 是否处于非0常量填充模式
	reg[15:0] const_to_fill_r; // 待填充的常量
	reg post_mac_is_a_eq_1_r; // 后乘加处理的参数A的实际值是否为1
	reg post_mac_is_b_eq_0_r; // 后乘加处理的参数B的实际值是否为0
	reg[4:0] post_mac_fixed_point_quat_accrc_r; // 后乘加处理的定点数量化精度
	reg[31:0] post_mac_param_a_r; // 后乘加处理的参数A
	reg[31:0] post_mac_param_b_r; // 后乘加处理的参数B
	
	assign pool_mode = 
		((proc_mode_r[1:0] == PROC_MODE_MAX)  & MAX_POOL_SUPPORTED)  ? PROC_MODE_MAX:
		((proc_mode_r[1:0] == PROC_MODE_AVG)  & AVG_POOL_SUPPORTED)  ? PROC_MODE_AVG:
		((proc_mode_r[1:0] == PROC_MODE_UPSP) & UP_SAMPLE_SUPPORTED) ? PROC_MODE_UPSP:
		                                                               PROC_MODE_NONE;
	assign calfmt = 
		((calfmt_r[1:0] == CAL_FMT_INT8)  & INT8_SUPPORTED)  ? CAL_FMT_INT8:
		((calfmt_r[1:0] == CAL_FMT_INT16) & INT16_SUPPORTED) ? CAL_FMT_INT16:
		((calfmt_r[1:0] == CAL_FMT_FP16)  & FP16_SUPPORTED)  ? CAL_FMT_FP16:
		                                                       CAL_FMT_NONE;
	assign pool_horizontal_stride = 
		(MAX_POOL_SUPPORTED | AVG_POOL_SUPPORTED) ? 
			pool_horizontal_stride_r[2:0]:
			3'bxxx;
	assign pool_vertical_stride = 
		(MAX_POOL_SUPPORTED | AVG_POOL_SUPPORTED) ? 
			pool_vertical_stride_r[2:0]:
			3'bxxx;
	assign pool_window_w = 
		(MAX_POOL_SUPPORTED | AVG_POOL_SUPPORTED) ? 
			pool_window_w_or_upsample_horizontal_n_r:
			8'dx;
	assign pool_window_h = 
		(MAX_POOL_SUPPORTED | AVG_POOL_SUPPORTED) ? 
			pool_window_h_or_upsample_vertical_n_r:
			8'dx;
	assign post_mac_fixed_point_quat_accrc = 
		(POST_MAC_SUPPORTED & (INT8_SUPPORTED | INT16_SUPPORTED)) ? 
			post_mac_fixed_point_quat_accrc_r:
			5'bxxxxx;
	assign post_mac_is_a_eq_1 = 
		POST_MAC_SUPPORTED ? 
			post_mac_is_a_eq_1_r:
			1'bx;
	assign post_mac_is_b_eq_0 = 
		POST_MAC_SUPPORTED ? 
			post_mac_is_b_eq_0_r:
			1'bx;
	assign post_mac_param_a = 
		POST_MAC_SUPPORTED ? 
			post_mac_param_a_r:
			32'hxxxxxxxx;
	assign post_mac_param_b = 
		POST_MAC_SUPPORTED ? 
			post_mac_param_b_r:
			32'hxxxxxxxx;
	assign upsample_horizontal_n = 
		UP_SAMPLE_SUPPORTED ? 
			pool_window_w_or_upsample_horizontal_n_r:
			8'dx;
	assign upsample_vertical_n = 
		UP_SAMPLE_SUPPORTED ? 
			pool_window_h_or_upsample_vertical_n_r:
			8'dx;
	assign non_zero_const_padding_mode = 
		NON_ZERO_CONST_PADDING_SUPPORTED ? 
			is_non_zero_const_padding_mode_r:
			1'b0;
	assign const_to_fill = 
		NON_ZERO_CONST_PADDING_SUPPORTED ? 
			const_to_fill_r:
			16'hxxxx;
	
	// 处理模式
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			proc_mode_r <= {2'b11, PROC_MODE_NONE};
		else if(
			regs_en & regs_wen & (regs_addr == 32) & 
			(
				(MAX_POOL_SUPPORTED & (regs_din[3:0] == {2'b00, PROC_MODE_MAX})) | 
				(AVG_POOL_SUPPORTED & (regs_din[3:0] == {2'b00, PROC_MODE_AVG})) | 
				(UP_SAMPLE_SUPPORTED & (regs_din[3:0] == {2'b00, PROC_MODE_UPSP}))
			)
		)
			proc_mode_r <= # SIM_DELAY regs_din[3:0];
	end
	
	// 运算数据格式
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			calfmt_r <= {2'b11, CAL_FMT_NONE};
		else if(
			regs_en & regs_wen & (regs_addr == 32) & 
			(
				(INT8_SUPPORTED & (regs_din[7:4] == {2'b00, CAL_FMT_INT8})) | 
				(INT16_SUPPORTED & (regs_din[7:4] == {2'b00, CAL_FMT_INT16})) | 
				(FP16_SUPPORTED & (regs_din[7:4] == {2'b00, CAL_FMT_FP16}))
			)
		)
			calfmt_r <= # SIM_DELAY regs_din[7:4];
	end
	
	// 池化水平步长 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 32) & (MAX_POOL_SUPPORTED | AVG_POOL_SUPPORTED))
			pool_horizontal_stride_r <= # SIM_DELAY regs_din[15:8];
	end
	
	// 池化垂直步长 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 32) & (MAX_POOL_SUPPORTED | AVG_POOL_SUPPORTED))
			pool_vertical_stride_r <= # SIM_DELAY regs_din[23:16];
	end
	
	// 池化窗口宽度或上采样水平复制量 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 33))
			pool_window_w_or_upsample_horizontal_n_r <= # SIM_DELAY regs_din[7:0];
	end
	
	// 池化窗口高度或上采样垂直复制量 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 33))
			pool_window_h_or_upsample_vertical_n_r <= # SIM_DELAY regs_din[15:8];
	end
	
	// 是否处于非0常量填充模式
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			is_non_zero_const_padding_mode_r <= 1'b0;
		else if(regs_en & regs_wen & (regs_addr == 34) & NON_ZERO_CONST_PADDING_SUPPORTED)
			is_non_zero_const_padding_mode_r <= # SIM_DELAY regs_din[0];
	end
	
	// 待填充的常量
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 34) & NON_ZERO_CONST_PADDING_SUPPORTED)
			const_to_fill_r <= # SIM_DELAY regs_din[31:16];
	end
	
	// 后乘加处理的参数A的实际值是否为1
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			post_mac_is_a_eq_1_r <= 1'b1;
		else if(regs_en & regs_wen & (regs_addr == 35) & POST_MAC_SUPPORTED)
			post_mac_is_a_eq_1_r <= # SIM_DELAY regs_din[0];
	end
	
	// 后乘加处理的参数B的实际值是否为0
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			post_mac_is_b_eq_0_r <= 1'b1;
		else if(regs_en & regs_wen & (regs_addr == 35) & POST_MAC_SUPPORTED)
			post_mac_is_b_eq_0_r <= # SIM_DELAY regs_din[1];
	end
	
	// 后乘加处理的定点数量化精度
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 35) & POST_MAC_SUPPORTED & (INT8_SUPPORTED | INT16_SUPPORTED))
			post_mac_fixed_point_quat_accrc_r <= # SIM_DELAY regs_din[12:8];
	end
	
	// 后乘加处理的参数A
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 36) & POST_MAC_SUPPORTED)
			post_mac_param_a_r <= # SIM_DELAY regs_din[31:0];
	end
	
	// 后乘加处理的参数B
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 37) & POST_MAC_SUPPORTED)
			post_mac_param_b_r <= # SIM_DELAY regs_din[31:0];
	end
	
	/**
	寄存器(fmap_cfg0, fmap_cfg1, fmap_cfg2, fmap_cfg3, fmap_cfg4, fmap_cfg5, fmap_cfg6)
	
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg0 | 0xC0/48 |31~0: 输入特征图基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg1 | 0xC4/49 |31~0: 输出特征图基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg2 | 0xC8/50 |15~0: 输入特征图宽度 - 1       |      RW      |                                  |
	|          |         |31~16: 输入特征图高度 - 1      |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg3 | 0xCC/51 |23~0: 输入特征图大小 - 1       |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg4 | 0xD0/52 |15~0: 特征图通道数 - 1         |      RW      |                                  |
	|          |         |23~16: 特征图左部外填充数      |      RW      | 仅当支持外填充时可写非0值        |
	|          |         |31~24: 特征图上部外填充数      |      RW      | 仅当支持外填充时可写非0值        |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg5 | 0xD4/53 |15~0: 扩展输入特征图宽度 - 1   |      RW      | 仅当支持外填充时该字段可写       |
	|          |         |31~16: 扩展输入特征图高度 - 1  |      RW      | 仅当支持外填充时该字段可写       |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg6 | 0xD8/54 |14~0: 输出特征图宽度 - 1       |      RW      |                                  |
	|          |         |29~15: 输出特征图高度 - 1      |      RW      |                                  |
	|          |         |31~30: 输出特征图数据大小类型  |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	**/
	reg[31:0] ifmap_baseaddr_r; // 输入特征图基地址
	reg[31:0] ofmap_baseaddr_r; // 输出特征图基地址
	reg[15:0] ifmap_w_r; // 输入特征图宽度 - 1
	reg[15:0] ifmap_h_r; // 输入特征图高度 - 1
	reg[23:0] ifmap_size_r; // 输入特征图大小 - 1
	reg[15:0] ext_ifmap_w_r; // 扩展输入特征图宽度 - 1
	reg[15:0] ext_ifmap_h_r; // 扩展输入特征图高度 - 1
	reg[15:0] fmap_chn_n_r; // 特征图通道数 - 1
	reg[7:0] external_padding_left_r; // 特征图左部外填充数
	reg[7:0] external_padding_top_r; // 特征图上部外填充数
	reg[14:0] ofmap_w_r; // 输出特征图宽度 - 1
	reg[14:0] ofmap_h_r; // 输出特征图高度 - 1
	reg[1:0] ofmap_data_type_r; // 输出特征图数据大小类型
	
	assign ifmap_baseaddr = ifmap_baseaddr_r;
	assign ofmap_baseaddr = ofmap_baseaddr_r;
	assign is_16bit_data = calfmt != CAL_FMT_INT8;
	assign ifmap_w = ifmap_w_r;
	assign ifmap_h = ifmap_h_r;
	assign ifmap_size = ifmap_size_r;
	assign ext_ifmap_w = 
		EXT_PADDING_SUPPORTED ? 
			ext_ifmap_w_r:
			ifmap_w_r;
	assign ext_ifmap_h = 
		EXT_PADDING_SUPPORTED ? 
			ext_ifmap_h_r:
			ifmap_h_r;
	assign fmap_chn_n = fmap_chn_n_r;
	assign external_padding_left = 
		EXT_PADDING_SUPPORTED ? 
			external_padding_left_r[2:0]:
			3'b000;
	assign external_padding_top = 
		EXT_PADDING_SUPPORTED ? 
			external_padding_top_r[2:0]:
			3'b000;
	assign ofmap_w = ofmap_w_r | 16'h0000;
	assign ofmap_h = ofmap_h_r | 16'h0000;
	assign ofmap_data_type = ofmap_data_type_r;
	
	// 输入特征图基地址
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 48))
			ifmap_baseaddr_r <= # SIM_DELAY regs_din[31:0];
	end
	
	// 输出特征图基地址
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 49))
			ofmap_baseaddr_r <= # SIM_DELAY regs_din[31:0];
	end
	
	// 输入特征图宽度 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 50))
			ifmap_w_r <= # SIM_DELAY regs_din[15:0];
	end
	
	// 输入特征图高度 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 50))
			ifmap_h_r <= # SIM_DELAY regs_din[31:16];
	end
	
	// 输入特征图大小 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 51))
			ifmap_size_r <= # SIM_DELAY regs_din[23:0];
	end
	
	// 特征图通道数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 52))
			fmap_chn_n_r <= # SIM_DELAY regs_din[15:0];
	end
	
	// 左部外填充数
	always @(posedge aclk)
	begin
		if(
			regs_en & regs_wen & (regs_addr == 52) & 
			((regs_din[23:16] == 8'd0) | EXT_PADDING_SUPPORTED)
		)
			external_padding_left_r <= # SIM_DELAY regs_din[23:16];
	end
	
	// 上部外填充数
	always @(posedge aclk)
	begin
		if(
			regs_en & regs_wen & (regs_addr == 52) & 
			((regs_din[31:24] == 8'd0) | EXT_PADDING_SUPPORTED)
		)
			external_padding_top_r <= # SIM_DELAY regs_din[31:24];
	end
	
	// 扩展输入特征图宽度 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 53) & EXT_PADDING_SUPPORTED)
			ext_ifmap_w_r <= # SIM_DELAY regs_din[15:0];
	end
	
	// 扩展输入特征图高度 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 53) & EXT_PADDING_SUPPORTED)
			ext_ifmap_h_r <= # SIM_DELAY regs_din[31:16];
	end
	
	// 输出特征图宽度 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 54))
			ofmap_w_r <= # SIM_DELAY regs_din[14:0];
	end
	
	// 输出特征图高度 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 54))
			ofmap_h_r <= # SIM_DELAY regs_din[29:15];
	end
	
	// 输出特征图数据大小类型
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 54))
			ofmap_data_type_r <= # SIM_DELAY regs_din[31:30];
	end
	
	/**
	寄存器(buf_cfg0, buf_cfg1)
	
	--------------------------------------------------------------------------------------------------------
	| buf_cfg0 |0x100/64 |3~0: 特征图缓存                |      RW      |                                  |
	|          |         |     每个表面行的表面个数类型  |              |                                  |
	|          |         |31~16: 特征图缓存              |      RW      |                                  |
	|          |         |       可缓存的表面行数 - 1    |              |                                  |
	--------------------------------------------------------------------------------------------------------
	| buf_cfg1 |0x104/65 |7~0: 中间结果缓存可缓存行数 - 1|      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	**/
	reg[3:0] fmbufcoln_r; // 特征图缓存每个表面行的表面个数类型
	reg[15:0] fmbufrown_r; // 特征图缓存可缓存的表面行数 - 1
	reg[7:0] mid_res_buf_row_n_bufferable_r; // 中间结果缓存可缓存行数 - 1
	
	assign fmbufcoln = fmbufcoln_r;
	assign fmbufrown = fmbufrown_r[9:0];
	assign mid_res_buf_row_n_bufferable = mid_res_buf_row_n_bufferable_r[3:0];
	
	// 每个表面行的表面个数类型
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 64))
			fmbufcoln_r <= # SIM_DELAY regs_din[3:0];
	end
	
	// 特征图缓存可缓存的表面行数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 64))
			fmbufrown_r <= # SIM_DELAY regs_din[31:16];
	end
	
	// 中间结果缓存可缓存行数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 65))
			mid_res_buf_row_n_bufferable_r <= # SIM_DELAY regs_din[7:0];
	end
	
	/** 寄存器读结果 **/
	always @(posedge aclk)
	begin
		if(regs_en & (~is_write))
		begin
			case(regs_addr)
				0: regs_dout <= # SIM_DELAY {version_r[31:0]};
				1: regs_dout <= # SIM_DELAY {acc_id_r[1:0], acc_type_r[29:0]};
				2: regs_dout <= # SIM_DELAY {max_fmbuf_rown_r[15:0], post_mac_prl_n_r[7:0], atomic_c_r[7:0]};
				3: regs_dout <= # SIM_DELAY {s2mm_strm_data_width_r[15:0], mm2s_strm_data_width_r[15:0]};
				4: regs_dout <= # SIM_DELAY {phy_buffer_bank_depth_r[15:0], phy_buffer_bank_n_r[15:0]};
				5: regs_dout <= # SIM_DELAY {mid_res_buf_bank_depth_r[15:0], mid_res_buf_bank_n_r[15:0]};
				
				16: regs_dout <= # SIM_DELAY {8'd0, 8'd0, 5'd0, en_pm_cnt_r, to_use_post_mac_r, en_cal_sub_sys_r, 8'd0};
				
				24: regs_dout <= # SIM_DELAY {8'd0, 8'd0, 8'd0, 6'd0, fnl_res_tr_req_gen_blk_idle_r, sfc_row_access_blk_idle_r};
				25: regs_dout <= # SIM_DELAY {dma_mm2s_fns_cmd_n_r[31:0]};
				26: regs_dout <= # SIM_DELAY {dma_s2mm_fns_cmd_n_r[31:0]};
				27: regs_dout <= # SIM_DELAY {pm_cnt_r[31:0]};
				28: regs_dout <= # SIM_DELAY {mm2s_tsf_n_r[31:0]};
				29: regs_dout <= # SIM_DELAY {s2mm_tsf_n_r[31:0]};
				30: regs_dout <= # SIM_DELAY {upd_grp_run_n_r[31:0]};
				
				32: regs_dout <= # SIM_DELAY 
					{8'd0, pool_vertical_stride_r[7:0], pool_horizontal_stride_r[7:0], calfmt_r[3:0], proc_mode_r[3:0]};
				33: regs_dout <= # SIM_DELAY 
					{8'd0, 8'd0, pool_window_h_or_upsample_vertical_n_r[7:0], pool_window_w_or_upsample_horizontal_n_r[7:0]};
				34: regs_dout <= # SIM_DELAY {const_to_fill_r[15:0], 8'd0, 7'd0, is_non_zero_const_padding_mode_r};
				35: regs_dout <= # SIM_DELAY 
					{8'd0, 8'd0, 3'd0, post_mac_fixed_point_quat_accrc_r[4:0], 6'd0, post_mac_is_b_eq_0_r, post_mac_is_a_eq_1_r};
				36: regs_dout <= # SIM_DELAY {post_mac_param_a_r[31:0]};
				37: regs_dout <= # SIM_DELAY {post_mac_param_b_r[31:0]};
				
				48: regs_dout <= # SIM_DELAY {ifmap_baseaddr_r[31:0]};
				49: regs_dout <= # SIM_DELAY {ofmap_baseaddr_r[31:0]};
				50: regs_dout <= # SIM_DELAY {ifmap_h_r[15:0], ifmap_w_r[15:0]};
				51: regs_dout <= # SIM_DELAY {8'd0, ifmap_size_r[23:0]};
				52: regs_dout <= # SIM_DELAY {external_padding_top_r[7:0], external_padding_left_r[7:0], fmap_chn_n_r[15:0]};
				53: regs_dout <= # SIM_DELAY {ext_ifmap_h_r[15:0], ext_ifmap_w_r[15:0]};
				54: regs_dout <= # SIM_DELAY {ofmap_data_type_r[1:0], ofmap_h_r[14:0], ofmap_w_r[14:0]};
				
				64: regs_dout <= # SIM_DELAY {fmbufrown_r[15:0], 8'd0, 4'd0, fmbufcoln_r[3:0]};
				65: regs_dout <= # SIM_DELAY {8'd0, 8'd0, 8'd0, mid_res_buf_row_n_bufferable_r[7:0]};
				
				default: regs_dout <= # SIM_DELAY 32'h0000_0000;
			endcase
		end
	end
	
endmodule
