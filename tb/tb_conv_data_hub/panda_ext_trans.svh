`ifndef __PANDA_EXT_TRANS_H

`define __PANDA_EXT_TRANS_H

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
	
	function new(panda_axis_trans axis_tr = null, string name = "FmRdReqTransAdapter");
		super.new(name);
		
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
			printer.print_int("actual_sfc_rid", this.actual_sfc_rid, 32, UVM_DEC);
			printer.print_int("start_sfc_id", this.start_sfc_id, 32, UVM_DEC);
			printer.print_int("sfc_n_to_rd", this.sfc_n_to_rd, 32, UVM_DEC);
			printer.print_int("sfc_row_baseaddr", this.sfc_row_baseaddr, 32, UVM_HEX);
			printer.print_int("sfc_row_col_n_to_fetch", this.sfc_row_col_n_to_fetch, 32, UVM_DEC);
			printer.print_int("vld_data_n_foreach_sfc", this.vld_data_n_foreach_sfc, 32, UVM_DEC);
			printer.print_int("sfc_row_btt", this.sfc_row_btt, 32, UVM_DEC);
		end
	endfunction
	
	`uvm_object_utils_begin(FmRdReqTransAdapter)
		`uvm_field_int(id, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(to_rst_buf, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(actual_sfc_rid, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(start_sfc_id, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(sfc_n_to_rd, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(sfc_row_baseaddr, UVM_DEFAULT | UVM_NOPRINT | UVM_HEX)
		`uvm_field_int(sfc_row_col_n_to_fetch, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(vld_data_n_foreach_sfc, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(sfc_row_btt, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
	`uvm_object_utils_end
	
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
	
	function new(panda_axis_trans axis_tr = null, string name = "KernalRdReqTransAdapter");
		super.new(name);
		
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
	
	`uvm_object_utils_begin(KernalRdReqTransAdapter)
		`uvm_field_int(id, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(to_rst_buf, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(actual_cgrp_id_or_cgrpn, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(cgrp_id_ofs, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(wgtblk_id, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(start_sfc_id, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(sfc_n_to_rd, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(kernal_cgrp_baseaddr, UVM_DEFAULT | UVM_NOPRINT | UVM_HEX)
		`uvm_field_int(kernal_cgrp_btt, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(sfc_n_foreach_wgtblk, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
		`uvm_field_int(vld_data_n_foreach_sfc, UVM_DEFAULT | UVM_NOPRINT | UVM_DEC)
	`uvm_object_utils_end
	
endclass

`endif
