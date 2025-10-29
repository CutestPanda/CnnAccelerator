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


/********************************************************************
本模块: 卷积数据枢纽

描述:
1.特征图表面行缓存
接受访问请求、在逻辑缓存中检索表面行、置换原表面行、发送DMA命令、加载新表面行、从逻辑缓存获取表面行数据
访问请求分为正常和重置缓存两种
缓存单位为特征图表面行
特征图数据必须先加载到逻辑缓存中才可被获取, 而无法直接从外部存储器得到

2.卷积核权重块缓存
接受访问请求、检查权重块是否已缓存、置换交换区通道组、发送DMA命令、加载新的权重数据、从逻辑缓存获取权重数据
访问请求分为正常和重置缓存两种
缓存单位为卷积核通道组
卷积核权重数据必须先加载到逻辑缓存中才可被获取, 而无法直接从外部存储器得到

注意：
实际表面行号映射表MEM读延迟 = 1clk, 缓存行号映射表MEM读延迟 = 1clk, 物理缓存MEM读延迟 = 1clk
仿真时应对实际表面行号映射表MEM和缓存行号映射表MEM进行初始化, 但在实际运行时是不需要的

若卷积核权重块缓存处于组卷积模式, 则必须保证(物理)卷积核缓存可存下整个核组

协议:
AXIS MASTER/SLAVE
MEM MASTER

作者: 陈家耀
日期: 2025/10/16
********************************************************************/


module conv_data_hub #(
	parameter integer STREAM_DATA_WIDTH = 32, // DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer CBUF_BANK_N = 16, // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 4096, // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer FM_RD_REQ_PRE_ACPT_N = 4, // 可提前接受的特征图读请求个数(1 | 2 | 4 | 8 | 16)
	parameter integer KWGTBLK_RD_REQ_PRE_ACPT_N = 4, // 可提前接受的卷积核权重块读请求个数(1 | 2 | 4 | 8 | 16)
	parameter integer MAX_FMBUF_ROWN = 512, // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer LG_FMBUF_BUFFER_RID_WIDTH = 9, // 特征图缓存的缓存行号的位宽(3~10, 应为clogb2(MAX_FMBUF_ROWN))
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	input wire aclken,
	
	// 运行时参数
	// [特征图缓存]
	input wire[3:0] fmbufcoln, // 每个表面行的表面个数类型
	input wire[9:0] fmbufrown, // 可缓存的表面行数 - 1
	// [卷积核缓存]
	input wire grp_conv_buf_mode, // 是否处于组卷积缓存模式
	input wire[2:0] kbufgrpsz, // 每个通道组的权重块个数的类型
	// 说明: 仅当"处于组卷积缓存模式"时可用
	input wire[2:0] sfc_n_each_wgtblk, // 每个权重块的表面个数的类型
	// 说明: 仅当"不处于组卷积缓存模式"时可用
	input wire[7:0] kbufgrpn, // 可缓存的通道组数 - 1
	// [物理缓存]
	input wire[7:0] fmbufbankn, // 分配给特征图缓存的Bank数
	
	// 特征图表面行读请求(AXIS从机)
	/*
	请求格式 -> 
		{
			保留(6bit),
			是否重置缓存(1bit),
			实际表面行号(12bit),
			起始表面编号(12bit),
			待读取的表面个数 - 1(12bit),
			表面行基地址(32bit),
			表面行有效字节数(24bit),
			每个表面的有效数据个数 - 1(5bit)
		}
	*/
	input wire[103:0] s_fm_rd_req_axis_data,
	input wire s_fm_rd_req_axis_valid,
	output wire s_fm_rd_req_axis_ready,
	
	// 卷积核权重块读请求(AXIS从机)
	/*
	请求格式 -> 
		正常模式:
		{
			保留(6bit),
			是否重置缓存(1'b0)(1bit),
			实际通道组号(10bit),
			权重块编号(7bit),
			起始表面编号(7bit),
			待读取的表面个数 - 1(5bit),
			卷积核通道组基地址(32bit),
			卷积核通道组有效字节数(24bit),
			每个权重块的表面个数 - 1(7bit),
			每个表面的有效数据个数 - 1(5bit)
		}
		
		重置缓存:
		{
			保留(6bit),
			是否重置缓存(1'b1)(1bit),
			卷积核核组实际通道组数 - 1(10bit),
			通道组号偏移(10bit),
			保留(77bit)
		}
	*/
	input wire[103:0] s_kwgtblk_rd_req_axis_data,
	input wire s_kwgtblk_rd_req_axis_valid,
	output wire s_kwgtblk_rd_req_axis_ready,
	
	// 特征图表面行数据输出(AXIS主机)
	output wire[ATOMIC_C*2*8-1:0] m_fm_fout_axis_data,
	output wire m_fm_fout_axis_last, // 标志本次读请求的最后1个表面
	output wire m_fm_fout_axis_valid,
	input wire m_fm_fout_axis_ready,
	
	// 卷积核权重块数据输出(AXIS主机)
	output wire[ATOMIC_C*2*8-1:0] m_kout_wgtblk_axis_data,
	output wire m_kout_wgtblk_axis_last, // 标志本次读请求的最后1个表面
	output wire m_kout_wgtblk_axis_valid,
	input wire m_kout_wgtblk_axis_ready,
	
	// DMA(MM2S方向)命令流#0(AXIS主机)
	output wire[55:0] m0_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m0_dma_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m0_dma_cmd_axis_last, // 帧尾标志
	output wire m0_dma_cmd_axis_valid,
	input wire m0_dma_cmd_axis_ready,
	// DMA(MM2S方向)数据流#0(AXIS从机)
	input wire[STREAM_DATA_WIDTH-1:0] s0_dma_strm_axis_data,
	input wire[STREAM_DATA_WIDTH/8-1:0] s0_dma_strm_axis_keep,
	input wire s0_dma_strm_axis_last,
	input wire s0_dma_strm_axis_valid,
	output wire s0_dma_strm_axis_ready,
	
	// DMA(MM2S方向)命令流#1(AXIS主机)
	output wire[55:0] m1_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m1_dma_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m1_dma_cmd_axis_last, // 帧尾标志
	output wire m1_dma_cmd_axis_valid,
	input wire m1_dma_cmd_axis_ready,
	// DMA(MM2S方向)数据流#1(AXIS从机)
	input wire[STREAM_DATA_WIDTH-1:0] s1_dma_strm_axis_data,
	input wire[STREAM_DATA_WIDTH/8-1:0] s1_dma_strm_axis_keep,
	input wire s1_dma_strm_axis_last,
	input wire s1_dma_strm_axis_valid,
	output wire s1_dma_strm_axis_ready,
	
	// 实际表面行号映射表MEM主接口
	// 说明: 实际表面行号 ----映射----> 缓存行号
	output wire actual_rid_mp_tb_mem_clk,
	// [写端口]
	output wire actual_rid_mp_tb_mem_wen_a,
	output wire[11:0] actual_rid_mp_tb_mem_addr_a,
	output wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_din_a,
	// [读端口]
	output wire actual_rid_mp_tb_mem_ren_b,
	output wire[11:0] actual_rid_mp_tb_mem_addr_b,
	input wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_dout_b,
	
	// 缓存行号映射表MEM主接口
	// 说明: 缓存行号 ----映射----> 实际表面行号
	output wire buffer_rid_mp_tb_mem_clk,
	// [写端口]
	output wire buffer_rid_mp_tb_mem_wen_a,
	output wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_a,
	output wire[11:0] buffer_rid_mp_tb_mem_din_a,
	// [读端口]
	output wire buffer_rid_mp_tb_mem_ren_b,
	output wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_b,
	input wire[11:0] buffer_rid_mp_tb_mem_dout_b,
	
	// 物理缓存的MEM主接口
	output wire phy_conv_buf_mem_clk_a,
	output wire[CBUF_BANK_N-1:0] phy_conv_buf_mem_en_a,
	output wire[CBUF_BANK_N*ATOMIC_C*2-1:0] phy_conv_buf_mem_wen_a,
	output wire[CBUF_BANK_N*16-1:0] phy_conv_buf_mem_addr_a,
	output wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_din_a,
	input wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_dout_a
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
	
	// 优先编码器
	// 说明: 编号越小的请求优先级越高
	function [3:0] pri_encode(input [15:0] encode_in);
	begin
		if(encode_in[0])
			pri_encode = 4'd0;
		else if(encode_in[1])
			pri_encode = 4'd1;
		else if(encode_in[2])
			pri_encode = 4'd2;
		else if(encode_in[3])
			pri_encode = 4'd3;
		else if(encode_in[4])
			pri_encode = 4'd4;
		else if(encode_in[5])
			pri_encode = 4'd5;
		else if(encode_in[6])
			pri_encode = 4'd6;
		else if(encode_in[7])
			pri_encode = 4'd7;
		else if(encode_in[8])
			pri_encode = 4'd8;
		else if(encode_in[9])
			pri_encode = 4'd9;
		else if(encode_in[10])
			pri_encode = 4'd10;
		else if(encode_in[11])
			pri_encode = 4'd11;
		else if(encode_in[12])
			pri_encode = 4'd12;
		else if(encode_in[13])
			pri_encode = 4'd13;
		else if(encode_in[14])
			pri_encode = 4'd14;
		else
			pri_encode = 4'd15;
	end
	endfunction
	
	/** 常量 **/
	// 每个通道组的权重块个数的类型编码
	localparam KBUFGRPSZ_1 = 3'b000; // 1x1
	localparam KBUFGRPSZ_9 = 3'b001; // 3x3
	localparam KBUFGRPSZ_25 = 3'b010; // 5x5
	localparam KBUFGRPSZ_49 = 3'b011; // 7x7
	localparam KBUFGRPSZ_81 = 3'b100; // 9x9
	localparam KBUFGRPSZ_121 = 3'b101; // 11x11
	// 特征图表面行读请求各字段的起始索引
	localparam integer FM_RD_REQ_TO_RST_BUF_FLAG_SID = 97; // 索引: 是否重置缓存
	localparam integer FM_RD_REQ_ACTUAL_SFC_RID_SID = 85; // 索引: 实际表面行号
	localparam integer FM_RD_REQ_ORG_SFC_ID_SID = 73; // 索引: 起始表面编号
	localparam integer FM_RD_REQ_SFC_N_SID = 61; // 索引: 待读取的表面个数 - 1
	localparam integer FM_RD_REQ_SFC_ROW_BASEADDR_SID = 29; // 索引: 表面行基地址
	localparam integer FM_RD_REQ_SFC_ROW_LEN_SID = 5; // 索引: 表面行有效字节数
	localparam integer FM_RD_REQ_SFC_VLD_DATA_N_SID = 0; // 索引: 每个表面的有效数据个数 - 1
	// 卷积核权重块读请求各字段的起始索引
	localparam integer KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID = 97; // 索引: 是否重置缓存
	localparam integer KWGTBLK_RD_REQ_CGRPN_SID = 87; // 索引: 卷积核核组实际通道组数 - 1
	localparam integer KWGTBLK_RD_REQ_CGRP_ID_OFS = 77; // 索引: 通道组号偏移
	localparam integer KWGTBLK_RD_REQ_ACTUAL_CGRPID_SID = 87; // 索引: 实际通道组号
	localparam integer KWGTBLK_RD_REQ_WGTBLK_ID_SID = 80; // 索引: 权重块编号
	localparam integer KWGTBLK_RD_REQ_ORG_SFC_ID_SID = 73; // 索引: 起始表面编号
	localparam integer KWGTBLK_RD_REQ_SFC_N_SID = 68; // 索引: 待读取的表面个数 - 1
	localparam integer KWGTBLK_RD_REQ_CGRP_BASEADDR_SID = 36; // 索引: 卷积核通道组基地址
	localparam integer KWGTBLK_RD_REQ_CGRP_LEN_SID = 12; // 索引: 卷积核通道组有效字节数
	localparam integer KWGTBLK_RD_REQ_WGTBLK_VLD_SFC_N_SID = 5; // 索引: 每个权重块的表面个数 - 1
	localparam integer KWGTBLK_RD_REQ_SFC_VLD_DATA_N_SID = 0; // 索引: 每个表面的有效数据个数 - 1
	// 读特征图表面行处理状态常量
	localparam FM_RD_STS_EMPTY = 3'b000; // 状态: 未接受请求
	localparam FM_RD_STS_SEARCH = 3'b001; // 状态: 检索表面行
	localparam FM_RD_STS_RPLC = 3'b010; // 状态: 置换原表面行与发送DMA命令
	localparam FM_RD_STS_BUF_REQ = 3'b011; // 状态: 向逻辑特征图缓存发起读请求
	localparam FM_RD_STS_OUT_DATA = 3'b100; // 状态: 逻辑特征图缓存输出数据
	// 读卷积核权重块处理状态常量
	localparam KWGTBLK_RD_STS_EMPTY = 3'b000; // 状态: 未接受请求
	localparam KWGTBLK_RD_STS_SEND_DMA_CMD = 3'b001; // 状态: 发送DMA命令
	localparam KWGTBLK_RD_STS_RPLC = 3'b010; // 状态: 置换原通道组
	localparam KWGTBLK_RD_STS_BUF_REQ = 3'b011; // 状态: 向逻辑卷积核缓存发起读请求
	localparam KWGTBLK_RD_STS_OUT_DATA = 3'b100; // 状态: 逻辑卷积核缓存输出数据
	
	/** 获取特征图数据的DMA(MM2S方向)适配器 **/
	// [适配器命令流输入(AXIS从机)]
	wire[55:0] s0_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire[30:0] s0_dma_cmd_axis_user; // {读请求项索引(4bit), 实际表面行号(12bit), 表面行的缓存编号(10bit), 每个表面的有效数据个数 - 1(5bit)}
	wire s0_dma_cmd_axis_valid;
	wire s0_dma_cmd_axis_ready;
	// [适配器数据流输出(AXIS主机)]
	wire[ATOMIC_C*2*8-1:0] m0_dma_sfc_axis_data;
	wire[25:0] m0_dma_sfc_axis_user; // {读请求项索引(4bit), 实际表面行号(12bit), 表面行的缓存编号(10bit)}
	wire[ATOMIC_C*2-1:0] m0_dma_sfc_axis_keep;
	wire m0_dma_sfc_axis_last;
	wire m0_dma_sfc_axis_valid;
	wire m0_dma_sfc_axis_ready;
	
	conv_data_dma_mm2s_adapter #(
		.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH),
		.ATOMIC_C(ATOMIC_C),
		.EXTRA_DATA_WIDTH(26),
		.SIM_DELAY(SIM_DELAY)
	)conv_data_dma_mm2s_adapter_fmap_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.s_dma_cmd_axis_data(s0_dma_cmd_axis_data),
		.s_dma_cmd_axis_user(s0_dma_cmd_axis_user),
		.s_dma_cmd_axis_valid(s0_dma_cmd_axis_valid),
		.s_dma_cmd_axis_ready(s0_dma_cmd_axis_ready),
		
		.s_dma_strm_axis_data(s0_dma_strm_axis_data),
		.s_dma_strm_axis_keep(s0_dma_strm_axis_keep),
		.s_dma_strm_axis_last(s0_dma_strm_axis_last),
		.s_dma_strm_axis_valid(s0_dma_strm_axis_valid),
		.s_dma_strm_axis_ready(s0_dma_strm_axis_ready),
		
		.m_dma_cmd_axis_data(m0_dma_cmd_axis_data),
		.m_dma_cmd_axis_user(m0_dma_cmd_axis_user),
		.m_dma_cmd_axis_last(m0_dma_cmd_axis_last),
		.m_dma_cmd_axis_valid(m0_dma_cmd_axis_valid),
		.m_dma_cmd_axis_ready(m0_dma_cmd_axis_ready),
		
		.m_dma_sfc_axis_data(m0_dma_sfc_axis_data),
		.m_dma_sfc_axis_user(m0_dma_sfc_axis_user),
		.m_dma_sfc_axis_keep(m0_dma_sfc_axis_keep),
		.m_dma_sfc_axis_last(m0_dma_sfc_axis_last),
		.m_dma_sfc_axis_valid(m0_dma_sfc_axis_valid),
		.m_dma_sfc_axis_ready(m0_dma_sfc_axis_ready)
	);
	
	/** 获取卷积核数据的DMA(MM2S方向)适配器 **/
	// [适配器命令流输入(AXIS从机)]
	wire[55:0] s1_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire[25:0] s1_dma_cmd_axis_user; // {读请求项索引(4bit), 实际通道组号(10bit), 每个权重块的表面个数 - 1(7bit), 每个表面的有效数据个数 - 1(5bit)}
	wire s1_dma_cmd_axis_valid;
	wire s1_dma_cmd_axis_ready;
	// [适配器数据流输出(AXIS主机)]
	wire[ATOMIC_C*2*8-1:0] m1_dma_sfc_axis_data;
	wire[20:0] m1_dma_sfc_axis_user; // {读请求项索引(4bit), 实际通道组号(10bit), 每个权重块的表面个数 - 1(7bit)}
	wire[ATOMIC_C*2-1:0] m1_dma_sfc_axis_keep;
	wire m1_dma_sfc_axis_last;
	wire m1_dma_sfc_axis_valid;
	wire m1_dma_sfc_axis_ready;
	
	conv_data_dma_mm2s_adapter #(
		.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH),
		.ATOMIC_C(ATOMIC_C),
		.EXTRA_DATA_WIDTH(21),
		.SIM_DELAY(SIM_DELAY)
	)conv_data_dma_mm2s_adapter_kernal_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.s_dma_cmd_axis_data(s1_dma_cmd_axis_data),
		.s_dma_cmd_axis_user(s1_dma_cmd_axis_user),
		.s_dma_cmd_axis_valid(s1_dma_cmd_axis_valid),
		.s_dma_cmd_axis_ready(s1_dma_cmd_axis_ready),
		
		.s_dma_strm_axis_data(s1_dma_strm_axis_data),
		.s_dma_strm_axis_keep(s1_dma_strm_axis_keep),
		.s_dma_strm_axis_last(s1_dma_strm_axis_last),
		.s_dma_strm_axis_valid(s1_dma_strm_axis_valid),
		.s_dma_strm_axis_ready(s1_dma_strm_axis_ready),
		
		.m_dma_cmd_axis_data(m1_dma_cmd_axis_data),
		.m_dma_cmd_axis_user(m1_dma_cmd_axis_user),
		.m_dma_cmd_axis_last(m1_dma_cmd_axis_last),
		.m_dma_cmd_axis_valid(m1_dma_cmd_axis_valid),
		.m_dma_cmd_axis_ready(m1_dma_cmd_axis_ready),
		
		.m_dma_sfc_axis_data(m1_dma_sfc_axis_data),
		.m_dma_sfc_axis_user(m1_dma_sfc_axis_user),
		.m_dma_sfc_axis_keep(m1_dma_sfc_axis_keep),
		.m_dma_sfc_axis_last(m1_dma_sfc_axis_last),
		.m_dma_sfc_axis_valid(m1_dma_sfc_axis_valid),
		.m_dma_sfc_axis_ready(m1_dma_sfc_axis_ready)
	);
	
	/**
	特征图表面行读请求
	
	未接受请求(空) -> [检索表面行] -> [置换原表面行与发送DMA命令] -> 向逻辑特征图缓存发起读请求 -> 逻辑特征图缓存输出数据
	**/
	// [逻辑特征图缓存重置与置换]
	reg rst_logic_fmbuf; // 重置逻辑特征图缓存
	wire sfc_row_rplc_req; // 表面行置换请求
	wire[9:0] sfc_rid_to_rplc; // 待置换的表面行编号
	// [表面行存入]
	wire[3:0] sfc_row_stored_rd_req_eid; // 新存入表面行对应的读请求项索引
	wire sfc_row_stored_vld; // 表面行存储完成
	// [表面行检索输入]
	reg sfc_row_search_i_req; // 检索请求
	reg[11:0] sfc_row_search_i_rid; // 待检索的表面行号
	reg[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] sfc_row_search_i_rd_req_eid; // 执行检索操作的读请求项索引
	// [表面行检索输出]
	// 说明: 表面行检索具有2clk的时延
	wire sfc_row_search_o_vld; // 检索结果有效
	wire[9:0] sfc_row_search_o_buf_id; // 检索得到的缓存号
	wire sfc_row_search_o_found; // 检索的表面行已缓存
	reg[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] sfc_row_search_o_rd_req_eid[1:2]; // 延迟1~2clk的执行检索操作的读请求项索引
	// [特征图表面行数据输入]
	wire[ATOMIC_C*2*8-1:0] s_fm_fin_axis_data;
	wire[ATOMIC_C*2-1:0] s_fm_fin_axis_keep;
	wire[25:0] s_fm_fin_axis_user; // {读请求项索引(4bit), 实际表面行号(12bit), 表面行的缓存编号(10bit)}
	wire s_fm_fin_axis_last; // 标志当前表面行的最后1个表面
	wire s_fm_fin_axis_valid;
	wire s_fm_fin_axis_ready;
	// [特征图表面行缓存状态]
	reg[9:0] fm_buf_rid_to_rplc; // 特征图缓存待填充/置换的缓存行号
	reg fm_buf_first_filled_n; // 特征图缓存尚未被初次填满
	// [读请求存储实体]
	reg[11:0] fm_rd_req_actual_sfc_rid[0:FM_RD_REQ_PRE_ACPT_N-1]; // 实际表面行号
	reg[9:0] fm_rd_req_buf_sfc_rid[0:FM_RD_REQ_PRE_ACPT_N-1]; // 缓存表面行号
	reg[11:0] fm_rd_req_org_sfc_id[0:FM_RD_REQ_PRE_ACPT_N-1]; // 起始表面编号
	reg[11:0] fm_rd_req_sfc_n[0:FM_RD_REQ_PRE_ACPT_N-1]; // 待读取的表面个数 - 1
	reg[31:0] fm_rd_req_sfc_row_baseaddr[0:FM_RD_REQ_PRE_ACPT_N-1]; // 表面行基地址
	reg[23:0] fm_rd_req_sfc_row_len[0:FM_RD_REQ_PRE_ACPT_N-1]; // 表面行有效字节数
	reg[4:0] fm_rd_req_sfc_vld_data_n[0:FM_RD_REQ_PRE_ACPT_N-1]; // 每个表面的有效数据个数 - 1
	reg[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rd_req_age_tbit; // 年龄翻转位
	// [读请求处理阶段]
	reg[2:0] fm_rd_req_sts[0:FM_RD_REQ_PRE_ACPT_N-1]; // 处理状态
	reg[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rd_req_buffer_available; // 缓存可获取
	reg[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rd_req_buf_sfc_rid_vld; // 缓存表面行号有效
	reg[clogb2(FM_RD_REQ_PRE_ACPT_N-1)+1:0] acceptable_fm_rd_req_wptr; // 待接受的读请求(写指针)
	reg[clogb2(FM_RD_REQ_PRE_ACPT_N-1)+1:0] buffer_available_fm_rd_req_rptr; // 缓存可获取的读请求(读指针)
	reg[clogb2(FM_RD_REQ_PRE_ACPT_N-1)+1:0] exporting_fm_rd_req_ptr; // 正在输出数据的读请求(指针)
	wire[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rd_req_entry_actual_sfc_rid_matched_vec; // 读请求条目的实际表面行号与待接受读请求的相匹配(标志向量)
	wire[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rd_req_entry_vld; // 读请求条目有效(标志向量)
	wire[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rd_req_buf_sfc_rid_not_ready; // 缓存表面行号尚未准备好(标志向量)
	wire fm_rd_req_buf_full; // 读请求缓存满标志
	wire fm_rd_req_buf_empty; // 读请求缓存空标志
	// [缓存读请求]
	wire[39:0] s_fmbuf_rd_req_axis_data;
	wire s_fmbuf_rd_req_axis_valid;
	wire s_fmbuf_rd_req_axis_ready;
	// [DMA(MM2S方向)#0命令仲裁]
	wire[FM_RD_REQ_PRE_ACPT_N-1:0] dma0_mm2s_cmd_req; // 命令请求
	wire[FM_RD_REQ_PRE_ACPT_N-1:0] dma0_mm2s_cmd_grant; // 命令许可
	wire[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] dma0_mm2s_cmd_arb_sel; // 仲裁选择
	reg[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rd_req_entry_dma0_mm2s_cmd_sent; // 读请求条目已经向DMA发送命令
	// [表面行置换仲裁]
	wire[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rplc_req; // 置换请求
	wire[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rplc_grant; // 置换许可
	wire[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] fm_rplc_sel; // 置换选择
	reg[FM_RD_REQ_PRE_ACPT_N-1:0] fm_rd_req_entry_rplc_fns; // 读请求条目已经置换原表面行
	wire[FM_RD_REQ_PRE_ACPT_N-1:0] pre_fm_rd_req_entry_using_buf_row; // 前置读请求条目正在使用缓存行
	// [待处理的表面行置换操作fifo]
	wire fm_rplc_op_msg_fifo_wen;
	wire[3:0] fm_rplc_op_msg_fifo_din; // {执行操作的读请求项索引(4bit)}
	// 说明: 满标志未使用, 这是因为本fifo深度是"可提前接受的特征图读请求个数"(FM_RD_REQ_PRE_ACPT_N), 读请求存储实体未满时本fifo必定未满
	wire fm_rplc_op_msg_fifo_full_n;
	wire fm_rplc_op_msg_fifo_ren;
	wire[3:0] fm_rplc_op_msg_fifo_dout; // {执行操作的读请求项索引(4bit)}
	wire fm_rplc_op_msg_fifo_empty_n;
	// [待处理的发送DMA命令操作fifo]
	wire fm_sending_dma_cmd_op_msg_fifo_wen;
	wire[3:0] fm_sending_dma_cmd_op_msg_fifo_din; // {执行操作的读请求项索引(4bit)}
	// 说明: 满标志未使用, 这是因为本fifo深度是"可提前接受的特征图读请求个数"(FM_RD_REQ_PRE_ACPT_N), 读请求存储实体未满时本fifo必定未满
	wire fm_sending_dma_cmd_op_msg_fifo_full_n;
	wire fm_sending_dma_cmd_op_msg_fifo_ren;
	wire[3:0] fm_sending_dma_cmd_op_msg_fifo_dout; // {执行操作的读请求项索引(4bit)}
	wire fm_sending_dma_cmd_op_msg_fifo_empty_n;
	
	/*
	握手条件:
		aclken & 
		s_fm_rd_req_axis_valid & 
		(~rst_logic_fmbuf) & 
		(~fm_rd_req_buf_full) & 
		(~(|fm_rd_req_buf_sfc_rid_not_ready)) & 
		((~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) | fm_rd_req_buf_empty) & 
		((|fm_rd_req_entry_actual_sfc_rid_matched_vec) | (~sfc_row_search_i_req))
	*/
	assign s_fm_rd_req_axis_ready = 
		aclken & 
		(~rst_logic_fmbuf) & // 当前不在"重置逻辑特征图缓存"
		(~fm_rd_req_buf_full) & // 读请求缓存非满
		(~(|fm_rd_req_buf_sfc_rid_not_ready)) & // 等待缓存表面行号准备好
		((~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) | fm_rd_req_buf_empty) & // 对于"重置缓存", 需要等待读请求缓存空再处理
		// 要么是从读请求缓存中找到了与实际表面行号相匹配的条目, 要么表面行检索未被占用
		((|fm_rd_req_entry_actual_sfc_rid_matched_vec) | (~sfc_row_search_i_req));
	
	assign s0_dma_cmd_axis_data = {
		fm_rd_req_sfc_row_len[dma0_mm2s_cmd_arb_sel], // 待传输字节数(24bit)
		fm_rd_req_sfc_row_baseaddr[dma0_mm2s_cmd_arb_sel] // 传输首地址(32bit)
	};
	assign s0_dma_cmd_axis_user = {
		dma0_mm2s_cmd_arb_sel | 4'b0000, // 读请求项索引(4bit)
		fm_rd_req_actual_sfc_rid[dma0_mm2s_cmd_arb_sel], // 实际表面行号(12bit)
		fm_rd_req_buf_sfc_rid[dma0_mm2s_cmd_arb_sel], // 表面行的缓存编号(10bit)
		fm_rd_req_sfc_vld_data_n[dma0_mm2s_cmd_arb_sel] // 每个表面的有效数据个数 - 1(5bit)
	};
	/*
	握手条件: 
		aclken & 
		s0_dma_cmd_axis_ready & 
		fm_sending_dma_cmd_op_msg_fifo_empty_n & dma0_mm2s_cmd_req[dma0_mm2s_cmd_arb_sel]
	*/
	assign s0_dma_cmd_axis_valid = 
		aclken & 
		fm_sending_dma_cmd_op_msg_fifo_empty_n & dma0_mm2s_cmd_req[dma0_mm2s_cmd_arb_sel];
	
	assign sfc_row_rplc_req = 
		aclken & 
		fm_rplc_op_msg_fifo_empty_n & 
		fm_rplc_req[fm_rplc_sel] & 
		(~(|pre_fm_rd_req_entry_using_buf_row));
	assign sfc_rid_to_rplc = 
		fm_rd_req_buf_sfc_rid[fm_rplc_sel];
	
	assign s_fm_fin_axis_data = m0_dma_sfc_axis_data;
	assign s_fm_fin_axis_keep = m0_dma_sfc_axis_keep;
	assign s_fm_fin_axis_user = m0_dma_sfc_axis_user;
	assign s_fm_fin_axis_last = m0_dma_sfc_axis_last;
	assign s_fm_fin_axis_valid = aclken & m0_dma_sfc_axis_valid;
	assign m0_dma_sfc_axis_ready = aclken & s_fm_fin_axis_ready;
	
	assign fm_rd_req_buf_full = fm_rd_req_entry_vld[acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0]];
	assign fm_rd_req_buf_empty = ~(|fm_rd_req_entry_vld);
	
	assign s_fmbuf_rd_req_axis_data = {
		5'bxxxxx, // 保留(5bit)
		1'b0, // 是否需要自动置换表面行(1bit)
		fm_rd_req_buf_sfc_rid[buffer_available_fm_rd_req_rptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0]], // 表面行的缓存编号(10bit)
		fm_rd_req_org_sfc_id[buffer_available_fm_rd_req_rptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0]], // 起始表面编号(12bit)
		fm_rd_req_sfc_n[buffer_available_fm_rd_req_rptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0]] // 待读取的表面个数 - 1(12bit)
	};
	/*
	握手条件: 
		aclken & 
		s_fmbuf_rd_req_axis_ready & 
		(fm_rd_req_sts[buffer_available_fm_rd_req_rptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0]] == FM_RD_STS_BUF_REQ) & 
		fm_rd_req_buffer_available[buffer_available_fm_rd_req_rptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0]]
	*/
	assign s_fmbuf_rd_req_axis_valid = 
		aclken & 
		(fm_rd_req_sts[buffer_available_fm_rd_req_rptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0]] == FM_RD_STS_BUF_REQ) & 
		fm_rd_req_buffer_available[buffer_available_fm_rd_req_rptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0]];
	
	assign dma0_mm2s_cmd_arb_sel = fm_sending_dma_cmd_op_msg_fifo_dout[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0];
	
	assign fm_rplc_sel = fm_rplc_op_msg_fifo_dout[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0];
	
	assign fm_rplc_op_msg_fifo_wen = 
		aclken & sfc_row_search_o_vld & (~sfc_row_search_o_found) & (~fm_buf_first_filled_n);
	assign fm_rplc_op_msg_fifo_din = 
		sfc_row_search_o_rd_req_eid[2] | 4'b0000;
	/*
	握手条件: 
		aclken & 
		fm_rplc_op_msg_fifo_empty_n & 
		(fm_rd_req_sts[fm_rplc_sel] == FM_RD_STS_RPLC) & 
		fm_rplc_grant[fm_rplc_sel]
	*/
	assign fm_rplc_op_msg_fifo_ren = 
		aclken & 
		(fm_rd_req_sts[fm_rplc_sel] == FM_RD_STS_RPLC) & // 被选中的读请求条目处于"置换原表面行与发送DMA命令"状态
		fm_rplc_grant[fm_rplc_sel]; // 表面行置换完成
	
	assign fm_sending_dma_cmd_op_msg_fifo_wen = 
		aclken & sfc_row_search_o_vld & (~sfc_row_search_o_found);
	assign fm_sending_dma_cmd_op_msg_fifo_din = 
		sfc_row_search_o_rd_req_eid[2] | 4'b0000;
	/*
	握手条件: 
		aclken & 
		fm_sending_dma_cmd_op_msg_fifo_empty_n & 
		(fm_rd_req_sts[dma0_mm2s_cmd_arb_sel] == FM_RD_STS_RPLC) & 
		dma0_mm2s_cmd_grant[dma0_mm2s_cmd_arb_sel]
	*/
	assign fm_sending_dma_cmd_op_msg_fifo_ren = 
		aclken & 
		(fm_rd_req_sts[dma0_mm2s_cmd_arb_sel] == FM_RD_STS_RPLC) & // 被选中的读请求条目处于"置换原表面行与发送DMA命令"状态
		dma0_mm2s_cmd_grant[dma0_mm2s_cmd_arb_sel]; // DMA命令发送完成
	
	// 重置逻辑特征图缓存
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rst_logic_fmbuf <= 1'b0;
		else if(aclken)
			rst_logic_fmbuf <= # SIM_DELAY 
				s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & 
				s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID];
	end
	
	// 表面行检索请求
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			sfc_row_search_i_req <= 1'b0;
		else if(aclken)
			sfc_row_search_i_req <= # SIM_DELAY 
					// 提示: 目前是仅检索当前读请求条目的实际表面行号, 实际上还可以检索一下后续几个读请求条目的实际表面行号, 以避免置换掉即将要使用的表面行
					(~sfc_row_search_i_req) & 
					(
						s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & 
						(~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) & // 不是"重置缓存"的读请求
						(~(|fm_rd_req_entry_actual_sfc_rid_matched_vec)) // 从读请求缓存中找不到与实际表面行号相匹配的条目
					);
	end
	
	// 待检索的表面行号, 执行检索操作的读请求项索引
	always @(posedge aclk)
	begin
		if(
			aclken & 
			s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & 
			(~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) & // 不是"重置缓存"的读请求
			(~(|fm_rd_req_entry_actual_sfc_rid_matched_vec)) // 从读请求缓存中找不到与实际表面行号相匹配的条目
		)
		begin
			sfc_row_search_i_rid <= # SIM_DELAY 
				s_fm_rd_req_axis_data[FM_RD_REQ_ACTUAL_SFC_RID_SID+11:FM_RD_REQ_ACTUAL_SFC_RID_SID];
			sfc_row_search_i_rd_req_eid <= # SIM_DELAY 
				acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0];
		end
	end
	
	// 延迟1~2clk的执行检索操作的读请求项索引
	always @(posedge aclk)
	begin
		if(aclken)
			{sfc_row_search_o_rd_req_eid[2], sfc_row_search_o_rd_req_eid[1]} <= # SIM_DELAY 
				{sfc_row_search_o_rd_req_eid[1], sfc_row_search_i_rd_req_eid};
	end
	
	// 特征图缓存待填充/置换的缓存行号
	// 说明: 置换策略为FIFO
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				// 接受了"重置缓存"的读请求 -> 清零计数器
				(s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) | 
				// 检索表面行时缺失 -> 更新计数器
				(sfc_row_search_o_vld & (~sfc_row_search_o_found))
			)
		)
			fm_buf_rid_to_rplc <= # SIM_DELAY 
				{10{~(
					(s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) | 
					(fm_buf_rid_to_rplc == fmbufrown)
				)}} & (fm_buf_rid_to_rplc + 1'b1);
	end
	
	// 特征图缓存尚未被初次填满
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			fm_buf_first_filled_n <= 1'b1;
		else if(
			aclken & 
			(
				// 接受了"重置缓存"的读请求 -> 置位本标志
				(s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) | 
				// 检索表面行时缺失, 且特征图缓存尚未被初次填满 -> 粘滞更新
				(sfc_row_search_o_vld & (~sfc_row_search_o_found) & fm_buf_first_filled_n)
			)
		)
			fm_buf_first_filled_n <= # SIM_DELAY 
				(s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) | 
				(~(fm_buf_rid_to_rplc == fmbufrown));
	end
	
	genvar fm_rd_req_i;
	generate	
		for(fm_rd_req_i = 0;fm_rd_req_i < FM_RD_REQ_PRE_ACPT_N;fm_rd_req_i = fm_rd_req_i + 1)
		begin:fm_rd_req_blk
			assign fm_rd_req_entry_actual_sfc_rid_matched_vec[fm_rd_req_i] = 
				fm_rd_req_entry_vld[fm_rd_req_i] & // 条目有效
				(fm_rd_req_actual_sfc_rid[fm_rd_req_i] == 
					s_fm_rd_req_axis_data[FM_RD_REQ_ACTUAL_SFC_RID_SID+11:FM_RD_REQ_ACTUAL_SFC_RID_SID]); // 实际表面行号匹配
			assign fm_rd_req_entry_vld[fm_rd_req_i] = 
				fm_rd_req_sts[fm_rd_req_i] != FM_RD_STS_EMPTY;
			assign fm_rd_req_buf_sfc_rid_not_ready[fm_rd_req_i] = 
				fm_rd_req_entry_vld[fm_rd_req_i] & // 条目有效
				(~fm_rd_req_buf_sfc_rid_vld[fm_rd_req_i]); // 缓存表面行号无效
			
			assign dma0_mm2s_cmd_req[fm_rd_req_i] = 
				(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_RPLC) & // 当前读请求条目处于"置换原表面行与发送DMA命令"状态
				(~fm_rd_req_entry_dma0_mm2s_cmd_sent[fm_rd_req_i]); // 当前读请求条目尚未向DMA发送命令
			assign dma0_mm2s_cmd_grant[fm_rd_req_i] = 
				fm_sending_dma_cmd_op_msg_fifo_empty_n & // 待处理的发送DMA命令操作fifo非空
				dma0_mm2s_cmd_req[fm_rd_req_i] & // 发送DMA命令请求有效
				(dma0_mm2s_cmd_arb_sel == fm_rd_req_i) & // 当前读请求条目被选中
				s0_dma_cmd_axis_ready;
			
			assign fm_rplc_req[fm_rd_req_i] = 
				(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_RPLC) & // 当前读请求条目处于"置换原表面行与发送DMA命令"状态
				(~fm_rd_req_entry_rplc_fns[fm_rd_req_i]); // 当前读请求条目尚未完成置换原表面行
			assign fm_rplc_grant[fm_rd_req_i] = 
				fm_rplc_op_msg_fifo_empty_n & // 待处理的表面行置换操作fifo非空
				fm_rplc_req[fm_rd_req_i] & // 置换原表面行请求有效
				(fm_rplc_sel == fm_rd_req_i) & // 当前读请求条目被选中
				(~(|pre_fm_rd_req_entry_using_buf_row)); // 前置读请求条目不使用被选中条目的缓存行
			
			assign pre_fm_rd_req_entry_using_buf_row[fm_rd_req_i] = 
				fm_rd_req_entry_vld[fm_rd_req_i] & // 条目有效
				(fm_rd_req_buf_sfc_rid[fm_rplc_sel] == fm_rd_req_buf_sfc_rid[fm_rd_req_i]) & // 缓存行号与(置换)选中的条目产生冲突
				// 该条目比(置换)选中的条目更老
				((fm_rd_req_age_tbit[fm_rplc_sel] ^ fm_rd_req_age_tbit[fm_rd_req_i]) ^ (fm_rplc_sel > fm_rd_req_i));
			
			// 处理状态
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					fm_rd_req_sts[fm_rd_req_i] <= FM_RD_STS_EMPTY;
				else if(aclken)
				begin
					case(fm_rd_req_sts[fm_rd_req_i])
						FM_RD_STS_EMPTY:
							if(
								s_fm_rd_req_axis_valid & 
								(~rst_logic_fmbuf) & // 当前不在"重置逻辑特征图缓存"
								(acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == 
									fm_rd_req_i) & // 待接受的读请求(写指针)指向当前条目
								(~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) & // 不是"重置缓存"的读请求
								(~(|fm_rd_req_buf_sfc_rid_not_ready)) & // 等待缓存表面行号准备好
								(
									(|fm_rd_req_entry_actual_sfc_rid_matched_vec) | 
									(~sfc_row_search_i_req)
								) // 要么是从读请求缓存中找到了与实际表面行号相匹配的条目, 要么表面行检索未被占用
							)
								fm_rd_req_sts[fm_rd_req_i] <= # SIM_DELAY 
									// 说明: 从读请求缓存中找到了与实际表面行号相匹配的条目, 那就直接发起缓存读请求, 否则检索表面行
									(|fm_rd_req_entry_actual_sfc_rid_matched_vec) ? 
										FM_RD_STS_BUF_REQ:
										FM_RD_STS_SEARCH;
						FM_RD_STS_SEARCH:
							if(sfc_row_search_o_vld & (sfc_row_search_o_rd_req_eid[2] == fm_rd_req_i))
								fm_rd_req_sts[fm_rd_req_i] <= # SIM_DELAY 
									/*
									说明: 
										找到了对应的表面行, 那就直接发起缓存读请求
										即使没找到对应的表面行, 也并不一定就要置换, 不过肯定是要发送DMA命令来从下级存储器取这个表面行的
									*/
									sfc_row_search_o_found ? 
										FM_RD_STS_BUF_REQ:
										FM_RD_STS_RPLC;
						FM_RD_STS_RPLC:
							/*
							说明: 
								即使某个读请求条目的"发送DMA命令"比"置换原表面行"超前, 也是可以的, 
								这是因为(逻辑)特征图缓存保证了当缓存行无效时才开始接受特征图数据
							*/
							if(
								(fm_rplc_grant[fm_rd_req_i] | fm_rd_req_entry_rplc_fns[fm_rd_req_i]) & // 表面行置换完成或无需置换
								// DMA命令发送完成
								(dma0_mm2s_cmd_grant[fm_rd_req_i] | fm_rd_req_entry_dma0_mm2s_cmd_sent[fm_rd_req_i])
							)
								fm_rd_req_sts[fm_rd_req_i] <= # SIM_DELAY FM_RD_STS_BUF_REQ;
						FM_RD_STS_BUF_REQ:
							if(
								s_fmbuf_rd_req_axis_ready & 
								(buffer_available_fm_rd_req_rptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == 
									fm_rd_req_i) & // 缓存可获取的读请求(读指针)指向当前条目
								fm_rd_req_buffer_available[fm_rd_req_i] // 该条目的表面行数据从缓存中可获取
							)
								fm_rd_req_sts[fm_rd_req_i] <= # SIM_DELAY FM_RD_STS_OUT_DATA;
						FM_RD_STS_OUT_DATA:
							if(
								m_fm_fout_axis_valid & m_fm_fout_axis_ready & m_fm_fout_axis_last & // 特征图表面行数据输出完成
								(exporting_fm_rd_req_ptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == 
									fm_rd_req_i) // 正在输出数据的读请求(指针)指向当前条目
							)
								fm_rd_req_sts[fm_rd_req_i] <= # SIM_DELAY FM_RD_STS_EMPTY;
						default:
							fm_rd_req_sts[fm_rd_req_i] <= # SIM_DELAY FM_RD_STS_EMPTY;
					endcase
				end
			end
			
			// 实际表面行号, 起始表面编号, 待读取的表面个数 - 1, 表面行基地址, 表面行有效字节数, 每个表面的有效数据个数 - 1, 年龄翻转位
			always @(posedge aclk)
			begin
				if(
					aclken & 
					// 载入新的请求项, 且该请求项不是"重置缓存"
					s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & 
					(acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == fm_rd_req_i) & 
					(~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID])
				)
				begin
					{
						fm_rd_req_actual_sfc_rid[fm_rd_req_i], 
						fm_rd_req_org_sfc_id[fm_rd_req_i], 
						fm_rd_req_sfc_n[fm_rd_req_i], 
						fm_rd_req_sfc_row_baseaddr[fm_rd_req_i], 
						fm_rd_req_sfc_row_len[fm_rd_req_i], 
						fm_rd_req_sfc_vld_data_n[fm_rd_req_i]
					} <= # SIM_DELAY s_fm_rd_req_axis_data[96:0];
					
					fm_rd_req_age_tbit[fm_rd_req_i] <= # SIM_DELAY acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1)+1];
				end
			end
			
			// 缓存可获取
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						// 载入新的请求项 -> 置位本标志
						(
							s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & 
							(acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == fm_rd_req_i)
						) | 
						// 置换原表面行与发送DMA命令 -> 清零本标志
						(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_RPLC) | 
						// (逻辑)特征图缓存存入当前请求项指定的表面行 -> 置位本标志
						(sfc_row_stored_vld & (sfc_row_stored_rd_req_eid[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == fm_rd_req_i))
					)
				)
					fm_rd_req_buffer_available[fm_rd_req_i] <= # SIM_DELAY ~(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_RPLC);
			end
			
			// 缓存表面行号
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						// 载入新的请求项, 且该请求项不是"重置缓存", 且从读请求缓存中找到了与实际表面行号相匹配的条目
						(
							
							(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_EMPTY) & 
							s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & 
							(acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == fm_rd_req_i) & 
							(~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID]) & 
							(|fm_rd_req_entry_actual_sfc_rid_matched_vec)
						) | 
						// 检索表面行完成
						(
							(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_SEARCH) & 
							sfc_row_search_o_vld & (sfc_row_search_o_rd_req_eid[2] == fm_rd_req_i)
						)
					)
				)
					fm_rd_req_buf_sfc_rid[fm_rd_req_i] <= # SIM_DELAY 
						(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_EMPTY) ? 
							// 将匹配标志向量作优先编码, 从匹配条目中选出唯一项, 得到其缓存表面行号
							fm_rd_req_buf_sfc_rid[
								pri_encode(fm_rd_req_entry_actual_sfc_rid_matched_vec | 16'h0000) & 
								{(clogb2(FM_RD_REQ_PRE_ACPT_N-1)+1){1'b1}}
							]:
							(
								sfc_row_search_o_found ? 
									sfc_row_search_o_buf_id: // 检索表面行时命中, 使用"检索得到的缓存号"
									fm_buf_rid_to_rplc // 检索表面行时缺失, 若特征图缓存尚未被初次填满则直接分配1个无效缓存行, 否则置换1个缓存行
							);
			end
			
			// 缓存表面行号有效
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						// 载入新的请求项, 且该请求项不是"重置缓存" -> 初始化本标志
						(
							(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_EMPTY) & 
							s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & 
							(acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == fm_rd_req_i) & 
							(~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID])
						) | 
						// 检索表面行完成 -> 置位本标志
						(
							(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_SEARCH) & 
							sfc_row_search_o_vld & (sfc_row_search_o_rd_req_eid[2] == fm_rd_req_i)
						)
					)
				)
					fm_rd_req_buf_sfc_rid_vld[fm_rd_req_i] <= # SIM_DELAY 
						(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_SEARCH) | 
						(|fm_rd_req_entry_actual_sfc_rid_matched_vec);
			end
			
			// 读请求条目已经向DMA发送命令
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						// 载入新的请求项 -> 清零本标志
						(
							(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_EMPTY) & 
							s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & 
							(acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == fm_rd_req_i)
						) | 
						// 发送DMA命令被许可 -> 置位本标志
						dma0_mm2s_cmd_grant[fm_rd_req_i]
					)
				)
					fm_rd_req_entry_dma0_mm2s_cmd_sent[fm_rd_req_i] <= # SIM_DELAY dma0_mm2s_cmd_grant[fm_rd_req_i];
			end
			
			// 读请求条目已经置换原表面行
			always @(posedge aclk)
			begin
				if(
					aclken & 
					(
						// 载入新的请求项, 且该请求项不是"重置缓存" -> 初始化本标志
						(
							(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_EMPTY) & 
							s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & 
							(acceptable_fm_rd_req_wptr[clogb2(FM_RD_REQ_PRE_ACPT_N-1):0] == fm_rd_req_i) & 
							(~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID])
						) | 
						// 检索表面行时命中, 直接从缓存获取特征图数据, 不需要置换; 或者特征图缓存尚未被初次填满, 那分配1个无效缓存行即可, 不需要置换 -> 置位本标志
						(
							(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_SEARCH) & 
							sfc_row_search_o_vld & (sfc_row_search_o_rd_req_eid[2] == fm_rd_req_i) & 
							(sfc_row_search_o_found | fm_buf_first_filled_n)
						) | 
						// 置换请求被许可 -> 置位本标志
						(
							(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_RPLC) & 
							fm_rplc_grant[fm_rd_req_i]
						)
					)
				)
					fm_rd_req_entry_rplc_fns[fm_rd_req_i] <= # SIM_DELAY 
						(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_SEARCH) | 
						(fm_rd_req_sts[fm_rd_req_i] == FM_RD_STS_RPLC) | 
						(|fm_rd_req_entry_actual_sfc_rid_matched_vec);
			end
		end
	endgenerate
	
	// 待接受的读请求(写指针)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			acceptable_fm_rd_req_wptr <= 0;
		else if(
			aclken & 
			s_fm_rd_req_axis_valid & s_fm_rd_req_axis_ready & (~s_fm_rd_req_axis_data[FM_RD_REQ_TO_RST_BUF_FLAG_SID])
		)
			acceptable_fm_rd_req_wptr <= # SIM_DELAY acceptable_fm_rd_req_wptr + 1;
	end
	
	// 缓存可获取的读请求(读指针)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			buffer_available_fm_rd_req_rptr <= 0;
		else if(
			aclken & 
			s_fmbuf_rd_req_axis_valid & s_fmbuf_rd_req_axis_ready
		)
			buffer_available_fm_rd_req_rptr <= # SIM_DELAY buffer_available_fm_rd_req_rptr + 1;
	end
	
	// 正在输出数据的读请求(指针)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			exporting_fm_rd_req_ptr <= 0;
		else if(
			aclken & 
			m_fm_fout_axis_valid & m_fm_fout_axis_ready & m_fm_fout_axis_last
		)
			exporting_fm_rd_req_ptr <= # SIM_DELAY exporting_fm_rd_req_ptr + 1;
	end
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(FM_RD_REQ_PRE_ACPT_N),
		.fifo_data_width(4),
		.almost_full_th(1),
		.almost_empty_th(0),
		.simulation_delay(SIM_DELAY)
	)fm_rplc_op_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(fm_rplc_op_msg_fifo_wen),
		.fifo_din(fm_rplc_op_msg_fifo_din),
		.fifo_full_n(fm_rplc_op_msg_fifo_full_n),
		
		.fifo_ren(fm_rplc_op_msg_fifo_ren),
		.fifo_dout(fm_rplc_op_msg_fifo_dout),
		.fifo_empty_n(fm_rplc_op_msg_fifo_empty_n)
	);
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(FM_RD_REQ_PRE_ACPT_N),
		.fifo_data_width(4),
		.almost_full_th(1),
		.almost_empty_th(0),
		.simulation_delay(SIM_DELAY)
	)fm_sending_dma_cmd_op_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(fm_sending_dma_cmd_op_msg_fifo_wen),
		.fifo_din(fm_sending_dma_cmd_op_msg_fifo_din),
		.fifo_full_n(fm_sending_dma_cmd_op_msg_fifo_full_n),
		
		.fifo_ren(fm_sending_dma_cmd_op_msg_fifo_ren),
		.fifo_dout(fm_sending_dma_cmd_op_msg_fifo_dout),
		.fifo_empty_n(fm_sending_dma_cmd_op_msg_fifo_empty_n)
	);
	
	/**
	卷积核权重数据流
	
	将DMA(MM2S方向)数据流#1分割成以权重块为单位的数据包, 并给出通道组最后1个权重块标志
	**/
	// [DMA(MM2S方向)数据流#1随路信息]
	wire[3:0] m1_dma_sfc_axis_user_req_eid; // 读请求项索引
	wire[9:0] m1_dma_sfc_axis_user_actual_cgrp_id; // 实际通道组号
	wire[6:0] m1_dma_sfc_axis_user_sfc_n; // 每个权重块的表面个数 - 1
	// [表面与权重块计数器]
	reg[6:0] kernal_sfc_cnt; // 表面计数器
	wire[6:0] kernal_wgtblk_n_foreach_cgrp; // 每个通道组的权重块个数 - 1
	reg[6:0] kernal_wgtblk_cnt; // 权重块计数器
	// [输入通道组数据流]
	wire[ATOMIC_C*2*8-1:0] m_kbuf_in_cgrp_axis_data;
	wire[ATOMIC_C*2-1:0] m_kbuf_in_cgrp_axis_keep;
	wire[14:0] m_kbuf_in_cgrp_axis_user; // {读请求项索引(4bit), 实际通道组号(10bit), 标志通道组的最后1个权重块(1bit)}
	wire m_kbuf_in_cgrp_axis_last; // 标志权重块的最后1个表面
	wire m_kbuf_in_cgrp_axis_valid;
	wire m_kbuf_in_cgrp_axis_ready;
	
	assign {
		m1_dma_sfc_axis_user_req_eid,
		m1_dma_sfc_axis_user_actual_cgrp_id,
		m1_dma_sfc_axis_user_sfc_n
	} = m1_dma_sfc_axis_user;
	
	assign m_kbuf_in_cgrp_axis_data = m1_dma_sfc_axis_data;
	assign m_kbuf_in_cgrp_axis_keep = m1_dma_sfc_axis_keep;
	assign m_kbuf_in_cgrp_axis_user = {
		m1_dma_sfc_axis_user_req_eid, // 读请求项索引(4bit)
		m1_dma_sfc_axis_user_actual_cgrp_id, // 实际通道组号(10bit)
		kernal_wgtblk_cnt == kernal_wgtblk_n_foreach_cgrp // 标志通道组的最后1个权重块(1bit)
	};
	assign m_kbuf_in_cgrp_axis_last = kernal_sfc_cnt == m1_dma_sfc_axis_user_sfc_n;
	assign m_kbuf_in_cgrp_axis_valid = aclken & m1_dma_sfc_axis_valid;
	assign m1_dma_sfc_axis_ready = aclken & m_kbuf_in_cgrp_axis_ready;
	
	assign kernal_wgtblk_n_foreach_cgrp = 
		(
			(kbufgrpsz == KBUFGRPSZ_1)  ? 7'd1:
			(kbufgrpsz == KBUFGRPSZ_9)  ? 7'd9:
			(kbufgrpsz == KBUFGRPSZ_25) ? 7'd25:
			(kbufgrpsz == KBUFGRPSZ_49) ? 7'd49:
			(kbufgrpsz == KBUFGRPSZ_81) ? 7'd81:
										  7'd121
		) - 7'd1;
	
	// 表面计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_sfc_cnt <= 7'd0;
		else if(aclken & m_kbuf_in_cgrp_axis_valid & m_kbuf_in_cgrp_axis_ready)
			kernal_sfc_cnt <= # SIM_DELAY 
				(kernal_sfc_cnt == m1_dma_sfc_axis_user_sfc_n) ? 
					7'd0:
					(kernal_sfc_cnt + 1'b1);
	end
	
	// 权重块计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			kernal_wgtblk_cnt <= 7'd0;
		else if(aclken & m_kbuf_in_cgrp_axis_valid & m_kbuf_in_cgrp_axis_ready & m_kbuf_in_cgrp_axis_last)
			kernal_wgtblk_cnt <= # SIM_DELAY 
				(kernal_wgtblk_cnt == kernal_wgtblk_n_foreach_cgrp) ? 
					7'd0:
					(kernal_wgtblk_cnt + 1'b1);
	end
	
	/** 卷积核权重块读请求 **/
	// [逻辑卷积核缓存重置]
	reg rst_logic_kbuf; // 重置逻辑卷积核缓存
	reg[9:0] cgrpn; // 实际通道组数 - 1
	// [逻辑卷积核缓存置换]
	wire[1:0] sw_rgn_rplc; // 置换交换区通道组({通道组#1, 通道组#0})
	wire has_sw_rgn; // 是否存在交换区
	// [输入通道组数据流]
	wire[ATOMIC_C*2*8-1:0] s_kbuf_in_cgrp_axis_data;
	wire[ATOMIC_C*2-1:0] s_kbuf_in_cgrp_axis_keep;
	wire[14:0] s_kbuf_in_cgrp_axis_user; // {读请求项索引(4bit), 实际通道组号(10bit), 标志通道组的最后1个权重块(1bit)}
	wire s_kbuf_in_cgrp_axis_last; // 标志权重块的最后1个表面
	wire s_kbuf_in_cgrp_axis_valid;
	wire s_kbuf_in_cgrp_axis_ready;
	// [缓存读请求]
	wire[31:0] s_kbuf_rd_req_axis_data;
	wire s_kbuf_rd_req_axis_valid;
	wire s_kbuf_rd_req_axis_ready;
	// [预占用的驻留区]
	reg[8:0] warm_rsv_rgn_grpn; // 预热的驻留区通道组数
	wire en_rsv_rgn_warm_up; // 允许驻留区预热(标志)
	// [读请求存储实体]
	reg[9:0] kwgtblk_rd_req_actual_cgrpid[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 实际通道组号
	reg[6:0] kwgtblk_rd_req_wgtblk_id[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 权重块编号
	reg[6:0] kwgtblk_rd_req_org_sfc_id[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 起始表面编号
	reg[4:0] kwgtblk_rd_req_sfc_n[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 待读取的表面个数 - 1
	reg[31:0] kwgtblk_rd_req_trans_baseaddr[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 卷积核通道组基地址
	reg[23:0] kwgtblk_rd_req_trans_btt[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 卷积核通道组有效字节数
	reg[6:0] kwgtblk_rd_req_wgtblk_vld_sfc_n[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 每个权重块的表面个数 - 1
	reg[4:0] kwgtblk_rd_req_sfc_vld_data_n[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 每个表面的有效数据个数 - 1
	reg kwgtblk_rd_req_tbit[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 年龄翻转位
	// [读请求处理阶段]
	reg[2:0] kwgtblk_rd_req_sts[0:KWGTBLK_RD_REQ_PRE_ACPT_N-1]; // 处理状态
	wire[KWGTBLK_RD_REQ_PRE_ACPT_N-1:0] kwgtblk_rd_req_sw_region_occupied_flag[0:1]; // 交换区占用标志
	reg[1:0] kwgtblk_rd_req_sw_region_pre_loaded_flag; // 交换区预加载标志
	reg[9:0] kwgtblk_rd_req_sw_region_pre_loaded_cgrpid[0:1]; // 交换区预加载通道组号
	reg[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1)+1:0] acceptable_kwgtblk_rd_req_wptr; // 待接受的读请求(写指针)
	reg[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1)+1:0] accessible_kwgtblk_rd_req_rptr; // 待启动访问的读请求(读指针)
	reg[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1)+1:0] outputting_kwgtblk_rd_req_rptr; // 正在输出数据的读请求(读指针)
	wire[KWGTBLK_RD_REQ_PRE_ACPT_N-1:0] kwgtblk_rd_req_entry_vld; // 读请求条目有效(标志向量)
	wire[KWGTBLK_RD_REQ_PRE_ACPT_N-1:0] kwgtblk_rd_req_entry_sending_dma_cmd; // 读请求条目处于"发送DMA命令"状态(标志向量)
	reg has_sending_dma_cmd_kwgtblk_rd_req_entry; // 存在处于"发送DMA命令"状态的读请求条目(标志)
	reg[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0] sending_dma_cmd_kwgtblk_rd_req_eid; // 处于"发送DMA命令"状态的读请求条目编号
	wire kwgtblk_rd_req_buf_full; // 读请求缓存满标志
	wire kwgtblk_rd_req_buf_empty; // 读请求缓存空标志
	// [通道组检索]
	wire[8:0] rsv_rgn_vld_grpn; // 驻留区有效通道组数
	wire[1:0] sw_rgn_vld; // 交换区通道组有效({通道组#1, 通道组#0})
	wire[9:0] sw_rgn0_grpid; // 交换区通道组#0实际通道组号
	wire[9:0] sw_rgn1_grpid; // 交换区通道组#1实际通道组号
	wire[KWGTBLK_RD_REQ_PRE_ACPT_N-1:0] acceptable_kwgtblk_rd_req_cgrpid_match_prev; // 待接受读请求所访问通道组匹配前置处理中请求的通道组号
	wire acceptable_kwgtblk_rd_req_hit_in_logic_buf; // 待接受读请求所访问通道组在逻辑缓存命中
	wire acceptable_kwgtblk_rd_req_found_cgrp_from_prev; // 待接受读请求所访问通道组在前置处理中请求里找到
	// [待处理的交换区置换操作fifo]
	wire sw_rgn_rplc_op_msg_fifo_wen;
	wire[4:0] sw_rgn_rplc_op_msg_fifo_din; // {年龄翻转位(1bit), 执行操作的读请求项索引(4bit)}
	// 说明: 满标志未使用, 这是因为本fifo深度是"可提前接受的卷积核权重块读请求个数"(KWGTBLK_RD_REQ_PRE_ACPT_N), 读请求存储实体未满时本fifo必定未满
	wire sw_rgn_rplc_op_msg_fifo_full_n;
	wire sw_rgn_rplc_op_msg_fifo_ren;
	wire[4:0] sw_rgn_rplc_op_msg_fifo_dout; // {年龄翻转位(1bit), 执行操作的读请求项索引(4bit)}
	wire sw_rgn_rplc_op_msg_fifo_empty_n;
	
	assign s_kwgtblk_rd_req_axis_ready = 
		aclken & 
		(~rst_logic_kbuf) & // 当前不在"重置逻辑卷积核缓存"
		(~kwgtblk_rd_req_buf_full) & // 读请求缓存非满
		// 对于"重置缓存", 需要等待读请求缓存空再处理
		((~s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]) | kwgtblk_rd_req_buf_empty) & 
		// 如果缓存未命中, 那么要求没有处于"发送DMA命令"状态的读请求条目或DMA可接受命令
		(
			acceptable_kwgtblk_rd_req_hit_in_logic_buf | acceptable_kwgtblk_rd_req_found_cgrp_from_prev | 
			((~has_sending_dma_cmd_kwgtblk_rd_req_entry) | s1_dma_cmd_axis_ready)
		);
	
	assign s1_dma_cmd_axis_data = {
		kwgtblk_rd_req_trans_btt[sending_dma_cmd_kwgtblk_rd_req_eid], // 待传输字节数(24bit)
		kwgtblk_rd_req_trans_baseaddr[sending_dma_cmd_kwgtblk_rd_req_eid] // 传输首地址(32bit)
	};
	assign s1_dma_cmd_axis_user = {
		sending_dma_cmd_kwgtblk_rd_req_eid | 4'b0000, // 读请求项索引(4bit)
		kwgtblk_rd_req_actual_cgrpid[sending_dma_cmd_kwgtblk_rd_req_eid], // 实际通道组号(10bit)
		kwgtblk_rd_req_wgtblk_vld_sfc_n[sending_dma_cmd_kwgtblk_rd_req_eid], // 每个权重块的表面个数 - 1(7bit)
		kwgtblk_rd_req_sfc_vld_data_n[sending_dma_cmd_kwgtblk_rd_req_eid] // 每个表面的有效数据个数 - 1(5bit)
	};
	assign s1_dma_cmd_axis_valid = aclken & has_sending_dma_cmd_kwgtblk_rd_req_entry;
	
	// 说明: 优先置换通道组#0
	assign sw_rgn_rplc[0] = 
		aclken & 
		sw_rgn_rplc_op_msg_fifo_empty_n & 
		(kwgtblk_rd_req_sts[sw_rgn_rplc_op_msg_fifo_dout[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]] == KWGTBLK_RD_STS_RPLC) & 
		(~(|kwgtblk_rd_req_sw_region_occupied_flag[0]));
	assign sw_rgn_rplc[1] = 
		aclken & 
		sw_rgn_rplc_op_msg_fifo_empty_n & 
		(kwgtblk_rd_req_sts[sw_rgn_rplc_op_msg_fifo_dout[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]] == KWGTBLK_RD_STS_RPLC) & 
		((|kwgtblk_rd_req_sw_region_occupied_flag[0]) & (~(|kwgtblk_rd_req_sw_region_occupied_flag[1])));
	
	assign s_kbuf_in_cgrp_axis_data = m_kbuf_in_cgrp_axis_data;
	assign s_kbuf_in_cgrp_axis_keep = m_kbuf_in_cgrp_axis_keep;
	assign s_kbuf_in_cgrp_axis_user = m_kbuf_in_cgrp_axis_user;
	assign s_kbuf_in_cgrp_axis_last = m_kbuf_in_cgrp_axis_last;
	assign s_kbuf_in_cgrp_axis_valid = aclken & m_kbuf_in_cgrp_axis_valid;
	assign m_kbuf_in_cgrp_axis_ready = aclken & s_kbuf_in_cgrp_axis_ready;
	
	assign s_kbuf_rd_req_axis_data = {
		2'bxx, // 保留(2bit)
		1'b0, // 是否需要自动置换交换区通道组(1bit)
		kwgtblk_rd_req_actual_cgrpid[accessible_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]], // 实际通道组号(10bit)
		kwgtblk_rd_req_wgtblk_id[accessible_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]], // 权重块编号(7bit)
		kwgtblk_rd_req_org_sfc_id[accessible_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]], // 起始表面编号(7bit)
		kwgtblk_rd_req_sfc_n[accessible_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]] // 待读取的表面个数 - 1(5bit)
	};
	assign s_kbuf_rd_req_axis_valid = 
		aclken & 
		(kwgtblk_rd_req_sts[accessible_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]] == KWGTBLK_RD_STS_BUF_REQ) & 
		(
			// 在驻留区命中
			(
				kwgtblk_rd_req_actual_cgrpid[accessible_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]] < 
					{1'b0, rsv_rgn_vld_grpn}
			) | 
			// 在交换区通道组#0命中
			(
				sw_rgn_vld[0] & 
				(
					kwgtblk_rd_req_actual_cgrpid[accessible_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]] == 
						sw_rgn0_grpid
				)
			) | 
			// 在交换区通道组#1命中
			(
				sw_rgn_vld[1] & 
				(
					kwgtblk_rd_req_actual_cgrpid[accessible_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]] == 
						sw_rgn1_grpid
				)
			)
		);
	
	assign en_rsv_rgn_warm_up = 
		(~grp_conv_buf_mode) & has_sw_rgn & // 如果处于组卷积缓存模式或没有交换区, 那么逻辑卷积核缓存全为驻留区, 此时根本没必要去记录预热通道组数
		((warm_rsv_rgn_grpn + 1'b1) < {1'b0, kbufgrpn}); // 驻留区预热通道组数 < 可缓存的通道组数 - 2, 驻留区尚未预热完
	
	assign kwgtblk_rd_req_buf_full = kwgtblk_rd_req_entry_vld[acceptable_kwgtblk_rd_req_wptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]];
	assign kwgtblk_rd_req_buf_empty = ~(|kwgtblk_rd_req_entry_vld);
	
	assign acceptable_kwgtblk_rd_req_hit_in_logic_buf = 
		// 在驻留区命中
		(
			s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_ACTUAL_CGRPID_SID+9:KWGTBLK_RD_REQ_ACTUAL_CGRPID_SID] < 
				{1'b0, rsv_rgn_vld_grpn}
		) | 
		// 在交换区通道组#0命中
		(
			sw_rgn_vld[0] & 
			(
				s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_ACTUAL_CGRPID_SID+9:KWGTBLK_RD_REQ_ACTUAL_CGRPID_SID] == 
					sw_rgn0_grpid
			)
		) | 
		// 在交换区通道组#1命中
		(
			sw_rgn_vld[1] & 
			(
				s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_ACTUAL_CGRPID_SID+9:KWGTBLK_RD_REQ_ACTUAL_CGRPID_SID] == 
					sw_rgn1_grpid
			)
		);
	assign acceptable_kwgtblk_rd_req_found_cgrp_from_prev = |acceptable_kwgtblk_rd_req_cgrpid_match_prev;
	
	assign sw_rgn_rplc_op_msg_fifo_wen = 
		aclken & 
		s1_dma_cmd_axis_valid & s1_dma_cmd_axis_ready & 
		(~en_rsv_rgn_warm_up) & (~grp_conv_buf_mode) & has_sw_rgn;
	assign sw_rgn_rplc_op_msg_fifo_din[4] = 
		kwgtblk_rd_req_tbit[sending_dma_cmd_kwgtblk_rd_req_eid];
	assign sw_rgn_rplc_op_msg_fifo_din[3:0] = 
		sending_dma_cmd_kwgtblk_rd_req_eid | 4'b0000;
	assign sw_rgn_rplc_op_msg_fifo_ren = 
		aclken & 
		(kwgtblk_rd_req_sts[sw_rgn_rplc_op_msg_fifo_dout[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]] == KWGTBLK_RD_STS_RPLC) & 
		((~(|kwgtblk_rd_req_sw_region_occupied_flag[1])) | (~(|kwgtblk_rd_req_sw_region_occupied_flag[0])));
	
	// 重置逻辑卷积核缓存
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rst_logic_kbuf <= 1'b0;
		else if(aclken)
			rst_logic_kbuf <= # SIM_DELAY 
				s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
				s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID];
	end
	// 实际通道组数 - 1
	always @(posedge aclk)
	begin
		if(
			aclken & 
			// 载入新的请求项, 且该请求项是"重置缓存"
			s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
			s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]
		)
			cgrpn <= # SIM_DELAY s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_CGRPN_SID+9:KWGTBLK_RD_REQ_CGRPN_SID];
	end
	
	// 预热的驻留区通道组数
	always @(posedge aclk)
	begin
		if(
			aclken & 
			(
				// 载入新的请求项, 且该请求项是"重置缓存"
				(
					s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
					s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]
				) | 
				// DMA命令被接受, 预热/准备存入新的通道组
				(s1_dma_cmd_axis_valid & s1_dma_cmd_axis_ready & en_rsv_rgn_warm_up)
			)
		)
			warm_rsv_rgn_grpn <= # SIM_DELAY 
				{9{~(
					s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
					s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]
				)}} & (warm_rsv_rgn_grpn + 1'b1);
	end
	
	genvar kwgtblk_rd_req_i;
	generate
		for(kwgtblk_rd_req_i = 0;kwgtblk_rd_req_i < KWGTBLK_RD_REQ_PRE_ACPT_N;kwgtblk_rd_req_i = kwgtblk_rd_req_i + 1)
		begin:kwgtblk_rd_req_blk
			assign kwgtblk_rd_req_entry_vld[kwgtblk_rd_req_i] = 
				kwgtblk_rd_req_sts[kwgtblk_rd_req_i] != KWGTBLK_RD_STS_EMPTY;
			assign kwgtblk_rd_req_entry_sending_dma_cmd[kwgtblk_rd_req_i] = 
				kwgtblk_rd_req_sts[kwgtblk_rd_req_i] == KWGTBLK_RD_STS_SEND_DMA_CMD;
			assign acceptable_kwgtblk_rd_req_cgrpid_match_prev[kwgtblk_rd_req_i] = 
				kwgtblk_rd_req_entry_vld[kwgtblk_rd_req_i] & // 请求项有效
				(
					s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_ACTUAL_CGRPID_SID+9:KWGTBLK_RD_REQ_ACTUAL_CGRPID_SID] == 
						kwgtblk_rd_req_actual_cgrpid[kwgtblk_rd_req_i]
				); // 通道组号匹配
			
			// 实际通道组号, 权重块编号, 起始表面编号, 
			// 待读取的表面个数 - 1, 卷积核通道组基地址, 卷积核通道组有效字节数, 每个权重块的表面个数 - 1, 每个表面的有效数据个数 - 1
			// 年龄翻转位
			always @(posedge aclk)
			begin
				if(
					aclken & 
					// 载入新的请求项, 且该请求项不是"重置缓存"
					s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
					(acceptable_kwgtblk_rd_req_wptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0] == kwgtblk_rd_req_i) & 
					(~s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID])
				)
				begin
					{
						kwgtblk_rd_req_actual_cgrpid[kwgtblk_rd_req_i], // 实际通道组号(10bit)
						kwgtblk_rd_req_wgtblk_id[kwgtblk_rd_req_i], // 权重块编号(7bit)
						kwgtblk_rd_req_org_sfc_id[kwgtblk_rd_req_i], // 起始表面编号(7bit)
						kwgtblk_rd_req_sfc_n[kwgtblk_rd_req_i], // 待读取的表面个数 - 1(5bit)
						kwgtblk_rd_req_trans_baseaddr[kwgtblk_rd_req_i], // 卷积核通道组基地址(32bit)
						kwgtblk_rd_req_trans_btt[kwgtblk_rd_req_i], // 卷积核通道组有效字节数(24bit)
						kwgtblk_rd_req_wgtblk_vld_sfc_n[kwgtblk_rd_req_i], // 每个权重块的表面个数 - 1(7bit)
						kwgtblk_rd_req_sfc_vld_data_n[kwgtblk_rd_req_i] // 每个表面的有效数据个数 - 1(5bit)
					} <= # SIM_DELAY s_kwgtblk_rd_req_axis_data[96:0];
					
					kwgtblk_rd_req_tbit[kwgtblk_rd_req_i] <= # SIM_DELAY 
						acceptable_kwgtblk_rd_req_wptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1)+1];
				end
			end
			
			// 处理状态
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					kwgtblk_rd_req_sts[kwgtblk_rd_req_i] <= KWGTBLK_RD_STS_EMPTY;
				else if(aclken)
				begin
					case(kwgtblk_rd_req_sts[kwgtblk_rd_req_i])
						KWGTBLK_RD_STS_EMPTY:
							if(
								(~rst_logic_kbuf) & 
								(acceptable_kwgtblk_rd_req_wptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0] == kwgtblk_rd_req_i) & 
								(~s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]) & // 该请求项不是"重置缓存"
								(
									acceptable_kwgtblk_rd_req_hit_in_logic_buf | 
									acceptable_kwgtblk_rd_req_found_cgrp_from_prev | 
									((~has_sending_dma_cmd_kwgtblk_rd_req_entry) | s1_dma_cmd_axis_ready)
								) // 如果缓存未命中, 那么要求没有处于"发送DMA命令"状态的读请求条目或DMA可接受命令
							)
								kwgtblk_rd_req_sts[kwgtblk_rd_req_i] <= # SIM_DELAY 
									(acceptable_kwgtblk_rd_req_hit_in_logic_buf | acceptable_kwgtblk_rd_req_found_cgrp_from_prev) ? 
										KWGTBLK_RD_STS_BUF_REQ:
										KWGTBLK_RD_STS_SEND_DMA_CMD;
						KWGTBLK_RD_STS_SEND_DMA_CMD:
							if(s1_dma_cmd_axis_ready)
								/*
								说明: 
									如果读请求的权重数据将存储到新的/无效的交换区通道组, 那么多余的"置换交换区"操作并没有影响
									如果读请求的权重数据将存储到有效的交换区通道组, 那么显然需要置换原来的交换区通道组
								*/
								kwgtblk_rd_req_sts[kwgtblk_rd_req_i] <= # SIM_DELAY 
									(en_rsv_rgn_warm_up | grp_conv_buf_mode | (~has_sw_rgn)) ? 
										KWGTBLK_RD_STS_BUF_REQ:
										KWGTBLK_RD_STS_RPLC;
						KWGTBLK_RD_STS_RPLC:
							if(
								sw_rgn_rplc_op_msg_fifo_empty_n & 
								(sw_rgn_rplc_op_msg_fifo_dout[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0] == kwgtblk_rd_req_i) & 
								((~(|kwgtblk_rd_req_sw_region_occupied_flag[1])) | (~(|kwgtblk_rd_req_sw_region_occupied_flag[0])))
							)
								kwgtblk_rd_req_sts[kwgtblk_rd_req_i] <= # SIM_DELAY KWGTBLK_RD_STS_BUF_REQ;
						KWGTBLK_RD_STS_BUF_REQ:
							if(
								s_kbuf_rd_req_axis_valid & s_kbuf_rd_req_axis_ready & 
								(accessible_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0] == kwgtblk_rd_req_i)
							)
								kwgtblk_rd_req_sts[kwgtblk_rd_req_i] <= # SIM_DELAY KWGTBLK_RD_STS_OUT_DATA;
						KWGTBLK_RD_STS_OUT_DATA:
							if(
								m_kout_wgtblk_axis_valid & m_kout_wgtblk_axis_ready & m_kout_wgtblk_axis_last & // 权重块输出完成
								(outputting_kwgtblk_rd_req_rptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0] == kwgtblk_rd_req_i)
							)
								kwgtblk_rd_req_sts[kwgtblk_rd_req_i] <= # SIM_DELAY KWGTBLK_RD_STS_EMPTY;
						default:
							kwgtblk_rd_req_sts[kwgtblk_rd_req_i] <= # SIM_DELAY KWGTBLK_RD_STS_EMPTY;
					endcase
				end
			end
		end
	endgenerate
	
	// 交换区占用标志
	genvar kernal_sw_rgn_occupied_i;
	genvar kernal_sw_rgn_occupied_j;
	generate
		for(kernal_sw_rgn_occupied_i = 0;kernal_sw_rgn_occupied_i < 2;kernal_sw_rgn_occupied_i = kernal_sw_rgn_occupied_i + 1)
		begin:kernal_sw_rgn_occupied_blk_i
			// 交换区预加载标志
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					kwgtblk_rd_req_sw_region_pre_loaded_flag[kernal_sw_rgn_occupied_i] <= 1'b0;
				else if(
					aclken & 
					(
						// 重置缓存
						(
							s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
							s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]
						) | 
						// 置换通道组
						sw_rgn_rplc[kernal_sw_rgn_occupied_i]
					)
				)
					kwgtblk_rd_req_sw_region_pre_loaded_flag[kernal_sw_rgn_occupied_i] <= # SIM_DELAY 
						(~(
							s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
							s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]
						)) & sw_rgn_rplc[kernal_sw_rgn_occupied_i];
			end
			
			// 交换区预加载通道组号
			always @(posedge aclk)
			begin
				if(
					aclken & 
					sw_rgn_rplc[kernal_sw_rgn_occupied_i]
				)
					kwgtblk_rd_req_sw_region_pre_loaded_cgrpid[kernal_sw_rgn_occupied_i] <= # SIM_DELAY 
						kwgtblk_rd_req_actual_cgrpid[sw_rgn_rplc_op_msg_fifo_dout[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0]];
			end
			
			for(kernal_sw_rgn_occupied_j = 0;kernal_sw_rgn_occupied_j < KWGTBLK_RD_REQ_PRE_ACPT_N;
				kernal_sw_rgn_occupied_j = kernal_sw_rgn_occupied_j + 1)
			begin:kernal_sw_rgn_occupied_blk_j
				assign kwgtblk_rd_req_sw_region_occupied_flag[kernal_sw_rgn_occupied_i][kernal_sw_rgn_occupied_j] = 
					// 交换区通道组已经完成预加载
					kwgtblk_rd_req_sw_region_pre_loaded_flag[kernal_sw_rgn_occupied_i] & 
					// 交换区预加载通道组号与当前请求项的通道组号匹配
					(
						kwgtblk_rd_req_sw_region_pre_loaded_cgrpid[kernal_sw_rgn_occupied_i] == 
							kwgtblk_rd_req_actual_cgrpid[kernal_sw_rgn_occupied_j]
					) & 
					// 当前请求项有效
					kwgtblk_rd_req_entry_vld[kernal_sw_rgn_occupied_j] & 
					// 当前请求项比待执行置换操作的项更老
					(
						(sw_rgn_rplc_op_msg_fifo_dout[4] ^ kwgtblk_rd_req_tbit[kernal_sw_rgn_occupied_j]) ^ 
						(kernal_sw_rgn_occupied_j < sw_rgn_rplc_op_msg_fifo_dout[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0])
					);
			end
		end
	endgenerate
	
	// 待接受的读请求(写指针)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			acceptable_kwgtblk_rd_req_wptr <= 0;
		else if(
			aclken & 
			// 载入新的请求项, 且该请求项不是"重置缓存"
			s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
			(~s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID])
		)
			acceptable_kwgtblk_rd_req_wptr <= # SIM_DELAY acceptable_kwgtblk_rd_req_wptr + 1;
	end
	
	// 待启动访问的读请求(读指针)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			accessible_kwgtblk_rd_req_rptr <= 0;
		else if(
			aclken & 
			s_kbuf_rd_req_axis_valid & s_kbuf_rd_req_axis_ready
		)
			accessible_kwgtblk_rd_req_rptr <= # SIM_DELAY accessible_kwgtblk_rd_req_rptr + 1;
	end
	
	// 正在输出数据的读请求(读指针)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			outputting_kwgtblk_rd_req_rptr <= 0;
		else if(
			aclken & 
			m_kout_wgtblk_axis_valid & m_kout_wgtblk_axis_ready & m_kout_wgtblk_axis_last // 权重块输出完成
		)
			outputting_kwgtblk_rd_req_rptr <= # SIM_DELAY outputting_kwgtblk_rd_req_rptr + 1;
	end
	
	// 存在处于"发送DMA命令"状态的读请求条目(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			has_sending_dma_cmd_kwgtblk_rd_req_entry <= 1'b0;
		else if(
			aclken & 
			(
				// 载入新的请求项, 且该请求项不是"重置缓存", 且缓存未命中
				(
					s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
					(~s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]) & 
					(~(acceptable_kwgtblk_rd_req_hit_in_logic_buf | acceptable_kwgtblk_rd_req_found_cgrp_from_prev))
				) | 
				s1_dma_cmd_axis_ready
			)
		)
			has_sending_dma_cmd_kwgtblk_rd_req_entry <= # SIM_DELAY 
				s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
				(~s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]) & 
				(~(acceptable_kwgtblk_rd_req_hit_in_logic_buf | acceptable_kwgtblk_rd_req_found_cgrp_from_prev));
	end
	
	// 处于"发送DMA命令"状态的读请求条目编号
	always @(posedge aclk)
	begin
		if(
			aclken & 
			// 载入新的请求项, 且该请求项不是"重置缓存", 且缓存未命中
			s_kwgtblk_rd_req_axis_valid & s_kwgtblk_rd_req_axis_ready & 
			(~s_kwgtblk_rd_req_axis_data[KWGTBLK_RD_REQ_TO_RST_BUF_FLAG_SID]) & 
			(~(acceptable_kwgtblk_rd_req_hit_in_logic_buf | acceptable_kwgtblk_rd_req_found_cgrp_from_prev))
		)
			sending_dma_cmd_kwgtblk_rd_req_eid <= # SIM_DELAY acceptable_kwgtblk_rd_req_wptr[clogb2(KWGTBLK_RD_REQ_PRE_ACPT_N-1):0];
	end
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(KWGTBLK_RD_REQ_PRE_ACPT_N),
		.fifo_data_width(5),
		.almost_full_th(1),
		.almost_empty_th(0),
		.simulation_delay(SIM_DELAY)
	)sw_rgn_rplc_op_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(sw_rgn_rplc_op_msg_fifo_wen),
		.fifo_din(sw_rgn_rplc_op_msg_fifo_din),
		.fifo_full_n(sw_rgn_rplc_op_msg_fifo_full_n),
		
		.fifo_ren(sw_rgn_rplc_op_msg_fifo_ren),
		.fifo_dout(sw_rgn_rplc_op_msg_fifo_dout),
		.fifo_empty_n(sw_rgn_rplc_op_msg_fifo_empty_n)
	);
	
	/** (逻辑)特征图缓存 **/
	// [特征图缓存ICB主机#0]
	// (命令通道)
	wire[31:0] m0_fmbuf_cmd_addr;
	wire m0_fmbuf_cmd_read; // const -> 1'b0
	wire[ATOMIC_C*2*8-1:0] m0_fmbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] m0_fmbuf_cmd_wmask; // const -> {(ATOMIC_C*2){1'b1}}
	wire m0_fmbuf_cmd_valid;
	wire m0_fmbuf_cmd_ready;
	// (响应通道)
	wire[ATOMIC_C*2*8-1:0] m0_fmbuf_rsp_rdata; // ignored
	wire m0_fmbuf_rsp_err; // ignored
	wire m0_fmbuf_rsp_valid;
	wire m0_fmbuf_rsp_ready; // const -> 1'b1
	// [特征图缓存ICB主机#1]
	// (命令通道)
	wire[31:0] m1_fmbuf_cmd_addr;
	wire m1_fmbuf_cmd_read; // const -> 1'b1
	wire[ATOMIC_C*2*8-1:0] m1_fmbuf_cmd_wdata; // not care
	wire[ATOMIC_C*2-1:0] m1_fmbuf_cmd_wmask; // not care
	wire m1_fmbuf_cmd_valid;
	wire m1_fmbuf_cmd_ready;
	// (响应通道)
	wire[ATOMIC_C*2*8-1:0] m1_fmbuf_rsp_rdata;
	wire m1_fmbuf_rsp_err; // ignored
	wire m1_fmbuf_rsp_valid;
	wire m1_fmbuf_rsp_ready;
	
	logic_feature_map_buffer #(
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.ATOMIC_C(ATOMIC_C),
		.BUFFER_RID_WIDTH(LG_FMBUF_BUFFER_RID_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)logic_feature_map_buffer_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.fmbufcoln(fmbufcoln),
		.fmbufrown(fmbufrown),
		
		.rst_logic_fmbuf(rst_logic_fmbuf),
		.sfc_row_rplc_req(sfc_row_rplc_req),
		.sfc_rid_to_rplc(sfc_rid_to_rplc),
		.sfc_row_stored_rd_req_eid(sfc_row_stored_rd_req_eid),
		.sfc_row_stored_vld(sfc_row_stored_vld),
		
		.sfc_row_search_i_req(sfc_row_search_i_req),
		.sfc_row_search_i_rid(sfc_row_search_i_rid),
		.sfc_row_search_o_vld(sfc_row_search_o_vld),
		.sfc_row_search_o_buf_id(sfc_row_search_o_buf_id),
		.sfc_row_search_o_found(sfc_row_search_o_found),
		
		.s_fin_axis_data(s_fm_fin_axis_data),
		.s_fin_axis_keep(s_fm_fin_axis_keep),
		.s_fin_axis_user(s_fm_fin_axis_user),
		.s_fin_axis_last(s_fm_fin_axis_last),
		.s_fin_axis_valid(s_fm_fin_axis_valid),
		.s_fin_axis_ready(s_fm_fin_axis_ready),
		
		.s_rd_req_axis_data(s_fmbuf_rd_req_axis_data),
		.s_rd_req_axis_valid(s_fmbuf_rd_req_axis_valid),
		.s_rd_req_axis_ready(s_fmbuf_rd_req_axis_ready),
		
		.m_fout_axis_data(m_fm_fout_axis_data),
		.m_fout_axis_user(),
		.m_fout_axis_last(m_fm_fout_axis_last),
		.m_fout_axis_valid(m_fm_fout_axis_valid),
		.m_fout_axis_ready(m_fm_fout_axis_ready),
		
		.m0_fmbuf_cmd_addr(m0_fmbuf_cmd_addr),
		.m0_fmbuf_cmd_read(m0_fmbuf_cmd_read),
		.m0_fmbuf_cmd_wdata(m0_fmbuf_cmd_wdata),
		.m0_fmbuf_cmd_wmask(m0_fmbuf_cmd_wmask),
		.m0_fmbuf_cmd_valid(m0_fmbuf_cmd_valid),
		.m0_fmbuf_cmd_ready(m0_fmbuf_cmd_ready),
		.m0_fmbuf_rsp_rdata(m0_fmbuf_rsp_rdata),
		.m0_fmbuf_rsp_err(m0_fmbuf_rsp_err),
		.m0_fmbuf_rsp_valid(m0_fmbuf_rsp_valid),
		.m0_fmbuf_rsp_ready(m0_fmbuf_rsp_ready),
		
		.m1_fmbuf_cmd_addr(m1_fmbuf_cmd_addr),
		.m1_fmbuf_cmd_read(m1_fmbuf_cmd_read),
		.m1_fmbuf_cmd_wdata(m1_fmbuf_cmd_wdata),
		.m1_fmbuf_cmd_wmask(m1_fmbuf_cmd_wmask),
		.m1_fmbuf_cmd_valid(m1_fmbuf_cmd_valid),
		.m1_fmbuf_cmd_ready(m1_fmbuf_cmd_ready),
		.m1_fmbuf_rsp_rdata(m1_fmbuf_rsp_rdata),
		.m1_fmbuf_rsp_err(m1_fmbuf_rsp_err),
		.m1_fmbuf_rsp_valid(m1_fmbuf_rsp_valid),
		.m1_fmbuf_rsp_ready(m1_fmbuf_rsp_ready),
		
		.actual_rid_mp_tb_mem_clk(actual_rid_mp_tb_mem_clk),
		.actual_rid_mp_tb_mem_wen_a(actual_rid_mp_tb_mem_wen_a),
		.actual_rid_mp_tb_mem_addr_a(actual_rid_mp_tb_mem_addr_a),
		.actual_rid_mp_tb_mem_din_a(actual_rid_mp_tb_mem_din_a),
		.actual_rid_mp_tb_mem_ren_b(actual_rid_mp_tb_mem_ren_b),
		.actual_rid_mp_tb_mem_addr_b(actual_rid_mp_tb_mem_addr_b),
		.actual_rid_mp_tb_mem_dout_b(actual_rid_mp_tb_mem_dout_b),
		
		.buffer_rid_mp_tb_mem_clk(buffer_rid_mp_tb_mem_clk),
		.buffer_rid_mp_tb_mem_wen_a(buffer_rid_mp_tb_mem_wen_a),
		.buffer_rid_mp_tb_mem_addr_a(buffer_rid_mp_tb_mem_addr_a),
		.buffer_rid_mp_tb_mem_din_a(buffer_rid_mp_tb_mem_din_a),
		.buffer_rid_mp_tb_mem_ren_b(buffer_rid_mp_tb_mem_ren_b),
		.buffer_rid_mp_tb_mem_addr_b(buffer_rid_mp_tb_mem_addr_b),
		.buffer_rid_mp_tb_mem_dout_b(buffer_rid_mp_tb_mem_dout_b)
	);
	
	/** (逻辑)卷积核缓存 **/
	// [卷积核缓存ICB主机#0]
	// (命令通道)
	wire[31:0] m0_kbuf_cmd_addr;
	wire m0_kbuf_cmd_read; // const -> 1'b0
	wire[ATOMIC_C*2*8-1:0] m0_kbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] m0_kbuf_cmd_wmask; // const -> {(ATOMIC_C*2){1'b1}}
	wire m0_kbuf_cmd_valid;
	wire m0_kbuf_cmd_ready;
	// (响应通道)
	wire[ATOMIC_C*2*8-1:0] m0_kbuf_rsp_rdata; // ignored
	wire m0_kbuf_rsp_err; // ignored
	wire m0_kbuf_rsp_valid;
	wire m0_kbuf_rsp_ready; // const -> 1'b1
	// [卷积核缓存ICB主机#1]
	// (命令通道)
	wire[31:0] m1_kbuf_cmd_addr;
	wire m1_kbuf_cmd_read; // const -> 1'b1
	wire[ATOMIC_C*2*8-1:0] m1_kbuf_cmd_wdata; // not care
	wire[ATOMIC_C*2-1:0] m1_kbuf_cmd_wmask; // not care
	wire m1_kbuf_cmd_valid;
	wire m1_kbuf_cmd_ready;
	// (响应通道)
	wire[ATOMIC_C*2*8-1:0] m1_kbuf_rsp_rdata;
	wire m1_kbuf_rsp_err; // ignored
	wire m1_kbuf_rsp_valid;
	wire m1_kbuf_rsp_ready;
	
	logic_kernal_buffer #(
		.ATOMIC_C(ATOMIC_C),
		.ATOMIC_K(ATOMIC_K),
		.SIM_DELAY(SIM_DELAY)
	)logic_kernal_buffer_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.grp_conv_buf_mode(grp_conv_buf_mode),
		.kbufgrpsz(kbufgrpsz),
		.sfc_n_each_wgtblk(sfc_n_each_wgtblk),
		.kbufgrpn(kbufgrpn),
		
		.cgrpn(cgrpn),
		
		.rst_logic_kbuf(rst_logic_kbuf),
		.sw_rgn_rplc(sw_rgn_rplc),
		
		.rsv_rgn_vld_grpn(rsv_rgn_vld_grpn),
		.sw_rgn_vld(sw_rgn_vld),
		.sw_rgn0_grpid(sw_rgn0_grpid),
		.sw_rgn1_grpid(sw_rgn1_grpid),
		.has_sw_rgn(has_sw_rgn),
		.rsv_rgn_full(),
		.cgrp_stored_rd_req_eid(),
		.cgrp_stored_vld(),
		
		.s_in_cgrp_axis_data(s_kbuf_in_cgrp_axis_data),
		.s_in_cgrp_axis_keep(s_kbuf_in_cgrp_axis_keep),
		.s_in_cgrp_axis_user(s_kbuf_in_cgrp_axis_user),
		.s_in_cgrp_axis_last(s_kbuf_in_cgrp_axis_last),
		.s_in_cgrp_axis_valid(s_kbuf_in_cgrp_axis_valid),
		.s_in_cgrp_axis_ready(s_kbuf_in_cgrp_axis_ready),
		
		.s_rd_req_axis_data(s_kbuf_rd_req_axis_data),
		.s_rd_req_axis_valid(s_kbuf_rd_req_axis_valid),
		.s_rd_req_axis_ready(s_kbuf_rd_req_axis_ready),
		
		.m_out_wgtblk_axis_data(m_kout_wgtblk_axis_data),
		.m_out_wgtblk_axis_user(),
		.m_out_wgtblk_axis_last(m_kout_wgtblk_axis_last),
		.m_out_wgtblk_axis_valid(m_kout_wgtblk_axis_valid),
		.m_out_wgtblk_axis_ready(m_kout_wgtblk_axis_ready),
		
		.m0_kbuf_cmd_addr(m0_kbuf_cmd_addr),
		.m0_kbuf_cmd_read(m0_kbuf_cmd_read),
		.m0_kbuf_cmd_wdata(m0_kbuf_cmd_wdata),
		.m0_kbuf_cmd_wmask(m0_kbuf_cmd_wmask),
		.m0_kbuf_cmd_valid(m0_kbuf_cmd_valid),
		.m0_kbuf_cmd_ready(m0_kbuf_cmd_ready),
		.m0_kbuf_rsp_rdata(m0_kbuf_rsp_rdata),
		.m0_kbuf_rsp_err(m0_kbuf_rsp_err),
		.m0_kbuf_rsp_valid(m0_kbuf_rsp_valid),
		.m0_kbuf_rsp_ready(m0_kbuf_rsp_ready),
		
		.m1_kbuf_cmd_addr(m1_kbuf_cmd_addr),
		.m1_kbuf_cmd_read(m1_kbuf_cmd_read),
		.m1_kbuf_cmd_wdata(m1_kbuf_cmd_wdata),
		.m1_kbuf_cmd_wmask(m1_kbuf_cmd_wmask),
		.m1_kbuf_cmd_valid(m1_kbuf_cmd_valid),
		.m1_kbuf_cmd_ready(m1_kbuf_cmd_ready),
		.m1_kbuf_rsp_rdata(m1_kbuf_rsp_rdata),
		.m1_kbuf_rsp_err(m1_kbuf_rsp_err),
		.m1_kbuf_rsp_valid(m1_kbuf_rsp_valid),
		.m1_kbuf_rsp_ready(m1_kbuf_rsp_ready),
		
		.wt_rsv_rgn_actual_gid_mismatch()
	);
	
	/** (物理)卷积私有缓存 **/
	// [特征图缓存ICB从机#0]
	// (命令通道)
	wire[31:0] s0_fmbuf_cmd_addr;
	wire s0_fmbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] s0_fmbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] s0_fmbuf_cmd_wmask;
	wire s0_fmbuf_cmd_valid;
	wire s0_fmbuf_cmd_ready;
	// 响应通道
	wire[ATOMIC_C*2*8-1:0] s0_fmbuf_rsp_rdata;
	wire s0_fmbuf_rsp_err;
	wire s0_fmbuf_rsp_valid;
	wire s0_fmbuf_rsp_ready;
	// [特征图缓存ICB从机#1]
	// (命令通道)
	wire[31:0] s1_fmbuf_cmd_addr;
	wire s1_fmbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] s1_fmbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] s1_fmbuf_cmd_wmask;
	wire s1_fmbuf_cmd_valid;
	wire s1_fmbuf_cmd_ready;
	// (响应通道)
	wire[ATOMIC_C*2*8-1:0] s1_fmbuf_rsp_rdata;
	wire s1_fmbuf_rsp_err;
	wire s1_fmbuf_rsp_valid;
	wire s1_fmbuf_rsp_ready;
	// [卷积核缓存ICB从机#0]
	// (命令通道)
	wire[31:0] s0_kbuf_cmd_addr;
	wire s0_kbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] s0_kbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] s0_kbuf_cmd_wmask;
	wire s0_kbuf_cmd_valid;
	wire s0_kbuf_cmd_ready;
	// (响应通道)
	wire[ATOMIC_C*2*8-1:0] s0_kbuf_rsp_rdata;
	wire s0_kbuf_rsp_err;
	wire s0_kbuf_rsp_valid;
	wire s0_kbuf_rsp_ready;
	// [卷积核缓存ICB从机#1]
	// (命令通道)
	wire[31:0] s1_kbuf_cmd_addr;
	wire s1_kbuf_cmd_read;
	wire[ATOMIC_C*2*8-1:0] s1_kbuf_cmd_wdata;
	wire[ATOMIC_C*2-1:0] s1_kbuf_cmd_wmask;
	wire s1_kbuf_cmd_valid;
	wire s1_kbuf_cmd_ready;
	// (响应通道)
	wire[ATOMIC_C*2*8-1:0] s1_kbuf_rsp_rdata;
	wire s1_kbuf_rsp_err;
	wire s1_kbuf_rsp_valid;
	wire s1_kbuf_rsp_ready;
	
	assign s0_fmbuf_cmd_addr = m0_fmbuf_cmd_addr;
	assign s0_fmbuf_cmd_read = m0_fmbuf_cmd_read;
	assign s0_fmbuf_cmd_wdata = m0_fmbuf_cmd_wdata;
	assign s0_fmbuf_cmd_wmask = m0_fmbuf_cmd_wmask;
	assign s0_fmbuf_cmd_valid = aclken & m0_fmbuf_cmd_valid;
	assign m0_fmbuf_cmd_ready = aclken & s0_fmbuf_cmd_ready;
	assign m0_fmbuf_rsp_rdata = s0_fmbuf_rsp_rdata;
	assign m0_fmbuf_rsp_err = s0_fmbuf_rsp_err;
	assign m0_fmbuf_rsp_valid = aclken & s0_fmbuf_rsp_valid;
	assign s0_fmbuf_rsp_ready = aclken & m0_fmbuf_rsp_ready;
	
	assign s1_fmbuf_cmd_addr = m1_fmbuf_cmd_addr;
	assign s1_fmbuf_cmd_read = m1_fmbuf_cmd_read;
	assign s1_fmbuf_cmd_wdata = m1_fmbuf_cmd_wdata;
	assign s1_fmbuf_cmd_wmask = m1_fmbuf_cmd_wmask;
	assign s1_fmbuf_cmd_valid = aclken & m1_fmbuf_cmd_valid;
	assign m1_fmbuf_cmd_ready = aclken & s1_fmbuf_cmd_ready;
	assign m1_fmbuf_rsp_rdata = s1_fmbuf_rsp_rdata;
	assign m1_fmbuf_rsp_err = s1_fmbuf_rsp_err;
	assign m1_fmbuf_rsp_valid = aclken & s1_fmbuf_rsp_valid;
	assign s1_fmbuf_rsp_ready = aclken & m1_fmbuf_rsp_ready;
	
	assign s0_kbuf_cmd_addr = m0_kbuf_cmd_addr;
	assign s0_kbuf_cmd_read = m0_kbuf_cmd_read;
	assign s0_kbuf_cmd_wdata = m0_kbuf_cmd_wdata;
	assign s0_kbuf_cmd_wmask = m0_kbuf_cmd_wmask;
	assign s0_kbuf_cmd_valid = aclken & m0_kbuf_cmd_valid;
	assign m0_kbuf_cmd_ready = aclken & s0_kbuf_cmd_ready;
	assign m0_kbuf_rsp_rdata = s0_kbuf_rsp_rdata;
	assign m0_kbuf_rsp_err = s0_kbuf_rsp_err;
	assign m0_kbuf_rsp_valid = aclken & s0_kbuf_rsp_valid;
	assign s0_kbuf_rsp_ready = aclken & m0_kbuf_rsp_ready;
	
	assign s1_kbuf_cmd_addr = m1_kbuf_cmd_addr;
	assign s1_kbuf_cmd_read = m1_kbuf_cmd_read;
	assign s1_kbuf_cmd_wdata = m1_kbuf_cmd_wdata;
	assign s1_kbuf_cmd_wmask = m1_kbuf_cmd_wmask;
	assign s1_kbuf_cmd_valid = aclken & m1_kbuf_cmd_valid;
	assign m1_kbuf_cmd_ready = aclken & s1_kbuf_cmd_ready;
	assign m1_kbuf_rsp_rdata = s1_kbuf_rsp_rdata;
	assign m1_kbuf_rsp_err = s1_kbuf_rsp_err;
	assign m1_kbuf_rsp_valid = aclken & s1_kbuf_rsp_valid;
	assign s1_kbuf_rsp_ready = aclken & m1_kbuf_rsp_ready;
	
	phy_conv_buffer #(
		.ATOMIC_C(ATOMIC_C),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.EN_EXCEED_BD_PROTECT("true"),
		.EN_HP_ICB("true"),
		.EN_ICB0_FMBUF_REG_SLICE("true"),
		.EN_ICB1_FMBUF_REG_SLICE("true"),
		.EN_ICB0_KBUF_REG_SLICE("true"),
		.EN_ICB1_KBUF_REG_SLICE("true"),
		.SIM_DELAY(SIM_DELAY)
	)phy_conv_buffer_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(aclken),
		
		.fmbufbankn(fmbufbankn),
		
		.s0_fmbuf_cmd_addr(s0_fmbuf_cmd_addr),
		.s0_fmbuf_cmd_read(s0_fmbuf_cmd_read),
		.s0_fmbuf_cmd_wdata(s0_fmbuf_cmd_wdata),
		.s0_fmbuf_cmd_wmask(s0_fmbuf_cmd_wmask),
		.s0_fmbuf_cmd_valid(s0_fmbuf_cmd_valid),
		.s0_fmbuf_cmd_ready(s0_fmbuf_cmd_ready),
		.s0_fmbuf_rsp_rdata(s0_fmbuf_rsp_rdata),
		.s0_fmbuf_rsp_err(s0_fmbuf_rsp_err),
		.s0_fmbuf_rsp_valid(s0_fmbuf_rsp_valid),
		.s0_fmbuf_rsp_ready(s0_fmbuf_rsp_ready),
		
		.s1_fmbuf_cmd_addr(s1_fmbuf_cmd_addr),
		.s1_fmbuf_cmd_read(s1_fmbuf_cmd_read),
		.s1_fmbuf_cmd_wdata(s1_fmbuf_cmd_wdata),
		.s1_fmbuf_cmd_wmask(s1_fmbuf_cmd_wmask),
		.s1_fmbuf_cmd_valid(s1_fmbuf_cmd_valid),
		.s1_fmbuf_cmd_ready(s1_fmbuf_cmd_ready),
		.s1_fmbuf_rsp_rdata(s1_fmbuf_rsp_rdata),
		.s1_fmbuf_rsp_err(s1_fmbuf_rsp_err),
		.s1_fmbuf_rsp_valid(s1_fmbuf_rsp_valid),
		.s1_fmbuf_rsp_ready(s1_fmbuf_rsp_ready),
		
		.s0_kbuf_cmd_addr(s0_kbuf_cmd_addr),
		.s0_kbuf_cmd_read(s0_kbuf_cmd_read),
		.s0_kbuf_cmd_wdata(s0_kbuf_cmd_wdata),
		.s0_kbuf_cmd_wmask(s0_kbuf_cmd_wmask),
		.s0_kbuf_cmd_valid(s0_kbuf_cmd_valid),
		.s0_kbuf_cmd_ready(s0_kbuf_cmd_ready),
		.s0_kbuf_rsp_rdata(s0_kbuf_rsp_rdata),
		.s0_kbuf_rsp_err(s0_kbuf_rsp_err),
		.s0_kbuf_rsp_valid(s0_kbuf_rsp_valid),
		.s0_kbuf_rsp_ready(s0_kbuf_rsp_ready),
		
		.s1_kbuf_cmd_addr(s1_kbuf_cmd_addr),
		.s1_kbuf_cmd_read(s1_kbuf_cmd_read),
		.s1_kbuf_cmd_wdata(s1_kbuf_cmd_wdata),
		.s1_kbuf_cmd_wmask(s1_kbuf_cmd_wmask),
		.s1_kbuf_cmd_valid(s1_kbuf_cmd_valid),
		.s1_kbuf_cmd_ready(s1_kbuf_cmd_ready),
		.s1_kbuf_rsp_rdata(s1_kbuf_rsp_rdata),
		.s1_kbuf_rsp_err(s1_kbuf_rsp_err),
		.s1_kbuf_rsp_valid(s1_kbuf_rsp_valid),
		.s1_kbuf_rsp_ready(s1_kbuf_rsp_ready),
		
		.mem_clk_a(phy_conv_buf_mem_clk_a),
		.mem_en_a(phy_conv_buf_mem_en_a),
		.mem_wen_a(phy_conv_buf_mem_wen_a),
		.mem_addr_a(phy_conv_buf_mem_addr_a),
		.mem_din_a(phy_conv_buf_mem_din_a),
		.mem_dout_a(phy_conv_buf_mem_dout_a)
	);
	
endmodule
