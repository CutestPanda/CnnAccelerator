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

class ConvDataHubCfg extends tue_configuration;
	
	rand int unsigned stream_data_width; // DMA数据流的位宽
	rand int unsigned atomic_c; // 通道并行数
	rand int unsigned atomic_k; // 核并行数
	
	rand fmbuf_coln_t fmbufcoln; // 每个表面行区域可存储的表面个数
	rand int unsigned fmbufrown; // 可缓存的表面行数
	
	rand bit grp_conv_buf_mode; // 是否处于组卷积缓存模式
	rand kernal_sz_t kernal_shape; // 卷积核形状
	rand wgtblk_sfc_n_t sfc_n_each_wgtblk; // 每个权重块区域可存储的表面个数
	rand int unsigned kbufgrpn; // 可缓存的通道组数
	
	rand int unsigned fmap_mem_baseaddr; // 特征图在存储映射中的基地址
	rand int unsigned total_fmrow_n; // 待测特征图表面行总数
	rand int unsigned fmrow_len; // 待测特征图列数
	rand int unsigned sfc_data_n_foreach_fmrow[]; // 各个特征图表面行上表面的有效数据个数
	rand bit[11:0] actual_sfc_rid_foreach_fmrow[]; // 各个特征图表面行的实际表面行号
	int unsigned abs_baseaddr_foreach_fmrow[]; // 各个特征图表面行的绝对基地址
	
	rand int unsigned kernal_mem_baseaddr; // 卷积核权重在存储映射中的基地址
	rand int unsigned total_kernal_set_n; // 核组个数
	rand int unsigned total_cgrp_n; // 通道组总数
	rand int unsigned cgrpn_foreach_kernal_set[]; // 各个核组的通道组数
	rand int unsigned wgtblk_w_foreach_kernal_set[]; // 各个核组的权重块宽度
	rand int unsigned depth_foreach_kernal_cgrp[]; // 各个通道组的表面深度
	int unsigned abs_baseaddr_foreach_cgrp[]; // 各个通道组的绝对基地址
	
	static function int unsigned kernal_sz_t_to_int(kernal_sz_t sz);
		case(sz)
			KBUFGRPSZ_1x1: return 1 * 1;
			KBUFGRPSZ_3x3: return 3 * 3;
			KBUFGRPSZ_5x5: return 5 * 5;
			KBUFGRPSZ_7x7: return 7 * 7;
			KBUFGRPSZ_9x9: return 9 * 9;
			KBUFGRPSZ_11x11: return 11 * 11;
		endcase
	endfunction
	
	static function int unsigned kernal_wgtblk_sfc_n_t_to_int(wgtblk_sfc_n_t sfc_n);
		case(sfc_n)
			WGTBLK_SFC_N_1: return 1;
			WGTBLK_SFC_N_2: return 2;
			WGTBLK_SFC_N_4: return 4;
			WGTBLK_SFC_N_8: return 8;
			WGTBLK_SFC_N_16: return 16;
			WGTBLK_SFC_N_32: return 32;
			WGTBLK_SFC_N_64: return 64;
			WGTBLK_SFC_N_128: return 128;
		endcase
	endfunction
	
	function void post_randomize();
		int unsigned cgrp_i;
		
		super.post_randomize();
		
		this.abs_baseaddr_foreach_fmrow = new[this.total_fmrow_n];
		this.abs_baseaddr_foreach_cgrp = new[this.total_cgrp_n];
		
		foreach(this.abs_baseaddr_foreach_fmrow[i])
		begin
			if(i == 0)
			begin
				this.abs_baseaddr_foreach_fmrow[i] = this.fmap_mem_baseaddr;
			end
			else
			begin
				this.abs_baseaddr_foreach_fmrow[i] = this.abs_baseaddr_foreach_fmrow[i-1] + 
					this.fmrow_len * this.sfc_data_n_foreach_fmrow[i-1] * 
					this.atomic_c * 2;
			end
		end
		
		cgrp_i = 0;
		
		for(int unsigned k = 0;k < this.total_kernal_set_n;k++)
		begin
			int unsigned cgrp_n;
			
			cgrp_n = this.cgrpn_foreach_kernal_set[k];
			
			for(int unsigned c = 0;c < cgrp_n;c++)
			begin
				if(cgrp_i == 0)
				begin
					this.abs_baseaddr_foreach_cgrp[cgrp_i] = this.kernal_mem_baseaddr;
				end
				else
				begin
					this.abs_baseaddr_foreach_cgrp[cgrp_i] = this.abs_baseaddr_foreach_cgrp[cgrp_i - 1] + 
						ConvDataHubCfg::kernal_sz_t_to_int(this.kernal_shape) * 
						this.wgtblk_w_foreach_kernal_set[k] * 
						this.atomic_c * 2;
				end
				
				cgrp_i++;
			end
		end
	endfunction
	
	constraint c_valid_stream_data_width{
		stream_data_width inside {32, 64, 128, 256};
	}
	
	constraint c_valid_atomic_x{
		atomic_c inside {1, 2, 4, 8, 16, 32};
		atomic_k inside {1, 2, 4, 8, 16, 32};
	}
	
	constraint c_valid_fmbufrown{
		fmbufrown >= 1;
	}
	
	constraint c_valid_kbufgrpn{
		kbufgrpn >= 1;
	}
	
	constraint c_valid_x_mem_baseaddr{
		(fmap_mem_baseaddr % (atomic_c * 2)) == 0;
		(fmap_mem_baseaddr % (stream_data_width / 8)) == 0;
		
		(kernal_mem_baseaddr % (atomic_c * 2)) == 0;
		(kernal_mem_baseaddr % (stream_data_width / 8)) == 0;
	}
	
	constraint c_valid_total_fmrow_n{
		total_fmrow_n >= 1;
	}
	
	constraint c_valid_fmrow_len{
		fmrow_len >= 1;
		
		if(fmbufcoln == COLN_4){
			fmrow_len <= 4;
		}else if(fmbufcoln == COLN_8){
			fmrow_len <= 8;
		}else if(fmbufcoln == COLN_16){
			fmrow_len <= 16;
		}else if(fmbufcoln == COLN_32){
			fmrow_len <= 32;
		}else if(fmbufcoln == COLN_64){
			fmrow_len <= 64;
		}else if(fmbufcoln == COLN_128){
			fmrow_len <= 128;
		}else if(fmbufcoln == COLN_256){
			fmrow_len <= 256;
		}else if(fmbufcoln == COLN_512){
			fmrow_len <= 512;
		}else if(fmbufcoln == COLN_1024){
			fmrow_len <= 1024;
		}else if(fmbufcoln == COLN_2048){
			fmrow_len <= 2048;
		}else{
			fmrow_len <= 4096;
		}
	}
	
	constraint c_valid_sfc_data_n_foreach_fmrow{
		solve total_fmrow_n, atomic_c before sfc_data_n_foreach_fmrow;
		
		sfc_data_n_foreach_fmrow.size() == total_fmrow_n;
		
		foreach(sfc_data_n_foreach_fmrow[i]){
			sfc_data_n_foreach_fmrow[i] inside {[1:atomic_c]};
		}
	}
	
	constraint c_valid_actual_sfc_rid_foreach_fmrow{
		solve total_fmrow_n before actual_sfc_rid_foreach_fmrow;
		
		actual_sfc_rid_foreach_fmrow.size() == total_fmrow_n;
		
		unique {actual_sfc_rid_foreach_fmrow};
	}
	
	constraint c_valid_total_kernal_set_n{
		total_kernal_set_n >= 1;
	}
	
	constraint c_valid_total_cgrp_n{
		total_cgrp_n >= total_kernal_set_n;
	}
	
	constraint c_valid_cgrpn_foreach_kernal_set{
		solve total_kernal_set_n, total_cgrp_n before cgrpn_foreach_kernal_set;
		
		cgrpn_foreach_kernal_set.size() == total_kernal_set_n;
		cgrpn_foreach_kernal_set.sum() == total_cgrp_n;
		
		foreach(cgrpn_foreach_kernal_set[i]){
			cgrpn_foreach_kernal_set[i] >= 1;
		}
	}
	
	constraint c_valid_wgtblk_w_foreach_kernal_set{
		solve total_kernal_set_n before wgtblk_w_foreach_kernal_set;
		
		wgtblk_w_foreach_kernal_set.size() == total_kernal_set_n;
		
		foreach(wgtblk_w_foreach_kernal_set[i]){
			wgtblk_w_foreach_kernal_set[i] >= 1;
			
			if(grp_conv_buf_mode){
				wgtblk_w_foreach_kernal_set[i] <= ConvDataHubCfg::kernal_wgtblk_sfc_n_t_to_int(sfc_n_each_wgtblk);
			}else{
				wgtblk_w_foreach_kernal_set[i] <= atomic_k;
			}
		}
	}
	
	constraint c_valid_depth_foreach_kernal_cgrp{
		depth_foreach_kernal_cgrp.size() == total_cgrp_n;
		
		foreach(depth_foreach_kernal_cgrp[i]){
			depth_foreach_kernal_cgrp[i] inside {[1:atomic_c]};
		}
	}
	
	`tue_object_default_constructor(ConvDataHubCfg)
	
	`uvm_object_utils_begin(ConvDataHubCfg)
		`uvm_field_int(stream_data_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(atomic_c, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(atomic_k, UVM_DEFAULT | UVM_DEC)
		`uvm_field_enum(fmbuf_coln_t, fmbufcoln, UVM_DEFAULT)
		`uvm_field_int(fmbufrown, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(grp_conv_buf_mode, UVM_DEFAULT | UVM_BIN)
		`uvm_field_enum(kernal_sz_t, kernal_shape, UVM_DEFAULT)
		`uvm_field_enum(wgtblk_sfc_n_t, sfc_n_each_wgtblk, UVM_DEFAULT)
		`uvm_field_int(kbufgrpn, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(fmap_mem_baseaddr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(total_fmrow_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(fmrow_len, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(sfc_data_n_foreach_fmrow, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(actual_sfc_rid_foreach_fmrow, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(abs_baseaddr_foreach_fmrow, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(kernal_mem_baseaddr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(total_kernal_set_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(total_cgrp_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(cgrpn_foreach_kernal_set, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(wgtblk_w_foreach_kernal_set, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(depth_foreach_kernal_cgrp, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(abs_baseaddr_foreach_cgrp, UVM_DEFAULT | UVM_HEX)
	`uvm_object_utils_end
	
endclass

`endif
