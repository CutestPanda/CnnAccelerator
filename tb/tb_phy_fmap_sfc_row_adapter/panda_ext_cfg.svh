`ifndef __PANDA_EXT_CFG_H
`define __PANDA_EXT_CFG_H

class PhyFmapSfcRowAdapterCfg extends tue_configuration;
	
	rand int atomic_c; // 通道并行数
	
	rand int conv_horizontal_stride; // 卷积水平步长
	
	rand int external_padding_left; // 左部外填充数
	rand int external_padding_right; // 右部外填充数
	rand int inner_padding_left_right; // 左右内填充数
	rand int ifmap_w; // 输入特征图宽度
	int ofmap_w; // 输出特征图宽度
	
	rand int kernal_dilation_hzt_n; // 水平膨胀量
	rand int kernal_w; // (膨胀前)卷积核宽度
	int kernal_w_dilated; // (膨胀后)卷积核宽度
	
	constraint c_default_cst{
		atomic_c inside {1, 2, 4, 8, 16, 32};
		
		conv_horizontal_stride inside {[1:8]};
		
		external_padding_left inside {[0:7]};
		external_padding_right inside {[0:7]};
		inner_padding_left_right inside {[0:7]};
		ifmap_w >= 1;
		
		kernal_dilation_hzt_n inside {[0:15]};
		kernal_w inside {1, 3, 5, 7, 9, 11};
		
		(((external_padding_left + ifmap_w + (ifmap_w - 1) * 
			inner_padding_left_right + external_padding_right) - 
			(kernal_w + (kernal_w - 1) * kernal_dilation_hzt_n)
		) % conv_horizontal_stride) == 0;
	}
	
	function void post_randomize();
		super.post_randomize();
		
		this.kernal_w_dilated = this.kernal_w + (this.kernal_w - 1) * this.kernal_dilation_hzt_n;
		this.ofmap_w = 
			((this.external_padding_left + this.ifmap_w + (this.ifmap_w - 1) * 
				this.inner_padding_left_right + this.external_padding_right) - this.kernal_w_dilated) / this.conv_horizontal_stride + 1;
	endfunction
	
	`tue_object_default_constructor(PhyFmapSfcRowAdapterCfg)
	
	`uvm_object_utils_begin(PhyFmapSfcRowAdapterCfg)
		`uvm_field_int(atomic_c, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(conv_horizontal_stride, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(external_padding_left, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(external_padding_right, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(inner_padding_left_right, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(ifmap_w, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(ofmap_w, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(kernal_dilation_hzt_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(kernal_w, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(kernal_w_dilated, UVM_DEFAULT | UVM_DEC)
	`uvm_object_utils_end
	
endclass

`endif
