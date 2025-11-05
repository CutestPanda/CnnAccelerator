`ifndef __PANDA_EXT_TRANS_H

`define __PANDA_EXT_TRANS_H

`include "panda_defines.svh"

class ArrayInTrans extends panda_axis_master_trans;
	
	AbstractData data_gen; // 数据生成器
	
	local AbstractData data_arr[];
	
	rand int sfc_n; // 表面总数
	rand int vld_data_n_foreach_sfc; // 每个表面的有效数据个数
	
	constraint c_strm_len{
		len == sfc_n;
	}
	
	virtual function void do_print(uvm_printer printer);
		printer.print_int("sfc_n", this.sfc_n, 32, UVM_DEC);
		printer.print_int("vld_data_n_foreach_sfc", this.vld_data_n_foreach_sfc, 32, UVM_DEC);
		
		for(int i = 0;i < this.sfc_n;i++)
		begin
			for(int j = 0;j < this.vld_data_n_foreach_sfc;j++)
				this.data_arr[i * this.vld_data_n_foreach_sfc + j].print_data(printer, $sformatf("org_data[%0d][%0d]", i, j));
		end
	endfunction
	
	function void pre_randomize();
		super.pre_randomize();
		
		if(this.data_gen == null)
		begin
			`uvm_error(this.get_name(), "no data_gen!")
			
			this.data_gen = PackedReal::type_id::create("default_data_gen");
		end
		
		this.data.rand_mode(0);
		c_valid_data.constraint_mode(0);
	endfunction
	
	function void post_randomize();
		super.post_randomize();
		
		this.data = new[this.sfc_n];
		this.data_arr = new[this.sfc_n * this.vld_data_n_foreach_sfc];
		
		for(int i = 0;i < this.sfc_n;i++)
		begin
			this.data[i] = {(`PANDA_AXIS_MAX_DATA_WIDTH){1'b0}};
			
			for(int j = 0;j < this.vld_data_n_foreach_sfc;j++)
			begin
				uvm_object data_gen_clone;
				
				data_gen_clone = this.data_gen.clone();
				
				if(!$cast(this.data_arr[i * this.vld_data_n_foreach_sfc + j], data_gen_clone))
				begin
					`uvm_error(this.get_name(), "cannot cast data_gen_clone!")
					
					return;
				end
				
				if(!this.data_arr[i * this.vld_data_n_foreach_sfc + j].randomize())
				begin
					`uvm_error(this.get_name(), "cannot randomize data_arr[x]!")
					
					return;
				end
				
				this.data[i][16*j+:16] = this.data_arr[i * this.vld_data_n_foreach_sfc + j].encode_to_int16();
			end
		end
	endfunction
	
	`tue_object_default_constructor(ArrayInTrans)
	`uvm_object_utils(ArrayInTrans)
	
endclass

class SfcStrmAdapter extends tue_sequence_item #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(tue_configuration_dummy),
	.PROXY_STATUS(tue_status_dummy)
);
	
	AbstractSurface sfc_arr[];
	
	function int get_len();
		return this.sfc_arr.size();
	endfunction
	
	function void convert(panda_axis_trans axis_tr = null, calfmt_t cal_fmt = FP16, int atomic_c = 4);
		if(axis_tr != null)
		begin
			this.sfc_arr = new[axis_tr.len];
			
			if(cal_fmt == FP16)
			begin
				for(int i = 0;i < axis_tr.len;i++)
					this.sfc_arr[i] = Fp16Surface::type_id::create("fp16_sfc");
			end
			else if(cal_fmt == INT16)
			begin
				for(int i = 0;i < axis_tr.len;i++)
					this.sfc_arr[i] = Int16Surface::type_id::create("int16_sfc");
			end
			else
			begin
				for(int i = 0;i < axis_tr.len;i++)
					this.sfc_arr[i] = Int16Surface::type_id::create("int16_sfc");
			end
			
			for(int i = 0;i < axis_tr.len;i++)
			begin
				this.sfc_arr[i].len = atomic_c;
				this.sfc_arr[i].fmt_data = new[atomic_c];
				
				for(int j = 0;j < atomic_c;j++)
					this.sfc_arr[i].fmt_data[j] = axis_tr.data[i][16*j+:16];
				
				this.sfc_arr[i].restore_data_array();
			end
		end
	endfunction
	
	`tue_object_default_constructor(SfcStrmAdapter)
	
	`uvm_object_utils_begin(SfcStrmAdapter)
		`uvm_field_array_object(sfc_arr, UVM_PRINT)
	`uvm_object_utils_end
	
endclass

`endif
