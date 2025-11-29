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
本模块: 通用卷积处理单元的寄存器配置接口

描述:
寄存器 -> 
	| 寄存器名 | 偏移量  |             含义              |   读写特性   |              备注                |
    --------------------------------------------------------------------------------------------------------
    | version  | 0x00/0  |31~0: 版本号                   |      RO      | 用日期表示的版本号,              |
	|          |         |                               |              | 每4位取值0~9, 小端格式           |
	--------------------------------------------------------------------------------------------------------
	| acc_name | 0x04/1  |29~0: 加速器类型               |      RO      | 用小写字母表示的加速器类型, 每5位|
	|          |         |                               |              | 取值0~26, 小端格式, 26表示'\0'   |
	|          |         |31~30: 加速器ID                |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  info0   | 0x08/2  |7~0: 核并行数 - 1              |      RO      |                                  |
	|          |         |15~8: 通道并行数 - 1           |              |                                  |
	|          |         |23~16: 最大的计算轮次 - 1      |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  info1   | 0x0C/3  |7~0: MM2S通道数据位宽 - 1      |      RO      |                                  |
	|          |         |15~8: S2MM通道数据位宽 - 1     |              |                                  |
	|          |         |31~16: 物理缓存BANK数 - 1      |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  info2   | 0x10/4  |15~0: 物理缓存BANK深度 - 1     |      RO      |                                  |
	|          |         |31~16: 特征图缓存              |              |                                  |
	|          |         |       最大表面行数 - 1        |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  info3   | 0x14/5  |15~0: 中间结果缓存BANK数 - 1   |      RO      |                                  |
	|          |         |31~16: 中间结果缓存BANK深度 - 1|              |                                  |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	|  ctrl0   | 0x40/16 | 0: 使能计算子系统             |      RW      |                                  |
	|          |         | 1: 使能性能监测计数器         |      RW      | 仅当支持性能监测时, 写1生效      |
	|          |         | 8: 启动卷积核权重             |      WO      | 向该位写1会向卷积核权重          |
	|          |         |    访问请求生成单元           |              | 访问请求生成单元发送start信号    |
	|          |         | 9: 启动特征图表面行           |      WO      | 向该位写1会向特征图表面行        |
	|          |         |    访问请求生成单元           |              | 访问请求生成单元发送start信号    |
	|          |         |10: 启动最终结果               |      WO      | 向该位写1会向最终结果            |
	|          |         |    传输请求生成单元           |              | 传输请求生成单元发送start信号    |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	|  sts0    | 0x60/24 | 0: 卷积核权重                 |      RO      |                                  |
	|          |         |    访问请求生成单元空闲标志   |              |                                  |
	|          |         | 1: 特征图表面行               |      RO      |                                  |
	|          |         |    访问请求生成单元空闲标志   |              |                                  |
	|          |         | 2: 最终结果                   |      RO      |                                  |
	|          |         |    传输请求生成单元空闲标志   |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  sts1    | 0x64/25 |31~0: 0号MM2S通道完成的命令数  |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	|  sts2    | 0x68/26 |31~0: 1号MM2S通道完成的命令数  |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	|  sts3    | 0x6C/27 |31~0: S2MM通道完成的命令数     |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	|  sts4    | 0x70/28 |31~0: 性能监测计数器           |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	| cal_cfg  | 0x80/32 |2~0: 运算数据格式              |      RW      | 在写入时, 仅对支持的             |
	|          |         |                               |              | 运算数据格式生效                 |
	|          |         |10~8: 卷积垂直步长 - 1         |      RW      | 在写入时, 仅对支持的             |
	|          |         |                               |              | 卷积垂直步长生效                 |
	|          |         |13~11: 卷积水平步长 - 1        |      RW      | 在写入时, 仅对支持的             |
	|          |         |                               |              | 卷积水平步长生效                 |
	|          |         |19~16: 计算轮次 - 1            |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	|grp_conv0 | 0xA0/40 | 0: 进入组卷积模式             |      RW      | 仅当支持组卷积时, 写1生效        |
	|          |         |31~1: (特征图)每组的数据量     |      RW      | 仅当支持组卷积时, 该字段可用     |
	--------------------------------------------------------------------------------------------------------
	|grp_conv1 | 0xA4/41 |15~0: 每组的通道数/核数 - 1    |      RW      | 仅当支持组卷积时, 该字段可用     |
	|          |         |31~16: 分组数 - 1              |              | 仅当支持组卷积时, 该字段可用     |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg0 | 0xC0/48 |31~0: 输入特征图基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg1 | 0xC4/49 |31~0: 输出特征图基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg2 | 0xC8/50 |15~0: 输入特征图宽度 - 1       |      RW      |                                  |
	|          |         |31~16: 输入特征图通道数 - 1    |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg3 | 0xCC/51 |23~0: 输入特征图大小 - 1       |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg4 | 0xD0/52 |2~0: 左部外填充数              |      RW      | 仅在支持外填充时, 写非0值生效    |
	|          |         |5~3: 上部外填充数              |      RW      | 仅在支持外填充时, 写非0值生效    |
	|          |         |8~6: 左右内填充数              |      RW      | 仅在支持内填充时, 写非0值生效    |
	|          |         |11~9: 上下内填充数             |      RW      | 仅在支持内填充时, 写非0值生效    |
	|          |         |31~16: 扩展后特征图的垂直边界  |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg5 | 0xD4/53 |1~0: 输出特征图数据大小类型    |      RW      |                                  |
	|          |         |16~2: 输出特征图宽度 - 1       |      RW      |                                  |
	|          |         |31~17: 输出特征图高度 - 1      |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	|krn_cfg0  |0x100/64 |31~0: 卷积核权重基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|krn_cfg1  |0x104/65 |3~0: 卷积核形状                |      RW      |                                  |
	|          |         |7~4: 卷积核膨胀量              |      RW      | 仅当支持卷积核膨胀时, 写非0值生效|
	|          |         |15~8: (膨胀后)卷积核边长 - 1   |      RW      |                                  |
	|          |         |31~16: 每个核组的通道组数 - 1  |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|krn_cfg2  |0x108/66 |15~0: 核数 - 1                 |      RW      |                                  |
	|          |         |31~16: 核组个数 - 1            |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|krn_cfg3  |0x10C/67 |7~0: 权重块最大宽度            |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	********************************************************************************************************
	--------------------------------------------------------------------------------------------------------
	|buf_cfg0  |0x140/80 |15~0: 分配给特征图缓存的Bank数 |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|buf_cfg1  |0x144/81 |3~0: 每个表面行的表面个数类型  |      RW      |                                  |
	|          |         |31~16: 可缓存的表面行数 - 1    |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|buf_cfg2  |0x148/82 |3~0: 每个权重块的表面个数的类型|      RW      |                                  |
	|          |         |23~8: 可缓存的通道组数 - 1     |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|buf_cfg3  |0x14C/83 |15~0: 每个输出特征图表面行的   |      RW      |                                  |
	|          |         |      中间结果项数 - 1         |              |                                  |
	|          |         |23~16: 可缓存的中间结果行数 - 1|      RW      |                                  |
	--------------------------------------------------------------------------------------------------------

注意：
无

协议:
AXI-Lite SLAVE
BLK CTRL

作者: 陈家耀
日期: 2025/11/29
********************************************************************/


module reg_if_for_generic_conv #(
	parameter INT8_SUPPORTED = 1'b0, // 是否支持INT8
	parameter INT16_SUPPORTED = 1'b1, // 是否支持INT16
	parameter FP16_SUPPORTED = 1'b1, // 是否支持FP16
	parameter LARGE_V_STRD_SUPPORTED = 1'b1, // 是否支持>1的卷积垂直步长
	parameter LARGE_H_STRD_SUPPORTED = 1'b1, // 是否支持>1的卷积水平步长
	parameter GRP_CONV_SUPPORTED = 1'b0, // 是否支持组卷积
	parameter EXT_PADDING_SUPPORTED = 1'b1, // 是否支持外填充
	parameter INNER_PADDING_SUPPORTED = 1'b0, // 是否支持内填充
	parameter KERNAL_DILATION_SUPPORTED = 1'b0, // 是否支持卷积核膨胀
	parameter EN_PERF_MON = 1'b1, // 是否支持性能监测
	parameter integer ACCELERATOR_ID = 0, // 加速器ID(0~3)
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 1, // 最大的计算轮次(1~16)
	parameter integer MM2S_STREAM_DATA_WIDTH = 32, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16, // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 4096, // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
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
	
	// 使能信号
	output wire en_mac_array, // 使能乘加阵列
	output wire en_packer, // 使能打包器
	
	// 运行时参数
	// [计算参数]
	output wire[1:0] calfmt, // 运算数据格式
	output wire[2:0] conv_vertical_stride, // 卷积垂直步长 - 1
	output wire[2:0] conv_horizontal_stride, // 卷积水平步长 - 1
	output wire[3:0] cal_round, // 计算轮次 - 1
	// [组卷积模式]
	output wire is_grp_conv_mode, // 是否处于组卷积模式
	output wire[15:0] group_n, // 分组数 - 1
	output wire[15:0] n_foreach_group, // 每组的通道数/核数 - 1
	output wire[31:0] data_size_foreach_group, // (特征图)每组的数据量
	// [特征图参数]
	output wire[31:0] ifmap_baseaddr, // 输入特征图基地址
	output wire[31:0] ofmap_baseaddr, // 输出特征图基地址
	output wire[15:0] ifmap_w, // 输入特征图宽度 - 1
	output wire[23:0] ifmap_size, // 输入特征图大小 - 1
	output wire[15:0] fmap_chn_n, // 特征图通道数 - 1
	output wire[15:0] fmap_ext_i_bottom, // 扩展后特征图的垂直边界
	output wire[2:0] external_padding_left, // 左部外填充数
	output wire[2:0] external_padding_top, // 上部外填充数
	output wire[2:0] inner_padding_left_right, // 左右内填充数
	output wire[2:0] inner_padding_top_bottom, // 上下内填充数
	output wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	output wire[15:0] ofmap_h, // 输出特征图高度 - 1
	output wire[1:0] ofmap_data_type, // 输出特征图数据大小类型
	// [卷积核参数]
	output wire[31:0] kernal_wgt_baseaddr, // 卷积核权重基地址
	output wire[2:0] kernal_shape, // 卷积核形状
	output wire[3:0] kernal_dilation_hzt_n, // 水平膨胀量
	output wire[4:0] kernal_w_dilated, // (膨胀后)卷积核宽度 - 1
	output wire[3:0] kernal_dilation_vtc_n, // 垂直膨胀量
	output wire[4:0] kernal_h_dilated, // (膨胀后)卷积核高度 - 1
	output wire[15:0] kernal_chn_n, // 通道数 - 1
	output wire[15:0] cgrpn_foreach_kernal_set, // 每个核组的通道组数 - 1
	output wire[15:0] kernal_num_n, // 核数 - 1
	output wire[15:0] kernal_set_n, // 核组个数 - 1
	output wire[5:0] max_wgtblk_w, // 权重块最大宽度
	// [缓存参数]
	output wire[7:0] fmbufbankn, // 分配给特征图缓存的Bank数
	output wire[3:0] fmbufcoln, // 每个表面行的表面个数类型
	output wire[9:0] fmbufrown, // 可缓存的表面行数 - 1
	output wire[2:0] sfc_n_each_wgtblk, // 每个权重块的表面个数的类型
	output wire[7:0] kbufgrpn, // 可缓存的通道组数 - 1
	output wire[15:0] mid_res_item_n_foreach_row, // 每个输出特征图表面行的中间结果项数 - 1
	output wire[3:0] mid_res_buf_row_n_bufferable, // 可缓存行数 - 1
	
	// 块级控制
	// [卷积核权重访问请求生成单元]
	output wire kernal_access_blk_start,
	input wire kernal_access_blk_idle,
	input wire kernal_access_blk_done,
	// [特征图表面行访问请求生成单元]
	output wire fmap_access_blk_start,
	input wire fmap_access_blk_idle,
	input wire fmap_access_blk_done,
	// [最终结果传输请求生成单元]
	output wire fnl_res_trans_blk_start,
	input wire fnl_res_trans_blk_idle,
	input wire fnl_res_trans_blk_done,
	
	// DMA命令完成指示
	input wire mm2s_0_cmd_done, // 0号MM2S通道命令完成(指示)
	input wire mm2s_1_cmd_done, // 1号MM2S通道命令完成(指示)
	input wire s2mm_cmd_done // S2MM通道命令完成(指示)
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
	
	/** 内部配置 **/
	localparam integer REGS_N = 128; // 寄存器总数
	
	/** 常量 **/
	// 寄存器配置状态独热码编号
	localparam integer REG_CFG_STS_ADDR = 0; // 状态:地址阶段
	localparam integer REG_CFG_STS_RW_REG = 1; // 状态:读/写寄存器
	localparam integer REG_CFG_STS_RW_RESP = 2; // 状态:读/写响应
	// 运算数据格式
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	
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
	|          |         |31~30: 加速器ID                |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  info0   | 0x08/2  |7~0: 核并行数 - 1              |      RO      |                                  |
	|          |         |15~8: 通道并行数 - 1           |              |                                  |
	|          |         |23~16: 最大的计算轮次 - 1      |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  info1   | 0x0C/3  |7~0: MM2S通道数据位宽 - 1      |      RO      |                                  |
	|          |         |15~8: S2MM通道数据位宽 - 1     |              |                                  |
	|          |         |31~16: 物理缓存BANK数 - 1      |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  info2   | 0x10/4  |15~0: 物理缓存BANK深度 - 1     |      RO      |                                  |
	|          |         |31~16: 特征图缓存              |              |                                  |
	|          |         |       最大表面行数 - 1        |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  info3   | 0x14/5  |15~0: 中间结果缓存BANK数 - 1   |      RO      |                                  |
	|          |         |31~16: 中间结果缓存BANK深度 - 1|              |                                  |
	--------------------------------------------------------------------------------------------------------
	**/
	wire[31:0] version_r; // 版本号
	wire[29:0] accelerator_type_r; // 加速器类型
	wire[1:0] accelerator_id_r; // 加速器ID
	wire[7:0] atomic_k_r; // 核并行数 - 1
	wire[7:0] atomic_c_r; // 通道并行数 - 1
	wire[7:0] max_cal_round_n_r; // 最大的计算轮次 - 1
	wire[7:0] mm2s_data_width_r; // MM2S通道数据位宽 - 1
	wire[7:0] s2mm_data_width_r; // S2MM通道数据位宽 - 1
	wire[15:0] phy_buf_bank_n_r; // 物理缓存BANK数 - 1
	wire[15:0] phy_buf_bank_depth_r; // 物理缓存BANK深度 - 1
	wire[15:0] max_fmbuf_rown_r; // 特征图缓存最大表面行数 - 1
	wire[15:0] mid_res_buf_bank_n_r; // 中间结果缓存BANK数 - 1
	wire[15:0] mid_res_buf_bank_depth_r; // 中间结果缓存BANK深度 - 1
	
	assign version_r = {4'd7, 4'd2, 4'd1, 4'd1, 4'd5, 4'd2, 4'd0, 4'd2}; // 2025.11.27
	assign accelerator_type_r = {5'd26, 5'd26, 5'd21, 5'd13, 5'd14, 5'd2}; // "conv"
	assign accelerator_id_r = ACCELERATOR_ID;
	assign atomic_k_r = ATOMIC_K - 1;
	assign atomic_c_r = ATOMIC_C - 1;
	assign max_cal_round_n_r = MAX_CAL_ROUND - 1;
	assign mm2s_data_width_r = MM2S_STREAM_DATA_WIDTH - 1;
	assign s2mm_data_width_r = S2MM_STREAM_DATA_WIDTH - 1;
	assign phy_buf_bank_n_r = CBUF_BANK_N - 1;
	assign phy_buf_bank_depth_r = CBUF_DEPTH_FOREACH_BANK - 1;
	assign max_fmbuf_rown_r = MAX_FMBUF_ROWN - 1;
	assign mid_res_buf_bank_n_r = RBUF_BANK_N - 1;
	assign mid_res_buf_bank_depth_r = RBUF_DEPTH - 1;
	
	/**
	寄存器(ctrl0)
	
	--------------------------------------------------------------------------------------------------------
	|  ctrl0   | 0x40/16 | 0: 使能计算子系统             |      RW      |                                  |
	|          |         | 1: 使能性能监测计数器         |      RW      | 仅当支持性能监测时, 写1生效      |
	|          |         | 8: 启动卷积核权重             |      WO      | 向该位写1会向卷积核权重          |
	|          |         |    访问请求生成单元           |              | 访问请求生成单元发送start信号    |
	|          |         | 9: 启动特征图表面行           |      WO      | 向该位写1会向特征图表面行        |
	|          |         |    访问请求生成单元           |              | 访问请求生成单元发送start信号    |
	|          |         |10: 启动最终结果               |      WO      | 向该位写1会向最终结果            |
	|          |         |    传输请求生成单元           |              | 传输请求生成单元发送start信号    |
	--------------------------------------------------------------------------------------------------------
	**/
	reg en_cal_sub_sys_r; // 使能计算子系统
	reg en_pm_cnt_r; // 使能性能监测计数器
	reg kernal_access_blk_start_r; // 启动卷积核权重访问请求生成单元(指示)
	reg fmap_access_blk_start_r; // 启动特征图表面行访问请求生成单元(指示)
	reg fnl_res_trans_blk_start_r; // 启动最终结果传输请求生成单元(指示)
	
	assign en_mac_array = en_cal_sub_sys_r;
	assign en_packer = en_cal_sub_sys_r;
	
	assign kernal_access_blk_start = kernal_access_blk_start_r;
	assign fmap_access_blk_start = fmap_access_blk_start_r;
	assign fnl_res_trans_blk_start = fnl_res_trans_blk_start_r;
	
	// 使能计算子系统
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			en_cal_sub_sys_r <= 1'b0;
		else if(regs_en & regs_wen & (regs_addr == 16))
			en_cal_sub_sys_r <= # SIM_DELAY regs_din[0];
	end
	
	// 使能性能监测计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			en_pm_cnt_r <= 1'b0;
		else if(regs_en & regs_wen & (regs_addr == 16) & ((~regs_din[1]) | EN_PERF_MON))
			en_pm_cnt_r <= # SIM_DELAY regs_din[1];
	end
	
	// 启动卷积核权重访问请求生成单元(指示), 启动特征图表面行访问请求生成单元(指示), 启动最终结果传输请求生成单元(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{fnl_res_trans_blk_start_r, fmap_access_blk_start_r, kernal_access_blk_start_r} <= 3'b000;
		else
			{fnl_res_trans_blk_start_r, fmap_access_blk_start_r, kernal_access_blk_start_r} <= # SIM_DELAY 
				{3{regs_en & regs_wen & (regs_addr == 16)}} & regs_din[10:8];
	end
	
	/**
	寄存器(sts0, sts1, sts2, sts3, sts4)
	
	--------------------------------------------------------------------------------------------------------
	|  sts0    | 0x60/24 | 0: 卷积核权重                 |      RO      |                                  |
	|          |         |    访问请求生成单元空闲标志   |              |                                  |
	|          |         | 1: 特征图表面行               |      RO      |                                  |
	|          |         |    访问请求生成单元空闲标志   |              |                                  |
	|          |         | 2: 最终结果                   |      RO      |                                  |
	|          |         |    传输请求生成单元空闲标志   |              |                                  |
	--------------------------------------------------------------------------------------------------------
	|  sts1    | 0x64/25 |31~0: 0号MM2S通道完成的命令数  |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	|  sts2    | 0x68/26 |31~0: 1号MM2S通道完成的命令数  |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	|  sts3    | 0x6C/27 |31~0: S2MM通道完成的命令数     |      WC      |                                  |
	--------------------------------------------------------------------------------------------------------
	|  sts4    | 0x70/28 |31~0: 性能监测计数器           |      WC      | 仅当支持性能监测时, 该字段可用   |
	--------------------------------------------------------------------------------------------------------
	**/
	wire kernal_access_blk_idle_r; // 卷积核权重访问请求生成单元空闲标志
	wire fmap_access_blk_idle_r; // 特征图表面行访问请求生成单元空闲标志
	wire fnl_res_trans_blk_idle_r; // 最终结果传输请求生成单元空闲标志
	reg[31:0] dma_mm2s_0_fns_cmd_n_r; // 0号MM2S通道完成的命令数
	reg[31:0] dma_mm2s_1_fns_cmd_n_r; // 1号MM2S通道完成的命令数
	reg[31:0] dma_s2mm_fns_cmd_n_r; // S2MM通道完成的命令数
	reg[31:0] pm_cnt_r; // 性能监测计数器
	
	assign kernal_access_blk_idle_r = kernal_access_blk_idle;
	assign fmap_access_blk_idle_r = fmap_access_blk_idle;
	assign fnl_res_trans_blk_idle_r = fnl_res_trans_blk_idle;
	
	// 0号MM2S通道完成的命令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dma_mm2s_0_fns_cmd_n_r <= 32'd0;
		else if(
			mm2s_0_cmd_done | 
			(regs_en & regs_wen & (regs_addr == 25))
		)
			dma_mm2s_0_fns_cmd_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 25)) ? 
					32'd0:
					(dma_mm2s_0_fns_cmd_n_r + 1'b1);
	end
	
	// 1号MM2S通道完成的命令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dma_mm2s_1_fns_cmd_n_r <= 32'd0;
		else if(
			mm2s_1_cmd_done | 
			(regs_en & regs_wen & (regs_addr == 26))
		)
			dma_mm2s_1_fns_cmd_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 26)) ? 
					32'd0:
					(dma_mm2s_1_fns_cmd_n_r + 1'b1);
	end
	
	// S2MM通道完成的命令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dma_s2mm_fns_cmd_n_r <= 32'd0;
		else if(
			s2mm_cmd_done | 
			(regs_en & regs_wen & (regs_addr == 27))
		)
			dma_s2mm_fns_cmd_n_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 27)) ? 
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
				(regs_en & regs_wen & (regs_addr == 28))
			)
		)
			pm_cnt_r <= # SIM_DELAY 
				(regs_en & regs_wen & (regs_addr == 28)) ? 
					32'd0:
					(pm_cnt_r + 1'b1);
	end
	
	/**
	寄存器(cal_cfg)
	
	--------------------------------------------------------------------------------------------------------
	| cal_cfg  | 0x80/32 |2~0: 运算数据格式              |      RW      | 在写入时, 仅对支持的             |
	|          |         |                               |              | 运算数据格式生效                 |
	|          |         |10~8: 卷积垂直步长 - 1         |      RW      | 在写入时, 仅对支持的             |
	|          |         |                               |              | 卷积垂直步长生效                 |
	|          |         |13~11: 卷积水平步长 - 1        |      RW      | 在写入时, 仅对支持的             |
	|          |         |                               |              | 卷积水平步长生效                 |
	|          |         |19~16: 计算轮次 - 1            |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	**/
	reg[2:0] calfmt_r; // 运算数据格式
	reg[2:0] conv_vertical_stride_r; // 卷积垂直步长 - 1
	reg[2:0] conv_horizontal_stride_r; // 卷积水平步长 - 1
	reg[3:0] cal_round_r; // 计算轮次 - 1
	
	assign calfmt = 
		({2{INT8_SUPPORTED & (calfmt_r[1:0] == CAL_FMT_INT8)}} & CAL_FMT_INT8) | 
		({2{INT16_SUPPORTED & (calfmt_r[1:0] == CAL_FMT_INT16)}} & CAL_FMT_INT16) | 
		({2{FP16_SUPPORTED & (calfmt_r[1:0] == CAL_FMT_FP16)}} & CAL_FMT_FP16);
	assign conv_vertical_stride = 
		LARGE_V_STRD_SUPPORTED ? 
			conv_vertical_stride_r:
			3'd0;
	assign conv_horizontal_stride = 
		LARGE_H_STRD_SUPPORTED ? 
			conv_horizontal_stride_r:
			3'd0;
	assign cal_round = cal_round_r;
	
	// 运算数据格式
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			calfmt_r <= 3'b111;
		else if(
			regs_en & regs_wen & (regs_addr == 32) & 
			(
				((regs_din[2:0] == (CAL_FMT_INT8 | 3'b000)) & INT8_SUPPORTED) | 
				((regs_din[2:0] == (CAL_FMT_INT16 | 3'b000)) & INT16_SUPPORTED) | 
				((regs_din[2:0] == (CAL_FMT_FP16 | 3'b000)) & FP16_SUPPORTED)
			)
		)
			calfmt_r <= # SIM_DELAY regs_din[2:0];
	end
	
	// 卷积垂直步长 - 1
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			conv_vertical_stride_r <= 3'd0;
		else if(
			regs_en & regs_wen & (regs_addr == 32) & 
			((regs_din[10:8] == 3'd0) | LARGE_V_STRD_SUPPORTED)
		)
			conv_vertical_stride_r <= # SIM_DELAY regs_din[10:8];
	end
	
	// 卷积水平步长 - 1
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			conv_horizontal_stride_r <= 3'd0;
		else if(
			regs_en & regs_wen & (regs_addr == 32) & 
			((regs_din[13:11] == 3'd0) | LARGE_H_STRD_SUPPORTED)
		)
			conv_horizontal_stride_r <= # SIM_DELAY regs_din[13:11];
	end
	
	// 计算轮次 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 32))
			cal_round_r <= # SIM_DELAY regs_din[19:16];
	end
	
	/**
	寄存器(grp_conv0, grp_conv1)
	
	--------------------------------------------------------------------------------------------------------
	|grp_conv0 | 0xA0/40 | 0: 进入组卷积模式             |      RW      | 仅当支持组卷积时, 写1生效        |
	|          |         |31~1: (特征图)每组的数据量     |      RW      | 仅当支持组卷积时, 该字段可用     |
	--------------------------------------------------------------------------------------------------------
	|grp_conv1 | 0xA4/41 |15~0: 每组的通道数/核数 - 1    |      RW      | 仅当支持组卷积时, 该字段可用     |
	|          |         |31~16: 分组数 - 1              |              | 仅当支持组卷积时, 该字段可用     |
	--------------------------------------------------------------------------------------------------------
	**/
	reg is_grp_conv_mode_r; // 进入组卷积模式
	reg[30:0] data_size_foreach_group_r; // (特征图)每组的数据量
	reg[15:0] n_foreach_group_r; // 每组的通道数/核数 - 1
	reg[15:0] group_n_r; // 分组数 - 1
	
	assign is_grp_conv_mode = GRP_CONV_SUPPORTED & is_grp_conv_mode_r;
	assign group_n = group_n_r;
	assign n_foreach_group = n_foreach_group_r;
	assign data_size_foreach_group = data_size_foreach_group_r | 32'h0000_0000;
	
	// 进入组卷积模式
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			is_grp_conv_mode_r <= 1'b0;
		else if(
			regs_en & regs_wen & (regs_addr == 40) & 
			((~regs_din[0]) | GRP_CONV_SUPPORTED)
		)
			is_grp_conv_mode_r <= # SIM_DELAY regs_din[0];
	end
	
	// (特征图)每组的数据量
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 40) & GRP_CONV_SUPPORTED)
			data_size_foreach_group_r <= # SIM_DELAY regs_din[31:1];
	end
	
	// 每组的通道数/核数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 41) & GRP_CONV_SUPPORTED)
			n_foreach_group_r <= # SIM_DELAY regs_din[15:0];
	end
	
	// 分组数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 41) & GRP_CONV_SUPPORTED)
			group_n_r <= # SIM_DELAY regs_din[31:16];
	end
	
	/**
	寄存器(fmap_cfg0, fmap_cfg1, fmap_cfg2, fmap_cfg3, fmap_cfg4, fmap_cfg5)
	
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg0 | 0xC0/48 |31~0: 输入特征图基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg1 | 0xC4/49 |31~0: 输出特征图基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg2 | 0xC8/50 |15~0: 输入特征图宽度 - 1       |      RW      |                                  |
	|          |         |31~16: 输入特征图通道数 - 1    |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg3 | 0xCC/51 |23~0: 输入特征图大小 - 1       |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg4 | 0xD0/52 |2~0: 左部外填充数              |      RW      | 仅在支持外填充时, 写非0值生效    |
	|          |         |5~3: 上部外填充数              |      RW      | 仅在支持外填充时, 写非0值生效    |
	|          |         |8~6: 左右内填充数              |      RW      | 仅在支持内填充时, 写非0值生效    |
	|          |         |11~9: 上下内填充数             |      RW      | 仅在支持内填充时, 写非0值生效    |
	|          |         |31~16: 扩展后特征图的垂直边界  |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|fmap_cfg5 | 0xD4/53 |1~0: 输出特征图数据大小类型    |      RW      |                                  |
	|          |         |16~2: 输出特征图宽度 - 1       |      RW      |                                  |
	|          |         |31~17: 输出特征图高度 - 1      |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	**/
	reg[31:0] ifmap_baseaddr_r; // 输入特征图基地址
	reg[31:0] ofmap_baseaddr_r; // 输出特征图基地址
	reg[15:0] ifmap_w_r; // 输入特征图宽度 - 1
	reg[15:0] fmap_chn_n_r; // 特征图通道数 - 1
	reg[23:0] ifmap_size_r; // 输入特征图大小 - 1
	reg[2:0] external_padding_left_r; // 左部外填充数
	reg[2:0] external_padding_top_r; // 上部外填充数
	reg[2:0] inner_padding_left_right_r; // 左右内填充数
	reg[2:0] inner_padding_top_bottom_r; // 上下内填充数
	reg[15:0] fmap_ext_i_bottom_r; // 扩展后特征图的垂直边界
	reg[1:0] ofmap_data_type_r; // 输出特征图数据大小类型
	reg[14:0] ofmap_w_r; // 输出特征图宽度 - 1
	reg[14:0] ofmap_h_r; // 输出特征图高度 - 1
	
	assign ifmap_baseaddr = ifmap_baseaddr_r;
	assign ofmap_baseaddr = ofmap_baseaddr_r;
	assign ifmap_w = ifmap_w_r;
	assign ifmap_size = ifmap_size_r;
	assign fmap_chn_n = fmap_chn_n_r;
	assign fmap_ext_i_bottom = fmap_ext_i_bottom_r;
	assign external_padding_left = 
		EXT_PADDING_SUPPORTED ? 
			external_padding_left_r:
			3'd0;
	assign external_padding_top = 
		EXT_PADDING_SUPPORTED ? 
			external_padding_top_r:
			3'd0;
	assign inner_padding_left_right = 
		INNER_PADDING_SUPPORTED ? 
			inner_padding_left_right_r:
			3'd0;
	assign inner_padding_top_bottom = 
		INNER_PADDING_SUPPORTED ? 
			inner_padding_top_bottom_r:
			3'd0;
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
	
	// 特征图通道数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 50))
			fmap_chn_n_r <= # SIM_DELAY regs_din[31:16];
	end
	
	// 输入特征图大小 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 51))
			ifmap_size_r <= # SIM_DELAY regs_din[23:0];
	end
	
	// 左部外填充数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			external_padding_left_r <= 3'd0;
		else if(
			regs_en & regs_wen & (regs_addr == 52) & 
			((regs_din[2:0] == 3'd0) | EXT_PADDING_SUPPORTED)
		)
			external_padding_left_r <= # SIM_DELAY regs_din[2:0];
	end
	
	// 上部外填充数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			external_padding_top_r <= 3'd0;
		else if(
			regs_en & regs_wen & (regs_addr == 52) & 
			((regs_din[5:3] == 3'd0) | EXT_PADDING_SUPPORTED)
		)
			external_padding_top_r <= # SIM_DELAY regs_din[5:3];
	end
	
	// 左右内填充数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			inner_padding_left_right_r <= 3'd0;
		else if(
			regs_en & regs_wen & (regs_addr == 52) & 
			((regs_din[8:6] == 3'd0) | INNER_PADDING_SUPPORTED)
		)
			inner_padding_left_right_r <= # SIM_DELAY regs_din[8:6];
	end
	
	// 上下内填充数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			inner_padding_top_bottom_r <= 3'd0;
		else if(
			regs_en & regs_wen & (regs_addr == 52) & 
			((regs_din[11:9] == 3'd0) | INNER_PADDING_SUPPORTED)
		)
			inner_padding_top_bottom_r <= # SIM_DELAY regs_din[11:9];
	end
	
	// 扩展后特征图的垂直边界
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 52))
			fmap_ext_i_bottom_r <= # SIM_DELAY regs_din[31:16];
	end
	
	// 输出特征图数据大小类型
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 53))
			ofmap_data_type_r <= # SIM_DELAY regs_din[1:0];
	end
	
	// 输出特征图宽度 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 53))
			ofmap_w_r <= # SIM_DELAY regs_din[16:2];
	end
	
	// 输出特征图高度 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 53))
			ofmap_h_r <= # SIM_DELAY regs_din[31:17];
	end
	
	/**
	寄存器(krn_cfg0, krn_cfg1, krn_cfg2, krn_cfg3)
	
	--------------------------------------------------------------------------------------------------------
	|krn_cfg0  |0x100/64 |31~0: 卷积核权重基地址         |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|krn_cfg1  |0x104/65 |3~0: 卷积核形状                |      RW      |                                  |
	|          |         |7~4: 卷积核膨胀量              |      RW      | 仅当支持卷积核膨胀时, 写非0值生效|
	|          |         |15~8: (膨胀后)卷积核边长 - 1   |      RW      |                                  |
	|          |         |31~16: 每个核组的通道组数 - 1  |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|krn_cfg2  |0x108/66 |15~0: 核数 - 1                 |      RW      |                                  |
	|          |         |31~16: 核组个数 - 1            |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|krn_cfg3  |0x10C/67 |7~0: 权重块最大宽度            |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	**/
	reg[31:0] kernal_wgt_baseaddr_r; // 卷积核权重基地址
	reg[3:0] kernal_shape_r; // 卷积核形状
	reg[3:0] kernal_dilation_n_r; // 膨胀量
	reg[7:0] kernal_len_dilated_r; // (膨胀后)卷积核边长 - 1
	reg[15:0] cgrpn_foreach_kernal_set_r; // 每个核组的通道组数 - 1
	reg[15:0] kernal_num_n_r; // 核数 - 1
	reg[15:0] kernal_set_n_r; // 核组个数 - 1
	reg[7:0] max_wgtblk_w_r; // 权重块最大宽度
	
	assign kernal_wgt_baseaddr = kernal_wgt_baseaddr_r;
	assign kernal_shape = kernal_shape_r;
	assign kernal_dilation_hzt_n = 
		KERNAL_DILATION_SUPPORTED ? 
			kernal_dilation_n_r:
			4'd0;
	assign kernal_w_dilated = kernal_len_dilated_r[4:0];
	assign kernal_dilation_vtc_n = 
		KERNAL_DILATION_SUPPORTED ? 
			kernal_dilation_n_r:
			4'd0;
	assign kernal_h_dilated = kernal_len_dilated_r[4:0];
	assign kernal_chn_n = fmap_chn_n_r; // 卷积核通道数 = 特征图通道数
	assign cgrpn_foreach_kernal_set = cgrpn_foreach_kernal_set_r;
	assign kernal_num_n = kernal_num_n_r;
	assign kernal_set_n = kernal_set_n_r;
	assign max_wgtblk_w = max_wgtblk_w_r[5:0];
	
	// 卷积核权重基地址
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 64))
			kernal_wgt_baseaddr_r <= # SIM_DELAY regs_din[31:0];
	end
	
	// 卷积核形状
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 65))
			kernal_shape_r <= # SIM_DELAY regs_din[3:0];
	end
	
	// 膨胀量
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_dilation_n_r <= 4'd0;
		else if(
			regs_en & regs_wen & (regs_addr == 65) & 
			((regs_din[7:4] == 4'd0) | KERNAL_DILATION_SUPPORTED)
		)
			kernal_dilation_n_r <= # SIM_DELAY regs_din[7:4];
	end
	
	// (膨胀后)卷积核边长 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 65))
			kernal_len_dilated_r <= # SIM_DELAY regs_din[15:8];
	end
	
	// 每个核组的通道组数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 65))
			cgrpn_foreach_kernal_set_r <= # SIM_DELAY regs_din[31:16];
	end
	
	// 核数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 66))
			kernal_num_n_r <= # SIM_DELAY regs_din[15:0];
	end
	
	// 核组个数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 66))
			kernal_set_n_r <= # SIM_DELAY regs_din[31:16];
	end
	
	// 权重块最大宽度
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 67))
			max_wgtblk_w_r <= # SIM_DELAY regs_din[7:0];
	end
	
	/**
	寄存器(buf_cfg0, buf_cfg1, buf_cfg2, buf_cfg3)
	
	--------------------------------------------------------------------------------------------------------
	|buf_cfg0  |0x140/80 |15~0: 分配给特征图缓存的Bank数 |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|buf_cfg1  |0x144/81 |3~0: 每个表面行的表面个数类型  |      RW      |                                  |
	|          |         |31~16: 可缓存的表面行数 - 1    |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|buf_cfg2  |0x148/82 |3~0: 每个权重块的表面个数的类型|      RW      |                                  |
	|          |         |23~8: 可缓存的通道组数 - 1     |      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	|buf_cfg3  |0x14C/83 |15~0: 每个输出特征图表面行的   |      RW      |                                  |
	|          |         |      中间结果项数 - 1         |              |                                  |
	|          |         |23~16: 可缓存的中间结果行数 - 1|      RW      |                                  |
	--------------------------------------------------------------------------------------------------------
	**/
	reg[15:0] fmbufbankn_r; // 分配给特征图缓存的Bank数
	reg[3:0] fmbufcoln_r; // 每个表面行的表面个数类型
	reg[15:0] fmbufrown_r; // 可缓存的表面行数 - 1
	reg[3:0] sfc_n_each_wgtblk_r; // 每个权重块的表面个数的类型
	reg[15:0] kbufgrpn_r; // 可缓存的通道组数 - 1
	reg[15:0] mid_res_item_n_foreach_row_r; // 每个输出特征图表面行的中间结果项数 - 1
	reg[7:0] mid_res_buf_row_n_bufferable_r; // 可缓存行数 - 1
	
	assign fmbufbankn = fmbufbankn_r[7:0];
	assign fmbufcoln = fmbufcoln_r;
	assign fmbufrown = fmbufrown_r[9:0];
	assign sfc_n_each_wgtblk = sfc_n_each_wgtblk_r[2:0];
	assign kbufgrpn = kbufgrpn_r[7:0];
	assign mid_res_item_n_foreach_row = mid_res_item_n_foreach_row_r;
	assign mid_res_buf_row_n_bufferable = mid_res_buf_row_n_bufferable_r[3:0];
	
	// 分配给特征图缓存的Bank数
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 80))
			fmbufbankn_r <= # SIM_DELAY regs_din[15:0];
	end
	
	// 每个表面行的表面个数类型
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 81))
			fmbufcoln_r <= # SIM_DELAY regs_din[3:0];
	end
	
	// 可缓存的表面行数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 81))
			fmbufrown_r <= # SIM_DELAY regs_din[31:16];
	end
	
	// 每个权重块的表面个数的类型
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 82))
			sfc_n_each_wgtblk_r <= # SIM_DELAY regs_din[3:0];
	end
	
	// 可缓存的通道组数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 82))
			kbufgrpn_r <= # SIM_DELAY regs_din[23:8];
	end
	
	// 每个输出特征图表面行的中间结果项数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 83))
			mid_res_item_n_foreach_row_r <= # SIM_DELAY regs_din[15:0];
	end
	
	// 可缓存行数 - 1
	always @(posedge aclk)
	begin
		if(regs_en & regs_wen & (regs_addr == 83))
			mid_res_buf_row_n_bufferable_r <= # SIM_DELAY regs_din[23:16];
	end
	
	/** 寄存器读结果 **/
	always @(posedge aclk)
	begin
		if(regs_en & (~is_write))
		begin
			case(regs_addr)
				0: regs_dout <= # SIM_DELAY {version_r[31:0]};
				1: regs_dout <= # SIM_DELAY {accelerator_id_r[1:0], accelerator_type_r[29:0]};
				2: regs_dout <= # SIM_DELAY {8'h00, max_cal_round_n_r[7:0], atomic_c_r[7:0], atomic_k_r[7:0]};
				3: regs_dout <= # SIM_DELAY {phy_buf_bank_n_r[15:0], s2mm_data_width_r[7:0], mm2s_data_width_r[7:0]};
				4: regs_dout <= # SIM_DELAY {max_fmbuf_rown_r[15:0], phy_buf_bank_depth_r[15:0]};
				5: regs_dout <= # SIM_DELAY {mid_res_buf_bank_depth_r[15:0], mid_res_buf_bank_n_r[15:0]};
				
				16: regs_dout <= # SIM_DELAY {30'd0, en_pm_cnt_r, en_cal_sub_sys_r};
				
				24: regs_dout <= # SIM_DELAY {29'd0, fnl_res_trans_blk_idle_r, fmap_access_blk_idle_r, kernal_access_blk_idle_r};
				25: regs_dout <= # SIM_DELAY {dma_mm2s_0_fns_cmd_n_r[31:0]};
				26: regs_dout <= # SIM_DELAY {dma_mm2s_1_fns_cmd_n_r[31:0]};
				27: regs_dout <= # SIM_DELAY {dma_s2mm_fns_cmd_n_r[31:0]};
				28: regs_dout <= # SIM_DELAY {pm_cnt_r[31:0]};
				
				32: regs_dout <= # SIM_DELAY {
					12'd0, cal_round_r[3:0], 2'b00, conv_horizontal_stride_r[2:0], conv_vertical_stride_r[2:0], 5'd0, calfmt_r[2:0]
				};
				
				40: regs_dout <= # SIM_DELAY {data_size_foreach_group_r[30:0], is_grp_conv_mode_r};
				41: regs_dout <= # SIM_DELAY {group_n_r[15:0], n_foreach_group_r[15:0]};
				
				48: regs_dout <= # SIM_DELAY {ifmap_baseaddr_r[31:0]};
				49: regs_dout <= # SIM_DELAY {ofmap_baseaddr_r[31:0]};
				50: regs_dout <= # SIM_DELAY {fmap_chn_n_r[15:0], ifmap_w_r[15:0]};
				51: regs_dout <= # SIM_DELAY {8'h00, ifmap_size_r[23:0]};
				52: regs_dout <= # SIM_DELAY {
					fmap_ext_i_bottom_r[15:0], 4'd0,
					inner_padding_top_bottom_r[2:0], inner_padding_left_right_r[2:0],
					external_padding_top_r[2:0], external_padding_left_r[2:0]
				};
				53: regs_dout <= # SIM_DELAY {ofmap_h_r[14:0], ofmap_w_r[14:0], ofmap_data_type_r[1:0]};
				
				64: regs_dout <= # SIM_DELAY {kernal_wgt_baseaddr_r[31:0]};
				65: regs_dout <= # SIM_DELAY {
					cgrpn_foreach_kernal_set_r[15:0], kernal_len_dilated_r[7:0],
					kernal_dilation_n_r[3:0], kernal_shape_r[3:0]
				};
				66: regs_dout <= # SIM_DELAY {kernal_set_n_r[15:0], kernal_num_n_r[15:0]};
				67: regs_dout <= # SIM_DELAY {24'd0, max_wgtblk_w_r[7:0]};
				
				80: regs_dout <= # SIM_DELAY {16'd0, fmbufbankn_r[15:0]};
				81: regs_dout <= # SIM_DELAY {fmbufrown_r[15:0], 12'h000, fmbufcoln_r[3:0]};
				82: regs_dout <= # SIM_DELAY {8'h00, kbufgrpn_r[15:0], 4'h0, sfc_n_each_wgtblk_r[3:0]};
				83: regs_dout <= # SIM_DELAY {8'h00, mid_res_buf_row_n_bufferable_r[7:0], mid_res_item_n_foreach_row_r[15:0]};
				
				default: regs_dout <= # SIM_DELAY 32'h0000_0000;
			endcase
		end
	end
	
endmodule
