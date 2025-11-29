`ifndef __PANDA_EXT_CFG_H
`define __PANDA_EXT_CFG_H

class SurfaceCfg extends tue_configuration;
	
	rand int unsigned len_foreach_sfc; // 每个表面的数据个数
	rand bit is_format_16; // 是否16位数据
	
	constraint c_valid_len_foreach_sfc{
		len_foreach_sfc inside {[1:32]};
	}
	
	constraint c_fixed_format_16{
		is_format_16 == 1'b1;
	}
	
	`tue_object_default_constructor(SurfaceCfg)
	
	`uvm_object_utils_begin(SurfaceCfg)
		`uvm_field_int(len_foreach_sfc, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(is_format_16, UVM_DEFAULT | UVM_BIN)
	`uvm_object_utils_end
	
endclass

class SurfaceGrpCfg extends SurfaceCfg;
	
	rand int unsigned sfc_n; // 表面个数
	
	constraint c_valid_sfc_n{
		sfc_n >= 1;
	}
	
	`tue_object_default_constructor(SurfaceGrpCfg)
	
	`uvm_object_utils_begin(SurfaceGrpCfg)
		`uvm_field_int(sfc_n, UVM_DEFAULT | UVM_DEC)
	`uvm_object_utils_end
	
endclass

typedef SurfaceGrpCfg FmapRowCfg;
typedef SurfaceGrpCfg KernalWgtBlkCfg;

class KernalCGrpCfg extends SurfaceCfg;
	
	rand int unsigned sfc_n_foreach_wgt_blk; // 每个权重块的表面个数
	rand kernal_sz_t kernal_shape; // 卷积核形状
	
	constraint c_valid_sfc_n_foreach_wgt_blk{
		sfc_n_foreach_wgt_blk >= 1;
	}
	
	`tue_object_default_constructor(KernalCGrpCfg)
	
	`uvm_object_utils_begin(KernalCGrpCfg)
		`uvm_field_int(sfc_n_foreach_wgt_blk, UVM_DEFAULT | UVM_DEC)
		`uvm_field_enum(kernal_sz_t, kernal_shape, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

class FmapCfg extends tue_configuration;
	
	rand int unsigned fmap_mem_baseaddr; // 特征图在存储映射中的基地址
	rand int unsigned ofmap_baseaddr; // 输出特征图基地址
	rand int unsigned fmap_w; // 特征图宽度
	rand int unsigned fmap_h; // 特征图高度
	rand int unsigned fmap_c; // 特征图通道数
	
	rand ofmap_data_type_t ofmap_data_type; // 输出特征图数据大小类型
	
	constraint c_default_cst{
		fmap_w >= 1;
		fmap_h >= 1;
		fmap_c >= 1;
	}
	
	`tue_object_default_constructor(FmapCfg)
	
	`uvm_object_utils_begin(FmapCfg)
		`uvm_field_int(fmap_mem_baseaddr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(ofmap_baseaddr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(fmap_w, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(fmap_h, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(fmap_c, UVM_DEFAULT | UVM_DEC)
		`uvm_field_enum(ofmap_data_type_t, ofmap_data_type, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

class KernalCfg extends tue_configuration;
	
	rand int unsigned kernal_mem_baseaddr; // 卷积核权重在存储映射中的基地址
	
	rand kernal_sz_t kernal_shape; // 卷积核形状
	rand int unsigned kernal_num_n; // 核数
	rand int unsigned kernal_chn_n; // 通道数
	
	constraint c_default_cst{
		kernal_num_n >= 1;
		kernal_chn_n >= 1;
	}
	
	`tue_object_default_constructor(KernalCfg)
	
	`uvm_object_utils_begin(KernalCfg)
		`uvm_field_int(kernal_mem_baseaddr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_enum(kernal_sz_t, kernal_shape, UVM_DEFAULT)
		`uvm_field_int(kernal_num_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(kernal_chn_n, UVM_DEFAULT | UVM_DEC)
	`uvm_object_utils_end
	
endclass

class ConvCalCfg extends tue_configuration;
	
	rand int unsigned atomic_c; // 通道并行数
	rand int unsigned atomic_k; // 核并行数
	
	rand calfmt_t calfmt; // 运算数据格式
	rand int unsigned conv_vertical_stride; // 卷积垂直步长
	rand int unsigned conv_horizontal_stride; // 卷积水平步长
	rand int unsigned cal_round; // 计算轮次
	
	rand bit is_grp_conv_mode; // 是否处于组卷积模式
	rand int unsigned group_n; // 组卷积分组数
	
	rand int unsigned external_padding_left; // 左部外填充数
	rand int unsigned external_padding_right; // 右部外填充数
	rand int unsigned external_padding_top; // 上部外填充数
	rand int unsigned external_padding_bottom; // 下部外填充数
	rand int unsigned inner_padding_left_right; // 左右内填充数
	rand int unsigned inner_padding_top_bottom; // 上下内填充数
	
	rand int unsigned kernal_dilation_n; // 卷积核膨胀量
	rand int unsigned max_wgtblk_w; // 权重块最大宽度
	
	constraint c_default_cst{
		atomic_c inside {1, 2, 4, 8, 16, 32};
		atomic_k inside {1, 2, 4, 8, 16, 32};
		
		conv_vertical_stride >= 1;
		conv_horizontal_stride >= 1;
		cal_round >= 1;
		group_n >= 1;
		
		max_wgtblk_w >= 1;
	}
	
	virtual function void do_print(uvm_printer printer);
		super.do_print(printer);
		
		printer.print_int("is_grp_conv_mode", this.is_grp_conv_mode, 1, UVM_BIN);
		
		if(this.is_grp_conv_mode)
			printer.print_int("group_n", this.group_n, 32, UVM_DEC);
	endfunction
	
	`tue_object_default_constructor(ConvCalCfg)
	
	`uvm_object_utils_begin(ConvCalCfg)
		`uvm_field_int(atomic_c, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(atomic_k, UVM_DEFAULT | UVM_DEC)
		
		`uvm_field_enum(calfmt_t, calfmt, UVM_DEFAULT)
		`uvm_field_int(conv_vertical_stride, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(conv_horizontal_stride, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(cal_round, UVM_DEFAULT | UVM_DEC)
		
		`uvm_field_int(is_grp_conv_mode, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(group_n, UVM_DEFAULT | UVM_NOPRINT)
		
		`uvm_field_int(external_padding_left, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(external_padding_right, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(external_padding_top, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(external_padding_bottom, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(inner_padding_left_right, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(inner_padding_top_bottom, UVM_DEFAULT | UVM_DEC)
		
		`uvm_field_int(kernal_dilation_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(max_wgtblk_w, UVM_DEFAULT | UVM_DEC)
	`uvm_object_utils_end
	
endclass

class BufferCfg extends tue_configuration;
	
	rand int unsigned stream_data_width; // DMA数据流的位宽
	rand int unsigned fnl_res_data_width; // 最终结果数据流的位宽
	
	rand int unsigned fmbufbankn; // 分配给特征图缓存的Bank数
	rand fmbuf_coln_t fmbufcoln; // 每个表面行的表面个数类型
	rand int unsigned fmbufrown; // 可缓存的表面行数
	
	rand wgtblk_sfc_n_t sfc_n_each_wgtblk; // 每个权重块的表面个数的类型
	rand int unsigned kbufgrpn; // 可缓存的通道组数
	
	rand int unsigned mid_res_item_n_foreach_row; // 每个输出特征图表面行的中间结果项数
	rand int unsigned mid_res_buf_row_n_bufferable; // 可缓存中间结果行数
	
	constraint c_default_cst{
		stream_data_width inside {32, 64, 128, 256};
		fnl_res_data_width inside {32, 64, 128, 256};
		
		fmbufbankn >= 1;
		fmbufrown >= 2;
		kbufgrpn >= 3;
		mid_res_item_n_foreach_row >= 1;
		mid_res_buf_row_n_bufferable >= 2;
	}
	
	`tue_object_default_constructor(BufferCfg)
	
	`uvm_object_utils_begin(BufferCfg)
		`uvm_field_int(stream_data_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(fnl_res_data_width, UVM_DEFAULT | UVM_DEC)
		
		`uvm_field_int(fmbufbankn, UVM_DEFAULT | UVM_DEC)
		`uvm_field_enum(fmbuf_coln_t, fmbufcoln, UVM_DEFAULT)
		`uvm_field_int(fmbufrown, UVM_DEFAULT | UVM_DEC)
		
		`uvm_field_enum(wgtblk_sfc_n_t, sfc_n_each_wgtblk, UVM_DEFAULT)
		`uvm_field_int(kbufgrpn, UVM_DEFAULT | UVM_DEC)
		
		`uvm_field_int(mid_res_item_n_foreach_row, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(mid_res_buf_row_n_bufferable, UVM_DEFAULT | UVM_DEC)
	`uvm_object_utils_end
	
endclass

class FmapBuilderCfg extends tue_configuration;
	
	rand bit has_vld_actual_sfc_rid; // 实际表面行号有效
	
	rand int unsigned fmap_mem_baseaddr; // 特征图在存储映射中的基地址
	rand int unsigned total_fmrow_n; // 待测特征图表面行总数
	rand int unsigned fmrow_len; // 待测特征图列数
	rand int unsigned sfc_data_n_foreach_fmrow[]; // 各个特征图表面行上表面的有效数据个数
	rand int unsigned actual_sfc_rid_foreach_fmrow[]; // 各个特征图表面行的实际表面行号
	
	int unsigned abs_baseaddr_foreach_fmrow[]; // 各个特征图表面行的绝对基地址
	
	constraint c_default_cst{
		solve total_fmrow_n before sfc_data_n_foreach_fmrow;
		solve total_fmrow_n before actual_sfc_rid_foreach_fmrow;
		
		total_fmrow_n >= 1;
		fmrow_len >= 1;
		
		sfc_data_n_foreach_fmrow.size() == total_fmrow_n;
		actual_sfc_rid_foreach_fmrow.size() == total_fmrow_n;
		
		unique {actual_sfc_rid_foreach_fmrow};
	}
	
	function void post_randomize();
		super.post_randomize();
		
		this.abs_baseaddr_foreach_fmrow = new[this.total_fmrow_n];
	endfunction
	
	function void from_cfg(FmapCfg fmap_cfg, ConvCalCfg cal_cfg);
		int unsigned rid; // 表面行号
		
		this.has_vld_actual_sfc_rid = 1'b0;
		
		this.fmap_mem_baseaddr = fmap_cfg.fmap_mem_baseaddr;
		this.fmrow_len = fmap_cfg.fmap_w;
		
		if(cal_cfg.is_grp_conv_mode)
		begin
			int unsigned n_foreach_group; // 每组的通道数
			int unsigned cgrpn_foreach_group; // 每组的通道组数
			
			n_foreach_group = fmap_cfg.fmap_c / cal_cfg.group_n;
			cgrpn_foreach_group = (n_foreach_group / cal_cfg.atomic_c) + ((n_foreach_group % cal_cfg.atomic_c) ? 1:0);
			
			this.total_fmrow_n = fmap_cfg.fmap_h * cgrpn_foreach_group * cal_cfg.group_n;
			
			this.sfc_data_n_foreach_fmrow = new[this.total_fmrow_n];
			this.actual_sfc_rid_foreach_fmrow = new[this.total_fmrow_n];
			this.abs_baseaddr_foreach_fmrow = new[this.total_fmrow_n];
			
			rid = 0;
			
			for(int unsigned g = 0;g < cal_cfg.group_n;g++)
			begin
				for(int unsigned c = 0;c < cgrpn_foreach_group;c++)
				begin
					for(int unsigned y = 0;y < fmap_cfg.fmap_h;y++)
					begin
						this.sfc_data_n_foreach_fmrow[rid] = 
							(c == (cgrpn_foreach_group - 1)) ? 
								((n_foreach_group % cal_cfg.atomic_c) ? (n_foreach_group % cal_cfg.atomic_c):cal_cfg.atomic_c):
								cal_cfg.atomic_c;
						
						rid++;
					end
				end
			end
		end
		else
		begin
			int unsigned cgrpn; // 总通道组数
			
			cgrpn = (fmap_cfg.fmap_c / cal_cfg.atomic_c) + ((fmap_cfg.fmap_c % cal_cfg.atomic_c) ? 1:0);
			
			this.total_fmrow_n = fmap_cfg.fmap_h * cgrpn;
			
			this.sfc_data_n_foreach_fmrow = new[this.total_fmrow_n];
			this.actual_sfc_rid_foreach_fmrow = new[this.total_fmrow_n];
			this.abs_baseaddr_foreach_fmrow = new[this.total_fmrow_n];
			
			for(int unsigned c = 0;c < cgrpn;c++)
			begin
				for(int unsigned y = 0;y < fmap_cfg.fmap_h;y++)
				begin
					this.sfc_data_n_foreach_fmrow[rid] = 
						(c == (cgrpn - 1)) ? 
							((fmap_cfg.fmap_c % cal_cfg.atomic_c) ? (fmap_cfg.fmap_c % cal_cfg.atomic_c):cal_cfg.atomic_c):
							cal_cfg.atomic_c;
					
					rid++;
				end
			end
		end
	endfunction
	
	`tue_object_default_constructor(FmapBuilderCfg)
	
	`uvm_object_utils_begin(FmapBuilderCfg)
		`uvm_field_int(fmap_mem_baseaddr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(total_fmrow_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(fmrow_len, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(sfc_data_n_foreach_fmrow, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(actual_sfc_rid_foreach_fmrow, UVM_DEFAULT | UVM_DEC)
		
		`uvm_field_array_int(abs_baseaddr_foreach_fmrow, UVM_DEFAULT | UVM_HEX)
	`uvm_object_utils_end
	
endclass

class KernalSetBuilderCfg extends tue_configuration;
	
	rand int unsigned kernal_mem_baseaddr; // 卷积核权重在存储映射中的基地址
	rand kernal_sz_t kernal_shape; // 卷积核形状
	rand int unsigned total_kernal_set_n; // 核组个数
	rand int unsigned total_cgrp_n; // 通道组总数
	rand int unsigned cgrpn_foreach_kernal_set[]; // 各个核组的通道组数
	rand int unsigned wgtblk_w_foreach_kernal_set[]; // 各个核组的权重块宽度
	rand int unsigned depth_foreach_kernal_cgrp[]; // 各个通道组的表面深度
	
	int unsigned abs_baseaddr_foreach_cgrp[]; // 各个通道组的绝对基地址
	
	constraint c_default_cst{
		solve total_kernal_set_n, total_cgrp_n before cgrpn_foreach_kernal_set;
		solve total_kernal_set_n before wgtblk_w_foreach_kernal_set;
		
		total_kernal_set_n >= 1;
		total_cgrp_n >= total_kernal_set_n;
		
		cgrpn_foreach_kernal_set.size() == total_kernal_set_n;
		wgtblk_w_foreach_kernal_set.size() == total_kernal_set_n;
		depth_foreach_kernal_cgrp.size() == total_cgrp_n;
		
		cgrpn_foreach_kernal_set.sum() == total_cgrp_n;
		
		foreach(cgrpn_foreach_kernal_set[i]){
			cgrpn_foreach_kernal_set[i] >= 1;
		}
		
		foreach(wgtblk_w_foreach_kernal_set[i]){
			wgtblk_w_foreach_kernal_set[i] >= 1;
		}
		
		foreach(depth_foreach_kernal_cgrp[i]){
			depth_foreach_kernal_cgrp[i] >= 1;
		}
	}
	
	function void post_randomize();
		super.post_randomize();
		
		this.abs_baseaddr_foreach_cgrp = new[this.total_cgrp_n];
	endfunction
	
	function void from_cfg(KernalCfg kernal_cfg, ConvCalCfg cal_cfg);
		int unsigned c_foreach_kernal_set; // 每个核组的通道数
		int unsigned cgrpn; // 每个核组的通道组数
		int unsigned cgrpid; // 通道组号
		
		cgrpid = 0;
		
		this.kernal_mem_baseaddr = kernal_cfg.kernal_mem_baseaddr;
		this.kernal_shape = kernal_cfg.kernal_shape;
		
		if(cal_cfg.is_grp_conv_mode)
		begin
			this.total_kernal_set_n = cal_cfg.group_n;
			
			c_foreach_kernal_set = kernal_cfg.kernal_chn_n / cal_cfg.group_n;
		end
		else
		begin
			this.total_kernal_set_n = 
				(kernal_cfg.kernal_num_n / cal_cfg.max_wgtblk_w) + ((kernal_cfg.kernal_num_n % cal_cfg.max_wgtblk_w) ? 1:0);
			
			c_foreach_kernal_set = kernal_cfg.kernal_chn_n;
		end
		
		cgrpn = (c_foreach_kernal_set / cal_cfg.atomic_c) + ((c_foreach_kernal_set % cal_cfg.atomic_c) ? 1:0);
		
		this.total_cgrp_n = this.total_kernal_set_n * cgrpn;
		
		this.cgrpn_foreach_kernal_set = new[this.total_kernal_set_n];
		this.wgtblk_w_foreach_kernal_set = new[this.total_kernal_set_n];
		this.depth_foreach_kernal_cgrp = new[this.total_cgrp_n];
		
		foreach(this.cgrpn_foreach_kernal_set[i])
		begin
			this.cgrpn_foreach_kernal_set[i] = cgrpn;
		end
		
		if(cal_cfg.is_grp_conv_mode)
		begin
			foreach(this.wgtblk_w_foreach_kernal_set[i])
			begin
				this.wgtblk_w_foreach_kernal_set[i] = kernal_cfg.kernal_num_n / cal_cfg.group_n;
			end
		end
		else
		begin
			for(int unsigned i = 0;i < this.total_kernal_set_n;i++)
			begin
				this.wgtblk_w_foreach_kernal_set[i] = 
					(i == (this.total_kernal_set_n - 1)) ? 
						(
							(kernal_cfg.kernal_num_n % cal_cfg.max_wgtblk_w) ? 
								(kernal_cfg.kernal_num_n % cal_cfg.max_wgtblk_w):
								cal_cfg.max_wgtblk_w
						):
						cal_cfg.max_wgtblk_w;
			end
		end
		
		for(int unsigned k = 0;k < this.total_kernal_set_n;k++)
		begin
			for(int unsigned c = 0;c < cgrpn;c++)
			begin
				this.depth_foreach_kernal_cgrp[cgrpid] = 
					(c == (cgrpn - 1)) ? 
						(
							(c_foreach_kernal_set % cal_cfg.atomic_c) ? 
								(c_foreach_kernal_set % cal_cfg.atomic_c):
								cal_cfg.atomic_c
						):
						cal_cfg.atomic_c;
				
				cgrpid++;
			end
		end
	endfunction
	
	`tue_object_default_constructor(KernalSetBuilderCfg)
	
	`uvm_object_utils_begin(KernalSetBuilderCfg)
		`uvm_field_int(kernal_mem_baseaddr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_enum(kernal_sz_t, kernal_shape, UVM_DEFAULT)
		`uvm_field_int(total_kernal_set_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(total_cgrp_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(cgrpn_foreach_kernal_set, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(wgtblk_w_foreach_kernal_set, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(depth_foreach_kernal_cgrp, UVM_DEFAULT | UVM_DEC)
		
		`uvm_field_array_int(abs_baseaddr_foreach_cgrp, UVM_DEFAULT | UVM_HEX)
	`uvm_object_utils_end
	
endclass

`endif
