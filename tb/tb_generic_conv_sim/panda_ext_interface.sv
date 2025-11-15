`ifndef __PANDA_EXT_IF_H
`define __PANDA_EXT_IF_H

interface generic_conv_sim_cfg_if(
	input bit clk,
	input bit rst_n
);
	
	// 使能信号
	logic en_mac_array; // 使能乘加阵列
	logic en_packer; // 使能打包器
	
	// 运行时参数
	// [计算参数]
	logic[1:0] calfmt; // 运算数据格式
	logic[2:0] conv_vertical_stride; // 卷积垂直步长 - 1
	logic[2:0] conv_horizontal_stride; // 卷积水平步长 - 1
	logic[3:0] cal_round; // 计算轮次 - 1
	// [组卷积模式]
	logic is_grp_conv_mode; // 是否处于组卷积模式
	logic[15:0] group_n; // 分组数 - 1
	logic[15:0] n_foreach_group; // 每组的通道数/核数 - 1
	logic[31:0] data_size_foreach_group; // (特征图)每组的数据量
	// [特征图参数]
	logic[31:0] fmap_baseaddr; // 特征图数据基地址
	logic[15:0] ifmap_w; // 输入特征图宽度 - 1
	logic[23:0] ifmap_size; // 输入特征图大小 - 1
	logic[15:0] fmap_chn_n; // 特征图通道数 - 1
	logic[15:0] fmap_ext_i_bottom; // 扩展后特征图的垂直边界
	logic[2:0] external_padding_left; // 左部外填充数
	logic[2:0] external_padding_top; // 上部外填充数
	logic[2:0] inner_padding_left_right; // 左右内填充数
	logic[2:0] inner_padding_top_bottom; // 上下内填充数
	logic[15:0] ofmap_w; // 输出特征图宽度 - 1
	logic[15:0] ofmap_h; // 输出特征图高度 - 1
	// [卷积核参数]
	logic[31:0] kernal_wgt_baseaddr; // 卷积核权重基地址
	logic[2:0] kernal_shape; // 卷积核形状
	logic[3:0] kernal_dilation_hzt_n; // 水平膨胀量
	logic[4:0] kernal_w_dilated; // (膨胀后)卷积核宽度 - 1
	logic[3:0] kernal_dilation_vtc_n; // 垂直膨胀量
	logic[4:0] kernal_h_dilated; // (膨胀后)卷积核高度 - 1
	logic[15:0] kernal_chn_n; // 通道数 - 1
	logic[15:0] cgrpn_foreach_kernal_set; // 每个核组的通道组数 - 1
	logic[15:0] kernal_num_n; // 核数 - 1
	logic[15:0] kernal_set_n; // 核组个数 - 1
	logic[5:0] max_wgtblk_w; // 权重块最大宽度
	// [缓存参数]
	logic[7:0] fmbufbankn; // 分配给特征图缓存的Bank数
	logic[3:0] fmbufcoln; // 每个表面行的表面个数类型
	logic[9:0] fmbufrown; // 可缓存的表面行数 - 1
	logic[2:0] kbufgrpsz; // 每个通道组的权重块个数的类型
	logic[2:0] sfc_n_each_wgtblk; // 每个权重块的表面个数的类型
	logic[7:0] kbufgrpn; // 可缓存的通道组数 - 1
	logic[15:0] mid_res_item_n_foreach_row; // 每个输出特征图表面行的中间结果项数 - 1
	logic[3:0] mid_res_buf_row_n_bufferable; // 可缓存行数 - 1
	
	clocking master_cb @(posedge clk);
		output en_mac_array;
		output en_packer;
		
		output calfmt;
		output conv_vertical_stride;
		output conv_horizontal_stride;
		output cal_round;
		output is_grp_conv_mode;
		output group_n;
		output n_foreach_group;
		output data_size_foreach_group;
		output fmap_baseaddr;
		output ifmap_w;
		output ifmap_size;
		output fmap_chn_n;
		output fmap_ext_i_bottom;
		output external_padding_left;
		output external_padding_top;
		output inner_padding_left_right;
		output inner_padding_top_bottom;
		output ofmap_w;
		output ofmap_h;
		output kernal_wgt_baseaddr;
		output kernal_shape;
		output kernal_dilation_hzt_n;
		output kernal_w_dilated;
		output kernal_dilation_vtc_n;
		output kernal_h_dilated;
		output kernal_chn_n;
		output cgrpn_foreach_kernal_set;
		output kernal_num_n;
		output kernal_set_n;
		output max_wgtblk_w;
		output fmbufbankn;
		output fmbufcoln;
		output fmbufrown;
		output kbufgrpsz;
		output sfc_n_each_wgtblk;
		output kbufgrpn;
		output mid_res_item_n_foreach_row;
		output mid_res_buf_row_n_bufferable;
	endclocking
	
endinterface

`endif
