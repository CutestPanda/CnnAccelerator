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
本模块: AXI-通用卷积处理单元

描述:
AXI-通用卷积处理单元(顶层模块)

包括寄存器配置接口、控制子系统、数据枢纽、计算子系统

支持普通卷积(包括全连接层)、组卷积(包括深度可分离卷积)、转置卷积(转换为合适的特征图填充与卷积步长来实现)
支持特征图外填充与内填充
支持卷积核膨胀
支持计算轮次拓展
支持批归一化处理
支持Leaky-Relu激活

注意：
需要外接2个DMA(MM2S)通道和1个DMA(S2MM)通道

可将SRAM和乘法器的接口引出, 在SOC层面再连接, 以实现SRAM和乘法器的共享

BN与激活并行数(BN_ACT_PRL_N)必须<=核并行数(ATOMIC_K)

协议:
AXI-Lite SLAVE
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/12/22
********************************************************************/


module axi_generic_conv #(
	parameter integer BN_SUPPORTED = 1, // 是否支持批归一化处理
	parameter integer LEAKY_RELU_SUPPORTED = 1, // 是否支持Leaky-Relu激活
	parameter integer INT8_SUPPORTED = 0, // 是否支持INT8
	parameter integer INT16_SUPPORTED = 0, // 是否支持INT16
	parameter integer FP16_SUPPORTED = 1, // 是否支持FP16
	parameter integer LARGE_V_STRD_SUPPORTED = 1, // 是否支持>1的卷积垂直步长
	parameter integer LARGE_H_STRD_SUPPORTED = 1, // 是否支持>1的卷积水平步长
	parameter integer GRP_CONV_SUPPORTED = 0, // 是否支持组卷积
	parameter integer EXT_PADDING_SUPPORTED = 1, // 是否支持外填充
	parameter integer INNER_PADDING_SUPPORTED = 0, // 是否支持内填充
	parameter integer KERNAL_DILATION_SUPPORTED = 0, // 是否支持卷积核膨胀
	parameter integer EN_PERF_MON = 1, // 是否支持性能监测
	parameter integer ACCELERATOR_ID = 0, // 加速器ID(0~3)
	parameter integer FP32_KEEP = 0, // 是否保持FP32输出
	parameter integer ATOMIC_K = 4, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer BN_ACT_PRL_N = 1, // BN与激活并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 2, // 最大的计算轮次(1~16)
	parameter integer MM2S_STREAM_DATA_WIDTH = 64, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16, // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 1024, // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512, // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer MAX_KERNAL_N = 1024, // 最大的卷积核个数(512 | 1024 | 2048 | 4096 | 8192)
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
	
	// BN参数存储器(AXI从机)
    // 读地址通道
    input wire[31:0] s_axi_araddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_arburst,
    input wire[3:0] s_axi_arcache, // ignored
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_arlen,
    input wire s_axi_arlock, // ignored
    input wire[2:0] s_axi_arprot, // ignored
    input wire[2:0] s_axi_arsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // 写地址通道
    input wire[31:0] s_axi_awaddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_awburst,
    input wire[3:0] s_axi_awcache, // ignored
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_awlen,
    input wire s_axi_awlock, // ignored
    input wire[2:0] s_axi_awprot, // ignored
    input wire[2:0] s_axi_awsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // 写响应通道
    output wire[1:0] s_axi_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    // 读数据通道
    output wire[31:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // 写数据通道
    input wire[31:0] s_axi_wdata,
    input wire s_axi_wlast,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
	
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
	output wire[4:0] m_axis_fnl_res_user, // {是否最后1个子行(1bit), 子行号(4bit)}
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
	
	/** 内部参数 **/
	// 特征图缓存的缓存行号的位宽
	localparam integer LG_FMBUF_BUFFER_RID_WIDTH = clogb2(MAX_FMBUF_ROWN);
	// 批归一化与激活处理结果fifo的位宽
	localparam integer BN_ACT_PROC_RES_FIFO_WIDTH = BN_ACT_PRL_N*(FP32_KEEP ? 32:16)+BN_ACT_PRL_N+1+5;
	// BN乘法器的位宽
	localparam integer BN_MUL_OP_WIDTH = INT8_SUPPORTED ? 4*18:(INT16_SUPPORTED ? 32:25);
	localparam integer BN_MUL_CE_WIDTH = INT8_SUPPORTED ? 4:3;
	localparam integer BN_MUL_RES_WIDTH = INT8_SUPPORTED ? 4*36:(INT16_SUPPORTED ? 64:50);
	// 泄露Relu乘法器的位宽
	localparam integer LEAKY_RELU_MUL_OP_WIDTH = INT16_SUPPORTED ? 32:25;
	localparam integer LEAKY_RELU_MUL_CE_WIDTH = 2;
	localparam integer LEAKY_RELU_MUL_RES_WIDTH = INT16_SUPPORTED ? 64:50;
	
	/** 寄存器配置接口 **/
	// 使能信号
	wire en_mac_array; // 使能乘加阵列
	wire en_packer; // 使能打包器
	wire en_bn_act_proc; // 使能批归一化与激活处理单元
	// 运行时参数
	// [计算参数]
	wire[1:0] calfmt; // 运算数据格式
	wire[2:0] conv_vertical_stride; // 卷积垂直步长 - 1
	wire[2:0] conv_horizontal_stride; // 卷积水平步长 - 1
	wire[3:0] cal_round; // 计算轮次 - 1
	// [组卷积模式]
	wire is_grp_conv_mode; // 是否处于组卷积模式
	wire[15:0] group_n; // 分组数 - 1
	wire[15:0] n_foreach_group; // 每组的通道数/核数 - 1
	wire[31:0] data_size_foreach_group; // (特征图)每组的数据量
	// [特征图参数]
	wire[31:0] ifmap_baseaddr; // 输入特征图基地址
	wire[31:0] ofmap_baseaddr; // 输出特征图基地址
	wire[15:0] ifmap_w; // 输入特征图宽度 - 1
	wire[23:0] ifmap_size; // 输入特征图大小 - 1
	wire[15:0] fmap_chn_n; // 特征图通道数 - 1
	wire[15:0] fmap_ext_i_bottom; // 扩展后特征图的垂直边界
	wire[2:0] external_padding_left; // 左部外填充数
	wire[2:0] external_padding_top; // 上部外填充数
	wire[2:0] inner_padding_left_right; // 左右内填充数
	wire[2:0] inner_padding_top_bottom; // 上下内填充数
	wire[15:0] ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] ofmap_h; // 输出特征图高度 - 1
	wire[1:0] ofmap_data_type; // 输出特征图数据大小类型
	// [卷积核参数]
	wire[31:0] kernal_wgt_baseaddr; // 卷积核权重基地址
	wire[2:0] kernal_shape; // 卷积核形状
	wire[3:0] kernal_dilation_hzt_n; // 水平膨胀量
	wire[4:0] kernal_w_dilated; // (膨胀后)卷积核宽度 - 1
	wire[3:0] kernal_dilation_vtc_n; // 垂直膨胀量
	wire[4:0] kernal_h_dilated; // (膨胀后)卷积核高度 - 1
	wire[15:0] kernal_chn_n; // 通道数 - 1
	wire[15:0] cgrpn_foreach_kernal_set; // 每个核组的通道组数 - 1
	wire[15:0] kernal_num_n; // 核数 - 1
	wire[15:0] kernal_set_n; // 核组个数 - 1
	wire[5:0] max_wgtblk_w; // 权重块最大宽度
	// [缓存参数]
	wire[7:0] fmbufbankn; // 分配给特征图缓存的Bank数
	wire[3:0] fmbufcoln; // 每个表面行的表面个数类型
	wire[9:0] fmbufrown; // 可缓存的表面行数 - 1
	wire[2:0] sfc_n_each_wgtblk; // 每个权重块的表面个数的类型
	wire[7:0] kbufgrpn; // 可缓存的通道组数 - 1
	wire[15:0] mid_res_item_n_foreach_row; // 每个输出特征图表面行的中间结果项数 - 1
	wire[3:0] mid_res_buf_row_n_bufferable; // 可缓存行数 - 1
	// [批归一化与激活参数]
	wire use_bn_unit; // 启用BN单元
	wire use_act_unit; // 启用激活单元
	wire[4:0] bn_fixed_point_quat_accrc; // (批归一化操作数A)定点数量化精度
	wire bn_is_a_eq_1; // 批归一化参数A的实际值为1(标志)
	wire bn_is_b_eq_0; // 批归一化参数B的实际值为0(标志)
	wire[4:0] leaky_relu_fixed_point_quat_accrc; // (泄露Relu激活参数)定点数量化精度
	wire[31:0] leaky_relu_param_alpha; // 泄露Relu激活参数
	// 块级控制
	// [卷积核权重访问请求生成单元]
	wire kernal_access_blk_start;
	wire kernal_access_blk_idle;
	wire kernal_access_blk_done;
	// [特征图表面行访问请求生成单元]
	wire fmap_access_blk_start;
	wire fmap_access_blk_idle;
	wire fmap_access_blk_done;
	// [最终结果传输请求生成单元]
	wire fnl_res_trans_blk_start;
	wire fnl_res_trans_blk_idle;
	wire fnl_res_trans_blk_done;
	
	reg_if_for_generic_conv #(
		.BN_SUPPORTED(BN_SUPPORTED ? 1'b1:1'b0),
		.LEAKY_RELU_SUPPORTED(LEAKY_RELU_SUPPORTED ? 1'b1:1'b0),
		.INT8_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.INT16_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.FP16_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.LARGE_V_STRD_SUPPORTED(LARGE_V_STRD_SUPPORTED ? 1'b1:1'b0),
		.LARGE_H_STRD_SUPPORTED(LARGE_H_STRD_SUPPORTED ? 1'b1:1'b0),
		.GRP_CONV_SUPPORTED(GRP_CONV_SUPPORTED ? 1'b1:1'b0),
		.EXT_PADDING_SUPPORTED(EXT_PADDING_SUPPORTED ? 1'b1:1'b0),
		.INNER_PADDING_SUPPORTED(INNER_PADDING_SUPPORTED ? 1'b1:1'b0),
		.KERNAL_DILATION_SUPPORTED(KERNAL_DILATION_SUPPORTED ? 1'b1:1'b0),
		.EN_PERF_MON(EN_PERF_MON ? 1'b1:1'b0),
		.ACCELERATOR_ID(ACCELERATOR_ID),
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
	)reg_if_for_generic_conv_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.s_axi_lite_araddr(s_axi_lite_araddr),
		.s_axi_lite_arvalid(s_axi_lite_arvalid),
		.s_axi_lite_arready(s_axi_lite_arready),
		.s_axi_lite_awaddr(s_axi_lite_awaddr),
		.s_axi_lite_awvalid(s_axi_lite_awvalid),
		.s_axi_lite_awready(s_axi_lite_awready),
		.s_axi_lite_bresp(s_axi_lite_bresp),
		.s_axi_lite_bvalid(s_axi_lite_bvalid),
		.s_axi_lite_bready(s_axi_lite_bready),
		.s_axi_lite_rdata(s_axi_lite_rdata),
		.s_axi_lite_rresp(s_axi_lite_rresp),
		.s_axi_lite_rvalid(s_axi_lite_rvalid),
		.s_axi_lite_rready(s_axi_lite_rready),
		.s_axi_lite_wdata(s_axi_lite_wdata),
		.s_axi_lite_wvalid(s_axi_lite_wvalid),
		.s_axi_lite_wready(s_axi_lite_wready),
		
		.en_mac_array(en_mac_array),
		.en_packer(en_packer),
		.en_bn_act_proc(en_bn_act_proc),
		
		.calfmt(calfmt),
		.conv_vertical_stride(conv_vertical_stride),
		.conv_horizontal_stride(conv_horizontal_stride),
		.cal_round(cal_round),
		.is_grp_conv_mode(is_grp_conv_mode),
		.group_n(group_n),
		.n_foreach_group(n_foreach_group),
		.data_size_foreach_group(data_size_foreach_group),
		.ifmap_baseaddr(ifmap_baseaddr),
		.ofmap_baseaddr(ofmap_baseaddr),
		.ifmap_w(ifmap_w),
		.ifmap_size(ifmap_size),
		.fmap_chn_n(fmap_chn_n),
		.fmap_ext_i_bottom(fmap_ext_i_bottom),
		.external_padding_left(external_padding_left),
		.external_padding_top(external_padding_top),
		.inner_padding_left_right(inner_padding_left_right),
		.inner_padding_top_bottom(inner_padding_top_bottom),
		.ofmap_w(ofmap_w),
		.ofmap_h(ofmap_h),
		.ofmap_data_type(ofmap_data_type),
		.kernal_wgt_baseaddr(kernal_wgt_baseaddr),
		.kernal_shape(kernal_shape),
		.kernal_dilation_hzt_n(kernal_dilation_hzt_n),
		.kernal_w_dilated(kernal_w_dilated),
		.kernal_dilation_vtc_n(kernal_dilation_vtc_n),
		.kernal_h_dilated(kernal_h_dilated),
		.kernal_chn_n(kernal_chn_n),
		.cgrpn_foreach_kernal_set(cgrpn_foreach_kernal_set),
		.kernal_num_n(kernal_num_n),
		.kernal_set_n(kernal_set_n),
		.max_wgtblk_w(max_wgtblk_w),
		.fmbufbankn(fmbufbankn),
		.fmbufcoln(fmbufcoln),
		.fmbufrown(fmbufrown),
		.sfc_n_each_wgtblk(sfc_n_each_wgtblk),
		.kbufgrpn(kbufgrpn),
		.mid_res_item_n_foreach_row(mid_res_item_n_foreach_row),
		.mid_res_buf_row_n_bufferable(mid_res_buf_row_n_bufferable),
		.use_bn_unit(use_bn_unit),
		.use_act_unit(use_act_unit),
		.bn_fixed_point_quat_accrc(bn_fixed_point_quat_accrc),
		.bn_is_a_eq_1(bn_is_a_eq_1),
		.bn_is_b_eq_0(bn_is_b_eq_0),
		.leaky_relu_fixed_point_quat_accrc(leaky_relu_fixed_point_quat_accrc),
		.leaky_relu_param_alpha(leaky_relu_param_alpha),
		
		.kernal_access_blk_start(kernal_access_blk_start),
		.kernal_access_blk_idle(kernal_access_blk_idle),
		.kernal_access_blk_done(kernal_access_blk_done),
		
		.fmap_access_blk_start(fmap_access_blk_start),
		.fmap_access_blk_idle(fmap_access_blk_idle),
		.fmap_access_blk_done(fmap_access_blk_done),
		
		.fnl_res_trans_blk_start(fnl_res_trans_blk_start),
		.fnl_res_trans_blk_idle(fnl_res_trans_blk_idle),
		.fnl_res_trans_blk_done(fnl_res_trans_blk_done),
		
		.s0_mm2s_strm_axis_keep(s0_dma_strm_axis_keep),
		.s0_mm2s_strm_axis_valid(s0_dma_strm_axis_valid),
		.s0_mm2s_strm_axis_ready(s0_dma_strm_axis_ready),
		
		.s1_mm2s_strm_axis_keep(s1_dma_strm_axis_keep),
		.s1_mm2s_strm_axis_valid(s1_dma_strm_axis_valid),
		.s1_mm2s_strm_axis_ready(s1_dma_strm_axis_ready),
		
		.s_s2mm_strm_axis_keep(m_axis_fnl_res_keep),
		.s_s2mm_strm_axis_valid(m_axis_fnl_res_valid),
		.s_s2mm_strm_axis_ready(m_axis_fnl_res_ready),
		
		.mm2s_0_cmd_done(mm2s_0_cmd_done),
		.mm2s_1_cmd_done(mm2s_1_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done)
	);
	
	/** BN参数MEM控制器 **/
	// [AXI-SRAM控制器给出的存储器接口]
	wire axi_sram_ctrler_ram_clk;
    wire axi_sram_ctrler_ram_rst;
    wire axi_sram_ctrler_ram_en;
    wire[3:0] axi_sram_ctrler_ram_wen;
    wire[29:0] axi_sram_ctrler_ram_addr;
    wire[31:0] axi_sram_ctrler_ram_din;
    wire[31:0] axi_sram_ctrler_ram_dout;
	// [BN参数MEM接口]
	wire bn_mem_clk_a;
	wire bn_mem_en_a;
	wire[7:0] bn_mem_wen_a;
	wire[15:0] bn_mem_addr_a;
	wire[63:0] bn_mem_din_a; // {参数B(32bit), 参数A(32bit)}
	wire[63:0] bn_mem_dout_a; // {参数B(32bit), 参数A(32bit)}
	// [读数据重对齐]
	reg axi_sram_ctrler_word_sel;
	
	assign axi_sram_ctrler_ram_dout = 
		axi_sram_ctrler_word_sel ? 
			bn_mem_dout_a[63:32]:
			bn_mem_dout_a[31:0];
	
	assign bn_mem_clk_a = axi_sram_ctrler_ram_clk;
	assign bn_mem_en_a = axi_sram_ctrler_ram_en;
	assign bn_mem_wen_a = 
		axi_sram_ctrler_ram_addr[0] ? 
			{axi_sram_ctrler_ram_wen, 4'b0000}:
			{4'b0000, axi_sram_ctrler_ram_wen};
	assign bn_mem_addr_a = 
		axi_sram_ctrler_ram_addr[16:1];
	assign bn_mem_din_a = 
		axi_sram_ctrler_ram_addr[0] ? 
			{axi_sram_ctrler_ram_din, 32'dx}:
			{32'dx, axi_sram_ctrler_ram_din};
	
	always @(posedge axi_sram_ctrler_ram_clk)
	begin
		if(axi_sram_ctrler_ram_en)
			axi_sram_ctrler_word_sel <= # SIM_DELAY axi_sram_ctrler_ram_addr[0];
	end
	
	axi_bram_ctrler #(
		.bram_depth(MAX_KERNAL_N*2),
		.bram_read_la(1),
		.en_read_buf_fifo("false"),
		.simulation_delay(SIM_DELAY)
	)bn_param_sram_ctrler(
		.clk(aclk),
		.rst_n(aresetn),
		
		.s_axi_araddr(s_axi_araddr),
		.s_axi_arburst(s_axi_arburst),
		.s_axi_arcache(s_axi_arcache),
		.s_axi_arlen(s_axi_arlen),
		.s_axi_arlock(s_axi_arlock),
		.s_axi_arprot(s_axi_arprot),
		.s_axi_arsize(s_axi_arsize),
		.s_axi_arvalid(s_axi_arvalid),
		.s_axi_arready(s_axi_arready),
		.s_axi_awaddr(s_axi_awaddr),
		.s_axi_awburst(s_axi_awburst),
		.s_axi_awcache(s_axi_awcache),
		.s_axi_awlen(s_axi_awlen),
		.s_axi_awlock(s_axi_awlock),
		.s_axi_awprot(s_axi_awprot),
		.s_axi_awsize(s_axi_awsize),
		.s_axi_awvalid(s_axi_awvalid),
		.s_axi_awready(s_axi_awready),
		.s_axi_bresp(s_axi_bresp),
		.s_axi_bvalid(s_axi_bvalid),
		.s_axi_bready(s_axi_bready),
		.s_axi_rdata(s_axi_rdata),
		.s_axi_rlast(s_axi_rlast),
		.s_axi_rresp(s_axi_rresp),
		.s_axi_rvalid(s_axi_rvalid),
		.s_axi_rready(s_axi_rready),
		.s_axi_wdata(s_axi_wdata),
		.s_axi_wlast(s_axi_wlast),
		.s_axi_wstrb(s_axi_wstrb),
		.s_axi_wvalid(s_axi_wvalid),
		.s_axi_wready(s_axi_wready),
		
		.bram_clk(axi_sram_ctrler_ram_clk),
		.bram_rst(axi_sram_ctrler_ram_rst),
		.bram_en(axi_sram_ctrler_ram_en),
		.bram_wen(axi_sram_ctrler_ram_wen),
		.bram_addr(axi_sram_ctrler_ram_addr),
		.bram_din(axi_sram_ctrler_ram_din),
		.bram_dout(axi_sram_ctrler_ram_dout),
		
		.axi_bram_ctrler_err()
	);
	
	/** 控制子系统 **/
	// 后级计算单元控制
	wire rst_adapter; // 重置适配器(标志)
	wire on_incr_phy_row_traffic; // 增加1个物理特征图表面行流量(指示)
	wire[15:0] cgrp_n_of_fmap_region_that_kernal_set_sel; // 核组所选定特征图域的通道组数 - 1
	// 卷积核权重块读请求(AXIS主机)
	wire[103:0] m_kwgtblk_rd_req_axis_data;
	wire m_kwgtblk_rd_req_axis_valid;
	wire m_kwgtblk_rd_req_axis_ready;
	// 特征图表面行读请求(AXIS主机)
	wire[103:0] m_fm_rd_req_axis_data;
	wire m_fm_rd_req_axis_valid;
	wire m_fm_rd_req_axis_ready;
	// 特征图切块信息(AXIS主机)
	wire[7:0] m_fm_cake_info_axis_data; // {保留(4bit), 每个切片里的有效表面行数(4bit)}
	wire m_fm_cake_info_axis_valid;
	wire m_fm_cake_info_axis_ready;
	// 子表面行信息(AXIS主机)
	wire[15:0] m_sub_row_msg_axis_data; // {输出通道号(16bit)}
	wire m_sub_row_msg_axis_last; // 整个输出特征图的最后1个子表面行(标志)
	wire m_sub_row_msg_axis_valid;
	wire m_sub_row_msg_axis_ready;
	// 无符号乘法器
	// [乘法器#0(u16*u16)]
	wire[15:0] mul0_op_a; // 操作数A
	wire[15:0] mul0_op_b; // 操作数B
	wire mul0_ce; // 计算使能
	wire[31:0] mul0_res; // 计算结果
	// [乘法器#1(u16*u24)]
	wire[15:0] mul1_op_a; // 操作数A
	wire[23:0] mul1_op_b; // 操作数B
	wire mul1_ce; // 计算使能
	wire[39:0] mul1_res; // 计算结果
	// [乘法器#2(u16*u24)]
	wire[15:0] mul2_op_a; // 操作数A
	wire[23:0] mul2_op_b; // 操作数B
	wire mul2_ce; // 计算使能
	wire[39:0] mul2_res; // 计算结果
	
	conv_ctrl_sub_system #(
		.ATOMIC_C(ATOMIC_C),
		.ATOMIC_K(ATOMIC_K),
		.SIM_DELAY(SIM_DELAY)
	)conv_ctrl_sub_system_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.calfmt(calfmt),
		.conv_vertical_stride(conv_vertical_stride),
		.is_grp_conv_mode(is_grp_conv_mode),
		.group_n(group_n),
		.n_foreach_group(n_foreach_group),
		.data_size_foreach_group(data_size_foreach_group),
		.ifmap_baseaddr(ifmap_baseaddr),
		.ofmap_baseaddr(ofmap_baseaddr),
		.ifmap_w(ifmap_w),
		.ifmap_size(ifmap_size),
		.fmap_chn_n(fmap_chn_n),
		.fmap_ext_i_bottom(fmap_ext_i_bottom),
		.external_padding_top(external_padding_top),
		.inner_padding_top_bottom(inner_padding_top_bottom),
		.ofmap_w(ofmap_w),
		.ofmap_h(ofmap_h),
		.ofmap_data_type(ofmap_data_type),
		.kernal_wgt_baseaddr(kernal_wgt_baseaddr),
		.kernal_shape(kernal_shape),
		.kernal_dilation_vtc_n(kernal_dilation_vtc_n),
		.kernal_h_dilated(kernal_h_dilated),
		.kernal_chn_n(kernal_chn_n),
		.cgrpn_foreach_kernal_set(cgrpn_foreach_kernal_set),
		.kernal_num_n(kernal_num_n),
		.kernal_set_n(kernal_set_n),
		.max_wgtblk_w(max_wgtblk_w),
		
		.kernal_access_blk_start(kernal_access_blk_start),
		.kernal_access_blk_idle(kernal_access_blk_idle),
		.kernal_access_blk_done(kernal_access_blk_done),
		
		.fmap_access_blk_start(fmap_access_blk_start),
		.fmap_access_blk_idle(fmap_access_blk_idle),
		.fmap_access_blk_done(fmap_access_blk_done),
		
		.fnl_res_trans_blk_start(fnl_res_trans_blk_start),
		.fnl_res_trans_blk_idle(fnl_res_trans_blk_idle),
		.fnl_res_trans_blk_done(fnl_res_trans_blk_done),
		
		.rst_adapter(rst_adapter),
		.on_incr_phy_row_traffic(on_incr_phy_row_traffic),
		.cgrp_n_of_fmap_region_that_kernal_set_sel(cgrp_n_of_fmap_region_that_kernal_set_sel),
		
		.m_kwgtblk_rd_req_axis_data(m_kwgtblk_rd_req_axis_data),
		.m_kwgtblk_rd_req_axis_valid(m_kwgtblk_rd_req_axis_valid),
		.m_kwgtblk_rd_req_axis_ready(m_kwgtblk_rd_req_axis_ready),
		
		.m_fm_rd_req_axis_data(m_fm_rd_req_axis_data),
		.m_fm_rd_req_axis_valid(m_fm_rd_req_axis_valid),
		.m_fm_rd_req_axis_ready(m_fm_rd_req_axis_ready),
		
		.m_fm_cake_info_axis_data(m_fm_cake_info_axis_data),
		.m_fm_cake_info_axis_valid(m_fm_cake_info_axis_valid),
		.m_fm_cake_info_axis_ready(m_fm_cake_info_axis_ready),
		
		.m_sub_row_msg_axis_data(m_sub_row_msg_axis_data),
		.m_sub_row_msg_axis_last(m_sub_row_msg_axis_last),
		.m_sub_row_msg_axis_valid(m_sub_row_msg_axis_valid),
		.m_sub_row_msg_axis_ready(m_sub_row_msg_axis_ready),
		
		.m_dma_s2mm_cmd_axis_data(m_dma_s2mm_cmd_axis_data),
		.m_dma_s2mm_cmd_axis_user(m_dma_s2mm_cmd_axis_user),
		.m_dma_s2mm_cmd_axis_valid(m_dma_s2mm_cmd_axis_valid),
		.m_dma_s2mm_cmd_axis_ready(m_dma_s2mm_cmd_axis_ready),
		
		.mul0_op_a(mul0_op_a),
		.mul0_op_b(mul0_op_b),
		.mul0_ce(mul0_ce),
		.mul0_res(mul0_res),
		
		.mul1_op_a(mul1_op_a),
		.mul1_op_b(mul1_op_b),
		.mul1_ce(mul1_ce),
		.mul1_res(mul1_res),
		
		.mul2_op_a(mul2_op_a),
		.mul2_op_b(mul2_op_b),
		.mul2_ce(mul2_ce),
		.mul2_res(mul2_res)
	);
	
	/** 卷积数据枢纽 **/
	// 特征图表面行读请求(AXIS从机)
	wire[103:0] s_fm_rd_req_axis_data;
	wire s_fm_rd_req_axis_valid;
	wire s_fm_rd_req_axis_ready;
	// 卷积核权重块读请求(AXIS从机)
	wire[103:0] s_kwgtblk_rd_req_axis_data;
	wire s_kwgtblk_rd_req_axis_valid;
	wire s_kwgtblk_rd_req_axis_ready;
	// 特征图表面行数据输出(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_fm_fout_axis_data;
	wire m_fm_fout_axis_last; // 标志本次读请求的最后1个表面
	wire m_fm_fout_axis_valid;
	wire m_fm_fout_axis_ready;
	// 卷积核权重块数据输出(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_kout_wgtblk_axis_data;
	wire m_kout_wgtblk_axis_last; // 标志本次读请求的最后1个表面
	wire m_kout_wgtblk_axis_valid;
	wire m_kout_wgtblk_axis_ready;
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
	
	assign s_fm_rd_req_axis_data = m_fm_rd_req_axis_data;
	assign s_fm_rd_req_axis_valid = m_fm_rd_req_axis_valid;
	assign m_fm_rd_req_axis_ready = s_fm_rd_req_axis_ready;
	
	assign s_kwgtblk_rd_req_axis_data = m_kwgtblk_rd_req_axis_data;
	assign s_kwgtblk_rd_req_axis_valid = m_kwgtblk_rd_req_axis_valid;
	assign m_kwgtblk_rd_req_axis_ready = s_kwgtblk_rd_req_axis_ready;
	
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
		.SIM_DELAY(SIM_DELAY)
	)conv_data_hub_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.fmbufcoln(fmbufcoln),
		.fmbufrown(fmbufrown),
		.fmrow_random_rd_mode(1'b0),
		.grp_conv_buf_mode(is_grp_conv_mode),
		.kbufgrpsz(kernal_shape),
		.sfc_n_each_wgtblk(sfc_n_each_wgtblk),
		.kbufgrpn(kbufgrpn),
		.fmbufbankn(fmbufbankn),
		
		.s_fm_rd_req_axis_data(s_fm_rd_req_axis_data),
		.s_fm_rd_req_axis_valid(s_fm_rd_req_axis_valid),
		.s_fm_rd_req_axis_ready(s_fm_rd_req_axis_ready),
		
		.s_fm_random_rd_axis_data(16'dx),
		.s_fm_random_rd_axis_last(1'bx),
		.s_fm_random_rd_axis_valid(1'b0),
		.s_fm_random_rd_axis_ready(),
		
		.s_kwgtblk_rd_req_axis_data(s_kwgtblk_rd_req_axis_data),
		.s_kwgtblk_rd_req_axis_valid(s_kwgtblk_rd_req_axis_valid),
		.s_kwgtblk_rd_req_axis_ready(s_kwgtblk_rd_req_axis_ready),
		
		.m_fm_fout_axis_data(m_fm_fout_axis_data),
		.m_fm_fout_axis_last(m_fm_fout_axis_last),
		.m_fm_fout_axis_valid(m_fm_fout_axis_valid),
		.m_fm_fout_axis_ready(m_fm_fout_axis_ready),
		
		.m_kout_wgtblk_axis_data(m_kout_wgtblk_axis_data),
		.m_kout_wgtblk_axis_last(m_kout_wgtblk_axis_last),
		.m_kout_wgtblk_axis_valid(m_kout_wgtblk_axis_valid),
		.m_kout_wgtblk_axis_ready(m_kout_wgtblk_axis_ready),
		
		.m0_dma_cmd_axis_data(m0_dma_cmd_axis_data),
		.m0_dma_cmd_axis_user(m0_dma_cmd_axis_user),
		.m0_dma_cmd_axis_last(m0_dma_cmd_axis_last),
		.m0_dma_cmd_axis_valid(m0_dma_cmd_axis_valid),
		.m0_dma_cmd_axis_ready(m0_dma_cmd_axis_ready),
		
		.s0_dma_strm_axis_data(s0_dma_strm_axis_data),
		.s0_dma_strm_axis_keep(s0_dma_strm_axis_keep),
		.s0_dma_strm_axis_last(s0_dma_strm_axis_last),
		.s0_dma_strm_axis_valid(s0_dma_strm_axis_valid),
		.s0_dma_strm_axis_ready(s0_dma_strm_axis_ready),
		
		.m1_dma_cmd_axis_data(m1_dma_cmd_axis_data),
		.m1_dma_cmd_axis_user(m1_dma_cmd_axis_user),
		.m1_dma_cmd_axis_last(m1_dma_cmd_axis_last),
		.m1_dma_cmd_axis_valid(m1_dma_cmd_axis_valid),
		.m1_dma_cmd_axis_ready(m1_dma_cmd_axis_ready),
		
		.s1_dma_strm_axis_data(s1_dma_strm_axis_data),
		.s1_dma_strm_axis_keep(s1_dma_strm_axis_keep),
		.s1_dma_strm_axis_last(s1_dma_strm_axis_last),
		.s1_dma_strm_axis_valid(s1_dma_strm_axis_valid),
		.s1_dma_strm_axis_ready(s1_dma_strm_axis_ready),
		
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
		.phy_conv_buf_mem_dout_a(phy_conv_buf_mem_dout_a)
	);
	
	/** 计算子系统 **/
	// 特征图切块信息(AXIS从机)
	wire[7:0] s_fm_cake_info_axis_data; // {保留(4bit), 每个切片里的有效表面行数(4bit)}
	wire s_fm_cake_info_axis_valid;
	wire s_fm_cake_info_axis_ready;
	// 子表面行信息(AXIS从机)
	wire[15:0] s_sub_row_msg_axis_data; // {输出通道号(16bit)}
	wire s_sub_row_msg_axis_last; // 整个输出特征图的最后1个子表面行(标志)
	wire s_sub_row_msg_axis_valid;
	wire s_sub_row_msg_axis_ready;
	// 物理特征图表面行数据(AXIS从机)
	wire[ATOMIC_C*2*8-1:0] s_fmap_row_axis_data;
	wire s_fmap_row_axis_last; // 标志物理特征图行的最后1个表面
	wire s_fmap_row_axis_valid;
	wire s_fmap_row_axis_ready;
	// 卷积核权重块数据(AXIS从机)
	wire[ATOMIC_C*2*8-1:0] s_kwgtblk_axis_data;
	wire s_kwgtblk_axis_last; // 标志卷积核权重块的最后1个表面
	wire s_kwgtblk_axis_valid;
	wire s_kwgtblk_axis_ready;
	// (卷积乘加)有符号乘法器阵列
	wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_array_op_a; // 操作数A
	wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_array_op_b; // 操作数B
	wire[ATOMIC_K-1:0] mul_array_ce; // 计算使能
	wire[ATOMIC_K*ATOMIC_C*32-1:0] mul_array_res; // 计算结果
	// BN乘法器组
	wire[BN_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_op_a; // 操作数A
	wire[BN_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_op_b; // 操作数B
	wire[BN_MUL_CE_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_ce; // 计算使能
	wire[BN_MUL_RES_WIDTH*BN_ACT_PRL_N-1:0] bn_mul_res; // 计算结果
	// 泄露Relu乘法器组
	wire[LEAKY_RELU_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_op_a; // 操作数A
	wire[LEAKY_RELU_MUL_OP_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_op_b; // 操作数B
	wire[LEAKY_RELU_MUL_CE_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_ce; // 计算使能
	wire[LEAKY_RELU_MUL_RES_WIDTH*BN_ACT_PRL_N-1:0] leaky_relu_mul_res; // 计算结果
	// 中间结果缓存MEM主接口
	wire mid_res_mem_clk_a;
	wire[RBUF_BANK_N-1:0] mid_res_mem_wen_a;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_a;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_din_a;
	wire mid_res_mem_clk_b;
	wire[RBUF_BANK_N-1:0] mid_res_mem_ren_b;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_b;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_dout_b;
	// BN参数MEM主接口
	wire bn_mem_clk_b;
	wire bn_mem_ren_b;
	wire[15:0] bn_mem_addr_b;
	wire[63:0] bn_mem_dout_b; // {参数B(32bit), 参数A(32bit)}
	// 处理结果fifo(MEM主接口)
	wire proc_res_fifo_mem_clk;
	wire proc_res_fifo_mem_wen_a;
	wire[8:0] proc_res_fifo_mem_addr_a;
	wire[BN_ACT_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_din_a;
	wire proc_res_fifo_mem_ren_b;
	wire[8:0] proc_res_fifo_mem_addr_b;
	wire[BN_ACT_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_dout_b;
	
	assign s_fm_cake_info_axis_data = m_fm_cake_info_axis_data;
	assign s_fm_cake_info_axis_valid = m_fm_cake_info_axis_valid;
	assign m_fm_cake_info_axis_ready = s_fm_cake_info_axis_ready;
	
	assign s_sub_row_msg_axis_data = m_sub_row_msg_axis_data;
	assign s_sub_row_msg_axis_last = m_sub_row_msg_axis_last;
	assign s_sub_row_msg_axis_valid = m_sub_row_msg_axis_valid;
	assign m_sub_row_msg_axis_ready = s_sub_row_msg_axis_ready;
	
	assign s_fmap_row_axis_data = m_fm_fout_axis_data;
	assign s_fmap_row_axis_last = m_fm_fout_axis_last;
	assign s_fmap_row_axis_valid = m_fm_fout_axis_valid;
	assign m_fm_fout_axis_ready = s_fmap_row_axis_ready;
	
	assign s_kwgtblk_axis_data = m_kout_wgtblk_axis_data;
	assign s_kwgtblk_axis_last = m_kout_wgtblk_axis_last;
	assign s_kwgtblk_axis_valid = m_kout_wgtblk_axis_valid;
	assign m_kout_wgtblk_axis_ready = s_kwgtblk_axis_ready;
	
	conv_cal_sub_system #(
		.ATOMIC_K(ATOMIC_K),
		.ATOMIC_C(ATOMIC_C),
		.BN_ACT_PRL_N(BN_ACT_PRL_N),
		.STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.FP32_KEEP(FP32_KEEP ? 1'b1:1'b0),
		.MAX_CAL_ROUND(MAX_CAL_ROUND),
		.EN_SMALL_FP16("true"),
		.EN_SMALL_FP32("true"),
		.BN_ACT_INT16_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.BN_ACT_INT32_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.BN_ACT_FP32_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.SIM_DELAY(SIM_DELAY)
	)conv_cal_sub_system_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.rst_adapter(rst_adapter),
		.on_incr_phy_row_traffic(on_incr_phy_row_traffic),
		.row_n_submitted_to_mac_array(),
		.en_mac_array(en_mac_array),
		.ftm_sfc_cal_n(),
		.en_packer(en_packer),
		.en_bn_act_proc(en_bn_act_proc),
		
		.conv_horizontal_stride(conv_horizontal_stride),
		.calfmt(calfmt),
		.cal_round(cal_round),
		.external_padding_left(external_padding_left),
		.inner_padding_left_right(inner_padding_left_right),
		.ifmap_w(ifmap_w),
		.ofmap_w(ofmap_w),
		.cgrp_n_of_fmap_region_that_kernal_set_sel(cgrp_n_of_fmap_region_that_kernal_set_sel),
		.kernal_shape(kernal_shape),
		.kernal_dilation_hzt_n(kernal_dilation_hzt_n),
		.kernal_w_dilated(kernal_w_dilated),
		.mid_res_item_n_foreach_row(mid_res_item_n_foreach_row),
		.mid_res_buf_row_n_bufferable(mid_res_buf_row_n_bufferable),
		.use_bn_unit(use_bn_unit),
		.use_act_unit(use_act_unit),
		.bn_fixed_point_quat_accrc(bn_fixed_point_quat_accrc),
		.bn_is_a_eq_1(bn_is_a_eq_1),
		.bn_is_b_eq_0(bn_is_b_eq_0),
		.leaky_relu_fixed_point_quat_accrc(leaky_relu_fixed_point_quat_accrc),
		.leaky_relu_param_alpha(leaky_relu_param_alpha),
		
		.s_fm_cake_info_axis_data(s_fm_cake_info_axis_data),
		.s_fm_cake_info_axis_valid(s_fm_cake_info_axis_valid),
		.s_fm_cake_info_axis_ready(s_fm_cake_info_axis_ready),
		
		.s_sub_row_msg_axis_data(s_sub_row_msg_axis_data),
		.s_sub_row_msg_axis_last(s_sub_row_msg_axis_last),
		.s_sub_row_msg_axis_valid(s_sub_row_msg_axis_valid),
		.s_sub_row_msg_axis_ready(s_sub_row_msg_axis_ready),
		
		.s_fmap_row_axis_data(s_fmap_row_axis_data),
		.s_fmap_row_axis_last(s_fmap_row_axis_last),
		.s_fmap_row_axis_valid(s_fmap_row_axis_valid),
		.s_fmap_row_axis_ready(s_fmap_row_axis_ready),
		
		.s_kwgtblk_axis_data(s_kwgtblk_axis_data),
		.s_kwgtblk_axis_last(s_kwgtblk_axis_last),
		.s_kwgtblk_axis_valid(s_kwgtblk_axis_valid),
		.s_kwgtblk_axis_ready(s_kwgtblk_axis_ready),
		
		.m_axis_fnl_res_data(m_axis_fnl_res_data),
		.m_axis_fnl_res_keep(m_axis_fnl_res_keep),
		.m_axis_fnl_res_user(m_axis_fnl_res_user),
		.m_axis_fnl_res_last(m_axis_fnl_res_last),
		.m_axis_fnl_res_valid(m_axis_fnl_res_valid),
		.m_axis_fnl_res_ready(m_axis_fnl_res_ready),
		
		.mul0_op_a(mul_array_op_a),
		.mul0_op_b(mul_array_op_b),
		.mul0_ce(mul_array_ce),
		.mul0_res(mul_array_res),
		
		.mul1_op_a(bn_mul_op_a),
		.mul1_op_b(bn_mul_op_b),
		.mul1_ce(bn_mul_ce),
		.mul1_res(bn_mul_res),
		
		.mul2_op_a(leaky_relu_mul_op_a),
		.mul2_op_b(leaky_relu_mul_op_b),
		.mul2_ce(leaky_relu_mul_ce),
		.mul2_res(leaky_relu_mul_res),
		
		.mid_res_mem_clk_a(mid_res_mem_clk_a),
		.mid_res_mem_wen_a(mid_res_mem_wen_a),
		.mid_res_mem_addr_a(mid_res_mem_addr_a),
		.mid_res_mem_din_a(mid_res_mem_din_a),
		.mid_res_mem_clk_b(mid_res_mem_clk_b),
		.mid_res_mem_ren_b(mid_res_mem_ren_b),
		.mid_res_mem_addr_b(mid_res_mem_addr_b),
		.mid_res_mem_dout_b(mid_res_mem_dout_b),
		
		.bn_mem_clk_b(bn_mem_clk_b),
		.bn_mem_ren_b(bn_mem_ren_b),
		.bn_mem_addr_b(bn_mem_addr_b),
		.bn_mem_dout_b(bn_mem_dout_b),
		
		.proc_res_fifo_mem_clk(proc_res_fifo_mem_clk),
		.proc_res_fifo_mem_wen_a(proc_res_fifo_mem_wen_a),
		.proc_res_fifo_mem_addr_a(proc_res_fifo_mem_addr_a),
		.proc_res_fifo_mem_din_a(proc_res_fifo_mem_din_a),
		.proc_res_fifo_mem_ren_b(proc_res_fifo_mem_ren_b),
		.proc_res_fifo_mem_addr_b(proc_res_fifo_mem_addr_b),
		.proc_res_fifo_mem_dout_b(proc_res_fifo_mem_dout_b)
	);
	
	/** 乘法器 **/
	unsigned_mul #(
		.op_a_width(16),
		.op_b_width(16),
		.output_width(32),
		.simulation_delay(SIM_DELAY)
	)mul_u16_u16_u0(
		.clk(aclk),
		
		.ce_s0_mul(mul0_ce),
		
		.op_a(mul0_op_a),
		.op_b(mul0_op_b),
		
		.res(mul0_res)
	);
	
	unsigned_mul #(
		.op_a_width(16),
		.op_b_width(24),
		.output_width(40),
		.simulation_delay(SIM_DELAY)
	)mul_u16_u24_u0(
		.clk(aclk),
		
		.ce_s0_mul(mul1_ce),
		
		.op_a(mul1_op_a),
		.op_b(mul1_op_b),
		
		.res(mul1_res)
	);
	
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
	
	genvar conv_mac_mul_i;
	generate
		for(conv_mac_mul_i = 0;conv_mac_mul_i < ATOMIC_K*ATOMIC_C;conv_mac_mul_i = conv_mac_mul_i + 1)
		begin:mul_blk
			signed_mul #(
				.op_a_width(16),
				.op_b_width(16),
				.output_width(32),
				.en_in_reg("false"),
				.en_out_reg("false"),
				.simulation_delay(SIM_DELAY)
			)mul_s16_s16_u(
				.clk(aclk),
				
				.ce_in_reg(1'b0),
				.ce_mul(mul_array_ce[conv_mac_mul_i/ATOMIC_C]),
				.ce_out_reg(1'b0),
				
				.op_a(mul_array_op_a[16*conv_mac_mul_i+15:16*conv_mac_mul_i]),
				.op_b(mul_array_op_b[16*conv_mac_mul_i+15:16*conv_mac_mul_i]),
				
				.res(mul_array_res[32*conv_mac_mul_i+31:32*conv_mac_mul_i])
			);
		end
	endgenerate
	
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
				.clk(aclk),
				
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
					.clk(aclk),
					
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
					.clk(aclk),
					
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
				.INIT_FILE("default"),
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
		.INIT_FILE("random"),
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
		.INIT_FILE("random"),
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
	endgenerate
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(BN_ACT_PROC_RES_FIFO_WIDTH),
		.mem_depth(512),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)bn_act_proc_res_fifo_ram_u(
		.clk(proc_res_fifo_mem_clk),
		
		.wen_a(proc_res_fifo_mem_wen_a),
		.addr_a(proc_res_fifo_mem_addr_a),
		.din_a(proc_res_fifo_mem_din_a),
		
		.ren_b(proc_res_fifo_mem_ren_b),
		.addr_b(proc_res_fifo_mem_addr_b),
		.dout_b(proc_res_fifo_mem_dout_b)
	);
	
	bram_true_dual_port #(
		.mem_width(64),
		.mem_depth(MAX_KERNAL_N),
		.INIT_FILE("no_init"),
		.read_write_mode("read_first"),
		.use_output_register("false"),
		.en_byte_write("true"),
		.simulation_delay(SIM_DELAY)
	)bn_param_ram_u(
		.clk(bn_mem_clk_a),
		
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
	
endmodule
