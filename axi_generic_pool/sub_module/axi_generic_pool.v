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
本模块: AXI-通用池化处理单元

描述:
AXI-通用池化处理单元(顶层模块)

包括寄存器配置接口、控制子系统(池化表面行缓存访问控制、最终结果传输请求生成单元)、
计算子系统(池化表面行适配器、池化中间结果更新与缓存、后乘加处理)、数据枢纽、最终结果数据收集器

支持最大池化、平均池化、(最近邻)上采样、填充(由无复制的上采样模式来支持)、逐元素常量运算(由后乘加处理来支持)

注意：
需要外接1个DMA(MM2S)通道和1个DMA(S2MM)通道

可将SRAM和乘法器的接口引出, 在SOC层面再连接, 以实现SRAM和乘法器的共享

后乘加并行数(POST_MAC_PRL_N)必须<=通道并行数(ATOMIC_C)

协议:
AXI-Lite SLAVE
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/12/23
********************************************************************/


module axi_generic_pool #(
	parameter integer ACCELERATOR_ID = 0, // 加速器ID(0~3)
	parameter integer MAX_POOL_SUPPORTED = 1, // 是否支持最大池化
	parameter integer AVG_POOL_SUPPORTED = 0, // 是否支持平均池化
	parameter integer UP_SAMPLE_SUPPORTED = 1, // 是否支持上采样
	parameter integer POST_MAC_SUPPORTED = 0, // 是否支持后乘加处理
	parameter integer INT8_SUPPORTED = 0, // 是否支持INT8运算数据格式
	parameter integer INT16_SUPPORTED = 0, // 是否支持INT16运算数据格式
	parameter integer FP16_SUPPORTED = 1, // 是否支持FP16运算数据格式
	parameter integer EXT_PADDING_SUPPORTED = 1, // 是否支持外填充
	parameter integer NON_ZERO_CONST_PADDING_SUPPORTED = 0, // 是否支持非0常量填充模式
	parameter integer EN_PERF_MON = 1, // 是否支持性能监测
	parameter integer KEEP_FP32_OUT = 0, // 是否保持FP32输出
	parameter integer ATOMIC_C = 8, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer POST_MAC_PRL_N = 1, // 后乘加并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MM2S_STREAM_DATA_WIDTH = 64, // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64, // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16, // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 512, // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
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
	
	// S2MM方向DMA命令(AXIS主机)
	output wire[55:0] m_dma_s2mm_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_dma_s2mm_cmd_axis_user, // 固定(1'b1)/递增(1'b0)传输(1bit)
	output wire m_dma_s2mm_cmd_axis_valid,
	input wire m_dma_s2mm_cmd_axis_ready,
	// 最终结果数据流(AXIS主机)
	output wire[S2MM_STREAM_DATA_WIDTH-1:0] m_axis_fnl_res_data,
	output wire[S2MM_STREAM_DATA_WIDTH/8-1:0] m_axis_fnl_res_keep,
	output wire m_axis_fnl_res_last, // 本行最后1个最终结果(标志)
	output wire m_axis_fnl_res_valid,
	input wire m_axis_fnl_res_ready,
	
	// DMA(MM2S方向)命令流(AXIS主机)
	output wire[55:0] m_dma_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_dma_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m_dma_cmd_axis_last, // 帧尾标志
	output wire m_dma_cmd_axis_valid,
	input wire m_dma_cmd_axis_ready,
	// DMA(MM2S方向)数据流(AXIS从机)
	input wire[MM2S_STREAM_DATA_WIDTH-1:0] s_dma_strm_axis_data,
	input wire[MM2S_STREAM_DATA_WIDTH/8-1:0] s_dma_strm_axis_keep,
	input wire s_dma_strm_axis_last,
	input wire s_dma_strm_axis_valid,
	output wire s_dma_strm_axis_ready,
	
	// DMA命令完成指示
	input wire mm2s_cmd_done, // MM2S通道命令完成(指示)
	input wire s2mm_cmd_done // S2MM通道命令完成(指示)
);
	
	/** 函数 **/
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
	// 后乘加处理的运算数据格式的编码
	localparam POST_MAC_CAL_FMT_INT16 = 2'b00;
	localparam POST_MAC_CAL_FMT_INT32 = 2'b01;
	localparam POST_MAC_CAL_FMT_FP32 = 2'b10;
	localparam POST_MAC_CAL_FMT_NONE = 2'b11;
	// 池化的运算数据格式的编码
	localparam CAL_FMT_INT8 = 2'b00;
	localparam CAL_FMT_INT16 = 2'b01;
	localparam CAL_FMT_FP16 = 2'b10;
	
	/** 内部参数 **/
	// 特征图缓存的缓存行号的位宽
	localparam integer LG_FMBUF_BUFFER_RID_WIDTH = clogb2(MAX_FMBUF_ROWN);
	// 后乘加处理的乘法器位宽
	localparam integer POST_MAC_MUL_OP_WIDTH = INT8_SUPPORTED ? 4*18:(INT16_SUPPORTED ? 32:25);
	localparam integer POST_MAC_MUL_CE_WIDTH = INT8_SUPPORTED ? 4:3;
	localparam integer POST_MAC_MUL_RES_WIDTH = INT8_SUPPORTED ? 4*36:(INT16_SUPPORTED ? 64:50);
	// 后乘加处理结果fifo的位宽
	localparam integer POST_MAC_PROC_RES_FIFO_WIDTH = POST_MAC_PRL_N*32+POST_MAC_PRL_N+1+5;
	
	/** 寄存器配置接口 **/
	// 控制信号
	wire en_adapter; // 使能适配器
	wire en_post_mac; // 使能后乘加处理
	// 运行时参数
	// [计算参数]
	wire[1:0] pool_mode; // 池化模式
	wire[1:0] calfmt; // 运算数据格式
	wire[2:0] pool_horizontal_stride; // 池化水平步长 - 1
	wire[2:0] pool_vertical_stride; // 池化垂直步长 - 1
	wire[7:0] pool_window_w; // 池化窗口宽度 - 1
	wire[7:0] pool_window_h; // 池化窗口高度 - 1
	// [后乘加处理参数]
	wire[4:0] post_mac_fixed_point_quat_accrc; // 定点数量化精度
	wire post_mac_is_a_eq_1; // 参数A的实际值为1(标志)
	wire post_mac_is_b_eq_0; // 参数B的实际值为0(标志)
	wire[31:0] post_mac_param_a; // 参数A
	wire[31:0] post_mac_param_b; // 参数B
	// [上采样参数]
	wire[7:0] upsample_horizontal_n; // 上采样水平复制量 - 1
	wire[7:0] upsample_vertical_n; // 上采样垂直复制量 - 1
	wire non_zero_const_padding_mode; // 是否处于非0常量填充模式
	wire[15:0] const_to_fill; // 待填充的常量
	// [特征图参数]
	wire[31:0] ifmap_baseaddr; // 输入特征图基地址
	wire[31:0] ofmap_baseaddr; // 输出特征图基地址
	wire is_16bit_data; // 是否16位(输入)特征图数据
	wire[15:0] ifmap_w; // 输入特征图宽度 - 1
	wire[15:0] ifmap_h; // 输入特征图高度 - 1
	wire[23:0] ifmap_size; // 输入特征图大小 - 1
	wire[15:0] ext_ifmap_w; // 扩展输入特征图宽度 - 1
	wire[15:0] ext_ifmap_h; // 扩展输入特征图高度 - 1
	wire[15:0] fmap_chn_n; // 通道数 - 1
	wire[2:0] external_padding_left; // 左部外填充数
	wire[2:0] external_padding_top; // 上部外填充数
	wire[15:0] ofmap_w; // 输出特征图宽度 - 1
	wire[15:0] ofmap_h; // 输出特征图高度 - 1
	wire[1:0] ofmap_data_type; // 输出特征图数据大小类型
	// [特征图缓存参数]
	wire[3:0] fmbufcoln; // 每个表面行的表面个数类型
	wire[9:0] fmbufrown; // 可缓存的表面行数 - 1
	// [中间结果缓存参数]
	wire[3:0] mid_res_buf_row_n_bufferable; // 可缓存行数 - 1
	// 块级控制
	// [池化表面行缓存访问控制]
	wire sfc_row_access_blk_start;
	wire sfc_row_access_blk_idle;
	wire sfc_row_access_blk_done;
	// [最终结果传输请求生成单元]
	wire fnl_res_tr_req_gen_blk_start;
	wire fnl_res_tr_req_gen_blk_idle;
	wire fnl_res_tr_req_gen_blk_done;
	
	reg_if_for_generic_pool #(
		.ACCELERATOR_ID(ACCELERATOR_ID),
		.MAX_POOL_SUPPORTED(MAX_POOL_SUPPORTED ? 1'b1:1'b0),
		.AVG_POOL_SUPPORTED(AVG_POOL_SUPPORTED ? 1'b1:1'b0),
		.UP_SAMPLE_SUPPORTED(UP_SAMPLE_SUPPORTED ? 1'b1:1'b0),
		.POST_MAC_SUPPORTED(POST_MAC_SUPPORTED ? 1'b1:1'b0),
		.INT8_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.INT16_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.FP16_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.EXT_PADDING_SUPPORTED(EXT_PADDING_SUPPORTED ? 1'b1:1'b0),
		.NON_ZERO_CONST_PADDING_SUPPORTED(
			(UP_SAMPLE_SUPPORTED && EXT_PADDING_SUPPORTED && NON_ZERO_CONST_PADDING_SUPPORTED) ? 
				1'b1:
				1'b0
		),
		.EN_PERF_MON(EN_PERF_MON ? 1'b1:1'b0),
		.ATOMIC_C(ATOMIC_C),
		.POST_MAC_PRL_N(POST_MAC_PRL_N),
		.MM2S_STREAM_DATA_WIDTH(MM2S_STREAM_DATA_WIDTH),
		.S2MM_STREAM_DATA_WIDTH(S2MM_STREAM_DATA_WIDTH),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.SIM_DELAY(SIM_DELAY)
	)reg_if_for_generic_pool_u(
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
		
		.en_adapter(en_adapter),
		.en_post_mac(en_post_mac),
		
		.mm2s_cmd_done(mm2s_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done),
		
		.sfc_row_access_blk_start(sfc_row_access_blk_start),
		.sfc_row_access_blk_idle(sfc_row_access_blk_idle),
		.sfc_row_access_blk_done(sfc_row_access_blk_done),
		.fnl_res_tr_req_gen_blk_start(fnl_res_tr_req_gen_blk_start),
		.fnl_res_tr_req_gen_blk_idle(fnl_res_tr_req_gen_blk_idle),
		.fnl_res_tr_req_gen_blk_done(fnl_res_tr_req_gen_blk_done),
		
		.pool_mode(pool_mode),
		.calfmt(calfmt),
		.pool_horizontal_stride(pool_horizontal_stride),
		.pool_vertical_stride(pool_vertical_stride),
		.pool_window_w(pool_window_w),
		.pool_window_h(pool_window_h),
		.post_mac_fixed_point_quat_accrc(post_mac_fixed_point_quat_accrc),
		.post_mac_is_a_eq_1(post_mac_is_a_eq_1),
		.post_mac_is_b_eq_0(post_mac_is_b_eq_0),
		.post_mac_param_a(post_mac_param_a),
		.post_mac_param_b(post_mac_param_b),
		.upsample_horizontal_n(upsample_horizontal_n),
		.upsample_vertical_n(upsample_vertical_n),
		.non_zero_const_padding_mode(non_zero_const_padding_mode),
		.const_to_fill(const_to_fill),
		.ifmap_baseaddr(ifmap_baseaddr),
		.ofmap_baseaddr(ofmap_baseaddr),
		.is_16bit_data(is_16bit_data),
		.ifmap_w(ifmap_w),
		.ifmap_h(ifmap_h),
		.ifmap_size(ifmap_size),
		.ext_ifmap_w(ext_ifmap_w),
		.ext_ifmap_h(ext_ifmap_h),
		.fmap_chn_n(fmap_chn_n),
		.external_padding_left(external_padding_left),
		.external_padding_top(external_padding_top),
		.ofmap_w(ofmap_w),
		.ofmap_h(ofmap_h),
		.ofmap_data_type(ofmap_data_type),
		.fmbufcoln(fmbufcoln),
		.fmbufrown(fmbufrown),
		.mid_res_buf_row_n_bufferable(mid_res_buf_row_n_bufferable)
	);
	
	/** 补充运行时参数 **/
	wire[15:0] ofmap_w_for_adapter; // 对适配器来说的"输出特征图宽度 - 1"
	wire[15:0] ofmap_h_for_sfc_row_access; // 对池化表面行缓存访问控制单元来说的"输出特征图高度 - 1"
	wire[3:0] bank_n_foreach_ofmap_row; // 每个输出特征图行所占用的中间结果缓存MEM个数
	wire[1:0] post_mac_calfmt; // 后乘加处理的数据格式
	
	// 提示: 上采样水平复制量(upsample_horizontal_n)恒为1时, 始终为"输出特征图宽度 - 1"(ofmap_w)即可
	assign ofmap_w_for_adapter = 
		(pool_mode == POOL_MODE_UPSP) ? 
			ext_ifmap_w:
			ofmap_w;
	// 提示: 上采样垂直复制量(upsample_vertical_n)恒为1时, 始终为"输出特征图高度 - 1"(ofmap_h)即可
	assign ofmap_h_for_sfc_row_access = 
		(pool_mode == POOL_MODE_UPSP) ? 
			ext_ifmap_h:
			ofmap_h;
	assign bank_n_foreach_ofmap_row = 
		(ofmap_w[15:clogb2(RBUF_DEPTH)] | 4'd0) + 1'b1;
	assign post_mac_calfmt = 
		(calfmt == CAL_FMT_INT8)  ? POST_MAC_CAL_FMT_INT16:
		(calfmt == CAL_FMT_INT16) ? POST_MAC_CAL_FMT_INT32:
		(calfmt == CAL_FMT_FP16)  ? POST_MAC_CAL_FMT_FP32:
		                            POST_MAC_CAL_FMT_NONE;
	
	/** 池化表面行缓存访问控制 **/
	// 池化表面行信息(AXIS主机)
	wire[15:0] m_pool_sfc_row_info_axis_data;
	wire m_pool_sfc_row_info_axis_valid;
	wire m_pool_sfc_row_info_axis_ready;
	// 特征图表面行读请求(AXIS主机)
	wire[103:0] m_fm_rd_req_axis_data;
	wire m_fm_rd_req_axis_valid;
	wire m_fm_rd_req_axis_ready;
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] shared_mul0_op_a; // 操作数A
	wire[15:0] shared_mul0_op_b; // 操作数B
	wire[3:0] shared_mul0_tid; // 操作ID
	wire shared_mul0_req;
	wire shared_mul0_grant;
	// [计算结果]
	wire[31:0] shared_mul0_res;
	wire[3:0] shared_mul0_oid;
	wire shared_mul0_ovld;
	// (共享)有符号乘法器#1
	// [计算输入]
	wire[17:0] shared_mul1_op_a; // 操作数A
	wire[24:0] shared_mul1_op_b; // 操作数B
	wire[3:0] shared_mul1_tid; // 操作ID
	wire shared_mul1_req;
	wire shared_mul1_grant;
	// [计算结果]
	wire[42:0] shared_mul1_res;
	wire[3:0] shared_mul1_oid;
	wire shared_mul1_ovld;
	// 实际乘法器#0
	reg[17:0] mul0_op_a;
	reg[24:0] mul0_op_b;
	reg[3:0] mul0_tid;
	reg mul0_ce;
	wire[42:0] mul0_res;
	reg[3:0] mul0_oid;
	reg mul0_ovld;
	
	assign shared_mul0_grant = shared_mul0_req;
	assign shared_mul0_res = mul0_res[31:0];
	assign shared_mul0_oid = mul0_oid;
	assign shared_mul0_ovld = mul0_ovld;
	
	assign shared_mul1_grant = (~shared_mul0_req) & shared_mul1_req;
	assign shared_mul1_res = mul0_res;
	assign shared_mul1_oid = mul0_oid;
	assign shared_mul1_ovld = mul0_ovld;
	
	always @(posedge aclk)
	begin
		if(shared_mul0_req | shared_mul1_req)
		begin
			mul0_op_a <= # SIM_DELAY 
				shared_mul0_req ? 
					{2'b00, shared_mul0_op_a}:
					shared_mul1_op_a;
			mul0_op_b <= # SIM_DELAY 
				shared_mul0_req ? 
					{9'd0, shared_mul0_op_b}:
					shared_mul1_op_b;
			mul0_tid <= # SIM_DELAY 
				shared_mul0_req ? 
					shared_mul0_tid:
					shared_mul1_tid;
		end
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{mul0_ovld, mul0_ce} <= 2'b00;
		else
			{mul0_ovld, mul0_ce} <= # SIM_DELAY 
				{
					mul0_ce,
					shared_mul0_req | shared_mul1_req
				};
	end
	
	always @(posedge aclk)
	begin
		if(mul0_ce)
			mul0_oid <= # SIM_DELAY mul0_tid;
	end
	
	pool_sfc_row_buffer_access_ctrl #(
		.ATOMIC_C(ATOMIC_C),
		.SIM_DELAY(SIM_DELAY)
	)pool_sfc_row_buffer_access_ctrl_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.pool_mode(pool_mode),
		.pool_vertical_stride(pool_vertical_stride),
		.pool_window_h(pool_window_h),
		.fmap_baseaddr(ifmap_baseaddr),
		.is_16bit_data(is_16bit_data),
		.ifmap_w(ifmap_w),
		.ifmap_h(ifmap_h),
		.ifmap_size(ifmap_size),
		.fmap_chn_n(fmap_chn_n),
		.external_padding_top(external_padding_top),
		.ofmap_h(ofmap_h_for_sfc_row_access),
		
		.blk_start(sfc_row_access_blk_start),
		.blk_idle(sfc_row_access_blk_idle),
		.blk_done(sfc_row_access_blk_done),
		
		.m_pool_sfc_row_info_axis_data(m_pool_sfc_row_info_axis_data),
		.m_pool_sfc_row_info_axis_valid(m_pool_sfc_row_info_axis_valid),
		.m_pool_sfc_row_info_axis_ready(m_pool_sfc_row_info_axis_ready),
		
		.m_fm_rd_req_axis_data(m_fm_rd_req_axis_data),
		.m_fm_rd_req_axis_valid(m_fm_rd_req_axis_valid),
		.m_fm_rd_req_axis_ready(m_fm_rd_req_axis_ready),
		
		.mul0_op_a(shared_mul0_op_a),
		.mul0_op_b(shared_mul0_op_b),
		.mul0_tid(shared_mul0_tid),
		.mul0_req(shared_mul0_req),
		.mul0_grant(shared_mul0_grant),
		.mul0_res(shared_mul0_res),
		.mul0_oid(shared_mul0_oid),
		.mul0_ovld(shared_mul0_ovld),
		
		.mul1_op_a(shared_mul1_op_a),
		.mul1_op_b(shared_mul1_op_b),
		.mul1_tid(shared_mul1_tid),
		.mul1_req(shared_mul1_req),
		.mul1_grant(shared_mul1_grant),
		.mul1_res(shared_mul1_res),
		.mul1_oid(shared_mul1_oid),
		.mul1_ovld(shared_mul1_ovld)
	);
	
	/** 最终结果传输请求生成单元 **/
	// DMA命令(AXIS主机)
	wire[55:0] m_fnl_res_tr_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire[24:0] m_fnl_res_tr_dma_cmd_axis_user; // {命令ID(24bit), 固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_fnl_res_tr_dma_cmd_axis_valid;
	wire m_fnl_res_tr_dma_cmd_axis_ready;
	// (共享)无符号乘法器#0
	// [计算输入]
	wire[15:0] shared_mul2_op_a; // 操作数A
	wire[23:0] shared_mul2_op_b; // 操作数B
	wire[3:0] shared_mul2_tid; // 操作ID
	wire shared_mul2_req;
	wire shared_mul2_grant;
	// [计算结果]
	wire[39:0] shared_mul2_res;
	wire[3:0] shared_mul2_oid;
	wire shared_mul2_ovld;
	// (共享)无符号乘法器#1
	// [计算输入]
	wire[15:0] shared_mul3_op_a; // 操作数A
	wire[23:0] shared_mul3_op_b; // 操作数B
	wire[3:0] shared_mul3_tid; // 操作ID
	wire shared_mul3_req;
	wire shared_mul3_grant;
	// [计算结果]
	wire[39:0] shared_mul3_res;
	wire[3:0] shared_mul3_oid;
	wire shared_mul3_ovld;
	// 实际乘法器#1
	reg[15:0] mul1_op_a;
	reg[23:0] mul1_op_b;
	reg[3:0] mul1_tid;
	reg mul1_ce;
	wire[39:0] mul1_res;
	reg[3:0] mul1_oid;
	reg mul1_ovld;
	
	assign m_dma_s2mm_cmd_axis_data = m_fnl_res_tr_dma_cmd_axis_data;
	assign m_dma_s2mm_cmd_axis_user = m_fnl_res_tr_dma_cmd_axis_user[0];
	assign m_dma_s2mm_cmd_axis_valid = m_fnl_res_tr_dma_cmd_axis_valid;
	assign m_fnl_res_tr_dma_cmd_axis_ready = m_dma_s2mm_cmd_axis_ready;
	
	assign shared_mul2_grant = shared_mul2_req;
	assign shared_mul2_res = mul1_res;
	assign shared_mul2_oid = mul1_oid;
	assign shared_mul2_ovld = mul1_ovld;
	
	assign shared_mul3_grant = (~shared_mul2_req) & shared_mul3_req;
	assign shared_mul3_res = mul1_res;
	assign shared_mul3_oid = mul1_oid;
	assign shared_mul3_ovld = mul1_ovld;
	
	always @(posedge aclk)
	begin
		if(shared_mul2_req | shared_mul3_req)
		begin
			mul1_op_a <= # SIM_DELAY 
				shared_mul2_req ? 
					shared_mul2_op_a:
					shared_mul3_op_a;
			mul1_op_b <= # SIM_DELAY 
				shared_mul2_req ? 
					shared_mul2_op_b:
					shared_mul3_op_b;
			mul1_tid <= # SIM_DELAY 
				shared_mul2_req ? 
					shared_mul2_tid:
					shared_mul3_tid;
		end
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			{mul1_ovld, mul1_ce} <= 2'b00;
		else
			{mul1_ovld, mul1_ce} <= # SIM_DELAY 
				{
					mul1_ce,
					shared_mul2_req | shared_mul3_req
				};
	end
	
	always @(posedge aclk)
	begin
		if(mul1_ce)
			mul1_oid <= # SIM_DELAY mul1_tid;
	end
	
	fnl_res_trans_req_gen #(
		.ATOMIC_K(ATOMIC_C),
		.SIM_DELAY(SIM_DELAY)
	)fnl_res_trans_req_gen_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.ofmap_baseaddr(ofmap_baseaddr),
		.ofmap_w(ofmap_w),
		.ofmap_h(ofmap_h),
		.ofmap_data_type(ofmap_data_type),
		.kernal_num_n(fmap_chn_n),
		.max_wgtblk_w(ATOMIC_C),
		.is_grp_conv_mode(1'b0),
		.n_foreach_group(16'dx),
		.en_send_sub_row_msg(1'b0),
		
		.blk_start(fnl_res_tr_req_gen_blk_start),
		.blk_idle(fnl_res_tr_req_gen_blk_idle),
		.blk_done(fnl_res_tr_req_gen_blk_done),
		
		.m_sub_row_msg_axis_data(),
		.m_sub_row_msg_axis_last(),
		.m_sub_row_msg_axis_valid(),
		.m_sub_row_msg_axis_ready(1'b1),
		
		.m_dma_cmd_axis_data(m_fnl_res_tr_dma_cmd_axis_data),
		.m_dma_cmd_axis_user(m_fnl_res_tr_dma_cmd_axis_user),
		.m_dma_cmd_axis_valid(m_fnl_res_tr_dma_cmd_axis_valid),
		.m_dma_cmd_axis_ready(m_fnl_res_tr_dma_cmd_axis_ready),
		
		.mul0_op_a(shared_mul2_op_a),
		.mul0_op_b(shared_mul2_op_b),
		.mul0_tid(shared_mul2_tid),
		.mul0_req(shared_mul2_req),
		.mul0_grant(shared_mul2_grant),
		.mul0_res(shared_mul2_res),
		.mul0_oid(shared_mul2_oid),
		.mul0_ovld(shared_mul2_ovld),
		
		.mul1_op_a(shared_mul3_op_a),
		.mul1_op_b(shared_mul3_op_b),
		.mul1_tid(shared_mul3_tid),
		.mul1_req(shared_mul3_req),
		.mul1_grant(shared_mul3_grant),
		.mul1_res(shared_mul3_res),
		.mul1_oid(shared_mul3_oid),
		.mul1_ovld(shared_mul3_ovld)
	);
	
	/** 池化数据枢纽 **/
	// 特征图表面行读请求(AXIS从机)
	wire[103:0] s_fm_rd_req_axis_data;
	wire s_fm_rd_req_axis_valid;
	wire s_fm_rd_req_axis_ready;
	// 特征图表面行随机读取(AXIS从机)
	wire[15:0] s_fm_random_rd_axis_data; // 表面号
	wire s_fm_random_rd_axis_last; // 标志本次读请求待读取的最后1个表面
	wire s_fm_random_rd_axis_valid;
	wire s_fm_random_rd_axis_ready;
	// 特征图表面行数据输出(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_fm_fout_axis_data;
	wire m_fm_fout_axis_last; // 标志本次读请求的最后1个表面
	wire m_fm_fout_axis_valid;
	wire m_fm_fout_axis_ready;
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
	)pool_data_hub_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.fmbufcoln(fmbufcoln),
		.fmbufrown(fmbufrown),
		.fmrow_random_rd_mode(1'b1),
		.grp_conv_buf_mode(1'b0),
		.kbufgrpsz(3'bxxx),
		.sfc_n_each_wgtblk(3'bxxx),
		.kbufgrpn(8'hxx),
		.fmbufbankn(CBUF_BANK_N),
		
		.s_fm_rd_req_axis_data(s_fm_rd_req_axis_data),
		.s_fm_rd_req_axis_valid(s_fm_rd_req_axis_valid),
		.s_fm_rd_req_axis_ready(s_fm_rd_req_axis_ready),
		
		.s_fm_random_rd_axis_data(s_fm_random_rd_axis_data),
		.s_fm_random_rd_axis_last(s_fm_random_rd_axis_last),
		.s_fm_random_rd_axis_valid(s_fm_random_rd_axis_valid),
		.s_fm_random_rd_axis_ready(s_fm_random_rd_axis_ready),
		
		.s_kwgtblk_rd_req_axis_data(104'dx),
		.s_kwgtblk_rd_req_axis_valid(1'b0),
		.s_kwgtblk_rd_req_axis_ready(),
		
		.m_fm_fout_axis_data(m_fm_fout_axis_data),
		.m_fm_fout_axis_last(m_fm_fout_axis_last),
		.m_fm_fout_axis_valid(m_fm_fout_axis_valid),
		.m_fm_fout_axis_ready(m_fm_fout_axis_ready),
		
		.m_kout_wgtblk_axis_data(),
		.m_kout_wgtblk_axis_last(),
		.m_kout_wgtblk_axis_valid(),
		.m_kout_wgtblk_axis_ready(1'b1),
		
		.m0_dma_cmd_axis_data(m_dma_cmd_axis_data),
		.m0_dma_cmd_axis_user(m_dma_cmd_axis_user),
		.m0_dma_cmd_axis_last(m_dma_cmd_axis_last),
		.m0_dma_cmd_axis_valid(m_dma_cmd_axis_valid),
		.m0_dma_cmd_axis_ready(m_dma_cmd_axis_ready),
		
		.s0_dma_strm_axis_data(s_dma_strm_axis_data),
		.s0_dma_strm_axis_keep(s_dma_strm_axis_keep),
		.s0_dma_strm_axis_last(s_dma_strm_axis_last),
		.s0_dma_strm_axis_valid(s_dma_strm_axis_valid),
		.s0_dma_strm_axis_ready(s_dma_strm_axis_ready),
		
		.m1_dma_cmd_axis_data(),
		.m1_dma_cmd_axis_user(),
		.m1_dma_cmd_axis_last(),
		.m1_dma_cmd_axis_valid(),
		.m1_dma_cmd_axis_ready(1'b1),
		
		.s1_dma_strm_axis_data({MM2S_STREAM_DATA_WIDTH{1'bx}}),
		.s1_dma_strm_axis_keep({(MM2S_STREAM_DATA_WIDTH/8){1'bx}}),
		.s1_dma_strm_axis_last(1'bx),
		.s1_dma_strm_axis_valid(1'b0),
		.s1_dma_strm_axis_ready(),
		
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
	
	/** 池化表面行适配器 **/
	// 池化表面行信息(AXIS从机)
	wire[15:0] s_pool_sfc_row_info_axis_data;
	wire s_pool_sfc_row_info_axis_valid;
	wire s_pool_sfc_row_info_axis_ready;
	// 特征图表面行随机读取(AXIS主机)
	wire[15:0] m_fm_random_rd_axis_data; // 表面号
	wire m_fm_random_rd_axis_last; // 标志本次读请求待读取的最后1个表面
	wire m_fm_random_rd_axis_valid;
	wire m_fm_random_rd_axis_ready;
	// 待转换的特征图表面行数据(AXIS从机)
	wire[ATOMIC_C*2*8-1:0] s_adapter_fm_axis_data;
	wire s_adapter_fm_axis_last; // 标志本次读请求的最后1个表面
	wire s_adapter_fm_axis_valid;
	wire s_adapter_fm_axis_ready;
	// 转换后的特征图表面行数据(AXIS主机)
	wire[ATOMIC_C*16-1:0] m_adapter_fm_axis_data; // ATOMIC_C个定点数或FP16
	wire[ATOMIC_C*2-1:0] m_adapter_fm_axis_keep;
	wire[2:0] m_adapter_fm_axis_user; // {本表面全0(标志), 初始化池化结果(标志), 最后1组池化表面(标志)}
	wire m_adapter_fm_axis_last; // 本行最后1个池化表面(标志)
	wire m_adapter_fm_axis_valid;
	wire m_adapter_fm_axis_ready;
	
	assign s_pool_sfc_row_info_axis_data = m_pool_sfc_row_info_axis_data;
	assign s_pool_sfc_row_info_axis_valid = m_pool_sfc_row_info_axis_valid;
	assign m_pool_sfc_row_info_axis_ready = s_pool_sfc_row_info_axis_ready;
	
	assign s_fm_random_rd_axis_data = m_fm_random_rd_axis_data;
	assign s_fm_random_rd_axis_last = m_fm_random_rd_axis_last;
	assign s_fm_random_rd_axis_valid = m_fm_random_rd_axis_valid;
	assign m_fm_random_rd_axis_ready = s_fm_random_rd_axis_ready;
	
	assign s_adapter_fm_axis_data = m_fm_fout_axis_data;
	assign s_adapter_fm_axis_last = m_fm_fout_axis_last;
	assign s_adapter_fm_axis_valid = m_fm_fout_axis_valid;
	assign m_fm_fout_axis_ready = s_adapter_fm_axis_ready;
	
	pool_sfc_row_adapter #(
		.ATOMIC_C(ATOMIC_C),
		.SIM_DELAY(SIM_DELAY)
	)pool_sfc_row_adapter_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.en_adapter(en_adapter),
		
		.pool_mode(pool_mode),
		.pool_horizontal_stride(pool_horizontal_stride),
		.pool_window_w(pool_window_w),
		.ifmap_w(ifmap_w),
		.external_padding_left(external_padding_left),
		.ofmap_w(ofmap_w_for_adapter),
		.upsample_horizontal_n(upsample_horizontal_n),
		.upsample_vertical_n(upsample_vertical_n),
		.non_zero_const_padding_mode(non_zero_const_padding_mode),
		.const_to_fill(const_to_fill),
		
		.s_pool_sfc_row_info_axis_data(s_pool_sfc_row_info_axis_data),
		.s_pool_sfc_row_info_axis_valid(s_pool_sfc_row_info_axis_valid),
		.s_pool_sfc_row_info_axis_ready(s_pool_sfc_row_info_axis_ready),
		
		.m_fm_random_rd_axis_data(m_fm_random_rd_axis_data),
		.m_fm_random_rd_axis_last(m_fm_random_rd_axis_last),
		.m_fm_random_rd_axis_valid(m_fm_random_rd_axis_valid),
		.m_fm_random_rd_axis_ready(m_fm_random_rd_axis_ready),
		
		.s_adapter_fm_axis_data(s_adapter_fm_axis_data),
		.s_adapter_fm_axis_last(s_adapter_fm_axis_last),
		.s_adapter_fm_axis_valid(s_adapter_fm_axis_valid),
		.s_adapter_fm_axis_ready(s_adapter_fm_axis_ready),
		
		.m_adapter_fm_axis_data(m_adapter_fm_axis_data),
		.m_adapter_fm_axis_keep(m_adapter_fm_axis_keep),
		.m_adapter_fm_axis_user(m_adapter_fm_axis_user),
		.m_adapter_fm_axis_last(m_adapter_fm_axis_last),
		.m_adapter_fm_axis_valid(m_adapter_fm_axis_valid),
		.m_adapter_fm_axis_ready(m_adapter_fm_axis_ready)
	);
	
	/** 池化中间结果更新与缓存 **/
	// 池化表面输入(AXIS从机)
	wire[ATOMIC_C*48-1:0] s_axis_mid_res_buf_data;
	wire[ATOMIC_C*6-1:0] s_axis_mid_res_buf_keep;
	wire[3:0] s_axis_mid_res_buf_user; // {本表面全0(标志), 是否最后1轮计算(标志), 初始化池化结果(标志), 最后1组池化表面(标志)}
	wire s_axis_mid_res_buf_last; // 本行最后1个池化表面(标志)
	wire s_axis_mid_res_buf_valid;
	wire s_axis_mid_res_buf_ready;
	// 池化结果输出(AXIS主机)
	wire[ATOMIC_C*32-1:0] m_axis_mid_res_buf_data; // ATOMIC_C个定点数或FP32
	wire[ATOMIC_C*4-1:0] m_axis_mid_res_buf_keep;
	wire m_axis_mid_res_buf_last; // 本行最后1个池化结果(标志)
	wire m_axis_mid_res_buf_valid;
	wire m_axis_mid_res_buf_ready;
	// 中间结果缓存MEM主接口
	wire mid_res_mem_clk_a;
	wire[RBUF_BANK_N-1:0] mid_res_mem_wen_a;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_a;
	wire[RBUF_BANK_N*(ATOMIC_C*4*8+ATOMIC_C)-1:0] mid_res_mem_din_a;
	wire mid_res_mem_clk_b;
	wire[RBUF_BANK_N-1:0] mid_res_mem_ren_b;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_b;
	wire[RBUF_BANK_N*(ATOMIC_C*4*8+ATOMIC_C)-1:0] mid_res_mem_dout_b;
	// 池化中间结果更新单元
	// [更新单元组输入]
	wire[ATOMIC_C*48-1:0] pool_upd_i_new_res; // 新结果
	wire[ATOMIC_C*32-1:0] pool_upd_i_org_mid_res; // 原中间结果
	wire[3+ATOMIC_C-1:0] pool_upd_i_info_along[0:ATOMIC_C-1]; // 随路数据
	wire[ATOMIC_C-1:0] pool_upd_i_mask; // 项掩码
	wire pool_upd_i_first_item; // 是否第1项(标志)
	wire pool_upd_i_last_grp; // 是否最后1组(标志)
	wire pool_upd_i_last_res; // 本行最后1个中间结果(标志)
	wire pool_upd_i_is_zero_sfc; // 是否空表面(标志)
	wire[ATOMIC_C-1:0] pool_upd_i_valid; // 输入有效指示
	// [更新单元组输出]
	wire[ATOMIC_C*32-1:0] pool_upd_o_data; // 单精度浮点数或定点数
	wire[3+ATOMIC_C-1:0] pool_upd_o_info_along[0:ATOMIC_C-1]; // 随路数据
	wire[ATOMIC_C-1:0] pool_upd_o_mask; // 输出项掩码
	wire pool_upd_o_last_grp; // 是否最后1组(标志)
	wire pool_upd_o_last_res; // 本行最后1个中间结果(标志)
	wire pool_upd_o_to_upd_mem; // 更新缓存MEM(标志)
	wire[ATOMIC_C-1:0] pool_upd_o_valid; // 输出有效指示
	
	assign {pool_upd_o_to_upd_mem, pool_upd_o_last_grp, pool_upd_o_last_res, pool_upd_o_mask} = 
		pool_upd_o_info_along[0];
	
	genvar mid_res_i;
	generate
		for(mid_res_i = 0;mid_res_i < ATOMIC_C;mid_res_i = mid_res_i + 1)
		begin:mid_res_blk
			assign s_axis_mid_res_buf_data[(mid_res_i+1)*48-1:mid_res_i*48] = 
				{32'd0, m_adapter_fm_axis_data[(mid_res_i+1)*16-1:mid_res_i*16]};
			
			assign s_axis_mid_res_buf_keep[(mid_res_i+1)*6-1:mid_res_i*6] = 
				{6{m_adapter_fm_axis_keep[mid_res_i*2]}};
			
			assign pool_upd_i_info_along[mid_res_i] = 
				(mid_res_i == 0) ? 
					{
						((pool_mode == POOL_MODE_UPSP) | pool_upd_i_first_item) | 
						((pool_mode == POOL_MODE_MAX) | (~pool_upd_i_is_zero_sfc)),
						pool_upd_i_last_grp,
						pool_upd_i_last_res,
						pool_upd_i_mask
					}:
					{(3+ATOMIC_C){1'bx}};
			
			pool_middle_res_upd #(
				.INFO_ALONG_WIDTH(ATOMIC_C+3),
				.SIM_DELAY(SIM_DELAY)
			)pool_middle_res_upd_u(
				.aclk(aclk),
				.aresetn(aresetn),
				.aclken(1'b1),
				
				.pool_mode(pool_mode),
				.calfmt(calfmt),
				
				.pool_upd_in_data(pool_upd_i_new_res[mid_res_i*48+15:mid_res_i*48]),
				.pool_upd_in_org_mid_res(pool_upd_i_org_mid_res[mid_res_i*32+31:mid_res_i*32]),
				.pool_upd_in_is_first_item(pool_upd_i_first_item),
				.pool_upd_in_is_zero_sfc(pool_upd_i_is_zero_sfc),
				.pool_upd_in_info_along(pool_upd_i_info_along[mid_res_i]),
				.pool_upd_in_valid(pool_upd_i_valid[mid_res_i]),
				
				.pool_upd_out_data(pool_upd_o_data[mid_res_i*32+31:mid_res_i*32]),
				.pool_upd_out_info_along(pool_upd_o_info_along[mid_res_i]),
				.pool_upd_out_valid(pool_upd_o_valid[mid_res_i])
			);
		end
	endgenerate
	
	assign s_axis_mid_res_buf_user = {m_adapter_fm_axis_user[2], 1'b1, m_adapter_fm_axis_user[1:0]};
	assign s_axis_mid_res_buf_last = m_adapter_fm_axis_last;
	assign s_axis_mid_res_buf_valid = m_adapter_fm_axis_valid;
	assign m_adapter_fm_axis_ready = s_axis_mid_res_buf_ready;
	
	conv_middle_res_acmlt_buf #(
		.ATOMIC_K(ATOMIC_C),
		.RBUF_BANK_N(RBUF_BANK_N),
		.RBUF_DEPTH(RBUF_DEPTH),
		.INFO_ALONG_WIDTH(1),
		.SIM_DELAY(SIM_DELAY)
	)pool_middle_res_buf_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.calfmt(calfmt),
		.row_n_bufferable(mid_res_buf_row_n_bufferable),
		.bank_n_foreach_ofmap_row(bank_n_foreach_ofmap_row),
		.max_upd_latency(2 + 6),
		.en_cal_round_ext(1'b0),
		.ofmap_w(ofmap_w),
		
		.s_axis_mid_res_data(s_axis_mid_res_buf_data),
		.s_axis_mid_res_keep(s_axis_mid_res_buf_keep),
		.s_axis_mid_res_user(s_axis_mid_res_buf_user),
		.s_axis_mid_res_last(s_axis_mid_res_buf_last),
		.s_axis_mid_res_valid(s_axis_mid_res_buf_valid),
		.s_axis_mid_res_ready(s_axis_mid_res_buf_ready),
		
		.m_axis_fnl_res_data(m_axis_mid_res_buf_data),
		.m_axis_fnl_res_keep(m_axis_mid_res_buf_keep),
		.m_axis_fnl_res_user(),
		.m_axis_fnl_res_last(m_axis_mid_res_buf_last),
		.m_axis_fnl_res_valid(m_axis_mid_res_buf_valid),
		.m_axis_fnl_res_ready(m_axis_mid_res_buf_ready),
		
		.mem_clk_a(mid_res_mem_clk_a),
		.mem_wen_a(mid_res_mem_wen_a),
		.mem_addr_a(mid_res_mem_addr_a),
		.mem_din_a(mid_res_mem_din_a),
		.mem_clk_b(mid_res_mem_clk_b),
		.mem_ren_b(mid_res_mem_ren_b),
		.mem_addr_b(mid_res_mem_addr_b),
		.mem_dout_b(mid_res_mem_dout_b),
		
		.acmlt_in_new_res(pool_upd_i_new_res),
		.acmlt_in_org_mid_res(pool_upd_i_org_mid_res),
		.acmlt_in_mask(pool_upd_i_mask),
		.acmlt_in_first_item(pool_upd_i_first_item),
		.acmlt_in_last_grp(pool_upd_i_last_grp),
		.acmlt_in_last_res(pool_upd_i_last_res),
		.acmlt_in_info_along(pool_upd_i_is_zero_sfc),
		.acmlt_in_valid(pool_upd_i_valid),
		
		.acmlt_out_data(pool_upd_o_data),
		.acmlt_out_mask(pool_upd_o_mask),
		.acmlt_out_last_grp(pool_upd_o_last_grp),
		.acmlt_out_last_res(pool_upd_o_last_res),
		.acmlt_out_to_upd_mem(pool_upd_o_to_upd_mem),
		.acmlt_out_valid(pool_upd_o_valid[0])
	);
	
	/** 后乘加处理 **/
	// 池化最终结果(AXIS从机)
	wire[ATOMIC_C*32-1:0] s_axis_post_mac_data; // 对于ATOMIC_C个最终结果 -> {单精度浮点数或定点数(32位)}
	wire[ATOMIC_C*4-1:0] s_axis_post_mac_keep;
	wire s_axis_post_mac_last; // 本行最后1个最终结果(标志)
	wire s_axis_post_mac_valid;
	wire s_axis_post_mac_ready;
	// 经过后乘加处理的结果(AXIS主机)
	wire[POST_MAC_PRL_N*32-1:0] m_axis_post_mac_data; // 对于POST_MAC_PRL_N个最终结果 -> {单精度浮点数或定点数(32位)}
	wire[POST_MAC_PRL_N*4-1:0] m_axis_post_mac_keep;
	wire m_axis_post_mac_last; // 本行最后1个处理结果(标志)
	wire m_axis_post_mac_valid;
	wire m_axis_post_mac_ready;
	// 后乘加处理的乘法器组
	wire[POST_MAC_MUL_OP_WIDTH*POST_MAC_PRL_N-1:0] post_mac_mul_op_a; // 操作数A
	wire[POST_MAC_MUL_OP_WIDTH*POST_MAC_PRL_N-1:0] post_mac_mul_op_b; // 操作数B
	wire[POST_MAC_MUL_CE_WIDTH*POST_MAC_PRL_N-1:0] post_mac_mul_ce; // 计算使能
	wire[POST_MAC_MUL_RES_WIDTH*POST_MAC_PRL_N-1:0] post_mac_mul_res; // 计算结果
	// 处理结果fifo(MEM主接口)
	wire proc_res_fifo_mem_clk;
	wire proc_res_fifo_mem_wen_a;
	wire[8:0] proc_res_fifo_mem_addr_a;
	wire[POST_MAC_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_din_a;
	wire proc_res_fifo_mem_ren_b;
	wire[8:0] proc_res_fifo_mem_addr_b;
	wire[POST_MAC_PROC_RES_FIFO_WIDTH-1:0] proc_res_fifo_mem_dout_b;
	
	/**
	使能后乘加处理   -> (中间结果缓存)池化结果输出
	不使能后乘加处理 -> 无效
	**/
	assign s_axis_post_mac_data = m_axis_mid_res_buf_data;
	assign s_axis_post_mac_keep = m_axis_mid_res_buf_keep;
	assign s_axis_post_mac_last = m_axis_mid_res_buf_last;
	assign s_axis_post_mac_valid = en_post_mac & m_axis_mid_res_buf_valid;
	
	conv_bn_act_proc #(
		.FP32_KEEP(1'b1),
		.ATOMIC_K(ATOMIC_C),
		.BN_ACT_PRL_N(POST_MAC_PRL_N),
		.INT16_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
		.INT32_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
		.FP32_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
		.SIM_DELAY(SIM_DELAY)
	)post_mac_proc_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.en_bn_act_proc(en_post_mac),
		
		.calfmt(post_mac_calfmt),
		.use_bn_unit(1'b1),
		.use_act_unit(1'b0),
		.bn_fixed_point_quat_accrc(post_mac_fixed_point_quat_accrc),
		.bn_is_a_eq_1(post_mac_is_a_eq_1),
		.bn_is_b_eq_0(post_mac_is_b_eq_0),
		.is_in_const_mac_mode(1'b1),
		.param_a_in_const_mac_mode(post_mac_param_a),
		.param_b_in_const_mac_mode(post_mac_param_b),
		.leaky_relu_fixed_point_quat_accrc(5'dx),
		.leaky_relu_param_alpha(32'hxxxxxxxx),
		
		.s_sub_row_msg_axis_data(16'hxxxx),
		.s_sub_row_msg_axis_last(1'bx),
		.s_sub_row_msg_axis_valid(1'b0),
		.s_sub_row_msg_axis_ready(),
		
		.s_axis_fnl_res_data(s_axis_post_mac_data),
		.s_axis_fnl_res_keep(s_axis_post_mac_keep),
		.s_axis_fnl_res_user(5'bxxxxx),
		.s_axis_fnl_res_last(s_axis_post_mac_last),
		.s_axis_fnl_res_valid(s_axis_post_mac_valid),
		.s_axis_fnl_res_ready(s_axis_post_mac_ready),
		
		.m_axis_bn_act_res_data(m_axis_post_mac_data),
		.m_axis_bn_act_res_keep(m_axis_post_mac_keep),
		.m_axis_bn_act_res_user(),
		.m_axis_bn_act_res_last(m_axis_post_mac_last),
		.m_axis_bn_act_res_valid(m_axis_post_mac_valid),
		.m_axis_bn_act_res_ready(m_axis_post_mac_ready),
		
		.bn_mem_clk_b(),
		.bn_mem_ren_b(),
		.bn_mem_addr_b(),
		.bn_mem_dout_b(64'dx),
		
		.proc_res_fifo_mem_clk(proc_res_fifo_mem_clk),
		.proc_res_fifo_mem_wen_a(proc_res_fifo_mem_wen_a),
		.proc_res_fifo_mem_addr_a(proc_res_fifo_mem_addr_a),
		.proc_res_fifo_mem_din_a(proc_res_fifo_mem_din_a),
		.proc_res_fifo_mem_ren_b(proc_res_fifo_mem_ren_b),
		.proc_res_fifo_mem_addr_b(proc_res_fifo_mem_addr_b),
		.proc_res_fifo_mem_dout_b(proc_res_fifo_mem_dout_b),
		
		.mul0_op_a(post_mac_mul_op_a),
		.mul0_op_b(post_mac_mul_op_b),
		.mul0_ce(post_mac_mul_ce),
		.mul0_res(post_mac_mul_res),
		
		.mul1_op_a(),
		.mul1_op_b(),
		.mul1_ce(),
		.mul1_res({(POST_MAC_PRL_N*(INT16_SUPPORTED ? 64:50)){1'bx}})
	);
	
	/** 输出数据舍入单元组 **/
	// [舍入单元组输入]
	wire[ATOMIC_C*32-1:0] s_axis_round_data; // ATOMIC_C个定点数或FP32
	wire[ATOMIC_C*4-1:0] s_axis_round_keep;
	wire s_axis_round_last; // 本行最后1个池化结果(标志)
	wire s_axis_round_valid;
	wire s_axis_round_ready;
	// [舍入单元组输出]
	wire[ATOMIC_C*(KEEP_FP32_OUT ? 32:16)-1:0] m_axis_round_data; // ATOMIC_C个定点数或浮点数
	wire[ATOMIC_C*(KEEP_FP32_OUT ? 4:2)-1:0] m_axis_round_keep;
	wire m_axis_round_last; // 本行最后1个池化结果(标志)
	wire m_axis_round_valid;
	wire m_axis_round_ready;
	// [流水线控制]
	// (第0级)
	wire[ATOMIC_C-1:0] round_mask_s0;
	wire round_last_s0;
	wire round_valid_s0;
	wire round_ready_s0;
	wire[ATOMIC_C-1:0] round_ce_s0;
	// (第1级)
	reg[ATOMIC_C-1:0] round_mask_s1;
	reg round_last_s1;
	reg round_valid_s1;
	wire round_ready_s1;
	wire[ATOMIC_C-1:0] round_ce_s1;
	// (第2级)
	reg[ATOMIC_C-1:0] round_mask_s2;
	reg round_last_s2;
	reg round_valid_s2;
	wire round_ready_s2;
	
	/**
	使能后乘加处理   -> 后乘加处理输入
	不使能后乘加处理 -> 舍入单元组输入
	**/
	assign m_axis_mid_res_buf_ready = 
		en_post_mac ? 
			s_axis_post_mac_ready:
			s_axis_round_ready;
	
	/**
	使能后乘加处理   -> 舍入单元组输入
	不使能后乘加处理 -> 忽略
	**/
	assign m_axis_post_mac_ready = 
		(~en_post_mac) | s_axis_round_ready;
	
	/**
	使能后乘加处理   -> 经过后乘加处理的结果
	不使能后乘加处理 -> (中间结果缓存)池化结果输出
	**/
	assign s_axis_round_data = 
		en_post_mac ? 
			(m_axis_post_mac_data | {(ATOMIC_C*32){1'b0}}):
			m_axis_mid_res_buf_data;
	assign s_axis_round_keep = 
		en_post_mac ? 
			(m_axis_post_mac_keep | {(ATOMIC_C*4){1'b0}}):
			m_axis_mid_res_buf_keep;
	assign s_axis_round_last = 
		en_post_mac ? 
			m_axis_post_mac_last:
			m_axis_mid_res_buf_last;
	assign s_axis_round_valid = 
		en_post_mac ? 
			m_axis_post_mac_valid:
			m_axis_mid_res_buf_valid;
	
	assign round_last_s0 = s_axis_round_last;
	assign round_valid_s0 = s_axis_round_valid;
	
	assign round_ready_s0 = (~round_valid_s1) | round_ready_s1;
	assign round_ready_s1 = (~round_valid_s2) | round_ready_s2;
	assign round_ready_s2 = m_axis_round_ready;
	
	always @(posedge aclk)
	begin
		if(round_valid_s0 & round_ready_s0)
		begin
			round_mask_s1 <= # SIM_DELAY round_mask_s0;
			round_last_s1 <= # SIM_DELAY round_last_s0;
		end
	end
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			round_valid_s1 <= 1'b0;
		else if(round_ready_s0)
			round_valid_s1 <= # SIM_DELAY round_valid_s0;
	end
	
	always @(posedge aclk)
	begin
		if(round_valid_s1 & round_ready_s1)
		begin
			round_mask_s2 <= # SIM_DELAY round_mask_s1;
			round_last_s2 <= # SIM_DELAY round_last_s1;
		end
	end
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			round_valid_s2 <= 1'b0;
		else if(round_ready_s1)
			round_valid_s2 <= # SIM_DELAY round_valid_s1;
	end
	
	genvar round_i;
	generate
		if(KEEP_FP32_OUT == 0)
		begin
			assign s_axis_round_ready = round_ready_s0;
			
			assign m_axis_round_last = round_last_s2;
			assign m_axis_round_valid = round_valid_s2;
			
			for(round_i = 0;round_i < ATOMIC_C;round_i = round_i + 1)
			begin:round_blk
				assign m_axis_round_keep[round_i*2+1:round_i*2] = {2{round_mask_s2[round_i]}};
				
				assign round_mask_s0[round_i] = s_axis_round_keep[round_i*4];
				
				assign round_ce_s0[round_i] = round_valid_s0 & round_ready_s0 & round_mask_s0[round_i];
				assign round_ce_s1[round_i] = round_valid_s1 & round_ready_s1 & round_mask_s1[round_i];
				
				out_round_cell #(
					.USE_EXT_CE(1'b1),
					.INT8_SUPPORTED(INT8_SUPPORTED ? 1'b1:1'b0),
					.INT16_SUPPORTED(INT16_SUPPORTED ? 1'b1:1'b0),
					.FP16_SUPPORTED(FP16_SUPPORTED ? 1'b1:1'b0),
					.INFO_ALONG_WIDTH(1),
					.SIM_DELAY(SIM_DELAY)
				)out_round_cell_u(
					.aclk(aclk),
					.aresetn(aresetn),
					.aclken(1'b1),
					
					.calfmt(calfmt),
					.fixed_point_quat_accrc(4'bxxxx), // 运行时参数需要给出!!!
					
					.s0_ce(round_ce_s0[round_i]),
					.s1_ce(round_ce_s1[round_i]),
					
					.round_i_op_x(s_axis_round_data[round_i*32+31:round_i*32]),
					.round_i_info_along(1'bx),
					.round_i_vld(1'bx),
					
					.round_o_res(m_axis_round_data[round_i*16+15:round_i*16]),
					.round_o_info_along(),
					.round_o_vld()
				);
			end
		end
		else
		begin
			assign m_axis_round_data = s_axis_round_data;
			assign m_axis_round_keep = s_axis_round_keep;
			assign m_axis_round_last = s_axis_round_last;
			assign m_axis_round_valid = s_axis_round_valid;
			assign s_axis_round_ready = m_axis_round_ready;
		end
	endgenerate
	
	/** 最终结果数据收集器 **/
	// 收集器输入(AXIS从机)
	wire[ATOMIC_C*(KEEP_FP32_OUT ? 32:16)-1:0] s_axis_collector_data;
	wire[ATOMIC_C*(KEEP_FP32_OUT ? 4:2)-1:0] s_axis_collector_keep;
	wire s_axis_collector_last;
	wire s_axis_collector_valid;
	wire s_axis_collector_ready;
	// 收集器输出(AXIS主机)
	wire[S2MM_STREAM_DATA_WIDTH-1:0] m_axis_collector_data;
	wire[S2MM_STREAM_DATA_WIDTH-1:0] m_axis_collector_keep;
	wire m_axis_collector_last;
	wire m_axis_collector_valid;
	wire m_axis_collector_ready;
	
	assign s_axis_collector_data = m_axis_round_data;
	assign s_axis_collector_keep = m_axis_round_keep;
	assign s_axis_collector_last = m_axis_round_last;
	assign s_axis_collector_valid = m_axis_round_valid;
	assign m_axis_round_ready = s_axis_collector_ready;
	
	assign m_axis_fnl_res_data = m_axis_collector_data;
	assign m_axis_fnl_res_keep = m_axis_collector_keep;
	assign m_axis_fnl_res_last = m_axis_collector_last;
	assign m_axis_fnl_res_valid = m_axis_collector_valid;
	assign m_axis_collector_ready = m_axis_fnl_res_ready;
	
	conv_final_data_collector #(
		.IN_ITEM_WIDTH(ATOMIC_C),
		.OUT_ITEM_WIDTH(S2MM_STREAM_DATA_WIDTH/(KEEP_FP32_OUT ? 32:16)),
		.DATA_WIDTH_FOREACH_ITEM(KEEP_FP32_OUT ? 32:16),
		.HAS_USER("false"),
		.USER_WIDTH(1),
		.EN_COLLECTOR_OUT_REG_SLICE("true"),
		.SIM_DELAY(SIM_DELAY)
	)pool_final_data_collector_u(
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
	
	/** 乘法器 **/
	signed_mul #(
		.op_a_width(18),
		.op_b_width(25),
		.output_width(43),
		.en_in_reg("false"),
		.en_out_reg("false"),
		.simulation_delay(SIM_DELAY)
	)mul_s18_s25_u0(
		.clk(aclk),
		
		.ce_in_reg(1'b0),
		.ce_mul(mul0_ce),
		.ce_out_reg(1'b0),
		
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
	
	genvar post_mac_mul_i;
	generate
		if(INT8_SUPPORTED)
		begin:case_post_mac_int16_supported
			for(post_mac_mul_i = 0;post_mac_mul_i < 4 * POST_MAC_PRL_N;post_mac_mul_i = post_mac_mul_i + 1)
			begin:post_mac_mul_blk_a
				signed_mul #(
					.op_a_width(18),
					.op_b_width(18),
					.output_width(36),
					.en_in_reg("false"),
					.en_out_reg("false"),
					.simulation_delay(SIM_DELAY)
				)post_mac_mul_u(
					.clk(aclk),
					
					.ce_in_reg(1'b0),
					.ce_mul(post_mac_mul_ce[post_mac_mul_i]),
					.ce_out_reg(1'b0),
					
					.op_a(post_mac_mul_op_a[(post_mac_mul_i+1)*18-1:post_mac_mul_i*18]),
					.op_b(post_mac_mul_op_b[(post_mac_mul_i+1)*18-1:post_mac_mul_i*18]),
					
					.res(post_mac_mul_res[(post_mac_mul_i+1)*36-1:post_mac_mul_i*36])
				);
			end
		end
		else
		begin:case_post_mac_int16_not_supported
			for(post_mac_mul_i = 0;post_mac_mul_i < POST_MAC_PRL_N;post_mac_mul_i = post_mac_mul_i + 1)
			begin:post_mac_mul_blk_b
				signed_mul #(
					.op_a_width(INT16_SUPPORTED ? 32:25),
					.op_b_width(INT16_SUPPORTED ? 32:25),
					.output_width(INT16_SUPPORTED ? 64:50),
					.en_in_reg("true"),
					.en_out_reg("true"),
					.simulation_delay(SIM_DELAY)
				)post_mac_mul_u(
					.clk(aclk),
					
					.ce_in_reg(post_mac_mul_ce[post_mac_mul_i*3+0]),
					.ce_mul(post_mac_mul_ce[post_mac_mul_i*3+1]),
					.ce_out_reg(post_mac_mul_ce[post_mac_mul_i*3+2]),
					
					.op_a(post_mac_mul_op_a[(post_mac_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:post_mac_mul_i*(INT16_SUPPORTED ? 32:25)]),
					.op_b(post_mac_mul_op_b[(post_mac_mul_i+1)*(INT16_SUPPORTED ? 32:25)-1:post_mac_mul_i*(INT16_SUPPORTED ? 32:25)]),
					
					.res(post_mac_mul_res[(post_mac_mul_i+1)*(INT16_SUPPORTED ? 64:50)-1:post_mac_mul_i*(INT16_SUPPORTED ? 64:50)])
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
				.mem_width(ATOMIC_C*4*8+ATOMIC_C),
				.mem_depth(RBUF_DEPTH),
				.INIT_FILE("default"),
				.simulation_delay(SIM_DELAY)
			)mid_res_ram_u(
				.clk(mid_res_mem_clk_a),
				
				.wen_a(mid_res_mem_wen_a[mid_res_mem_i]),
				.addr_a(mid_res_mem_addr_a[mid_res_mem_i*16+15:mid_res_mem_i*16]),
				.din_a(mid_res_mem_din_a[(mid_res_mem_i+1)*(ATOMIC_C*4*8+ATOMIC_C)-1:mid_res_mem_i*(ATOMIC_C*4*8+ATOMIC_C)]),
				
				.ren_b(mid_res_mem_ren_b[mid_res_mem_i]),
				.addr_b(mid_res_mem_addr_b[mid_res_mem_i*16+15:mid_res_mem_i*16]),
				.dout_b(mid_res_mem_dout_b[(mid_res_mem_i+1)*(ATOMIC_C*4*8+ATOMIC_C)-1:mid_res_mem_i*(ATOMIC_C*4*8+ATOMIC_C)])
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
		.mem_width(POST_MAC_PROC_RES_FIFO_WIDTH),
		.mem_depth(512),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)post_mac_proc_res_fifo_ram_u(
		.clk(proc_res_fifo_mem_clk),
		
		.wen_a(proc_res_fifo_mem_wen_a),
		.addr_a(proc_res_fifo_mem_addr_a),
		.din_a(proc_res_fifo_mem_din_a),
		
		.ren_b(proc_res_fifo_mem_ren_b),
		.addr_b(proc_res_fifo_mem_addr_b),
		.dout_b(proc_res_fifo_mem_dout_b)
	);
	
endmodule
