`ifndef __PANDA_EXT_TRANS_H

`define __PANDA_EXT_TRANS_H

typedef tue_sequence_item #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(tue_configuration_dummy),
	.PROXY_STATUS(tue_status_dummy)
)pure_tue_sequence_item;

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

class panda_kernal_access_req_gen_blk_ctrl_trans extends panda_blk_ctrl_abstract_trans;
	
	typedef bit[2:0] bit3;
	
	int unsigned id;
	
	rand bit is_16bit_wgt; // 是否16位权重数据
	rand int unsigned kernal_wgt_baseaddr; // 卷积核权重基地址
	rand int unsigned kernal_chn_n; // 通道数
	rand int unsigned kernal_num_n; // 核数
	rand kernal_sz_t kernal_shape; // 卷积核形状
	rand int unsigned ofmap_h; // 输出特征图高度
	rand bit is_grp_conv_mode; // 是否处于组卷积模式
	rand int unsigned group_n; // 分组数
	rand int unsigned cgrpn_foreach_kernal_set; // 每个核组的通道组数
	rand int unsigned max_wgtblk_w; // 权重块最大宽度
	rand int unsigned conv_vertical_stride; // 卷积垂直步长
	rand int unsigned ext_i_bottom; // 扩展后特征图的垂直边界
	rand int unsigned external_padding_top; // 上部外填充数
	rand int unsigned inner_padding_top_bottom; // 上下内填充数
	rand int unsigned kernal_dilation_vtc_n; // 垂直膨胀量
	
	int unsigned n_foreach_group; // 每组的通道数/核数
	
	virtual function void unpack_params(panda_blk_ctrl_params params);
		this.is_16bit_wgt = params & 'b1;
		params >>= 1;
		
		this.kernal_wgt_baseaddr = params & 'hffff_ffff;
		params >>= 32;
		
		this.kernal_chn_n = params & 'hffff;
		this.kernal_chn_n++;
		params >>= 16;
		
		this.kernal_num_n = params & 'hffff;
		this.kernal_num_n++;
		params >>= 16;
		
		this.kernal_shape = kernal_sz_t'(params & 'b111);
		params >>= 3;
		
		this.ofmap_h = params & 'hffff;
		this.ofmap_h++;
		params >>= 16;
		
		this.is_grp_conv_mode = params & 'b1;
		params >>= 1;
		
		this.n_foreach_group = params & 'hffff;
		this.n_foreach_group++;
		params >>= 16;
		
		this.group_n = params & 'hffff;
		this.group_n++;
		params >>= 16;
		
		this.cgrpn_foreach_kernal_set = params & 'hffff;
		this.cgrpn_foreach_kernal_set++;
		params >>= 16;
		
		this.max_wgtblk_w = params & 'b111111;
		params >>= 6;
		
		this.conv_vertical_stride = params & 'b111;
		this.conv_vertical_stride++;
		params >>= 3;
		
		this.ext_i_bottom = params & 'hffff;
		params >>= 16;
		
		this.external_padding_top = params & 'b111;
		params >>= 3;
		
		this.inner_padding_top_bottom = params & 'b111;
		params >>= 3;
		
		this.kernal_dilation_vtc_n = params & 'b1111;
		params >>= 4;
	endfunction
	
	virtual function panda_blk_ctrl_params pack_params();
		panda_blk_ctrl_params p;
		
		p[0] = this.is_16bit_wgt;
		p[32:1] = this.kernal_wgt_baseaddr;
		p[48:33] = this.kernal_chn_n - 1;
		p[64:49] = this.kernal_num_n - 1;
		p[67:65] = bit3'(this.kernal_shape);
		p[83:68] = this.ofmap_h - 1;
		p[84] = this.is_grp_conv_mode;
		p[100:85] = this.n_foreach_group - 1;
		p[116:101] = this.group_n - 1;
		p[132:117] = this.cgrpn_foreach_kernal_set - 1;
		p[138:133] = this.max_wgtblk_w;
		p[141:139] = this.conv_vertical_stride - 1;
		p[157:142] = this.ext_i_bottom;
		p[160:158] = this.external_padding_top;
		p[163:161] = this.inner_padding_top_bottom;
		p[167:164] = this.kernal_dilation_vtc_n;
		
		return p;
	endfunction
	
	virtual function void do_print(uvm_printer printer);
		super.do_print(printer);
		
		printer.print_int("kernal_chn_n", this.kernal_chn_n, 32, UVM_DEC);
		printer.print_int("kernal_num_n", this.kernal_num_n, 32, UVM_DEC);
		printer.print_int("ofmap_h", this.ofmap_h, 32, UVM_DEC);
		
		printer.print_int("cgrpn_foreach_kernal_set", this.cgrpn_foreach_kernal_set, 32, UVM_DEC);
		
		if(this.is_grp_conv_mode)
		begin
			printer.print_int("n_foreach_group", this.n_foreach_group, 32, UVM_DEC);
			printer.print_int("group_n", this.group_n, 32, UVM_DEC);
		end
		
		printer.print_int("max_wgtblk_w", this.max_wgtblk_w, 32, UVM_DEC);
		printer.print_int("conv_vertical_stride", this.conv_vertical_stride, 32, UVM_DEC);
		printer.print_int("ext_i_bottom", this.ext_i_bottom, 32, UVM_DEC);
		printer.print_int("external_padding_top", this.external_padding_top, 32, UVM_DEC);
		printer.print_int("inner_padding_top_bottom", this.inner_padding_top_bottom, 32, UVM_DEC);
		printer.print_int("kernal_dilation_vtc_n", this.kernal_dilation_vtc_n, 32, UVM_DEC);
		
		printer.print_time("process_begin_time", this.process_begin_time);
		printer.print_time("process_end_time", this.process_end_time);
	endfunction
	
	constraint c_valid_is_16bit_wgt{
		is_16bit_wgt == 1'b1;
	}
	
	constraint c_valid_kernal_chn_num_n{
		if(is_grp_conv_mode){
			kernal_chn_n == kernal_num_n;
			
			(kernal_chn_n % group_n) == 0;
		}
	}
	
	constraint c_valid_max_wgtblk_w{
		max_wgtblk_w <= 32;
	}
	
	constraint c_valid_conv_vertical_stride{
		conv_vertical_stride >= 1;
	}
	
	function void post_randomize();
		super.post_randomize();
		
		if(this.is_grp_conv_mode)
		begin
			this.n_foreach_group = this.kernal_chn_n / this.group_n;
		end
	endfunction
	
	`tue_object_default_constructor(panda_kernal_access_req_gen_blk_ctrl_trans)
	
	`uvm_object_utils_begin(panda_kernal_access_req_gen_blk_ctrl_trans)
		`uvm_field_int(id, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(is_16bit_wgt, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(kernal_wgt_baseaddr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(kernal_chn_n, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(kernal_num_n, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_enum(kernal_sz_t, kernal_shape, UVM_DEFAULT)
		`uvm_field_int(ofmap_h, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(is_grp_conv_mode, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(n_foreach_group, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(group_n, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(cgrpn_foreach_kernal_set, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(max_wgtblk_w, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(conv_vertical_stride, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(ext_i_bottom, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(external_padding_top, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(inner_padding_top_bottom, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(kernal_dilation_vtc_n, UVM_DEFAULT | UVM_NOPRINT)
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

class panda_kernal_access_req_gen_blk_ctrl_trans_factory extends panda_trans_factory;
	
	virtual function uvm_sequence_item create_item();
		return panda_kernal_access_req_gen_blk_ctrl_trans::type_id::create("panda_kernal_access_req_gen_blk_ctrl_trans");
	endfunction
	
	`tue_object_default_constructor(panda_kernal_access_req_gen_blk_ctrl_trans_factory)
	`uvm_object_utils(panda_kernal_access_req_gen_blk_ctrl_trans_factory)
	
endclass

class panda_dummy_blk_ctrl_trans_factory extends panda_trans_factory;
	
	virtual function uvm_sequence_item create_item();
		return panda_blk_ctrl_dummy_trans::type_id::create("panda_blk_ctrl_dummy_trans");
	endfunction
	
	`tue_object_default_constructor(panda_dummy_blk_ctrl_trans_factory)
	`uvm_object_utils(panda_dummy_blk_ctrl_trans_factory)
	
endclass

class FmRdReqTransAdapter extends pure_tue_sequence_item;
	
	local panda_axis_trans axis_tr;
	
	int unsigned id;
	
	bit to_rst_buf; // 是否重置缓存
	int unsigned actual_sfc_rid; // 实际表面行号
	int unsigned start_sfc_id; // 起始表面编号
	int unsigned sfc_n_to_rd; // 待读取的表面个数
	int unsigned sfc_row_baseaddr; // 表面行基地址
	int unsigned sfc_row_col_n_to_fetch; // 表面行列数
	int unsigned vld_data_n_foreach_sfc; // 每个表面的有效数据个数
	int unsigned sfc_row_btt; // 表面行有效字节数
	
	function void convert(panda_axis_trans axis_tr = null);
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

class KernalRdReqTransAdapter extends pure_tue_sequence_item;
	
	local panda_axis_trans axis_tr;
	
	int unsigned id;
	
	bit to_rst_buf; // 是否重置缓存
	int unsigned actual_cgrp_id_or_cgrpn; // 实际通道组号或卷积核核组实际通道组数
	int unsigned cgrp_id_ofs; // 通道组号偏移
	
	int unsigned wgtblk_id; // 权重块编号
	int unsigned start_sfc_id; // 起始表面编号
	int unsigned sfc_n_to_rd; // 待读取的表面个数
	int unsigned kernal_cgrp_baseaddr; // 卷积核通道组基地址
	int unsigned kernal_cgrp_btt; // 卷积核通道组有效字节数
	int unsigned sfc_n_foreach_wgtblk; // 每个权重块的表面个数
	int unsigned vld_data_n_foreach_sfc; // 每个表面的有效数据个数
	
	function void convert(panda_axis_trans axis_tr = null);
		if(axis_tr != null)
		begin
			this.axis_tr = axis_tr;
			
			this.to_rst_buf = axis_tr.data[0][97];
			if(this.to_rst_buf)
				this.actual_cgrp_id_or_cgrpn = {1'b0, axis_tr.data[0][96:87]} + 1;
			else
				this.actual_cgrp_id_or_cgrpn = axis_tr.data[0][96:87];
			this.cgrp_id_ofs = axis_tr.data[0][86:77];
			this.wgtblk_id = axis_tr.data[0][86:80];
			this.start_sfc_id = axis_tr.data[0][79:73];
			this.sfc_n_to_rd = {1'b0, axis_tr.data[0][72:68]} + 1;
			this.kernal_cgrp_baseaddr = axis_tr.data[0][67:36];
			this.kernal_cgrp_btt = axis_tr.data[0][35:12];
			this.sfc_n_foreach_wgtblk = {1'b0, axis_tr.data[0][11:5]} + 1;
			this.vld_data_n_foreach_sfc = {1'b0, axis_tr.data[0][4:0]} + 1;
		end
	endfunction
	
	virtual function void do_print(uvm_printer printer);
		super.do_print(printer);
		
		if(!this.to_rst_buf)
		begin
			printer.print_int("actual_cgrp_id", this.actual_cgrp_id_or_cgrpn, 32, UVM_DEC);
			printer.print_int("wgtblk_id", this.wgtblk_id, 32, UVM_DEC);
			printer.print_int("start_sfc_id", this.start_sfc_id, 32, UVM_DEC);
			printer.print_int("sfc_n_to_rd", this.sfc_n_to_rd, 32, UVM_DEC);
			printer.print_int("kernal_cgrp_baseaddr", this.kernal_cgrp_baseaddr, 32, UVM_HEX);
			printer.print_int("kernal_cgrp_btt", this.kernal_cgrp_btt, 32, UVM_DEC);
			printer.print_int("sfc_n_foreach_wgtblk", this.sfc_n_foreach_wgtblk, 32, UVM_DEC);
			printer.print_int("vld_data_n_foreach_sfc", this.vld_data_n_foreach_sfc, 32, UVM_DEC);
		end
		else
		begin
			printer.print_int("cgrpn", this.actual_cgrp_id_or_cgrpn, 32, UVM_DEC);
			printer.print_int("cgrp_id_ofs", this.cgrp_id_ofs, 32, UVM_DEC);
		end
	endfunction
	
	virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
		KernalRdReqTransAdapter rhs_;
		
		do_compare = super.do_compare(rhs, comparer);
		
		if(!$cast(rhs_, rhs))
			`uvm_fatal(this.get_name(), "cmp cast err!")
		
		do_compare &= comparer.compare_field(this.to_rst_buf ? "cgrpn":"actual_cgrp_id",
			this.actual_cgrp_id_or_cgrpn, rhs_.actual_cgrp_id_or_cgrpn, 32);
		
		if(this.to_rst_buf)
			do_compare &= comparer.compare_field("cgrp_id_ofs", this.cgrp_id_ofs, rhs_.cgrp_id_ofs, 32);
		
		if(!this.to_rst_buf)
		begin
			do_compare &= comparer.compare_field("wgtblk_id", this.wgtblk_id, rhs_.wgtblk_id, 32);
			do_compare &= comparer.compare_field("start_sfc_id", this.start_sfc_id, rhs_.start_sfc_id, 32);
			do_compare &= comparer.compare_field("sfc_n_to_rd", this.sfc_n_to_rd, rhs_.sfc_n_to_rd, 32);
			do_compare &= comparer.compare_field("kernal_cgrp_baseaddr", this.kernal_cgrp_baseaddr, rhs_.kernal_cgrp_baseaddr, 32);
			do_compare &= comparer.compare_field("kernal_cgrp_btt", this.kernal_cgrp_btt, rhs_.kernal_cgrp_btt, 32);
			do_compare &= comparer.compare_field("sfc_n_foreach_wgtblk", this.sfc_n_foreach_wgtblk, rhs_.sfc_n_foreach_wgtblk, 32);
			do_compare &= comparer.compare_field("vld_data_n_foreach_sfc", this.vld_data_n_foreach_sfc, rhs_.vld_data_n_foreach_sfc, 32);
		end
	endfunction
	
	`tue_object_default_constructor(KernalRdReqTransAdapter)
	
	`uvm_object_utils_begin(KernalRdReqTransAdapter)
		`uvm_field_int(id, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(to_rst_buf, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(actual_cgrp_id_or_cgrpn, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(cgrp_id_ofs, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(wgtblk_id, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(start_sfc_id, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(sfc_n_to_rd, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(kernal_cgrp_baseaddr, UVM_DEFAULT | UVM_NOPRINT | UVM_HEX | UVM_NOCOMPARE)
		`uvm_field_int(kernal_cgrp_btt, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(sfc_n_foreach_wgtblk, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(vld_data_n_foreach_sfc, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC | UVM_NOCOMPARE)
	`uvm_object_utils_end
	
endclass

virtual class AbstractFinalResAdapter extends pure_tue_sequence_item;
	
	local panda_axis_trans axis_tr;
	
	int unsigned print_id_base = 0;
	int unsigned id;
	
	AbstractData data_fifo[$];
	string print_context[$];
	
	pure virtual protected function AbstractData create_data();
	
	function void convert(panda_axis_trans axis_tr = null);
		if(axis_tr != null)
		begin
			this.axis_tr = axis_tr;
			
			for(int i = 0;i < this.axis_tr.get_len();i++)
			begin
				panda_axis_data cur_data;
				panda_axis_mask cur_keep;
				
				cur_data = this.axis_tr.data[i];
				cur_keep = this.axis_tr.keep[i];
				
				while(cur_keep[3:0] == 4'b1111)
				begin
					AbstractData abst_data;
					
					abst_data = this.create_data();
					abst_data.set_by_int32(cur_data[31:0]);
					
					this.data_fifo.push_back(abst_data);
					
					cur_data >>= 32;
					cur_keep >>= 4;
				end
			end
		end
	endfunction
	
	function void put_data(ref AbstractData data_arr[]);
		for(int i = 0;i < data_arr.size();i++)
			this.data_fifo.push_back(data_arr[i]);
	endfunction
	
	virtual function void do_print(uvm_printer printer);
		super.do_print(printer);
		
		for(int i = 0;i < this.data_fifo.size();i++)
		begin
			this.data_fifo[i].print_data(
				printer,
				{
					$sformatf("data[id: %0d]", this.print_id_base + i),
					(i < this.print_context.size()) ? 
						$sformatf("[%0s]", this.print_context[i]):
						""
				}
			);
		end
	endfunction
	
	`tue_object_default_constructor(AbstractFinalResAdapter)
	
	`uvm_object_utils_begin(AbstractFinalResAdapter)
		`uvm_field_int(id, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_queue_object(data_fifo, UVM_DEFAULT | UVM_NOPRINT)
	`uvm_object_utils_end
	
endclass

class Fp16FinalResAdapter extends AbstractFinalResAdapter;
	
	virtual protected function AbstractData create_data();
		return PackedReal::type_id::create();
	endfunction
	
	`tue_object_default_constructor(Fp16FinalResAdapter)
	
	`uvm_object_utils(Fp16FinalResAdapter)
	
endclass

virtual class MidResAccumInTr extends pure_tue_sequence_item;
	
	bit is_first_item; // 是否第1项
	
	pure virtual function void from_axis_tr(panda_axis_trans axis_tr);
	
	`tue_object_default_constructor(MidResAccumInTr)
	
endclass

class FpMidResAccumInTr extends MidResAccumInTr;
	
	int new_v_exp; // 新中间结果的指数部分
	longint new_v_frac; // 新中间结果的尾数部分
	real new_v_fp; // 新中间结果的浮点表示
	
	real org_v_fp; // 原中间结果的浮点表示
	
	virtual function void from_axis_tr(panda_axis_trans axis_tr);
		if(axis_tr != null)
		begin
			this.is_first_item = axis_tr.user[0][0];
			
			if(this.is_first_item)
				this.org_v_fp = 0.0;
			else
				this.org_v_fp = decode_fp32(axis_tr.data[0][31:0]);
			
			this.new_v_frac = {{24{axis_tr.data[0][71]}}, axis_tr.data[0][71:32]};
			this.new_v_exp = {24'd0, axis_tr.data[0][79:72]} - 50;
			
			this.new_v_fp = get_fixed36_exp(this.new_v_frac, this.new_v_exp);
		end
	endfunction
	
	virtual function string convert2string();
		return $sformatf("%0f + %0f = %0f", this.org_v_fp, this.new_v_fp, this.org_v_fp + this.new_v_fp);
	endfunction
	
	`tue_object_default_constructor(FpMidResAccumInTr)
	
	`uvm_object_utils_begin(FpMidResAccumInTr)
		`uvm_field_int(is_first_item, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(new_v_exp, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(new_v_frac, UVM_DEFAULT | UVM_DEC)
		`uvm_field_real(new_v_fp, UVM_DEFAULT)
		`uvm_field_real(org_v_fp, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

`endif
