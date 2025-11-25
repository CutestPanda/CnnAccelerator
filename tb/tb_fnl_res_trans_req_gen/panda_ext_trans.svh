`ifndef __PANDA_EXT_TRANS_H

`define __PANDA_EXT_TRANS_H

typedef tue_sequence_item #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(tue_configuration_dummy),
	.PROXY_STATUS(tue_status_dummy)
)pure_tue_sequence_item;

class panda_fnl_res_trans_req_gen_blk_ctrl_trans extends panda_blk_ctrl_abstract_trans;
	
	typedef bit[1:0] bit2;
	
	int unsigned id;
	
	rand int unsigned ofmap_baseaddr; // 输出特征图基地址
	rand int unsigned ofmap_w; // 输出特征图宽度
	rand int unsigned ofmap_h; // 输出特征图高度
	rand ofmap_data_type_t ofmap_data_type; // 输出特征图数据大小类型
	rand int unsigned kernal_num_n; // 卷积核核数
	rand int unsigned max_wgtblk_w; // 权重块最大宽度
	rand bit is_grp_conv_mode; // 是否处于组卷积模式
	rand int unsigned group_n; // 分组数
	
	int unsigned n_foreach_group; // 每组的通道数/核数
	
	virtual function void unpack_params(panda_blk_ctrl_params params);
		this.ofmap_baseaddr = params & 'hffff_ffff;
		params >>= 32;
		
		this.ofmap_w = params & 'hffff;
		this.ofmap_w++;
		params >>= 16;
		
		this.ofmap_h = params & 'hffff;
		this.ofmap_h++;
		params >>= 16;
		
		this.ofmap_data_type = ofmap_data_type_t'(params & 'b11);
		params >>= 2;
		
		this.kernal_num_n = params & 'hffff;
		this.kernal_num_n++;
		params >>= 16;
		
		this.max_wgtblk_w = params & 'b111111;
		params >>= 6;
		
		this.is_grp_conv_mode = params & 'b1;
		params >>= 1;
		
		this.group_n = params & 'hffff;
		this.group_n++;
		params >>= 16;
		
		this.n_foreach_group = params & 'hffff;
		this.n_foreach_group++;
		params >>= 16;
	endfunction
	
	virtual function panda_blk_ctrl_params pack_params();
		panda_blk_ctrl_params p;
		
		p[31:0] = this.ofmap_baseaddr;
		p[47:32] = this.ofmap_w - 1;
		p[63:48] = this.ofmap_h - 1;
		p[65:64] = bit2'(this.ofmap_data_type);
		p[81:66] = this.kernal_num_n - 1;
		p[87:82] = this.max_wgtblk_w;
		p[88] = this.is_grp_conv_mode;
		p[104:89] = this.group_n - 1;
		p[120:105] = this.n_foreach_group - 1;
		
		return p;
	endfunction
	
	virtual function void do_print(uvm_printer printer);
		super.do_print(printer);
		
		printer.print_int("id", this.id, 32, UVM_DEC);
		printer.print_int("is_grp_conv_mode", this.is_grp_conv_mode, 1, UVM_BIN);
		
		printer.print_int("ofmap_baseaddr", this.ofmap_baseaddr, 32, UVM_HEX);
		printer.print_int("ofmap_w", this.ofmap_w, 32, UVM_DEC);
		printer.print_int("ofmap_h", this.ofmap_h, 32, UVM_DEC);
		printer.print_string(
			"ofmap_data_type",
			(this.ofmap_data_type == DATA_1_BYTE) ? "1 byte":
			(this.ofmap_data_type == DATA_2_BYTE) ? "2 byte":
			                                        "4 byte"
		);
		
		printer.print_int("kernal_num_n", this.kernal_num_n, 32, UVM_DEC);
		printer.print_int("max_wgtblk_w", this.max_wgtblk_w, 32, UVM_DEC);
		
		if(this.is_grp_conv_mode)
		begin
			printer.print_int("group_n", this.group_n, 32, UVM_DEC);
			printer.print_int("n_foreach_group", this.n_foreach_group, 32, UVM_DEC);
		end
		
		printer.print_time("process_begin_time", this.process_begin_time);
		printer.print_time("process_end_time", this.process_end_time);
	endfunction
	
	constraint c_default_cst{
		ofmap_w >= 1;
		ofmap_h >= 1;
		kernal_num_n >= 1;
		max_wgtblk_w >= 1;
		
		if(is_grp_conv_mode){
			(kernal_num_n % group_n) == 0;
		}
	}
	
	function void post_randomize();
		super.post_randomize();
		
		if(this.is_grp_conv_mode)
		begin
			this.n_foreach_group = this.kernal_num_n / this.group_n;
		end
	endfunction
	
	`tue_object_default_constructor(panda_fnl_res_trans_req_gen_blk_ctrl_trans)
	
	`uvm_object_utils_begin(panda_fnl_res_trans_req_gen_blk_ctrl_trans)
		`uvm_field_int(id, UVM_DEFAULT | UVM_NOCOMPARE | UVM_NOPRINT)
		
		`uvm_field_int(ofmap_baseaddr, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(ofmap_w, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(ofmap_h, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_enum(ofmap_data_type_t, ofmap_data_type, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(kernal_num_n, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(max_wgtblk_w, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(is_grp_conv_mode, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(group_n, UVM_DEFAULT | UVM_NOPRINT)
		`uvm_field_int(n_foreach_group, UVM_DEFAULT | UVM_NOPRINT)
		
		`uvm_field_int(process_begin_time, UVM_DEFAULT | UVM_NOCOMPARE | UVM_NOPRINT)
		`uvm_field_int(process_end_time, UVM_DEFAULT | UVM_NOCOMPARE | UVM_NOPRINT)
	`uvm_object_utils_end
	
endclass

class panda_fnl_res_trans_req_gen_blk_ctrl_trans_factory extends panda_trans_factory;
	
	virtual function uvm_sequence_item create_item();
		return panda_fnl_res_trans_req_gen_blk_ctrl_trans::type_id::create();
	endfunction
	
	`tue_object_default_constructor(panda_fnl_res_trans_req_gen_blk_ctrl_trans_factory)
	`uvm_object_utils(panda_fnl_res_trans_req_gen_blk_ctrl_trans_factory)
	
endclass

class DMAS2MMReqTransAdapter extends pure_tue_sequence_item;
	
	local panda_axis_trans axis_tr;
	
	int unsigned tr_id;
	
	int unsigned baseaddr; // 传输基地址
	int unsigned btt; // 待传输字节数
	
	string trans_type; // 传输类型
	int unsigned cmd_id; // 命令ID
	
	function void convert(panda_axis_trans axis_tr = null);
		if(axis_tr != null)
		begin
			this.axis_tr = axis_tr;
			
			this.baseaddr = this.axis_tr.data[0][31:0];
			this.btt = this.axis_tr.data[0][55:32];
			
			this.trans_type = this.axis_tr.user[0][0] ? "Fixed":"Incr";
			this.cmd_id = this.axis_tr.user[0][24:1];
		end
	endfunction
	
	`tue_object_default_constructor(DMAS2MMReqTransAdapter)
	
	`uvm_object_utils_begin(DMAS2MMReqTransAdapter)
		`uvm_field_int(tr_id, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(baseaddr, UVM_DEFAULT | UVM_HEX)
		`uvm_field_int(btt, UVM_DEFAULT | UVM_DEC)
		`uvm_field_string(trans_type, UVM_DEFAULT)
		`uvm_field_int(cmd_id, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
	`uvm_object_utils_end
	
endclass

`endif
