`ifndef __PANDA_EXT_TRANS_H

`define __PANDA_EXT_TRANS_H

class panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans extends panda_blk_ctrl_abstract_trans;
	
	int unsigned id;
	
	// 计算参数
	rand int conv_vertical_stride; // 卷积垂直步长
	// 组卷积模式
	rand bit is_grp_conv_mode; // 是否处于组卷积模式
	rand int n_foreach_group; // 每组的通道数
	int data_size_foreach_group; // 每组的数据量
	// [特征图参数]
	rand bit[31:0] fmap_baseaddr; // 特征图数据基地址
	rand bit is_16bit_data; // 是否16位特征图数据
	rand int ifmap_w; // 输入特征图宽度
	rand int ifmap_h; // 输入特征图高度
	int ifmap_size; // 输入特征图大小
	int ofmap_h; // 输出特征图高度
	rand int fmap_chn_n; // 通道数
	int ext_i_bottom; // 扩展后特征图的垂直边界
	rand int external_padding_top; // 上部外填充数
	rand int external_padding_bottom; // 下部外填充数
	rand int inner_padding_top_bottom; // 上下内填充数
	// [卷积核参数]
	rand int kernal_set_n; // 核组个数
	rand int kernal_dilation_vtc_n; // 垂直膨胀量
	rand int kernal_w; // (膨胀前)卷积核宽度
	rand int kernal_h; // (膨胀前)卷积核高度
	int kernal_h_dilated; // (膨胀后)卷积核高度
	
	constraint default_c{
		conv_vertical_stride >= 1;
		ifmap_w >= 1;
		ifmap_h >= 1;
		fmap_chn_n >= 1;
		external_padding_top >= 0;
		external_padding_bottom >= 0;
		inner_padding_top_bottom >= 0;
		kernal_set_n >= 1;
		kernal_dilation_vtc_n >= 0;
		
		is_16bit_data == 1'b1;
		
		kernal_w == kernal_h;
		
		kernal_w inside {1, 3, 5, 7, 9, 11};
		
		if(is_grp_conv_mode){
			n_foreach_group >= 1;
			(fmap_chn_n % n_foreach_group) == 0;
			
			kernal_set_n == (fmap_chn_n / n_foreach_group);
		}
		
		(((ifmap_h + external_padding_top + (ifmap_h - 1) * inner_padding_top_bottom + external_padding_bottom) - 
			(kernal_h + (kernal_h - 1) * kernal_dilation_vtc_n)) % conv_vertical_stride) == 0;
		(ifmap_h + external_padding_top + (ifmap_h - 1) * inner_padding_top_bottom + external_padding_bottom) >= 
			(kernal_h + (kernal_h - 1) * kernal_dilation_vtc_n);
	}
	
	virtual function void unpack_params(panda_blk_ctrl_params params);
		this.conv_vertical_stride = params & 'b111;
		this.conv_vertical_stride++;
		params >>= 3;
		
		this.is_grp_conv_mode = params & 'b1;
		params >>= 1;
		
		this.n_foreach_group = params & 'hffff;
		this.n_foreach_group++;
		params >>= 16;
		
		this.data_size_foreach_group = params & 'hffff_ffff;
		params >>= 32;
		
		this.fmap_baseaddr = params & 'hffff_ffff;
		params >>= 32;
		
		this.is_16bit_data = params & 'b1;
		params >>= 1;
		
		this.ifmap_w = params & 'hffff;
		this.ifmap_w++;
		params >>= 16;
		
		this.ifmap_size = params & 'hffffff;
		this.ifmap_size++;
		params >>= 24;
		
		this.ofmap_h = params & 'hffff;
		this.ofmap_h++;
		params >>= 16;
		
		this.fmap_chn_n = params & 'hffff;
		this.fmap_chn_n++;
		params >>= 16;
		
		this.ext_i_bottom = params & 'hffff;
		params >>= 16;
		
		this.external_padding_top = params & 'b111;
		params >>= 3;
		
		this.inner_padding_top_bottom = params & 'b111;
		params >>= 3;
		
		this.kernal_set_n = params & 'hffff;
		this.kernal_set_n++;
		params >>= 16;
		
		this.kernal_dilation_vtc_n = params & 'b1111;
		params >>= 4;
		
		this.kernal_w = params & 'b1111;
		this.kernal_w++;
		params >>= 4;
		
		this.kernal_h = params & 'b1111;
		this.kernal_h++;
		params >>= 4;
		
		this.kernal_h_dilated = params & 'b11111;
		this.kernal_h_dilated++;
		params >>= 5;
	endfunction
	
	virtual function panda_blk_ctrl_params pack_params();
		panda_blk_ctrl_params p;
		
		p[2:0] = this.conv_vertical_stride - 1;
		p[3] = this.is_grp_conv_mode;
		p[19:4] = this.n_foreach_group - 1;
		p[51:20] = this.data_size_foreach_group;
		p[83:52] = this.fmap_baseaddr;
		p[84] = this.is_16bit_data;
		p[100:85] = this.ifmap_w - 1;
		p[124:101] = this.ifmap_size - 1;
		p[140:125] = this.ofmap_h - 1;
		p[156:141] = this.fmap_chn_n - 1;
		p[172:157] = this.ext_i_bottom;
		p[175:173] = this.external_padding_top;
		p[178:176] = this.inner_padding_top_bottom;
		p[194:179] = this.kernal_set_n - 1;
		p[198:195] = this.kernal_dilation_vtc_n;
		p[202:199] = this.kernal_w - 1;
		p[206:203] = this.kernal_h - 1;
		p[211:207] = this.kernal_h_dilated - 1;
		
		return p;
	endfunction
	
	function void post_randomize();
		super.post_randomize();
		
		this.ifmap_size = this.ifmap_w * this.ifmap_h;
		
		if(is_grp_conv_mode)
			this.data_size_foreach_group = this.ifmap_size * this.n_foreach_group * (this.is_16bit_data ? 2:1);
		
		this.ext_i_bottom = this.ifmap_h + this.external_padding_top + (this.ifmap_h - 1) * this.inner_padding_top_bottom - 1;
		
		this.kernal_h_dilated = this.kernal_h + (this.kernal_h - 1) * this.kernal_dilation_vtc_n;
		
		this.ofmap_h = ((this.ext_i_bottom + 1 + this.external_padding_bottom) - this.kernal_h_dilated) / this.conv_vertical_stride + 1;
	endfunction
	
	virtual function void do_print(uvm_printer printer);
		super.do_print(printer);
		
		printer.print_int("conv_vertical_stride", this.conv_vertical_stride, 32, UVM_DEC);
		printer.print_int("is_grp_conv_mode", this.is_grp_conv_mode, 1, UVM_BIN);
		
		if(this.is_grp_conv_mode)
		begin
			printer.print_int("n_foreach_group", this.n_foreach_group, 32, UVM_DEC);
			printer.print_int("data_size_foreach_group", this.data_size_foreach_group, 32, UVM_DEC);
		end
		
		printer.print_int("fmap_baseaddr", this.fmap_baseaddr, 32, UVM_HEX);
		printer.print_int("is_16bit_data", this.is_16bit_data, 1, UVM_BIN);
		printer.print_int("ifmap_w", this.ifmap_w, 32, UVM_DEC);
		printer.print_int("ifmap_h", this.ifmap_h, 32, UVM_DEC);
		printer.print_int("fmap_chn_n", this.fmap_chn_n, 32, UVM_DEC);
		printer.print_int("ofmap_h", this.ofmap_h, 32, UVM_DEC);
		printer.print_int("external_padding_top", this.external_padding_top, 32, UVM_DEC);
		printer.print_int("external_padding_bottom", this.external_padding_bottom, 32, UVM_DEC);
		printer.print_int("inner_padding_top_bottom", this.inner_padding_top_bottom, 32, UVM_DEC);
		
		if(!this.is_grp_conv_mode)
			printer.print_int("kernal_set_n", this.kernal_set_n, 32, UVM_DEC);
		
		printer.print_int("kernal_w_h", this.kernal_w, 32, UVM_DEC);
		printer.print_int("kernal_dilation_n", this.kernal_dilation_vtc_n, 32, UVM_DEC);
		
		printer.print_time("process_begin_time", this.process_begin_time);
		printer.print_time("process_end_time", this.process_end_time);
	endfunction
	
	`tue_object_default_constructor(panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans)
	
	`uvm_object_utils_begin(panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans)
		`uvm_field_int(id, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		
		`uvm_field_int(conv_vertical_stride, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(is_grp_conv_mode, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(n_foreach_group, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(data_size_foreach_group, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(fmap_baseaddr, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(is_16bit_data, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(ifmap_w, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(ifmap_h, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(ifmap_size, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(ofmap_h, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(fmap_chn_n, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(ext_i_bottom, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(external_padding_top, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(external_padding_bottom, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(inner_padding_top_bottom, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(kernal_set_n, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(kernal_dilation_vtc_n, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(kernal_w, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(kernal_h, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(kernal_h_dilated, UVM_DEFAULT | UVM_NOPRINT)
		
		`uvm_field_int(process_begin_time, UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE)
		`uvm_field_int(process_end_time, UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE)
	`uvm_object_utils_end
	
endclass

class panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans_factory extends panda_trans_factory;
	
	virtual function uvm_sequence_item create_item();
		return panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans::type_id::create("panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans");
	endfunction
	
	`tue_object_default_constructor(panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans_factory)
	`uvm_object_utils(panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans_factory)
	
endclass

class FmRdReqTransAdapter extends tue_sequence_item #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(tue_configuration_dummy),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local panda_axis_trans axis_tr;
	
	int unsigned id;
	
	bit to_rst_buf; // 是否重置缓存
	int unsigned actual_sfc_rid; // 实际表面行号
	int unsigned start_sfc_id; // 起始表面编号
	int unsigned sfc_n_to_rd; // 待读取的表面个数
	bit[31:0] sfc_row_baseaddr; // 表面行基地址
	int unsigned sfc_row_col_n_to_fetch; // 表面行列数
	int unsigned vld_data_n_foreach_sfc; // 每个表面的有效数据个数
	int unsigned sfc_row_btt; // 表面行有效字节数
	
	function convert(panda_axis_trans axis_tr = null);
		if(axis_tr != null)
		begin
			this.axis_tr = axis_tr;
			
			this.to_rst_buf = axis_tr.data[0][97];
			this.actual_sfc_rid = {1'b0, axis_tr.data[0][96:85]};
			this.start_sfc_id = {1'b0, axis_tr.data[0][84:73]};
			this.sfc_n_to_rd = {1'b0, axis_tr.data[0][72:61]} + 1;
			this.sfc_row_baseaddr = axis_tr.data[0][60:29];
			this.sfc_row_btt = {1'b0, axis_tr.data[0][28:5]};
			this.vld_data_n_foreach_sfc = {1'b0, axis_tr.data[0][4:0]} + 1;
			this.sfc_row_col_n_to_fetch = this.sfc_row_btt / this.vld_data_n_foreach_sfc / 2;
		end
	endfunction
	
	virtual function void do_print(uvm_printer printer);
		super.do_print(printer);
		
		if(!this.to_rst_buf)
		begin
			printer.print_int("actual_sfc_rid", this.actual_sfc_rid, 32, UVM_HEX);
			printer.print_int("start_sfc_id", this.start_sfc_id, 32, UVM_DEC);
			printer.print_int("sfc_n_to_rd", this.sfc_n_to_rd, 32, UVM_DEC);
			printer.print_int("sfc_row_baseaddr", this.sfc_row_baseaddr, 32, UVM_HEX);
			printer.print_int("sfc_row_col_n_to_fetch", this.sfc_row_col_n_to_fetch, 32, UVM_DEC);
			printer.print_int("vld_data_n_foreach_sfc", this.vld_data_n_foreach_sfc, 32, UVM_DEC);
			printer.print_int("sfc_row_btt", this.sfc_row_btt, 32, UVM_DEC);
		end
	endfunction
	
	`tue_object_default_constructor(FmRdReqTransAdapter)
	
	`uvm_object_utils_begin(FmRdReqTransAdapter)
		`uvm_field_int(id, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		
		`uvm_field_int(to_rst_buf, UVM_DEFAULT | UVM_BIN)
		
		`uvm_field_int(actual_sfc_rid, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(start_sfc_id, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(sfc_n_to_rd, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(sfc_row_baseaddr, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(sfc_row_col_n_to_fetch, UVM_DEFAULT | UVM_NOPRINT | UVM_NOCOMPARE)
		`uvm_field_int(vld_data_n_foreach_sfc, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(sfc_row_btt, UVM_DEFAULT | UVM_NOPRINT)
	`uvm_object_utils_end
	
endclass

`endif
