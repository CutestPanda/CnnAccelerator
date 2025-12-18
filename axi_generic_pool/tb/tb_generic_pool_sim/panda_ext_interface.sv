`ifndef __PANDA_EXT_IF_H
`define __PANDA_EXT_IF_H

interface generic_pool_sim_cfg_if(
	input bit clk,
	input bit rst_n
);
	
	// 控制信号
	logic en_adapter; // 使能适配器
	logic en_post_mac; // 使能后乘加处理
	
	// 运行时参数
	// [计算参数]
	logic[1:0] pool_mode; // 池化模式
	logic[1:0] calfmt; // 运算数据格式
	logic[2:0] pool_horizontal_stride; // 池化水平步长 - 1
	logic[2:0] pool_vertical_stride; // 池化垂直步长 - 1
	logic[7:0] pool_window_w; // 池化窗口宽度 - 1
	logic[7:0] pool_window_h; // 池化窗口高度 - 1
	// [后乘加处理参数]
	logic[4:0] post_mac_fixed_point_quat_accrc; // 定点数量化精度
	logic post_mac_is_a_eq_1; // 参数A的实际值为1(标志)
	logic post_mac_is_b_eq_0; // 参数B的实际值为0(标志)
	logic[31:0] post_mac_param_a; // 参数A
	logic[31:0] post_mac_param_b; // 参数B
	// [上采样参数]
	logic[7:0] upsample_horizontal_n; // 上采样水平复制量 - 1
	logic[7:0] upsample_vertical_n; // 上采样垂直复制量 - 1
	logic non_zero_const_padding_mode; // 是否处于非0常量填充模式
	logic[15:0] const_to_fill; // 待填充的常量
	// [特征图参数]
	logic[31:0] ifmap_baseaddr; // 输入特征图基地址
	logic[31:0] ofmap_baseaddr; // 输出特征图基地址
	logic is_16bit_data; // 是否16位(输入)特征图数据
	logic[15:0] ifmap_w; // 输入特征图宽度 - 1
	logic[15:0] ifmap_h; // 输入特征图高度 - 1
	logic[23:0] ifmap_size; // 输入特征图大小 - 1
	logic[15:0] ext_ifmap_w; // 扩展输入特征图宽度 - 1
	logic[15:0] ext_ifmap_h; // 扩展输入特征图高度 - 1
	logic[15:0] fmap_chn_n; // 通道数 - 1
	logic[2:0] external_padding_left; // 左部外填充数
	logic[2:0] external_padding_top; // 上部外填充数
	logic[15:0] ofmap_w; // 输出特征图宽度 - 1
	logic[15:0] ofmap_h; // 输出特征图高度 - 1
	logic[1:0] ofmap_data_type; // 输出特征图数据大小类型
	// [特征图缓存参数]
	logic[3:0] fmbufcoln; // 每个表面行的表面个数类型
	logic[9:0] fmbufrown; // 可缓存的表面行数 - 1
	// [中间结果缓存参数]
	logic[3:0] mid_res_buf_row_n_bufferable; // 可缓存行数 - 1
	
	clocking master_cb @(posedge clk);
		output en_adapter;
		output en_post_mac;
		
		output pool_mode;
		output calfmt;
		output pool_horizontal_stride;
		output pool_vertical_stride;
		output pool_window_w;
		output pool_window_h;
		output post_mac_fixed_point_quat_accrc;
		output post_mac_is_a_eq_1;
		output post_mac_is_b_eq_0;
		output post_mac_param_a;
		output post_mac_param_b;
		output upsample_horizontal_n;
		output upsample_vertical_n;
		output non_zero_const_padding_mode;
		output const_to_fill;
		output ifmap_baseaddr;
		output ofmap_baseaddr;
		output is_16bit_data;
		output ifmap_w;
		output ifmap_h;
		output ifmap_size;
		output ext_ifmap_w;
		output ext_ifmap_h;
		output fmap_chn_n;
		output external_padding_left;
		output external_padding_top;
		output ofmap_w;
		output ofmap_h;
		output ofmap_data_type;
		output fmbufcoln;
		output fmbufrown;
		output mid_res_buf_row_n_bufferable;
	endclocking
	
endinterface

`endif
