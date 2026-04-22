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
本模块: 大胖达AI引擎

描述:
通用卷积处理单元 -> 
	支持普通卷积(包括全连接层)、组卷积(包括深度可分离卷积)、转置卷积(转换为合适的特征图填充与卷积步长来实现)
	支持特征图外填充与内填充
	支持卷积核膨胀
	支持计算轮次拓展
	支持批归一化处理
	支持Leaky-Relu激活、Sigmoid激活和Tanh激活

通用池化处理单元 -> 
	支持最大池化、平均池化
	支持(最近邻)上采样
	支持(非0常量)填充(由无复制的上采样模式来支持)
	支持逐元素常量运算(由后乘加处理来支持)

逐元素操作单元 -> 
	输入数据转换(FP16转FP32、U8/S8/U16/S16/U32/S32转FP32)
	二次幂计算(操作数X ^ 2)
	乘加计算(操作数A * 操作数X + 操作数B)
	输出数据转换(FP32转S33)
	舍入单元(S33转U8/S8/U16/S16/U32/S32、FP32转FP16)

运行时可选的输出数据舍入

注意：
需要外接2个DMA(MM2S)通道和1个DMA(S2MM)通道

可将SRAM和乘法器的接口引出, 在SOC层面再连接, 以实现SRAM和乘法器的共享

BN与激活并行数(BN_ACT_PRL_N)必须<=通道并行数或核并行数(ATOMIC_N)

通道并行数或核并行数(ATOMIC_N)必须能被卷积乘加阵列计算核心时钟倍率(CONV_MAC_ARRAY_CLK_RATE)整除
BN与激活并行数(BN_ACT_PRL_N)必须能被BN与激活单元的时钟倍率(BN_ACT_CLK_RATE)整除
通道并行数或核并行数(ATOMIC_N)必须能被中间结果缓存时钟倍率(MID_RES_BUF_CLK_RATE)整除
逐元素操作处理流水线条数(ELEMENT_WISE_PROC_PIPELINE_N)必须能被逐元素操作功能单元的时钟倍率(ELM_PROC_FU_CLK_RATE)整除

逐元素操作的操作数A与操作数B不能同时为变量

协议:
AXI-Lite SLAVE
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2026/01/17
********************************************************************/


module panda_ai_engine #(
	// 卷积与池化配置
	parameter integer CONV_ACCELERATOR_ID = 0, // 卷积加速器ID(0~3)
	parameter integer POOL_ACCELERATOR_ID = 0, // 池化加速器ID(0~3)
	parameter integer ATOMIC_N = 8, // 通道并行数或核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1, // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer CONV_MAC_ARRAY_CLK_RATE = 1, // 卷积乘加阵列计算核心时钟倍率(>=1)
	parameter integer BN_ACT_CLK_RATE = 1, // BN与激活单元的时钟倍率(>=1)
	parameter integer MID_RES_BUF_CLK_RATE = 1, // 中间结果缓存时钟倍率(1 | 2 | 4 | 8)
	parameter CONV_ASYNC_MAC_ARRAY_OPT_MODE = "area", // 卷积异步计算核心的优化模式("area" | "performance")(仅在计算核心时钟倍率>1时可用)
	parameter integer MAX_CAL_ROUND = 2, // 最大的计算轮次(1~16)
	parameter integer FP32_KEEP = 0, // 是否保持FP32输出
	parameter integer MAX_KERNAL_N = 1024, // 最大的卷积核个数(512 | 1024 | 2048 | 4096 | 8192)
	parameter integer BN_SUPPORTED = 1, // 是否支持批归一化处理
	parameter integer LEAKY_RELU_SUPPORTED = 1, // 是否支持Leaky-Relu激活
	parameter integer SIGMOID_SUPPORTED = 1, // 是否支持Sigmoid激活
	parameter integer TANH_SUPPORTED = 1, // 是否支持Tanh激活
	parameter integer INT8_SUPPORTED = 0, // 是否支持INT8
	parameter integer INT16_SUPPORTED = 0, // 是否支持INT16
	parameter integer FP16_SUPPORTED = 1, // 是否支持FP16
	parameter integer LARGE_V_STRD_SUPPORTED = 1, // 是否支持>1的卷积垂直步长
	parameter integer LARGE_H_STRD_SUPPORTED = 1, // 是否支持>1的卷积水平步长
	parameter integer GRP_CONV_SUPPORTED = 0, // 是否支持组卷积
	parameter integer CONV_EXT_PADDING_SUPPORTED = 1, // 是否支持卷积外填充
	parameter integer CONV_INNER_PADDING_SUPPORTED = 0, // 是否支持卷积内填充
	parameter integer KERNAL_DILATION_SUPPORTED = 0, // 是否支持卷积核膨胀
	parameter integer MAX_POOL_SUPPORTED = 1, // 是否支持最大池化
	parameter integer AVG_POOL_SUPPORTED = 0, // 是否支持平均池化
	parameter integer UP_SAMPLE_SUPPORTED = 1, // 是否支持上采样
	parameter integer POOL_POST_MAC_SUPPORTED = 0, // 是否支持池化后乘加处理
	parameter integer POOL_EXT_PADDING_SUPPORTED = 1, // 是否支持池化外填充
	parameter integer NON_ZERO_CONST_PADDING_SUPPORTED = 1, // 是否支持非0常量填充模式
	parameter integer RUNTIME_ODATA_ROUND_SEL_SUPPORTED = 0, // 是否支持运行时输出数据舍入选择
	// 逐元素操作单元配置
	parameter integer ELM_PROC_ACCELERATOR_ID = 0, // 逐元素操作加速器ID(0~3)
	parameter integer ELEMENT_WISE_PROC_PIPELINE_N = 4, // 逐元素操作处理流水线条数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ELM_PROC_FU_CLK_RATE = 2, // 逐元素操作功能单元的时钟倍率(1 | 2 | 4 | 8)
	// [输入与输出项字节数配置]
	parameter integer ELM_PROC_IN_STRM_WIDTH_1_BYTE_SUPPORTED = 1, // 是否支持输入流项位宽为1字节
	parameter integer ELM_PROC_IN_STRM_WIDTH_2_BYTE_SUPPORTED = 1, // 是否支持输入流项位宽为2字节
	parameter integer ELM_PROC_IN_STRM_WIDTH_4_BYTE_SUPPORTED = 1, // 是否支持输入流项位宽为4字节
	parameter integer ELM_PROC_OUT_STRM_WIDTH_1_BYTE_SUPPORTED = 1, // 是否支持输出流项位宽为1字节
	parameter integer ELM_PROC_OUT_STRM_WIDTH_2_BYTE_SUPPORTED = 1, // 是否支持输出流项位宽为2字节
	parameter integer ELM_PROC_OUT_STRM_WIDTH_4_BYTE_SUPPORTED = 1, // 是否支持输出流项位宽为4字节
	// [输入数据转换单元配置]
	parameter integer ELM_PROC_EN_IN_DATA_CVT = 1, // 启用输入数据转换单元
	parameter integer ELM_PROC_IN_DATA_CVT_EN_ROUND = 1, // 是否需要进行四舍五入
	parameter integer ELM_PROC_IN_DATA_CVT_FP16_IN_DATA_SUPPORTED = 0, // 是否支持FP16输入数据格式
	parameter integer ELM_PROC_IN_DATA_CVT_S33_IN_DATA_SUPPORTED = 1, // 是否支持S33输入数据格式
	// [计算单元配置]
	parameter integer ELM_PROC_EN_POW2_CAL_UNIT = 1, // 启用二次幂计算单元
	parameter integer ELM_PROC_EN_MAC_UNIT = 1, // 启用乘加计算单元
	parameter integer ELM_PROC_CAL_EN_ROUND = 1, // 是否需要进行四舍五入
	parameter integer ELM_PROC_CAL_INT16_SUPPORTED = 0, // 是否支持INT16运算数据格式
	parameter integer ELM_PROC_CAL_INT32_SUPPORTED = 0, // 是否支持INT32运算数据格式
	parameter integer ELM_PROC_CAL_FP32_SUPPORTED = 1, // 是否支持FP32运算数据格式
	// [输出数据转换单元配置]
	parameter integer ELM_PROC_EN_OUT_DATA_CVT = 1, // 启用输出数据转换单元
	parameter integer ELM_PROC_OUT_DATA_CVT_EN_ROUND = 1, // 是否需要进行四舍五入
	parameter integer ELM_PROC_OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED = 1, // 是否支持S33输出数据格式
	// [舍入单元配置]
	parameter integer ELM_PROC_EN_ROUND_UNIT = 1, // 启用舍入单元
	parameter integer ELM_PROC_ROUND_S33_ROUND_SUPPORTED = 1, // 是否支持S33数据的舍入
	parameter integer ELM_PROC_ROUND_FP32_ROUND_SUPPORTED = 1, // 是否支持FP32数据的舍入
	// 总线与缓存配置
	parameter integer MM2S_STREAM_DATA_WIDTH = 64, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer PHY_BUF_USE_TRUE_DUAL_PORT_SRAM = 0, // 物理缓存是否使用真双口RAM
	parameter integer CBUF_BANK_N = 16, // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 512, // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512, // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 8, // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512, // 中间结果缓存MEM深度(16 | ...)
	// 仿真与调试配置
	parameter integer EN_PERF_MON = 1, // 是否支持性能监测
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 主时钟和复位
	input wire aclk,
	input wire aresetn,
	// 卷积乘加阵列时钟和复位
	input wire mac_array_aclk,
	input wire mac_array_aresetn,
	// BN与激活单元时钟和复位
	input wire bn_act_aclk,
	input wire bn_act_aresetn,
	// 中间结果缓存时钟和复位
	input wire mid_res_buf_aclk,
	input wire mid_res_buf_aresetn,
	// 逐元素操作处理时钟和复位
	input wire elm_proc_aclk,
	input wire elm_proc_aresetn,
	
	// 寄存器配置接口#0(AXI-Lite从机)
    // 读地址通道
    input wire[31:0] s_axi_lite_conv_araddr,
    input wire s_axi_lite_conv_arvalid,
    output wire s_axi_lite_conv_arready,
    // 写地址通道
    input wire[31:0] s_axi_lite_conv_awaddr,
    input wire s_axi_lite_conv_awvalid,
    output wire s_axi_lite_conv_awready,
    // 写响应通道
    output wire[1:0] s_axi_lite_conv_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_conv_bvalid,
    input wire s_axi_lite_conv_bready,
    // 读数据通道
    output wire[31:0] s_axi_lite_conv_rdata,
    output wire[1:0] s_axi_lite_conv_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_conv_rvalid,
    input wire s_axi_lite_conv_rready,
    // 写数据通道
    input wire[31:0] s_axi_lite_conv_wdata,
    input wire s_axi_lite_conv_wvalid,
    output wire s_axi_lite_conv_wready,
	
	// 寄存器配置接口#1(AXI-Lite从机)
    // 读地址通道
    input wire[31:0] s_axi_lite_pool_araddr,
    input wire s_axi_lite_pool_arvalid,
    output wire s_axi_lite_pool_arready,
    // 写地址通道
    input wire[31:0] s_axi_lite_pool_awaddr,
    input wire s_axi_lite_pool_awvalid,
    output wire s_axi_lite_pool_awready,
    // 写响应通道
    output wire[1:0] s_axi_lite_pool_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_pool_bvalid,
    input wire s_axi_lite_pool_bready,
    // 读数据通道
    output wire[31:0] s_axi_lite_pool_rdata,
    output wire[1:0] s_axi_lite_pool_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_pool_rvalid,
    input wire s_axi_lite_pool_rready,
    // 写数据通道
    input wire[31:0] s_axi_lite_pool_wdata,
    input wire s_axi_lite_pool_wvalid,
    output wire s_axi_lite_pool_wready,
	
	// 寄存器配置接口#2(AXI-Lite从机)
    // 读地址通道
    input wire[31:0] s_axi_lite_elm_araddr,
    input wire s_axi_lite_elm_arvalid,
    output wire s_axi_lite_elm_arready,
    // 写地址通道
    input wire[31:0] s_axi_lite_elm_awaddr,
    input wire s_axi_lite_elm_awvalid,
    output wire s_axi_lite_elm_awready,
    // 写响应通道
    output wire[1:0] s_axi_lite_elm_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_elm_bvalid,
    input wire s_axi_lite_elm_bready,
    // 读数据通道
    output wire[31:0] s_axi_lite_elm_rdata,
    output wire[1:0] s_axi_lite_elm_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_elm_rvalid,
    input wire s_axi_lite_elm_rready,
    // 写数据通道
    input wire[31:0] s_axi_lite_elm_wdata,
    input wire s_axi_lite_elm_wvalid,
    output wire s_axi_lite_elm_wready,
	
	// BN参数存储器(AXI从机)
    // 读地址通道
    input wire[31:0] s_axi_conv_araddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_conv_arburst,
    input wire[3:0] s_axi_conv_arcache, // ignored
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_conv_arlen,
    input wire s_axi_conv_arlock, // ignored
    input wire[2:0] s_axi_conv_arprot, // ignored
    input wire[2:0] s_axi_conv_arsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_conv_arvalid,
    output wire s_axi_conv_arready,
    // 写地址通道
    input wire[31:0] s_axi_conv_awaddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_conv_awburst,
    input wire[3:0] s_axi_conv_awcache, // ignored
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_conv_awlen,
    input wire s_axi_conv_awlock, // ignored
    input wire[2:0] s_axi_conv_awprot, // ignored
    input wire[2:0] s_axi_conv_awsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_conv_awvalid,
    output wire s_axi_conv_awready,
    // 写响应通道
    output wire[1:0] s_axi_conv_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_conv_bvalid,
    input wire s_axi_conv_bready,
    // 读数据通道
    output wire[31:0] s_axi_conv_rdata,
    output wire s_axi_conv_rlast,
    output wire[1:0] s_axi_conv_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_conv_rvalid,
    input wire s_axi_conv_rready,
    // 写数据通道
    input wire[31:0] s_axi_conv_wdata,
    input wire s_axi_conv_wlast,
    input wire[3:0] s_axi_conv_wstrb,
    input wire s_axi_conv_wvalid,
    output wire s_axi_conv_wready,
	
	// DMA命令完成指示
	input wire mm2s_0_cmd_done, // 0号MM2S通道命令完成(指示)
	input wire mm2s_1_cmd_done, // 1号MM2S通道命令完成(指示)
	input wire s2mm_cmd_done, // S2MM通道命令完成(指示)
	
	// DMA(MM2S方向)命令流#0(AXIS主机)
	output wire[55:0] m0_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m0_dma_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m0_dma_cmd_axis_last, // 帧尾标志
	output wire m0_dma_cmd_axis_valid,
	input wire m0_dma_cmd_axis_ready,
	// DMA(MM2S方向)数据流#0(AXIS从机)
	input wire[MM2S_STREAM_DATA_WIDTH-1:0] s0_dma_strm_axis_data,
	input wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s0_dma_strm_axis_keep,
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
	input wire[MM2S_STREAM_DATA_WIDTH-1:0] s1_dma_strm_axis_data,
	input wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s1_dma_strm_axis_keep,
	input wire s1_dma_strm_axis_last,
	input wire s1_dma_strm_axis_valid,
	output wire s1_dma_strm_axis_ready,
	
	// DMA(S2MM方向)命令流(AXIS主机)
	output wire[55:0] m_dma_s2mm_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_dma_s2mm_cmd_axis_user, // 固定(1'b1)/递增(1'b0)传输(1bit)
	output wire m_dma_s2mm_cmd_axis_valid,
	input wire m_dma_s2mm_cmd_axis_ready,
	// 最终结果数据流(AXIS主机)
	output wire[S2MM_STREAM_DATA_WIDTH-1:0] m_axis_fnl_res_data,
	output wire[S2MM_STREAM_DATA_WIDTH/8-1:0] m_axis_fnl_res_keep,
	output wire m_axis_fnl_res_last, // 本行最后1个最终结果(标志)
	output wire m_axis_fnl_res_valid,
	input wire m_axis_fnl_res_ready
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
	// 池化模式的编码
	localparam POOL_MODE_AVG = 2'b00;
	localparam POOL_MODE_MAX = 2'b01;
	localparam POOL_MODE_UPSP = 2'b10;
	localparam POOL_MODE_NONE = 2'b11;
	// 输出特征图数据大小类型编码
	localparam OFMAP_DATA_1_BYTE = 2'b00; // 1字节
	localparam OFMAP_DATA_2_BYTE = 2'b01; // 2字节
	localparam OFMAP_DATA_4_BYTE = 2'b10; // 4字节
	
	/** 内部参数 **/
	// 核并行数
	localparam integer ATOMIC_K = ATOMIC_N;
	// 通道并行数
	localparam integer ATOMIC_C = ATOMIC_N;
	// 特征图缓存的缓存行号的位宽
	localparam integer LG_FMBUF_BUFFER_RID_WIDTH = clogb2(MAX_FMBUF_ROWN);
	// 批归一化与激活处理结果fifo的位宽
	localparam integer BN_ACT_PROC_RES_FIFO_WIDTH = BN_ACT_PRL_N*32+BN_ACT_PRL_N+1+5;
	// BN乘法器的位宽
	localparam integer BN_MUL_OP_WIDTH = INT8_SUPPORTED ? 4*18:(INT16_SUPPORTED ? 32:25);
	localparam integer BN_MUL_CE_WIDTH = INT8_SUPPORTED ? 4:3;
	localparam integer BN_MUL_RES_WIDTH = INT8_SUPPORTED ? 4*36:(INT16_SUPPORTED ? 64:50);
	// 泄露Relu乘法器的位宽
	localparam integer LEAKY_RELU_MUL_OP_WIDTH = INT16_SUPPORTED ? 32:25;
	localparam integer LEAKY_RELU_MUL_CE_WIDTH = 2;
	localparam integer LEAKY_RELU_MUL_RES_WIDTH = INT16_SUPPORTED ? 64:50;
	// 寄存器片配置
	localparam EN_MID_RES_REG_SLICE = "false"; // 是否使能中间结果输入寄存器片
	localparam EN_FNL_RES_REG_SLICE = "false"; // 是否使能最终结果输出寄存器片
	// 共享的中间结果更新与缓存模块是否固定选择池化加速器
	localparam SHARED_MID_RES_BUF_ALWAYS_SEL_POOL_ACC = 
		((CONV_MAC_ARRAY_CLK_RATE > 1) & (CONV_ASYNC_MAC_ARRAY_OPT_MODE == "performance")) ? 
			1'b1:
			1'b0;
	
	/** AXI-通用卷积处理单元(核心) **/
	// 使能信号
	wire en_conv_accelerator; // 使能卷积加速器
	// (共享)数据枢纽
	// [运行时参数]
	wire[3:0] conv_data_hub_fmbufcoln; // 每个表面行的表面个数类型
	wire[9:0] conv_data_hub_fmbufrown; // 可缓存的表面行数 - 1
	wire conv_data_hub_is_grp_conv_mode; // 是否处于组卷积缓存模式
	wire[2:0] conv_data_hub_kernal_shape; // 卷积核形状
	wire[2:0] conv_data_hub_sfc_n_each_wgtblk; // 每个权重块的表面个数的类型
	wire[7:0] conv_data_hub_kbufgrpn; // 可缓存的通道组数 - 1
	wire[7:0] conv_data_hub_fmbufbankn; // 分配给特征图缓存的Bank数
	// [特征图表面行读请求(AXIS主机)]
	wire[103:0] m_conv_fm_rd_req_axis_data;
	wire m_conv_fm_rd_req_axis_valid;
	wire m_conv_fm_rd_req_axis_ready;
	// [卷积核权重块读请求(AXIS主机)]
	wire[103:0] m_conv_kwgtblk_rd_req_axis_data;
	wire m_conv_kwgtblk_rd_req_axis_valid;
	wire m_conv_kwgtblk_rd_req_axis_ready;
	// [特征图表面行数据(AXIS从机)]
	wire[ATOMIC_C*2*8-1:0] s_conv_fm_sfc_row_axis_data;
	wire s_conv_fm_sfc_row_axis_last; // 标志本次读请求的最后1个表面
	wire s_conv_fm_sfc_row_axis_valid;
	wire s_conv_fm_sfc_row_axis_ready;
	// [卷积核权重块数据(AXIS从机)]
	wire[ATOMIC_C*2*8-1:0] s_conv_kernal_wgtblk_axis_data;
	wire s_conv_kernal_wgtblk_axis_last; // 标志本次读请求的最后1个表面
	wire s_conv_kernal_wgtblk_axis_valid;
	wire s_conv_kernal_wgtblk_axis_ready;
	// (共享)最终结果传输请求生成单元
	// [运行时参数]
	wire[31:0] conv_fnl_res_tr_req_gen_ofmap_baseaddr; // 输出特征图基地址
	wire[15:0] conv_fnl_res_tr_req_gen_ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] conv_fnl_res_tr_req_gen_ofmap_h; // 输出特征图高度 - 1
	wire[1:0] conv_fnl_res_tr_req_gen_ofmap_data_type; // 输出特征图数据大小类型
	wire[15:0] conv_fnl_res_tr_req_gen_kernal_num_n; // 卷积核核数 - 1
	wire[5:0] conv_fnl_res_tr_req_gen_max_wgtblk_w; // 权重块最大宽度
	wire conv_fnl_res_tr_req_gen_is_grp_conv_mode; // 是否处于组卷积模式
	wire[15:0] conv_fnl_res_tr_req_gen_n_foreach_group; // 每组的通道数/核数 - 1
	// [块级控制]
	wire conv_fnl_res_trans_blk_start;
	wire conv_fnl_res_trans_blk_idle;
	wire conv_fnl_res_trans_blk_done;
	// (共享)中间结果缓存
	// [使能信号]
	wire conv_en_mid_res_buf_dup; // 使能中间结果缓存
	// [运行时参数]
	wire[1:0] conv_mid_res_buf_calfmt; // 运算数据格式
	wire[3:0] conv_mid_res_buf_row_n_bufferable_dup; // 可缓存行数 - 1
	wire[3:0] conv_mid_res_buf_bank_n_foreach_ofmap_row; // 每个输出特征图行所占用的缓存MEM个数
	wire[3:0] conv_mid_res_buf_max_upd_latency; // 最大的更新时延
	// [中间结果(AXIS主机)]
	wire[ATOMIC_K*48-1:0] m_axis_conv_ext_mid_res_data;
	wire[ATOMIC_K*6-1:0] m_axis_conv_ext_mid_res_keep;
	wire[2:0] m_axis_conv_ext_mid_res_user; // {是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire m_axis_conv_ext_mid_res_last; // 本行最后1个中间结果(标志)
	wire m_axis_conv_ext_mid_res_valid;
	wire m_axis_conv_ext_mid_res_ready;
	// [最终结果(AXIS从机)]
	wire[ATOMIC_K*32-1:0] s_axis_conv_ext_fnl_res_data; // ATOMIC_K个最终结果(单精度浮点数或定点数)
	wire[ATOMIC_K*4-1:0] s_axis_conv_ext_fnl_res_keep;
	wire[4:0] s_axis_conv_ext_fnl_res_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire s_axis_conv_ext_fnl_res_last; // 本行最后1个最终结果(标志)
	wire s_axis_conv_ext_fnl_res_valid;
	wire s_axis_conv_ext_fnl_res_ready;
	// (共享)BN与激活单元
	// [使能信号]
	wire conv_en_bn_act_proc_dup; // 使能处理单元
	// [运行时参数]
	wire[1:0] conv_bn_act_calfmt; // 运算数据格式
	wire conv_bn_act_use_bn_unit; // 启用BN单元
	wire[2:0] conv_bn_act_act_func_type; // 激活函数类型
	wire[4:0] conv_bn_act_bn_fixed_point_quat_accrc; // (批归一化操作数A)定点数量化精度
	wire conv_bn_act_bn_is_a_eq_1; // 批归一化参数A的实际值为1(标志)
	wire conv_bn_act_bn_is_b_eq_0; // 批归一化参数B的实际值为0(标志)
	wire[4:0] conv_bn_act_leaky_relu_fixed_point_quat_accrc; // (泄露Relu激活参数)定点数量化精度
	wire[31:0] conv_bn_act_leaky_relu_param_alpha; // 泄露Relu激活参数
	wire[4:0] conv_bn_act_sigmoid_tanh_fixed_point_quat_accrc; // (Sigmoid或Tanh输入)定点数量化精度
	// [卷积最终结果(AXIS主机)]
	wire[ATOMIC_K*32-1:0] m_axis_conv_ext_bn_act_i_data; // 对于ATOMIC_K个最终结果 -> {单精度浮点数或定点数(32位)}
	wire[ATOMIC_K*4-1:0] m_axis_conv_ext_bn_act_i_keep;
	wire[4:0] m_axis_conv_ext_bn_act_i_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_conv_ext_bn_act_i_last; // 本行最后1个最终结果(标志)
	wire m_axis_conv_ext_bn_act_i_valid;
	wire m_axis_conv_ext_bn_act_i_ready;
	// [经过BN与激活处理的结果(AXIS从机)]
	wire[BN_ACT_PRL_N*32-1:0] s_axis_conv_ext_bn_act_o_data; // 对于BN_ACT_PRL_N个最终结果 -> {浮点数或定点数}
	wire[BN_ACT_PRL_N*4-1:0] s_axis_conv_ext_bn_act_o_keep;
	wire[4:0] s_axis_conv_ext_bn_act_o_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire s_axis_conv_ext_bn_act_o_last; // 本行最后1个处理结果(标志)
	wire s_axis_conv_ext_bn_act_o_valid;
	wire s_axis_conv_ext_bn_act_o_ready;
	// [BN参数MEM接口]
	wire bn_mem_clk_a;
	wire bn_mem_en_a;
	wire[7:0] bn_mem_wen_a;
	wire[15:0] bn_mem_addr_a;
	wire[63:0] bn_mem_din_a; // {参数B(32bit), 参数A(32bit)}
	wire[63:0] bn_mem_dout_a; // {参数B(32bit), 参数A(32bit)}
	// [Sigmoid函数值查找表MEM接口]
	wire sigmoid_lut_mem_clk_b;
	wire sigmoid_lut_mem_en_b;
	wire[3:0] sigmoid_lut_mem_wen_b;
	wire[15:0] sigmoid_lut_mem_addr_b;
	wire[31:0] sigmoid_lut_mem_din_b;
	wire[31:0] sigmoid_lut_mem_dout_b[0:BN_ACT_PRL_N-1];
	// (共享)输出数据舍入单元组
	// [运行时参数]
	wire[1:0] conv_round_calfmt; // 运算数据格式
	wire[3:0] conv_round_fixed_point_quat_accrc; // 定点数量化精度
	// [待舍入数据(AXIS主机)]
	wire[ATOMIC_K*32-1:0] m_axis_conv_ext_round_i_data; // ATOMIC_K个定点数或FP32
	wire[ATOMIC_K*4-1:0] m_axis_conv_ext_round_i_keep;
	wire[4:0] m_axis_conv_ext_round_i_user;
	wire m_axis_conv_ext_round_i_last;
	wire m_axis_conv_ext_round_i_valid;
	wire m_axis_conv_ext_round_i_ready;
	// [舍入后数据(AXIS从机)]
	wire[ATOMIC_K*16-1:0] s_axis_conv_ext_round_o_data; // ATOMIC_K个定点数或浮点数
	wire[ATOMIC_K*2-1:0] s_axis_conv_ext_round_o_keep;
	wire[4:0] s_axis_conv_ext_round_o_user;
	wire s_axis_conv_ext_round_o_last;
	wire s_axis_conv_ext_round_o_valid;
	wire s_axis_conv_ext_round_o_ready;
	// (共享)最终结果数据收集器
	// [待收集的数据流(AXIS主机)]
	wire[ATOMIC_K*(FP32_KEEP ? 32:16)-1:0] m_axis_conv_ext_collector_data;
	wire[ATOMIC_K*(FP32_KEEP ? 4:2)-1:0] m_axis_conv_ext_collector_keep;
	wire m_axis_conv_ext_collector_last;
	wire m_axis_conv_ext_collector_valid;
	wire m_axis_conv_ext_collector_ready;
	
	axi_generic_conv_core #(
		.MAC_ARRAY_CLK_RATE(CONV_MAC_ARRAY_CLK_RATE),
		.MID_RES_BUF_CLK_RATE(MID_RES_BUF_CLK_RATE),
		.ASYNC_MAC_ARRAY_OPT_MODE(CONV_ASYNC_MAC_ARRAY_OPT_MODE),
		.BN_SUPPORTED(BN_SUPPORTED),
		.LEAKY_RELU_SUPPORTED(LEAKY_RELU_SUPPORTED),
		.SIGMOID_SUPPORTED(SIGMOID_SUPPORTED),
		.TANH_SUPPORTED(TANH_SUPPORTED),
		.INT8_SUPPORTED(INT8_SUPPORTED),
		.INT16_SUPPORTED(INT16_SUPPORTED),
		.FP16_SUPPORTED(FP16_SUPPORTED),
		.LARGE_V_STRD_SUPPORTED(LARGE_V_STRD_SUPPORTED),
		.LARGE_H_STRD_SUPPORTED(LARGE_H_STRD_SUPPORTED),
		.GRP_CONV_SUPPORTED(GRP_CONV_SUPPORTED),
		.EXT_PADDING_SUPPORTED(CONV_EXT_PADDING_SUPPORTED),
		.INNER_PADDING_SUPPORTED(CONV_INNER_PADDING_SUPPORTED),
		.KERNAL_DILATION_SUPPORTED(KERNAL_DILATION_SUPPORTED),
		.EN_PERF_MON(EN_PERF_MON),
		.ACCELERATOR_ID(CONV_ACCELERATOR_ID),
		.FP32_KEEP(FP32_KEEP),
		.ATOMIC_K(ATOMIC_K),
		.ATOMIC_C(ATOMIC_C),
		.BN_ACT_PRL_N(BN_ACT_PRL_N),
		.MAX_CAL_ROUND(MAX_CAL_ROUND),
		.MM2S_STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.S2MM_STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.MAX_KERNAL_N(MAX_KERNAL_N),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.SIM_DELAY(SIM_DELAY)
	)axi_generic_conv_core_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		.mac_array_aclk(mac_array_aclk),
		.mac_array_aresetn(mac_array_aresetn),
		.mac_array_aclken(1'b1),
		
		.en_accelerator(en_conv_accelerator),
		
		.s_axi_lite_araddr(s_axi_lite_conv_araddr),
		.s_axi_lite_arvalid(s_axi_lite_conv_arvalid),
		.s_axi_lite_arready(s_axi_lite_conv_arready),
		.s_axi_lite_awaddr(s_axi_lite_conv_awaddr),
		.s_axi_lite_awvalid(s_axi_lite_conv_awvalid),
		.s_axi_lite_awready(s_axi_lite_conv_awready),
		.s_axi_lite_bresp(s_axi_lite_conv_bresp),
		.s_axi_lite_bvalid(s_axi_lite_conv_bvalid),
		.s_axi_lite_bready(s_axi_lite_conv_bready),
		.s_axi_lite_rdata(s_axi_lite_conv_rdata),
		.s_axi_lite_rresp(s_axi_lite_conv_rresp),
		.s_axi_lite_rvalid(s_axi_lite_conv_rvalid),
		.s_axi_lite_rready(s_axi_lite_conv_rready),
		.s_axi_lite_wdata(s_axi_lite_conv_wdata),
		.s_axi_lite_wvalid(s_axi_lite_conv_wvalid),
		.s_axi_lite_wready(s_axi_lite_conv_wready),
		
		.s_axi_araddr(s_axi_conv_araddr),
		.s_axi_arburst(s_axi_conv_arburst),
		.s_axi_arcache(s_axi_conv_arcache),
		.s_axi_arlen(s_axi_conv_arlen),
		.s_axi_arlock(s_axi_conv_arlock),
		.s_axi_arprot(s_axi_conv_arprot),
		.s_axi_arsize(s_axi_conv_arsize),
		.s_axi_arvalid(s_axi_conv_arvalid),
		.s_axi_arready(s_axi_conv_arready),
		.s_axi_awaddr(s_axi_conv_awaddr),
		.s_axi_awburst(s_axi_conv_awburst),
		.s_axi_awcache(s_axi_conv_awcache),
		.s_axi_awlen(s_axi_conv_awlen),
		.s_axi_awlock(s_axi_conv_awlock),
		.s_axi_awprot(s_axi_conv_awprot),
		.s_axi_awsize(s_axi_conv_awsize),
		.s_axi_awvalid(s_axi_conv_awvalid),
		.s_axi_awready(s_axi_conv_awready),
		.s_axi_bresp(s_axi_conv_bresp),
		.s_axi_bvalid(s_axi_conv_bvalid),
		.s_axi_bready(s_axi_conv_bready),
		.s_axi_rdata(s_axi_conv_rdata),
		.s_axi_rlast(s_axi_conv_rlast),
		.s_axi_rresp(s_axi_conv_rresp),
		.s_axi_rvalid(s_axi_conv_rvalid),
		.s_axi_rready(s_axi_conv_rready),
		.s_axi_wdata(s_axi_conv_wdata),
		.s_axi_wlast(s_axi_conv_wlast),
		.s_axi_wstrb(s_axi_conv_wstrb),
		.s_axi_wvalid(s_axi_conv_wvalid),
		.s_axi_wready(s_axi_conv_wready),
		
		.s0_dma_strm_axis_keep(s0_dma_strm_axis_keep),
		.s0_dma_strm_axis_valid(s0_dma_strm_axis_valid),
		.s0_dma_strm_axis_ready(s0_dma_strm_axis_ready),
		
		.s1_dma_strm_axis_keep(s1_dma_strm_axis_keep),
		.s1_dma_strm_axis_valid(s1_dma_strm_axis_valid),
		.s1_dma_strm_axis_ready(s1_dma_strm_axis_ready),
		
		.s_axis_fnl_res_keep(m_axis_fnl_res_keep),
		.s_axis_fnl_res_valid(m_axis_fnl_res_valid),
		.s_axis_fnl_res_ready(m_axis_fnl_res_ready),
		
		.data_hub_fmbufcoln(conv_data_hub_fmbufcoln),
		.data_hub_fmbufrown(conv_data_hub_fmbufrown),
		.data_hub_is_grp_conv_mode(conv_data_hub_is_grp_conv_mode),
		.data_hub_kernal_shape(conv_data_hub_kernal_shape),
		.data_hub_sfc_n_each_wgtblk(conv_data_hub_sfc_n_each_wgtblk),
		.data_hub_kbufgrpn(conv_data_hub_kbufgrpn),
		.data_hub_fmbufbankn(conv_data_hub_fmbufbankn),
		.m_fm_rd_req_axis_data(m_conv_fm_rd_req_axis_data),
		.m_fm_rd_req_axis_valid(m_conv_fm_rd_req_axis_valid),
		.m_fm_rd_req_axis_ready(m_conv_fm_rd_req_axis_ready),
		.m_kwgtblk_rd_req_axis_data(m_conv_kwgtblk_rd_req_axis_data),
		.m_kwgtblk_rd_req_axis_valid(m_conv_kwgtblk_rd_req_axis_valid),
		.m_kwgtblk_rd_req_axis_ready(m_conv_kwgtblk_rd_req_axis_ready),
		.s_fm_sfc_row_axis_data(s_conv_fm_sfc_row_axis_data),
		.s_fm_sfc_row_axis_last(s_conv_fm_sfc_row_axis_last),
		.s_fm_sfc_row_axis_valid(s_conv_fm_sfc_row_axis_valid),
		.s_fm_sfc_row_axis_ready(s_conv_fm_sfc_row_axis_ready),
		.s_kernal_wgtblk_axis_data(s_conv_kernal_wgtblk_axis_data),
		.s_kernal_wgtblk_axis_last(s_conv_kernal_wgtblk_axis_last),
		.s_kernal_wgtblk_axis_valid(s_conv_kernal_wgtblk_axis_valid),
		.s_kernal_wgtblk_axis_ready(s_conv_kernal_wgtblk_axis_ready),
		
		.fnl_res_tr_req_gen_ofmap_baseaddr(conv_fnl_res_tr_req_gen_ofmap_baseaddr),
		.fnl_res_tr_req_gen_ofmap_w(conv_fnl_res_tr_req_gen_ofmap_w),
		.fnl_res_tr_req_gen_ofmap_h(conv_fnl_res_tr_req_gen_ofmap_h),
		.fnl_res_tr_req_gen_ofmap_data_type(conv_fnl_res_tr_req_gen_ofmap_data_type),
		.fnl_res_tr_req_gen_kernal_num_n(conv_fnl_res_tr_req_gen_kernal_num_n),
		.fnl_res_tr_req_gen_max_wgtblk_w(conv_fnl_res_tr_req_gen_max_wgtblk_w),
		.fnl_res_tr_req_gen_is_grp_conv_mode(conv_fnl_res_tr_req_gen_is_grp_conv_mode),
		.fnl_res_tr_req_gen_n_foreach_group(conv_fnl_res_tr_req_gen_n_foreach_group),
		.fnl_res_trans_blk_start(conv_fnl_res_trans_blk_start),
		.fnl_res_trans_blk_idle(conv_fnl_res_trans_blk_idle),
		.fnl_res_trans_blk_done(conv_fnl_res_trans_blk_done),
		
		.en_mid_res_buf_dup(conv_en_mid_res_buf_dup),
		.mid_res_buf_calfmt(conv_mid_res_buf_calfmt),
		.mid_res_buf_row_n_bufferable_dup(conv_mid_res_buf_row_n_bufferable_dup),
		.mid_res_buf_bank_n_foreach_ofmap_row(conv_mid_res_buf_bank_n_foreach_ofmap_row),
		.mid_res_buf_max_upd_latency(conv_mid_res_buf_max_upd_latency),
		.m_axis_ext_mid_res_data(m_axis_conv_ext_mid_res_data),
		.m_axis_ext_mid_res_keep(m_axis_conv_ext_mid_res_keep),
		.m_axis_ext_mid_res_user(m_axis_conv_ext_mid_res_user),
		.m_axis_ext_mid_res_last(m_axis_conv_ext_mid_res_last),
		.m_axis_ext_mid_res_valid(m_axis_conv_ext_mid_res_valid),
		.m_axis_ext_mid_res_ready(m_axis_conv_ext_mid_res_ready),
		.s_axis_ext_fnl_res_data(s_axis_conv_ext_fnl_res_data),
		.s_axis_ext_fnl_res_keep(s_axis_conv_ext_fnl_res_keep),
		.s_axis_ext_fnl_res_user(s_axis_conv_ext_fnl_res_user),
		.s_axis_ext_fnl_res_last(s_axis_conv_ext_fnl_res_last),
		.s_axis_ext_fnl_res_valid(s_axis_conv_ext_fnl_res_valid),
		.s_axis_ext_fnl_res_ready(s_axis_conv_ext_fnl_res_ready),
		
		.en_bn_act_proc_dup(conv_en_bn_act_proc_dup),
		.bn_act_calfmt(conv_bn_act_calfmt),
		.bn_act_use_bn_unit(conv_bn_act_use_bn_unit),
		.bn_act_act_func_type(conv_bn_act_act_func_type),
		.bn_act_bn_fixed_point_quat_accrc(conv_bn_act_bn_fixed_point_quat_accrc),
		.bn_act_bn_is_a_eq_1(conv_bn_act_bn_is_a_eq_1),
		.bn_act_bn_is_b_eq_0(conv_bn_act_bn_is_b_eq_0),
		.bn_act_leaky_relu_fixed_point_quat_accrc(conv_bn_act_leaky_relu_fixed_point_quat_accrc),
		.bn_act_leaky_relu_param_alpha(conv_bn_act_leaky_relu_param_alpha),
		.bn_act_sigmoid_tanh_fixed_point_quat_accrc(conv_bn_act_sigmoid_tanh_fixed_point_quat_accrc),
		.m_axis_ext_bn_act_i_data(m_axis_conv_ext_bn_act_i_data),
		.m_axis_ext_bn_act_i_keep(m_axis_conv_ext_bn_act_i_keep),
		.m_axis_ext_bn_act_i_user(m_axis_conv_ext_bn_act_i_user),
		.m_axis_ext_bn_act_i_last(m_axis_conv_ext_bn_act_i_last),
		.m_axis_ext_bn_act_i_valid(m_axis_conv_ext_bn_act_i_valid),
		.m_axis_ext_bn_act_i_ready(m_axis_conv_ext_bn_act_i_ready),
		.s_axis_ext_bn_act_o_data(s_axis_conv_ext_bn_act_o_data),
		.s_axis_ext_bn_act_o_keep(s_axis_conv_ext_bn_act_o_keep),
		.s_axis_ext_bn_act_o_user(s_axis_conv_ext_bn_act_o_user),
		.s_axis_ext_bn_act_o_last(s_axis_conv_ext_bn_act_o_last),
		.s_axis_ext_bn_act_o_valid(s_axis_conv_ext_bn_act_o_valid),
		.s_axis_ext_bn_act_o_ready(s_axis_conv_ext_bn_act_o_ready),
		.bn_mem_clk_a(bn_mem_clk_a),
		.bn_mem_en_a(bn_mem_en_a),
		.bn_mem_wen_a(bn_mem_wen_a),
		.bn_mem_addr_a(bn_mem_addr_a),
		.bn_mem_din_a(bn_mem_din_a),
		.bn_mem_dout_a(bn_mem_dout_a),
		.sigmoid_lut_mem_clk_b(sigmoid_lut_mem_clk_b),
		.sigmoid_lut_mem_en_b(sigmoid_lut_mem_en_b),
		.sigmoid_lut_mem_wen_b(sigmoid_lut_mem_wen_b),
		.sigmoid_lut_mem_addr_b(sigmoid_lut_mem_addr_b),
		.sigmoid_lut_mem_din_b(sigmoid_lut_mem_din_b),
		.sigmoid_lut_mem_dout_b(sigmoid_lut_mem_dout_b[0]),
		
		.round_calfmt(conv_round_calfmt),
		.round_fixed_point_quat_accrc(conv_round_fixed_point_quat_accrc),
		.m_axis_ext_round_i_data(m_axis_conv_ext_round_i_data),
		.m_axis_ext_round_i_keep(m_axis_conv_ext_round_i_keep),
		.m_axis_ext_round_i_user(m_axis_conv_ext_round_i_user),
		.m_axis_ext_round_i_last(m_axis_conv_ext_round_i_last),
		.m_axis_ext_round_i_valid(m_axis_conv_ext_round_i_valid),
		.m_axis_ext_round_i_ready(m_axis_conv_ext_round_i_ready),
		.s_axis_ext_round_o_data(s_axis_conv_ext_round_o_data),
		.s_axis_ext_round_o_keep(s_axis_conv_ext_round_o_keep),
		.s_axis_ext_round_o_user(s_axis_conv_ext_round_o_user),
		.s_axis_ext_round_o_last(s_axis_conv_ext_round_o_last),
		.s_axis_ext_round_o_valid(s_axis_conv_ext_round_o_valid),
		.s_axis_ext_round_o_ready(s_axis_conv_ext_round_o_ready),
		
		.m_axis_ext_collector_data(m_axis_conv_ext_collector_data),
		.m_axis_ext_collector_keep(m_axis_conv_ext_collector_keep),
		.m_axis_ext_collector_last(m_axis_conv_ext_collector_last),
		.m_axis_ext_collector_valid(m_axis_conv_ext_collector_valid),
		.m_axis_ext_collector_ready(m_axis_conv_ext_collector_ready),
		
		.mm2s_0_cmd_done(mm2s_0_cmd_done),
		.mm2s_1_cmd_done(mm2s_1_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done)
	);
	
	/** AXI-通用池化处理单元(核心) **/
	// 使能信号
	wire en_pool_accelerator; // 使能池化加速器
	// (共享)数据枢纽
	// [运行时参数]
	wire[3:0] pool_data_hub_fmbufcoln; // 每个表面行的表面个数类型
	wire[9:0] pool_data_hub_fmbufrown; // 可缓存的表面行数 - 1
	wire pool_data_hub_fmrow_random_rd_mode; // 是否处于表面行随机读取模式
	wire pool_data_hub_grp_conv_buf_mode; // 是否处于组卷积缓存模式
	wire[7:0] pool_data_hub_fmbufbankn; // 分配给特征图缓存的Bank数
	// [特征图表面行读请求(AXIS主机)]
	wire[103:0] m_pool_fm_rd_req_axis_data;
	wire m_pool_fm_rd_req_axis_valid;
	wire m_pool_fm_rd_req_axis_ready;
	// 特征图表面行随机读取(AXIS主机)
	wire[15:0] m_pool_fm_random_rd_axis_data; // 表面号
	wire m_pool_fm_random_rd_axis_last; // 标志本次读请求待读取的最后1个表面
	wire m_pool_fm_random_rd_axis_valid;
	wire m_pool_fm_random_rd_axis_ready;
	// [特征图表面行数据(AXIS从机)]
	wire[ATOMIC_C*2*8-1:0] s_pool_fm_sfc_row_axis_data;
	wire s_pool_fm_sfc_row_axis_last; // 标志本次读请求的最后1个表面
	wire s_pool_fm_sfc_row_axis_valid;
	wire s_pool_fm_sfc_row_axis_ready;
	// (共享)最终结果传输请求生成单元
	// [运行时参数]
	wire[31:0] pool_fnl_res_tr_req_gen_ofmap_baseaddr; // 输出特征图基地址
	wire[15:0] pool_fnl_res_tr_req_gen_ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] pool_fnl_res_tr_req_gen_ofmap_h; // 输出特征图高度 - 1
	wire[1:0] pool_fnl_res_tr_req_gen_ofmap_data_type; // 输出特征图数据大小类型
	wire[15:0] pool_fnl_res_tr_req_gen_kernal_num_n; // 卷积核核数 - 1
	wire[5:0] pool_fnl_res_tr_req_gen_max_wgtblk_w; // 权重块最大宽度
	wire pool_fnl_res_tr_req_gen_is_grp_conv_mode; // 是否处于组卷积模式
	wire pool_fnl_res_tr_req_gen_en_send_sub_row_msg; // 是否输出子表面行信息
	// [块级控制]
	wire pool_fnl_res_tr_req_gen_blk_start;
	wire pool_fnl_res_tr_req_gen_blk_idle;
	wire pool_fnl_res_tr_req_gen_blk_done;
	// (共享)中间结果缓存
	// [使能信号]
	wire pool_en_mid_res_buf_dup; // 使能中间结果缓存
	// [运行时参数]
	wire[1:0] pool_mid_res_buf_calfmt; // 运算数据格式
	wire[3:0] pool_mid_res_buf_row_n_bufferable_dup; // 可缓存行数 - 1
	wire[3:0] pool_mid_res_buf_bank_n_foreach_ofmap_row; // 每个输出特征图行所占用的缓存MEM个数
	wire[3:0] pool_mid_res_buf_max_upd_latency; // 最大的更新时延
	wire pool_mid_res_buf_en_cal_round_ext; // 是否启用计算轮次拓展功能
	wire[15:0] pool_mid_res_buf_ofmap_w; // 输出特征图宽度 - 1
	wire[1:0] pool_mid_res_buf_pool_mode; // 池化模式
	// [性能监测]
	wire pool_en_upd_grp_run_cnt; // 使能更新单元组运行周期数计数器
	wire[31:0] pool_upd_grp_run_n; // 更新单元组运行周期数
	// [中间结果(AXIS主机)]
	wire[ATOMIC_C*48-1:0] m_axis_pool_ext_mid_res_data;
	wire[ATOMIC_C*6-1:0] m_axis_pool_ext_mid_res_keep;
	wire[3:0] m_axis_pool_ext_mid_res_user; // {本表面全0(标志), 是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire m_axis_pool_ext_mid_res_last; // 本行最后1个中间结果(标志)
	wire m_axis_pool_ext_mid_res_valid;
	wire m_axis_pool_ext_mid_res_ready;
	// [最终结果(AXIS从机)]
	wire[ATOMIC_C*32-1:0] s_axis_pool_ext_fnl_res_data; // ATOMIC_C个最终结果(单精度浮点数或定点数)
	wire[ATOMIC_C*4-1:0] s_axis_pool_ext_fnl_res_keep;
	wire s_axis_pool_ext_fnl_res_last; // 本行最后1个最终结果(标志)
	wire s_axis_pool_ext_fnl_res_valid;
	wire s_axis_pool_ext_fnl_res_ready;
	// (共享)BN与激活单元
	// [使能信号]
	wire pool_en_bn_act_proc_dup; // 使能处理单元
	// [运行时参数]
	wire[1:0] pool_bn_act_calfmt; // 运算数据格式
	wire pool_bn_act_use_bn_unit; // 启用BN单元
	wire[2:0] pool_bn_act_act_func_type; // 激活函数类型
	wire[4:0] pool_bn_act_bn_fixed_point_quat_accrc; // (操作数A)定点数量化精度
	wire pool_bn_act_bn_is_a_eq_1; // 参数A的实际值为1(标志)
	wire pool_bn_act_bn_is_b_eq_0; // 参数B的实际值为0(标志)
	wire pool_bn_act_is_in_const_mac_mode; // 是否处于常量乘加模式
	wire[31:0] pool_bn_act_param_a_in_const_mac_mode; // 常量乘加模式下的参数A
	wire[31:0] pool_bn_act_param_b_in_const_mac_mode; // 常量乘加模式下的参数B
	// [后乘加处理输入(AXIS主机)]
	wire[ATOMIC_C*32-1:0] m_axis_pool_ext_bn_act_i_data; // 对于ATOMIC_C个最终结果 -> {单精度浮点数或定点数(32位)}
	wire[ATOMIC_C*4-1:0] m_axis_pool_ext_bn_act_i_keep;
	wire[4:0] m_axis_pool_ext_bn_act_i_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_pool_ext_bn_act_i_last; // 本行最后1个最终结果(标志)
	wire m_axis_pool_ext_bn_act_i_valid;
	wire m_axis_pool_ext_bn_act_i_ready;
	// [后乘加处理结果(AXIS从机)]
	wire[BN_ACT_PRL_N*32-1:0] s_axis_pool_ext_bn_act_o_data; // 对于BN_ACT_PRL_N个最终结果 -> {浮点数或定点数}
	wire[BN_ACT_PRL_N*4-1:0] s_axis_pool_ext_bn_act_o_keep;
	wire[4:0] s_axis_pool_ext_bn_act_o_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire s_axis_pool_ext_bn_act_o_last; // 本行最后1个处理结果(标志)
	wire s_axis_pool_ext_bn_act_o_valid;
	wire s_axis_pool_ext_bn_act_o_ready;
	// (共享)输出数据舍入单元组
	// [运行时参数]
	wire[1:0] pool_round_calfmt; // 运算数据格式
	wire[3:0] pool_round_fixed_point_quat_accrc; // 定点数量化精度
	// [待舍入数据(AXIS主机)]
	wire[ATOMIC_C*32-1:0] m_axis_pool_ext_round_i_data; // ATOMIC_C个定点数或FP32
	wire[ATOMIC_C*4-1:0] m_axis_pool_ext_round_i_keep;
	wire[4:0] m_axis_pool_ext_round_i_user;
	wire m_axis_pool_ext_round_i_last;
	wire m_axis_pool_ext_round_i_valid;
	wire m_axis_pool_ext_round_i_ready;
	// [舍入后数据(AXIS从机)]
	wire[ATOMIC_C*16-1:0] s_axis_pool_ext_round_o_data; // ATOMIC_C个定点数或浮点数
	wire[ATOMIC_C*2-1:0] s_axis_pool_ext_round_o_keep;
	wire[4:0] s_axis_pool_ext_round_o_user;
	wire s_axis_pool_ext_round_o_last;
	wire s_axis_pool_ext_round_o_valid;
	wire s_axis_pool_ext_round_o_ready;
	// (共享)最终结果数据收集器
	// [待收集的数据流(AXIS主机)]
	wire[ATOMIC_C*(FP32_KEEP ? 32:16)-1:0] m_axis_pool_ext_collector_data;
	wire[ATOMIC_C*(FP32_KEEP ? 4:2)-1:0] m_axis_pool_ext_collector_keep;
	wire m_axis_pool_ext_collector_last;
	wire m_axis_pool_ext_collector_valid;
	wire m_axis_pool_ext_collector_ready;
	
	axi_generic_pool_core #(
		.MID_RES_BUF_CLK_RATE(MID_RES_BUF_CLK_RATE),
		.ACCELERATOR_ID(POOL_ACCELERATOR_ID),
		.MAX_POOL_SUPPORTED(MAX_POOL_SUPPORTED),
		.AVG_POOL_SUPPORTED(AVG_POOL_SUPPORTED),
		.UP_SAMPLE_SUPPORTED(UP_SAMPLE_SUPPORTED),
		.POST_MAC_SUPPORTED(POOL_POST_MAC_SUPPORTED),
		.INT8_SUPPORTED(INT8_SUPPORTED),
		.INT16_SUPPORTED(INT16_SUPPORTED),
		.FP16_SUPPORTED(FP16_SUPPORTED),
		.EXT_PADDING_SUPPORTED(POOL_EXT_PADDING_SUPPORTED),
		.NON_ZERO_CONST_PADDING_SUPPORTED(NON_ZERO_CONST_PADDING_SUPPORTED),
		.EN_PERF_MON(EN_PERF_MON),
		.KEEP_FP32_OUT(FP32_KEEP),
		.ATOMIC_C(ATOMIC_C),
		.POST_MAC_PRL_N(BN_ACT_PRL_N),
		.MM2S_STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.S2MM_STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.SIM_DELAY(SIM_DELAY)
	)axi_generic_pool_core_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.en_accelerator(en_pool_accelerator),
		
		.s_axi_lite_araddr(s_axi_lite_pool_araddr),
		.s_axi_lite_arvalid(s_axi_lite_pool_arvalid),
		.s_axi_lite_arready(s_axi_lite_pool_arready),
		.s_axi_lite_awaddr(s_axi_lite_pool_awaddr),
		.s_axi_lite_awvalid(s_axi_lite_pool_awvalid),
		.s_axi_lite_awready(s_axi_lite_pool_awready),
		.s_axi_lite_bresp(s_axi_lite_pool_bresp),
		.s_axi_lite_bvalid(s_axi_lite_pool_bvalid),
		.s_axi_lite_bready(s_axi_lite_pool_bready),
		.s_axi_lite_rdata(s_axi_lite_pool_rdata),
		.s_axi_lite_rresp(s_axi_lite_pool_rresp),
		.s_axi_lite_rvalid(s_axi_lite_pool_rvalid),
		.s_axi_lite_rready(s_axi_lite_pool_rready),
		.s_axi_lite_wdata(s_axi_lite_pool_wdata),
		.s_axi_lite_wvalid(s_axi_lite_pool_wvalid),
		.s_axi_lite_wready(s_axi_lite_pool_wready),
		
		.s_dma_strm_axis_keep(s0_dma_strm_axis_keep),
		.s_dma_strm_axis_valid(s0_dma_strm_axis_valid),
		.s_dma_strm_axis_ready(s0_dma_strm_axis_ready),
		
		.s_axis_fnl_res_keep(m_axis_fnl_res_keep),
		.s_axis_fnl_res_valid(m_axis_fnl_res_valid),
		.s_axis_fnl_res_ready(m_axis_fnl_res_ready),
		
		.mm2s_cmd_done(mm2s_0_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done),
		
		.data_hub_fmbufcoln(pool_data_hub_fmbufcoln),
		.data_hub_fmbufrown(pool_data_hub_fmbufrown),
		.data_hub_fmrow_random_rd_mode(pool_data_hub_fmrow_random_rd_mode),
		.data_hub_grp_conv_buf_mode(pool_data_hub_grp_conv_buf_mode),
		.data_hub_fmbufbankn(pool_data_hub_fmbufbankn),
		.m_fm_rd_req_axis_data(m_pool_fm_rd_req_axis_data),
		.m_fm_rd_req_axis_valid(m_pool_fm_rd_req_axis_valid),
		.m_fm_rd_req_axis_ready(m_pool_fm_rd_req_axis_ready),
		.m_fm_random_rd_axis_data(m_pool_fm_random_rd_axis_data),
		.m_fm_random_rd_axis_last(m_pool_fm_random_rd_axis_last),
		.m_fm_random_rd_axis_valid(m_pool_fm_random_rd_axis_valid),
		.m_fm_random_rd_axis_ready(m_pool_fm_random_rd_axis_ready),
		.s_fm_sfc_row_axis_data(s_pool_fm_sfc_row_axis_data),
		.s_fm_sfc_row_axis_last(s_pool_fm_sfc_row_axis_last),
		.s_fm_sfc_row_axis_valid(s_pool_fm_sfc_row_axis_valid),
		.s_fm_sfc_row_axis_ready(s_pool_fm_sfc_row_axis_ready),
		
		.fnl_res_tr_req_gen_ofmap_baseaddr(pool_fnl_res_tr_req_gen_ofmap_baseaddr),
		.fnl_res_tr_req_gen_ofmap_w(pool_fnl_res_tr_req_gen_ofmap_w),
		.fnl_res_tr_req_gen_ofmap_h(pool_fnl_res_tr_req_gen_ofmap_h),
		.fnl_res_tr_req_gen_ofmap_data_type(pool_fnl_res_tr_req_gen_ofmap_data_type),
		.fnl_res_tr_req_gen_kernal_num_n(pool_fnl_res_tr_req_gen_kernal_num_n),
		.fnl_res_tr_req_gen_max_wgtblk_w(pool_fnl_res_tr_req_gen_max_wgtblk_w),
		.fnl_res_tr_req_gen_is_grp_conv_mode(pool_fnl_res_tr_req_gen_is_grp_conv_mode),
		.fnl_res_tr_req_gen_en_send_sub_row_msg(pool_fnl_res_tr_req_gen_en_send_sub_row_msg),
		.fnl_res_tr_req_gen_blk_start(pool_fnl_res_tr_req_gen_blk_start),
		.fnl_res_tr_req_gen_blk_idle(pool_fnl_res_tr_req_gen_blk_idle),
		.fnl_res_tr_req_gen_blk_done(pool_fnl_res_tr_req_gen_blk_done),
		
		.en_mid_res_buf_dup(pool_en_mid_res_buf_dup),
		.mid_res_buf_calfmt(pool_mid_res_buf_calfmt),
		.mid_res_buf_row_n_bufferable_dup(pool_mid_res_buf_row_n_bufferable_dup),
		.mid_res_buf_bank_n_foreach_ofmap_row(pool_mid_res_buf_bank_n_foreach_ofmap_row),
		.mid_res_buf_max_upd_latency(pool_mid_res_buf_max_upd_latency),
		.mid_res_buf_en_cal_round_ext(pool_mid_res_buf_en_cal_round_ext),
		.mid_res_buf_ofmap_w(pool_mid_res_buf_ofmap_w),
		.mid_res_buf_pool_mode(pool_mid_res_buf_pool_mode),
		.en_upd_grp_run_cnt(pool_en_upd_grp_run_cnt),
		.upd_grp_run_n(pool_upd_grp_run_n),
		.m_axis_ext_mid_res_data(m_axis_pool_ext_mid_res_data),
		.m_axis_ext_mid_res_keep(m_axis_pool_ext_mid_res_keep),
		.m_axis_ext_mid_res_user(m_axis_pool_ext_mid_res_user),
		.m_axis_ext_mid_res_last(m_axis_pool_ext_mid_res_last),
		.m_axis_ext_mid_res_valid(m_axis_pool_ext_mid_res_valid),
		.m_axis_ext_mid_res_ready(m_axis_pool_ext_mid_res_ready),
		.s_axis_ext_fnl_res_data(s_axis_pool_ext_fnl_res_data),
		.s_axis_ext_fnl_res_keep(s_axis_pool_ext_fnl_res_keep),
		.s_axis_ext_fnl_res_last(s_axis_pool_ext_fnl_res_last),
		.s_axis_ext_fnl_res_valid(s_axis_pool_ext_fnl_res_valid),
		.s_axis_ext_fnl_res_ready(s_axis_pool_ext_fnl_res_ready),
		
		.en_bn_act_proc_dup(pool_en_bn_act_proc_dup),
		.bn_act_calfmt(pool_bn_act_calfmt),
		.bn_act_use_bn_unit(pool_bn_act_use_bn_unit),
		.bn_act_act_func_type(pool_bn_act_act_func_type),
		.bn_act_bn_fixed_point_quat_accrc(pool_bn_act_bn_fixed_point_quat_accrc),
		.bn_act_bn_is_a_eq_1(pool_bn_act_bn_is_a_eq_1),
		.bn_act_bn_is_b_eq_0(pool_bn_act_bn_is_b_eq_0),
		.bn_act_is_in_const_mac_mode(pool_bn_act_is_in_const_mac_mode),
		.bn_act_param_a_in_const_mac_mode(pool_bn_act_param_a_in_const_mac_mode),
		.bn_act_param_b_in_const_mac_mode(pool_bn_act_param_b_in_const_mac_mode),
		.m_axis_ext_bn_act_i_data(m_axis_pool_ext_bn_act_i_data),
		.m_axis_ext_bn_act_i_keep(m_axis_pool_ext_bn_act_i_keep),
		.m_axis_ext_bn_act_i_user(m_axis_pool_ext_bn_act_i_user),
		.m_axis_ext_bn_act_i_last(m_axis_pool_ext_bn_act_i_last),
		.m_axis_ext_bn_act_i_valid(m_axis_pool_ext_bn_act_i_valid),
		.m_axis_ext_bn_act_i_ready(m_axis_pool_ext_bn_act_i_ready),
		.s_axis_ext_bn_act_o_data(s_axis_pool_ext_bn_act_o_data),
		.s_axis_ext_bn_act_o_keep(s_axis_pool_ext_bn_act_o_keep),
		.s_axis_ext_bn_act_o_user(s_axis_pool_ext_bn_act_o_user),
		.s_axis_ext_bn_act_o_last(s_axis_pool_ext_bn_act_o_last),
		.s_axis_ext_bn_act_o_valid(s_axis_pool_ext_bn_act_o_valid),
		.s_axis_ext_bn_act_o_ready(s_axis_pool_ext_bn_act_o_ready),
		
		.round_calfmt(pool_round_calfmt),
		.round_fixed_point_quat_accrc(pool_round_fixed_point_quat_accrc),
		.m_axis_ext_round_i_data(m_axis_pool_ext_round_i_data),
		.m_axis_ext_round_i_keep(m_axis_pool_ext_round_i_keep),
		.m_axis_ext_round_i_user(m_axis_pool_ext_round_i_user),
		.m_axis_ext_round_i_last(m_axis_pool_ext_round_i_last),
		.m_axis_ext_round_i_valid(m_axis_pool_ext_round_i_valid),
		.m_axis_ext_round_i_ready(m_axis_pool_ext_round_i_ready),
		.s_axis_ext_round_o_data(s_axis_pool_ext_round_o_data),
		.s_axis_ext_round_o_keep(s_axis_pool_ext_round_o_keep),
		.s_axis_ext_round_o_user(s_axis_pool_ext_round_o_user),
		.s_axis_ext_round_o_last(s_axis_pool_ext_round_o_last),
		.s_axis_ext_round_o_valid(s_axis_pool_ext_round_o_valid),
		.s_axis_ext_round_o_ready(s_axis_pool_ext_round_o_ready),
		
		.m_axis_ext_collector_data(m_axis_pool_ext_collector_data),
		.m_axis_ext_collector_keep(m_axis_pool_ext_collector_keep),
		.m_axis_ext_collector_last(m_axis_pool_ext_collector_last),
		.m_axis_ext_collector_valid(m_axis_pool_ext_collector_valid),
		.m_axis_ext_collector_ready(m_axis_pool_ext_collector_ready)
	);
	
	/** AXI-逐元素操作处理单元 **/
	// 使能逐元素操作处理单元
	wire en_elm_proc_accelerator;
	// DMA(MM2S方向)命令流#0(AXIS主机)
	wire[55:0] m0_elm_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m0_elm_dma_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m0_elm_dma_cmd_axis_last; // 帧尾标志
	wire m0_elm_dma_cmd_axis_valid;
	wire m0_elm_dma_cmd_axis_ready;
	// DMA(MM2S方向)数据流#0(AXIS从机)
	wire[MM2S_STREAM_DATA_WIDTH-1:0] s0_elm_dma_strm_axis_data;
	wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s0_elm_dma_strm_axis_keep;
	wire s0_elm_dma_strm_axis_last;
	wire s0_elm_dma_strm_axis_valid;
	wire s0_elm_dma_strm_axis_ready;
	// DMA(MM2S方向)命令流#1(AXIS主机)
	wire[55:0] m1_elm_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m1_elm_dma_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m1_elm_dma_cmd_axis_last; // 帧尾标志
	wire m1_elm_dma_cmd_axis_valid;
	wire m1_elm_dma_cmd_axis_ready;
	// DMA(MM2S方向)数据流#1(AXIS从机)
	wire[MM2S_STREAM_DATA_WIDTH-1:0] s1_elm_dma_strm_axis_data;
	wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s1_elm_dma_strm_axis_keep;
	wire s1_elm_dma_strm_axis_last;
	wire s1_elm_dma_strm_axis_valid;
	wire s1_elm_dma_strm_axis_ready;
	// DMA(S2MM方向)命令流(AXIS主机)
	wire[55:0] m_elm_dma_s2mm_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_elm_dma_s2mm_cmd_axis_user; // 固定(1'b1)/递增(1'b0)传输(1bit)
	wire m_elm_dma_s2mm_cmd_axis_valid;
	wire m_elm_dma_s2mm_cmd_axis_ready;
	// DMA(S2MM方向)数据流(AXIS主机)
	wire[S2MM_STREAM_DATA_WIDTH-1:0] m_elm_dma_strm_axis_data;
	wire[S2MM_STREAM_DATA_WIDTH/8-1:0] m_elm_dma_strm_axis_keep;
	wire m_elm_dma_strm_axis_last;
	wire m_elm_dma_strm_axis_valid;
	wire m_elm_dma_strm_axis_ready;
	
	assign en_elm_proc_accelerator = axi_element_wise_proc_u.en_accelerator;
	
	axi_element_wise_proc #(
		.ACCELERATOR_ID(ELM_PROC_ACCELERATOR_ID),
		.MM2S_STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.S2MM_STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.ELEMENT_WISE_PROC_PIPELINE_N(ELEMENT_WISE_PROC_PIPELINE_N),
		.FU_CLK_RATE(ELM_PROC_FU_CLK_RATE),
		.IN_STRM_WIDTH_1_BYTE_SUPPORTED(ELM_PROC_IN_STRM_WIDTH_1_BYTE_SUPPORTED),
		.IN_STRM_WIDTH_2_BYTE_SUPPORTED(ELM_PROC_IN_STRM_WIDTH_2_BYTE_SUPPORTED),
		.IN_STRM_WIDTH_4_BYTE_SUPPORTED(ELM_PROC_IN_STRM_WIDTH_4_BYTE_SUPPORTED),
		.OUT_STRM_WIDTH_1_BYTE_SUPPORTED(ELM_PROC_OUT_STRM_WIDTH_1_BYTE_SUPPORTED),
		.OUT_STRM_WIDTH_2_BYTE_SUPPORTED(ELM_PROC_OUT_STRM_WIDTH_2_BYTE_SUPPORTED),
		.OUT_STRM_WIDTH_4_BYTE_SUPPORTED(ELM_PROC_OUT_STRM_WIDTH_4_BYTE_SUPPORTED),
		.EN_IN_DATA_CVT(ELM_PROC_EN_IN_DATA_CVT),
		.IN_DATA_CVT_EN_ROUND(ELM_PROC_IN_DATA_CVT_EN_ROUND),
		.IN_DATA_CVT_FP16_IN_DATA_SUPPORTED(ELM_PROC_IN_DATA_CVT_FP16_IN_DATA_SUPPORTED),
		.IN_DATA_CVT_S33_IN_DATA_SUPPORTED(ELM_PROC_IN_DATA_CVT_S33_IN_DATA_SUPPORTED),
		.EN_POW2_CAL_UNIT(ELM_PROC_EN_POW2_CAL_UNIT),
		.EN_MAC_UNIT(ELM_PROC_EN_MAC_UNIT),
		.CAL_EN_ROUND(ELM_PROC_CAL_EN_ROUND),
		.CAL_INT16_SUPPORTED(ELM_PROC_CAL_INT16_SUPPORTED),
		.CAL_INT32_SUPPORTED(ELM_PROC_CAL_INT32_SUPPORTED),
		.CAL_FP32_SUPPORTED(ELM_PROC_CAL_FP32_SUPPORTED),
		.EN_OUT_DATA_CVT(ELM_PROC_EN_OUT_DATA_CVT),
		.OUT_DATA_CVT_EN_ROUND(ELM_PROC_OUT_DATA_CVT_EN_ROUND),
		.OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED(ELM_PROC_OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED),
		.EN_ROUND_UNIT(ELM_PROC_EN_ROUND_UNIT),
		.ROUND_S33_ROUND_SUPPORTED(ELM_PROC_ROUND_S33_ROUND_SUPPORTED),
		.ROUND_FP32_ROUND_SUPPORTED(ELM_PROC_ROUND_FP32_ROUND_SUPPORTED),
		.EN_PERF_MON(EN_PERF_MON),
		.SIM_DELAY(SIM_DELAY)
	)axi_element_wise_proc_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.proc_aclk(elm_proc_aclk),
		.proc_aresetn(elm_proc_aresetn),
		
		.s_axi_lite_araddr(s_axi_lite_elm_araddr),
		.s_axi_lite_arvalid(s_axi_lite_elm_arvalid),
		.s_axi_lite_arready(s_axi_lite_elm_arready),
		.s_axi_lite_awaddr(s_axi_lite_elm_awaddr),
		.s_axi_lite_awvalid(s_axi_lite_elm_awvalid),
		.s_axi_lite_awready(s_axi_lite_elm_awready),
		.s_axi_lite_bresp(s_axi_lite_elm_bresp),
		.s_axi_lite_bvalid(s_axi_lite_elm_bvalid),
		.s_axi_lite_bready(s_axi_lite_elm_bready),
		.s_axi_lite_rdata(s_axi_lite_elm_rdata),
		.s_axi_lite_rresp(s_axi_lite_elm_rresp),
		.s_axi_lite_rvalid(s_axi_lite_elm_rvalid),
		.s_axi_lite_rready(s_axi_lite_elm_rready),
		.s_axi_lite_wdata(s_axi_lite_elm_wdata),
		.s_axi_lite_wvalid(s_axi_lite_elm_wvalid),
		.s_axi_lite_wready(s_axi_lite_elm_wready),
		
		.mm2s_0_cmd_done(mm2s_0_cmd_done),
		.mm2s_1_cmd_done(mm2s_1_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done),
		
		.m0_dma_cmd_axis_data(m0_elm_dma_cmd_axis_data),
		.m0_dma_cmd_axis_user(m0_elm_dma_cmd_axis_user),
		.m0_dma_cmd_axis_last(m0_elm_dma_cmd_axis_last),
		.m0_dma_cmd_axis_valid(m0_elm_dma_cmd_axis_valid),
		.m0_dma_cmd_axis_ready(m0_elm_dma_cmd_axis_ready),
		
		.s0_dma_strm_axis_data(s0_elm_dma_strm_axis_data),
		.s0_dma_strm_axis_keep(s0_elm_dma_strm_axis_keep),
		.s0_dma_strm_axis_last(s0_elm_dma_strm_axis_last),
		.s0_dma_strm_axis_valid(s0_elm_dma_strm_axis_valid),
		.s0_dma_strm_axis_ready(s0_elm_dma_strm_axis_ready),
		
		.m1_dma_cmd_axis_data(m1_elm_dma_cmd_axis_data),
		.m1_dma_cmd_axis_user(m1_elm_dma_cmd_axis_user),
		.m1_dma_cmd_axis_last(m1_elm_dma_cmd_axis_last),
		.m1_dma_cmd_axis_valid(m1_elm_dma_cmd_axis_valid),
		.m1_dma_cmd_axis_ready(m1_elm_dma_cmd_axis_ready),
		
		.s1_dma_strm_axis_data(s1_elm_dma_strm_axis_data),
		.s1_dma_strm_axis_keep(s1_elm_dma_strm_axis_keep),
		.s1_dma_strm_axis_last(s1_elm_dma_strm_axis_last),
		.s1_dma_strm_axis_valid(s1_elm_dma_strm_axis_valid),
		.s1_dma_strm_axis_ready(s1_elm_dma_strm_axis_ready),
		
		.m_dma_s2mm_cmd_axis_data(m_elm_dma_s2mm_cmd_axis_data),
		.m_dma_s2mm_cmd_axis_user(m_elm_dma_s2mm_cmd_axis_user),
		.m_dma_s2mm_cmd_axis_valid(m_elm_dma_s2mm_cmd_axis_valid),
		.m_dma_s2mm_cmd_axis_ready(m_elm_dma_s2mm_cmd_axis_ready),
		
		.m_dma_strm_axis_data(m_elm_dma_strm_axis_data),
		.m_dma_strm_axis_keep(m_elm_dma_strm_axis_keep),
		.m_dma_strm_axis_last(m_elm_dma_strm_axis_last),
		.m_dma_strm_axis_valid(m_elm_dma_strm_axis_valid),
		.m_dma_strm_axis_ready(m_elm_dma_strm_axis_ready)
	);
	
	/** (共享)数据枢纽 **/
	// 运行时参数
	wire[3:0] data_hub_fmbufcoln; // 每个表面行的表面个数类型
	wire[9:0] data_hub_fmbufrown; // 可缓存的表面行数 - 1
	wire data_hub_fmrow_random_rd_mode; // 是否处于表面行随机读取模式
	wire data_hub_is_grp_conv_mode; // 是否处于组卷积缓存模式
	wire[2:0] data_hub_kernal_shape; // 卷积核形状
	wire[2:0] data_hub_sfc_n_each_wgtblk; // 每个权重块的表面个数的类型
	wire[7:0] data_hub_kbufgrpn; // 可缓存的通道组数 - 1
	wire[7:0] data_hub_fmbufbankn; // 分配给特征图缓存的Bank数
	// 特征图表面行读请求(AXIS从机)
	wire[103:0] s_data_hub_fm_rd_req_axis_data;
	wire s_data_hub_fm_rd_req_axis_valid;
	wire s_data_hub_fm_rd_req_axis_ready;
	// 特征图表面行随机读取(AXIS从机)
	wire[15:0] s_data_hub_fm_random_rd_axis_data; // 表面号
	wire s_data_hub_fm_random_rd_axis_last; // 标志本次读请求待读取的最后1个表面
	wire s_data_hub_fm_random_rd_axis_valid;
	wire s_data_hub_fm_random_rd_axis_ready;
	// 卷积核权重块读请求(AXIS从机)
	wire[103:0] s_data_hub_kwgtblk_rd_req_axis_data;
	wire s_data_hub_kwgtblk_rd_req_axis_valid;
	wire s_data_hub_kwgtblk_rd_req_axis_ready;
	// 特征图表面行数据输出(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_data_hub_fm_fout_axis_data;
	wire m_data_hub_fm_fout_axis_last; // 标志本次读请求的最后1个表面
	wire m_data_hub_fm_fout_axis_valid;
	wire m_data_hub_fm_fout_axis_ready;
	// 卷积核权重块数据输出(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_data_hub_kout_wgtblk_axis_data;
	wire m_data_hub_kout_wgtblk_axis_last; // 标志本次读请求的最后1个表面
	wire m_data_hub_kout_wgtblk_axis_valid;
	wire m_data_hub_kout_wgtblk_axis_ready;
	// DMA(MM2S方向)命令流#0(AXIS主机)
	wire[55:0] m0_conv_pool_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m0_conv_pool_dma_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m0_conv_pool_dma_cmd_axis_last; // 帧尾标志
	wire m0_conv_pool_dma_cmd_axis_valid;
	wire m0_conv_pool_dma_cmd_axis_ready;
	// DMA(MM2S方向)数据流#0(AXIS从机)
	wire[MM2S_STREAM_DATA_WIDTH-1:0] s0_conv_pool_dma_strm_axis_data;
	wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s0_conv_pool_dma_strm_axis_keep;
	wire s0_conv_pool_dma_strm_axis_last;
	wire s0_conv_pool_dma_strm_axis_valid;
	wire s0_conv_pool_dma_strm_axis_ready;
	// DMA(MM2S方向)命令流#1(AXIS主机)
	wire[55:0] m1_conv_pool_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m1_conv_pool_dma_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m1_conv_pool_dma_cmd_axis_last; // 帧尾标志
	wire m1_conv_pool_dma_cmd_axis_valid;
	wire m1_conv_pool_dma_cmd_axis_ready;
	// DMA(MM2S方向)数据流#1(AXIS从机)
	wire[MM2S_STREAM_DATA_WIDTH-1:0] s1_conv_pool_dma_strm_axis_data;
	wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s1_conv_pool_dma_strm_axis_keep;
	wire s1_conv_pool_dma_strm_axis_last;
	wire s1_conv_pool_dma_strm_axis_valid;
	wire s1_conv_pool_dma_strm_axis_ready;
	// 实际表面行号映射表MEM主接口
	wire actual_rid_mp_tb_mem_clk;
	wire actual_rid_mp_tb_mem_wen_a;
	wire[11:0] actual_rid_mp_tb_mem_addr_a;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_din_a;
	wire actual_rid_mp_tb_mem_ren_b;
	wire[11:0] actual_rid_mp_tb_mem_addr_b;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_dout_b;
	// 缓存行号映射表MEM主接口
	wire buffer_rid_mp_tb_mem_clk;
	wire buffer_rid_mp_tb_mem_wen_a;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_a;
	wire[11:0] buffer_rid_mp_tb_mem_din_a;
	wire buffer_rid_mp_tb_mem_ren_b;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_b;
	wire[11:0] buffer_rid_mp_tb_mem_dout_b;
	// 物理缓存的MEM主接口
	wire phy_conv_buf_mem_clk_a;
	wire[CBUF_BANK_N-1:0] phy_conv_buf_mem_en_a;
	wire[CBUF_BANK_N*ATOMIC_C*2-1:0] phy_conv_buf_mem_wen_a;
	wire[CBUF_BANK_N*16-1:0] phy_conv_buf_mem_addr_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_din_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_dout_a;
	wire phy_conv_buf_mem_clk_b;
	wire[CBUF_BANK_N-1:0] phy_conv_buf_mem_en_b;
	wire[CBUF_BANK_N*ATOMIC_C*2-1:0] phy_conv_buf_mem_wen_b;
	wire[CBUF_BANK_N*16-1:0] phy_conv_buf_mem_addr_b;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_din_b;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_dout_b;
	
	assign data_hub_fmbufcoln = 
		({4{en_conv_accelerator}} & conv_data_hub_fmbufcoln) | 
		({4{en_pool_accelerator}} & pool_data_hub_fmbufcoln);
	assign data_hub_fmbufrown = 
		({10{en_conv_accelerator}} & conv_data_hub_fmbufrown) | 
		({10{en_pool_accelerator}} & pool_data_hub_fmbufrown);
	assign data_hub_fmrow_random_rd_mode = 
		en_pool_accelerator;
	assign data_hub_is_grp_conv_mode = 
		(en_conv_accelerator & conv_data_hub_is_grp_conv_mode) | 
		(en_pool_accelerator & pool_data_hub_grp_conv_buf_mode);
	assign data_hub_kernal_shape = 
		conv_data_hub_kernal_shape;
	assign data_hub_sfc_n_each_wgtblk = 
		conv_data_hub_sfc_n_each_wgtblk;
	assign data_hub_kbufgrpn = 
		conv_data_hub_kbufgrpn;
	assign data_hub_fmbufbankn = 
		({8{en_conv_accelerator}} & conv_data_hub_fmbufbankn) | 
		({8{en_pool_accelerator}} & pool_data_hub_fmbufbankn);
	
	assign s_data_hub_fm_rd_req_axis_data = 
		({104{en_conv_accelerator}} & m_conv_fm_rd_req_axis_data) | 
		({104{en_pool_accelerator}} & m_pool_fm_rd_req_axis_data);
	assign s_data_hub_fm_rd_req_axis_valid = 
		(en_conv_accelerator & m_conv_fm_rd_req_axis_valid) | 
		(en_pool_accelerator & m_pool_fm_rd_req_axis_valid);
	assign m_conv_fm_rd_req_axis_ready = 
		(~en_conv_accelerator) | s_data_hub_fm_rd_req_axis_ready;
	assign m_pool_fm_rd_req_axis_ready = 
		(~en_pool_accelerator) | s_data_hub_fm_rd_req_axis_ready;
	
	assign s_data_hub_fm_random_rd_axis_data = m_pool_fm_random_rd_axis_data;
	assign s_data_hub_fm_random_rd_axis_last = m_pool_fm_random_rd_axis_last;
	assign s_data_hub_fm_random_rd_axis_valid = en_pool_accelerator & m_pool_fm_random_rd_axis_valid;
	assign m_pool_fm_random_rd_axis_ready = (~en_pool_accelerator) | s_data_hub_fm_random_rd_axis_ready;
	
	assign s_data_hub_kwgtblk_rd_req_axis_data = m_conv_kwgtblk_rd_req_axis_data;
	assign s_data_hub_kwgtblk_rd_req_axis_valid = en_conv_accelerator & m_conv_kwgtblk_rd_req_axis_valid;
	assign m_conv_kwgtblk_rd_req_axis_ready = (~en_conv_accelerator) | s_data_hub_kwgtblk_rd_req_axis_ready;
	
	assign s_conv_fm_sfc_row_axis_data = m_data_hub_fm_fout_axis_data;
	assign s_conv_fm_sfc_row_axis_last = m_data_hub_fm_fout_axis_last;
	assign s_conv_fm_sfc_row_axis_valid = en_conv_accelerator & m_data_hub_fm_fout_axis_valid;
	assign s_pool_fm_sfc_row_axis_data = m_data_hub_fm_fout_axis_data;
	assign s_pool_fm_sfc_row_axis_last = m_data_hub_fm_fout_axis_last;
	assign s_pool_fm_sfc_row_axis_valid = en_pool_accelerator & m_data_hub_fm_fout_axis_valid;
	assign m_data_hub_fm_fout_axis_ready = 
		(en_conv_accelerator & s_conv_fm_sfc_row_axis_ready) | 
		(en_pool_accelerator & s_pool_fm_sfc_row_axis_ready);
	
	assign s_conv_kernal_wgtblk_axis_data = m_data_hub_kout_wgtblk_axis_data;
	assign s_conv_kernal_wgtblk_axis_last = m_data_hub_kout_wgtblk_axis_last;
	assign s_conv_kernal_wgtblk_axis_valid = en_conv_accelerator & m_data_hub_kout_wgtblk_axis_valid;
	assign m_data_hub_kout_wgtblk_axis_ready = en_conv_accelerator & s_conv_kernal_wgtblk_axis_ready;
	
	conv_data_hub #(
		.STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.ATOMIC_C(ATOMIC_C),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.FM_RD_REQ_PRE_ACPT_N(4),
		.KWGTBLK_RD_REQ_PRE_ACPT_N(4),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.LG_FMBUF_BUFFER_RID_WIDTH(LG_FMBUF_BUFFER_RID_WIDTH),
		.EN_REG_SLICE_IN_FM_RD_REQ("true"),
		.EN_REG_SLICE_IN_KWGTBLK_RD_REQ("true"),
		.PHY_BUF_USE_TRUE_DUAL_PORT_SRAM(PHY_BUF_USE_TRUE_DUAL_PORT_SRAM ? "true":"false"),
		.SIM_DELAY(SIM_DELAY)
	)conv_data_hub_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.fmbufcoln(data_hub_fmbufcoln),
		.fmbufrown(data_hub_fmbufrown),
		.fmrow_random_rd_mode(data_hub_fmrow_random_rd_mode),
		.grp_conv_buf_mode(data_hub_is_grp_conv_mode),
		.kbufgrpsz(data_hub_kernal_shape),
		.sfc_n_each_wgtblk(data_hub_sfc_n_each_wgtblk),
		.kbufgrpn(data_hub_kbufgrpn),
		.fmbufbankn(data_hub_fmbufbankn),
		
		.s_fm_rd_req_axis_data(s_data_hub_fm_rd_req_axis_data),
		.s_fm_rd_req_axis_valid(s_data_hub_fm_rd_req_axis_valid),
		.s_fm_rd_req_axis_ready(s_data_hub_fm_rd_req_axis_ready),
		
		.s_fm_random_rd_axis_data(s_data_hub_fm_random_rd_axis_data),
		.s_fm_random_rd_axis_last(s_data_hub_fm_random_rd_axis_last),
		.s_fm_random_rd_axis_valid(s_data_hub_fm_random_rd_axis_valid),
		.s_fm_random_rd_axis_ready(s_data_hub_fm_random_rd_axis_ready),
		
		.s_kwgtblk_rd_req_axis_data(s_data_hub_kwgtblk_rd_req_axis_data),
		.s_kwgtblk_rd_req_axis_valid(s_data_hub_kwgtblk_rd_req_axis_valid),
		.s_kwgtblk_rd_req_axis_ready(s_data_hub_kwgtblk_rd_req_axis_ready),
		
		.m_fm_fout_axis_data(m_data_hub_fm_fout_axis_data),
		.m_fm_fout_axis_last(m_data_hub_fm_fout_axis_last),
		.m_fm_fout_axis_valid(m_data_hub_fm_fout_axis_valid),
		.m_fm_fout_axis_ready(m_data_hub_fm_fout_axis_ready),
		
		.m_kout_wgtblk_axis_data(m_data_hub_kout_wgtblk_axis_data),
		.m_kout_wgtblk_axis_last(m_data_hub_kout_wgtblk_axis_last),
		.m_kout_wgtblk_axis_valid(m_data_hub_kout_wgtblk_axis_valid),
		.m_kout_wgtblk_axis_ready(m_data_hub_kout_wgtblk_axis_ready),
		
		.m0_dma_cmd_axis_data(m0_conv_pool_dma_cmd_axis_data),
		.m0_dma_cmd_axis_user(m0_conv_pool_dma_cmd_axis_user),
		.m0_dma_cmd_axis_last(m0_conv_pool_dma_cmd_axis_last),
		.m0_dma_cmd_axis_valid(m0_conv_pool_dma_cmd_axis_valid),
		.m0_dma_cmd_axis_ready(m0_conv_pool_dma_cmd_axis_ready),
		
		.s0_dma_strm_axis_data(s0_conv_pool_dma_strm_axis_data),
		.s0_dma_strm_axis_keep(s0_conv_pool_dma_strm_axis_keep),
		.s0_dma_strm_axis_last(s0_conv_pool_dma_strm_axis_last),
		.s0_dma_strm_axis_valid(s0_conv_pool_dma_strm_axis_valid),
		.s0_dma_strm_axis_ready(s0_conv_pool_dma_strm_axis_ready),
		
		.m1_dma_cmd_axis_data(m1_conv_pool_dma_cmd_axis_data),
		.m1_dma_cmd_axis_user(m1_conv_pool_dma_cmd_axis_user),
		.m1_dma_cmd_axis_last(m1_conv_pool_dma_cmd_axis_last),
		.m1_dma_cmd_axis_valid(m1_conv_pool_dma_cmd_axis_valid),
		.m1_dma_cmd_axis_ready(m1_conv_pool_dma_cmd_axis_ready),
		
		.s1_dma_strm_axis_data(s1_conv_pool_dma_strm_axis_data),
		.s1_dma_strm_axis_keep(s1_conv_pool_dma_strm_axis_keep),
		.s1_dma_strm_axis_last(s1_conv_pool_dma_strm_axis_last),
		.s1_dma_strm_axis_valid(s1_conv_pool_dma_strm_axis_valid),
		.s1_dma_strm_axis_ready(s1_conv_pool_dma_strm_axis_ready),
		
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
		.buffer_rid_mp_tb_mem_dout_b(buffer_rid_mp_tb_mem_dout_b),
		
		.phy_conv_buf_mem_clk_a(phy_conv_buf_mem_clk_a),
		.phy_conv_buf_mem_en_a(phy_conv_buf_mem_en_a),
		.phy_conv_buf_mem_wen_a(phy_conv_buf_mem_wen_a),
		.phy_conv_buf_mem_addr_a(phy_conv_buf_mem_addr_a),
		.phy_conv_buf_mem_din_a(phy_conv_buf_mem_din_a),
		.phy_conv_buf_mem_dout_a(phy_conv_buf_mem_dout_a),
		.phy_conv_buf_mem_clk_b(phy_conv_buf_mem_clk_b),
		.phy_conv_buf_mem_en_b(phy_conv_buf_mem_en_b),
		.phy_conv_buf_mem_wen_b(phy_conv_buf_mem_wen_b),
		.phy_conv_buf_mem_addr_b(phy_conv_buf_mem_addr_b),
		.phy_conv_buf_mem_din_b(phy_conv_buf_mem_din_b),
		.phy_conv_buf_mem_dout_b(phy_conv_buf_mem_dout_b)
	);
	
	/** 中间结果输入寄存器片 **/
	// 寄存器片(AXIS从机)
	wire[ATOMIC_K*48-1:0] s_axis_mid_res_reg_data;
	wire[ATOMIC_K*6-1:0] s_axis_mid_res_reg_keep;
	wire[3:0] s_axis_mid_res_reg_user; // {随路数据, 是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire s_axis_mid_res_reg_last; // 本行最后1个中间结果(标志)
	wire s_axis_mid_res_reg_valid;
	wire s_axis_mid_res_reg_ready;
	// 寄存器片(AXIS主机)
	wire[ATOMIC_K*48-1:0] m_axis_mid_res_reg_data;
	wire[ATOMIC_K*6-1:0] m_axis_mid_res_reg_keep;
	wire[3:0] m_axis_mid_res_reg_user; // {随路数据, 是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire m_axis_mid_res_reg_last; // 本行最后1个中间结果(标志)
	wire m_axis_mid_res_reg_valid;
	wire m_axis_mid_res_reg_ready;
	
	generate
		if(SHARED_MID_RES_BUF_ALWAYS_SEL_POOL_ACC)
		begin
			assign s_axis_mid_res_reg_data = m_axis_pool_ext_mid_res_data;
			assign s_axis_mid_res_reg_keep = m_axis_pool_ext_mid_res_keep;
			assign s_axis_mid_res_reg_user = m_axis_pool_ext_mid_res_user;
			assign s_axis_mid_res_reg_last = m_axis_pool_ext_mid_res_last;
			assign s_axis_mid_res_reg_valid = en_pool_accelerator & m_axis_pool_ext_mid_res_valid;
			assign m_axis_conv_ext_mid_res_ready = 1'b1;
			assign m_axis_pool_ext_mid_res_ready = (~en_pool_accelerator) | s_axis_mid_res_reg_ready;
		end
		else
		begin
			assign s_axis_mid_res_reg_data = 
				({(ATOMIC_K*48){en_conv_accelerator}} & m_axis_conv_ext_mid_res_data) | 
				({(ATOMIC_K*48){en_pool_accelerator}} & m_axis_pool_ext_mid_res_data);
			assign s_axis_mid_res_reg_keep = 
				({(ATOMIC_K*6){en_conv_accelerator}} & m_axis_conv_ext_mid_res_keep) | 
				({(ATOMIC_K*6){en_pool_accelerator}} & m_axis_pool_ext_mid_res_keep);
			assign s_axis_mid_res_reg_user = 
				({4{en_conv_accelerator}} & {1'b0, m_axis_conv_ext_mid_res_user}) | 
				({4{en_pool_accelerator}} & m_axis_pool_ext_mid_res_user);
			assign s_axis_mid_res_reg_last = 
				(en_conv_accelerator & m_axis_conv_ext_mid_res_last) | 
				(en_pool_accelerator & m_axis_pool_ext_mid_res_last);
			assign s_axis_mid_res_reg_valid = 
				(en_conv_accelerator & m_axis_conv_ext_mid_res_valid) | 
				(en_pool_accelerator & m_axis_pool_ext_mid_res_valid);
			assign m_axis_conv_ext_mid_res_ready = (~en_conv_accelerator) | s_axis_mid_res_reg_ready;
			assign m_axis_pool_ext_mid_res_ready = (~en_pool_accelerator) | s_axis_mid_res_reg_ready;
		end
	endgenerate
	
	axis_reg_slice #(
		.data_width(ATOMIC_K*48),
		.user_width(4),
		.forward_registered(EN_MID_RES_REG_SLICE),
		.back_registered(EN_MID_RES_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)mid_res_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(1'b1),
		
		.s_axis_data(s_axis_mid_res_reg_data),
		.s_axis_keep(s_axis_mid_res_reg_keep),
		.s_axis_user(s_axis_mid_res_reg_user),
		.s_axis_last(s_axis_mid_res_reg_last),
		.s_axis_valid(s_axis_mid_res_reg_valid),
		.s_axis_ready(s_axis_mid_res_reg_ready),
		
		.m_axis_data(m_axis_mid_res_reg_data),
		.m_axis_keep(m_axis_mid_res_reg_keep),
		.m_axis_user(m_axis_mid_res_reg_user),
		.m_axis_last(m_axis_mid_res_reg_last),
		.m_axis_valid(m_axis_mid_res_reg_valid),
		.m_axis_ready(m_axis_mid_res_reg_ready)
	);
	
	/** 中间结果更新与缓存 **/
	// 使能信号
	reg en_mid_res_buf_dup_r;
	// 运行时参数
	wire[1:0] mid_res_buf_calfmt; // 运算数据格式
	wire[3:0] mid_res_buf_row_n_bufferable_dup; // 可缓存行数 - 1
	wire[3:0] mid_res_buf_bank_n_foreach_ofmap_row; // 每个输出特征图行所占用的缓存MEM个数
	wire[3:0] mid_res_buf_max_upd_latency; // 最大的更新时延
	wire mid_res_buf_en_cal_round_ext; // 是否启用计算轮次拓展功能
	wire[15:0] mid_res_buf_ofmap_w; // 输出特征图宽度 - 1
	wire[1:0] mid_res_buf_pool_mode; // 池化模式
	// 中间结果(AXIS从机)
	wire[ATOMIC_K*48-1:0] s_axis_mid_res_data;
	wire[ATOMIC_K*6-1:0] s_axis_mid_res_keep;
	wire[3:0] s_axis_mid_res_user; // {随路数据, 是否最后1轮计算(标志), 初始化中间结果(标志), 最后1组中间结果(标志)}
	wire s_axis_mid_res_last; // 本行最后1个中间结果(标志)
	wire s_axis_mid_res_valid;
	wire s_axis_mid_res_ready;
	// 最终结果(AXIS主机)
	wire[ATOMIC_K*32-1:0] m_axis_buf_fnl_res_data; // ATOMIC_K个最终结果(单精度浮点数或定点数)
	wire[ATOMIC_K*4-1:0] m_axis_buf_fnl_res_keep;
	wire[4:0] m_axis_buf_fnl_res_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_buf_fnl_res_last; // 本行最后1个最终结果(标志)
	wire m_axis_buf_fnl_res_valid;
	wire m_axis_buf_fnl_res_ready;
	// 中间结果缓存MEM主接口
	wire mid_res_mem_clk_a;
	wire[RBUF_BANK_N-1:0] mid_res_mem_wen_a;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_a;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_din_a;
	wire mid_res_mem_clk_b;
	wire[RBUF_BANK_N-1:0] mid_res_mem_ren_b;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_b;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_dout_b;
	// 中间结果更新单元组
	wire acmlt_aclk;
	wire acmlt_aresetn;
	wire acmlt_aclken;
	reg[3:1] pool_en_upd_grp_run_cnt_delayed; // 延迟的使能更新单元组运行周期数计数器信号
	// [更新单元组输入]
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE*48-1:0] acmlt_in_new_res; // 新结果
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE*32-1:0] acmlt_in_org_mid_res; // 原中间结果
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE+3-1:0] acmlt_in_info_along[0:ATOMIC_K/MID_RES_BUF_CLK_RATE-1]; // 随路数据
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE-1:0] acmlt_in_mask; // 项掩码
	wire acmlt_in_first_item; // 是否第1项(标志)
	wire acmlt_in_last_grp; // 是否最后1组(标志)
	wire acmlt_in_last_res; // 本行最后1个中间结果(标志)
	wire acmlt_in_is_zero_sfc; // 是否空表面(标志)
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE-1:0] acmlt_in_valid; // 输入有效指示
	// [更新单元组输出]
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE*32-1:0] conv_acmlt_out_data; // 单精度浮点数或定点数
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE+3-1:0] conv_acmlt_out_info_along[0:ATOMIC_K/MID_RES_BUF_CLK_RATE-1]; // 随路数据
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE-1:0] conv_acmlt_out_valid; // 输出有效指示
	wire[ATOMIC_C/MID_RES_BUF_CLK_RATE*32-1:0] pool_acmlt_out_data; // 单精度浮点数或定点数
	wire[ATOMIC_C/MID_RES_BUF_CLK_RATE+3-1:0] pool_acmlt_out_info_along[0:ATOMIC_K/MID_RES_BUF_CLK_RATE-1]; // 随路数据
	wire[ATOMIC_C/MID_RES_BUF_CLK_RATE-1:0] pool_acmlt_out_valid; // 输出有效指示
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE*32-1:0] acmlt_out_data; // 单精度浮点数或定点数
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE-1:0] acmlt_out_valid; // 输出有效指示
	wire[ATOMIC_K/MID_RES_BUF_CLK_RATE-1:0] acmlt_out_mask; // 输出项掩码
	wire acmlt_out_last_grp; // 是否最后1组(标志)
	wire acmlt_out_last_res; // 本行最后1个中间结果(标志)
	wire acmlt_out_to_upd_mem; // 更新缓存MEM(标志)
	// [性能监测]
	reg[31:0] upd_grp_run_cnt; // 更新单元组运行周期数(计数器)
	
	generate
		if(SHARED_MID_RES_BUF_ALWAYS_SEL_POOL_ACC)
		begin
			assign mid_res_buf_calfmt = pool_mid_res_buf_calfmt;
			assign mid_res_buf_row_n_bufferable_dup = pool_mid_res_buf_row_n_bufferable_dup;
			assign mid_res_buf_bank_n_foreach_ofmap_row = pool_mid_res_buf_bank_n_foreach_ofmap_row;
			assign mid_res_buf_max_upd_latency = pool_mid_res_buf_max_upd_latency;
			assign mid_res_buf_en_cal_round_ext = 1'b0;
		end
		else
		begin
			assign mid_res_buf_calfmt = 
				({2{en_conv_accelerator}} & conv_mid_res_buf_calfmt) | 
				({2{en_pool_accelerator}} & pool_mid_res_buf_calfmt);
			assign mid_res_buf_row_n_bufferable_dup = 
				({4{en_conv_accelerator}} & conv_mid_res_buf_row_n_bufferable_dup) | 
				({4{en_pool_accelerator}} & pool_mid_res_buf_row_n_bufferable_dup);
			assign mid_res_buf_bank_n_foreach_ofmap_row = 
				({4{en_conv_accelerator}} & conv_mid_res_buf_bank_n_foreach_ofmap_row) | 
				({4{en_pool_accelerator}} & pool_mid_res_buf_bank_n_foreach_ofmap_row);
			assign mid_res_buf_max_upd_latency = 
				({4{en_conv_accelerator}} & conv_mid_res_buf_max_upd_latency) | 
				({4{en_pool_accelerator}} & pool_mid_res_buf_max_upd_latency);
			assign mid_res_buf_en_cal_round_ext = en_conv_accelerator;
		end
	endgenerate
	
	assign mid_res_buf_ofmap_w = pool_mid_res_buf_ofmap_w;
	assign mid_res_buf_pool_mode = pool_mid_res_buf_pool_mode;
	
	assign s_axis_mid_res_data = m_axis_mid_res_reg_data;
	assign s_axis_mid_res_keep = m_axis_mid_res_reg_keep;
	assign s_axis_mid_res_user = m_axis_mid_res_reg_user;
	assign s_axis_mid_res_last = m_axis_mid_res_reg_last;
	assign s_axis_mid_res_valid = m_axis_mid_res_reg_valid;
	assign m_axis_mid_res_reg_ready = s_axis_mid_res_ready;
	
	generate
		if(SHARED_MID_RES_BUF_ALWAYS_SEL_POOL_ACC)
		begin
			assign acmlt_out_data = pool_acmlt_out_data;
			assign acmlt_out_valid = pool_acmlt_out_valid;
			assign acmlt_out_to_upd_mem = pool_acmlt_out_info_along[0][ATOMIC_C/MID_RES_BUF_CLK_RATE+2];
			assign {acmlt_out_last_res, acmlt_out_last_grp, acmlt_out_mask} = 
				pool_acmlt_out_info_along[0][ATOMIC_K/MID_RES_BUF_CLK_RATE+1:0];
		end
		else
		begin
			assign acmlt_out_data = 
				({(ATOMIC_K/MID_RES_BUF_CLK_RATE*32){en_conv_accelerator}} & conv_acmlt_out_data) | 
				({(ATOMIC_K/MID_RES_BUF_CLK_RATE*32){en_pool_accelerator}} & pool_acmlt_out_data);
			assign acmlt_out_valid = 
				({(ATOMIC_K/MID_RES_BUF_CLK_RATE){en_conv_accelerator}} & conv_acmlt_out_valid) | 
				({(ATOMIC_K/MID_RES_BUF_CLK_RATE){en_pool_accelerator}} & pool_acmlt_out_valid);
			assign acmlt_out_to_upd_mem = 
				en_conv_accelerator | 
				pool_acmlt_out_info_along[0][ATOMIC_C/MID_RES_BUF_CLK_RATE+2];
			assign {acmlt_out_last_res, acmlt_out_last_grp, acmlt_out_mask} = 
				({(ATOMIC_K/MID_RES_BUF_CLK_RATE+2){en_conv_accelerator}} & conv_acmlt_out_info_along[0][ATOMIC_K/MID_RES_BUF_CLK_RATE+1:0]) | 
				({(ATOMIC_K/MID_RES_BUF_CLK_RATE+2){en_pool_accelerator}} & pool_acmlt_out_info_along[0][ATOMIC_K/MID_RES_BUF_CLK_RATE+1:0]);
		end
	endgenerate
	
	assign pool_upd_grp_run_n = upd_grp_run_cnt;
	
	// 使能中间结果缓存
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			en_mid_res_buf_dup_r <= 1'b0;
		else
			en_mid_res_buf_dup_r <= # SIM_DELAY 
				(en_conv_accelerator & (!SHARED_MID_RES_BUF_ALWAYS_SEL_POOL_ACC) & conv_en_mid_res_buf_dup) | 
				(en_pool_accelerator & pool_en_mid_res_buf_dup);
	end
	
	// 延迟的使能更新单元组运行周期数计数器信号
	always @(posedge acmlt_aclk or negedge acmlt_aresetn)
	begin
		if(~acmlt_aresetn)
			pool_en_upd_grp_run_cnt_delayed <= 3'b000;
		else
			pool_en_upd_grp_run_cnt_delayed <= # SIM_DELAY {pool_en_upd_grp_run_cnt_delayed[2:1], pool_en_upd_grp_run_cnt};
	end
	
	// 更新单元组运行周期数(计数器)
	// 警告: 未作跨时钟域处理!!!
	always @(posedge acmlt_aclk or negedge acmlt_aresetn)
	begin
		if(~acmlt_aresetn)
			upd_grp_run_cnt <= 32'd0;
		else if(
			(~pool_en_upd_grp_run_cnt_delayed[2]) | acmlt_out_valid[0]
		)
			upd_grp_run_cnt <= # SIM_DELAY 
				pool_en_upd_grp_run_cnt_delayed[2] ? 
					(upd_grp_run_cnt + 1'b1):
					32'd0;
	end
	
	genvar acmlt_i;
	generate
		for(acmlt_i = 0;acmlt_i < ATOMIC_K/MID_RES_BUF_CLK_RATE;acmlt_i = acmlt_i + 1)
		begin:acmlt_blk
			assign acmlt_in_info_along[acmlt_i] = 
				(acmlt_i == 0) ? 
					{
						((mid_res_buf_pool_mode == POOL_MODE_UPSP) | acmlt_in_first_item) | 
						((mid_res_buf_pool_mode == POOL_MODE_MAX) | (~acmlt_in_is_zero_sfc)),
						acmlt_in_last_res,
						acmlt_in_last_grp,
						acmlt_in_mask
					}:
					{(ATOMIC_K/MID_RES_BUF_CLK_RATE+3){1'bx}};
			
			if(!SHARED_MID_RES_BUF_ALWAYS_SEL_POOL_ACC)
			begin
				conv_middle_res_accumulate #(
					.EN_SMALL_FP32("true"),
					.INFO_ALONG_WIDTH(ATOMIC_K/MID_RES_BUF_CLK_RATE+3),
					.SIM_DELAY(SIM_DELAY)
				)conv_middle_res_accumulate_u(
					.aclk(acmlt_aclk),
					.aresetn(acmlt_aresetn),
					.aclken(acmlt_aclken),
					
					.calfmt(mid_res_buf_calfmt),
					
					.acmlt_in_exp(acmlt_in_new_res[acmlt_i*48+47:acmlt_i*48+40]),
					.acmlt_in_frac(acmlt_in_new_res[acmlt_i*48+39:acmlt_i*48+0]),
					.acmlt_in_org_mid_res(acmlt_in_org_mid_res[acmlt_i*32+31:acmlt_i*32+0]),
					.acmlt_in_first_item(acmlt_in_first_item),
					.acmlt_in_info_along(acmlt_in_info_along[acmlt_i]),
					.acmlt_in_valid(en_conv_accelerator & acmlt_in_valid[acmlt_i]),
					
					.acmlt_out_data(conv_acmlt_out_data[acmlt_i*32+31:acmlt_i*32+0]),
					.acmlt_out_info_along(conv_acmlt_out_info_along[acmlt_i]),
					.acmlt_out_valid(conv_acmlt_out_valid[acmlt_i])
				);
			end
			
			pool_middle_res_upd #(
				.INFO_ALONG_WIDTH(ATOMIC_C+3),
				.SIM_DELAY(SIM_DELAY)
			)pool_middle_res_upd_u(
				.aclk(acmlt_aclk),
				.aresetn(acmlt_aresetn),
				.aclken(acmlt_aclken),
				
				.pool_mode(mid_res_buf_pool_mode),
				.calfmt(mid_res_buf_calfmt),
				
				.pool_upd_in_data(acmlt_in_new_res[acmlt_i*48+15:acmlt_i*48]),
				.pool_upd_in_org_mid_res(acmlt_in_org_mid_res[acmlt_i*32+31:acmlt_i*32]),
				.pool_upd_in_is_first_item(acmlt_in_first_item),
				.pool_upd_in_is_zero_sfc(acmlt_in_is_zero_sfc),
				.pool_upd_in_info_along(acmlt_in_info_along[acmlt_i]),
				.pool_upd_in_valid(en_pool_accelerator & acmlt_in_valid[acmlt_i]),
				
				.pool_upd_out_data(pool_acmlt_out_data[acmlt_i*32+31:acmlt_i*32]),
				.pool_upd_out_info_along(pool_acmlt_out_info_along[acmlt_i]),
				.pool_upd_out_valid(pool_acmlt_out_valid[acmlt_i])
			);
		end
		
		if(MID_RES_BUF_CLK_RATE == 1)
		begin
			conv_middle_res_acmlt_buf #(
				.TSF_N_FOREACH_SFC(1),
				.ATOMIC_K(ATOMIC_K),
				.RBUF_BANK_N(RBUF_BANK_N),
				.RBUF_DEPTH(RBUF_DEPTH),
				.INFO_ALONG_WIDTH(1),
				.SIM_DELAY(SIM_DELAY)
			)middle_res_acmlt_buf_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(1'b1),
				
				.calfmt(mid_res_buf_calfmt),
				.row_n_bufferable(mid_res_buf_row_n_bufferable_dup),
				.bank_n_foreach_ofmap_row(mid_res_buf_bank_n_foreach_ofmap_row),
				.max_upd_latency(mid_res_buf_max_upd_latency),
				.en_cal_round_ext(mid_res_buf_en_cal_round_ext),
				.ofmap_w(mid_res_buf_ofmap_w),
				
				.s_axis_mid_res_data(s_axis_mid_res_data),
				.s_axis_mid_res_keep(s_axis_mid_res_keep),
				.s_axis_mid_res_user(s_axis_mid_res_user),
				.s_axis_mid_res_last(s_axis_mid_res_last),
				.s_axis_mid_res_valid(s_axis_mid_res_valid),
				.s_axis_mid_res_ready(s_axis_mid_res_ready),
				
				.m_axis_fnl_res_data(m_axis_buf_fnl_res_data),
				.m_axis_fnl_res_keep(m_axis_buf_fnl_res_keep),
				.m_axis_fnl_res_user(m_axis_buf_fnl_res_user),
				.m_axis_fnl_res_last(m_axis_buf_fnl_res_last),
				.m_axis_fnl_res_valid(m_axis_buf_fnl_res_valid),
				.m_axis_fnl_res_ready(m_axis_buf_fnl_res_ready),
				
				.mem_clk_a(mid_res_mem_clk_a),
				.mem_wen_a(mid_res_mem_wen_a),
				.mem_addr_a(mid_res_mem_addr_a),
				.mem_din_a(mid_res_mem_din_a),
				.mem_clk_b(mid_res_mem_clk_b),
				.mem_ren_b(mid_res_mem_ren_b),
				.mem_addr_b(mid_res_mem_addr_b),
				.mem_dout_b(mid_res_mem_dout_b),
				
				.acmlt_aclk(acmlt_aclk),
				.acmlt_aresetn(acmlt_aresetn),
				.acmlt_aclken(acmlt_aclken),
				.acmlt_in_new_res(acmlt_in_new_res),
				.acmlt_in_org_mid_res(acmlt_in_org_mid_res),
				.acmlt_in_mask(acmlt_in_mask),
				.acmlt_in_first_item(acmlt_in_first_item),
				.acmlt_in_last_grp(acmlt_in_last_grp),
				.acmlt_in_last_res(acmlt_in_last_res),
				.acmlt_in_info_along(acmlt_in_is_zero_sfc),
				.acmlt_in_valid(acmlt_in_valid),
				
				.acmlt_out_data(acmlt_out_data),
				.acmlt_out_mask(acmlt_out_mask),
				.acmlt_out_last_grp(acmlt_out_last_grp),
				.acmlt_out_last_res(acmlt_out_last_res),
				.acmlt_out_to_upd_mem(acmlt_out_to_upd_mem),
				.acmlt_out_valid(acmlt_out_valid[0])
			);
		end
		else
		begin
			async_conv_middle_res_acmlt_buf #(
				.EN_IN_ASYNC_FIFO("true"),
				.BUF_CLK_RATE(MID_RES_BUF_CLK_RATE),
				.ATOMIC_K(ATOMIC_K),
				.RBUF_BANK_N(RBUF_BANK_N),
				.RBUF_DEPTH(RBUF_DEPTH),
				.INFO_ALONG_WIDTH(1),
				.SIM_DELAY(SIM_DELAY)
			)middle_res_acmlt_buf_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(1'b1),
				.mid_res_buf_aclk(mid_res_buf_aclk),
				.mid_res_buf_aresetn(mid_res_buf_aresetn),
				.mid_res_buf_aclken(1'b1),
				
				.runtime_params_vld(en_mid_res_buf_dup_r),
				
				.calfmt(mid_res_buf_calfmt),
				.row_n_bufferable(mid_res_buf_row_n_bufferable_dup),
				.bank_n_foreach_ofmap_row(mid_res_buf_bank_n_foreach_ofmap_row),
				.max_upd_latency(mid_res_buf_max_upd_latency),
				.en_cal_round_ext(mid_res_buf_en_cal_round_ext),
				.ofmap_w(mid_res_buf_ofmap_w),
				
				.s_axis_mid_res_data(s_axis_mid_res_data),
				.s_axis_mid_res_keep(s_axis_mid_res_keep),
				.s_axis_mid_res_user(s_axis_mid_res_user),
				.s_axis_mid_res_last(s_axis_mid_res_last),
				.s_axis_mid_res_valid(s_axis_mid_res_valid),
				.s_axis_mid_res_ready(s_axis_mid_res_ready),
				
				.m_axis_fnl_res_data(m_axis_buf_fnl_res_data),
				.m_axis_fnl_res_keep(m_axis_buf_fnl_res_keep),
				.m_axis_fnl_res_user(m_axis_buf_fnl_res_user),
				.m_axis_fnl_res_last(m_axis_buf_fnl_res_last),
				.m_axis_fnl_res_valid(m_axis_buf_fnl_res_valid),
				.m_axis_fnl_res_ready(m_axis_buf_fnl_res_ready),
				
				.mem_clk_a(mid_res_mem_clk_a),
				.mem_wen_a(mid_res_mem_wen_a),
				.mem_addr_a(mid_res_mem_addr_a),
				.mem_din_a(mid_res_mem_din_a),
				.mem_clk_b(mid_res_mem_clk_b),
				.mem_ren_b(mid_res_mem_ren_b),
				.mem_addr_b(mid_res_mem_addr_b),
				.mem_dout_b(mid_res_mem_dout_b),
				
				.acmlt_aclk(acmlt_aclk),
				.acmlt_aresetn(acmlt_aresetn),
				.acmlt_aclken(acmlt_aclken),
				.acmlt_in_new_res(acmlt_in_new_res),
				.acmlt_in_org_mid_res(acmlt_in_org_mid_res),
				.acmlt_in_mask(acmlt_in_mask),
				.acmlt_in_first_item(acmlt_in_first_item),
				.acmlt_in_last_grp(acmlt_in_last_grp),
				.acmlt_in_last_res(acmlt_in_last_res),
				.acmlt_in_info_along(acmlt_in_is_zero_sfc),
				.acmlt_in_valid(acmlt_in_valid),
				
				.acmlt_out_data(acmlt_out_data),
				.acmlt_out_mask(acmlt_out_mask),
				.acmlt_out_last_grp(acmlt_out_last_grp),
				.acmlt_out_last_res(acmlt_out_last_res),
				.acmlt_out_to_upd_mem(acmlt_out_to_upd_mem),
				.acmlt_out_valid(acmlt_out_valid[0])
			);
		end
	endgenerate
	
	/** 最终结果输出寄存器片 **/
	// 寄存器片(AXIS从机)
	wire[ATOMIC_K*32-1:0] s_axis_fnl_res_reg_data; // ATOMIC_K个最终结果(单精度浮点数或定点数)
	wire[ATOMIC_K*4-1:0] s_axis_fnl_res_reg_keep;
	wire[4:0] s_axis_fnl_res_reg_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire s_axis_fnl_res_reg_last; // 本行最后1个最终结果(标志)
	wire s_axis_fnl_res_reg_valid;
	wire s_axis_fnl_res_reg_ready;
	// 寄存器片(AXIS主机)
	wire[ATOMIC_K*32-1:0] m_axis_fnl_res_reg_data; // ATOMIC_K个最终结果(单精度浮点数或定点数)
	wire[ATOMIC_K*4-1:0] m_axis_fnl_res_reg_keep;
	wire[4:0] m_axis_fnl_res_reg_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_fnl_res_reg_last; // 本行最后1个最终结果(标志)
	wire m_axis_fnl_res_reg_valid;
	wire m_axis_fnl_res_reg_ready;
	
	assign s_axis_fnl_res_reg_data = m_axis_buf_fnl_res_data;
	assign s_axis_fnl_res_reg_keep = m_axis_buf_fnl_res_keep;
	assign s_axis_fnl_res_reg_user = m_axis_buf_fnl_res_user;
	assign s_axis_fnl_res_reg_last = m_axis_buf_fnl_res_last;
	assign s_axis_fnl_res_reg_valid = m_axis_buf_fnl_res_valid;
	assign m_axis_buf_fnl_res_ready = s_axis_fnl_res_reg_ready;
	
	assign s_axis_conv_ext_fnl_res_data = m_axis_fnl_res_reg_data;
	assign s_axis_conv_ext_fnl_res_keep = m_axis_fnl_res_reg_keep;
	assign s_axis_conv_ext_fnl_res_user = m_axis_fnl_res_reg_user;
	assign s_axis_conv_ext_fnl_res_last = m_axis_fnl_res_reg_last;
	assign s_axis_conv_ext_fnl_res_valid = en_conv_accelerator & (!SHARED_MID_RES_BUF_ALWAYS_SEL_POOL_ACC) & m_axis_fnl_res_reg_valid;
	assign s_axis_pool_ext_fnl_res_data = m_axis_fnl_res_reg_data;
	assign s_axis_pool_ext_fnl_res_keep = m_axis_fnl_res_reg_keep;
	assign s_axis_pool_ext_fnl_res_last = m_axis_fnl_res_reg_last;
	assign s_axis_pool_ext_fnl_res_valid = en_pool_accelerator & m_axis_fnl_res_reg_valid;
	assign m_axis_fnl_res_reg_ready = 
		(en_conv_accelerator & (!SHARED_MID_RES_BUF_ALWAYS_SEL_POOL_ACC) & s_axis_conv_ext_fnl_res_ready) | 
		(en_pool_accelerator & s_axis_pool_ext_fnl_res_ready);
	
	axis_reg_slice #(
		.data_width(ATOMIC_K*32),
		.user_width(5),
		.forward_registered(EN_FNL_RES_REG_SLICE),
		.back_registered(EN_FNL_RES_REG_SLICE),
		.en_ready("true"),
		.en_clk_en("true"),
		.simulation_delay(SIM_DELAY)
	)fnl_res_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(1'b1),
		
		.s_axis_data(s_axis_fnl_res_reg_data),
		.s_axis_keep(s_axis_fnl_res_reg_keep),
		.s_axis_user(s_axis_fnl_res_reg_user),
		.s_axis_last(s_axis_fnl_res_reg_last),
		.s_axis_valid(s_axis_fnl_res_reg_valid),
		.s_axis_ready(s_axis_fnl_res_reg_ready),
		
		.m_axis_data(m_axis_fnl_res_reg_data),
		.m_axis_keep(m_axis_fnl_res_reg_keep),
		.m_axis_user(m_axis_fnl_res_reg_user),
		.m_axis_last(m_axis_fnl_res_reg_last),
		.m_axis_valid(m_axis_fnl_res_reg_valid),
		.m_axis_ready(m_axis_fnl_res_reg_ready)
	);
	
	/** 最终结果传输请求生成单元 **/
	// 运行时参数
	wire[31:0] fnl_res_tr_req_gen_ofmap_baseaddr; // 输出特征图基地址
	wire[15:0] fnl_res_tr_req_gen_ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] fnl_res_tr_req_gen_ofmap_h; // 输出特征图高度 - 1
	wire[1:0] fnl_res_tr_req_gen_ofmap_data_type; // 输出特征图数据大小类型
	wire[15:0] fnl_res_tr_req_gen_kernal_num_n; // 卷积核核数 - 1
	wire[5:0] fnl_res_tr_req_gen_max_wgtblk_w; // 权重块最大宽度
	wire fnl_res_tr_req_gen_is_grp_conv_mode; // 是否处于组卷积模式
	wire[15:0] fnl_res_tr_req_gen_n_foreach_group; // 每组的通道数/核数 - 1
	wire fnl_res_tr_req_gen_en_send_sub_row_msg; // 是否输出子表面行信息
	// 块级控制
	wire fnl_res_trans_blk_start;
	wire fnl_res_trans_blk_idle;
	wire fnl_res_trans_blk_done;
	// 子表面行信息(AXIS主机)
	wire[15:0] m_sub_row_msg_axis_data; // {输出通道号(16bit)}
	wire m_sub_row_msg_axis_last; // 整个输出特征图的最后1个子表面行(标志)
	wire m_sub_row_msg_axis_valid;
	wire m_sub_row_msg_axis_ready;
	// DMA命令(AXIS主机)
	wire[55:0] m_conv_pool_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire[24:0] m_conv_pool_dma_cmd_axis_user; // {命令ID(24bit), 固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_conv_pool_dma_cmd_axis_valid;
	wire m_conv_pool_dma_cmd_axis_ready;
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] fnl_res_trans_mul0_op_a; // 操作数A
	wire[23:0] fnl_res_trans_mul0_op_b; // 操作数B
	wire[3:0] fnl_res_trans_mul0_tid; // 操作ID
	wire fnl_res_trans_mul0_req;
	wire fnl_res_trans_mul0_grant;
	// [计算结果]
	wire[39:0] fnl_res_trans_mul0_res;
	wire[3:0] fnl_res_trans_mul0_oid;
	wire fnl_res_trans_mul0_ovld;
	// (共享)无符号乘法器#1
	// [计算输入]
	wire[15:0] fnl_res_trans_mul1_op_a; // 操作数A
	wire[23:0] fnl_res_trans_mul1_op_b; // 操作数B
	wire[3:0] fnl_res_trans_mul1_tid; // 操作ID
	wire fnl_res_trans_mul1_req;
	wire fnl_res_trans_mul1_grant;
	// [计算结果]
	wire[39:0] fnl_res_trans_mul1_res;
	wire[3:0] fnl_res_trans_mul1_oid;
	wire fnl_res_trans_mul1_ovld;
	// 乘法器(u16*u24)
	// [计算端口]
	wire[15:0] mul2_op_a; // 操作数A
	wire[23:0] mul2_op_b; // 操作数B
	wire mul2_ce; // 计算使能
	wire[39:0] mul2_res; // 计算结果
	// [延迟1clk的乘法器输入]
	reg[15:0] fnl_res_trans_shared_mul_op_a_d1;
	reg[23:0] fnl_res_trans_shared_mul_op_b_d1;
	reg[3:0] fnl_res_trans_shared_mul_tid_d1;
	reg fnl_res_trans_shared_mul_req_d1;
	// [延迟2clk的乘法器输入]
	reg[3:0] fnl_res_trans_shared_mul_tid_d2;
	reg fnl_res_trans_shared_mul_req_d2;
	
	assign fnl_res_tr_req_gen_ofmap_baseaddr = 
		({32{en_conv_accelerator}} & conv_fnl_res_tr_req_gen_ofmap_baseaddr) | 
		({32{en_pool_accelerator}} & pool_fnl_res_tr_req_gen_ofmap_baseaddr);
	assign fnl_res_tr_req_gen_ofmap_w = 
		({16{en_conv_accelerator}} & conv_fnl_res_tr_req_gen_ofmap_w) | 
		({16{en_pool_accelerator}} & pool_fnl_res_tr_req_gen_ofmap_w);
	assign fnl_res_tr_req_gen_ofmap_h = 
		({16{en_conv_accelerator}} & conv_fnl_res_tr_req_gen_ofmap_h) | 
		({16{en_pool_accelerator}} & pool_fnl_res_tr_req_gen_ofmap_h);
	assign fnl_res_tr_req_gen_ofmap_data_type = 
		({2{en_conv_accelerator}} & conv_fnl_res_tr_req_gen_ofmap_data_type) | 
		({2{en_pool_accelerator}} & pool_fnl_res_tr_req_gen_ofmap_data_type);
	assign fnl_res_tr_req_gen_kernal_num_n = 
		({16{en_conv_accelerator}} & conv_fnl_res_tr_req_gen_kernal_num_n) | 
		({16{en_pool_accelerator}} & pool_fnl_res_tr_req_gen_kernal_num_n);
	assign fnl_res_tr_req_gen_max_wgtblk_w = 
		({6{en_conv_accelerator}} & conv_fnl_res_tr_req_gen_max_wgtblk_w) | 
		({6{en_pool_accelerator}} & pool_fnl_res_tr_req_gen_max_wgtblk_w);
	assign fnl_res_tr_req_gen_is_grp_conv_mode = 
		(en_conv_accelerator & conv_fnl_res_tr_req_gen_is_grp_conv_mode) | 
		(en_pool_accelerator & pool_fnl_res_tr_req_gen_is_grp_conv_mode);
	assign fnl_res_tr_req_gen_n_foreach_group = 
		conv_fnl_res_tr_req_gen_n_foreach_group;
	assign fnl_res_tr_req_gen_en_send_sub_row_msg = 
		en_conv_accelerator;
	
	assign fnl_res_trans_blk_start = 
		(en_conv_accelerator & conv_fnl_res_trans_blk_start) | 
		(en_pool_accelerator & pool_fnl_res_tr_req_gen_blk_start);
	assign conv_fnl_res_trans_blk_idle = fnl_res_trans_blk_idle;
	assign pool_fnl_res_tr_req_gen_blk_idle = fnl_res_trans_blk_idle;
	assign conv_fnl_res_trans_blk_done = fnl_res_trans_blk_done;
	assign pool_fnl_res_tr_req_gen_blk_done = fnl_res_trans_blk_done;
	
	assign mul2_op_a = fnl_res_trans_shared_mul_op_a_d1;
	assign mul2_op_b = fnl_res_trans_shared_mul_op_b_d1;
	assign mul2_ce = fnl_res_trans_shared_mul_req_d1;
	
	assign fnl_res_trans_mul0_grant = fnl_res_trans_mul0_req;
	assign fnl_res_trans_mul0_res = mul2_res;
	assign fnl_res_trans_mul0_oid = fnl_res_trans_shared_mul_tid_d2;
	assign fnl_res_trans_mul0_ovld = fnl_res_trans_shared_mul_req_d2;
	
	assign fnl_res_trans_mul1_grant = (~fnl_res_trans_mul0_req) & fnl_res_trans_mul1_req;
	assign fnl_res_trans_mul1_res = mul2_res;
	assign fnl_res_trans_mul1_oid = fnl_res_trans_shared_mul_tid_d2;
	assign fnl_res_trans_mul1_ovld = fnl_res_trans_shared_mul_req_d2;
	
	always @(posedge aclk)
	begin
		if(fnl_res_trans_mul0_req | fnl_res_trans_mul1_req)
			{
				fnl_res_trans_shared_mul_op_a_d1,
				fnl_res_trans_shared_mul_op_b_d1,
				fnl_res_trans_shared_mul_tid_d1
			} <= # SIM_DELAY 
				fnl_res_trans_mul0_req ? 
					{
						fnl_res_trans_mul0_op_a,
						fnl_res_trans_mul0_op_b,
						fnl_res_trans_mul0_tid
					}:
					{
						fnl_res_trans_mul1_op_a,
						fnl_res_trans_mul1_op_b,
						fnl_res_trans_mul1_tid
					};
	end
	
	always @(posedge aclk)
	begin
		if(fnl_res_trans_shared_mul_req_d1)
			fnl_res_trans_shared_mul_tid_d2 <= # SIM_DELAY fnl_res_trans_shared_mul_tid_d1;
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{fnl_res_trans_shared_mul_req_d2, fnl_res_trans_shared_mul_req_d1} <= 2'b00;
		else
			{fnl_res_trans_shared_mul_req_d2, fnl_res_trans_shared_mul_req_d1} <= # SIM_DELAY 
				{fnl_res_trans_shared_mul_req_d1, fnl_res_trans_mul0_req | fnl_res_trans_mul1_req};
	end
	
	fnl_res_trans_req_gen #(
		.ATOMIC_K(ATOMIC_K),
		.SIM_DELAY(SIM_DELAY)
	)fnl_res_trans_req_gen_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.ofmap_baseaddr(fnl_res_tr_req_gen_ofmap_baseaddr),
		.ofmap_w(fnl_res_tr_req_gen_ofmap_w),
		.ofmap_h(fnl_res_tr_req_gen_ofmap_h),
		.ofmap_data_type(fnl_res_tr_req_gen_ofmap_data_type),
		.kernal_num_n(fnl_res_tr_req_gen_kernal_num_n),
		.max_wgtblk_w(fnl_res_tr_req_gen_max_wgtblk_w),
		.is_grp_conv_mode(fnl_res_tr_req_gen_is_grp_conv_mode),
		.n_foreach_group(fnl_res_tr_req_gen_n_foreach_group),
		.en_send_sub_row_msg(fnl_res_tr_req_gen_en_send_sub_row_msg),
		
		.blk_start(fnl_res_trans_blk_start),
		.blk_idle(fnl_res_trans_blk_idle),
		.blk_done(fnl_res_trans_blk_done),
		
		.m_sub_row_msg_axis_data(m_sub_row_msg_axis_data),
		.m_sub_row_msg_axis_last(m_sub_row_msg_axis_last),
		.m_sub_row_msg_axis_valid(m_sub_row_msg_axis_valid),
		.m_sub_row_msg_axis_ready(m_sub_row_msg_axis_ready),
		
		.m_dma_cmd_axis_data(m_conv_pool_dma_cmd_axis_data),
		.m_dma_cmd_axis_user(m_conv_pool_dma_cmd_axis_user),
		.m_dma_cmd_axis_valid(m_conv_pool_dma_cmd_axis_valid),
		.m_dma_cmd_axis_ready(m_conv_pool_dma_cmd_axis_ready),
		
		.mul0_op_a(fnl_res_trans_mul0_op_a),
		.mul0_op_b(fnl_res_trans_mul0_op_b),
		.mul0_tid(fnl_res_trans_mul0_tid),
		.mul0_req(fnl_res_trans_mul0_req),
		.mul0_grant(fnl_res_trans_mul0_grant),
		.mul0_res(fnl_res_trans_mul0_res),
		.mul0_oid(fnl_res_trans_mul0_oid),
		.mul0_ovld(fnl_res_trans_mul0_ovld),
		
		.mul1_op_a(fnl_res_trans_mul1_op_a),
		.mul1_op_b(fnl_res_trans_mul1_op_b),
		.mul1_tid(fnl_res_trans_mul1_tid),
		.mul1_req(fnl_res_trans_mul1_req),
		.mul1_grant(fnl_res_trans_mul1_grant),
		.mul1_res(fnl_res_trans_mul1_res),
		.mul1_oid(fnl_res_trans_mul1_oid),
		.mul1_ovld(fnl_res_trans_mul1_ovld)
	);
	
	/** BN与激活单元 **/
	// 使能信号
	wire en_bn_act_proc_dup; // 使能处理单元
	// 运行时参数
	wire[1:0] bn_act_calfmt; // 运算数据格式
	wire bn_act_use_bn_unit; // 启用BN单元
	wire[2:0] bn_act_act_func_type; // 激活函数类型
	wire[4:0] bn_act_bn_fixed_point_quat_accrc; // (批归一化操作数A)定点数量化精度
	wire bn_act_bn_is_a_eq_1; // 批归一化参数A的实际值为1(标志)
	wire bn_act_bn_is_b_eq_0; // 批归一化参数B的实际值为0(标志)
	wire bn_act_is_in_const_mac_mode; // 是否处于常量乘加模式
	wire[31:0] bn_act_param_a_in_const_mac_mode; // 常量乘加模式下的参数A
	wire[31:0] bn_act_param_b_in_const_mac_mode; // 常量乘加模式下的参数B
	wire[4:0] bn_act_leaky_relu_fixed_point_quat_accrc; // (泄露Relu激活参数)定点数量化精度
	wire[31:0] bn_act_leaky_relu_param_alpha; // 泄露Relu激活参数
	wire[4:0] bn_act_sigmoid_tanh_fixed_point_quat_accrc; // (Sigmoid或Tanh输入)定点数量化精度
	// BN与激活处理输入(AXIS从机)
	wire[ATOMIC_K*32-1:0] s_axis_bn_act_i_data; // 对于ATOMIC_K个最终结果 -> {单精度浮点数或定点数(32位)}
	wire[ATOMIC_K*4-1:0] s_axis_bn_act_i_keep;
	wire[4:0] s_axis_bn_act_i_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire s_axis_bn_act_i_last; // 本行最后1个最终结果(标志)
	wire s_axis_bn_act_i_valid;
	wire s_axis_bn_act_i_ready;
	// 经过BN与激活处理的结果(AXIS主机)
	wire[BN_ACT_PRL_N*32-1:0] m_axis_bn_act_o_data; // 对于BN_ACT_PRL_N个最终结果 -> {浮点数或定点数}
	wire[BN_ACT_PRL_N*4-1:0] m_axis_bn_act_o_keep;
	wire[4:0] m_axis_bn_act_o_user; // {是否最后1个子行(1bit), 子行号(4bit)}
	wire m_axis_bn_act_o_last; // 本行最后1个处理结果(标志)
	wire m_axis_bn_act_o_valid;
	wire m_axis_bn_act_o_ready;
	// BN乘法器组
	wire bn_mul_clk;
	wire[BN_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_op_a; // 操作数A
	wire[BN_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_op_b; // 操作数B
	wire[BN_MUL_CE_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_ce; // 计算使能
	wire[BN_MUL_RES_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_res; // 计算结果
	// 泄露Relu乘法器组
	wire leaky_relu_mul_clk;
	wire[LEAKY_RELU_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_op_a; // 操作数A
	wire[LEAKY_RELU_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_op_b; // 操作数B
	wire[LEAKY_RELU_MUL_CE_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_ce; // 计算使能
	wire[LEAKY_RELU_MUL_RES_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_res; // 计算结果
	// BN参数MEM主接口
	wire bn_mem_clk_b;
	wire bn_mem_ren_b;
	wire[15:0] bn_mem_addr_b;
	wire[63:0] bn_mem_dout_b; // {参数B(32bit), 参数A(32bit)}
	// 处理结果fifo(MEM主接口)
	wire proc_res_fifo_mem_clk_a;
	wire proc_res_fifo_mem_wen_a;
	wire[8:0] proc_res_fifo_mem_addr_a;
	wire[BN_ACT_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_din_a;
	wire proc_res_fifo_mem_clk_b;
	wire proc_res_fifo_mem_ren_b;
	wire[8:0] proc_res_fifo_mem_addr_b;
	wire[BN_ACT_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_dout_b;
	// Sigmoid函数值查找表(MEM主接口)
	wire sigmoid_lut_mem_clk_a;
	wire[BN_ACT_PRL_N-1:0] sigmoid_lut_mem_ren_a;
	wire[12*BN_ACT_PRL_N-1:0] sigmoid_lut_mem_addr_a;
	wire[16*BN_ACT_PRL_N-1:0] sigmoid_lut_mem_dout_a;
	wire[31:0] sigmoid_lut_mem_dout_a_32[0:BN_ACT_PRL_N-1];
	reg[BN_ACT_PRL_N-1:0] sigmoid_lut_mem_dout_a_half_word_sel;
	
	assign en_bn_act_proc_dup = 
		(en_conv_accelerator & conv_en_bn_act_proc_dup) | 
		(en_pool_accelerator & pool_en_bn_act_proc_dup);
	
	assign bn_act_calfmt = 
		({2{en_conv_accelerator}} & conv_bn_act_calfmt) | 
		({2{en_pool_accelerator}} & pool_bn_act_calfmt);
	assign bn_act_use_bn_unit = 
		(en_conv_accelerator & conv_bn_act_use_bn_unit) | 
		(en_pool_accelerator & pool_bn_act_use_bn_unit);
	assign bn_act_act_func_type = 
		({3{en_conv_accelerator}} & conv_bn_act_act_func_type) | 
		({3{en_pool_accelerator}} & pool_bn_act_act_func_type);
	assign bn_act_bn_fixed_point_quat_accrc = 
		({5{en_conv_accelerator}} & conv_bn_act_bn_fixed_point_quat_accrc) | 
		({5{en_pool_accelerator}} & pool_bn_act_bn_fixed_point_quat_accrc);
	assign bn_act_bn_is_a_eq_1 = 
		(en_conv_accelerator & conv_bn_act_bn_is_a_eq_1) | 
		(en_pool_accelerator & pool_bn_act_bn_is_a_eq_1);
	assign bn_act_bn_is_b_eq_0 = 
		(en_conv_accelerator & conv_bn_act_bn_is_b_eq_0) | 
		(en_pool_accelerator & pool_bn_act_bn_is_b_eq_0);
	assign bn_act_is_in_const_mac_mode = en_pool_accelerator;
	assign bn_act_param_a_in_const_mac_mode = pool_bn_act_param_a_in_const_mac_mode;
	assign bn_act_param_b_in_const_mac_mode = pool_bn_act_param_b_in_const_mac_mode;
	assign bn_act_leaky_relu_fixed_point_quat_accrc = conv_bn_act_leaky_relu_fixed_point_quat_accrc;
	assign bn_act_leaky_relu_param_alpha = conv_bn_act_leaky_relu_param_alpha;
	assign bn_act_sigmoid_tanh_fixed_point_quat_accrc = conv_bn_act_sigmoid_tanh_fixed_point_quat_accrc;
	
	assign s_axis_bn_act_i_data = 
		({(ATOMIC_K*32){en_conv_accelerator}} & m_axis_conv_ext_bn_act_i_data) | 
		({(ATOMIC_K*32){en_pool_accelerator}} & m_axis_pool_ext_bn_act_i_data);
	assign s_axis_bn_act_i_keep = 
		({(ATOMIC_K*4){en_conv_accelerator}} & m_axis_conv_ext_bn_act_i_keep) | 
		({(ATOMIC_K*4){en_pool_accelerator}} & m_axis_pool_ext_bn_act_i_keep);
	assign s_axis_bn_act_i_user = 
		({5{en_conv_accelerator}} & m_axis_conv_ext_bn_act_i_user) | 
		({5{en_pool_accelerator}} & m_axis_pool_ext_bn_act_i_user);
	assign s_axis_bn_act_i_last = 
		(en_conv_accelerator & m_axis_conv_ext_bn_act_i_last) | 
		(en_pool_accelerator & m_axis_pool_ext_bn_act_i_last);
	assign s_axis_bn_act_i_valid = 
		(en_conv_accelerator & m_axis_conv_ext_bn_act_i_valid) | 
		(en_pool_accelerator & m_axis_pool_ext_bn_act_i_valid);
	assign m_axis_conv_ext_bn_act_i_ready = (~en_conv_accelerator) | s_axis_bn_act_i_ready;
	assign m_axis_pool_ext_bn_act_i_ready = (~en_pool_accelerator) | s_axis_bn_act_i_ready;
	
	assign s_axis_conv_ext_bn_act_o_data = m_axis_bn_act_o_data;
	assign s_axis_conv_ext_bn_act_o_keep = m_axis_bn_act_o_keep;
	assign s_axis_conv_ext_bn_act_o_user = m_axis_bn_act_o_user;
	assign s_axis_conv_ext_bn_act_o_last = m_axis_bn_act_o_last;
	assign s_axis_conv_ext_bn_act_o_valid = en_conv_accelerator & m_axis_bn_act_o_valid;
	assign s_axis_pool_ext_bn_act_o_data = m_axis_bn_act_o_data;
	assign s_axis_pool_ext_bn_act_o_keep = m_axis_bn_act_o_keep;
	assign s_axis_pool_ext_bn_act_o_user = m_axis_bn_act_o_user;
	assign s_axis_pool_ext_bn_act_o_last = m_axis_bn_act_o_last;
	assign s_axis_pool_ext_bn_act_o_valid = en_pool_accelerator & m_axis_bn_act_o_valid;
	assign m_axis_bn_act_o_ready = 
		(en_conv_accelerator & s_axis_conv_ext_bn_act_o_ready) | 
		(en_pool_accelerator & s_axis_pool_ext_bn_act_o_ready);
	
	conv_bn_act_proc #(
		.BN_ACT_CLK_RATE(BN_ACT_CLK_RATE),
		.FP32_KEEP(1'b1),
		.ATOMIC_K(ATOMIC_K),
		.BN_ACT_PRL_N(BN_ACT_PRL_N),
		.INT16_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.INT32_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.FP32_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.SIM_DELAY(SIM_DELAY)
	)bn_act_proc_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		.bn_act_aclk(bn_act_aclk),
		.bn_act_aresetn(bn_act_aresetn),
		.bn_act_aclken(1'b1),
		
		.en_bn_act_proc(en_bn_act_proc_dup),
		
		.calfmt(bn_act_calfmt),
		.use_bn_unit(bn_act_use_bn_unit),
		.act_func_type(bn_act_act_func_type),
		.bn_fixed_point_quat_accrc(bn_act_bn_fixed_point_quat_accrc),
		.bn_is_a_eq_1(bn_act_bn_is_a_eq_1),
		.bn_is_b_eq_0(bn_act_bn_is_b_eq_0),
		.is_in_const_mac_mode(bn_act_is_in_const_mac_mode),
		.param_a_in_const_mac_mode(bn_act_param_a_in_const_mac_mode),
		.param_b_in_const_mac_mode(bn_act_param_b_in_const_mac_mode),
		.leaky_relu_fixed_point_quat_accrc(bn_act_leaky_relu_fixed_point_quat_accrc),
		.leaky_relu_param_alpha(bn_act_leaky_relu_param_alpha),
		.sigmoid_tanh_fixed_point_quat_accrc(bn_act_sigmoid_tanh_fixed_point_quat_accrc),
		
		.s_sub_row_msg_axis_data(m_sub_row_msg_axis_data),
		.s_sub_row_msg_axis_last(m_sub_row_msg_axis_last),
		.s_sub_row_msg_axis_valid(m_sub_row_msg_axis_valid),
		.s_sub_row_msg_axis_ready(m_sub_row_msg_axis_ready),
		
		.s_axis_fnl_res_data(s_axis_bn_act_i_data),
		.s_axis_fnl_res_keep(s_axis_bn_act_i_keep),
		.s_axis_fnl_res_user(s_axis_bn_act_i_user),
		.s_axis_fnl_res_last(s_axis_bn_act_i_last),
		.s_axis_fnl_res_valid(s_axis_bn_act_i_valid),
		.s_axis_fnl_res_ready(s_axis_bn_act_i_ready),
		
		.m_axis_bn_act_res_data(m_axis_bn_act_o_data),
		.m_axis_bn_act_res_keep(m_axis_bn_act_o_keep),
		.m_axis_bn_act_res_user(m_axis_bn_act_o_user),
		.m_axis_bn_act_res_last(m_axis_bn_act_o_last),
		.m_axis_bn_act_res_valid(m_axis_bn_act_o_valid),
		.m_axis_bn_act_res_ready(m_axis_bn_act_o_ready),
		
		.bn_mem_clk_b(bn_mem_clk_b),
		.bn_mem_ren_b(bn_mem_ren_b),
		.bn_mem_addr_b(bn_mem_addr_b),
		.bn_mem_dout_b(bn_mem_dout_b),
		
		.proc_res_fifo_mem_clk_a(proc_res_fifo_mem_clk_a),
		.proc_res_fifo_mem_wen_a(proc_res_fifo_mem_wen_a),
		.proc_res_fifo_mem_addr_a(proc_res_fifo_mem_addr_a),
		.proc_res_fifo_mem_din_a(proc_res_fifo_mem_din_a),
		.proc_res_fifo_mem_clk_b(proc_res_fifo_mem_clk_b),
		.proc_res_fifo_mem_ren_b(proc_res_fifo_mem_ren_b),
		.proc_res_fifo_mem_addr_b(proc_res_fifo_mem_addr_b),
		.proc_res_fifo_mem_dout_b(proc_res_fifo_mem_dout_b),
		
		.mul0_clk(bn_mul_clk),
		.mul0_op_a(bn_mul_op_a),
		.mul0_op_b(bn_mul_op_b),
		.mul0_ce(bn_mul_ce),
		.mul0_res(bn_mul_res),
		
		.mul1_clk(leaky_relu_mul_clk),
		.mul1_op_a(leaky_relu_mul_op_a),
		.mul1_op_b(leaky_relu_mul_op_b),
		.mul1_ce(leaky_relu_mul_ce),
		.mul1_res(leaky_relu_mul_res),
		
		.sigmoid_lut_mem_clk_a(sigmoid_lut_mem_clk_a),
		.sigmoid_lut_mem_ren_a(sigmoid_lut_mem_ren_a),
		.sigmoid_lut_mem_addr_a(sigmoid_lut_mem_addr_a),
		.sigmoid_lut_mem_dout_a(sigmoid_lut_mem_dout_a)
	);
	
	/** 输出数据舍入单元组 **/
	// 运行时参数
	wire en_out_round; // 使能输出数据舍入
	wire[1:0] round_calfmt; // 运算数据格式
	wire[3:0] round_fixed_point_quat_accrc; // 定点数量化精度
	// 待舍入数据(AXIS从机)
	wire[ATOMIC_K*32-1:0] s_axis_round_data; // ATOMIC_K个定点数或FP32
	wire[ATOMIC_K*4-1:0] s_axis_round_keep;
	wire[4:0] s_axis_round_user;
	wire s_axis_round_last;
	wire s_axis_round_valid;
	wire s_axis_round_ready;
	// 舍入后数据(AXIS主机)
	wire[ATOMIC_K*16-1:0] m_axis_round_data; // ATOMIC_K个定点数或FP32
	wire[ATOMIC_K*2-1:0] m_axis_round_keep;
	wire[4:0] m_axis_round_user;
	wire m_axis_round_last;
	wire m_axis_round_valid;
	wire m_axis_round_ready;
	
	// 警告: 应该根据"运算数据格式"和"输出特征图数据大小类型"来判断是否需要进行输出数据舍入!!!
	assign en_out_round = 
		(FP32_KEEP == 0) & 
		(
			(RUNTIME_ODATA_ROUND_SEL_SUPPORTED == 0) | 
			(en_conv_accelerator & (conv_fnl_res_tr_req_gen_ofmap_data_type != OFMAP_DATA_4_BYTE)) | 
			(en_pool_accelerator & (pool_fnl_res_tr_req_gen_ofmap_data_type != OFMAP_DATA_4_BYTE))
		);
	assign round_calfmt = 
		({2{en_conv_accelerator}} & conv_round_calfmt) | 
		({2{en_pool_accelerator}} & pool_round_calfmt);
	assign round_fixed_point_quat_accrc = 
		({4{en_conv_accelerator}} & conv_round_fixed_point_quat_accrc) | 
		({4{en_pool_accelerator}} & pool_round_fixed_point_quat_accrc);
	
	assign s_axis_round_data = 
		({(ATOMIC_K*32){en_conv_accelerator}} & m_axis_conv_ext_round_i_data) | 
		({(ATOMIC_K*32){en_pool_accelerator}} & m_axis_pool_ext_round_i_data);
	assign s_axis_round_keep = 
		({(ATOMIC_K*4){en_conv_accelerator}} & m_axis_conv_ext_round_i_keep) | 
		({(ATOMIC_K*4){en_pool_accelerator}} & m_axis_pool_ext_round_i_keep);
	assign s_axis_round_user = 
		({5{en_conv_accelerator}} & m_axis_conv_ext_round_i_user) | 
		({5{en_pool_accelerator}} & m_axis_pool_ext_round_i_user);
	assign s_axis_round_last = 
		(en_conv_accelerator & m_axis_conv_ext_round_i_last) | 
		(en_pool_accelerator & m_axis_pool_ext_round_i_last);
	assign s_axis_round_valid = 
		en_out_round & 
		(
			(en_conv_accelerator & m_axis_conv_ext_round_i_valid) | 
			(en_pool_accelerator & m_axis_pool_ext_round_i_valid)
		);
	
	assign s_axis_conv_ext_round_o_data = m_axis_round_data;
	assign s_axis_conv_ext_round_o_keep = m_axis_round_keep;
	assign s_axis_conv_ext_round_o_user = m_axis_round_user;
	assign s_axis_conv_ext_round_o_last = m_axis_round_last;
	assign s_axis_conv_ext_round_o_valid = en_out_round & en_conv_accelerator & m_axis_round_valid;
	assign s_axis_pool_ext_round_o_data = m_axis_round_data;
	assign s_axis_pool_ext_round_o_keep = m_axis_round_keep;
	assign s_axis_pool_ext_round_o_user = m_axis_round_user;
	assign s_axis_pool_ext_round_o_last = m_axis_round_last;
	assign s_axis_pool_ext_round_o_valid = en_out_round & en_pool_accelerator & m_axis_round_valid;
	assign m_axis_round_ready = 
		(~en_out_round) | 
		(en_conv_accelerator & s_axis_conv_ext_round_o_ready) | 
		(en_pool_accelerator & s_axis_pool_ext_round_o_ready);
	
	out_round_group #(
		.ATOMIC_K(ATOMIC_K),
		.INT8_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.INT16_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.FP16_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.USER_WIDTH(5),
		.SIM_DELAY(SIM_DELAY)
	)out_round_group_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.calfmt(round_calfmt),
		.fixed_point_quat_accrc(round_fixed_point_quat_accrc),
		
		.s_axis_round_data(s_axis_round_data),
		.s_axis_round_keep(s_axis_round_keep),
		.s_axis_round_user(s_axis_round_user),
		.s_axis_round_last(s_axis_round_last),
		.s_axis_round_valid(s_axis_round_valid),
		.s_axis_round_ready(s_axis_round_ready),
		
		.m_axis_round_data(m_axis_round_data),
		.m_axis_round_keep(m_axis_round_keep),
		.m_axis_round_user(m_axis_round_user),
		.m_axis_round_last(m_axis_round_last),
		.m_axis_round_valid(m_axis_round_valid),
		.m_axis_round_ready(m_axis_round_ready)
	);
	
	/** 最终结果数据收集器 **/
	// 待收集的数据流(AXIS从机)
	wire[ATOMIC_K*((RUNTIME_ODATA_ROUND_SEL_SUPPORTED | FP32_KEEP) ? 32:16)-1:0] s_axis_collector_data;
	wire[ATOMIC_K*((RUNTIME_ODATA_ROUND_SEL_SUPPORTED | FP32_KEEP) ? 4:2)-1:0] s_axis_collector_keep;
	wire s_axis_collector_last;
	wire s_axis_collector_valid;
	wire s_axis_collector_ready;
	// 整理后的数据流(AXIS主机)
	wire[S2MM_STREAM_DATA_WIDTH-1:0] m_axis_collector_data;
	wire[S2MM_STREAM_DATA_WIDTH/8-1:0] m_axis_collector_keep;
	wire m_axis_collector_last;
	wire m_axis_collector_valid;
	wire m_axis_collector_ready;
	
	assign m_axis_conv_ext_round_i_ready = 
		(~en_conv_accelerator) | 
		(
			en_out_round ? 
				s_axis_round_ready:
				s_axis_collector_ready
		);
	assign m_axis_pool_ext_round_i_ready = 
		(~en_pool_accelerator) | 
		(
			en_out_round ? 
				s_axis_round_ready:
				s_axis_collector_ready
		);
	
	assign s_axis_collector_data = 
		({(ATOMIC_K*2*16){en_out_round & en_conv_accelerator}} & (m_axis_conv_ext_collector_data | {(ATOMIC_K*2*16){1'b0}})) | 
		({(ATOMIC_K*2*16){en_out_round & en_pool_accelerator}} & (m_axis_pool_ext_collector_data | {(ATOMIC_K*2*16){1'b0}})) | 
		({(ATOMIC_K*2*16){~en_out_round}} & s_axis_round_data);
	assign s_axis_collector_keep = 
		({(ATOMIC_K*2*2){en_out_round & en_conv_accelerator}} & (m_axis_conv_ext_collector_keep | {(ATOMIC_K*2*2){1'b0}})) | 
		({(ATOMIC_K*2*2){en_out_round & en_pool_accelerator}} & (m_axis_pool_ext_collector_keep | {(ATOMIC_K*2*2){1'b0}})) | 
		({(ATOMIC_K*2*2){~en_out_round}} & s_axis_round_keep);
	assign s_axis_collector_last = 
		((en_out_round & en_conv_accelerator) & m_axis_conv_ext_collector_last) | 
		((en_out_round & en_pool_accelerator) & m_axis_pool_ext_collector_last) | 
		((~en_out_round) & s_axis_round_last);
	assign s_axis_collector_valid = 
		((en_out_round & en_conv_accelerator) & m_axis_conv_ext_collector_valid) | 
		((en_out_round & en_pool_accelerator) & m_axis_pool_ext_collector_valid) | 
		(((~en_out_round) & en_conv_accelerator) & m_axis_conv_ext_round_i_valid) | 
		(((~en_out_round) & en_pool_accelerator) & m_axis_pool_ext_round_i_valid);
	assign m_axis_conv_ext_collector_ready = 
		(~en_out_round) | (~en_conv_accelerator) | s_axis_collector_ready;
	assign m_axis_pool_ext_collector_ready = 
		(~en_out_round) | (~en_pool_accelerator) | s_axis_collector_ready;
	
	conv_final_data_collector #(
		.IN_ITEM_WIDTH(ATOMIC_K*(RUNTIME_ODATA_ROUND_SEL_SUPPORTED ? 2:1)),
		.OUT_ITEM_WIDTH(S2MM_STREAM_DATA_WIDTH/((RUNTIME_ODATA_ROUND_SEL_SUPPORTED | (~FP32_KEEP)) ? 16:32)),
		.DATA_WIDTH_FOREACH_ITEM((RUNTIME_ODATA_ROUND_SEL_SUPPORTED | (~FP32_KEEP)) ? 16:32),
		.HAS_USER("false"),
		.USER_WIDTH(1),
		.EN_COLLECTOR_OUT_REG_SLICE("true"),
		.SIM_DELAY(SIM_DELAY)
	)final_data_collector_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.s_axis_collector_data(s_axis_collector_data),
		.s_axis_collector_keep(s_axis_collector_keep),
		.s_axis_collector_user(1'bx),
		.s_axis_collector_last(s_axis_collector_last),
		.s_axis_collector_valid(s_axis_collector_valid),
		.s_axis_collector_ready(s_axis_collector_ready),
		
		.m_axis_collector_data(m_axis_collector_data),
		.m_axis_collector_keep(m_axis_collector_keep),
		.m_axis_collector_user(),
		.m_axis_collector_last(m_axis_collector_last),
		.m_axis_collector_valid(m_axis_collector_valid),
		.m_axis_collector_ready(m_axis_collector_ready)
	);
	
	/** DMA通道 **/
	assign m0_dma_cmd_axis_data = 
		en_elm_proc_accelerator ? 
			m0_elm_dma_cmd_axis_data:
			m0_conv_pool_dma_cmd_axis_data;
	assign m0_dma_cmd_axis_user = 
		en_elm_proc_accelerator ? 
			m0_elm_dma_cmd_axis_user:
			m0_conv_pool_dma_cmd_axis_user;
	assign m0_dma_cmd_axis_last = 
		en_elm_proc_accelerator ? 
			m0_elm_dma_cmd_axis_last:
			m0_conv_pool_dma_cmd_axis_last;
	assign m0_dma_cmd_axis_valid = 
		en_elm_proc_accelerator ? 
			m0_elm_dma_cmd_axis_valid:
			m0_conv_pool_dma_cmd_axis_valid;
	assign m0_elm_dma_cmd_axis_ready = 
		(~en_elm_proc_accelerator) | m0_dma_cmd_axis_ready;
	assign m0_conv_pool_dma_cmd_axis_ready = 
		en_elm_proc_accelerator | m0_dma_cmd_axis_ready;
	
	assign m1_dma_cmd_axis_data = 
		en_elm_proc_accelerator ? 
			m1_elm_dma_cmd_axis_data:
			m1_conv_pool_dma_cmd_axis_data;
	assign m1_dma_cmd_axis_user = 
		en_elm_proc_accelerator ? 
			m1_elm_dma_cmd_axis_user:
			m1_conv_pool_dma_cmd_axis_user;
	assign m1_dma_cmd_axis_last = 
		en_elm_proc_accelerator ? 
			m1_elm_dma_cmd_axis_last:
			m1_conv_pool_dma_cmd_axis_last;
	assign m1_dma_cmd_axis_valid = 
		en_elm_proc_accelerator ? 
			m1_elm_dma_cmd_axis_valid:
			m1_conv_pool_dma_cmd_axis_valid;
	assign m1_elm_dma_cmd_axis_ready = 
		(~en_elm_proc_accelerator) | m1_dma_cmd_axis_ready;
	assign m1_conv_pool_dma_cmd_axis_ready = 
		en_elm_proc_accelerator | m1_dma_cmd_axis_ready;
	
	assign s0_elm_dma_strm_axis_data = s0_dma_strm_axis_data;
	assign s0_elm_dma_strm_axis_keep = s0_dma_strm_axis_keep;
	assign s0_elm_dma_strm_axis_last = s0_dma_strm_axis_last;
	assign s0_elm_dma_strm_axis_valid = en_elm_proc_accelerator & s0_dma_strm_axis_valid;
	assign s0_conv_pool_dma_strm_axis_data = s0_dma_strm_axis_data;
	assign s0_conv_pool_dma_strm_axis_keep = s0_dma_strm_axis_keep;
	assign s0_conv_pool_dma_strm_axis_last = s0_dma_strm_axis_last;
	assign s0_conv_pool_dma_strm_axis_valid = (~en_elm_proc_accelerator) & s0_dma_strm_axis_valid;
	assign s0_dma_strm_axis_ready = 
		en_elm_proc_accelerator ? 
			s0_elm_dma_strm_axis_ready:
			s0_conv_pool_dma_strm_axis_ready;
	
	assign s1_elm_dma_strm_axis_data = s1_dma_strm_axis_data;
	assign s1_elm_dma_strm_axis_keep = s1_dma_strm_axis_keep;
	assign s1_elm_dma_strm_axis_last = s1_dma_strm_axis_last;
	assign s1_elm_dma_strm_axis_valid = en_elm_proc_accelerator & s1_dma_strm_axis_valid;
	assign s1_conv_pool_dma_strm_axis_data = s1_dma_strm_axis_data;
	assign s1_conv_pool_dma_strm_axis_keep = s1_dma_strm_axis_keep;
	assign s1_conv_pool_dma_strm_axis_last = s1_dma_strm_axis_last;
	assign s1_conv_pool_dma_strm_axis_valid = (~en_elm_proc_accelerator) & s1_dma_strm_axis_valid;
	assign s1_dma_strm_axis_ready = 
		en_elm_proc_accelerator ? 
			s1_elm_dma_strm_axis_ready:
			s1_conv_pool_dma_strm_axis_ready;
	
	assign m_dma_s2mm_cmd_axis_data = 
		en_elm_proc_accelerator ? 
			m_elm_dma_s2mm_cmd_axis_data:
			m_conv_pool_dma_cmd_axis_data;
	assign m_dma_s2mm_cmd_axis_user = 
		en_elm_proc_accelerator ? 
			m_elm_dma_s2mm_cmd_axis_user:
			m_conv_pool_dma_cmd_axis_user[0];
	assign m_dma_s2mm_cmd_axis_valid = 
		en_elm_proc_accelerator ? 
			m_elm_dma_s2mm_cmd_axis_valid:
			m_conv_pool_dma_cmd_axis_valid;
	assign m_elm_dma_s2mm_cmd_axis_ready = 
		(~en_elm_proc_accelerator) | m_dma_s2mm_cmd_axis_ready;
	assign m_conv_pool_dma_cmd_axis_ready = 
		en_elm_proc_accelerator | m_dma_s2mm_cmd_axis_ready;
	
	assign m_axis_fnl_res_data = 
		en_elm_proc_accelerator ? 
			m_elm_dma_strm_axis_data:
			m_axis_collector_data;
	assign m_axis_fnl_res_keep = 
		en_elm_proc_accelerator ? 
			m_elm_dma_strm_axis_keep:
			m_axis_collector_keep;
	assign m_axis_fnl_res_last = 
		en_elm_proc_accelerator ? 
			m_elm_dma_strm_axis_last:
			m_axis_collector_last;
	assign m_axis_fnl_res_valid = 
		en_elm_proc_accelerator ? 
			m_elm_dma_strm_axis_valid:
			m_axis_collector_valid;
	assign m_elm_dma_strm_axis_ready = 
		(~en_elm_proc_accelerator) | m_axis_fnl_res_ready;
	assign m_axis_collector_ready = 
		en_elm_proc_accelerator | m_axis_fnl_res_ready;
	
	/** 乘法器 **/
	unsigned_mul #(
		.op_a_width(16),
		.op_b_width(24),
		.output_width(40),
		.simulation_delay(SIM_DELAY)
	)mul_u16_u24_u1(
		.clk(aclk),
		
		.ce_s0_mul(mul2_ce),
		
		.op_a(mul2_op_a),
		.op_b(mul2_op_b),
		
		.res(mul2_res)
	);
	
	genvar bn_act_mul_i;
	generate
		for(bn_act_mul_i = 0;bn_act_mul_i < BN_ACT_PRL_N;bn_act_mul_i = bn_act_mul_i + 1)
		begin:leaky_relu_mul_blk
			signed_mul #(
				.op_a_width(INT16_SUPPORTED ? 32:25),
				.op_b_width(INT16_SUPPORTED ? 32:25),
				.output_width(INT16_SUPPORTED ? 64:50),
				.en_in_reg("false"),
				.en_out_reg("true"),
				.simulation_delay(SIM_DELAY)
			)leaky_relu_mul_u(
				.clk(leaky_relu_mul_clk),
				
				.ce_in_reg(1'b0),
				.ce_mul(leaky_relu_mul_ce[bn_act_mul_i*2+0]),
				.ce_out_reg(leaky_relu_mul_ce[bn_act_mul_i*2+1]),
				
				.op_a(leaky_relu_mul_op_a[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:bn_act_mul_i*(INT16_SUPPORTED ? 32:25)]),
				.op_b(leaky_relu_mul_op_b[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:bn_act_mul_i*(INT16_SUPPORTED ? 32:25)]),
				
				.res(leaky_relu_mul_res[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 64:50)-1:bn_act_mul_i*(INT16_SUPPORTED ? 64:50)])
			);
		end
		
		if(INT8_SUPPORTED)
		begin:case_bn_act_int16_supported
			for(bn_act_mul_i = 0;bn_act_mul_i < 4 * BN_ACT_PRL_N;bn_act_mul_i = bn_act_mul_i + 1)
			begin:bn_mul_blk_a
				signed_mul #(
					.op_a_width(18),
					.op_b_width(18),
					.output_width(36),
					.en_in_reg("false"),
					.en_out_reg("false"),
					.simulation_delay(SIM_DELAY)
				)bn_mul_u(
					.clk(bn_mul_clk),
					
					.ce_in_reg(1'b0),
					.ce_mul(bn_mul_ce[bn_act_mul_i]),
					.ce_out_reg(1'b0),
					
					.op_a(bn_mul_op_a[(bn_act_mul_i+1)*18-1:bn_act_mul_i*18]),
					.op_b(bn_mul_op_b[(bn_act_mul_i+1)*18-1:bn_act_mul_i*18]),
					
					.res(bn_mul_res[(bn_act_mul_i+1)*36-1:bn_act_mul_i*36])
				);
			end
		end
		else
		begin:case_bn_act_int16_not_supported
			for(bn_act_mul_i = 0;bn_act_mul_i < BN_ACT_PRL_N;bn_act_mul_i = bn_act_mul_i + 1)
			begin:bn_mul_blk_b
				signed_mul #(
					.op_a_width(INT16_SUPPORTED ? 32:25),
					.op_b_width(INT16_SUPPORTED ? 32:25),
					.output_width(INT16_SUPPORTED ? 64:50),
					.en_in_reg("true"),
					.en_out_reg("true"),
					.simulation_delay(SIM_DELAY)
				)bn_mul_u(
					.clk(bn_mul_clk),
					
					.ce_in_reg(bn_mul_ce[bn_act_mul_i*3+0]),
					.ce_mul(bn_mul_ce[bn_act_mul_i*3+1]),
					.ce_out_reg(bn_mul_ce[bn_act_mul_i*3+2]),
					
					.op_a(bn_mul_op_a[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:bn_act_mul_i*(INT16_SUPPORTED ? 32:25)]),
					.op_b(bn_mul_op_b[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:bn_act_mul_i*(INT16_SUPPORTED ? 32:25)]),
					
					.res(bn_mul_res[(bn_act_mul_i+1)*(INT16_SUPPORTED ? 64:50)-1:bn_act_mul_i*(INT16_SUPPORTED ? 64:50)])
				);
			end
		end
	endgenerate
	
	/** SRAM **/
	genvar mid_res_mem_i;
	generate
		for(mid_res_mem_i = 0;mid_res_mem_i < RBUF_BANK_N;mid_res_mem_i = mid_res_mem_i + 1)
		begin:mem_blk
			bram_simple_dual_port #(
				.style("LOW_LATENCY"),
				.mem_width(ATOMIC_K*4*8+ATOMIC_K),
				.mem_depth(RBUF_DEPTH),
				.INIT_FILE("no_init"),
				.simulation_delay(SIM_DELAY)
			)mid_res_ram_u(
				.clk(mid_res_mem_clk_a),
				
				.wen_a(mid_res_mem_wen_a[mid_res_mem_i]),
				.addr_a(mid_res_mem_addr_a[mid_res_mem_i*16+15:mid_res_mem_i*16]),
				.din_a(mid_res_mem_din_a[(mid_res_mem_i+1)*(ATOMIC_K*4*8+ATOMIC_K)-1:mid_res_mem_i*(ATOMIC_K*4*8+ATOMIC_K)]),
				
				.ren_b(mid_res_mem_ren_b[mid_res_mem_i]),
				.addr_b(mid_res_mem_addr_b[mid_res_mem_i*16+15:mid_res_mem_i*16]),
				.dout_b(mid_res_mem_dout_b[(mid_res_mem_i+1)*(ATOMIC_K*4*8+ATOMIC_K)-1:mid_res_mem_i*(ATOMIC_K*4*8+ATOMIC_K)])
			);
		end
	endgenerate
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(LG_FMBUF_BUFFER_RID_WIDTH),
		.mem_depth(4096),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)actual_rid_mp_tb_ram_u(
		.clk(actual_rid_mp_tb_mem_clk),
		
		.wen_a(actual_rid_mp_tb_mem_wen_a),
		.addr_a(actual_rid_mp_tb_mem_addr_a),
		.din_a(actual_rid_mp_tb_mem_din_a),
		
		.ren_b(actual_rid_mp_tb_mem_ren_b),
		.addr_b(actual_rid_mp_tb_mem_addr_b),
		.dout_b(actual_rid_mp_tb_mem_dout_b)
	);
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(12),
		.mem_depth(2 ** LG_FMBUF_BUFFER_RID_WIDTH),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)buffer_rid_mp_tb_ram_u(
		.clk(buffer_rid_mp_tb_mem_clk),
		
		.wen_a(buffer_rid_mp_tb_mem_wen_a),
		.addr_a(buffer_rid_mp_tb_mem_addr_a),
		.din_a(buffer_rid_mp_tb_mem_din_a),
		
		.ren_b(buffer_rid_mp_tb_mem_ren_b),
		.addr_b(buffer_rid_mp_tb_mem_addr_b),
		.dout_b(buffer_rid_mp_tb_mem_dout_b)
	);
	
	genvar phy_conv_buf_mem_i;
	generate
		for(phy_conv_buf_mem_i = 0;phy_conv_buf_mem_i < CBUF_BANK_N;phy_conv_buf_mem_i = phy_conv_buf_mem_i + 1)
		begin:phy_conv_buf_mem_blk
			if(PHY_BUF_USE_TRUE_DUAL_PORT_SRAM)
			begin
				bram_true_dual_port #(
					.mem_width(ATOMIC_C*2*8),
					.mem_depth(CBUF_DEPTH_FOREACH_BANK),
					.INIT_FILE("no_init"),
					.read_write_mode("read_first"),
					.use_output_register("false"),
					.en_byte_write("true"),
					.simulation_delay(SIM_DELAY)
				)phy_conv_buf_ram_u(
					.clk(phy_conv_buf_mem_clk_a),
					
					.ena(phy_conv_buf_mem_en_a[phy_conv_buf_mem_i]),
					.wea(phy_conv_buf_mem_wen_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2-1:phy_conv_buf_mem_i*ATOMIC_C*2]),
					.addra(phy_conv_buf_mem_addr_a[phy_conv_buf_mem_i*16+clogb2(CBUF_DEPTH_FOREACH_BANK-1):phy_conv_buf_mem_i*16]),
					.dina(phy_conv_buf_mem_din_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8]),
					.douta(phy_conv_buf_mem_dout_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8]),
					
					.enb(phy_conv_buf_mem_en_b[phy_conv_buf_mem_i]),
					.web(phy_conv_buf_mem_wen_b[(phy_conv_buf_mem_i+1)*ATOMIC_C*2-1:phy_conv_buf_mem_i*ATOMIC_C*2]),
					.addrb(phy_conv_buf_mem_addr_b[phy_conv_buf_mem_i*16+clogb2(CBUF_DEPTH_FOREACH_BANK-1):phy_conv_buf_mem_i*16]),
					.dinb(phy_conv_buf_mem_din_b[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8]),
					.doutb(phy_conv_buf_mem_dout_b[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8])
				);
			end
			else
			begin
				assign phy_conv_buf_mem_dout_b = {(CBUF_BANK_N*ATOMIC_C*2*8){1'bx}};
				
				bram_single_port #(
					.style("LOW_LATENCY"),
					.rw_mode("read_first"),
					.mem_width(ATOMIC_C*2*8),
					.mem_depth(CBUF_DEPTH_FOREACH_BANK),
					.INIT_FILE("no_init"),
					.byte_write_mode("true"),
					.simulation_delay(SIM_DELAY)
				)phy_conv_buf_ram_u(
					.clk(phy_conv_buf_mem_clk_a),
					
					.en(phy_conv_buf_mem_en_a[phy_conv_buf_mem_i]),
					.wen(phy_conv_buf_mem_wen_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2-1:phy_conv_buf_mem_i*ATOMIC_C*2]),
					.addr(phy_conv_buf_mem_addr_a[phy_conv_buf_mem_i*16+clogb2(CBUF_DEPTH_FOREACH_BANK-1):phy_conv_buf_mem_i*16]),
					.din(phy_conv_buf_mem_din_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8]),
					.dout(phy_conv_buf_mem_dout_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8])
				);
			end
		end
	endgenerate
	
	bram_simple_dual_port_async #(
		.style("LOW_LATENCY"),
		.mem_width(BN_ACT_PROC_RES_FIFO_WIDTH),
		.mem_depth(512),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)proc_res_fifo_ram_u(
		.clk_a(proc_res_fifo_mem_clk_a),
		.clk_b(proc_res_fifo_mem_clk_b),
		
		.wen_a(proc_res_fifo_mem_wen_a),
		.addr_a(proc_res_fifo_mem_addr_a),
		.din_a(proc_res_fifo_mem_din_a),
		
		.ren_b(proc_res_fifo_mem_ren_b),
		.addr_b(proc_res_fifo_mem_addr_b),
		.dout_b(proc_res_fifo_mem_dout_b)
	);
	
	bram_true_dual_port_async #(
		.mem_width(64),
		.mem_depth(MAX_KERNAL_N),
		.INIT_FILE("no_init"),
		.read_write_mode("read_first"),
		.use_output_register("false"),
		.en_byte_write("true"),
		.simulation_delay(SIM_DELAY)
	)bn_param_ram_u(
		.clk_a(bn_mem_clk_a),
		.clk_b(bn_mem_clk_b),
		
		.ena(bn_mem_en_a),
		.wea(bn_mem_wen_a),
		.addra(bn_mem_addr_a),
		.dina(bn_mem_din_a),
		.douta(bn_mem_dout_a),
		
		.enb(bn_mem_ren_b),
		.web(8'b0000_0000),
		.addrb(bn_mem_addr_b),
		.dinb(64'dx),
		.doutb(bn_mem_dout_b)
	);
	
	genvar sigmoid_lut_mem_i;
	generate
		for(sigmoid_lut_mem_i = 0;sigmoid_lut_mem_i < BN_ACT_PRL_N;sigmoid_lut_mem_i = sigmoid_lut_mem_i + 1)
		begin:sigmoid_lut_mem_blk
			assign sigmoid_lut_mem_dout_a[sigmoid_lut_mem_i*16+15:sigmoid_lut_mem_i*16] = 
				sigmoid_lut_mem_dout_a_half_word_sel[sigmoid_lut_mem_i] ? 
					sigmoid_lut_mem_dout_a_32[sigmoid_lut_mem_i][31:16]:
					sigmoid_lut_mem_dout_a_32[sigmoid_lut_mem_i][15:0];
			
			always @(posedge sigmoid_lut_mem_clk_a)
			begin
				if(sigmoid_lut_mem_ren_a[sigmoid_lut_mem_i])
					sigmoid_lut_mem_dout_a_half_word_sel[sigmoid_lut_mem_i] <= # SIM_DELAY 
						sigmoid_lut_mem_addr_a[12*sigmoid_lut_mem_i+0];
			end
			
			bram_true_dual_port_async #(
				.mem_width(32),
				.mem_depth(4096/2),
				.INIT_FILE("no_init"),
				.read_write_mode("read_first"),
				.use_output_register("false"),
				.en_byte_write("true"),
				.simulation_delay(SIM_DELAY)
			)sigmoid_lut_mem_u(
				.clk_a(sigmoid_lut_mem_clk_b),
				.clk_b(sigmoid_lut_mem_clk_a),
				
				.ena(sigmoid_lut_mem_en_b),
				.wea(sigmoid_lut_mem_wen_b),
				.addra(sigmoid_lut_mem_addr_b[10:0]),
				.dina(sigmoid_lut_mem_din_b),
				.douta(sigmoid_lut_mem_dout_b[sigmoid_lut_mem_i]),
				
				.enb(sigmoid_lut_mem_ren_a[sigmoid_lut_mem_i]),
				.web(4'b0000),
				.addrb(sigmoid_lut_mem_addr_a[12*sigmoid_lut_mem_i+11:12*sigmoid_lut_mem_i+1]),
				.dinb(32'dx),
				.doutb(sigmoid_lut_mem_dout_a_32[sigmoid_lut_mem_i])
			);
		end
	endgenerate
	
	/** 调试 **/
	/*
	// MM2S#0
	(*mark_debug="true"*)reg[31:0] mm2s_0_id;
	(*mark_debug="true"*)wire mm2s_0_last;
	(*mark_debug="true"*)wire mm2s_0_valid;
	(*mark_debug="true"*)wire mm2s_0_ready;
	// MM2S#1
	(*mark_debug="true"*)reg[31:0] mm2s_1_id;
	(*mark_debug="true"*)wire mm2s_1_last;
	(*mark_debug="true"*)wire mm2s_1_valid;
	(*mark_debug="true"*)wire mm2s_1_ready;
	// S2MM
	(*mark_debug="true"*)reg[31:0] s2mm_id;
	(*mark_debug="true"*)wire s2mm_last;
	(*mark_debug="true"*)wire s2mm_valid;
	(*mark_debug="true"*)wire s2mm_ready;
	// 乘加阵列特征图数据输入
	(*mark_debug="true"*)reg[31:0] array_i_fmap_id;
	(*mark_debug="true"*)wire array_i_fmap_last;
	(*mark_debug="true"*)wire array_i_fmap_valid;
	(*mark_debug="true"*)wire array_i_fmap_ready;
	// 乘加阵列卷积核数据输入
	(*mark_debug="true"*)reg[31:0] array_i_kernal_id;
	(*mark_debug="true"*)wire array_i_kernal_last;
	(*mark_debug="true"*)wire array_i_kernal_valid;
	(*mark_debug="true"*)wire array_i_kernal_ready;
	// 乘加阵列结果输出
	(*mark_debug="true"*)reg[31:0] array_o_id;
	(*mark_debug="true"*)wire array_o_valid;
	(*mark_debug="true"*)wire array_o_ready;
	// 卷积中间结果表面行信息打包输出
	(*mark_debug="true"*)reg[31:0] pkt_o_id;
	(*mark_debug="true"*)wire pkt_o_last;
	(*mark_debug="true"*)wire pkt_o_valid;
	(*mark_debug="true"*)wire pkt_o_ready;
	// 中间结果累加与缓存输出
	(*mark_debug="true"*)reg[31:0] mid_res_o_id;
	(*mark_debug="true"*)wire mid_res_o_last;
	(*mark_debug="true"*)wire mid_res_o_valid;
	(*mark_debug="true"*)wire mid_res_o_ready;
	// BN与激活处理输入
	(*mark_debug="true"*)reg[31:0] bn_act_i_id;
	(*mark_debug="true"*)wire bn_act_i_last;
	(*mark_debug="true"*)wire bn_act_i_valid;
	(*mark_debug="true"*)wire bn_act_i_ready;
	// BN与激活处理输出
	(*mark_debug="true"*)reg[31:0] bn_act_o_id;
	(*mark_debug="true"*)wire bn_act_o_last;
	(*mark_debug="true"*)wire bn_act_o_valid;
	(*mark_debug="true"*)wire bn_act_o_ready;
	
	assign {mm2s_0_last, mm2s_0_valid, mm2s_0_ready} = 
		{s0_dma_strm_axis_last, s0_dma_strm_axis_valid, s0_dma_strm_axis_ready};
	assign {mm2s_1_last, mm2s_1_valid, mm2s_1_ready} = 
		{s1_dma_strm_axis_last, s1_dma_strm_axis_valid, s1_dma_strm_axis_ready};
	assign {s2mm_last, s2mm_valid, s2mm_ready} = 
		{m_axis_fnl_res_last, m_axis_fnl_res_valid, m_axis_fnl_res_ready};
	assign {array_i_fmap_last, array_i_fmap_valid, array_i_fmap_ready} = {
		axi_generic_conv_core_u.conv_cal_sub_system_u.array_i_ftm_sfc_last,
		axi_generic_conv_core_u.conv_cal_sub_system_u.array_i_ftm_sfc_vld,
		axi_generic_conv_core_u.conv_cal_sub_system_u.array_i_ftm_sfc_rdy
	};
	assign {array_i_kernal_last, array_i_kernal_valid, array_i_kernal_ready} = {
		axi_generic_conv_core_u.conv_cal_sub_system_u.array_i_kernal_sfc_last,
		axi_generic_conv_core_u.conv_cal_sub_system_u.array_i_kernal_sfc_vld,
		axi_generic_conv_core_u.conv_cal_sub_system_u.array_i_kernal_buf_full_n
	};
	assign {array_o_valid, array_o_ready} = {
		axi_generic_conv_core_u.conv_cal_sub_system_u.array_o_res_vld,
		axi_generic_conv_core_u.conv_cal_sub_system_u.array_o_res_rdy
	};
	assign {pkt_o_last, pkt_o_valid, pkt_o_ready} = {
		axi_generic_conv_core_u.conv_cal_sub_system_u.m_axis_pkt_out_last,
		axi_generic_conv_core_u.conv_cal_sub_system_u.m_axis_pkt_out_valid,
		axi_generic_conv_core_u.conv_cal_sub_system_u.m_axis_pkt_out_ready
	};
	assign {mid_res_o_last, mid_res_o_valid, mid_res_o_ready} = {
		m_axis_buf_fnl_res_last,
		m_axis_buf_fnl_res_valid,
		m_axis_buf_fnl_res_ready
	};
	assign {bn_act_i_last, bn_act_i_valid, bn_act_i_ready} = {
		s_axis_bn_act_i_last,
		s_axis_bn_act_i_valid,
		s_axis_bn_act_i_ready
	};
	assign {bn_act_o_last, bn_act_o_valid, bn_act_o_ready} = {
		m_axis_bn_act_o_last,
		m_axis_bn_act_o_valid,
		m_axis_bn_act_o_ready
	};
	
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			mm2s_0_id <= # SIM_DELAY 32'd0;
		else if(mm2s_0_valid & mm2s_0_ready)
			mm2s_0_id <= # SIM_DELAY mm2s_0_id + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			mm2s_1_id <= # SIM_DELAY 32'd0;
		else if(mm2s_1_valid & mm2s_1_ready)
			mm2s_1_id <= # SIM_DELAY mm2s_1_id + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			s2mm_id <= # SIM_DELAY 32'd0;
		else if(s2mm_valid & s2mm_ready)
			s2mm_id <= # SIM_DELAY s2mm_id + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			array_i_fmap_id <= # SIM_DELAY 32'd0;
		else if(array_i_fmap_valid & array_i_fmap_ready)
			array_i_fmap_id <= # SIM_DELAY array_i_fmap_id + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			array_i_kernal_id <= # SIM_DELAY 32'd0;
		else if(array_i_kernal_valid & array_i_kernal_ready)
			array_i_kernal_id <= # SIM_DELAY array_i_kernal_id + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			array_o_id <= # SIM_DELAY 32'd0;
		else if(array_o_valid & array_o_ready)
			array_o_id <= # SIM_DELAY array_o_id + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			pkt_o_id <= # SIM_DELAY 32'd0;
		else if(pkt_o_valid & pkt_o_ready)
			pkt_o_id <= # SIM_DELAY pkt_o_id + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			mid_res_o_id <= # SIM_DELAY 32'd0;
		else if(mid_res_o_valid & mid_res_o_ready)
			mid_res_o_id <= # SIM_DELAY mid_res_o_id + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			bn_act_i_id <= # SIM_DELAY 32'd0;
		else if(bn_act_i_valid & bn_act_i_ready)
			bn_act_i_id <= # SIM_DELAY bn_act_i_id + 1'b1;
	end
	always @(posedge aclk)
	begin
		if(~en_conv_accelerator)
			bn_act_o_id <= # SIM_DELAY 32'd0;
		else if(bn_act_o_valid & bn_act_o_ready)
			bn_act_o_id <= # SIM_DELAY bn_act_o_id + 1'b1;
	end
	*/
	
endmodule
