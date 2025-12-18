`ifndef __PANDA_EXT_TRANS_H

`define __PANDA_EXT_TRANS_H

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

class panda_kernal_access_req_gen_blk_ctrl_trans_factory extends panda_trans_factory;
	
	virtual function uvm_sequence_item create_item();
		return panda_kernal_access_req_gen_blk_ctrl_trans::type_id::create("panda_kernal_access_req_gen_blk_ctrl_trans");
	endfunction
	
	`tue_object_default_constructor(panda_kernal_access_req_gen_blk_ctrl_trans_factory)
	`uvm_object_utils(panda_kernal_access_req_gen_blk_ctrl_trans_factory)
	
endclass

class KernalRdReqTransAdapter extends tue_sequence_item #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(tue_configuration_dummy),
	.PROXY_STATUS(tue_status_dummy)
);
	
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

`endif
