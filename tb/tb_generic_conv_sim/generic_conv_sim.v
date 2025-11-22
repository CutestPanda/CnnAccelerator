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
本模块: 请填写

描述:
请填写

注意：
请填写

协议:
请填写

作者: 陈家耀
日期: 2025/11/13
********************************************************************/


module generic_conv_sim #(
	parameter integer ATOMIC_K = 8, // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MAX_CAL_ROUND = 1, // 最大的计算轮次(1~16)
	parameter integer STREAM_DATA_WIDTH = 32, // DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer FNL_RES_DATA_WIDTH = 64, // 最终结果数据流的位宽(32 | 64 | 128 | 256)
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
	
	// 使能信号
	input wire en_mac_array, // 使能乘加阵列
	input wire en_packer, // 使能打包器
	
	// 运行时参数
	// [计算参数]
	input wire[1:0] calfmt, // 运算数据格式
	input wire[2:0] conv_vertical_stride, // 卷积垂直步长 - 1
	input wire[2:0] conv_horizontal_stride, // 卷积水平步长 - 1
	input wire[3:0] cal_round, // 计算轮次 - 1
	// [组卷积模式]
	input wire is_grp_conv_mode, // 是否处于组卷积模式
	input wire[15:0] group_n, // 分组数 - 1
	input wire[15:0] n_foreach_group, // 每组的通道数/核数 - 1
	input wire[31:0] data_size_foreach_group, // (特征图)每组的数据量
	// [特征图参数]
	input wire[31:0] fmap_baseaddr, // 特征图数据基地址
	input wire[15:0] ifmap_w, // 输入特征图宽度 - 1
	input wire[23:0] ifmap_size, // 输入特征图大小 - 1
	input wire[15:0] fmap_chn_n, // 特征图通道数 - 1
	input wire[15:0] fmap_ext_i_bottom, // 扩展后特征图的垂直边界
	input wire[2:0] external_padding_left, // 左部外填充数
	input wire[2:0] external_padding_top, // 上部外填充数
	input wire[2:0] inner_padding_left_right, // 左右内填充数
	input wire[2:0] inner_padding_top_bottom, // 上下内填充数
	input wire[15:0] ofmap_w, // 输出特征图宽度 - 1
	input wire[15:0] ofmap_h, // 输出特征图高度 - 1
	// [卷积核参数]
	input wire[31:0] kernal_wgt_baseaddr, // 卷积核权重基地址
	input wire[2:0] kernal_shape, // 卷积核形状
	input wire[3:0] kernal_dilation_hzt_n, // 水平膨胀量
	input wire[4:0] kernal_w_dilated, // (膨胀后)卷积核宽度 - 1
	input wire[3:0] kernal_dilation_vtc_n, // 垂直膨胀量
	input wire[4:0] kernal_h_dilated, // (膨胀后)卷积核高度 - 1
	input wire[15:0] kernal_chn_n, // 通道数 - 1
	input wire[15:0] cgrpn_foreach_kernal_set, // 每个核组的通道组数 - 1
	input wire[15:0] kernal_num_n, // 核数 - 1
	input wire[15:0] kernal_set_n, // 核组个数 - 1
	input wire[5:0] max_wgtblk_w, // 权重块最大宽度
	// [缓存参数]
	input wire[7:0] fmbufbankn, // 分配给特征图缓存的Bank数
	input wire[3:0] fmbufcoln, // 每个表面行的表面个数类型
	input wire[9:0] fmbufrown, // 可缓存的表面行数 - 1
	input wire[2:0] kbufgrpsz, // 每个通道组的权重块个数的类型
	input wire[2:0] sfc_n_each_wgtblk, // 每个权重块的表面个数的类型
	input wire[7:0] kbufgrpn, // 可缓存的通道组数 - 1
	input wire[15:0] mid_res_item_n_foreach_row, // 每个输出特征图表面行的中间结果项数 - 1
	input wire[3:0] mid_res_buf_row_n_bufferable, // 可缓存行数 - 1
	
	// 块级控制
	// [卷积核权重访问请求生成单元]
	input wire kernal_access_blk_start,
	output wire kernal_access_blk_idle,
	output wire kernal_access_blk_done,
	// [特征图表面行访问请求生成单元]
	input wire fmap_access_blk_start,
	output wire fmap_access_blk_idle,
	output wire fmap_access_blk_done,
	
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
	
	// 最终结果数据流(AXIS主机)
	output wire[FNL_RES_DATA_WIDTH-1:0] m_axis_fnl_res_data,
	output wire[FNL_RES_DATA_WIDTH/8-1:0] m_axis_fnl_res_keep,
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
	localparam integer LG_FMBUF_BUFFER_RID_WIDTH = clogb2(MAX_FMBUF_ROWN); // 特征图缓存的缓存行号的位宽
	
	/** 通用卷积单元控制子系统 **/
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
	
	conv_ctrl_sub_system #(
		.ATOMIC_C(ATOMIC_C),
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
		.fmap_baseaddr(fmap_baseaddr),
		.ifmap_w(ifmap_w),
		.ifmap_size(ifmap_size),
		.fmap_chn_n(fmap_chn_n),
		.fmap_ext_i_bottom(fmap_ext_i_bottom),
		.external_padding_top(external_padding_top),
		.inner_padding_top_bottom(inner_padding_top_bottom),
		.ofmap_h(ofmap_h),
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
		
		.rst_adapter(rst_adapter),
		.on_incr_phy_row_traffic(on_incr_phy_row_traffic),
		.en_mac_array(),
		.en_packer(),
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
		
		.mul0_op_a(mul0_op_a),
		.mul0_op_b(mul0_op_b),
		.mul0_ce(mul0_ce),
		.mul0_res(mul0_res),
		.mul1_op_a(mul1_op_a),
		.mul1_op_b(mul1_op_b),
		.mul1_ce(mul1_ce),
		.mul1_res(mul1_res)
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
		.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH),
		.ATOMIC_C(ATOMIC_C),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.FM_RD_REQ_PRE_ACPT_N(4),
		.KWGTBLK_RD_REQ_PRE_ACPT_N(4),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.LG_FMBUF_BUFFER_RID_WIDTH(LG_FMBUF_BUFFER_RID_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)conv_data_hub_u(
		.aclk(aclk),
		.aresetn(aresetn),
		.aclken(1'b1),
		
		.fmbufcoln(fmbufcoln),
		.fmbufrown(fmbufrown),
		.grp_conv_buf_mode(is_grp_conv_mode),
		.kbufgrpsz(kbufgrpsz),
		.sfc_n_each_wgtblk(sfc_n_each_wgtblk),
		.kbufgrpn(kbufgrpn),
		.fmbufbankn(fmbufbankn),
		
		.s_fm_rd_req_axis_data(s_fm_rd_req_axis_data),
		.s_fm_rd_req_axis_valid(s_fm_rd_req_axis_valid),
		.s_fm_rd_req_axis_ready(s_fm_rd_req_axis_ready),
		
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
	
	/** 通用卷积单元计算子系统 **/
	// 特征图切块信息(AXIS从机)
	wire[7:0] s_fm_cake_info_axis_data; // {保留(4bit), 每个切片里的有效表面行数(4bit)}
	wire s_fm_cake_info_axis_valid;
	wire s_fm_cake_info_axis_ready;
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
	// 有符号乘法器阵列
	wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_array_op_a; // 操作数A
	wire[ATOMIC_K*ATOMIC_C*16-1:0] mul_array_op_b; // 操作数B
	wire[ATOMIC_K-1:0] mul_array_ce; // 计算使能
	wire[ATOMIC_K*ATOMIC_C*32-1:0] mul_array_res; // 计算结果
	// 缓存MEM主接口
	wire mid_res_mem_clk_a;
	wire[RBUF_BANK_N-1:0] mid_res_mem_wen_a;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_a;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_din_a;
	wire mid_res_mem_clk_b;
	wire[RBUF_BANK_N-1:0] mid_res_mem_ren_b;
	wire[RBUF_BANK_N*16-1:0] mid_res_mem_addr_b;
	wire[RBUF_BANK_N*(ATOMIC_K*4*8+ATOMIC_K)-1:0] mid_res_mem_dout_b;
	
	assign s_fm_cake_info_axis_data = m_fm_cake_info_axis_data;
	assign s_fm_cake_info_axis_valid = m_fm_cake_info_axis_valid;
	assign m_fm_cake_info_axis_ready = s_fm_cake_info_axis_ready;
	
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
		.STREAM_DATA_WIDTH(FNL_RES_DATA_WIDTH),
		.MAX_CAL_ROUND(MAX_CAL_ROUND),
		.EN_SMALL_FP16("true"),
		.EN_SMALL_FP32("true"),
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
		.en_packer(en_packer),
		
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
		
		.s_fm_cake_info_axis_data(s_fm_cake_info_axis_data),
		.s_fm_cake_info_axis_valid(s_fm_cake_info_axis_valid),
		.s_fm_cake_info_axis_ready(s_fm_cake_info_axis_ready),
		
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
		
		.mul_op_a(mul_array_op_a),
		.mul_op_b(mul_array_op_b),
		.mul_ce(mul_array_ce),
		.mul_res(mul_array_res),
		
		.mem_clk_a(mid_res_mem_clk_a),
		.mem_wen_a(mid_res_mem_wen_a),
		.mem_addr_a(mid_res_mem_addr_a),
		.mem_din_a(mid_res_mem_din_a),
		.mem_clk_b(mid_res_mem_clk_b),
		.mem_ren_b(mid_res_mem_ren_b),
		.mem_addr_b(mid_res_mem_addr_b),
		.mem_dout_b(mid_res_mem_dout_b)
	);
	
	/** 乘法器 **/
	unsigned_mul #(
		.op_a_width(16),
		.op_b_width(16),
		.output_width(32),
		.simulation_delay(SIM_DELAY)
	)mul_u16_u16_u(
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
	)mul_u16_u24_u(
		.clk(aclk),
		
		.ce_s0_mul(mul1_ce),
		
		.op_a(mul1_op_a),
		.op_b(mul1_op_b),
		
		.res(mul1_res)
	);
	
	genvar mul_i;
	generate
		for(mul_i = 0;mul_i < ATOMIC_K*ATOMIC_C;mul_i = mul_i + 1)
		begin:mul_blk
			signed_mul #(
				.op_a_width(16),
				.op_b_width(16),
				.output_width(32),
				.simulation_delay(SIM_DELAY)
			)mul_s16_s16_u(
				.clk(aclk),
				
				.ce_s0_mul(mul_array_ce[mul_i/ATOMIC_C]),
				
				.op_a(mul_array_op_a[16*mul_i+15:16*mul_i]),
				.op_b(mul_array_op_b[16*mul_i+15:16*mul_i]),
				
				.res(mul_array_res[32*mul_i+31:32*mul_i])
			);
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
	
endmodule
