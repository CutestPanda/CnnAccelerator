`ifndef __PANDA_EXT_CFG_H
`define __PANDA_EXT_CFG_H

class MidResInfoPackerCfg extends tue_configuration;
	
	rand int atomic_k; // 核并行数
	
	rand int ofmap_w; // 输出特征图宽度
	rand int kernal_w; // (膨胀前)卷积核宽度
	rand int cgrp_n_of_fmap_region_that_kernal_set_sel; // 核组所选定特征图域的通道组数
	
	rand int cal_round_n; // 计算轮次
	
	constraint c_default_cst{
		atomic_k inside {1, 2, 4, 8, 16, 32};
		
		ofmap_w >= 1;
		kernal_w inside {1, 3, 5, 7, 9, 11};
		cgrp_n_of_fmap_region_that_kernal_set_sel >= 1;
		
		cal_round_n >= 1;
	}
	
	`tue_object_default_constructor(MidResInfoPackerCfg)
	
	`uvm_object_utils_begin(MidResInfoPackerCfg)
		`uvm_field_int(atomic_k, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(ofmap_w, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(kernal_w, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(cgrp_n_of_fmap_region_that_kernal_set_sel, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(cal_round_n, UVM_DEFAULT | UVM_DEC)
	`uvm_object_utils_end
	
endclass

`endif
